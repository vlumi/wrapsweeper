import Foundation

/// Per-difficulty stats store (clears + best time + career counters), persisted
/// in `UserDefaults` with optional cross-device sync via iCloud KVS (see
/// `CloudStatsStore` / `StatsMerge`). The `ScoreRecord` value type lives in
/// `ScoreRecord.swift`.
@MainActor
public final class Scoreboard: ObservableObject {
    /// THIS device's own records — the source of truth for our counts (every
    /// `DeviceCounter.mine`) and best times. Writes mutate this; it's persisted
    /// locally and pushed to the cloud as this device's blob. Internal: the UI
    /// reads the merged view via the accessors / `displayRecords`.
    @Published private(set) var records: [String: ScoreRecord]

    /// The cross-device view: this device's records merged with every other
    /// device's cloud blob (see `StatsMerge`). Equals `records` when sync is off or
    /// unavailable. All public read accessors and the UI go through this.
    @Published public private(set) var displayRecords: [String: ScoreRecord]

    /// Storage key of the config whose record was just set, so the scoreboard can
    /// highlight that row. Set by `submit`/`submitLossProgress` on a new best;
    /// cleared by `clearRecentRecord()` when the next game ends (so an accidental
    /// restart before checking scores doesn't lose the highlight). Not persisted.
    @Published public private(set) var recentRecord: String?

    private let defaults: UserDefaults
    private let key = "donpa.stats.v1"
    /// Cache of the last computed cross-device merge (own + others), persisted so
    /// the combined totals survive going offline — otherwise others' contributions
    /// would vanish on an airplane / signed-out and the displayed totals would
    /// collapse to this device's own, then jump back on reconnect. Only written
    /// while sync is on and the cloud is reachable; read as the display when sync
    /// is on but the cloud is momentarily unavailable.
    private let mergedKey = "donpa.stats.merged.v1"

    // MARK: Cross-device sync (iCloud KVS)

    /// The cloud store, or nil for a pure-local scoreboard (the default, and every
    /// existing test). Injected by the app.
    private let cloud: (any CloudStatsStore)?
    private let deviceID: String
    /// User preference gate. When false, the cloud is never read/written and the
    /// display is just this device's own records. Settable so a Settings toggle
    /// can flip it live.
    public var syncEnabled: Bool {
        didSet {
            guard syncEnabled != oldValue else { return }
            if syncEnabled {
                // Re-enabling: re-publish this device's blob and pull everyone's.
                pushAndMerge()
            } else {
                // Turning off is a real opt-out: remove this device's blob from the
                // cloud so it stops contributing to other devices' totals (other
                // devices' blobs are untouched). Then show local-only.
                cloud?.deleteOwnBlob(deviceID: deviceID)
                refreshDisplay()
            }
        }
    }

    /// True when sync is on AND the cloud is reachable (signed into iCloud) — for
    /// the Settings status row.
    public var isCloudActive: Bool { syncEnabled && (cloud?.isAvailable ?? false) }

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

    public init(
        defaults: UserDefaults = .standard,
        cloud: (any CloudStatsStore)? = nil,
        syncEnabled: Bool = true
    ) {
        self.defaults = defaults
        self.cloud = cloud
        self.deviceID = DeviceID.current(in: defaults)
        self.syncEnabled = syncEnabled
        let own = Self.load(from: defaults, key: key)
        records = own
        // Start from the cached merge if sync is on (so an offline launch shows the
        // last-known combined totals, not just this device's); own-only otherwise.
        if syncEnabled, let cached = Self.loadIfPresent(from: defaults, key: mergedKey) {
            displayRecords = cached
        } else {
            displayRecords = own
        }
        // Re-merge when another device syncs or the iCloud account changes.
        cloud?.onExternalChange = { [weak self] in self?.refreshDisplay() }
        // Initial reconcile: publish our blob and pull everyone's (refreshes the
        // cache when reachable; leaves the cached merge in place when offline).
        pushAndMerge()
    }

    /// Push this device's blob to the cloud, then re-merge for display. No-op when
    /// sync is off or the cloud is unavailable.
    private func pushAndMerge() {
        guard syncEnabled, let cloud, cloud.isAvailable else {
            refreshDisplay()
            return
        }
        let file = StatsFile(version: Self.currentVersion, records: records)
        if let data = try? JSONEncoder().encode(file) {
            cloud.writeOwnBlob(data, deviceID: deviceID)
        }
        refreshDisplay()
    }

    /// Pull the latest from the cloud and re-merge — call when the app becomes
    /// active, so a change made on another device (incl. removing a device, which
    /// REDUCES totals) lands even if the live notification was missed while
    /// backgrounded. `synchronize()` nudges KVS to fetch; the re-merge reflects
    /// whatever's arrived. No-op when sync is off/unavailable.
    public func refreshFromCloud() {
        guard syncEnabled, let cloud, cloud.isAvailable else { return }
        cloud.synchronize()
        refreshDisplay()
    }

    /// Recompute `displayRecords` = own records merged with the other devices'
    /// cloud blobs, and cache it for offline. Behaviour by state:
    /// - sync OFF (user opted out): show own-only and drop the cache.
    /// - sync ON but cloud unreachable (offline / signed out): KEEP the last-known
    ///   cached merge, so combined totals don't collapse on an airplane.
    /// - sync ON and reachable: re-merge from the cloud and refresh the cache.
    private func refreshDisplay() {
        guard syncEnabled else {
            displayRecords = records
            defaults.removeObject(forKey: mergedKey)  // user opted out → forget others
            return
        }
        guard let cloud, cloud.isAvailable else {
            // Offline: leave displayRecords showing the cached merge (loaded at
            // init or last computed online). Only fall back to own-only if there's
            // no cache yet (never synced).
            if defaults.data(forKey: mergedKey) == nil { displayRecords = records }
            return
        }
        let blobs = cloud.readAllBlobs()
        var others: [String: [String: ScoreRecord]] = [:]
        for (id, data) in blobs where id != deviceID {
            // Decode each device's blob with the same tolerant per-entry loader, so
            // one corrupt foreign blob can't break the merge.
            others[id] = Self.decodeBlob(data)
        }
        let merged = StatsMerge.merge(mine: records, others: others)
        displayRecords = merged
        // Cache the merged totals so they persist across launches / offline.
        let file = StatsFile(version: Self.currentVersion, records: merged)
        if let data = try? JSONEncoder().encode(file) {
            defaults.set(data, forKey: mergedKey)
        }
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
        return decodeBlob(data)
    }

    /// Like `load`, but nil when the key is absent (vs an empty table) — so the
    /// caller can tell "no cached merge yet" from "a cached empty table".
    private static func loadIfPresent(from defaults: UserDefaults, key: String) -> [String:
        ScoreRecord]?
    {
        guard defaults.data(forKey: key) != nil else { return nil }
        return load(from: defaults, key: key)
    }

    /// Decode a stats blob (local or a cloud per-device blob) into records,
    /// resilient to partial corruption and old formats:
    /// 1. Prefer the versioned envelope; reject a *newer* version (a breaking
    ///    change this build predates) so we don't overwrite/mis-read it.
    /// 2. Fall back to a legacy bare `[String: ScoreRecord]` (pre-envelope).
    /// 3. Either way, decode **per entry** — one corrupt/incompatible record is
    ///    dropped, never wiping the whole table.
    static func decodeBlob(_ data: Data) -> [String: ScoreRecord] {
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

    // Read accessors reflect the cross-device DISPLAY view (own merged with other
    // devices'); writes below mutate this device's OWN `records`.

    public func record(for config: GameConfig) -> ScoreRecord? {
        displayRecords[config.storageKey]
    }

    /// Best time for this config, in centiseconds.
    public func best(for config: GameConfig) -> Int? {
        displayRecords[config.storageKey]?.bestCentiseconds
    }

    public func wins(for config: GameConfig) -> Int {
        displayRecords[config.storageKey]?.wins.total ?? 0
    }

    /// Best progress (0...1) to display for this config: 1.0 once the board has
    /// ever been cleared (a win is implicitly full), otherwise the best partial
    /// progress from a loss. `nil` if the config has never been finished.
    public func bestProgress(for config: GameConfig) -> Double? {
        guard let record = displayRecords[config.storageKey] else { return nil }
        // A recorded best TIME is itself proof the board was cleared (100%) — more
        // robust than the wins counter, which can read 0 while a best time survives
        // (the tolerant decode resets counters but keeps best times; and best time
        // merges by `min` across devices independently of the wins sum). Checking
        // the time avoids showing "<100% AND a best time" for a board that was, in
        // fact, cleared (possibly only on another device).
        if record.bestCentiseconds != nil || record.wins.total > 0 { return 1.0 }
        return record.bestLossProgress
    }

    /// True if `centiseconds` would beat (or set) the best time for this config —
    /// compared against the cross-device best (so a faster time on another device
    /// already counts).
    public func isNewRecord(_ centiseconds: Int, for config: GameConfig) -> Bool {
        guard let best = displayRecords[config.storageKey]?.bestCentiseconds else { return true }
        return centiseconds < best
    }

    /// Record a win: always bumps the clear count, and updates the best time if
    /// `centiseconds` beats it. Returns true if it set a new best time.
    @discardableResult
    public func submit(_ centiseconds: Int, for config: GameConfig) -> Bool {
        var record = records[config.storageKey] ?? ScoreRecord()
        record.wins.add(1)
        // "New record" is judged against the CROSS-DEVICE best (the merged display),
        // not just this device's — so a time another device already beat doesn't
        // falsely read as a record. The value still stores in this device's own
        // record; the merge re-derives the displayed best.
        let isBest = best(for: config).map { centiseconds < $0 } ?? true
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
        // Compare against the CROSS-DEVICE best progress (the merged display), so a
        // loss doesn't read as a "new best %" if another device already did better
        // (or cleared the board — which makes the displayed best 100%).
        // `bestProgress(for:)` returns 1.0 when any device has a win.
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
        cloud?.deleteOwnBlob(deviceID: deviceID)
        records = [:]
        recentRecord = nil
        // persist() re-publishes an empty own-blob and re-merges; combined with the
        // delete above, this device contributes nothing anywhere.
        persist()
    }

    /// Persist this device's own records locally, then push to the cloud + re-merge
    /// the display. Every write path funnels here.
    private func persist() {
        let file = StatsFile(version: Self.currentVersion, records: records)
        if let data = try? JSONEncoder().encode(file) {
            defaults.set(data, forKey: key)
        }
        pushAndMerge()
    }
}
