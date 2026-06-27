import Foundation

/// A cumulative total that stays correct across devices (a conflict-free
/// grow-only counter / G-Counter).
///
/// The trick: a device only ever writes its OWN running count; it never merges
/// another device's value. Under sync each device owns one record in the cloud,
/// so there's no conflict to resolve — concurrent play on two devices just has
/// each bump its own count, and the displayed value is the sum of all devices'
/// counts. No `max`/`sum` ambiguity, no per-event IDs, no lost updates.
///
/// Locally that collapses to two numbers: this device's precise `mine`, plus a
/// cached `othersTotal` (the sum of every *other* device's count, refreshed from
/// the cloud when sync runs). So the structure is bounded to two `Int`s no matter
/// how many devices ever sync — and `add` only touches `mine`. With no sync yet,
/// `othersTotal` is 0, so `total == mine`.
public struct DeviceCounter: Codable, Equatable, Sendable {
    /// This device's own count — the only field this device writes.
    public private(set) var mine: Int
    /// Cached sum of all OTHER devices' counts (set by a future sync; 0 until then).
    public private(set) var othersTotal: Int

    public init(mine: Int = 0, othersTotal: Int = 0) {
        self.mine = mine
        self.othersTotal = othersTotal
    }

    enum CodingKeys: String, CodingKey { case mine, othersTotal }

    /// Both fields default to 0 if absent, so a counter written without
    /// `othersTotal` (it's only set by sync) still decodes.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mine = try c.decodeIfPresent(Int.self, forKey: .mine) ?? 0
        othersTotal = try c.decodeIfPresent(Int.self, forKey: .othersTotal) ?? 0
    }

    /// The cumulative total across all devices.
    public var total: Int { mine + othersTotal }

    /// Add to this device's own count. (Never touches other devices' totals.)
    public mutating func add(_ delta: Int) {
        mine += delta
    }

    /// Replace the cached "others" sum from a sync read (sum of every other
    /// device's count). This device's `mine` is untouched — it's the source of
    /// truth for its own slot, written to the cloud separately.
    public mutating func setOthersTotal(_ sum: Int) {
        othersTotal = sum
    }
}
