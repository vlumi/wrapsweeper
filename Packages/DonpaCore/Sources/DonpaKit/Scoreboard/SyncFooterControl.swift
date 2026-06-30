import DonpaCore
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Compact iCloud-sync control for the stats sheet footer: a toggle plus inline
/// status. Opt-in (off by default). The toggle refuses to turn on while iCloud is
/// unavailable (signed out) — there'd be nothing to sync with — and the status then
/// tells the player to sign in. KVS has no in-app permission prompt to surface.
struct SyncFooterControl: View {
    @ObservedObject var settings: Settings
    @ObservedObject var scoreboard: Scoreboard

    /// Turning sync ON only sticks when iCloud is actually reachable; otherwise the
    /// switch snaps back off (the status row explains why). Turning OFF always works.
    private var syncBinding: Binding<Bool> {
        Binding(
            get: { settings.syncScores },
            set: { settings.syncScores = $0 && scoreboard.isCloudAvailable })
    }

    var body: some View {
        HStack(spacing: 8) {
            Toggle(isOn: syncBinding) {
                Text("Sync", bundle: .module).font(.subheadline.weight(.medium))
            }
            .toggleStyle(.switch)
            .fixedSize()

            if settings.syncScores, scoreboard.isCloudActive {
                Label {
                    Text("via iCloud", bundle: .module)
                } icon: {
                    Image(systemName: "checkmark.icloud")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if !scoreboard.isCloudAvailable {
                signInPrompt
            } else {
                Text("This device only", bundle: .module)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
    }

    /// How the player gets iCloud signed in. macOS can deep-link straight to the
    /// Apple-ID pane; iOS can't (the only public URL opens THIS app's settings, not
    /// iCloud sign-in), so there it's plain guidance text, not a misleading button.
    @ViewBuilder private var signInPrompt: some View {
        #if os(macOS)
        Button {
            if let url = URL(
                string: "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane")
            {
                NSWorkspace.shared.open(url)
            }
        } label: {
            Text("Sign into iCloud", bundle: .module).font(.caption.bold())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        #else
        Text("iCloud sign-in required", bundle: .module)
            .font(.caption)
            .foregroundStyle(.secondary)
        #endif
    }
}
