//
//  RecentDatasets.swift
//  Role: The recents list — every dataset the app remembers having opened,
//        the persisted store behind it, and the location labels that tell
//        same-named entries apart.
//
//  WHY THIS IS ITS OWN TYPE (docs/development-process.md §7). S3 touches
//  `AppState`, so it extracts one seam at a green test boundary. This is the
//  cheapest true seam on S3's path: the list is real state with real
//  transitions (remember, remove, bookmark refresh, the cap at eight), it is
//  persisted as a unit, and the labels derive from it alone. // v2 S3
//
//  `AppState` holds it and keeps NO forwarding properties: views read
//  `appState.recents.…` directly. What stays behind on `AppState` is the
//  coordination the list cannot own — `DatasetRecoveryRecord` (which pairs a
//  recent with per-session position state the record needs at write time) and
//  the open/resolve flows, which touch readers and security scopes.
//
//  The labels are STORED, not computed per access. The comment this replaces
//  claimed "recomputed only when the list changes" of a computed property that
//  in fact ran its O(n²) disambiguation on every read — harmless at n ≤ 8, but
//  the claim was wrong, and #31 is the standing item about exactly that
//  pattern. Recomputing on mutation makes the claim true.
//

import Foundation

@MainActor
@Observable
final class RecentDatasets {

    /// Most recently opened first. Capped at `capacity`.
    private(set) var entries: [RecentDataset]

    /// Where each entry lives, keyed by its path (`RecentDataset.id`), said
    /// only as precisely as it takes to tell same-named entries apart — see
    /// `RecentDatasetLocation`. Recomputed on every mutation, never on read.
    private(set) var locationLabels: [String: String] = [:]

    /// Eight, matching the shipped behaviour this type was extracted from.
    static let capacity = 8

    private let persist: ([RecentDataset]) -> Void

    /// `persist` is injectable so tests never write the user's real recents —
    /// `WorkspaceRecoveryStore` is `UserDefaults.standard` all the way down.
    init(entries: [RecentDataset] = WorkspaceRecoveryStore.recent(),
         persist: @escaping ([RecentDataset]) -> Void = WorkspaceRecoveryStore.saveRecent) {
        self.entries = entries
        self.persist = persist
        relabel()
    }

    /// Insert (or move) `entry` to the front, drop anything past the cap,
    /// and persist.
    func remember(_ entry: RecentDataset) {
        entries.removeAll { $0.id == entry.id }
        entries.insert(entry, at: 0)
        if entries.count > Self.capacity {
            entries.removeLast(entries.count - Self.capacity)
        }
        save()
    }

    func remove(id: String) {
        let before = entries.count
        entries.removeAll { $0.id == id }
        // A miss is a no-op, same contract as `updateBookmark`: persisting an
        // unchanged list would still clobber the store with this instance's
        // snapshot for no reason.
        guard entries.count != before else { return }
        save()
    }

    func entry(withID id: String) -> RecentDataset? {
        entries.first { $0.id == id }
    }

    /// Replace a stale security-scoped bookmark in place. A miss is a no-op:
    /// the entry may have been removed while the resolve was in flight.
    func updateBookmark(_ bookmark: Data, forID id: String) {
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
        // duplicate-free list is byte-identical. Gate A review, 2026-08-19.
        locationLabels = Dictionary(zip(paths, labels), uniquingKeysWith: { first, _ in first })
    }
}
