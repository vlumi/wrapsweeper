#!/usr/bin/env swift
//
// Build the framed manga panels (win / loss / pause) into the catalog assets.
//
// The sources are already KEYED — transparent where the page/margin was, opaque
// where the art is (border, interior, and any art spilling past the frame). The
// script's only job is to add a thin white "page" OUTLINE at every transparent↔
// opaque boundary, so the black-ink art (and the bits spilling outside the frame)
// still read against a dark background (dark mode). Then it crops to the opaque
// content bounds and emits @1x/@2x/@3x.
//
// No keying / flood / thresholds here: do the transparency in the source (an
// editor), and this just outlines + packages it.
//
//   swift Scripts/assets/make-panels.swift            # all three panels
//   swift Scripts/assets/make-panels.swift win loss   # a subset
//
// Sources: Scripts/assets/<panel>-source.png (pre-keyed, alpha baked in).
// Output: the matching imageset in Panels.xcassets.
//
// The TITLE screen is NOT here: it's a full-bleed poster on a white plate (no
// frame, no transparency), so it ships as its raw PNG with no processing.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let cs = CGColorSpace(name: CGColorSpace.sRGB)!

struct Panel {
    let name: String  // CLI name
    let source: String  // Scripts/assets/<source>
    let imageset: String  // PanelXxx.imageset
    let file: String  // panel-xxx (png basename)
}
let panels = [
    Panel(name: "win", source: "panel-win-source.png", imageset: "PanelWin", file: "panel-win"),
    Panel(
        name: "loss", source: "panel-loss-source.png", imageset: "PanelLoss", file: "panel-loss"),
    Panel(
        name: "pause", source: "pause-panel-source.png", imageset: "PanelPause",
        file: "panel-pause"),
]

// repo root (this script lives at Scripts/assets/, three levels down)
let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let requested = Array(CommandLine.arguments.dropFirst())
let selected = requested.isEmpty ? panels : panels.filter { requested.contains($0.name) }

func process(_ panel: Panel) {
    let srcPath = root.appendingPathComponent("Scripts/assets/\(panel.source)").path
    guard let isrc = CGImageSourceCreateWithURL(URL(fileURLWithPath: srcPath) as CFURL, nil),
        let img = CGImageSourceCreateImageAtIndex(isrc, 0, nil)
    else {
        print("SKIP \(panel.name): no source at \(srcPath)")
        return
    }
    let w = img.width, h = img.height, bpr = w * 4
    var px = [UInt8](repeating: 0, count: bpr * h)
    let c = CGContext(
        data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bpr,
        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))

    func opaque(_ x: Int, _ y: Int) -> Bool { px[y * bpr + x * 4 + 3] > 40 }

    // White "page" outline (~5px at output) at every transparent↔opaque edge: a
    // transparent pixel within `edge` of an opaque one becomes opaque white. A
    // round (distance) brush keeps corners smooth.
    let edge = max(3, Int((CGFloat(w) * 0.004).rounded()))
    var add = [Int]()  // pixel indices to paint white (collect first, apply after)
    for y in 0..<h {
        for x in 0..<w where !opaque(x, y) {
            var near = false
            var dy = -edge
            scan: while dy <= edge {
                var dx = -edge
                while dx <= edge {
                    let nx = x + dx, ny = y + dy
                    if nx >= 0, nx < w, ny >= 0, ny < h, opaque(nx, ny),
                        dx * dx + dy * dy <= edge * edge
                    {
                        near = true
                        break scan
                    }
                    dx += 1
                }
                dy += 1
            }
            if near { add.append(y * bpr + x * 4) }
        }
    }
    for i in add { px[i] = 255; px[i + 1] = 255; px[i + 2] = 255; px[i + 3] = 255 }

    // Crop to the opaque content bounds (art + outline).
    func anyOpaque(col x: Int) -> Bool { (0..<h).contains { px[$0 * bpr + x * 4 + 3] > 0 } }
    func anyOpaque(row y: Int) -> Bool { (0..<w).contains { px[y * bpr + $0 * 4 + 3] > 0 } }
    var minX = 0; while minX < w && !anyOpaque(col: minX) { minX += 1 }
    var maxX = w - 1; while maxX > minX && !anyOpaque(col: maxX) { maxX -= 1 }
    var minY = 0; while minY < h && !anyOpaque(row: minY) { minY += 1 }
    var maxY = h - 1; while maxY > minY && !anyOpaque(row: maxY) { maxY -= 1 }

    let outCtx = CGContext(
        data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bpr,
        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let cropped = outCtx.makeImage()!.cropping(
        to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))!

    let dir = root.appendingPathComponent(
        "Packages/DonpaCore/Sources/DonpaKit/Resources/Panels.xcassets/\(panel.imageset).imageset")
    let base: CGFloat = 418  // @1x point size
    for scale in 1...3 {
        let sw = Int((base * CGFloat(scale)).rounded())
        let sh = Int(CGFloat(cropped.height) / CGFloat(cropped.width) * CGFloat(sw))
        let ctx = CGContext(
            data: nil, width: sw, height: sh, bitsPerComponent: 8, bytesPerRow: 0,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.clear(CGRect(x: 0, y: 0, width: sw, height: sh))
        ctx.interpolationQuality = .high
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: sw, height: sh))
        let out = ctx.makeImage()!
        let suffix = scale == 1 ? "" : "@\(scale)x"
        let path = dir.appendingPathComponent("\(panel.file)\(suffix).png")
        let dest = CGImageDestinationCreateWithURL(
            path as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, out, nil)
        CGImageDestinationFinalize(dest)
        print("wrote \(panel.imageset)/\(panel.file)\(suffix).png (\(sw)x\(sh))")
    }
}

for panel in selected { process(panel) }
