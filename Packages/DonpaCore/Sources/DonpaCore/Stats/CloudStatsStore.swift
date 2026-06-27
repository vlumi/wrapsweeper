import Foundation

/// The cloud side of scoreboard sync, abstracted so `Scoreboard` doesn't depend
/// on `NSUbiquitousKeyValueStore` directly (and so it's mockable in tests).
///
/// The layout is **one blob per device**: each device writes only its own
/// `records` table under a key derived from its `DeviceID`, and reads every
/// device's blob to merge (see `StatsMerge`). No device writes another's slot, so
/// there's nothing to conflict-resolve.
@MainActor
public protocol CloudStatsStore: AnyObject {
    /// Whether the cloud is currently available (signed into iCloud). When false,
    /// reads/writes are no-ops and the app stays local-only.
    var isAvailable: Bool { get }

    /// Write this device's encoded records blob to its own slot.
    func writeOwnBlob(_ data: Data, deviceID: String)

    /// Remove this device's own slot from the cloud (when the player turns sync off
    /// or resets) — so it stops contributing to other devices' totals. Other
    /// devices' slots are untouched.
    func deleteOwnBlob(deviceID: String)

    /// Every device's blob, keyed by device id (including this device's own).
    func readAllBlobs() -> [String: Data]

    /// Hint the store to push/pull now (best-effort; not a guarantee).
    func synchronize()

    /// Called when the cloud changes externally (another device synced) or the
    /// iCloud account changes — so the host can re-merge and refresh status.
    var onExternalChange: (() -> Void)? { get set }
}

#if canImport(Foundation)
/// `NSUbiquitousKeyValueStore`-backed store. Per-device blobs live under keys
/// prefixed `donpa.stats.blob.` so they're easy to enumerate and never collide
/// with any other KVS use.
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

    /// Signed into iCloud iff there's a ubiquity identity token. (KVS itself has no
    /// per-app permission — it rides on the system iCloud sign-in.)
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
        // Fires for server changes AND account changes; either way, re-merge.
        onExternalChange?()
    }
}
#endif
