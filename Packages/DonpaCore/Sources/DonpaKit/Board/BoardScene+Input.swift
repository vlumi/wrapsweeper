import DonpaCore
import SpriteKit

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// All board input: scene↔board coordinate mapping, tap/long-press/flag actions,
/// and the per-platform gesture/mouse/keyboard handlers. Mutable drag state lives
/// on `BoardScene` (extensions can't hold stored properties).
extension BoardScene {

    // MARK: Input mapping

    /// Scene-space point → board coordinate (accounting for the board layer).
    public func coord(atScenePoint p: CGPoint) -> Coord? {
        let local = boardLayer.convert(p, from: self)
        guard let c = layout.coord(at: local), viewModel.game.board.cellCount > 0 else {
            return nil
        }
        return c
    }

    func flag(atScenePoint p: CGPoint) {
        guard let c = coord(atScenePoint: p) else { return }
        viewModel.toggleFlag(c)
    }

    /// A plain tap/click: a revealed number chords; a hidden cell follows the
    /// current input mode (reveal or flag), so in Flag mode a stray tap can't open.
    func tapAction(atScenePoint p: CGPoint) {
        if handleMinimapTap(atScenePoint: p) { return }
        guard let c = coord(atScenePoint: p) else { return }
        if viewModel.game.board[c].state == .revealed {
            viewModel.chord(c)
        } else {
            switch viewModel.inputMode {
            case .reveal:
                // On a known mine, show the hit-mine tile instantly (before the
                // off-thread reveal). No-op on the safe first click.
                if viewModel.canRevealHitMine(c) { revealHitTileInstantly(at: c) }
                viewModel.reveal(c)
            case .flag: viewModel.toggleFlag(c)
            }
        }
    }

    /// A long-press: the opposite action to the current mode on a hidden cell
    /// (flag in Reveal, reveal in Flag); chords on a revealed number, like a tap.
    func longPressAction(atScenePoint p: CGPoint) {
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

    /// Map a hosting-view point to scene space via `SKView`'s own view↔scene
    /// transform (Y-flip + camera).
    func scenePoint(fromViewPoint p: CGPoint) -> CGPoint {
        convertPoint(fromView: p)
    }

    // MARK: Gesture recognizers (pan + zoom)

    func installGestureRecognizers(on view: SKView) {
        #if os(iOS)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        pan.maximumNumberOfTouches = 2
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch))
        // No double-tap, so single taps fire immediately with no timeout.
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
    @objc func handlePan(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: g.view)
        if g.state == .began { lastPan = .zero }
        pan(byTranslation: CGPoint(x: t.x - lastPan.x, y: t.y - lastPan.y))
        lastPan = t
        if g.state == .ended || g.state == .cancelled { panEnded() }
    }

    @objc func handlePinch(_ g: UIPinchGestureRecognizer) {
        // Zoom toward the pinch midpoint so the point under the fingers stays put.
        zoom(by: g.scale, aroundViewPoint: g.location(in: g.view))
        g.scale = 1
    }

    @objc func handleTap(_ g: UITapGestureRecognizer) {
        tapAction(atScenePoint: scenePoint(fromViewPoint: g.location(in: g.view)))
    }

    @objc func handleLong(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        longPressAction(atScenePoint: scenePoint(fromViewPoint: g.location(in: g.view)))
    }
    #elseif os(macOS)
    @objc func handlePinch(_ g: NSMagnificationGestureRecognizer) {
        // Zoom toward the trackpad pinch centroid so the point under it stays put.
        zoom(by: 1 + g.magnification, aroundViewPoint: g.location(in: g.view))
        g.magnification = 0
    }

    /// Two-finger trackpad swipe (or mouse wheel) pans; ⌘+scroll zooms toward the
    /// cursor (the mouse-zoom idiom). Coarse wheel line deltas are scaled up.
    public override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            let dy = event.scrollingDeltaY
            guard dy != 0 else { return }
            let factor = 1 + max(-0.5, min(0.5, dy * 0.01))  // up = in, down = out
            zoom(by: factor, aroundViewPoint: viewPoint(of: event))
            return
        }
        let step: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
        // Natural scroll: content follows the fingers. AppKit Y grows upward like
        // the scene, so pass deltas through directly.
        pan(
            byTranslation: CGPoint(
                x: event.scrollingDeltaX * step, y: event.scrollingDeltaY * step))
        if event.phase == .ended || event.momentumPhase == .ended { panEnded() }
    }

    /// An event's location in hosting-view coords (for cursor-anchored zoom).
    private func viewPoint(of event: NSEvent) -> CGPoint? {
        guard let view else { return nil }
        return view.convert(event.locationInWindow, from: nil)
    }

    public override func mouseDown(with event: NSEvent) {
        let p = view?.convert(event.locationInWindow, from: nil) ?? .zero
        lastDragViewPoint = p
        mouseDownViewPoint = p
        didDragInScene = false
    }

    public override func mouseDragged(with event: NSEvent) {
        // Grab model: content follows the cursor. Use the camera-independent
        // view-space delta and let pan() scale it by zoom.
        guard let view = view else { return }
        let p = view.convert(event.locationInWindow, from: nil)
        // Only become a drag once movement clears the threshold.
        if !didDragInScene {
            let moved = hypot(p.x - mouseDownViewPoint.x, p.y - mouseDownViewPoint.y)
            guard moved > Self.dragThreshold else { return }
            didDragInScene = true
        }
        // pan() applies +Y to the camera; negate so content follows the cursor.
        pan(byTranslation: CGPoint(x: p.x - lastDragViewPoint.x, y: -(p.y - lastDragViewPoint.y)))
        lastDragViewPoint = p
    }

    public override func mouseUp(with event: NSEvent) {
        if didDragInScene { panEnded() }  // spring back if the drag overshot the edge
        guard !didDragInScene else { return }  // a real drag panned; don't also click
        let p = event.location(in: self)
        // Control is the temporary "other action" modifier: it does the long-press
        // action (flag in Reveal mode, reveal in Flag mode).
        if NSEvent.modifierFlags.contains(.control) {
            longPressAction(atScenePoint: p)
        } else {
            tapAction(atScenePoint: p)
        }
    }

    public override func rightMouseUp(with event: NSEvent) {
        flag(atScenePoint: event.location(in: self))
    }

    // Key input handled directly: SwiftUI menu shortcuts for bare keys don't fire
    // reliably, but the scene receives key events via the responder chain. Space
    // toggles reveal/flag; Esc pauses/resumes mid-play.
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
