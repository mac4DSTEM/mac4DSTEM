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

// EVERYTHING IN THIS FILE IS `nonisolated`. The app target sets
// SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor, so a bare `struct` here would be
// MainActor-isolated — and every one of these types is handed to the five
// reader ACTORS on every read. Without this, the readers make cross-actor calls
// for plain value types, which Swift 5 mode reports as 35 warnings (three
// classes of them "this is an error in the Swift 6 language mode") and Swift 6
// would reject outright. The neighbouring value types that cross the same
// boundary — `FourDScanTile`, `ResidentCube`, `CalibratedDataCubeExportOptions`
// — are all explicitly `nonisolated` for the same reason.
//
// It is invisible to `tools/load-spec-test`, which compiles this file with bare
// `swiftc` (default *nonisolated*) and therefore validates different isolation
// semantics from the app. Found by adversarial review 2026-08-18; the app build
// is the only place it shows.

/// A half-open rectangle in one plane, in source-file pixel coordinates.
///
/// Stored as offset + extent rather than as `Range` pairs so it is trivially
/// `Codable` and `Equatable` — this value is written into session sidecars and
/// every export, and compared to decide whether a resident buffer is stale.
nonisolated struct AxisCrop: Equatable, Sendable, Codable {
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
nonisolated struct LoadSpecification: Equatable, Sendable, Codable {
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
nonisolated struct LoadPushdown: Equatable, Sendable, Codable {
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

// MARK: - Geometry

nonisolated extension AxisCrop {
    /// Whether this crop fits inside a `height` x `width` source plane.
    func fits(height: Int, width: Int) -> Bool {
        yOffset >= 0 && xOffset >= 0 && self.height > 0 && self.width > 0
            && yOffset + self.height <= height
            && xOffset + self.width <= width
    }
}

nonisolated extension LoadSpecification {
    /// Offset of the view's first scan position within the source scan.
    var scanOffset: (y: Int, x: Int) {
        (scanCrop?.yOffset ?? 0, scanCrop?.xOffset ?? 0)
    }

    /// Offset of the view's first detector pixel within the source detector.
    var detectorOffset: (y: Int, x: Int) {
        (detectorCrop?.yOffset ?? 0, detectorCrop?.xOffset ?? 0)
    }
}

/// Why a specification cannot be applied to a source, or to a reader.
///
/// **Every one of these is a refusal, never a fallback.** A specification that
/// cannot be honoured must stop the read: a reader that quietly returned the
/// full extent, or the right number of pixels from the wrong place, would
/// fabricate a result rather than fail — the defect this stage is designed
/// against (docs/load-pipeline-plan.md §6, L3 correction 2026-08-18).
nonisolated enum LoadSpecificationError: LocalizedError, Equatable {
    case notFourDimensional([Int])
    case scanCropOutOfBounds(AxisCrop, sourceHeight: Int, sourceWidth: Int)
    case detectorCropOutOfBounds(AxisCrop, sourceHeight: Int, sourceWidth: Int)
    case binningNotAvailable(Int)
    /// A reader was handed a view of a file it did not open, or of a shape it
    /// did not discover.
    case sourceMismatch(expected: [Int], received: [Int])
    /// A reader that cannot apply a specification at all was handed one.
    case unsupportedByReader(String)

    var errorDescription: String? {
        switch self {
        case .notFourDimensional(let shape):
            return "A load specification needs a 4D dataset; this one is \(shape.count)D."
        case .scanCropOutOfBounds(let crop, let h, let w):
            return "The scan crop (\(crop.height)x\(crop.width) at y \(crop.yOffset), x \(crop.xOffset)) does not fit the \(h)x\(w) scan."
        case .detectorCropOutOfBounds(let crop, let h, let w):
            return "The diffraction crop (\(crop.height)x\(crop.width) at y \(crop.yOffset), x \(crop.xOffset)) does not fit the \(h)x\(w) detector."
        case .binningNotAvailable(let factor):
            return "Diffraction binning (factor \(factor)) is not available yet."
        case .sourceMismatch(let expected, let received):
            return "This reader holds a \(expected.map(String.init).joined(separator: " x ")) dataset, but was handed a view of \(received.map(String.init).joined(separator: " x "))."
        case .unsupportedByReader(let detail):
            return "This data source cannot apply a load specification: \(detail)"
        }
    }
}

/// A source dataset paired with the specification that selects part of it, and
/// the descriptor of what that selection actually is.
///
/// **The three are constructed together, and that is the whole reason this type
/// exists.** A reader handed a *cropped* descriptor and a `.fullExtent`
/// specification would read the right number of pixels from the wrong place in
/// the file — the same length, so every length check downstream passes, and the
/// numbers are simply about different data. Passing a descriptor and a
/// specification as two parameters makes that mistake expressible at every call
/// site; deriving `descriptor` inside `init(source:specification:)` removes it
/// from all of them.
///
/// **It is not unrepresentable, and an earlier version of this comment claimed
/// it was.** `init(fullExtentOf:)` below takes any descriptor without
/// validating it, so handing it an already-cropped descriptor reconstructs
/// exactly the forbidden pair. What catches that is `requireSource` at the first
/// read — a refusal, loudly, rather than a wrong number — not the type. Stated
/// accurately here because a guarantee that is really a runtime check is the
/// kind of claim this repository has been burned by. (Adversarial review,
/// 2026-08-18.)
///
/// Coordinates: `descriptor` extents and every `ry`/`rx`/`yRange` a reader is
/// given are in **view** coordinates, starting at 0. Readers add
/// `specification.scanOffset` / `detectorOffset` to reach the source.
nonisolated struct LoadView: Sendable {
    /// The dataset as stored in the file, at full extent.
    let source: DatasetDescriptor
    /// Which part of `source` is loaded.
    let specification: LoadSpecification
    /// The shape being processed. Identical to `source` — the same value, not a
    /// copy — when the specification is full extent, so that removing a
    /// specification restores the original dataset identity exactly.
    let descriptor: DatasetDescriptor

    /// Validate `specification` against `source` and derive the view.
    ///
    /// Throws rather than clamping: a crop that does not fit is a caller
    /// mistake, and silently shrinking it would change what was measured
    /// without saying so.
    init(source: DatasetDescriptor, specification: LoadSpecification) throws {
        guard source.is4D else {
            throw LoadSpecificationError.notFourDimensional(source.shape)
        }
        guard specification.detectorBin == 1 else {
            // L4 lifts this. Until it does, refusing is the only honest answer:
            // returning unbinned pixels for a binned request would put every
            // intensity threshold downstream off by bin_factor^2.
            throw LoadSpecificationError.binningNotAvailable(specification.detectorBin)
        }
        if let scanCrop = specification.scanCrop {
            guard scanCrop.fits(height: source.ry, width: source.rx) else {
                throw LoadSpecificationError.scanCropOutOfBounds(
                    scanCrop, sourceHeight: source.ry, sourceWidth: source.rx
                )
            }
        }
        if let detectorCrop = specification.detectorCrop {
            guard detectorCrop.fits(height: source.qy, width: source.qx) else {
                throw LoadSpecificationError.detectorCropOutOfBounds(
                    detectorCrop, sourceHeight: source.qy, sourceWidth: source.qx
                )
            }
        }
        self.source = source
        self.specification = specification
        if specification.isFullExtent {
            self.descriptor = source
        } else {
            self.descriptor = DatasetDescriptor(
                filePath: source.filePath,
                datasetPath: source.datasetPath,
                shape: [
                    specification.scanCrop?.height ?? source.ry,
                    specification.scanCrop?.width ?? source.rx,
                    specification.detectorCrop?.height ?? source.qy,
                    specification.detectorCrop?.width ?? source.qx,
                ],
                dtypeDescription: source.dtypeDescription,
                // The file's chunking, carried unchanged: it describes how the
                // SOURCE is stored, which is what a reader plans its I/O
                // against. It is not a claim about the view's own layout.
                chunkShape: source.chunkShape
            )
        }
    }

    /// The whole dataset, no crop — the shipped path, since production sets no
    /// specification until L5's configurator.
    ///
    /// **Non-validating**, which is why it cannot fail and why it is the hole in
    /// the guarantee above: it trusts that `source` really is a full-extent
    /// descriptor. Readers re-check with `requireSource` against the shape they
    /// discovered themselves, so a wrong descriptor becomes a refusal at the
    /// first read rather than a silently misplaced one.
    init(fullExtentOf source: DatasetDescriptor) {
        self.source = source
        self.specification = .fullExtent
        self.descriptor = source
    }

    var isFullExtent: Bool { specification.isFullExtent }

    /// Source scan row for a view scan row.
    func sourceScanY(_ viewY: Int) -> Int { specification.scanOffset.y + viewY }
    /// Source scan column for a view scan column.
    func sourceScanX(_ viewX: Int) -> Int { specification.scanOffset.x + viewX }

    /// Take the detector crop out of one full **source** pattern, laid out
    /// `[sourceQy * sourceQx]` row-major.
    ///
    /// This is the "slice after reading" half of the 2026-08-18 decision: the
    /// raw formats store patterns contiguously, so a detector crop cannot skip
    /// bytes without many small strided reads. It saves memory, not I/O, and
    /// `LoadPushdown` says so.
    func detectorSlice(of pattern: [Float]) -> [Float] {
        guard let crop = specification.detectorCrop else { return pattern }
        let sourceQx = source.qx
        var output = [Float]()
        output.reserveCapacity(crop.height * crop.width)
        for row in 0..<crop.height {
            let start = (crop.yOffset + row) * sourceQx + crop.xOffset
            output.append(contentsOf: pattern[start..<(start + crop.width)])
        }
        return output
    }

    /// Check that a reader's own discovered shape is the source this view
    /// describes. Cheap, and it turns "the wrong file's view" into a refusal.
    func requireSource(shape: [Int]) throws {
        guard source.shape == shape else {
            throw LoadSpecificationError.sourceMismatch(
                expected: shape, received: source.shape
            )
        }
    }
}

// MARK: - In-memory sources

nonisolated extension LoadView {
    /// Slice this view out of a flat **full-extent source cube**, laid out
    /// `[Ry][Rx][Qy][Qx]` row-major.
    ///
    /// Shared by the synthetic in-memory `FourDDataSource`s in `mac4DSTEMTests/`
    /// and `tools/`, so a fixture reader is view-correct by construction instead
    /// of each harness reimplementing the offsets — and so a fixture that has
    /// not been taught about crops fails a crop test rather than quietly
    /// returning the full extent, which is the failure mode this stage exists to
    /// design against.
    ///
    /// `ry`/`rx`/`yRange` are **view** coordinates; the cube is indexed in
    /// source coordinates.
    func pattern(fromFullCube cube: [Float], ry: Int, rx: Int) -> [Float] {
        let sourcePatternCount = source.qy * source.qx
        let frame = (sourceScanY(ry) * source.rx + sourceScanX(rx)) * sourcePatternCount
        let full = Array(cube[frame..<(frame + sourcePatternCount)])
        return detectorSlice(of: full)
    }

    func scanRow(fromFullCube cube: [Float], ry: Int) -> [Float] {
        var row = [Float]()
        row.reserveCapacity(descriptor.rx * descriptor.qy * descriptor.qx)
        for rx in 0..<descriptor.rx {
            row.append(contentsOf: pattern(fromFullCube: cube, ry: ry, rx: rx))
        }
        return row
    }

    func scanTile(fromFullCube cube: [Float], yRange: Range<Int>) -> FourDScanTile {
        var pixels = [Float]()
        pixels.reserveCapacity(
            yRange.count * descriptor.rx * descriptor.qy * descriptor.qx
        )
        for ry in yRange {
            pixels.append(contentsOf: scanRow(fromFullCube: cube, ry: ry))
        }
        return FourDScanTile(
            yRange: yRange, scanWidth: descriptor.rx,
            detectorHeight: descriptor.qy, detectorWidth: descriptor.qx,
            pixels: pixels
        )
    }
}
