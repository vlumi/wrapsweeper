import Foundation

/// The pure, deterministic merge at the heart of cross-device scoreboard sync.
///
/// Each device owns one blob of `records` in the cloud, keyed by its `DeviceID`,
/// holding ONLY its own counts (every `DeviceCounter.mine`; `othersTotal` in a
/// stored blob is ignored on read, so there's no transitive double-counting).
/// To display the cross-device view, a device merges its own records with every
/// *other* device's blob:
///
/// - **Cumulative counters** (wins, gamesPlayed, tiles, …): `mine` stays this
///   device's own precise count; `othersTotal` becomes the sum of every other
///   device's `mine`. So `total = mine + Σ others` — conflict-free, order- and
///   duplicate-independent (re-reading the same blob can't inflate it), and
///   concurrent play on two devices Just Works.
/// - **"Best" fields** (bestCentiseconds, bestLossProgress): idempotent
///   `min`/`max` across ALL blobs (mine + others), nil-safe.
///
/// Pure: no I/O, no clock, no globals — just (mine, others) → merged. That's what
/// makes it unit-testable headless (the high-value tests; KVS itself can only be
/// verified on real devices).
enum StatsMerge {
    /// Merge this device's records with the other devices' record blobs into the
    /// display records. `mine` is this device's own table; `others` is keyed by
    /// the other devices' ids (this device's own id must NOT be in `others`).
    static func merge(
        mine: [String: ScoreRecord], others: [String: [String: ScoreRecord]]
    ) -> [String: ScoreRecord] {
        // Every config key that appears anywhere.
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
        foldCounter(\.tilesOpened)
        foldCounter(\.flagsPlaced)
        foldCounter(\.minesHit)
        foldCounter(\.minesDisarmed)
        foldCounter(\.playtimeCentiseconds)

        // Best fields: idempotent min/max across this device + all others.
        let allBest = ([own] + others).compactMap(\.bestCentiseconds)
        out.bestCentiseconds = allBest.min()
        let allProgress = ([own] + others).compactMap(\.bestLossProgress)
        out.bestLossProgress = allProgress.max()

        return out
    }
}
