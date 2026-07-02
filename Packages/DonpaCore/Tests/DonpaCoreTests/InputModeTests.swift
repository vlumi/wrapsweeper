import XCTest

@testable import DonpaCore

final class InputModeTests: XCTestCase {
    func testFlippedSwapsModes() {
        XCTAssertEqual(InputMode.reveal.flipped, .flag)
        XCTAssertEqual(InputMode.flag.flipped, .reveal)
    }

    func testToggleFlipsInPlaceAndRoundTrips() {
        var mode = InputMode.reveal
        mode.toggle()
        XCTAssertEqual(mode, .flag)
        mode.toggle()
        XCTAssertEqual(mode, .reveal)
    }
}
