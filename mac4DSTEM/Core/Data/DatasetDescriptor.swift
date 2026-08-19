import Foundation

// `nonisolated` on the TYPE, so the synthesized `Hashable`/`Equatable`
// conformances are too: the app builds with MainActor default isolation, and
// an isolated conformance used from the readers' nonisolated contexts is an
// error in the Swift 6 language mode. The per-member markers predate this and
// stay — they are what the members mean. // v2 S3
nonisolated struct DatasetDescriptor: Identifiable, Hashable {
    let id = UUID()

    /// Absolute path to the .h5 file on disk.
    let filePath: String
    /// Internal HDF5 path to the dataset, e.g. "/4DSTEM_experiment/.../data".
    let datasetPath: String
    /// Dataset dimensions in HDF5 order. For 4D-STEM: [Ry, Rx, Qy, Qx].
    let shape: [Int]
    /// e.g. "float32", "float64", "uint16".
    let dtypeDescription: String
    /// Chunk dimensions if the dataset is chunked, else nil for contiguous data.
    let chunkShape: [Int]?

    nonisolated var is4D: Bool { shape.count == 4 }

    nonisolated var ry: Int { is4D ? shape[0] : 0 }
    nonisolated var rx: Int { is4D ? shape[1] : 0 }
    nonisolated var qy: Int { is4D ? shape[2] : 0 }
    nonisolated var qx: Int { is4D ? shape[3] : 0 }

    /// Bytes if the full cube were resident as float32.
    nonisolated var byteCountAsFloat32: Int { shape.reduce(1, *) * 4 }

    nonisolated var shapeString: String { shape.map(String.init).joined(separator: " x ") }

    nonisolated var fileName: String { (filePath as NSString).lastPathComponent }
}
