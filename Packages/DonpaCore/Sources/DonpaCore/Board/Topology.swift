/// The single seam through which "epic" board variants are introduced.
///
/// Everything above this protocol — mine placement, adjacency counts,
/// flood-fill, win/lose detection — is written in terms of `neighbors(of:)`
/// and `allCoords()` only. Swapping square↔hex or bounded↔wrapped therefore
/// requires a new `Topology` and nothing else.
public protocol Topology: Sendable {
    /// Total number of playable cells on the board.
    var cellCount: Int { get }

    /// The neighbours of `c` that are on the board, already normalized.
    ///
    /// 8 for square grids, 6 for hex. For wrapped topologies the returned
    /// coordinates are the normalized (wrapped) cells, so callers never see
    /// off-board coordinates.
    func neighbors(of c: Coord) -> [Coord]

    /// Maps a raw coordinate onto the board.
    ///
    /// Returns `nil` for bounded topologies when `c` lies outside the board.
    /// Wrapped topologies instead fold `c` back onto the board (modulo) and
    /// never return `nil`.
    func normalize(_ c: Coord) -> Coord?

    /// Every playable coordinate, in a stable order.
    func allCoords() -> AnySequence<Coord>
}

/// A topology whose cells form a dense `width × height` rectangle addressed by
/// `(x, y)` with `0 ≤ x < width`, `0 ≤ y < height`. This is exactly the property
/// that licenses **flat array storage** (`index = y·width + x`) instead of a
/// dictionary — the memory- and speed-critical path for huge boards. Square
/// grids (bounded and wrapped) are rectangular; a future non-grid topology (e.g.
/// a sparse or irregular board) simply wouldn't conform, and `Board` falls back
/// to dictionary storage for it.
public protocol RectangularTopology: Topology {
    var width: Int { get }
    var height: Int { get }
}

extension RectangularTopology {
    /// Row-major flat index for an in-bounds coordinate, or nil if off-board.
    /// `cellCount == width * height`, so indices are `0 ..< cellCount`.
    public func index(of c: Coord) -> Int? {
        guard c.x >= 0, c.x < width, c.y >= 0, c.y < height else { return nil }
        return c.y * width + c.x
    }

    /// The coordinate at a flat index (inverse of `index(of:)`).
    public func coord(at index: Int) -> Coord {
        Coord(index % width, index / width)
    }
}
