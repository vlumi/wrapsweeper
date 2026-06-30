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
        // S = 16×16 = 256 cells. easy .10→26, normal .13→33, hard .16→41,
        // brutal .19→49, insane .22→56.
        XCTAssertEqual(GameConfig.modern(.s, .easy, .bounded).mineCount, 26)
        XCTAssertEqual(GameConfig.modern(.s, .normal, .bounded).mineCount, 33)
        XCTAssertEqual(GameConfig.modern(.s, .hard, .bounded).mineCount, 41)
        XCTAssertEqual(GameConfig.modern(.s, .brutal, .bounded).mineCount, 49)
        XCTAssertEqual(GameConfig.modern(.s, .insane, .bounded).mineCount, 56)
        // Square sizes across the ladder (XS=9, M=25, L=50, XL=100, XXL=300, XXXL=1000).
        XCTAssertEqual(tuple(GameConfig.modern(.xs, .easy, .bounded)).prefix(2), [9, 9])
        XCTAssertEqual(tuple(GameConfig.modern(.m, .easy, .bounded)).prefix(2), [25, 25])
        XCTAssertEqual(tuple(GameConfig.modern(.l, .easy, .bounded)).prefix(2), [50, 50])
        XCTAssertEqual(tuple(GameConfig.modern(.xxl, .easy, .bounded)).prefix(2), [300, 300])
        XCTAssertEqual(tuple(GameConfig.modern(.xxxl, .easy, .bounded)).prefix(2), [1000, 1000])
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
        // S·Hard = 16×16, 41 mines, square + bounded. The key is geometry-based,
        // so renaming the size case (medium→s) leaves existing scores' keys intact.
        XCTAssertEqual(
            GameConfig.modern(.s, .hard, .bounded).storageKey, "v1|modern|sq|bounded|16x16|m41")
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
        let xs = GameConfig.modern(.xs, .normal, .bounded).storageKey
        let m = GameConfig.modern(.m, .normal, .bounded).storageKey
        XCTAssertNotEqual(xs, m)
        // And the key contains the concrete geometry, not the word "normal".
        XCTAssertTrue(xs.contains("9x9"))
        XCTAssertFalse(xs.contains("normal"))
    }

    // MARK: Labels

    func testLabels() {
        XCTAssertEqual(GameConfig.classic(.beginner).label, "Beginner")
        // Size label is the shirt-size letter; density is a sapper tier.
        XCTAssertEqual(GameConfig.modern(.s, .hard, .bounded).label, "S · Veteran")
    }

    // MARK: Rank insignia + modern accessors

    func testDensityInsigniaAscends() {
        // Enlisted tiers are 1/2/3 chevron stripes; the top two are officer marks.
        XCTAssertEqual(chevrons(.easy), 1)
        XCTAssertEqual(chevrons(.normal), 2)
        XCTAssertEqual(chevrons(.hard), 3)
        if case .star = Density.brutal.insignia {} else { XCTFail("brutal should be .star") }
        if case .staredLaurel = Density.insane.insignia {
        } else {
            XCTFail("insane should be .staredLaurel")
        }
    }

    func testModernAccessors() {
        let modern = GameConfig.modern(.m, .brutal, .bounded)
        XCTAssertEqual(modern.modernSize, .m)
        XCTAssertEqual(modern.modernDensity, .brutal)
        // Classic configs have neither.
        XCTAssertNil(GameConfig.classic(.expert).modernSize)
        XCTAssertNil(GameConfig.classic(.expert).modernDensity)
    }

    private func chevrons(_ d: Density) -> Int? {
        if case .chevrons(let n) = d.insignia { return n }
        return nil
    }

    // MARK: A config builds a playable, winnable game (integration sanity)

    func testModernConfigProducesAPlayableGame() {
        var game = Game(config: .modern(.xs, .easy, .bounded))
        var rng = SeededRNG(seed: 3)
        game.reveal(Coord(4, 4), using: &rng)
        XCTAssertNotEqual(game.status, .lost, "first click must be safe")
        XCTAssertEqual(game.mineCount, GameConfig.modern(.xs, .easy, .bounded).mineCount)
    }

    private func tuple(_ c: GameConfig) -> [Int] { [c.width, c.height, c.mineCount] }

    // MARK: Picker detail + tagline strings (every case is non-empty, detail
    // carries the expected numbers). Asserts contracts, not exact copy, so a
    // tagline reword doesn't break the test — but every code path is exercised.

    func testClassicDetailAndTagline() {
        for preset in ClassicPreset.allCases {
            let d = preset.dimensions
            let detail = preset.detail
            XCTAssertTrue(detail.contains("\(d.width)"), "detail names width: \(detail)")
            XCTAssertTrue(detail.contains("\(d.height)"), "detail names height: \(detail)")
            XCTAssertTrue(detail.contains("\(d.mines)"), "detail names mines: \(detail)")
            XCTAssertFalse(preset.tagline.isEmpty, "tagline non-empty for \(preset)")
        }
    }

    func testSizeDetailAndTagline() {
        for size in BoardSize.allCases {
            // The detail interpolates numbers with locale digit-grouping (e.g.
            // "1,000×1,000"), so compare on digits only.
            let digits = size.detail.filter(\.isNumber)
            XCTAssertTrue(digits.contains("\(size.side)"), "detail names side: \(size.detail)")
            XCTAssertFalse(size.tagline.isEmpty, "tagline non-empty for \(size)")
        }
    }

    func testDensityDetailAndTagline() {
        for density in Density.allCases {
            let pct = Int((density.fraction * 100).rounded())
            XCTAssertTrue(
                density.detail.contains("\(pct)"), "detail names percent: \(density.detail)")
            XCTAssertFalse(density.tagline.isEmpty, "tagline non-empty for \(density)")
        }
    }

    /// Taglines are distinct within each axis (no copy-paste duplicates).
    func testTaglinesAreDistinctWithinEachAxis() {
        XCTAssertEqual(
            Set(ClassicPreset.allCases.map(\.tagline)).count, ClassicPreset.allCases.count)
        XCTAssertEqual(Set(BoardSize.allCases.map(\.tagline)).count, BoardSize.allCases.count)
        XCTAssertEqual(Set(Density.allCases.map(\.tagline)).count, Density.allCases.count)
    }

    // MARK: Wrapped (torus) edges axis

    /// Every edges case has a distinct, non-empty label (the New Game picker's
    /// Bounded/Wrapped segments) and an id matching its rawValue.
    func testEdgesLabelsAndIDs() {
        let labels = BoardEdges.allCases.map(\.label)
        XCTAssertTrue(labels.allSatisfy { !$0.isEmpty }, "each edges case has a label")
        XCTAssertEqual(Set(labels).count, BoardEdges.allCases.count, "labels are distinct")
        for e in BoardEdges.allCases { XCTAssertEqual(e.id, e.rawValue) }
    }

    /// The `edges` axis selects the topology: bounded → square, wrapped → torus.
    func testEdgesSelectsTopology() {
        let bounded = GameConfig.modern(.s, .normal, .bounded)
        let wrapped = GameConfig.modern(.s, .normal, .wrapped)
        XCTAssertTrue(bounded.topology is BoundedSquareTopology)
        XCTAssertTrue(wrapped.topology is WrappedSquareTopology)
        XCTAssertEqual(bounded.edges, .bounded)
        XCTAssertEqual(wrapped.edges, .wrapped)
        // Classic is always bounded.
        XCTAssertEqual(GameConfig.classic(.beginner).edges, .bounded)
    }

    /// Bounded and wrapped key distinctly (so their scores never collide), and the
    /// wrapped key carries the `wrapped` edges token.
    func testEdgesDistinguishStorageKey() {
        let bounded = GameConfig.modern(.s, .normal, .bounded).storageKey
        let wrapped = GameConfig.modern(.s, .normal, .wrapped).storageKey
        XCTAssertNotEqual(bounded, wrapped)
        XCTAssertTrue(wrapped.contains("wrapped"), wrapped)
        XCTAssertTrue(bounded.contains("bounded"), bounded)
    }

    /// A config round-trips through Codable with its edges intact.
    func testCodableRoundTripPreservesEdges() throws {
        for cfg in [
            GameConfig.modern(.m, .hard, .wrapped),
            GameConfig.modern(.l, .easy, .bounded),
            GameConfig.classic(.expert),
        ] {
            let data = try JSONEncoder().encode(cfg)
            let back = try JSONDecoder().decode(GameConfig.self, from: data)
            XCTAssertEqual(back, cfg)
        }
    }

    /// BACK-COMPAT: a save written before the edges axis existed (modern config with
    /// no `_2` field) must still decode — as a bounded board, not a failure.
    func testDecodesLegacyModernWithoutEdgesAsBounded() throws {
        // The pre-wrapped synthesized format: {"modern":{"_0":<size>,"_1":<density>}}.
        let legacy = #"{"modern":{"_0":"m","_1":"hard"}}"#
        let cfg = try JSONDecoder().decode(GameConfig.self, from: Data(legacy.utf8))
        XCTAssertEqual(cfg, .modern(.m, .hard, .bounded), "missing edges → bounded")
    }
}
