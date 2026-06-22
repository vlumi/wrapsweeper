import DonpaCore
import SpriteKit
import SwiftUI

#if os(iOS)
import UIKit
#endif

/// The full game surface: a status bar over a pannable/zoomable SpriteKit board.
/// Hosts a single long-lived `BoardScene`, which owns all board input (tap,
/// flag, chord, pan, zoom) natively; this view only renders chrome.
/// Thin wrapper that owns the stores and applies the user's appearance choice.
/// `.preferredColorScheme` is applied HERE so the descendant `GameContent` reads
/// the resolved scheme via `@Environment(\.colorScheme)` — a view cannot observe
/// a scheme it forces on itself, so the read must happen below the modifier.
public struct GameView: View {
    @StateObject private var viewModel: GameViewModel
    @StateObject private var scoreboard: Scoreboard
    @StateObject private var settings: Settings
    @ObservedObject private var navigator: Navigator
    @State private var scene: BoardScene

    public init(config: GameConfig = .classic(.beginner)) {
        self.init(
            viewModel: GameViewModel(config: config),
            scoreboard: Scoreboard(),
            settings: Settings(),
            navigator: Navigator())
    }

    /// Use this when the host (e.g. the macOS menu bar) needs to drive the same
    /// view model / navigation that the board renders.
    public init(
        viewModel: GameViewModel, scoreboard: Scoreboard, settings: Settings,
        navigator: Navigator
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _scoreboard = StateObject(wrappedValue: scoreboard)
        _settings = StateObject(wrappedValue: settings)
        _navigator = ObservedObject(wrappedValue: navigator)
        _scene = State(initialValue: BoardScene(viewModel: viewModel))
    }

    public var body: some View {
        ZStack {
            GameContent(
                viewModel: viewModel, scoreboard: scoreboard, settings: settings,
                navigator: navigator, scene: scene)
            // The title fades out over the (always-mounted) board. The fade is
            // scoped to this overlay alone via `.animation(_:value:)` — an
            // imperative `withAnimation` here would also animate the chrome's
            // first layout underneath, making the status bar visibly settle.
            TitleScreen(
                settings: settings,
                onStart: {
                    // Start a fresh game with the hub's current selection.
                    viewModel.newGame(config: settings.currentConfig)
                    navigator.showingTitle = false
                },
                onSettings: { navigator.showingSettings = true },
                onScores: { navigator.showingScores = true }
            )
            .opacity(navigator.showingTitle ? 1 : 0)
            .allowsHitTesting(navigator.showingTitle)
            .animation(.easeInOut(duration: 0.3), value: navigator.showingTitle)
            .zIndex(1)
        }
        .preferredColorScheme(settings.appearance.colorScheme)
    }
}

/// The actual game surface. Lives below `GameView`'s `.preferredColorScheme`, so
/// its `@Environment(\.colorScheme)` is the effective appearance for all of
/// system/light/dark — the single source the chrome and the SKScene both use.
private struct GameContent: View {
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
        .overlay { mangaPanel }
        .onAppear {
            // Restore the persisted board selection on launch.
            if viewModel.config != settings.currentConfig {
                viewModel.newGame(config: settings.currentConfig)
            }
        }
        .onChange(of: viewModel.lastResult?.id) { _ in handleResult() }
        // A new game (incl. Space-to-restart) clears any lingering panel.
        .onChange(of: viewModel.gameID) { _ in dismissPanel() }
        .sheet(isPresented: $navigator.showingScores) {
            ScoreboardView(scoreboard: scoreboard)
        }
        .sheet(isPresented: $navigator.showingSettings) {
            SettingsView(settings: settings)
        }
    }

    // MARK: Result feedback (manga result screen + restart pop + haptics)

    /// The end-of-game result screen. It blocks the board and stays until the
    /// player chooses: Continue (also a tap anywhere) dismisses to inspect the
    /// board; Return to title (also Esc) goes home. Restart is Space / Cmd-R.
    @ViewBuilder private var mangaPanel: some View {
        if let panel {
            MangaPanelView(
                kind: panel,
                reduceMotion: reduceMotion,
                onContinue: { dismissPanel() },
                onRestart: { restartFromPanel() },
                onReturnToTitle: { returnToTitleFromPanel() }
            )
            .transition(.opacity)
        }
    }

    private func restartFromPanel() {
        dismissPanel()
        viewModel.newGame()
    }

    private func returnToTitleFromPanel() {
        dismissPanel()
        goHome()
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

    // MARK: Board + mode toggle

    /// Where the toggle sits within its strip: hugging the handed bottom corner
    /// (thumb-reachable). In a bottom strip this picks the left/right end; in a
    /// side strip it sits at the bottom of that side.
    private var toggleAlignment: Alignment {
        settings.handedness == .right ? .bottomTrailing : .bottomLeading
    }

    /// The board plus the floating reveal/flag toggle, arranged so the toggle
    /// never overlaps the grid: a strip *below* the board when the space is tall,
    /// *beside* it when wide. The board takes the remaining room and the
    /// SpriteKit scene fits/centres the grid within it, so it simply shrinks in
    /// tight cases rather than being covered or clipped.
    private var boardArea: some View {
        GeometryReader { geo in
            // Put the strip wherever the *board* leaves the most room: compare
            // the window's aspect to the board's. If the window is proportionally
            // wider than the board, there's spare width → strip on the side; else
            // spare height → strip at the bottom. (A wide board like Expert in a
            // wide window still gets the strip at the bottom.)
            let windowAspect = geo.size.width / max(geo.size.height, 1)
            let boardAspect = CGFloat(viewModel.boardWidth) / CGFloat(max(viewModel.boardHeight, 1))
            let sideStrip = windowAspect > boardAspect
            let strip: CGFloat = gameInProgress ? 84 : 0

            if sideStrip {
                HStack(spacing: 0) {
                    board
                    if gameInProgress {
                        modeToggle.padding(12).frame(width: strip, alignment: toggleAlignment)
                    }
                }
            } else {
                VStack(spacing: 0) {
                    board
                    if gameInProgress {
                        modeToggle.padding(12).frame(height: strip, alignment: toggleAlignment)
                    }
                }
            }
        }
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
    }

    // MARK: Status bar

    private var statusBar: some View {
        // Three equal-width zones keep the new-game button truly centred without
        // overlapping the side controls. Counters get layout priority so they
        // shrink (never vanish) when the window gets very narrow; the icon
        // buttons hold a fixed size.
        HStack(spacing: 6) {
            HStack(spacing: 8) {
                counter(label: "⚑", value: viewModel.flagsRemaining)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)

            newGameButton

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                // Settings/Scores live on the home hub now; Home returns there.
                iconButton("house", help: "Home") { goHome() }
                timeCounter(label: "⏱", centiseconds: viewModel.elapsedCentiseconds)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(palette.statusBar)
    }

    /// New game. A restart symbol tinted by game state (neutral / won / lost),
    /// so it stays expressive without the emoji face crowding the other icons.
    private var newGameButton: some View {
        Button(action: { viewModel.newGame() }) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(newGameTint)
                .scaleEffect(restartPop ? 1.35 : 1.0)  // one-shot pop on game end
        }
        .buttonStyle(.plain)
        .help(Text("New game", bundle: .module))
        .accessibilityLabel(Text("New game", bundle: .module))
        // Convey, in words, what the icon's colour shows.
        .accessibilityValue(statusDescription)
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

    /// Flag/mine count: a fixed 3-digit readout (e.g. `010`).
    private func counter(label: String, value: Int) -> some View {
        counterLabel(label, String(format: "%03d", max(0, value)), a11y: "Mines remaining")
    }

    /// Live toolbar timer: the classic 3-digit whole-second LED (e.g. `047`),
    /// kept compact and capped at 999 like the original. The stored time keeps
    /// counting past that; precise tenths (`m:ss.t`) appear in results, not here.
    private func timeCounter(label: String, centiseconds: Int) -> some View {
        let seconds = min(999, max(0, centiseconds / 100))
        return counterLabel(label, String(format: "%03d", seconds), a11y: "Time, seconds")
    }

    private func counterLabel(_ label: String, _ value: String, a11y: LocalizedStringKey)
        -> some View
    {
        HStack(spacing: 3) {
            Text(verbatim: label)  // glyph (⚑ / ⏱)
            Text(verbatim: value)
                .font(.system(.title3, design: .monospaced).weight(.bold))
                .foregroundStyle(palette.counter)
        }
        // Shrink to fit very narrow windows rather than clipping or pushing the
        // timer out of the bar entirely.
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .layoutPriority(1)
        // The glyph (⚑ / ⏱) is meaningless to VoiceOver; speak a real label.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(a11y, bundle: .module))
        .accessibilityValue(Text(verbatim: value))
    }

}

// ScoreboardView and SettingsView (the sheets) live in SheetViews.swift.
