import Foundation

/// Persists the in-progress `GameSnapshot` to a file in Application Support.
///
/// Writes are **atomic** (`Data.write(options: .atomic)` writes a temp file then
/// renames), so a crash mid-save can never leave a half-written, corrupt save —
/// the previous good save survives intact. Loads are **tolerant**: a missing,
/// unreadable, or wrong-version file yields nil rather than throwing, so a bad
/// save just means "no game to resume", never a crash.
public struct SaveStore {
    private let url: URL
    private let fileManager: FileManager

    public init(
        directory: URL, fileManager: FileManager = .default,
        filename: String = "currentGame.json"
    ) {
        self.fileManager = fileManager
        self.url = directory.appendingPathComponent(filename)
    }

    /// The production store, in Application Support (temp dir as a last resort if
    /// it's somehow unavailable). Tests construct `SaveStore(directory:)` directly.
    public static func appSupport(
        fileManager: FileManager = .default, filename: String = "currentGame.json"
    ) -> SaveStore {
        let dir =
            (try? fileManager.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true)) ?? fileManager.temporaryDirectory
        return SaveStore(directory: dir, fileManager: fileManager, filename: filename)
    }

    /// A fresh, empty store in a unique temp directory — so each launch starts
    /// with NO saved game and never reads or writes the real Application Support
    /// store. Used by UI tests (launch arg `-uitest-clean`) so they're
    /// deterministic and can't be polluted by, or pollute, a real save.
    public static func ephemeral(fileManager: FileManager = .default) -> SaveStore {
        let dir = fileManager.temporaryDirectory
            .appendingPathComponent("donpa-uitest-\(UUID().uuidString)", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return SaveStore(directory: dir, fileManager: fileManager)
    }

    /// Whether the app was launched for a clean UI-test run.
    public static var isUITestCleanLaunch: Bool {
        ProcessInfo.processInfo.arguments.contains("-uitest-clean")
    }

    /// Atomically write the snapshot. Failures are swallowed — a save that didn't
    /// land just means the prior save (or none) is what restores.
    public func save(_ snapshot: GameSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    /// Load a saved snapshot, or nil if there's none / it's unreadable / it's a
    /// version this build doesn't understand.
    ///
    /// Accepts any save at or below `currentVersion` — the format is additive, so
    /// an older save still decodes (newer fields default; see `GameSnapshot`'s
    /// decoder). A save from a *newer* app (`version > current`) may rely on a
    /// breaking change this build predates, so it's discarded rather than risked.
    public func load() -> GameSnapshot? {
        guard let data = try? Data(contentsOf: url),
            let snapshot = try? JSONDecoder().decode(GameSnapshot.self, from: data),
            snapshot.version <= GameSnapshot.currentVersion
        else { return nil }
        return snapshot.migrated()
    }

    public var hasSave: Bool { fileManager.fileExists(atPath: url.path) }

    /// Remove the save (on finish / new game / return to title).
    public func clear() {
        try? fileManager.removeItem(at: url)
    }
}
