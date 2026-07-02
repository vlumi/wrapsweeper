import Foundation

/// The cloud side of scoreboard sync, abstracted off `NSUbiquitousKeyValueStore`
/// so it's mockable in tests. Layout is **one blob per device**: each writes only
/// its own slot (keyed by `DeviceID`) and reads all blobs to merge (`StatsMerge`),
/// so there's nothing to conflict-resolve.
@MainActor
public protocol CloudStatsStore: AnyObject {
    /// Whether iCloud is available; when false, reads/writes are no-ops.
    var isAvailable: Bool { get }

    /// Write this device's encoded records blob to its own slot.
    func writeOwnBlob(_ data: Data, deviceID: String)

    /// Remove this device's own slot (on sync-off / reset) so it stops contributing
    /// to other devices' totals. Other slots are untouched.
    func deleteOwnBlob(deviceID: String)

    /// Every device's blob, keyed by device id (including this device's own).
    func readAllBlobs() -> [String: Data]

    /// Delete EVERY device's blob (the global-wipe hammer). Only removes blobs
    /// currently visible in the cloud — an offline device's blob is dealt with by
    /// the reset epoch (it self-wipes when it next sees the newer epoch).
    func deleteAllBlobs()

    /// The board-wide reset generation. Bumping it tombstones all data written
    /// before it: every device compares this to the epoch it last honored and, when
    /// this is greater, wipes its own local + blob (so an offline device that missed
    /// the wipe catches up instead of resurrecting). 0 when never set.
    func readResetEpoch() -> Int

    /// Publish a new reset epoch (monotonic; only ever bumped upward).
    func writeResetEpoch(_ epoch: Int)

    /// Hint the store to push/pull now (best-effort).
    func synchronize()

    /// Called on external cloud change or iCloud account change, so the host
    /// re-merges and refreshes status.
    var onExternalChange: (() -> Void)? { get set }
}

#if canImport(Foundation)
/// `NSUbiquitousKeyValueStore`-backed store. Per-device blobs live under keys
/// prefixed `donpa.stats.blob.`, so they're easy to enumerate and never collide.
@MainActor
public final class UbiquitousStatsStore: CloudStatsStore {
    private static let blobPrefix = "donpa.stats.blob."
    private static let resetEpochKey = "donpa.stats.resetEpoch"

    private let kvs = NSUbiquitousKeyValueStore.default
    public var onExternalChange: (() -> Void)?
    private var observer: NSObjectProtocol?

    public init() {
        // The external-change notification's delivery thread is NOT documented as
        // main; the callback re-enters @MainActor sync code, so marshal it to the
        // main queue explicitly (block-based observer with queue: .main) instead of
        // a selector that runs on whatever thread posted.
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: kvs,
            queue: .main
        ) { [weak self] _ in
            // Fires for server and account changes; either way, re-merge.
            MainActor.assumeIsolated { self?.onExternalChange?() }
        }
        kvs.synchronize()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Signed into iCloud iff there's a ubiquity identity token.
    public var isAvailable: Bool { FileManager.default.ubiquityIdentityToken != nil }

    public func writeOwnBlob(_ data: Data, deviceID: String) {
        guard isAvailable else { return }
        kvs.set(data, forKey: Self.blobPrefix + deviceID)
        kvs.synchronize()
    }

    public func deleteOwnBlob(deviceID: String) {
        guard isAvailable else { return }
        kvs.removeObject(forKey: Self.blobPrefix + deviceID)
        kvs.synchronize()
    }

    public func readAllBlobs() -> [String: Data] {
        guard isAvailable else { return [:] }
        var out: [String: Data] = [:]
        for (key, value) in kvs.dictionaryRepresentation where key.hasPrefix(Self.blobPrefix) {
            if let data = value as? Data {
                out[String(key.dropFirst(Self.blobPrefix.count))] = data
            }
        }
        return out
    }

    public func deleteAllBlobs() {
        guard isAvailable else { return }
        for key in kvs.dictionaryRepresentation.keys where key.hasPrefix(Self.blobPrefix) {
            kvs.removeObject(forKey: key)
        }
        kvs.synchronize()
    }

    public func readResetEpoch() -> Int {
        guard isAvailable else { return 0 }
        // KVS longLong is 0 when the key is absent — the pre-wipe baseline.
        return Int(kvs.longLong(forKey: Self.resetEpochKey))
    }

    public func writeResetEpoch(_ epoch: Int) {
        guard isAvailable else { return }
        // Best-effort monotonic guard: KVS is eventually consistent, so a wiper
        // computing its next epoch from a stale read could otherwise LOWER the
        // published epoch and split devices into diverging generations. A re-read
        // here can still be stale, but never regress what this device can see.
        let current = Int(kvs.longLong(forKey: Self.resetEpochKey))
        kvs.set(Int64(max(current, epoch)), forKey: Self.resetEpochKey)
        kvs.synchronize()
    }

    public func synchronize() { kvs.synchronize() }
}
#endif
