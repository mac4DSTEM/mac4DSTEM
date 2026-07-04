//
//  DatasetDescriptor.swift
//  Role: Immutable description of one HDF5 dataset we might analyze.
//
//  Holds the shape ([Ry, Rx, Qy, Qx] for a 4DSTEM cube), a human-readable
//  dtype string, chunk layout, and the file/dataset paths. This is a pure
//  value type (struct) — exactly the kind of thing the code-quality rules
//  ask us to model with `struct`.
//

import Foundation

// MARK: - DatasetDescriptor

struct DatasetDescriptor: Identifiable, Hashable {
    let id = UUID()

    /// Absolute path to the .h5 file on disk.
    let filePath: String
    /// Internal HDF5 path to the dataset, e.g. "/4DSTEM_experiment/.../data".
    let datasetPath: String
    /// Dataset dimensions in HDF5 order. For 4DSTEM: [Ry, Rx, Qy, Qx].
    let shape: [Int]
    /// e.g. "float32", "float64", "uint16".
    let dtypeDescription: String
    /// Chunk dimensions if the dataset is chunked, else nil (contiguous).
    let chunkShape: [Int]?

    // MARK: Convenience accessors (4DSTEM semantics)

    var is4D: Bool { shape.count == 4 }

    var ry: Int { is4D ? shape[0] : 0 }   // real-space scan rows
    var rx: Int { is4D ? shape[1] : 0 }   // real-space scan cols
    var qy: Int { is4D ? shape[2] : 0 }   // detector rows
    var qx: Int { is4D ? shape[3] : 0 }   // detector cols

    /// Bytes if the full cube were resident as float32.
    var byteCountAsFloat32: Int { shape.reduce(1, *) * 4 }

    var shapeString: String { shape.map(String.init).joined(separator: " × ") }

    var fileName: String { (filePath as NSString).lastPathComponent }
}
