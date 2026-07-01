/// Pointy-top hexagonal geometry: a `width × height`, 6-connected grid with hard
/// edges. Cells are stored in **odd-r offset coordinates** — a rectangle of rows
/// where odd rows are shoved half a cell right — so the flat `index = y·width + x`
/// storage that `RectangularTopology` licenses still applies, exactly as for the
/// square topologies. Only the neighbour set (6, and row-parity-dependent) and the
/// pixel layout differ; the game logic is unchanged.
public struct HexTopology: RectangularTopology {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        precondition(width > 0 && height > 0, "board must be non-empty")
        self.width = width
        self.height = height
    }

    public var cellCount: Int { width * height }

    /// The 6 neighbour offsets for **even** rows (odd-r layout, y-up). E/W are
    /// shared with odd rows; the four diagonals shift by row parity.
    static let evenRowOffsets: [(Int, Int)] = [
        (1, 0), (-1, 0),
        (-1, 1), (0, 1),
        (-1, -1), (0, -1),
    ]

    /// The 6 neighbour offsets for **odd** rows.
    static let oddRowOffsets: [(Int, Int)] = [
        (1, 0), (-1, 0),
        (0, 1), (1, 1),
        (0, -1), (1, -1),
    ]

    public func neighbors(of c: Coord) -> [Coord] {
        let offsets = (c.y & 1) == 0 ? Self.evenRowOffsets : Self.oddRowOffsets
        return offsets.compactMap { dx, dy in
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
