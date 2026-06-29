import DonpaCore
import SwiftUI

/// The full game surface: a status bar over a pannable/zoomable SpriteKit board.
/// A thin wrapper that owns the stores and hosts a single long-lived `BoardScene`
/// (which owns all board input natively). `.preferredColorScheme` is applied HERE
/// so the descendant `GameContent` can read the resolved scheme — a view can't
/// observe a scheme it forces on itself, so the read must be below the modifier.
public struct GameView: View {
    @StateObject private var viewModel: GameViewModel
    @StateObject private var scoreboard: Scoreboard
    @StateObject private var settings: Settings
    @ObservedObject private var navigator: Navigator
    @State private var scene: BoardScene
    /// Brief in-app splash mirroring the OS launch image (which can't be delayed,
    /// being pre-process) so the hand-off into the title is seamless.
    @State private var showSplash = true

    public init(config: GameConfig = .classic(.beginner)) {
        // Scoreboard iCloud sync is gated by `syncScores` (opt-in, OFF by default);
        // the cloud store also no-ops when signed out.
        let syncOn = UserDefaults.standard.object(forKey: "donpa.syncScores") as? Bool ?? false
        self.init(
            viewModel: GameViewModel(config: config),
            scoreboard: Scoreboard(cloud: UbiquitousStatsStore(), syncEnabled: syncOn),
            settings: Settings(),
            navigator: Navigator())
    }

    /// For a host (e.g. the macOS menu bar) that drives the same view model /
    /// navigation the board renders.
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
            // Title fade scoped to this overlay via `.animation(_:value:)` — an
            // imperative `withAnimation` would also animate the chrome's first
            // layout, making the status bar visibly settle.
            TitleScreen(
                settings: settings,
                // "Press start": GameContent decides resume vs. New Game (it owns
                // the save), so the tap just signals intent via a counter bump.
                onStart: { navigator.startRequested &+= 1 },
                onSettings: { navigator.showingSettings = true },
                onScores: { navigator.showingScores = true },
                onAbout: { navigator.showingAbout = true }
            )
            .opacity(navigator.showingTitle ? 1 : 0)
            .allowsHitTesting(navigator.showingTitle)
            .animation(.easeInOut(duration: 0.3), value: navigator.showingTitle)
            .zIndex(1)

            // New Game popup above both board and title (zIndex 2) so the
            // still-visible title can't occlude it. Tap-outside / X / Esc dismiss.
            if navigator.showingNewGame {
                NewGamePopup(
                    settings: settings,
                    onStart: { startSelectedGame() },
                    onClose: { navigator.showingNewGame = false }
                )
                .transition(.opacity)
                .zIndex(2)
            }

            // In-app splash on top (zIndex 3), fading out after a beat.
            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(3)
                    .task {
                        try? await Task.sleep(nanoseconds: 800_000_000)
                        withAnimation(.easeOut(duration: 0.4)) { showSplash = false }
                    }
            }
        }
        .preferredColorScheme(settings.appearance.colorScheme)
        .animation(.easeInOut(duration: 0.2), value: navigator.showingNewGame)
        // Keep the scoreboard's iCloud-sync gate in step with the Settings toggle.
        .onChangeCompat(of: settings.syncScores) { scoreboard.syncEnabled = $0 }
    }

    /// Start a fresh game with the popup's selection and leave the title — the
    /// single entry point for the New Game button, result screen, and title tap.
    private func startSelectedGame() {
        navigator.showingNewGame = false
        viewModel.newGame(config: settings.currentConfig)
        navigator.showingTitle = false
    }
}
