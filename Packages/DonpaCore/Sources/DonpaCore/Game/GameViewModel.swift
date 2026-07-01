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

/// The live game clock, split out as its own observable so the ~10×/sec timer tick
/// only re-renders the timer readout — NOT the whole `GameContent` body. (Reading
/// the tick straight off `GameViewModel` made every view observing the VM re-render
/// 10×/sec — wasteful, and a battery drain on iOS in particular.)
@MainActor
public final class GameClock: ObservableObject {
    /// Elapsed centiseconds, from the wall clock (not a tick count) so it's exact.
    @Published public fileprivate(set) var elapsedCentiseconds: Int = 0
}

/// Bridges the pure `Game` value type to SwiftUI/SpriteKit: owns the current
/// game/config/timer and republishes on board change so views + scene redraw.
@MainActor
public final class GameViewModel: ObservableObject {
    @Published public private(set) var game: Game
    @Published public private(set) var config: GameConfig
    /// The live clock, observed on its own by the timer readout (see `GameClock`).
    public let clock = GameClock()
    /// Elapsed centiseconds — the live display value lives on `clock`; this mirrors
    /// it for snapshot/restore/tests without making the VM re-publish on every tick.
    public var elapsedCentiseconds: Int { clock.elapsedCentiseconds }

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

    /// Chord actions this game (a mastery signal; folded into the game-end stats).
    /// Reset on new game / restore.
    public private(set) var chordsThisGame = 0

    /// Sticky "purity" bits for no-flag / no-chord feats: latch true the moment the
    /// feat is broken and never reset within a game. On RESTORE they default to
    /// "violated" (true) — a resumed game can't earn these (board state can't prove a
    /// clean run), erring toward denial over a false award. See the achievements plan.
    public private(set) var usedFlagEver = false
    public private(set) var usedChordEver = false

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

    /// The `gameID` the most recently started compute belongs to. Lets a stale
    /// task tell whether a newer compute is arming the current generation (so it
    /// leaves the gate alone) or not (so it must release `isComputing` itself).
    private var computeGeneration = -1

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
        let tokenBefore = game.changeToken
        let generation = gameID
        computeGeneration = generation
        pendingWork = Task {
            let updated = await Task.detached {
                var working = snapshot
                mutate(&working)
                return working
            }.value
            let outcome = Self.computeOutcome(
                finished: generation, current: self.gameID,
                latestStarted: self.computeGeneration)
            if outcome.applyResult {
                self.game = updated
                // Skip the redraw/autosave/minimap-rebuild if nothing actually changed
                // — e.g. chording a number whose flag count doesn't match does no work,
                // and on a huge board a stream of such no-op taps would otherwise each
                // queue a full-board snapshot + minimap raster and back up the app.
                if updated.changeToken != tokenBefore {
                    afterApply()
                    self.bump()
                }
            }
            if outcome.releaseGate { self.isComputing = false }
        }
    }

    /// What a finishing off-main compute should do, decided purely so it's testable
    /// (the async closure just applies the result, with no branching of its own).
    /// - `finished`: the gameID the finishing task belongs to.
    /// - `current`: the live gameID now.
    /// - `latestStarted`: the gameID of the most recently *started* compute.
    ///
    /// `applyResult` — only the live task (`finished == current`) writes its board +
    /// runs afterApply; a stale task (a newGame/restore bumped gameID past it) must
    /// not clobber the newer game.
    /// `releaseGate` — release `isComputing` for the live task, OR for a stale task
    /// when no newer compute is arming the current generation (`latestStarted !=
    /// current`); otherwise that newer compute owns the release. So the gate can
    /// never wedge shut regardless of which entry point bumped gameID.
    static func computeOutcome(finished: Int, current: Int, latestStarted: Int)
        -> (applyResult: Bool, releaseGate: Bool)
    {
        let live = finished == current
        return (applyResult: live, releaseGate: live || latestStarted != current)
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
        if !wasFlagged, game.board[c].state == .flagged {
            flagsPlacedThisGame += 1
            usedFlagEver = true  // latches; a placed-then-removed flag still counts
        }
        bump()
    }

    public func chord(_ c: Coord) {
        // Gated on .playing so a post-game chord can't re-publish the result (which
        // would replay the end-game panel on every click).
        guard canTakeInput, game.status == .playing else { return }
        chordsThisGame += 1
        usedChordEver = true
        computeOffMain({ game in game.chord(c) }) { [weak self] in
            self?.finishIfEnded()
        }
    }

    public func newGame(config: GameConfig? = nil, seed: UInt64? = nil) {
        // Flush the outgoing game's activity before discarding it, so abandoning a
        // dug-into game still counts. (A finished game already flushed at end.)
        if game.status == .playing { flushActivity() }
        if let config { self.config = config }
        game = Game(config: self.config)
        clock.elapsedCentiseconds = 0
        lastWin = nil
        lastResult = nil
        inputMode = .reveal
        pendingCameraRestore = nil
        cameraView = nil
        isComputing = false  // gameID bumps below → any in-flight compute is dropped
        flagsPlacedThisGame = 0
        chordsThisGame = 0
        usedFlagEver = false
        usedChordEver = false
        flushedTiles = 0
        flushedFlags = 0
        flushedCentiseconds = 0
        resetTimer()
        gameID &+= 1
        bump()
        armBoard(seed: seed)
    }

    /// Pre-place mines off the main thread right after a new game, so the heavy
    /// placement on a huge board happens while the player looks at the fresh board,
    /// not on their first tap (the first reveal then only relocates mines under the
    /// click). The empty board shows immediately, gated by `isComputing` while arming.
    /// `seed` (perf harness only) makes mine placement deterministic so a profiled
    /// board is identical run to run; nil uses the system generator (normal play).
    private func armBoard(seed: UInt64? = nil) {
        computeOffMain({ game in
            if let seed {
                var rng = SeededGenerator(seed: seed)
                game.placeMinesEagerly(using: &rng)
            } else {
                var rng = SystemRandomNumberGenerator()
                game.placeMinesEagerly(using: &rng)
            }
        })
    }

    /// A snapshot of the current game (live timer span folded in for an exact
    /// elapsed), or nil if there's nothing worth saving.
    public func snapshot() -> GameSnapshot? {
        GameSnapshot(
            game: game, config: config, elapsedCentiseconds: currentCentiseconds(),
            camera: cameraView, inputMode: inputMode)
    }

    /// The `Sendable` inputs a snapshot needs, captured cheaply on the main actor so
    /// the actual snapshot BUILD (which scans the whole board to derive the
    /// revealed/flagged coord sets — heavy on a 1M-cell board) can run OFF the main
    /// thread (see `GameSnapshot(inputs:)`).
    public struct SnapshotInputs: Sendable {
        public let game: Game
        public let config: GameConfig
        public let elapsedCentiseconds: Int
        public let camera: CameraView?
        public let inputMode: InputMode
    }

    /// Capture the snapshot inputs, or nil unless a save is worthwhile (in progress).
    public func snapshotInputs() -> SnapshotInputs? {
        guard game.status == .playing else { return nil }
        return SnapshotInputs(
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
        clock.elapsedCentiseconds = snapshot.elapsedCentiseconds
        isPaused = false
        isComputing = false
        // Flag placements aren't persisted, so a resumed game only counts ones made
        // after resume (a minor under-count, not worth a snapshot field).
        flagsPlacedThisGame = 0
        chordsThisGame = 0
        // Purity bits default to VIOLATED on restore: board state can't prove a clean
        // no-flag/no-chord run, so a resumed game can't earn those feats (deny over
        // false-award). A non-empty restored flag set makes usedFlag definitely true;
        // chord leaves no trace, so it's unknowable → true. See the achievements plan.
        usedFlagEver = true
        usedChordEver = true
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
        clock.elapsedCentiseconds = finalCentiseconds
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
                self.clock.elapsedCentiseconds = self.currentCentiseconds()
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
        clock.elapsedCentiseconds = accumulatedCentiseconds
    }

    private func resetTimer() {
        timer?.cancel()
        timer = nil
        accumulatedCentiseconds = 0
        runningSince = nil
        isPaused = false
        clock.elapsedCentiseconds = 0
    }

    private func bump() { revision &+= 1 }
}
