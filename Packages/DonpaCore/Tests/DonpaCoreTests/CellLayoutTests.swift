import CoreGraphics
import XCTest

@testable import DonpaCore

final class CellLayoutTests: XCTestCase {
    func testCenterIsHalfACellInFromTheOrigin() {
        let layout = SquareLayout(cellSize: 32)
        XCTAssertEqual(layout.center(of: Coord(0, 0)), CGPoint(x: 16, y: 16))
        XCTAssertEqual(layout.center(of: Coord(2, 3)), CGPoint(x: 80, y: 112))
    }

    func testCoordAtPointMapsBackToTheCell() {
        let layout = SquareLayout(cellSize: 32)
        XCTAssertEqual(layout.coord(at: CGPoint(x: 0, y: 0)), Coord(0, 0))
        XCTAssertEqual(layout.coord(at: CGPoint(x: 31, y: 31)), Coord(0, 0))
        XCTAssertEqual(layout.coord(at: CGPoint(x: 32, y: 0)), Coord(1, 0))
        XCTAssertEqual(layout.coord(at: CGPoint(x: 80, y: 112)), Coord(2, 3))
    }

    func testCenterRoundTripsThroughCoord() {
        let layout = SquareLayout(cellSize: 24)
        for x in 0..<10 {
            for y in 0..<10 {
                let c = Coord(x, y)
                XCTAssertEqual(layout.coord(at: layout.center(of: c)), c)
            }
        }
    }

    func testPointsOutsideTheBoardReturnNil() {
        let layout = SquareLayout()
        XCTAssertNil(layout.coord(at: CGPoint(x: -1, y: 10)))
        XCTAssertNil(layout.coord(at: CGPoint(x: 10, y: -1)))
    }

    func testBoardSizeScalesWithCellSize() {
        let layout = SquareLayout(cellSize: 10)
        XCTAssertEqual(layout.boardSize(width: 9, height: 16), CGSize(width: 90, height: 160))
    }

    /// The square-grid `CellLayout` defaults: uniform pitch, square tile.
    func testSquareLayoutGeometryDefaults() {
        let layout = SquareLayout(cellSize: 20)
        XCTAssertEqual(layout.columnPitch, 20)
        XCTAssertEqual(layout.rowPitch, 20)
        XCTAssertEqual(layout.tileShape, .roundedSquare)
        XCTAssertEqual(layout.tileSize, CGSize(width: 20, height: 20))
    }

    // MARK: HexLayout

    /// Hex geometry knobs: full-width columns, √3/2 row pitch, hex tile taller than
    /// wide by 2/√3 — what the renderer reads to size/space tiles.
    func testHexLayoutGeometry() {
        let layout = HexLayout(cellSize: 32)
        XCTAssertEqual(layout.columnPitch, 32, accuracy: 0.001)
        XCTAssertEqual(layout.rowPitch, 32 * 0.866_025_403_784_438_6, accuracy: 0.001)
        XCTAssertEqual(layout.tileShape, .pointyHex)
        XCTAssertEqual(layout.tileSize.width, 32, accuracy: 0.001)
        XCTAssertEqual(layout.tileSize.height, 32 * 1.154_700_538_379_251_5, accuracy: 0.001)
    }

    /// `boardSize`: width gains half a cell for the odd-row shift (height > 1), and
    /// height is (h-1) row pitches plus one full vertex-to-vertex hex height. A
    /// single row has no odd-row overhang.
    func testHexBoardSize() {
        let layout = HexLayout(cellSize: 32)
        let pitch = 32 * 0.866_025_403_784_438_6
        let vertexH = 32 * 1.154_700_538_379_251_5
        let multi = layout.boardSize(width: 4, height: 3)
        XCTAssertEqual(multi.width, (4 + 0.5) * 32, accuracy: 0.001)
        XCTAssertEqual(multi.height, 2 * pitch + vertexH, accuracy: 0.001)
        // Single row: no odd rows exist, so no half-cell width overhang.
        let single = layout.boardSize(width: 4, height: 1)
        XCTAssertEqual(single.width, 4 * 32, accuracy: 0.001)
        XCTAssertEqual(single.height, vertexH, accuracy: 0.001)
    }

    func testHexOddRowsAreShiftedRight() {
        let layout = HexLayout(cellSize: 32)
        // Even row: no shift; odd row: half a cell to the right.
        XCTAssertEqual(layout.center(of: Coord(0, 0)).x, 16, accuracy: 0.001)
        XCTAssertEqual(layout.center(of: Coord(0, 1)).x, 32, accuracy: 0.001)
    }

    func testHexRowsPackAtThreeQuarterHeight() {
        let layout = HexLayout(cellSize: 32)
        let pitch = 32.0 * 0.866_025_403_784_438_6  // √3/2
        XCTAssertEqual(layout.center(of: Coord(0, 0)).y, pitch * 0.5, accuracy: 0.001)
        XCTAssertEqual(layout.center(of: Coord(0, 1)).y, pitch * 1.5, accuracy: 0.001)
    }

    func testHexCenterRoundTripsThroughCoord() {
        // The whole hit-test correctness claim: every centre maps back to its cell.
        let layout = HexLayout(cellSize: 28)
        for x in 0..<12 {
            for y in 0..<12 {
                let c = Coord(x, y)
                XCTAssertEqual(layout.coord(at: layout.center(of: c)), c)
            }
        }
    }

    func testHexPointsOutsideTheBoardReturnNil() {
        let layout = HexLayout()
        XCTAssertNil(layout.coord(at: CGPoint(x: -1, y: 10)))
        XCTAssertNil(layout.coord(at: CGPoint(x: 10, y: -1)))
    }
}
