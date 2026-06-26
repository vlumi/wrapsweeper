import DonpaCore
import SpriteKit

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Board rendering: cell-node construction and **viewport culling**. Only cells
/// within the camera's visible rect are built (kept in `cellNodes`), so the live
/// node count stays ~one screenful regardless of board size — the path that makes
/// huge boards (e.g. 100×100) tractable. Split out of BoardScene.swift to keep
/// that file within length limits.
extension BoardScene {
    func rebuildIfNeeded() {
        if viewModel.gameID != lastGameID {
            lastGameID = viewModel.gameID
            lastAnimatedResultID = -1  // a fresh game can animate its own result
            effectsLayer.removeAllChildren()
            boardLayer.position = .zero  // clear any leftover shake offset
            // A resumed game adopts its saved view as the sticky restore target
            // (consume the VM's one-shot hand-off); a fresh game has none, so the
            // target is cleared and we fall back to the default fit. The target
            // survives the launch-time resizes that would otherwise re-centre over
            // it (cleared once the player pans/zooms — see BoardScene+Pan).
            restoreCameraTarget = viewModel.pendingCameraRestore
            viewModel.pendingCameraRestore = nil
            applyDesiredCameraOrCenter()
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

    /// An inclusive rectangular range of cell coordinates (the visible window).
    /// Internal so the +Effects extension can cull the mode-glow to the same range.
    struct CellRange: Equatable {
        let minX, maxX, minY, maxY: Int
        func contains(_ c: Coord) -> Bool {
            c.x >= minX && c.x <= maxX && c.y >= minY && c.y <= maxY
        }
        /// Visit every coordinate in the range (row-major).
        func forEach(_ body: (Coord) -> Void) {
            guard minX <= maxX, minY <= maxY else { return }
            for y in minY...maxY {
                for x in minX...maxX { body(Coord(x, y)) }
            }
        }
    }

    /// The cells currently within the camera's viewport, plus a one-cell margin so
    /// a cell is built just before it scrolls in. Clamped to the board bounds, so
    /// for a board that fits the viewport this is the whole board (culling no-op).
    func visibleRange() -> CellRange {
        let w = viewModel.boardWidth
        let h = viewModel.boardHeight
        let scale = cameraNode.xScale
        // Visible world half-extents: scene is `size` points, scaled by the camera.
        let halfW = size.width / 2 * scale
        let halfH = size.height / 2 * scale
        let cam = cameraNode.position
        let cell = layout.cellSize
        // World rect → cell indices (SquareLayout: cell = floor(world / cellSize)).
        // +1 cell of margin each side so cells appear before scrolling fully in.
        let minX = max(0, Int(((cam.x - halfW) / cell).rounded(.down)) - 1)
        let maxX = min(w - 1, Int(((cam.x + halfW) / cell).rounded(.down)) + 1)
        let minY = max(0, Int(((cam.y - halfH) / cell).rounded(.down)) - 1)
        let maxY = min(h - 1, Int(((cam.y + halfH) / cell).rounded(.down)) + 1)
        return CellRange(minX: minX, maxX: maxX, minY: minY, maxY: maxY)
    }

    /// The camera's currently-visible region as a normalized rect (0…1 in each
    /// axis, y measured from the board TOP down — matching screen/board layout).
    /// The fullscreen overview draws and drags this "you are here" box. Clamped to
    /// the board; spans the whole board when it fits the viewport.
    public func visibleNormalizedRect() -> CGRect {
        let board = layout.boardSize(width: viewModel.boardWidth, height: viewModel.boardHeight)
        guard board.width > 0, board.height > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        let scale = cameraNode.xScale
        let halfW = size.width / 2 * scale
        let halfH = size.height / 2 * scale
        let cam = cameraNode.position
        let minX = max(0, (cam.x - halfW) / board.width)
        let maxX = min(1, (cam.x + halfW) / board.width)
        // World y is up; flip to top-down. The camera's high-y edge is the board
        // top, so the rect's top (small normalized y) comes from the high world y.
        let topY = max(0, 1 - (cam.y + halfH) / board.height)
        let botY = min(1, 1 - (cam.y - halfH) / board.height)
        return CGRect(x: minX, y: topY, width: maxX - minX, height: botY - topY)
    }

    /// Full rebuild: drop all cell nodes and rebuild those in the visible range.
    /// Called on a board-state change (`revision`) or palette change.
    func rebuild() {
        boardLayer.removeAllChildren()
        cellNodes.removeAll(keepingCapacity: true)
        builtRange = nil
        buildVisibleCells()
    }

    /// Bring the built cell nodes in line with the current visible range: add
    /// newly-visible cells, remove newly-hidden ones. O(visible), not O(board) —
    /// the core of culling. Idempotent, so it's safe to call on every viewport
    /// change (pan/zoom) and after a rebuild.
    func buildVisibleCells() {
        let range = visibleRange()
        guard range != builtRange else { return }
        let game = viewModel.game

        // Remove cells that have scrolled out of view.
        for (c, node) in cellNodes where !range.contains(c) {
            node.removeFromParent()
            cellNodes[c] = nil
        }
        // Add cells that have scrolled into view (skip any already built).
        for y in range.minY...range.maxY {
            for x in range.minX...range.maxX {
                let c = Coord(x, y)
                guard cellNodes[c] == nil else { continue }
                let node = cellNode(for: c, cell: game.board[c])
                node.position = layout.center(of: c)
                boardLayer.addChild(node)
                cellNodes[c] = node
            }
        }
        builtRange = range
    }

    /// A cell as `SKSpriteNode`s over cached, shared textures (tile background +
    /// number/mine glyph), so hundreds of visible cells batch into few draw calls
    /// rather than each being a freshly-tessellated `SKShapeNode`. The rare drawn
    /// glyphs — the swallowtail flag and the loss burst-mine — stay as their own
    /// nodes (few on screen at once, not worth caching).
    private func cellNode(for coord: Coord, cell: Cell) -> SKNode {
        let size = layout.cellSize
        let container = SKNode()

        let tile = SKSpriteNode(texture: tileTexture(for: cell))
        tile.size = CGSize(width: size, height: size)
        container.addChild(tile)

        // Overlay above the tile. The flag and burst are SKShapeNode-based; an
        // SKSpriteNode (the tile) and SKShapeNodes render in separate passes, so
        // without an explicit higher zPosition the shapes draw *under* the sprite
        // tile and vanish. Texture glyphs (also sprites) layer fine, but set z on
        // all overlays uniformly so the rule is one line, not per-branch.
        let overlay: SKNode?
        if cell.state == .revealed, cell.isMine, coord == viewModel.game.lossCoord {
            overlay = burstMineNode(size: size)
        } else if cell.state == .flagged {
            overlay = flagNode(size: size, color: palette.flagGlyph)
        } else if let glyph = glyph(for: cell) {
            let sprite = SKSpriteNode(texture: glyphTexture(glyph.text, color: glyph.color))
            sprite.size = CGSize(width: size, height: size)
            overlay = sprite
        } else {
            overlay = nil
        }
        if let overlay {
            overlay.zPosition = 1
            container.addChild(overlay)
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
            return nil  // drawn as a swallowtail flagNode, not a text glyph
        case .hidden:
            return nil
        case .revealed:
            if cell.isMine { return ("✸", palette.mineGlyph) }
            guard cell.adjacentMines > 0 else { return nil }
            return (String(cell.adjacentMines), palette.number(cell.adjacentMines))
        }
    }

    // MARK: Cached cell textures

    /// Cell-sized rounded-rect tile background (inset 1pt, corner 3pt — matching
    /// the previous `SKShapeNode`), cached by fill colour + pixel size. ~3 distinct
    /// textures (hidden / revealed / mine) shared across every tile on screen.
    private func tileTexture(for cell: Cell) -> SKTexture {
        let fill = fillColor(for: cell)
        let px = max(4, Int(layout.cellSize.rounded()))
        let key = "tile-\(px)-\(fill)"
        if let cached = tileTextureCache[key] { return cached }

        let scale: CGFloat = 2  // supersample for a crisp rounded corner
        let dim = Int(CGFloat(px) * scale)
        let inset = 1 * scale
        let corner = 3 * scale
        let img = drawCellImage(dim: dim) { ctx in
            let rect = CGRect(
                x: inset, y: inset, width: CGFloat(dim) - inset * 2,
                height: CGFloat(dim) - inset * 2)
            let path = CGPath(
                roundedRect: rect, cornerWidth: corner, cornerHeight: corner,
                transform: nil)
            ctx.addPath(path)
            ctx.setFillColor(fill.cgColor)
            ctx.fillPath()
        }
        let texture = SKTexture(cgImage: img)
        texture.filteringMode = .linear
        tileTextureCache[key] = texture
        return texture
    }

    /// A cell-sized texture of a centred glyph (a number or the `✸` mine), cached
    /// by text + colour + pixel size, so all "3" cells (say) share one texture.
    /// Drawn via the platform image renderer (which handles the text coordinate
    /// system correctly) rather than text into a raw CGContext — the latter
    /// renders flipped/off-canvas, so glyphs didn't appear.
    private func glyphTexture(_ text: String, color: SKColor) -> SKTexture {
        let px = max(4, Int(layout.cellSize.rounded()))
        let key = "glyph-\(text)-\(px)-\(color)"
        if let cached = tileTextureCache[key] { return cached }

        let scale: CGFloat = 2
        let dim = CGFloat(px) * scale
        let fontSize = dim * 0.5
        #if os(macOS)
        let font =
            NSFont(name: "Menlo-Bold", size: fontSize)
            ?? .monospacedSystemFont(ofSize: fontSize, weight: .bold)
        #else
        let font =
            UIFont(name: "Menlo-Bold", size: fontSize)
            ?? .monospacedSystemFont(ofSize: fontSize, weight: .bold)
        #endif
        let str = NSAttributedString(
            string: text, attributes: [.font: font, .foregroundColor: color])
        let bounds = str.size()
        let rect = CGRect(
            x: (dim - bounds.width) / 2, y: (dim - bounds.height) / 2,
            width: bounds.width, height: bounds.height)
        let canvas = CGSize(width: dim, height: dim)

        let cgImage: CGImage
        #if os(macOS)
        let image = NSImage(size: canvas)
        image.lockFocus()
        str.draw(in: rect)
        image.unlockFocus()
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return SKTexture()
        }
        cgImage = cg
        #else
        let renderer = UIGraphicsImageRenderer(size: canvas)
        let uiImage = renderer.image { _ in str.draw(in: rect) }
        guard let cg = uiImage.cgImage else { return SKTexture() }
        cgImage = cg
        #endif

        let texture = SKTexture(cgImage: cgImage)
        texture.filteringMode = .linear
        tileTextureCache[key] = texture
        return texture
    }

    /// Render a square `dim×dim` transparent image with `draw`, returning the
    /// CGImage for an `SKTexture`. Used by the tile texture builder (shapes only;
    /// text uses the platform renderer in `glyphTexture`).
    private func drawCellImage(dim: Int, _ draw: (CGContext) -> Void) -> CGImage {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: nil, width: dim, height: dim, bitsPerComponent: 8, bytesPerRow: 0,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.clear(CGRect(x: 0, y: 0, width: dim, height: dim))
        draw(ctx)
        return ctx.makeImage()!
    }
}
