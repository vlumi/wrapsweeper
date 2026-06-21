import XCTest

@testable import DonpaCore

final class GameConfigTests: XCTestCase {

    // MARK: Classic presets keep exact original numbers

    func testClassicPresetDimensions() {
        XCTAssertEqual(tuple(GameConfig.classic(.beginner)), [9, 9, 10])
        XCTAssertEqual(tuple(GameConfig.classic(.intermediate)), [16, 16, 40])
        XCTAssertEqual(tuple(GameConfig.classic(.expert)), [30, 16, 99])
    }

    // MARK: Modern = size × density (mine = round(density × cells))

    func testModernMineCounts() {
        // Medium 16×16 = 256 cells. easy .10→26, normal .13→33, hard .16→41,
        // brutal .19→49, insane .22→56.
        XCTAssertEqual(GameConfig.modern(.medium, .easy).mineCount, 26)
        XCTAssertEqual(GameConfig.modern(.medium, .normal).mineCount, 33)
        XCTAssertEqual(GameConfig.modern(.medium, .hard).mineCount, 41)
        XCTAssertEqual(GameConfig.modern(.medium, .brutal).mineCount, 49)
        XCTAssertEqual(GameConfig.modern(.medium, .insane).mineCount, 56)
        // Square sizes.
        XCTAssertEqual(tuple(GameConfig.modern(.small, .easy)).prefix(2), [9, 9])
        XCTAssertEqual(tuple(GameConfig.modern(.large, .easy)).prefix(2), [25, 25])
    }

    func testEveryModernConfigLeavesASafeCell() {
        for config in GameConfig.modernConfigs {
            XCTAssertLessThan(
                config.mineCount, config.width * config.height,
                "\(config.label) must leave at least one safe cell")
        }
    }

    // MARK: Storage keys — versioned, geometry-bearing, forward-compatible

    func testClassicStorageKeys() {
        XCTAssertEqual(GameConfig.classic(.beginner).storageKey, "v1|classic|beginner")
        XCTAssertEqual(GameConfig.classic(.expert).storageKey, "v1|classic|expert")
    }

    func testModernStorageKeyEncodesShapeEdgesAndGeometry() {
        // Medium·Hard = 16×16, 41 mines, square + bounded.
        XCTAssertEqual(
            GameConfig.modern(.medium, .hard).storageKey, "v1|modern|sq|bounded|16x16|m41")
    }

    func testEveryConfigHasAUniqueStorageKey() {
        let all = GameConfig.classicConfigs + GameConfig.modernConfigs
        let keys = all.map(\.storageKey)
        XCTAssertEqual(Set(keys).count, keys.count, "storage keys must be unique per config")
    }

    /// The format-lock guarantee: keys carry geometry, so if a tier were ever
    /// redefined to a different size, it would produce a DIFFERENT key — old
    /// scores stay attached to their real board rather than being silently
    /// re-pointed. We assert the key is a function of geometry, not the tier
    /// token, by comparing two configs that share a token but differ in size.
    func testKeyIsGeometryBoundNotTierBound() {
        // Two modern configs with the same density token but different sizes
        // must have different keys (because geometry differs).
        let small = GameConfig.modern(.small, .normal).storageKey
        let large = GameConfig.modern(.large, .normal).storageKey
        XCTAssertNotEqual(small, large)
        // And the key contains the concrete geometry, not the word "normal".
        XCTAssertTrue(small.contains("9x9"))
        XCTAssertFalse(small.contains("normal"))
    }

    // MARK: Labels

    func testLabels() {
        XCTAssertEqual(GameConfig.classic(.beginner).label, "Beginner")
        XCTAssertEqual(GameConfig.modern(.medium, .hard).label, "Medium · Hard")
    }

    // MARK: A config builds a playable, winnable game (integration sanity)

    func testModernConfigProducesAPlayableGame() {
        var game = Game(config: .modern(.small, .easy))
        var rng = SeededRNG(seed: 3)
        game.reveal(Coord(4, 4), using: &rng)
        XCTAssertNotEqual(game.status, .lost, "first click must be safe")
        XCTAssertEqual(game.mineCount, GameConfig.modern(.small, .easy).mineCount)
    }

    private func tuple(_ c: GameConfig) -> [Int] { [c.width, c.height, c.mineCount] }
}
