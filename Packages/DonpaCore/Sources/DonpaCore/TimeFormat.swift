import Foundation

/// Formats a play time (stored in centiseconds) as `m:ss.t` — minutes, seconds,
/// and tenths — e.g. `0:04.7`, `2:05.3`. The stored value can be higher
/// precision; display rounds to a tenth.
public enum TimeFormat {
    public static func mmsst(centiseconds: Int) -> String {
        let tenths = (centiseconds + 5) / 10  // round centiseconds → tenths
        let totalSeconds = tenths / 10
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let frac = tenths % 10
        return String(format: "%d:%02d.%d", minutes, seconds, frac)
    }
}
