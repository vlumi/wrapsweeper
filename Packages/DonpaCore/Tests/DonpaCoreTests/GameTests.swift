import XCTest

@testable import DonpaCore

final class GameTests: XCTestCase {

    // MARK: First-click safety + flood-fill

    func testFirstClickAlwaysOpensARegion() {
        // The clicked cell must end up revealed and be a 0 (so a region opens).
        for seed in UInt64(0)..<100 {
            var game = Game(difficulty: .beginner)
            var rng = SeededRNG(seed: seed)
            let click = Coord(4, 4)
            game.reveal(click, using: &rng)
            XCTAssertEqual(game.board[click].state, .revealed)
            XCTAssertEqual(
                game.board[click].adjacentMines, 0,
                "seed \(seed): first click was not a 0")
            XCTAssertNotEqual(game.status, .lost)
            // A 0-opening reveals more than one cell.
            let revealed = game.board.allCoords.filter { game.board[$0].state == .revealed }.count
            XCTAssertGreaterThan(revealed, 1, "seed \(seed): no region opened")
        }
    }

    /// The pre-armed path: mines are placed BEFORE the first click (no safe zone),
    /// then the first reveal relocates any under the click. The same first-click
    /// safety guarantee must hold — clicked cell is a 0, opens a region, never a loss.
    func testPreArmedFirstClickAlsoOpensARegion() {
        for seed in UInt64(0)..<100 {
            var game = Game(difficulty: .beginner)
            var rng = SeededRNG(seed: seed)
            game.placeMinesEagerly(using: &rng)  // armed with no safe zone
            XCTAssertEqual(game.board.mineCoords.count, game.mineCount, "all mines placed")
            let click = Coord(4, 4)
            game.reveal(click, using: &rng)  // relocates the safe zone, then opens
            XCTAssertNotEqual(game.status, .lost, "seed \(seed): pre-armed first click lost")
            XCTAssertEqual(
                game.board[click].adjacentMines, 0, "seed \(seed): first click not a 0")
            XCTAssertEqual(
                game.board.mineCoords.count, game.mineCount, "relocation preserves mine count")
            let revealed = game.board.allCoords.filter { game.board[$0].state == .revealed }.count
            XCTAssertGreaterThan(revealed, 1, "seed \(seed): no region opened")
        }
    }

    func testFloodFillStopsAtNumbers() {
        var game = Game(difficulty: .beginner)
        var rng = SeededRNG(seed: 3)
        game.reveal(Coord(4, 4), using: &rng)
        // Every revealed cell is either a 0 or borders the opened 0-region;
        // no mine should ever be revealed by a safe flood-fill.
        for c in game.board.allCoords where game.board[c].state == .revealed {
            XCTAssertFalse(game.board[c].isMine, "flood-fill revealed a mine at \(c)")
        }
    }

    // MARK: Lose

    func testRevealingMineLoses() {
        var game = Game(difficulty: .beginner)
        var rng = SeededRNG(seed: 5)
        game.reveal(Coord(0, 0), using: &rng)  // place mines + start
        // Find a mine and reveal it.
        let mine = game.board.allCoords.first { game.board[$0].isMine }!
        game.reveal(mine, using: &rng)
        XCTAssertEqual(game.status, .lost)
        XCTAssertEqual(game.board[mine].state, .revealed)
    }

    // MARK: Win

    func testRevealingAllSafeCellsWins() {
        var game = Game(difficulty: .beginner)
        var rng = SeededRNG(seed: 9)
        game.reveal(Coord(4, 4), using: &rng)
        // Reveal every non-mine cell; the game must end in .won and not .lost.
        for c in game.board.allCoords where !game.board[c].isMine {
            game.reveal(c, using: &rng)
        }
        XCTAssertEqual(game.status, .won)
    }

    // MARK: Flagging

    func testFlagToggle() {
        var game = Game(difficulty: .beginner)
        var rng = SeededRNG(seed: 2)
        game.reveal(Coord(4, 4), using: &rng)
        let target = game.board.allCoords.first { game.board[$0].state == .hidden }!
        XCTAssertEqual(game.flagsRemaining, 10)
        game.toggleFlag(target)
        XCTAssertEqual(game.board[target].state, .flagged)
        XCTAssertEqual(game.flagsRemaining, 9)
        game.toggleFlag(target)
        XCTAssertEqual(game.board[target].state, .hidden)
    }

    func testCannotRevealFlaggedCell() {
        var game = Game(difficulty: .beginner)
        var rng = SeededRNG(seed: 2)
        game.reveal(Coord(4, 4), using: &rng)
        let target = game.board.allCoords.first { game.board[$0].state == .hidden }!
        game.toggleFlag(target)
        game.reveal(target, using: &rng)
        XCTAssertEqual(game.board[target].state, .flagged, "flagged cell must resist reveal")
    }

    // MARK: Epic-readiness — identical logic on a wrapped torus

    func testGameLogicRunsUnchangedOnWrappedTopology() {
        // The whole point of the Topology seam: Game needs zero changes to play
        // on a torus. Play a full game to a win on a wrapped board.
        let t = WrappedSquareTopology(width: 9, height: 9)
        var game = Game(topology: t, mineCount: 10)
        var rng = SeededRNG(seed: 11)
        let click = Coord(4, 4)
        game.reveal(click, using: &rng)
        XCTAssertEqual(
            game.board[click].adjacentMines, 0,
            "first click on torus must still be a 0")
        XCTAssertNotEqual(game.status, .lost)
        for c in game.board.allCoords where !game.board[c].isMine {
            game.reveal(c, using: &rng)
        }
        XCTAssertEqual(game.status, .won, "wrapped game should be winnable with unchanged logic")
    }

    func testGameLogicRunsUnchangedOnHexTopology() {
        // Same seam, second geometry: a 6-neighbour hex board plays with zero
        // game-logic changes. Play a full game to a win.
        let t = HexTopology(width: 9, height: 9)
        var game = Game(topology: t, mineCount: 10)
        var rng = SeededRNG(seed: 11)
        let click = Coord(4, 4)
        game.reveal(click, using: &rng)
        XCTAssertEqual(
            game.board[click].adjacentMines, 0,
            "first click on hex must still open a 0")
        XCTAssertNotEqual(game.status, .lost)
        for c in game.board.allCoords where !game.board[c].isMine {
            game.reveal(c, using: &rng)
        }
        XCTAssertEqual(game.status, .won, "hex game should be winnable with unchanged logic")
    }

    /// On a wrapped topology `normalize` never fails, so actions must FOLD a raw
    /// off-board coord onto the board — not index phantom cells with it (which
    /// silently discards writes and can double-count reveals).
    func testWrappedActionsFoldOffBoardCoords() {
        let t = WrappedSquareTopology(width: 9, height: 9)
        var game = Game(topology: t, mineCount: 10)
        var rng = SeededRNG(seed: 11)
        game.reveal(Coord(4, 4), using: &rng)

        // Flag through the seam: (-1, y) is (8, y) on the torus.
        guard let y = (0..<9).first(where: { game.board[Coord(8, $0)].state == .hidden }) else {
            return XCTFail("no hidden cell in the last column for seed")
        }
        game.toggleFlag(Coord(-1, y))
        XCTAssertEqual(game.board[Coord(8, y)].state, .flagged, "flag folds onto the board")
        game.toggleFlag(Coord(-1, y))  // unflag for the reveal below

        // Reveal through the seam: the folded cell changes state, and the derived
        // progress counter matches the board (no phantom increment).
        guard
            let y2 = (0..<9).first(where: {
                game.board[Coord(8, $0)].state == .hidden && !game.board[Coord(8, $0)].isMine
            })
        else {
            return XCTFail("no hidden safe cell in the last column for seed")
        }
        game.reveal(Coord(-1, y2), using: &rng)
        XCTAssertEqual(game.board[Coord(8, y2)].state, .revealed, "reveal folds onto the board")
        XCTAssertEqual(
            game.revealedSafeCount, game.board.revealedSafeCount,
            "counter must track real cells, never a phantom")
    }

    func testGameLogicRunsUnchangedOnWrappedHexTopology() {
        // Both seams at once: a 6-neighbour hex board whose edges wrap. Even height
        // (8) is required for a consistent hex torus. Play a full game to a win.
        let t = WrappedHexTopology(width: 8, height: 8)
        var game = Game(topology: t, mineCount: 8)
        var rng = SeededRNG(seed: 7)
        let click = Coord(4, 4)
        game.reveal(click, using: &rng)
        XCTAssertNotEqual(game.status, .lost)
        for c in game.board.allCoords where !game.board[c].isMine {
            game.reveal(c, using: &rng)
        }
        XCTAssertEqual(
            game.status, .won, "wrapped-hex game should be winnable with unchanged logic")
    }

    // MARK: changeToken — cheap "did anything change" fingerprint

    /// The token must move when a reveal opens cells and when a flag toggles — the
    /// mutations a redraw/save cares about.
    func testChangeTokenMovesOnRealMutations() {
        var game = Game(difficulty: .beginner)
        var rng = SeededRNG(seed: 1)

        let t0 = game.changeToken
        game.reveal(Coord(4, 4), using: &rng)  // first click opens a region
        let tReveal = game.changeToken
        XCTAssertNotEqual(tReveal, t0, "a reveal changes the token")

        let hidden = game.board.allCoords.first { game.board[$0].state == .hidden }!
        game.toggleFlag(hidden)
        XCTAssertNotEqual(game.changeToken, tReveal, "a flag toggle changes the token")
    }

    /// The point of the token: a no-op chord (number whose flag count doesn't match)
    /// mutates nothing, so the token is identical — letting the VM skip the
    /// redraw/autosave/minimap-rebuild it would otherwise trigger.
    func testChangeTokenStableAcrossNoOpChord() {
        var game = Game(difficulty: .beginner)
        var rng = SeededRNG(seed: 2)
        game.reveal(Coord(4, 4), using: &rng)
        // A revealed number with NO flags around it: chording it can't satisfy the
        // count, so it does nothing.
        guard
            let numbered = game.board.allCoords.first(where: {
                game.board[$0].state == .revealed && game.board[$0].adjacentMines > 0
            })
        else { return XCTFail("no numbered revealed cell after the opening") }

        let before = game.changeToken
        game.chord(numbered, using: &rng)  // no flags placed → inert
        XCTAssertEqual(game.changeToken, before, "a no-op chord must not move the token")
    }
}
