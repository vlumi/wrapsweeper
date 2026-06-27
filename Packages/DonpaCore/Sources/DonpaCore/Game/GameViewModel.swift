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

    /// True while a reveal/chord is being computed OFF the main thread (the heavy
    /// flood-fill / mine placement on a huge board). The UI shows a processing
    /// indicator and blocks further board input while this is set — so the screen
    /// never freezes, but you also can't open a tile against a board that hasn't
    /// finished updating (which could be a guaranteed mine). Cleared when the
    /// computed result is applied.
    @Published public private(set) var isComputing = false

    /// Flag *placements* this game (each hidden→flagged action, not net flags) —
    /// the lifetime "flags placed" stat counts actions, so re-flagging a cell
    /// counts again. Reset on new game / restore; read once at game end.
    public private(set) var flagsPlacedThisGame = 0

    /// Career activity already flushed to the lifetime totals for THIS game, so a
    /// flush only ever sends the new delta (never double-counts). Reset per game.
    private var flushedTiles = 0
    private var flushedFlags = 0
    private var flushedCentiseconds = 0

    /// Push the unflushed slice of this game's activity (tiles opened, flag
    /// placements, centiseconds played) to the lifetime career totals. Called on
    /// pause (which is also when the scoreboard opens — so the Career page is
    /// current the moment you look at it), on background/quit, and at game
    /// end/discard — so live activity accumulates without a per-tile write storm,
    /// and abandoning a dug-into game still credits its effort. Set by the host
    /// (`GameView`), which owns the scoreboard; Core never references it. Carries
    /// DELTAS since the last flush.
    public var onActivityFlush:
        ((_ tilesDelta: Int, _ flagsDelta: Int, _ centisecondsDelta: Int) -> Void)?

    /// Flush this game's activity delta (tiles/flags/time since the last flush) to
    /// the career totals via `onActivityFlush`, then mark it flushed. Idempotent —
    /// a flush with nothing new sends nothing.
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

    /// Board input is accepted only when not paused and not mid-compute. The
    /// compute gate is what stops a tap landing on a board that hasn't finished
    /// updating (e.g. opening a cell that the in-flight reveal is about to change).
    private var canTakeInput: Bool { !isPaused && !isComputing }

    /// Whether a reveal of `c` would detonate a mine right now — i.e. input is
    /// accepted, the game is live, and `c` is a still-hidden mine. The scene uses
    /// this to fire the explosion instantly on tap (before the off-thread reveal),
    /// for immediate feedback. Mines exist only after the first click (always
    /// safe), so this is false on the opening move.
    public func canRevealHitMine(_ c: Coord) -> Bool {
        guard canTakeInput, game.status == .playing else { return false }
        return game.board[c].state == .hidden && game.board[c].isMine
    }

    /// Run a heavy, board-mutating action OFF the main thread, then apply the
    /// result back on the main actor. `mutate` does the expensive work (flood-fill
    /// / mine placement) on a *copy* of the game — `Game` is a `Sendable` value, so
    /// this is safe — while the UI stays responsive and shows a processing
    /// indicator (`isComputing`). `afterApply` runs on the main actor once the new
    /// state is installed (timer start, end-game detection). A redraw is bumped at
    /// the end. Input is gated by `canTakeInput`, so only one compute runs at once.
    /// The in-flight compute, if any — held so tests can deterministically await
    /// it (`await viewModel.awaitPendingWork()`). Not for production callers; the
    /// scene just observes `isComputing`/`revision`.
    private var pendingWork: Task<Void, Never>?

    /// Await the current reveal/chord compute (test-only synchronization point).
    public func awaitPendingWork() async {
        await pendingWork?.value
    }

    private func computeOffMain(
        _ mutate: @Sendable @escaping (inout Game) -> Void,
        afterApply: @escaping () -> Void = {}
    ) {
        isComputing = true
        let snapshot = game  // O(1) COW copy; the mutation in the task triggers the copy
        let generation = gameID  // if a new/restored game starts meanwhile, discard
        pendingWork = Task {
            // Do the expensive mutation off the main thread on a copy, then return
            // the new value. `Game` is Sendable, so it crosses back safely.
            let updated = await Task.detached {
                var working = snapshot
                mutate(&working)
                return working
            }.value
            // A newGame/restore during the compute bumps gameID; its fresh board
            // must not be clobbered by this now-stale result.
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
        // Flagging is O(1), so it stays synchronous — but still blocked mid-compute
        // (the board is changing under it) and when paused/finished.
        guard canTakeInput, game.status == .notStarted || game.status == .playing else { return }
        let wasFlagged = game.board[c].state == .flagged
        game.toggleFlag(c)
        // Count a placement (hidden→flagged), not a removal — the "flags placed"
        // stat counts actions, so a re-flag counts again.
        if !wasFlagged, game.board[c].state == .flagged { flagsPlacedThisGame += 1 }
        bump()
    }

    public func chord(_ c: Coord) {
        // Once the game is over (or paused/computing), input is inert — chording a
        // revealed cell must not re-publish the result (which would replay the
        // end-game animation and panel on every post-loss click).
        guard canTakeInput, game.status == .playing else { return }
        computeOffMain({ game in game.chord(c) }) { [weak self] in
            self?.finishIfEnded()
        }
    }

    public func newGame(config: GameConfig? = nil) {
        // Flush any unrecorded activity from the outgoing game before discarding it,
        // so abandoning a dug-into game (restart / new game mid-play) still credits
        // its tiles/flags/time to the lifetime totals. A finished game already
        // flushed at end; an untouched board has nothing new.
        if game.status == .playing { flushActivity() }
        if let config { self.config = config }
        game = Game(config: self.config)
        elapsedCentiseconds = 0
        lastWin = nil
        lastResult = nil
        inputMode = .reveal  // every game starts in reveal mode
        // A brand-new game centres on its own default fit, not a resumed view.
        pendingCameraRestore = nil
        cameraView = nil
        // gameID bumps below, so any in-flight reveal compute discards its result;
        // clear the gate so the fresh board takes input immediately.
        isComputing = false
        flagsPlacedThisGame = 0
        flushedTiles = 0
        flushedFlags = 0
        flushedCentiseconds = 0
        resetTimer()
        gameID &+= 1
        bump()
        armBoard()
    }

    /// Pre-place the mines OFF the main thread right after a new game, so the heavy
    /// placement (and adjacency) on a huge board happens while the player looks at
    /// the fresh board — not on their first tap. The first reveal then only has to
    /// relocate any mines under the click (cheap; see `Game.reveal`). The board
    /// shows immediately (empty) and takes the brief `isComputing` gate while
    /// arming; a tap during arming is blocked, then opens once placement lands.
    private func armBoard() {
        computeOffMain({ game in
            var rng = SystemRandomNumberGenerator()
            game.placeMinesEagerly(using: &rng)
        })
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
        isComputing = false  // discard any in-flight compute (gameID bumps below)
        // Not persisted in the snapshot, so a resumed game only counts flag
        // placements made after the resume (a minor under-count for the lifetime
        // "flags placed" stat — not worth a snapshot field for a flavour count).
        flagsPlacedThisGame = 0
        // Seed the flush trackers to the restored state: the tiles and time from
        // before the save were already flushed to the career totals (the
        // background pause flushes), so only post-resume activity should count
        // again — otherwise resuming would re-add the whole board's tiles/time.
        flushedTiles = game.revealedSafeCount
        flushedFlags = 0
        flushedCentiseconds = snapshot.elapsedCentiseconds
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
        // Flush the final activity slice (tiles/flags/time since the last flush) to
        // the career totals BEFORE the host records the outcome — so the end-of-game
        // record adds only the games-played + win/loss + mine outcome, never the
        // tiles/flags/time again (those flow through flushes during play).
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

    /// Pause the clock mid-game: bank the live span and stop ticking, leaving the
    /// game playable-but-frozen. No-op unless a game is actually in progress.
    public func pause() {
        guard game.status == .playing, !isPaused else { return }
        // Flush activity to the career totals while the clock is still live, so the
        // scoreboard (which opens via a pause) shows current tiles/flags/time.
        flushActivity()
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
