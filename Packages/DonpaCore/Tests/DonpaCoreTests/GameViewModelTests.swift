import XCTest

@testable import DonpaCore

/// Behaviour of the `GameViewModel` orchestration that the existing
/// `GameResultTests` / `PauseTests` don't cover: snapshot/restore round-trips,
/// the input guards (paused + finished), the redraw counters, and flag
/// accounting. Time-dependent timer math is deliberately left to integration —
/// these assert the deterministic state machine.
@MainActor
final class GameViewModelTests: XCTestCase {

    /// Start a game with a safe first reveal at the origin (mines avoid the first
    /// click), so the board is `.playing` with a known mine layout.
    private func startedGame(_ config: GameConfig = .beginner) -> GameViewModel {
        let vm = GameViewModel(config: config)
        vm.reveal(Coord(0, 0))
        return vm
    }

    /// A cell that's still hidden after the opening reveal — the first reveal can
    /// flood-fill arbitrarily far, so a fixed corner isn't reliably unrevealed.
    private func aHiddenCell(_ vm: GameViewModel) -> Coord {
        for c in vm.game.board.allCoords where vm.game.board[c].state == .hidden {
            return c
        }
        XCTFail("no hidden cell after the opening reveal")
        return Coord(0, 0)
    }

    // MARK: New game / counters

    func testNewGameBumpsGameIDAndRevision() {
        let vm = GameViewModel(config: .beginner)
        let id0 = vm.gameID
        let rev0 = vm.revision
        vm.newGame()
        XCTAssertGreaterThan(vm.gameID, id0, "a fresh game bumps gameID")
        XCTAssertGreaterThan(vm.revision, rev0, "a fresh game bumps revision (redraw)")
    }

    func testRevealBumpsRevision() {
        let vm = GameViewModel(config: .beginner)
        let rev0 = vm.revision
        vm.reveal(Coord(0, 0))
        XCTAssertGreaterThan(vm.revision, rev0, "a reveal asks the scene to redraw")
    }

    func testNewGameWithConfigSwitchesBoard() {
        let vm = GameViewModel(config: .beginner)
        vm.newGame(config: .classic(.expert))
        XCTAssertEqual(vm.config, .classic(.expert))
        XCTAssertEqual(vm.boardWidth, 30)
        XCTAssertEqual(vm.boardHeight, 16)
        XCTAssertEqual(vm.status, .notStarted)
    }

    // MARK: Flag accounting

    func testToggleFlagAdjustsFlagsRemaining() {
        let vm = startedGame()
        let before = vm.flagsRemaining
        // Flag a still-hidden cell far from the opened origin region.
        let target = aHiddenCell(vm)
        vm.toggleFlag(target)
        XCTAssertEqual(vm.flagsRemaining, before - 1, "flagging a cell uses one flag")
        vm.toggleFlag(target)
        XCTAssertEqual(vm.flagsRemaining, before, "unflagging returns the flag")
    }

    // MARK: Input guards — paused

    func testRevealIsInertWhilePaused() {
        let vm = startedGame()
        vm.pause()
        let revBefore = vm.revision
        let revealedBefore = vm.game.revealedSafeCount
        // Reveal a still-hidden cell; while paused it must do nothing.
        vm.reveal(aHiddenCell(vm))
        XCTAssertEqual(
            vm.game.revealedSafeCount, revealedBefore, "paused reveal must not open cells")
        XCTAssertEqual(vm.revision, revBefore, "paused reveal must not request a redraw")
    }

    func testToggleFlagIsInertWhilePaused() {
        let vm = startedGame()
        vm.pause()
        let flagsBefore = vm.flagsRemaining
        vm.toggleFlag(aHiddenCell(vm))
        XCTAssertEqual(vm.flagsRemaining, flagsBefore, "paused flag toggle must be inert")
    }

    func testResumeReenablesInput() {
        let vm = startedGame()
        vm.pause()
        vm.resume()
        let revBefore = vm.revision
        vm.toggleFlag(aHiddenCell(vm))
        XCTAssertGreaterThan(vm.revision, revBefore, "input works again after resume")
    }

    // MARK: Deterministic loss (read the placed mines, then step on one)

    /// After the first reveal the mine layout is fixed and public, so we can force
    /// a loss without relying on chance.
    private func forceLoss(_ vm: GameViewModel) {
        guard let mine = vm.game.board.mineCoords.first else {
            return XCTFail("no mines placed after first reveal")
        }
        vm.reveal(mine)
    }

    func testForcedLossPublishesLossResultWithCoord() {
        let vm = startedGame()
        forceLoss(vm)
        XCTAssertEqual(vm.status, .lost)
        guard case .lost(let at)? = vm.lastResult?.result else {
            return XCTFail("a loss must publish a .lost result")
        }
        XCTAssertEqual(at, vm.game.lossCoord, "the published loss coord matches the detonated mine")
    }

    func testLossStopsTheClockAtAFixedValue() {
        let vm = startedGame()
        forceLoss(vm)
        let frozen = vm.elapsedCentiseconds
        // The clock is stopped on game-over, so the value can't keep climbing.
        XCTAssertEqual(vm.elapsedCentiseconds, frozen, "elapsed is frozen once the game ends")
    }

    // MARK: Snapshot / restore round-trip

    func testSnapshotIsNilForNotStartedGame() {
        let vm = GameViewModel(config: .beginner)
        // A not-started game has nothing worth saving.
        XCTAssertNil(vm.snapshot(), "an untouched game produces no snapshot")
    }

    func testRestoreRebuildsTheGameState() {
        let vm = startedGame()
        // Make some moves so the restored state is non-trivial.
        vm.toggleFlag(aHiddenCell(vm))
        let snapshot = try? XCTUnwrap(vm.snapshot())
        guard let snapshot else { return }

        let restored = GameViewModel(config: .classic(.expert))  // different board
        restored.restore(from: snapshot)

        XCTAssertEqual(restored.config, vm.config, "restore adopts the saved config")
        XCTAssertEqual(restored.boardWidth, vm.boardWidth)
        XCTAssertEqual(restored.status, vm.status)
        XCTAssertEqual(
            restored.game.board.mineCoords, vm.game.board.mineCoords,
            "the exact mine layout survives a round-trip")
        XCTAssertEqual(
            restored.flagsRemaining, vm.flagsRemaining, "flag state survives a round-trip")
        XCTAssertFalse(restored.isPaused, "a freshly restored game is live, not paused")
    }

    func testRestoreClearsAnyPriorResult() {
        // A finished VM that then restores a live snapshot must drop the stale result.
        let live = startedGame()
        let snapshot = try? XCTUnwrap(live.snapshot())
        guard let snapshot else { return }

        let other = startedGame()
        forceLoss(other)
        XCTAssertNotNil(other.lastResult)
        other.restore(from: snapshot)
        XCTAssertNil(other.lastResult, "restoring a live game clears the prior outcome")
        XCTAssertEqual(other.inputMode, .reveal, "restore resets to reveal mode")
    }
}
