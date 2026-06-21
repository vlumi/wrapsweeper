import DonpaCore
import SwiftUI

/// The end-of-game result screen: a dramatic comic frame that slams in over the
/// board on win/loss and *stays* until the player chooses. It dims and blocks
/// the board; a tap anywhere that isn't the "Title" button dismisses it (to
/// inspect the finished board), with explicit Continue / Title buttons under the
/// art. Restarting the same board is Space / Cmd-R, not a button here.
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
        case loss

        var imageName: String { self == .loss ? "PanelLoss" : "PanelWin" }
        var accent: Color { self == .loss ? .red : .green }
        var isWin: Bool { self != .loss }
        /// Spoken description for VoiceOver (the art conveys nothing to it).
        var a11yLabel: String {
            switch self {
            case .win: return "Minefield cleared"
            case .record(let cs):
                return "New record! Minefield cleared in \(TimeFormat.mmsst(centiseconds: cs))"
            case .loss: return "Boom — you stepped on a mine"
            }
        }
        /// The new-best time, if this is a record win.
        var recordCentiseconds: Int? {
            if case .record(let cs) = self { return cs }
            return nil
        }
    }

    let kind: Kind
    let reduceMotion: Bool
    /// Dismiss the result screen to inspect the finished board (also the
    /// tap-anywhere action). Restarting is Space / Cmd-R, not a button.
    let onContinue: () -> Void
    /// Back to the title screen.
    let onReturnToTitle: () -> Void

    @State private var appeared = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Dimmed backdrop: blocks the board and, tapped, retries.
                Color.black.opacity(appeared ? 0.45 : 0)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { onContinue() }
                    .accessibilityHidden(true)

                VStack(spacing: 18) {
                    panelImage
                    buttons
                }
                .padding(24)
                // Scale with the window: fill most of it, but bounded by both
                // width and (roughly-square art + buttons) height so it stays a
                // sensible size from small windows up to full screen.
                .frame(maxWidth: panelWidth(in: geo.size))
                .scaleEffect(scale)
                .opacity(appeared ? 1 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { animateIn() }
    }

    /// Responsive panel width. The art is roughly square, so size it off the
    /// *shorter* window dimension — that keeps it square-ish and centered whether
    /// the window is wide or tall — then clamp so it's never tiny or absurd.
    private func panelWidth(in size: CGSize) -> CGFloat {
        let shorter = min(size.width, size.height)
        return min(max(shorter * 0.82, 280), 900)
    }

    private var panelImage: some View {
        Image(kind.imageName, bundle: .module)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
            // Opaque white backing: the art is black ink on white, and the
            // outside-only transparency can leak into interior light regions — a
            // white plate makes any such leak read as page-white in both
            // appearances rather than punching a hole to the board.
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(alignment: .top) { recordBadge }
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

    private var buttons: some View {
        HStack(spacing: 14) {
            // A matched pair of solid capsules: neutral Title, accent Continue —
            // both clearly visible on the dark backdrop. Continue just dismisses
            // the panel to inspect the board; restart is Space / Cmd-R.
            capsuleButton(
                "Title", icon: "house.fill", fill: Color(white: 0.92), text: .black,
                action: onReturnToTitle
            )
            .keyboardShortcut(.cancelAction)  // Esc returns to title

            capsuleButton(
                "Continue", icon: "checkmark", fill: kind.accent, text: .white,
                action: onContinue
            )
            .keyboardShortcut(.defaultAction)  // Return also continues
        }
        .frame(maxWidth: 360)
    }

    private func capsuleButton(
        _ title: String, icon: String, fill: Color, text: Color, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(fill, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Code-drawn "new record" flourish over the win art — a tilted ribbon with
    /// the kana headline and the best time, so a record win reads as more than a
    /// plain clear without needing separate art.
    @ViewBuilder private var recordBadge: some View {
        if let cs = kind.recordCentiseconds {
            VStack(spacing: 2) {
                Text("新記録")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                Text("NEW RECORD · \(TimeFormat.mmsst(centiseconds: cs))")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(kind.accent.opacity(0.95)))
            .overlay(Capsule().stroke(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
            .rotationEffect(.degrees(-6))
            .offset(y: 14)
            .scaleEffect(appeared ? 1 : 0.5)
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
