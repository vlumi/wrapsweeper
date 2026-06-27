/// The single seam through which board variants are introduced: all game logic
/// is written in terms of `neighbors(of:)` and `allCoords()`, so swapping
/// square↔hex or bounded↔wrapped requires only a new `Topology`.
public protocol Topology: Sendable {
    var cellCount: Int { get }

    /// On-board, normalized neighbours of `c` (8 for square, 6 for hex). Wrapped
    /// topologies return the wrapped cells, so callers never see off-board coords.
    func neighbors(of c: Coord) -> [Coord]

    /// Maps a raw coordinate onto the board. `nil` if off-board for bounded
    /// topologies; wrapped topologies fold it back (modulo) and never return `nil`.
    func normalize(_ c: Coord) -> Coord?

    /// Every playable coordinate, in a stable order.
    func allCoords() -> AnySequence<Coord>
}

/// A topology whose cells form a dense `width × height` rectangle — the property
/// that licenses flat array storage (`index = y·width + x`) over a dictionary,
/// the speed/memory path for huge boards. A non-grid topology wouldn't conform.
public protocol RectangularTopology: Topology {
    var width: Int { get }
    var height: Int { get }
}

extension RectangularTopology {
    /// Row-major flat index for an in-bounds coordinate, or nil if off-board.
    public func index(of c: Coord) -> Int? {
        guard c.x >= 0, c.x < width, c.y >= 0, c.y < height else { return nil }
        return c.y * width + c.x
    }

    /// The coordinate at a flat index (inverse of `index(of:)`).
    public func coord(at index: Int) -> Coord {
        Coord(index % width, index / width)
    }
}
