import SwiftUI

/// A fixed-width LED-style readout with a leading glyph (⚑ / ⏱) — the mine count
/// and timer. Shrinks to fit narrow windows. The glyph is meaningless to
/// VoiceOver, so a real `a11y` label is spoken instead.
struct CounterReadout: View {
    let glyph: String
    let value: String
    let a11y: LocalizedStringKey
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(verbatim: glyph).font(.title3)
            Text(verbatim: value)
                .font(.system(.title, design: .monospaced).weight(.bold))
                .foregroundStyle(tint)
        }
        .lineLimit(1)
        .layoutPriority(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(a11y, bundle: .module))
        .accessibilityValue(Text(verbatim: value))
    }

    /// Flag/mine count, fixed 3-digit (e.g. `010`).
    static func mines(_ value: Int, tint: Color) -> CounterReadout {
        CounterReadout(
            glyph: "⚑", value: String(format: "%03d", max(0, value)),
            a11y: "Mines remaining", tint: tint)
    }

    /// Whole-second timer: zero-padded 3-digit (e.g. `047`) under 1000s, then `m:ss`
    /// instead of sticking at 999. Capped at 99:59.
    static func time(centiseconds: Int, tint: Color) -> CounterReadout {
        let seconds = max(0, centiseconds / 100)
        let value: String
        if seconds < 1000 {
            value = String(format: "%03d", seconds)
        } else {
            let capped = min(seconds, 99 * 60 + 59)
            value = String(format: "%d:%02d", capped / 60, capped % 60)
        }
        return CounterReadout(glyph: "⏱", value: value, a11y: "Time, seconds", tint: tint)
    }
}

/// Live fraction of safe cells revealed, as a whole percent. Always shown so the
/// player can track progress on boards they rarely fully clear.
struct ProgressReadout: View {
    let progress: Double
    let tint: Color

    var body: some View {
        // Floor, matching the scoreboard's "Best %" (so 3.6% reads "3%").
        let pct = Int((progress * 100).rounded(.down))
        // Zero-pad to 3 digits so the width never jitters across 1→2→3 digits.
        return HStack(spacing: 4) {
            Image(systemName: "chart.bar.fill").font(.body)
            Text(verbatim: String(format: "%03d%%", pct))
                .font(.system(.title, design: .monospaced).weight(.bold))
                .foregroundStyle(tint)
        }
        .lineLimit(1)
        .layoutPriority(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Cleared", bundle: .module))
        .accessibilityValue(Text(verbatim: "\(pct)%"))
    }
}
