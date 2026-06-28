import Foundation

/// The camera view to restore with a saved game, stored window-independently so
/// it restores sensibly on another window size or device:
/// - `centerX` / `centerY` are the camera centre as a normalized board point
///   (0…1), re-clamped to the new viewport by the renderer.
/// - `scale` is world-units-per-point (bigger = more zoomed out), a window-size-
///   independent ratio, so it restores as-is.
public struct CameraView: Codable, Sendable, Equatable {
    public let centerX: Double
    public let centerY: Double
    public let scale: Double

    public init(centerX: Double, centerY: Double, scale: Double) {
        self.centerX = centerX
        self.centerY = centerY
        self.scale = scale
    }
}

/// A compact, `Codable` capture of an in-progress game. Stores the *config*
/// (carrying topology kind + params, so `any Topology` is never encoded) plus the
/// mine layout and revealed/flagged cells as coordinate sets — far smaller than
/// the full cell dictionary on huge boards.
///
/// Format is **additive**: new fields are optional-with-default, so an older save
/// still restores (`SaveStore.load` accepts `version <= currentVersion`). Only
/// `config` and `mines` are required; without them decode throws and the save is
/// discarded. Bump `currentVersion` only for a *breaking* change, so older apps
/// then refuse a newer save rather than mis-read it.
public struct GameSnapshot: Codable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let config: GameConfig
    public let mines: Set<Coord>
    public let revealed: Set<Coord>
    public let flagged: Set<Coord>
    public let status: GameStatus
    public let revealedSafeCount: Int
    public let lossCoord: Coord?
    /// Banked play time; the live span is always folded in before saving.
    public let elapsedCentiseconds: Int
    /// The camera view to restore, or nil if none was captured (older saves, or a
    /// board that fits the viewport).
    public let camera: CameraView?
    /// The dig/flag input mode the player left on, so a resumed game keeps it
    /// (defaults to `.reveal` for older saves).
    public let inputMode: InputMode

    /// Tolerant decode: `config` + `mines` required; everything else defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        config = try c.decode(GameConfig.self, forKey: .config)
        mines = try c.decode(Set<Coord>.self, forKey: .mines)
        revealed = try c.decodeIfPresent(Set<Coord>.self, forKey: .revealed) ?? []
        flagged = try c.decodeIfPresent(Set<Coord>.self, forKey: .flagged) ?? []
        status = try c.decodeIfPresent(GameStatus.self, forKey: .status) ?? .playing
        revealedSafeCount = try c.decodeIfPresent(Int.self, forKey: .revealedSafeCount) ?? 0
        lossCoord = try c.decodeIfPresent(Coord.self, forKey: .lossCoord)
        elapsedCentiseconds =
            try c.decodeIfPresent(Int.self, forKey: .elapsedCentiseconds) ?? 0
        camera = try c.decodeIfPresent(CameraView.self, forKey: .camera)
        inputMode = try c.decodeIfPresent(InputMode.self, forKey: .inputMode) ?? .reveal
    }

    /// Capture a snapshot of a live game; nil unless it's genuinely in progress.
    public init?(
        game: Game, config: GameConfig, elapsedCentiseconds: Int, camera: CameraView? = nil,
        inputMode: InputMode = .reveal
    ) {
        guard game.status == .playing else { return nil }
        self.version = Self.currentVersion
        self.config = config
        self.mines = game.board.mineCoords
        self.revealed = game.board.revealedCoords
        self.flagged = game.board.flaggedCoords
        self.status = game.status
        self.revealedSafeCount = game.revealedSafeCount
        self.lossCoord = game.lossCoord
        self.elapsedCentiseconds = elapsedCentiseconds
        self.camera = camera
        self.inputMode = inputMode
    }

    /// Rebuild the `Game` this snapshot describes (topology from the config).
    public func makeGame() -> Game {
        Game.restored(from: self)
    }

    /// Migration seam for a future *breaking* change: when `currentVersion` is
    /// bumped, transform an older-`version` snapshot up to the current shape here.
    /// Identity today.
    public func migrated() -> GameSnapshot {
        self
    }
}
