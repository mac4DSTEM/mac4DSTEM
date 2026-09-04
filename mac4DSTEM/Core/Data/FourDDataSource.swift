//
//  FourDDataSource.swift
//  Role: The abstraction over a 4D-STEM data file, so FourDArray and AppState
//        work identically against HDF5 (H5Reader) or Gatan DM4 (DM4Reader).
//
//  All conformers are actors (file access is serialized off the main thread).
//  Reads return Float32 regardless of the on-disk dtype.
//

import Foundation

/// How a data file is named in a message the user reads.
///
/// The readers all knew the file by its absolute path and printed it. On a
/// public repo, in a screenshot, in a pasted bug report, that path is the
/// user's home directory, their volume names and their folder structure —
/// none of which helps them fix a file that will not open. The message names
/// the file; the log and the recents list still hold the whole path.
package nonisolated func displayFileName(_ path: String) -> String {
    let name = (path as NSString).lastPathComponent
    return name.isEmpty ? path : name
}

/// Contiguous scan-row tile in app order `[tileRy,Rx,Qy,Qx]`.
package nonisolated struct FourDScanTile: Sendable {
    package let yRange: Range<Int>
    package let scanWidth: Int
    package let detectorHeight: Int
    package let detectorWidth: Int
    package let pixels: [Float]

    package var rowCount: Int { yRange.count }

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(yRange: Range<Int>, scanWidth: Int, detectorHeight: Int, detectorWidth: Int, pixels: [Float]) {
        self.yRange = yRange
        self.scanWidth = scanWidth
        self.detectorHeight = detectorHeight
        self.detectorWidth = detectorWidth
        self.pixels = pixels
    }
}

/// Per-position origin arrays read from a py4DSTEM calibration bundle. Values
/// stay in py4DSTEM's detector-axis frame here; AppState performs the single
/// documented qx/qy -> app y/x conversion when activating the dataset.
package nonisolated struct PixelOriginMaps: Sendable {
    /// py4DSTEM real-space array shape [R_Nx, R_Ny].
    package var shape: [Int]
    package var fittedQX: [Double]
    package var fittedQY: [Double]
    package var measuredQX: [Double]? = nil
    package var measuredQY: [Double]? = nil

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(shape: [Int], fittedQX: [Double], fittedQY: [Double], measuredQX: [Double]? = nil, measuredQY: [Double]? = nil) {
        self.shape = shape
        self.fittedQX = fittedQX
        self.fittedQY = fittedQY
        self.measuredQX = measuredQX
        self.measuredQY = measuredQY
    }
}

/// Pixel-size calibration read from the file, when the format carries it
/// (DM4 does; plain HDF5 usually doesn't). Units are the file's own strings
/// (Gatan: "nm" real-space, "1/nm" diffraction).
package nonisolated struct PixelCalibration: Sendable {
    package var rSize: Double?
    package var rUnits: String?
    package var qSize: Double?
    package var qUnits: String?
    /// py4DSTEM QR_flip (detector axes transposed relative to scan), if stored.
    package var qrFlip: Bool?

    // py4DSTEM origin/ellipse calibration, kept under py4DSTEM's own names
    // and axis frame to avoid a silent swap: py4DSTEM patterns are indexed
    // (qx, qy) with qx along the FIRST (row) axis, so its qx corresponds to
    // this app's detector y and its qy to this app's detector x. Convert at
    // the point of use, not here.
    /// Mean fitted beam origin along py4DSTEM's qx (first/row) axis, px.
    package var qx0Mean: Double? = nil
    /// Mean fitted beam origin along py4DSTEM's qy (second/column) axis, px.
    package var qy0Mean: Double? = nil
    /// Elliptical distortion parameters (py4DSTEM keys "a", "b", "theta";
    /// theta in radians).
    package var ellipseA: Double? = nil
    package var ellipseB: Double? = nil
    package var ellipseTheta: Double? = nil
    /// py4DSTEM QR_rotation in radians.
    package var qrRotationRad: Double? = nil
    /// Probe radius returned by py4DSTEM probe-size fitting, in detector px.
    package var probeSemiangle: Double? = nil
    /// Fitted (and optionally measured) per-position origins from py4DSTEM.
    package var originMaps: PixelOriginMaps? = nil

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(rSize: Double? = nil, rUnits: String? = nil, qSize: Double? = nil, qUnits: String? = nil, qrFlip: Bool? = nil, qx0Mean: Double? = nil, qy0Mean: Double? = nil, ellipseA: Double? = nil, ellipseB: Double? = nil, ellipseTheta: Double? = nil, qrRotationRad: Double? = nil, probeSemiangle: Double? = nil, originMaps: PixelOriginMaps? = nil) {
        self.rSize = rSize
        self.rUnits = rUnits
        self.qSize = qSize
        self.qUnits = qUnits
        self.qrFlip = qrFlip
        self.qx0Mean = qx0Mean
        self.qy0Mean = qy0Mean
        self.ellipseA = ellipseA
        self.ellipseB = ellipseB
        self.ellipseTheta = ellipseTheta
        self.qrRotationRad = qrRotationRad
        self.probeSemiangle = probeSemiangle
        self.originMaps = originMaps
    }
}

package protocol FourDDataSource: Actor {
    /// The primary 4D datacube in the file, at **full extent**. A crop is a
    /// `LoadView` of this, never a different discovery result.
    func discoverPrimaryDataset() throws -> DatasetDescriptor

    /// What this reader pushes into its own I/O for **this view**, versus
    /// applies in memory.
    ///
    /// **Declared, never assumed** (decided 2026-08-18), and it takes the view
    /// because the answer is not a property of the format alone: HDF5's
    /// hyperslab skips cropped-out bytes on a *contiguous* dataset, but a
    /// chunked one is read and decompressed a whole chunk at a time, so a crop
    /// inside a chunk skips nothing. Measured 2026-08-18 on a gzip-chunked
    /// (16,16,256,256) f4 dataset with chunks (1,16,256,256): reading 1/64 of
    /// the detector pixels took 0.135 s against 0.137 s for all of them. The raw
    /// formats store patterns contiguously, so a scan crop is a seek but a
    /// detector crop is a slice after the read.
    ///
    /// The app records this in provenance, so the saving is never overstated —
    /// which is the whole reason the declaration exists rather than being
    /// inferred from the format name.
    nonisolated func loadPushdown(for view: LoadView) -> LoadPushdown

    // Every read takes a `LoadView`, not a bare descriptor. All scan and
    // detector indices below are in **view** coordinates, starting at 0; the
    // reader adds the view's offsets to reach the source. Passing the view
    // rather than the descriptor is what stops a reader from being handed a
    // cropped shape with no idea where that shape sits in the file — the state
    // three of these conformers were in before 2026-08-18, when the descriptor
    // was accepted and never read.

    /// One CBED pattern [Qy*Qx] at view scan position (ry, rx).
    func readPattern(_ view: LoadView, ry: Int, rx: Int) throws -> [Float]
    /// One view scan row [Rx*Qy*Qx] for a fixed ry (chunk-friendly streaming).
    func readScanRow(_ view: LoadView, ry: Int) throws -> [Float]
    /// Contiguous view scan rows `[yRange.count,Rx,Qy,Qx]`. Whole-cube analyses
    /// use this bounded unit instead of requiring a resident float32 datacube.
    func readScanTile(_ view: LoadView,
                      yRange: Range<Int>) throws -> FourDScanTile
    /// A scalar attribute (e.g. accelerating voltage), or nil if absent.
    func readDoubleAttribute(_ name: String, onObjectPath path: String) -> Double?
    /// Pixel sizes/units from file metadata, or nil if the format has none.
    func pixelCalibration() -> PixelCalibration?
}
