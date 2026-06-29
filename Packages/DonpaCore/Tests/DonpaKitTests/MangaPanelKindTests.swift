import DonpaCore
import XCTest

@testable import DonpaKit

/// The view itself needs UI automation (ignored for coverage), but
/// `MangaPanelView.Kind` is pure logic — the asset name, accent, spoken label,
/// and the improvement-delta presentation that drive win/loss/record. Lock those
/// down here.
final class MangaPanelKindTests: XCTestCase {
    func testImageName() {
        XCTAssertEqual(MangaPanelView.Kind.win.imageName, "PanelWin")
        XCTAssertEqual(
            MangaPanelView.Kind.record(centiseconds: 1234, improvedBy: 100).imageName, "PanelWin")
        XCTAssertEqual(
            MangaPanelView.Kind.loss(progress: 0.5, safeRemaining: 10, best: .notBest).imageName,
            "PanelLoss")
    }

    func testIsWin() {
        XCTAssertTrue(MangaPanelView.Kind.win.isWin)
        XCTAssertTrue(MangaPanelView.Kind.record(centiseconds: 1, improvedBy: nil).isWin)
        XCTAssertFalse(
            MangaPanelView.Kind.loss(progress: 0.5, safeRemaining: 10, best: .notBest).isWin)
    }

    func testBestLossHeadline() {
        // A new-best loss surfaces a pill headline; a first run counts as best too.
        XCTAssertEqual(
            MangaPanelView.Kind.loss(progress: 0.42, safeRemaining: 30, best: .improved(by: 0.1))
                .bestLossHeadline, "42%")
        XCTAssertEqual(
            MangaPanelView.Kind.loss(progress: 0.42, safeRemaining: 30, best: .first)
                .bestLossHeadline, "42%")
        // A non-best loss shows no pill.
        XCTAssertNil(
            MangaPanelView.Kind.loss(progress: 0.42, safeRemaining: 30, best: .notBest)
                .bestLossHeadline)
        XCTAssertNil(MangaPanelView.Kind.win.bestLossHeadline)
        XCTAssertNil(MangaPanelView.Kind.record(centiseconds: 1, improvedBy: nil).bestLossHeadline)
    }

    func testNearHundredLossShowsTilesLeft() {
        XCTAssertEqual(MangaPanelView.Kind.lossHeadline(0.997, safeRemaining: 2), "2 left")
        XCTAssertEqual(MangaPanelView.Kind.lossHeadline(0.50, safeRemaining: 100), "50%")
        XCTAssertEqual(MangaPanelView.Kind.lossHeadline(1.0, safeRemaining: 0), "100%")
    }

    func testPercentRounds() {
        XCTAssertEqual(MangaPanelView.Kind.percent(0.0), "0%")
        XCTAssertEqual(MangaPanelView.Kind.percent(0.874), "87%")
        XCTAssertEqual(MangaPanelView.Kind.percent(1.0), "100%")
    }

    func testRecordCentiseconds() {
        XCTAssertEqual(
            MangaPanelView.Kind.record(centiseconds: 4242, improvedBy: 50).recordCentiseconds, 4242)
        XCTAssertNil(MangaPanelView.Kind.win.recordCentiseconds)
        XCTAssertNil(
            MangaPanelView.Kind.loss(progress: 0.5, safeRemaining: 10, best: .notBest)
                .recordCentiseconds)
    }

    // MARK: Improvement deltas (the panel shows how much better, not the absolute)

    func testRecordImprovedBy() {
        // A record beating a prior best carries the shaved-off centiseconds.
        XCTAssertEqual(
            MangaPanelView.Kind.record(centiseconds: 1000, improvedBy: 420).recordImprovedBy, 420)
        // A first-ever clear has no prior best → no delta.
        XCTAssertNil(
            MangaPanelView.Kind.record(centiseconds: 1000, improvedBy: nil).recordImprovedBy)
    }

    func testLossImprovedBy() {
        XCTAssertEqual(
            MangaPanelView.Kind.loss(progress: 0.6, safeRemaining: 5, best: .improved(by: 0.2))
                .lossImprovedBy, 0.2)
        // First run / non-best carry no delta.
        XCTAssertNil(
            MangaPanelView.Kind.loss(progress: 0.6, safeRemaining: 5, best: .first).lossImprovedBy)
        XCTAssertNil(
            MangaPanelView.Kind.loss(progress: 0.6, safeRemaining: 5, best: .notBest).lossImprovedBy
        )
    }

    func testImprovementFormatters() {
        // Time improvement reads as "faster" with a leading minus, mm:ss.t.
        XCTAssertEqual(
            MangaPanelView.Kind.timeImprovement(420),
            "−" + TimeFormat.mmsst(centiseconds: 420))
        // Progress improvement is floored and signed "+N%".
        XCTAssertEqual(MangaPanelView.Kind.progressImprovement(0.234), "+23%")
        XCTAssertEqual(MangaPanelView.Kind.progressImprovement(0.0), "+0%")
    }

    func testAccessibilityLabels() {
        XCTAssertEqual(MangaPanelView.Kind.win.a11yLabel, "Minefield cleared")
        XCTAssertTrue(
            MangaPanelView.Kind.loss(progress: 0.5, safeRemaining: 10, best: .notBest)
                .a11yLabel.contains("Boom"))
        // The record label embeds the formatted time (12.34s = 1234 cs).
        XCTAssertTrue(
            MangaPanelView.Kind.record(centiseconds: 1234, improvedBy: 10).a11yLabel.contains(
                TimeFormat.mmsst(centiseconds: 1234)))
    }
}
