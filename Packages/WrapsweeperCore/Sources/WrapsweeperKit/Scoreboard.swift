import Foundation
import WrapsweeperCore

/// Per-difficulty stats: how many games have been cleared, and the best time.
public struct ScoreRecord: Codable, Equatable, Sendable {
    /// Total games cleared on this difficulty.
    public var wins: Int
    /// Fastest winning time in seconds, or nil if none recorded yet.
    public var bestSeconds: Int?

    public init(wins: Int = 0, bestSeconds: Int? = nil) {
        self.wins = wins
        self.bestSeconds = bestSeconds
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
    private let key = "wrapsweeper.stats.v1"

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

    public func best(for config: GameConfig) -> Int? {
        records[config.storageKey]?.bestSeconds
    }

    public func wins(for config: GameConfig) -> Int {
        records[config.storageKey]?.wins ?? 0
    }

    /// True if `seconds` would beat (or set) the best time for this config.
    public func isNewRecord(_ seconds: Int, for config: GameConfig) -> Bool {
        guard let best = records[config.storageKey]?.bestSeconds else { return true }
        return seconds < best
    }

    /// Record a win: always bumps the clear count, and updates the best time if
    /// `seconds` beats it. Returns true if it set a new best time.
    @discardableResult
    public func submit(_ seconds: Int, for config: GameConfig) -> Bool {
        var record = records[config.storageKey] ?? ScoreRecord()
        record.wins += 1
        let isBest = record.bestSeconds.map { seconds < $0 } ?? true
        if isBest { record.bestSeconds = seconds }
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
