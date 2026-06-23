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
        XCTAssertEqual(
            MangaPanelView.Kind.loss(progress: 0.5, safeRemaining: 10, isBest: false).imageName,
            "PanelLoss")
    }

    func testIsWin() {
        XCTAssertTrue(MangaPanelView.Kind.win.isWin)
        XCTAssertTrue(MangaPanelView.Kind.record(centiseconds: 1).isWin)
        XCTAssertFalse(
            MangaPanelView.Kind.loss(progress: 0.5, safeRemaining: 10, isBest: false).isWin)
    }

    func testBestLossHeadline() {
        // Only a new-best loss surfaces a pill headline.
        XCTAssertEqual(
            MangaPanelView.Kind.loss(progress: 0.42, safeRemaining: 30, isBest: true)
                .bestLossHeadline, "42%")
        XCTAssertNil(
            MangaPanelView.Kind.loss(progress: 0.42, safeRemaining: 30, isBest: false)
                .bestLossHeadline)
        XCTAssertNil(MangaPanelView.Kind.win.bestLossHeadline)
        XCTAssertNil(MangaPanelView.Kind.record(centiseconds: 1).bestLossHeadline)
    }

    func testNearHundredLossShowsTilesLeft() {
        // A loss that rounds to 100% but isn't a clear shows the tiles-left count,
        // not a misleading "100%".
        XCTAssertEqual(MangaPanelView.Kind.lossHeadline(0.997, safeRemaining: 2), "2 left")
        // A genuine lower loss still shows the percent.
        XCTAssertEqual(MangaPanelView.Kind.lossHeadline(0.50, safeRemaining: 100), "50%")
        // Defensive: rounds-to-100 with zero remaining (shouldn't happen on a
        // loss) falls back to the percent rather than "0 left".
        XCTAssertEqual(MangaPanelView.Kind.lossHeadline(1.0, safeRemaining: 0), "100%")
    }

    func testPercentRounds() {
        XCTAssertEqual(MangaPanelView.Kind.percent(0.0), "0%")
        XCTAssertEqual(MangaPanelView.Kind.percent(0.874), "87%")
        XCTAssertEqual(MangaPanelView.Kind.percent(1.0), "100%")
    }

    func testRecordCentiseconds() {
        XCTAssertEqual(MangaPanelView.Kind.record(centiseconds: 4242).recordCentiseconds, 4242)
        XCTAssertNil(MangaPanelView.Kind.win.recordCentiseconds)
        XCTAssertNil(
            MangaPanelView.Kind.loss(progress: 0.5, safeRemaining: 10, isBest: false)
                .recordCentiseconds)
    }

    func testAccessibilityLabels() {
        XCTAssertEqual(MangaPanelView.Kind.win.a11yLabel, "Minefield cleared")
        XCTAssertTrue(
            MangaPanelView.Kind.loss(progress: 0.5, safeRemaining: 10, isBest: false)
                .a11yLabel.contains("Boom"))
        // The record label embeds the formatted time (12.34s = 1234 cs).
        XCTAssertTrue(
            MangaPanelView.Kind.record(centiseconds: 1234).a11yLabel.contains(
                TimeFormat.mmsst(centiseconds: 1234)))
    }
}
