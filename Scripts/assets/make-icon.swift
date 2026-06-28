#!/usr/bin/env swift
//
// App icon: a detonating mine in a halftone comic burst, at every catalog size.
// Pure CoreGraphics. `--mono` renders the grayscale treatment.
//   swift Scripts/assets/make-icon.swift <outDir> [--mono]
//
// `--launch` instead emits the launch-screen image — the mono burst-mine on a
// transparent background (it sits on the launch screen's charcoal bg colour) at
// @1x/@2x/@3x: launch.png, launch@2x.png, launch@3x.png.
//   swift Scripts/assets/make-icon.swift <outDir> --launch

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let outDir = args.count > 1 && !args[1].hasPrefix("--") ? args[1] : "."
let mono = args.contains("--mono")
let launch = args.contains("--launch")

let space = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

/// Colour ("cover") ships by default; `--mono` is the B&W "interior-page" look.
struct Palette {
    let bgTop, bgBottom, burst, ink, halftone, bgHalftone: CGColor

    static let color = Palette(
        bgTop: rgb(0.62, 0.10, 0.10), bgBottom: rgb(0.30, 0.04, 0.06),
        burst: rgb(0.98, 0.86, 0.30), ink: rgb(0.10, 0.06, 0.05),
        // Halftone dots = the same dark ink as the outline/mine, fully opaque, so
        // the icon stays a tight ~4-colour set (red bg, yellow burst, dark ink,
        // grey mine highlight) and the dots read as bold Ben-Day, not a faint wash.
        halftone: rgb(0.10, 0.06, 0.05, 1.0),
        bgHalftone: rgb(0.10, 0.06, 0.05, 1.0))

    static let mono = Palette(
        bgTop: rgb(0.32, 0.32, 0.33), bgBottom: rgb(0.12, 0.12, 0.13),
        burst: rgb(0.93, 0.92, 0.89), ink: rgb(0.08, 0.08, 0.09),
        halftone: rgb(0.08, 0.08, 0.09, 1.0),
        bgHalftone: rgb(0.08, 0.08, 0.09, 1.0))
}

/// A jagged comic impact starburst centred at c.
func burstPath(c: CGPoint, rOuter: CGFloat, rInner: CGFloat, spikes: Int, phase: CGFloat) -> CGPath
{
    let p = CGMutablePath()
    for i in 0..<(spikes * 2) {
        let a = phase + CGFloat(i) * .pi / CGFloat(spikes)
        let r = i % 2 == 0 ? rOuter : rInner
        let pt = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    p.closeSubpath()
    return p
}

/// Ben-Day halftone dots over `rect` (call inside a clip), with dot size GRADED
/// by distance from `center` — small near the centre (the bright burst core),
/// growing outward to `maxDot` near the edges. Varying the dot size is how real
/// halftone fakes a gradient/shading, so the burst reads as lit from the middle
/// rather than a flat dot grid. `gap` is the grid pitch.
func halftone(
    _ ctx: CGContext, in rect: CGRect, center: CGPoint, radius: CGFloat,
    minDot: CGFloat, maxDot: CGFloat, gap: CGFloat, color: CGColor
) {
    ctx.setFillColor(color)
    var y = rect.minY
    while y < rect.maxY {
        var x = rect.minX
        while x < rect.maxX {
            // Cell centre → normalized distance from the burst centre (0…1).
            let cx = x + gap / 2, cy = y + gap / 2
            let d = (hypot(cx - center.x, cy - center.y) / radius).clamped(to: 0...1)
            // Ease so the core stays clearly light and growth ramps toward edges.
            let dot = minDot + (maxDot - minDot) * (d * d)
            ctx.fillEllipse(in: CGRect(x: cx - dot / 2, y: cy - dot / 2, width: dot, height: dot))
            x += gap
        }
        y += gap
    }
}

extension Comparable {
    func clamped(to r: ClosedRange<Self>) -> Self { min(max(self, r.lowerBound), r.upperBound) }
}

/// A spiky mine disc with radial spikes and a small specular highlight, at c.
func drawMine(_ ctx: CGContext, c: CGPoint, r: CGFloat, fill: CGColor) {
    ctx.setFillColor(fill)
    ctx.setStrokeColor(fill)
    ctx.setLineWidth(r * 0.34)
    ctx.setLineCap(.round)
    for i in 0..<8 {
        let a = CGFloat(i) * .pi / 4
        ctx.move(to: CGPoint(x: c.x + cos(a) * r * 0.7, y: c.y + sin(a) * r * 0.7))
        ctx.addLine(to: CGPoint(x: c.x + cos(a) * r * 1.55, y: c.y + sin(a) * r * 1.55))
    }
    ctx.strokePath()
    ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    ctx.setFillColor(rgb(1, 1, 1, 0.5))
    ctx.fillEllipse(
        in: CGRect(x: c.x - r * 0.45, y: c.y + r * 0.1, width: r * 0.5, height: r * 0.5))
}

/// `transparentBackground` skips the gradient ground (for the launch image,
/// which composites on the launch screen's background colour).
func renderIcon(size: Int, palette pal: Palette, transparentBackground: Bool = false) -> CGImage {
    guard
        let ctx = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fatalError("could not create context") }

    let s = CGFloat(size)
    let c = CGPoint(x: s / 2, y: s / 2)

    if !transparentBackground {
        // Flat red field — the gradient is faked by the graded halftone dots
        // below, so a smooth colour gradient would be redundant and add colours.
        // Keeps the icon to a tight printed-comic palette.
        ctx.setFillColor(pal.bgTop)
        ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
        // Background halftone: dark dots over the red field, graded so they grow
        // toward the bottom — the printed-comic shading that fakes the gradient
        // and matches the burst's Ben-Day dots.
        // Centre at the TOP (CG y = s): dots are smallest near the top and grow
        // toward the bottom, deepening the field downward like the old gradient.
        halftone(
            ctx, in: CGRect(x: 0, y: 0, width: s, height: s),
            center: CGPoint(x: s / 2, y: s), radius: s,
            minDot: s * 0.004, maxDot: s * 0.034, gap: s * 0.05, color: pal.bgHalftone)
    }

    let burst = burstPath(c: c, rOuter: s * 0.46, rInner: s * 0.30, spikes: 14, phase: 0.16)
    ctx.addPath(burst)
    ctx.setFillColor(pal.burst)
    ctx.fillPath()
    ctx.addPath(burst)
    ctx.setStrokeColor(pal.ink)
    ctx.setLineWidth(s * 0.018)
    ctx.setLineJoin(.round)
    ctx.strokePath()

    ctx.saveGState()
    ctx.addPath(burst)
    ctx.clip()
    halftone(
        ctx, in: CGRect(x: 0, y: 0, width: s, height: s), center: c, radius: s * 0.46,
        minDot: s * 0.008, maxDot: s * 0.058, gap: s * 0.066, color: pal.halftone)
    ctx.restoreGState()

    drawMine(ctx, c: c, r: s * 0.16, fill: pal.ink)

    guard let image = ctx.makeImage() else { fatalError("could not render image") }
    return image
}

func writePNG(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard
        let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("could not create PNG destination") }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("could not write PNG") }
    print("Wrote \(path)")
}

if launch {
    // Launch image: mono burst-mine, transparent bg, @1x/@2x/@3x. 256pt base.
    for (scale, suffix) in [(1, ""), (2, "@2x"), (3, "@3x")] {
        let image = renderIcon(
            size: 256 * scale, palette: .mono, transparentBackground: true)
        writePNG(image, to: "\(outDir)/launch\(suffix).png")
    }
} else {
    // Every pixel size the catalog references, keyed by pixel dimension so the
    // names match Contents.json: the macOS set (16/32/64/128/256/512), the iOS
    // iPhone/iPad set (40/58/60/76/80/87/120/152/167/180), and the shared 1024
    // marketing icon.
    let palette = mono ? Palette.mono : Palette.color
    let sizes = [
        16, 20, 29, 32, 40, 58, 60, 64, 76, 80, 87, 120, 128, 152, 167, 180, 256, 512, 1024,
    ]
    for px in sizes {
        writePNG(renderIcon(size: px, palette: palette), to: "\(outDir)/icon-\(px).png")
    }
}
