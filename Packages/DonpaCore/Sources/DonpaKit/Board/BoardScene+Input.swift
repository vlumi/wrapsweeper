import DonpaCore
import SpriteKit

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// All board input: scene↔board coordinate mapping, the tap/long-press/flag
/// actions, and the per-platform gesture/mouse/keyboard handlers. Split out of
/// BoardScene.swift to keep that file within the length limit. The mutable drag
/// state lives on `BoardScene` itself (extensions can't hold stored properties).
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

    /// A plain tap/click. A revealed number always chords; a hidden cell does
    /// whatever the current input mode says (reveal or flag). This is the
    /// safety mechanism: in Flag mode a stray tap can't open a tile.
    func tapAction(atScenePoint p: CGPoint) {
        // A tap on the minimap's expand icon opens the overview, not a board move.
        if handleMinimapTap(atScenePoint: p) { return }
        guard let c = coord(atScenePoint: p) else { return }
        if viewModel.game.board[c].state == .revealed {
            viewModel.chord(c)
        } else {
            switch viewModel.inputMode {
            case .reveal:
                // On a known mine, show the hit-mine tile + explosion instantly
                // (before the off-thread reveal). No-op on the safe first click.
                if viewModel.canRevealHitMine(c) { revealHitTileInstantly(at: c) }
                viewModel.reveal(c)
            case .flag: viewModel.toggleFlag(c)
            }
        }
    }

    /// A long-press: the opposite primary action to the current mode on a
    /// hidden cell (flag in Reveal mode, reveal in Flag mode). On a revealed
    /// number it chords, same as a tap, so it's never a dead gesture.
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

    /// Map a point in the hosting view's coordinates to scene space. `SKView`
    /// owns the view↔scene transform (Y-flip + camera), so we let it do the work.
    func scenePoint(fromViewPoint p: CGPoint) -> CGPoint {
        convertPoint(fromView: p)
    }

    // MARK: Gesture recognizers (pan + zoom)

    func installGestureRecognizers(on view: SKView) {
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
    @objc func handlePan(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: g.view)
        if g.state == .began { lastPan = .zero }
        pan(byTranslation: CGPoint(x: t.x - lastPan.x, y: t.y - lastPan.y))
        lastPan = t
        if g.state == .ended || g.state == .cancelled { panEnded() }
    }

    @objc func handlePinch(_ g: UIPinchGestureRecognizer) {
        // Zoom toward the pinch midpoint so the board point under the fingers
        // stays put, rather than zooming the camera centre.
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
        // Zoom toward the trackpad pinch centroid so the board point under it
        // stays put, rather than zooming the camera centre.
        zoom(by: 1 + g.magnification, aroundViewPoint: g.location(in: g.view))
        g.magnification = 0
    }

    /// Two-finger trackpad swipe (or mouse wheel) pans the camera, the way
    /// Maps and Preview behave. Precise deltas come from the trackpad; a plain
    /// wheel reports coarse line deltas, so scale those up.
    public override func scrollWheel(with event: NSEvent) {
        // ⌘ + scroll zooms toward the cursor (the mouse-zoom idiom — a Magic Mouse
        // has no pinch gesture, so this is how a mouse user zooms). Plain scroll
        // still pans.
        if event.modifierFlags.contains(.command) {
            let dy = event.scrollingDeltaY
            guard dy != 0 else { return }
            // Each notch of scroll nudges the zoom a little; up = in, down = out.
            let factor = 1 + max(-0.5, min(0.5, dy * 0.01))
            zoom(by: factor, aroundViewPoint: viewPoint(of: event))
            return
        }
        let step: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
        // Natural-scroll convention: content follows the fingers. AppKit's Y
        // grows upward, matching the scene, so pass deltas through directly.
        pan(
            byTranslation: CGPoint(
                x: event.scrollingDeltaX * step, y: event.scrollingDeltaY * step))
        // Spring back when the trackpad gesture (and its momentum) finishes.
        if event.phase == .ended || event.momentumPhase == .ended { panEnded() }
    }

    /// An `NSEvent`'s location in the hosting view's coordinates (for cursor-anchored
    /// zoom). nil if there's no view yet.
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
