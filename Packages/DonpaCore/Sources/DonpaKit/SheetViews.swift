import DonpaCore
import SwiftUI

/// The high-score table: clears + best time per config. Classic configs always
/// show; Modern configs appear once they've been played (to avoid 15 empty
/// rows). Stored by geometry, so re-tuned tiers would list as separate entries.
struct ScoreboardView: View {
    @ObservedObject var scoreboard: Scoreboard
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingReset = false

    /// Modern configs the player has played at all — has a win *or* a recorded
    /// best progress from a loss (so partially-cleared hard boards still show).
    private var playedModern: [GameConfig] {
        GameConfig.modernConfigs.filter { scoreboard.record(for: $0) != nil }
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("High Scores", bundle: .module).font(.title2.bold())

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
                Button(role: .destructive) {
                    confirmingReset = true
                } label: {
                    Text("Reset", bundle: .module)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("Done", bundle: .module)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 320)
        .confirmationDialog(
            Text("Clear all high scores?", bundle: .module), isPresented: $confirmingReset
        ) {
            Button(role: .destructive) {
                scoreboard.reset()
            } label: {
                Text("Clear scores", bundle: .module)
            }
            Button(role: .cancel) {
            } label: {
                Text("Cancel", bundle: .module)
            }
        }
    }

    private func section(_ title: LocalizedStringKey, configs: [GameConfig]) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title, bundle: .module).font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                Text("Cleared", bundle: .module).font(.caption).foregroundStyle(.secondary)
                    .frame(width: 62, alignment: .trailing)
                Text("Best %", bundle: .module).font(.caption).foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
                Text("Best", bundle: .module).font(.caption).foregroundStyle(.secondary)
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
            Text(verbatim: config.label)  // already localized by GameConfig
            Spacer()
            Text("\(scoreboard.wins(for: config))")
                .font(.body.monospaced())
                .frame(width: 62, alignment: .trailing)
            Group {
                if let progress = scoreboard.bestProgress(for: config) {
                    Text("\(Int((progress * 100).rounded()))%").font(.body.monospaced())
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .frame(width: 52, alignment: .trailing)
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
    @State private var showingAbout = false
    /// The language in effect when this sheet appeared. If the picker moves away
    /// from it, the app needs a restart to actually switch — surfaced loudly.
    @State private var launchLanguage: LanguagePreference?

    private var languageChanged: Bool {
        launchLanguage != nil && settings.language != launchLanguage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings", bundle: .module).font(.title2.bold())

            VStack(alignment: .leading, spacing: 6) {
                Text("Appearance", bundle: .module).font(.headline)
                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(AppearancePreference.allCases) { pref in
                        Text(verbatim: pref.label).tag(pref)  // label localized in Settings
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Toggle side", bundle: .module).font(.headline)
                Picker("Toggle side", selection: $settings.handedness) {
                    ForEach(Handedness.allCases) { h in
                        Text(verbatim: h.label).tag(h)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Language", bundle: .module).font(.headline)
                Picker("Language", selection: $settings.language) {
                    ForEach(LanguagePreference.allCases) { lang in
                        Text(verbatim: lang.label).tag(lang)
                    }
                }
                .labelsHidden()
                if languageChanged {
                    restartNotice
                }
            }

            // macOS surfaces About via the app menu ("About Donpa Squad"); iOS
            // has no such menu, so expose it here in Settings.
            #if os(iOS)
            Button {
                showingAbout = true
            } label: {
                Label {
                    Text("About Donpa Squad", bundle: .module)
                } icon: {
                    Image(systemName: "info.circle")
                }
            }
            #endif

            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("Done", bundle: .module)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 320)
        .sheet(isPresented: $showingAbout) {
            AboutView()
        }
        .onAppear { launchLanguage = settings.language }
        .animation(.easeInOut(duration: 0.2), value: languageChanged)
    }

    /// Prominent notice shown once the language picker is changed: a tinted
    /// callout making clear the app must be restarted to switch language.
    private var restartNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Restart the app to change the language.", bundle: .module)
                .font(.callout.weight(.semibold))
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.orange.opacity(0.5), lineWidth: 1))
        .transition(.opacity)
    }
}
