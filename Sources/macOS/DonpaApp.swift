import DonpaCore
import DonpaKit
import SwiftUI

@main
struct DonpaApp: App {
    @StateObject private var viewModel = GameViewModel()
    @StateObject private var scoreboard = Scoreboard()
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
                WindowSizer.growToFit(forBoard: config.width, by: config.height)
            }
            .onAppear {
                WindowSizer.growToFit(
                    forBoard: viewModel.config.width, by: viewModel.config.height)
            }
            .sheet(isPresented: $showingAbout) { AboutView() }
        }
        .commands {
            // Replace the standard "About <app>" with our own panel.
            CommandGroup(replacing: .appInfo) {
                Button("About Donpa Squad") { showingAbout = true }
            }
            // Settings lives in the app menu at the standard ⌘, slot (no toolbar
            // gear on macOS). Presented as the in-window sheet via the navigator.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { navigator.showingSettings = true }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .newItem) {
                // New Game opens the config popup (pick mode/size, then Start);
                // Restart replays the same board; the difficulty items below jump
                // straight to a fresh game with a chosen classic config.
                Button("New Game…") { navigator.showingNewGame = true }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Restart Game") { viewModel.newGame() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Title Screen") {
                    viewModel.newGame()  // returning to title resets the board
                    navigator.showingTitle = true
                }
                .keyboardShortcut("t", modifiers: .command)
            }
            CommandMenu("Game") {
                Button("High Scores") { navigator.showingScores = true }
                    .keyboardShortcut("s", modifiers: [.command, .shift])

                Divider()

                Button(
                    viewModel.inputMode == .flag
                        ? "Switch to Reveal Mode"
                        : "Switch to Flag Mode"
                ) {
                    viewModel.inputMode.toggle()
                }
                .keyboardShortcut("f", modifiers: .command)

                Divider()

                classicButton(.beginner, key: "1")
                classicButton(.intermediate, key: "2")
                classicButton(.expert, key: "3")
            }
        }
    }

    private func classicButton(_ preset: ClassicPreset, key: KeyEquivalent) -> some View {
        Button(preset.label) {
            settings.mode = .classic
            settings.classicPreset = preset
            viewModel.newGame(config: .classic(preset))
        }
        .keyboardShortcut(key, modifiers: .command)
    }
}
