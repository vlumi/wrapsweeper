import SpriteKit
import SwiftUI

/// The full set of board + chrome colors for one appearance. A `Palette` is
/// resolved for the current light/dark mode, then feeds both the SwiftUI chrome
/// (`Color`) and the SpriteKit scene (`SKColor`) so the two never drift.
public struct Palette {
    // Chrome
    let pageBackground: Color
    let statusBar: Color
    let counter: Color

    // Board (SpriteKit)
    let sceneBackground: SKColor
    let hiddenTile: SKColor
    let revealedTile: SKColor
    let mineTile: SKColor
    let flagGlyph: SKColor
    let mineGlyph: SKColor
    /// Adjacency-count colors, indexed 1...8.
    let numbers: [SKColor]

    /// Input-mode accent tints — used for the toggle's armed half and the board
    /// mode-glow, so the live tool reads at a glance. Teal for dig ("step
    /// safely"), orange for flag (warning). Defined once here (as `SKColor`) so
    /// the SwiftUI chrome and the SpriteKit scene share the exact values.
    let digTint: SKColor
    let flagTint: SKColor

    /// SwiftUI `Color` views of the mode tints, for the chrome.
    var digColor: Color { Color(digTint) }
    var flagColor: Color { Color(flagTint) }

    /// The accent tint for an input mode.
    func modeTint(for mode: InputMode) -> SKColor { mode == .flag ? flagTint : digTint }

    /// Faint ink for the board mode-glow screentone (dig dots / flag hatch) drawn
    /// over the unopened tiles. Neutral and translucent so the *pattern* is the
    /// cue (colour-blind safe); tuned per appearance to read on the tile colour.
    let screentoneInk: SKColor

    public static let dark = Palette(
        pageBackground: Color(white: 0.08),
        statusBar: Color(white: 0.14),
        counter: Color(red: 1, green: 0.45, blue: 0.3),
        sceneBackground: SKColor(white: 0.12, alpha: 1),
        hiddenTile: SKColor(white: 0.32, alpha: 1),
        revealedTile: SKColor(white: 0.2, alpha: 1),
        mineTile: SKColor(red: 0.6, green: 0.1, blue: 0.1, alpha: 1),
        flagGlyph: SKColor(red: 0.95, green: 0.4, blue: 0.3, alpha: 1),
        mineGlyph: .white,
        numbers: [
            SKColor(red: 0.40, green: 0.70, blue: 1.00, alpha: 1),  // 1
            SKColor(red: 0.45, green: 0.85, blue: 0.45, alpha: 1),  // 2
            SKColor(red: 1.00, green: 0.45, blue: 0.45, alpha: 1),  // 3
            SKColor(red: 0.65, green: 0.55, blue: 1.00, alpha: 1),  // 4
            SKColor(red: 0.85, green: 0.55, blue: 0.30, alpha: 1),  // 5
            SKColor(red: 0.40, green: 0.80, blue: 0.80, alpha: 1),  // 6
            SKColor(white: 0.85, alpha: 1),  // 7
            SKColor(white: 0.65, alpha: 1),  // 8
        ],
        digTint: SKColor(red: 0.10, green: 0.55, blue: 0.62, alpha: 1),
        flagTint: SKColor(red: 1.00, green: 0.50, blue: 0.00, alpha: 1),
        // Dark ink on the dark board (a recessed shadow, like the light board's
        // dark ink) rather than light-on-dark, which glows and reads far stronger
        // than the light-mode effect at the same opacity.
        screentoneInk: SKColor(white: 0, alpha: 0.30)
    )

    public static let light = Palette(
        pageBackground: Color(white: 0.96),
        statusBar: Color(white: 0.90),
        counter: Color(red: 0.80, green: 0.25, blue: 0.15),
        sceneBackground: SKColor(white: 0.88, alpha: 1),
        hiddenTile: SKColor(white: 0.70, alpha: 1),
        revealedTile: SKColor(white: 0.82, alpha: 1),
        mineTile: SKColor(red: 0.80, green: 0.20, blue: 0.20, alpha: 1),
        flagGlyph: SKColor(red: 0.80, green: 0.20, blue: 0.10, alpha: 1),
        mineGlyph: SKColor(white: 0.1, alpha: 1),
        numbers: [
            SKColor(red: 0.10, green: 0.35, blue: 0.85, alpha: 1),  // 1
            SKColor(red: 0.10, green: 0.50, blue: 0.15, alpha: 1),  // 2
            SKColor(red: 0.80, green: 0.15, blue: 0.15, alpha: 1),  // 3
            SKColor(red: 0.35, green: 0.20, blue: 0.70, alpha: 1),  // 4
            SKColor(red: 0.60, green: 0.30, blue: 0.05, alpha: 1),  // 5
            SKColor(red: 0.10, green: 0.50, blue: 0.55, alpha: 1),  // 6
            SKColor(white: 0.25, alpha: 1),  // 7
            SKColor(white: 0.45, alpha: 1),  // 8
        ],
        digTint: SKColor(red: 0.10, green: 0.55, blue: 0.62, alpha: 1),
        flagTint: SKColor(red: 1.00, green: 0.50, blue: 0.00, alpha: 1),
        // Alpha 0.32 here matches the dark board's per-tile brightness shift
        // (≈0.10): the light tile is brighter, so the same shift needs less alpha.
        screentoneInk: SKColor(white: 1, alpha: 0.32)  // light ink on the light board
    )

    public static func resolved(for scheme: ColorScheme) -> Palette {
        scheme == .dark ? .dark : .light
    }

    /// Color for an adjacency count (1...8), clamped to the available entries.
    func number(_ n: Int) -> SKColor {
        numbers[min(max(n, 1), numbers.count) - 1]
    }
}
