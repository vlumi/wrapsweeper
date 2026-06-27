/// A fully-specified, playable board configuration — the single source of board
/// dimensions, mine count, topology, display label, and (critically) the
/// **stable persistence key** used by the scoreboard.
///
/// Two modes are first-class:
/// - **Classic** — the three original Minesweeper presets, exact dims/mines.
/// - **Modern** — a curated `Size × Density` grid (square boards; density is a
///   mine percentage, so size and difficulty compose independently).
///
/// Future "epic" axes (hex shape, wrapped edges) are represented in the storage
/// key *now* with explicit defaults (`sq`, `bounded`), so adding them later
/// never invalidates existing keys — no migration. The key also encodes the
/// concrete geometry (`WxH|mN`), so re-tuning a tier later simply produces a new
/// key (a new scoreboard entry) rather than silently re-pointing old scores.

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

    /// Concrete facts for the selected preset, shown under the picker carousel:
    /// board dimensions and mine count.
    public var detail: String {
        let d = dimensions
        return String(
            localized: "\(d.width)×\(d.height) · \(d.mines) mines", bundle: .module,
            comment: "Classic preset detail: WIDTH×HEIGHT · N mines")
    }

    /// A short, playful tagline conveying how the preset *feels* to play — shown
    /// under the picker carousel alongside `detail`.
    public var tagline: String {
        switch self {
        case .beginner: return String(localized: "Boots on, recruit", bundle: .module)
        case .intermediate: return String(localized: "Things get spicy", bundle: .module)
        case .expert: return String(localized: "One wrong step…", bundle: .module)
        }
    }
}

/// Modern board sizes (square), named as shirt sizes (XS…XXXL). Side lengths
/// chosen via solver analysis. XS–XL (9…100) are the "sane" playable tiers. XXL
/// (300×300 = 90k cells) is the epic-but-finishable summit — a few resumable
/// sessions for a strong player. XXXL (1000×1000 = 1M cells) is the sandbox flex:
/// effectively unwinnable (~15–40h even on the easiest density, with no undo), a
/// "we go to a million" spectacle rather than a tuned challenge. Both XXL/XXXL are
/// far larger than any viewport — panned/zoomed via the minimap, and the stress
/// case for viewport culling. Labels show verbatim in EN/FI; Japanese uses size
/// words (極小…超巨大) instead of the Latin letters.
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

    /// Board dimensions for the selected size, shown under the picker carousel.
    public var detail: String {
        String(
            localized: "\(side)×\(side)", bundle: .module,
            comment: "Board size detail: SIDE×SIDE")
    }

    /// A short, playful tagline conveying the *commitment* a size demands — from a
    /// coffee-break sweep up to the effectively-endless XXXL. Shown under the
    /// picker carousel alongside `detail`.
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
/// analysis to ramp from fair (Easy) to near-unsolvable-by-logic (Insane).
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

    /// Display labels are sapper-themed skill tiers (ascending difficulty),
    /// tying difficulty to the game's combat-engineer character. These are
    /// display-only — the `rawValue` (easy/normal/…) is unchanged, so scoreboard
    /// keys keyed on it are unaffected.
    public var label: String {
        switch self {
        case .easy: return String(localized: "Trainee", bundle: .module)
        case .normal: return String(localized: "Sapper", bundle: .module)
        case .hard: return String(localized: "Veteran", bundle: .module)
        case .brutal: return String(localized: "Ace", bundle: .module)
        case .insane: return String(localized: "Legend", bundle: .module)
        }
    }

    /// Mine density as a whole percent, shown under the picker carousel. (Density
    /// has no fixed board size — that's the orthogonal Size axis.)
    public var detail: String {
        String(
            localized: "\(Int((fraction * 100).rounded()))% mines", bundle: .module,
            comment: "Modern difficulty detail: N% mines")
    }

    /// A short, playful tagline conveying how punishing a density plays — from
    /// room-to-breathe up to abandon-hope. Shown under the picker carousel.
    public var tagline: String {
        switch self {
        case .easy: return String(localized: "Easy does it", bundle: .module)
        case .normal: return String(localized: "Mind your step", bundle: .module)
        case .hard: return String(localized: "Sweating now", bundle: .module)
        case .brutal: return String(localized: "This is mean", bundle: .module)
        case .insane: return String(localized: "No pain, no gain", bundle: .module)
        }
    }

    /// Ascending rank insignia for the tier, shown instead of the (long, hard-to-
    /// localize) text in the compact difficulty picker — so the rank reads at a
    /// glance, language-free. The `label` stays the accessibility name. Lower
    /// ranks are enlisted chevron stripes; the top two are officer marks (a star,
    /// then a star in a laurel wreath for the apex).
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

/// Topology axes — only one value each ships now; the rest exist so the storage
/// key can name them explicitly and stay forward-compatible.
public enum BoardShape: String, Sendable { case square = "sq" }
public enum BoardEdges: String, Sendable { case bounded }

public enum GameConfig: Hashable, Sendable, Codable {
    case classic(ClassicPreset)
    case modern(BoardSize, Density)

    // Square + bounded for every shipping config; future variants add cases.
    public var shape: BoardShape { .square }
    public var edges: BoardEdges { .bounded }

    public var width: Int { dims.width }
    public var height: Int { dims.height }
    public var mineCount: Int { dims.mines }

    private var dims: BoardDimensions {
        switch self {
        case .classic(let preset):
            return preset.dimensions
        case .modern(let size, let density):
            let side = size.side
            let mines = Int((Double(side * side) * density.fraction).rounded())
            return BoardDimensions(width: side, height: side, mines: mines)
        }
    }

    /// The board geometry to play on. Square + bounded today; the shape/edges
    /// axes will select hex/wrapped topologies later (all dense rectangles —
    /// hence `RectangularTopology`, which `Board` requires for flat storage).
    public var topology: any RectangularTopology {
        BoundedSquareTopology(width: width, height: height)
    }

    /// Human-facing label. Classic configs keep their nostalgic names; modern
    /// configs read as "Size · Density".
    public var label: String {
        switch self {
        case .classic(let preset):
            return preset.label
        case .modern(let size, let density):
            return "\(size.label) · \(density.label)"
        }
    }

    /// The Modern size, or nil for a Classic config.
    public var modernSize: BoardSize? {
        if case .modern(let size, _) = self { return size }
        return nil
    }

    /// The Modern difficulty tier, or nil for a Classic config. Lets the chrome
    /// show the rank insignia for the density part of a Modern config.
    public var modernDensity: Density? {
        if case .modern(_, let density) = self { return density }
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
    public static let modernConfigs: [GameConfig] =
        BoardSize.allCases.flatMap { size in
            Density.allCases.map { GameConfig.modern(size, $0) }
        }

    // Convenience shortcuts for the classic presets.
    public static let beginner = GameConfig.classic(.beginner)
    public static let intermediate = GameConfig.classic(.intermediate)
    public static let expert = GameConfig.classic(.expert)
}
