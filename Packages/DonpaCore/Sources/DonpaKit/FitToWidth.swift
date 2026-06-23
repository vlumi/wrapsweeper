import SwiftUI

/// Lays out `content` at its natural (ideal) size and uniformly scales the whole
/// thing down to fit the available width — geometry scaling, not per-view font
/// scaling. Everything inside shrinks by one factor together (staying
/// proportional, no truncation, no jitter), and is never scaled *up* past 1.
///
/// `content` is measured with `.fixedSize(horizontal:)` so it reports its full
/// natural width; pass a row that fills the width itself (e.g. with a `Spacer`)
/// and it will be scaled to fit when too wide, or shown full-size (filling the
/// width, Spacer expanding) when it fits.
///
/// Used by the status bar so the config label, the three metric readouts, and the
/// High Scores medal all shrink together on a narrow phone instead of each
/// self-scaling to a different size.
struct FitToWidth<Content: View>: View {
    @ViewBuilder var content: Content

    @State private var naturalWidth: CGFloat = 0
    @State private var rowHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let scale = naturalWidth > 0 ? min(1, geo.size.width / naturalWidth) : 1
            content
                // When it fits (scale == 1) let it fill the width so a Spacer can
                // expand; when it doesn't, render at natural width and scale down.
                .frame(
                    width: scale < 1 ? naturalWidth : geo.size.width,
                    alignment: .leading
                )
                .scaleEffect(scale, anchor: .leading)
        }
        .frame(height: rowHeight)
        .background(
            // Measure the content's natural width once, off-screen, unconstrained.
            content
                .fixedSize(horizontal: true, vertical: false)
                .background(
                    GeometryReader { g in
                        Color.clear
                            .onAppear {
                                naturalWidth = g.size.width
                                rowHeight = g.size.height
                            }
                            .onChangeCompat(of: g.size) {
                                naturalWidth = $0.width
                                rowHeight = $0.height
                            }
                    }
                )
                .hidden()
        )
    }
}
