import DonpaCore
import XCTest

@testable import DonpaKit

/// `Settings.currentConfig` is what the New Game popup turns the player's pending
/// choices into — including the new wrapped-edges axis. Lock the mapping +
/// persistence (pure logic; the picker UI itself is coverage-ignored).
@MainActor
final class SettingsConfigTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        return d
    }

    func testModernEdgesDefaultsToBounded() {
        let s = Settings(defaults: freshDefaults())
        XCTAssertEqual(s.modernEdges, .bounded, "off by default — existing behaviour unchanged")
    }

    func testCurrentConfigCarriesTheChosenEdges() {
        let s = Settings(defaults: freshDefaults())
        s.mode = .modern
        s.modernEdges = .wrapped
        guard case .modern(_, _, let edges) = s.currentConfig else {
            return XCTFail("modern mode should yield a modern config")
        }
        XCTAssertEqual(edges, .wrapped, "the picker's edges choice flows into the config")
        XCTAssertTrue(s.currentConfig.topology is WrappedSquareTopology)

        // Classic is always bounded, regardless of the modern edges setting.
        s.mode = .classic
        XCTAssertEqual(s.currentConfig.edges, .bounded)
    }

    func testModernEdgesPersists() {
        let defaults = freshDefaults()
        let a = Settings(defaults: defaults)
        a.modernEdges = .wrapped
        // A fresh Settings on the same store restores the choice.
        let b = Settings(defaults: defaults)
        XCTAssertEqual(b.modernEdges, .wrapped)
    }
}
