import DonpaCore
import SwiftUI

/// The in-game top status strip: config badge + read-only metric readouts + the
/// High Scores medal.
extension GameContent {
    // MARK: Status bar

    /// The thin top strip: config label, read-only metrics (mines, clear %, timer),
    /// and the High Scores medal in the right corner. The left cluster is uniformly
    /// scaled by `FitToWidth` so it shrinks as one on a narrow phone.
    var statusBar: some View {
        // The medal is pinned right OUTSIDE FitToWidth so the expanding Spacer isn't
        // measured — a Spacer inside collapses when measured but expands when
        // rendered, so the row would clip instead of shrinking as one.
        HStack(spacing: 16) {
            FitToWidth {
                HStack(spacing: 16) {
                    // Tappable badge for the current game; opens the New Game popup.
                    configButton
                    CounterReadout.mines(viewModel.flagsRemaining, tint: palette.counter)
                    ProgressReadout(progress: viewModel.game.progress, tint: palette.counter)
                    CounterReadout.time(
                        centiseconds: viewModel.elapsedCentiseconds, tint: palette.counter)
                }
                .lineLimit(1)
            }
            Spacer(minLength: 12)
            mangaIconButton(.medal, size: 40, help: "High Scores") {
                navigator.showingScores = true
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(palette.statusBar)
    }

    /// The current-game badge, tappable to open the New Game popup. Pulses with
    /// `restartPop` on a fresh game.
    private var configButton: some View {
        Button(action: { navigator.showingNewGame = true }) {
            HStack(spacing: 6) {
                // Modern config: rank insignia then size name (matching the
                // scoreboard / picker); classic shows its plain preset name.
                if let size = viewModel.config.modernSize,
                    let density = viewModel.config.modernDensity
                {
                    DensityInsignia.image(density)
                        .resizable().scaledToFit().frame(height: 24)
                    Text(verbatim: size.label).font(.subheadline.weight(.bold))
                } else {
                    Text(viewModel.config.label).font(.subheadline.weight(.bold))
                }
                // Swap arrows read as "switch game", not a dropdown or "add".
                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption.weight(.bold))
                    .opacity(0.85)
            }
            .foregroundStyle(.white)
            .fixedSize()  // resist shrinking when the bar is tight
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(palette.counter))
            .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .layoutPriority(1)  // the status bar yields the metrics before the pill
        .scaleEffect(restartPop ? 1.15 : 1.0)
        .help(Text("Change game", bundle: .module))
        .accessibilityLabel(Text("Change game", bundle: .module))
        .accessibilityValue(Text(viewModel.config.label))
        .accessibilityIdentifier("game.config")
    }
}
