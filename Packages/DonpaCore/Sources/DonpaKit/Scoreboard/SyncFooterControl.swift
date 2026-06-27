import DonpaCore
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Compact iCloud-sync control for the stats sheet footer: a toggle with an
/// inline status to its right. Opt-in (off by default). When on + signed out, the
/// status is a tappable nudge that deep-links to system Settings — KVS has no
/// in-app permission prompt, so the most we can do is point the player there.
struct SyncFooterControl: View {
    @ObservedObject var settings: Settings
    @ObservedObject var scoreboard: Scoreboard

    var body: some View {
        HStack(spacing: 8) {
            Toggle(isOn: $settings.syncScores) {
                Text("Sync", bundle: .module).font(.subheadline.weight(.medium))
            }
            .toggleStyle(.switch)
            .fixedSize()

            if settings.syncScores {
                if scoreboard.isCloudActive {
                    Label {
                        Text("via iCloud", bundle: .module)
                    } icon: {
                        Image(systemName: "checkmark.icloud")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Button {
                        openSystemSettings()
                    } label: {
                        Text("Sign into iCloud", bundle: .module).font(.caption.bold())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }
            } else {
                Text("This device only", bundle: .module)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
    }

    /// Deep-link to the system Settings/Preferences so the player can sign into
    /// iCloud (we can't toggle the system setting from inside the app).
    private func openSystemSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #elseif os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane")
        {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
}
