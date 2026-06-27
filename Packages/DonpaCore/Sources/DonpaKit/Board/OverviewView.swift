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
    /// Keyboard focus so Esc reaches `.onExitCommand` (macOS); unused on iOS.
    @FocusState private var focused: Bool

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

                overviewImage
                    .frame(width: w, height: h)
                    .overlay(alignment: .topLeading) {
                        // The "you are here" rectangle, in the image's own space.
                        Rectangle()
                            .stroke(palette.counter, lineWidth: 2)
                            .background(palette.counter.opacity(0.18))
                            .frame(
                                width: max(6, viewport.width * w),
                                height: max(6, viewport.height * h)
                            )
                            .offset(x: viewport.minX * w, y: viewport.minY * h)
                            .allowsHitTesting(false)
                    }
                    // Drag/tap navigates — gesture is bound to the IMAGE only (in
                    // its own 0…w/0…h space), so taps OUTSIDE the image fall through
                    // to the backdrop and close the overview.
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in jumpInImage(value.location, w: w, h: h) }
                    )
                    // Centre the image (and only the image) in the screen.
                    .frame(width: geo.size.width, height: geo.size.height)
            }

            closeButton
        }
        .onAppear { viewport = scene.visibleNormalizedRect() }
        #if os(macOS)
        // Hold keyboard focus (ring suppressed) so Esc closes the overview — the
        // SpriteKit board would otherwise keep first responder and swallow it.
        // `.onExitCommand` is the proper Escape hook (same as the result panel);
        // iOS has no Esc, so this is macOS-only (the API is unavailable on iOS).
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onExitCommand { onClose() }
        #endif
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

    /// Map a point in the image's own space (0…w, 0…h) to a normalized board
    /// point and drive the camera there live; re-read the resulting viewport so
    /// the box tracks where the (clamped) camera landed.
    private func jumpInImage(_ point: CGPoint, w: CGFloat, h: CGFloat) {
        guard w > 0, h > 0 else { return }
        scene.centerCamera(onNormalizedPoint: CGPoint(x: point.x / w, y: point.y / h))
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
