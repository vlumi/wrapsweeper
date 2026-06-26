import DonpaCore
import SwiftUI

/// The in-game top status strip (config badge + read-only metric readouts + the
/// High Scores medal). Split out of GameContentChrome.swift to keep that file
/// within length limits.
extension GameContent {
    // MARK: Status bar

    /// The thin top strip: the current config label, then read-only metrics
    /// (mines, the live clear %, the timer), with the trophy (High Scores) alone
    /// in the right corner. Kept just tall enough for the numbers; all actions
    /// live in the board-side strip.
    ///
    /// The whole row is laid out at its natural size and then uniformly scaled to
    /// fit the width via `FitToWidth` — so on a narrow phone everything (label,
    /// the three metrics, the medal) shrinks *together* by one factor, staying
    /// proportional and the same relative size, instead of each child self-scaling
    /// to a different size, jittering, or truncating.
    var statusBar: some View {
        // The medal is pinned to the right OUTSIDE FitToWidth; FitToWidth scales
        // only the left cluster (config badge + the three readouts). Keeping the
        // expanding Spacer out of the measured content is what makes scaling work:
        // a Spacer inside FitToWidth collapses to its minLength when measured but
        // expands when rendered, so the measured natural width never matched the
        // laid-out width and the row clipped instead of shrinking as one.
        HStack(spacing: 16) {
            FitToWidth {
                HStack(spacing: 16) {
                    // Which game you're playing (e.g. "Expert" or "Medium · Sapper"),
                    // as a tappable badge that opens the New Game popup — tapping the
                    // current game to change it (replaces a separate New Game button).
                    configButton
                    CounterReadout.mines(viewModel.flagsRemaining, tint: palette.counter)
                    // `game.progress` re-renders on every reveal via @Published revision.
                    ProgressReadout(progress: viewModel.game.progress, tint: palette.counter)
                    CounterReadout.time(
                        centiseconds: viewModel.elapsedCentiseconds, tint: palette.counter)
                }
                .lineLimit(1)
            }
            Spacer(minLength: 12)
            // High Scores sits apart on the right — same read-only character.
            // (On the title screen it stays on the art; this is its in-game home.)
            mangaIconButton(.medal, size: 40, help: "High Scores") {
                navigator.showingScores = true
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(palette.statusBar)
    }

    /// The current-game badge, tappable to open the New Game popup (the in-game
    /// counterpart to tapping the title splash). A trailing chevron hints it's a
    /// menu; the badge pulses with `restartPop` on a fresh game like the old New
    /// Game button did.
    private var configButton: some View {
        Button(action: { navigator.showingNewGame = true }) {
            HStack(spacing: 6) {
                // Modern config: difficulty rank insignia then size name (same
                // order as the scoreboard and the New Game picker). Classic shows
                // its plain preset name.
                if let size = viewModel.config.modernSize,
                    let density = viewModel.config.modernDensity
                {
                    DensityInsignia.image(density)
                        .resizable().scaledToFit().frame(height: 24)
                    Text(verbatim: size.label).font(.subheadline.weight(.bold))
                } else {
                    Text(viewModel.config.label).font(.subheadline.weight(.bold))
                }
                // Swap arrows read as "switch to a different game" — not a
                // dropdown (chevron) and not "add" (plus).
                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption.weight(.bold))
                    .opacity(0.85)
            }
            .foregroundStyle(.white)
            .fixedSize()  // resist shrinking when the status bar is tight
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
