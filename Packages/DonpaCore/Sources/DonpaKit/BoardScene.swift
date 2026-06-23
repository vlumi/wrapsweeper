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
    private var lastRevision = -1
    private var lastGameID = -1
    private var lastAnimatedResultID = -1

    /// The active color palette. Set by the host when the system appearance
    /// changes; updating it recolors the background and rebuilds the cells.
    public var palette: Palette = .dark {
        didSet {
            backgroundColor = palette.sceneBackground
            rebuild()
        }
    }

    public init(viewModel: GameViewModel, layout: any CellLayout = SquareLayout()) {
        self.viewModel = viewModel
        self.layout = layout
        super.init(size: CGSize(width: 320, height: 320))
        scaleMode = .resizeFill
        backgroundColor = palette.sceneBackground
        addChild(boardLayer)
        addChild(effectsLayer)
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
    }

    // MARK: Rendering

    private func rebuildIfNeeded() {
        if viewModel.gameID != lastGameID {
            lastGameID = viewModel.gameID
            lastAnimatedResultID = -1  // a fresh game can animate its own result
            effectsLayer.removeAllChildren()
            boardLayer.position = .zero  // clear any leftover shake offset
            centerCamera()
        }
        if viewModel.revision != lastRevision {
            lastRevision = viewModel.revision
            rebuild()
        }
        // After the board reflects the final state, play the end-game effect
        // once. No further revisions occur post-end, so this fires exactly once.
        if let event = viewModel.lastResult, event.id != lastAnimatedResultID {
            lastAnimatedResultID = event.id
            playEndGameEffects(event.result)
        }
    }

    private func rebuild() {
        boardLayer.removeAllChildren()
        let game = viewModel.game
        for c in game.board.allCoords {
            let node = cellNode(for: c, cell: game.board[c])
            node.position = layout.center(of: c)
            boardLayer.addChild(node)
        }
    }

    private func cellNode(for coord: Coord, cell: Cell) -> SKNode {
        let size = layout.cellSize
        let container = SKNode()
        let inset: CGFloat = 1
        let rect = CGRect(
            x: -size / 2 + inset, y: -size / 2 + inset,
            width: size - inset * 2, height: size - inset * 2)
        let tile = SKShapeNode(rect: rect, cornerRadius: 3)
        tile.lineWidth = 0
        tile.fillColor = fillColor(for: cell)
        container.addChild(tile)

        // The mine you hit gets the manga burst (icon motif, flat); other mines
        // keep the plain ✸.
        if cell.state == .revealed, cell.isMine, coord == viewModel.game.lossCoord {
            container.addChild(burstMineNode(size: size))
        } else if let glyph = glyph(for: cell) {
            let label = SKLabelNode(text: glyph.text)
            label.fontName = "Menlo-Bold"
            label.fontSize = size * 0.5
            label.fontColor = glyph.color
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            container.addChild(label)
        }
        return container
    }

    private func fillColor(for cell: Cell) -> SKColor {
        switch cell.state {
        case .hidden, .flagged:
            return palette.hiddenTile
        case .revealed:
            return cell.isMine ? palette.mineTile : palette.revealedTile
        }
    }

    private func glyph(for cell: Cell) -> (text: String, color: SKColor)? {
        switch cell.state {
        case .flagged:
            return ("⚑", palette.flagGlyph)
        case .hidden:
            return nil
        case .revealed:
            if cell.isMine { return ("✸", palette.mineGlyph) }
            guard cell.adjacentMines > 0 else { return nil }
            return (String(cell.adjacentMines), palette.number(cell.adjacentMines))
        }
    }

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

    // Internal so BoardScene+Pan (which owns pan/zoom/clamp) can reach them.
    func centerCamera() {
        let board = layout.boardSize(width: viewModel.boardWidth, height: viewModel.boardHeight)
        cameraNode.position = CGPoint(x: board.width / 2, y: board.height / 2)
        // Camera scale = world-units-per-point; bigger = more zoomed out.
        // `fitScale` fits the whole board; the floor keeps cells from exceeding
        // the max on-screen size (relative to the window) when the window is
        // larger than the board.
        let viewportMin = min(size.width, size.height)
        let maxCell = min(
            Self.absoluteMaxCellSize, max(40, viewportMin * Self.maxCellFractionOfViewport))
        let cellFloor = layout.cellSize / maxCell
        cameraNode.setScale(max(fitScale, cellFloor))
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
        if NSEvent.modifierFlags.contains(.control) {
            flag(atScenePoint: p)
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
