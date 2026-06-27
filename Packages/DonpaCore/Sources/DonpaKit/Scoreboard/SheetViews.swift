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
    @ObservedObject var settings: Settings
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
            content
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                // Sync control pinned to the bottom so it's always visible, not
                // buried under the scrolling stats.
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 0) {
                        Divider()
                        syncFooterControl
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                    .background(.bar)
                }
                .navigationTitle(Text("Service Record", bundle: .module))
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
            Text("Service Record", bundle: .module).font(.title2.bold())

            content  // sizes to content; capped by the sheet's maxHeight below

            Divider()
            // Footer: sync control on the left, Reset / Done on the right.
            HStack(spacing: 12) {
                syncFooterControl
                Spacer()
                Button(role: .destructive) {
                    confirmingReset = true
                } label: {
                    Text("Reset", bundle: .module)
                }
                Button {
                    dismiss()
                } label: {
                    Text("Done", bundle: .module)
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, Self.rowInset)  // align with the row text
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 14)  // rest of the side margin lives on the rows
        // Width is driven firmly (a sheet otherwise shrinks to content and never
        // widens for two columns). Height is a CAP only — the sheet sizes to its
        // content and only grows to `sheetHeight` (then the scores column scrolls),
        // so a short table doesn't leave a tall empty sheet.
        .frame(width: sheetWidth)
        .frame(maxHeight: sheetHeight)
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
    private var sheetHeight: CGFloat { min(1100, max(380, container.height * 0.94)) }
    /// Likewise for width, so a narrow window can't push the sheet off the sides.
    /// Cap is comfortably past the two-column breakpoint so a roomy window gives
    /// Career + High Scores side by side; a small window still shrinks to fit.
    private var sheetWidth: CGFloat { min(820, max(300, container.width * 0.9)) }
    #endif

    /// Gutter reserved to the right of the whole table so the scroll indicator
    /// sits clear of it — rows *and* their divider hairlines end before the bar.
    private static let scrollbarGutter: CGFloat = 16
    /// Horizontal breathing room inside each row, so the record-highlight band
    /// (and the rows generally) aren't flush against the text. Pulled in from the
    /// sheet's outer padding so the overall margin stays about the same.
    private static let rowInset: CGFloat = 10

    /// One scrolling sheet (no tabs): Career first, then High Scores, then the
    /// sync footer. On a wide enough sheet the two stat groups sit side by side;
    /// otherwise they stack. (A future Achievements section slots in after Career.)
    @ViewBuilder private var content: some View {
        // Decide columns from the known layout width (no GeometryReader — that's
        // greedy on height and would force a tall, half-empty sheet). The sheet
        // sizes to content; the scores column scrolls only once it exceeds the cap.
        if layoutWidth >= Self.twoColumnMinWidth {
            // Wide: Career is a fixed column (short, static); only the High Scores
            // ROWS scroll — its header stays pinned above them. Both top-aligned so
            // a short table doesn't stretch.
            HStack(alignment: .top, spacing: 28) {
                careerSection
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("Commendations")
                    ScrollView {
                        scoresRows
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.trailing, Self.scrollbarGutter)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            // Narrow: one scroll over both, stacked (headers scroll with content).
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    careerSection
                    scoresSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, Self.scrollbarGutter)
            }
        }
    }

    /// Width to base the column decision on. macOS knows the sheet width; iOS uses
    /// the presenting window (the sheet fills it on iPhone, is narrower on iPad).
    private var layoutWidth: CGFloat {
        #if os(macOS)
        return sheetWidth
        #else
        return available.width
        #endif
    }

    /// Below this width the two stat groups stack instead of going side-by-side.
    /// Generous so two columns only appear when each is comfortably wide (no label
    /// wrapping like "Aloittelija"/"Keskitaso").
    private static let twoColumnMinWidth: CGFloat = 680

    /// Lifetime totals. Deliberately NO win rate / loss ratio — raw, neutral counts
    /// (a win% only discourages); honest but never framed as "you lose most games".
    @ViewBuilder private var careerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Tour of Duty")
            if scoreboard.totalGamesPlayed > 0 {
                VStack(spacing: 0) {
                    statRow("Games played", Self.grouped(scoreboard.totalGamesPlayed))
                    Divider()
                    statRow("Tiles cleared", Self.grouped(scoreboard.totalTilesOpened))
                    Divider()
                    statRow("Flags placed", Self.grouped(scoreboard.totalFlagsPlaced))
                    Divider()
                    statRow("Mines disarmed", Self.grouped(scoreboard.totalMinesDisarmed))
                    Divider()
                    statRow("Mines hit", Self.grouped(scoreboard.totalMinesHit))
                    Divider()
                    statRow(
                        "Time played", Self.durationLabel(scoreboard.totalPlaytimeCentiseconds))
                }
            } else {
                Text("Play a game to start your career stats.", bundle: .module)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
        }
    }

    /// Per-board best time + clears, with the section header (used in the narrow
    /// single-scroll layout, where the header scrolls with the rows).
    @ViewBuilder private var scoresSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Commendations")
            scoresRows
        }
    }

    /// Just the score tables (no header) — for the wide layout where the header is
    /// pinned above the scroll. Classic always shows; Modern once played.
    @ViewBuilder private var scoresRows: some View {
        VStack(alignment: .leading, spacing: 16) {
            section("Classic", configs: GameConfig.classicConfigs)
            if !playedModern.isEmpty {
                section("Modern", configs: playedModern)
            }
        }
    }

    /// A bold section heading for the Career / High Scores groups.
    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title, bundle: .module)
            .font(.title3.bold())
            .padding(.horizontal, Self.rowInset)
    }

    /// Compact iCloud-sync control for the footer: a toggle with an inline status
    /// to its right. Opt-in (off by default). When on + signed out, the status is a
    /// tappable nudge that deep-links to system Settings (KVS has no in-app
    /// permission prompt — the most we can do is point there).
    @ViewBuilder private var syncFooterControl: some View {
        HStack(spacing: 8) {
            Toggle(isOn: $settings.syncScores) {
                Text("Sync", bundle: .module).font(.subheadline.weight(.medium))
            }
            .toggleStyle(.switch)
            .fixedSize()

            if settings.syncScores {
                if scoreboard.isCloudActive {
                    Label {
                        Text("via iCloud", bundle: .module)
                    } icon: {
                        Image(systemName: "checkmark.icloud")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Button {
                        openSystemSettings()
                    } label: {
                        Text("Sign into iCloud", bundle: .module).font(.caption.bold())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }
            } else {
                Text("This device only", bundle: .module)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
    }

    /// Deep-link to the system Settings/Preferences so the player can sign into
    /// iCloud (we can't toggle the system setting from inside the app).
    private func openSystemSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #elseif os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane")
        {
            NSWorkspace.shared.open(url)
        }
        #endif
    }

    private func statRow(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(label, bundle: .module)
            Spacer()
            Text(verbatim: value).font(.body.monospaced())
        }
        .padding(.vertical, 6)
        .padding(.horizontal, Self.rowInset)
    }

    /// Coarse human duration for lifetime playtime (hours/minutes, not the precise
    /// A count formatted with the locale's grouping separator (e.g. `1,234,567` /
    /// `1 234 567`), for the lifetime totals which can run large.
    static func grouped(_ value: Int) -> String { value.formatted(.number) }

    /// per-game m:ss.t). E.g. `14h 23m`, `45m`, `< 1m`.
    static func durationLabel(_ centiseconds: Int) -> String {
        let totalMinutes = centiseconds / 6000
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "< 1m"
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
            // Modern rows: the difficulty rank insignia in a fixed-width column
            // (so the size letters line up), then the size name. Classic rows show
            // their preset name.
            if let size = config.modernSize, let density = config.modernDensity {
                DensityInsignia.image(density)
                    .resizable().scaledToFit().frame(width: 30, height: 20)
                Text(verbatim: size.label)
            } else {
                Text(verbatim: config.label)  // already localized by GameConfig
            }
            Spacer()
            Text(verbatim: Self.grouped(scoreboard.wins(for: config)))
                .font(.body.monospaced())
                .frame(width: 56, alignment: .trailing)
            Group {
                if let progress = scoreboard.bestProgress(for: config) {
                    // Floor, not round: a 99.7%-cleared loss must not read "100%"
                    // (which would be indistinguishable from an actual clear).
                    // Only a genuine 1.0 shows 100%.
                    Text("\(Int((progress * 100).rounded(.down)))%").font(.body.monospaced())
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

            // iCloud score sync lives in the scoreboard's Career tab (where the
            // totals it affects are shown), not here. About lives on the title
            // screen's "i" button + the macOS app menu.
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
