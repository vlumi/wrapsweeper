import DonpaCore
import SpriteKit

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Cell-node construction and **viewport culling**: only cells in the camera's
/// visible rect are built (kept in `cellNodes`), so the live node count stays ~one
/// screenful regardless of board size — what makes huge boards tractable.
extension BoardScene {
    func rebuildIfNeeded() {
        if viewModel.gameID != lastGameID {
            lastGameID = viewModel.gameID
            lastAnimatedResultID = -1  // a fresh game can animate its own result
            effectsLayer.removeAllChildren()
            boardLayer.position = .zero  // clear any leftover shake offset
            // A resumed game adopts its saved view as the sticky restore target
            // (consuming the VM's one-shot hand-off); a fresh game clears it and
            // falls back to the default fit.
            restoreCameraTarget = viewModel.pendingCameraRestore
            viewModel.pendingCameraRestore = nil
            applyDesiredCameraOrCenter()
        }
        if viewModel.revision != lastRevision {
            lastRevision = viewModel.revision
            rebuild()
        }
        // Play the end-game effect once, in the same turn as the rebuild so the
        // shockwave radiates over the just-revealed mines in sync.
        if let event = viewModel.lastResult, event.id != lastAnimatedResultID {
            lastAnimatedResultID = event.id
            playEndGameEffects(event.result)
        }
    }

    /// An inclusive rectangular range of cell coordinates (the visible window).
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
        // World rect → cell indices, +1 cell of margin each side so cells appear
        // before fully scrolling in.
        let minX = max(0, Int(((cam.x - halfW) / cell).rounded(.down)) - 1)
        let maxX = min(w - 1, Int(((cam.x + halfW) / cell).rounded(.down)) + 1)
        let minY = max(0, Int(((cam.y - halfH) / cell).rounded(.down)) - 1)
        let maxY = min(h - 1, Int(((cam.y + halfH) / cell).rounded(.down)) + 1)
        return CellRange(minX: minX, maxX: maxX, minY: minY, maxY: maxY)
    }

    /// The camera's visible region as a normalized rect (0…1, y from the board TOP
    /// down). The fullscreen overview draws and drags this "you are here" box.
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
        // World y is up; flip to top-down (high world y = board top).
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

    /// Sync built cell nodes to the visible range: add newly-visible, remove
    /// newly-hidden. O(visible), idempotent — safe to call on every viewport change.
    func buildVisibleCells() {
        let range = visibleRange()
        guard range != builtRange else { return }
        // An inverted range (min > max) can occur transiently before the scene has
        // a valid size or the camera is clamped; `minY...maxY` would trap, so bail
        // this frame and let a later one build.
        guard range.minX <= range.maxX, range.minY <= range.maxY else { return }
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

    /// Instant mine-hit feedback: swap the tapped cell to its revealed hit-mine
    /// face synchronously on tap, before the off-thread reveal — so it appears the
    /// moment you click. The detonation FX follows when the reveal lands (playLoss);
    /// no explosion here, so it doesn't cover the just-shown tile. The post-reveal
    /// rebuild produces an identical node, so the handoff is seamless.
    func revealHitTileInstantly(at c: Coord) {
        let size = layout.cellSize
        cellNodes[c]?.removeFromParent()
        let container = SKNode()
        let tile = SKSpriteNode(texture: tileTexture(forFill: palette.mineTile))
        tile.size = CGSize(width: size, height: size)
        container.addChild(tile)
        let burst = burstMineNode(size: size)
        burst.zPosition = 1
        container.addChild(burst)
        container.position = layout.center(of: c)
        boardLayer.addChild(container)
        cellNodes[c] = container
    }

    private func cellNode(for coord: Coord, cell: Cell) -> SKNode {
        let size = layout.cellSize
        let container = SKNode()

        let tile = SKSpriteNode(texture: tileTexture(for: cell))
        tile.size = CGSize(width: size, height: size)
        container.addChild(tile)

        // Overlay above the tile. SKShapeNodes (flag, burst) render in a separate
        // pass from the sprite tile; without an explicit higher z they draw under
        // it and vanish. Set z on all overlays uniformly.
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
            return nil  // drawn as a flagNode, not a text glyph
        case .hidden:
            return nil
        case .revealed:
            if cell.isMine { return ("✸", palette.mineGlyph) }
            guard cell.adjacentMines > 0 else { return nil }
            return (String(cell.adjacentMines), palette.number(cell.adjacentMines))
        }
    }

    // MARK: Cached cell textures

    /// Cell-sized rounded-rect tile background, cached by fill colour + pixel size.
    /// ~3 distinct textures (hidden / revealed / mine) shared across every tile.
    private func tileTexture(for cell: Cell) -> SKTexture {
        tileTexture(forFill: fillColor(for: cell))
    }

    /// The cached rounded-rect tile background for a given fill colour.
    func tileTexture(forFill fill: SKColor) -> SKTexture {
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

    /// Cell-sized texture of a centred glyph (number or `✸` mine), cached by text +
    /// colour + pixel size. Drawn via the platform image renderer, not text into a
    /// raw CGContext — the latter renders flipped/off-canvas.
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

    /// Render a square `dim×dim` transparent image with `draw` into a CGImage for an
    /// `SKTexture`. Shapes only; text uses the platform renderer in `glyphTexture`.
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
