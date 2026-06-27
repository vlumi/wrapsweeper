import Foundation

/// Per-config stats. "Best" fields are idempotent merges (min/max); cumulative
/// counts are `DeviceCounter`s so they sum correctly across devices.
public struct ScoreRecord: Equatable, Sendable {
    public var wins: DeviceCounter
    /// Games finished (won or lost). Deliberately never shown as a win-rate ratio.
    public var gamesPlayed: DeviceCounter
    public var tilesOpened: DeviceCounter
    public var flagsPlaced: DeviceCounter
    public var minesHit: DeviceCounter
    /// Mines correctly flagged at game end ("disarmed").
    public var minesDisarmed: DeviceCounter
    public var playtimeCentiseconds: DeviceCounter
    /// Fastest winning time in centiseconds, or nil if none yet.
    public var bestCentiseconds: Int?
    /// Best fraction (0...1) of safe cells revealed in a *losing* game; a win is
    /// implicitly 100% (`wins.total > 0`). Optional so old records decode.
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

    /// Tolerant decode: best time / best %% are idempotent (min/max) fields, so
    /// they decode unchanged and existing high scores survive. Counters use `try?`
    /// — a missing field or a legacy scalar `wins` (bare Int) yields an empty
    /// counter, resetting counts to zero rather than dropping the record.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func counter(_ key: CodingKeys) -> DeviceCounter {
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

// Local per-difficulty stats are persisted in `UserDefaults` — no security
// beyond the OS preferences file, which is fine for a local high-score table.
