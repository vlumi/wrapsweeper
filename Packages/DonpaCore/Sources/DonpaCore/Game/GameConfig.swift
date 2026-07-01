/// A fully-specified, playable board configuration — the single source of
/// dimensions, mine count, topology, display label, and the stable persistence
/// key used by the scoreboard.
///
/// Two modes: **Classic** (the three original presets) and **Modern** (a curated
/// `Size × Density` grid; density is a mine percentage so size and difficulty
/// compose independently).
///
/// Future axes (hex shape, wrapped edges) are encoded in the storage key now with
/// explicit defaults (`sq`, `bounded`), so adding them never invalidates existing
/// keys. The key also encodes concrete geometry (`WxH|mN`), so re-tuning a tier
/// produces a new key (new scoreboard entry) rather than re-pointing old scores.

import Foundation

/// Board width/height/mine-count, computed from a `GameConfig`.
public struct BoardDimensions: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let mines: Int
}

public enum ClassicPreset: String, CaseIterable, Sendable, Codable {
    case beginner, intermediate, expert

    var dimensions: BoardDimensions {
        switch self {
        case .beginner: return BoardDimensions(width: 9, height: 9, mines: 10)
        case .intermediate: return BoardDimensions(width: 16, height: 16, mines: 40)
        case .expert: return BoardDimensions(width: 30, height: 16, mines: 99)
        }
    }

    public var label: String {
        switch self {
        case .beginner: return String(localized: "Beginner", bundle: .module)
        case .intermediate: return String(localized: "Intermediate", bundle: .module)
        case .expert: return String(localized: "Expert", bundle: .module)
        }
    }

    /// Board dimensions and mine count, shown under the picker carousel.
    public var detail: String {
        let d = dimensions
        return String(
            localized: "\(d.width)×\(d.height) · \(d.mines) mines", bundle: .module,
            comment: "Classic preset detail: WIDTH×HEIGHT · N mines")
    }

    /// A short, playful tagline shown under the picker carousel.
    public var tagline: String {
        switch self {
        case .beginner: return String(localized: "Boots on, recruit", bundle: .module)
        case .intermediate: return String(localized: "Things get spicy", bundle: .module)
        case .expert: return String(localized: "One wrong step…", bundle: .module)
        }
    }
}

/// Modern board sizes (square), shirt-sized XS…XXXL. Side lengths are powers of two
/// (8…256, then 1024), so every board is even-sided — the property a hex torus
/// needs for consistent wrap-around (odd height breaks hex adjacency symmetry). The
/// top rung jumps ×4 to 1024² (~1M cells): the effectively-unwinnable stress case
/// for viewport culling. XS–XXL are the playable tiers.
public enum BoardSize: String, CaseIterable, Sendable, Codable {
    case xs, s, m, l, xl, xxl, xxxl

    var side: Int {
        switch self {
        case .xs: return 8
        case .s: return 16
        case .m: return 32
        case .l: return 64
        case .xl: return 128
        case .xxl: return 256
        case .xxxl: return 1024
        }
    }

    public var label: String {
        switch self {
        case .xs: return String(localized: "XS", bundle: .module)
        case .s: return String(localized: "S", bundle: .module)
        case .m: return String(localized: "M", bundle: .module)
        case .l: return String(localized: "L", bundle: .module)
        case .xl: return String(localized: "XL", bundle: .module)
        case .xxl: return String(localized: "XXL", bundle: .module)
        case .xxxl: return String(localized: "XXXL", bundle: .module)
        }
    }

    /// Board dimensions, shown under the picker carousel.
    public var detail: String {
        String(
            localized: "\(side)×\(side)", bundle: .module,
            comment: "Board size detail: SIDE×SIDE")
    }

    /// A short, playful tagline shown under the picker carousel.
    public var tagline: String {
        switch self {
        case .xs: return String(localized: "Over before your coffee", bundle: .module)
        case .s: return String(localized: "A quick recon", bundle: .module)
        case .m: return String(localized: "A proper mission", bundle: .module)
        case .l: return String(localized: "Clear your evening", bundle: .module)
        case .xl: return String(localized: "Pack a lunch", bundle: .module)
        case .xxl: return String(localized: "Pack a lunch. And dinner.", bundle: .module)
        case .xxxl: return String(localized: "Abandon all hope, ye who enter", bundle: .module)
        }
    }
}

/// Modern difficulty = mine density (fraction of cells). Even 2-point steps, from
/// fair (easy) to near-unsolvable-by-logic (insane), chosen via solver analysis on
/// the power-of-two size ladder: bigger boards saturate to ~100% forced-guess
/// sooner, so the top tier stays modest to keep all five distinct on the boards
/// people actually play.
///
/// **Hex runs +2 points denser than square** (12/14/16/18/20% vs 10/12/14/16/18%):
/// a hex cell has 6 neighbours vs 8, so the same mine% cascades more and plays
/// noticeably easier (the small/sparse boards were near one-tap). The bump matches
/// hex difficulty back to square roughly tier-for-tier. See the TierAnalysis dev
/// tool, which measures both topologies.
public enum Density: String, CaseIterable, Sendable, Codable {
    case easy, normal, hard, brutal, insane

    /// Mine fraction for a given board shape. Square is the base ladder; hex adds
    /// two points per tier to offset its gentler 6-neighbour cascades.
    func fraction(shape: BoardShape) -> Double {
        base + (shape == .hex ? 0.02 : 0)
    }

    /// The square (base) fraction — also what the picker's "N% mines" label shows.
    var fraction: Double { base }

    private var base: Double {
        switch self {
        case .easy: return 0.10
        case .normal: return 0.12
        case .hard: return 0.14
        case .brutal: return 0.16
        case .insane: return 0.18
        }
    }

    /// Sapper-themed skill tiers (ascending). Display-only — the `rawValue`
    /// (easy/normal/…) is unchanged, so scoreboard keys are unaffected.
    public var label: String {
        switch self {
        case .easy: return String(localized: "Trainee", bundle: .module)
        case .normal: return String(localized: "Sapper", bundle: .module)
        case .hard: return String(localized: "Veteran", bundle: .module)
        case .brutal: return String(localized: "Ace", bundle: .module)
        case .insane: return String(localized: "Legend", bundle: .module)
        }
    }

    /// Mine density as a whole percent, shown under the picker carousel.
    public var detail: String {
        String(
            localized: "\(Int((fraction * 100).rounded()))% mines", bundle: .module,
            comment: "Modern difficulty detail: N% mines")
    }

    /// A short, playful tagline shown under the picker carousel.
    public var tagline: String {
        switch self {
        case .easy: return String(localized: "Easy does it", bundle: .module)
        case .normal: return String(localized: "Mind your step", bundle: .module)
        case .hard: return String(localized: "Sweating now", bundle: .module)
        case .brutal: return String(localized: "This is mean", bundle: .module)
        case .insane: return String(localized: "No pain, no gain", bundle: .module)
        }
    }

    /// Ascending rank insignia, shown language-free in the compact difficulty
    /// picker; `label` stays the accessibility name.
    public enum Insignia: Sendable {
        case chevrons(Int)  // N stacked stripes
        case star  // single officer star
        case staredLaurel  // star in a laurel wreath (apex)
    }
    public var insignia: Insignia {
        switch self {
        case .easy: return .chevrons(1)
        case .normal: return .chevrons(2)
        case .hard: return .chevrons(3)
        case .brutal: return .star
        case .insane: return .staredLaurel
        }
    }
}

/// The board's cell shape — square (8-neighbour) or hex (6-neighbour). Orthogonal
/// to `BoardEdges`, so the full matrix is shape × edges. Named in the storage key
/// (`sq`/`hex`) for forward-compatible scoreboard entries.
public enum BoardShape: String, Sendable, Codable, CaseIterable, Identifiable {
    case square = "sq"
    /// Pointy-top hexagonal cells — `HexTopology`. Modern boards only.
    case hex

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .square: return String(localized: "Square", bundle: .module)
        case .hex: return String(localized: "Hex", bundle: .module)
        }
    }
}
public enum BoardEdges: String, Sendable, Codable, CaseIterable, Identifiable {
    case bounded
    /// Edges wrap (torus) — `WrappedSquareTopology`. Modern boards only.
    case wrapped

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .bounded: return String(localized: "Bounded", bundle: .module)
        case .wrapped: return String(localized: "Wrapped", bundle: .module)
        }
    }
}

public enum GameConfig: Hashable, Sendable {
    case classic(ClassicPreset)
    // Associated values are ordered size, density, edges, shape so `shape` appends
    // as `_3` in the synthesized wire format — `_2` stays `edges`, keeping saves
    // written before the hex axis decodable (see the `Codable` extension).
    case modern(BoardSize, Density, BoardEdges, BoardShape)

    /// Square for Classic; the chosen shape for Modern.
    public var shape: BoardShape {
        if case .modern(_, _, _, let shape) = self { return shape }
        return .square
    }
    /// Bounded for Classic; the chosen edges for Modern.
    public var edges: BoardEdges {
        if case .modern(_, _, let edges, _) = self { return edges }
        return .bounded
    }

    public var width: Int { dims.width }
    public var height: Int { dims.height }
    public var mineCount: Int { dims.mines }

    private var dims: BoardDimensions {
        switch self {
        case .classic(let preset):
            return preset.dimensions
        case .modern(let size, let density, _, let shape):
            let side = size.side
            let mines = Int((Double(side * side) * density.fraction(shape: shape)).rounded())
            return BoardDimensions(width: side, height: side, mines: mines)
        }
    }

    /// The board geometry to play on, the full shape × edges matrix (all
    /// `RectangularTopology`, which `Board` requires for flat storage). Every Modern
    /// size is even-sided (powers of two), so the wrapped-hex torus is always valid.
    public var topology: any RectangularTopology {
        switch (shape, edges) {
        case (.square, .bounded): return BoundedSquareTopology(width: width, height: height)
        case (.square, .wrapped): return WrappedSquareTopology(width: width, height: height)
        case (.hex, .bounded): return HexTopology(width: width, height: height)
        case (.hex, .wrapped): return WrappedHexTopology(width: width, height: height)
        }
    }

    /// The pixel layout matching `shape` — the `CellLayout` the renderer positions
    /// and hit-tests with. Pairs with `topology`; changes when a new game switches
    /// shape, so the scene reads it from the live config rather than caching it.
    public func layout(cellSize: CGFloat = 32) -> any CellLayout {
        switch shape {
        case .square: return SquareLayout(cellSize: cellSize)
        case .hex: return HexLayout(cellSize: cellSize)
        }
    }

    /// Human-facing label; modern configs read as "Size · Density".
    public var label: String {
        switch self {
        case .classic(let preset):
            return preset.label
        case .modern(let size, let density, _, _):
            return "\(size.label) · \(density.label)"
        }
    }

    /// The Modern size, or nil for a Classic config.
    public var modernSize: BoardSize? {
        if case .modern(let size, _, _, _) = self { return size }
        return nil
    }

    /// The Modern difficulty tier, or nil for a Classic config.
    public var modernDensity: Density? {
        if case .modern(_, let density, _, _) = self { return density }
        return nil
    }

    /// Stable, versioned, geometry-bearing persistence key. Encodes every
    /// future axis explicitly so older keys never become ambiguous.
    ///
    ///   classic:  v1|classic|beginner
    ///   modern:   v1|modern|sq|bounded|16x16|m33
    public var storageKey: String {
        switch self {
        case .classic(let preset):
            return "v1|classic|\(preset.rawValue)"
        case .modern:
            return
                "v1|modern|\(shape.rawValue)|\(edges.rawValue)|\(width)x\(height)|m\(mineCount)"
        }
    }

    /// All configs offered in each mode, in display order.
    public static let classicConfigs: [GameConfig] =
        ClassicPreset.allCases.map(GameConfig.classic)
    /// The bounded, square Modern configs, in display order. (The wrapped and hex
    /// variants are separate axes surfaced in the New Game picker, not enumerated
    /// here.)
    public static let modernConfigs: [GameConfig] =
        BoardSize.allCases.flatMap { size in
            Density.allCases.map { GameConfig.modern(size, $0, .bounded, .square) }
        }

    // Convenience shortcuts for the classic presets.
    public static let beginner = GameConfig.classic(.beginner)
    public static let intermediate = GameConfig.classic(.intermediate)
    public static let expert = GameConfig.classic(.expert)
}

// Hand-written `Codable` matching Swift's synthesized enum format
// (`{"classic":{"_0":…}}` / `{"modern":{"_0":…,"_1":…,"_2":…,"_3":…}}`), but with
// the topology axes DEFAULTED when absent: `edges` (`_2`) → `.bounded`, `shape`
// (`_3`) → `.square`. So a saved game written before wrapped/hex boards existed
// still decodes (as a bounded square board) instead of failing the whole snapshot.
// Keep `_0`/`_1` exactly as before.
extension GameConfig: Codable {
    private enum CaseKey: String, CodingKey { case classic, modern }
    // Wire keys are `_0`…`_3` to match Swift's synthesized enum format (so
    // pre-existing saves still decode); the Swift identifiers are named to satisfy
    // the linter while the rawValue keeps the on-disk key unchanged.
    private enum ClassicKey: String, CodingKey { case preset = "_0" }
    private enum ModernKey: String, CodingKey {
        case size = "_0", density = "_1", edges = "_2", shape = "_3"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CaseKey.self)
        if let classic = try? c.nestedContainer(keyedBy: ClassicKey.self, forKey: .classic) {
            self = .classic(try classic.decode(ClassicPreset.self, forKey: .preset))
        } else if let modern = try? c.nestedContainer(keyedBy: ModernKey.self, forKey: .modern) {
            let size = try modern.decode(BoardSize.self, forKey: .size)
            let density = try modern.decode(Density.self, forKey: .density)
            let edges = try modern.decodeIfPresent(BoardEdges.self, forKey: .edges) ?? .bounded
            let shape = try modern.decodeIfPresent(BoardShape.self, forKey: .shape) ?? .square
            self = .modern(size, density, edges, shape)
        } else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "unknown GameConfig case"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CaseKey.self)
        switch self {
        case .classic(let preset):
            var classic = c.nestedContainer(keyedBy: ClassicKey.self, forKey: .classic)
            try classic.encode(preset, forKey: .preset)
        case .modern(let size, let density, let edges, let shape):
            var modern = c.nestedContainer(keyedBy: ModernKey.self, forKey: .modern)
            try modern.encode(size, forKey: .size)
            try modern.encode(density, forKey: .density)
            try modern.encode(edges, forKey: .edges)
            try modern.encode(shape, forKey: .shape)
        }
    }
}
