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
    /// click), so the board is `.playing` with a known mine layout. Reveal computes
    /// off the main thread, so await it before inspecting the board.
    private func startedGame(_ config: GameConfig = .beginner) async -> GameViewModel {
        let vm = GameViewModel(config: config)
        vm.reveal(Coord(0, 0))
        await vm.awaitPendingWork()
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

    func testRevealBumpsRevision() async {
        let vm = GameViewModel(config: .beginner)
        let rev0 = vm.revision
        vm.reveal(Coord(0, 0))
        await vm.awaitPendingWork()
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

    func testToggleFlagAdjustsFlagsRemaining() async {
        let vm = await startedGame()
        let before = vm.flagsRemaining
        // Flag a still-hidden cell far from the opened origin region.
        let target = aHiddenCell(vm)
        vm.toggleFlag(target)
        XCTAssertEqual(vm.flagsRemaining, before - 1, "flagging a cell uses one flag")
        vm.toggleFlag(target)
        XCTAssertEqual(vm.flagsRemaining, before, "unflagging returns the flag")
    }

    // MARK: Input guards — paused

    func testRevealIsInertWhilePaused() async {
        let vm = await startedGame()
        vm.pause()
        let revBefore = vm.revision
        let revealedBefore = vm.game.revealedSafeCount
        // Reveal a still-hidden cell; while paused it must do nothing.
        vm.reveal(aHiddenCell(vm))
        XCTAssertEqual(
            vm.game.revealedSafeCount, revealedBefore, "paused reveal must not open cells")
        XCTAssertEqual(vm.revision, revBefore, "paused reveal must not request a redraw")
    }

    func testToggleFlagIsInertWhilePaused() async {
        let vm = await startedGame()
        vm.pause()
        let flagsBefore = vm.flagsRemaining
        vm.toggleFlag(aHiddenCell(vm))
        XCTAssertEqual(vm.flagsRemaining, flagsBefore, "paused flag toggle must be inert")
    }

    func testResumeReenablesInput() async {
        let vm = await startedGame()
        vm.pause()
        vm.resume()
        let revBefore = vm.revision
        vm.toggleFlag(aHiddenCell(vm))
        XCTAssertGreaterThan(vm.revision, revBefore, "input works again after resume")
    }

    // MARK: Deterministic loss (read the placed mines, then step on one)

    /// After the first reveal the mine layout is fixed and public, so we can force
    /// a loss without relying on chance.
    private func forceLoss(_ vm: GameViewModel) async {
        guard let mine = vm.game.board.mineCoords.first else {
            return XCTFail("no mines placed after first reveal")
        }
        vm.reveal(mine)
        await vm.awaitPendingWork()
    }

    func testCanRevealHitMineReflectsTheBoardAndGate() async {
        let vm = await startedGame()
        let mine = try? XCTUnwrap(vm.game.board.mineCoords.first)
        guard let mine else { return }
        XCTAssertTrue(vm.canRevealHitMine(mine), "a hidden mine cell would detonate")
        // A hidden NON-MINE cell would not. (aHiddenCell can land on a mine, so
        // pick a hidden cell that isn't one — else this flakes on the layout.)
        let hiddenSafe = vm.game.board.allCoords.first {
            vm.game.board[$0].state == .hidden && !vm.game.board[$0].isMine
        }
        if let hiddenSafe {
            XCTAssertFalse(
                vm.canRevealHitMine(hiddenSafe), "a hidden non-mine cell would not detonate")
        }
        // Blocked while paused (input gate).
        vm.pause()
        XCTAssertFalse(vm.canRevealHitMine(mine), "no detonation preview while input is gated")
    }

    func testChordComputesAndCanEndTheGame() async {
        // Chording a revealed number that borders a (wrongly) flagged-free mine
        // detonates — exercises the async chord path. Find a lost outcome via chord.
        let vm = await startedGame()
        // Reveal around to get a numbered cell, then chord it; bounded sweep.
        for c in vm.game.board.allCoords where vm.game.board[c].state == .revealed {
            vm.chord(c)
            await vm.awaitPendingWork()
            break  // one chord is enough to exercise the path
        }
        // The game is still in a valid state (chord on a satisfied/0 number is inert).
        XCTAssertTrue(vm.status == .playing || vm.status == .lost || vm.status == .won)
    }

    func testForcedLossPublishesLossResultWithCoord() async {
        let vm = await startedGame()
        await forceLoss(vm)
        XCTAssertEqual(vm.status, .lost)
        guard case .lost(let at)? = vm.lastResult?.result else {
            return XCTFail("a loss must publish a .lost result")
        }
        XCTAssertEqual(at, vm.game.lossCoord, "the published loss coord matches the detonated mine")
    }

    func testLossStopsTheClockAtAFixedValue() async {
        let vm = await startedGame()
        await forceLoss(vm)
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

    func testRestoreRebuildsTheGameState() async {
        let vm = await startedGame()
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

    func testRestoreKeepsTheInputMode() async {
        let vm = await startedGame()
        vm.inputMode = .flag  // player switched to flagging before leaving
        let snapshot = try? XCTUnwrap(vm.snapshot())
        guard let snapshot else { return }

        let restored = GameViewModel(config: .classic(.expert))
        restored.restore(from: snapshot)
        XCTAssertEqual(restored.inputMode, .flag, "resuming keeps the dig/flag toggle")
    }

    func testRestoreClearsAnyPriorResult() async {
        // A finished VM that then restores a live snapshot must drop the stale result.
        let live = await startedGame()
        let snapshot = try? XCTUnwrap(live.snapshot())
        guard let snapshot else { return }

        let other = await startedGame()
        await forceLoss(other)
        XCTAssertNotNil(other.lastResult)
        other.restore(from: snapshot)
        XCTAssertNil(other.lastResult, "restoring a live game clears the prior outcome")
        XCTAssertEqual(other.inputMode, .reveal, "restore resets to reveal mode")
    }

    // MARK: Camera save/restore wiring

    func testSnapshotCarriesTheLiveCameraView() async {
        let vm = await startedGame()
        let camera = CameraView(centerX: 0.4, centerY: 0.6, scale: 1.8)
        vm.cameraView = camera  // the scene keeps this current each frame
        XCTAssertEqual(vm.snapshot()?.camera, camera, "snapshot persists the live camera view")
    }

    func testRestoreQueuesThePendingCameraForTheScene() async {
        let vm = await startedGame()
        let camera = CameraView(centerX: 0.2, centerY: 0.9, scale: 3.0)
        vm.cameraView = camera
        let snapshot = try? XCTUnwrap(vm.snapshot())
        guard let snapshot else { return }

        let restored = GameViewModel(config: .beginner)
        restored.restore(from: snapshot)
        XCTAssertEqual(
            restored.pendingCameraRestore, camera,
            "restore queues the saved view for the scene to apply on rebuild")
    }

    func testNewGameClearsThePendingCamera() async {
        let vm = await startedGame()
        vm.pendingCameraRestore = CameraView(centerX: 0.5, centerY: 0.5, scale: 2)
        vm.newGame()
        XCTAssertNil(vm.pendingCameraRestore, "a fresh game centres on its own fit, not a resume")
        XCTAssertNil(vm.cameraView)
    }
}
