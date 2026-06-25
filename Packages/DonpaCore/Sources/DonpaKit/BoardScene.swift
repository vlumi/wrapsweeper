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
    /// Board revision the overview image was last rendered for (rebuild on change).
    var lastMinimapRevision = -1
    /// Cached board size the minimap was built for, to detect new-game/resize.
    var lastMinimapBoard: CGSize = .zero

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
        addChild(boardLayer)
        addChild(glowLayer)  // above tiles…
        addChild(effectsLayer)  // …but below end-game effects
        addChild(cameraNode)
        camera = cameraNode
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func didMove(to view: SKView) {
        super.didMove(to: view)
        rebuildIfNeeded()
        centerCamera()
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
        centerCamera()
    }

    // MARK: Input mapping

    /// Scene-space point → board coordinate (accounting for the board layer).
    public func coord(atScenePoint p: CGPoint) -> Coord? {
        let local = boardLayer.convert(p, from: self)
        guard let c = layout.coord(at: local), viewModel.game.board.cellCount > 0 else {
            return nil
        }
        return c
    }

    private func flag(atScenePoint p: CGPoint) {
        guard let c = coord(atScenePoint: p) else { return }
        viewModel.toggleFlag(c)
    }

    /// A plain tap/click. A revealed number always chords; a hidden cell does
    /// whatever the current input mode says (reveal or flag). This is the
    /// safety mechanism: in Flag mode a stray tap can't open a tile.
    private func tapAction(atScenePoint p: CGPoint) {
        guard let c = coord(atScenePoint: p) else { return }
        if viewModel.game.board[c].state == .revealed {
            viewModel.chord(c)
        } else {
            switch viewModel.inputMode {
            case .reveal: viewModel.reveal(c)
            case .flag: viewModel.toggleFlag(c)
            }
        }
    }

    /// A long-press: the opposite primary action to the current mode on a
    /// hidden cell (flag in Reveal mode, reveal in Flag mode). On a revealed
    /// number it chords, same as a tap, so it's never a dead gesture.
    private func longPressAction(atScenePoint p: CGPoint) {
        guard let c = coord(atScenePoint: p) else { return }
        if viewModel.game.board[c].state == .revealed {
            viewModel.chord(c)
        } else {
            switch viewModel.inputMode {
            case .reveal: viewModel.toggleFlag(c)
            case .flag: viewModel.reveal(c)
            }
        }
    }

    /// Map a point in the hosting view's coordinates to scene space. `SKView`
    /// owns the view↔scene transform (Y-flip + camera), so we let it do the work.
    private func scenePoint(fromViewPoint p: CGPoint) -> CGPoint {
        convertPoint(fromView: p)
    }

    // MARK: Gesture recognizers (pan + zoom)

    private func installGestureRecognizers(on view: SKView) {
        #if os(iOS)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        pan.maximumNumberOfTouches = 2
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch))
        // Single tap reveals a hidden cell or chords a revealed number; no
        // double-tap, so taps fire immediately with no timeout.
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        let long = UILongPressGestureRecognizer(target: self, action: #selector(handleLong))
        long.minimumPressDuration = 0.3
        for g in [pan, pinch, tap, long] as [UIGestureRecognizer] {
            view.addGestureRecognizer(g)
        }
        #elseif os(macOS)
        // Clicks, drag-to-pan, and right-click are handled directly via mouse
        // events (mouseDown/Dragged/Up below). Only zoom needs a recognizer.
        let pinch = NSMagnificationGestureRecognizer(target: self, action: #selector(handlePinch))
        view.addGestureRecognizer(pinch)
        #endif
    }

    #if os(iOS)
    private var lastPan: CGPoint = .zero

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: g.view)
        if g.state == .began { lastPan = .zero }
        pan(byTranslation: CGPoint(x: t.x - lastPan.x, y: t.y - lastPan.y))
        lastPan = t
        if g.state == .ended || g.state == .cancelled { panEnded() }
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        zoom(by: g.scale)
        g.scale = 1
    }

    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        tapAction(atScenePoint: scenePoint(fromViewPoint: g.location(in: g.view)))
    }

    @objc private func handleLong(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        longPressAction(atScenePoint: scenePoint(fromViewPoint: g.location(in: g.view)))
    }
    #elseif os(macOS)
    @objc private func handlePinch(_ g: NSMagnificationGestureRecognizer) {
        zoom(by: 1 + g.magnification)
        g.magnification = 0
    }

    /// Two-finger trackpad swipe (or mouse wheel) pans the camera, the way
    /// Maps and Preview behave. Precise deltas come from the trackpad; a plain
    /// wheel reports coarse line deltas, so scale those up.
    public override func scrollWheel(with event: NSEvent) {
        let step: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
        // Natural-scroll convention: content follows the fingers. AppKit's Y
        // grows upward, matching the scene, so pass deltas through directly.
        pan(
            byTranslation: CGPoint(
                x: event.scrollingDeltaX * step, y: event.scrollingDeltaY * step))
        // Spring back when the trackpad gesture (and its momentum) finishes.
        if event.phase == .ended || event.momentumPhase == .ended { panEnded() }
    }

    // Left mouse: a press that stays put is a click (reveal/flag/chord); a press
    // that moves past a small threshold is a drag-pan (and suppresses the click).
    // Right/Control-click always flags. The threshold matters: a normal click
    // carries a pixel or two of jitter, which must NOT count as a drag or clicks
    // get eaten. `SKScene` reports event locations already in scene space.
    private var lastDragViewPoint: CGPoint = .zero
    private var mouseDownViewPoint: CGPoint = .zero
    private var didDragInScene = false
    private static let dragThreshold: CGFloat = 4

    public override func mouseDown(with event: NSEvent) {
        let p = view?.convert(event.locationInWindow, from: nil) ?? .zero
        lastDragViewPoint = p
        mouseDownViewPoint = p
        didDragInScene = false
    }

    public override func mouseDragged(with event: NSEvent) {
        // Grab model: content follows the cursor, so the camera moves opposite to
        // the cursor. Use the view-space delta (camera-independent) and let
        // pan() scale it by the current zoom. AppKit view Y grows upward, which
        // matches the scene, so no Y flip is needed.
        guard let view = view else { return }
        let p = view.convert(event.locationInWindow, from: nil)
        // Only become a drag once movement clears the threshold, so click jitter
        // doesn't suppress the click.
        if !didDragInScene {
            let moved = hypot(p.x - mouseDownViewPoint.x, p.y - mouseDownViewPoint.y)
            guard moved > Self.dragThreshold else { return }
            didDragInScene = true
        }
        // pan() applies +Y to the camera; negate so a grab drag moves content
        // with the cursor on both axes.
        pan(byTranslation: CGPoint(x: p.x - lastDragViewPoint.x, y: -(p.y - lastDragViewPoint.y)))
        lastDragViewPoint = p
    }

    public override func mouseUp(with event: NSEvent) {
        if didDragInScene { panEnded() }  // spring back if the drag overshot the edge
        guard !didDragInScene else { return }  // a real drag panned; don't also click
        let p = event.location(in: self)
        // Control is the temporary "other action" modifier (matching the cursor,
        // which flips to the other mode while Ctrl is held): in Reveal mode it
        // flags, in Flag mode it reveals — i.e. the long-press action.
        if NSEvent.modifierFlags.contains(.control) {
            longPressAction(atScenePoint: p)
        } else {
            tapAction(atScenePoint: p)
        }
    }

    public override func rightMouseUp(with event: NSEvent) {
        flag(atScenePoint: event.location(in: self))
    }

    // The scene handles key input directly: SwiftUI menu shortcuts for bare keys
    // don't fire reliably, but the scene is in the responder chain for its
    // gesture recognizers and receives key events here. Space toggles reveal/flag
    // mode; Esc pauses/resumes mid-play. (Restarting a finished board is ⌘R.)
    public override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 49:  // Space
            viewModel.inputMode.toggle()
        case 53:  // Escape
            if viewModel.isPaused {
                viewModel.resume()
            } else {
                viewModel.pause()
            }
        default:
            super.keyDown(with: event)
        }
    }
    #endif
}
