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
            .frame(height: height)
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

// MARK: - Platform-backed drum

#if os(iOS)

/// `UIScrollView`-backed horizontal drum (see `CarouselPicker`).
private struct DrumScroll<Content: View>: UIViewRepresentable {
    let count: Int
    @Binding var selection: Int
    let cardWidth: CGFloat
    let spacing: CGFloat
    @ViewBuilder let content: (Int) -> Content

    var step: CGFloat { cardWidth + spacing }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> CenteringScrollView {
        let scroll = CenteringScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.decelerationRate = .fast
        scroll.delegate = context.coordinator
        scroll.clipsToBounds = false
        scroll.cardWidth = cardWidth
        scroll.step = step
        scroll.indexProvider = { selection }

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = spacing
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        context.coordinator.stack = stack

        for i in 0..<count {
            let hc = context.coordinator.makeHost(i, self)
            let v = hc.view!
            v.translatesAutoresizingMaskIntoConstraints = false
            v.backgroundColor = .clear
            v.widthAnchor.constraint(equalToConstant: cardWidth).isActive = true
            v.tag = i
            v.addGestureRecognizer(
                UITapGestureRecognizer(
                    target: context.coordinator, action: #selector(Coordinator.tapped(_:))))
            stack.addArrangedSubview(v)
        }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
        return scroll
    }

    func updateUIView(_ scroll: CenteringScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.refresh(self)
        scroll.indexProvider = { selection }
        // Centering (inset + offset) is handled in the scroll view's
        // layoutSubviews, so it lands correctly once bounds are final — not only
        // after the first touch. Here we just nudge it to the new selection.
        scroll.recenter(animated: false)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: DrumScroll
        weak var stack: UIStackView?
        private var hosts: [UIHostingController<Content>] = []

        init(_ parent: DrumScroll) { self.parent = parent }

        func makeHost(_ i: Int, _ parent: DrumScroll) -> UIHostingController<Content> {
            let hc = UIHostingController(rootView: parent.content(i))
            hc.view.backgroundColor = .clear
            hosts.append(hc)
            return hc
        }

        func refresh(_ parent: DrumScroll) {
            for (i, hc) in hosts.enumerated() { hc.rootView = parent.content(i) }
        }

        @objc func tapped(_ g: UITapGestureRecognizer) {
            guard let i = g.view?.tag, i != parent.selection else { return }
            parent.selection = i
        }

        // The card nearest the viewport centre, given the current offset. A
        // half-card inset at each end lets every card — including the first and
        // last — be scrolled to centre; UIScrollView clamps the offset to the inset
        // range, so there's no dead over-scroll past the ends.
        private func centered(_ scroll: UIScrollView) -> Int {
            let raw = (scroll.contentOffset.x + scroll.contentInset.left) / parent.step
            return min(max(Int(raw.rounded()), 0), parent.count - 1)
        }

        func scrollViewDidScroll(_ scroll: UIScrollView) {
            guard scroll.isDragging || scroll.isDecelerating else { return }
            let i = centered(scroll)
            if i != parent.selection { parent.selection = i }
        }

        func scrollViewWillEndDragging(
            _ scroll: UIScrollView, withVelocity velocity: CGPoint,
            targetContentOffset: UnsafeMutablePointer<CGPoint>
        ) {
            let side = scroll.contentInset.left
            let raw = (targetContentOffset.pointee.x + side) / parent.step
            let i = min(max(Int(raw.rounded()), 0), parent.count - 1)
            targetContentOffset.pointee = CGPoint(x: CGFloat(i) * parent.step - side, y: 0)
        }
    }
}

/// A `UIScrollView` for the drum: a half-card inset at each end so EVERY card
/// (including the first/last) can be scrolled to centre, while UIScrollView's own
/// clamp to that inset range stops any dead over-scroll past the ends. "Centered =
/// selected." Lays out across passes (the inset depends on the final width, unknown
/// on the first `updateUIView`), so it re-pins in `layoutSubviews`.
final class CenteringScrollView: UIScrollView {
    var cardWidth: CGFloat = 0
    var step: CGFloat = 1
    var indexProvider: () -> Int = { 0 }

    /// The content offset that brings card `i` to centre (given the current inset).
    func offset(forIndex i: Int) -> CGFloat { CGFloat(i) * step - contentInset.left }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Half-card inset each side so the first/last card can reach centre.
        let side = max(0, (bounds.width - cardWidth) / 2)
        if abs(contentInset.left - side) > 0.5 {
            contentInset = UIEdgeInsets(top: 0, left: side, bottom: 0, right: side)
            recenter(animated: false)  // inset changed — re-pin
        } else {
            recenter(animated: false)
        }
    }

    /// Scroll the current selection toward centre (clamped to the edges), unless
    /// the user is interacting.
    func recenter(animated: Bool) {
        guard !isDragging, !isDecelerating else { return }
        let target = offset(forIndex: indexProvider())
        if abs(contentOffset.x - target) > 0.5 {
            setContentOffset(CGPoint(x: target, y: 0), animated: animated)
        }
    }
}

#elseif os(macOS)

/// SwiftUI carousel for macOS (the `NSScrollView` drum's fling/snap geometry was
/// fragile under a flipped doc view). No scroll physics: the cards are an `HStack`
/// slid so the selected card sits under the center window. When the window is wide
/// enough to show every card at once, the whole strip is simply centered with no
/// per-selection slide — so a roomy window needs no scrolling and any card is one
/// click away. Below that width it falls back to centering on the selection.
/// Click a card to select it, or use the arrow keys (the host cycles `Settings`,
/// which this follows); a horizontal drag also steps the selection.
private struct DrumScroll<Content: View>: View {
    let count: Int
    @Binding var selection: Int
    let cardWidth: CGFloat
    let spacing: CGFloat
    var onInteract: (() -> Void)?
    @ViewBuilder let content: (Int) -> Content

    private var step: CGFloat { cardWidth + spacing }
    /// Total width to lay all cards side by side.
    private var contentWidth: CGFloat { CGFloat(count) * cardWidth + CGFloat(count - 1) * spacing }

    var body: some View {
        GeometryReader { geo in
            let centerX = geo.size.width / 2
            let fitsAll = contentWidth <= geo.size.width
            // If everything fits, center the whole strip (no scroll). Otherwise
            // slide so the selected card's center lands at centerX — but CLAMP so
            // the strip stops with the first card flush left (offset 0) and the
            // last flush right (offset = width − contentWidth), with no dead
            // over-scroll past the ends. So a middle pick centers, while the ends
            // sit at the edges — one move to easiest/smallest or hardest/biggest.
            let ideal = centerX - (CGFloat(selection) * step + cardWidth / 2)
            let minOffset = geo.size.width - contentWidth  // last card flush right
            let offset =
                fitsAll
                ? centerX - contentWidth / 2
                : min(0, max(minOffset, ideal))
            HStack(spacing: spacing) {
                ForEach(0..<count, id: \.self) { i in
                    content(i)
                        .frame(width: cardWidth)
                        .contentShape(Rectangle())
                        .onTapGesture { select(i) }
                }
            }
            .padding(.vertical, 2)
            .offset(x: offset)
            // Animate the slide right here on the offset, keyed to the offset value
            // itself — the implicit animation on the outer view didn't reliably
            // reach this nested `.offset` (inside GeometryReader + clip), so the
            // strip jumped while colours animated. Keying on `offset` also covers
            // arrow-key changes (which mutate selection → offset without a
            // withAnimation wrapper).
            .animation(.snappy, value: offset)
            .frame(maxHeight: .infinity, alignment: .center)
            .frame(width: geo.size.width, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(
                fitsAll
                    ? nil
                    : DragGesture(minimumDistance: 12)
                        .onEnded { v in
                            if v.translation.width < -20 {
                                select(selection + 1)
                            } else if v.translation.width > 20 {
                                select(selection - 1)
                            }
                        }
            )
            // Clip to the row's bounds so off-window cards don't bleed across the
            // modal (and onto the board behind it).
            .clipped()
        }
    }

    private func select(_ i: Int) {
        onInteract?()
        let clamped = min(max(i, 0), count - 1)
        if clamped != selection { selection = clamped }
    }
}

#endif
