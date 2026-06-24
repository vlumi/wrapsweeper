import SwiftUI

/// Lays out `content` at its natural (ideal) size and uniformly scales the whole
/// thing down to fit the available width — geometry scaling, not per-view font
/// scaling. Everything inside shrinks by one factor together (staying
/// proportional, no truncation, no jitter), and is never scaled *up* past 1.
///
/// Used by the status bar so the config label and the three metric readouts all
/// shrink together on a narrow phone instead of each self-scaling to a different
/// size. Pass a row with NO expanding Spacer — the natural width must be
/// well-defined (a Spacer collapses when measured but expands when rendered, so
/// the two disagree and the row clips instead of scaling).
struct FitToWidth<Content: View>: View {
    @ViewBuilder var content: Content

    @State private var naturalSize: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let scale = naturalSize.width > 0 ? min(1, geo.size.width / naturalSize.width) : 1
            // Lay the content out at its full natural width, then scale the whole
            // thing down by one factor. Pinned leading.
            content
                .fixedSize()
                .scaleEffect(scale, anchor: .leading)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
        }
        // Until measured, take natural height (nil frame); once known, pin to it so
        // the GeometryReader doesn't greedily expand vertically.
        .frame(height: naturalSize.height > 0 ? naturalSize.height : nil)
        .background(
            // Measure the content's true natural size off-screen. `fixedSize()`
            // makes it ignore the proposed width and report its ideal size.
            content
                .fixedSize()
                .background(
                    GeometryReader { g in
                        Color.clear
                            .onAppear { naturalSize = g.size }
                            .onChangeCompat(of: g.size) { naturalSize = $0 }
                    }
                )
                .hidden()
                .allowsHitTesting(false)
        )
    }
}
