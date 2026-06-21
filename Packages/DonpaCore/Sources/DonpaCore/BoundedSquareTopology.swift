/// Classic Minesweeper geometry: a `width × height` square grid with hard edges.
///
/// 8-connected (Moore neighbourhood). Coordinates outside the rectangle are
/// off-board, so `normalize` returns `nil` for them and `neighbors` simply
/// omits them — this is what gives the board its edges and corners.
public struct BoundedSquareTopology: Topology {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        precondition(width > 0 && height > 0, "board must be non-empty")
        self.width = width
        self.height = height
    }

    public var cellCount: Int { width * height }

    /// The 8 Moore offsets, shared by every square topology.
    static let offsets: [(Int, Int)] = [
        (-1, -1), (0, -1), (1, -1),
        (-1, 0), (1, 0),
        (-1, 1), (0, 1), (1, 1),
    ]

    public func neighbors(of c: Coord) -> [Coord] {
        Self.offsets.compactMap { dx, dy in
            normalize(Coord(c.x + dx, c.y + dy))
        }
    }

    public func normalize(_ c: Coord) -> Coord? {
        guard c.x >= 0, c.x < width, c.y >= 0, c.y < height else { return nil }
        return c
    }

    public func allCoords() -> AnySequence<Coord> {
        AnySequence { () -> AnyIterator<Coord> in
            var x = 0
            var y = 0
            return AnyIterator {
                guard y < self.height else { return nil }
                let coord = Coord(x, y)
                x += 1
                if x == self.width {
                    x = 0
                    y += 1
                }
                return coord
            }
        }
    }
}
