#!/usr/bin/env swift
//
// App icon: a detonating mine in a halftone comic burst, at every catalog size.
// Pure CoreGraphics. `--mono` renders the grayscale treatment.
//   swift Scripts/make-icon.swift <outDir> [--mono]
//
// `--launch` instead emits the launch-screen image — the mono burst-mine on a
// transparent background (it sits on the launch screen's charcoal bg colour) at
// @1x/@2x/@3x: launch.png, launch@2x.png, launch@3x.png.
//   swift Scripts/make-icon.swift <outDir> --launch

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
    let bgTop, bgBottom, burst, ink, halftone: CGColor

    static let color = Palette(
        bgTop: rgb(0.62, 0.10, 0.10), bgBottom: rgb(0.30, 0.04, 0.06),
        burst: rgb(0.98, 0.86, 0.30), ink: rgb(0.10, 0.06, 0.05),
        halftone: rgb(0.85, 0.50, 0.08, 0.55))

    static let mono = Palette(
        bgTop: rgb(0.32, 0.32, 0.33), bgBottom: rgb(0.12, 0.12, 0.13),
        burst: rgb(0.93, 0.92, 0.89), ink: rgb(0.08, 0.08, 0.09),
        halftone: rgb(0.10, 0.10, 0.11, 0.40))
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

/// Even Ben-Day halftone dots over `rect` (call inside a clip).
func halftone(_ ctx: CGContext, in rect: CGRect, dot: CGFloat, gap: CGFloat, color: CGColor) {
    ctx.setFillColor(color)
    var y = rect.minY
    while y < rect.maxY {
        var x = rect.minX
        while x < rect.maxX {
            ctx.fillEllipse(in: CGRect(x: x, y: y, width: dot, height: dot))
            x += gap
        }
        y += gap
    }
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
        let bg = CGGradient(
            colorsSpace: space, colors: [pal.bgTop, pal.bgBottom] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(
            bg, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])
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
        ctx, in: CGRect(x: 0, y: 0, width: s, height: s), dot: s * 0.02, gap: s * 0.052,
        color: pal.halftone)
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
    // Every pixel size the catalog references: iOS 1024 plus the macOS
    // 16/32/128/256/512 set at @1x and @2x. Keys match the Contents.json names.
    let palette = mono ? Palette.mono : Palette.color
    for px in [16, 32, 64, 128, 256, 512, 1024] {
        writePNG(renderIcon(size: px, palette: palette), to: "\(outDir)/icon-\(px).png")
    }
}
