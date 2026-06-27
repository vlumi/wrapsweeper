import SwiftUI

/// Manga screentone for the mode toggle's segment backgrounds: Ben-Day dots (dig)
/// or diagonal hatch (flag). The SwiftUI counterpart to `BoardScene`'s texture.
struct ScreentonePattern: View {
    let dots: Bool
    let color: Color

    var body: some View {
        Canvas { ctx, area in
            let w = area.width, h = area.height
            let shading = GraphicsContext.Shading.color(color)
            if dots {
                let gap = w * 0.22, r = w * 0.05
                var row = 0
                var y = gap / 2
                while y < h + gap {
                    let offset = row.isMultiple(of: 2) ? 0 : gap / 2
                    var x = gap / 2 - gap + offset
                    while x < w + gap {
                        ctx.fill(
                            Path(
                                ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                            with: shading)
                        x += gap
                    }
                    y += gap * 0.86
                    row += 1
                }
            } else {
                let gap = w * 0.20
                var d = -h
                while d < w {
                    var line = Path()
                    line.move(to: CGPoint(x: d, y: 0))
                    line.addLine(to: CGPoint(x: d + h, y: h))
                    ctx.stroke(line, with: shading, lineWidth: w * 0.05)
                    d += gap
                }
            }
        }
    }
}
