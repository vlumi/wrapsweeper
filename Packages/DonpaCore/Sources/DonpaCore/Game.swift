/// The overall play state.
public enum GameStatus: Sendable, Equatable {
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

    /// The mine that ended the game on a loss — the specific cell whose reveal
    /// detonated (even when reached via a chord). `nil` unless the game is lost.
    /// Lets the renderer focus the loss animation on the cell the player hit.
    public private(set) var lossCoord: Coord?

    private let topology: any Topology
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
    public init(topology: any Topology, mineCount: Int) {
        self.topology = topology
        self.board = Board(topology: topology)
        self.mineCount = mineCount
    }

    /// Test seam: start a game with a known mine layout already placed, as if
    /// the first click had happened. Lets tests (and the solver suite) reason
    /// about specific boards deterministically. Not part of the public API.
    init(topology: any Topology, mines: Set<Coord>) {
        self.topology = topology
        var board = Board(topology: topology)
        board.placeMines(at: mines)
        self.board = board
        self.mineCount = mines.count
        self.minesPlaced = true
        self.status = .playing
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
    public mutating func reveal<R: RandomNumberGenerator>(_ c: Coord, using rng: inout R) {
        guard status == .notStarted || status == .playing else { return }
        guard topology.normalize(c) != nil else { return }
        guard board[c].state == .hidden else { return }

        if !minesPlaced {
            let mines = MinePlacer.placeMines(
                topology: topology, mineCount: mineCount, firstClick: c, using: &rng)
            board.placeMines(at: mines)
            minesPlaced = true
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
        // Win when every non-mine cell is revealed.
        for c in board.allCoords where !board[c].isMine && board[c].state != .revealed {
            return
        }
        status = .won
        flagAllMines()
    }

    private mutating func revealAllMines() {
        for c in board.allCoords where board[c].isMine {
            board[c].state = .revealed
        }
    }

    private mutating func flagAllMines() {
        for c in board.allCoords where board[c].isMine {
            board[c].state = .flagged
        }
    }
}
