import XCTest

@testable import DonpaCore

final class MinePlacerTests: XCTestCase {

    func testPlacesExactCount() {
        let t = BoundedSquareTopology(width: 9, height: 9)
        var rng = SeededRNG(seed: 1)
        let mines = MinePlacer.placeMines(
            topology: t, mineCount: 10, firstClick: Coord(4, 4), using: &rng)
        XCTAssertEqual(mines.count, 10)
    }

    func testFirstClickAndNeighboursAreSafe() {
        let t = BoundedSquareTopology(width: 9, height: 9)
        let firstClick = Coord(4, 4)
        // Try many seeds: the safe zone must never contain a mine.
        for seed in UInt64(0)..<200 {
            var rng = SeededRNG(seed: seed)
            let mines = MinePlacer.placeMines(
                topology: t, mineCount: 10, firstClick: firstClick, using: &rng)
            var safeZone: Set<Coord> = [firstClick]
            safeZone.formUnion(t.neighbors(of: firstClick))
            XCTAssertTrue(
                mines.isDisjoint(with: safeZone),
                "seed \(seed) put a mine in the safe zone")
        }
    }

    func testDenseBoardStillExcludesFirstClick() {
        // Board so full of mines that the safe zone can't be fully honoured;
        // the clicked cell itself must still be mine-free.
        let t = BoundedSquareTopology(width: 3, height: 3)  // 9 cells
        let firstClick = Coord(1, 1)
        var rng = SeededRNG(seed: 7)
        let mines = MinePlacer.placeMines(
            topology: t, mineCount: 8, firstClick: firstClick, using: &rng)
        XCTAssertEqual(mines.count, 8)
        XCTAssertFalse(mines.contains(firstClick))
    }
}
