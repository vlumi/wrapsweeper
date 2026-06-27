import DonpaCore
import SwiftUI

/// The home hub, shown on launch and when you leave a game. The manga splash *is*
/// the Start button (tapping opens the New Game popup); High Scores / Settings /
/// About sit as round buttons in the top-right corner. The art shows on a white
/// plate in both appearances — the screentone doesn't invert cleanly.
struct TitleScreen: View {
    @ObservedObject var settings: Settings
    let onStart: () -> Void
    let onSettings: () -> Void
    let onScores: () -> Void
    let onAbout: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Palette.resolved(for: colorScheme).pageBackground
                    .ignoresSafeArea()

                startArt
                    .frame(maxHeight: geo.size.height - 32)
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // Secondary actions in the screen's top-right corner.
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 8) {
                    roundButton(label: "High Scores", id: "title.highScores", action: onScores) {
                        MangaIcon(symbol: .medal, size: 34, tint: .white)
                    }
                    roundButton(label: "Settings", id: "title.settings", action: onSettings) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    roundButton(label: "About", id: "title.about", action: onAbout) {
                        Image(systemName: "info")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(16)
            }
        }
    }

    /// The manga splash, tappable as the primary "press start" action.
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
        .accessibilityIdentifier("title.start")
    }

    /// Small round overlay button for a secondary corner action.
    private func roundButton<Icon: View>(
        label: LocalizedStringKey, id: String, action: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        Button(action: action) {
            icon()
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.55), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label, bundle: .module))
        .accessibilityIdentifier(id)
    }
}
