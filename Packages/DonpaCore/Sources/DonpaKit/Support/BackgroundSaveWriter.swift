import DonpaCore
import Foundation

/// Serializes the encode + atomic write of a `GameSnapshot` off the main thread.
/// The caller snapshots on the main actor (a consistent read of live state) and
/// hands over the immutable `Sendable` value; only the expensive encode + write
/// runs here, so a save on a huge board never stalls input. Being an `actor`
/// serializes writes (no two `.atomic` renames racing) in call order.
actor BackgroundSaveWriter {
    private let store: SaveStore

    init(store: SaveStore) {
        self.store = store
    }

    /// Encode + write the snapshot, off the main thread.
    func write(_ snapshot: GameSnapshot) {
        store.save(snapshot)
    }

    /// Remove the save, serialized with writes so a clear can't race a pending write.
    func clear() {
        store.clear()
    }
}
