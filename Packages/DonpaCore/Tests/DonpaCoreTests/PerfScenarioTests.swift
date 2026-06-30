import XCTest

@testable import DonpaCore

/// `PerfScenario.parse` reads the `-perf-scenario <name>` launch arg the profiling
/// harness passes; absent or unknown → nil (a normal launch).
final class PerfScenarioTests: XCTestCase {
    func testParsesKnownScenario() {
        XCTAssertEqual(
            PerfScenario.parse(["app", "-perf-scenario", "xxxl-opened"]), .xxxlOpened)
        // Order-independent, ignores surrounding args.
        XCTAssertEqual(
            PerfScenario.parse(["app", "-uitest-clean", "-perf-scenario", "xxxl-opened", "x"]),
            .xxxlOpened)
    }

    func testNilWhenAbsentOrUnknown() {
        XCTAssertNil(PerfScenario.parse(["app", "-uitest-clean"]), "no flag → nil")
        XCTAssertNil(PerfScenario.parse(["app", "-perf-scenario"]), "flag with no value → nil")
        XCTAssertNil(
            PerfScenario.parse(["app", "-perf-scenario", "bogus"]), "unknown name → nil")
    }
}
