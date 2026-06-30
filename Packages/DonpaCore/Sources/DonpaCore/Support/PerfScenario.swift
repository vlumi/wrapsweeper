import Foundation

/// A launch-time performance scenario, selected with `-perf-scenario <name>` so the
/// profiling harness (a UI test recorded under `xctrace`) can put the app into a
/// known heavy state deterministically — no fragile UI-driving of the SpriteView
/// board. Test/profiling only; absent in normal launches.
///
/// The app reads `current` at launch and, if set, jumps straight into the scenario
/// instead of the title. See `Scripts/perf-profile.sh`.
public enum PerfScenario: String, Sendable {
    /// XXXL (1000², 1M cells) Modern board with a region opened at the centre — the
    /// configuration the big-board CPU work targets (render load + autosave scan +
    /// idle timer churn).
    case xxxlOpened = "xxxl-opened"

    /// The scenario requested on the command line, or nil for a normal launch.
    public static var current: PerfScenario? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-perf-scenario"), i + 1 < args.count else {
            return nil
        }
        return PerfScenario(rawValue: args[i + 1])
    }
}
