import SpriteKit
import SwiftUI

/// Hosts a `BoardScene` and keeps its palette in sync. The palette is passed in
/// as a value, so SwiftUI's `update{NS,UI}View` runs whenever the resolved
/// scheme changes and pushes it to the scene — deterministic, unlike relying on
/// `.onChange` to fire (which proved unreliable for the SpriteKit scene,
/// notably when toggling the system appearance on iOS/iPadOS).
struct BoardView: View {
    let scene: BoardScene
    let palette: Palette
    let inputMode: InputMode
    /// When false (e.g. the result panel is up), the board shows the normal
    /// arrow cursor instead of the reveal/flag mode cursor.
    var boardCursorActive: Bool = true

    var body: some View {
        BoardSKView(
            scene: scene, palette: palette, inputMode: inputMode,
            boardCursorActive: boardCursorActive)
    }
}

#if os(macOS)
private struct BoardSKView: NSViewRepresentable {
    let scene: BoardScene
    let palette: Palette
    let inputMode: InputMode
    let boardCursorActive: Bool

    func makeNSView(context: Context) -> ScrollForwardingSKView {
        let view = ScrollForwardingSKView()
        view.ignoresSiblingOrder = true
        scene.palette = palette
        view.inputMode = inputMode
        view.boardCursorActive = boardCursorActive
        view.presentScene(scene)
        return view
    }

    func updateNSView(_ view: ScrollForwardingSKView, context: Context) {
        if view.scene !== scene { view.presentScene(scene) }
        scene.palette = palette
        view.inputMode = inputMode
        view.boardCursorActive = boardCursorActive
    }
}

/// An `SKView` that forwards scroll events to its scene — `SKView` otherwise
/// swallows `scrollWheel` instead of routing it to `BoardScene` — and shows a
/// mode-aware cursor over the board (crosshair to reveal, a flag to flag).
final class ScrollForwardingSKView: SKView {
    var inputMode: InputMode = .reveal {
        didSet {
            guard inputMode != oldValue else { return }
            window?.invalidateCursorRects(for: self)
        }
    }
    /// When false (result panel up), show the normal arrow over the board.
    var boardCursorActive: Bool = true {
        didSet {
            guard boardCursorActive != oldValue else { return }
            window?.invalidateCursorRects(for: self)
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: cursor(for: inputMode))
    }

    private func cursor(for mode: InputMode) -> NSCursor {
        guard boardCursorActive else { return .arrow }
        switch mode {
        case .reveal: return Self.crosshairCursor
        case .flag: return Self.flagCursor
        }
    }

    /// A bold crosshair that reads on both light and dark tiles. The system
    /// `.crosshair` is a thin black line that all but vanishes on the light-mode
    /// manga board; here a thick black cross (contrasts on light) sits inside a
    /// wider white halo (contrasts on dark), so a strong edge shows either way.
    private static let crosshairCursor: NSCursor = {
        let dim: CGFloat = 32
        let size = NSSize(width: dim, height: dim)
        let c = dim / 2
        let arm: CGFloat = 12  // half-length of each crosshair arm
        let gap: CGFloat = 3  // centre gap so the exact point stays clickable

        let image = NSImage(size: size, flipped: false) { _ in
            func strokeCross(width: CGFloat, color: NSColor) {
                color.set()
                let path = NSBezierPath()
                path.lineWidth = width
                path.lineCapStyle = .square
                path.move(to: NSPoint(x: c - arm, y: c))
                path.line(to: NSPoint(x: c - gap, y: c))
                path.move(to: NSPoint(x: c + gap, y: c))
                path.line(to: NSPoint(x: c + arm, y: c))
                path.move(to: NSPoint(x: c, y: c - arm))
                path.line(to: NSPoint(x: c, y: c - gap))
                path.move(to: NSPoint(x: c, y: c + gap))
                path.line(to: NSPoint(x: c, y: c + arm))
                path.stroke()
            }
            strokeCross(width: 6, color: NSColor.white.withAlphaComponent(0.95))  // halo
            strokeCross(width: 3, color: .black)  // bold core
            // A center dot marks the exact hot spot.
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: c - 1.5, y: c - 1.5, width: 3, height: 3)).fill()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: c, y: c))
    }()

    /// A flag-shaped cursor drawn from the `flag.fill` SF Symbol, so it matches
    /// the toolbar's flag-mode icon.
    private static let flagCursor: NSCursor = {
        let size = NSSize(width: 24, height: 24)
        let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        let symbol =
            NSImage(systemSymbolName: "flag.fill", accessibilityDescription: "Flag")?
            .withSymbolConfiguration(config)
        guard let symbol else { return .arrow }
        // Tint the flag orange to match the flag-mode toolbar tint.
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.systemOrange.set()
            rect.fill(using: .sourceOver)
            symbol.draw(
                in: rect, from: .zero, operation: .destinationIn, fraction: 1)
            return true
        }
        // Hot spot at the flagpole base (bottom-left-ish).
        return NSCursor(image: image, hotSpot: NSPoint(x: 4, y: size.height - 4))
    }()

    override func scrollWheel(with event: NSEvent) {
        if let board = scene as? BoardScene {
            board.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }
}
#else
private struct BoardSKView: UIViewRepresentable {
    let scene: BoardScene
    let palette: Palette
    let inputMode: InputMode  // unused on iOS (no pointer cursor)
    let boardCursorActive: Bool  // unused on iOS (no pointer cursor)

    func makeUIView(context: Context) -> SKView {
        let view = SKView()
        view.ignoresSiblingOrder = true
        scene.palette = palette
        view.presentScene(scene)
        return view
    }

    func updateUIView(_ view: SKView, context: Context) {
        if view.scene !== scene { view.presentScene(scene) }
        scene.palette = palette
    }
}
#endif
