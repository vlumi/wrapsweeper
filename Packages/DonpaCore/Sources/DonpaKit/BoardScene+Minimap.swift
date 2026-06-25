import DonpaCore
import SpriteKit

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// A corner overview ("minimap") of the whole board with a rectangle marking the
/// visible viewport — the navigation aid for boards too big to see at once.
///
/// Shown only when the board exceeds the viewport (small/classic boards that fit
/// don't need it). The overview is a single downsampled `SKTexture` (one node, not
/// per-cell), rebuilt only when the board state changes; the viewport rectangle is
/// repositioned every frame as you pan/zoom. Pinned to the camera so it stays
/// fixed on screen — in ONE fixed corner (top-left); a minimap that hops corners
/// as you pan would feel unstable.
extension BoardScene {
    /// Fraction of the shorter viewport side the minimap's longer side spans.
    private static let minimapFraction: CGFloat = 0.26
    private static let minimapMaxSide: CGFloat = 200
    /// Padding from the viewport edges so the minimap doesn't crowd/cover the
    /// playfield right at the corner.
    private static let minimapPadding: CGFloat = 16

    func refreshMinimap() {
        let w = viewModel.boardWidth
        let h = viewModel.boardHeight
        let range = visibleRange()
        // Only when the board is bigger than what's visible (else it fits — no
        // overview needed). `visibleRange` is clamped to the board, so "covers the
        // whole board" means it fits.
        let fits =
            range.minX <= 0 && range.minY <= 0 && range.maxX >= w - 1 && range.maxY >= h - 1
        // Publish to the chrome so the toolbar toggle can disable itself when the
        // whole board fits (nothing to map). Only assign on change to avoid
        // needless @Published churn every frame.
        let exceeds = !fits
        if viewModel.boardExceedsViewport != exceeds {
            viewModel.boardExceedsViewport = exceeds
        }
        // Show only when the board exceeds the view AND the user wants it.
        guard exceeds, showMinimap else {
            minimapNode?.isHidden = true
            return
        }

        ensureMinimapNode()
        minimapNode?.isHidden = false

        // Rebuild the overview image only when the board changed (revealed cells)
        // or the board itself changed (new game / different size).
        let boardSize = CGSize(width: w, height: h)
        if viewModel.revision != lastMinimapRevision || boardSize != lastMinimapBoard {
            lastMinimapRevision = viewModel.revision
            lastMinimapBoard = boardSize
            updateMinimapImage(boardW: w, boardH: h)
        }

        layoutMinimap(boardW: w, boardH: h, range: range)
    }

    /// On-screen size of the minimap (the longer side scaled to the fraction, the
    /// shorter side following the board's aspect ratio). Capped.
    private func minimapSize(boardW: Int, boardH: Int) -> CGSize {
        let viewportMin = min(size.width, size.height)
        let longer = min(Self.minimapMaxSide, viewportMin * Self.minimapFraction)
        let aspect = CGFloat(boardW) / CGFloat(max(1, boardH))
        return aspect >= 1
            ? CGSize(width: longer, height: longer / aspect)
            : CGSize(width: longer * aspect, height: longer)
    }

    private func ensureMinimapNode() {
        guard minimapNode == nil else { return }
        let container = SKNode()
        container.zPosition = 100  // above the board, below nothing else on camera

        // Opaque panel + border so the minimap reads as a distinct HUD element,
        // not part of the board (the overview's tile greys otherwise blend into
        // the board's). Sized to the image in `layoutMinimap`.
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

        cameraNode.addChild(container)
        minimapNode = container
    }

    /// Render the whole board to a small image: one pixel block per cell, hidden
    /// vs revealed vs mine shaded distinctly. O(cells) once per board change, not
    /// per frame — and a single sprite, not per-cell nodes.
    private func updateMinimapImage(boardW: Int, boardH: Int) {
        // Pixel-per-cell, capped so a 1000² board still renders to a sane bitmap.
        let maxDim = 240
        let ppc = max(1, min(maxDim / max(boardW, boardH), 4))
        let pxW = boardW * ppc
        let pxH = boardH * ppc
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard
            let ctx = CGContext(
                data: nil, width: pxW, height: pxH, bitsPerComponent: 8, bytesPerRow: 0,
                space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }

        ctx.setFillColor(palette.hiddenTile.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: pxW, height: pxH))

        let board = viewModel.game.board
        let revealed = palette.revealedTile.cgColor
        let mine = palette.mineTile.cgColor
        let flag = palette.flagGlyph.cgColor
        // CG origin is bottom-left; board y grows downward in our layout, so flip y.
        for y in 0..<boardH {
            for x in 0..<boardW {
                let cell = board[Coord(x, y)]
                let color: CGColor?
                switch cell.state {
                case .revealed: color = cell.isMine ? mine : revealed
                case .flagged: color = flag
                case .hidden: color = nil  // background already painted
                }
                guard let color else { continue }
                ctx.setFillColor(color)
                // No y-flip: board row 0 paints at CG y=0; combined with the
                // sprite's presentation this lands board-top at minimap-top,
                // matching the viewport-rect math (which is y-up from the top).
                ctx.fill(CGRect(x: x * ppc, y: y * ppc, width: ppc, height: ppc))
            }
        }
        guard let cg = ctx.makeImage() else { return }
        let texture = SKTexture(cgImage: cg)
        texture.filteringMode = .nearest  // crisp cell blocks, no blur
        minimapImage?.texture = texture
    }

    /// Position + size the minimap in the fixed top-left corner, and move the
    /// viewport rectangle to mirror the visible cell range. Camera children render
    /// WITHOUT the camera's scale applied (per SKCameraNode docs), so everything
    /// here is in plain screen points — no counter-scaling, and zoom doesn't move
    /// or resize the minimap.
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

        // Viewport rectangle: map the visible cell range onto the minimap image.
        // `SKTexture(cgImage:)` renders the overview with board row 0 at the
        // minimap BOTTOM on both platforms (verified on device: the image looks
        // correct, the rect was the mirrored one). So map board-y bottom-up —
        // minimap-bottom (−h/2) plus y — to track the image.
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
    }
}
