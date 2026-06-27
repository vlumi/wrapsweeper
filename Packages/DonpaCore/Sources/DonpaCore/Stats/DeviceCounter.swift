import Foundation

/// A cumulative total that stays correct across devices: a conflict-free
/// grow-only counter (G-Counter).
///
/// Invariant: a device only ever writes its OWN count, never merging another's.
/// Each device owns one cloud record, so there's nothing to conflict-resolve and
/// the displayed value is the sum of all devices' counts. Locally that's two Ints:
/// this device's precise `mine` plus a cached `othersTotal` (sum of every other
/// device's count, refreshed by sync). With no sync, `othersTotal` is 0.
public struct DeviceCounter: Codable, Equatable, Sendable {
    /// This device's own count — the only field this device writes.
    public private(set) var mine: Int
    /// Cached sum of all OTHER devices' counts (set by sync; 0 until then).
    public private(set) var othersTotal: Int

    public init(mine: Int = 0, othersTotal: Int = 0) {
        self.mine = mine
        self.othersTotal = othersTotal
    }

    enum CodingKeys: String, CodingKey { case mine, othersTotal }

    /// Both fields default to 0 if absent, so an older counter still decodes.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mine = try c.decodeIfPresent(Int.self, forKey: .mine) ?? 0
        othersTotal = try c.decodeIfPresent(Int.self, forKey: .othersTotal) ?? 0
    }

    /// The cumulative total across all devices.
    public var total: Int { mine + othersTotal }

    /// Add to this device's own count.
    public mutating func add(_ delta: Int) {
        mine += delta
    }

    /// Replace the cached "others" sum from a sync read. `mine` is untouched — it's
    /// this device's own slot, written to the cloud separately.
    public mutating func setOthersTotal(_ sum: Int) {
        othersTotal = sum
    }
}
