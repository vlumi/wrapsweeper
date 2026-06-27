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

    private let kvs = NSUbiquitousKeyValueStore.default
    public var onExternalChange: (() -> Void)?

    public init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(externalChange(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: kvs)
        kvs.synchronize()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

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

    public func synchronize() { kvs.synchronize() }

    @objc private func externalChange(_ note: Notification) {
        // Fires for server and account changes; either way, re-merge.
        onExternalChange?()
    }
}
#endif
