import Foundation

/// A stable per-install identifier, used as this device's slot key in the iCloud
/// scoreboard sync (each device writes only its own slot — see `DeviceCounter`).
///
/// It's a UUID generated once and persisted in `UserDefaults`, NOT
/// `identifierForVendor` — that's iOS-only (absent on macOS) and we need one
/// identifier scheme across both. The trade-off: deleting/reinstalling mints a
/// new id (the old slot is abandoned in the cloud), which is the known churn risk
/// the sync design accepts; pruning stale slots is deferred (a reinstall can't be
/// told apart from a device that's merely offline).
public enum DeviceID {
    static let defaultsKey = "donpa.deviceID"

    /// The stable id for this install, creating + persisting one on first use.
    public static func current(in defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: defaultsKey) { return existing }
        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: defaultsKey)
        return fresh
    }
}
