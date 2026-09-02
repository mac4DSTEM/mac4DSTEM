import Foundation
import DSTEMCore

package nonisolated struct RecentDataset: Codable, Identifiable, Hashable {
    package let id: String
    package var displayName: String
    package var bookmark: Data
    package var lastOpened: Date

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package init(id: String, displayName: String, bookmark: Data, lastOpened: Date) {
        self.id = id
        self.displayName = displayName
        self.bookmark = bookmark
        self.lastOpened = lastOpened
    }
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
package nonisolated enum RecentDatasetLocation {

    /// A label per path, in the same order, each the shortest form that
    /// distinguishes it from every other entry sharing its file name.
    ///
    /// Pure string work on the stored path — no file-system access. That is
    /// deliberate: this runs while drawing the welcome screen, the volumes
    /// involved may be unmounted, and asking the disk about a NAS that is not
    /// there would stall the first screen of the app. It also means this cannot
    /// claim a volume is "on the network", which would need a real query; the
    /// volume NAME is shown and the reader draws their own conclusion.
    package static func labels(for paths: [String]) -> [String] {
        let names = paths.map { fileName(of: $0) }
        return paths.enumerated().map { index, path in
            let siblings = paths.enumerated()
                .filter { $0.offset != index && names[$0.offset] == names[index] }
                .map(\.element)
            return label(for: path, distinguishedFrom: siblings)
        }
    }

    /// The shortest label for `path` that no entry in `others` shares.
    package static func label(for path: String, distinguishedFrom others: [String]) -> String {
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
    package static func volumeName(of path: String) -> String {
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

package nonisolated struct DatasetRecoveryRecord: Codable, Equatable {
    package var datasetID: String
    package var bookmark: Data
    package var selectedX: Int
    package var selectedY: Int
    package var analysisMode: String
    package var updated: Date
    /// The load specification whose FRAME `selectedX/Y` are expressed in.
    /// A position is only meaningful in the view it was selected in: after a
    /// promote the coordinates are full-extent, after a sidecar restore the
    /// view is the rehearsal crop, and clamping one frame's position into the
    /// other manufactured "a defensible pixel the user never chose" (S3's
    /// carried finding, fixed v2 S5). Nil = written by an older build, frame
    /// unknown — the restore applies the position only if it fits, and drops
    /// it otherwise. Optional so old persisted records still decode.
    package var loadSpecification: LoadSpecification? = nil

    /// The recorded position, applied only when it is honest in the view
    /// being restored: the same SCAN frame (when the record knows its frame)
    /// and inside the extents. Nil means "no honest position" — the caller
    /// keeps its default. NEVER clamp: a position clamped across frames is a
    /// defensible pixel the user never chose, which reads as their selection
    /// and is not.
    ///
    /// Only `scanCrop` is compared: scan coordinates live in the scan crop's
    /// frame, and a detector crop or bin moves no scan index — a whole-spec
    /// comparison dropped honest positions on detector-only changes
    /// (Gate B-lite F13). Pure, so the tests can pin every branch. // v2 S5
    package nonisolated func position(
        inViewWith specification: LoadSpecification, rx: Int, ry: Int
    ) -> (x: Int, y: Int)? {
        if let frame = loadSpecification, frame.scanCrop != specification.scanCrop {
            return nil
        }
        guard rx > 0, ry > 0,
              (0..<rx).contains(selectedX), (0..<ry).contains(selectedY) else { return nil }
        return (selectedX, selectedY)
    }

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package init(datasetID: String, bookmark: Data, selectedX: Int, selectedY: Int, analysisMode: String, updated: Date, loadSpecification: LoadSpecification? = nil) {
        self.datasetID = datasetID
        self.bookmark = bookmark
        self.selectedX = selectedX
        self.selectedY = selectedY
        self.analysisMode = analysisMode
        self.updated = updated
        self.loadSpecification = loadSpecification
    }
}

/// Small UserDefaults-backed index only. Scientific results and large arrays
/// remain in the source/session sidecar; this stores security-scoped bookmarks
/// and enough UI position to recover a window after relaunch.
package nonisolated enum WorkspaceRecoveryStore {
    private static let recentKey = "workspace.recent-datasets.v1"
    private static let recoveryKey = "workspace.last-dataset.v1"

    package static func recent() -> [RecentDataset] { decode([RecentDataset].self, key: recentKey) ?? [] }
    package static func recovery() -> DatasetRecoveryRecord? { decode(DatasetRecoveryRecord.self, key: recoveryKey) }

    package static func saveRecent(_ entries: [RecentDataset]) { encode(entries, key: recentKey) }
    package static func saveRecovery(_ record: DatasetRecoveryRecord) { encode(record, key: recoveryKey) }
    package static func clearRecovery() { UserDefaults.standard.removeObject(forKey: recoveryKey) }

    package static func bookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: [.withSecurityScope],
                             includingResourceValuesForKeys: [.nameKey], relativeTo: nil)
    }

    package static func resolve(_ bookmark: Data) throws -> (url: URL, stale: Bool) {
        var stale = false
        // `.withoutMounting` is load-bearing (Gate D, 2026-08-25): resolving
        // a bookmark whose volume is an unreachable network share otherwise
        // BLOCKS while the system attempts to mount it — measured at 30.03 s
        // on this machine's own stored NAS recents entry, 2026-08-25; the
        // reproducible pin is `BookmarkResolutionLatencyTests`, which drives
        // every stored bookmark — and every caller of this function runs on
        // the main actor, so each attempt freezes the whole UI for that
        // long; queued clicks then serialize into minutes. An unmounted
        // volume must resolve to a fast failure ("no longer accessible"),
        // never to a silent mount attempt.
        let url = try URL(resolvingBookmarkData: bookmark,
                          options: [.withSecurityScope, .withoutUI, .withoutMounting],
                          relativeTo: nil, bookmarkDataIsStale: &stale)
        return (url, stale)
    }

    /// The volume name a failed resolution is waiting on, or nil when the
    /// bookmark's target is not on an absent `/Volumes/…` mount.
    ///
    /// Read from the bookmark's EMBEDDED path — `resourceValues(forKeys:
    /// fromBookmarkData:)` never touches the filesystem the way resolution
    /// does, so this is safe to call in a catch block on the main actor.
    /// Exists so the two resolution catch blocks can tell "the file is gone"
    /// (forget the bookmark) from "the volume is not mounted right now"
    /// (KEEP it) — the Gate D second reader caught both catches destroying
    /// state on a merely-unplugged NAS (2026-08-25): a recents row deleted
    /// with its volume label, and a chosen sidecar grant silently forgotten,
    /// which re-arms the silent-full-extent reopen through a new trigger.
    package static func unmountedVolumeName(forBookmark bookmark: Data) -> String? {
        guard let path = URL.resourceValues(
                forKeys: [.pathKey], fromBookmarkData: bookmark
              )?.path,
              path.hasPrefix("/Volumes/") else { return nil }
        let components = path.split(separator: "/")
        guard components.count >= 2 else { return nil }
        let volume = String(components[1])
        return FileManager.default.fileExists(atPath: "/Volumes/\(volume)")
            ? nil : volume
    }

    private static func encode<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }

    private static func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
