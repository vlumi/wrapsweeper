import DonpaCore
import SpriteKit

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// End-of-game board animations, on `effectsLayer` (never wiped by `rebuild()`).
/// Quick, non-blocking, and Reduce-Motion aware.
extension BoardScene {

    /// Flat burst-mine for the detonated cell (the app-icon motif).
    func burstMineNode(size: CGFloat) -> SKNode {
        let node = SKNode()
        let ink = palette.mineGlyph

        let path = CGMutablePath()
        let spikes = 11
        let rOut = size * 0.46, rIn = size * 0.30
        for i in 0..<(spikes * 2) {
            let a = 0.16 + CGFloat(i) * .pi / CGFloat(spikes)
            let r = i % 2 == 0 ? rOut : rIn
            let p = CGPoint(x: cos(a) * r, y: sin(a) * r)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        let burst = SKShapeNode(path: path)
        burst.fillColor = SKColor(red: 0.98, green: 0.82, blue: 0.25, alpha: 1)
        burst.strokeColor = ink
        burst.lineWidth = max(1, size * 0.02)
        burst.lineJoin = .round
        node.addChild(burst)

        let r = size * 0.15
        for i in 0..<8 {
            let a = CGFloat(i) * .pi / 4
            let line = CGMutablePath()
            line.move(to: CGPoint(x: cos(a) * r * 0.6, y: sin(a) * r * 0.6))
            line.addLine(to: CGPoint(x: cos(a) * r * 1.5, y: sin(a) * r * 1.5))
            let spoke = SKShapeNode(path: line)
            spoke.strokeColor = ink
            spoke.lineWidth = max(1, size * 0.05)
            spoke.lineCap = .round
            node.addChild(spoke)
        }
        let disc = SKShapeNode(circleOfRadius: r)
        disc.fillColor = ink
        disc.strokeColor = .clear
        node.addChild(disc)
        return node
    }

    // MARK: Mode glow

    /// A faint screentone over the unopened tiles signalling which tool a tap will
    /// use. The cue is the PATTERN, not colour (colour-blind safe): dig = Ben-Day
    /// dots, flag = diagonal hatch, both in one neutral ink. Rebuilt only on mode /
    /// revision / visibility / viewport change, not every frame.
    func refreshModeGlow() {
        // Persists after win/loss, frozen at the last mode. Hidden while paused
        // (the pause overlay blurs the board anyway).
        let visible = !viewModel.isPaused
        let mode = viewModel.inputMode
        let range = visibleRange()
        guard
            mode != lastGlowMode || visible != lastGlowLive
                || viewModel.revision != lastGlowRevision || range != lastGlowRange
        else { return }
        lastGlowMode = mode
        lastGlowLive = visible
        lastGlowRevision = viewModel.revision
        lastGlowRange = range
        glowLayer.removeAllChildren()
        guard visible else { return }

        let texture = screentoneTexture(for: mode)
        let size = layout.cellSize
        // The texture is clipped to the tile outline (hexagon or rounded square) and
        // drawn at the tile's aspect, so the sprite matches the tile beneath exactly —
        // the wash follows the hex edges instead of overhanging as a square block.
        let washSize = layout.tileSize
        // Each wash tile is an `SKSpriteNode` sharing the one cached screentone
        // texture — so SpriteKit batches them all into ~one draw call (a huge board
        // can have thousands of unopened tiles on screen). A per-cell `SKShapeNode`
        // here pegged the CPU: SpriteKit re-tessellates every shape's path every
        // frame, never batching, so thousands of them re-stroked at 60fps melted the
        // Mac (XXXL on a big resizable window). The faint pattern over the rounded
        // tile beneath reads fine as a square, so no per-tile rounded-rect needed.
        // Flagged tiles are unopened, so they get the screentone too; since the
        // glow layer sits above the board's flag glyph, re-stamp the flag on top.
        // Only the visible window (same cull as the tiles).
        range.forEach { c in
            // `c` is the screen position (drawn there); read state from the logical
            // cell it shows (identity when bounded, wrapped cell when not).
            let state = viewModel.game.board[displayCoord(c)].state
            guard state == .hidden || state == .flagged else { return }
            let center = layout.center(of: c)
            let tile = SKSpriteNode(texture: texture, size: washSize)
            tile.position = center
            tile.isUserInteractionEnabled = false
            glowLayer.addChild(tile)
            if state == .flagged {
                let flag = flagSprite(size: size, color: palette.flagGlyph)
                flag.position = center
                // Above the wash: the view sets `ignoresSiblingOrder`, so equal-z
                // siblings draw in undefined order — without an explicit higher z the
                // screentone sprite can land on top and stripe/dot the flag.
                flag.zPosition = 1
                glowLayer.addChild(flag)
            }
        }
    }

    /// Cached screentone texture for a mode: dots for dig, hatch for flag, in a faint
    /// neutral ink, **clipped to the tile outline** so on a hex board the wash follows
    /// the hexagon instead of overhanging as a square block. Cached per mode + tile
    /// pixel size + shape + ink. Drawn on a canvas matching the tile's aspect (a hex
    /// is taller than wide) so the pattern isn't squashed.
    func screentoneTexture(for mode: InputMode) -> SKTexture {
        let shape = layout.tileShape
        let (wPx, hPx) = tilePixelSize()
        let ink = palette.screentoneInk
        // Key by shape + ink so square/hex and light/dark don't share a stale texture.
        let key = "\(mode)-\(wPx)x\(hPx)-\(shape)-\(ink)"
        if let cached = glowTextureCache[key] { return cached }

        let scale = 2  // supersample for crisp dots/lines, then SKTexture downscales
        let w = wPx * scale
        let h = hPx * scale
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        // Clip everything (pattern + compensation) to the tile outline, so the wash
        // stops at the hexagon's slanted edges rather than filling the sprite square.
        ctx.saveGState()
        addTilePath(to: ctx, shape: shape, w: CGFloat(w), h: CGFloat(h), inset: 0)
        ctx.clip()
        ctx.setFillColor(ink.cgColor)
        ctx.setStrokeColor(ink.cgColor)
        drawScreentonePattern(ctx, mode: mode, width: CGFloat(w), height: CGFloat(h))
        // The ink pushes brightness one way (lighter on dark, darker on light); lay
        // an opposite-sign wash of equal average underneath so a screentoned tile
        // averages back to the bare tile colour.
        guard let inked = ctx.makeImage() else {
            ctx.restoreGState()
            return SKTexture()
        }
        let coverage = meanAlpha(of: inked, width: w, height: h)
        let comp = compensatingTexture(
            inkWhite: inkWhite(ink), coverage: coverage, width: w, height: h)
        let full = CGRect(x: 0, y: 0, width: w, height: h)
        // Compensation first, then the ink on top — both under the same tile clip.
        ctx.clear(full)
        if let comp { ctx.draw(comp, in: full) }
        ctx.draw(inked, in: full)
        ctx.restoreGState()

        let texture = SKTexture(cgImage: ctx.makeImage()!)
        texture.filteringMode = .linear
        glowTextureCache[key] = texture
        return texture
    }

    /// Draw the mode's screentone into `ctx` (already set to the ink colour): dig =
    /// staggered dots that shrink toward the centre, flag = diagonal hatch that
    /// thickens toward the centre — opposite vignettes so the modes read distinct.
    /// Pattern scale keys off the width; the vignette centres on the tile.
    private func drawScreentonePattern(
        _ ctx: CGContext, mode: InputMode, width: CGFloat, height: CGFloat
    ) {
        let f = width
        let midX = width / 2, midY = height / 2
        let maxDist = hypot(midX, midY)  // centre→corner
        switch mode {
        case .reveal:
            let gap = f * 0.20, baseR = f * 0.055
            var row = 0
            var y = gap / 2
            while y < height + gap {
                let offset = row.isMultiple(of: 2) ? 0 : gap / 2
                var x = gap / 2 - gap + offset
                while x < width + gap {
                    let dist = hypot(x - midX, y - midY) / maxDist
                    let r = baseR * (0.55 + 0.45 * dist)  // smaller centre, fuller edges
                    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                    x += gap
                }
                y += gap * 0.86
                row += 1
            }
        case .flag:
            let gap = f * 0.18
            var d = -height
            while d < width {
                let lineMid = d + height / 2
                let dist = abs(lineMid - midX) / midX
                ctx.setLineWidth(f * (0.075 - 0.045 * min(1, dist)))  // thicker centre
                ctx.move(to: CGPoint(x: d, y: 0))
                ctx.addLine(to: CGPoint(x: d + height, y: height))
                ctx.strokePath()
                d += gap
            }
        }
    }

    /// The ink's white value (0 = black ink, 1 = white ink).
    private func inkWhite(_ color: SKColor) -> CGFloat {
        var w: CGFloat = 0, a: CGFloat = 0
        #if os(macOS)
        (color.usingColorSpace(.genericGray) ?? color).getWhite(&w, alpha: &a)
        #else
        color.getWhite(&w, alpha: &a)
        #endif
        return w
    }

    /// Mean alpha (0…1) of a premultiplied-RGBA image — how much of the sprite the
    /// ink pattern covers on average (over the full `width×height` canvas, which for
    /// a hex includes the transparent corners outside the clipped tile).
    private func meanAlpha(of image: CGImage, width: Int, height: Int) -> CGFloat {
        let bpr = width * 4
        var buf = [UInt8](repeating: 0, count: bpr * height)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let c = CGContext(
            data: &buf, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bpr,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var total = 0
        for i in stride(from: 3, to: buf.count, by: 4) { total += Int(buf[i]) }
        return CGFloat(total) / CGFloat(width * height) / 255
    }

    /// A flat wash of the opposite luminance to the ink, at the alpha that cancels
    /// the ink's average brightness. nil when no compensation is needed. Drawn full-
    /// canvas; the caller clips it to the tile outline along with the ink.
    private func compensatingTexture(
        inkWhite: CGFloat, coverage: CGFloat, width: Int, height: Int
    ) -> CGImage? {
        guard coverage > 0.001 else { return nil }
        let opposite: CGFloat = inkWhite > 0.5 ? 0 : 1
        let alpha = min(1, coverage)  // equal-area, opposite colour → mean ≈ neutral
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let c = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(red: opposite, green: opposite, blue: opposite, alpha: alpha)
        c.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return c.makeImage()
    }

    static var prefersReducedMotion: Bool {
        #if os(iOS)
        return UIAccessibility.isReduceMotionEnabled
        #elseif os(macOS)
        return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #else
        return false
        #endif
    }

    // O(1) — the board stores its mine set, not a full-board scan.
    private var mineCoords: Set<Coord> {
        viewModel.game.board.mineCoords
    }

    func playLoss(trigger: Coord?, reduceMotion: Bool) {
        let cell = layout.cellSize
        let origin = trigger.map { layout.center(of: $0) }

        // Detonate the hit tile first so its explosion leads the shockwave.
        if let origin {
            effectsLayer.addChild(detonation(at: origin, size: cell))
        }
        if reduceMotion {
            if let origin { effectsLayer.addChild(flash(at: origin, size: cell)) }
            return
        }
        // Other mines pulse, staggered outward — only VISIBLE ones (culling keeps a
        // huge board off the main thread). A flagged ("disarmed") mine doesn't
        // detonate; it stays intact under its flag.
        let range = visibleRange()
        let board = viewModel.game.board
        let speed = cell * 18  // points/sec the shock wave travels
        for c in mineCoords where c != trigger && range.contains(c) && board[c].state != .flagged {
            let p = layout.center(of: c)
            let delay = origin.map { hypot(p.x - $0.x, p.y - $0.y) / speed } ?? 0
            let pulse = minePulse(at: p, size: cell)
            pulse.node.run(.sequence([.wait(forDuration: delay), pulse.pulseAction]))
            effectsLayer.addChild(pulse.node)
        }
        shakeBoard()
    }

    func playWin(reduceMotion: Bool) {
        let cell = layout.cellSize
        let board = layout.boardSize(width: viewModel.boardWidth, height: viewModel.boardHeight)
        let boardCentre = CGPoint(x: board.width / 2, y: board.height / 2)
        // The ripple radiates from where the player is LOOKING (camera/screen centre),
        // not the board's geometric middle — on a wrapped board the middle can be
        // off-screen, and even bounded this reads better when zoomed/panned.
        let centre = cameraNode.position

        if reduceMotion {
            let overlay = SKShapeNode(rectOf: CGSize(width: board.width, height: board.height))
            overlay.position = boardCentre
            overlay.fillColor = SKColor.green.withAlphaComponent(0.18)
            overlay.lineWidth = 0
            overlay.blendMode = .add
            overlay.alpha = 0
            overlay.run(
                .sequence([
                    .fadeAlpha(to: 0.5, duration: 0.12), .fadeOut(withDuration: 0.35),
                    .removeFromParent(),
                ]))
            effectsLayer.addChild(overlay)
            return
        }
        // Ripple wave: each revealed cell flashes, delayed by distance from centre.
        // Only VISIBLE revealed cells (same cull as the loss shockwave).
        let speed = cell * 22
        let gameBoard = viewModel.game.board
        let range = visibleRange()
        range.forEach { c in
            // `c` is the screen position; read the logical cell it shows (wrap-safe).
            guard gameBoard[displayCoord(c)].state == .revealed else { return }
            let p = layout.center(of: c)
            let delay = hypot(p.x - centre.x, p.y - centre.y) / speed
            effectsLayer.addChild(winRipple(at: p, size: cell, delay: delay))
        }
    }

    // MARK: Effect node builders

    /// A bright additive burst that scales up then collapses.
    private func detonation(at p: CGPoint, size: CGFloat) -> SKNode {
        let burst = SKShapeNode(circleOfRadius: size * 0.5)
        burst.position = p
        burst.fillColor = SKColor(red: 1, green: 0.5, blue: 0.2, alpha: 1)
        burst.lineWidth = 0
        // Above the tiles and starting at 1.4×, so a pre-fired burst reads as an
        // explosion on the first frame rather than a faint ring behind the tile.
        burst.zPosition = 10
        burst.setScale(1.4)
        burst.run(
            .sequence([
                .group([
                    .sequence([.scale(to: 1.9, duration: 0.12), .scale(to: 0.0, duration: 0.20)]),
                    .fadeOut(withDuration: 0.32),
                ]),
                .removeFromParent(),
            ]))
        return burst
    }

    private func flash(at p: CGPoint, size: CGFloat) -> SKNode {
        let rect = SKShapeNode(rectOf: CGSize(width: size, height: size), cornerRadius: 3)
        rect.position = p
        rect.fillColor = .white
        rect.lineWidth = 0
        rect.blendMode = .add
        rect.alpha = 0
        rect.run(
            .sequence([
                .fadeAlpha(to: 0.8, duration: 0.05), .fadeOut(withDuration: 0.18),
                .removeFromParent(),
            ]))
        return rect
    }

    private func minePulse(at p: CGPoint, size: CGFloat) -> (node: SKNode, pulseAction: SKAction) {
        let node = SKShapeNode(circleOfRadius: size * 0.4)
        node.position = p
        node.fillColor = SKColor(red: 0.9, green: 0.3, blue: 0.2, alpha: 1)
        node.lineWidth = 0
        node.blendMode = .add
        node.alpha = 0
        let pulse = SKAction.sequence([
            .group([
                .sequence([.scale(to: 1.4, duration: 0.10), .scale(to: 1.0, duration: 0.12)]),
                .sequence([.fadeAlpha(to: 0.85, duration: 0.06), .fadeOut(withDuration: 0.22)]),
            ]),
            .removeFromParent(),
        ])
        return (node, pulse)
    }

    private func winRipple(at p: CGPoint, size: CGFloat, delay: TimeInterval) -> SKNode {
        let tile = SKShapeNode(
            rectOf: CGSize(width: size * 0.9, height: size * 0.9), cornerRadius: 3)
        tile.position = p
        tile.fillColor = SKColor.green.withAlphaComponent(0.6)
        tile.lineWidth = 0
        tile.blendMode = .add
        tile.alpha = 0
        tile.run(
            .sequence([
                .wait(forDuration: delay),
                .group([
                    .sequence([.fadeAlpha(to: 0.7, duration: 0.10), .fadeOut(withDuration: 0.22)]),
                    .sequence([.scale(to: 1.15, duration: 0.10), .scale(to: 1.0, duration: 0.12)]),
                ]),
                .removeFromParent(),
            ]))
        return tile
    }

    /// Decaying jitter of the board, snapped back to origin so drift can't
    /// accumulate.
    private func shakeBoard() {
        let origin = boardLayer.position
        let amps: [CGFloat] = [7, -6, 5, -4, 3, -2]
        var steps: [SKAction] = amps.enumerated().map { i, a in
            .moveBy(x: a, y: i.isMultiple(of: 2) ? -a * 0.5 : a * 0.5, duration: 0.035)
        }
        steps.append(.move(to: origin, duration: 0.03))
        boardLayer.run(.sequence(steps))
    }
}
