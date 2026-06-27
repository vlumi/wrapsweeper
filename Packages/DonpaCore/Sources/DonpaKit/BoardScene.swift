import DonpaCore
import SpriteKit

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Renders the board with an `SKCameraNode` for pan/zoom. Cell nodes are rebuilt
/// from the view model whenever its revision changes.
public final class BoardScene: SKScene {
    // Accessible to the BoardScene+Effects extension (same module).
    let viewModel: GameViewModel
    let layout: any CellLayout
    let cameraNode = SKCameraNode()  // internal: pan/zoom lives in BoardScene+Pan
    let boardLayer = SKNode()
    /// End-of-game effects live here, a sibling of `boardLayer`, so `rebuild()`
    /// (which clears `boardLayer`, including on every palette push) never wipes
    /// an in-flight animation.
    let effectsLayer = SKNode()
    /// Mode-glow hint (teal dig / orange flag) washed over the unopened tiles, a
    /// sibling above `boardLayer` so it tints over the tiles, below `effectsLayer`
    /// so end-game effects win. Never wiped by `rebuild()`.
    let glowLayer = SKNode()
    // Render state — read/written by the rendering methods in BoardScene+Render
    // (a separate file), so these are internal rather than private.
    var lastRevision = -1
    var lastGameID = -1
    var lastAnimatedResultID = -1
    /// The cell nodes currently built and parented under `boardLayer`, keyed by
    /// coord. Only **visible** cells (camera rect + margin) are built — on a huge
    /// board the live node count stays ~one screenful regardless of board size.
    /// When the whole board fits the viewport (every small/classic board), the
    /// visible range is the whole board, so this holds every cell exactly as a
    /// full rebuild would — culling is invisible at those sizes.
    var cellNodes: [Coord: SKNode] = [:]
    /// The cell range last built, so a viewport change only touches the delta.
    var builtRange: CellRange?
    // Mode-glow state, compared each frame so the glow only rebuilds on change.
    // Internal so the +Effects extension (which owns the glow) can read/write.
    var lastGlowMode: InputMode?
    var lastGlowLive: Bool?
    var lastGlowRevision = -1
    /// The visible range the glow was last stamped for — so it re-stamps when the
    /// viewport scrolls new hidden tiles in, not only on mode/revision change.
    var lastGlowRange: CellRange?
    /// Cached halftone wash textures, keyed by mode + a cell-size/appearance tag,
    /// so the screentone is built once and reused across every hidden tile.
    var glowTextureCache: [String: SKTexture] = [:]
    /// Cached tile-background and glyph textures, keyed by role + pixel size +
    /// colour (so light/dark and size changes miss the cache and rebuild, like
    /// the glow cache). Every visible cell is an `SKSpriteNode` sharing one of
    /// these — SpriteKit batches same-texture sprites into one draw call, far
    /// cheaper than a per-cell `SKShapeNode` (the old hot spot on big boards).
    var tileTextureCache: [String: SKTexture] = [:]

    // Minimap (overview) — a corner thumbnail of the whole board with a rectangle
    // marking the visible viewport, shown only when the board exceeds the view.
    // Lives in BoardScene+Minimap; pinned to the camera so it's fixed on screen.
    /// Container pinned to the camera (built lazily in the +Minimap extension).
    var minimapNode: SKNode?
    /// Opaque background panel behind the overview, so it reads as a HUD element.
    var minimapPanel: SKShapeNode?
    /// The overview image sprite inside `minimapNode`, rebuilt on board change.
    var minimapImage: SKSpriteNode?
    /// The "you are here" viewport rectangle, repositioned each frame.
    var minimapViewport: SKShapeNode?
    /// Small expand-icon node in the minimap corner — tap it to open the overview.
    var minimapExpand: SKNode?
    /// The expand icon's hit rect in CAMERA space (screen-fixed), set in layout so
    /// the tap handler can test against it. nil while the minimap is hidden.
    var minimapExpandHitRect: CGRect?
    /// Board revision the overview image was last rendered for (rebuild on change).
    var lastMinimapRevision = -1
    /// Cached board size the minimap was built for, to detect new-game/resize.
    var lastMinimapBoard: CGSize = .zero
    /// User preference (pushed from the chrome's toolbar toggle, via BoardView):
    /// show the minimap when the board exceeds the viewport. Default on.
    var showMinimap = true
    /// Called when the minimap's expand icon is tapped — the host opens the
    /// fullscreen overview. Set by `GameContent` via `BoardView`.
    var onOpenOverview: (() -> Void)?

    /// A saved camera view (centre + zoom) to hold onto across the launch dance,
    /// instead of the default fit. It's STICKY rather than one-shot: the window
    /// settles to its restored frame *after* the scene mounts, firing `didMove`
    /// and `didChangeSize`, each of which would otherwise re-centre — so the
    /// target is re-applied (re-clamped to the new size) at every such point until
    /// the player actually pans/zooms (or starts a new game), then it's cleared.
    var restoreCameraTarget: CameraView?

    /// The active color palette. Set by the host when the system appearance
    /// changes; updating it recolors the background and rebuilds the cells.
    public var palette: Palette = .dark {
        didSet {
            backgroundColor = palette.sceneBackground
            rebuild()
            lastGlowMode = nil  // force the glow to recolor from the new palette
        }
    }

    public init(viewModel: GameViewModel, layout: any CellLayout = SquareLayout()) {
        self.viewModel = viewModel
        self.layout = layout
        super.init(size: CGSize(width: 320, height: 320))
        scaleMode = .resizeFill
        backgroundColor = palette.sceneBackground
        // Layer order is by zPosition, NOT add-order: the SKView sets
        // `ignoresSiblingOrder = true` (a batching win), so equal-z siblings draw
        // in an undefined order. The cell tiles are opaque `SKSpriteNode`s; without
        // an explicit higher z the glow's `SKShapeNode` tiles batch *under* them and
        // vanish (the same trap the per-cell overlays hit — see BoardScene+Render).
        boardLayer.zPosition = 0
        glowLayer.zPosition = 1  // above tiles…
        effectsLayer.zPosition = 2  // …but below end-game effects
        addChild(boardLayer)
        addChild(glowLayer)
        addChild(effectsLayer)
        addChild(cameraNode)
        camera = cameraNode
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func didMove(to view: SKView) {
        super.didMove(to: view)
        rebuildIfNeeded()
        applyDesiredCameraOrCenter()
        installGestureRecognizers(on: view)
        #if os(macOS)
        // Take first responder so the scene receives key events (Space) without
        // the user having to click the board first.
        view.window?.makeFirstResponder(view)
        #endif
    }

    public override func update(_ currentTime: TimeInterval) {
        rebuildIfNeeded()
        // Cull to the current viewport every frame: cheap no-op unless the camera
        // moved (guarded by `builtRange`), and it catches pan, zoom, and the
        // animated spring-back without each having to call in.
        buildVisibleCells()
        refreshModeGlow()
        refreshMinimap()
        // Keep the view model's live camera view current (after any restore in
        // rebuildIfNeeded), so an autosave persists where the player is looking.
        viewModel.cameraView = currentCameraView()
    }

    // MARK: Rendering — cell nodes + viewport culling live in BoardScene+Render.

    /// Play a one-shot end-game animation (implemented in BoardScene+Effects).
    func playEndGameEffects(_ result: GameResult) {
        effectsLayer.removeAllChildren()
        switch result {
        case .lost(let at): playLoss(trigger: at, reduceMotion: Self.prefersReducedMotion)
        case .won: playWin(reduceMotion: Self.prefersReducedMotion)
        }
    }

    // MARK: Camera

    /// The on-screen cell-size cap is *relative to the window*: a small board may
    /// grow to fill a big/full-screen window with large cells, but no single cell
    /// exceeds this fraction of the viewport's smaller side — so a tiny board
    /// (e.g. 2×2) can't blow up to where a couple of cells fill the screen.
    private static let maxCellFractionOfViewport: CGFloat = 0.22
    /// Absolute ceiling so even on a huge display cells stay reasonable.
    private static let absoluteMaxCellSize: CGFloat = 140
    /// Cap on how many cells the *initial* zoom shows at once. The render cost is
    /// per-visible-cell (one SKNode each, culled to the viewport), so bounding the
    /// visible count — not the cell size — is what keeps a fresh huge board fast
    /// regardless of window size. A bigger window shows the same ~count of bigger
    /// cells, not more cells.
    private static let maxStartVisibleCells: CGFloat = 600
    /// Absolute floor so a cell never *starts* smaller than comfortably tappable
    /// (~28pt — a bit under the 44pt HIG target, fine for a grid you can zoom).
    /// A huge board opens showing fewer, tappable cells rather than a sea of
    /// untappable ones; the player can still zoom further out manually.
    private static let minStartCellSize: CGFloat = 28
    /// When the board exceeds the viewport, the start zoom is nudged in by this
    /// factor so edge cells are clipped mid-cell — signalling the board continues
    /// past the edges instead of looking complete. <1 because scale is
    /// world-units-per-point (smaller scale = more zoomed in).
    private static let edgePeekZoom: CGFloat = 0.92
    /// Smallest on-screen cell size (points) reachable by manual zoom-OUT — only a
    /// little below the ~28pt start floor, so there's a small buffer past the
    /// opening view but it never reaches the tiny/choppy range (sub-20pt cells on
    /// a huge board, where the whole grid becomes visible and laggy). The
    /// whole-board overview is the future minimap's job, not deep zoom-out.
    private static let minInteractiveCellSize: CGFloat = 22

    /// The most zoomed-OUT camera scale allowed: the larger of "whole board fits"
    /// and "cells at the min interactive size" is the *smaller* scale (more zoomed
    /// in), so we clamp to whichever keeps cells tappable. For a board that fits at
    /// a comfortable size this is `fitScale` (unchanged); for a huge board it stops
    /// zoom-out before cells get too small to tap (and before the node count
    /// explodes). Internal so BoardScene+Pan's `zoom`/clamps use it.
    var maxZoomOutScale: CGFloat {
        let interactiveLimit = layout.cellSize / Self.minInteractiveCellSize
        return min(fitScale, interactiveLimit)
    }

    // Internal so BoardScene+Pan (which owns pan/zoom/clamp) can reach them.
    func centerCamera() {
        let board = layout.boardSize(width: viewModel.boardWidth, height: viewModel.boardHeight)
        cameraNode.position = CGPoint(x: board.width / 2, y: board.height / 2)
        // Camera scale = world-units-per-point; a larger scale is more zoomed out,
        // and on-screen cell size = layout.cellSize / scale.
        let viewportMin = min(size.width, size.height)
        // Biggest cells allowed (don't let a tiny board blow up) → smallest scale.
        let maxCell = min(
            Self.absoluteMaxCellSize, max(40, viewportMin * Self.maxCellFractionOfViewport))
        let cellFloor = layout.cellSize / maxCell
        // Smallest on-screen cell the start zoom uses: large enough that no more
        // than `maxStartVisibleCells` fit the viewport (so the node count is
        // bounded on any window size), but never below the legibility floor.
        let area = max(1, size.width * size.height)
        let startCell = max(Self.minStartCellSize, (area / Self.maxStartVisibleCells).squareRoot())
        let cellCeiling = layout.cellSize / startCell
        // Prefer to fit the whole board, but clamp into [cellFloor, cellCeiling]:
        // never bigger than maxCell, never so small the viewport shows > the cap.
        var scale = min(max(fitScale, cellFloor), cellCeiling)
        // When the board is bigger than the viewport (we're not fitting the whole
        // thing), nudge the zoom in (smaller scale) so the edge cells are clipped
        // mid-cell — a visual cue that the board continues past the edges. Skip it
        // when the whole board fits (nothing beyond the edge to hint at).
        if scale < fitScale {
            scale *= Self.edgePeekZoom
        }
        cameraNode.setScale(scale)
    }

    /// Smallest scale that still fits the whole board (the zoomed-out limit).
    var fitScale: CGFloat {
        let board = layout.boardSize(width: viewModel.boardWidth, height: viewModel.boardHeight)
        guard size.width > 0, size.height > 0,
            board.width > 0, board.height > 0
        else { return 1 }
        let margin: CGFloat = 1.1
        return max(board.width * margin / size.width, board.height * margin / size.height)
    }

    public override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        applyDesiredCameraOrCenter()
    }

    // Input mapping, gestures, and mouse/keyboard handling live in
    // BoardScene+Input.swift. The mutable state those handlers use is declared
    // here (extensions can't hold stored properties):
    #if os(iOS)
    var lastPan: CGPoint = .zero
    #elseif os(macOS)
    // Left mouse: a press that stays put is a click; a press that moves past a
    // small threshold is a drag-pan (and suppresses the click). The threshold
    // matters — a normal click carries a pixel or two of jitter, which must NOT
    // count as a drag or clicks get eaten.
    var lastDragViewPoint: CGPoint = .zero
    var mouseDownViewPoint: CGPoint = .zero
    var didDragInScene = false
    static let dragThreshold: CGFloat = 4
    #endif
}
