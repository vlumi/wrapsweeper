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
        // Clip so off-centre cards don't bleed past the modal; neighbours still peek
        // inside the full-width frame.
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
        // Centering is handled in layoutSubviews (lands once bounds are final);
        // here we just nudge to the new selection.
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

        // The card nearest the viewport centre for the current offset.
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

/// The drum's `UIScrollView`: a half-card inset at each end so every card
/// (including first/last) can reach centre, with UIScrollView's own inset clamp
/// preventing dead over-scroll. The inset depends on the final width (unknown on
/// the first `updateUIView`), so it re-pins in `layoutSubviews`.
final class CenteringScrollView: UIScrollView {
    var cardWidth: CGFloat = 0
    var step: CGFloat = 1
    var indexProvider: () -> Int = { 0 }

    /// The content offset that brings card `i` to centre (given the current inset).
    func offset(forIndex i: Int) -> CGFloat { CGFloat(i) * step - contentInset.left }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side = max(0, (bounds.width - cardWidth) / 2)
        if abs(contentInset.left - side) > 0.5 {
            contentInset = UIEdgeInsets(top: 0, left: side, bottom: 0, right: side)
            recenter(animated: false)  // inset changed — re-pin
        } else {
            recenter(animated: false)
        }
    }

    /// Scroll the selection toward centre, unless the user is interacting.
    func recenter(animated: Bool) {
        guard !isDragging, !isDecelerating else { return }
        let target = offset(forIndex: indexProvider())
        if abs(contentOffset.x - target) > 0.5 {
            setContentOffset(CGPoint(x: target, y: 0), animated: animated)
        }
    }
}

#elseif os(macOS)

/// SwiftUI carousel for macOS (no scroll physics — the NSScrollView drum's
/// fling/snap was fragile under a flipped doc view). Cards are an `HStack` slid so
/// the selected card sits under the centre window; if the window fits all cards
/// the whole strip is just centred. Click, arrow keys, or a horizontal drag step
/// the selection.
struct DrumScroll<Content: View>: View {
    let count: Int
    @Binding var selection: Int
    let cardWidth: CGFloat
    let spacing: CGFloat
    var onInteract: (() -> Void)?
    @ViewBuilder let content: (Int) -> Content

    private var step: CGFloat { cardWidth + spacing }
    private var contentWidth: CGFloat { CGFloat(count) * cardWidth + CGFloat(count - 1) * spacing }

    var body: some View {
        GeometryReader { geo in
            let centerX = geo.size.width / 2
            let fitsAll = contentWidth <= geo.size.width
            // Fits all → centre the whole strip. Otherwise slide the selected card
            // to centre, clamped so the ends sit flush (no dead over-scroll).
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
            // Animate keyed to `offset` itself: an outer implicit animation doesn't
            // reliably reach this nested `.offset` (inside GeometryReader + clip),
            // and this also covers arrow-key changes (no withAnimation wrapper).
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
            // Clip so off-window cards don't bleed across the modal.
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
