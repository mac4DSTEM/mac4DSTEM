//
//  HDF5HelperProtocol.swift
//  Role: the XPC interface of the HDF5 helper (`HDF5Helper.xpc`, embedded in the app) and the values that cross it.
//        Every libhdf5 call for a file opened through the helper runs in that process: a crafted file that crashes or
//        hangs libhdf5 ends the helper, and the app gets an error sentence (docs/hdf5-helper.md).
//        Slice 1: open, describe the primary dataset, close. Reads come in slice 2.
//

import Foundation

/// The helper's XPC interface. Each call carries the seconds the helper's watchdog allows it; a call still running past
/// them ends the helper process (`_exit`), the only way to stop a libhdf5 call that does not return. Replies carry an
/// error sentence, nil on success; structured values cross as JSON (`HDF5HelperDataset`).
@objc package nonisolated protocol HDF5HelperXPC {
    /// Opens the file named by `bookmark` (`HDF5HelperBookmark`); replies with a handle (> 0, random, so never reused by a
    /// restarted helper) or 0 and the sentence that says why not. A bookmark, not a URL: the helper has its own
    /// sandbox, and the bookmark carries the app's access to the file the user chose.
    func open(bookmark: Data, seconds: Double, reply: @escaping @Sendable (Int, String?) -> Void)
    /// The datacube the in-process reader would choose (`H5Reader.discoverPrimaryDataset`), as JSON.
    func describePrimaryDataset(handle: Int, seconds: Double, reply: @escaping @Sendable (Data?, String?) -> Void)
    /// Releases the handle; unknown handles are ignored.
    func close(handle: Int, reply: @escaping @Sendable () -> Void)
    /// Tests only (`HDF5HelperFault`): replies false at once when the fault is not honoured (a Release helper, or the
    /// service running in process).
    func injectFault(_ kind: Int, seconds: Double, reply: @escaping @Sendable (Bool) -> Void)
}

/// How the file crosses to the helper. The app (which holds the user's access to the file: an open panel's URL, or a
/// security-scoped URL it is accessing) makes the bookmark; the helper resolves it and starts accessing the URL as a
/// security-scoped resource for as long as it holds the file. The bookmark is made without `.withSecurityScope`: that
/// kind resolves only in the app that made it, and the helper is another bundle. A plain bookmark made by a sandboxed
/// process carries a sandbox extension for the file, which the resolving process consumes with
/// `startAccessingSecurityScopedResource()`.
package nonisolated enum HDF5HelperBookmark {
    /// The bookmark for `url` (`.securityScopeAllowOnlyReadAccess` applies only with `.withSecurityScope`, so none).
    package static func make(_ url: URL) throws -> Data {
        try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// The URL the bookmark names; the caller starts and stops accessing it.
    package static func resolve(_ bookmark: Data) throws -> URL {
        var stale = false
        return try URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], relativeTo: nil,
                       bookmarkDataIsStale: &stale)
    }
}

/// What a test asks the helper to do to itself. Debug builds of the helper honour it; Release builds ignore it.
package nonisolated enum HDF5HelperFault: Int, Sendable {
    /// The process ends at once, as a libhdf5 crash would end it.
    case crash = 1
    /// Blocks inside a watched call, as a libhdf5 call that never returns would; the watchdog then ends the helper.
    case hang = 2
}

/// The primary dataset as it crosses the connection. The file path stays the app's: the helper may see the file under
/// another path, and the app's `DatasetDescriptor` names the file the user opened.
package nonisolated struct HDF5HelperDataset: Codable, Equatable, Sendable {
    package var datasetPath: String
    package var shape: [Int]
    package var dtypeDescription: String
    package var chunkShape: [Int]?
    package var storedRank: Int

    package init(_ descriptor: DatasetDescriptor) {
        datasetPath = descriptor.datasetPath
        shape = descriptor.shape
        dtypeDescription = descriptor.dtypeDescription
        chunkShape = descriptor.chunkShape
        storedRank = descriptor.storedRank
    }

    package func descriptor(filePath: String) -> DatasetDescriptor {
        DatasetDescriptor(filePath: filePath, datasetPath: datasetPath, shape: shape, dtypeDescription: dtypeDescription,
                          chunkShape: chunkShape, storedRank: storedRank)
    }
}
