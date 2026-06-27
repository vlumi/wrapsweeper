import SwiftUI

/// Lays `content` out at its natural size and uniformly scales the whole thing
/// down to fit the available width (geometry scaling, never up past 1), so a row
/// of views shrinks together rather than each self-scaling. Pass a row with NO
/// expanding Spacer — a Spacer collapses when measured but expands when rendered,
/// so the row would clip instead of scaling.
struct FitToWidth<Content: View>: View {
    @ViewBuilder var content: Content

    @State private var naturalSize: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let scale = naturalSize.width > 0 ? min(1, geo.size.width / naturalSize.width) : 1
            content
                .fixedSize()
                .scaleEffect(scale, anchor: .leading)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
        }
        // Pin to the measured height so the GeometryReader doesn't expand vertically.
        .frame(height: naturalSize.height > 0 ? naturalSize.height : nil)
        .background(
            // Measure the content's natural size off-screen (fixedSize → ideal size).
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
