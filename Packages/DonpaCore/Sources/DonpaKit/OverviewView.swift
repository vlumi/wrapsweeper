import DonpaCore
import SpriteKit
import SwiftUI

/// Fullscreen board overview for navigating a board too big to see at once. Shows
/// the whole board as a downsampled image with a "you are here" rectangle; drag
/// (or tap) anywhere to recentre the live board there — the board follows
/// immediately behind the overview. Dismissed by the X or a tap on the backdrop.
///
/// The small corner minimap is just a position indicator + the entry point to
/// this view (too small to navigate on); all navigation happens here.
struct OverviewView: View {
    let scene: BoardScene
    let onClose: () -> Void

    @ObservedObject var settings: Settings
    @Environment(\.colorScheme) private var colorScheme
    private var palette: Palette { .resolved(for: colorScheme) }

    /// The board overview as a SwiftUI image, rebuilt when the board changes.
    /// `revision` (passed in) drives the refresh.
    let revision: Int

    /// Live viewport rect (normalized, y-down) — re-read each drag so the box
    /// tracks where the camera actually landed (after clamping).
    @State private var viewport: CGRect = .init(x: 0, y: 0, width: 1, height: 1)

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onClose() }

            GeometryReader { geo in
                // Fit the board's aspect ratio into the available space.
                let board = CGSize(
                    width: CGFloat(max(1, scene.viewModel.boardWidth)),
                    height: CGFloat(max(1, scene.viewModel.boardHeight)))
                let maxW = geo.size.width - 48
                let maxH = geo.size.height - 48
                let aspect = board.width / board.height
                let w = min(maxW, maxH * aspect)
                let h = w / aspect
                let frame = CGRect(
                    x: (geo.size.width - w) / 2, y: (geo.size.height - h) / 2,
                    width: w, height: h)

                overviewImage
                    .frame(width: w, height: h)
                    .position(x: frame.midX, y: frame.midY)
                    .overlay(alignment: .topLeading) {
                        // The "you are here" rectangle, in the image's own space.
                        Rectangle()
                            .stroke(palette.counter, lineWidth: 2)
                            .background(palette.counter.opacity(0.18))
                            .frame(
                                width: max(6, viewport.width * w),
                                height: max(6, viewport.height * h)
                            )
                            .offset(
                                x: frame.minX + viewport.minX * w, y: frame.minY + viewport.minY * h
                            )
                            .allowsHitTesting(false)
                    }
                    // Drag or tap anywhere on the board image → recentre there.
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in jump(to: value.location, in: frame) }
                    )
            }

            closeButton
        }
        .onAppear { viewport = scene.visibleNormalizedRect() }
        .id(revision)  // rebuild the image when the board state changes
    }

    /// The downsampled board image (a bit higher-res than the corner minimap).
    @ViewBuilder private var overviewImage: some View {
        if let cg = scene.boardOverviewImage(pixelsPerCell: overviewPPC) {
            Image(decorative: cg, scale: 1, orientation: .up)
                .resizable()
                .interpolation(.none)  // crisp cell blocks
                .border(palette.counter, width: 2)
        } else {
            Rectangle().fill(palette.pageBackground)
        }
    }

    /// Pixels-per-cell for the fullscreen image — capped so a 1000² board stays a
    /// sane bitmap, but denser than the corner minimap since it's shown big.
    private var overviewPPC: Int {
        let maxDim = 600
        let side = max(scene.viewModel.boardWidth, scene.viewModel.boardHeight)
        return max(1, min(maxDim / max(1, side), 6))
    }

    /// Map a point in the image frame to a normalized board point and drive the
    /// camera there live; re-read the resulting viewport so the box tracks it.
    private func jump(to point: CGPoint, in frame: CGRect) {
        guard frame.width > 0, frame.height > 0 else { return }
        let nx = (point.x - frame.minX) / frame.width
        let ny = (point.y - frame.minY) / frame.height
        scene.centerCamera(onNormalizedPoint: CGPoint(x: nx, y: ny))
        viewport = scene.visibleNormalizedRect()
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.largeTitle)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.4))
                        .padding(16)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel(Text("Close", bundle: .module))
                .accessibilityIdentifier("overview.close")
            }
            Spacer()
        }
    }
}
