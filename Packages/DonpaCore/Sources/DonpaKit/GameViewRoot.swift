import DonpaCore
import SwiftUI

/// The full game surface: a status bar over a pannable/zoomable SpriteKit board.
/// Hosts a single long-lived `BoardScene`, which owns all board input (tap,
/// flag, chord, pan, zoom) natively; this view only renders chrome.
///
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
    /// Brief in-app splash on first launch, mirroring the OS launch image so its
    /// hand-off into the title is seamless. (The OS launch screen itself can't be
    /// delayed — it's pre-process — so this app-controlled splash is what lingers.)
    @State private var showSplash = true

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
                // "Press start": tapping the art opens the New Game config popup
                // rather than starting immediately, so the title and the in-game
                // New Game button share one chooser.
                onStart: { navigator.showingNewGame = true },
                onSettings: { navigator.showingSettings = true },
                onScores: { navigator.showingScores = true }
            )
            .opacity(navigator.showingTitle ? 1 : 0)
            .allowsHitTesting(navigator.showingTitle)
            .animation(.easeInOut(duration: 0.3), value: navigator.showingTitle)
            .zIndex(1)

            // The New Game config popup sits ABOVE both the board and the title
            // (zIndex 2): it's opened from the in-game New Game button, the result
            // screen, and the title art — so it must never be occluded by the
            // still-visible title. Dimmed overlay with tap-outside / X / Esc to
            // dismiss, matching the result screen's pattern across platforms.
            if navigator.showingNewGame {
                NewGamePopup(
                    settings: settings,
                    onStart: { startSelectedGame() },
                    onClose: { navigator.showingNewGame = false }
                )
                .transition(.opacity)
                .zIndex(2)
            }

            // The in-app splash sits on top of everything (zIndex 3) and fades
            // out after a beat, revealing the title beneath.
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
    }

    /// Start a fresh game with the popup's current selection and leave the title.
    /// The single entry point used by the in-game New Game button, the result
    /// screen, and the title art tap.
    private func startSelectedGame() {
        navigator.showingNewGame = false
        viewModel.newGame(config: settings.currentConfig)
        navigator.showingTitle = false
    }
}
