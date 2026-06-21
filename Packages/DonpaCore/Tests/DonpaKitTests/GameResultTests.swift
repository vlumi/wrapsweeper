import DonpaCore
import XCTest

@testable import DonpaKit

@MainActor
final class GameResultTests: XCTestCase {

    /// Play a board to its end and return the view model once finished.
    private func playToEnd(_ vm: GameViewModel) {
        // First reveal at the centre starts the game; then reveal cells until it
        // ends (win or loss). Bounded by the cell count so it always terminates.
        let w = vm.boardWidth
        let h = vm.boardHeight
        vm.reveal(Coord(w / 2, h / 2))
        var guardCount = 0
        outer: while vm.status == .playing && guardCount < w * h * 2 {
            for y in 0..<h {
                for x in 0..<w {
                    guardCount += 1
                    vm.reveal(Coord(x, y))
                    if vm.status != .playing { break outer }
                }
            }
        }
    }

    func testNoResultWhilePlaying() {
        let vm = GameViewModel(config: .classic(.beginner))
        vm.reveal(Coord(4, 4))
        // After one reveal the game is either still playing or ended; if still
        // playing there must be no result yet.
        if vm.status == .playing {
            XCTAssertNil(vm.lastResult)
        }
    }

    func testResultMatchesFinalStatus() {
        let vm = GameViewModel(config: .classic(.beginner))
        playToEnd(vm)
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

    func testLostResultCarriesTheLossCoord() {
        // Try several games until one is lost, then assert the coord matches.
        for _ in 0..<50 {
            let vm = GameViewModel(config: .classic(.beginner))
            playToEnd(vm)
            if case .lost(let at)? = vm.lastResult?.result {
                XCTAssertEqual(at, vm.game.lossCoord)
                return
            }
        }
        // Extremely unlikely to never lose across 50 full sweeps; not a failure
        // of the feature if it happens, so just succeed.
    }

    func testNewGameClearsTheResult() {
        let vm = GameViewModel(config: .classic(.beginner))
        playToEnd(vm)
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

    func testResultIDIncrementsPerGame() {
        let vm = GameViewModel(config: .classic(.beginner))
        playToEnd(vm)
        let firstID = vm.lastResult?.id
        vm.newGame()
        playToEnd(vm)
        let secondID = vm.lastResult?.id
        XCTAssertNotNil(firstID)
        XCTAssertNotNil(secondID)
        XCTAssertGreaterThan(secondID!, firstID!, "each finished game gets a fresh result id")
    }
}
