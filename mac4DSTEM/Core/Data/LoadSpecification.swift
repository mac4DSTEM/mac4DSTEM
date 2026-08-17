//
//  LoadSpecification.swift
//  Role: *What part of the source file is being loaded* — a real-space crop, a
//        diffraction crop, and (from L4) a diffraction bin factor.
//
//  A LOAD IS A VIEW, NOT A NEW DATASET (decided 2026-08-17, docs/v2-scope.md
//  §6.1). The source file is never modified and its full extent stays reachable;
//  changing the specification reopens, it does not re-derive from reduced data.
//  That is what makes "validate on a cropped, binned view, then re-run on the
//  full dataset" work: REMOVING the specification *is* the promotion to full
//  extent. If a reduced cube were a new dataset, re-running at full extent would
//  mean redoing the analysis from scratch — the manual step this app exists to
//  remove.
//
//  DEVIATION from py4DSTEM (preprocess.crop_data_diffraction /
//  bin_data_diffraction, References/py4DSTEM-dev/py4DSTEM/preprocess/preprocess.py:139,155):
//  py4DSTEM mutates the datacube in place and leaves the fitted origin (qx0/qy0)
//  referring to the old detector frame; bin additionally rescales Q_pixel_size
//  but not the origin. Here the origin is a per-position fitted map that feeds
//  disk detection, strain and ACOM, so a silently stale origin would fabricate
//  results rather than merely mislabel them. This app applies the specification
//  at READ time and re-references every detector-frame calibration value against
//  the new frame, or invalidates it explicitly with a named reason.
//

import Foundation

/// A half-open rectangle in one plane, in source-file pixel coordinates.
///
/// Stored as offset + extent rather than as `Range` pairs so it is trivially
/// `Codable` and `Equatable` — this value is written into session sidecars and
/// every export, and compared to decide whether a resident buffer is stale.
struct AxisCrop: Equatable, Sendable, Codable {
    /// Offset from the source origin, in source pixels.
    var yOffset: Int
    var xOffset: Int
    /// Extent of the view, in source pixels.
    var height: Int
    var width: Int

    var yRange: Range<Int> { yOffset..<(yOffset + height) }
    var xRange: Range<Int> { xOffset..<(xOffset + width) }

    var isEmpty: Bool { height <= 0 || width <= 0 }
}

/// What part of the source is loaded. `nil` crops mean "the whole axis".
struct LoadSpecification: Equatable, Sendable, Codable {
    /// Real-space (scan) crop. nil = the whole scan.
    var scanCrop: AxisCrop?
    /// Diffraction-space (detector) crop. nil = the whole detector.
    var detectorCrop: AxisCrop?
    /// Diffraction bin factor. 1 = none. L4 offers 2, 4 and 8 only.
    var detectorBin: Int = 1

    static let fullExtent = LoadSpecification()

    /// True when this loads the file exactly as stored.
    ///
    /// The property the whole design rests on: a specification equal to
    /// `.fullExtent` is indistinguishable from not having one, so promoting a
    /// rehearsal to the full dataset is *removing* the specification, not
    /// converting a derived file back into a source.
    var isFullExtent: Bool {
        scanCrop == nil && detectorCrop == nil && detectorBin == 1
    }
}

/// How much of a specification a reader was able to push into its own I/O.
///
/// **This exists so the saving is never overstated.** Cropping at read time
/// saves memory *and* I/O only when the reader can skip the bytes. HDF5 can, on
/// all four axes, via the hyperslab it already builds. The raw formats
/// (DM4, MIB, EMPAD) store patterns contiguously, so a *scan* crop is a
/// contiguous seek and does skip bytes, while a *detector* crop would need many
/// small strided reads within each frame — so those readers slice after reading
/// and save memory only.
///
/// Decided 2026-08-18: push down where it pays, slice where it does not, and
/// have every reader *declare which*, rather than letting the app claim an I/O
/// saving it did not get. A reader that silently ignores a specification is the
/// defect this type is designed against — three of the five conformers ignore
/// the descriptor they are handed today.
struct LoadPushdown: Equatable, Sendable, Codable {
    /// The reader skipped the cropped-out scan positions on disk.
    var scanCropSkipsIO: Bool
    /// The reader skipped the cropped-out detector pixels on disk.
    var detectorCropSkipsIO: Bool

    /// Everything pushed down — HDF5's hyperslab.
    static let full = LoadPushdown(scanCropSkipsIO: true, detectorCropSkipsIO: true)
    /// Scan crop seeks, detector crop is sliced after the read — raw formats.
    static let scanOnly = LoadPushdown(scanCropSkipsIO: true, detectorCropSkipsIO: false)
    /// Nothing skipped; the specification is applied entirely in memory.
    static let none = LoadPushdown(scanCropSkipsIO: false, detectorCropSkipsIO: false)
}
