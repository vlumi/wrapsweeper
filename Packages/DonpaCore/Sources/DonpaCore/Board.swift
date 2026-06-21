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
        set { cells[c] = newValue }
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
    }

    public var mineCount: Int {
        cells.values.reduce(0) { $0 + ($1.isMine ? 1 : 0) }
    }

    public var flagCount: Int {
        cells.values.reduce(0) { $0 + ($1.state == .flagged ? 1 : 0) }
    }
}
