import DonpaCore
import SwiftUI

/// The home hub, shown on launch and whenever you leave a game. The manga
/// "ドンパ隊 / DONPA SQUAD" splash *is* the Start button — tapping it opens the
/// New Game config popup (the single place you choose a game). High Scores and
/// Settings stay as round buttons on the art's top-right corner; a "Tap to
/// start" hint makes the primary action obvious.
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
            ZStack {
                Palette.resolved(for: colorScheme).pageBackground
                    .ignoresSafeArea()

                // The art is the whole hub now — no separate picker column — so it
                // simply grows to fill, centered, never wasting horizontal space.
                startArt
                    .frame(maxHeight: geo.size.height - 32)
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // Secondary actions in the SCREEN's top-right corner (over the page,
            // which may or may not overlap the art depending on its size).
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 8) {
                    roundIcon("trophy.fill", label: "High Scores", action: onScores)
                    roundIcon("gearshape.fill", label: "Settings", action: onSettings)
                }
                .padding(16)
            }
        }
    }

    /// The manga splash, tappable as the primary "press start" action (the whole
    /// image is the button — no extra hint needed; it opens the New Game popup).
    private var startArt: some View {
        Button(action: onStart) {
            Image("TitleScreen", bundle: .module)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .shadow(color: .black.opacity(0.35), radius: 16, y: 5)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
        .accessibilityLabel(Text("Start", bundle: .module))
    }

    /// Small round overlay button for a secondary action in the corner.
    private func roundIcon(_ icon: String, label: LocalizedStringKey, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.55), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label, bundle: .module))
    }
}
