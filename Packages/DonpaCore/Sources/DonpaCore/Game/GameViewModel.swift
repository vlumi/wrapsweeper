import Combine
import Foundation

/// What a plain tap/click on a *hidden* cell does. A revealed number always
/// chords and a long-press always does the opposite action, regardless of mode.
public enum InputMode: String, Codable, Sendable {
    case reveal
    case flag

    public mutating func toggle() { self = flipped }
    public var flipped: InputMode { self == .reveal ? .flag : .reveal }
}

/// The outcome of a finished game, for end-of-game feedback.
public enum GameResult: Equatable, Sendable {
    case won(centiseconds: Int, config: GameConfig)
    /// `at` is the detonated mine (for a focused loss animation).
    case lost(at: Coord?)

    public var isWin: Bool { if case .won = self { return true } else { return false } }
}

/// A result tagged with a monotonic id, so observers fire even on two identical
/// outcomes in a row.
public struct GameResultEvent: Equatable, Sendable {
    public let id: Int
    public let result: GameResult
}

/// Bridges the pure `Game` value type to SwiftUI/SpriteKit: owns the current
/// game/config/timer and republishes on board change so views + scene redraw.
@MainActor
public final class GameViewModel: ObservableObject {
    @Published public private(set) var game: Game
    @Published public private(set) var config: GameConfig
    /// Elapsed centiseconds, from the wall clock (not a tick count) so it's exact.
    @Published public private(set) var elapsedCentiseconds: Int = 0

    /// Bumped on every state change so the scene re-renders without diffing.
    @Published public private(set) var revision: Int = 0

    /// Bumped only on a fresh game, so the scene resets its camera then (not on
    /// every reveal).
    @Published public private(set) var gameID: Int = 0

    /// The win's final time + config, set at win, cleared on next new game.
    @Published public private(set) var lastWin: (config: GameConfig, centiseconds: Int)?

    /// Most recent outcome for end-of-game feedback; cleared on next new game.
    @Published public private(set) var lastResult: GameResultEvent?
    private var resultCounter = 0

    @Published public var inputMode: InputMode = .reveal

    private var timer: AnyCancellable?
    /// Segmented clock: `elapsed = accumulated + (now − runningSince)`. Pausing
    /// folds the live span into `accumulated` (a plain number, persists cleanly).
    private var accumulatedCentiseconds = 0
    private var runningSince: Date?

    /// Clock paused mid-game (game live, clock stopped) — drives the pause overlay.
    @Published public private(set) var isPaused = false

    /// True while a reveal/chord computes OFF the main thread (heavy flood-fill /
    /// placement on a huge board). Blocks board input so a tap can't land on a
    /// board that hasn't finished updating (could be a guaranteed mine).
    @Published public private(set) var isComputing = false

    /// Flag *placements* this game (each hidden→flagged action, so a re-flag counts
    /// again — the lifetime stat counts actions). Reset on new game / restore.
    public private(set) var flagsPlacedThisGame = 0

    /// Activity already flushed for THIS game, so a flush only sends the new delta.
    private var flushedTiles = 0
    private var flushedFlags = 0
    private var flushedCentiseconds = 0

    /// Pushes the unflushed activity DELTA (tiles/flags/time) to the lifetime
    /// totals — called on pause (also when the scoreboard opens), background, and
    /// game end/discard, so it accrues without a per-tile write storm and an
    /// abandoned game still counts. Set by the host (which owns the scoreboard);
    /// Core never references it.
    public var onActivityFlush:
        ((_ tilesDelta: Int, _ flagsDelta: Int, _ centisecondsDelta: Int) -> Void)?

    /// Flush this game's activity delta via `onActivityFlush`. Idempotent.
    public func flushActivity() {
        let tiles = game.revealedSafeCount
        let flags = flagsPlacedThisGame
        let centi = currentCentiseconds()
        let dt = tiles - flushedTiles
        let df = flags - flushedFlags
        let dc = centi - flushedCentiseconds
        guard dt != 0 || df != 0 || dc != 0 else { return }
        flushedTiles = tiles
        flushedFlags = flags
        flushedCentiseconds = centi
        onActivityFlush?(dt, df, dc)
    }

    /// Whether the board extends beyond the viewport; published by `BoardScene`
    /// each frame so the chrome can enable/disable the minimap toggle.
    @Published public var boardExceedsViewport = false

    /// Live camera view, kept current by `BoardScene` so `snapshot()` can persist
    /// it. Plain (not `@Published`) — written every frame, nothing observes it.
    public var cameraView: CameraView?

    /// One-shot camera view to restore on the next game, consumed by `BoardScene`.
    /// Separate from `cameraView` (which the scene overwrites each frame) so it
    /// survives until applied.
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

    /// Input accepted only when not paused and not mid-compute (the compute gate
    /// stops a tap landing on a board the in-flight reveal is about to change).
    private var canTakeInput: Bool { !isPaused && !isComputing }

    /// Whether revealing `c` would detonate a mine right now — the scene fires the
    /// explosion instantly on tap (before the off-thread reveal). False on the
    /// opening move, since mines exist only after the always-safe first click.
    public func canRevealHitMine(_ c: Coord) -> Bool {
        guard canTakeInput, game.status == .playing else { return false }
        return game.board[c].state == .hidden && game.board[c].isMine
    }

    /// In-flight compute, held so tests can await it. Not for production callers.
    private var pendingWork: Task<Void, Never>?

    /// Await the current reveal/chord compute (test-only).
    public func awaitPendingWork() async {
        await pendingWork?.value
    }

    /// Run a heavy board mutation off the main thread on a COW copy, apply it back
    /// on the main actor, then `afterApply` + redraw. `canTakeInput` gates to one
    /// compute at a time.
    private func computeOffMain(
        _ mutate: @Sendable @escaping (inout Game) -> Void,
        afterApply: @escaping () -> Void = {}
    ) {
        isComputing = true
        let snapshot = game  // O(1) COW; the task's mutation triggers the copy
        let generation = gameID
        pendingWork = Task {
            let updated = await Task.detached {
                var working = snapshot
                mutate(&working)
                return working
            }.value
            // A newGame/restore mid-compute bumps gameID; don't clobber its board.
            guard self.gameID == generation else { return }
            self.game = updated
            afterApply()
            self.isComputing = false
            self.bump()
        }
    }

    public func reveal(_ c: Coord) {
        guard canTakeInput, game.status == .notStarted || game.status == .playing else { return }
        let wasNotStarted = game.status == .notStarted
        computeOffMain({ game in game.reveal(c) }) { [weak self] in
            // The first reveal places mines and starts the clock.
            if wasNotStarted, self?.game.status == .playing { self?.startTimer() }
            self?.finishIfEnded()
        }
    }

    public func toggleFlag(_ c: Coord) {
        // O(1), so synchronous — but still gated mid-compute / paused / finished.
        guard canTakeInput, game.status == .notStarted || game.status == .playing else { return }
        let wasFlagged = game.board[c].state == .flagged
        game.toggleFlag(c)
        if !wasFlagged, game.board[c].state == .flagged { flagsPlacedThisGame += 1 }
        bump()
    }

    public func chord(_ c: Coord) {
        // Gated on .playing so a post-game chord can't re-publish the result (which
        // would replay the end-game panel on every click).
        guard canTakeInput, game.status == .playing else { return }
        computeOffMain({ game in game.chord(c) }) { [weak self] in
            self?.finishIfEnded()
        }
    }

    public func newGame(config: GameConfig? = nil) {
        // Flush the outgoing game's activity before discarding it, so abandoning a
        // dug-into game still counts. (A finished game already flushed at end.)
        if game.status == .playing { flushActivity() }
        if let config { self.config = config }
        game = Game(config: self.config)
        elapsedCentiseconds = 0
        lastWin = nil
        lastResult = nil
        inputMode = .reveal
        pendingCameraRestore = nil
        cameraView = nil
        isComputing = false  // gameID bumps below → any in-flight compute is dropped
        flagsPlacedThisGame = 0
        flushedTiles = 0
        flushedFlags = 0
        flushedCentiseconds = 0
        resetTimer()
        gameID &+= 1
        bump()
        armBoard()
    }

    /// Pre-place mines off the main thread right after a new game, so the heavy
    /// placement on a huge board happens while the player looks at the fresh board,
    /// not on their first tap (the first reveal then only relocates mines under the
    /// click). The empty board shows immediately, gated by `isComputing` while arming.
    private func armBoard() {
        computeOffMain({ game in
            var rng = SystemRandomNumberGenerator()
            game.placeMinesEagerly(using: &rng)
        })
    }

    /// A snapshot of the current game (live timer span folded in for an exact
    /// elapsed), or nil if there's nothing worth saving.
    public func snapshot() -> GameSnapshot? {
        GameSnapshot(
            game: game, config: config, elapsedCentiseconds: currentCentiseconds(),
            camera: cameraView, inputMode: inputMode)
    }

    /// Restore a persisted game and resume its clock from the saved elapsed.
    public func restore(from snapshot: GameSnapshot) {
        config = snapshot.config
        game = snapshot.makeGame()
        lastWin = nil
        lastResult = nil
        inputMode = snapshot.inputMode
        pendingCameraRestore = snapshot.camera
        cameraView = snapshot.camera
        timer?.cancel()
        accumulatedCentiseconds = snapshot.elapsedCentiseconds
        elapsedCentiseconds = snapshot.elapsedCentiseconds
        isPaused = false
        isComputing = false
        // Flag placements aren't persisted, so a resumed game only counts ones made
        // after resume (a minor under-count, not worth a snapshot field).
        flagsPlacedThisGame = 0
        // Seed flush trackers to the restored state: pre-save tiles/time were
        // already flushed, so only post-resume activity counts (no re-adding).
        flushedTiles = game.revealedSafeCount
        flushedFlags = 0
        flushedCentiseconds = snapshot.elapsedCentiseconds
        if game.status == .playing { startTimer() } else { runningSince = nil }
        gameID &+= 1
        bump()
    }

    /// Stop the clock, capture a win, and publish the outcome.
    private func finishIfEnded() {
        guard game.status == .won || game.status == .lost else { return }
        let finalCentiseconds = currentCentiseconds()
        timer?.cancel()
        timer = nil
        runningSince = nil
        accumulatedCentiseconds = finalCentiseconds
        elapsedCentiseconds = finalCentiseconds
        // Flush the final activity slice BEFORE the host records the outcome, so the
        // end record adds only games-played + win/loss + mines, not tiles/flags/time
        // again (those flow through flushes).
        flushActivity()
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

    /// Pause the clock mid-game (game stays playable-but-frozen). No-op unless live.
    public func pause() {
        guard game.status == .playing, !isPaused else { return }
        // Flush while the clock is still live, so the scoreboard (opened via a
        // pause) shows current tiles/flags/time.
        flushActivity()
        foldRunningSpan()
        timer?.cancel()
        timer = nil
        isPaused = true
    }

    public func resume() {
        guard isPaused else { return }
        isPaused = false
        startTimer()
    }

    private func startTimer() {
        runningSince = Date()
        // Tick ~10×/sec for tenths; the value is from the wall clock, so no drift.
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
