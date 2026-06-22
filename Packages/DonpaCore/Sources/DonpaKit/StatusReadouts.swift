import SwiftUI

/// A fixed-width 3-digit LED-style readout with a leading glyph (⚑ / ⏱) — the
/// mine count and the timer in the thin top metrics strip. Shrinks to fit very
/// narrow windows rather than clipping. The glyph is meaningless to VoiceOver,
/// so a real `a11y` label is spoken instead.
struct CounterReadout: View {
    let glyph: String
    let value: String
    let a11y: LocalizedStringKey
    let tint: Color

    var body: some View {
        HStack(spacing: 3) {
            Text(verbatim: glyph)
            Text(verbatim: value)
                .font(.system(.title3, design: .monospaced).weight(.bold))
                .foregroundStyle(tint)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .layoutPriority(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(a11y, bundle: .module))
        .accessibilityValue(Text(verbatim: value))
    }

    /// Flag/mine count: a fixed 3-digit readout (e.g. `010`).
    static func mines(_ value: Int, tint: Color) -> CounterReadout {
        CounterReadout(
            glyph: "⚑", value: String(format: "%03d", max(0, value)),
            a11y: "Mines remaining", tint: tint)
    }

    /// The classic 3-digit whole-second timer (e.g. `047`), capped at 999 like
    /// the original. The stored time keeps counting past that; precise tenths
    /// (`m:ss.t`) appear in results, not here.
    static func time(centiseconds: Int, tint: Color) -> CounterReadout {
        let seconds = min(999, max(0, centiseconds / 100))
        return CounterReadout(
            glyph: "⏱", value: String(format: "%03d", seconds), a11y: "Time, seconds", tint: tint)
    }
}

/// Live fraction of safe cells revealed, as a whole percent. Always shown so the
/// player can track progress on boards they rarely fully clear.
struct ProgressReadout: View {
    let progress: Double
    let tint: Color

    var body: some View {
        let pct = Int((progress * 100).rounded())
        return HStack(spacing: 3) {
            Image(systemName: "chart.bar.fill").font(.caption)
            Text(verbatim: "\(pct)%")
                .font(.system(.title3, design: .monospaced).weight(.bold))
                .foregroundStyle(tint)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Cleared", bundle: .module))
        .accessibilityValue(Text(verbatim: "\(pct)%"))
    }
}
