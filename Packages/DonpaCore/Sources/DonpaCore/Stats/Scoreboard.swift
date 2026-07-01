import Foundation

/// Per-difficulty stats store (clears + best time + career counters), persisted
/// in `UserDefaults` with optional cross-device sync via iCloud KVS (see
/// `CloudStatsStore` / `StatsMerge`). The `ScoreRecord` value type lives in
/// `ScoreRecord.swift`.
@MainActor
public final class Scoreboard: ObservableObject {
    /// THIS device's own records — the source of truth for our counts and best
    /// times. Writes mutate this; it's pushed to the cloud as this device's blob.
    /// The UI reads the merged `displayRecords` via the accessors.
    @Published private(set) var records: [String: ScoreRecord]

    /// Cross-device view: own records merged with every other device's blob (see
    /// `StatsMerge`); equals `records` when sync is off/unavailable. The UI uses this.
    @Published public private(set) var displayRecords: [String: ScoreRecord]

    /// The config whose record was just set, so the scoreboard can highlight that
    /// row; cleared when the next game ends. Not persisted.
    @Published public private(set) var recentRecord: String?

    private let defaults: UserDefaults
    private let key = "donpa.stats.v1"

    /// Owns the iCloud-KVS sync (push / merge / offline cache); nil-cloud → local.
    private let sync: StatsSyncCoordinator

    /// User gate for cross-device sync (pass-through to the coordinator).
    public var syncEnabled: Bool {
        get { sync.syncEnabled }
        set { sync.syncEnabled = newValue }
    }
    /// Sync on AND iCloud reachable — for the status row.
    public var isCloudActive: Bool { sync.isCloudActive }
    /// iCloud reachable (signed in), independent of the sync preference — so the UI
    /// can refuse to enable sync when it couldn't work.
    public var isCloudAvailable: Bool { sync.isCloudAvailable }
    /// Pull + re-merge from the cloud (call on foreground).
    public func refreshFromCloud() { sync.refreshFromCloud() }

    /// On-disk envelope: a format `version` wrapping the records, keyed by
    /// `GameConfig.storageKey` (geometry-bearing, so new variants add keys). `epoch`
    /// is the reset generation this blob was written under (see the wipe tombstone
    /// in `StatsSyncCoordinator`); a reader ignores blobs stamped below the current
    /// epoch. Only ever ENCODED (decoding reads the fields via `JSONSerialization` in
    /// `decodeBlob`/`decodeEpoch`, which default a missing epoch to 0), so no
    /// property default is needed here.
    private struct StatsFile: Encodable {
        var version: Int
        var records: [String: ScoreRecord]
        var epoch: Int
    }
    /// Bump only for a *breaking* shape change (additive fields decode tolerantly);
    /// then add a `migrated(_:)` step.
    private static let currentVersion = 1

    private static func encodeFile(_ records: [String: ScoreRecord], epoch: Int) -> Data? {
        try? JSONEncoder().encode(
            StatsFile(version: currentVersion, records: records, epoch: epoch))
    }

    /// The reset epoch stamped in a blob (0 if absent / undecodable).
    static func decodeEpoch(_ data: Data) -> Int {
        guard let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return 0 }
        return top["epoch"] as? Int ?? 0
    }

    #if DEBUG
    /// Test-only: forge a single-config blob at a specific epoch, to exercise the
    /// stale-epoch rejection path (a returning offline device's pre-wipe blob).
    static func testMakeBlob(wins: Int, for config: GameConfig, epoch: Int) -> Data {
        var rec = ScoreRecord()
        rec.wins.add(wins)
        return encodeFile([config.storageKey: rec], epoch: epoch) ?? Data()
    }
    #endif

    public init(
        defaults: UserDefaults = .standard,
        cloud: (any CloudStatsStore)? = nil,
        syncEnabled: Bool = true
    ) {
        self.defaults = defaults
        // Load own records, but drop them if the local blob predates the reset-epoch
        // floor — the one-off pre-release wipe applies to this device's own store
        // too, not just the cloud (see StatsSyncCoordinator.epochFloor).
        let own = Self.load(from: defaults, key: key)
        records = own
        displayRecords = own
        sync = StatsSyncCoordinator(
            cloud: cloud, deviceID: DeviceID.current(in: defaults), defaults: defaults,
            syncEnabled: syncEnabled, encode: Self.encodeFile, decode: Self.decodeBlob,
            decodeEpoch: Self.decodeEpoch)
        // Wire the coordinator's hooks now that `self` exists; it only calls them
        // from the methods invoked below.
        sync.ownRecords = { [weak self] in self?.records ?? [:] }
        sync.onMerged = { [weak self] merged in self?.displayRecords = merged }
        // On honoring a remote wipe, drop this device's own records (+ persist the
        // empty local store, without re-pushing — the coordinator handles the blob).
        sync.clearOwnRecords = { [weak self] in
            self?.records = [:]
            self?.recentRecord = nil
            self?.persistLocalOnly()
        }
        // Offline launch: show the last-known cached merge if syncing.
        if syncEnabled, let cached = sync.cachedMerge() { displayRecords = cached }
        sync.pushAndMerge()
    }

    private static func load(from defaults: UserDefaults, key: String) -> [String: ScoreRecord] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        // Drop own records written below the reset-epoch floor (pre-upgrade), so the
        // one-off clean slate covers this device's local store, not just the cloud.
        guard decodeEpoch(data) >= StatsSyncCoordinator.epochFloor else { return [:] }
        return decodeBlob(data)
    }

    /// Decode a stats blob (local, or a cloud per-device blob), resilient to old
    /// formats and partial corruption: prefer the versioned envelope (reject a
    /// newer version this build predates); fall back to a legacy bare dict; either
    /// way decode **per entry**, so one bad record is dropped, never the whole table.
    static func decodeBlob(_ data: Data) -> [String: ScoreRecord] {
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

    /// Migration seam. Identity today; transform records up one step per version
    /// here when `currentVersion` is bumped (with fixture tests).
    private static func migrated(_ records: [String: ScoreRecord], from version: Int)
        -> [String: ScoreRecord]
    {
        records
    }

    // Read accessors reflect the cross-device DISPLAY view (own merged with other
    // devices'); writes below mutate this device's OWN `records`.

    public func record(for config: GameConfig) -> ScoreRecord? {
        displayRecords[config.storageKey]
    }

    public func best(for config: GameConfig) -> Int? {
        displayRecords[config.storageKey]?.bestCentiseconds
    }

    public func wins(for config: GameConfig) -> Int {
        displayRecords[config.storageKey]?.wins.total ?? 0
    }

    /// Best progress (0...1), or nil if the config was never finished. A recorded
    /// best TIME means cleared → 100% (more robust than the wins counter, which can
    /// read 0 while a best time survives — see ScoreRecord's tolerant decode); else
    /// the best loss progress.
    public func bestProgress(for config: GameConfig) -> Double? {
        guard let record = displayRecords[config.storageKey] else { return nil }
        if record.bestCentiseconds != nil || record.wins.total > 0 { return 1.0 }
        return record.bestLossProgress
    }

    /// Whether `centiseconds` beats the cross-device best (so a faster time on
    /// another device already counts).
    public func isNewRecord(_ centiseconds: Int, for config: GameConfig) -> Bool {
        guard let best = displayRecords[config.storageKey]?.bestCentiseconds else { return true }
        return centiseconds < best
    }

    /// Record a win: bump the clear count, set the best time if it beats the
    /// cross-device best. Returns true on a new best.
    @discardableResult
    public func submit(_ centiseconds: Int, for config: GameConfig) -> Bool {
        var record = records[config.storageKey] ?? ScoreRecord()
        record.wins.add(1)
        // Judge against the cross-device best, but store in this device's own record.
        let isBest = best(for: config).map { centiseconds < $0 } ?? true
        if isBest {
            record.bestCentiseconds = centiseconds
            recentRecord = config.storageKey
        }
        records[config.storageKey] = record
        persist()
        return isBest
    }

    /// Record a *losing* game's progress, kept only if it beats the cross-device
    /// best (which is 100% once any device has cleared it). Returns true on a new
    /// best. Don't call on a win — that's `submit`.
    @discardableResult
    public func submitLossProgress(_ progress: Double, for config: GameConfig) -> Bool {
        var record = records[config.storageKey] ?? ScoreRecord()
        let currentBest = bestProgress(for: config) ?? 0
        let isBest = progress > currentBest
        if isBest {
            record.bestLossProgress = progress
            records[config.storageKey] = record
            recentRecord = config.storageKey
            persist()
        }
        return isBest
    }

    /// Add an in-game activity DELTA (tiles/flags/time) to the lifetime totals.
    /// Called repeatedly during play (the view model tracks what's flushed, so no
    /// double-count); does NOT touch games-played or outcomes. Empty deltas skipped.
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

    /// Record a finished game's outcome: games-played + the mine tally (one hit on
    /// a loss; disarmed count on a win). Activity accrues separately via
    /// `recordActivity`; wins/loss-progress via `submit`/`submitLossProgress`.
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
    public var totalWins: Int { displayRecords.values.reduce(0) { $0 + $1.wins.total } }
    public var totalGamesPlayed: Int {
        displayRecords.values.reduce(0) { $0 + $1.gamesPlayed.total }
    }
    public var totalTilesOpened: Int {
        displayRecords.values.reduce(0) { $0 + $1.tilesOpened.total }
    }
    public var totalFlagsPlaced: Int {
        displayRecords.values.reduce(0) { $0 + $1.flagsPlaced.total }
    }
    public var totalMinesHit: Int { displayRecords.values.reduce(0) { $0 + $1.minesHit.total } }
    public var totalMinesDisarmed: Int {
        displayRecords.values.reduce(0) { $0 + $1.minesDisarmed.total }
    }
    public var totalPlaytimeCentiseconds: Int {
        displayRecords.values.reduce(0) { $0 + $1.playtimeCentiseconds.total }
    }

    /// Clear the just-set-record highlight. Called when the next game ends.
    public func clearRecentRecord() {
        recentRecord = nil
    }

    /// Clear THIS device's scores — locally AND its contribution to iCloud (delete
    /// its cloud blob). So the shared totals on the player's OTHER devices drop by
    /// this device's amount too. Other devices' own blobs are untouched — a reset
    /// here can't erase another device's history. (When sync is off, this is a
    /// purely local clear; deleting the blob is a no-op since it isn't published.)
    public func reset() {
        sync.deleteOwnBlob()
        records = [:]
        recentRecord = nil
        persist()  // re-publishes an empty blob + re-merges → contributes nothing
    }

    /// GLOBAL wipe across all the player's devices, and it STICKS: bumps the cloud
    /// reset epoch (a tombstone every device honors, so an offline one wipes itself
    /// on return instead of resurrecting), deletes all cloud blobs, and clears this
    /// device. Returns whether the global tombstone was planted — false means sync
    /// was off or iCloud unreachable, so per the sync-scoped rule this fell back to
    /// a LOCAL-only clear (the cloud was deliberately left untouched).
    @discardableResult
    public func wipeAllSynced() -> Bool {
        let global = sync.wipeAllSynced()
        records = [:]
        recentRecord = nil
        if global {
            persistLocalOnly()  // epoch already bumped; coordinator owns the blob
            sync.refresh()
        } else {
            reset()  // local clear (also removes our own blob if one somehow exists)
        }
        return global
    }

    /// Persist own records locally (stamped with the current epoch), then push +
    /// re-merge via the coordinator. Every score-write path funnels here.
    private func persist() {
        persistLocalOnly()
        sync.pushAndMerge()
    }

    /// Write own records to the local store only (stamped with the honored epoch),
    /// without touching the cloud. Used when the coordinator already owns the cloud
    /// side (honoring a remote wipe, or after a global wipe bumped the epoch).
    private func persistLocalOnly() {
        if let data = Self.encodeFile(records, epoch: sync.honoredEpoch) {
            defaults.set(data, forKey: key)
        }
    }
}
