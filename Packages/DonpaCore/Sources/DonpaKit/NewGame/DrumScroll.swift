import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Platform-backed drum

#if os(iOS)

/// `UIScrollView`-backed horizontal drum (see `CarouselPicker`).
struct DrumScroll<Content: View>: UIViewRepresentable {
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
        // Clip to the row's own bounds so off-centre cards don't bleed past the New
        // Game modal's edges on a narrow iPhone. Neighbours still peek — the scroll
        // view spans the full row width (wider than one card), so adjacent cards
        // show *inside* the frame; they just can't spill outside it.
        scroll.clipsToBounds = true
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
struct DrumScroll<Content: View>: View {
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
