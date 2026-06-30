import DonpaCore
import SpriteKit

/// Camera pan / zoom and the edge handling that keeps the board in view.
///
/// Edge feel = a resting margin (half a cell of breathing room) plus rubber-banding
/// past it: pulling beyond the margin meets rising resistance and springs back when
/// the gesture ends. On an axis where the board fits, the camera locks to centre.
extension BoardScene {
    /// Resting breathing room past each edge, so you don't pan flush to the edge.
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

    /// Resting margin on every edge = the minimap footprint plus the base breathing
    /// room, so edge tiles never sit flush to the window — whether the minimap is
    /// shown or not, and on all four sides (not just the minimap's corner). The
    /// footprint is in screen points, converted to scene units at the current zoom so
    /// the on-screen gap stays consistent across window size and zoom.
    private func edgeMargins() -> EdgeMargins {
        let scale = cameraNode.xScale
        let mm = minimapCornerFootprint()
        let x = baseEdgeMargin + mm.width * scale
        let y = baseEdgeMargin + mm.height * scale
        return EdgeMargins(loX: x, hiX: x, loY: y, hiY: y)
    }

    /// Pan the camera by a view-space translation delta.
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

    /// Multiply the current zoom by `factor` (>1 zooms in), about the camera
    /// centre. Clamped to `maxZoomOutScale` and a most-zoomed-in cap.
    public func zoom(by factor: CGFloat) {
        zoom(by: factor, aroundViewPoint: nil)
    }

    /// Zoom anchored on a hosting-view point (pinch midpoint / cursor) so the board
    /// point under it stays put. `nil` anchors on the camera centre. Reads the scene
    /// point under the anchor before/after the scale change (via `SKView`'s
    /// transform) and shifts the camera by the difference, so the projection is
    /// never hand-derived.
    public func zoom(by factor: CGFloat, aroundViewPoint viewAnchor: CGPoint?) {
        restoreCameraTarget = nil  // the player took over; stop re-applying the saved view
        // A fast trackpad zoom-out delivers `magnification ≤ −1`, so the caller's
        // `1 + magnification` factor arrives ≤ 0; dividing by it would jump to the
        // most-zoomed-in limit. Floor it to a small positive step.
        let safeFactor = max(factor, 0.1)
        let old = cameraNode.xScale
        let new = min(max(old / safeFactor, 0.1), maxZoomOutScale)
        guard new != old else { return }

        let before = viewAnchor.map { convertPoint(fromView: $0) }
        cameraNode.setScale(new)
        if let before, let viewAnchor {
            // The same view point now maps elsewhere; nudge the camera so the board
            // point under the cursor returns to it.
            let after = convertPoint(fromView: viewAnchor)
            cameraNode.position = CGPoint(
                x: cameraNode.position.x + (before.x - after.x),
                y: cameraNode.position.y + (before.y - after.y))
        }
        // A smaller scale may pull empty space in; re-clamp to the margin edge.
        cameraNode.position = clampedCameraPosition(cameraNode.position)
    }

    /// Reset camera to fit and center the whole board (e.g. on new game).
    public func resetCamera() { centerCamera() }

    /// The current camera view (normalized centre + zoom) for persistence.
    /// Normalized in scene space (camera y up, no flip) so `applyCameraView`
    /// round-trips it. nil when the board has no size yet.
    func currentCameraView() -> CameraView? {
        let board = layout.boardSize(width: viewModel.boardWidth, height: viewModel.boardHeight)
        guard board.width > 0, board.height > 0 else { return nil }
        return CameraView(
            centerX: Double(cameraNode.position.x / board.width),
            centerY: Double(cameraNode.position.y / board.height),
            scale: Double(cameraNode.xScale))
    }

    /// Place the camera for a (re)layout: honour a pending restore target (re-clamped
    /// to the current size), else the default fit. Called from every auto-centre
    /// point (`didMove`, `didChangeSize`, new-game rebuild) so the restored view
    /// survives the window settling on launch.
    func applyDesiredCameraOrCenter() {
        if let target = restoreCameraTarget {
            applyCameraView(target)
        } else {
            centerCamera()
        }
        // Recompute the minimap against the freshly-settled camera/size now, rather
        // than waiting on the next `update()` tick — the render loop idles when the
        // scene is static, so on launch (the real viewport size arrives via
        // `didChangeSize` after the placeholder) the minimap would otherwise stay
        // hidden until a pan woke the loop and re-evaluated `boardExceedsViewport`.
        refreshMinimap()
    }

    /// Apply a saved camera view: set the zoom, then place the centre by
    /// denormalizing against the *current* board size and clamping — so a view saved
    /// at one window size restores sensibly at another.
    func applyCameraView(_ view: CameraView) {
        let board = layout.boardSize(width: viewModel.boardWidth, height: viewModel.boardHeight)
        let scale = min(max(CGFloat(view.scale), 0.1), maxZoomOutScale)
        cameraNode.setScale(scale)
        let target = CGPoint(
            x: CGFloat(view.centerX) * board.width,
            y: CGFloat(view.centerY) * board.height)
        cameraNode.position = clampedCameraPosition(target)
    }

    /// Centre on a normalized board point (0,0 = top-left), keeping the current
    /// zoom — the overview drives this live. Clamped to the resting bounds.
    public func centerCamera(onNormalizedPoint p: CGPoint) {
        restoreCameraTarget = nil  // overview navigation is a deliberate move
        let board = layout.boardSize(width: viewModel.boardWidth, height: viewModel.boardHeight)
        let nx = min(max(p.x, 0), 1)
        let ny = min(max(p.y, 0), 1)
        // Board y grows downward; world y is up, so flip the normalized y.
        let target = CGPoint(x: nx * board.width, y: (1 - ny) * board.height)
        cameraNode.position = clampedCameraPosition(target)
    }

    /// Clamp a proposed camera centre to the resting bounds (up to the per-edge
    /// margin past each board edge). On an axis where the board fits, lock to centre.
    func clampedCameraPosition(_ proposed: CGPoint) -> CGPoint {
        // A torus has no edges to clamp to — the camera roams freely.
        guard !isWrapped else { return proposed }
        return axisMap(proposed) { center, halfBoard, halfView, loMargin, hiMargin in
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
        // Torus: no edges, so no rubber-band — pan tracks the finger 1:1.
        guard !isWrapped else { return proposed }
        return axisMap(proposed) { center, halfBoard, halfView, loMargin, hiMargin in
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

    /// Apply a per-axis transform of (proposed centre, half-board, half-view, low/
    /// high margin) to both axes — the shared shape of the clamp and rubber-band.
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
