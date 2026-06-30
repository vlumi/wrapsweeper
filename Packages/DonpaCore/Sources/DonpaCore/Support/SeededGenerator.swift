/// A small, deterministic `RandomNumberGenerator` (SplitMix64) for reproducible
/// mine placement — used by the perf harness so a profiled board is identical run
/// to run (system RNG otherwise varies the layout and muddies A/B comparisons).
/// Not for gameplay randomness; production play uses the system generator.
public struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) { self.state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
