import Foundation

/// Formats a play time (centiseconds) as `m:ss.t`, rounding to a tenth.
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
