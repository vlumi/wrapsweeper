import XCTest

@testable import DonpaCore

/// `Board.mineCount`/`flagCount` are maintained incrementally (set in
/// `placeMines`, adjusted in the cell subscript) rather than scanned, so this
/// pins the invariants: they must always match a full scan.
final class BoardCountersTests: XCTestCase {
    private func scannedFlags(_ board: Board) -> Int {
        board.allCoords.filter { board[$0].state == .flagged }.count
    }

    func testEmptyBoardHasZeroCounts() {
        let board = Board(topology: BoundedSquareTopology(width: 5, height: 5))
        XCTAssertEqual(board.mineCount, 0)
        XCTAssertEqual(board.flagCount, 0)
    }

    func testMineCountAfterPlacement() {
        var board = Board(topology: BoundedSquareTopology(width: 5, height: 5))
        board.placeMines(at: [Coord(0, 0), Coord(1, 1), Coord(2, 2)])
        XCTAssertEqual(board.mineCount, 3)
    }

    func testFlagCountTracksFlagAndUnflag() {
        var board = Board(topology: BoundedSquareTopology(width: 4, height: 4))
        XCTAssertEqual(board.flagCount, 0)

        board[Coord(0, 0)].state = .flagged
        board[Coord(1, 0)].state = .flagged
        XCTAssertEqual(board.flagCount, 2)
        XCTAssertEqual(board.flagCount, scannedFlags(board))

        // Unflag one.
        board[Coord(0, 0)].state = .hidden
        XCTAssertEqual(board.flagCount, 1)
        XCTAssertEqual(board.flagCount, scannedFlags(board))
    }

    func testReflaggingSameCellDoesNotDoubleCount() {
        var board = Board(topology: BoundedSquareTopology(width: 4, height: 4))
        board[Coord(2, 2)].state = .flagged
        // Writing the same state again must not increment again.
        board[Coord(2, 2)].state = .flagged
        XCTAssertEqual(board.flagCount, 1)
    }

    func testFlaggedToRevealedDecrements() {
        var board = Board(topology: BoundedSquareTopology(width: 4, height: 4))
        board[Coord(0, 0)].state = .flagged
        XCTAssertEqual(board.flagCount, 1)
        // A direct flag→revealed transition (e.g. chord) still decrements.
        board[Coord(0, 0)].state = .revealed
        XCTAssertEqual(board.flagCount, 0)
        XCTAssertEqual(board.flagCount, scannedFlags(board))
    }
}
