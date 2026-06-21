import XCTest

@testable import DonpaCore

final class TopologyTests: XCTestCase {

    // MARK: BoundedSquareTopology

    func testBoundedNeighborCounts() {
        let t = BoundedSquareTopology(width: 5, height: 5)
        // Corner has 3 neighbours, edge has 5, interior has 8.
        XCTAssertEqual(t.neighbors(of: Coord(0, 0)).count, 3)
        XCTAssertEqual(t.neighbors(of: Coord(2, 0)).count, 5)
        XCTAssertEqual(t.neighbors(of: Coord(2, 2)).count, 8)
    }

    func testBoundedNormalizeRejectsOffBoard() {
        let t = BoundedSquareTopology(width: 3, height: 3)
        XCTAssertNil(t.normalize(Coord(-1, 0)))
        XCTAssertNil(t.normalize(Coord(3, 0)))
        XCTAssertEqual(t.normalize(Coord(2, 2)), Coord(2, 2))
    }

    func testBoundedAllCoordsCoversBoard() {
        let t = BoundedSquareTopology(width: 4, height: 3)
        let coords = Array(t.allCoords())
        XCTAssertEqual(coords.count, 12)
        XCTAssertEqual(Set(coords).count, 12)
    }

    // MARK: WrappedSquareTopology

    func testWrappedHasNoEdges() {
        let t = WrappedSquareTopology(width: 5, height: 5)
        // Every cell — including corners — has exactly 8 neighbours on a torus.
        for c in t.allCoords() {
            XCTAssertEqual(t.neighbors(of: c).count, 8, "cell \(c) should have 8 neighbours")
        }
    }

    func testWrappedNormalizeFolds() {
        let t = WrappedSquareTopology(width: 4, height: 4)
        XCTAssertEqual(t.normalize(Coord(-1, -1)), Coord(3, 3))
        XCTAssertEqual(t.normalize(Coord(4, 4)), Coord(0, 0))
        XCTAssertEqual(t.normalize(Coord(5, 2)), Coord(1, 2))
    }

    func testWrappedCornerWrapsToOppositeCorner() {
        let t = WrappedSquareTopology(width: 5, height: 5)
        let n = Set(t.neighbors(of: Coord(0, 0)))
        // Top-left's diagonal neighbour wraps to the bottom-right corner.
        XCTAssertTrue(n.contains(Coord(4, 4)))
    }
}
