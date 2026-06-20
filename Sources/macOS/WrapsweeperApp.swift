import SwiftUI
import WrapsweeperCore
import WrapsweeperKit

@main
struct WrapsweeperApp: App {
    @StateObject private var viewModel = GameViewModel()
    @StateObject private var scoreboard = Scoreboard()
    @StateObject private var settings = Settings()

    var body: some Scene {
        WindowGroup {
            GameView(viewModel: viewModel, scoreboard: scoreboard, settings: settings)
                .frame(minWidth: 360, minHeight: 480)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Game") { viewModel.newGame() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu("Game") {
                Button(
                    viewModel.inputMode == .flag
                        ? "Switch to Reveal Mode"
                        : "Switch to Flag Mode"
                ) {
                    viewModel.inputMode.toggle()
                }
                .keyboardShortcut("f", modifiers: .command)

                Divider()

                ForEach(Array(Difficulty.presets.enumerated()), id: \.element) { index, d in
                    Button(d.name) { viewModel.newGame(difficulty: d) }
                        .keyboardShortcut(
                            KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
            }
        }
    }
}
