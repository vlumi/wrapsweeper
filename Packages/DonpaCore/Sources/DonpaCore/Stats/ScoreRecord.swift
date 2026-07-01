import Foundation

/// Per-config stats. Cumulative counts are `DeviceCounter`s so they sum correctly
/// across devices. Best time + top times are **device-owned** (each device keeps its
/// own; the cross-device view is projected at merge time — see `StatsMerge`), so a
/// timestamp can ride with each value without the merge ever separating them.
///
/// We collect generously and expose only sums/bests today — the extra fields feed
/// achievements / gating / rank later (see the progression-layer plan). All fields
/// decode tolerantly (missing → empty/nil), so the blob format stays v1: adding a
/// field never invalidates an existing record.
public struct ScoreRecord: Equatable, Sendable {
    public var wins: DeviceCounter
    /// Games finished (won or lost). Deliberately never shown as a win-rate ratio.
    public var gamesPlayed: DeviceCounter
    /// Games lost. Redundant with `gamesPlayed - wins` but tracked explicitly so it
    /// stays correct independent of how the others are adjusted.
    public var losses: DeviceCounter
    public var tilesOpened: DeviceCounter
    public var flagsPlaced: DeviceCounter
    public var minesHit: DeviceCounter
    /// Mines correctly flagged at game end ("disarmed").
    public var minesDisarmed: DeviceCounter
    public var playtimeCentiseconds: DeviceCounter
    /// Chord actions taken (mastery signal; a low count on a win is skillful).
    public var chordsUsed: DeviceCounter
    /// Wins in which no flag was ever placed (a mastery feat). Needs the game-end
    /// `usedFlagEver` signal.
    public var noFlagWins: DeviceCounter
    /// Wins in which chord was never used. Needs the game-end `usedChordEver` signal.
    public var noChordWins: DeviceCounter

    /// This DEVICE's fastest winning time (+ when), or nil if none yet. Device-owned:
    /// the merge projects the cross-device min for display but never overwrites this.
    public var best: BestTime?
    /// This device's fastest `topTimeLimit` winning times, fastest first. Device-
    /// owned; the merge projects the cross-device top list for display.
    public var topTimes: [BestTime]
    /// Best fraction (0...1) of safe cells revealed in a *losing* game; a win is
    /// implicitly 100% (`wins.total > 0`). Optional so old records decode.
    public var bestLossProgress: Double?
    /// First and most-recent time this config was played (min / max merge).
    public var firstPlayed: Date?
    public var lastPlayed: Date?

    /// How many top times to retain per config, per device.
    public static let topTimeLimit = 5

    /// Fastest winning centiseconds (compat shim over `best`), for existing callers.
    public var bestCentiseconds: Int? { best?.centiseconds }

    public init(
        wins: DeviceCounter = .init(), gamesPlayed: DeviceCounter = .init(),
        losses: DeviceCounter = .init(), tilesOpened: DeviceCounter = .init(),
        flagsPlaced: DeviceCounter = .init(), minesHit: DeviceCounter = .init(),
        minesDisarmed: DeviceCounter = .init(), playtimeCentiseconds: DeviceCounter = .init(),
        chordsUsed: DeviceCounter = .init(), noFlagWins: DeviceCounter = .init(),
        noChordWins: DeviceCounter = .init(),
        best: BestTime? = nil, topTimes: [BestTime] = [], bestLossProgress: Double? = nil,
        firstPlayed: Date? = nil, lastPlayed: Date? = nil
    ) {
        self.wins = wins
        self.gamesPlayed = gamesPlayed
        self.losses = losses
        self.tilesOpened = tilesOpened
        self.flagsPlaced = flagsPlaced
        self.minesHit = minesHit
        self.minesDisarmed = minesDisarmed
        self.playtimeCentiseconds = playtimeCentiseconds
        self.chordsUsed = chordsUsed
        self.noFlagWins = noFlagWins
        self.noChordWins = noChordWins
        self.best = best
        self.topTimes = topTimes
        self.bestLossProgress = bestLossProgress
        self.firstPlayed = firstPlayed
        self.lastPlayed = lastPlayed
    }
}

extension ScoreRecord: Codable {
    enum CodingKeys: String, CodingKey {
        case wins, gamesPlayed, losses, tilesOpened, flagsPlaced, minesHit, minesDisarmed
        case playtimeCentiseconds, chordsUsed, noFlagWins, noChordWins
        case best, topTimes, bestLossProgress, firstPlayed, lastPlayed
        // Legacy: a pre-`best` record stored the scalar `bestCentiseconds`.
        case legacyBestCentiseconds = "bestCentiseconds"
    }

    /// Tolerant decode: every field defaults to empty/nil when absent, so adding
    /// fields never drops a record and old blobs (incl. a pre-`best` scalar
    /// `bestCentiseconds`, dated to `firstPlayed`/now) still load. Counters use `try?`
    /// so a missing field or a legacy scalar `wins` yields an empty counter.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func counter(_ key: CodingKeys) -> DeviceCounter {
            (try? c.decode(DeviceCounter.self, forKey: key)) ?? .init()
        }
        wins = counter(.wins)
        gamesPlayed = counter(.gamesPlayed)
        losses = counter(.losses)
        tilesOpened = counter(.tilesOpened)
        flagsPlaced = counter(.flagsPlaced)
        minesHit = counter(.minesHit)
        minesDisarmed = counter(.minesDisarmed)
        playtimeCentiseconds = counter(.playtimeCentiseconds)
        chordsUsed = counter(.chordsUsed)
        noFlagWins = counter(.noFlagWins)
        noChordWins = counter(.noChordWins)
        // `try?` on `decode` yields nil for a missing/mistyped key (no `?? nil`).
        topTimes = (try? c.decode([BestTime].self, forKey: .topTimes)) ?? []
        bestLossProgress = try? c.decode(Double.self, forKey: .bestLossProgress)
        firstPlayed = try? c.decode(Date.self, forKey: .firstPlayed)
        lastPlayed = try? c.decode(Date.self, forKey: .lastPlayed)
        // `best`: prefer the new pair; else lift a legacy scalar into a `BestTime`
        // (dated to firstPlayed, or the epoch as a neutral placeholder).
        if let best = try? c.decode(BestTime.self, forKey: .best) {
            self.best = best
        } else if let cs = try? c.decode(Int.self, forKey: .legacyBestCentiseconds) {
            best = BestTime(
                centiseconds: cs, achievedAt: firstPlayed ?? Date(timeIntervalSince1970: 0))
        } else {
            best = nil
        }
        // Keep topTimes consistent with a lifted legacy best.
        if let best, topTimes.isEmpty { topTimes = [best] }
    }

    /// Explicit encode (the decode-only `legacyBestCentiseconds` key means the
    /// synthesized `Encodable` can't be generated). Writes the current shape only.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(wins, forKey: .wins)
        try c.encode(gamesPlayed, forKey: .gamesPlayed)
        try c.encode(losses, forKey: .losses)
        try c.encode(tilesOpened, forKey: .tilesOpened)
        try c.encode(flagsPlaced, forKey: .flagsPlaced)
        try c.encode(minesHit, forKey: .minesHit)
        try c.encode(minesDisarmed, forKey: .minesDisarmed)
        try c.encode(playtimeCentiseconds, forKey: .playtimeCentiseconds)
        try c.encode(chordsUsed, forKey: .chordsUsed)
        try c.encode(noFlagWins, forKey: .noFlagWins)
        try c.encode(noChordWins, forKey: .noChordWins)
        try c.encodeIfPresent(best, forKey: .best)
        try c.encode(topTimes, forKey: .topTimes)
        try c.encodeIfPresent(bestLossProgress, forKey: .bestLossProgress)
        try c.encodeIfPresent(firstPlayed, forKey: .firstPlayed)
        try c.encodeIfPresent(lastPlayed, forKey: .lastPlayed)
    }
}

// Local per-difficulty stats are persisted in `UserDefaults` — no security
// beyond the OS preferences file, which is fine for a local high-score table.
