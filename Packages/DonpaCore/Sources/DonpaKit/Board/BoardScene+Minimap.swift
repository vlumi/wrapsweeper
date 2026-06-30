import DonpaCore
import SpriteKit

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// A corner "minimap" of the whole board with a viewport rectangle — the
/// navigation aid for boards too big to see at once. Shown only when the board
/// exceeds the viewport. The overview is one downsampled `SKTexture` (rebuilt only
/// on board change); the viewport rect repositions every frame. Pinned to the
/// camera in ONE fixed corner (top-left) — hopping corners would feel unstable.
extension BoardScene {
    /// Fraction of the shorter viewport side the minimap's longer side spans.
    private static let minimapFraction: CGFloat = 0.26
    private static let minimapMaxSide: CGFloat = 200
    private static let minimapPadding: CGFloat = 16
    /// Scale runs [min…max] mapping linearly from the compact base size to a large
    /// size that's `minimapMaxFraction` of the viewport's shorter side — so the
    /// max is genuinely big on a large window, not just base×k. min=1 = base.
    static let minimapScaleMin: CGFloat = 1
    static let minimapScaleMax: CGFloat = 4
    /// The max minimap's longer side as a fraction of the viewport's shorter side.
    static let minimapMaxFraction: CGFloat = 0.66
    /// Resize-caret geometry: a gap between the minimap edge and the caret (so the
    /// map's own corner tile stays tappable), the caret arm length, and the hit
    /// strip thickness (the L-shaped touch area's width).
    private static let handleGap: CGFloat = 4
    private static let handleArm: CGFloat = 20
    private static let handleThickness: CGFloat = 36

    func refreshMinimap() {
        let w = viewModel.boardWidth
        let h = viewModel.boardHeight
        // Whether the WHOLE board fits, from the true visible world rect — NOT
        // `visibleRange()`, whose +1-cell culling margin (so cells build before
        // scrolling in) makes a board with a partly-clipped edge column read as
        // "fits", leaving the minimap hidden until a nudge crossed the rounding edge.
        let board = layout.boardSize(width: w, height: h)
        let scale = cameraNode.xScale
        let halfW = size.width / 2 * scale
        let halfH = size.height / 2 * scale
        let cam = cameraNode.position
        let eps: CGFloat = 0.5  // sub-pixel slack, so an exact fit isn't a false "exceeds"
        let fits =
            cam.x - halfW <= eps && cam.y - halfH <= eps
            && cam.x + halfW >= board.width - eps && cam.y + halfH >= board.height - eps
        // Publish so the toolbar toggle can disable when the board fits. Assign only
        // on change to avoid @Published churn every frame.
        let exceeds = !fits
        if viewModel.boardExceedsViewport != exceeds {
            viewModel.boardExceedsViewport = exceeds
        }
        guard exceeds, showMinimap else {
            minimapNode?.isHidden = true
            minimapImageRect = nil  // no stale hit areas while hidden
            minimapHandleRects = []
            return
        }

        ensureMinimapNode()
        minimapNode?.isHidden = false

        // Rebuild the overview image only on a board-state or board-size change.
        let boardSize = CGSize(width: w, height: h)
        if viewModel.revision != lastMinimapRevision || boardSize != lastMinimapBoard {
            lastMinimapRevision = viewModel.revision
            lastMinimapBoard = boardSize
            updateMinimapImage(boardW: w, boardH: h)
        }

        layoutMinimap(boardW: w, boardH: h, range: visibleRange())
    }

    /// The minimap's longer-side length in points for a given scale. `scale` runs
    /// [min…max]; at min it's the compact base size, at max a large fraction of the
    /// viewport — so on a big window the max is genuinely big, while staying
    /// viewport-relative on a phone. Linear in between.
    func minimapLongerSide(scale: CGFloat) -> CGFloat {
        let viewportMin = min(size.width, size.height)
        let base = min(Self.minimapMaxSide, viewportMin * Self.minimapFraction)
        let maxLonger = max(base, viewportMin * Self.minimapMaxFraction)
        let s = min(max(scale, Self.minimapScaleMin), Self.minimapScaleMax)
        let t = (s - Self.minimapScaleMin) / (Self.minimapScaleMax - Self.minimapScaleMin)
        return base + t * (maxLonger - base)
    }

    /// On-screen minimap size for the current scale, the shorter side following the
    /// board aspect.
    private func minimapSize(boardW: Int, boardH: Int) -> CGSize {
        let longer = minimapLongerSide(scale: minimapScale)
        let aspect = CGFloat(boardW) / CGFloat(max(1, boardH))
        return aspect >= 1
            ? CGSize(width: longer, height: longer / aspect)
            : CGSize(width: longer * aspect, height: longer)
    }

    /// The minimap's full on-screen footprint (image + frame + edge gap), regardless
    /// of whether it's currently shown — the pan margin reserves this much on every
    /// edge so edge tiles never sit flush to the window, minimap or not. The `+ 6`
    /// mirrors `layoutMinimap`'s `framePad`.
    func minimapCornerFootprint() -> CGSize {
        let mm = minimapSize(boardW: viewModel.boardWidth, boardH: viewModel.boardHeight)
        // edge gap + frame border (framePad) + the resize caret sitting outside the
        // corner, so the map AND its handle clear all board tiles.
        let extra = Self.minimapPadding + 6 + Self.handleGap + Self.handleArm
        return CGSize(width: mm.width + extra, height: mm.height + extra)
    }

    private func ensureMinimapNode() {
        guard minimapNode == nil else { return }
        let container = SKNode()
        container.zPosition = 100
        container.alpha = 0.68  // semi-transparent HUD; the board shows through

        // Panel + border frame it as a HUD element. Sized in `layoutMinimap`.
        let panel = SKShapeNode()
        panel.fillColor = palette.sceneBackground
        panel.strokeColor = palette.flagGlyph
        panel.lineWidth = 2
        panel.zPosition = 0
        container.addChild(panel)
        minimapPanel = panel

        let image = SKSpriteNode()
        image.zPosition = 1
        container.addChild(image)
        minimapImage = image

        let viewport = SKShapeNode()
        viewport.strokeColor = palette.flagGlyph
        viewport.lineWidth = 2
        viewport.fillColor = palette.flagGlyph.withAlphaComponent(0.22)
        viewport.isAntialiased = false
        viewport.zPosition = 2
        container.addChild(viewport)
        minimapViewport = viewport

        // Resize handle: a small grip just outside the bottom-right corner. Drag to
        // resize; tap to snap min↔max. Positioned in `layoutMinimap`.
        let handle = resizeHandleNode()
        handle.zPosition = 3
        container.addChild(handle)
        minimapHandle = handle

        cameraNode.addChild(container)
        minimapNode = container
    }

    /// An L-shaped "resize" caret hugging the minimap's bottom-right corner from
    /// OUTSIDE it: a vertical arm up the right edge + a horizontal arm along the
    /// bottom, joined by a quarter-arc that ECHOES the minimap's rounded corner
    /// (concentric, just outside it). Node origin is the corner point (set in
    /// `layoutMinimap`); arms extend up (+y) and left (−x).
    private func resizeHandleNode() -> SKNode {
        let node = SKNode()
        let arm = Self.handleArm
        // Match the panel's 6pt corner radius, offset out by the gap so the arc sits
        // concentric with (just outside) the minimap's rounded corner.
        let radius = 6 + Self.handleGap
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: arm))  // top of the vertical arm
        path.addLine(to: CGPoint(x: 0, y: radius))  // down to where the arc begins
        // Quarter-arc around the corner: tangent to the vertical arm at (0, radius),
        // tangent to the horizontal arm at (-radius, 0).
        path.addArc(
            tangent1End: CGPoint(x: 0, y: 0), tangent2End: CGPoint(x: -radius, y: 0),
            radius: radius)
        path.addLine(to: CGPoint(x: -arm, y: 0))  // out along the horizontal arm
        let caret = SKShapeNode(path: path)
        caret.strokeColor = palette.flagGlyph
        caret.lineWidth = 4.5
        caret.lineCap = .round
        caret.lineJoin = .round
        node.addChild(caret)
        return node
    }

    /// Render the whole board to a small image for the minimap sprite.
    private func updateMinimapImage(boardW: Int, boardH: Int) {
        // Pixels-per-cell, capped so a 1000² board still renders to a sane bitmap.
        let maxDim = 240
        let ppc = max(1, min(maxDim / max(boardW, boardH), 4))
        // Render OFF the main thread (the per-cell loop is heavy on a 1M-cell
        // board): snapshot the Sendable board + colours now, apply the texture back
        // on the main actor only if no newer board state has superseded it.
        let board = viewModel.game.board
        let colors = overviewColors
        let generation = lastMinimapRevision
        // Supersede any render still running for an older revision — its result would
        // be discarded anyway, so don't let it finish burning a core. The render runs
        // in this child task (NOT `Task.detached`, which wouldn't inherit
        // cancellation) so `Task.isCancelled` inside `renderOverview` actually fires.
        minimapRenderTask?.cancel()
        minimapRenderTask = Task.detached { [weak self] in
            let cg = Self.renderOverview(
                board: board, width: boardW, height: boardH, ppc: ppc, colors: colors)
            guard let cg else { return }
            await MainActor.run {
                guard let self, !Task.isCancelled,
                    generation == self.lastMinimapRevision
                else { return }
                let texture = SKTexture(cgImage: cg)
                texture.filteringMode = .nearest  // crisp cell blocks, no blur
                self.minimapImage?.texture = texture
            }
        }
    }

    /// Overview fill colours, bundled `Sendable` so the render can run off the main
    /// actor (it can't touch `palette` there).
    struct OverviewColors: Sendable {
        let hidden, revealed, mine, flag: CGColor
    }
    var overviewColors: OverviewColors {
        OverviewColors(
            hidden: palette.hiddenTile.cgColor, revealed: palette.revealedTile.cgColor,
            mine: palette.mineTile.cgColor, flag: palette.flagGlyph.cgColor)
    }

    /// A downsampled image of the whole board (one `ppc`×`ppc` block per cell,
    /// hidden/revealed/mine/flag distinct), shared by the corner minimap and the
    /// fullscreen overview. Board row 0 paints at CG y=0 (what the viewport-rect
    /// math expects). The overview calls this synchronously; the live minimap runs
    /// it off the main thread (see `updateMinimapImage`).
    func boardOverviewImage(pixelsPerCell ppc: Int) -> CGImage? {
        Self.renderOverview(
            board: viewModel.game.board, width: viewModel.boardWidth,
            height: viewModel.boardHeight, ppc: ppc, colors: overviewColors)
    }

    /// Pure renderer — no `self`, so it runs on any thread. Inputs are `Sendable`.
    nonisolated static func renderOverview(
        board: Board, width boardW: Int, height boardH: Int, ppc: Int, colors: OverviewColors
    ) -> CGImage? {
        let pxW = boardW * ppc
        let pxH = boardH * ppc
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard
            let ctx = CGContext(
                data: nil, width: pxW, height: pxH, bitsPerComponent: 8, bytesPerRow: 0,
                space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        ctx.setFillColor(colors.hidden)
        ctx.fill(CGRect(x: 0, y: 0, width: pxW, height: pxH))
        // Walk the dense flat store by index — NOT `board[Coord(x,y)]`, which does a
        // topology `index(of:)` + protocol-witness dispatch + ARC retain/release per
        // cell. On a 1M-cell board that per-cell overhead WAS the runaway (profiled
        // ~74% of all CPU in `Board.subscript`/`swift_retain`). Index → x,y directly.
        var aborted = false
        board.forEachCellIndexed { i, cell in
            if aborted { return }
            // Cancellation: a newer board revision supersedes this render. Check only
            // periodically — `Task.isCancelled` per cell would itself be 1M calls.
            if i & 0x3FFF == 0, Task.isCancelled {
                aborted = true
                return
            }
            let color: CGColor?
            switch cell.state {
            case .revealed: color = cell.isMine ? colors.mine : colors.revealed
            case .flagged: color = colors.flag
            case .hidden: color = nil  // background already painted
            }
            guard let color else { return }
            let x = i % boardW
            let y = i / boardW
            ctx.setFillColor(color)
            ctx.fill(CGRect(x: x * ppc, y: y * ppc, width: ppc, height: ppc))
        }
        if aborted { return nil }
        return ctx.makeImage()
    }

    /// Position the minimap in the top-left corner and move the viewport rectangle
    /// to mirror the visible cell range. Camera children render WITHOUT the camera
    /// scale (per SKCameraNode docs), so everything here is plain screen points.
    private func layoutMinimap(boardW: Int, boardH: Int, range: CellRange) {
        guard let minimapNode, let minimapImage, let minimapViewport else { return }
        let mm = minimapSize(boardW: boardW, boardH: boardH)
        minimapImage.size = mm
        minimapImage.position = .zero

        // Panel frames the image with a small inset border.
        let framePad: CGFloat = 6
        minimapPanel?.path = CGPath(
            roundedRect: CGRect(
                x: -mm.width / 2 - framePad, y: -mm.height / 2 - framePad,
                width: mm.width + framePad * 2, height: mm.height + framePad * 2),
            cornerWidth: 6, cornerHeight: 6, transform: nil)

        // Fixed top-left corner: camera origin is screen centre, y-up.
        let halfW = size.width / 2
        let halfH = size.height / 2
        let pad = Self.minimapPadding
        minimapNode.position = CGPoint(
            x: -halfW + pad + mm.width / 2 + framePad,
            y: halfH - pad - mm.height / 2 - framePad)

        layoutMinimapViewport(mm: mm, boardW: boardW, boardH: boardH, range: range)

        // The minimap image's rect in CAMERA space (container pos + local image
        // half-extents) — the hit area for tap/drag-to-navigate.
        minimapImageRect = CGRect(
            x: minimapNode.position.x - mm.width / 2,
            y: minimapNode.position.y - mm.height / 2,
            width: mm.width, height: mm.height)

        // Resize caret at the corner point OUTSIDE the image's bottom-right (so the
        // map's own corner tile stays tappable). Container-local origin = the corner.
        let hx = mm.width / 2 + framePad + Self.handleGap
        let hy = -mm.height / 2 - framePad - Self.handleGap
        minimapHandle?.position = CGPoint(x: hx, y: hy)
        // L-shaped hit area in CAMERA space: a vertical arm (up the right edge) and a
        // horizontal arm (along the bottom), each a `handleThickness`-wide strip
        // spanning the arm, overlapping at the corner. Generous for touch.
        let cornerX = minimapNode.position.x + hx
        let cornerY = minimapNode.position.y + hy
        let arm = Self.handleArm
        let t = Self.handleThickness
        // Both arms start `t/2` past the corner (down/right) so they overlap a full
        // t×t square AT the bend — no uncovered notch there.
        minimapHandleRects = [
            // vertical arm: spans from below the corner up past the arm top
            CGRect(x: cornerX - t / 2, y: cornerY - t / 2, width: t, height: arm + t),
            // horizontal arm: spans from right of the corner left past the arm end
            CGRect(x: cornerX - arm - t / 2, y: cornerY - t / 2, width: arm + t, height: t),
        ]
    }

    /// Place the "you are here" viewport rect on the minimap. Bounded draws a single
    /// rect at the visible range; WRAPPED tiles it across the minimap edges (modulo
    /// the board) so the box splits at the seam to match the torus.
    private func layoutMinimapViewport(mm: CGSize, boardW: Int, boardH: Int, range: CellRange) {
        guard let minimapViewport else { return }
        let cellW = mm.width / CGFloat(boardW)
        let cellH = mm.height / CGFloat(boardH)
        let rw = CGFloat(range.maxX - range.minX + 1) * cellW
        let rh = CGFloat(range.maxY - range.minY + 1) * cellH
        let midX = CGFloat(range.minX + range.maxX) / 2 + 0.5
        let midY = CGFloat(range.minY + range.maxY) / 2 + 0.5

        guard isWrapped else {
            minimapViewport.path = CGPath(
                rect: CGRect(x: -rw / 2, y: -rh / 2, width: rw, height: rh), transform: nil)
            minimapViewport.position = CGPoint(
                x: -mm.width / 2 + midX * cellW, y: -mm.height / 2 + midY * cellH)
            return
        }
        // Torus: centre modulo the board, tile ±one board span per axis (enough — we
        // never show more than one board-worth), clip to the minimap, cap at its size.
        func mod(_ v: CGFloat, _ m: CGFloat) -> CGFloat {
            let r = v.truncatingRemainder(dividingBy: m)
            return r < 0 ? r + m : r
        }
        let cx = mod(midX * cellW, mm.width)
        let cy = mod(midY * cellH, mm.height)
        let bw = min(rw, mm.width)
        let bh = min(rh, mm.height)
        let full = CGRect(x: -mm.width / 2, y: -mm.height / 2, width: mm.width, height: mm.height)
        let path = CGMutablePath()
        for ox in [-mm.width, 0, mm.width] {
            for oy in [-mm.height, 0, mm.height] {
                let box = CGRect(
                    x: -mm.width / 2 + cx + ox - bw / 2,
                    y: -mm.height / 2 + cy + oy - bh / 2, width: bw, height: bh)
                let clipped = box.intersection(full)
                if !clipped.isNull { path.addRect(clipped) }
            }
        }
        minimapViewport.path = path
        minimapViewport.position = .zero
    }

    /// Scene point → camera-local (camera children ignore the camera scale).
    private func cameraLocal(_ p: CGPoint) -> CGPoint {
        CGPoint(
            x: (p.x - cameraNode.position.x) / cameraNode.xScale,
            y: (p.y - cameraNode.position.y) / cameraNode.yScale)
    }

    /// Begin minimap navigation: only if the point is INSIDE the map (so a tap/drag
    /// that starts elsewhere isn't hijacked). Recenters and returns true on a hit.
    @discardableResult
    func handleMinimapNavigation(atScenePoint p: CGPoint) -> Bool {
        guard !(minimapNode?.isHidden ?? true), let rect = minimapImageRect else { return false }
        guard rect.contains(cameraLocal(p)) else { return false }
        scrubMinimap(toScenePoint: p)
        return true
    }

    /// Continue a minimap scrub: recenter on the point, CLAMPED to the map bounds —
    /// so dragging a finger past the edge pins to that edge (and into a corner
    /// reaches the corner), rather than dropping the gesture once outside.
    func scrubMinimap(toScenePoint p: CGPoint) {
        guard let rect = minimapImageRect else { return }
        let camLocal = cameraLocal(p)
        // Normalize within the image, clamped to [0,1]. centerCamera expects
        // (0,0) = board TOP-left, but the texture renders row 0 at the BOTTOM →
        // flip y.
        let nx = min(max((camLocal.x - rect.minX) / rect.width, 0), 1)
        let ny = min(max(1 - (camLocal.y - rect.minY) / rect.height, 0), 1)
        centerCamera(onNormalizedPoint: CGPoint(x: nx, y: ny))
    }

    /// Whether a scene-space point is on the minimap's L-shaped resize handle.
    func minimapHandleHit(atScenePoint p: CGPoint) -> Bool {
        guard !(minimapNode?.isHidden ?? true) else { return false }
        let local = cameraLocal(p)
        return minimapHandleRects.contains { $0.contains(local) }
    }

    /// Resize the minimap so the dragged handle tracks the cursor. The minimap's
    /// top-LEFT screen anchor is fixed regardless of size, so the cursor's reach from
    /// that anchor (along the longer axis) IS the desired longer-side length; invert
    /// the scale↦size mapping to recover the scale.
    func resizeMinimap(toScenePoint p: CGPoint) {
        let viewportMin = min(size.width, size.height)
        let base = min(Self.minimapMaxSide, viewportMin * Self.minimapFraction)
        let maxLonger = max(base, viewportMin * Self.minimapMaxFraction)
        guard maxLonger > base else { return }
        // Fixed top-left anchor in camera-local coords (mirrors layoutMinimap's
        // corner math: -halfW + pad + framePad, halfH - pad - framePad).
        let framePad: CGFloat = 6
        let anchorX = -size.width / 2 + Self.minimapPadding + framePad
        let anchorY = size.height / 2 - Self.minimapPadding - framePad
        let local = cameraLocal(p)
        let reach = max(local.x - anchorX, anchorY - local.y)  // rightward / downward
        let t = (reach - base) / (maxLonger - base)
        setMinimapScale(Self.minimapScaleMin + t * (Self.minimapScaleMax - Self.minimapScaleMin))
    }

    /// Tap on the handle (or ⌘0) snaps between min and max size.
    func toggleMinimapSize() {
        let mid = (Self.minimapScaleMin + Self.minimapScaleMax) / 2
        setMinimapScale(minimapScale >= mid ? Self.minimapScaleMin : Self.minimapScaleMax)
    }

    /// Clamp + apply a new scale and push it to the host to persist. Re-layout is
    /// automatic on the next `update()` (refreshMinimap reads `minimapScale`).
    private func setMinimapScale(_ s: CGFloat) {
        let clamped = min(max(s, Self.minimapScaleMin), Self.minimapScaleMax)
        guard clamped != minimapScale else { return }
        minimapScale = clamped
        onMinimapScaleChange?(clamped)
    }
}
