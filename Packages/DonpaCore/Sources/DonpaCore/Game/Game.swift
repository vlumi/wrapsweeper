/// The overall play state.
public enum GameStatus: String, Sendable, Equatable, Codable {
    case notStarted
    case playing
    case won
    case lost
}

/// Drives the rules: first-click mine placement, flood-fill reveal, flagging,
/// chording, and win/lose detection.
///
/// `Game` is deliberately free of any rendering or timing concern and free of
/// any hard-coded geometry — it asks the `Topology` (via `Board`) for neighbours
/// and works unchanged on bounded, wrapped, square, or hex boards.
public struct Game: Sendable {
    public private(set) var board: Board
    public private(set) var status: GameStatus = .notStarted
    public let mineCount: Int

    /// Count of non-mine cells revealed so far, tracked incrementally so win
    /// detection and progress are O(1) rather than an O(n) board scan (matters
    /// for huge boards). A win is exactly `revealedSafeCount == safeCellCount`.
    public private(set) var revealedSafeCount: Int = 0

    /// Total non-mine cells on the board — the denominator for progress.
    public var safeCellCount: Int { board.cellCount - mineCount }

    /// Fraction of safe cells revealed, 0...1. 1.0 means the board is cleared
    /// (a win). Useful as a score on hard boards that are rarely fully cleared.
    public var progress: Double {
        let safe = safeCellCount
        return safe > 0 ? Double(revealedSafeCount) / Double(safe) : 0
    }

    /// The mine that ended the game on a loss — the specific cell whose reveal
    /// detonated (even when reached via a chord). `nil` unless the game is lost.
    /// Lets the renderer focus the loss animation on the cell the player hit.
    public private(set) var lossCoord: Coord?

    private let topology: any RectangularTopology
    private var minesPlaced = false

    public init(difficulty: Difficulty) {
        let topology = BoundedSquareTopology(width: difficulty.width, height: difficulty.height)
        self.topology = topology
        self.board = Board(topology: topology)
        self.mineCount = difficulty.mineCount
    }

    /// Start a game from a `GameConfig` (the modern path): the config supplies
    /// both the topology and the mine count.
    public init(config: GameConfig) {
        self.topology = config.topology
        self.board = Board(topology: config.topology)
        self.mineCount = config.mineCount
    }

    /// For epic variants / tests: inject any topology directly.
    public init(topology: any RectangularTopology, mineCount: Int) {
        self.topology = topology
        self.board = Board(topology: topology)
        self.mineCount = mineCount
    }

    /// Test seam: start a game with a known mine layout already placed, as if
    /// the first click had happened. Lets tests (and the solver suite) reason
    /// about specific boards deterministically. Not part of the public API.
    init(topology: any RectangularTopology, mines: Set<Coord>) {
        self.topology = topology
        var board = Board(topology: topology)
        board.placeMines(at: mines)
        self.board = board
        self.mineCount = mines.count
        self.minesPlaced = true
        self.status = .playing
    }

    /// Rebuild a game from a persisted snapshot. Mines are restored exactly (not
    /// re-randomized — they're first-click-safe), cells set revealed/flagged, and
    /// the derived game fields restored. The topology comes from the saved config.
    public static func restored(from s: GameSnapshot) -> Game {
        var game = Game(topology: s.config.topology, mineCount: s.config.mineCount)
        game.board.restore(mines: s.mines, revealed: s.revealed, flagged: s.flagged)
        game.minesPlaced = !game.board.mineCoords.isEmpty
        game.status = s.status
        // Derive from the actual restored board rather than trusting the saved
        // number, so a corrupt/tampered save can't skew progress or win detection.
        game.revealedSafeCount = game.board.revealedSafeCount
        game.lossCoord = s.lossCoord
        return game
    }

    public var flagsRemaining: Int { mineCount - board.flagCount }

    // MARK: - Reveal

    /// Reveals `c`. On the first reveal, mines are placed avoiding `c` and its
    /// neighbours, guaranteeing a 0-opening.
    public mutating func reveal(_ c: Coord) {
        var rng = SystemRandomNumberGenerator()
        reveal(c, using: &rng)
    }

    /// Testable variant with an injectable RNG.
    /// Place all mines now, with NO safe zone — for arming the board *before* the
    /// first click (off the main thread), since the first click isn't known yet.
    /// The first reveal then relocates any mines under it (see `reveal`). Idempotent
    /// guard: only places on a fresh board.
    public mutating func placeMinesEagerly<R: RandomNumberGenerator>(using rng: inout R) {
        guard !minesPlaced else { return }
        let mines = MinePlacer.randomMines(topology: topology, mineCount: mineCount, using: &rng)
        board.placeMines(at: mines)
        minesPlaced = true
    }

    public mutating func reveal<R: RandomNumberGenerator>(_ c: Coord, using rng: inout R) {
        guard status == .notStarted || status == .playing else { return }
        guard topology.normalize(c) != nil else { return }
        guard board[c].state == .hidden else { return }

        if !minesPlaced {
            // Not pre-armed (direct construction / tests): place now, excluding the
            // first-click safe zone in one shot.
            let mines = MinePlacer.placeMines(
                topology: topology, mineCount: mineCount, firstClick: c, using: &rng)
            board.placeMines(at: mines)
            minesPlaced = true
            status = .playing
        } else if status == .notStarted {
            // Pre-armed off-thread (no safe zone then); now that we know the first
            // click, move any mines out of its neighbourhood so it opens a region.
            var safeZone: Set<Coord> = [c]
            safeZone.formUnion(topology.neighbors(of: c))
            board.relocateMines(outOf: safeZone, using: &rng)
            status = .playing
        }

        if board[c].isMine {
            board[c].state = .revealed
            status = .lost
            lossCoord = c
            revealAllMines()
            return
        }

        floodFill(from: c)
        checkWin()
    }

    /// Reveals a 0-region: BFS that reveals each cell it visits and keeps
    /// expanding only out of 0-cells, so numbered cells form the border and are
    /// shown but not expanded past. Uses `topology.neighbors`, so it is
    /// geometry-agnostic. Flagged and mine cells are never enqueued.
    private mutating func floodFill(from start: Coord) {
        var queue = [start]
        var enqueued: Set<Coord> = [start]

        while let c = queue.popLast() {
            board[c].state = .revealed
            revealedSafeCount += 1  // flood-fill only ever reveals non-mine cells
            guard board[c].adjacentMines == 0 else { continue }
            for n in topology.neighbors(of: c) where !enqueued.contains(n) {
                guard board[n].state == .hidden, !board[n].isMine else { continue }
                enqueued.insert(n)
                queue.append(n)
            }
        }
    }

    // MARK: - Flagging

    public mutating func toggleFlag(_ c: Coord) {
        guard status == .playing || status == .notStarted else { return }
        guard topology.normalize(c) != nil else { return }
        switch board[c].state {
        case .hidden: board[c].state = .flagged
        case .flagged: board[c].state = .hidden
        case .revealed: break
        }
    }

    // MARK: - Chord

    /// Double-click/both-button reveal: if `c` is a revealed number whose
    /// adjacent flag count equals its number, reveal all its non-flagged
    /// neighbours. Mis-flagging here can lose the game — classic behaviour.
    public mutating func chord(_ c: Coord) {
        var rng = SystemRandomNumberGenerator()
        chord(c, using: &rng)
    }

    public mutating func chord<R: RandomNumberGenerator>(_ c: Coord, using rng: inout R) {
        guard status == .playing else { return }
        guard board[c].state == .revealed, board[c].adjacentMines > 0 else { return }
        let neighbors = topology.neighbors(of: c)
        let flagged = neighbors.filter { board[$0].state == .flagged }.count
        guard flagged == board[c].adjacentMines else { return }
        for n in neighbors where board[n].state == .hidden {
            reveal(n, using: &rng)
            if status == .lost { return }
        }
    }

    // MARK: - Win/lose helpers

    private mutating func checkWin() {
        // Win when every non-mine cell is revealed — an O(1) counter check
        // rather than scanning the whole board (which is costly on huge boards).
        guard revealedSafeCount == safeCellCount else { return }
        status = .won
        flagAllMines()
    }

    private mutating func revealAllMines() {
        for c in board.mineCoords where board[c].state != .flagged {
            // Leave correctly-flagged mines flagged: the player marked them, so the
            // flag should stay shown — and revealing them would clear the flag,
            // making `flagsRemaining` jump back up (the "mines left" counter surged
            // after a loss). Untouched flags keep `flagCount` intact.
            board[c].state = .revealed
        }
    }

    private mutating func flagAllMines() {
        for c in board.mineCoords {
            board[c].state = .flagged
        }
    }
}
