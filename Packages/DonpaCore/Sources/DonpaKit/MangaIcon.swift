import SwiftUI

/// Procedural manga-style chrome glyphs, drawn as bold hand-inked strokes to
/// match the app icon / exploded-mine language (round caps + joins, heavy
/// weight). One `Canvas`-drawn shape per symbol, tinted by the caller, scalable
/// and crisp at any size — the toolbar counterpart to `make-icon.swift`.
///
/// Utility glyphs (close X, the %-chart, About's info/link) stay SF Symbols —
/// system affordances where a custom hand would be noise, not flavour.
struct MangaIcon: View {
    enum Symbol {
        case newGame  // plus in an ink ring
        case retry  // circular arrow
        case pause  // two bars
        case play  // filled triangle (resume)
        case home  // army tent
        case medal  // ribbon + star disc (High Scores)
        case reveal  // bootprint (reveal mode — tread carefully)
        case flag  // swallowtail flag on a pole (flag mode)
    }

    let symbol: Symbol
    var size: CGFloat = 30
    /// Stroke/fill colour; defaults to the current foreground style.
    var tint: Color = .primary

    var body: some View {
        if symbol == .reveal {
            // The army boot-print is too detailed to survive hand-drawn paths at
            // toolbar size, so it ships as a high-res template asset (rendered by
            // Scripts/make-boot.swift) that tints like the procedural glyphs.
            // The print is portrait (~1:2), so frame it taller-than-wide and let
            // it fill the height — boxing it square shrinks it to an unreadable
            // sliver where only the solid toe-cap survives.
            Image("BootPrint", bundle: .module)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(tint)
                .frame(width: size * 0.7, height: size * 1.3)
                // A slight left lean reads as mid-stride rather than a static stamp.
                .rotationEffect(.degrees(-12))
        } else {
            Canvas { ctx, area in
                // Draw at the intended `size`, centered in whatever area the Canvas
                // is handed — `Canvas` is greedy, so without this the glyph would
                // scale with the available space (e.g. shrink relative to a larger
                // strip in full-screen). The outer `.frame` then pins the layout box.
                let s = size
                ctx.translateBy(x: (area.width - s) / 2, y: (area.height - s) / 2)
                Self.draw(symbol, in: ctx, side: s, color: tint)
            }
            .frame(width: size, height: size)
        }
    }

    /// Per-symbol drawing params, bundled so each glyph helper stays small.
    private struct Pen {
        let ctx: GraphicsContext
        let s: CGFloat
        let shading: GraphicsContext.Shading
        let stroke: StrokeStyle
        let thin: StrokeStyle
        var c: CGPoint { CGPoint(x: s / 2, y: s / 2) }
        func stroke(_ p: Path, thin: Bool = false) {
            ctx.stroke(p, with: shading, style: thin ? self.thin : stroke)
        }
        func fill(_ p: Path) { ctx.fill(p, with: shading) }
    }

    /// Draw `symbol` centered in a `side`×`side` box. Static so it can be reused
    /// (e.g. by tests or other renderers) without a view instance.
    static func draw(_ symbol: Symbol, in ctx: GraphicsContext, side s: CGFloat, color: Color) {
        let lw = s * 0.10  // bold ink stroke
        let pen = Pen(
            ctx: ctx, s: s, shading: .color(color),
            stroke: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round),
            thin: StrokeStyle(lineWidth: lw * 0.7, lineCap: .round, lineJoin: .round))
        switch symbol {
        case .newGame: drawNewGame(pen)
        case .retry: drawRetry(pen)
        case .pause: drawPause(pen)
        case .play: drawPlay(pen)
        case .home: drawHome(pen)
        case .medal: drawMedal(pen)
        case .reveal: drawReveal(pen)
        case .flag: drawFlag(pen)
        }
    }

    private static func drawNewGame(_ pen: Pen) {
        let s = pen.s
        var ring = Path()
        ring.addEllipse(in: CGRect(x: s * 0.16, y: s * 0.16, width: s * 0.68, height: s * 0.68))
        pen.stroke(ring)
        var plus = Path()
        plus.move(to: CGPoint(x: s * 0.34, y: pen.c.y))
        plus.addLine(to: CGPoint(x: s * 0.66, y: pen.c.y))
        plus.move(to: CGPoint(x: pen.c.x, y: s * 0.34))
        plus.addLine(to: CGPoint(x: pen.c.x, y: s * 0.66))
        pen.stroke(plus)
    }

    private static func drawRetry(_ pen: Pen) {
        let s = pen.s
        var arc = Path()
        arc.addArc(
            center: pen.c, radius: s * 0.30, startAngle: .radians(.pi * 0.55),
            endAngle: .radians(.pi * 2.15), clockwise: false)
        pen.stroke(arc)
        let a = CGPoint(
            x: pen.c.x + cos(.pi * 0.55) * s * 0.30, y: pen.c.y + sin(.pi * 0.55) * s * 0.30)
        var head = Path()
        head.move(to: CGPoint(x: a.x - s * 0.10, y: a.y + s * 0.02))
        head.addLine(to: CGPoint(x: a.x + s * 0.10, y: a.y + s * 0.04))
        head.addLine(to: CGPoint(x: a.x + s * 0.02, y: a.y - s * 0.14))
        head.closeSubpath()
        pen.fill(head)
    }

    private static func drawPause(_ pen: Pen) {
        let s = pen.s
        for dx in [-s * 0.12, s * 0.12] {
            pen.fill(
                Path(
                    roundedRect: CGRect(
                        x: pen.c.x + dx - s * 0.05, y: s * 0.28, width: s * 0.10, height: s * 0.44),
                    cornerRadius: s * 0.04))
        }
    }

    private static func drawPlay(_ pen: Pen) {  // filled triangle (resume)
        let s = pen.s
        var tri = Path()
        tri.move(to: CGPoint(x: s * 0.34, y: s * 0.26))
        tri.addLine(to: CGPoint(x: s * 0.74, y: s * 0.50))
        tri.addLine(to: CGPoint(x: s * 0.34, y: s * 0.74))
        tri.closeSubpath()
        pen.fill(tri)
    }

    private static func drawHome(_ pen: Pen) {  // Quonset/Nissen barracks + flag
        let s = pen.s
        let baseY = s * 0.88
        let poleX = s * 0.10
        // Hut occupies the width to the right of the pole, so the building stays
        // large while the flagpole runs full height beside it.
        let leftX = s * 0.20, rightX = s * 0.94
        let r = (rightX - leftX) / 2
        let cx = (leftX + rightX) / 2
        // Nissen-hut profile: short straight walls rising from the baseline, then a
        // semicircular arch springing from the wall tops — taller than a plain
        // half-cylinder. Door knocked out (even-odd) so the silhouette reads as a
        // building, not a dome.
        let wallTopY = baseY - s * 0.16
        var hut = Path()
        hut.move(to: CGPoint(x: leftX, y: baseY))
        hut.addLine(to: CGPoint(x: leftX, y: wallTopY))
        hut.addArc(
            center: CGPoint(x: cx, y: wallTopY), radius: r,
            startAngle: .radians(.pi), endAngle: .radians(0), clockwise: false)
        hut.addLine(to: CGPoint(x: rightX, y: baseY))
        hut.closeSubpath()
        // Central door plus a small square window either side, all knocked out of
        // the filled silhouette (even-odd) so they read as openings.
        var openings = Path()
        openings.addRect(
            CGRect(x: cx - s * 0.10, y: s * 0.56, width: s * 0.20, height: baseY - s * 0.56))
        let winSide = s * 0.13, winY = s * 0.60
        openings.addRect(CGRect(x: cx - s * 0.30, y: winY, width: winSide, height: winSide))
        openings.addRect(CGRect(x: cx + s * 0.17, y: winY, width: winSide, height: winSide))
        var hutWithDoor = hut
        hutWithDoor.addPath(openings)
        pen.ctx.fill(hutWithDoor, with: pen.shading, style: FillStyle(eoFill: true))
        // Full-height flagpole on the left with a medium pennant up top — the
        // "military base entrance" tell, clear of the building.
        var pole = Path()
        pole.move(to: CGPoint(x: poleX, y: baseY))
        pole.addLine(to: CGPoint(x: poleX, y: s * 0.06))
        pen.stroke(pole, thin: true)
        var flag = Path()
        flag.move(to: CGPoint(x: poleX, y: s * 0.05))
        flag.addLine(to: CGPoint(x: poleX + s * 0.28, y: s * 0.15))
        flag.addLine(to: CGPoint(x: poleX, y: s * 0.25))
        flag.closeSubpath()
        pen.fill(flag)
    }

    private static func drawMedal(_ pen: Pen) {
        let s = pen.s
        // Bold ribbon tails (filled wedges) from the shoulders down to the disc —
        // thicker than strokes so they read at small sizes.
        var ribbon = Path()
        ribbon.move(to: CGPoint(x: s * 0.30, y: s * 0.14))
        ribbon.addLine(to: CGPoint(x: s * 0.45, y: s * 0.14))
        ribbon.addLine(to: CGPoint(x: s * 0.52, y: s * 0.46))
        ribbon.addLine(to: CGPoint(x: s * 0.40, y: s * 0.46))
        ribbon.closeSubpath()
        ribbon.move(to: CGPoint(x: s * 0.70, y: s * 0.14))
        ribbon.addLine(to: CGPoint(x: s * 0.55, y: s * 0.14))
        ribbon.addLine(to: CGPoint(x: s * 0.48, y: s * 0.46))
        ribbon.addLine(to: CGPoint(x: s * 0.60, y: s * 0.46))
        ribbon.closeSubpath()
        pen.fill(ribbon)
        // Big filled disc, with the star knocked out (negative space) so the
        // medal reads as a unit even tiny.
        let disc = CGRect(x: s * 0.24, y: s * 0.40, width: s * 0.52, height: s * 0.52)
        var coin = Path()
        coin.addEllipse(in: disc)
        coin.addPath(starPath(center: CGPoint(x: s * 0.50, y: s * 0.66), r: s * 0.19))
        pen.ctx.fill(coin, with: pen.shading, style: FillStyle(eoFill: true))
    }

    private static func drawReveal(_ pen: Pen) {  // army bootprint (reveal — tread)
        let s = pen.s
        let cx = s * 0.50
        // Army boot sole: a U-shaped (horseshoe) lugged toe band drawn as a thick
        // stroke open at the bottom, with cleat stars in the hollow, plus a
        // separate rounded heel block below. The open-U toe + heel reads as a
        // combat-boot print rather than a plain footprint.
        var toe = Path()
        toe.move(to: CGPoint(x: s * 0.30, y: s * 0.56))
        toe.addArc(
            center: CGPoint(x: cx, y: s * 0.40), radius: s * 0.20,
            startAngle: .radians(.pi * 0.85), endAngle: .radians(.pi * 0.15),
            clockwise: true)
        pen.ctx.stroke(
            toe, with: pen.shading,
            style: StrokeStyle(lineWidth: s * 0.15, lineCap: .round))
        // Two small cleat stars in the hollow of the U.
        pen.fill(starPath(center: CGPoint(x: cx, y: s * 0.34), r: s * 0.06))
        pen.fill(starPath(center: CGPoint(x: cx, y: s * 0.50), r: s * 0.055))
        // Heel block — a rounded bar set back below the toe band.
        var heel = Path()
        heel.addRoundedRect(
            in: CGRect(x: s * 0.36, y: s * 0.68, width: s * 0.28, height: s * 0.20),
            cornerSize: CGSize(width: s * 0.06, height: s * 0.06))
        pen.fill(heel)
    }

    private static func drawFlag(_ pen: Pen) {  // swallowtail flag on a ball-top pole
        let s = pen.s
        let poleX = s * 0.30
        let topY = s * 0.12
        // Ball finial on top of the pole, matching the title-art flag.
        var ball = Path()
        ball.addEllipse(
            in: CGRect(x: poleX - s * 0.07, y: topY - s * 0.07, width: s * 0.14, height: s * 0.14))
        pen.fill(ball)
        // Pole down from just under the ball.
        var pole = Path()
        pole.move(to: CGPoint(x: poleX, y: topY + s * 0.05))
        pole.addLine(to: CGPoint(x: poleX, y: s * 0.86))
        pen.stroke(pole)
        // Rectangular flag flying right from the top, with a swallowtail V-notch
        // cut into the fly (right) edge — the "square with a cut-out" look.
        let flagTop = s * 0.20, flagBot = s * 0.50, fly = s * 0.80, notch = s * 0.66
        var flag = Path()
        flag.move(to: CGPoint(x: poleX, y: flagTop))
        flag.addLine(to: CGPoint(x: fly, y: flagTop))
        flag.addLine(to: CGPoint(x: notch, y: (flagTop + flagBot) / 2))  // V-notch in
        flag.addLine(to: CGPoint(x: fly, y: flagBot))
        flag.addLine(to: CGPoint(x: poleX, y: flagBot))
        flag.closeSubpath()
        pen.fill(flag)
    }

    private static func starPath(center c: CGPoint, r: CGFloat) -> Path {
        var p = Path()
        for i in 0..<10 {
            let a = -CGFloat.pi / 2 + CGFloat(i) * .pi / 5
            let rr = i % 2 == 0 ? r : r * 0.45
            let pt = CGPoint(x: c.x + cos(a) * rr, y: c.y + sin(a) * rr)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}
