#!/usr/bin/env swift
//
// Army boot-print glyph for the reveal/"dig — tread carefully" input mode.
//
// A detailed boot print won't survive being hand-drawn at toolbar/cursor size,
// so it ships as a *template* asset traced from a public-domain silhouette
// (Scripts/assets/boot-print.svg — a potrace vectorisation from svgsilh.com,
// CC0; toe block + separate heel block, portrait ~1:2). This script rasterises
// that SVG at its true aspect, turns it into a tintable black template (alpha
// from the rendered ink), and writes the three catalog scales into the BootPrint
// imageset, where it tints like the procedural chrome glyphs.
//
//   swift Scripts/assets/make-boot.swift
//
// Requires ImageMagick (`magick`) — `brew install imagemagick`. Quick Look's
// `qlmanage -t` was tried first but CROPS the tall print (drops the heel), so a
// true-aspect rasteriser is required.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
// repo root (this script lives at Scripts/assets/, three levels down)
let svg = root.appendingPathComponent("Scripts/assets/boot-print.svg")
let imageset = root.appendingPathComponent(
    "Packages/DonpaCore/Sources/DonpaKit/Resources/Panels.xcassets/BootPrint.imageset")
let space = CGColorSpace(name: CGColorSpace.sRGB)!

// 1) Rasterise the SVG at true aspect on a transparent background.
let tmp = FileManager.default.temporaryDirectory
    .appendingPathComponent("donpa-boot-\(getpid()).png")
func magick() -> URL {
    for bin in ["/opt/homebrew/bin/magick", "/usr/local/bin/magick", "/opt/homebrew/bin/convert"] {
        if FileManager.default.isExecutableFile(atPath: bin) { return URL(fileURLWithPath: bin) }
    }
    fatalError("ImageMagick not found — `brew install imagemagick`")
}
let p = Process()
p.executableURL = magick()
p.arguments = ["-background", "none", "-density", "200", svg.path, tmp.path]
try p.run()
p.waitUntilExit()
guard let isrc = CGImageSourceCreateWithURL(tmp as CFURL, nil),
    let img = CGImageSourceCreateImageAtIndex(isrc, 0, nil)
else { fatalError("magick did not produce a render at \(tmp.path)") }

// 2) Force the rendered ink to a clean black template, keeping its alpha.
let w = img.width, h = img.height, bpr = w * 4
var px = [UInt8](repeating: 0, count: bpr * h)
let cctx = CGContext(
    data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bpr,
    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
cctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
var out = [UInt8](repeating: 0, count: bpr * h)
for i in stride(from: 0, to: px.count, by: 4) {
    out[i + 3] = px[i + 3]  // RGB stay 0 (black), alpha from the render
}
let octx = CGContext(
    data: &out, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bpr,
    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let template = octx.makeImage()!

// 3) Write the three catalog scales, preserving the print's portrait aspect on a
//    60pt-tall box (so SwiftUI's scaledToFit letterboxes it cleanly, never crops).
let aspect = Double(w) / Double(h)
func write(scale: Int) {
    let boxH = 60 * scale
    let boxW = Int((Double(boxH) * aspect).rounded())
    let ctx = CGContext(
        data: nil, width: boxW, height: boxH, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.clear(CGRect(x: 0, y: 0, width: boxW, height: boxH))
    ctx.interpolationQuality = .high
    ctx.draw(template, in: CGRect(x: 0, y: 0, width: boxW, height: boxH))
    let out = ctx.makeImage()!
    let suffix = scale == 1 ? "" : "@\(scale)x"
    let path = imageset.appendingPathComponent("boot\(suffix).png")
    let dest = CGImageDestinationCreateWithURL(
        path as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, out, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(path.path) (\(boxW)x\(boxH))")
}
write(scale: 1)
write(scale: 2)
write(scale: 3)
try? FileManager.default.removeItem(at: tmp)
