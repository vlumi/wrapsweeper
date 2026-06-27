import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// A horizontal "drum" picker: equal-width name-only cards scroll under a fixed
/// center window; the centered card *is* the selection. Flinging snaps the
/// nearest card to center; tapping selects; an external `selection` change scrolls
/// the matching card to center. Backed by the platform scroll view (iOS 16 /
/// macOS 14 SwiftUI ScrollView lacks reliable deceleration + centered readout).
/// Used by `BoardSelectionPicker` for rows that won't fit a segmented control.
struct CarouselPicker: View {
    let labels: [String]
    @Binding var selection: Int
    /// Highlighted with the focus ring when this row is keyboard-focused (macOS).
    var focused: Bool = false
    /// Optional per-card symbol shown above the label (the difficulty rank
    /// insignia). nil → label-only cards.
    var symbol: ((Int) -> Image?)?
    /// User directly interacted with this row, so the host can move keyboard focus
    /// here. nil on iOS.
    var onInteract: (() -> Void)?

    // Wide enough for the longest label ("Intermediate") so labels never clip and
    // we avoid a jumpy minimumScaleFactor.
    private let cardWidth: CGFloat = 116
    private let spacing: CGFloat = 8
    private var height: CGFloat { symbol == nil ? 52 : 64 }

    private var contentWidth: CGFloat {
        CGFloat(labels.count) * cardWidth + CGFloat(max(0, labels.count - 1)) * spacing
    }

    var body: some View {
        GeometryReader { geo in
            // When every card fits there's no overflow to hint, so drop the
            // edge-fade and chevrons — they only make sense in the drum.
            let fits = cardsFit(in: geo.size.width)
            row(fits: fits)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .modifier(EdgeFade(active: !fits))
                .overlay(alignment: .leading) { if !fits { edgeChevron(.left) } }
                .overlay(alignment: .trailing) { if !fits { edgeChevron(.right) } }
        }
        .frame(height: height)
        .padding(.horizontal, 4)
        // Focus panel + ring is always present (transparent when unfocused), so
        // toggling focus only recolours — rows don't wobble as focus moves.
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

    /// Whether all cards fit the given width (so they lay out statically). iOS
    /// always uses the swipe drum, so cards never "fit" there.
    private func cardsFit(in width: CGFloat) -> Bool {
        #if os(iOS)
        return false
        #else
        return contentWidth <= width
        #endif
    }

    private enum Edge { case left, right }

    /// An edge chevron, visible only when more cards lie that way, tappable to step.
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

    /// Platform layout. iOS always uses the swipe drum. macOS lays cards out
    /// statically when they fit (click any directly), falling back to the carousel
    /// only on overflow.
    @ViewBuilder private func row(fits: Bool) -> some View {
        #if os(iOS)
        DrumScroll(
            count: labels.count, selection: $selection,
            cardWidth: cardWidth, spacing: spacing
        ) { i in
            card(i)
        }
        #else
        if fits {
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
        #endif
    }

    /// One card. The selected card carries the accent fill + border (marking the
    /// pick by the card itself, not a fixed centre ring — which would float over
    /// the middle card when the strip is statically centred). Fixed size with an
    /// always-present border, so selecting never resizes a card.
    private func card(_ i: Int) -> some View {
        let sel = i == selection
        return VStack(spacing: 3) {
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
                // Label colour/opacity stay constant (never keyed to selection):
                // animating a Text's foregroundStyle snaps glyphs rather than
                // crossfading, so cards jumped mid-slide. Selection shows via the
                // chip background + border (Shapes animate colour cleanly). fixedSize
                // lays the label out once so it only ever translates.
                .fixedSize()
                .foregroundStyle(.primary)
        }
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

/// Fades the row's left/right edges so peeking neighbours dissolve (reading as
/// "more this way") rather than hard-clipping. Identity when inactive (all cards
/// fit), so a full row isn't dimmed at its ends.
private struct EdgeFade: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        if active {
            content.mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.10),
                        .init(color: .black, location: 0.90),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .leading, endPoint: .trailing))
        } else {
            content
        }
    }
}
