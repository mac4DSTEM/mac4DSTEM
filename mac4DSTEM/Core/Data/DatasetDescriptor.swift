import Foundation

struct DatasetDescriptor: Identifiable, Hashable {
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

    var is4D: Bool { shape.count == 4 }

    var ry: Int { is4D ? shape[0] : 0 }
    var rx: Int { is4D ? shape[1] : 0 }
    var qy: Int { is4D ? shape[2] : 0 }
    var qx: Int { is4D ? shape[3] : 0 }

    /// Bytes if the full cube were resident as float32.
    var byteCountAsFloat32: Int { shape.reduce(1, *) * 4 }

    var shapeString: String { shape.map(String.init).joined(separator: " x ") }

    var fileName: String { (filePath as NSString).lastPathComponent }
}
