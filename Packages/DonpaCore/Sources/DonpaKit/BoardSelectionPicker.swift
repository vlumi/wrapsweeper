import DonpaCore
import SwiftUI

/// The board-config chooser: a Classic/Modern mode switch over the matching
/// picker (3 classic presets, or Size × Density for Modern). Binds directly to
/// `Settings` with no side effects — picking here updates the *pending* choice;
/// the host decides when to actually start a game (the home hub's Start button).
///
/// On macOS it's keyboard-drivable: up/down move between rows (Mode / Size /
/// Difficulty), left/right cycle the selection within the focused row. The
/// focused row is highlighted. `focusedRow` is owned by the host (the popup,
/// which holds the keyboard focus) and clamped here as the row set changes
/// (Classic has 2 rows, Modern 3).
struct BoardSelectionPicker: View {
    @ObservedObject var settings: Settings
    /// Index of the keyboard-focused row, or nil when not keyboard-driven (iOS,
    /// or before the first arrow press). Highlighted when set.
    var focusedRow: Int?

    var body: some View {
        VStack(spacing: 8) {
            row(0) {
                Picker("Mode", selection: $settings.mode) {
                    ForEach(GameMode.allCases) { Text(verbatim: $0.label).tag($0) }
                }
            }

            switch settings.mode {
            case .classic:
                row(1) {
                    Picker("Difficulty", selection: $settings.classicPreset) {
                        ForEach(ClassicPreset.allCases, id: \.self) {
                            Text(verbatim: $0.label).tag($0)
                        }
                    }
                }
            case .modern:
                row(1) {
                    Picker("Size", selection: $settings.modernSize) {
                        ForEach(BoardSize.allCases, id: \.self) { Text(verbatim: $0.label).tag($0) }
                    }
                }
                row(2) {
                    Picker("Difficulty", selection: $settings.modernDensity) {
                        ForEach(Density.allCases, id: \.self) { Text(verbatim: $0.label).tag($0) }
                    }
                }
            }
        }
    }

    /// A segmented picker wrapped with a focus highlight when it's the keyboard-
    /// focused row, so the player can see which row left/right will act on.
    private func row<P: View>(_ index: Int, @ViewBuilder _ picker: () -> P) -> some View {
        picker()
            .labelsHidden()
            .pickerStyle(.segmented)
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor, lineWidth: focusedRow == index ? 2.5 : 0)
            )
    }
}
