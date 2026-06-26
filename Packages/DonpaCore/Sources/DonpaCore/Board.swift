/// Per-cell visibility state.
public enum CellState: Sendable {
    case hidden
    case revealed
    case flagged
}

/// One cell's full state, bit-packed into a single byte — `state` (2 bits),
/// `isMine` (1 bit), `adjacentMines` (4 bits, 0…8). On a 1000² board this makes
/// the cell array 1MB instead of 16MB (the unpacked struct strides 16 bytes), so
/// the whole board copies ~16× cheaper (matters for the per-move COW copy and
/// overall memory). The public API is unchanged — `state`/`isMine`/`adjacentMines`
/// are still settable vars — so nothing outside this file is affected.
public struct Cell: Sendable {
    private var bits: UInt8 = 0  // [ adjacent:4 | mine:1 | state:2 ], bit 7 unused

    public init() {}

    public var state: CellState {
        get {
            switch bits & 0b11 {
            case 1: return .revealed
            case 2: return .flagged
            default: return .hidden
            }
        }
        set {
            let code: UInt8
            switch newValue {
            case .hidden: code = 0
            case .revealed: code = 1
            case .flagged: code = 2
            }
            bits = (bits & ~0b11) | code
        }
    }

    public var isMine: Bool {
        get { bits & 0b100 != 0 }
        set { bits = newValue ? (bits | 0b100) : (bits & ~0b100) }
    }

    /// Number of mines among this cell's neighbours. Valid once mines are placed.
    public var adjacentMines: Int {
        get { Int(bits >> 3) }
        set { bits = (bits & 0b111) | (UInt8(newValue) << 3) }
    }
}

/// Dense flat cell storage for a rectangular board — `index = y·width + x`, the
/// memory/speed path for huge boards (a 1000² dict was ~100MB+ and slow). Get
/// returns a default `Cell` for an off-board coord; set ignores it.
///
/// Every board topology is a dense `width × height` rectangle (bounded square,
/// wrapped/torus square, and — when it lands — hex via offset storage), so this
/// takes a `RectangularTopology`: the constraint is in the type, not a runtime
/// check, so a non-rectangular board is simply unrepresentable.
///
/// It's a **struct holding the array directly** (not an enum with an associated
/// array): a write mutates the array in place via copy-on-write. An enum case
/// would force `self = .flat(cells, …)` on every write, un-uniquing the array
/// reference and copying all N cells per write → O(n²) (measured: 27s for a
/// 500² placeMines; the struct form is ~0.5s).
private struct CellStore: Sendable {
    private var cells: [Cell]
    private let rect: any RectangularTopology

    init(topology: any RectangularTopology) {
        self.rect = topology
        self.cells = Array(repeating: Cell(), count: topology.cellCount)
    }

    subscript(_ c: Coord) -> Cell {
        get {
            guard let i = rect.index(of: c) else { return Cell() }
            return cells[i]
        }
        set {
            // In-place array write: `cells` is uniquely referenced here, so COW
            // mutates without copying — O(1) per write even on a 1M board.
            guard let i = rect.index(of: c) else { return }
            cells[i] = newValue
        }
    }

    /// All (coord, cell) pairs — for the persistence/derived accessors.
    func forEach(_ body: (Coord, Cell) -> Void) {
        for (i, cell) in cells.enumerated() { body(rect.coord(at: i), cell) }
    }
}

/// The grid of cells plus the mine layout, indexed by `Coord`.
///
/// `Board` knows *what* is in each cell and how to recompute adjacency, but it
/// holds no game rules (those live in `Game`). All neighbour questions are
/// delegated to the injected `Topology`, so the board is geometry-agnostic. Cells
/// are held in a flat row-major array (see `CellStore`) — every supported
/// topology is a dense `width × height` rectangle.
public struct Board: Sendable {
    public let topology: any RectangularTopology
    private var cells: CellStore

    /// The mine coordinates, stored once in `placeMines`. Kept as a set so the
    /// "reveal/flag every mine" end-game paths and `mineCoords` iterate only the
    /// mines (e.g. ~130k) rather than scanning every cell (e.g. 1M) on a huge board.
    private var minePositions: Set<Coord> = []
    /// Mines on the board — set once in `placeMines`. Tracked rather than scanned
    /// so it's O(1) (matters on huge boards).
    public private(set) var mineCount: Int = 0
    /// Flagged cells — maintained incrementally as cell state changes (every
    /// mutation goes through the subscript), so it's O(1) per query.
    public private(set) var flagCount: Int = 0

    public init(topology: any RectangularTopology) {
        self.topology = topology
        self.cells = CellStore(topology: topology)
    }

    public subscript(_ c: Coord) -> Cell {
        get { cells[c] }
        set {
            // Keep flagCount in step with any state change — all cell mutation
            // funnels through here, so the counter can't drift.
            let was = cells[c].state
            if was != newValue.state {
                if was == .flagged { flagCount -= 1 }
                if newValue.state == .flagged { flagCount += 1 }
            }
            cells[c] = newValue
        }
    }

    public var allCoords: AnySequence<Coord> { topology.allCoords() }
    public var cellCount: Int { topology.cellCount }

    /// Coordinate sets for persistence — compact alternative to encoding the full
    /// cell dict (a 1000² save would be huge otherwise).
    public var mineCoords: Set<Coord> { minePositions }
    public var revealedCoords: Set<Coord> { coords { $0.state == .revealed } }
    public var flaggedCoords: Set<Coord> { coords { $0.state == .flagged } }

    /// Count of revealed non-mine cells — the source of truth for progress/win,
    /// derived from the actual board (so a restored game can recompute it rather
    /// than trust a persisted number).
    public var revealedSafeCount: Int { coords { $0.state == .revealed && !$0.isMine }.count }

    private func coords(where match: (Cell) -> Bool) -> Set<Coord> {
        var result: Set<Coord> = []
        cells.forEach { c, cell in if match(cell) { result.insert(c) } }
        return result
    }

    /// Rebuild a board from a saved layout: place `mines` (recomputing adjacency),
    /// then set the given cells revealed / flagged. Used to restore a persisted
    /// in-progress game without re-randomizing the (first-click-safe) mines.
    ///
    /// Coordinates are filtered to in-bounds cells, so a corrupt or tampered save
    /// with off-board coords can't insert phantom cells or skew the mine count —
    /// it just yields a (possibly odd but valid) board, never a broken one.
    public mutating func restore(mines: Set<Coord>, revealed: Set<Coord>, flagged: Set<Coord>) {
        let onBoard = Set(topology.allCoords())
        placeMines(at: mines.intersection(onBoard))
        for c in revealed where onBoard.contains(c) { self[c].state = .revealed }
        for c in flagged where onBoard.contains(c) { self[c].state = .flagged }
    }

    /// Places mines on the given coordinates and recomputes adjacency counts.
    ///
    /// Both passes iterate only the MINES, not every cell — so on a huge board the
    /// cost scales with the mine count (e.g. ~130k), not the cell count (1M). Mines
    /// are flagged in one pass; adjacency is then *scattered* outward (each mine
    /// bumps its neighbours' counts) rather than gathered per cell (each cell
    /// summing its neighbours), turning an N×8 scan into mines×8.
    ///
    /// Assumes a clean board (fresh `Board`, or a fresh one in `restore`): cells
    /// start with `isMine == false` and `adjacentMines == 0`, so no reset pass is
    /// needed. `placeMines` is only ever called once per board, on a clean one.
    public mutating func placeMines(at mineCoords: Set<Coord>) {
        minePositions = mineCoords
        mineCount = mineCoords.count
        for c in mineCoords {
            cells[c].isMine = true
            for n in topology.neighbors(of: c) {
                cells[n].adjacentMines += 1
            }
        }
    }
}
