import Foundation

nonisolated struct RecentDataset: Codable, Identifiable, Hashable {
    let id: String
    var displayName: String
    var bookmark: Data
    var lastOpened: Date
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
