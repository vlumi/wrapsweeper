import DonpaCore
import SwiftUI

/// The board-config chooser, presented as a self-contained modal overlay: a
/// dimmed backdrop (tap outside to dismiss) over a card holding
/// `BoardSelectionPicker` (Classic/Modern + size/difficulty, bound to `Settings`),
/// a Start button, and a close (X) in the corner.
///
/// This is the single place a new game is configured — reached both from the
/// in-game "New Game" action and by tapping the title art ("press start"). On
/// Start it begins a game with the chosen config and dismisses; the picker binds
/// to `Settings`, so the selection persists as the player's last choice.
///
/// Presented as an overlay rather than a `.sheet` so the dismiss affordances
/// (tap-outside + X) are consistent across iOS and macOS, matching the result
/// screen's pattern. On macOS it's keyboard-drivable: up/down move between the
/// picker rows (Mode / Size / Difficulty), left/right cycle the selection within
/// the focused row, Return starts, Esc closes.
struct NewGamePopup: View {
    @ObservedObject var settings: Settings
    /// Begin a game with the current selection. The host clears the title and
    /// starts the view model.
    let onStart: () -> Void
    /// Dismiss without starting (X, backdrop tap, or Escape).
    let onClose: () -> Void

    #if os(macOS)
    /// Keyboard-focused picker row: 0 = Mode, then Size/Difficulty depending on
    /// mode. nil until the first arrow press, so the highlight only appears once
    /// the player starts using the keyboard.
    @State private var focusedRow: Int?
    #endif

    var body: some View {
        ZStack {
            // Dimmed backdrop: blocks what's behind and dismisses when tapped.
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onClose() }

            card
                .overlay(alignment: .topTrailing) { closeButton }
                // Swallow taps on the card so they don't reach the backdrop.
                .contentShape(Rectangle())
                .onTapGesture {}
                .padding(24)
        }
        #if os(macOS)
        // An AppKit key-catcher takes first responder from the SpriteKit board
        // and routes arrows/Return/Esc — SwiftUI @FocusState can't reliably pry
        // it loose, especially after a game ends.
        .background(KeyCatcher { handleKey($0) })
        #endif
    }

    #if os(macOS)
    private func handleKey(_ key: KeyCatcher.Key) {
        switch key {
        case .up: focusedRow = max(0, (focusedRow ?? 0) - 1)
        case .down:
            let rows = settings.mode == .classic ? 2 : 3
            focusedRow = min(rows - 1, (focusedRow ?? -1) + 1)
        case .left: cycleSelection(in: focusedRow ?? 0, by: -1)
        case .right: cycleSelection(in: focusedRow ?? 0, by: 1)
        case .enter: onStart()
        case .escape: onClose()
        }
    }
    #endif

    private var card: some View {
        VStack(spacing: 20) {
            Text("New game", bundle: .module).font(.title2.bold())

            #if os(macOS)
            BoardSelectionPicker(settings: settings, focusedRow: focusedRow)
            Text("Arrows to choose · Return to start", bundle: .module)
                .font(.caption)
                .foregroundStyle(.secondary)
            #else
            BoardSelectionPicker(settings: settings)
            #endif

            Button {
                onStart()
            } label: {
                Label {
                    Text("Start", bundle: .module)
                } icon: {
                    Image(systemName: "play.fill")
                }
                .font(.title3.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.accentColor, in: Capsule())
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("newgame.start")
        }
        .padding(24)
        .frame(maxWidth: 460)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 6)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark.circle.fill")
                .font(.title)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.4))
                .padding(8)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)  // Escape closes
        .accessibilityLabel(Text("Close", bundle: .module))
    }

    #if os(macOS)
    /// Cycle the selection in the given row. Row 0 is always Mode; rows 1+ are
    /// Difficulty (Classic) or Size then Difficulty (Modern).
    private func cycleSelection(in row: Int, by step: Int) {
        switch (settings.mode, row) {
        case (_, 0):
            settings.mode = settings.mode == .classic ? .modern : .classic
        case (.classic, _):
            settings.classicPreset = Self.cycled(settings.classicPreset, by: step)
        case (.modern, 1):
            settings.modernSize = Self.cycled(settings.modernSize, by: step)
        case (.modern, _):
            settings.modernDensity = Self.cycled(settings.modernDensity, by: step)
        }
    }

    /// Next/previous case of a `CaseIterable` enum, wrapping at the ends.
    private static func cycled<T: CaseIterable & Equatable>(_ value: T, by step: Int) -> T {
        let all = Array(T.allCases)
        guard let i = all.firstIndex(of: value), !all.isEmpty else { return value }
        let next = (i + step % all.count + all.count) % all.count
        return all[next]
    }
    #endif
}
