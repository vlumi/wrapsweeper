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
                .frame(minWidth: 320, minHeight: 420)
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
