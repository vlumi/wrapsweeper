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
            TitleScreen { navigator.showingTitle = false }
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

    @State private var showingScores = false
    @State private var showingSettings = false
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
            // Palette passed as a value: BoardView's updateUIView/NSView pushes
            // it to the scene whenever the resolved scheme changes — reliable
            // where .onChange on the SwiftUI side was not.
            BoardView(
                scene: scene, palette: palette, inputMode: viewModel.inputMode,
                // Custom reveal/flag cursor only during a live game; otherwise
                // the normal arrow (title screen, result panel, or a finished
                // board you're just inspecting — where a flag cursor is stale).
                boardCursorActive: gameInProgress && !navigator.showingTitle
            )
            // Per-cell VoiceOver is a future task (needs a scalable cursor
            // model for huge boards); for now announce a useful summary.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Board")
            .accessibilityValue(
                "\(viewModel.config.label), "
                    + "\(viewModel.boardWidth) by \(viewModel.boardHeight), "
                    + "\(viewModel.flagsRemaining) mines remaining, \(statusDescription)")
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
        .sheet(isPresented: $showingScores) {
            ScoreboardView(scoreboard: scoreboard)
        }
        .sheet(isPresented: $showingSettings) {
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
                onReturnToTitle: { returnToTitleFromPanel() }
            )
            .transition(.opacity)
        }
    }

    private func returnToTitleFromPanel() {
        dismissPanel()
        // Reset the board so starting again from the title gives a fresh game,
        // not the just-finished one.
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
            kind = .loss
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

    // MARK: Status bar

    private var statusBar: some View {
        // Three equal-width zones keep the new-game button truly centred without
        // overlapping the side controls. Counters get layout priority so they
        // shrink (never vanish) when the window gets very narrow; the icon
        // buttons hold a fixed size.
        HStack(spacing: 6) {
            HStack(spacing: 8) {
                counter(label: "⚑", value: viewModel.flagsRemaining)
                modeToggle
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)

            newGameButton

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                iconButton("trophy", help: "High scores") { showingScores = true }
                iconButton("gearshape", help: "Settings") { showingSettings = true }
                timeCounter(label: "⏱", centiseconds: viewModel.elapsedCentiseconds)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .safeAreaInset(edge: .bottom, spacing: 0) { difficultyPicker }
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
        .help("New game")
        .accessibilityLabel("New game")
        // Convey, in words, what the icon's colour shows.
        .accessibilityValue(statusDescription)
    }

    /// Spoken game state, used as the new-game button's accessibility value and
    /// the board's status summary.
    private var statusDescription: String {
        switch viewModel.status {
        case .won: return "Won"
        case .lost: return "Lost"
        case .playing: return "In progress"
        case .notStarted: return "Ready"
        }
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

    private func iconButton(_ systemName: String, help: String, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)  // the symbol alone says nothing to VoiceOver
    }

    /// Toggle between reveal- and flag-mode for plain taps. The icon shows the
    /// CURRENT mode (what a tap will do), tinted when in flag mode so it's
    /// obvious you've armed flagging.
    private var modeToggle: some View {
        Button(action: { viewModel.inputMode.toggle() }) {
            Image(systemName: viewModel.inputMode == .flag ? "flag.fill" : "hand.tap.fill")
                .font(.system(size: 18))
                .foregroundStyle(viewModel.inputMode == .flag ? Color.orange : .secondary)
                .frame(width: 40, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            viewModel.inputMode == .flag
                                ? palette.modeFlagTint : palette.modeRevealTint)
                )
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.space, modifiers: [])
        .help(
            viewModel.inputMode == .flag
                ? "Flag mode — tap flags (Space)"
                : "Reveal mode — tap reveals (Space)"
        )
        .accessibilityLabel("Input mode")
        .accessibilityValue(viewModel.inputMode == .flag ? "Flag" : "Reveal")
        .accessibilityHint("Toggles between revealing and flagging")
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

    private func counterLabel(_ label: String, _ value: String, a11y: String) -> some View {
        HStack(spacing: 3) {
            Text(label)
            Text(value)
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
        .accessibilityLabel(a11y)
        .accessibilityValue(value)
    }

    /// The bottom configuration bar: a Classic/Modern mode switch over the
    /// matching board picker (3 classic presets, or Size × Density for Modern).
    /// Changing any control starts a new game with the implied config.
    private var difficultyPicker: some View {
        VStack(spacing: 8) {
            Picker("Mode", selection: modeBinding) {
                ForEach(GameMode.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            switch settings.mode {
            case .classic:
                Picker("Difficulty", selection: classicBinding) {
                    ForEach(ClassicPreset.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            case .modern:
                Picker("Size", selection: sizeBinding) {
                    ForEach(BoardSize.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                Picker("Difficulty", selection: densityBinding) {
                    ForEach(Density.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // Each binding writes the Settings selection, then starts a new game on the
    // resulting config so the board reflects the choice immediately.
    private var modeBinding: Binding<GameMode> {
        Binding(
            get: { settings.mode },
            set: {
                settings.mode = $0
                viewModel.newGame(config: settings.currentConfig)
            })
    }
    private var classicBinding: Binding<ClassicPreset> {
        Binding(
            get: { settings.classicPreset },
            set: {
                settings.classicPreset = $0
                viewModel.newGame(config: settings.currentConfig)
            })
    }
    private var sizeBinding: Binding<BoardSize> {
        Binding(
            get: { settings.modernSize },
            set: {
                settings.modernSize = $0
                viewModel.newGame(config: settings.currentConfig)
            })
    }
    private var densityBinding: Binding<Density> {
        Binding(
            get: { settings.modernDensity },
            set: {
                settings.modernDensity = $0
                viewModel.newGame(config: settings.currentConfig)
            })
    }
}

// ScoreboardView and SettingsView (the sheets) live in SheetViews.swift.
