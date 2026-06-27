import Foundation

/// Per-config stats. "Best" fields are idempotent merges (min/max); the cumulative
/// counts are `DeviceCounter`s so they sum correctly across devices. Counts are
/// tracked per-config here even though several are only *displayed* as global
/// totals (summed across configs) — keeping the per-config breakdown for possible
/// per-tier views later, at no extra cost.
public struct ScoreRecord: Equatable, Sendable {
    /// Games cleared. (Displayed per-config in the scoreboard table.)
    public var wins: DeviceCounter
    /// Games finished (won or lost). Never shown as a ratio with `wins` — a
    /// win-rate readout would just discourage; the raw totals stay neutral.
    public var gamesPlayed: DeviceCounter
    /// Safe cells revealed across all games on this config.
    public var tilesOpened: DeviceCounter
    /// Flags placed (each flag action).
    public var flagsPlaced: DeviceCounter
    /// Mines detonated (losing moves).
    public var minesHit: DeviceCounter
    /// Mines correctly flagged at game end ("disarmed") — a positive accuracy stat.
    public var minesDisarmed: DeviceCounter
    /// Time spent in games, in centiseconds.
    public var playtimeCentiseconds: DeviceCounter
    /// Fastest winning time in centiseconds (hundredths), or nil if none yet.
    public var bestCentiseconds: Int?
    /// Best fraction (0...1) of safe cells revealed in a *losing* game. A win is
    /// implicitly 100%, so this only tracks losses; `wins.total > 0` means 100% at
    /// display time. Optional so old saved records (without it) decode cleanly.
    public var bestLossProgress: Double?

    public init(
        wins: DeviceCounter = .init(), gamesPlayed: DeviceCounter = .init(),
        tilesOpened: DeviceCounter = .init(), flagsPlaced: DeviceCounter = .init(),
        minesHit: DeviceCounter = .init(), minesDisarmed: DeviceCounter = .init(),
        playtimeCentiseconds: DeviceCounter = .init(),
        bestCentiseconds: Int? = nil, bestLossProgress: Double? = nil
    ) {
        self.wins = wins
        self.gamesPlayed = gamesPlayed
        self.tilesOpened = tilesOpened
        self.flagsPlaced = flagsPlaced
        self.minesHit = minesHit
        self.minesDisarmed = minesDisarmed
        self.playtimeCentiseconds = playtimeCentiseconds
        self.bestCentiseconds = bestCentiseconds
        self.bestLossProgress = bestLossProgress
    }
}

extension ScoreRecord: Codable {
    enum CodingKeys: String, CodingKey {
        case wins, gamesPlayed, tilesOpened, flagsPlaced, minesHit, minesDisarmed
        case playtimeCentiseconds, bestCentiseconds, bestLossProgress
    }

    /// Tolerant decode. **Best time / best %% are idempotent (min/max) fields, not
    /// per-device — they decode unchanged, so existing high scores SURVIVE.** The
    /// cumulative counters use `try?`: a missing field (older save) *or* a legacy
    /// scalar `wins` (a bare Int from before per-device counters) both yield an
    /// empty counter, so the counts reset to zero without dropping the record (and
    /// its preserved high scores). No migration code to carry forever.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func counter(_ key: CodingKeys) -> DeviceCounter {
            // `try?` so a legacy scalar (old bare-Int `wins`) or missing field
            // yields an empty counter rather than throwing and dropping the record.
            (try? c.decode(DeviceCounter.self, forKey: key)) ?? .init()
        }
        wins = counter(.wins)
        gamesPlayed = counter(.gamesPlayed)
        tilesOpened = counter(.tilesOpened)
        flagsPlaced = counter(.flagsPlaced)
        minesHit = counter(.minesHit)
        minesDisarmed = counter(.minesDisarmed)
        playtimeCentiseconds = counter(.playtimeCentiseconds)
        bestCentiseconds = try c.decodeIfPresent(Int.self, forKey: .bestCentiseconds)
        bestLossProgress = try c.decodeIfPresent(Double.self, forKey: .bestLossProgress)
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
        records[config.storageKey]?.wins.total ?? 0
    }

    /// Best progress (0...1) to display for this config: 1.0 once the board has
    /// ever been cleared (a win is implicitly full), otherwise the best partial
    /// progress from a loss. `nil` if the config has never been finished.
    public func bestProgress(for config: GameConfig) -> Double? {
        guard let record = records[config.storageKey] else { return nil }
        if record.wins.total > 0 { return 1.0 }
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
        record.wins.add(1)
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
        let currentBest = record.wins.total > 0 ? 1.0 : (record.bestLossProgress ?? 0)
        let isBest = progress > currentBest
        if isBest {
            record.bestLossProgress = progress
            records[config.storageKey] = record
            recentRecord = config.storageKey
            persist()
        }
        return isBest
    }

    /// Record the cumulative tallies from a finished game (won or lost), on top of
    /// the win / loss-progress recorded via `submit`/`submitLossProgress`. Bumps the
    /// per-config G-Counters; displayed as global totals (see the `total*` accessors).
    /// Call once per finished game.
    /// Add a slice of in-game **activity** to the lifetime totals: tiles opened,
    /// flag placements, and centiseconds played. Called repeatedly during a game
    /// (flushed on pause / scoreboard-open / background / end), so the Career page
    /// reflects activity as it happens — and abandoning a dug-into game still keeps
    /// its effort. Deltas only (the view model tracks what's already flushed), so
    /// this never double-counts, and it does NOT touch games-played or outcomes.
    /// A no-op delta still persists nothing of consequence; callers skip empty
    /// flushes. Zero-skip keeps the common idle case cheap.
    public func recordActivity(
        for config: GameConfig, tilesOpened: Int, flagsPlaced: Int, playtimeCentiseconds: Int
    ) {
        guard tilesOpened != 0 || flagsPlaced != 0 || playtimeCentiseconds != 0 else { return }
        var record = records[config.storageKey] ?? ScoreRecord()
        record.tilesOpened.add(tilesOpened)
        record.flagsPlaced.add(flagsPlaced)
        record.playtimeCentiseconds.add(playtimeCentiseconds)
        records[config.storageKey] = record
        persist()
    }

    /// Record a finished game's **outcome**: bump games-played and add the mine
    /// tally (one hit on a loss; the disarmed count on a win). Activity (tiles /
    /// flags / time) is NOT here — it accrues live via `recordActivity`. Wins and
    /// loss-progress go through `submit` / `submitLossProgress`.
    public func recordGameOutcome(for config: GameConfig, minesHit: Int, minesDisarmed: Int) {
        var record = records[config.storageKey] ?? ScoreRecord()
        record.gamesPlayed.add(1)
        record.minesHit.add(minesHit)
        record.minesDisarmed.add(minesDisarmed)
        records[config.storageKey] = record
        persist()
    }

    /// Global cumulative totals (summed across every config). These are the
    /// player-facing lifetime stats — never a ratio (no win%, which only
    /// discourages); the raw counts stay neutral.
    public var totalWins: Int { records.values.reduce(0) { $0 + $1.wins.total } }
    public var totalGamesPlayed: Int { records.values.reduce(0) { $0 + $1.gamesPlayed.total } }
    public var totalTilesOpened: Int { records.values.reduce(0) { $0 + $1.tilesOpened.total } }
    public var totalFlagsPlaced: Int { records.values.reduce(0) { $0 + $1.flagsPlaced.total } }
    public var totalMinesHit: Int { records.values.reduce(0) { $0 + $1.minesHit.total } }
    public var totalMinesDisarmed: Int {
        records.values.reduce(0) { $0 + $1.minesDisarmed.total }
    }
    public var totalPlaytimeCentiseconds: Int {
        records.values.reduce(0) { $0 + $1.playtimeCentiseconds.total }
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
