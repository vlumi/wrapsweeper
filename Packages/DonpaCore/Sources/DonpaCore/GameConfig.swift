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
}

/// Modern board sizes (square). Side lengths chosen via solver analysis.
public enum BoardSize: String, CaseIterable, Sendable, Codable {
    case small, medium, large

    var side: Int {
        switch self {
        case .small: return 9
        case .medium: return 16
        case .large: return 25
        }
    }

    public var label: String {
        switch self {
        case .small: return String(localized: "Small", bundle: .module)
        case .medium: return String(localized: "Medium", bundle: .module)
        case .large: return String(localized: "Large", bundle: .module)
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
    /// axes will select hex/wrapped topologies later.
    public var topology: any Topology {
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
