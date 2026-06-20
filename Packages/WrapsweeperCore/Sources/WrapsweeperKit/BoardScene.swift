import SpriteKit
import WrapsweeperCore

/// Renders the board with an `SKCameraNode` for pan/zoom. Cell nodes are rebuilt
/// from the view model whenever its revision changes.
public final class BoardScene: SKScene {
    private let viewModel: GameViewModel
    private let layout: any CellLayout
    private let cameraNode = SKCameraNode()
    private let boardLayer = SKNode()
    private var lastRevision = -1
    private var lastGameID = -1
    #if os(macOS)
    private weak var panRecognizer: NSGestureRecognizer?
    private var clickRecognizers: [NSGestureRecognizer] = []
    #endif

    public init(viewModel: GameViewModel, layout: any CellLayout = SquareLayout()) {
        self.viewModel = viewModel
        self.layout = layout
        super.init(size: CGSize(width: 320, height: 320))
        scaleMode = .resizeFill
        backgroundColor = SKColor(white: 0.12, alpha: 1)
        addChild(boardLayer)
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
            centerCamera()
        }
        guard viewModel.revision != lastRevision else { return }
        lastRevision = viewModel.revision
        rebuild()
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

        if let glyph = glyph(for: cell) {
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
            return SKColor(white: 0.32, alpha: 1)
        case .revealed:
            return cell.isMine
                ? SKColor(red: 0.6, green: 0.1, blue: 0.1, alpha: 1)
                : SKColor(white: 0.2, alpha: 1)
        }
    }

    private func glyph(for cell: Cell) -> (text: String, color: SKColor)? {
        switch cell.state {
        case .flagged:
            return ("⚑", SKColor(red: 0.95, green: 0.4, blue: 0.3, alpha: 1))
        case .hidden:
            return nil
        case .revealed:
            if cell.isMine { return ("✸", .white) }
            guard cell.adjacentMines > 0 else { return nil }
            return (String(cell.adjacentMines), Self.numberColor(cell.adjacentMines))
        }
    }

    private static func numberColor(_ n: Int) -> SKColor {
        switch n {
        case 1: return SKColor(red: 0.40, green: 0.70, blue: 1.00, alpha: 1)
        case 2: return SKColor(red: 0.45, green: 0.85, blue: 0.45, alpha: 1)
        case 3: return SKColor(red: 1.00, green: 0.45, blue: 0.45, alpha: 1)
        case 4: return SKColor(red: 0.65, green: 0.55, blue: 1.00, alpha: 1)
        case 5: return SKColor(red: 0.85, green: 0.55, blue: 0.30, alpha: 1)
        case 6: return SKColor(red: 0.40, green: 0.80, blue: 0.80, alpha: 1)
        case 7: return SKColor(white: 0.85, alpha: 1)
        default: return SKColor(white: 0.65, alpha: 1)
        }
    }

    // MARK: Camera

    private func centerCamera() {
        let board = layout.boardSize(width: viewModel.boardWidth, height: viewModel.boardHeight)
        cameraNode.position = CGPoint(x: board.width / 2, y: board.height / 2)
        cameraNode.setScale(fitScale)
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
        let pan = NSPanGestureRecognizer(target: self, action: #selector(handlePan))
        let pinch = NSMagnificationGestureRecognizer(target: self, action: #selector(handlePinch))
        // One primary-click recognizer; ⌘ held = chord, otherwise reveal. A
        // single recognizer resolves instantly (no double-click timeout).
        let click = NSClickGestureRecognizer(target: self, action: #selector(handleClick))
        let rightClick = NSClickGestureRecognizer(target: self, action: #selector(handleRightClick))
        rightClick.buttonMask = 0x2  // secondary (right) button
        // The pan only engages once the click recognizer has given up, so a
        // plain click is never swallowed by the drag recognizer. AppKit
        // expresses this through the delegate (no UIKit-style `require(toFail:)`).
        pan.delaysPrimaryMouseButtonEvents = false
        self.panRecognizer = pan
        self.clickRecognizers = [click]
        for g in [pan, pinch, click, rightClick] as [NSGestureRecognizer] {
            g.delegate = self
            view.addGestureRecognizer(g)
        }
        #endif
    }

    #if os(iOS)
    private var lastPan: CGPoint = .zero

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: g.view)
        if g.state == .began { lastPan = .zero }
        pan(byTranslation: CGPoint(x: t.x - lastPan.x, y: t.y - lastPan.y))
        lastPan = t
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
    private var lastPan: CGPoint = .zero

    @objc private func handlePan(_ g: NSPanGestureRecognizer) {
        let t = g.translation(in: g.view)
        // AppKit's view Y grows upward, opposite UIKit; flip to match pan()'s
        // expectation that a downward drag moves content down.
        if g.state == .began { lastPan = .zero }
        pan(byTranslation: CGPoint(x: t.x - lastPan.x, y: -(t.y - lastPan.y)))
        lastPan = t
    }

    @objc private func handlePinch(_ g: NSMagnificationGestureRecognizer) {
        zoom(by: 1 + g.magnification)
        g.magnification = 0
    }

    @objc private func handleClick(_ g: NSClickGestureRecognizer) {
        let p = scenePoint(fromViewPoint: g.location(in: g.view))
        // Control-click always flags (the classic Mac right-click equivalent),
        // regardless of mode; a plain click follows the current input mode.
        if NSEvent.modifierFlags.contains(.control) {
            flag(atScenePoint: p)
        } else {
            tapAction(atScenePoint: p)
        }
    }

    @objc private func handleRightClick(_ g: NSClickGestureRecognizer) {
        flag(atScenePoint: scenePoint(fromViewPoint: g.location(in: g.view)))
    }

    // The scene handles key input directly: a bare Space as a SwiftUI menu
    // shortcut doesn't fire reliably, but the scene is in the responder chain
    // for its gesture recognizers and receives key events here.
    public override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " {
            viewModel.inputMode.toggle()
        } else {
            super.keyDown(with: event)
        }
    }
    #endif

    // MARK: Pan / zoom

    /// Smallest scale that still fits the whole board (the zoomed-out limit).
    private var fitScale: CGFloat {
        let board = layout.boardSize(width: viewModel.boardWidth, height: viewModel.boardHeight)
        guard size.width > 0, size.height > 0,
            board.width > 0, board.height > 0
        else { return 1 }
        let margin: CGFloat = 1.1
        return max(board.width * margin / size.width, board.height * margin / size.height)
    }

    /// Pan the camera by a view-space translation delta (recognizer units, which
    /// share the scene's point system under `.resizeFill`).
    public func pan(byTranslation delta: CGPoint) {
        let scale = cameraNode.xScale
        cameraNode.position = clampedCameraPosition(
            CGPoint(
                x: cameraNode.position.x - delta.x * scale,
                y: cameraNode.position.y + delta.y * scale
            ))
    }

    /// Multiply the current zoom by `factor` (>1 zooms in). Never zooms out past
    /// the whole board fitting on screen, and caps how far in you can go.
    public func zoom(by factor: CGFloat) {
        let next = cameraNode.xScale / factor
        cameraNode.setScale(min(max(next, 0.1), fitScale))
        // A smaller scale shows more board, which may pull empty space into
        // view; re-clamp so the board edge stays flush with the viewport.
        cameraNode.position = clampedCameraPosition(cameraNode.position)
    }

    /// Clamp a proposed camera centre so the viewport never extends past the
    /// board. On an axis where the board is smaller than the viewport (e.g. when
    /// fully zoomed out), the camera locks to the board centre — so a stray drag
    /// can't nudge a board that already fits, and clicks aren't lost to it.
    private func clampedCameraPosition(_ proposed: CGPoint) -> CGPoint {
        let board = layout.boardSize(width: viewModel.boardWidth, height: viewModel.boardHeight)
        let scale = cameraNode.xScale
        let halfViewW = size.width / 2 * scale
        let halfViewH = size.height / 2 * scale

        func clamp(center: CGFloat, halfBoard: CGFloat, halfView: CGFloat) -> CGFloat {
            // Slack = how far the centre can move off board-centre each way.
            let slack = halfBoard - halfView
            if slack <= 0 { return halfBoard }  // board fits this axis → lock to centre
            return min(max(center, halfView), 2 * halfBoard - halfView)
        }

        return CGPoint(
            x: clamp(center: proposed.x, halfBoard: board.width / 2, halfView: halfViewW),
            y: clamp(center: proposed.y, halfBoard: board.height / 2, halfView: halfViewH)
        )
    }

    /// Reset camera to fit and center the whole board (e.g. on new game).
    public func resetCamera() { centerCamera() }
}

#if os(macOS)
extension BoardScene: NSGestureRecognizerDelegate {
    /// Make the drag recognizer wait for the click recognizers to fail, so a
    /// stationary click reveals reliably instead of being eaten by the pan.
    public func gestureRecognizer(
        _ recognizer: NSGestureRecognizer,
        shouldRequireFailureOf other: NSGestureRecognizer
    ) -> Bool {
        recognizer === panRecognizer && clickRecognizers.contains(other)
    }
}
#endif
