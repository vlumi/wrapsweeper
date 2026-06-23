import DonpaCore
import SpriteKit

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// End-of-game board animations, on `effectsLayer` (never wiped by `rebuild()`).
/// Tasteful and quick (<~1s), non-blocking — the board stays interactive for a
/// restart — and respects Reduce Motion.
extension BoardScene {

    /// Flat burst-mine for the detonated cell (the app-icon motif, no halftone or
    /// gradient — those would be noise at cell size).
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

    /// The flag placed on a flagged cell — the swallowtail flag from the toolbar
    /// toggle (`MangaIcon.flag`), drawn with SpriteKit paths so it matches the
    /// chrome and stays crisp at any zoom. Centred on the cell origin (y-up).
    func flagNode(size: CGFloat, color: SKColor) -> SKNode {
        let node = SKNode()
        // Work in a centred box of side `g`, mapping MangaIcon's 0…1 design space
        // (top-down) to SpriteKit (y-up): x → x-0.5, y → 0.5-y, scaled by g.
        let g = size * 0.66
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: (x - 0.5) * g, y: (0.5 - y) * g)
        }
        let poleX: CGFloat = 0.30
        // Ball finial.
        let ball = SKShapeNode(circleOfRadius: 0.07 * g)
        ball.position = p(poleX, 0.12)
        ball.fillColor = color
        ball.strokeColor = .clear
        node.addChild(ball)
        // Pole.
        let pole = CGMutablePath()
        pole.move(to: p(poleX, 0.17))
        pole.addLine(to: p(poleX, 0.86))
        let poleNode = SKShapeNode(path: pole)
        poleNode.strokeColor = color
        poleNode.lineWidth = max(1, 0.07 * g)
        poleNode.lineCap = .round
        node.addChild(poleNode)
        // Swallowtail flag with a V-notch cut into the fly edge.
        let flag = CGMutablePath()
        flag.move(to: p(poleX, 0.20))
        flag.addLine(to: p(0.80, 0.20))
        flag.addLine(to: p(0.66, 0.35))  // notch in
        flag.addLine(to: p(0.80, 0.50))
        flag.addLine(to: p(poleX, 0.50))
        flag.closeSubpath()
        let flagNode = SKShapeNode(path: flag)
        flagNode.fillColor = color
        flagNode.strokeColor = .clear
        node.addChild(flagNode)
        return node
    }

    // MARK: Mode glow

    /// A faint manga *screentone* over the *unopened* tiles, signalling which tool
    /// a tap will use — without touching the revealed numbers. The cue is the
    /// PATTERN, not colour: dig = Ben-Day dots, flag = diagonal hatch, both in a
    /// single neutral ink. Distinguishable by texture alone (fully colour-blind
    /// safe) and a nod to the manga theme. Rebuilt only when the mode, the board
    /// revision, or live/visibility changes (not every frame).
    func refreshModeGlow() {
        // Shown whenever the board is visible (not paused — the pause overlay
        // blurs the board anyway). It persists after win/loss, frozen at the last
        // mode, so a finished board keeps its texture instead of going flat.
        let visible = !viewModel.isPaused
        let mode = viewModel.inputMode
        // The board revision changes as cells open, so the wash tracks which
        // tiles are still hidden.
        guard
            mode != lastGlowMode || visible != lastGlowLive
                || viewModel.revision != lastGlowRevision
        else { return }
        lastGlowMode = mode
        lastGlowLive = visible
        lastGlowRevision = viewModel.revision
        glowLayer.removeAllChildren()
        guard visible else { return }

        let texture = screentoneTexture(for: mode)
        let size = layout.cellSize
        let inset: CGFloat = 1
        let side = size - inset * 2
        for c in viewModel.game.board.allCoords
        where viewModel.game.board[c].state == .hidden || viewModel.game.board[c].state == .flagged
        {
            let tile = SKShapeNode(
                rect: CGRect(x: -side / 2, y: -side / 2, width: side, height: side),
                cornerRadius: 3)
            tile.position = layout.center(of: c)
            tile.fillColor = .white  // the texture carries the ink; no extra tint
            tile.fillTexture = texture
            tile.strokeColor = .clear
            tile.isUserInteractionEnabled = false
            glowLayer.addChild(tile)
        }
    }

    /// A cached, cell-sized screentone texture for a mode: Ben-Day dots for dig,
    /// diagonal hatch for flag, in a single faint neutral ink (the cue is the
    /// pattern, not colour). Cached per mode + cell size so it's built once.
    func screentoneTexture(for mode: InputMode) -> SKTexture {
        let px = max(8, Int(layout.cellSize.rounded()))
        let ink = palette.screentoneInk
        // Key by ink too: the colour differs by appearance, so light/dark must not
        // share a cached texture (otherwise switching theme reuses the stale one).
        let key = "\(mode)-\(px)-\(ink)"
        if let cached = glowTextureCache[key] { return cached }

        let dim = px * 2  // supersample for crisp dots/lines, then SKTexture downscales
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: nil, width: dim, height: dim, bitsPerComponent: 8, bytesPerRow: 0,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.clear(CGRect(x: 0, y: 0, width: dim, height: dim))
        ctx.setFillColor(ink.cgColor)
        ctx.setStrokeColor(ink.cgColor)
        drawScreentonePattern(ctx, mode: mode, dim: dim)
        // Balance the average brightness: the ink only pushes one way (lighter on
        // the dark board, darker on the light board), which would shift the mean
        // tile brightness away from the bare tile. Measure the mean ink coverage
        // and lay a faint OPPOSITE-sign wash underneath at the same average, so a
        // screentoned tile averages back to the original tile colour.
        guard let inked = ctx.makeImage() else { return SKTexture() }
        let coverage = meanAlpha(of: inked, dim: dim)  // 0…1 average opacity of the ink
        let comp = compensatingTexture(inkWhite: inkWhite(ink), coverage: coverage, dim: dim)
        // Draw compensation first, then the ink on top.
        ctx.clear(CGRect(x: 0, y: 0, width: dim, height: dim))
        if let comp { ctx.draw(comp, in: CGRect(x: 0, y: 0, width: dim, height: dim)) }
        ctx.draw(inked, in: CGRect(x: 0, y: 0, width: dim, height: dim))

        let texture = SKTexture(cgImage: ctx.makeImage()!)
        texture.filteringMode = .linear
        glowTextureCache[key] = texture
        return texture
    }

    /// Stroke/fill the mode's screentone pattern into `ctx` (already set up with
    /// the ink colour): fine staggered Ben-Day dots that shrink toward the tile
    /// centre for dig, narrow diagonal hatch that thickens toward the centre for
    /// flag — opposite vignettes so the two modes read as plainly different.
    private func drawScreentonePattern(_ ctx: CGContext, mode: InputMode, dim: Int) {
        let f = CGFloat(dim)
        let mid = f / 2, maxDist = f / 2 * 1.414  // centre→corner
        switch mode {
        case .reveal:
            let gap = f * 0.20, baseR = f * 0.055
            var row = 0
            var y = gap / 2
            while y < f + gap {
                let offset = row.isMultiple(of: 2) ? 0 : gap / 2
                var x = gap / 2 - gap + offset
                while x < f + gap {
                    let dist = hypot(x - mid, y - mid) / maxDist  // 0 centre → 1 corner
                    let r = baseR * (0.55 + 0.45 * dist)  // smaller centre, fuller edges
                    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                    x += gap
                }
                y += gap * 0.86
                row += 1
            }
        case .flag:
            let gap = f * 0.18
            var d = -f
            while d < f {
                let lineMid = d + f / 2
                let dist = abs(lineMid - mid) / mid  // 0 centre → 1 edge
                ctx.setLineWidth(f * (0.075 - 0.045 * min(1, dist)))  // thicker centre
                ctx.move(to: CGPoint(x: d, y: 0))
                ctx.addLine(to: CGPoint(x: d + f, y: f))
                ctx.strokePath()
                d += gap
            }
        }
    }

    /// The ink's white value (0 = black ink on the light board, 1 = white ink on
    /// the dark board).
    private func inkWhite(_ color: SKColor) -> CGFloat {
        var w: CGFloat = 0, a: CGFloat = 0
        #if os(macOS)
        (color.usingColorSpace(.genericGray) ?? color).getWhite(&w, alpha: &a)
        #else
        color.getWhite(&w, alpha: &a)
        #endif
        return w
    }

    /// Mean alpha (0…1) of a premultiplied-RGBA image — how much of the tile the
    /// ink pattern covers on average.
    private func meanAlpha(of image: CGImage, dim: Int) -> CGFloat {
        let bpr = dim * 4
        var buf = [UInt8](repeating: 0, count: bpr * dim)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let c = CGContext(
            data: &buf, width: dim, height: dim, bitsPerComponent: 8, bytesPerRow: bpr,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.draw(image, in: CGRect(x: 0, y: 0, width: dim, height: dim))
        var total = 0
        for i in stride(from: 3, to: buf.count, by: 4) { total += Int(buf[i]) }
        return CGFloat(total) / CGFloat(dim * dim) / 255
    }

    /// A flat wash of the OPPOSITE luminance to the ink, at the alpha needed so its
    /// brightness contribution cancels the ink's average — keeping the mean tile
    /// brightness neutral. Returns nil if no compensation is needed.
    private func compensatingTexture(inkWhite: CGFloat, coverage: CGFloat, dim: Int) -> CGImage? {
        guard coverage > 0.001 else { return nil }
        // Ink shifts brightness by (inkWhite - 0.5) over `coverage` of the area;
        // a full-area opposite wash at this alpha restores the mean.
        let opposite: CGFloat = inkWhite > 0.5 ? 0 : 1
        let alpha = min(1, coverage)  // equal-area, opposite colour → mean ≈ neutral
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let c = CGContext(
            data: nil, width: dim, height: dim, bitsPerComponent: 8, bytesPerRow: 0,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(red: opposite, green: opposite, blue: opposite, alpha: alpha)
        c.fill(CGRect(x: 0, y: 0, width: dim, height: dim))
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

    private var mineCoords: [Coord] {
        viewModel.game.board.allCoords.filter { viewModel.game.board[$0].isMine }
    }

    func playLoss(trigger: Coord?, reduceMotion: Bool) {
        let cell = layout.cellSize
        let origin = trigger.map { layout.center(of: $0) }

        if let origin {
            effectsLayer.addChild(detonation(at: origin, size: cell))
        }
        if reduceMotion {
            if let origin { effectsLayer.addChild(flash(at: origin, size: cell)) }
            return
        }
        // Other mines pulse, staggered outward from the trigger.
        let speed = cell * 18  // points/sec the shock wave travels
        for c in mineCoords where c != trigger {
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
        let centre = CGPoint(x: board.width / 2, y: board.height / 2)

        if reduceMotion {
            let overlay = SKShapeNode(rectOf: CGSize(width: board.width, height: board.height))
            overlay.position = centre
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
        let speed = cell * 22
        for c in viewModel.game.board.allCoords
        where viewModel.game.board[c].state == .revealed {
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
        burst.blendMode = .add
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
