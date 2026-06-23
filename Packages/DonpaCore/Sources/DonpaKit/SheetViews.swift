import DonpaCore
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// The high-score table: clears + best time per config. Classic configs always
/// show; Modern configs appear once they've been played (to avoid 15 empty
/// rows). Stored by geometry, so re-tuned tiers would list as separate entries.
struct ScoreboardView: View {
    @ObservedObject var scoreboard: Scoreboard
    /// Size of the presenting window, so the sheet grows with it and never
    /// overflows. `.zero` → fall back to the screen.
    var available: CGSize = .zero
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingReset = false

    /// Modern configs the player has played at all — has a win *or* a recorded
    /// best progress from a loss (so partially-cleared hard boards still show).
    private var playedModern: [GameConfig] {
        GameConfig.modernConfigs.filter { scoreboard.record(for: $0) != nil }
    }

    var body: some View {
        sheetChrome
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

    /// iOS: a NavigationStack with Reset / Done as nav-bar items (chrome, not
    /// content) over the scrolling list. macOS: the inline title + bottom buttons,
    /// window-sized so the sheet grows with the window without overflowing.
    @ViewBuilder private var sheetChrome: some View {
        #if os(iOS)
        NavigationStack {
            scoreList
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .navigationTitle(Text("High Scores", bundle: .module))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .destructiveAction) {
                        Button(role: .destructive) {
                            confirmingReset = true
                        } label: {
                            Text("Reset", bundle: .module)
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Text("Done", bundle: .module)
                        }
                        .accessibilityIdentifier("sheet.done")
                    }
                }
        }
        #else
        VStack(spacing: 16) {
            Text("High Scores", bundle: .module).font(.title2.bold())

            scoreList
                .frame(maxHeight: .infinity)

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
            .padding(.horizontal, Self.rowInset)  // align buttons with the row text
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 14)  // rest of the side margin lives on the rows
        // Size to a bounded fraction of the available height so the sheet grows
        // on a big screen but never overflows a small window. (A sheet sizes to
        // its content, so we drive the height explicitly rather than fill.)
        .frame(maxWidth: sheetWidth, maxHeight: sheetHeight)
        .frame(minWidth: min(340, sheetWidth), minHeight: min(360, sheetHeight))
        #endif
    }

    #if os(macOS)
    /// Container size to bound against: the presenting window, or the screen as a
    /// fallback before the window size is known. (macOS only — iOS uses a
    /// NavigationStack sheet that sizes itself.)
    private var container: CGSize {
        if available != .zero { return available }
        let h = NSScreen.main?.visibleFrame.height ?? 800
        let w = NSScreen.main?.visibleFrame.width ?? 1000
        return CGSize(width: w, height: h)
    }

    /// Tall in a big window, short in a small one — bounded so it never overflows.
    private var sheetHeight: CGFloat { min(760, max(360, container.height * 0.85)) }
    /// Likewise for width, so a narrow window can't push the sheet off the sides.
    private var sheetWidth: CGFloat { min(440, max(300, container.width * 0.9)) }
    #endif

    /// Gutter reserved to the right of the whole table so the scroll indicator
    /// sits clear of it — rows *and* their divider hairlines end before the bar.
    private static let scrollbarGutter: CGFloat = 16
    /// Horizontal breathing room inside each row, so the record-highlight band
    /// (and the rows generally) aren't flush against the text. Pulled in from the
    /// sheet's outer padding so the overall margin stays about the same.
    private static let rowInset: CGFloat = 10

    private var scoreList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                section("Classic", configs: GameConfig.classicConfigs)
                if !playedModern.isEmpty {
                    section("Modern", configs: playedModern)
                }
            }
            .padding(.trailing, Self.scrollbarGutter)
        }
    }

    private func section(_ title: LocalizedStringKey, configs: [GameConfig]) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title, bundle: .module).font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                Text("Cleared", bundle: .module).font(.caption).foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .trailing)
                Text("Best %", bundle: .module).font(.caption).foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
                Text("Best", bundle: .module).font(.caption).foregroundStyle(.secondary)
                    .frame(width: 68, alignment: .trailing)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, Self.rowInset)

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
                .frame(width: 56, alignment: .trailing)
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
            .frame(width: 68, alignment: .trailing)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, Self.rowInset)
        .background(rowHighlight(for: config))
    }

    /// Tinted band behind the row whose record was just set, so a fresh best
    /// stands out when the scoreboard opens. Persists until the next game ends.
    @ViewBuilder private func rowHighlight(for config: GameConfig) -> some View {
        if scoreboard.recentRecord == config.storageKey {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.18))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(0.5)))
        }
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

    /// Measured natural height of the content, used to size the iOS sheet to fit
    /// (a compact card) rather than the default near-fullscreen page sheet.
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        sheetChrome
            .sheet(isPresented: $showingAbout) {
                AboutView()
            }
            .onAppear { launchLanguage = settings.language }
            .animation(.easeInOut(duration: 0.2), value: languageChanged)
    }

    /// The settings rows, shared by both platforms.
    private var settingsList: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingRow("Appearance") {
                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(AppearancePreference.allCases) { pref in
                        Text(verbatim: pref.label).tag(pref)  // label localized in Settings
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            settingRow("Toggle side") {
                Picker("Toggle side", selection: $settings.handedness) {
                    ForEach(Handedness.allCases) { h in
                        Text(verbatim: h.label).tag(h)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            settingRow("Language") {
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
        }
    }

    /// iOS wraps the rows in a NavigationStack with a "Done" toolbar item (reads
    /// as chrome, not content) and a fit-content detent. macOS keeps the inline
    /// title + bottom Done button, which look right in a macOS sheet.
    @ViewBuilder private var sheetChrome: some View {
        #if os(iOS)
        NavigationStack {
            settingsList
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(heightReader)
                .navigationTitle(Text("Settings", bundle: .module))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Text("Done", bundle: .module)
                        }
                        .accessibilityIdentifier("sheet.done")
                    }
                }
        }
        // Size the sheet to its content (compact card) instead of the default
        // near-fullscreen page sheet. +64 leaves room for the nav bar + grabber.
        .presentationDetents(contentHeight > 0 ? [.height(contentHeight + 64)] : [.medium])
        #else
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings", bundle: .module).font(.title2.bold())
            settingsList
            Divider()
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
        #endif
    }

    /// A labelled settings row: a headline over its control(s).
    private func settingRow<Content: View>(
        _ title: LocalizedStringKey, @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title, bundle: .module).font(.headline)
            content()
        }
    }

    /// Reports the content's natural height (for the iOS fit-content detent).
    private var heightReader: some View {
        GeometryReader { geo in
            Color.clear.onAppear { contentHeight = geo.size.height }
                .onChangeCompat(of: geo.size.height) { contentHeight = $0 }
        }
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
