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

/// Board width/height/mine-count, computed from a `GameConfig`.
public struct BoardDimensions: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let mines: Int
}

public enum ClassicPreset: String, CaseIterable, Sendable {
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
        case .beginner: return "Beginner"
        case .intermediate: return "Intermediate"
        case .expert: return "Expert"
        }
    }
}

/// Modern board sizes (square). Side lengths chosen via solver analysis.
public enum BoardSize: String, CaseIterable, Sendable {
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
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }
}

/// Modern difficulty = mine density (fraction of cells). Tiers chosen via solver
/// analysis to ramp from fair (Easy) to near-unsolvable-by-logic (Insane).
public enum Density: String, CaseIterable, Sendable {
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

    public var label: String {
        switch self {
        case .easy: return "Easy"
        case .normal: return "Normal"
        case .hard: return "Hard"
        case .brutal: return "Brutal"
        case .insane: return "Insane"
        }
    }
}

/// Topology axes — only one value each ships now; the rest exist so the storage
/// key can name them explicitly and stay forward-compatible.
public enum BoardShape: String, Sendable { case square = "sq" }
public enum BoardEdges: String, Sendable { case bounded }

public enum GameConfig: Hashable, Sendable {
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
