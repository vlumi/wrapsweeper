import CoreGraphics
import DonpaCore
import XCTest

@testable import DonpaKit

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
}
