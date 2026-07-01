import Foundation

/// The pure, deterministic merge at the heart of cross-device scoreboard sync.
///
/// Each device owns one cloud blob keyed by its `DeviceID`, holding ONLY its own
/// counts (a stored `othersTotal` is ignored on read, so no double-counting). To
/// display the cross-device view, a device merges its own records with every
/// other device's blob:
///
/// - **Cumulative counters**: `mine` stays this device's count; `othersTotal`
///   becomes Σ of every other device's `mine`. So `total = mine + Σ others` —
///   conflict-free, order- and duplicate-independent.
/// - **"Best" fields**: idempotent `min`/`max` across all blobs, nil-safe.
///
/// Pure (no I/O, no clock), so it's unit-testable headless.
enum StatsMerge {
    /// Merge this device's records (`mine`) with the other devices' blobs
    /// (`others`, which must NOT contain this device's own id).
    static func merge(
        mine: [String: ScoreRecord], others: [String: [String: ScoreRecord]]
    ) -> [String: ScoreRecord] {
        var configKeys = Set(mine.keys)
        for table in others.values { configKeys.formUnion(table.keys) }

        var merged: [String: ScoreRecord] = [:]
        for key in configKeys {
            let ownRecord = mine[key] ?? ScoreRecord()
            let othersRecords = others.values.compactMap { $0[key] }
            merged[key] = mergeOne(own: ownRecord, others: othersRecords)
        }
        return merged
    }

    /// Merge one config's record: this device's own record against the other
    /// devices' records for the same config.
    private static func mergeOne(own: ScoreRecord, others: [ScoreRecord]) -> ScoreRecord {
        var out = own

        // Counters: keep my `mine`, set othersTotal = Σ each other device's `mine`.
        func foldCounter(_ kp: WritableKeyPath<ScoreRecord, DeviceCounter>) {
            let othersSum = others.reduce(0) { $0 + $1[keyPath: kp].mine }
            out[keyPath: kp].setOthersTotal(othersSum)
        }
        foldCounter(\.wins)
        foldCounter(\.gamesPlayed)
        foldCounter(\.losses)
        foldCounter(\.tilesOpened)
        foldCounter(\.flagsPlaced)
        foldCounter(\.minesHit)
        foldCounter(\.minesDisarmed)
        foldCounter(\.playtimeCentiseconds)
        foldCounter(\.chordsUsed)
        foldCounter(\.noFlagWins)
        foldCounter(\.noChordWins)

        // Best time + top times are DEVICE-OWNED: `own` keeps this device's own best
        // untouched; the DISPLAY record projects the cross-device view. Because each
        // `BestTime` carries its own timestamp, picking whole entries by their time
        // keeps every (time, date) pair intact — the timestamp is never merged apart.
        out.topTimes = own.topTimes.mergedTop(
            with: others.map(\.topTimes), limit: ScoreRecord.topTimeLimit)
        out.best = out.topTimes.first ?? own.best

        // Loss progress: idempotent max across all devices.
        out.bestLossProgress = ([own] + others).compactMap(\.bestLossProgress).max()

        // Dates: earliest first-played, latest last-played across all devices.
        out.firstPlayed = ([own] + others).compactMap(\.firstPlayed).min()
        out.lastPlayed = ([own] + others).compactMap(\.lastPlayed).max()

        return out
    }
}
