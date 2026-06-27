import DonpaCore
import SwiftUI

/// Rank-insignia images for the Modern difficulty tiers — chevron stripes for the
/// enlisted ranks, a star for Ace, a star-in-laurel for the apex. Rendered once
/// to flat template `Image`s so they work as single labels in a segmented
/// `Picker` (which flattens multi-view labels) and can be reused wherever a tier
/// is shown (the difficulty picker, the in-game config badge, the scoreboard).
enum DensityInsignia {
    /// Solid-**patch** insignia (filled box, symbol knocked out) — for the config
    /// pill and the scoreboard, where it reads as a badge.
    @MainActor static func image(_ density: Density) -> Image {
        patchCache[density] ?? Image(systemName: "questionmark")
    }

    /// **Inked-symbol** insignia (no patch, transparent background) — for the
    /// segmented difficulty picker, so the control's own selection highlight shows
    /// clearly behind the picked symbol (a solid patch would hide it).
    @MainActor static func markImage(_ density: Density) -> Image {
        markCache[density] ?? Image(systemName: "questionmark")
    }

    @MainActor private static let patchCache = render { badge($0) }
    @MainActor private static let markCache = render {
        mark($0).foregroundStyle(.black).frame(width: 46, height: 30)
    }

    /// Render each tier's view to a flat template image (cached once).
    @MainActor private static func render<V: View>(_ make: (Density.Insignia) -> V)
        -> [Density: Image]
    {
        var out: [Density: Image] = [:]
        for d in Density.allCases {
            let renderer = ImageRenderer(content: make(d.insignia))
            renderer.scale = 3
            if let cg = renderer.cgImage {
                out[d] = Image(decorative: cg, scale: 3).renderingMode(.template)
            }
        }
        return out
    }

    /// The bare insignia mark: sideways chevron stripes for the enlisted ranks
    /// (up-chevron rotated 90° CCW, nested), a star for Ace, a star-in-laurel for
    /// the apex.
    @MainActor @ViewBuilder
    private static func mark(_ insignia: Density.Insignia) -> some View {
        switch insignia {
        case .chevrons(let n):
            HStack(spacing: -5) {
                ForEach(0..<n, id: \.self) { _ in
                    Image(systemName: "chevron.left").font(.system(size: 16, weight: .black))
                }
            }
        case .star:
            Image(systemName: "star.fill").font(.system(size: 16, weight: .black))
        case .staredLaurel:
            HStack(spacing: -3) {
                Image(systemName: "laurel.leading").font(.system(size: 20, weight: .bold))
                Image(systemName: "star.fill").font(.system(size: 11, weight: .black))
                Image(systemName: "laurel.trailing").font(.system(size: 20, weight: .bold))
            }
        }
    }

    /// A solid filled patch with the insignia *knocked out* (negative space) — a
    /// single-colour badge with no separate frame. Rendered as a template so the
    /// host tints the whole patch.
    @MainActor @ViewBuilder
    private static func badge(_ insignia: Density.Insignia) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .frame(width: 46, height: 30)  // uniform patch size across tiers
            .overlay(mark(insignia).foregroundStyle(.black).blendMode(.destinationOut))
            .foregroundStyle(.black)
            .compositingGroup()  // so destinationOut only affects this patch
    }
}
