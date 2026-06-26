import DonpaCore
import SpriteKit
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
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
    // Internal so the chrome extension (GameContentChrome) can read it.
    @State var restartPop = false
    @State private var windowSize: CGSize = .zero
    /// Atomic, crash-safe store for the in-progress game (save/restore on quit).
    /// Under the UI-test launch arg it's a clean ephemeral store, so tests never
    /// read or write the real saved game; otherwise the production Application
    /// Support store.
    @State private var saveStore =
        SaveStore.isUITestCleanLaunch ? SaveStore.ephemeral() : SaveStore.appSupport()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Heartbeat for the periodic autosave (crash protection): a save can't be
    /// counted on between board moves — pure pan/zoom doesn't bump `revision` —
    /// so an unflushed reframe (or a long think) would be lost to a crash. This
    /// flushes roughly once a minute while a game is live. (Deliberate exits —
    /// background, Home, pause — save immediately; this is the safety net.)
    private let autosaveHeartbeat =
        Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    #if os(macOS)
    /// Fires just before the app quits — the macOS save-on-exit hook (see body).
    private var appWillTerminate: NotificationCenter.Publisher {
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
    }
    #endif

    /// One resolved scheme for both the chrome and the scene. Driven by the
    /// user's setting; `.system` reads the real OS appearance (see
    /// `resolvedScheme`). `colorScheme` is only the iOS fallback, but reading it
    /// also re-runs `body` when the OS appearance flips while on System.
    private var scheme: ColorScheme {
        settings.appearance.resolvedScheme(systemFallback: colorScheme)
    }
    var palette: Palette { .resolved(for: scheme) }

    /// A live game (not yet won/lost) — the only time the board takes input and
    /// so the only time the custom reveal/flag cursor makes sense. Internal so the
    /// chrome extension (GameContentChrome) can read it.
    var gameInProgress: Bool {
        viewModel.status == .notStarted || viewModel.status == .playing
    }

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            boardArea
        }
        .background(palette.pageBackground)
        // Track the window size so presented sheets can size to it.
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { windowSize = geo.size }
                    .onChangeCompat(of: geo.size) { windowSize = $0 }
            }
        )
        .onAppear { onLaunch() }
        .onChangeCompat(of: viewModel.lastResult?.id) { _ in handleResult() }
        // Any new game (New Game / Retry / ⌘R) clears a lingering panel.
        .onChangeCompat(of: viewModel.gameID) { _ in dismissPanel() }
        // Autosave on every state change while playing (crash protection); clear
        // the save once the game is no longer in progress.
        .onChangeCompat(of: viewModel.revision) { _ in autosave() }
        // Leaving the foreground auto-pauses and saves; the atomic write means a
        // background-kill can't corrupt the save.
        .onChangeCompat(of: scenePhase) { phase in
            if phase != .active {
                viewModel.pause()
                autosave()
            }
        }
        // Pausing flushes a save (it's a natural "I'm stepping away" moment, and
        // the manual pause button doesn't change game state, so `revision` won't
        // fire). Only on the transition into paused.
        .onChangeCompat(of: viewModel.isPaused) { paused in
            if paused { autosave() }
        }
        // Periodic crash-protection save while the app is active — bounds how much
        // a crash can lose (esp. pan/zoom, which doesn't bump `revision`).
        .onReceive(autosaveHeartbeat) { _ in
            if scenePhase == .active { autosave() }
        }
        // macOS quit (⌘Q) doesn't reliably deliver a `scenePhase` change before the
        // process exits, so the background-save above can miss it. `willTerminate`
        // fires synchronously just before exit; the atomic write completes in time.
        // (iOS gets this via the `scenePhase` background transition instead.)
        #if os(macOS)
        .onReceive(appWillTerminate) { _ in
            viewModel.pause()
            autosave()
        }
        #endif
        .sheet(isPresented: $navigator.showingScores) {
            ScoreboardView(scoreboard: scoreboard, available: windowSize)
        }
        .sheet(isPresented: $navigator.showingSettings) {
            SettingsView(settings: settings)
        }
        .sheet(isPresented: $navigator.showingAbout) {
            AboutView()
        }
        // Title art tapped: resume the saved game, or open the New Game popup.
        .onChangeCompat(of: navigator.startRequested) { _ in handleStartRequest() }
        // Home requested (in-game button / macOS ⌘T): pause + save, then title.
        .onChangeCompat(of: navigator.homeRequested) { _ in goHome() }
    }

    // MARK: Save / restore lifecycle

    /// On launch: if there's a saved in-progress game, resume straight into it
    /// and skip the title (returning players want to keep playing — the title hub
    /// and its High Scores/Settings/About are a tap away via Home). With no saved
    /// game, stay on the title and prime the board with the persisted config so an
    /// immediate New Game matches their last selection.
    private func onLaunch() {
        // Tapping the minimap's expand badge opens the fullscreen overview.
        scene.onOpenOverview = { navigator.showingOverview = true }
        if let snapshot = saveStore.load() {
            viewModel.restore(from: snapshot)
            navigator.showingTitle = false
        } else if viewModel.config != settings.currentConfig {
            viewModel.newGame(config: settings.currentConfig)
        }
    }

    /// Title art tapped ("press start"): leave the title for the game screen. If a
    /// saved game exists, resume it directly; otherwise reveal the (last-config,
    /// not-started) board and open the New Game popup over it — so dismissing the
    /// popup leaves a ready-to-play board rather than a dead screen. This is the
    /// single place the resume decision lives, since `saveStore` is owned here.
    private func handleStartRequest() {
        navigator.showingTitle = false
        if let snapshot = saveStore.load() {
            viewModel.restore(from: snapshot)
        } else {
            // The board is already primed with the last-used config (onLaunch /
            // the previous newGame); just offer the chooser over it.
            navigator.showingNewGame = true
        }
    }

    /// Persist the live game, or clear the save once it's no longer in progress.
    private func autosave() {
        if let snapshot = viewModel.snapshot() {
            saveStore.save(snapshot)
        } else {
            saveStore.clear()
        }
    }

    // MARK: Result feedback (manga result screen + restart pop + haptics)

    /// The end-of-game result screen, overlaid on the BOARD only so the control
    /// strip's actions (New Game / Retry / Home) stay live — the panel itself
    /// carries no buttons. It dims the board and stays until dismissed (the X, a
    /// tap anywhere, or Esc) to inspect the finished board.
    @ViewBuilder var mangaPanel: some View {
        if let panel {
            MangaPanelView(
                kind: panel,
                reduceMotion: reduceMotion,
                onContinue: { dismissPanel() }
            )
            .transition(.opacity)
        }
    }

    /// Return to the home hub WITHOUT ending the game: pause it and save, so the
    /// title art's "press start" can resume right where it left off. (Previously
    /// this reset the board, which silently discarded an in-progress game — the
    /// exact footgun this avoids.) Discarding is now an explicit New Game instead.
    /// Internal — the chrome extension's Home button calls it.
    func goHome() {
        viewModel.pause()
        autosave()
        navigator.showingTitle = true
    }

    /// On any finished game: record the time (wins), then haptic, the manga
    /// result screen, and a restart-button pop. This is the single end-of-game
    /// hook — it also submits the score, so a new best becomes a record panel
    /// rather than auto-opening the scoreboard over everything.
    private func handleResult() {
        guard let result = viewModel.lastResult?.result else { return }
        fireHaptic(for: result)

        // A finished game clears the previous record highlight; submit() below
        // re-sets it if *this* game was itself a record.
        scoreboard.clearRecentRecord()

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
            let safeRemaining = viewModel.game.safeCellCount - viewModel.game.revealedSafeCount
            kind = .loss(progress: progress, safeRemaining: safeRemaining, isBest: isBest)
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

}

// ScoreboardView and SettingsView (the sheets) live in SheetViews.swift.
