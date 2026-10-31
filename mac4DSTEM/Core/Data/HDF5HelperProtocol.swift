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
    /// Opens the file; replies with a handle (> 0, random, so never reused by a restarted helper) or 0 and the
    /// sentence that says why not.
    func open(url: URL, seconds: Double, reply: @escaping @Sendable (Int, String?) -> Void)
    /// The datacube the in-process reader would choose (`H5Reader.discoverPrimaryDataset`), as JSON.
    func describePrimaryDataset(handle: Int, seconds: Double, reply: @escaping @Sendable (Data?, String?) -> Void)
    /// Releases the handle; unknown handles are ignored.
    func close(handle: Int, reply: @escaping @Sendable () -> Void)
    /// Tests only (`HDF5HelperFault`): replies false at once when the fault is not honoured (a Release helper, or the
    /// service running in process).
    func injectFault(_ kind: Int, seconds: Double, reply: @escaping @Sendable (Bool) -> Void)
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
