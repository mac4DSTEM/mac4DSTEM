//
//  FourDDataSource.swift
//  Role: The abstraction over a 4D-STEM data file, so FourDArray and AppState
//        work identically against HDF5 (H5Reader) or Gatan DM4 (DM4Reader).
//
//  All conformers are actors (file access is serialized off the main thread).
//  Reads return Float32 regardless of the on-disk dtype.
//

import Foundation

/// Contiguous scan-row tile in app order `[tileRy,Rx,Qy,Qx]`.
nonisolated struct FourDScanTile: Sendable {
    let yRange: Range<Int>
    let scanWidth: Int
    let detectorHeight: Int
    let detectorWidth: Int
    let pixels: [Float]

    var rowCount: Int { yRange.count }
}

/// Per-position origin arrays read from a py4DSTEM calibration bundle. Values
/// stay in py4DSTEM's detector-axis frame here; AppState performs the single
/// documented qx/qy -> app y/x conversion when activating the dataset.
struct PixelOriginMaps: Sendable {
    /// py4DSTEM real-space array shape [R_Nx, R_Ny].
    var shape: [Int]
    var fittedQX: [Double]
    var fittedQY: [Double]
    var measuredQX: [Double]? = nil
    var measuredQY: [Double]? = nil
}

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

    // py4DSTEM origin/ellipse calibration, kept under py4DSTEM's own names
    // and axis frame to avoid a silent swap: py4DSTEM patterns are indexed
    // (qx, qy) with qx along the FIRST (row) axis, so its qx corresponds to
    // this app's detector y and its qy to this app's detector x. Convert at
    // the point of use, not here.
    /// Mean fitted beam origin along py4DSTEM's qx (first/row) axis, px.
    var qx0Mean: Double? = nil
    /// Mean fitted beam origin along py4DSTEM's qy (second/column) axis, px.
    var qy0Mean: Double? = nil
    /// Elliptical distortion parameters (py4DSTEM keys "a", "b", "theta";
    /// theta in radians).
    var ellipseA: Double? = nil
    var ellipseB: Double? = nil
    var ellipseTheta: Double? = nil
    /// py4DSTEM QR_rotation in radians.
    var qrRotationRad: Double? = nil
    /// Probe radius returned by py4DSTEM probe-size fitting, in detector px.
    var probeSemiangle: Double? = nil
    /// Fitted (and optionally measured) per-position origins from py4DSTEM.
    var originMaps: PixelOriginMaps? = nil
}

protocol FourDDataSource: Actor {
    /// The primary 4D datacube in the file.
    func discoverPrimaryDataset() throws -> DatasetDescriptor
    /// One CBED pattern [Qy*Qx] at scan position (ry, rx).
    func readPattern(_ descriptor: DatasetDescriptor, ry: Int, rx: Int) throws -> [Float]
    /// One scan row [Rx*Qy*Qx] for a fixed ry (chunk-friendly cube streaming).
    func readScanRow(_ descriptor: DatasetDescriptor, ry: Int) throws -> [Float]
    /// Contiguous scan rows `[yRange.count,Rx,Qy,Qx]`. Whole-cube analyses use
    /// this bounded unit instead of requiring a resident float32 datacube.
    func readScanTile(_ descriptor: DatasetDescriptor,
                      yRange: Range<Int>) throws -> FourDScanTile
    /// A scalar attribute (e.g. accelerating voltage), or nil if absent.
    func readDoubleAttribute(_ name: String, onObjectPath path: String) -> Double?
    /// Pixel sizes/units from file metadata, or nil if the format has none.
    func pixelCalibration() -> PixelCalibration?
}
