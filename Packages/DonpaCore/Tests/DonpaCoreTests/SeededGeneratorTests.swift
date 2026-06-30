import XCTest

@testable import DonpaCore

/// `SeededGenerator` (SplitMix64) backs the perf harness's reproducible boards, so
/// its contract is exactly: same seed → same sequence, different seeds → different.
final class SeededGeneratorTests: XCTestCase {
    func testSameSeedProducesSameSequence() {
        var a = SeededGenerator(seed: 0xDEAD_BEEF)
        var b = SeededGenerator(seed: 0xDEAD_BEEF)
        let seqA = (0..<10).map { _ in a.next() }
        let seqB = (0..<10).map { _ in b.next() }
        XCTAssertEqual(seqA, seqB, "identical seeds must yield identical streams")
    }

    func testDifferentSeedsDiverge() {
        var a = SeededGenerator(seed: 1)
        var b = SeededGenerator(seed: 2)
        let seqA = (0..<10).map { _ in a.next() }
        let seqB = (0..<10).map { _ in b.next() }
        XCTAssertNotEqual(seqA, seqB, "different seeds must not produce the same stream")
    }

    func testProducesVariedOutput() {
        // Guard against a degenerate generator that returns a constant.
        var g = SeededGenerator(seed: 42)
        let values = Set((0..<20).map { _ in g.next() })
        XCTAssertGreaterThan(values.count, 15, "output should be well-spread, not constant")
    }
}
