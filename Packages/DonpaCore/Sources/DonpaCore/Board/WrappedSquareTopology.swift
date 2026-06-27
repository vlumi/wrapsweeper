/// A `width × height` square grid whose edges wrap — topologically a torus.
/// `normalize` folds coordinates with modulo (never `nil`), so every cell has
/// 8 neighbours and there are no edges or corners.
public struct WrappedSquareTopology: RectangularTopology {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        precondition(width > 0 && height > 0, "board must be non-empty")
        self.width = width
        self.height = height
    }

    public var cellCount: Int { width * height }

    public func neighbors(of c: Coord) -> [Coord] {
        BoundedSquareTopology.offsets.compactMap { dx, dy in
            normalize(Coord(c.x + dx, c.y + dy))
        }
    }

    public func normalize(_ c: Coord) -> Coord? {
        // Euclidean modulo so negative coordinates wrap correctly.
        let nx = ((c.x % width) + width) % width
        let ny = ((c.y % height) + height) % height
        return Coord(nx, ny)
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
