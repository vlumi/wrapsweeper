import Foundation

/// The camera view to restore with a saved game: where the player was looking
/// and how far zoomed in. Stored window-independently so a game saved on one
/// window size (or device) restores sensibly on another:
/// - `centerX` / `centerY` are the camera centre as a **normalized board point**
///   (0…1 of board width/height), so the same board point is recentred regardless
///   of window size; the renderer re-clamps it to the new viewport's bounds.
/// - `scale` is the camera's world-units-per-point (bigger = more zoomed out) —
///   a board↔point ratio, independent of window size, so it restores as-is.
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

/// A compact, `Codable` capture of an in-progress game, for save/restore across
/// app launches. Stores the *config* (which carries the topology kind + params,
/// so the existential `any Topology` is never encoded) plus the placed mine
/// layout and the revealed/flagged cells as coordinate sets — far smaller than
/// the full cell dictionary, and the safe path on huge boards.
///
/// **Forward/backward compatibility.** The format is **additive**: new fields are
/// added as optional-with-default and `decode` tolerates their absence, so a save
/// written by an older app still restores in a newer one (`SaveStore.load`
/// accepts `version <= currentVersion`). Two essentials — `config` and `mines` —
/// are required; without them there's no game to rebuild, so a save missing them
/// is rejected (decode throws → discarded). **Bump `currentVersion` only for a
/// breaking change** (removing/repurposing a field): older apps then refuse the
/// newer save rather than mis-read it.
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
    /// The camera view (centre + zoom) to restore, or nil if none was captured
    /// (older saves, or a board that fits the viewport so the camera is locked
    /// centred anyway). Additive + optional, so older saves still decode.
    public let camera: CameraView?

    /// Tolerant decode: `config` + `mines` are required (no game without them);
    /// everything else defaults if absent, so older/forward saves still load.
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
    }

    /// Capture a snapshot of a live game. Returns nil for a game not worth saving
    /// (not started, or already finished) — only a genuine in-progress game is.
    public init?(
        game: Game, config: GameConfig, elapsedCentiseconds: Int, camera: CameraView? = nil
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
    }

    /// Rebuild the `Game` this snapshot describes (topology from the config).
    public func makeGame() -> Game {
        Game.restored(from: self)
    }

    /// Migration seam, mirroring `Scoreboard`. Additive changes are handled by
    /// the tolerant decoder above; this is for a future *breaking* change — when
    /// `currentVersion` is bumped, transform a snapshot decoded at its older
    /// `version` up to the current shape here (one step per version), with
    /// fixture-based tests. Identity today (no breaking changes yet).
    public func migrated() -> GameSnapshot {
        self
    }
}
