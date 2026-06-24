import SwiftUI

/// App "About": name, version, and credits. Shown from the title screen's "i"
/// button (both platforms) and, on macOS, also the app menu ("About Donpa
/// Squad") — one shared view so the entry points never drift.
public struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    private var palette: Palette { Palette.resolved(for: colorScheme) }

    /// `CFBundleShortVersionString` (build) read from the main bundle, e.g.
    /// "0.1.0 (1)". Falls back gracefully if absent.
    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    /// The git commit the build was stamped with (`GitCommitSHA`, injected by
    /// Scripts/embed-commit-sha.sh at build time). Absent on builds made before
    /// that script existed (e.g. 0.1.0 (2)) — hidden when missing rather than
    /// showing a placeholder.
    private var commitSHA: String? {
        Bundle.main.infoDictionary?["GitCommitSHA"] as? String
    }

    /// Whether the UI is in Japanese. The app name and author name are the same
    /// entities written in two scripts (not translated text), so both pick their
    /// form from this rather than going through the string catalog.
    private var isJapanese: Bool {
        Bundle.module.preferredLocalizations.first?.hasPrefix("ja") ?? false
    }

    /// App name and author name in the script matching the UI: kana/kanji in
    /// Japanese, romaji elsewhere. Symmetric local choices, not catalog strings.
    private var appName: String { isJapanese ? "ドンパ隊" : "Donpa Squad" }
    private var authorName: String { isJapanese ? "三﨑ヴィッレ" : "Ville Misaki" }

    /// Measured natural height of the content, for the iOS fit-content detent
    /// (same compact-card treatment as the Settings / Scores sheets).
    @State private var contentHeight: CGFloat = 0

    public var body: some View {
        chrome
            .background(palette.pageBackground.ignoresSafeArea())
            .accessibilityElement(children: .contain)
    }

    /// The shared credits content (no chrome / Done button).
    private var content: some View {
        VStack(spacing: 16) {
            appIcon
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 8, y: 3)

            VStack(spacing: 4) {
                Text(verbatim: appName).font(.title2.bold())
                // Show the kana subtitle only when the title isn't already kana.
                if !isJapanese {
                    Text(verbatim: "ドンパ隊").font(.title3).foregroundStyle(.secondary)
                }
            }

            Text("A Minesweeper game for Apple platforms.", bundle: .module)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Version in a rounded badge — the same pill language as the in-game
            // config badge, so About reads as part of the app, not a system sheet.
            Text("Version \(versionString)", bundle: .module)
                .font(.footnote.monospaced().weight(.semibold))
                .foregroundStyle(palette.counter)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(palette.counter.opacity(0.15)))
                .overlay(Capsule().stroke(palette.counter.opacity(0.3), lineWidth: 1))

            // The build's git commit, when stamped in — small and quiet, for
            // matching a TestFlight/App Store build back to its source.
            if let sha = commitSHA {
                Text(verbatim: sha)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }

            Divider().frame(maxWidth: 220)

            VStack(spacing: 6) {
                Text(verbatim: "© 2026 \(authorName)").font(.footnote)
                Text(verbatim: "MIT License").font(.footnote).foregroundStyle(.secondary)
                Link(destination: URL(string: "https://github.com/vlumi/donpa")!) {
                    Label {
                        Text(verbatim: "github.com/vlumi/donpa")
                    } icon: {
                        Image(systemName: "link")
                    }
                    .font(.footnote)
                }
                .tint(palette.counter)
            }
        }
    }

    /// iOS wraps the content in a NavigationStack with a toolbar "Done" and a
    /// fit-content detent — matching the Settings / Scores sheets. macOS keeps the
    /// inline layout with a bottom Done button (right in a macOS sheet).
    @ViewBuilder private var chrome: some View {
        #if os(iOS)
        NavigationStack {
            content
                .padding(28)
                .frame(maxWidth: .infinity)
                .background(heightReader)
                .navigationTitle(Text("About", bundle: .module))
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
        .presentationDetents(contentHeight > 0 ? [.height(contentHeight + 64)] : [.medium])
        #else
        VStack(spacing: 16) {
            content
            Button {
                dismiss()
            } label: {
                Text("Done", bundle: .module)
            }
            .keyboardShortcut(.defaultAction)
            .padding(.top, 4)
        }
        .padding(28)
        .frame(minWidth: 300)
        #endif
    }

    #if os(iOS)
    /// Reports the content's natural height (for the iOS fit-content detent).
    private var heightReader: some View {
        GeometryReader { geo in
            Color.clear.onAppear { contentHeight = geo.size.height }
                .onChangeCompat(of: geo.size.height) { contentHeight = $0 }
        }
    }
    #endif

    /// The app icon from the asset catalog. The 1024 icon image is the only one
    /// directly loadable by name; the `AppIcon` set itself isn't a UI image.
    @ViewBuilder private var appIcon: some View {
        #if os(macOS)
        if let nsImage = NSApplication.shared.applicationIconImage {
            Image(nsImage: nsImage).resizable()
        } else {
            placeholderIcon
        }
        #else
        if let ui = uiAppIcon {
            Image(uiImage: ui).resizable()
        } else {
            placeholderIcon
        }
        #endif
    }

    private var placeholderIcon: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.secondary.opacity(0.2))
            .overlay(Image(systemName: "flag.fill").font(.largeTitle).foregroundStyle(.secondary))
    }

    #if os(iOS)
    /// The primary app icon image, dug out of the bundle's icon dictionary.
    private var uiAppIcon: UIImage? {
        guard
            let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
            let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
            let files = primary["CFBundleIconFiles"] as? [String],
            let name = files.last
        else { return nil }
        return UIImage(named: name)
    }
    #endif
}
