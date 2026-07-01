import DonpaCore
import SpriteKit

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Cached cell textures: the tile background, over-flag ring, flag, and number
/// glyphs are drawn once per (shape, size, colour) and shared across every cell, so
/// SpriteKit batches same-texture sprites into ~one draw call — the path that keeps
/// huge boards cheap. The tile/ring outline follows `layout.tileShape` (rounded
/// square or pointy-top hexagon); a hex tile is drawn on a taller-than-wide canvas
/// (`layout.tileSize`) so vertically-interlocking rows tile without gaps.
extension BoardScene {
    /// Cell-sized tile background, cached by fill colour + pixel size.
    /// ~3 distinct textures (hidden / revealed / mine) shared across every tile.
    func tileTexture(for cell: Cell) -> SKTexture {
        tileTexture(forFill: fillColor(for: cell))
    }

    /// The cached tile background for a given fill colour — a rounded square or a
    /// pointy-top hexagon, per `layout.tileShape`. Drawn on a canvas matching the
    /// tile's aspect (a hex is taller than wide), so the sprite tiles seamlessly.
    func tileTexture(forFill fill: SKColor) -> SKTexture {
        let shape = layout.tileShape
        let (wPx, hPx) = tilePixelSize()
        let key = "tile-\(shape)-\(wPx)x\(hPx)-\(fill)"
        if let cached = tileTextureCache[key] { return cached }

        let scale: CGFloat = 2  // supersample for a crisp edge
        let inset = 1 * scale
        let img = drawTileImage(wPx: wPx, hPx: hPx, scale: scale) { ctx, w, h in
            addTilePath(to: ctx, shape: shape, w: w, h: h, inset: inset)
            ctx.setFillColor(fill.cgColor)
            ctx.fillPath()
        }
        let texture = SKTexture(cgImage: img)
        texture.filteringMode = .linear
        tileTextureCache[key] = texture
        return texture
    }

    /// The tile texture's pixel dimensions (rounded from `layout.tileSize`).
    func tilePixelSize() -> (w: Int, h: Int) {
        (
            max(4, Int(layout.tileSize.width.rounded())),
            max(4, Int(layout.tileSize.height.rounded()))
        )
    }

    /// Add the tile outline (rounded square or pointy-top hexagon) to `ctx`, inset
    /// from the `w×h` canvas edges (canvas points, already scaled by the caller).
    /// Non-private so the mode-glow can clip its screentone to the same outline.
    func addTilePath(
        to ctx: CGContext, shape: TileShape, w: CGFloat, h: CGFloat, inset: CGFloat
    ) {
        let lo = inset
        let rightX = w - inset
        let topY = h - inset
        switch shape {
        case .roundedSquare:
            let corner = 3 * (w / max(4, layout.cellSize))
            ctx.addPath(
                CGPath(
                    roundedRect: CGRect(x: lo, y: lo, width: rightX - lo, height: topY - lo),
                    cornerWidth: corner, cornerHeight: corner, transform: nil))
        case .pointyHex:
            // Pointy-top regular hexagon: vertices at top & bottom (canvas full
            // height), flats left & right (canvas full width). The two side vertices
            // sit a quarter of the vertex-to-vertex height in from top and bottom.
            let midX = w / 2
            let quarterH = (topY - lo) * 0.25
            ctx.move(to: CGPoint(x: midX, y: topY))  // top vertex
            ctx.addLine(to: CGPoint(x: rightX, y: topY - quarterH))  // upper-right
            ctx.addLine(to: CGPoint(x: rightX, y: lo + quarterH))  // lower-right
            ctx.addLine(to: CGPoint(x: midX, y: lo))  // bottom vertex
            ctx.addLine(to: CGPoint(x: lo, y: lo + quarterH))  // lower-left
            ctx.addLine(to: CGPoint(x: lo, y: topY - quarterH))  // upper-left
            ctx.closePath()
        }
    }

    /// A sprite carrying the cached flag texture, sized to the cell. Use this instead
    /// of `flagNode` (a tree of `SKShapeNode`s) anywhere many flags can be on screen
    /// at once: SpriteKit re-strokes every visible `SKShapeNode`'s path EVERY frame
    /// (`CGPathCreateCopyByStrokingPath` — profiled hot on a huge board with many
    /// flags), whereas same-texture sprites batch and never re-stroke.
    func flagSprite(size: CGFloat, color: SKColor) -> SKSpriteNode {
        let sprite = SKSpriteNode(texture: flagTexture(color: color))
        sprite.size = CGSize(width: size, height: size)
        return sprite
    }

    /// A sprite ringing an over-flagged number (more flags around it than its count —
    /// a definite error). A cached texture, not an `SKShapeNode`, so it batches and
    /// never re-strokes per frame like everything else on the board. Kept faint: it's
    /// a quiet "check this", not an alarm.
    func overFlagRingSprite(size: CGFloat) -> SKSpriteNode {
        let sprite = SKSpriteNode(texture: overFlagRingTexture(color: palette.mineGlyph))
        sprite.size = layout.tileSize
        sprite.alpha = 0.35
        return sprite
    }

    /// Hollow tile-outline ring (rounded square or hexagon, per `layout.tileShape`),
    /// cached by shape + colour + pixel size. The cue is a SHAPE (a ring inset from
    /// the tile edge), not a fill tint — so it reads without relying on colour (the
    /// app's a11y stance), over the number glyph.
    private func overFlagRingTexture(color: SKColor) -> SKTexture {
        let shape = layout.tileShape
        let (wPx, hPx) = tilePixelSize()
        let key = "overflag-\(shape)-\(wPx)x\(hPx)-\(color)"
        if let cached = tileTextureCache[key] { return cached }

        let scale: CGFloat = 2
        let lineWidth = max(2, CGFloat(wPx) * scale * 0.06)
        let inset = lineWidth  // ring sits just inside the tile edge
        let img = drawTileImage(wPx: wPx, hPx: hPx, scale: scale) { ctx, w, h in
            addTilePath(to: ctx, shape: shape, w: w, h: h, inset: inset)
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(lineWidth)
            ctx.strokePath()
        }
        let texture = SKTexture(cgImage: img)
        texture.filteringMode = .linear
        tileTextureCache[key] = texture
        return texture
    }

    /// Cell-sized flag texture, cached by colour + pixel size. Mirrors `flagNode`'s
    /// swallowtail geometry (pole + finial + V-notched flag) so the cached sprite and
    /// the animated shape version look identical.
    private func flagTexture(color: SKColor) -> SKTexture {
        let px = max(4, Int(layout.cellSize.rounded()))
        let key = "flag-\(px)-\(color)"
        if let cached = tileTextureCache[key] { return cached }

        let scale: CGFloat = 2
        let dim = Int(CGFloat(px) * scale)
        let g = CGFloat(dim) * 0.66
        // Centred box, top-down 0…1 mapped into the dim×dim canvas (CG y-up: a
        // top-down y becomes `mid + (0.5 - y) * g`).
        let mid = CGFloat(dim) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: mid + (x - 0.5) * g, y: mid + (0.5 - y) * g)
        }
        let poleX: CGFloat = 0.30
        let img = drawCellImage(dim: dim) { ctx in
            ctx.setFillColor(color.cgColor)
            ctx.setStrokeColor(color.cgColor)
            // Finial.
            let r = 0.07 * g
            ctx.fillEllipse(
                in: CGRect(
                    x: p(poleX, 0.12).x - r, y: p(poleX, 0.12).y - r,
                    width: r * 2, height: r * 2))
            // Pole.
            ctx.setLineWidth(max(1, 0.07 * g))
            ctx.setLineCap(.round)
            ctx.move(to: p(poleX, 0.17))
            ctx.addLine(to: p(poleX, 0.86))
            ctx.strokePath()
            // Swallowtail flag with a V-notch in the fly edge.
            ctx.move(to: p(poleX, 0.20))
            ctx.addLine(to: p(0.80, 0.20))
            ctx.addLine(to: p(0.66, 0.35))
            ctx.addLine(to: p(0.80, 0.50))
            ctx.addLine(to: p(poleX, 0.50))
            ctx.closePath()
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
    func glyphTexture(_ text: String, color: SKColor) -> SKTexture {
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

    /// Render a `wPx×hPx`-point image (supersampled by `scale`) with `draw`, which
    /// receives the context and the scaled canvas width/height. For non-square tiles
    /// (hex) whose sprite is taller than wide.
    private func drawTileImage(
        wPx: Int, hPx: Int, scale: CGFloat, _ draw: (CGContext, CGFloat, CGFloat) -> Void
    ) -> CGImage {
        let w = Int(CGFloat(wPx) * scale)
        let h = Int(CGFloat(hPx) * scale)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        draw(ctx, CGFloat(w), CGFloat(h))
        return ctx.makeImage()!
    }
}
