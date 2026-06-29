import DonpaCore
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// The high-score table: clears + best time per config. Classic always shows;
/// Modern appears once played (to avoid 15 empty rows). Stored by geometry.
struct ScoreboardView: View {
    @ObservedObject var scoreboard: Scoreboard
    @ObservedObject var settings: Settings
    /// Presenting window size, so the sheet grows with it. `.zero` → use the screen.
    var available: CGSize = .zero
    /// The config the player is currently on (the storageKey), so its row gets a
    /// persistent "you are here" marker. nil when opened from the title (browsing).
    var currentConfigKey: String?
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingReset = false

    /// Modern configs the player has played at all — a win or a recorded best
    /// progress from a loss.
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

    /// iOS: a NavigationStack with Reset / Done nav-bar items over the list. macOS:
    /// inline title + bottom buttons, window-sized.
    @ViewBuilder private var sheetChrome: some View {
        #if os(iOS)
        NavigationStack {
            content
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                // Sync control pinned to the bottom, not buried under the stats.
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 0) {
                        Divider()
                        SyncFooterControl(settings: settings, scoreboard: scoreboard)
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
            HStack(spacing: 12) {
                SyncFooterControl(settings: settings, scoreboard: scoreboard)
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
        // Width is driven firmly (else the sheet shrinks to content and won't widen
        // for two columns). Height is a cap only — the sheet sizes to content and
        // only grows to `sheetHeight` (then the scores column scrolls).
        .frame(width: sheetWidth)
        .frame(maxHeight: sheetHeight)
        #endif
    }

    #if os(macOS)
    /// Container to bound against: the presenting window, or the screen as a
    /// fallback before its size is known.
    private var container: CGSize {
        if available != .zero { return available }
        let h = NSScreen.main?.visibleFrame.height ?? 800
        let w = NSScreen.main?.visibleFrame.width ?? 1000
        return CGSize(width: w, height: h)
    }

    /// Tall in a big window, short in a small one, bounded so it never overflows.
    private var sheetHeight: CGFloat { min(1100, max(380, container.height * 0.94)) }
    /// Cap past the two-column breakpoint so a roomy window gives two columns; a
    /// small window still shrinks to fit.
    private var sheetWidth: CGFloat { min(820, max(300, container.width * 0.9)) }
    #endif

    /// Gutter at the right of the table so the scroll indicator sits clear of the
    /// rows and their dividers.
    private static let scrollbarGutter: CGFloat = 16
    /// Horizontal breathing room inside each row (and the record-highlight band).
    private static let rowInset: CGFloat = 10

    /// One scrolling sheet: Career, then High Scores, then the sync footer. Two
    /// columns when wide enough, otherwise stacked.
    @ViewBuilder private var content: some View {
        // Decide columns from the known layout width (no GeometryReader — greedy on
        // height, forcing a tall half-empty sheet).
        if layoutWidth >= Self.twoColumnMinWidth {
            // Wide: Career is a fixed column; only the High Scores rows scroll, its
            // header pinned. Top-aligned so a short table doesn't stretch.
            HStack(alignment: .top, spacing: 28) {
                careerSection
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("Commendations")
                    anchoredScroll {
                        scoresRows
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.trailing, Self.scrollbarGutter)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            // Narrow: one scroll over both, stacked (headers scroll with content).
            anchoredScroll {
                VStack(alignment: .leading, spacing: 24) {
                    careerSection
                    scoresSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, Self.scrollbarGutter)
            }
        }
    }

    /// A ScrollView that, when opened in-game (`currentConfigKey` set), jumps the
    /// current config's row into view — so you land on the board you're playing.
    /// Opened from the title (key nil) it stays at the top for plain browsing.
    @ViewBuilder private func anchoredScroll<Content: View>(
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        let inner = content()
        ScrollViewReader { proxy in
            ScrollView {
                inner
            }
            .onAppear {
                guard let key = currentConfigKey else { return }
                // A beat after layout so the target row exists before we scroll.
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(key, anchor: .center)
                    }
                }
            }
        }
    }

    /// Width for the column decision: the sheet width (macOS) or presenting window
    /// (iOS).
    private var layoutWidth: CGFloat {
        #if os(macOS)
        return sheetWidth
        #else
        return available.width
        #endif
    }

    /// Below this width the two stat groups stack. Generous so each column is
    /// comfortably wide before splitting (avoids label wrapping).
    private static let twoColumnMinWidth: CGFloat = 680

    /// Lifetime totals. Deliberately no win rate — raw, neutral counts (a win%
    /// only discourages).
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

    /// Score tables with the section header — the narrow layout, where the header
    /// scrolls with the rows.
    @ViewBuilder private var scoresSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Commendations")
            scoresRows
        }
    }

    /// Score tables without the header — the wide layout, header pinned above the
    /// scroll. Classic always shows; Modern once played.
    @ViewBuilder private var scoresRows: some View {
        VStack(alignment: .leading, spacing: 16) {
            section("Classic", configs: GameConfig.classicConfigs)
            if !playedModern.isEmpty {
                section("Modern", configs: playedModern)
            }
        }
    }

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title, bundle: .module)
            .font(.title3.bold())
            .padding(.horizontal, Self.rowInset)
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

    /// A count with the locale's grouping separator (e.g. `1,234,567`), for the
    /// large lifetime totals.
    static func grouped(_ value: Int) -> String { value.formatted(.number) }

    /// Coarse human duration for lifetime playtime (hours/minutes). E.g. `14h 23m`,
    /// `45m`, `< 1m`.
    static func durationLabel(_ centiseconds: Int) -> String {
        let totalMinutes = centiseconds / 6000
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        // Localized units (en "14h 23m" / fi "14 t 23 min" / ja "14時間23分").
        if h > 0 {
            return String(
                localized: "\(h)h \(m)m", bundle: .module,
                comment: "Playtime, hours+minutes: H hours M minutes")
        }
        if m > 0 {
            return String(
                localized: "\(m)m", bundle: .module, comment: "Playtime, minutes only: M minutes")
        }
        return String(
            localized: "< 1m", bundle: .module, comment: "Playtime under a minute")
    }

    private func section(_ title: LocalizedStringKey, configs: [GameConfig]) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title, bundle: .module).font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                Text("Cleared", bundle: .module).font(.caption).foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .trailing)
                Text("Best %", bundle: .module).font(.caption).foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .trailing)
                Text("Best", bundle: .module).font(.caption).foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .trailing)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, Self.rowInset)

            ForEach(configs, id: \.self) { config in
                ScoreRow(
                    scoreboard: scoreboard, config: config,
                    currentConfigKey: currentConfigKey, rowInset: Self.rowInset
                )
                .id(config.storageKey)  // scroll anchor for the current-config jump
                if config != configs.last { Divider() }
            }
        }
    }
}
