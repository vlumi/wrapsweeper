import SpriteKit

/// Camera pan / zoom and the edge handling that keeps the board in view.
///
/// Edge feel = a fixed margin plus rubber-banding past it: the board rests with
/// a small margin (half a cell) of breathing room past each edge, reachable by a
/// normal drag; pulling *beyond* that margin meets rising resistance and springs
/// back to the margin edge when the gesture ends. On an axis where the board
/// already fits the viewport the camera locks to centre (no drift).
extension BoardScene {
    /// Resting breathing room past each edge, in scene units.
    private var edgeMargin: CGFloat { layout.cellSize / 2 }
    /// How far past the margin a rubber-band pull can reach.
    private var maxPull: CGFloat { layout.cellSize * 2 }

    /// Pan the camera by a view-space translation delta (recognizer units, which
    /// share the scene's point system under `.resizeFill`).
    public func pan(byTranslation delta: CGPoint) {
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

    /// Multiply the current zoom by `factor` (>1 zooms in). Never zooms out past
    /// `maxZoomOutScale` (whole board OR the min interactive cell size, whichever
    /// keeps cells tappable — so a huge board can't be zoomed out to an untappable
    /// sea of cells), and caps how far in you can go.
    public func zoom(by factor: CGFloat) {
        let next = cameraNode.xScale / factor
        cameraNode.setScale(min(max(next, 0.1), maxZoomOutScale))
        // A smaller scale shows more board, which may pull empty space into
        // view; re-clamp so the board rests at the margin edge.
        cameraNode.position = clampedCameraPosition(cameraNode.position)
    }

    /// Reset camera to fit and center the whole board (e.g. on new game).
    public func resetCamera() { centerCamera() }

    /// Centre the camera on a normalized board point (0…1 in each axis), keeping
    /// the current zoom — the fullscreen overview drives this live as the player
    /// drags/taps the viewport rectangle. Clamped to the resting bounds so it
    /// can't scroll past the edges. (0,0) = top-left of the board.
    public func centerCamera(onNormalizedPoint p: CGPoint) {
        let board = layout.boardSize(width: viewModel.boardWidth, height: viewModel.boardHeight)
        let nx = min(max(p.x, 0), 1)
        let ny = min(max(p.y, 0), 1)
        // Board y grows downward; world y is up, so flip the normalized y.
        let target = CGPoint(x: nx * board.width, y: (1 - ny) * board.height)
        cameraNode.position = clampedCameraPosition(target)
    }

    /// Clamp a proposed camera centre to the resting bounds: the viewport may sit
    /// up to `edgeMargin` past each board edge, no further. On an axis where the
    /// board is smaller than the viewport the camera locks to the board centre,
    /// so a stray drag can't nudge a board that already fits.
    func clampedCameraPosition(_ proposed: CGPoint) -> CGPoint {
        axisMap(proposed) { center, halfBoard, halfView in
            let slack = halfBoard - halfView
            if slack <= 0 { return halfBoard }  // board fits this axis → lock to centre
            return min(
                max(center, halfView - edgeMargin), 2 * halfBoard - halfView + edgeMargin)
        }
    }

    /// Like `clampedCameraPosition`, but past the margin edge the motion is damped
    /// (the further out, the more resistance), so a pull beyond the resting bound
    /// feels elastic. `panEnded()` springs it back to the margin afterward.
    private func rubberBandedCameraPosition(_ proposed: CGPoint) -> CGPoint {
        axisMap(proposed) { center, halfBoard, halfView in
            let slack = halfBoard - halfView
            if slack <= 0 { return halfBoard }  // board fits → lock to centre
            let lo = halfView - edgeMargin  // resting edges (margin applied)
            let hi = 2 * halfBoard - halfView + edgeMargin
            // Diminishing returns: overshoot d maps to maxPull*(1 - 1/(1+d/maxPull)).
            func resist(_ overshoot: CGFloat) -> CGFloat {
                maxPull * (1 - 1 / (1 + overshoot / maxPull))
            }
            if center < lo { return lo - resist(lo - center) }
            if center > hi { return hi + resist(center - hi) }
            return center
        }
    }

    /// Apply a per-axis transform of (proposed centre, half-board, half-view) to
    /// both axes — the shared shape of the clamp and the rubber-band.
    private func axisMap(
        _ proposed: CGPoint, _ transform: (CGFloat, CGFloat, CGFloat) -> CGFloat
    ) -> CGPoint {
        let board = layout.boardSize(width: viewModel.boardWidth, height: viewModel.boardHeight)
        let scale = cameraNode.xScale
        let halfViewW = size.width / 2 * scale
        let halfViewH = size.height / 2 * scale
        return CGPoint(
            x: transform(proposed.x, board.width / 2, halfViewW),
            y: transform(proposed.y, board.height / 2, halfViewH)
        )
    }
}
