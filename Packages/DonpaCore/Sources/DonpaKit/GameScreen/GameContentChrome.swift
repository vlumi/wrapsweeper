import DonpaCore
import SwiftUI

/// The in-game action buttons, in their fixed far-edge → toggle order. (Starting
/// a different game lives in the status-bar config badge, not here.)
enum GameAction: Hashable { case home, retry, pause, minimap }

/// The in-game chrome for `GameContent`: the thin top metrics strip, the board +
/// its control strip (actions + flag toggle), and the pause overlay. Split out of
/// GameView.swift to keep that file within length limits.
extension GameContent {
    // MARK: Board + control strip

    var leftHanded: Bool { settings.handedness == .left }

    /// The board plus the control strip (centered actions + the flag toggle in
    /// the handed corner). The strip never overlaps the grid: it sits *below* the
    /// board when the board leaves vertical room, or *beside* it (on the handed
    /// side) when it leaves horizontal room. The board takes the remaining space
    /// and the SpriteKit scene fits/centres the grid, so it shrinks in tight
    /// cases rather than being covered. The strip stays visible after the game
    /// ends so New Game / Retry / Home remain reachable (the flag toggle hides,
    /// since a finished board takes no input).
    var boardArea: some View {
        GeometryReader { geo in
            // Put the strip wherever the *board* leaves the most room: compare the
            // window's aspect to the board's. Proportionally wider than the board
            // → spare width → side strip; else spare height → bottom strip. (A wide
            // board like Expert in a wide window still gets a bottom strip.)
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

    /// The dig/flag toggle. Always present so the control set stays stable, but
    /// disabled (and dimmed) once the board is finished, since a finished board
    /// takes no input.
    var toggleControl: some View {
        modeToggle
            .disabled(!gameInProgress)
            .opacity(gameInProgress ? 1 : 0.4)
    }

    /// Bottom strip: the flag toggle pinned hard to the handed end (under the
    /// thumb), the action group pinned hard to the opposite end, and a single
    /// spacer between them — so each is flush to its own edge (not "almost
    /// centred") and they never overlap.
    var bottomControlStrip: some View {
        HStack(spacing: 8) {
            if leftHanded { toggleControl; Spacer(minLength: 8) }
            actionButtons(vertical: false)
            if !leftHanded { Spacer(minLength: 8); toggleControl }
        }
        .padding(.horizontal, 12)
    }

    /// Side strip (on the handed side): actions pinned to the top, the flag toggle
    /// pinned to the bottom for thumb reach, a spacer between.
    var sideControlStrip: some View {
        VStack(spacing: 8) {
            actionButtons(vertical: true)
            Spacer(minLength: 8)
            toggleControl
        }
        .padding(.vertical, 12)
    }

    var board: some View {
        // Palette passed as a value: BoardView's updateUIView/NSView pushes it to
        // the scene whenever the resolved scheme changes — reliable where
        // .onChange on the SwiftUI side was not.
        BoardView(
            scene: scene, palette: palette, inputMode: viewModel.inputMode,
            // Custom reveal/flag cursor only during a live game; otherwise the
            // normal arrow (title screen, result panel, or a finished board
            // you're just inspecting — where a flag cursor is stale).
            // No custom reveal/flag cursor while paused: the board is blurred
            // under the pause panel, so a dig/flag cursor there is stale.
            boardCursorActive: gameInProgress && !navigator.showingTitle && !viewModel.isPaused,
            showMinimap: settings.showMinimap
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Per-cell VoiceOver is a future task (needs a scalable cursor model for
        // huge boards); for now announce a useful summary.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Board", bundle: .module))
        .accessibilityValue(boardSummary)
        .accessibilityIdentifier("game.board")
        // The mode hint is a manga screentone (dig dots / flag hatch) over the
        // unopened tiles, drawn inside the SpriteKit scene — see
        // BoardScene.refreshModeGlow.
        // Result screen dims the board ONLY, leaving the control strip live.
        .overlay { mangaPanel }
        .overlay { pauseOverlay }
        .overlay { processingOverlay }
        .animation(.easeInOut(duration: 0.2), value: viewModel.isPaused)
        .animation(.easeInOut(duration: 0.15), value: showProcessing)
        .clipped()  // keep the dimmed backdrop within the board's bounds
    }

    /// Shown while a reveal/chord/new-board is being computed off the main thread (a
    /// big board's mine placement / flood-fill). Board input is blocked meanwhile
    /// (the view model's `canTakeInput`), so this must make "disabled" obvious — a
    /// dim wash over the whole board plus a centred spinner, not a subtle corner
    /// badge that left taps feeling broken. Dimmer than the pause overlay (it's
    /// transient, the board needn't be hidden), but unmistakably "not now".
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
            .allowsHitTesting(false)  // never intercept; input is gated in the model
        }
    }

    /// Covers the board while paused so it can't be studied; tap (or the strip's
    /// resume) continues the game. Blurs rather than blacks out so it reads as
    /// "paused", not "blank".
    @ViewBuilder var pauseOverlay: some View {
        if viewModel.isPaused {
            GeometryReader { geo in
                ZStack {
                    // Blur still hides the board (can't study it while paused); the
                    // "squad resting" manga panel sits on top as the pause art.
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay(palette.pageBackground.opacity(0.5))
                    // Sized like the win/loss result panel: off the shorter window
                    // dimension, clamped — so the pause art matches them. Reserve
                    // room for the hint so the panel + hint stay grouped and
                    // centred (not the hint stranded at the screen bottom).
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

    /// The in-game actions, pinned to the end of the strip opposite the flag
    /// toggle. Ordered *from the far edge inward toward the toggle*: Home (leaving
    /// the game — furthest, so it's hardest to mis-tap), then Retry, and Pause
    /// last so the most-used mid-play control sits nearest the thumb/toggle.
    /// (Starting a different game lives in the status-bar config badge, mirroring
    /// the title screen, so there's no New Game button here.) For a left-handed
    /// strip the toggle is on the other end, so the order is mirrored to keep
    /// Pause adjacent to it. A row in the bottom strip, a column in the narrow
    /// side strip.
    @ViewBuilder
    func actionButtons(vertical: Bool) -> some View {
        let layout =
            vertical
            ? AnyLayout(VStackLayout(spacing: 16)) : AnyLayout(HStackLayout(spacing: 16))
        // `actionOrder` is far-edge → toggle. The vertical strip is always
        // toggle-at-bottom, so top→bottom matches it directly. The horizontal
        // strip only needs reversing when the toggle is on the LEFT (left-handed),
        // so Pause still lands next to it.
        let reverse = !vertical && leftHanded
        let ordered = reverse ? Array(actionOrder.reversed()) : actionOrder
        layout {
            ForEach(ordered, id: \.self) { action in
                actionView(action)
            }
        }
    }

    /// The fixed action sequence, far-edge → toggle. Always the same set (so the
    /// control row never reflows); Pause and Minimap are just disabled when they
    /// don't apply (off-play / board fits the viewport).
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
            // Pause/Resume toggle: shows Play while paused so the same button
            // resumes. Always present (stable layout); enabled while the game is
            // live (playing or paused), dimmed otherwise.
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
            // Toggle the corner minimap. Tint reflects ITS OWN on/off state — a
            // fixed accent when shown, secondary when hidden — NOT `newGameTint`
            // (that's the game-outcome colour for Retry; a map toggle has nothing
            // to do with won/lost). Only meaningful when the board exceeds the
            // viewport. (The fullscreen overview opens from an icon ON the minimap.)
            mapButton(
                .minimap, help: "Overview map", id: "game.minimap",
                tint: settings.showMinimap ? palette.counter : .secondary
            ) { settings.showMinimap.toggle() }
        }
    }

    /// A toolbar button for a big-board map control (minimap toggle / open
    /// overview): disabled + dimmed when the board fits the viewport, since
    /// there's nothing off-screen to map.
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
        // Neutral while idle/playing; colour is reserved for the outcome so it
        // can't be mistaken for the (red) loss state.
        switch viewModel.status {
        case .won: return .green
        case .lost: return .red
        case .notStarted, .playing: return .secondary
        }
    }

    /// Distinct colours for the two input modes — the armed toggle half, matching
    /// the board mode-glow. Sourced from the palette so the toggle and the
    /// SpriteKit glow never drift.
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
                .contentShape(Rectangle())  // whole frame tappable, not just the glyph
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)  // the symbol alone says nothing to VoiceOver
    }

    /// Toggle between reveal- and flag-mode for plain taps. A *segmented pair*
    /// (dig | flag) shows both tools at once so it's self-evident the control
    /// switches modes and which one is armed — but the WHOLE pill is one button
    /// that just flips the mode, so you never have to aim at a half with your
    /// thumb. The armed half is filled (teal for dig, orange for flag); Space
    /// also toggles.
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

    /// One half of the dig|flag pair — pure visual (the whole pill is the button).
    /// The armed half is filled with its mode colour and a white glyph; both
    /// halves carry the mode's manga screentone (dots for dig, hatch for flag)
    /// behind the glyph, matching the board's unopened-tile texture.
    private func modeSegment(_ symbol: MangaIcon.Symbol, active: Bool, fill: Color) -> some View {
        MangaIcon(symbol: symbol, size: 34, tint: active ? .white : .secondary)
            .frame(width: 50, height: 60)
            .background {
                ZStack {
                    if active { fill }
                    // Screentone on top of the fill (white ink on the coloured
                    // armed side; muted ink on the empty side) — same dots/hatch
                    // vocabulary as the board.
                    ScreentonePattern(
                        dots: symbol == .reveal,
                        color: active ? .white.opacity(0.35) : .primary.opacity(0.18))
                }
            }
    }
}
