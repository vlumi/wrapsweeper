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
