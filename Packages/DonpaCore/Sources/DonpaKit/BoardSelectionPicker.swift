import DonpaCore
import SwiftUI

/// The board-config chooser: a Classic/Modern mode switch over the matching
/// picker (3 classic presets, or Size × Density for Modern). Binds directly to
/// `Settings` with no side effects — picking here updates the *pending* choice;
/// the host decides when to actually start a game (the home hub's Start button).
struct BoardSelectionPicker: View {
    @ObservedObject var settings: Settings

    var body: some View {
        VStack(spacing: 8) {
            Picker("Mode", selection: $settings.mode) {
                ForEach(GameMode.allCases) { Text(verbatim: $0.label).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            switch settings.mode {
            case .classic:
                Picker("Difficulty", selection: $settings.classicPreset) {
                    ForEach(ClassicPreset.allCases, id: \.self) { Text(verbatim: $0.label).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            case .modern:
                Picker("Size", selection: $settings.modernSize) {
                    ForEach(BoardSize.allCases, id: \.self) { Text(verbatim: $0.label).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                Picker("Difficulty", selection: $settings.modernDensity) {
                    ForEach(Density.allCases, id: \.self) { Text(verbatim: $0.label).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
        }
    }
}
