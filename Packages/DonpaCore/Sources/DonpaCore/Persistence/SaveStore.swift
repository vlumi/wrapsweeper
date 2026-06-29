import Foundation

/// Persists the in-progress `GameSnapshot` to a file in Application Support.
///
/// Writes are atomic, so a crash mid-save leaves the previous good save intact.
/// Loads are tolerant: a missing, unreadable, or wrong-version file yields nil
/// rather than throwing.
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

    /// The Application Support directory, resolved ONCE per process. Resolving it
    /// hits the filesystem (`url(for:create:)` → `getattrlist`); `GameContent.init`
    /// calls `appSupport()` on every SwiftUI `body` re-evaluation (the timer alone
    /// fires ~10×/s), so an uncached lookup showed up as a steady idle-CPU drain in
    /// the `NSHostingView.layout` path. Cached, repeat calls are free.
    private static let appSupportDirectory: URL = {
        let fm = FileManager.default
        return
            (try? fm.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true)) ?? fm.temporaryDirectory
    }()

    /// The production store, in Application Support (temp dir as a last resort).
    public static func appSupport(
        fileManager: FileManager = .default, filename: String = "currentGame.json"
    ) -> SaveStore {
        SaveStore(directory: appSupportDirectory, fileManager: fileManager, filename: filename)
    }

    /// A fresh, empty store in a unique temp directory, never touching the real
    /// Application Support store. Used by UI tests (`-uitest-clean`) for isolation.
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

    /// Atomically write the snapshot; failures are swallowed (prior save restores).
    public func save(_ snapshot: GameSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    /// Load a saved snapshot, or nil if none/unreadable/unsupported version.
    /// Accepts any save at or below `currentVersion` (additive format). A *newer*
    /// app's save may rely on a breaking change, so it's discarded.
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
