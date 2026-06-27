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

    /// Flag/mine count: a fixed 3-digit readout (e.g. `010`).
    static func mines(_ value: Int, tint: Color) -> CounterReadout {
        CounterReadout(
            glyph: "⚑", value: String(format: "%03d", max(0, value)),
            a11y: "Mines remaining", tint: tint)
    }

    /// The whole-second timer. Under 1000s it's the classic zero-padded 3-digit
    /// readout (e.g. `047`) — the nostalgic look for normal games. Beyond that
    /// (long huge-board games easily exceed 999s) it rolls over to `m:ss`
    /// (e.g. `17:23`) instead of sticking at 999. Capped at 99:59 so the field
    /// can't grow without bound.
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
        // Floor, not round-to-nearest — matching the scoreboard's "Best %": you
        // haven't reached 4% until you've actually cleared 4%, so 3.6% reads "3%".
        // (Rounding here made the live readout disagree with the scoreboard.)
        let pct = Int((progress * 100).rounded(.down))
        // Zero-pad to a fixed 3-digit field (e.g. `072%`, `100%`) so the readout's
        // width never jitters as the value crosses 1→2→3 digits — matching the
        // zero-padded 3-digit mine/timer counters.
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
