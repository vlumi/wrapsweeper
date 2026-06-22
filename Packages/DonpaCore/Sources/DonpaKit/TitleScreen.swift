import DonpaCore
import SwiftUI

/// The home hub, shown on launch and whenever you leave a game. The manga
/// "ドンパ隊 / DONPA SQUAD" splash heads it; below sit the board-type selection
/// (the only place you choose the game now) and entries into Settings and High
/// Scores. Start begins a game with the current selection.
///
/// The art is a single drop-in PNG in the `Panels` asset catalog. It's black ink
/// on a white page shown on a white plate in both appearances (the screentone
/// doesn't invert cleanly), framed by the page background.
struct TitleScreen: View {
    @ObservedObject var settings: Settings
    let onStart: () -> Void
    let onSettings: () -> Void
    let onScores: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            // The art is portrait, so it gets the most room stacked (full height).
            // Only go side-by-side when the window is genuinely wide — otherwise
            // a square-ish window should stack so the tall art can grow.
            let sideBySide = geo.size.width > geo.size.height * 1.4
            ZStack {
                Palette.resolved(for: colorScheme).pageBackground
                    .ignoresSafeArea()

                if sideBySide {
                    // Art + controls locked side-by-side, the pair centered.
                    let controlsW: CGFloat = min(360, max(240, geo.size.width * 0.28))
                    HStack(spacing: 20) {
                        art.frame(maxHeight: geo.size.height - 48)
                        controls.frame(width: controlsW)
                    }
                    .padding(24)
                } else {
                    // Art + controls locked together as one block, centered (art
                    // capped to leave room for the controls — no gap between).
                    VStack(spacing: 16) {
                        art.frame(maxHeight: geo.size.height - 240)
                        controls.frame(maxWidth: 460)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    /// The manga splash (the hero), with the secondary actions — High Scores and
    /// Settings — as small round buttons tucked into its top-right corner.
    private var art: some View {
        Image("TitleScreen", bundle: .module)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black.opacity(0.35), radius: 16, y: 5)
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 8) {
                    roundIcon("trophy.fill", label: "High Scores", action: onScores)
                    roundIcon("gearshape.fill", label: "Settings", action: onSettings)
                }
                .padding(10)
            }
    }

    /// Just the board selection + Start — the secondary actions live on the art.
    private var controls: some View {
        VStack(spacing: 14) {
            BoardSelectionPicker(settings: settings)

            Button(action: onStart) {
                Label {
                    Text("Start", bundle: .module)
                } icon: {
                    Image(systemName: "play.fill")
                }
                .font(.title3.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.accentColor, in: Capsule())
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)  // Return / Space-ish start
        }
    }

    /// Small round overlay button for a secondary action on the art corner.
    private func roundIcon(_ icon: String, label: LocalizedStringKey, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(.black.opacity(0.55), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label, bundle: .module))
    }

    private func hubButton(_ title: LocalizedStringKey, icon: String, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            Label {
                Text(title, bundle: .module)
            } icon: {
                Image(systemName: icon)
            }
            .font(.callout.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(.secondary.opacity(0.18), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
