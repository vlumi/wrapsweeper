import DonpaCore
import SpriteKit
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// The game surface. Lives below `GameView`'s `.preferredColorScheme`, so its
/// `@Environment(\.colorScheme)` is the effective appearance the chrome and the
/// SKScene both use.
struct GameContent: View {
    @ObservedObject var viewModel: GameViewModel
    @ObservedObject var scoreboard: Scoreboard
    @ObservedObject var settings: Settings
    @ObservedObject var navigator: Navigator
    let scene: BoardScene

    @State private var panel: MangaPanelView.Kind?
    @State private var panelTask: Task<Void, Never>?
    /// Coalesces the per-move autosave: snapshotting a huge board is expensive, so
    /// saving on every reveal stalls the main thread. Save once activity settles;
    /// the periodic/pause/Home/quit saves are the durability backstops.
    @State private var autosaveTask: Task<Void, Never>?
    @State var restartPop = false
    /// Whether to SHOW the processing overlay — debounced off `viewModel.isComputing`
    /// so a fast compute never flashes it. (The input gate uses `isComputing`
    /// directly; only the visual waits.) Driven by `driveProcessingOverlay`.
    @State var showProcessing = false
    @State private var processingTask: Task<Void, Never>?
    @State private var processingShownAt: Date?
    @State private var windowSize: CGSize = .zero
    /// True when WE paused to show the scoreboard — used to auto-resume on dismiss,
    /// but only if the player hadn't already paused it themselves.
    @State private var pausedForScores = false
    /// Atomic, crash-safe store for the in-progress game. Ephemeral under the
    /// UI-test launch arg so tests never touch the real save.
    @State private var saveStore: SaveStore
    /// Writes the save off the main thread so it never stalls input. The snapshot is
    /// still BUILT on the main actor; only the encode + atomic write is handed here.
    @State private var saveWriter: BackgroundSaveWriter
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Periodic crash-protection save: pure pan/zoom doesn't bump `revision`, so an
    /// unflushed reframe could be lost to a crash. Flushes ~once a minute while live
    /// (deliberate exits save immediately; this is the safety net).
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
        // One store backs both the synchronous reads and the background writer.
        let store =
            SaveStore.isUITestCleanLaunch ? SaveStore.ephemeral() : SaveStore.appSupport()
        _saveStore = State(initialValue: store)
        _saveWriter = State(initialValue: BackgroundSaveWriter(store: store))
    }

    /// One resolved scheme for chrome and scene. `colorScheme` is the iOS fallback,
    /// but reading it also re-runs `body` when the OS appearance flips on System.
    private var scheme: ColorScheme {
        settings.appearance.resolvedScheme(systemFallback: colorScheme)
    }
    var palette: Palette { .resolved(for: scheme) }

    /// A live game (not yet won/lost) — the only time the board takes input.
    var gameInProgress: Bool {
        viewModel.status == .notStarted || viewModel.status == .playing
    }

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            boardArea
        }
        .background(palette.pageBackground)
        // Track the window size so sheets can size to it.
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
        // Debounced save (see `autosaveSoon`); a per-move snapshot would stall a
        // huge board. Durability covered by the periodic/pause/Home/quit saves.
        .onChangeCompat(of: viewModel.revision) { _ in autosaveSoon() }
        // Leaving the foreground auto-pauses and saves inline (the process may
        // suspend/exit before a background task could run).
        .onChangeCompat(of: scenePhase) { phase in
            if phase != .active {
                viewModel.pause()
                autosaveBlocking()
            } else {
                // Pull latest scores from iCloud, so a change on another device
                // lands even if the live notification was missed.
                scoreboard.refreshFromCloud()
            }
        }
        // Pause is a natural "stepping away" save (and doesn't bump `revision`).
        .onChangeCompat(of: viewModel.isPaused) { paused in
            if paused { autosave() }
        }
        .onChangeCompat(of: viewModel.isComputing) { driveProcessingOverlay(computing: $0) }
        .onReceive(autosaveHeartbeat) { _ in
            if scenePhase == .active { autosave() }
        }
        // ⌘Q doesn't reliably deliver a `scenePhase` change before exit, so the
        // background-save above can miss it; `willTerminate` fires synchronously in
        // time. (iOS uses the `scenePhase` background transition instead.)
        #if os(macOS)
        .onReceive(appWillTerminate) { _ in
            viewModel.pause()
            autosaveBlocking()  // exiting; the write must finish inline
        }
        #endif
        .sheet(isPresented: $navigator.showingScores) {
            // From the title (browsing) there's no current board → no "you are here"
            // marker. In-game, mark the row for the config being played.
            ScoreboardView(
                scoreboard: scoreboard, settings: settings, available: windowSize,
                currentConfigKey: navigator.showingTitle ? nil : viewModel.config.storageKey)
        }
        // Opening the scoreboard pauses a live game (flushing career activity and
        // stopping the clock); auto-resume on dismiss only if WE paused.
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
        .onChangeCompat(of: navigator.startRequested) { _ in handleStartRequest() }
        .onChangeCompat(of: navigator.homeRequested) { _ in goHome() }
        .onChangeCompat(of: navigator.zoomInRequested) { _ in scene.zoom(by: 1.25) }
        .onChangeCompat(of: navigator.zoomOutRequested) { _ in scene.zoom(by: 0.8) }
        .onChangeCompat(of: navigator.toggleMinimapRequested) { _ in scene.toggleMinimapSize() }
    }

    // MARK: Save / restore lifecycle

    /// On launch: resume a saved in-progress game straight into the board (skipping
    /// the title), else stay on the title with the board primed to the persisted
    /// config so an immediate New Game matches the last selection.
    private func onLaunch() {
        // Persist a minimap resize back to Settings (survives new game / restart /
        // save-restore). The scene drives the gesture; Settings is the store.
        scene.onMinimapScaleChange = { settings.minimapScale = Double($0) }
        // Fold each live activity-flush delta (tiles/flags/time) into the lifetime
        // totals WITHOUT counting a game played — the outcome is recorded at end.
        // Wired before any newGame below so the first flush is caught.
        viewModel.onActivityFlush = { tiles, flags, centiseconds in
            scoreboard.recordActivity(
                for: viewModel.config, tilesOpened: tiles, flagsPlaced: flags,
                playtimeCentiseconds: centiseconds)
        }
        if let scenario = PerfScenario.current {
            startPerfScenario(scenario)
        } else if let snapshot = saveStore.load() {
            viewModel.restore(from: snapshot)
            navigator.showingTitle = false
        } else if viewModel.config != settings.currentConfig {
            viewModel.newGame(config: settings.currentConfig)
        }
    }

    /// Jump straight into a profiling scenario (see `PerfScenario`): start the heavy
    /// board, fill the screen, and open a region — off the title — so the harness
    /// measures the same state the manual repro hit (render cost scales with the
    /// visible-node count, hence a maximized window).
    private func startPerfScenario(_ scenario: PerfScenario) {
        switch scenario {
        case .xxxlOpened:
            // Fixed seed → identical mine layout every run, so before/after profiles
            // compare like with like (the revealed region is then near-identical too).
            viewModel.newGame(config: .modern(.xxxl, .normal, .bounded, .square), seed: 0xDEAD_BEEF)
            navigator.showingTitle = false
            #if os(macOS)
            // Maximize so the viewport shows a full screen of cells (the heavy case).
            DispatchQueue.main.async {
                if let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }),
                    let screen = window.screen ?? NSScreen.main
                {
                    window.setFrame(screen.visibleFrame, display: true)
                }
            }
            #endif
            // Open a region once mines finish arming. `newGame` arms the board off
            // the main thread (`isComputing` true), and `reveal` is gated on
            // `canTakeInput` — so revealing immediately here would be DROPPED and
            // nothing would open. Await the arming, then reveal: the first click is
            // first-click-safe and floods a region (the heavy render + autosave-scan
            // state the perf work targets). Exact tiles vary by RNG; the load is
            // stable. A second reveal nearby widens the opened area.
            Task {
                await viewModel.awaitPendingWork()
                let w = viewModel.boardWidth, h = viewModel.boardHeight
                viewModel.reveal(Coord(w / 2, h / 2))
                await viewModel.awaitPendingWork()
                viewModel.reveal(Coord(w / 2 + 7, h / 2 + 7))
            }
        }
    }

    /// "Press start": resume a saved game if there is one, else open the New Game
    /// popup over the already-primed board. The single place the resume decision
    /// lives, since `saveStore` is owned here.
    private func handleStartRequest() {
        navigator.showingTitle = false
        if let snapshot = saveStore.load() {
            viewModel.restore(from: snapshot)
        } else {
            navigator.showingNewGame = true
        }
    }

    /// Persist the live game, or clear the save once it's no longer in progress.
    ///
    /// Building the snapshot scans the whole board to derive the revealed/flagged
    /// coord sets — heavy on a 1M-cell board, and it used to run on the main actor,
    /// stalling input (a beachball on a weak CPU mid-reveal). So capture the cheap
    /// Sendable inputs here, then build the snapshot AND encode/write off the main
    /// thread via `saveWriter`. Falls back to clearing the save once not in progress.
    private func autosave() {
        autosaveTask?.cancel()  // an explicit save subsumes any pending debounce
        if let inputs = viewModel.snapshotInputs() {
            Task.detached(priority: .utility) {
                guard let snapshot = GameSnapshot(inputs: inputs) else { return }
                await saveWriter.write(snapshot)
            }
        } else {
            Task { await saveWriter.clear() }
        }
    }

    /// Debounce the processing overlay so it never flashes: wait a grace period and
    /// show only if STILL computing; once shown, keep it up a minimum duration. Both
    /// together are hardware-independent (a fixed threshold alone can't win).
    private func driveProcessingOverlay(computing: Bool) {
        let grace: TimeInterval = 0.12  // don't show for quick work
        let minVisible: TimeInterval = 0.3  // once shown, don't blip
        processingTask?.cancel()
        processingTask = Task {
            if computing {
                try? await Task.sleep(nanoseconds: UInt64(grace * 1e9))
                guard !Task.isCancelled, viewModel.isComputing, !showProcessing else { return }
                showProcessing = true
                processingShownAt = Date()
            } else if showProcessing {
                let elapsed = processingShownAt.map { Date().timeIntervalSince($0) } ?? minVisible
                let remaining = minVisible - elapsed
                if remaining > 0 { try? await Task.sleep(nanoseconds: UInt64(remaining * 1e9)) }
                guard !Task.isCancelled else { return }
                showProcessing = false
            }
        }
    }

    /// A SYNCHRONOUS save for app-exit paths (backgrounding, ⌘Q): the process may
    /// terminate the instant the handler returns, so the write must finish inline.
    private func autosaveBlocking() {
        autosaveTask?.cancel()
        if let snapshot = viewModel.snapshot() {
            saveStore.save(snapshot)
        } else {
            saveStore.clear()
        }
    }

    /// Schedule a save shortly after the last move, coalescing a burst of reveals
    /// into one write (a per-move snapshot would stall a huge board). The
    /// periodic/pause/Home/quit saves remain the durability backstops.
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
    /// strip's actions stay live. Dims the board until dismissed (X / tap / Esc).
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

    /// Return home WITHOUT ending the game: pause and save, so "press start" can
    /// resume where it left off. Discarding is an explicit New Game instead.
    func goHome() {
        viewModel.pause()
        autosave()
        navigator.showingTitle = true
    }

    /// The single end-of-game hook: haptic, score submission, the manga result
    /// screen, and a restart-button pop.
    private func handleResult() {
        guard let result = viewModel.lastResult?.result else { return }
        fireHaptic(for: result)

        // Clear the prior record highlight; submit() below re-sets it if THIS game
        // was a record.
        scoreboard.clearRecentRecord()

        let kind: MangaPanelView.Kind
        let isWin = result.isWin
        switch result {
        case .won(let centiseconds, let config):
            // Capture the prior best BEFORE submit() overwrites it, so the panel can
            // show how much faster this clear was rather than the (already-on-timer)
            // final time. No prior best → a first-ever clear (improvedBy nil).
            let priorBest = scoreboard.best(for: config)
            let isRecord = scoreboard.submit(
                centiseconds, for: config,
                noFlag: !viewModel.usedFlagEver, noChord: !viewModel.usedChordEver)
            if isRecord {
                let improvedBy = priorBest.map { $0 - centiseconds }
                kind = .record(centiseconds: centiseconds, improvedBy: improvedBy)
            } else {
                kind = .win
            }
        case .lost:
            // Record cleared % as a consolation score; the "new best %" pill shows
            // only when this loss beat the prior best, and by how much.
            let progress = viewModel.game.progress
            // Prior best progress BEFORE submit overwrites it (nil = first run).
            let priorProgress = scoreboard.bestProgress(for: viewModel.config)
            let isBest = scoreboard.submitLossProgress(progress, for: viewModel.config)
            let safeRemaining = viewModel.game.safeCellCount - viewModel.game.revealedSafeCount
            let best: MangaPanelView.LossBest
            if !isBest {
                best = .notBest
            } else if let prior = priorProgress {
                best = .improved(by: max(0, progress - prior))
            } else {
                best = .first
            }
            kind = .loss(progress: progress, safeRemaining: safeRemaining, best: best)
        }
        // The finished game's OUTCOME: games-played + the mine tally (activity
        // already accrued live via flushes). minesHit = the single loss detonation;
        // on a win disarmedMineCount reads the full set.
        scoreboard.recordGameOutcome(
            for: viewModel.config,
            won: isWin,
            minesHit: isWin ? 0 : 1,
            minesDisarmed: viewModel.game.board.disarmedMineCount,
            chordsUsed: viewModel.chordsThisGame)
        showPanel(kind)

        if !reduceMotion {
            restartPop = true
            withAnimation(.spring(response: 0.3, dampingFraction: 0.4)) { restartPop = false }
        }
    }

    /// Slam the result screen in after a short beat so the board's detonation / win
    /// ripple plays first. The beat is animation timing, not a hang.
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

// ScoreboardView and SettingsView live in SheetViews.swift.
