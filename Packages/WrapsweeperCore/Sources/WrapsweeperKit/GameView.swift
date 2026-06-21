import SpriteKit
import SwiftUI
import WrapsweeperCore

/// The full game surface: a status bar over a pannable/zoomable SpriteKit board.
/// Hosts a single long-lived `BoardScene`, which owns all board input (tap,
/// flag, chord, pan, zoom) natively; this view only renders chrome.
/// Thin wrapper that owns the stores and applies the user's appearance choice.
/// `.preferredColorScheme` is applied HERE so the descendant `GameContent` reads
/// the resolved scheme via `@Environment(\.colorScheme)` — a view cannot observe
/// a scheme it forces on itself, so the read must happen below the modifier.
public struct GameView: View {
    @StateObject private var viewModel: GameViewModel
    @StateObject private var scoreboard: Scoreboard
    @StateObject private var settings: Settings
    @State private var scene: BoardScene

    public init(config: GameConfig = .classic(.beginner)) {
        self.init(
            viewModel: GameViewModel(config: config),
            scoreboard: Scoreboard(),
            settings: Settings())
    }

    /// Use this when the host (e.g. the macOS menu bar) needs to drive the same
    /// view model that the board renders.
    public init(viewModel: GameViewModel, scoreboard: Scoreboard, settings: Settings) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _scoreboard = StateObject(wrappedValue: scoreboard)
        _settings = StateObject(wrappedValue: settings)
        _scene = State(initialValue: BoardScene(viewModel: viewModel))
    }

    public var body: some View {
        GameContent(viewModel: viewModel, scoreboard: scoreboard, settings: settings, scene: scene)
            .preferredColorScheme(settings.appearance.colorScheme)
    }
}

/// The actual game surface. Lives below `GameView`'s `.preferredColorScheme`, so
/// its `@Environment(\.colorScheme)` is the effective appearance for all of
/// system/light/dark — the single source the chrome and the SKScene both use.
private struct GameContent: View {
    @ObservedObject var viewModel: GameViewModel
    @ObservedObject var scoreboard: Scoreboard
    @ObservedObject var settings: Settings
    let scene: BoardScene

    @State private var showingScores = false
    @State private var showingSettings = false
    @Environment(\.colorScheme) private var colorScheme

    /// One resolved scheme for both the chrome and the scene. Driven by the
    /// user's setting; `.system` reads the real OS appearance (see
    /// `resolvedScheme`). `colorScheme` is only the iOS fallback, but reading it
    /// also re-runs `body` when the OS appearance flips while on System.
    private var scheme: ColorScheme {
        settings.appearance.resolvedScheme(systemFallback: colorScheme)
    }
    private var palette: Palette { .resolved(for: scheme) }

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            // Palette passed as a value: BoardView's updateUIView/NSView pushes
            // it to the scene whenever the resolved scheme changes — reliable
            // where .onChange on the SwiftUI side was not.
            BoardView(scene: scene, palette: palette, inputMode: viewModel.inputMode)
        }
        .background(palette.pageBackground)
        .onAppear {
            // Restore the persisted board selection on launch.
            if viewModel.config != settings.currentConfig {
                viewModel.newGame(config: settings.currentConfig)
            }
        }
        .onChange(of: viewModel.lastWin?.seconds) { _ in handleWin() }
        .sheet(isPresented: $showingScores) {
            ScoreboardView(scoreboard: scoreboard)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(settings: settings)
        }
    }

    /// When a win lands, record the time (the store keeps it only if it's a
    /// new best). Opens the scoreboard so the player sees the result.
    private func handleWin() {
        guard let win = viewModel.lastWin else { return }
        if scoreboard.submit(win.seconds, for: win.config) {
            showingScores = true
        }
    }

    // MARK: Status bar

    private var statusBar: some View {
        // Three equal-width zones keep the new-game button truly centred without
        // overlapping the side controls. Counters get layout priority so they
        // shrink (never vanish) when the window gets very narrow; the icon
        // buttons hold a fixed size.
        HStack(spacing: 6) {
            HStack(spacing: 8) {
                counter(label: "⚑", value: viewModel.flagsRemaining)
                modeToggle
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)

            newGameButton

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                iconButton("trophy", help: "High scores") { showingScores = true }
                iconButton("gearshape", help: "Settings") { showingSettings = true }
                counter(label: "⏱", value: viewModel.elapsedSeconds)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .safeAreaInset(edge: .bottom, spacing: 0) { difficultyPicker }
        .background(palette.statusBar)
    }

    /// New game. A restart symbol tinted by game state (neutral / won / lost),
    /// so it stays expressive without the emoji face crowding the other icons.
    private var newGameButton: some View {
        Button(action: { viewModel.newGame() }) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(newGameTint)
        }
        .buttonStyle(.plain)
        .help("New game")
    }

    private var newGameTint: Color {
        // Neutral while idle/playing; colour is reserved for the outcome so it
        // can't be mistaken for the (red) loss state.
        switch viewModel.status {
        case .won: return .green
        case .lost: return .red
        case .notStarted, .playing: return .secondary
        }
    }

    private func iconButton(_ systemName: String, help: String, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// Toggle between reveal- and flag-mode for plain taps. The icon shows the
    /// CURRENT mode (what a tap will do), tinted when in flag mode so it's
    /// obvious you've armed flagging.
    private var modeToggle: some View {
        Button(action: { viewModel.inputMode.toggle() }) {
            Image(systemName: viewModel.inputMode == .flag ? "flag.fill" : "hand.tap.fill")
                .font(.system(size: 18))
                .foregroundStyle(viewModel.inputMode == .flag ? Color.orange : .secondary)
                .frame(width: 40, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            viewModel.inputMode == .flag
                                ? palette.modeFlagTint : palette.modeRevealTint)
                )
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.space, modifiers: [])
        .help(
            viewModel.inputMode == .flag
                ? "Flag mode — tap flags (Space)"
                : "Reveal mode — tap reveals (Space)")
    }

    private func counter(label: String, value: Int) -> some View {
        HStack(spacing: 3) {
            Text(label)
            Text(String(format: "%03d", max(0, value)))
                .font(.system(.title3, design: .monospaced).weight(.bold))
                .foregroundStyle(palette.counter)
        }
        // Shrink to fit very narrow windows rather than clipping or pushing the
        // timer out of the bar entirely.
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .layoutPriority(1)
    }

    /// The bottom configuration bar: a Classic/Modern mode switch over the
    /// matching board picker (3 classic presets, or Size × Density for Modern).
    /// Changing any control starts a new game with the implied config.
    private var difficultyPicker: some View {
        VStack(spacing: 8) {
            Picker("Mode", selection: modeBinding) {
                ForEach(GameMode.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            switch settings.mode {
            case .classic:
                Picker("Difficulty", selection: classicBinding) {
                    ForEach(ClassicPreset.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            case .modern:
                Picker("Size", selection: sizeBinding) {
                    ForEach(BoardSize.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                Picker("Difficulty", selection: densityBinding) {
                    ForEach(Density.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // Each binding writes the Settings selection, then starts a new game on the
    // resulting config so the board reflects the choice immediately.
    private var modeBinding: Binding<GameMode> {
        Binding(
            get: { settings.mode },
            set: {
                settings.mode = $0
                viewModel.newGame(config: settings.currentConfig)
            })
    }
    private var classicBinding: Binding<ClassicPreset> {
        Binding(
            get: { settings.classicPreset },
            set: {
                settings.classicPreset = $0
                viewModel.newGame(config: settings.currentConfig)
            })
    }
    private var sizeBinding: Binding<BoardSize> {
        Binding(
            get: { settings.modernSize },
            set: {
                settings.modernSize = $0
                viewModel.newGame(config: settings.currentConfig)
            })
    }
    private var densityBinding: Binding<Density> {
        Binding(
            get: { settings.modernDensity },
            set: {
                settings.modernDensity = $0
                viewModel.newGame(config: settings.currentConfig)
            })
    }
}

/// The high-score table: clears + best time per config. Classic configs always
/// show; Modern configs appear once they've been played (to avoid 15 empty
/// rows). Stored by geometry, so re-tuned tiers would list as separate entries.
struct ScoreboardView: View {
    @ObservedObject var scoreboard: Scoreboard
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingReset = false

    /// Modern configs the player has actually cleared at least once.
    private var playedModern: [GameConfig] {
        GameConfig.modernConfigs.filter { scoreboard.wins(for: $0) > 0 }
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("High Scores").font(.title2.bold())

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section("Classic", configs: GameConfig.classicConfigs)
                    if !playedModern.isEmpty {
                        section("Modern", configs: playedModern)
                    }
                }
            }
            .frame(maxHeight: 360)

            HStack {
                Button("Reset", role: .destructive) { confirmingReset = true }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 320)
        .confirmationDialog("Clear all high scores?", isPresented: $confirmingReset) {
            Button("Clear scores", role: .destructive) { scoreboard.reset() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func section(_ title: String, configs: [GameConfig]) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                Text("Cleared").font(.caption).foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .trailing)
                Text("Best").font(.caption).foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .trailing)
            }
            .padding(.vertical, 4)

            ForEach(configs, id: \.self) { config in
                row(config)
                if config != configs.last { Divider() }
            }
        }
    }

    private func row(_ config: GameConfig) -> some View {
        HStack {
            Text(config.label)
            Spacer()
            Text("\(scoreboard.wins(for: config))")
                .font(.body.monospaced())
                .frame(width: 70, alignment: .trailing)
            Group {
                if let best = scoreboard.best(for: config) {
                    Text(String(format: "%03ds", best)).font(.body.monospaced().bold())
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .frame(width: 60, alignment: .trailing)
        }
        .padding(.vertical, 10)
    }
}

/// App settings. Currently just appearance; more rows (e.g. language) slot in
/// under the same VStack later.
struct SettingsView: View {
    @ObservedObject var settings: Settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings").font(.title2.bold())

            VStack(alignment: .leading, spacing: 6) {
                Text("Appearance").font(.headline)
                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(AppearancePreference.allCases) { pref in
                        Text(pref.label).tag(pref)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 320)
    }
}
