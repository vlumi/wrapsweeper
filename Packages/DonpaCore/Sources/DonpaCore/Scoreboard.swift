import Foundation

/// Per-config stats: how many games have been cleared, the best time, and the
/// best partial progress (for boards rarely cleared outright).
public struct ScoreRecord: Codable, Equatable, Sendable {
    /// Total games cleared on this config.
    public var wins: Int
    /// Fastest winning time in centiseconds (hundredths), or nil if none yet.
    public var bestCentiseconds: Int?
    /// Best fraction (0...1) of safe cells revealed in a *losing* game. A win is
    /// implicitly 100%, so this only tracks losses; `wins > 0` means 100% at
    /// display time. Optional so old saved records (without it) decode cleanly.
    public var bestLossProgress: Double?

    public init(wins: Int = 0, bestCentiseconds: Int? = nil, bestLossProgress: Double? = nil) {
        self.wins = wins
        self.bestCentiseconds = bestCentiseconds
        self.bestLossProgress = bestLossProgress
    }
}

/// Local per-difficulty stats store (clears + best time), persisted in
/// `UserDefaults`. No security beyond the OS's per-app preferences file — a
/// determined user can edit it, which is fine for a local high-score table.
@MainActor
public final class Scoreboard: ObservableObject {
    @Published public private(set) var records: [String: ScoreRecord]

    /// Storage key of the config whose record was just set, so the scoreboard can
    /// highlight that row. Set by `submit`/`submitLossProgress` on a new best;
    /// cleared by `clearRecentRecord()` when the next game ends (so an accidental
    /// restart before checking scores doesn't lose the highlight). Not persisted.
    @Published public private(set) var recentRecord: String?

    private let defaults: UserDefaults
    private let key = "donpa.stats.v1"

    /// On-disk envelope: a format `version` wrapping the keyed records, so a
    /// breaking change can be detected and migrated (rather than mis-read or
    /// silently dropped). Records are keyed by `GameConfig.storageKey`
    /// (geometry-bearing), so new board variants add keys without colliding.
    private struct StatsFile: Codable {
        var version: Int
        var records: [String: ScoreRecord]
    }
    /// Bump only for a *breaking* change to the record shape/meaning; additive
    /// fields are handled by `ScoreRecord`'s optional/defaulted decoding instead.
    /// When bumped, add a step to `migrated(_:)`.
    private static let currentVersion = 1

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        records = Self.load(from: defaults, key: key)
    }

    /// Load the stats, resilient to partial corruption and old formats:
    /// 1. Prefer the versioned envelope; reject a *newer* version (a breaking
    ///    change this build predates) so we don't overwrite/mis-read it.
    /// 2. Fall back to a legacy bare `[String: ScoreRecord]` (the pre-envelope
    ///    format), wrapped at the current version.
    /// 3. Either way, decode **per entry** — a single corrupt or incompatible
    ///    record is dropped, never wiping the whole table.
    private static func load(from defaults: UserDefaults, key: String) -> [String: ScoreRecord] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        // Decode each record independently (re-serialize its JSON fragment, then
        // decode), so a single corrupt or incompatible row is dropped rather than
        // failing the whole table.
        func perEntry(_ object: [String: Any]) -> [String: ScoreRecord] {
            var out: [String: ScoreRecord] = [:]
            for (k, v) in object {
                guard
                    let frag = try? JSONSerialization.data(
                        withJSONObject: v, options: [.fragmentsAllowed]),
                    let rec = try? JSONDecoder().decode(ScoreRecord.self, from: frag)
                else { continue }
                out[k] = rec
            }
            return out
        }

        guard let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }

        if let versioned = top["records"] as? [String: Any], let v = top["version"] as? Int {
            if v > currentVersion { return [:] }  // newer = unknown breaking change
            return migrated(perEntry(versioned), from: v)
        }
        // Legacy bare dict (pre-envelope): the records sit at the top level.
        return migrated(perEntry(top), from: 0)
    }

    /// Migration seam. Identity today — there are no breaking changes yet. When
    /// `currentVersion` is bumped, transform `records` saved at `version` up to
    /// the current shape here (one step per version), with fixture-based tests.
    private static func migrated(_ records: [String: ScoreRecord], from version: Int)
        -> [String: ScoreRecord]
    {
        records
    }

    public func record(for config: GameConfig) -> ScoreRecord? {
        records[config.storageKey]
    }

    /// Best time for this config, in centiseconds.
    public func best(for config: GameConfig) -> Int? {
        records[config.storageKey]?.bestCentiseconds
    }

    public func wins(for config: GameConfig) -> Int {
        records[config.storageKey]?.wins ?? 0
    }

    /// Best progress (0...1) to display for this config: 1.0 once the board has
    /// ever been cleared (a win is implicitly full), otherwise the best partial
    /// progress from a loss. `nil` if the config has never been finished.
    public func bestProgress(for config: GameConfig) -> Double? {
        guard let record = records[config.storageKey] else { return nil }
        if record.wins > 0 { return 1.0 }
        return record.bestLossProgress
    }

    /// True if `centiseconds` would beat (or set) the best time for this config.
    public func isNewRecord(_ centiseconds: Int, for config: GameConfig) -> Bool {
        guard let best = records[config.storageKey]?.bestCentiseconds else { return true }
        return centiseconds < best
    }

    /// Record a win: always bumps the clear count, and updates the best time if
    /// `centiseconds` beats it. Returns true if it set a new best time.
    @discardableResult
    public func submit(_ centiseconds: Int, for config: GameConfig) -> Bool {
        var record = records[config.storageKey] ?? ScoreRecord()
        record.wins += 1
        let isBest = record.bestCentiseconds.map { centiseconds < $0 } ?? true
        if isBest {
            record.bestCentiseconds = centiseconds
            recentRecord = config.storageKey
        }
        records[config.storageKey] = record
        persist()
        return isBest
    }

    /// Record the safe-cell progress (0...1) from a *losing* game, keeping it
    /// only if it beats the stored best loss-progress. Wins are recorded via
    /// `submit(_:for:)` (a win is implicitly 100%, so don't call this on a win).
    /// Returns true if it set a new best loss-progress.
    @discardableResult
    public func submitLossProgress(_ progress: Double, for config: GameConfig) -> Bool {
        var record = records[config.storageKey] ?? ScoreRecord()
        // A win is implicitly 100%, so once the board has ever been cleared a
        // loss can't be a "new best" — compare against the displayed best, which
        // is 1.0 when there's a win.
        let currentBest = record.wins > 0 ? 1.0 : (record.bestLossProgress ?? 0)
        let isBest = progress > currentBest
        if isBest {
            record.bestLossProgress = progress
            records[config.storageKey] = record
            recentRecord = config.storageKey
            persist()
        }
        return isBest
    }

    /// Clear the just-set-record highlight. Called when the next game ends.
    public func clearRecentRecord() {
        recentRecord = nil
    }

    public func reset() {
        records = [:]
        recentRecord = nil
        persist()
    }

    private func persist() {
        let file = StatsFile(version: Self.currentVersion, records: records)
        if let data = try? JSONEncoder().encode(file) {
            defaults.set(data, forKey: key)
        }
    }
}
