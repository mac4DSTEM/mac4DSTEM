//
//  RecentDatasets.swift
//  Role: The recents list — every dataset the app remembers having opened,
//        the persisted store behind it, and the location labels that tell
//        same-named entries apart.
//
//  WHY THIS IS ITS OWN TYPE (docs/archive/development-process-2026-08-31.md §7):
//  the list is real state with real transitions (remember, remove, bookmark
//  refresh, the cap at eight), it is persisted as a unit, and the labels
//  derive from it alone.
//
//  `AppState` holds it and keeps NO forwarding properties: views read
//  `appState.recents.…` directly. What stays behind on `AppState` is the
//  coordination the list cannot own — `DatasetRecoveryRecord` (which pairs a
//  recent with per-session position state the record needs at write time) and
//  the open/resolve flows, which touch readers and security scopes.
//
//  The labels are STORED, not computed per access — a computed property here
//  would run its O(n²) disambiguation on every read (harmless at n ≤ 8, but
//  the pattern open-items #31 tracks). Recomputing only on mutation avoids it.
//

import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif

@MainActor
@Observable
package final class RecentDatasets {

    /// Most recently opened first. Capped at `capacity`.
    package private(set) var entries: [RecentDataset]

    /// Where each entry lives, keyed by its path (`RecentDataset.id`), said
    /// only as precisely as it takes to tell same-named entries apart — see
    /// `RecentDatasetLocation`. Recomputed on every mutation, never on read.
    package private(set) var locationLabels: [String: String] = [:]

    /// Eight, matching the shipped behaviour this type was extracted from.
    package static let capacity = 8

    private let persist: ([RecentDataset]) -> Void

    /// `persist` is injectable so tests never write the user's real recents —
    /// `WorkspaceRecoveryStore` is `UserDefaults.standard` all the way down.
    package init(entries: [RecentDataset] = WorkspaceRecoveryStore.recent(),
         persist: @escaping ([RecentDataset]) -> Void = WorkspaceRecoveryStore.saveRecent) {
        self.entries = entries
        self.persist = persist
        relabel()
    }

    /// Insert (or move) `entry` to the front, drop anything past the cap,
    /// and persist.
    package func remember(_ entry: RecentDataset) {
        entries.removeAll { $0.id == entry.id }
        entries.insert(entry, at: 0)
        if entries.count > Self.capacity {
            entries.removeLast(entries.count - Self.capacity)
        }
        save()
    }

    package func remove(id: String) {
        let before = entries.count
        entries.removeAll { $0.id == id }
        // A miss is a no-op, same contract as `updateBookmark`: persisting an
        // unchanged list would still clobber the store with this instance's
        // snapshot for no reason.
        guard entries.count != before else { return }
        save()
    }

    package func entry(withID id: String) -> RecentDataset? {
        entries.first { $0.id == id }
    }

    /// Empty the list. Settings' "Clear Recent Datasets" (`ROADMAP.md`
    /// "Settings window") — an empty list is a no-op, the same guard
    /// `remove(id:)` uses, so a repeated click cannot clobber the store with
    /// an already-current empty snapshot for no reason.
    package func clearAll() {
        guard !entries.isEmpty else { return }
        entries.removeAll()
        save()
    }

    /// Replace a stale security-scoped bookmark in place. A miss is a no-op:
    /// the entry may have been removed while the resolve was in flight.
    package func updateBookmark(_ bookmark: Data, forID id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].bookmark = bookmark
        save()
    }

    private func save() {
        persist(entries)
        relabel()
    }

    private func relabel() {
        let paths = entries.map(\.id)
        let labels = RecentDatasetLocation.labels(for: paths)
        // `uniquingKeysWith`, not `uniqueKeysWithValues`: every in-app writer
        // dedupes by id, but this now runs at app INIT on whatever the store
        // decoded — and a corrupted or hand-edited blob with two equal paths
        // must not make the app unlaunchable. Duplicate paths get identical
        // labels anyway, so keeping the first is exact, and behaviour for a
        // duplicate-free list is byte-identical (Gate A reviewed).
        locationLabels = Dictionary(zip(paths, labels), uniquingKeysWith: { first, _ in first })
    }
}
