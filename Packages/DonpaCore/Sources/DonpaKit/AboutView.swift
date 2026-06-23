import SwiftUI

/// App "About": name, version, and credits. Shown from the macOS app menu
/// ("About Donpa Squad") and from a row in the iOS Settings sheet — one shared
/// view so the two never drift.
public struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    public init() {}

    /// `CFBundleShortVersionString` (build) read from the main bundle, e.g.
    /// "0.1.0 (1)". Falls back gracefully if absent.
    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
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

    public var body: some View {
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

            Text("Version \(versionString)", bundle: .module)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)

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
            }

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
        .accessibilityElement(children: .contain)
    }

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
