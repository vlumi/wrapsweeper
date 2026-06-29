import DonpaCore
import SwiftUI

/// One config's row in the high-score table: name/insignia, clears, best %, best
/// time — plus the two row cues (the just-set record flourish and the persistent
/// "you are here" band for the config being played) and the non-colour "new best"
/// marker on the value that just improved.
struct ScoreRow: View {
    @ObservedObject var scoreboard: Scoreboard
    let config: GameConfig
    /// The config the player is currently on, for the "you are here" band.
    let currentConfigKey: String?
    /// Shared horizontal inset (matches the header + section padding).
    let rowInset: CGFloat

    var body: some View {
        HStack {
            // Modern rows: rank insignia in a fixed-width column (so size letters
            // line up), then the size name. Classic rows show their preset name.
            if let size = config.modernSize, let density = config.modernDensity {
                DensityInsignia.image(density)
                    .resizable().scaledToFit().frame(width: 30, height: 20)
                Text(verbatim: size.label)
            } else {
                Text(verbatim: config.label)  // already localized by GameConfig
            }
            Spacer()
            Text(verbatim: ScoreboardView.grouped(scoreboard.wins(for: config)))
                .font(.body.monospaced())
                .frame(width: 56, alignment: .trailing)
            HStack(spacing: 3) {
                if recordMarker == .progress { newBestMarker }
                if let progress = scoreboard.bestProgress(for: config) {
                    // Floor, not round: a 99.7%-cleared loss must not read "100%".
                    Text("\(Int((progress * 100).rounded(.down)))%").font(.body.monospaced())
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .frame(width: 64, alignment: .trailing)
            HStack(spacing: 3) {
                if recordMarker == .time { newBestMarker }
                if let best = scoreboard.best(for: config) {
                    Text(TimeFormat.mmsst(centiseconds: best)).font(.body.monospaced().bold())
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .frame(width: 80, alignment: .trailing)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, rowInset)
        .background(rowHighlight)
    }

    /// Which "Best" column, if any, just set a record on this row — so the non-color
    /// "new best" marker can flag the exact value that improved (color alone isn't
    /// relied on; the row band is the primary cue). Derived from the stored best: a
    /// recorded time means the PB was a win (time); progress-only means a loss
    /// (clear-%). nil unless this is the recent-record row.
    private enum RecordField { case time, progress }
    private var recordMarker: RecordField? {
        guard scoreboard.recentRecord == config.storageKey else { return nil }
        return scoreboard.best(for: config) != nil ? .time : .progress
    }

    /// A small upward chevron flagging the just-improved value. Shape, not colour,
    /// so it survives any user accent choice and is colour-blind safe.
    private var newBestMarker: some View {
        Image(systemName: "arrow.up")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)
            .accessibilityLabel(Text("new best", bundle: .module))
    }

    /// Two distinct row cues. The just-set RECORD gets the strong accent flourish
    /// (transient — cleared when the next game ends). The CURRENT config (the board
    /// you're on) gets a subtler persistent "you are here" band, so opening the
    /// scoreboard always shows where you stand. Record wins when a row is both.
    @ViewBuilder private var rowHighlight: some View {
        if scoreboard.recentRecord == config.storageKey {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.18))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(0.5)))
        } else if currentConfigKey == config.storageKey {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.18), lineWidth: 1))
        }
    }
}
