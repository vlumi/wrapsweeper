/// A board configuration: dimensions plus mine count.
public struct Difficulty: Hashable, Sendable {
    public let name: String
    public let width: Int
    public let height: Int
    public let mineCount: Int

    public init(name: String, width: Int, height: Int, mineCount: Int) {
        precondition(width > 0 && height > 0, "board must be non-empty")
        precondition(
            mineCount >= 0 && mineCount < width * height,
            "mine count must leave at least one safe cell")
        self.name = name
        self.width = width
        self.height = height
        self.mineCount = mineCount
    }

    // Classic Minesweeper presets.
    public static let beginner = Difficulty(name: "Beginner", width: 9, height: 9, mineCount: 10)
    public static let intermediate = Difficulty(
        name: "Intermediate", width: 16, height: 16, mineCount: 40)
    public static let expert = Difficulty(name: "Expert", width: 30, height: 16, mineCount: 99)

    public static let presets: [Difficulty] = [.beginner, .intermediate, .expert]
}
