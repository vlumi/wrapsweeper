import XCTest

@testable import DonpaCore

final class LossCoordTests: XCTestCase {

    func testNilWhilePlaying() {
        // Two mines on a 5x5 so a single corner reveal can't open everything.
        let topo = BoundedSquareTopology(width: 5, height: 5)
        var game = Game(topology: topo, mines: [Coord(0, 0), Coord(4, 4)])
        var rng = SeededRNG(seed: 1)
        // (1,0) borders the (0,0) mine, so it's a numbered cell: flood-fill
        // stops at it and the board is not fully opened → still playing.
        game.reveal(Coord(1, 0), using: &rng)
        XCTAssertEqual(game.status, .playing)
        XCTAssertNil(game.lossCoord)
    }

    func testSetToTheRevealedMineOnLoss() {
        var game = Game(topology: BoundedSquareTopology(width: 4, height: 4), mines: [Coord(0, 0)])
        var rng = SeededRNG(seed: 1)
        game.reveal(Coord(0, 0), using: &rng)
        XCTAssertEqual(game.status, .lost)
        XCTAssertEqual(game.lossCoord, Coord(0, 0))
    }

    /// On a losing chord, lossCoord is the specific neighbour that detonated,
    /// not the chorded number cell.
    func testSetToTheDetonatingNeighbourOnLosingChord() {
        // 5x5 with mines at (0,0) and (4,4). Reveal (1,1): it borders the (0,0)
        // mine → a "1" with hidden neighbours, and the board isn't won. Flag a
        // SAFE neighbour so the "1" looks satisfied, then chord (1,1): it reveals
        // the real mine (0,0) and loses there, not at the chorded cell.
        let topo = BoundedSquareTopology(width: 5, height: 5)
        var game = Game(topology: topo, mines: [Coord(0, 0), Coord(4, 4)])
        var rng = SeededRNG(seed: 1)
        game.reveal(Coord(1, 1), using: &rng)
        XCTAssertEqual(game.status, .playing)
        XCTAssertEqual(game.board[Coord(1, 1)].state, .revealed)
        XCTAssertEqual(game.board[Coord(1, 1)].adjacentMines, 1)
        game.toggleFlag(Coord(2, 1))  // wrong (safe) flag → "1" appears satisfied
        game.chord(Coord(1, 1))
        XCTAssertEqual(game.status, .lost)
        XCTAssertEqual(game.lossCoord, Coord(0, 0), "loss is attributed to the detonated mine")
    }

    func testNilOnWin() {
        // Single mine; reveal every safe cell → win.
        let topo = BoundedSquareTopology(width: 4, height: 4)
        var game = Game(topology: topo, mines: [Coord(0, 0)])
        var rng = SeededRNG(seed: 1)
        for c in game.board.allCoords where c != Coord(0, 0) {
            game.reveal(c, using: &rng)
        }
        XCTAssertEqual(game.status, .won)
        XCTAssertNil(game.lossCoord)
    }
}
