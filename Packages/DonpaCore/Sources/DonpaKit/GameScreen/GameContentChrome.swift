import DonpaCore
import SwiftUI

/// The in-game action buttons, in their fixed far-edge → toggle order.
enum GameAction: Hashable { case home, retry, pause, minimap }

/// The in-game chrome for `GameContent`: the top metrics strip, the board + its
/// control strip (actions + flag toggle), and the pause overlay.
extension GameContent {
    // MARK: Board + control strip

    var leftHanded: Bool { settings.handedness == .left }

    /// The board plus the control strip (actions + flag toggle in the handed
    /// corner). The strip sits below or beside the board (never overlapping); the
    /// board takes the rest and the scene fits the grid into it. The strip stays
    /// visible after the game ends so the actions remain reachable.
    var boardArea: some View {
        GeometryReader { geo in
            // Put the strip where the board leaves the most room: window wider than
            // the board → side strip, else bottom strip.
            let windowAspect = geo.size.width / max(geo.size.height, 1)
            let boardAspect = CGFloat(viewModel.boardWidth) / CGFloat(max(viewModel.boardHeight, 1))
            let sideStrip = windowAspect > boardAspect

            if sideStrip {
                HStack(spacing: 0) {
                    if leftHanded { sideControlStrip.frame(width: 108) }
                    board
                    if !leftHanded { sideControlStrip.frame(width: 108) }
                }
            } else {
                VStack(spacing: 0) {
                    board
                    bottomControlStrip.frame(height: 84)
                }
            }
        }
    }

    /// The dig/flag toggle. Always present (stable control set), disabled + dimmed
    /// once the board is finished.
    var toggleControl: some View {
        modeToggle
            .disabled(!gameInProgress)
            .opacity(gameInProgress ? 1 : 0.4)
    }

    /// Bottom strip: flag toggle pinned to the handed end (under the thumb), actions
    /// to the opposite end, one spacer between.
    var bottomControlStrip: some View {
        HStack(spacing: 8) {
            if leftHanded { toggleControl; Spacer(minLength: 8) }
            actionButtons(vertical: false)
            if !leftHanded { Spacer(minLength: 8); toggleControl }
        }
        .padding(.horizontal, 12)
    }

    /// Side strip: actions at the top, flag toggle at the bottom for thumb reach.
    var sideControlStrip: some View {
        VStack(spacing: 8) {
            actionButtons(vertical: true)
            Spacer(minLength: 8)
            toggleControl
        }
        .padding(.vertical, 12)
    }

    var board: some View {
        BoardView(
            scene: scene, palette: palette, inputMode: viewModel.inputMode,
            // Custom reveal/flag cursor only during a live, non-paused game; the
            // normal arrow elsewhere (title, result panel, finished board, paused).
            boardCursorActive: gameInProgress && !navigator.showingTitle && !viewModel.isPaused,
            showMinimap: settings.showMinimap
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Per-cell VoiceOver is a future task; for now announce a summary.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Board", bundle: .module))
        .accessibilityValue(boardSummary)
        .accessibilityIdentifier("game.board")
        .overlay { mangaPanel }
        .overlay { pauseOverlay }
        .overlay { processingOverlay }
        .animation(.easeInOut(duration: 0.2), value: viewModel.isPaused)
        .animation(.easeInOut(duration: 0.15), value: showProcessing)
        .clipped()  // keep the dimmed backdrop within the board's bounds
    }

    /// Shown while a reveal/chord/new-board computes off the main thread (input is
    /// gated meanwhile): a dim wash + centred spinner, making "not now" obvious.
    @ViewBuilder var processingOverlay: some View {
        if showProcessing {
            ZStack {
                Rectangle()
                    .fill(palette.pageBackground.opacity(0.4))
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Working…", bundle: .module)
                        .font(.headline)
                        .foregroundStyle(palette.counter)
                }
                .padding(24)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
            .transition(.opacity)
            .allowsHitTesting(false)  // input is gated in the model
        }
    }

    /// Covers the board while paused; tap (or the strip's resume) continues. Blurs
    /// rather than blacks out so it reads as "paused", not "blank".
    @ViewBuilder var pauseOverlay: some View {
        if viewModel.isPaused {
            GeometryReader { geo in
                ZStack {
                    // Blur hides the board; the pause art sits on top.
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay(palette.pageBackground.opacity(0.5))
                    // Sized like the result panel (off the shorter window dimension,
                    // clamped) so they match; reserve room so panel + hint stay
                    // grouped and centred.
                    let shorter = min(geo.size.width, geo.size.height)
                    let panelW = min(max(shorter * 0.82, 220), 900)
                    VStack(spacing: 12) {
                        Image("PanelPause", bundle: .module)
                            .resizable()
                            .interpolation(.high)
                            .antialiased(true)
                            .scaledToFit()
                            .frame(
                                maxWidth: min(panelW, geo.size.width - 24),
                                maxHeight: geo.size.height - 80
                            )
                            .shadow(color: .black.opacity(0.35), radius: 14, y: 5)
                        Text("Tap to resume", bundle: .module)
                            .font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { viewModel.resume() }
            .transition(.opacity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Paused", bundle: .module))
            .accessibilityHint(Text("Tap to resume", bundle: .module))
            .accessibilityIdentifier("game.paused")
        }
    }

    /// The in-game actions, far-edge → toggle: Home (furthest, hardest to mis-tap),
    /// Retry, then Pause nearest the thumb. Mirrored for a left-handed strip so
    /// Pause stays next to the toggle. A row in the bottom strip, a column in the side.
    @ViewBuilder
    func actionButtons(vertical: Bool) -> some View {
        let layout =
            vertical
            ? AnyLayout(VStackLayout(spacing: 16)) : AnyLayout(HStackLayout(spacing: 16))
        // Vertical (toggle-at-bottom) matches top→bottom directly; the horizontal
        // strip reverses only when the toggle is on the LEFT.
        let reverse = !vertical && leftHanded
        let ordered = reverse ? Array(actionOrder.reversed()) : actionOrder
        layout {
            ForEach(ordered, id: \.self) { action in
                actionView(action)
            }
        }
    }

    /// Fixed action sequence (so the row never reflows); Pause/Minimap disable when
    /// they don't apply.
    private var actionOrder: [GameAction] { [.home, .retry, .pause, .minimap] }

    @ViewBuilder
    private func actionView(_ action: GameAction) -> some View {
        switch action {
        case .home:
            actionButton(.home, help: "Home") { navigator.homeRequested &+= 1 }
                .accessibilityIdentifier("game.home")
        case .retry:
            actionButton(.retry, help: "Retry", tint: newGameTint) { viewModel.newGame() }
        case .pause:
            // Pause/Resume toggle: shows Play while paused. Enabled while live
            // (playing or paused), dimmed otherwise.
            let paused = viewModel.isPaused
            let live = viewModel.status == .playing
            actionButton(
                paused ? .play : .pause, help: paused ? "Resume" : "Pause"
            ) {
                if paused { viewModel.resume() } else { viewModel.pause() }
            }
            .disabled(!live && !paused)
            .opacity(live || paused ? 1 : 0.4)
            .accessibilityIdentifier("game.pause")
        case .minimap:
            // Toggle the corner minimap; tint reflects its own on/off state (not
            // `newGameTint`, the outcome colour). Only meaningful when the board
            // exceeds the viewport.
            mapButton(
                .minimap, help: "Overview map", id: "game.minimap",
                tint: settings.showMinimap ? palette.counter : .secondary
            ) { settings.showMinimap.toggle() }
        }
    }

    /// A toolbar button for a map control: disabled + dimmed when the board fits.
    @ViewBuilder
    private func mapButton(
        _ symbol: MangaIcon.Symbol, help: LocalizedStringKey, id: String,
        tint: Color = .secondary, action: @escaping () -> Void
    ) -> some View {
        let available = viewModel.boardExceedsViewport
        actionButton(symbol, help: help, tint: tint, action: action)
            .disabled(!available)
            .opacity(available ? 1 : 0.4)
            .accessibilityIdentifier(id)
    }

    func actionButton(
        _ symbol: MangaIcon.Symbol, help: LocalizedStringKey, tint: Color = .secondary,
        action: @escaping () -> Void
    ) -> some View {
        let label = Text(help, bundle: .module)
        return Button(action: action) {
            MangaIcon(symbol: symbol, size: 38, tint: tint)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    /// Spoken game state, used as the new-game button's accessibility value and
    /// the board's status summary.
    var statusDescription: String {
        switch viewModel.status {
        case .won: return String(localized: "Won", bundle: .module)
        case .lost: return String(localized: "Lost", bundle: .module)
        case .playing: return String(localized: "In progress", bundle: .module)
        case .notStarted: return String(localized: "Ready", bundle: .module)
        }
    }

    /// VoiceOver summary of the board: config, size, mines remaining, and state.
    var boardSummary: String {
        let label = viewModel.config.label
        let width = viewModel.boardWidth
        let height = viewModel.boardHeight
        let mines = viewModel.flagsRemaining
        let status = statusDescription
        return String(
            localized: "\(label), \(width) by \(height), \(mines) mines remaining, \(status)",
            bundle: .module)
    }

    var newGameTint: Color {
        // Neutral while idle/playing; colour reserved for the outcome.
        switch viewModel.status {
        case .won: return .green
        case .lost: return .red
        case .notStarted, .playing: return .secondary
        }
    }

    /// Input-mode colours, from the palette so the toggle and the SpriteKit glow
    /// never drift.
    var digColor: Color { palette.digColor }
    var flagColor: Color { palette.flagColor }

    /// A small manga-glyph button (the top-strip medal). 44pt touch target.
    func mangaIconButton(
        _ symbol: MangaIcon.Symbol, size: CGFloat, help: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        let label = Text(help, bundle: .module)
        return Button(action: action) {
            MangaIcon(symbol: symbol, size: size, tint: .secondary)
                .frame(width: 44, height: 44)  // Apple's min touch target
                .contentShape(Rectangle())  // whole frame tappable
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    /// Reveal/flag toggle as a segmented dig|flag pair (both tools visible, armed
    /// half filled), but the WHOLE pill is one button that flips the mode — no need
    /// to aim at a half. Space also toggles.
    var modeToggle: some View {
        let flagging = viewModel.inputMode == .flag
        return Button(action: { viewModel.inputMode.toggle() }) {
            HStack(spacing: 0) {
                modeSegment(.reveal, active: !flagging, fill: digColor)
                modeSegment(.flag, active: flagging, fill: flagColor)
            }
            .background(Capsule().fill(palette.statusBar.opacity(0.6)))
            .overlay(Capsule().stroke(.primary.opacity(0.15), lineWidth: 1))
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.space, modifiers: [])
        .help(
            flagging
                ? Text("Flag mode — tap flags (Space)", bundle: .module)
                : Text("Dig mode — tap reveals (Space)", bundle: .module)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Input mode", bundle: .module))
        .accessibilityValue(
            flagging ? Text("Flag", bundle: .module) : Text("Dig", bundle: .module)
        )
        .accessibilityHint(Text("Toggles between revealing and flagging", bundle: .module))
    }

    /// One half of the dig|flag pair (pure visual; the whole pill is the button).
    /// The armed half is filled; both carry the mode's screentone behind the glyph,
    /// matching the board's unopened-tile texture.
    private func modeSegment(_ symbol: MangaIcon.Symbol, active: Bool, fill: Color) -> some View {
        MangaIcon(symbol: symbol, size: 34, tint: active ? .white : .secondary)
            .frame(width: 50, height: 60)
            .background {
                ZStack {
                    if active { fill }
                    ScreentonePattern(
                        dots: symbol == .reveal,
                        color: active ? .white.opacity(0.35) : .primary.opacity(0.18))
                }
            }
    }
}
