import Combine
import Foundation

/// What a plain tap/click on a *hidden* cell does. A revealed number always
/// chords and a long-press always does the opposite primary action, regardless
/// of mode — so the mode only decides reveal-vs-flag for a hidden-cell tap.
public enum InputMode: Sendable {
    case reveal
    case flag

    public mutating func toggle() { self = flipped }

    /// The other mode — used for the temporary Control-held "other action".
    public var flipped: InputMode { self == .reveal ? .flag : .reveal }
}

/// The outcome of a finished game, used to drive end-of-game feedback.
public enum GameResult: Equatable, Sendable {
    case won(centiseconds: Int, config: GameConfig)
    /// Lost — `at` is the mine that detonated (for a focused loss animation).
    case lost(at: Coord?)

    public var isWin: Bool { if case .won = self { return true } else { return false } }
}

/// A game result tagged with a monotonic id, so observers fire on every
/// outcome — even two identical results in a row.
public struct GameResultEvent: Equatable, Sendable {
    public let id: Int
    public let result: GameResult
}

/// Bridges the pure `Game` value type to SwiftUI/SpriteKit: owns the current
/// game, the selected difficulty, the timer, and the mine counter, and
/// republishes whenever the board changes so views and the scene can redraw.
@MainActor
public final class GameViewModel: ObservableObject {
    @Published public private(set) var game: Game
    @Published public private(set) var config: GameConfig
    /// Elapsed play time in centiseconds (hundredths). Driven by the wall clock
    /// (not a tick count) so it's accurate and uncapped; the UI rounds to 0.1s.
    @Published public private(set) var elapsedCentiseconds: Int = 0

    /// Bumped on every state-changing action so the SpriteKit scene knows to
    /// re-render without diffing the whole board.
    @Published public private(set) var revision: Int = 0

    /// Bumped only when a fresh game starts, so the scene can reset its camera
    /// (re-fit and re-center) without doing so on every reveal.
    @Published public private(set) var gameID: Int = 0

    /// Set once at the moment a game is won, carrying the final time
    /// (centiseconds) and the config it was won on. Cleared on the next new game.
    @Published public private(set) var lastWin: (config: GameConfig, centiseconds: Int)?

    /// The most recent game outcome, for end-of-game feedback (animation,
    /// banner, haptics). The `id` makes each result distinct so observers fire
    /// even on identical consecutive outcomes; cleared on the next new game.
    @Published public private(set) var lastResult: GameResultEvent?
    private var resultCounter = 0

    /// What a plain tap on a hidden cell does. Toggled from the toolbar so the
    /// player can place flags without risking an accidental reveal.
    @Published public var inputMode: InputMode = .reveal

    private var timer: AnyCancellable?
    /// Segmented clock: time banked from previous running spans, plus the start
    /// of the current span when running. `elapsed = accumulated + (now - runningSince)`.
    /// Pausing folds the live span into `accumulated`; this persists cleanly (a
    /// plain number, never a wall-clock delta) and supports pause/resume.
    private var accumulatedCentiseconds = 0
    private var runningSince: Date?

    /// Whether the clock is paused mid-game (running game, clock stopped). Drives
    /// the pause overlay; distinct from `.notStarted`/finished states.
    @Published public private(set) var isPaused = false

    /// Whether the board currently extends beyond the viewport (so there's
    /// off-screen board a minimap could map). Published by `BoardScene` each frame
    /// as the camera pans/zooms; the chrome uses it to enable/disable the minimap
    /// toggle (nothing to show when the whole board fits).
    @Published public var boardExceedsViewport = false

    /// The live camera view (centre + zoom), kept current by `BoardScene` as the
    /// player pans/zooms, so `snapshot()` can persist where they were looking.
    /// Plain (not `@Published`) — it's written every frame and nothing observes it.
    public var cameraView: CameraView?

    /// A one-shot camera view to restore, set by `restore(from:)` from the saved
    /// snapshot and consumed by `BoardScene` when it handles the new game (it reads
    /// then clears it, so the next new/normal game falls back to the default fit).
    /// Distinct from `cameraView` — which the scene overwrites every frame — so the
    /// pending value survives until the scene applies it.
    public var pendingCameraRestore: CameraView?

    public init(config: GameConfig = .classic(.beginner)) {
        self.config = config
        self.game = Game(config: config)
    }

    public var status: GameStatus { game.status }
    public var flagsRemaining: Int { game.flagsRemaining }
    public var boardWidth: Int { config.width }
    public var boardHeight: Int { config.height }

    // MARK: Actions

    public func reveal(_ c: Coord) {
        guard !isPaused, game.status == .notStarted || game.status == .playing else { return }
        let wasNotStarted = game.status == .notStarted
        game.reveal(c)
        if wasNotStarted, game.status == .playing { startTimer() }
        finishIfEnded()
        bump()
    }

    public func toggleFlag(_ c: Coord) {
        guard !isPaused, game.status == .notStarted || game.status == .playing else { return }
        game.toggleFlag(c)
        bump()
    }

    public func chord(_ c: Coord) {
        // Once the game is over (or paused), input is inert — chording a revealed
        // cell must not re-publish the result (which would replay the end-game
        // animation and panel on every post-loss click).
        guard !isPaused, game.status == .playing else { return }
        game.chord(c)
        finishIfEnded()
        bump()
    }

    public func newGame(config: GameConfig? = nil) {
        if let config { self.config = config }
        game = Game(config: self.config)
        elapsedCentiseconds = 0
        lastWin = nil
        lastResult = nil
        inputMode = .reveal  // every game starts in reveal mode
        // A brand-new game centres on its own default fit, not a resumed view.
        pendingCameraRestore = nil
        cameraView = nil
        resetTimer()
        gameID &+= 1
        bump()
    }

    /// A `GameSnapshot` of the current game, or nil if it's not a live game worth
    /// saving. The live timer span is folded in so the saved elapsed is exact.
    public func snapshot() -> GameSnapshot? {
        GameSnapshot(
            game: game, config: config, elapsedCentiseconds: currentCentiseconds(),
            camera: cameraView)
    }

    /// Restore a persisted game: rebuild the board/state, set the clock to the
    /// saved elapsed (and resume running it), and bump so views/scene redraw.
    public func restore(from snapshot: GameSnapshot) {
        config = snapshot.config
        game = snapshot.makeGame()
        lastWin = nil
        lastResult = nil
        inputMode = .reveal
        // Hand the saved view to the scene to apply on the upcoming rebuild; a
        // game with no saved camera (older save / board fits) falls back to the
        // default fit. cameraView is overwritten by the scene each frame, so the
        // pending value lives separately until consumed.
        pendingCameraRestore = snapshot.camera
        cameraView = snapshot.camera
        // Restore the banked time and resume the clock from there.
        timer?.cancel()
        accumulatedCentiseconds = snapshot.elapsedCentiseconds
        elapsedCentiseconds = snapshot.elapsedCentiseconds
        isPaused = false
        if game.status == .playing { startTimer() } else { runningSince = nil }
        gameID &+= 1
        bump()
    }

    /// Stop the clock when the game ends, capture a win for scoring, and publish
    /// the outcome for end-of-game feedback.
    private func finishIfEnded() {
        guard game.status == .won || game.status == .lost else { return }
        // Capture the precise final time from the wall clock before stopping.
        let finalCentiseconds = currentCentiseconds()
        timer?.cancel()
        timer = nil
        runningSince = nil
        accumulatedCentiseconds = finalCentiseconds
        elapsedCentiseconds = finalCentiseconds
        let result: GameResult
        if game.status == .won {
            lastWin = (config: config, centiseconds: finalCentiseconds)
            result = .won(centiseconds: finalCentiseconds, config: config)
        } else {
            result = .lost(at: game.lossCoord)
        }
        resultCounter += 1
        lastResult = GameResultEvent(id: resultCounter, result: result)
    }

    // MARK: Timer

    /// Pause the clock mid-game: bank the live span and stop ticking, leaving the
    /// game playable-but-frozen. No-op unless a game is actually in progress.
    public func pause() {
        guard game.status == .playing, !isPaused else { return }
        foldRunningSpan()
        timer?.cancel()
        timer = nil
        isPaused = true
    }

    /// Resume a paused clock: start a fresh running span and tick again.
    public func resume() {
        guard isPaused else { return }
        isPaused = false
        startTimer()
    }

    private func startTimer() {
        runningSince = Date()
        // Refresh ~10×/sec for a smooth tenths display; the value itself is
        // computed from the wall clock, so it never drifts.
        timer = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.elapsedCentiseconds = self.currentCentiseconds()
            }
    }

    /// `accumulated` + the live span (if running).
    private func currentCentiseconds() -> Int {
        guard let runningSince else { return accumulatedCentiseconds }
        let span = max(0, Int((Date().timeIntervalSince(runningSince) * 100).rounded()))
        return accumulatedCentiseconds + span
    }

    /// Move the live running span into `accumulated` and clear it.
    private func foldRunningSpan() {
        accumulatedCentiseconds = currentCentiseconds()
        runningSince = nil
        elapsedCentiseconds = accumulatedCentiseconds
    }

    private func resetTimer() {
        timer?.cancel()
        timer = nil
        accumulatedCentiseconds = 0
        runningSince = nil
        isPaused = false
        elapsedCentiseconds = 0
    }

    private func bump() { revision &+= 1 }
}
