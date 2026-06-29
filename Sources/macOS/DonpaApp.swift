import DonpaCore
import DonpaKit
import SwiftUI

@main
struct DonpaApp: App {
    @StateObject private var viewModel = GameViewModel()
    @StateObject private var scoreboard = Scoreboard(
        cloud: UbiquitousStatsStore(),
        syncEnabled: UserDefaults.standard.object(forKey: "donpa.syncScores") as? Bool ?? false)
    @StateObject private var settings = Settings()
    @StateObject private var navigator = Navigator()
    @State private var showingAbout = false

    var body: some Scene {
        WindowGroup {
            GameView(
                viewModel: viewModel, scoreboard: scoreboard, settings: settings,
                navigator: navigator
            )
            // Min size keeps the end-of-game result panel (square art + buttons)
            // from being clipped when the user shrinks the window.
            .frame(minWidth: 420, minHeight: 560)
            .onChange(of: viewModel.config) { _, config in
                WindowSizer.growToFit(for: config)
            }
            .onAppear {
                WindowSizer.growToFit(for: viewModel.config)
            }
            .sheet(isPresented: $showingAbout) { AboutView() }
        }
        .commands {
            // Replace the standard "About <app>" with our own panel.
            CommandGroup(replacing: .appInfo) {
                Button("About Donpa Squad") { showingAbout = true }
                    .disabled(modalOpen)
            }
            // Settings lives in the app menu at the standard ⌘, slot (no toolbar
            // gear on macOS). Presented as the in-window sheet via the navigator.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { navigator.showingSettings = true }
                    .keyboardShortcut(",", modifiers: .command)
                    .disabled(modalOpen)
            }
            CommandGroup(replacing: .newItem) {
                // New Game opens the config popup (pick mode/size, then Start);
                // Restart replays the same board; the difficulty items below jump
                // straight to a fresh game with a chosen classic config.
                Button("New Game…") { navigator.showingNewGame = true }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(modalOpen)
                Button("Restart Game") { viewModel.newGame() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(modalOpen)
                Button("Title Screen") {
                    // Pause + save (handled in GameContent), not discard.
                    navigator.homeRequested &+= 1
                }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(modalOpen)
            }
            CommandMenu("Game") {
                Button("High Scores") { navigator.showingScores = true }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(modalOpen)

                Divider()

                Button(
                    viewModel.inputMode == .flag
                        ? "Switch to Reveal Mode"
                        : "Switch to Flag Mode"
                ) {
                    viewModel.inputMode.toggle()
                }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(modalOpen)

                Divider()

                // ⌘0 toggles the corner minimap between its min and max size — it
                // pairs with ⌘+/⌘− as the "fit / actual-size" slot many apps use.
                Button("Toggle Minimap Size") { navigator.toggleMinimapRequested &+= 1 }
                    .keyboardShortcut("0", modifiers: .command)
                    .disabled(modalOpen)

                // ⌘+ / ⌘− zoom the board (about its centre). Bind zoom-in to the
                // "+" *character*, not a physical key: SwiftUI matches on the char
                // the keystroke produces, so this follows "+" wherever a layout puts
                // it — Finnish ⌘+ (its own key), US ⌘⇧=, JIS ⌘⇧;. Binding to "="
                // instead failed on Finnish, where "=" isn't on that key.
                Button("Zoom In") { navigator.zoomInRequested &+= 1 }
                    .keyboardShortcut("+", modifiers: .command)
                    .disabled(modalOpen)
                Button("Zoom Out") { navigator.zoomOutRequested &+= 1 }
                    .keyboardShortcut("-", modifiers: .command)
                    .disabled(modalOpen)

                Divider()

                classicButton(.beginner, key: "1")
                classicButton(.intermediate, key: "2")
                classicButton(.expert, key: "3")
            }
        }
    }

    /// True while any modal (a navigator sheet/popup, or the macOS About sheet) is
    /// presented — used to disable the menu commands and their keyboard shortcuts
    /// so they don't mutate or navigate the game hidden beneath the modal.
    private var modalOpen: Bool {
        navigator.isModalPresented || showingAbout
    }

    private func classicButton(_ preset: ClassicPreset, key: KeyEquivalent) -> some View {
        Button(preset.label) {
            settings.mode = .classic
            settings.classicPreset = preset
            viewModel.newGame(config: .classic(preset))
        }
        .keyboardShortcut(key, modifiers: .command)
        .disabled(modalOpen)
    }
}
