import DonpaCore
import SwiftUI

/// The in-game chrome for `GameContent`: the thin top metrics strip, the board +
/// its control strip (actions + flag toggle), and the pause overlay. Split out of
/// GameView.swift to keep that file within length limits.
extension GameContent {
    // MARK: Board + control strip

    var leftHanded: Bool { settings.handedness == .left }

    /// The board plus the control strip (centered actions + the flag toggle in
    /// the handed corner). The strip never overlaps the grid: it sits *below* the
    /// board when the board leaves vertical room, or *beside* it (on the handed
    /// side) when it leaves horizontal room. The board takes the remaining space
    /// and the SpriteKit scene fits/centres the grid, so it shrinks in tight
    /// cases rather than being covered. The strip stays visible after the game
    /// ends so New Game / Retry / Home remain reachable (the flag toggle hides,
    /// since a finished board takes no input).
    var boardArea: some View {
        GeometryReader { geo in
            // Put the strip wherever the *board* leaves the most room: compare the
            // window's aspect to the board's. Proportionally wider than the board
            // → spare width → side strip; else spare height → bottom strip. (A wide
            // board like Expert in a wide window still gets a bottom strip.)
            let windowAspect = geo.size.width / max(geo.size.height, 1)
            let boardAspect = CGFloat(viewModel.boardWidth) / CGFloat(max(viewModel.boardHeight, 1))
            let sideStrip = windowAspect > boardAspect

            if sideStrip {
                HStack(spacing: 0) {
                    if leftHanded { sideControlStrip.frame(width: 96) }
                    board
                    if !leftHanded { sideControlStrip.frame(width: 96) }
                }
            } else {
                VStack(spacing: 0) {
                    board
                    bottomControlStrip.frame(height: 84)
                }
            }
        }
    }

    /// The flag toggle, shown only during a live game (a finished board is inert).
    @ViewBuilder var toggleIfLive: some View {
        if gameInProgress { modeToggle }
    }

    /// Bottom strip: actions centered, flag toggle pinned to the handed end so
    /// it's under the thumb. A ZStack so the centered actions stay truly centered
    /// regardless of the toggle's side.
    var bottomControlStrip: some View {
        ZStack {
            actionButtons(vertical: false)
            HStack {
                if leftHanded { toggleIfLive; Spacer() } else { Spacer(); toggleIfLive }
            }
        }
        .padding(.horizontal, 12)
    }

    /// Side strip (on the handed side): actions centered in the column, the flag
    /// toggle pinned to the bottom for thumb reach.
    var sideControlStrip: some View {
        ZStack {
            actionButtons(vertical: true)
            VStack {
                Spacer()
                toggleIfLive
            }
        }
        .padding(.vertical, 12)
    }

    var board: some View {
        // Palette passed as a value: BoardView's updateUIView/NSView pushes it to
        // the scene whenever the resolved scheme changes — reliable where
        // .onChange on the SwiftUI side was not.
        BoardView(
            scene: scene, palette: palette, inputMode: viewModel.inputMode,
            // Custom reveal/flag cursor only during a live game; otherwise the
            // normal arrow (title screen, result panel, or a finished board
            // you're just inspecting — where a flag cursor is stale).
            boardCursorActive: gameInProgress && !navigator.showingTitle
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Per-cell VoiceOver is a future task (needs a scalable cursor model for
        // huge boards); for now announce a useful summary.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Board", bundle: .module))
        .accessibilityValue(boardSummary)
        .accessibilityIdentifier("game.board")
        // Result screen dims the board ONLY, leaving the control strip live.
        .overlay { mangaPanel }
        .overlay { pauseOverlay }
        .animation(.easeInOut(duration: 0.2), value: viewModel.isPaused)
        .clipped()  // keep the dimmed backdrop within the board's bounds
    }

    /// Covers the board while paused so it can't be studied; tap (or the strip's
    /// resume) continues the game. Blurs rather than blacks out so it reads as
    /// "paused", not "blank".
    @ViewBuilder var pauseOverlay: some View {
        if viewModel.isPaused {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(palette.pageBackground.opacity(0.5))
                VStack(spacing: 14) {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.secondary)
                    Text("Paused", bundle: .module).font(.title2.bold())
                    Text("Tap to resume", bundle: .module)
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { viewModel.resume() }
            .transition(.opacity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Paused", bundle: .module))
            .accessibilityHint(Text("Tap to resume", bundle: .module))
            .accessibilityIdentifier("game.paused")
        }
    }

    // MARK: Status bar

    /// The thin top strip: read-only metrics grouped on the left (mines, the live
    /// clear %, the timer), with the trophy (High Scores) alone in the right
    /// corner. Kept just tall enough for the numbers; all actions live in the
    /// board-side strip.
    var statusBar: some View {
        HStack(spacing: 14) {
            CounterReadout.mines(viewModel.flagsRemaining, tint: palette.counter)
            // `game.progress` re-renders on every reveal via the @Published revision.
            ProgressReadout(progress: viewModel.game.progress, tint: palette.counter)
            CounterReadout.time(
                centiseconds: viewModel.elapsedCentiseconds, tint: palette.counter)
            Spacer(minLength: 8)
            // High Scores sits apart on the right — same read-only character. (On
            // the title screen it stays on the art; this is its in-game home.)
            iconButton("trophy", help: "High Scores") { navigator.showingScores = true }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(palette.statusBar)
    }

    /// The centered in-game actions: start a different game (opens the config
    /// popup), retry the same board, and go home. These are the prominent
    /// controls; they share the board-side strip with the flag toggle. Laid out
    /// along the strip's long axis — a row in the bottom strip, a column in the
    /// narrow side strip.
    @ViewBuilder
    func actionButtons(vertical: Bool) -> some View {
        let layout =
            vertical
            ? AnyLayout(VStackLayout(spacing: 18)) : AnyLayout(HStackLayout(spacing: 18))
        layout {
            actionButton("plus.circle.fill", help: "New game") {
                navigator.showingNewGame = true
            }
            .scaleEffect(restartPop ? 1.25 : 1.0)
            actionButton("arrow.clockwise.circle.fill", help: "Retry", tint: newGameTint) {
                viewModel.newGame()
            }
            // Pause only makes sense during a live game.
            if viewModel.status == .playing {
                actionButton("pause.circle.fill", help: "Pause") { viewModel.pause() }
                    .accessibilityIdentifier("game.pause")
            }
            actionButton("house.fill", help: "Home") { goHome() }
                .accessibilityIdentifier("game.home")
        }
    }

    func actionButton(
        _ systemName: String, help: LocalizedStringKey, tint: Color = .secondary,
        action: @escaping () -> Void
    ) -> some View {
        let label = Text(help, bundle: .module)
        return Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 30))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    /// Spoken game state, used as the new-game button's accessibility value and
    /// the board's status summary.
    var statusDescription: String {
        switch viewModel.status {
        case .won: return String(localized: "Won", bundle: .module)
        case .lost: return String(localized: "Lost", bundle: .module)
        case .playing: return String(localized: "In progress", bundle: .module)
        case .notStarted: return String(localized: "Ready", bundle: .module)
        }
    }

    /// VoiceOver summary of the board: config, size, mines remaining, and state.
    var boardSummary: String {
        let label = viewModel.config.label
        let width = viewModel.boardWidth
        let height = viewModel.boardHeight
        let mines = viewModel.flagsRemaining
        let status = statusDescription
        return String(
            localized: "\(label), \(width) by \(height), \(mines) mines remaining, \(status)",
            bundle: .module)
    }

    var newGameTint: Color {
        // Neutral while idle/playing; colour is reserved for the outcome so it
        // can't be mistaken for the (red) loss state.
        switch viewModel.status {
        case .won: return .green
        case .lost: return .red
        case .notStarted, .playing: return .secondary
        }
    }

    func iconButton(
        _ systemName: String, help: LocalizedStringKey, action: @escaping () -> Void
    ) -> some View {
        let label = Text(help, bundle: .module)
        return Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)  // Apple's min touch target
                .contentShape(Rectangle())  // whole frame tappable, not just the glyph
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)  // the symbol alone says nothing to VoiceOver
    }

    /// Toggle between reveal- and flag-mode for plain taps. The icon shows the
    /// CURRENT mode (what a tap will do), tinted when in flag mode so it's
    /// obvious you've armed flagging.
    var modeToggle: some View {
        let flagging = viewModel.inputMode == .flag
        return Button(action: { viewModel.inputMode.toggle() }) {
            Image(systemName: flagging ? "flag.fill" : "hand.tap.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(flagging ? .white : .primary)
                .frame(width: 60, height: 60)
                .background(
                    Circle().fill(flagging ? Color.orange : palette.statusBar)
                )
                .overlay(Circle().stroke(.primary.opacity(0.15), lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.space, modifiers: [])
        .help(
            viewModel.inputMode == .flag
                ? Text("Flag mode — tap flags (Space)", bundle: .module)
                : Text("Reveal mode — tap reveals (Space)", bundle: .module)
        )
        .accessibilityLabel(Text("Input mode", bundle: .module))
        .accessibilityValue(
            viewModel.inputMode == .flag
                ? Text("Flag", bundle: .module)
                : Text("Reveal", bundle: .module)
        )
        .accessibilityHint(Text("Toggles between revealing and flagging", bundle: .module))
    }
}
