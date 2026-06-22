import DonpaCore
import SpriteKit
import SwiftUI

#if os(iOS)
import UIKit
#endif

/// The actual game surface. Lives below `GameView`'s `.preferredColorScheme`, so
/// its `@Environment(\.colorScheme)` is the effective appearance for all of
/// system/light/dark — the single source the chrome and the SKScene both use.
struct GameContent: View {
    @ObservedObject var viewModel: GameViewModel
    @ObservedObject var scoreboard: Scoreboard
    @ObservedObject var settings: Settings
    @ObservedObject var navigator: Navigator
    let scene: BoardScene

    @State private var panel: MangaPanelView.Kind?
    @State private var panelTask: Task<Void, Never>?
    @State private var restartPop = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One resolved scheme for both the chrome and the scene. Driven by the
    /// user's setting; `.system` reads the real OS appearance (see
    /// `resolvedScheme`). `colorScheme` is only the iOS fallback, but reading it
    /// also re-runs `body` when the OS appearance flips while on System.
    private var scheme: ColorScheme {
        settings.appearance.resolvedScheme(systemFallback: colorScheme)
    }
    private var palette: Palette { .resolved(for: scheme) }

    /// A live game (not yet won/lost) — the only time the board takes input and
    /// so the only time the custom reveal/flag cursor makes sense.
    private var gameInProgress: Bool {
        viewModel.status == .notStarted || viewModel.status == .playing
    }

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            boardArea
        }
        .background(palette.pageBackground)
        .onAppear {
            // Restore the persisted board selection on launch.
            if viewModel.config != settings.currentConfig {
                viewModel.newGame(config: settings.currentConfig)
            }
        }
        // The single-arg `onChange` closure keeps iOS-16 support (the zero/two-arg
        // forms are iOS 17 / macOS 14 only); the deprecation note on newer OSes
        // is harmless.
        .onChange(of: viewModel.lastResult?.id) { _ in handleResult() }
        // Any new game (New Game / Retry / ⌘R) clears a lingering panel.
        .onChange(of: viewModel.gameID) { _ in dismissPanel() }
        .sheet(isPresented: $navigator.showingScores) {
            ScoreboardView(scoreboard: scoreboard)
        }
        .sheet(isPresented: $navigator.showingSettings) {
            SettingsView(settings: settings)
        }
    }

    // MARK: Result feedback (manga result screen + restart pop + haptics)

    /// The end-of-game result screen, overlaid on the BOARD only so the control
    /// strip's actions (New Game / Retry / Home) stay live — the panel itself
    /// carries no buttons. It dims the board and stays until dismissed (the X, a
    /// tap anywhere, or Esc) to inspect the finished board.
    @ViewBuilder private var mangaPanel: some View {
        if let panel {
            MangaPanelView(
                kind: panel,
                reduceMotion: reduceMotion,
                onContinue: { dismissPanel() }
            )
            .transition(.opacity)
        }
    }

    /// Return to the home hub. Resets the board so picking/starting from the hub
    /// gives a fresh game rather than the just-played one.
    private func goHome() {
        viewModel.newGame()
        navigator.showingTitle = true
    }

    /// On any finished game: record the time (wins), then haptic, the manga
    /// result screen, and a restart-button pop. This is the single end-of-game
    /// hook — it also submits the score, so a new best becomes a record panel
    /// rather than auto-opening the scoreboard over everything.
    private func handleResult() {
        guard let result = viewModel.lastResult?.result else { return }
        fireHaptic(for: result)

        let kind: MangaPanelView.Kind
        switch result {
        case .won(let centiseconds, let config):
            let isRecord = scoreboard.submit(centiseconds, for: config)
            kind = isRecord ? .record(centiseconds: centiseconds) : .win
        case .lost:
            // Record how much of the board was cleared as a consolation score;
            // a "new best %" pill shows only when this loss beat the prior best.
            let progress = viewModel.game.progress
            let isBest = scoreboard.submitLossProgress(progress, for: viewModel.config)
            kind = .loss(progress: progress, isBest: isBest)
        }
        showPanel(kind)

        if !reduceMotion {
            restartPop = true
            withAnimation(.spring(response: 0.3, dampingFraction: 0.4)) { restartPop = false }
        }
    }

    /// Slam the result screen in after a short beat — so the board's detonation /
    /// win ripple plays first rather than being covered immediately. It then
    /// stays until the player picks Retry or Return to title.
    private func showPanel(_ kind: MangaPanelView.Kind) {
        panelTask?.cancel()
        panelTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)  // let board FX land
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { panel = kind }
        }
    }

    private func dismissPanel() {
        panelTask?.cancel()
        withAnimation(.easeIn(duration: 0.25)) { panel = nil }
    }

    private func fireHaptic(for result: GameResult) {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(result.isWin ? .success : .error)
        #endif
    }

    // MARK: Board + control strip

    private var leftHanded: Bool { settings.handedness == .left }

    /// The board plus the control strip (centered actions + the flag toggle in
    /// the handed corner). The strip never overlaps the grid: it sits *below* the
    /// board when the board leaves vertical room, or *beside* it (on the handed
    /// side) when it leaves horizontal room. The board takes the remaining space
    /// and the SpriteKit scene fits/centres the grid, so it shrinks in tight
    /// cases rather than being covered. The strip stays visible after the game
    /// ends so New Game / Retry / Home remain reachable (the flag toggle hides,
    /// since a finished board takes no input).
    private var boardArea: some View {
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
    @ViewBuilder private var toggleIfLive: some View {
        if gameInProgress { modeToggle }
    }

    /// Bottom strip: actions centered, flag toggle pinned to the handed end so
    /// it's under the thumb. A ZStack so the centered actions stay truly centered
    /// regardless of the toggle's side.
    private var bottomControlStrip: some View {
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
    private var sideControlStrip: some View {
        ZStack {
            actionButtons(vertical: true)
            VStack {
                Spacer()
                toggleIfLive
            }
        }
        .padding(.vertical, 12)
    }

    private var board: some View {
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
        // Result screen dims the board ONLY, leaving the control strip live.
        .overlay { mangaPanel }
        .clipped()  // keep the dimmed backdrop within the board's bounds
    }

    // MARK: Status bar

    /// The thin top strip: read-only metrics grouped on the left (mines, the live
    /// clear %, the timer), with the trophy (High Scores) alone in the right
    /// corner. Kept just tall enough for the numbers; all actions live in the
    /// board-side strip.
    private var statusBar: some View {
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
    private func actionButtons(vertical: Bool) -> some View {
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
            actionButton("house.fill", help: "Home") { goHome() }
        }
    }

    private func actionButton(
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
    private var statusDescription: String {
        switch viewModel.status {
        case .won: return String(localized: "Won", bundle: .module)
        case .lost: return String(localized: "Lost", bundle: .module)
        case .playing: return String(localized: "In progress", bundle: .module)
        case .notStarted: return String(localized: "Ready", bundle: .module)
        }
    }

    /// VoiceOver summary of the board: config, size, mines remaining, and state.
    private var boardSummary: String {
        let label = viewModel.config.label
        let width = viewModel.boardWidth
        let height = viewModel.boardHeight
        let mines = viewModel.flagsRemaining
        let status = statusDescription
        return String(
            localized: "\(label), \(width) by \(height), \(mines) mines remaining, \(status)",
            bundle: .module)
    }

    private var newGameTint: Color {
        // Neutral while idle/playing; colour is reserved for the outcome so it
        // can't be mistaken for the (red) loss state.
        switch viewModel.status {
        case .won: return .green
        case .lost: return .red
        case .notStarted, .playing: return .secondary
        }
    }

    private func iconButton(
        _ systemName: String, help: LocalizedStringKey, action: @escaping () -> Void
    ) -> some View {
        let label = Text(help, bundle: .module)
        return Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)  // the symbol alone says nothing to VoiceOver
    }

    /// Toggle between reveal- and flag-mode for plain taps. The icon shows the
    /// CURRENT mode (what a tap will do), tinted when in flag mode so it's
    /// obvious you've armed flagging.
    private var modeToggle: some View {
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

// ScoreboardView and SettingsView (the sheets) live in SheetViews.swift.
