import DonpaCore
import SwiftUI

/// The end-of-game result screen: a dramatic comic frame that slams in over the
/// board on win/loss and *stays* until dismissed. It dims the **board only** —
/// the control strip stays live — so the panel carries no buttons of its own
/// (New Game / Retry / Home live on the strip). A tap anywhere, the corner X, or
/// Esc dismisses it to inspect the finished board.
///
/// The art is a single drop-in PNG (border included, transparent outside the
/// panel shape) in the `Panels` asset catalog. The framing/FX here are
/// procedural: a coloured glow accent (win=green / loss=red), the slam-in, and
/// the record badge. Swapping the art is a catalog change, no code edit.
struct MangaPanelView: View {
    enum Kind: Equatable {
        case win
        /// A win that set a new best time, in centiseconds — gets a record badge.
        case record(centiseconds: Int)
        /// A loss, carrying the fraction (0...1) of safe cells cleared, the count
        /// of safe cells still unopened, and whether it beat the previous best — a
        /// "new best %" pill shows only when `isBest`. `safeRemaining` lets the
        /// display show "N tiles left" instead of a misleading "100%" when the
        /// player lost on the very last cells (0.99x rounds up to 100).
        case loss(progress: Double, safeRemaining: Int, isBest: Bool)

        var isWin: Bool {
            if case .loss = self { return false }
            return true
        }
        var imageName: String { isWin ? "PanelWin" : "PanelLoss" }
        var accent: Color { isWin ? .green : .red }
        /// Spoken description for VoiceOver (the art conveys nothing to it).
        var a11yLabel: String {
            switch self {
            case .win:
                return String(localized: "Minefield cleared", bundle: .module)
            case .record(let cs):
                return String(
                    localized:
                        "New record! Minefield cleared in \(TimeFormat.mmsst(centiseconds: cs))",
                    bundle: .module)
            case .loss(let progress, let safeRemaining, _):
                let cleared = Self.clearedDisplay(progress, safeRemaining: safeRemaining)
                return String(
                    localized: "Boom — you stepped on a mine. \(cleared).", bundle: .module)
            }
        }
        /// The new-best time, if this is a record win.
        var recordCentiseconds: Int? {
            if case .record(let cs) = self { return cs }
            return nil
        }
        /// The headline string for a *best* loss pill — "N left" when the player
        /// lost on the last cells (would otherwise read a misleading "100%"),
        /// otherwise the cleared percent. `nil` unless this is a new-best loss.
        var bestLossHeadline: String? {
            if case .loss(let p, let rem, let isBest) = self, isBest {
                return Self.lossHeadline(p, safeRemaining: rem)
            }
            return nil
        }

        /// Whole-percent string, e.g. `87%`. FLOORED, not rounded — matching the
        /// scoreboard's "Best %" and the live readout: you haven't reached 88%
        /// until you've actually cleared 88%, so 87.6% reads "87%". (Rounding here
        /// made the loss screen claim a higher % than reached / than the scoreboard
        /// later shows.)
        static func percent(_ fraction: Double) -> String {
            "\(Int((fraction * 100).rounded(.down)))%"
        }

        /// Short loss headline: the cleared percent, EXCEPT when it would round to
        /// 100% on a non-clear — then the count of safe tiles still unopened, so a
        /// last-cell loss reads "2 left" rather than a misleading "100%". This guard
        /// rounds (not floors) so a 99.6% near-clear still reads "N left" — the
        /// "so close" cue — rather than a flat "99%".
        static func lossHeadline(_ fraction: Double, safeRemaining: Int) -> String {
            if Int((fraction * 100).rounded()) >= 100 && safeRemaining > 0 {
                return String(localized: "\(safeRemaining) left", bundle: .module)
            }
            return percent(fraction)
        }

        /// Sentence fragment for the consolation/a11y line.
        static func clearedDisplay(_ fraction: Double, safeRemaining: Int) -> String {
            if Int((fraction * 100).rounded()) >= 100 && safeRemaining > 0 {
                return String(localized: "So close — \(safeRemaining) tiles left", bundle: .module)
            }
            return String(localized: "Cleared \(percent(fraction))", bundle: .module)
        }
    }

    let kind: Kind
    let reduceMotion: Bool
    /// Dismiss the result screen to inspect the finished board (the X, a tap
    /// anywhere, or Esc). The game actions (New Game / Retry / Home) live on the
    /// still-visible control strip, so the panel carries no buttons of its own.
    let onContinue: () -> Void

    @State private var appeared = false
    #if os(macOS)
    @FocusState private var focused: Bool
    #endif

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Dimmed backdrop over the BOARD AREA only (this view is overlaid
                // on the board, not the whole window), so the toolbar/control
                // strip stay live. Tapped, it dismisses to inspect the board.
                Color.black.opacity(appeared ? 0.45 : 0)
                    .contentShape(Rectangle())
                    .onTapGesture { onContinue() }
                    .accessibilityHidden(true)

                // The art, sized to fit the board area (minus a margin) so it's
                // never clipped on a small board region or window.
                panelImage
                    .frame(
                        maxWidth: min(panelWidth(in: geo.size), geo.size.width - 24),
                        maxHeight: geo.size.height - 24
                    )
                    .scaleEffect(scale)
                    .opacity(appeared ? 1 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            #if os(macOS)
            // Hold keyboard focus (ring suppressed) so Esc closes the panel
            // even though the SpriteKit board would otherwise keep first
            // responder. `.onExitCommand` is the proper Escape hook — an
            // Escape menu key-equivalent isn't delivered by AppKit.
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onAppear { focused = true }
            .onExitCommand { onContinue() }
            #endif
        }
        .onAppear { animateIn() }
    }

    /// Responsive panel width. The art is roughly square, so size it off the
    /// *shorter* window dimension — that keeps it square-ish and centered whether
    /// the window is wide or tall — then clamp so it's never tiny or absurd.
    private func panelWidth(in size: CGSize) -> CGFloat {
        let shorter = min(size.width, size.height)
        return min(max(shorter * 0.82, 220), 900)
    }

    private var panelImage: some View {
        Image(kind.imageName, bundle: .module)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
            // No white backing: the art's panel interior is baked opaque-white and
            // only the area *outside* its drawn border is transparent — so the
            // rounded corners show the dimmed board through, as intended.
            .overlay(alignment: .topLeading) { recordBadge }
            .overlay(alignment: .topLeading) { bestLossPill }
            .overlay(alignment: .topTrailing) { closeButton }
            // Coloured accent glow — the roadmap's "accent applied in code over
            // the mono art", kept subtle so it frames rather than tints.
            .shadow(color: kind.accent.opacity(0.7), radius: 28)
            .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
            // A tap on the art itself also dismisses (tap-anywhere-but-button).
            .contentShape(Rectangle())
            .onTapGesture { onContinue() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(kind.a11yLabel)
            .accessibilityAddTraits(.isImage)
    }

    /// Top-right X to dismiss the panel (also tap-anywhere or Esc).
    private var closeButton: some View {
        Button(action: onContinue) {
            Image(systemName: "xmark.circle.fill")
                .font(.title)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.4))
                .padding(8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Close", bundle: .module))
    }

    /// Code-drawn "new record" flourish — a compact tilted ribbon tucked into the
    /// top-left corner so it reads as a stamp without covering the character.
    @ViewBuilder private var recordBadge: some View {
        if let cs = kind.recordCentiseconds {
            VStack(spacing: 0) {
                // Kana headline kept verbatim in all languages — a manga flourish.
                Text(verbatim: "新記録")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                Text(verbatim: TimeFormat.mmsst(centiseconds: cs))
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(kind.accent.opacity(0.95)))
            .overlay(Capsule().stroke(.white, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
            .rotationEffect(.degrees(-8))
            .padding(.top, 10)
            .padding(.leading, 8)
            .scaleEffect(appeared ? 1 : 0.5, anchor: .topLeading)
        }
    }

    /// On a loss that beat the previous best %, a small red corner pill — mirrors
    /// the record badge so a "new best %" reads as an achievement, not just text.
    /// (A plain loss shows nothing; the live readout covers the unimproved case.)
    @ViewBuilder private var bestLossPill: some View {
        if let headline = kind.bestLossHeadline {
            VStack(spacing: 0) {
                Text(verbatim: headline)
                    .font(.system(size: 17, weight: .black, design: .rounded))
                Text("best", bundle: .module)
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .textCase(.uppercase)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.red.opacity(0.95)))
            .overlay(Capsule().stroke(.white, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
            .rotationEffect(.degrees(-8))
            .padding(.top, 10)
            .padding(.leading, 8)
            .scaleEffect(appeared ? 1 : 0.5, anchor: .topLeading)
        }
    }

    /// Slam-in overshoot: starts large, settles to 1.0. Reduce Motion gets a
    /// straight fade (handled by `appeared` alone, scale pinned to 1).
    private var scale: CGFloat {
        if reduceMotion { return 1 }
        return appeared ? 1 : 1.4
    }

    private func animateIn() {
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.25)) { appeared = true }
        } else {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.6)) { appeared = true }
        }
    }
}
