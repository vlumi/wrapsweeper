import DonpaCore
import SwiftUI

/// The opening title card: the manga "DONPA SQUAD / ドンパ隊" splash, shown on
/// launch. Tapping anywhere (or Space/Return on macOS) starts the game and
/// dismisses into the board. The art is a single drop-in PNG in the `Panels`
/// asset catalog, so swapping it is a catalog change.
///
/// The art is black ink on a white manga page; it's shown on a white plate in
/// *both* appearances rather than inverted (the screentone/gradient sky doesn't
/// invert cleanly), framed by the page background — so in dark mode it reads as
/// a bright manga page on a dark surround, matching the win/loss panels.
struct TitleScreen: View {
    let onStart: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        ZStack {
            // Surround: the page background tints with the appearance; the art
            // sits on its own white plate so it stays a crisp manga page.
            Palette.resolved(for: colorScheme).pageBackground
                .ignoresSafeArea()

            Image("TitleScreen", bundle: .module)
                .resizable()
                .interpolation(.high)  // smooth downscale: fine linework aliases
                .antialiased(true)  // badly when the window is small
                .scaledToFit()
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .shadow(color: .black.opacity(0.35), radius: 18, y: 6)
                .padding(12)
                // Gentle breathing so the baked-in "PRESS START" reads as live.
                // The repeating animation is bound to `pulse` *here* (not via an
                // imperative withAnimation) so it can't leak into the surrounding
                // background/opacity and make the whole screen pulse.
                .scaleEffect(pulse ? 1.012 : 1.0)
                .animation(
                    reduceMotion
                        ? nil
                        : .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                    value: pulse)
        }
        .contentShape(Rectangle())
        .onTapGesture { onStart() }
        // macOS: Space and Return also start (matches the in-game Space habit).
        .modifier(StartKeyShortcuts(onStart: onStart))
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Donpa Squad")
        .accessibilityHint("Tap to start")
        .onAppear {
            guard !reduceMotion else { return }
            pulse = true
        }
    }
}

/// Invisible buttons giving the title screen Space/Return keyboard shortcuts on
/// macOS without drawing anything. No-op on iOS (no hardware keyboard assumed).
private struct StartKeyShortcuts: ViewModifier {
    let onStart: () -> Void

    func body(content: Content) -> some View {
        #if os(macOS)
        content.background {
            ZStack {
                Button("", action: onStart).keyboardShortcut(.space, modifiers: [])
                Button("", action: onStart).keyboardShortcut(.defaultAction)
            }
            .opacity(0)
            .allowsHitTesting(false)
        }
        #else
        content
        #endif
    }
}
