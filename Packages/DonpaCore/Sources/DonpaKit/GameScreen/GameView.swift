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
    /// Coalesces the per-move autosave: snapshotting a huge board scans every cell
    /// and JSON-encodes hundreds of thousands of coords, so doing it on *every*
    /// reveal stalls the main thread on big boards. Instead we save once activity
    /// settles; the periodic/pause/Home/quit saves are the durability backstops.
    @State private var autosaveTask: Task<Void, Never>?
    // Internal so the chrome extension (GameContentChrome) can read it.
    @State var restartPop = false
    /// Whether to actually SHOW the processing overlay — debounced off
    /// `viewModel.isComputing` so a fast compute never flashes it. (The input gate
    /// uses `isComputing` directly and flips instantly; only the *visual* waits.)
    /// Driven by `driveProcessingOverlay`. Internal: the chrome reads it.
    @State var showProcessing = false
    @State private var processingTask: Task<Void, Never>?
    @State private var processingShownAt: Date?
    @State private var windowSize: CGSize = .zero
    /// True when WE paused the game to show the scoreboard (so its career stats are
    /// current and the clock doesn't run behind the sheet) — used to auto-resume on
    /// dismiss, but only if the player hadn't already paused it themselves.
    @State private var pausedForScores = false
    /// Atomic, crash-safe store for the in-progress game (save/restore on quit).
    /// Under the UI-test launch arg it's a clean ephemeral store, so tests never
    /// read or write the real saved game; otherwise the production Application
    /// Support store.
    @State private var saveStore: SaveStore
    /// Writes the save off the main thread (encode + atomic write), so a save on a
    /// huge board never stalls input. The snapshot is still BUILT on the main actor
    /// (a consistent read of game state); only the expensive tail is handed here.
    @State private var saveWriter: BackgroundSaveWriter
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

    init(
        viewModel: GameViewModel, scoreboard: Scoreboard, settings: Settings,
        navigator: Navigator, scene: BoardScene
    ) {
        self.viewModel = viewModel
        self.scoreboard = scoreboard
        self.settings = settings
        self.navigator = navigator
        self.scene = scene
        // One store backs both the synchronous reads (load on launch) and the
        // background writer (encode + atomic write off the main thread).
        let store =
            SaveStore.isUITestCleanLaunch ? SaveStore.ephemeral() : SaveStore.appSupport()
        _saveStore = State(initialValue: store)
        _saveWriter = State(initialValue: BackgroundSaveWriter(store: store))
    }

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
        // A move schedules a debounced save (see `autosaveSoon`) rather than saving
        // synchronously — on a huge board a per-move snapshot stalls the main
        // thread. Durability is covered by the periodic/pause/Home/quit saves.
        .onChangeCompat(of: viewModel.revision) { _ in autosaveSoon() }
        // Leaving the foreground auto-pauses and saves; the atomic write means a
        // background-kill can't corrupt the save.
        .onChangeCompat(of: scenePhase) { phase in
            if phase != .active {
                viewModel.pause()
                autosaveBlocking()  // process may suspend/exit; write inline
            } else {
                // Coming back to the foreground: pull the latest scores from iCloud,
                // so a change on another device (incl. a removed device, which
                // lowers totals) lands even if the live notification was missed.
                scoreboard.refreshFromCloud()
            }
        }
        // Pausing flushes a save (it's a natural "I'm stepping away" moment, and
        // the manual pause button doesn't change game state, so `revision` won't
        // fire). Only on the transition into paused.
        .onChangeCompat(of: viewModel.isPaused) { paused in
            if paused { autosave() }
        }
        // Debounce the processing overlay so a fast compute never flashes it (the
        // input gate uses isComputing directly; only the visual is delayed).
        .onChangeCompat(of: viewModel.isComputing) { driveProcessingOverlay(computing: $0) }
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
            autosaveBlocking()  // process is exiting; the write must finish inline
        }
        #endif
        .sheet(isPresented: $navigator.showingScores) {
            ScoreboardView(scoreboard: scoreboard, settings: settings, available: windowSize)
        }
        // Opening the scoreboard pauses a live game: it flushes the career activity
        // (so the Career tab is current) and stops the clock running behind the
        // sheet. Auto-resume on dismiss — but only if we were the ones who paused,
        // so a game the player had already paused stays paused.
        .onChangeCompat(of: navigator.showingScores) { showing in
            if showing {
                if viewModel.game.status == .playing && !viewModel.isPaused {
                    pausedForScores = true
                    viewModel.pause()
                }
            } else if pausedForScores {
                pausedForScores = false
                viewModel.resume()
            }
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
        // Keyboard zoom (macOS ⌘+ / ⌘−): zoom about the board centre — no cursor.
        .onChangeCompat(of: navigator.zoomInRequested) { _ in scene.zoom(by: 1.25) }
        .onChangeCompat(of: navigator.zoomOutRequested) { _ in scene.zoom(by: 0.8) }
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
        // Live career activity: the view model flushes the tiles/flags/time delta
        // on pause (incl. opening the scoreboard), background, and game end. We
        // fold each delta into the lifetime totals WITHOUT counting a game played —
        // the games-played + win/loss + mine outcome is recorded separately at end.
        // Wired before any newGame below so the first flush is caught.
        viewModel.onActivityFlush = { tiles, flags, centiseconds in
            scoreboard.recordActivity(
                for: viewModel.config, tilesOpened: tiles, flagsPlaced: flags,
                playtimeCentiseconds: centiseconds)
        }
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
    /// The snapshot is BUILT here on the main actor (a consistent read of the game
    /// state), then the encode + atomic write is handed to `saveWriter` so the
    /// disk work never stalls input — even on a huge board. The actor serializes
    /// writes, so they land in order and a clear can't race a pending write.
    private func autosave() {
        autosaveTask?.cancel()  // an explicit save subsumes any pending debounce
        if let snapshot = viewModel.snapshot() {
            Task { await saveWriter.write(snapshot) }
        } else {
            Task { await saveWriter.clear() }
        }
    }

    /// Debounce the processing overlay so it never flashes. A fixed time threshold
    /// alone can't win — short flashes on fast hardware, long flashes worse on slow
    /// (the work finishes just past it). So: when compute starts, wait a grace
    /// period; only show the overlay if it's STILL computing after that. Once shown,
    /// keep it up for a minimum duration even if compute finishes sooner, so it's
    /// never a one-frame blip. Both together are hardware-independent.
    private func driveProcessingOverlay(computing: Bool) {
        let grace: TimeInterval = 0.12  // don't show for quick work
        let minVisible: TimeInterval = 0.3  // once shown, don't blip
        processingTask?.cancel()
        processingTask = Task {
            if computing {
                // Show only if STILL computing after the grace period.
                try? await Task.sleep(nanoseconds: UInt64(grace * 1e9))
                guard !Task.isCancelled, viewModel.isComputing, !showProcessing else { return }
                showProcessing = true
                processingShownAt = Date()
            } else if showProcessing {
                // Hide, but not before the minimum visible time has elapsed.
                let elapsed = processingShownAt.map { Date().timeIntervalSince($0) } ?? minVisible
                let remaining = minVisible - elapsed
                if remaining > 0 { try? await Task.sleep(nanoseconds: UInt64(remaining * 1e9)) }
                guard !Task.isCancelled else { return }
                showProcessing = false
            }
        }
    }

    /// A SYNCHRONOUS save for app-exit paths (backgrounding, macOS ⌘Q): the
    /// process may terminate the instant the handler returns, before a background
    /// task could run, so the write must finish inline here. Rare, so the
    /// main-thread cost is acceptable; the atomic write keeps it crash-safe.
    private func autosaveBlocking() {
        autosaveTask?.cancel()
        if let snapshot = viewModel.snapshot() {
            saveStore.save(snapshot)
        } else {
            saveStore.clear()
        }
    }

    /// Schedule a save shortly after the last move, coalescing a burst of reveals
    /// into one write. Snapshotting a huge board is expensive (it scans every cell
    /// and encodes the revealed/flagged sets), so saving on *every* reveal stalls
    /// the main thread on XXL/XXXL; debouncing keeps taps responsive while the
    /// periodic/pause/Home/quit saves remain the durability backstops. A finished
    /// game still resolves quickly — `autosave()` clears the save when not playing.
    private func autosaveSoon() {
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            autosave()
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
        let isWin = result.isWin
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
        // The finished game's OUTCOME: games-played + the mine tally. The activity
        // (tiles / flags / time) already accrued live via flushes — the view model
        // flushed the final slice in finishIfEnded before this runs. minesHit is the
        // single detonation on a loss; on a win all mines are accounted for, so
        // disarmedMineCount reads the full set (you solved it).
        scoreboard.recordGameOutcome(
            for: viewModel.config,
            minesHit: isWin ? 0 : 1,
            minesDisarmed: viewModel.game.board.disarmedMineCount)
        showPanel(kind)

        if !reduceMotion {
            restartPop = true
            withAnimation(.spring(response: 0.3, dampingFraction: 0.4)) { restartPop = false }
        }
    }

    /// Slam the result screen in after a short beat — so the board's detonation /
    /// win ripple plays first rather than being covered immediately. It then
    /// stays until the player picks Retry or Return to title. The beat is just
    /// animation timing (an async sleep), not a hang: the end-game effects are now
    /// viewport-culled, so they build instantly even on a huge board.
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
