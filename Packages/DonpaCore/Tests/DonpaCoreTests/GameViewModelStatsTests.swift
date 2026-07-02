import XCTest

@testable import DonpaCore

/// The stat-accuracy behaviour of `GameViewModel`: the no-flag / no-chord purity
/// bits and the chord/flag counters that feed the lifetime stats. Split from
/// `GameViewModelTests` (which covers the state machine) — these guard the rule
/// that a NO-OP input never counts as an action.
@MainActor
final class GameViewModelStatsTests: XCTestCase {

    /// Start a game with a safe first reveal at the origin (mines avoid the first
    /// click), so the board is `.playing` with a known mine layout.
    private func startedGame(_ config: GameConfig = .beginner) async -> GameViewModel {
        let vm = GameViewModel(config: config)
        vm.reveal(Coord(0, 0))
        await vm.awaitPendingWork()
        return vm
    }

    /// A cell that's still hidden after the opening reveal.
    private func aHiddenCell(_ vm: GameViewModel) -> Coord {
        for c in vm.game.board.allCoords where vm.game.board[c].state == .hidden {
            return c
        }
        XCTFail("no hidden cell after the opening reveal")
        return Coord(0, 0)
    }

    /// The purity bits start clean; flags LATCH on first placement. Chord stats
    /// count ONLY a chord that actually acts — the UI routes every tap on a
    /// revealed cell through `chord`, so no-op taps (a hidden cell, a revealed
    /// 0-cell) must not inflate the count or burn the no-chord feat.
    func testPurityBitsLatchAndChordCounts() async {
        let vm = await startedGame()
        XCTAssertFalse(vm.usedFlagEver, "clean at start")
        XCTAssertFalse(vm.usedChordEver)
        XCTAssertEqual(vm.chordsThisGame, 0)

        let target = aHiddenCell(vm)
        vm.toggleFlag(target)
        vm.toggleFlag(target)  // unflag — still "used flags"
        XCTAssertTrue(vm.usedFlagEver, "latches on first placement, not cleared by unflag")

        // No-op chords: a hidden cell, and the revealed 0 under the first click.
        vm.chord(aHiddenCell(vm))
        vm.chord(Coord(0, 0))
        await vm.awaitPendingWork()
        XCTAssertFalse(vm.usedChordEver, "no-op taps must not count as chording")
        XCTAssertEqual(vm.chordsThisGame, 0)

        // A real chord: flag every mine neighbour of a suitable revealed number,
        // then chord it — this one counts.
        guard let (number, mines) = chordableNumber(vm) else {
            return XCTFail("no chordable number on this board")
        }
        for m in mines { vm.toggleFlag(m) }
        vm.chord(number)
        await vm.awaitPendingWork()
        XCTAssertTrue(vm.usedChordEver, "an acting chord latches")
        XCTAssertEqual(vm.chordsThisGame, 1)
    }

    /// A revealed number whose hidden neighbours include all its mines (so exact
    /// flagging is possible) and at least one safe cell (so the chord will act).
    private func chordableNumber(_ vm: GameViewModel) -> (Coord, [Coord])? {
        let board = vm.game.board
        for c in board.allCoords
        where board[c].state == .revealed && board[c].adjacentMines > 0 {
            let ns = board.topology.neighbors(of: c)
            let hiddenMines = ns.filter { board[$0].state == .hidden && board[$0].isMine }
            let hiddenSafe = ns.filter { board[$0].state == .hidden && !board[$0].isMine }
            guard hiddenMines.count == board[c].adjacentMines, !hiddenSafe.isEmpty else {
                continue
            }
            return (c, hiddenMines)
        }
        return nil
    }

    /// Flagging a revealed cell is a no-op all the way down: no latch, and no
    /// revision bump (a bump would schedule a full-board autosave + redraw for
    /// every stray right-click on opened ground).
    func testFlaggingARevealedCellChangesNothing() async {
        let vm = await startedGame()
        let before = vm.revision
        vm.toggleFlag(Coord(0, 0))  // the revealed first-click cell
        XCTAssertEqual(vm.revision, before, "no state change → no bump")
        XCTAssertFalse(vm.usedFlagEver)
        XCTAssertEqual(vm.flagsPlacedThisGame, 0)
    }

    /// A new game resets the purity bits to clean; a RESTORE defaults them to
    /// violated (a resumed game can't prove a clean run, so it can't earn the feat).
    func testPurityBitsResetOnNewGameAndViolatedOnRestore() async {
        let vm = await startedGame()
        vm.toggleFlag(aHiddenCell(vm))
        XCTAssertTrue(vm.usedFlagEver)

        vm.newGame()
        XCTAssertFalse(vm.usedFlagEver, "a fresh game is clean")
        XCTAssertFalse(vm.usedChordEver)
        XCTAssertEqual(vm.chordsThisGame, 0)

        // Restore defaults to violated (deny over false-award).
        let started = await startedGame()
        let snapshot = started.snapshot()!
        vm.restore(from: snapshot)
        XCTAssertTrue(vm.usedFlagEver, "restore can't prove a clean run → violated")
        XCTAssertTrue(vm.usedChordEver)
    }
}
