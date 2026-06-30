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

/// Modern board sizes (square), shirt-sized XS…XXXL; side lengths chosen via
/// solver analysis. XS–XL (9…100) are the playable tiers; XXL (300²) is the
/// epic-but-finishable summit; XXXL (1000² = 1M cells) is effectively unwinnable
/// and the stress case for viewport culling.
public enum BoardSize: String, CaseIterable, Sendable, Codable {
    case xs, s, m, l, xl, xxl, xxxl

    var side: Int {
        switch self {
        case .xs: return 9
        case .s: return 16
        case .m: return 25
        case .l: return 50
        case .xl: return 100
        case .xxl: return 300
        case .xxxl: return 1000
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

/// Modern difficulty = mine density (fraction of cells). Tiers chosen via solver
/// analysis, from fair (easy) to near-unsolvable-by-logic (insane).
public enum Density: String, CaseIterable, Sendable, Codable {
    case easy, normal, hard, brutal, insane

    var fraction: Double {
        switch self {
        case .easy: return 0.10
        case .normal: return 0.13
        case .hard: return 0.16
        case .brutal: return 0.19
        case .insane: return 0.22
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

/// Topology axes — one value each ships now; named in the storage key for
/// forward-compatibility.
public enum BoardShape: String, Sendable { case square = "sq" }
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
    case modern(BoardSize, Density, BoardEdges)

    /// Square for every shipping config (hex is a later axis).
    public var shape: BoardShape { .square }
    /// Bounded for Classic; the chosen edges for Modern.
    public var edges: BoardEdges {
        if case .modern(_, _, let edges) = self { return edges }
        return .bounded
    }

    public var width: Int { dims.width }
    public var height: Int { dims.height }
    public var mineCount: Int { dims.mines }

    private var dims: BoardDimensions {
        switch self {
        case .classic(let preset):
            return preset.dimensions
        case .modern(let size, let density, _):
            let side = size.side
            let mines = Int((Double(side * side) * density.fraction).rounded())
            return BoardDimensions(width: side, height: side, mines: mines)
        }
    }

    /// The board geometry to play on, selected by the `edges` axis (all
    /// `RectangularTopology`, which `Board` requires for flat storage).
    public var topology: any RectangularTopology {
        switch edges {
        case .bounded: return BoundedSquareTopology(width: width, height: height)
        case .wrapped: return WrappedSquareTopology(width: width, height: height)
        }
    }

    /// Human-facing label; modern configs read as "Size · Density".
    public var label: String {
        switch self {
        case .classic(let preset):
            return preset.label
        case .modern(let size, let density, _):
            return "\(size.label) · \(density.label)"
        }
    }

    /// The Modern size, or nil for a Classic config.
    public var modernSize: BoardSize? {
        if case .modern(let size, _, _) = self { return size }
        return nil
    }

    /// The Modern difficulty tier, or nil for a Classic config.
    public var modernDensity: Density? {
        if case .modern(_, let density, _) = self { return density }
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
    /// The bounded Modern configs, in display order. (The wrapped variants are a
    /// separate axis surfaced in the New Game picker, not enumerated here.)
    public static let modernConfigs: [GameConfig] =
        BoardSize.allCases.flatMap { size in
            Density.allCases.map { GameConfig.modern(size, $0, .bounded) }
        }

    // Convenience shortcuts for the classic presets.
    public static let beginner = GameConfig.classic(.beginner)
    public static let intermediate = GameConfig.classic(.intermediate)
    public static let expert = GameConfig.classic(.expert)
}

// Hand-written `Codable` matching Swift's synthesized enum format
// (`{"classic":{"_0":…}}` / `{"modern":{"_0":…,"_1":…,"_2":…}}`), but with the
// new `edges` (`_2`) DEFAULTED to `.bounded` when absent — so a saved game written
// before wrapped boards existed still decodes (as a bounded board) instead of
// failing the whole snapshot. Keep `_0`/`_1` exactly as before.
extension GameConfig: Codable {
    private enum CaseKey: String, CodingKey { case classic, modern }
    // Wire keys are `_0`/`_1`/`_2` to match Swift's synthesized enum format (so
    // pre-existing saves still decode); the Swift identifiers are named to satisfy
    // the linter while the rawValue keeps the on-disk key unchanged.
    private enum ClassicKey: String, CodingKey { case preset = "_0" }
    private enum ModernKey: String, CodingKey {
        case size = "_0", density = "_1", edges = "_2"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CaseKey.self)
        if let classic = try? c.nestedContainer(keyedBy: ClassicKey.self, forKey: .classic) {
            self = .classic(try classic.decode(ClassicPreset.self, forKey: .preset))
        } else if let modern = try? c.nestedContainer(keyedBy: ModernKey.self, forKey: .modern) {
            let size = try modern.decode(BoardSize.self, forKey: .size)
            let density = try modern.decode(Density.self, forKey: .density)
            let edges = try modern.decodeIfPresent(BoardEdges.self, forKey: .edges) ?? .bounded
            self = .modern(size, density, edges)
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
        case .modern(let size, let density, let edges):
            var modern = c.nestedContainer(keyedBy: ModernKey.self, forKey: .modern)
            try modern.encode(size, forKey: .size)
            try modern.encode(density, forKey: .density)
            try modern.encode(edges, forKey: .edges)
        }
    }
}
