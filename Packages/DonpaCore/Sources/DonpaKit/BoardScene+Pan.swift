import DonpaCore
import SpriteKit

/// Camera pan / zoom and the edge handling that keeps the board in view.
///
/// Edge feel = a fixed margin plus rubber-banding past it: the board rests with
/// a small margin (half a cell) of breathing room past each edge, reachable by a
/// normal drag; pulling *beyond* that margin meets rising resistance and springs
/// back to the margin edge when the gesture ends. On an axis where the board
/// already fits the viewport the camera locks to centre (no drift).
extension BoardScene {
    /// Base resting breathing room past each edge, in scene units — a small peek
    /// past the board so you're not panning flush to the last row/column.
    private var baseEdgeMargin: CGFloat { layout.cellSize / 2 }
    /// How far past the resting margin a rubber-band pull can reach.
    private var maxPull: CGFloat { layout.cellSize * 2 }

    /// Resting margin per edge, in SCENE units (loX/hiX = left/right, loY/hiY =
    /// bottom/top, since scene y is up).
    private struct EdgeMargins {
        var loX: CGFloat
        var hiX: CGFloat
        var loY: CGFloat
        var hiY: CGFloat
    }

    /// The minimap is a fixed-size HUD in the top-LEFT corner, so the left edge
    /// (loX) and top edge (hiY) get enough extra margin that panning into that
    /// corner rests the board edge clear of the minimap — it then covers empty
    /// space, not cells. The minimap's footprint is in screen points, converted to
    /// scene units at the current zoom, so the on-screen gap is consistent across
    /// window size and zoom (the previous fixed scene-unit margin looked
    /// window-relative because a constant world gap renders as a varying screen
    /// gap). The other two edges keep the base peek.
    private func edgeMargins() -> EdgeMargins {
        let base = baseEdgeMargin
        guard let mm = minimapCornerFootprint() else {
            return EdgeMargins(loX: base, hiX: base, loY: base, hiY: base)
        }
        let scale = cameraNode.xScale
        return EdgeMargins(
            loX: max(base, mm.width * scale),  // left edge clears the minimap width
            hiX: base,
            loY: base,
            hiY: max(base, mm.height * scale))  // top edge clears the minimap height
    }

    /// Pan the camera by a view-space translation delta (recognizer units, which
    /// share the scene's point system under `.resizeFill`).
    public func pan(byTranslation delta: CGPoint) {
        restoreCameraTarget = nil  // the player took over; stop re-applying the saved view
        let scale = cameraNode.xScale
        let proposed = CGPoint(
            x: cameraNode.position.x - delta.x * scale,
            y: cameraNode.position.y + delta.y * scale)
        cameraNode.position = rubberBandedCameraPosition(proposed)
    }

    /// When the gesture ends, spring the camera back so it rests at the margin
    /// edge (undoing any rubber-band overshoot).
    public func panEnded() {
        let target = clampedCameraPosition(cameraNode.position)
        guard target != cameraNode.position else { return }
        let move = SKAction.move(to: target, duration: 0.25)
        move.timingMode = .easeOut
        cameraNode.run(move)
    }

    /// Multiply the current zoom by `factor` (>1 zooms in), anchored on the
    /// camera centre. Never zooms out past `maxZoomOutScale` (whole board OR the
    /// min interactive cell size, whichever keeps cells tappable), and caps how
    /// far in you can go.
    public func zoom(by factor: CGFloat) {
        zoom(by: factor, aroundViewPoint: nil)
    }

    /// Zoom anchored on a point in the hosting view's coordinates (the pinch
    /// midpoint / cursor) so the board point under it stays put — "zoom to
    /// cursor". `nil` anchors on the camera centre (plain centre zoom).
    ///
    /// Done by reading the scene point under the anchor *before* and *after* the
    /// scale change (via `SKView`'s own view↔scene transform) and shifting the
    /// camera by the difference — so we never hand-derive the projection and it
    /// stays correct regardless of `anchorPoint` / Y-flip conventions.
    public func zoom(by factor: CGFloat, aroundViewPoint viewAnchor: CGPoint?) {
        restoreCameraTarget = nil  // the player took over; stop re-applying the saved view
        // A fast trackpad zoom-out can deliver `magnification ≤ −1`, so the caller's
        // `1 + magnification` factor arrives ≤ 0; dividing by it yields ∞ or a
        // negative scale that clamps to the most-zoomed-IN limit — the "jumps to a
        // very close zoom" bug. Floor the factor to a small positive step so a
        // single gesture can only zoom out so far per event.
        let safeFactor = max(factor, 0.1)
        let old = cameraNode.xScale
        let new = min(max(old / safeFactor, 0.1), maxZoomOutScale)
        guard new != old else { return }

        let before = viewAnchor.map { convertPoint(fromView: $0) }
        cameraNode.setScale(new)
        if let before, let viewAnchor {
            // The same view point now maps to a different scene point; nudge the
            // camera so the board point that was under the cursor returns to it.
            let after = convertPoint(fromView: viewAnchor)
            cameraNode.position = CGPoint(
                x: cameraNode.position.x + (before.x - after.x),
                y: cameraNode.position.y + (before.y - after.y))
        }
        // A smaller scale shows more board, which may pull empty space into
        // view; re-clamp so the board rests at the margin edge.
        cameraNode.position = clampedCameraPosition(cameraNode.position)
    }

    /// Reset camera to fit and center the whole board (e.g. on new game).
    public func resetCamera() { centerCamera() }

    /// The current camera view (centre as a normalized board point + zoom scale),
    /// for persistence. Normalized in scene space (camera y is up here, no flip),
    /// so `applyCameraView` round-trips it without convention mismatch. nil when
    /// the board has no size yet.
    func currentCameraView() -> CameraView? {
        let board = layout.boardSize(width: viewModel.boardWidth, height: viewModel.boardHeight)
        guard board.width > 0, board.height > 0 else { return nil }
        return CameraView(
            centerX: Double(cameraNode.position.x / board.width),
            centerY: Double(cameraNode.position.y / board.height),
            scale: Double(cameraNode.xScale))
    }

    /// Place the camera for a (re)layout: honour a held restore target if one is
    /// pending (re-clamped to the current size), else fall back to the default
    /// fit. Called from every spot that would otherwise auto-centre — `didMove`,
    /// `didChangeSize`, the new-game rebuild — so the restored view survives the
    /// window settling to its frame on launch (which fires those after the scene
    /// has already applied the restore).
    func applyDesiredCameraOrCenter() {
        if let target = restoreCameraTarget {
            applyCameraView(target)
        } else {
            centerCamera()
        }
    }

    /// Apply a saved camera view: set the zoom, then place the centre by
    /// denormalizing against the *current* board size and clamping to the current
    /// viewport's resting bounds — so a view saved at one window size restores
    /// sensibly at another (same board point centred, same zoom, never off-board).
    func applyCameraView(_ view: CameraView) {
        let board = layout.boardSize(width: viewModel.boardWidth, height: viewModel.boardHeight)
        // Clamp the zoom into the same range manual zoom allows.
        let scale = min(max(CGFloat(view.scale), 0.1), maxZoomOutScale)
        cameraNode.setScale(scale)
        let target = CGPoint(
            x: CGFloat(view.centerX) * board.width,
            y: CGFloat(view.centerY) * board.height)
        cameraNode.position = clampedCameraPosition(target)
    }

    /// Centre the camera on a normalized board point (0…1 in each axis), keeping
    /// the current zoom — the fullscreen overview drives this live as the player
    /// drags/taps the viewport rectangle. Clamped to the resting bounds so it
    /// can't scroll past the edges. (0,0) = top-left of the board.
    public func centerCamera(onNormalizedPoint p: CGPoint) {
        restoreCameraTarget = nil  // overview navigation is a deliberate move
        let board = layout.boardSize(width: viewModel.boardWidth, height: viewModel.boardHeight)
        let nx = min(max(p.x, 0), 1)
        let ny = min(max(p.y, 0), 1)
        // Board y grows downward; world y is up, so flip the normalized y.
        let target = CGPoint(x: nx * board.width, y: (1 - ny) * board.height)
        cameraNode.position = clampedCameraPosition(target)
    }

    /// Clamp a proposed camera centre to the resting bounds: the viewport may sit
    /// up to the per-edge margin past each board edge, no further. On an axis where
    /// the board is smaller than the viewport the camera locks to the board centre,
    /// so a stray drag can't nudge a board that already fits.
    func clampedCameraPosition(_ proposed: CGPoint) -> CGPoint {
        axisMap(proposed) { center, halfBoard, halfView, loMargin, hiMargin in
            let slack = halfBoard - halfView
            if slack <= 0 { return halfBoard }  // board fits this axis → lock to centre
            return min(
                max(center, halfView - loMargin), 2 * halfBoard - halfView + hiMargin)
        }
    }

    /// Like `clampedCameraPosition`, but past the margin edge the motion is damped
    /// (the further out, the more resistance), so a pull beyond the resting bound
    /// feels elastic. `panEnded()` springs it back to the margin afterward.
    private func rubberBandedCameraPosition(_ proposed: CGPoint) -> CGPoint {
        axisMap(proposed) { center, halfBoard, halfView, loMargin, hiMargin in
            let slack = halfBoard - halfView
            if slack <= 0 { return halfBoard }  // board fits → lock to centre
            let lo = halfView - loMargin  // resting edges (per-edge margin applied)
            let hi = 2 * halfBoard - halfView + hiMargin
            // Diminishing returns: overshoot d maps to maxPull*(1 - 1/(1+d/maxPull)).
            func resist(_ overshoot: CGFloat) -> CGFloat {
                maxPull * (1 - 1 / (1 + overshoot / maxPull))
            }
            if center < lo { return lo - resist(lo - center) }
            if center > hi { return hi + resist(center - hi) }
            return center
        }
    }

    /// Apply a per-axis transform of (proposed centre, half-board, half-view, low-
    /// edge margin, high-edge margin) to both axes — the shared shape of the clamp
    /// and the rubber-band. Margins are per-edge (the minimap corner gets more).
    private func axisMap(
        _ proposed: CGPoint,
        _ transform: (CGFloat, CGFloat, CGFloat, CGFloat, CGFloat) -> CGFloat
    ) -> CGPoint {
        let board = layout.boardSize(width: viewModel.boardWidth, height: viewModel.boardHeight)
        let scale = cameraNode.xScale
        let m = edgeMargins()
        let halfViewW = size.width / 2 * scale
        let halfViewH = size.height / 2 * scale
        return CGPoint(
            x: transform(proposed.x, board.width / 2, halfViewW, m.loX, m.hiX),
            y: transform(proposed.y, board.height / 2, halfViewH, m.loY, m.hiY)
        )
    }
}
