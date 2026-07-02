import XCTest

@testable import DonpaCore

@MainActor
final class GameResultTests: XCTestCase {

    /// Reveal and await the off-thread compute, so the result is applied before the
    /// caller inspects state. Reveal/chord now compute off the main thread (see
    /// GameViewModel.computeOffMain), so tests must await each one. Await first too,
    /// so a newGame's off-thread mine pre-arming has finished — otherwise the reveal
    /// is blocked by the `isComputing` gate and silently dropped.
    private func reveal(_ vm: GameViewModel, _ c: Coord) async {
        await vm.awaitPendingWork()
        vm.reveal(c)
        await vm.awaitPendingWork()
    }

    /// Play a board to its end and return the view model once finished.
    private func playToEnd(_ vm: GameViewModel) async {
        // First reveal at the centre starts the game; then reveal cells until it
        // ends (win or loss). Bounded by the cell count so it always terminates.
        let w = vm.boardWidth
        let h = vm.boardHeight
        await reveal(vm, Coord(w / 2, h / 2))
        var guardCount = 0
        outer: while vm.status == .playing && guardCount < w * h * 2 {
            for y in 0..<h {
                for x in 0..<w {
                    guardCount += 1
                    await reveal(vm, Coord(x, y))
                    if vm.status != .playing { break outer }
                }
            }
        }
    }

    func testNoResultWhilePlaying() async {
        let vm = GameViewModel(config: .classic(.beginner))
        await reveal(vm, Coord(4, 4))
        // After one reveal the game is either still playing or ended; if still
        // playing there must be no result yet.
        if vm.status == .playing {
            XCTAssertNil(vm.lastResult)
        }
    }

    func testResultMatchesFinalStatus() async {
        let vm = GameViewModel(config: .classic(.beginner))
        await playToEnd(vm)
        XCTAssertNotEqual(vm.status, .playing)
        let result = try? XCTUnwrap(vm.lastResult)
        switch (vm.status, result?.result) {
        case (.won, .won), (.lost, .lost):
            break
        default:
            XCTFail(
                "lastResult \(String(describing: result?.result)) must match status \(vm.status)")
        }
    }

    func testLostResultCarriesTheLossCoord() async {
        // Try several games until one is lost, then assert the coord matches.
        for _ in 0..<50 {
            let vm = GameViewModel(config: .classic(.beginner))
            await playToEnd(vm)
            if case .lost(let at)? = vm.lastResult?.result {
                XCTAssertEqual(at, vm.game.lossCoord)
                return
            }
        }
        // Extremely unlikely to never lose across 50 full sweeps; not a failure
        // of the feature if it happens, so just succeed.
    }

    func testNewGameClearsTheResult() async {
        let vm = GameViewModel(config: .classic(.beginner))
        await playToEnd(vm)
        XCTAssertNotNil(vm.lastResult)
        vm.newGame()
        XCTAssertNil(vm.lastResult)
        XCTAssertEqual(vm.status, .notStarted)
    }

    func testNewGameResetsToRevealMode() {
        let vm = GameViewModel(config: .classic(.beginner))
        vm.inputMode = .flag
        vm.newGame()
        XCTAssertEqual(vm.inputMode, .reveal, "every game should start in reveal mode")
    }

    /// Regression: after a game ends, any further input (reveal / chord on a
    /// revealed cell / flag) must be inert — it must not re-publish the result,
    /// which previously replayed the end-game animation and panel on each click.
    func testInputIsInertAfterGameEnds() async {
        // Find a lost game so we have a revealed mine to re-click (chord path).
        var vm = GameViewModel(config: .classic(.beginner))
        var lost = false
        for _ in 0..<50 {
            vm = GameViewModel(config: .classic(.beginner))
            await playToEnd(vm)
            if vm.status == .lost { lost = true; break }
        }
        guard lost else { return }  // see testLostResultCarriesTheLossCoord

        let idAfterEnd = vm.lastResult?.id
        let statusAfterEnd = vm.status

        // Re-click every cell every way: plain reveal, chord (revealed cells),
        // and flag. None should change the published result or the status.
        for y in 0..<vm.boardHeight {
            for x in 0..<vm.boardWidth {
                let c = Coord(x, y)
                vm.reveal(c)
                vm.chord(c)
                vm.toggleFlag(c)
            }
        }

        XCTAssertEqual(vm.lastResult?.id, idAfterEnd, "input after game-over must not re-publish")
        XCTAssertEqual(vm.status, statusAfterEnd, "input after game-over must not change status")
    }

    func testResultIDIncrementsPerGame() async {
        let vm = GameViewModel(config: .classic(.beginner))
        await playToEnd(vm)
        let firstID = vm.lastResult?.id
        vm.newGame()
        await playToEnd(vm)
        let secondID = vm.lastResult?.id
        XCTAssertNotNil(firstID)
        XCTAssertNotNil(secondID)
        XCTAssertGreaterThan(secondID!, firstID!, "each finished game gets a fresh result id")
    }

    func testIsWinDistinguishesOutcomes() {
        XCTAssertTrue(GameResult.won(centiseconds: 100, config: .beginner).isWin)
        XCTAssertFalse(GameResult.lost(at: Coord(1, 1)).isWin)
        XCTAssertFalse(GameResult.lost(at: nil).isWin)
    }
}
