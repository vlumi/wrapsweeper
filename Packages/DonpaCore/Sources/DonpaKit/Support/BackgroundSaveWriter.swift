import DonpaCore
import Foundation

/// Serializes the encode + atomic write of a `GameSnapshot` OFF the main thread.
///
/// Snapshotting itself (reading the board into the revealed/flagged coord sets)
/// must happen on the main actor — it's a consistent read of live game state — so
/// the caller builds the `GameSnapshot` and hands this immutable, `Sendable` value
/// over. Only the expensive tail (JSON encode + `Data.write`) runs here, so a save
/// on a huge board never stalls input.
///
/// Being an `actor` gives free serialization: writes can't interleave (no two
/// `.atomic` renames racing), and they land in call order. `SaveStore` is a
/// `Sendable` value (just a URL + FileManager), so it's safe to hold and call here.
actor BackgroundSaveWriter {
    private let store: SaveStore

    init(store: SaveStore) {
        self.store = store
    }

    /// Encode + write the snapshot. `await`ed without blocking the main thread —
    /// the actor hops execution off it. Serialized against other writes/clears.
    func write(_ snapshot: GameSnapshot) {
        store.save(snapshot)
    }

    /// Remove the save (game finished / new game / returned to title), serialized
    /// with writes so a clear can't race a still-pending write of a live game.
    func clear() {
        store.clear()
    }
}
