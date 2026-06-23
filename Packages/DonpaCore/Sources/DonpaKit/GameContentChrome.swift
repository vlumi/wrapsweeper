import DonpaCore
import SwiftUI

/// The in-game action buttons, in their fixed far-edge → toggle order. (Starting
/// a different game lives in the status-bar config badge, not here.)
enum GameAction: Hashable { case home, retry, pause }

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
            boardCursorActive: gameInProgress && !navigator.showingTitle
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Per-cell VoiceOver is a future task (needs a scalable cursor model for
        // huge boards); for now announce a useful summary.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Board", bundle: .module))
        .accessibilityValue(boardSummary)
        .accessibilityIdentifier("game.board")
        // A subtle inner edge-glow tinted to the armed input mode, so the whole
        // field reinforces which tool a tap will use (teal = dig, orange = flag).
        .overlay { modeGlow }
        // Result screen dims the board ONLY, leaving the control strip live.
        .overlay { mangaPanel }
        .overlay { pauseOverlay }
        .animation(.easeInOut(duration: 0.2), value: viewModel.isPaused)
        .animation(.easeInOut(duration: 0.2), value: viewModel.inputMode)
        .clipped()  // keep the dimmed backdrop within the board's bounds
    }

    /// A soft inner border glow in the armed mode's colour, drawn just inside the
    /// board edge. Shown only during a live game; fades when the mode changes.
    @ViewBuilder var modeGlow: some View {
        if let color = activeModeColor {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(color, lineWidth: 3)
                .blur(radius: 6)
                .padding(2)
                .opacity(0.8)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    /// Covers the board while paused so it can't be studied; tap (or the strip's
    /// resume) continues the game. Blurs rather than blacks out so it reads as
    /// "paused", not "blank".
    @ViewBuilder var pauseOverlay: some View {
        if viewModel.isPaused {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(palette.pageBackground.opacity(0.5))
                VStack(spacing: 14) {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.secondary)
                    Text("Paused", bundle: .module).font(.title2.bold())
                    Text("Tap to resume", bundle: .module)
                        .font(.callout).foregroundStyle(.secondary)
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

    // MARK: Status bar

    /// The thin top strip: the current config label, then read-only metrics
    /// (mines, the live clear %, the timer), with the trophy (High Scores) alone
    /// in the right corner. Kept just tall enough for the numbers; all actions
    /// live in the board-side strip.
    ///
    /// The whole row is laid out at its natural size and then uniformly scaled to
    /// fit the width via `FitToWidth` — so on a narrow phone everything (label,
    /// the three metrics, the medal) shrinks *together* by one factor, staying
    /// proportional and the same relative size, instead of each child self-scaling
    /// to a different size, jittering, or truncating.
    var statusBar: some View {
        FitToWidth {
            HStack(spacing: 16) {
                // Which game you're playing (e.g. "Expert" or "Medium · Sapper"),
                // as a tappable badge that opens the New Game popup — tapping the
                // current game to change it. This replaces the separate New Game
                // action button.
                configButton
                CounterReadout.mines(viewModel.flagsRemaining, tint: palette.counter)
                // `game.progress` re-renders on every reveal via the @Published revision.
                ProgressReadout(progress: viewModel.game.progress, tint: palette.counter)
                CounterReadout.time(
                    centiseconds: viewModel.elapsedCentiseconds, tint: palette.counter)
                Spacer(minLength: 12)
                // High Scores sits apart on the right — same read-only character.
                // (On the title screen it stays on the art; this is its in-game home.)
                mangaIconButton(.medal, size: 40, help: "High Scores") {
                    navigator.showingScores = true
                }
            }
            .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(palette.statusBar)
    }

    /// The current-game badge, tappable to open the New Game popup (the in-game
    /// counterpart to tapping the title splash). A trailing chevron hints it's a
    /// menu; the badge pulses with `restartPop` on a fresh game like the old New
    /// Game button did.
    private var configButton: some View {
        Button(action: { navigator.showingNewGame = true }) {
            HStack(spacing: 6) {
                Text(viewModel.config.label)
                    .font(.subheadline.weight(.bold))
                // Swap arrows read as "switch to a different game" — not a
                // dropdown (chevron) and not "add" (plus).
                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption.weight(.bold))
                    .opacity(0.85)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(palette.counter))
            .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .scaleEffect(restartPop ? 1.15 : 1.0)
        .help(Text("Change game", bundle: .module))
        .accessibilityLabel(Text("Change game", bundle: .module))
        .accessibilityValue(Text(viewModel.config.label))
        .accessibilityIdentifier("game.config")
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
    /// control row never reflows); Pause is just disabled off-play.
    private var actionOrder: [GameAction] { [.home, .retry, .pause] }

    @ViewBuilder
    private func actionView(_ action: GameAction) -> some View {
        switch action {
        case .home:
            actionButton(.home, help: "Home") { goHome() }
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
        }
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

    /// Distinct colours for the two input modes — used for the armed toggle half
    /// and the matching board glow, so the live tool is obvious at a glance.
    /// Dig is a calm teal ("step safely"); flag is the warning orange.
    static let digColor = Color(red: 0.10, green: 0.55, blue: 0.62)
    static let flagColor = Color.orange

    /// The colour of the currently-armed mode, or nil when no live game.
    var activeModeColor: Color? {
        guard gameInProgress else { return nil }
        return viewModel.inputMode == .flag ? Self.flagColor : Self.digColor
    }

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
                modeSegment(.reveal, active: !flagging, fill: Self.digColor)
                modeSegment(.flag, active: flagging, fill: Self.flagColor)
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
    /// The armed half is filled with its mode colour and a white glyph.
    private func modeSegment(_ symbol: MangaIcon.Symbol, active: Bool, fill: Color) -> some View {
        MangaIcon(symbol: symbol, size: 34, tint: active ? .white : .secondary)
            .frame(width: 50, height: 60)
            .background(active ? fill : .clear)
    }
}
