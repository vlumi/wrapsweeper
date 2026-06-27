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
    let viewModel: GameViewModel
    let layout: any CellLayout
    let cameraNode = SKCameraNode()
    let boardLayer = SKNode()
    /// End-game effects, a sibling of `boardLayer` so `rebuild()` (which clears
    /// `boardLayer`) never wipes an in-flight animation.
    let effectsLayer = SKNode()
    /// Mode-glow wash over unopened tiles: above `boardLayer`, below `effectsLayer`.
    /// Never wiped by `rebuild()`.
    let glowLayer = SKNode()
    // Render state — read/written by BoardScene+Render.
    var lastRevision = -1
    var lastGameID = -1
    var lastAnimatedResultID = -1
    /// Built cell nodes under `boardLayer`, keyed by coord. Only **visible** cells
    /// (camera rect + margin) are built, so the live node count stays ~one
    /// screenful regardless of board size. A board that fits holds every cell.
    var cellNodes: [Coord: SKNode] = [:]
    /// The cell range last built, so a viewport change only touches the delta.
    var builtRange: CellRange?
    // Mode-glow state, compared each frame so the glow only rebuilds on change.
    var lastGlowMode: InputMode?
    var lastGlowLive: Bool?
    var lastGlowRevision = -1
    /// Visible range the glow was last stamped for, so it re-stamps on scroll too.
    var lastGlowRange: CellRange?
    /// Screentone wash textures, keyed by mode + cell-size/appearance tag.
    var glowTextureCache: [String: SKTexture] = [:]
    /// Tile-background and glyph textures, keyed by role + pixel size + colour.
    /// Every visible cell is an `SKSpriteNode` sharing one of these, so SpriteKit
    /// batches same-texture sprites into one draw call (cheaper than per-cell
    /// `SKShapeNode` on big boards).
    var tileTextureCache: [String: SKTexture] = [:]

    // Minimap — corner thumbnail of the whole board with a viewport rectangle,
    // shown only when the board exceeds the view. Lives in BoardScene+Minimap;
    // pinned to the camera so it's screen-fixed.
    var minimapNode: SKNode?
    var minimapPanel: SKShapeNode?
    var minimapImage: SKSpriteNode?
    var minimapViewport: SKShapeNode?
    var minimapExpand: SKNode?
    /// The expand icon's hit rect in CAMERA space (screen-fixed); nil while hidden.
    var minimapExpandHitRect: CGRect?
    var lastMinimapRevision = -1
    var lastMinimapBoard: CGSize = .zero
    /// Show the minimap when the board exceeds the viewport (user preference).
    var showMinimap = true
    /// Called when the minimap's expand icon is tapped — the host opens the
    /// fullscreen overview.
    var onOpenOverview: (() -> Void)?

    /// A saved camera view to hold across the launch dance instead of the default
    /// fit. STICKY: the window settles to its restored frame *after* the scene
    /// mounts, firing `didMove`/`didChangeSize` which would each re-centre — so the
    /// target is re-applied at every such point until the player pans/zooms (or
    /// starts a new game), then cleared.
    var restoreCameraTarget: CameraView?

    /// Set by the host on appearance change; recolors the background and rebuilds.
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
        // Layer order is by zPosition, not add-order: the SKView sets
        // `ignoresSiblingOrder = true`, so equal-z siblings draw in undefined order.
        // Without an explicit higher z the glow's `SKShapeNode` tiles batch under
        // the opaque sprite tiles and vanish.
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
        // Cull to the viewport every frame (no-op unless the camera moved); catches
        // pan, zoom, and the animated spring-back without each calling in.
        buildVisibleCells()
        refreshModeGlow()
        refreshMinimap()
        // Keep the live camera view current so an autosave persists the view.
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

    /// Max on-screen cell size as a fraction of the viewport's smaller side, so a
    /// tiny board can't blow up to where a few cells fill the screen.
    private static let maxCellFractionOfViewport: CGFloat = 0.22
    private static let absoluteMaxCellSize: CGFloat = 140
    /// Cap on cells the *initial* zoom shows. Render cost is per-visible-cell, so
    /// bounding the visible count (not cell size) keeps a fresh huge board fast on
    /// any window size.
    private static let maxStartVisibleCells: CGFloat = 600
    /// Floor so a cell never *starts* smaller than comfortably tappable; the player
    /// can still zoom further out manually.
    private static let minStartCellSize: CGFloat = 28
    /// When the board exceeds the viewport, nudge the start zoom in so edge cells
    /// clip mid-cell, signalling the board continues. <1 because scale is
    /// world-units-per-point (smaller = more zoomed in).
    private static let edgePeekZoom: CGFloat = 0.92
    /// Smallest on-screen cell reachable by manual zoom-out — a small buffer past
    /// the start floor, never into the tiny/choppy range on a huge board.
    private static let minInteractiveCellSize: CGFloat = 22

    /// Most zoomed-out scale allowed: whichever of "whole board fits" / "cells at
    /// the min interactive size" keeps cells tappable (the smaller scale).
    var maxZoomOutScale: CGFloat {
        let interactiveLimit = layout.cellSize / Self.minInteractiveCellSize
        return min(fitScale, interactiveLimit)
    }

    func centerCamera() {
        let board = layout.boardSize(width: viewModel.boardWidth, height: viewModel.boardHeight)
        cameraNode.position = CGPoint(x: board.width / 2, y: board.height / 2)
        // Scale = world-units-per-point; larger = more zoomed out, cell size =
        // layout.cellSize / scale.
        let viewportMin = min(size.width, size.height)
        let maxCell = min(
            Self.absoluteMaxCellSize, max(40, viewportMin * Self.maxCellFractionOfViewport))
        let cellFloor = layout.cellSize / maxCell
        // Start cell large enough that no more than `maxStartVisibleCells` fit, but
        // never below the legibility floor.
        let area = max(1, size.width * size.height)
        let startCell = max(Self.minStartCellSize, (area / Self.maxStartVisibleCells).squareRoot())
        let cellCeiling = layout.cellSize / startCell
        // Prefer to fit the whole board, clamped into [cellFloor, cellCeiling].
        var scale = min(max(fitScale, cellFloor), cellCeiling)
        // Board bigger than the viewport: nudge zoom in so edge cells clip mid-cell.
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

    // Input/gesture/mouse/keyboard handling lives in BoardScene+Input.swift; the
    // mutable state it uses is declared here (extensions can't hold stored props).
    #if os(iOS)
    var lastPan: CGPoint = .zero
    #elseif os(macOS)
    // Left mouse: a press that stays put is a click; one that moves past the
    // threshold is a drag-pan (suppressing the click). The threshold absorbs the
    // pixel or two of click jitter that must not count as a drag.
    var lastDragViewPoint: CGPoint = .zero
    var mouseDownViewPoint: CGPoint = .zero
    var didDragInScene = false
    static let dragThreshold: CGFloat = 4
    #endif
}
