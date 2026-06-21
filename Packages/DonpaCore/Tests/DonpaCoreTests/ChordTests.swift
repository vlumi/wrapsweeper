import XCTest

@testable import DonpaCore

final class ChordTests: XCTestCase {

    /// Reveal a region, then find a revealed number whose mine-neighbours are
    /// fully known, flag exactly those, and chord — the remaining hidden
    /// neighbours should open and the game should not be lost.
    func testChordRevealsNeighborsWhenFlagsMatch() {
        var game = Game(difficulty: .beginner)
        var rng = SeededRNG(seed: 9)
        game.reveal(Coord(4, 4), using: &rng)

        let numbered = revealedNumberWithAllMineNeighborsKnown(in: game)
        guard let target = numbered else {
            XCTFail("no suitable numbered cell found for seed")
            return
        }

        // Flag every mine neighbour of the target.
        let mineNeighbors = neighbors(of: target, in: game).filter { game.board[$0].isMine }
        for m in mineNeighbors { game.toggleFlag(m) }

        let hiddenBefore = neighbors(of: target, in: game).filter {
            game.board[$0].state == .hidden
        }
        XCTAssertFalse(hiddenBefore.isEmpty, "test needs at least one hidden neighbour to open")

        game.chord(target, using: &rng)

        XCTAssertNotEqual(game.status, .lost, "chording correctly-flagged cell must not lose")
        for h in hiddenBefore {
            XCTAssertEqual(game.board[h].state, .revealed, "chord should have opened \(h)")
        }
    }

    /// Chording does nothing when the flag count doesn't match the number.
    func testChordNoOpWhenFlagsInsufficient() {
        var game = Game(difficulty: .beginner)
        var rng = SeededRNG(seed: 9)
        game.reveal(Coord(4, 4), using: &rng)

        guard let target = revealedNumberWithAllMineNeighborsKnown(in: game) else {
            XCTFail("no suitable numbered cell"); return
        }
        // No flags placed → chord must be a no-op.
        let snapshot = game.board.allCoords.map { game.board[$0].state }
        game.chord(target, using: &rng)
        let after = game.board.allCoords.map { game.board[$0].state }
        XCTAssertEqual(snapshot, after, "chord with too few flags must change nothing")
    }

    /// Chording is a no-op on a cell that isn't a revealed number.
    func testChordNoOpOnHiddenCell() {
        var game = Game(difficulty: .beginner)
        var rng = SeededRNG(seed: 9)
        game.reveal(Coord(4, 4), using: &rng)
        let hidden = game.board.allCoords.first { game.board[$0].state == .hidden }!
        let snapshot = game.board.allCoords.map { game.board[$0].state }
        game.chord(hidden, using: &rng)
        let after = game.board.allCoords.map { game.board[$0].state }
        XCTAssertEqual(snapshot, after, "chord on a hidden cell must change nothing")
    }

    /// Mis-flagging then chording reveals a real mine → the game is lost.
    func testChordLosesWhenAWrongFlagHidesAMine() throws {
        var game = Game(difficulty: .beginner)
        var rng = SeededRNG(seed: 9)
        game.reveal(Coord(4, 4), using: &rng)

        guard let target = revealedNumberWithAllMineNeighborsKnown(in: game) else {
            XCTFail("no suitable numbered cell"); return
        }
        let ns = neighbors(of: target, in: game)
        let mineNeighbors = ns.filter { game.board[$0].isMine }
        let safeHidden = ns.filter { game.board[$0].state == .hidden && !game.board[$0].isMine }
        guard !mineNeighbors.isEmpty, !safeHidden.isEmpty else {
            throw XCTSkip("seed didn't produce a mine + safe hidden neighbour pair")
        }
        // Flag the right *count* but the wrong cells: flag a safe cell instead
        // of (one of) the mines, so a mine stays unflagged and chord hits it.
        game.toggleFlag(safeHidden[0])
        for m in mineNeighbors.dropFirst() { game.toggleFlag(m) }

        // Flag count now equals the number, but a mine is unflagged.
        game.chord(target, using: &rng)
        XCTAssertEqual(game.status, .lost, "chording over an unflagged mine must lose")
    }

    // MARK: Helpers

    private func neighbors(of c: Coord, in game: Game) -> [Coord] {
        BoundedSquareTopology(width: 9, height: 9).neighbors(of: c)
    }

    /// A revealed cell with adjacentMines > 0 that has at least one hidden
    /// neighbour, so a chord has something to do.
    private func revealedNumberWithAllMineNeighborsKnown(in game: Game) -> Coord? {
        game.board.allCoords.first { c in
            guard game.board[c].state == .revealed, game.board[c].adjacentMines > 0 else {
                return false
            }
            return neighbors(of: c, in: game).contains { game.board[$0].state == .hidden }
        }
    }
}
