import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// A horizontal "drum" picker: equal-width name-only cards scroll under a fixed
/// center window, and the card centered there *is* the selection. Flinging
/// decelerates and snaps the nearest card to center; tapping a card selects it;
/// changing `selection` externally (e.g. the macOS arrow keys cycling `Settings`)
/// scrolls the matching card to center.
///
/// Backed by the platform scroll view (`UIScrollView` / `NSScrollView`) rather
/// than SwiftUI's `ScrollView`, because only the native view gives reliable
/// deceleration, settle-snap, and a centered-item readout on our deployment
/// targets (iOS 16 / macOS 14). Used by `BoardSelectionPicker` for the rows whose
/// labels won't fit a segmented control (Size's 7 tiers, the difficulty rows).
///
/// `labels` are the card strings in order; `selection` indexes them. The picker
/// is purely about *which index* — callers map their enum to/from the index.
struct CarouselPicker: View {
    let labels: [String]
    @Binding var selection: Int
    /// Highlighted with the focus ring when this row is keyboard-focused (macOS).
    var focused: Bool = false
    /// Optional per-card symbol shown ABOVE the label (e.g. the rank insignia on
    /// the difficulty row, connecting the card to the status-bar rank patch). Rows
    /// without symbols (Size, Classic) pass nil and the cards are label-only.
    var symbol: ((Int) -> Image?)?
    /// Called when the user directly interacts with this row (taps/clicks a card),
    /// so the host can move keyboard focus here. nil on iOS (no keyboard focus).
    var onInteract: (() -> Void)?

    // Wide enough for the longest label ("Intermediate") at the card font, so the
    // fixed-size labels never clip and we don't need a (jumpy) minimumScaleFactor.
    private let cardWidth: CGFloat = 116
    private let spacing: CGFloat = 8
    /// Taller when any card carries a symbol, to fit the stacked symbol + label.
    private var height: CGFloat { symbol == nil ? 52 : 64 }

    /// Width to lay every card side by side.
    private var contentWidth: CGFloat {
        CGFloat(labels.count) * cardWidth + CGFloat(max(0, labels.count - 1)) * spacing
    }

    var body: some View {
        rowContent
            .frame(maxWidth: .infinity)
            .frame(height: height)
            // Fade the row's edges instead of hard-clipping: keeps the drum's
            // off-centre cards from bleeding past the modal (a plain clip guillotines
            // a card mid-width, which looks broken) while the peeking neighbours
            // softly fade out — reading as "more this way". The mask also bounds the
            // content to the row width, so nothing spills outside the modal.
            .mask(edgeFade)
            // Edge chevrons hint "there's more this way" and step the selection
            // when tapped. They fade at the ends (no left arrow on the first card,
            // no right on the last) and overlay without affecting layout.
            .overlay(alignment: .leading) { edgeChevron(.left) }
            .overlay(alignment: .trailing) { edgeChevron(.right) }
            .padding(.horizontal, 4)
            // Keyboard focus: a tinted panel + ring around the whole row. The padding
            // and a 2pt-wide border are ALWAYS present (just transparent when not
            // focused), so toggling focus only changes colour — the layout never
            // resizes, so rows don't wobble as keyboard focus moves between them.
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(focused ? 0.12 : 0))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.accentColor.opacity(focused ? 1 : 0), lineWidth: 2))
            )
            .animation(.snappy, value: focused)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(labels.indices.contains(selection) ? labels[selection] : "")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: selection = min(selection + 1, labels.count - 1)
                case .decrement: selection = max(selection - 1, 0)
                @unknown default: break
                }
            }
    }

    /// A horizontal mask that's opaque in the middle and fades to clear at the
    /// left/right edges, so peeking cards dissolve rather than getting clipped.
    private var edgeFade: some View {
        let fade = 0.10  // fraction of width that fades on each side
        return LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: fade),
                .init(color: .black, location: 1 - fade),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading, endPoint: .trailing)
    }

    private enum Edge { case left, right }

    /// A small chevron at one edge: visible only when there are more cards that
    /// way (faded out otherwise), tappable to step the selection one card.
    @ViewBuilder private func edgeChevron(_ edge: Edge) -> some View {
        let canGo = edge == .left ? selection > 0 : selection < labels.count - 1
        Image(systemName: edge == .left ? "chevron.left" : "chevron.right")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .opacity(canGo ? 0.7 : 0)
            .allowsHitTesting(canGo)
            .onTapGesture {
                onInteract?()
                selection = edge == .left ? selection - 1 : selection + 1
            }
            .animation(.snappy, value: selection)
            .accessibilityHidden(true)  // the row itself is the a11y element
    }

    /// Platform-specific layout. iOS ALWAYS uses the swipe drum (selected card
    /// centers, with edge space so the ends can reach center) — a static tap-row
    /// felt wrong under a swipe model. macOS lays the cards out statically when
    /// they fit (you click any directly), and falls back to its SwiftUI carousel
    /// only when they overflow.
    @ViewBuilder private var rowContent: some View {
        #if os(iOS)
        DrumScroll(
            count: labels.count, selection: $selection,
            cardWidth: cardWidth, spacing: spacing
        ) { i in
            card(i)
        }
        #else
        GeometryReader { geo in
            if contentWidth <= geo.size.width {
                HStack(spacing: spacing) {
                    ForEach(0..<labels.count, id: \.self) { i in
                        card(i)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onInteract?()
                                selection = i
                            }
                    }
                }
                .frame(maxWidth: .infinity)
                .animation(.snappy, value: selection)
            } else {
                DrumScroll(
                    count: labels.count, selection: $selection,
                    cardWidth: cardWidth, spacing: spacing, onInteract: onInteract
                ) { i in
                    card(i)
                }
            }
        }
        #endif
    }

    /// Every card is a visible "chip" — so unselected options read as tappable
    /// cards (not just faint text), and a half-clipped chip at the edge signals
    /// there are more options to scroll to. The SELECTED card carries the accent
    /// fill + border — marking the pick by the card itself, not a fixed centre
    /// ring. (The ring only made sense in scroll mode, where selected == centred;
    /// when every card fits and the strip is statically centred, a centre ring
    /// would float over the middle card regardless of the real selection.)
    /// Every chip is the SAME fixed size with an always-present border (just
    /// recoloured when selected), so selecting never resizes a card.
    private func card(_ i: Int) -> some View {
        let sel = i == selection
        return VStack(spacing: 3) {
            // Optional rank insignia above the label (difficulty row), tying the
            // card to the status-bar rank patch. Template image → tinted to match.
            if let sym = symbol?(i) {
                sym
                    .resizable()
                    .scaledToFit()
                    .frame(height: 16)
                    .foregroundStyle(.primary)
            }
            Text(labels.indices.contains(i) ? labels[i] : "")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                // The label's colour and opacity are CONSTANT (never keyed to
                // selection). Animating a Text's foregroundStyle/opacity snaps the
                // glyphs rather than crossfading, so the outgoing/incoming current
                // cards visibly jumped mid-slide. Selection shows via the chip
                // background + border (Shapes, which animate colour cleanly).
                // fixedSize lays the label out once so it only ever translates.
                .fixedSize()
                .foregroundStyle(.primary)
        }
        // Horizontal breathing room inside the chip so the longest label
        // ("Intermediate") isn't cramped to the edges.
        .padding(.horizontal, 10)
        .frame(width: cardWidth - 6, height: height - 10)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(sel ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(
                            sel ? Color.accentColor : Color.primary.opacity(0.12),
                            lineWidth: sel ? 2.5 : 1))
        )
    }
}
