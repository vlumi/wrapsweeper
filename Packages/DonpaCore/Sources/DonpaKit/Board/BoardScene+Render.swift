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

    /// Whether the board wraps (torus). Wrapped boards scroll seamlessly: the
    /// viewport range is NOT clamped to bounds (it extends past the edges, with
    /// off-board screen positions resolving to wrapped cells via `displayCoord`).
    var isWrapped: Bool { viewModel.config.edges == .wrapped }

    /// Map a *screen* cell position (which on a wrapped board can be negative or
    /// ≥ width/height) to the logical board cell it shows. Identity when bounded.
    func displayCoord(_ screen: Coord) -> Coord {
        guard isWrapped else { return screen }
        // `normalize` folds with modulo and never returns nil for a wrapped board.
        return viewModel.game.board.topology.normalize(screen) ?? screen
    }

    /// The cells currently within the camera's viewport, plus a one-cell margin so
    /// a cell is built just before it scrolls in. For a BOUNDED board this is
    /// clamped to the board (the whole board when it fits — culling no-op); for a
    /// WRAPPED board it's left unclamped so the surface tiles infinitely as you pan,
    /// and each screen position resolves to a wrapped cell at build time.
    func visibleRange() -> CellRange {
        let w = viewModel.boardWidth
        let h = viewModel.boardHeight
        let scale = cameraNode.xScale
        // Visible world half-extents: scene is `size` points, scaled by the camera.
        let halfW = size.width / 2 * scale
        let halfH = size.height / 2 * scale
        let cam = cameraNode.position
        // Column/row pitch differ on a hex board (rows interlock at 3/4 height, and
        // odd rows shift half a column right), so map the world rect to indices with
        // each axis's own pitch. +2 columns / +1 row of margin covers the half-shift
        // and lets cells appear before fully scrolling in.
        let colPitch = layout.columnPitch
        let rowPitch = layout.rowPitch
        let rawMinX = Int(((cam.x - halfW) / colPitch).rounded(.down)) - 2
        let rawMaxX = Int(((cam.x + halfW) / colPitch).rounded(.down)) + 2
        let rawMinY = Int(((cam.y - halfH) / rowPitch).rounded(.down)) - 1
        let rawMaxY = Int(((cam.y + halfH) / rowPitch).rounded(.down)) + 1
        guard !isWrapped else {
            return CellRange(minX: rawMinX, maxX: rawMaxX, minY: rawMinY, maxY: rawMaxY)
        }
        return CellRange(
            minX: max(0, rawMinX), maxX: min(w - 1, rawMaxX),
            minY: max(0, rawMinY), maxY: min(h - 1, rawMaxY))
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
        // Add cells that have scrolled into view (skip any already built). The key
        // is the SCREEN position `c` (so a wrapped cell visible at two screen spots
        // across a seam is two nodes); the cell shown is `displayCoord(c)` —
        // identity when bounded, the wrapped cell when not. Node is laid out at the
        // screen position, so off-board positions tile past the edges.
        for y in range.minY...range.maxY {
            for x in range.minX...range.maxX {
                let c = Coord(x, y)
                guard cellNodes[c] == nil else { continue }
                // `c` is the screen position; `cell` is the logical cell it shows.
                // Pass the logical coord to `cellNode` so its loss-coord / over-flag
                // checks compare correctly; position the node at the screen spot.
                let cell = displayCoord(c)
                let node = cellNode(for: cell, cell: game.board[cell])
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
        tile.size = layout.tileSize
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
        tile.size = layout.tileSize
        container.addChild(tile)

        // Overlay above the tile. SKShapeNodes (flag, burst) render in a separate
        // pass from the sprite tile; without an explicit higher z they draw under
        // it and vanish. Set z on all overlays uniformly.
        let overlay: SKNode?
        if cell.state == .revealed, cell.isMine, coord == viewModel.game.lossCoord {
            overlay = burstMineNode(size: size)
        } else if cell.state == .flagged {
            overlay = flagSprite(size: size, color: palette.flagGlyph)
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
        // Passive error cue: ring a revealed number that has more flags around it
        // than its count (impossible — you slipped a flag). Above the glyph (z 2).
        if viewModel.game.board.isOverFlagged(coord) {
            let ring = overFlagRingSprite(size: size)
            ring.zPosition = 2
            container.addChild(ring)
        }
        return container
    }

    // Non-private: read by the tile-texture builders in BoardScene+TileTextures.
    func fillColor(for cell: Cell) -> SKColor {
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

    // Cached cell textures (tile / ring / flag / glyph) live in
    // BoardScene+TileTextures.swift — the shape-aware drawing that keeps big boards
    // batching. `fillColor` / `glyph` below feed them the per-cell colour + text.
}
