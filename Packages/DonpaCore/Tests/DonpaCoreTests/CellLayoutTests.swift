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

    // MARK: HexLayout

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
