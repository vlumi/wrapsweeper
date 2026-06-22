/// Per-cell visibility state.
public enum CellState: Sendable {
    case hidden
    case revealed
    case flagged
}

/// One cell's full state.
public struct Cell: Sendable {
    public var state: CellState = .hidden
    public var isMine: Bool = false
    /// Number of mines among this cell's neighbours. Valid once mines are placed.
    public var adjacentMines: Int = 0
}

/// The grid of cells plus the mine layout, indexed by `Coord`.
///
/// `Board` knows *what* is in each cell and how to recompute adjacency, but it
/// holds no game rules (those live in `Game`). All neighbour questions are
/// delegated to the injected `Topology`, so the board is geometry-agnostic.
public struct Board: Sendable {
    public let topology: any Topology
    private var cells: [Coord: Cell]

    /// Mines on the board — set once in `placeMines`. Tracked rather than scanned
    /// so it's O(1) (matters on huge boards).
    public private(set) var mineCount: Int = 0
    /// Flagged cells — maintained incrementally as cell state changes (every
    /// mutation goes through the subscript), so it's O(1) per query.
    public private(set) var flagCount: Int = 0

    public init(topology: any Topology) {
        self.topology = topology
        var cells: [Coord: Cell] = [:]
        cells.reserveCapacity(topology.cellCount)
        for c in topology.allCoords() {
            cells[c] = Cell()
        }
        self.cells = cells
    }

    public subscript(_ c: Coord) -> Cell {
        get { cells[c] ?? Cell() }
        set {
            // Keep flagCount in step with any state change — all cell mutation
            // funnels through here, so the counter can't drift.
            let was = cells[c]?.state
            if was != newValue.state {
                if was == .flagged { flagCount -= 1 }
                if newValue.state == .flagged { flagCount += 1 }
            }
            cells[c] = newValue
        }
    }

    public var allCoords: AnySequence<Coord> { topology.allCoords() }
    public var cellCount: Int { topology.cellCount }

    /// Places mines on the given coordinates and recomputes every adjacency count.
    public mutating func placeMines(at mineCoords: Set<Coord>) {
        for c in topology.allCoords() {
            cells[c]?.isMine = mineCoords.contains(c)
        }
        for c in topology.allCoords() {
            let count = topology.neighbors(of: c).reduce(0) { acc, n in
                acc + (cells[n]?.isMine == true ? 1 : 0)
            }
            cells[c]?.adjacentMines = count
        }
        mineCount = mineCoords.count
    }
}
