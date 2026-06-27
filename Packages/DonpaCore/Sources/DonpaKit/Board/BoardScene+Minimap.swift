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

    func refreshMinimap() {
        let w = viewModel.boardWidth
        let h = viewModel.boardHeight
        let range = visibleRange()
        // `visibleRange` is clamped to the board, so covering it whole means it fits.
        let fits =
            range.minX <= 0 && range.minY <= 0 && range.maxX >= w - 1 && range.maxY >= h - 1
        // Publish so the toolbar toggle can disable when the board fits. Assign only
        // on change to avoid @Published churn every frame.
        let exceeds = !fits
        if viewModel.boardExceedsViewport != exceeds {
            viewModel.boardExceedsViewport = exceeds
        }
        guard exceeds, showMinimap else {
            minimapNode?.isHidden = true
            minimapExpandHitRect = nil  // no stale tap target while hidden
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

        layoutMinimap(boardW: w, boardH: h, range: range)
    }

    /// On-screen minimap size: the longer side scaled to the fraction (capped), the
    /// shorter following the board aspect.
    private func minimapSize(boardW: Int, boardH: Int) -> CGSize {
        let viewportMin = min(size.width, size.height)
        let longer = min(Self.minimapMaxSide, viewportMin * Self.minimapFraction)
        let aspect = CGFloat(boardW) / CGFloat(max(1, boardH))
        return aspect >= 1
            ? CGSize(width: longer, height: longer / aspect)
            : CGSize(width: longer * aspect, height: longer)
    }

    /// The minimap's full on-screen footprint (image + frame + edge gap), or nil
    /// when hidden. The pan clamp uses it to clear the corner so the board can rest
    /// over empty margin. The `+ 6` mirrors `layoutMinimap`'s `framePad`.
    func minimapCornerFootprint() -> CGSize? {
        guard showMinimap, viewModel.boardExceedsViewport else { return nil }
        let mm = minimapSize(boardW: viewModel.boardWidth, boardH: viewModel.boardHeight)
        let extra = Self.minimapPadding + 6  // edge gap + frame border (framePad)
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

        // Expand badge (bottom-right): tapping its padded rect opens the fullscreen
        // overview. Built once; positioned in `layoutMinimap`.
        let expand = expandIconNode()
        expand.zPosition = 3
        container.addChild(expand)
        minimapExpand = expand

        cameraNode.addChild(container)
        minimapNode = container
    }

    /// A small "expand to fullscreen" badge: a rounded square with outward corner
    /// ticks, on an opaque disc so it reads against the map.
    private func expandIconNode() -> SKNode {
        let r: CGFloat = 12
        let node = SKNode()
        let disc = SKShapeNode(circleOfRadius: r)
        disc.fillColor = palette.flagGlyph
        disc.strokeColor = palette.sceneBackground
        disc.lineWidth = 1.5
        node.addChild(disc)
        // Four outward corner ticks (the expand glyph).
        let a = r * 0.42
        for (sx, sy) in [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)] {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: sx * a, y: sy * a * 0.4))
            path.addLine(to: CGPoint(x: sx * a, y: sy * a))
            path.addLine(to: CGPoint(x: sx * a * 0.4, y: sy * a))
            let tick = SKShapeNode(path: path)
            tick.strokeColor = palette.sceneBackground
            tick.lineWidth = 2
            tick.lineCap = .round
            node.addChild(tick)
        }
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
        Task {
            let cg = await Task.detached {
                Self.renderOverview(
                    board: board, width: boardW, height: boardH, ppc: ppc, colors: colors)
            }.value
            guard let cg, generation == lastMinimapRevision else { return }
            let texture = SKTexture(cgImage: cg)
            texture.filteringMode = .nearest  // crisp cell blocks, no blur
            minimapImage?.texture = texture
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
        for y in 0..<boardH {
            for x in 0..<boardW {
                let cell = board[Coord(x, y)]
                let color: CGColor?
                switch cell.state {
                case .revealed: color = cell.isMine ? colors.mine : colors.revealed
                case .flagged: color = colors.flag
                case .hidden: color = nil  // background already painted
                }
                guard let color else { continue }
                ctx.setFillColor(color)
                ctx.fill(CGRect(x: x * ppc, y: y * ppc, width: ppc, height: ppc))
            }
        }
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

        // Viewport rectangle mapped onto the minimap image. `SKTexture(cgImage:)`
        // renders board row 0 at the minimap BOTTOM, so map board-y bottom-up.
        let cellW = mm.width / CGFloat(boardW)
        let cellH = mm.height / CGFloat(boardH)
        let rw = CGFloat(range.maxX - range.minX + 1) * cellW
        let rh = CGFloat(range.maxY - range.minY + 1) * cellH
        minimapViewport.path = CGPath(
            rect: CGRect(x: -rw / 2, y: -rh / 2, width: rw, height: rh), transform: nil)
        let midX = CGFloat(range.minX + range.maxX) / 2 + 0.5
        let midY = CGFloat(range.minY + range.maxY) / 2 + 0.5
        minimapViewport.position = CGPoint(
            x: -mm.width / 2 + midX * cellW,
            y: -mm.height / 2 + midY * cellH)

        // Expand badge in the minimap's bottom-right corner (container-local).
        let bx = mm.width / 2 - 2
        let by = -mm.height / 2 + 2
        minimapExpand?.position = CGPoint(x: bx, y: by)
        // Tappable rect in CAMERA space = container + local pos ± a padded radius.
        let hitR: CGFloat = 18
        minimapExpandHitRect = CGRect(
            x: minimapNode.position.x + bx - hitR, y: minimapNode.position.y + by - hitR,
            width: hitR * 2, height: hitR * 2)
    }

    /// Test a scene-space tap against the expand badge; if it hits, open the
    /// overview and return true (so it's not treated as a board move).
    func handleMinimapTap(atScenePoint p: CGPoint) -> Bool {
        guard !(minimapNode?.isHidden ?? true), let hit = minimapExpandHitRect else { return false }
        // Scene → camera-local: subtract the camera centre, divide by scale.
        let camLocal = CGPoint(
            x: (p.x - cameraNode.position.x) / cameraNode.xScale,
            y: (p.y - cameraNode.position.y) / cameraNode.yScale)
        guard hit.contains(camLocal) else { return false }
        onOpenOverview?()
        return true
    }
}
