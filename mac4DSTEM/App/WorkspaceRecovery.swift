import Foundation

nonisolated struct RecentDataset: Codable, Identifiable, Hashable {
    let id: String
    var displayName: String
    var bookmark: Data
    var lastOpened: Date
}

/// Where a recent dataset lives, said only as precisely as it needs to be said.
///
/// **The defect this exists for** (Track B, 2026-08-18): the recents list showed
/// `url.lastPathComponent` and nothing else, so a dataset on a NAS and an
/// identical copy on a local SSD rendered as two identical rows. The
/// de-duplication was correct — the two paths genuinely differ — but the list
/// whose only purpose is choosing between datasets could not show the choice.
/// The release owner opened 3.96 GB over SMB with the same file sitting on a
/// local disk.
///
/// **Why not just print the path.** These are 90 characters of mount point and
/// inbox folders; a row that shows all of it shows nothing. And why not always
/// the parent folder: in the case that produced the defect, both copies live in
/// `00_inbox/4DSTEM_Binned_Cubes`, so the parent is identical and only the
/// volume differs. The rule below is therefore "volume, plus as much of the
/// directory chain as it takes to tell these particular entries apart".
nonisolated enum RecentDatasetLocation {

    /// A label per path, in the same order, each the shortest form that
    /// distinguishes it from every other entry sharing its file name.
    ///
    /// Pure string work on the stored path — no file-system access. That is
    /// deliberate: this runs while drawing the welcome screen, the volumes
    /// involved may be unmounted, and asking the disk about a NAS that is not
    /// there would stall the first screen of the app. It also means this cannot
    /// claim a volume is "on the network", which would need a real query; the
    /// volume NAME is shown and the reader draws their own conclusion.
    static func labels(for paths: [String]) -> [String] {
        let names = paths.map { fileName(of: $0) }
        return paths.enumerated().map { index, path in
            let siblings = paths.enumerated()
                .filter { $0.offset != index && names[$0.offset] == names[index] }
                .map(\.element)
            return label(for: path, distinguishedFrom: siblings)
        }
    }

    /// The shortest label for `path` that no entry in `others` shares.
    static func label(for path: String, distinguishedFrom others: [String]) -> String {
        let candidates = candidateLabels(for: path)
        guard !others.isEmpty else { return candidates.first ?? volumeName(of: path) }
        let otherCandidates = others.map(candidateLabels(for:))
        for depth in 0..<candidates.count {
            let candidate = candidates[depth]
            let collides = otherCandidates.contains { other in
                depth < other.count && other[depth] == candidate
            }
            if !collides { return candidate }
        }
        // Every level collided — two entries differ only above the deepest
        // directory shown. Fall back to the full path rather than to a label
        // that is still ambiguous: long and correct beats short and wrong.
        return path
    }

    /// Increasingly specific labels: the volume, then the volume with one
    /// directory, then two, and so on.
    private static func candidateLabels(for path: String) -> [String] {
        let volume = volumeName(of: path)
        let directories = directoryComponents(of: path)
        var labels = [volume]
        var trailing: [String] = []
        for component in directories.reversed() {
            trailing.insert(component, at: 0)
            labels.append(trailing.joined(separator: "/") + " — " + volume)
        }
        return labels
    }

    /// The volume a path sits on, by name. Paths outside `/Volumes` are on the
    /// startup disk, which is worth naming as such rather than leaving blank.
    static func volumeName(of path: String) -> String {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        if parts.count >= 2, parts[0] == "Volumes" { return String(parts[1]) }
        return "This Mac"
    }

    private static func fileName(of path: String) -> String {
        (path as NSString).lastPathComponent
    }

    /// Directory components between the volume root and the file itself.
    private static func directoryComponents(of path: String) -> [String] {
        var parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if !parts.isEmpty { parts.removeLast() }                       // the file
        if parts.count >= 2, parts[0] == "Volumes" { parts.removeFirst(2) }
        return parts
    }
}

nonisolated struct DatasetRecoveryRecord: Codable, Equatable {
    var datasetID: String
    var bookmark: Data
    var selectedX: Int
    var selectedY: Int
    var analysisMode: String
    var updated: Date
}

/// Small UserDefaults-backed index only. Scientific results and large arrays
/// remain in the source/session sidecar; this stores security-scoped bookmarks
/// and enough UI position to recover a window after relaunch.
nonisolated enum WorkspaceRecoveryStore {
    private static let recentKey = "workspace.recent-datasets.v1"
    private static let recoveryKey = "workspace.last-dataset.v1"

    static func recent() -> [RecentDataset] { decode([RecentDataset].self, key: recentKey) ?? [] }
    static func recovery() -> DatasetRecoveryRecord? { decode(DatasetRecoveryRecord.self, key: recoveryKey) }

    static func saveRecent(_ entries: [RecentDataset]) { encode(entries, key: recentKey) }
    static func saveRecovery(_ record: DatasetRecoveryRecord) { encode(record, key: recoveryKey) }
    static func clearRecovery() { UserDefaults.standard.removeObject(forKey: recoveryKey) }

    static func bookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: [.withSecurityScope],
                             includingResourceValuesForKeys: [.nameKey], relativeTo: nil)
    }

    static func resolve(_ bookmark: Data) throws -> (url: URL, stale: Bool) {
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark,
                          options: [.withSecurityScope, .withoutUI],
                          relativeTo: nil, bookmarkDataIsStale: &stale)
        return (url, stale)
    }

    private static func encode<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }

    private static func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
