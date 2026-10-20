import Darwin
import Foundation
import FormatoHDF5
import SpectroCore
import CuboCore

//
//  CalibratedDataCubeWriter.swift
//  Role: the Preprocess export: a real-space crop, optional scan stride and integer detector bin streamed into a canonical
//        float32 py4DSTEM DataCube, bounded by `tileRows`, with the hot-pixel filter, the calibration re-expressed in the file's
//        frame and the derivation and replay stamps. No kit writes a 4D datacube of this shape yet, so it stays on
//        `HDF5WriteLibrary`. Split out of BraggVectorEMDWriter.swift (2026-10-20).
//

nonisolated extension BraggVectorEMDWriter {
    /// Stream a real-space crop through an optional integer detector bin into
    /// a canonical float32 py4DSTEM DataCube. Source reads and destination
    /// writes stay bounded by `tileRows`; the final file appears atomically.
    /// `acceleratingVoltageKV` (the session's, or the raw file's own) is stamped
    /// as the root attribute `accelerating_voltage` only when finite and
    /// positive; nil, 0 or NaN writes nothing (no value is invented).
    package static func writeCalibratedDataCube(
        source: any FourDDataSource,
        view: LoadView,
        calibration: PixelCalibration,
        acceleratingVoltageKV: Double? = nil,
        options: CalibratedDataCubeExportOptions,
        to destination: URL,
        sourceFileName: String? = nil,
        replayRecord: SessionReplayRecord? = nil,
        cancellation: AnalysisCancellationToken? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> CalibratedDataCubeExportSummary {
        // The export crops what is *loaded*, so its bounds are the view's, not
        // the source file's.
        //
        // **A reduced view exports since v2 S10.** The blanket refusal that
        // stood here ("needs the calibration re-reference (L3)") guarded one
        // invariant: pixels and calibration must be in the SAME frame. That
        // invariant holds structurally now — every read goes through the view
        // (`readScanTile` returns view-frame patterns), and the session
        // calibration handed in is view-frame because L3's
        // `CalibrationReReference.apply` re-references it at load time — so
        // `transformedCalibration` only ever composes the EXPORT-time bin on
        // top, which is the same math for a reduced view as for a full one.
        // What replaced the refusal is the checks the invariant deserves:
        // `transformedCalibration` now REFUSES (never silently drops or
        // passes through) origin maps whose shape is not this view's, and
        // refuses an origin that lands outside the exported detector — the
        // frame-mismatch net for a caller that hands a source-frame
        // calibration with reduced pixels, the py4DSTEM `bin_data_diffraction`
        // defect the DEVIATION note in `transformedCalibration` describes.
        let descriptor = view.descriptor
        // Defence in depth (CR3): the rename below would replace the destination — never the source or its sidecar.
        if let line = exportDestinationRefusal(destination, sourcePath: descriptor.filePath) {
            throw WriterError.publishFailed(line)
        }
        guard options.scanY.lowerBound >= 0,
              options.scanY.upperBound <= descriptor.ry,
              options.scanX.lowerBound >= 0,
              options.scanX.upperBound <= descriptor.rx,
              !options.scanY.isEmpty, !options.scanX.isEmpty else {
            throw WriterError.invalidDimensions("the real-space crop is outside the source scan")
        }
        guard options.scanStride > 0,
              options.scanStride <= min(options.scanY.count, options.scanX.count) else {
            throw WriterError.invalidDimensions("the scan stride is invalid for the cropped scan")
        }
        let cropY = options.qCropY ?? 0..<descriptor.qy
        let cropX = options.qCropX ?? 0..<descriptor.qx
        guard cropY.lowerBound >= 0, cropY.upperBound <= descriptor.qy, !cropY.isEmpty,
              cropX.lowerBound >= 0, cropX.upperBound <= descriptor.qx, !cropX.isEmpty else {
            throw WriterError.invalidDimensions("the detector crop is outside the detector")
        }
        guard options.qBin > 0, options.qBin <= cropY.count,
              options.qBin <= cropX.count else {
            throw WriterError.invalidDimensions("the diffraction bin factor is invalid")
        }
        guard options.tileRows > 0 else {
            throw WriterError.invalidDimensions("the export tile height must be positive")
        }
        if let threshold = options.hotPixelThreshold {
            guard threshold.isFinite, threshold > 0 else {
                throw WriterError.invalidDimensions("the hot-pixel threshold must be positive")
            }
        }
        let outQY = cropY.count / options.qBin
        let outQX = cropX.count / options.qBin
        guard outQY > 0, outQX > 0 else {
            throw WriterError.invalidDimensions("the binned diffraction shape is empty")
        }
        let outputShape = [options.scanYPositions.count, options.scanXPositions.count, outQY, outQX]

        // The hot-pixel mask is found BEFORE anything is written, from the
        // mean of exactly the patterns the file will hold (py4DSTEM filters
        // the already cropped, thinned and binned cube), so the file's
        // provenance can name it and a cancelled or failed mask pass leaves
        // nothing behind.
        var hotPixels = [[Int]]()
        if let threshold = options.hotPixelThreshold {
            let mean = try await meanPattern(source: source, view: view, options: options,
                                             outputShape: outputShape,
                                             cancellation: cancellation, progress: progress)
            // CuboCore's classification of the mean (py4DSTEM's footprint and Float32 comparison); the mean itself is this
            // file's, accumulated in Double (`meanPattern`).
            let flags: [Bool]
            do {
                flags = try HotPixelFilter.mask(mean: mean, rows: outQY, columns: outQX, threshold: threshold)
            } catch {
                throw WriterError.invalidDimensions("the hot-pixel mask needs a finite threshold and finite pixels")
            }
            hotPixels = flags.indices.filter { flags[$0] }.map { [$0 / outQX, $0 % outQX] }
        }
        let summary = CalibratedDataCubeExportSummary(
            shape: outputShape,
            discardedQRows: cropY.count - outQY * options.qBin,
            discardedQColumns: cropX.count - outQX * options.qBin,
            hotPixels: hotPixels
        )

        try checkCancellation(cancellation)
        let fm = FileManager.default
        let (temporary, scratchDirectory) = temporaryPublishURL(for: destination)
        var published = false
        defer {
            // try? OK: best-effort scratch cleanup on the way
            // out — on the failure path the primary error is already
            // in flight, and a leftover .tmp in the system-provided scratch
            // directory harms nothing the error did not already report.
            if !published { try? fm.removeItem(at: temporary) }
            if let scratchDirectory { try? fm.removeItem(at: scratchDirectory) }
        }
        let h5 = try HDF5Serial.run { try HDF5WriteLibrary.load() }   // H5open is an API call too
        try await writeCalibratedDataCubeFile(
            at: temporary, source: source, view: view,
            calibration: try transformedCalibration(calibration, descriptor: descriptor,
                                                    options: options),
            options: options, outputShape: summary.shape,
            derivation: DataCubeDerivation.compose(view: view, options: options,
                                                   outputShape: summary.shape,
                                                   sourceFileName: sourceFileName,
                                                   hotPixels: hotPixels),
            hotPixelMask: hotPixels.map { $0[0] * outQX + $0[1] },
            replayRecord: replayRecord,
            acceleratingVoltageKV: acceleratingVoltageKV,
            cancellation: cancellation, progress: progress, hdf5: h5
        )
        try checkCancellation(cancellation)
        let renamed = temporary.path.withCString { sourcePath in
            destination.path.withCString { targetPath in Darwin.rename(sourcePath, targetPath) }
        }
        guard renamed == 0 else {
            throw WriterError.publishFailed(String(cString: strerror(errno)))
        }
        published = true
        return summary
    }

    /// Re-express the session calibration in the exported file's own frame.
    ///
    /// The input is the VIEW's calibration (L3 re-references it at load time;
    /// values fitted in-session are natively view-frame), so the only
    /// transform applied here is the EXPORT-time bin — the same
    /// `(x + 0.5) / b - 0.5` convention as `CalibrationReReference`, and
    /// deliberately so (its `binnedCoordinate` doc comment names this site).
    ///
    /// **Refuses instead of guessing** (v2 S10; both were silent before):
    /// origin maps whose shape is not this view's scan have no honest
    /// sub-rectangle, and an origin outside the exported detector means the
    /// calibration and the pixels are in different frames — writing either
    /// would reproduce py4DSTEM's `bin_data_diffraction` defect with this
    /// writer's own signature on it.
    static func transformedCalibration(
        _ source: PixelCalibration,
        descriptor: DatasetDescriptor,
        options: CalibratedDataCubeExportOptions
    ) throws -> PixelCalibration {
        var output = source
        let bin = Double(options.qBin)
        // py4DSTEM `thin_data_real` scales the real-space pixel size by the
        // stride (preprocess.py:338).
        output.rSize = source.rSize.map { $0 * Double(options.scanStride) }
        output.qSize = source.qSize.map { $0 * bin }
        // The origin is a COORDINATE: the detector crop moves its zero (the
        // first Q axis is the view's detector rows, py4DSTEM Qx), then the
        // bin's `(x + 0.5) / b - 0.5`.
        // DEVIATION: py4DSTEM's `crop_data_diffraction` and
        // `bin_data_diffraction` (preprocess.py:123-136 and the bin) leave
        // `calibration.origin` untouched, so a py4DSTEM-cropped or -binned
        // cube carries an origin in the SOURCE frame; this export writes it
        // in the exported file's own frame (Gate B refuter, 2026-10-01).
        let cropOffsetX = Double(options.qCropY?.lowerBound ?? 0)   // py4DSTEM qx = first axis
        let cropOffsetY = Double(options.qCropX?.lowerBound ?? 0)
        let transformQX: (Double) -> Double = { ($0 - cropOffsetX + 0.5) / bin - 0.5 }
        let transformQY: (Double) -> Double = { ($0 - cropOffsetY + 0.5) / bin - 0.5 }
        output.qx0Mean = source.qx0Mean.map(transformQX)
        output.qy0Mean = source.qy0Mean.map(transformQY)
        output.probeSemiangle = source.probeSemiangle.map { $0 / bin }
        // The ellipse semi-axes are LENGTHS in detector pixels, exactly like
        // the probe radius one line up — omitting them left an export-binned
        // file carrying view-frame axes beside binned-frame everything else
        // (found by S10's review of this function; theta is an angle and
        // does not move).
        output.ellipseA = source.ellipseA.map { $0 / bin }
        output.ellipseB = source.ellipseB.map { $0 / bin }

        if let maps = source.originMaps {
            guard maps.shape == [descriptor.ry, descriptor.rx],
                  maps.fittedQX.count == descriptor.ry * descriptor.rx,
                  maps.fittedQY.count == descriptor.ry * descriptor.rx else {
                throw WriterError.invalidDimensions(
                    "the calibration's origin maps describe a \(maps.shape.map(String.init).joined(separator: " × ")) scan but the exported view's scan is \(descriptor.ry) × \(descriptor.rx) — the maps are not in this view's frame, so there is no honest way to export them"
                )
            }
            func cropped(_ values: [Double]?, _ transformQ: (Double) -> Double) -> [Double]? {
                // Optional arrays (measured maps) may be absent; a PRESENT
                // array of the wrong length is the same frame mismatch as a
                // wrong shape and is refused by the caller's guard above for
                // the fitted maps — measured maps that disagree are dropped
                // with the same reasoning `CalibrationReReference` applies
                // (they are a fit-quality record, not the calibration).
                guard let values, values.count == descriptor.ry * descriptor.rx else {
                    return nil
                }
                var result = [Double]()
                result.reserveCapacity(options.scanYPositions.count * options.scanXPositions.count)
                for y in options.scanYPositions {
                    for x in options.scanXPositions {
                        result.append(transformQ(values[y * descriptor.rx + x]))
                    }
                }
                return result
            }
            // Non-optional by the guard above: the fitted maps have the
            // exact counts `cropped` requires.
            let fittedQX = cropped(maps.fittedQX, transformQX) ?? []
            let fittedQY = cropped(maps.fittedQY, transformQY) ?? []
            output.originMaps = PixelOriginMaps(
                shape: [options.scanYPositions.count, options.scanXPositions.count],
                fittedQX: fittedQX, fittedQY: fittedQY,
                measuredQX: cropped(maps.measuredQX, transformQX),
                measuredQY: cropped(maps.measuredQY, transformQY)
            )
            output.qx0Mean = fittedQX.isEmpty
                ? output.qx0Mean : fittedQX.reduce(0, +) / Double(fittedQX.count)
            output.qy0Mean = fittedQY.isEmpty
                ? output.qy0Mean : fittedQY.reduce(0, +) / Double(fittedQY.count)
        }

        // The frame-mismatch net: every exported origin must lie inside the
        // exported detector, in pixel-centre coordinates `[-0.5, extent-0.5)`
        // (the same half-open convention as `CalibrationReReference`, written
        // in the positive so NaN refuses). py4DSTEM's qx is the FIRST Q axis
        // — this file's dim2, extent qy/bin. A view-frame calibration always
        // passes (the view contains its beam or L3 already invalidated it);
        // what this catches is a source-frame calibration handed in beside
        // reduced pixels — a net, not a proof, and the invariant's real home
        // is L3.
        let outQX = Double((options.qCropY?.count ?? descriptor.qy) / options.qBin)   // py4DSTEM qx extent
        let outQY = Double((options.qCropX?.count ?? descriptor.qx) / options.qBin)   // py4DSTEM qy extent
        func inside(_ value: Double, _ extent: Double) -> Bool {
            value.isFinite && value >= -0.5 && value < extent - 0.5
        }
        var outlier: (name: String, x: Double, extent: Double)?
        if let qx0 = output.qx0Mean, !inside(qx0, outQX) {
            outlier = ("mean origin qx0", qx0, outQX)
        } else if let qy0 = output.qy0Mean, !inside(qy0, outQY) {
            outlier = ("mean origin qy0", qy0, outQY)
        } else if let maps = output.originMaps {
            if let index = maps.fittedQX.firstIndex(where: { !inside($0, outQX) }) {
                outlier = ("fitted origin qx0 at scan position \(index)",
                           maps.fittedQX[index], outQX)
            } else if let index = maps.fittedQY.firstIndex(where: { !inside($0, outQY) }) {
                outlier = ("fitted origin qy0 at scan position \(index)",
                           maps.fittedQY[index], outQY)
            }
        }
        if let outlier {
            throw WriterError.invalidDimensions(
                "the \(outlier.name) lands at \(String(format: "%.2f", outlier.x)) in the exported detector, outside its \(Int(outlier.extent))-pixel extent — the calibration handed to the export is not in this view's frame, and writing it would pair pixels in one frame with an origin in another"
            )
        }
        return output
    }

    static func writeCalibratedDataCubeFile(
        at url: URL,
        source: any FourDDataSource,
        view: LoadView,
        calibration: PixelCalibration,
        options: CalibratedDataCubeExportOptions,
        outputShape: [Int],
        derivation: DataCubeDerivation?,
        hotPixelMask: [Int],
        replayRecord: SessionReplayRecord?,
        acceleratingVoltageKV: Double?,
        cancellation: AnalysisCancellationToken?,
        progress: (@Sendable (Double) -> Void)?,
        hdf5 h5: HDF5WriteLibrary
    ) async throws {
        // The setup below creates handles the tile loop uses, so it cannot be
        // one closure under `HDF5Serial.run`; the lock is taken explicitly
        // here and released before the loop's first `await` on the source.
        // Every handle is closed under the lock again at exit.
        HDF5Serial.acquire()
        var setupLocked = true
        defer { if setupLocked { HDF5Serial.release() } }
        let fileID = url.path.withCString {
            h5.h5fcreate($0, h5FileTruncate, h5DefaultProperty, h5DefaultProperty)
        }
        guard fileID >= 0 else { throw WriterError.hdf5("creating the calibrated datacube") }
        defer { HDF5Serial.run { _ = h5.h5fclose(fileID) } }

        try writeStringAttribute("emd_group_type", value: "file", on: fileID, hdf5: h5)
        try writeScalarAttribute("version_major", value: Int32(1), type: h5.nativeInt,
                                 on: fileID, hdf5: h5)
        try writeScalarAttribute("version_minor", value: Int32(0), type: h5.nativeInt,
                                 on: fileID, hdf5: h5)
        try writeStringAttribute("UUID", value: UUID().uuidString, on: fileID, hdf5: h5)
        try writeStringAttribute("authoring_program", value: "mac4DSTEM", on: fileID, hdf5: h5)
        try writeStringAttribute("authoring_user", value: "", on: fileID, hdf5: h5)
        // The accelerating voltage, in kV, as the file-root attribute `AcceleratingVoltage` names — the one
        // spelling mac4DSTEM's opener reads back (`AppState.activate`), so a reopened export is not "Not set".
        // Absence is absence: a usable value (finite, > 0) is written, never a placeholder (owner 2026-10-01, 1a).
        // DEVIATION from py4DSTEM: its EMD files keep no voltage anywhere (py4DSTEM-dev f050d207: only
        // `read_dm.py:76-86` reads a DM "Microscope Info.Voltage", to convert mrad to 1/A, and stores none), and its
        // functions take eV (`electron_wavelength_angstrom(E_eV)`). This attribute is app-level, ignored by
        // `py4DSTEM.read` (emdfile `read.py` names the root attributes it uses: emd_group_type, version_*, UUID);
        // our reader takes kV or eV (> 1000) alike.
        if let acceleratingVoltageKV, acceleratingVoltageKV.isFinite, acceleratingVoltageKV > 0 {
            try writeScalarAttribute(AcceleratingVoltage.attributeName, value: acceleratingVoltageKV,
                                     type: h5.nativeDouble, on: fileID, hdf5: h5)
        }

        let root = try createGroup("datacube_root", in: fileID, hdf5: h5)
        defer { HDF5Serial.run { _ = h5.h5gclose(root) } }
        try writeNodeAttributes(groupType: "root", pythonClass: "Root", on: root, hdf5: h5)
        // Provenance the reduced file carries about itself (v2 S10): where its
        // pixels came from, and the recipe of the analyses run on this data —
        // the recipe already re-expressed in THIS file's frame by the caller
        // (`ReplayRecordFrameMap`), never the view's, so no reader has to know
        // a frame this file cannot describe. py4DSTEM ignores both attributes.
        // Absence is absence: a session with no recipe stamps nothing.
        if let derivation, let json = derivation.jsonString {
            try writeStringAttribute(derivationAttribute, value: json, on: root, hdf5: h5)
        }
        if let replayRecord, !replayRecord.isEmpty, let json = replayRecord.jsonString {
            try writeStringAttribute(replayRecordAttribute, value: json, on: root, hdf5: h5)
        }
        let cube = try createGroup("datacube", in: root, hdf5: h5)
        defer { HDF5Serial.run { _ = h5.h5gclose(cube) } }
        try writeNodeAttributes(groupType: "array", pythonClass: "DataCube", on: cube, hdf5: h5)

        let dimensions = outputShape.map(hsize_t.init)
        let fileSpace = dimensions.withUnsafeBufferPointer {
            h5.h5screateSimple(4, $0.baseAddress, nil)
        }
        guard fileSpace >= 0 else { throw WriterError.hdf5("creating the datacube dataspace") }
        defer { HDF5Serial.run { _ = h5.h5sclose(fileSpace) } }
        let creation = h5.h5pcreate(h5.datasetCreatePropertyClass)
        guard creation >= 0 else { throw WriterError.hdf5("creating the chunk property list") }
        defer { HDF5Serial.run { _ = h5.h5pclose(creation) } }
        let chunk = [hsize_t(1), hsize_t(1), dimensions[2], dimensions[3]]
        guard chunk.withUnsafeBufferPointer({
            h5.h5psetChunk(creation, 4, $0.baseAddress)
        }) >= 0 else { throw WriterError.hdf5("configuring datacube chunks") }
        let dataset = "data".withCString {
            h5.h5dcreate2(cube, $0, h5.nativeFloat, fileSpace, h5DefaultProperty,
                          creation, h5DefaultProperty)
        }
        guard dataset >= 0 else { throw WriterError.hdf5("creating the datacube dataset") }
        defer { HDF5Serial.run { _ = h5.h5dclose(dataset) } }
        try writeStringAttribute("units", value: "pixel intensity", on: dataset, hdf5: h5)

        let rStep = calibration.rSize ?? 1
        let qStep = calibration.qSize ?? 1
        let rUnits = calibration.rUnits ?? "pixels"
        let qUnits = calibration.qUnits ?? "pixels"
        func linearDimension(count: Int, step: Double) -> [Double] {
            count > 1 ? [0, step] : [0]
        }
        try writeDoubleVectorDataset("dim0", values: linearDimension(count: outputShape[0], step: rStep), name: "Rx",
                                     units: rUnits, in: cube, hdf5: h5)
        try writeDoubleVectorDataset("dim1", values: linearDimension(count: outputShape[1], step: rStep), name: "Ry",
                                     units: rUnits, in: cube, hdf5: h5)
        try writeDoubleVectorDataset("dim2", values: linearDimension(count: outputShape[2], step: qStep), name: "Qx",
                                     units: qUnits, in: cube, hdf5: h5)
        try writeDoubleVectorDataset("dim3", values: linearDimension(count: outputShape[3], step: qStep), name: "Qy",
                                     units: qUnits, in: cube, hdf5: h5)
        try writeCalibration(calibration, targetPath: "/datacube", in: root, hdf5: h5)
        HDF5Serial.release()
        setupLocked = false

        let outQY = outputShape[2], outQX = outputShape[3]
        let yPositions = options.scanYPositions
        // With the hot-pixel filter on, the mean pass took the first half of
        // the progress bar.
        let progressBase = options.hotPixelThreshold == nil ? 0.0 : 0.5
        var outRow = 0
        while outRow < yPositions.count {
            try checkCancellation(cancellation)
            // A stride of 1 reads `tileRows` contiguous scan rows at once, as
            // before; a thinned scan reads the rows it keeps one at a time.
            let rowsInTile = options.scanStride == 1
                ? min(options.tileRows, yPositions.count - outRow) : 1
            let sourceY = yPositions[outRow]
            let sourceTile = try await source.readScanTile(view, yRange: sourceY..<(sourceY + rowsInTile))
            try checkCancellation(cancellation)
            let output = try reducedTile(sourceTile, localRows: rowsInTile, view: view,
                                     options: options, outQY: outQY, outQX: outQX,
                                     hotPixelMask: hotPixelMask)
            let endY = outRow + rowsInTile

            // One tile's write is one operation under the lock; the read of
            // the next tile from the source actor happens outside it.
            do {
                HDF5Serial.acquire(); defer { HDF5Serial.release() }
                let targetSpace = h5.h5dgetSpace(dataset)
                guard targetSpace >= 0 else { throw WriterError.hdf5("opening the output dataspace") }
                defer { _ = h5.h5sclose(targetSpace) }
                let start = [hsize_t(outRow), 0, 0, 0]
                let count = [hsize_t(rowsInTile), hsize_t(outputShape[1]),
                             hsize_t(outQY), hsize_t(outQX)]
                let selected = start.withUnsafeBufferPointer { starts in
                    count.withUnsafeBufferPointer { counts in
                        h5.h5sselectHyperslab(targetSpace, h5SelectSet, starts.baseAddress,
                                              nil, counts.baseAddress, nil)
                    }
                }
                guard selected >= 0 else { throw WriterError.hdf5("selecting the output tile") }
                let memorySpace = count.withUnsafeBufferPointer {
                    h5.h5screateSimple(4, $0.baseAddress, nil)
                }
                guard memorySpace >= 0 else { throw WriterError.hdf5("creating the output tile dataspace") }
                let wrote = output.withUnsafeBytes {
                    h5.h5dwrite(dataset, h5.nativeFloat, memorySpace, targetSpace,
                                h5DefaultProperty, $0.baseAddress)
                }
                _ = h5.h5sclose(memorySpace)
                guard wrote >= 0 else { throw WriterError.hdf5("writing the output tile") }
            }
            outRow = endY
            progress?(progressBase + (1 - progressBase) * Double(outRow) / Double(yPositions.count))
        }
        try checkCancellation(cancellation)
        progress?(1)
    }

    /// One tile through the export's per-pattern reduction: scan positions
    /// thinned to `scanXPositions`, detector cropped (`crop_Q`), then summed
    /// in `qBin` blocks (`bin_Q`), then — if a mask is given — the hot-pixel
    /// replacement. `[localRows x outX x outQY x outQX]`, float32.
    static func reducedTile(
        _ tile: FourDScanTile, localRows: Int, view: LoadView,
        options: CalibratedDataCubeExportOptions, outQY: Int, outQX: Int,
        hotPixelMask: [Int]
    ) throws -> [Float] {
        let descriptor = view.descriptor
        let xPositions = options.scanXPositions
        let cropY0 = options.qCropY?.lowerBound ?? 0
        let cropX0 = options.qCropX?.lowerBound ?? 0
        let bin = options.qBin
        let sourcePatternCount = descriptor.qy * descriptor.qx
        let patternSize = outQY * outQX
        var output = [Float](repeating: 0, count: localRows * xPositions.count * patternSize)
        var flags = [Bool](repeating: false, count: hotPixelMask.isEmpty ? 0 : patternSize)
        for flat in hotPixelMask where flags.indices.contains(flat) { flags[flat] = true }
        for localY in 0..<localRows {
            for (outX, sourceX) in xPositions.enumerated() {
                let inputBase = (localY * descriptor.rx + sourceX) * sourcePatternCount
                let outputBase = (localY * xPositions.count + outX) * patternSize
                for qy in 0..<outQY {
                    for qx in 0..<outQX {
                        var sum: Float = 0
                        for by in 0..<bin {
                            let row = inputBase + (cropY0 + qy * bin + by) * descriptor.qx
                            for bx in 0..<bin {
                                sum += tile.pixels[row + cropX0 + qx * bin + bx]
                            }
                        }
                        output[outputBase + qy * outQX + qx] = sum
                    }
                }
                if !hotPixelMask.isEmpty {
                    try replaceHotPixels(in: &output, base: outputBase, rows: outQY, columns: outQX, mask: flags)
                }
            }
        }
        return output
    }

    /// The masked pixels of the pattern at `pixels[base ..< base + rows * columns]` replaced by CuboCore's clipped 3x3 median, in place
    /// (the other patterns are not touched). A non-finite pixel is refused, as the kit refuses it.
    package static func replaceHotPixels(in pixels: inout [Float], base: Int, rows: Int, columns: Int,
                                         mask: [Bool]) throws {
        let range = base..<(base + rows * columns)
        let cleaned: [Float]
        do {
            cleaned = try HotPixelFilter.replacing(Array(pixels[range]), rows: rows, columns: columns, mask: mask)
        } catch {
            throw WriterError.invalidDimensions("the hot-pixel filter needs finite pixels")
        }
        pixels.replaceSubrange(range, with: cleaned)
    }

    /// Mean of the exported (cropped, thinned, binned) patterns: the first of the
    /// filter's two passes over the source (py4DSTEM's `filter_hot_pixels`,
    /// preprocess/preprocess.py:349-460, pinned commit f050d207; the
    /// classification and the replacement are CuboCore's `HotPixelFilter`).
    ///
    /// DEVIATION: the mean is accumulated in Double and rounded once to Float;
    /// numpy accumulates a float32 axis=(0,1) mean sequentially in float32 (which
    /// is what CuboCore's own `HotPixelFilter.filter` does, so it is not used). A
    /// pixel is classified differently only when its excess lies within the
    /// float32 accumulation error of `thresh`. That error was measured on the
    /// raw 060 cube (108 900 patterns, numpy 2.5.0; Gate B refuter 2026-10-01):
    /// ~1e-5 relative at pixel values 1e3-1e4, but ~1e-3 relative (45-230
    /// counts) at 2e5 against thresh 8 — so inside a bright direct disk
    /// py4DSTEM's own mask is partly an accumulation artefact, and mask identity
    /// with py4DSTEM holds only where |excess - thresh| exceeds that error.
    static func meanPattern(
        source: any FourDDataSource, view: LoadView,
        options: CalibratedDataCubeExportOptions, outputShape: [Int],
        cancellation: AnalysisCancellationToken?,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> [Float] {
        let outQY = outputShape[2], outQX = outputShape[3]
        let patternSize = outQY * outQX
        let yPositions = options.scanYPositions
        var sums = [Double](repeating: 0, count: patternSize)
        for (index, sourceY) in yPositions.enumerated() {
            try checkCancellation(cancellation)
            let tile = try await source.readScanTile(view, yRange: sourceY..<(sourceY + 1))
            let reduced = try reducedTile(tile, localRows: 1, view: view, options: options,
                                      outQY: outQY, outQX: outQX, hotPixelMask: [])
            for pattern in 0..<outputShape[1] {
                let base = pattern * patternSize
                for i in 0..<patternSize { sums[i] += Double(reduced[base + i]) }
            }
            progress?(0.5 * Double(index + 1) / Double(yPositions.count))
        }
        let count = Double(yPositions.count * outputShape[1])
        return sums.map { Float($0 / count) }
    }
}
