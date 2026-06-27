import DonpaCore
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
    /// User preference for the big-board minimap (pushed into the scene as a value
    /// so the update runs when it changes, like `palette`).
    var showMinimap: Bool = true

    var body: some View {
        BoardSKView(
            scene: scene, palette: palette, inputMode: inputMode,
            boardCursorActive: boardCursorActive, showMinimap: showMinimap)
    }
}

#if os(macOS)
private struct BoardSKView: NSViewRepresentable {
    let scene: BoardScene
    let palette: Palette
    let inputMode: InputMode
    let boardCursorActive: Bool
    let showMinimap: Bool

    func makeNSView(context: Context) -> ScrollForwardingSKView {
        let view = ScrollForwardingSKView()
        view.ignoresSiblingOrder = true
        scene.palette = palette
        scene.showMinimap = showMinimap
        view.inputMode = inputMode
        view.boardCursorActive = boardCursorActive
        view.presentScene(scene)
        return view
    }

    func updateNSView(_ view: ScrollForwardingSKView, context: Context) {
        if view.scene !== scene { view.presentScene(scene) }
        scene.palette = palette
        scene.showMinimap = showMinimap
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

    /// Whether the pointer is currently over the board, so a mode/state change
    /// only re-applies the cursor when it would actually be visible.
    private var pointerInside = false

    // Cursor handling uses a tracking area + an explicit `NSCursor.set()` rather
    // than `addCursorRect`: `SKView` manages its own drawing/loop and cursor
    // rects proved unreliable inside the SwiftUI-hosted scene (the custom cursor
    // never showed), whereas `mouseEntered`/`mouseMoved` + `set()` are immune to
    // responder-chain and cursor-rect timing.
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
        // travels, and a stale cursor from a sibling view can win without this.
        cursor(for: effectiveMode).set()
    }

    override func mouseExited(with event: NSEvent) {
        pointerInside = false
        NSCursor.arrow.set()
    }

    // Holding Control temporarily flips the action (Ctrl+click flags in reveal
    // mode, reveals in flag mode); reflect that in the cursor while it's held.
    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        refreshCursor()
    }

    /// The mode the next plain click would use: the armed `inputMode`, flipped
    /// while Control is held (the temporary "other action" modifier).
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
        // Native, system-feeling cursors: a pointing hand for "open this tile",
        // and the flag.fill SF Symbol for flag mode. SF Symbols rasterise crisply
        // (unlike the muddy ImageRenderer route) and read as platform-native.
        case .reveal: return .pointingHand
        case .flag: return Self.flagCursor
        }
    }

    /// A flag cursor built from the `flag.fill` SF Symbol, tinted orange to match
    /// the flag-mode toggle. SF Symbols feel native and stay crisp at cursor size.
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
    let showMinimap: Bool

    func makeUIView(context: Context) -> SKView {
        let view = SKView()
        view.ignoresSiblingOrder = true
        scene.palette = palette
        scene.showMinimap = showMinimap
        view.presentScene(scene)
        return view
    }

    func updateUIView(_ view: SKView, context: Context) {
        if view.scene !== scene { view.presentScene(scene) }
        scene.palette = palette
        scene.showMinimap = showMinimap
    }
}
#endif
