import AppKit

/// Resizes the key window to a snug fit for a board's aspect ratio, so picking
/// Beginner (square) vs Expert (wide) gives a sensibly-shaped window instead of
/// reusing whatever loose size was there. The user can still resize/full-screen
/// afterward; this only fires on a config change.
enum WindowSizer {
    /// A comfortable on-screen cell size for the snug fit (matches the scene's
    /// max cell size so the snug window shows cells at their natural size).
    private static let cellSize: CGFloat = 40
    /// Approximate chrome height (status bar + difficulty pickers) added below
    /// the board area.
    private static let chromeHeight: CGFloat = 140
    private static let boardPadding: CGFloat = 24

    static func snugFit(forBoard cols: Int, by rows: Int) {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) else {
            return
        }
        // Don't fight the user in full screen.
        guard !window.styleMask.contains(.fullScreen) else { return }

        let boardW = CGFloat(cols) * cellSize + boardPadding * 2
        let boardH = CGFloat(rows) * cellSize + boardPadding
        var content = CGSize(width: boardW, height: boardH + chromeHeight)

        // Keep within the visible screen (minus a little breathing room).
        if let frame = window.screen?.visibleFrame {
            content.width = min(content.width, frame.width - 40)
            content.height = min(content.height, frame.height - 40)
        }
        content.width = max(content.width, 320)
        content.height = max(content.height, 420)

        window.setContentSize(content)
    }
}
