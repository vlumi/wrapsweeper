import XCTest

@testable import DonpaCore

@MainActor
final class PauseTests: XCTestCase {
    /// Reveal a safe cell to move the game into `.playing` (mines avoid the
    /// first click, so some reveal is always safe).
    private func startedGame() -> GameViewModel {
        let vm = GameViewModel(config: .beginner)
        vm.reveal(Coord(0, 0))
        return vm
    }

    func testPauseOnlyWhilePlaying() {
        let vm = GameViewModel(config: .beginner)
        vm.pause()  // .notStarted → no-op
        XCTAssertFalse(vm.isPaused)

        let playing = startedGame()
        XCTAssertEqual(playing.status, .playing)
        playing.pause()
        XCTAssertTrue(playing.isPaused)
    }

    func testResumeClearsPaused() {
        let vm = startedGame()
        vm.pause()
        XCTAssertTrue(vm.isPaused)
        vm.resume()
        XCTAssertFalse(vm.isPaused)
    }

    func testDoublePauseIsIdempotent() {
        let vm = startedGame()
        vm.pause()
        vm.pause()
        XCTAssertTrue(vm.isPaused)
        vm.resume()
        XCTAssertFalse(vm.isPaused)
    }

    func testNewGameClearsPaused() {
        let vm = startedGame()
        vm.pause()
        vm.newGame()
        XCTAssertFalse(vm.isPaused)
        XCTAssertEqual(vm.elapsedCentiseconds, 0)
    }

    func testPauseDoesNotEndOrAlterTheGame() {
        let vm = startedGame()
        let before = vm.game.revealedSafeCount
        vm.pause()
        XCTAssertEqual(vm.status, .playing, "pause freezes, never finishes the game")
        XCTAssertEqual(vm.game.revealedSafeCount, before)
    }
}
