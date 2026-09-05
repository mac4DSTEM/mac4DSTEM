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
package nonisolated struct AxisCrop: Equatable, Sendable, Codable {
    /// Offset from the source origin, in source pixels.
    package var yOffset: Int
    package var xOffset: Int
    /// Extent of the view, in source pixels.
    package var height: Int
    package var width: Int

    package var yRange: Range<Int> { yOffset..<(yOffset + height) }
    package var xRange: Range<Int> { xOffset..<(xOffset + width) }

    package var isEmpty: Bool { height <= 0 || width <= 0 }

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(yOffset: Int, xOffset: Int, height: Int, width: Int) {
        self.yOffset = yOffset
        self.xOffset = xOffset
        self.height = height
        self.width = width
    }
}

/// What part of the source is loaded. `nil` crops mean "the whole axis".
package nonisolated struct LoadSpecification: Equatable, Sendable, Codable {
    /// Real-space (scan) crop. nil = the whole scan.
    package var scanCrop: AxisCrop?
    /// Diffraction-space (detector) crop. nil = the whole detector.
    package var detectorCrop: AxisCrop?
    /// Diffraction bin factor. 1 = none.
    ///
    /// DEVIATION from py4DSTEM (`preprocess.bin_data_diffraction`,
    /// References/py4DSTEM-dev/py4DSTEM/preprocess/preprocess.py:154): py4DSTEM
    /// accepts any integer. This app offers **2, 4 and 8 only** (decided
    /// 2026-08-06). Two reasons, both practical: it keeps a ground-truth
    /// comparison exact rather than approximate, and it makes the edge-remainder
    /// path rare on real detectors, since 64/128/256/512 are all divisible by 8.
    /// The remainder path is still implemented and tested — a 384 px or cropped
    /// detector reaches it, and a rare untested path is worse than a common one.
    package var detectorBin: Int = 1

    /// The factors the app offers. `1` is "no binning", not a choice.
    package static let availableBinFactors = [2, 4, 8]

    package static let fullExtent = LoadSpecification()

    /// True when this loads the file exactly as stored.
    ///
    /// The property the whole design rests on: a specification equal to
    /// `.fullExtent` is indistinguishable from not having one, so promoting a
    /// rehearsal to the full dataset is *removing* the specification, not
    /// converting a derived file back into a source.
    package var isFullExtent: Bool {
        scanCrop == nil && detectorCrop == nil && detectorBin == 1
    }

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(scanCrop: AxisCrop? = nil, detectorCrop: AxisCrop? = nil, detectorBin: Int = 1) {
        self.scanCrop = scanCrop
        self.detectorCrop = detectorCrop
        self.detectorBin = detectorBin
    }
}

/// How much of a specification a reader was able to push into its own I/O.
///
/// **This exists so the saving is never overstated.** Cropping at read time
/// saves memory *and* I/O only when the reader can skip the bytes. HDF5 can, on
/// all four axes, via the hyperslab it already builds. Pattern-contiguous raw
/// formats (MIB, EMPAD, and some DM4) make a *scan* crop a contiguous seek,
/// while a *detector* crop needs many small strided reads within each frame —
/// so those readers slice after reading
/// and save memory only.
///
/// Decided 2026-08-18: push down where it pays, slice where it does not, and
/// have every reader *declare which*, rather than letting the app claim an I/O
/// saving it did not get. A reader that silently ignores a specification is the
/// defect this type is designed against — three of the five conformers ignore
/// the descriptor they are handed today.
package nonisolated struct LoadPushdown: Equatable, Sendable, Codable {
    /// The reader skipped the cropped-out scan positions on disk.
    package var scanCropSkipsIO: Bool
    /// The reader skipped the cropped-out detector pixels on disk.
    package var detectorCropSkipsIO: Bool

    /// Everything pushed down — HDF5's hyperslab.
    package static let full = LoadPushdown(scanCropSkipsIO: true, detectorCropSkipsIO: true)
    /// Scan crop seeks, detector crop is sliced after the read —
    /// pattern-contiguous raw formats.
    package static let scanOnly = LoadPushdown(scanCropSkipsIO: true, detectorCropSkipsIO: false)
    /// Nothing skipped; the specification is applied entirely in memory.
    package static let none = LoadPushdown(scanCropSkipsIO: false, detectorCropSkipsIO: false)

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(scanCropSkipsIO: Bool, detectorCropSkipsIO: Bool) {
        self.scanCropSkipsIO = scanCropSkipsIO
        self.detectorCropSkipsIO = detectorCropSkipsIO
    }
}

// MARK: - Geometry

nonisolated extension AxisCrop {
    /// Whether this crop fits inside a `height` x `width` source plane.
    package func fits(height: Int, width: Int) -> Bool {
        yOffset >= 0 && xOffset >= 0 && self.height > 0 && self.width > 0
            && yOffset + self.height <= height
            && xOffset + self.width <= width
    }
}

nonisolated extension LoadSpecification {
    /// Offset of the view's first scan position within the source scan.
    package var scanOffset: (y: Int, x: Int) {
        (scanCrop?.yOffset ?? 0, scanCrop?.xOffset ?? 0)
    }

    /// Offset of the view's first detector pixel within the source detector.
    package var detectorOffset: (y: Int, x: Int) {
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
package nonisolated enum LoadSpecificationError: LocalizedError, Equatable {
    case notFourDimensional([Int])
    case scanCropOutOfBounds(AxisCrop, sourceHeight: Int, sourceWidth: Int)
    case detectorCropOutOfBounds(AxisCrop, sourceHeight: Int, sourceWidth: Int)
    case binningNotAvailable(Int)
    /// Binning would leave no detector pixels at all.
    case binnedExtentIsEmpty(bin: Int, height: Int, width: Int)
    /// A reader was handed a view of a file it did not open, or of a shape it
    /// did not discover.
    case sourceMismatch(expected: [Int], received: [Int])
    /// A reader that cannot apply a specification at all was handed one.
    case unsupportedByReader(String)

    package var errorDescription: String? {
        switch self {
        case .notFourDimensional(let shape):
            return "A load specification needs a 4D dataset; this one is \(shape.count)D."
        case .scanCropOutOfBounds(let crop, let h, let w):
            return "The scan crop (\(crop.height)x\(crop.width) at y \(crop.yOffset), x \(crop.xOffset)) does not fit the \(h)x\(w) scan."
        case .detectorCropOutOfBounds(let crop, let h, let w):
            return "The diffraction crop (\(crop.height)x\(crop.width) at y \(crop.yOffset), x \(crop.xOffset)) does not fit the \(h)x\(w) detector."
        case .binnedExtentIsEmpty(let bin, let height, let width):
            return "Binning \(height) x \(width) detector pixels by \(bin) leaves nothing to load."
        case .binningNotAvailable(let factor):
            return "Diffraction bin factor \(factor) is not offered; use 2, 4 or 8."
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
package nonisolated struct LoadView: Sendable {
    /// The dataset as stored in the file, at full extent.
    package let source: DatasetDescriptor
    /// Which part of `source` is loaded.
    package let specification: LoadSpecification
    /// The shape being processed, **after** any crop and any binning. Identical
    /// to `source` — the same value, not a copy — when the specification is full
    /// extent, so that removing a specification restores the original dataset
    /// identity exactly.
    package let descriptor: DatasetDescriptor

    /// The detector rectangle a reader actually reads: the requested crop
    /// trimmed down to a whole number of bins.
    ///
    /// **Readers must use this, never `specification.detectorCrop`.** The two
    /// differ by the edge remainder, and reading the untrimmed rectangle would
    /// hand the bin step a row or column it cannot pair up. `nil` means "the
    /// whole detector, unbinned".
    package let readDetectorCrop: AxisCrop?

    /// Detector rows and columns dropped as the edge remainder, in source
    /// pixels. Zero unless binning is on and the extent does not divide.
    /// Surfaced to the user, per invariant I3 — a binned cube is a different
    /// measurement and a trimmed one is a different detector.
    package let discardedDetectorRows: Int
    package let discardedDetectorColumns: Int

    /// Validate `specification` against `source` and derive the view.
    ///
    /// Throws rather than clamping: a crop that does not fit is a caller
    /// mistake, and silently shrinking it would change what was measured
    /// without saying so.
    package init(source: DatasetDescriptor, specification: LoadSpecification) throws {
        guard source.is4D else {
            throw LoadSpecificationError.notFourDimensional(source.shape)
        }
        let bin = specification.detectorBin
        guard bin == 1 || LoadSpecification.availableBinFactors.contains(bin) else {
            throw LoadSpecificationError.binningNotAvailable(bin)
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
        // THE EDGE REMAINDER, and it is py4DSTEM's rule, reproduced.
        // `bin_data_diffraction` crops the detector to a multiple of the bin
        // factor before reshaping, and it takes the remainder off the END of
        // each axis (`data[..., :-(Q_Nx % bin), :-(Q_Ny % bin)]`,
        // preprocess.py:181). So the extent this app actually READS is the crop
        // trimmed down to a multiple of the factor, and the trimmed pixels are
        // never converted or allocated.
        //
        // **Never converted, not necessarily never fetched** — an earlier
        // version of this comment claimed the stronger thing. Whether the bytes
        // leave the disk is per reader and per file, which is the whole reason
        // `LoadPushdown` is declared rather than assumed: the raw readers fetch
        // a whole frame and decode part of it, and a CHUNKED HDF5 dataset is
        // read and inflated a whole chunk at a time. Corrected 2026-08-18.
        //
        // What was dropped is recorded and must be stated in the UI:
        // silently returning a smaller detector than the user asked for is the
        // kind of quiet difference that turns up later as an unexplained number.
        let requestedHeight = specification.detectorCrop?.height ?? source.qy
        let requestedWidth = specification.detectorCrop?.width ?? source.qx
        let discardedRows = requestedHeight % bin
        let discardedColumns = requestedWidth % bin
        self.discardedDetectorRows = discardedRows
        self.discardedDetectorColumns = discardedColumns
        let readHeight = requestedHeight - discardedRows
        let readWidth = requestedWidth - discardedColumns
        guard readHeight > 0, readWidth > 0 else {
            throw LoadSpecificationError.binnedExtentIsEmpty(
                bin: bin, height: requestedHeight, width: requestedWidth
            )
        }
        let (detectorY, detectorX) = specification.detectorOffset
        self.readDetectorCrop = (bin == 1 && specification.detectorCrop == nil)
            ? nil
            : AxisCrop(yOffset: detectorY, xOffset: detectorX,
                       height: readHeight, width: readWidth)

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
                    readHeight / bin,
                    readWidth / bin,
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
    package init(fullExtentOf source: DatasetDescriptor) {
        self.source = source
        self.specification = .fullExtent
        self.descriptor = source
        self.readDetectorCrop = nil
        self.discardedDetectorRows = 0
        self.discardedDetectorColumns = 0
    }

    package var isFullExtent: Bool { specification.isFullExtent }

    /// Source scan row for a view scan row.
    package func sourceScanY(_ viewY: Int) -> Int { specification.scanOffset.y + viewY }
    /// Source scan column for a view scan column.
    package func sourceScanX(_ viewX: Int) -> Int { specification.scanOffset.x + viewX }

    /// Take the detector crop out of one full **source** pattern, laid out
    /// `[sourceQy * sourceQx]` row-major, and bin it.
    ///
    /// This is the "slice after reading" half of the 2026-08-18 decision: the
    /// raw formats store patterns contiguously, so a detector crop cannot skip
    /// bytes without many small strided reads. It saves memory, not I/O, and
    /// `LoadPushdown` says so. Binning is always in memory — no format can sum
    /// pixels on the way off the disk.
    ///
    /// Slice and bin are one call on purpose: a reader that did only the first
    /// half would return a pattern of the wrong length, and it is better for
    /// that to be impossible than to be caught.
    package func detectorView(of pattern: [Float]) -> [Float] {
        guard let crop = readDetectorCrop else { return binned(pattern, patternCount: 1) }
        let sourceQx = source.qx
        var output = [Float]()
        output.reserveCapacity(crop.height * crop.width)
        for row in 0..<crop.height {
            let start = (crop.yOffset + row) * sourceQx + crop.xOffset
            output.append(contentsOf: pattern[start..<(start + crop.width)])
        }
        return binned(output, patternCount: 1)
    }

    /// Bin `patternCount` contiguous patterns that are already at the **read**
    /// extent (`readDetectorCrop`, so a whole number of bins on both axes).
    ///
    /// DEVIATION-free array math — this is py4DSTEM's, deliberately:
    /// `bin_data_diffraction` reshapes to `(…, Qx/b, b, Qy/b, b)` and calls
    /// `.sum(axis=(3, 5))` (preprocess.py:193). It **sums, it does not
    /// average**, so intensities scale by `bin_factor²` and every absolute
    /// intensity threshold moves with the factor. Averaging here would be a
    /// silent divergence from the reference implementation that no shape check
    /// could catch, and it would make binned and unbinned disk-detection
    /// thresholds look interchangeable when they are not.
    ///
    /// Accumulated in `Float` rather than `Double` because the reference sums in
    /// the array's own dtype, and a more accurate sum here would be a different
    /// answer.
    ///
    /// **That does not make this bit-identical to NumPy on arbitrary data.**
    /// NumPy's `.sum(axis=(3,5))` accumulates in a different order from this
    /// nested loop, so on real float32 patterns the two differ at the last few
    /// ulp — measured 2026-08-18 on a 256x256 diffraction pattern binned by 8:
    /// 797 of 1024 output pixels differed, by at most 4.7e-7 relative. That is
    /// scientifically irrelevant and it is not zero, so the exactness claimed in
    /// `tools/preprocess-crop-bin-test` holds because that fixture uses small
    /// integers, whose partial sums are exact in float32 in ANY order — not
    /// because the two implementations agree bit-for-bit in general.
    package func binned(_ pixels: [Float], patternCount: Int) -> [Float] {
        let bin = specification.detectorBin
        guard bin > 1 else { return pixels }
        let readHeight = readDetectorCrop?.height ?? source.qy
        let readWidth = readDetectorCrop?.width ?? source.qx
        let outHeight = readHeight / bin
        let outWidth = readWidth / bin
        var output = [Float](repeating: 0, count: patternCount * outHeight * outWidth)
        for pattern in 0..<patternCount {
            let inBase = pattern * readHeight * readWidth
            let outBase = pattern * outHeight * outWidth
            for outY in 0..<outHeight {
                for outX in 0..<outWidth {
                    var sum: Float = 0
                    for dy in 0..<bin {
                        let rowBase = inBase + (outY * bin + dy) * readWidth + outX * bin
                        for dx in 0..<bin {
                            sum += pixels[rowBase + dx]
                        }
                    }
                    output[outBase + outY * outWidth + outX] = sum
                }
            }
        }
        return output
    }

    /// Check that a reader's own discovered shape is the source this view
    /// describes. Cheap, and it turns "the wrong file's view" into a refusal.
    package func requireSource(shape: [Int]) throws {
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
    package func pattern(fromFullCube cube: [Float], ry: Int, rx: Int) -> [Float] {
        let sourcePatternCount = source.qy * source.qx
        let frame = (sourceScanY(ry) * source.rx + sourceScanX(rx)) * sourcePatternCount
        let full = Array(cube[frame..<(frame + sourcePatternCount)])
        return detectorView(of: full)
    }

    package func scanRow(fromFullCube cube: [Float], ry: Int) -> [Float] {
        var row = [Float]()
        row.reserveCapacity(descriptor.rx * descriptor.qy * descriptor.qx)
        for rx in 0..<descriptor.rx {
            row.append(contentsOf: pattern(fromFullCube: cube, ry: ry, rx: rx))
        }
        return row
    }

    package func scanTile(fromFullCube cube: [Float], yRange: Range<Int>) -> FourDScanTile {
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

// MARK: - Persistence

nonisolated extension LoadSpecification {

    /// A stable JSON string, for the session sidecar and for exports.
    ///
    /// **Why a string and not a set of numeric attributes.** A specification is
    /// one value with a growing shape — L4 added a bin factor, and a later stage
    /// may add more — and spreading it across `crop_y_offset`, `crop_height`,
    /// `bin_factor` … invites a reader that finds three of five and infers the
    /// rest. One field either round-trips or it does not.
    ///
    /// Sorted keys so the same specification always produces the same bytes: a
    /// sidecar that differs only in field order looks like a changed session to
    /// anything comparing files.
    package var jsonString: String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // try? OK (v2 S7 audit): the stored properties are integers and
        // nothing else; the synthesized encode cannot fail, and nil falls
        // through to "write no attribute".
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Decode a specification written by `jsonString`.
    ///
    /// **Validation is NOT done here**, on purpose: this type does not know
    /// which dataset it will be applied to. A decoded specification must be
    /// passed through `LoadView(source:specification:)` before it is trusted —
    /// which is what refuses a crop that does not fit the file it was reopened
    /// against, rather than silently loading a different region than the one the
    /// session recorded.
    /// Nil for malformed input. The one production caller
    /// (`BraggVectorEMDWriter.loadSession`) REFUSES on nil for a present
    /// attribute (`WriterError.malformedAttribute`) — a mangled crop
    /// attribute must not read as "no crop recorded". // v2 S7
    package static func decoded(from json: String) -> LoadSpecification? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(LoadSpecification.self, from: data)
    }

    /// A short human form for provenance display, or nil at full extent.
    package var provenanceSummary: String? {
        guard !isFullExtent else { return nil }
        var parts: [String] = []
        if let scan = scanCrop {
            parts.append("scan \(scan.height)x\(scan.width) at (\(scan.yOffset), \(scan.xOffset))")
        }
        if let detector = detectorCrop {
            parts.append("detector \(detector.height)x\(detector.width) at (\(detector.yOffset), \(detector.xOffset))")
        }
        if detectorBin > 1 { parts.append("binned \(detectorBin)x") }
        return parts.joined(separator: ", ")
    }
}
