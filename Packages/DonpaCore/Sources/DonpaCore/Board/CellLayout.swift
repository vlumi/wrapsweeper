import CoreGraphics

/// Maps logical cell coordinates to screen geometry and back — the visual
/// counterpart to `Topology`. `SquareLayout` ships now; `HexLayout` slots in here
/// later with no change to `BoardScene` or game logic.
public protocol CellLayout: Sendable {
    /// Side length / nominal size of one cell in points.
    var cellSize: CGFloat { get }

    /// Horizontal centre-to-centre spacing between columns in a row.
    var columnPitch: CGFloat { get }

    /// Vertical centre-to-centre spacing between rows. Equals `cellSize` for a
    /// square grid; smaller for a hex grid (rows interlock at 3/4 height).
    var rowPitch: CGFloat { get }

    /// The tile outline the renderer should draw for a cell.
    var tileShape: TileShape { get }

    /// The on-screen size of one tile's sprite (its outline's bounding box). Square
    /// for a square grid; a pointy hex is `cellSize` wide but taller (its vertex-to-
    /// vertex height), so its sprite must match or vertically-adjacent rows gap.
    var tileSize: CGSize { get }

    /// Centre point of cell `c` in scene coordinates.
    func center(of c: Coord) -> CGPoint

    /// The cell containing scene point `p`, or `nil` if none.
    func coord(at p: CGPoint) -> Coord?

    /// Bounding size of the whole board in points.
    func boardSize(width: Int, height: Int) -> CGSize
}

/// The outline a cell's tile is drawn with. `CellLayout` picks it so the renderer
/// stays geometry-agnostic (it just draws the requested shape at `cellSize`).
public enum TileShape: Sendable, Equatable {
    case roundedSquare
    /// Pointy-top regular hexagon, flat-to-flat width = `cellSize`.
    case pointyHex
}

extension CellLayout {
    // Square defaults: a uniform grid where both pitches are the cell size and the
    // tile is a `cellSize` square.
    public var columnPitch: CGFloat { cellSize }
    public var rowPitch: CGFloat { cellSize }
    public var tileShape: TileShape { .roundedSquare }
    public var tileSize: CGSize { CGSize(width: cellSize, height: cellSize) }
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
