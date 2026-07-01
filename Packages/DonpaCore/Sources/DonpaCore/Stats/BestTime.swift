import Foundation

/// A recorded winning time paired with WHEN it was achieved. The timestamp travels
/// with its value so cross-device merging can never separate them (the display picks
/// whole `BestTime`s by their `centiseconds`, never mins the times and dates apart).
/// Stored UTC; formatted in local time for display.
public struct BestTime: Equatable, Sendable, Codable {
    /// Winning time in centiseconds.
    public var centiseconds: Int
    /// When this time was set (wall-clock at record time; labeling, not ordering).
    public var achievedAt: Date

    public init(centiseconds: Int, achievedAt: Date) {
        self.centiseconds = centiseconds
        self.achievedAt = achievedAt
    }

    enum CodingKeys: String, CodingKey { case centiseconds = "cs", achievedAt = "at" }
}

extension Array where Element == BestTime {
    /// Merge device-owned top-time lists into the cross-device top `limit`, fastest
    /// first, de-duplicating identical (time, date) entries. Pure — the view
    /// projection over every device's own list; no list is mutated in place.
    public func mergedTop(with others: [[BestTime]], limit: Int) -> [BestTime] {
        var all = self
        for list in others { all.append(contentsOf: list) }
        // Stable de-dupe on (centiseconds, achievedAt): the same clear reported by
        // one device's own list shouldn't count twice if lists overlap.
        var seen = Set<String>()
        let unique = all.filter { entry in
            let key = "\(entry.centiseconds)@\(entry.achievedAt.timeIntervalSince1970)"
            return seen.insert(key).inserted
        }
        return Array(unique.sorted { $0.centiseconds < $1.centiseconds }.prefix(limit))
    }

    /// Insert a new time into this device's OWN top list, keeping it sorted (fastest
    /// first) and capped at `limit`. Returns whether the time made the cut.
    @discardableResult
    public mutating func insertTop(_ time: BestTime, limit: Int) -> Bool {
        append(time)
        sort { $0.centiseconds < $1.centiseconds }
        if count > limit { removeLast(count - limit) }
        return contains(time)
    }
}
