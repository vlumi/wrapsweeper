import Foundation

/// Owns the iCloud-KVS side of the scoreboard: pushing this device's blob,
/// merging every device's blob for display (`StatsMerge`), and caching the merge
/// so combined totals survive going offline. `Scoreboard` keeps the local store +
/// score API and delegates all sync here.
///
/// The coordinator reads this device's own records via `ownRecords` and publishes
/// the merged result via `onMerged` — so it never owns the records, just the
/// transport + merge.
@MainActor
final class StatsSyncCoordinator {
    private let cloud: (any CloudStatsStore)?
    private let deviceID: String
    private let defaults: UserDefaults
    /// Cache of the last merge, persisted so totals survive offline rather than
    /// collapsing to own-only then jumping back on reconnect.
    private let mergedKey = "donpa.stats.merged.v1"

    /// Read this device's own records (the source pushed + merged). Set by the
    /// owner after init, once `self` exists.
    var ownRecords: () -> [String: ScoreRecord] = { [:] }
    /// Publish the merged (or own-only) display. Set by the owner after init.
    var onMerged: ([String: ScoreRecord]) -> Void = { _ in }
    /// Encode/decode a records blob in the Scoreboard's persistence format.
    private let encode: ([String: ScoreRecord]) -> Data?
    private let decode: (Data) -> [String: ScoreRecord]

    /// User gate. Off → cloud never read/written (own-only display); flipping it
    /// re-publishes (on) or removes this device's blob + shows own-only (off).
    var syncEnabled: Bool {
        didSet {
            guard syncEnabled != oldValue else { return }
            if syncEnabled {
                pushAndMerge()
            } else {
                cloud?.deleteOwnBlob(deviceID: deviceID)
                refresh()
            }
        }
    }

    /// Sync on AND iCloud reachable — for the status row.
    var isCloudActive: Bool { syncEnabled && (cloud?.isAvailable ?? false) }

    /// Whether iCloud is reachable at all (signed in), independent of the sync
    /// preference — so the UI can refuse to enable sync when it couldn't work.
    var isCloudAvailable: Bool { cloud?.isAvailable ?? false }

    init(
        cloud: (any CloudStatsStore)?,
        deviceID: String,
        defaults: UserDefaults,
        syncEnabled: Bool,
        encode: @escaping ([String: ScoreRecord]) -> Data?,
        decode: @escaping (Data) -> [String: ScoreRecord]
    ) {
        self.cloud = cloud
        self.deviceID = deviceID
        self.defaults = defaults
        self.syncEnabled = syncEnabled
        self.encode = encode
        self.decode = decode
        self.cloud?.onExternalChange = { [weak self] in self?.refresh() }
    }

    /// The cached merge, or nil if none yet — lets a caller show last-known totals
    /// on an offline launch.
    func cachedMerge() -> [String: ScoreRecord]? {
        guard let data = defaults.data(forKey: mergedKey) else { return nil }
        return decode(data)
    }

    /// Push this device's blob, then re-merge. No-op on cloud when sync off /
    /// unavailable (still refreshes the display).
    func pushAndMerge() {
        if syncEnabled, let cloud, cloud.isAvailable, let data = encode(ownRecords()) {
            cloud.writeOwnBlob(data, deviceID: deviceID)
        }
        refresh()
    }

    /// Remove this device's cloud blob (on reset), so it stops contributing to
    /// other devices' totals. The caller then clears local + re-publishes empty.
    func deleteOwnBlob() {
        cloud?.deleteOwnBlob(deviceID: deviceID)
    }

    /// Pull + re-merge (call on foreground). No-op when sync off / unavailable.
    func refreshFromCloud() {
        guard syncEnabled, let cloud, cloud.isAvailable else { return }
        cloud.synchronize()
        refresh()
    }

    /// Recompute the display = own merged with other devices' blobs, and cache it.
    /// - sync OFF: own-only, drop the cache.
    /// - sync ON but unreachable (offline): keep the cached merge (don't collapse).
    /// - sync ON + reachable: re-merge and refresh the cache.
    func refresh() {
        guard syncEnabled else {
            onMerged(ownRecords())
            defaults.removeObject(forKey: mergedKey)
            return
        }
        guard let cloud, cloud.isAvailable else {
            // Offline: keep showing the cache; own-only only if there's none yet.
            if defaults.data(forKey: mergedKey) == nil { onMerged(ownRecords()) }
            return
        }
        var others: [String: [String: ScoreRecord]] = [:]
        for (id, data) in cloud.readAllBlobs() where id != deviceID {
            others[id] = decode(data)  // tolerant per-entry decode — a bad blob can't break it
        }
        let merged = StatsMerge.merge(mine: ownRecords(), others: others)
        onMerged(merged)
        if let data = encode(merged) { defaults.set(data, forKey: mergedKey) }
    }
}
