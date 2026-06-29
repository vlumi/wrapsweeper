import DonpaCore
import SpriteKit
import SwiftUI

/// Hosts a `BoardScene` and keeps its palette in sync. The palette is passed as a
/// value so `update{NS,UI}View` pushes it to the scene on every resolved-scheme
/// change — deterministic, unlike `.onChange` (unreliable for the SpriteKit scene).
struct BoardView: View {
    let scene: BoardScene
    let palette: Palette
    let inputMode: InputMode
    /// When false (e.g. result panel up), show the normal arrow, not the mode cursor.
    var boardCursorActive: Bool = true
    var showMinimap: Bool = true
    var minimapScale: Double = 1

    var body: some View {
        BoardSKView(
            scene: scene, palette: palette, inputMode: inputMode,
            boardCursorActive: boardCursorActive, showMinimap: showMinimap,
            minimapScale: minimapScale)
    }
}

#if os(macOS)
private struct BoardSKView: NSViewRepresentable {
    let scene: BoardScene
    let palette: Palette
    let inputMode: InputMode
    let boardCursorActive: Bool
    let showMinimap: Bool
    let minimapScale: Double

    func makeNSView(context: Context) -> ScrollForwardingSKView {
        let view = ScrollForwardingSKView()
        view.ignoresSiblingOrder = true
        scene.palette = palette
        scene.showMinimap = showMinimap
        scene.minimapScale = CGFloat(minimapScale)
        view.inputMode = inputMode
        view.boardCursorActive = boardCursorActive
        view.presentScene(scene)
        return view
    }

    func updateNSView(_ view: ScrollForwardingSKView, context: Context) {
        if view.scene !== scene { view.presentScene(scene) }
        scene.palette = palette
        scene.showMinimap = showMinimap
        scene.minimapScale = CGFloat(minimapScale)
        view.inputMode = inputMode
        view.boardCursorActive = boardCursorActive
    }
}

/// An `SKView` that forwards `scrollWheel` to its scene (it otherwise swallows it)
/// and shows a mode-aware cursor over the board.
final class ScrollForwardingSKView: SKView {
    var inputMode: InputMode = .reveal {
        didSet {
            guard inputMode != oldValue else { return }
            refreshCursor()
        }
    }
    /// When false (result panel up), show the normal arrow over the board.
    var boardCursorActive: Bool = true {
        didSet {
            guard boardCursorActive != oldValue else { return }
            refreshCursor()
        }
    }

    private var pointerInside = false

    // Tracking area + explicit `NSCursor.set()` rather than `addCursorRect`: cursor
    // rects proved unreliable in the SwiftUI-hosted scene (the custom cursor never
    // showed); `mouseEntered`/`mouseMoved` + `set()` are immune to that timing.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.activeInKeyWindow, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
                owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        pointerInside = true
        cursor(for: effectiveMode).set()
    }

    override func mouseMoved(with event: NSEvent) {
        // Re-assert each move: AppKit otherwise resets to the arrow as the pointer
        // travels, and a sibling view's stale cursor can win.
        cursor(for: effectiveMode).set()
    }

    override func mouseExited(with event: NSEvent) {
        pointerInside = false
        NSCursor.arrow.set()
    }

    // Holding Control temporarily flips the action; reflect it in the cursor.
    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        refreshCursor()
    }

    /// The mode the next plain click would use: `inputMode`, flipped while Control
    /// is held (the temporary "other action" modifier).
    private var effectiveMode: InputMode {
        NSEvent.modifierFlags.contains(.control) ? inputMode.flipped : inputMode
    }

    /// Re-apply the cursor for the current mode/state if the pointer is over us.
    private func refreshCursor() {
        guard pointerInside else { return }
        cursor(for: effectiveMode).set()
    }

    private func cursor(for mode: InputMode) -> NSCursor {
        guard boardCursorActive else { return .arrow }
        switch mode {
        case .reveal: return .pointingHand
        case .flag: return Self.flagCursor
        }
    }

    /// A flag cursor from the `flag.fill` SF Symbol, tinted orange to match the
    /// flag-mode toggle. SF Symbols stay crisp at cursor size.
    private static let flagCursor: NSCursor = {
        let size = NSSize(width: 24, height: 24)
        let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        let symbol =
            NSImage(systemSymbolName: "flag.fill", accessibilityDescription: "Flag")?
            .withSymbolConfiguration(config)
        guard let symbol else { return .arrow }
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.systemOrange.set()
            rect.fill(using: .sourceOver)
            symbol.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)
            return true
        }
        // Hot spot at the flagpole base.
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
    let boardCursorActive: Bool  // unused on iOS
    let showMinimap: Bool
    let minimapScale: Double

    func makeUIView(context: Context) -> SKView {
        let view = SKView()
        view.ignoresSiblingOrder = true
        scene.palette = palette
        scene.showMinimap = showMinimap
        scene.minimapScale = CGFloat(minimapScale)
        view.presentScene(scene)
        return view
    }

    func updateUIView(_ view: SKView, context: Context) {
        if view.scene !== scene { view.presentScene(scene) }
        scene.palette = palette
        scene.showMinimap = showMinimap
        scene.minimapScale = CGFloat(minimapScale)
    }
}
#endif
