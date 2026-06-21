import DonpaCore
import XCTest

@testable import DonpaKit

/// The view itself needs UI automation (ignored for coverage), but
/// `MangaPanelView.Kind` is pure logic — the asset name, accent, and spoken
/// label that drive win/loss/record presentation. Lock those down here.
final class MangaPanelKindTests: XCTestCase {
    func testImageName() {
        XCTAssertEqual(MangaPanelView.Kind.win.imageName, "PanelWin")
        XCTAssertEqual(MangaPanelView.Kind.record(centiseconds: 1234).imageName, "PanelWin")
        XCTAssertEqual(MangaPanelView.Kind.loss.imageName, "PanelLoss")
    }

    func testIsWin() {
        XCTAssertTrue(MangaPanelView.Kind.win.isWin)
        XCTAssertTrue(MangaPanelView.Kind.record(centiseconds: 1).isWin)
        XCTAssertFalse(MangaPanelView.Kind.loss.isWin)
    }

    func testRecordCentiseconds() {
        XCTAssertEqual(MangaPanelView.Kind.record(centiseconds: 4242).recordCentiseconds, 4242)
        XCTAssertNil(MangaPanelView.Kind.win.recordCentiseconds)
        XCTAssertNil(MangaPanelView.Kind.loss.recordCentiseconds)
    }

    func testAccessibilityLabels() {
        XCTAssertEqual(MangaPanelView.Kind.win.a11yLabel, "Minefield cleared")
        XCTAssertTrue(MangaPanelView.Kind.loss.a11yLabel.contains("Boom"))
        // The record label embeds the formatted time (12.34s = 1234 cs).
        XCTAssertTrue(
            MangaPanelView.Kind.record(centiseconds: 1234).a11yLabel.contains(
                TimeFormat.mmsst(centiseconds: 1234)))
    }
}
