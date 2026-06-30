import DonpaCore
import SwiftUI

/// The board-config chooser: a Classic/Modern mode switch over the matching
/// picker (3 classic presets, or Size × Density for Modern). Binds directly to
/// `Settings` — the pending choice; the host decides when to start a game.
///
/// The difficulty/size rows are `CarouselPicker` drums with a detail/tagline line
/// below the selected card. Mode stays a segmented control (two short options).
///
/// On macOS it's keyboard-drivable: up/down move between rows, left/right cycle
/// within the focused row. `focusedRow` is owned by the host and clamped here as
/// the row set changes (Classic 2 rows, Modern 3). Cycling mutates `Settings` and
/// each carousel follows its bound value, so the keys drive the drums.
struct BoardSelectionPicker: View {
    @ObservedObject var settings: Settings
    /// Keyboard-focused row, or nil when not keyboard-driven (iOS, or before the
    /// first arrow press).
    var focusedRow: Int?
    /// Ask the host to move keyboard focus to a row. nil on iOS.
    var onFocusRow: ((Int) -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            // Row 0: Mode.
            Picker("Mode", selection: $settings.mode) {
                ForEach(GameMode.allCases) { Text(verbatim: $0.label).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .modifier(FocusRing(focused: focusedRow == 0))
            .onChange(of: settings.mode) { _ in onFocusRow?(0) }

            switch settings.mode {
            case .classic:
                // Difficulty is row 1, lining up with Modern's difficulty row.
                carouselRow(
                    1,
                    labels: ClassicPreset.allCases.map(\.label),
                    index: classicIndex,
                    detail: settings.classicPreset.detail,
                    tagline: settings.classicPreset.tagline)
            case .modern:
                carouselRow(
                    1,
                    labels: Density.allCases.map(\.label),
                    index: densityIndex,
                    detail: settings.modernDensity.detail,
                    tagline: settings.modernDensity.tagline,
                    symbol: { i in
                        let all = Density.allCases
                        return all.indices.contains(i) ? DensityInsignia.markImage(all[i]) : nil
                    })
                carouselRow(
                    2,
                    labels: BoardSize.allCases.map(\.label),
                    index: sizeIndex,
                    detail: settings.modernSize.detail,
                    tagline: settings.modernSize.tagline)
                // Row 3: edges (bounded square vs wrapped torus). Modern only.
                Picker("Edges", selection: $settings.modernEdges) {
                    ForEach(BoardEdges.allCases) { Text(verbatim: $0.label).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .modifier(FocusRing(focused: focusedRow == 3))
                .onChange(of: settings.modernEdges) { _ in onFocusRow?(3) }
            }
        }
    }

    /// A carousel drum plus the detail/tagline line for its selected card.
    private func carouselRow(
        _ row: Int, labels: [String], index: Binding<Int>, detail: String, tagline: String,
        symbol: ((Int) -> Image?)? = nil
    ) -> some View {
        VStack(spacing: 4) {
            CarouselPicker(
                labels: labels, selection: index, focused: focusedRow == row, symbol: symbol,
                onInteract: { onFocusRow?(row) }
            )
            // Identity per label set, so switching mode builds a fresh carousel
            // centred on its selection rather than reusing a stale scroll offset.
            .id(labels)
            HStack(spacing: 6) {
                Text(verbatim: detail).fontWeight(.bold).foregroundStyle(.primary)
                Text(verbatim: "·").foregroundStyle(.secondary)
                Text(verbatim: tagline).italic().foregroundStyle(.primary.opacity(0.75))
            }
            .font(.body)
            // Wrap rather than shrink, so a longer line keeps the same font size.
            .lineLimit(2)
            .multilineTextAlignment(.center)
            // Fixed width so the swapping content doesn't reflow while the drum animates.
            .frame(maxWidth: .infinity)
            .animation(.snappy, value: detail)
        }
    }

    // MARK: Enum ↔ index bindings (the carousel works in index space)

    private var classicIndex: Binding<Int> {
        enumIndex(\.classicPreset, all: ClassicPreset.allCases)
    }
    private var densityIndex: Binding<Int> {
        enumIndex(\.modernDensity, all: Density.allCases)
    }
    private var sizeIndex: Binding<Int> {
        enumIndex(\.modernSize, all: BoardSize.allCases)
    }

    /// A `Binding<Int>` over a `Settings` enum, mapping case↔index in `allCases`.
    /// Out-of-range writes are ignored.
    private func enumIndex<T: Equatable>(
        _ keyPath: ReferenceWritableKeyPath<Settings, T>, all: [T]
    ) -> Binding<Int> {
        Binding(
            get: { all.firstIndex(of: settings[keyPath: keyPath]) ?? 0 },
            set: { i in
                guard all.indices.contains(i) else { return }
                settings[keyPath: keyPath] = all[i]
            })
    }
}

/// Wraps a control with the keyboard focus ring used across the picker rows.
private struct FocusRing: ViewModifier {
    let focused: Bool
    func body(content: Content) -> some View {
        content
            // Always-present panel, recoloured on focus (never resizes).
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(focused ? 0.12 : 0))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.accentColor.opacity(focused ? 1 : 0), lineWidth: 2)))
    }
}
