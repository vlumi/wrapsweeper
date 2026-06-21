import DonpaCore
import SwiftUI

/// The high-score table: clears + best time per config. Classic configs always
/// show; Modern configs appear once they've been played (to avoid 15 empty
/// rows). Stored by geometry, so re-tuned tiers would list as separate entries.
struct ScoreboardView: View {
    @ObservedObject var scoreboard: Scoreboard
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingReset = false

    /// Modern configs the player has actually cleared at least once.
    private var playedModern: [GameConfig] {
        GameConfig.modernConfigs.filter { scoreboard.wins(for: $0) > 0 }
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("High Scores").font(.title2.bold())

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section("Classic", configs: GameConfig.classicConfigs)
                    if !playedModern.isEmpty {
                        section("Modern", configs: playedModern)
                    }
                }
            }
            .frame(maxHeight: 360)

            HStack {
                Button("Reset", role: .destructive) { confirmingReset = true }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 320)
        .confirmationDialog("Clear all high scores?", isPresented: $confirmingReset) {
            Button("Clear scores", role: .destructive) { scoreboard.reset() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func section(_ title: String, configs: [GameConfig]) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                Text("Cleared").font(.caption).foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .trailing)
                Text("Best").font(.caption).foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .trailing)
            }
            .padding(.vertical, 4)

            ForEach(configs, id: \.self) { config in
                row(config)
                if config != configs.last { Divider() }
            }
        }
    }

    private func row(_ config: GameConfig) -> some View {
        HStack {
            Text(config.label)
            Spacer()
            Text("\(scoreboard.wins(for: config))")
                .font(.body.monospaced())
                .frame(width: 70, alignment: .trailing)
            Group {
                if let best = scoreboard.best(for: config) {
                    Text(TimeFormat.mmsst(centiseconds: best)).font(.body.monospaced().bold())
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .frame(width: 72, alignment: .trailing)
        }
        .padding(.vertical, 10)
    }
}

/// App settings. Currently just appearance; more rows (e.g. language) slot in
/// under the same VStack later.
struct SettingsView: View {
    @ObservedObject var settings: Settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings").font(.title2.bold())

            VStack(alignment: .leading, spacing: 6) {
                Text("Appearance").font(.headline)
                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(AppearancePreference.allCases) { pref in
                        Text(pref.label).tag(pref)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 320)
    }
}
