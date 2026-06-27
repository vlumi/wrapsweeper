import DonpaCore
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// App settings: appearance, toggle side, language.
struct SettingsView: View {
    @ObservedObject var settings: Settings
    @Environment(\.dismiss) private var dismiss
    /// The language in effect when this sheet appeared. Moving away from it needs a
    /// restart to switch, surfaced via `restartNotice`.
    @State private var launchLanguage: LanguagePreference?

    private var languageChanged: Bool {
        launchLanguage != nil && settings.language != launchLanguage
    }

    /// Measured content height, to size the iOS sheet to a compact card.
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        sheetChrome
            .onAppear { launchLanguage = settings.language }
            .animation(.easeInOut(duration: 0.2), value: languageChanged)
    }

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

            // Score sync lives in the scoreboard; About on the title screen.
        }
    }

    /// iOS: NavigationStack with a "Done" toolbar item + fit-content detent. macOS:
    /// inline title + bottom Done button.
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
        // +64 leaves room for the nav bar + grabber.
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

    /// A headline over its control(s).
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

    /// Tinted callout shown once the language picker changes: restart to switch.
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
