import DonpaCore
import Foundation

/// Per-config stats: how many games have been cleared, and the best time.
public struct ScoreRecord: Codable, Equatable, Sendable {
    /// Total games cleared on this config.
    public var wins: Int
    /// Fastest winning time in centiseconds (hundredths), or nil if none yet.
    public var bestCentiseconds: Int?

    public init(wins: Int = 0, bestCentiseconds: Int? = nil) {
        self.wins = wins
        self.bestCentiseconds = bestCentiseconds
    }
}

/// Local per-difficulty stats store (clears + best time), persisted in
/// `UserDefaults`. No security beyond the OS's per-app preferences file — a
/// determined user can edit it, which is fine for a local high-score table.
@MainActor
public final class Scoreboard: ObservableObject {
    @Published public private(set) var records: [String: ScoreRecord]

    private let defaults: UserDefaults
    // Key bumped from the old name-keyed store; entries are now keyed by
    // `GameConfig.storageKey` (geometry-bearing, versioned). Pre-release, so the
    // old store is simply not read — no migration by design.
    private let key = "donpa.stats.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode([String: ScoreRecord].self, from: data)
        {
            records = decoded
        } else {
            records = [:]
        }
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
        if isBest { record.bestCentiseconds = centiseconds }
        records[config.storageKey] = record
        persist()
        return isBest
    }

    public func reset() {
        records = [:]
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey: key)
        }
    }
}
