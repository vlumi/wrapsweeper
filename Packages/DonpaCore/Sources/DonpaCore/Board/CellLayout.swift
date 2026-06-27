import CoreGraphics

/// Maps logical cell coordinates to screen geometry and back — the *visual*
/// counterpart to `Topology`'s logical neighbours, and the second (and final)
/// seam epic features touch. `SquareLayout` ships now; `HexLayout` slots in here
/// later with no change to `BoardScene` or the game logic.
public protocol CellLayout: Sendable {
    /// Side length / nominal size of one cell in points.
    var cellSize: CGFloat { get }

    /// Centre point of cell `c` in scene coordinates.
    func center(of c: Coord) -> CGPoint

    /// The cell containing scene point `p`, or `nil` if none.
    func coord(at p: CGPoint) -> Coord?

    /// Bounding size of the whole board in points.
    func boardSize(width: Int, height: Int) -> CGSize
}

/// Square-grid layout. Origin at bottom-left (SpriteKit's coordinate system),
/// cell (0,0) centred half a cell in from the origin.
public struct SquareLayout: CellLayout {
    public let cellSize: CGFloat

    public init(cellSize: CGFloat = 32) {
        self.cellSize = cellSize
    }

    public func center(of c: Coord) -> CGPoint {
        CGPoint(
            x: (CGFloat(c.x) + 0.5) * cellSize,
            y: (CGFloat(c.y) + 0.5) * cellSize
        )
    }

    public func coord(at p: CGPoint) -> Coord? {
        guard p.x >= 0, p.y >= 0 else { return nil }
        return Coord(Int(p.x / cellSize), Int(p.y / cellSize))
    }

    public func boardSize(width: Int, height: Int) -> CGSize {
        CGSize(width: CGFloat(width) * cellSize, height: CGFloat(height) * cellSize)
    }
}
