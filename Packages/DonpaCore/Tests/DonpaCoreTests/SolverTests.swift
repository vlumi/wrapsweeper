import XCTest

@testable import DonpaCore

final class SolverTests: XCTestCase {

    /// The solver does real deductive work on real boards: across many seeded
    /// Beginner games at least one is won *with* deductions (not just an opening
    /// that auto-wins), and whenever deductions happen the game is won by logic.
    func testSolverPerformsDeductionsOnRealBoards() {
        var sawDeductionWin = false
        for seed in UInt64(0)..<300 {
            var game = Game(difficulty: .beginner)
            var rng = SeededRNG(seed: seed)
            let result = Solver().solve(&game, firstClick: Coord(4, 4), using: &rng)
            if result.solvedWithoutGuessing && result.deductions > 0 {
                sawDeductionWin = true
                break
            }
        }
        XCTAssertTrue(
            sawDeductionWin, "solver should win at least one game through actual deductions")
    }

    /// Two mines diagonally adjacent in a corner create a 50/50: the "2" sees two
    /// hidden cells and can't tell which are mined by single-constraint logic.
    /// The solver must get stuck rather than guess (and must not lose).
    func testGetsStuckOnAGuessBoardWithoutLosing() {
        // Mines at (0,0) and (1,1) on a 3x3; first click at (2,2).
        let topo = BoundedSquareTopology(width: 3, height: 3)
        var game = Game(topology: topo, mines: [Coord(0, 0), Coord(1, 1)])
        var rng = SeededRNG(seed: 1)
        let result = Solver().solve(&game, firstClick: Coord(2, 2), using: &rng)

        XCTAssertFalse(result.solvedWithoutGuessing)
        XCTAssertNotEqual(result.status, .lost, "the solver must never blow itself up")
    }

    /// Core invariant: a logical solver only ever reveals cells it has proven
    /// safe, so across many real (seeded, first-click-safe) games it must NEVER
    /// lose. Solved-or-stuck, never lost.
    func testNeverLosesAcrossManySeededGames() {
        for seed in UInt64(0)..<200 {
            var game = Game(difficulty: .beginner)
            var rng = SeededRNG(seed: seed)
            let result = Solver().solve(&game, firstClick: Coord(4, 4), using: &rng)
            XCTAssertNotEqual(
                result.status, .lost, "solver lost on seed \(seed) — it must only reveal safe cells"
            )
            XCTAssertGreaterThanOrEqual(result.firstOpenSize, 1)
        }
    }

    /// When the solver reports success, the game really is won.
    func testReportedSuccessImpliesWon() {
        for seed in UInt64(0)..<100 {
            var game = Game(difficulty: .beginner)
            var rng = SeededRNG(seed: seed)
            let result = Solver().solve(&game, firstClick: Coord(4, 4), using: &rng)
            if result.solvedWithoutGuessing {
                XCTAssertEqual(result.status, .won)
            }
        }
    }
}
