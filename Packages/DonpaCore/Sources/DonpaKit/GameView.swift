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
    // Internal so the chrome extension (GameContentChrome) can read it.
    @State var restartPop = false
    @State private var windowSize: CGSize = .zero
    /// Atomic, crash-safe store for the in-progress game (save/restore on quit).
    @State private var saveStore = SaveStore.appSupport()
    /// A saved game found on launch, awaiting the user's Resume/Discard choice.
    @State private var pendingResume: GameSnapshot?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .sheet(isPresented: $navigator.showingScores) {
            ScoreboardView(scoreboard: scoreboard, available: windowSize)
        }
        .sheet(isPresented: $navigator.showingSettings) {
            SettingsView(settings: settings)
        }
        // Exactly two choices. One button must carry the `.cancel` role or the OS
        // synthesizes its own Cancel — so Discard *is* the cancel role (it's the
        // "back out" action, and also handles Esc / click-away).
        .alert(
            Text("Resume your game?", bundle: .module),
            isPresented: Binding(
                get: { pendingResume != nil }, set: { if !$0 { pendingResume = nil } })
        ) {
            Button {
                resumePending()
            } label: {
                Text("Resume", bundle: .module)
            }
            Button(role: .cancel) {
                discardPending()
            } label: {
                Text("Discard", bundle: .module)
            }
        }
    }

    // MARK: Save / restore lifecycle

    /// On launch: offer to resume a saved in-progress game; otherwise restore the
    /// persisted board selection as before.
    private func onLaunch() {
        if let snapshot = saveStore.load() {
            pendingResume = snapshot
        } else if viewModel.config != settings.currentConfig {
            viewModel.newGame(config: settings.currentConfig)
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

    private func resumePending() {
        guard let snapshot = pendingResume else { return }
        pendingResume = nil
        viewModel.restore(from: snapshot)
        navigator.showingTitle = false
    }

    private func discardPending() {
        pendingResume = nil
        saveStore.clear()
        viewModel.newGame(config: settings.currentConfig)
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

    /// Return to the home hub. Resets the board so picking/starting from the hub
    /// gives a fresh game rather than the just-played one. Internal — the chrome
    /// extension's Home button calls it.
    func goHome() {
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

}

// ScoreboardView and SettingsView (the sheets) live in SheetViews.swift.
