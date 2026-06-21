import AppKit

/// Grows the key window when a board needs more room than the current window
/// gives it — but never shrinks. Picking a bigger board enlarges the window to
/// fit; picking a smaller one (or one that already fits) leaves the window
/// alone, so a maximized or manually-sized window is respected. The board view
/// itself centers and caps cell size within whatever space it's given.
enum WindowSizer {
    /// Target board area (points) used to derive a comfortable cell size, so a
    /// freshly-opened small window lands at a substantial size rather than tiny.
    private static let targetBoardWidth: CGFloat = 760
    private static let targetBoardHeight: CGFloat = 600
    /// Cell-size clamp for the *minimum* fit: a cap so small boards don't demand
    /// a giant window, a floor so dense boards stay clickable.
    private static let maxCellSize: CGFloat = 72
    private static let minCellSize: CGFloat = 24
    /// Approximate chrome height (status bar + difficulty pickers) added below
    /// the board area.
    private static let chromeHeight: CGFloat = 140
    private static let boardPadding: CGFloat = 24

    static func growToFit(forBoard cols: Int, by rows: Int) {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) else {
            return
        }
        // Don't fight the user in full screen.
        guard !window.styleMask.contains(.fullScreen) else { return }

        // Largest cell that fits both target dimensions, then clamped — this is
        // the *minimum* comfortable window for the board.
        let fit = min(targetBoardWidth / CGFloat(cols), targetBoardHeight / CGFloat(rows))
        let cell = min(maxCellSize, max(minCellSize, fit))

        let needW = CGFloat(cols) * cell + boardPadding * 2
        let needH = CGFloat(rows) * cell + boardPadding + chromeHeight

        // Grow-only: keep the larger of what's needed and the current size, so a
        // maximized/hand-sized window is never shrunk on a config change.
        let current = window.contentRect(forFrameRect: window.frame).size
        var content = CGSize(
            width: max(needW, current.width),
            height: max(needH, current.height))

        // Stay within the visible screen (minus a little breathing room).
        if let frame = window.screen?.visibleFrame {
            content.width = min(content.width, frame.width - 40)
            content.height = min(content.height, frame.height - 40)
        }
        content.width = max(content.width, 360)
        content.height = max(content.height, 480)

        // Nothing to do if the window already fits (avoids a no-op nudge).
        guard content.width > current.width + 1 || content.height > current.height + 1 else {
            return
        }
        window.setContentSize(content)
    }
}
