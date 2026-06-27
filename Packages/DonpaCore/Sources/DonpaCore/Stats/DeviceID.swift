import Foundation

/// A stable per-install identifier, used as this device's slot key in iCloud
/// scoreboard sync.
///
/// A UUID persisted in `UserDefaults`, not `identifierForVendor` (iOS-only; we
/// need one scheme across iOS + macOS). Trade-off: reinstalling mints a new id and
/// abandons the old cloud slot — the accepted churn risk, since a reinstall can't
/// be told apart from a merely-offline device.
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
