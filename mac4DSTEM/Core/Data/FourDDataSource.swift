//
//  FourDDataSource.swift
//  Role: The abstraction over a 4D-STEM data file, so FourDArray and AppState
//        work identically against HDF5 (H5Reader) or Gatan DM4 (DM4Reader).
//
//  All conformers are actors (file access is serialized off the main thread).
//  Reads return Float32 regardless of the on-disk dtype.
//

import Foundation

/// Pixel-size calibration read from the file, when the format carries it
/// (DM4 does; plain HDF5 usually doesn't). Units are the file's own strings
/// (Gatan: "nm" real-space, "1/nm" diffraction).
struct PixelCalibration: Sendable {
    var rSize: Double?
    var rUnits: String?
    var qSize: Double?
    var qUnits: String?
    /// py4DSTEM QR_flip (detector axes transposed relative to scan), if stored.
    var qrFlip: Bool?
}

protocol FourDDataSource: Actor {
    /// The primary 4D datacube in the file.
    func discoverPrimaryDataset() throws -> DatasetDescriptor
    /// One CBED pattern [Qy*Qx] at scan position (ry, rx).
    func readPattern(_ descriptor: DatasetDescriptor, ry: Int, rx: Int) throws -> [Float]
    /// One scan row [Rx*Qy*Qx] for a fixed ry (chunk-friendly cube streaming).
    func readScanRow(_ descriptor: DatasetDescriptor, ry: Int) throws -> [Float]
    /// A scalar attribute (e.g. accelerating voltage), or nil if absent.
    func readDoubleAttribute(_ name: String, onObjectPath path: String) -> Double?
    /// Pixel sizes/units from file metadata, or nil if the format has none.
    func pixelCalibration() -> PixelCalibration?
}
