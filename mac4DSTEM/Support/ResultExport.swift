//
//  ResultExport.swift
//  Role: Minimal result export — PNG of the current real-space result or
//        diffraction pattern (rendered exactly as displayed: colormap, log
//        scale, contrast window), CSV of detected Bragg peaks, and a native
//        py4DSTEM 0.14 / EMD 1.0 BraggVectors HDF5 sidecar.
//

import AppKit
import ImageIO
import UniformTypeIdentifiers

extension AppState {

    /// Export a calibrated, optionally cropped/Q-binned py4DSTEM DataCube.
    /// Publication is atomic and the source dataset is never opened for write.
    func exportCalibratedDataCube(options: CalibratedDataCubeExportOptions) {
        // The export reads through the loaded view, so the reader is never
        // handed a shape without its position in the file. A cropped view is
        // refused by the writer until L3's calibration re-reference lands — see
        // `writeCalibratedDataCube`.
        guard let descriptor, let view = loadView,
              let source = currentDataSourceForExport() else {
            present(SimpleError("No 4D dataset is open."))
            return
        }
        let panel = NSSavePanel()
        panel.title = "Export Calibrated py4DSTEM DataCube"
        panel.message = "The source stays unchanged. mac4DSTEM writes a new canonical EMD file."
        panel.allowedContentTypes = [UTType(filenameExtension: "h5") ?? .data]
        panel.nameFieldStringValue = exportBaseName + "_calibrated.h5"
        guard panel.runModal() == .OK, let url = panel.url else {
            statusText = "Calibrated DataCube export cancelled"
            return
        }

        let snapshot = sessionPixelCalibration(descriptor: descriptor)
        let epoch = datasetEpoch
        let token = beginCancellableOperation(
            "Preprocessing export", status: "Writing calibrated DataCube…",
            totalUnits: options.scanY.count * options.scanX.count
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.finishCancellableOperation(token) }
            do {
                let progressUpdate: @Sendable (Double) -> Void = { [weak self] fraction in
                    Task { @MainActor [weak self] in
                        self?.updateCancellableOperation(
                            token, progress: fraction,
                            status: "Writing calibrated DataCube… \(Int(fraction * 100)) %"
                        )
                    }
                }
                let summary = try await Task.detached(priority: .userInitiated) {
                    try await BraggVectorEMDWriter.writeCalibratedDataCube(
                        source: source, view: view, calibration: snapshot,
                        options: options, to: url, cancellation: token,
                        progress: progressUpdate
                    )
                }.value
                guard self.isCurrentOperation(token), self.datasetEpoch == epoch else { return }
                let dropped = summary.discardedQRows + summary.discardedQColumns
                let suffix = dropped == 0
                    ? ""
                    : " (trimmed \(summary.discardedQRows) Q row, \(summary.discardedQColumns) Q column)"
                self.statusText = "Exported \(summary.shape.map(String.init).joined(separator: " × ")) DataCube → \(url.lastPathComponent)\(suffix)"
            } catch BraggVectorEMDWriter.WriterError.cancelled {
                guard self.isCurrentOperation(token) else { return }
                self.statusText = "Calibrated DataCube export cancelled"
            } catch {
                guard self.isCurrentOperation(token), self.datasetEpoch == epoch else { return }
                self.present(error)
            }
        }
    }

    /// Resolve a previously user-approved session companion. Security-scoped
    /// bookmarks let a sandboxed app reopen the same sidecar across launches.
    func resolvedSessionSidecarURL(for descriptor: DatasetDescriptor) -> URL? {
        if let scopedSessionSidecarURL { return scopedSessionSidecarURL }
        guard let data = UserDefaults.standard.data(forKey: sessionBookmarkKey(descriptor)) else {
            return nil
        }
        var stale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            _ = url.startAccessingSecurityScopedResource()
            scopedSessionSidecarURL = url
            if stale { try storeSessionBookmark(url, for: descriptor) }
            return url
        } catch {
            UserDefaults.standard.removeObject(forKey: sessionBookmarkKey(descriptor))
            return nil
        }
    }

    /// First save uses a standard panel, defaulted beside the source dataset.
    /// That user action grants sandbox access to create the companion. The
    /// bookmark must be made only after atomic publication: Foundation cannot
    /// bookmark the not-yet-existing URL returned by NSSavePanel.
    private func writableSessionSidecarURL(for descriptor: DatasetDescriptor) -> URL? {
        if let resolved = resolvedSessionSidecarURL(for: descriptor) { return resolved }
        let suggested = BraggVectorEMDWriter.sessionSidecarURL(
            forSourcePath: descriptor.filePath
        )
        let panel = NSSavePanel()
        panel.title = "Choose Session Sidecar"
        panel.message = "Choose the companion file mac4DSTEM may update and reopen."
        panel.directoryURL = suggested.deletingLastPathComponent()
        panel.nameFieldStringValue = suggested.lastPathComponent
        panel.allowedContentTypes = [UTType(filenameExtension: "h5") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else {
            statusText = "Session sidecar save cancelled"
            return nil
        }
        _ = url.startAccessingSecurityScopedResource()
        scopedSessionSidecarURL = url
        return url
    }

    private func storeSessionBookmark(_ url: URL, for descriptor: DatasetDescriptor) throws {
        let data = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(data, forKey: sessionBookmarkKey(descriptor))
    }

    private func sessionBookmarkKey(_ descriptor: DatasetDescriptor) -> String {
        let encoded = Data(descriptor.filePath.utf8).base64EncodedString()
        return "session-sidecar-bookmark." + encoded
    }

    /// Export the current real-space result (virtual image / DPC / strain /
    /// ACOM map) as a PNG, rendered as displayed, with the scale bar burned in.
    func exportResultImage() {
        let source: (bytes: [UInt8], width: Int, height: Int)
        if let rgba = resultRGBA {
            source = (rgba.rgba, rgba.width, rgba.height)
        } else if let image = resultImage {
            let norm = image.normalized(symmetric: resultColormap.isDiverging)
            let bytes = Self.applyColormap(norm, colormap: resultColormap,
                                           lo: displayRangeLo, hi: displayRangeHi,
                                           gamma: resultGamma)
            source = (bytes, image.width, image.height)
        } else {
            present(SimpleError("No result image to export yet."))
            return
        }
        // The publication figure is "as displayed", so it applies the display
        // orientation (#17b) — and records it in the caption below, because an
        // applied-but-unrecorded rotation is the one outcome that is not
        // acceptable. The scientific bundle takes the opposite choice and stays
        // in scan-index order; see `scientificBundleMaps()`.
        let orientation = effectiveRealSpaceDisplayOrientation
        let oriented = Self.orientedRGBA(
            source.bytes, width: source.width, height: source.height,
            orientation: orientation, mirrored: effectiveRealSpaceDisplayMirrored
        )
        let cg = Self.cgImage(
            rgba: oriented.bytes, width: oriented.width, height: oriented.height
        )
        guard let cg else {
            present(SimpleError("Could not render the result image for export."))
            return
        }
        let pixel = currentResultPersistenceMetadata
        // A quarter turn puts the other axis along the burnt-in bar, and for a
        // non-square scan that is a different pixel size.
        let sampling = orientation.swapsAxes
            ? (pixel.row ?? pixel.column) : (pixel.column ?? pixel.row)
        let withScale = Self.burnScaleBar(on: cg,
                                      unitsPerDataPixel: sampling,
                                      unitLabel: sampling != nil ? (pixel.units ?? "px") : "px")
        let final = Self.publicationFigure(
            image: withScale, title: currentResultDisplayName,
            caption: publicationCaption,
            valueRange: resultDisplayedValueRange,
            valueUnits: currentResultValueUnits, colormap: resultColormap
        )
        Self.savePNG(final, suggestedName: exportBaseName + "_result.png", state: self)
    }

    private var publicationCaption: String {
        guard let product = displayedProduct else { return currentResultValueUnits }
        var parts = [
            product.domain.rawValue + " space",
            product.quantitativeStatus.rawValue,
        ]
        if let step = product.sampling.column ?? product.sampling.row {
            parts.append(String(format: "%.5g %@/px", step, product.sampling.units ?? "px"))
        }
        for key in ["source_product", "basis_mode", "matching_backend", "reference_mode"] {
            if let value = product.provenance[key] { parts.append("\(key)=\(value)") }
        }
        // Only when it is not the default: a figure that HAS been reoriented
        // must say so on its face, and one that has not should not carry noise.
        if !realSpaceDisplayIsDefault {
            for key in ["display_rotation_deg", "display_flip"] {
                if let value = realSpaceDisplayProvenance[key] {
                    parts.append("\(key)=\(value)")
                }
            }
        }
        return parts.joined(separator: " · ")
    }

    /// Quarter-turn + mirror on an RGBA8 buffer.
    ///
    /// Deliberately done in pixel indices rather than with a `CGContext`
    /// transform: the context's y-axis points the opposite way to the view's,
    /// so the sign of the rotation there is easy to get backwards and hard to
    /// see in a review. Here the mapping is stated directly and pinned by
    /// `ResultOrientationTests`.
    ///
    /// Matches SwiftUI's `rotationEffect`, which turns **clockwise** for a
    /// positive angle, so source `(x, y)` lands at `(h-1-y, x)` for 90°. The
    /// mirror is applied after the rotation, in display space, exactly as the
    /// viewer composes them.
    static func orientedRGBA(
        _ bytes: [UInt8], width: Int, height: Int,
        orientation: RealSpaceDisplayOrientation, mirrored: Bool
    ) -> (bytes: [UInt8], width: Int, height: Int) {
        guard width > 0, height > 0, bytes.count >= width * height * 4 else {
            return (bytes, width, height)
        }
        if orientation == .identity && !mirrored { return (bytes, width, height) }

        let outWidth = orientation.swapsAxes ? height : width
        let outHeight = orientation.swapsAxes ? width : height
        var out = [UInt8](repeating: 0, count: outWidth * outHeight * 4)

        for y in 0..<height {
            for x in 0..<width {
                var dx: Int
                var dy: Int
                switch orientation {
                case .identity: (dx, dy) = (x, y)
                case .quarterTurn: (dx, dy) = (height - 1 - y, x)
                case .halfTurn: (dx, dy) = (width - 1 - x, height - 1 - y)
                case .threeQuarterTurn: (dx, dy) = (y, width - 1 - x)
                }
                if mirrored { dx = outWidth - 1 - dx }
                let source = (y * width + x) * 4
                let destination = (dy * outWidth + dx) * 4
                out[destination] = bytes[source]
                out[destination + 1] = bytes[source + 1]
                out[destination + 2] = bytes[source + 2]
                out[destination + 3] = bytes[source + 3]
            }
        }
        return (out, outWidth, outHeight)
    }

    /// Export all coherent quantitative fields for the active strain or ACOM
    /// result. Raw Euler angles are radians; validity is explicit; no missing
    /// field is synthesized from display colors.
    func exportScientificBundle() {
        guard let descriptor, let maps = scientificBundleMaps() else {
            present(SimpleError("Compute a strain or orientation map before exporting a scientific bundle."))
            return
        }
        let panel = NSSavePanel()
        panel.title = "Export Scientific EMD Bundle"
        panel.allowedContentTypes = [UTType(filenameExtension: "h5") ?? .data]
        panel.nameFieldStringValue = exportBaseName + "_scientific_bundle.h5"
        guard panel.runModal() == .OK, let url = panel.url else {
            statusText = "Scientific bundle export cancelled"
            return
        }
        let calibration = sessionPixelCalibration(descriptor: descriptor)
        let token = beginCancellableOperation(
            "Scientific bundle", status: "Writing coherent EMD fields…",
            totalUnits: maps.count
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.finishCancellableOperation(token) }
            do {
                try await Task.detached(priority: .userInitiated) {
                    try BraggVectorEMDWriter.writeScientificBundle(
                        maps: maps, calibration: calibration, to: url,
                        cancellation: token
                    )
                }.value
                guard self.isCurrentOperation(token) else { return }
                let omitted = self.scientificBundleOmissions(in: maps)
                self.statusText = omitted.isEmpty
                    ? "Exported \(maps.count) coherent fields → \(url.lastPathComponent)"
                    : "Exported \(maps.count) coherent fields → \(url.lastPathComponent) "
                        + "· omitted \(omitted.joined(separator: ", ")) "
                        + "(different scan shape — rerun it at full scan to include it)"
            } catch BraggVectorEMDWriter.WriterError.cancelled {
                self.statusText = "Scientific bundle export cancelled"
            } catch {
                self.present(error)
            }
        }
    }

    /// Every coherent quantitative field computed this session, not just the
    /// one in front.
    ///
    /// This used to `return` out of the strain branch, so once a strain map
    /// existed the orientation fields could never be exported — running ACOM
    /// and then Strain silently produced a bundle with half the results
    /// missing (backlog #28, reported 2026-08-05). Both are accumulated now.
    /// Provenance was already per-`ScalarResultMap`, so a mixed bundle needs no
    /// special handling: each field keeps its own `bundle`, run semantics and
    /// `quantitative_status`, which strain and ACOM do not share.
    func scientificBundleMaps() -> [ScalarResultMap]? {
        let sampling = (calibration.rPixelSize, calibration.rPixelUnits)
        var bundle: [ScalarResultMap] = []
        if let map = strainMap {
            // The bundle stays in scan-index order — a quantitative field must
            // stay addressable by (Rx, Ry) — but it records the orientation the
            // user was viewing, so a figure made from this bundle can be
            // reconciled with one exported from the app (#17b).
            var provenance = [
                "bundle": "strain", "display_domain": "scan",
                "reference_positions": String(map.referencePositionCount),
                "indexed_fraction": String(map.indexedFraction),
                "basis_mode": map.diagnostics.automaticBasis ? "consensus" : "manual",
                "display_orientation_applied": "false",
            ]
            provenance.merge(realSpaceDisplayProvenance) { current, _ in current }
            func field(_ kind: String, _ name: String, _ units: String,
                       _ pixels: [Float]) -> ScalarResultMap {
                ScalarResultMap(
                    width: map.width, height: map.height, pixels: pixels,
                    kind: kind, displayName: name, valueUnits: units,
                    pixelSizeRow: sampling.0, pixelSizeColumn: sampling.0,
                    pixelUnits: sampling.1, provenance: provenance
                )
            }
            let masked: ([Float]) -> [Float] = { values in
                values.indices.map { map.mask[$0] ? values[$0] : Float.nan }
            }
            bundle += [
                field("strain_exx", "Strain ε_xx", "strain", masked(map.exx)),
                field("strain_eyy", "Strain ε_yy", "strain", masked(map.eyy)),
                field("strain_exy", "Strain ε_xy", "strain", masked(map.exy)),
                field("strain_theta", "Lattice rotation θ", "rad", masked(map.theta)),
                field("strain_validity", "Strain validity", "boolean", map.mask.map { $0 ? 1 : 0 }),
                field("strain_fit_residual", "Local fit residual", "detector_px",
                      masked(map.localResidualPixels)),
            ]
        }
        if let map = orientationMap, let semantics = acomLastRunSemantics {
            let valid = map.results.map { $0.templateIndex >= 0 }
            var provenance = semantics.provenance
            provenance.merge([
                "bundle": "orientation", "display_domain": "scan",
                "euler_convention": "Bunge extrinsic zxz, radians",
                "symmetry": map.symmetry.rawValue,
                "matching_backend": map.matchingBackend.rawValue,
                "template_count": String(map.templateCount),
                "quantitative_status": semantics.productStatus(
                    for: "orientation_bundle"
                ).rawValue,
                // As for strain: scan-index order is preserved, and the
                // viewer's orientation is recorded rather than applied (#17b).
                "display_orientation_applied": "false",
            ], uniquingKeysWith: { _, new in new })
            provenance.merge(realSpaceDisplayProvenance) { current, _ in current }
            func values(_ body: (OrientationResult) -> Float) -> [Float] {
                map.results.indices.map { valid[$0] ? body(map.results[$0]) : Float.nan }
            }
            func field(_ kind: String, _ name: String, _ units: String,
                       _ pixels: [Float]) -> ScalarResultMap {
                ScalarResultMap(
                    width: map.width, height: map.height, pixels: pixels,
                    kind: kind, displayName: name, valueUnits: units,
                    pixelSizeRow: sampling.0, pixelSizeColumn: sampling.0,
                    pixelUnits: sampling.1, provenance: provenance
                )
            }
            bundle += [
                field("orientation_phi1", "Euler φ₁", "rad", values { $0.euler.phi1 }),
                field("orientation_Phi", "Euler Φ", "rad", values { $0.euler.Phi }),
                field("orientation_phi2", "Euler φ₂", "rad", values { $0.euler.phi2 }),
                field("orientation_reliability", "Orientation reliability", "dimensionless",
                      values { $0.reliability }),
                field("orientation_score", "Orientation score", "dimensionless",
                      values { $0.score }),
                field("orientation_validity", "Orientation validity", "boolean",
                      valid.map { $0 ? 1 : 0 }),
            ]
        }
        // The writer requires every field in a bundle to share one shape. A
        // preview-scope ACOM map is subsampled, so naively mixing it with a
        // full-scan strain map would turn a previously-working export into a
        // hard "bundle fields must share one non-empty shape" failure. Keep the
        // scan-shaped family — those are the addressable, full-resolution
        // fields — and let the caller say what was left out.
        if Set(bundle.map { $0.width * 100_000 + $0.height }).count > 1 {
            if let d = descriptor,
               bundle.contains(where: { $0.width == d.rx && $0.height == d.ry }) {
                bundle = bundle.filter { $0.width == d.rx && $0.height == d.ry }
            } else if let largest = bundle.max(
                by: { $0.width * $0.height < $1.width * $1.height }
            ) {
                bundle = bundle.filter {
                    $0.width == largest.width && $0.height == largest.height
                }
            }
        }
        return bundle.isEmpty ? nil : bundle
    }

    /// Families that exist in memory but did not make it into the bundle,
    /// so a partial export never looks like a complete one.
    func scientificBundleOmissions(in maps: [ScalarResultMap]) -> [String] {
        let included = Set(maps.compactMap { $0.provenance["bundle"] })
        var omitted: [String] = []
        if strainMap != nil, !included.contains("strain") { omitted.append("strain") }
        if orientationMap != nil, acomLastRunSemantics != nil,
           !included.contains("orientation") {
            omitted.append("orientation")
        }
        return omitted
    }

    /// Export the currently displayed diffraction pattern as a PNG, with the
    /// q-space scale bar burned in.
    func exportDiffractionImage() {
        guard let pattern = displayedPattern else {
            present(SimpleError("No diffraction pattern to export yet."))
            return
        }
        let norm = pattern.normalized(useLog: logScale)
        let bytes = Self.applyColormap(norm, colormap: patternColormap,
                                       lo: patternDisplayRangeLo,
                                       hi: patternDisplayRangeHi,
                                       gamma: patternGamma)
        guard let cg = Self.cgImage(rgba: bytes, width: pattern.qx, height: pattern.qy) else {
            present(SimpleError("Could not render the diffraction pattern for export."))
            return
        }
        let qSize = calibration.qPixelSize
        let final = Self.burnScaleBar(on: cg,
                                      unitsPerDataPixel: qSize,
                                      unitLabel: qSize != nil ? (calibration.qPixelUnits ?? "1/nm") : "px")
        Self.savePNG(final, suggestedName: exportBaseName + "_cbed.png", state: self)
    }

    /// Export all detected Bragg peaks as CSV: scan position, detector
    /// position (subpixel), intensity.
    func exportBraggPeaksCSV() {
        guard let vectors = braggVectors else {
            present(SimpleError("No Bragg peaks to export — run Detect All Disks first."))
            return
        }
        // CSV stays in the app's Cartesian convention; the EMD export below
        // is the explicit py4DSTEM convention boundary.
        var csv = "scan_x,scan_y,detector_x,detector_y,intensity\n"
        csv.reserveCapacity(vectors.totalPeakCount * 32)
        for ry in 0..<vectors.scanHeight {
            for rx in 0..<vectors.scanWidth {
                for p in vectors.peaks[ry * vectors.scanWidth + rx] {
                    csv += "\(rx),\(ry),\(p.x),\(p.y),\(p.intensity)\n"
                }
            }
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = exportBaseName + "_bragg_peaks.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            statusText = "Exported \(vectors.totalPeakCount) peaks → \(url.lastPathComponent)"
        } catch {
            present(error)
        }
    }

    /// Export the complete detected peak grid as a py4DSTEM-readable EMD 1.0
    /// sidecar. The writer converts app detector (x=column,y=row) to py4DSTEM
    /// (qx=row,qy=column) and never modifies the source dataset.
    func exportBraggVectorsEMD() {
        guard let vectors = braggVectors, let descriptor else {
            present(SimpleError("No Bragg peaks to export — run Detect All Disks first."))
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "h5") ?? .data]
        panel.nameFieldStringValue = exportBaseName + "_braggvectors.h5"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let pixelCalibration = sessionPixelCalibration(descriptor: descriptor)
        let token = beginCancellableOperation(
            "Bragg-vector export", status: "Writing py4DSTEM sidecar…"
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.finishCancellableOperation(token) }
            do {
                let progressUpdate: @Sendable (Double) -> Void = { [weak self] fraction in
                    Task { @MainActor [weak self] in
                        self?.updateCancellableOperation(
                            token,
                            progress: fraction,
                            status: "Writing py4DSTEM sidecar… \(Int(fraction * 100)) %"
                        )
                    }
                }
                try await Task.detached(priority: .userInitiated) {
                    try BraggVectorEMDWriter.write(
                        vectors: vectors,
                        qWidth: descriptor.qx,
                        qHeight: descriptor.qy,
                        calibration: pixelCalibration,
                        to: url,
                        cancellation: token,
                        progress: progressUpdate
                    )
                }.value
                guard self.isCurrentOperation(token) else { return }
                self.statusText = "Exported \(vectors.totalPeakCount) peaks → \(url.lastPathComponent)"
            } catch BraggVectorEMDWriter.WriterError.cancelled {
                guard self.isCurrentOperation(token) else { return }
                self.statusText = "Bragg-vector export cancelled"
            } catch {
                guard self.isCurrentOperation(token) else { return }
                self.present(error)
            }
        }
    }

    /// Save the current scalar or scan-shaped scientific RGBA result to the stable companion
    /// `<source>.mac4dstem.h5`. Existing BraggVectors are preserved when the
    /// current session has none, and a current detection replaces the saved
    /// vectors together with the map in one atomic publication.
    func saveCurrentResultToSessionSidecar() {
        guard let descriptor else { return }
        let scalarMap: ScalarResultMap?
        let rgbaMap: RGBAResultMap?
        let metadata = restoredResultInfo ?? navigationResultInfo ?? currentScalarResultMetadata
        if let image = resultImage {
            let persistence: (
                row: Double?, column: Double?, units: String?, provenance: [String: String]
            )
            if restoredResultInfo != nil {
                persistence = restoredResultPixelInfo ?? (nil, nil, nil, [:])
            } else if navigationResultInfo != nil {
                persistence = navigationResultPixelInfo ?? (nil, nil, nil, [:])
            } else {
                persistence = currentResultPersistenceMetadata
            }
            scalarMap = ScalarResultMap(
                width: image.width, height: image.height, pixels: image.pixels,
                kind: metadata.kind, displayName: metadata.displayName,
                valueUnits: metadata.valueUnits,
                pixelSizeRow: persistence.row,
                pixelSizeColumn: persistence.column,
                pixelUnits: persistence.units,
                provenance: persistence.provenance
            )
            rgbaMap = nil
        } else if let image = resultRGBA,
                  image.width == descriptor.rx, image.height == descriptor.ry {
            let persistence = currentResultPersistenceMetadata
            scalarMap = nil
            rgbaMap = RGBAResultMap(
                width: image.width, height: image.height, rgba: image.rgba,
                kind: metadata.kind, displayName: metadata.displayName,
                valueUnits: metadata.valueUnits,
                pixelSizeRow: persistence.row,
                pixelSizeColumn: persistence.column,
                pixelUnits: persistence.units,
                provenance: persistence.provenance
            )
        } else {
            present(SimpleError("No scalar or scan-shaped RGBA result is available to save."))
            return
        }
        guard let url = writableSessionSidecarURL(for: descriptor) else { return }
        let pixelCalibration = sessionPixelCalibration(descriptor: descriptor)
        let vectors = braggVectors
        let epoch = datasetEpoch
        let token = beginCancellableOperation(
            "Session sidecar", status: "Saving \(metadata.displayName)…"
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.finishCancellableOperation(token) }
            do {
                let progressUpdate: @Sendable (Double) -> Void = { [weak self] fraction in
                    Task { @MainActor [weak self] in
                        self?.updateCancellableOperation(
                            token, progress: fraction,
                            status: "Saving \(metadata.displayName)… \(Int(fraction * 100)) %"
                        )
                    }
                }
                try await Task.detached(priority: .userInitiated) {
                    if let scalarMap {
                        try BraggVectorEMDWriter.mergeResultMap(
                            scalarMap, vectors: vectors,
                            qWidth: descriptor.qx, qHeight: descriptor.qy,
                            calibration: pixelCalibration, to: url,
                            cancellation: token, progress: progressUpdate
                        )
                    } else if let rgbaMap {
                        try BraggVectorEMDWriter.mergeRGBAResultMap(
                            rgbaMap, vectors: vectors,
                            qWidth: descriptor.qx, qHeight: descriptor.qy,
                            calibration: pixelCalibration, to: url,
                            cancellation: token, progress: progressUpdate
                        )
                    }
                }.value
                guard self.isCurrentOperation(token), self.datasetEpoch == epoch else { return }
                let inventoryTask = Task.detached(priority: .utility) {
                    try BraggVectorEMDWriter.loadInventory(from: url)
                }
                if let inventory = try? await inventoryTask.value {
                    guard self.isCurrentOperation(token), self.datasetEpoch == epoch else { return }
                    self.sessionInventory = inventory
                }
                do {
                    // The writer atomically published the target, so it now
                    // exists and can safely back a persistent security bookmark.
                    try self.storeSessionBookmark(url, for: descriptor)
                    self.statusText = "Saved \(metadata.displayName) → \(url.lastPathComponent)"
                } catch {
                    self.statusText = "Saved \(metadata.displayName); choose the sidecar again after relaunch"
                    self.errorMessage = "The result was saved to \(url.lastPathComponent), but mac4DSTEM could not remember access for a future launch: \(error.localizedDescription)"
                }
            } catch BraggVectorEMDWriter.WriterError.cancelled {
                guard self.isCurrentOperation(token) else { return }
                self.statusText = "Session sidecar save cancelled"
            } catch {
                guard self.isCurrentOperation(token) else { return }
                self.present(error)
            }
        }
    }

    /// Display any compatible saved scalar/RGBA result without rerunning its
    /// analysis. This changes the in-session selection; the persisted current
    /// item remains the last atomically saved result.
    func selectSavedSessionResult(_ saved: SessionResultDescriptor) async {
        guard let descriptor else { return }
        let url = resolvedSessionSidecarURL(for: descriptor)
            ?? BraggVectorEMDWriter.sessionSidecarURL(forSourcePath: descriptor.filePath)
        let epoch = datasetEpoch
        do {
            switch saved.storage {
            case .scalarFloat32:
                let map = try await Task.detached(priority: .utility) {
                    try BraggVectorEMDWriter.loadResultMap(id: saved.id, from: url)
                }.value
                guard epoch == datasetEpoch, let map else { return }
                resultImage = FloatImage(width: map.width, height: map.height, pixels: map.pixels)
                resultRGBA = nil
                restoredResultInfo = (map.kind, map.displayName, map.valueUnits)
                restoredResultPixelInfo = (
                    map.pixelSizeRow, map.pixelSizeColumn, map.pixelUnits, map.provenance
                )
                restoredResultDomain = map.provenance["display_domain"].flatMap(ProductDomain.init)
            case .rgba8:
                let map = try await Task.detached(priority: .utility) {
                    try BraggVectorEMDWriter.loadRGBAResultMap(id: saved.id, from: url)
                }.value
                guard epoch == datasetEpoch, let map else { return }
                resultImage = nil
                resultRGBA = RGBAImage(width: map.width, height: map.height, rgba: map.rgba)
                restoredResultInfo = (map.kind, map.displayName, map.valueUnits)
                restoredResultPixelInfo = (
                    map.pixelSizeRow, map.pixelSizeColumn, map.pixelUnits, map.provenance
                )
                restoredResultDomain = map.provenance["display_domain"].flatMap(ProductDomain.init)
            }
            sessionInventory = SessionSidecarInventory(
                hasSidecar: sessionInventory.hasSidecar,
                hasBraggVectors: sessionInventory.hasBraggVectors,
                hasCalibration: sessionInventory.hasCalibration,
                results: sessionInventory.results,
                currentResultID: saved.id
            )
            resultVersion &+= 1
            statusText = "Viewed saved \(saved.displayName) ← \(url.lastPathComponent)"
        } catch {
            guard epoch == datasetEpoch else { return }
            present(error)
        }
    }

    /// Load a saved product into an immutable comparison slot without changing
    /// the active scientific result or rerunning analysis.
    func loadSavedSessionResult(_ saved: SessionResultDescriptor, into slot: ComparisonSlot) async {
        guard let descriptor else { return }
        let url = resolvedSessionSidecarURL(for: descriptor)
            ?? BraggVectorEMDWriter.sessionSidecarURL(forSourcePath: descriptor.filePath)
        let epoch = datasetEpoch
        do {
            let product: DisplayedProduct?
            switch saved.storage {
            case .scalarFloat32:
                let map = try await Task.detached(priority: .utility) {
                    try BraggVectorEMDWriter.loadResultMap(id: saved.id, from: url)
                }.value
                guard let map else { return }
                let domain = map.provenance["display_domain"].flatMap(ProductDomain.init)
                    ?? legacyDomain(kind: map.kind, width: map.width, height: map.height,
                                    descriptor: descriptor)
                product = DisplayedProduct(
                    kind: map.kind, displayName: map.displayName,
                    payload: .scalar(FloatImage(width: map.width, height: map.height,
                                                pixels: map.pixels)),
                    domain: domain,
                    sampling: ProductSampling(row: map.pixelSizeRow,
                                              column: map.pixelSizeColumn,
                                              units: map.pixelUnits),
                    valueUnits: map.valueUnits,
                    quantitativeStatus: map.provenance["quantitative_status"]
                        .flatMap(ProductQuantitativeStatus.init)
                        ?? quantitativeStatus(for: map.kind, units: map.valueUnits),
                    provenance: map.provenance
                )
            case .rgba8:
                let map = try await Task.detached(priority: .utility) {
                    try BraggVectorEMDWriter.loadRGBAResultMap(id: saved.id, from: url)
                }.value
                guard let map else { return }
                product = DisplayedProduct(
                    kind: map.kind, displayName: map.displayName,
                    payload: .rgba(RGBAImage(width: map.width, height: map.height,
                                            rgba: map.rgba)),
                    domain: map.provenance["display_domain"].flatMap(ProductDomain.init)
                        ?? legacyDomain(kind: map.kind, width: map.width,
                                        height: map.height, descriptor: descriptor),
                    sampling: ProductSampling(
                        row: map.pixelSizeRow, column: map.pixelSizeColumn,
                        units: map.pixelUnits
                    ),
                    valueUnits: map.valueUnits,
                    quantitativeStatus: map.provenance["quantitative_status"]
                        .flatMap(ProductQuantitativeStatus.init)
                        ?? quantitativeStatus(for: map.kind, units: map.valueUnits),
                    provenance: map.provenance
                )
            }
            guard epoch == datasetEpoch, let product else { return }
            switch slot {
            case .a: comparisonProductA = product
            case .b: comparisonProductB = product
            }
            statusText = "Loaded \(saved.displayName) into comparison \(slot == .a ? "A" : "B")"
        } catch {
            guard epoch == datasetEpoch else { return }
            present(error)
        }
    }

    private func legacyDomain(
        kind: String, width: Int, height: Int, descriptor: DatasetDescriptor
    ) -> ProductDomain {
        // Exact frozen-v1 kinds only. Unknown legacy data is treated as scan
        // space only when its shape proves that mapping; no title parsing.
        switch kind {
        case "bragg_vector_map": return .detector
        case "parallax_preprocess", "parallax_alignment", "parallax_subpixel_bf",
             "parallax_corrected_phase", "parallax_depth",
             "ptychography_object_phase", "ptychography_object_amplitude",
             "ptychography_probe_phase", "ptychography_probe_amplitude":
            return .reconstruction
        default:
            return width == descriptor.rx && height == descriptor.ry ? .scan : .detector
        }
    }

    /// Validated controls available for the scalar map currently selected from
    /// the sidecar. This does not imply that its transient analysis arrays are
    /// resident or recoverable.
    var selectedSavedControlRehydration: SessionControlRehydration? {
        guard let info = restoredResultInfo, let pixelInfo = restoredResultPixelInfo else {
            return nil
        }
        let plan = SessionControlRehydration.parse(
            kind: info.kind, provenance: pixelInfo.provenance
        )
        return plan.isEmpty ? nil : plan
    }

    func applySelectedSavedControls() {
        guard let plan = selectedSavedControlRehydration else { return }
        if let value = plan.kdeUpsampleFactor { parallaxKDEUpsampleFactor = value }
        if let value = plan.kdeSigmaPixels { parallaxKDESigmaPixels = value }
        if let value = plan.kdeLanczosOrder { parallaxKDELanczosOrder = value }
        if let value = plan.positionIterations {
            parallaxPositionCorrectionIterations = value
        }
        if let value = plan.kdeLowpass { parallaxKDELowpass = value }
        if let value = plan.qLowpassInvAngstrom { parallaxQLowpassInvAngstrom = value }
        if let value = plan.qHighpassInvAngstrom { parallaxQHighpassInvAngstrom = value }
        if let value = plan.depthAngstrom {
            parallaxDepthStartAngstrom = value
            parallaxDepthEndAngstrom = value
            parallaxDepthPlaneCount = 1
        }
        if let value = plan.depthUseFullFit { parallaxDepthUseFullFit = value }
        if let value = plan.depthInformationLimit {
            parallaxDepthInformationLimit = value
        }
        if let value = plan.depthInformationPower { parallaxDepthInformationPower = value }
        if let value = plan.ptychographyIterations { ptychographyIterations = value }
        if let value = plan.ptychographyMethod {
            switch value {
            case "gradient-descent": ptychographyMethod = .gradientDescent
            case "difference-map_alternating-projections":
                ptychographyMethod = .differenceMapAlternatingProjections
            default: break
            }
        }
        if let value = plan.ptychographyStepSize { ptychographyStepSize = value }
        if let value = plan.ptychographyProjectionParameter {
            ptychographyProjectionParameter = value
        }
        if let value = plan.ptychographyNormalizationMinimum {
            ptychographyNormalizationMinimum = value
        }
        if let value = plan.ptychographyFixProbe { ptychographyFixProbe = value }
        if let value = plan.ptychographyConstrainObjectAmplitude {
            ptychographyConstrainObjectAmplitude = value
        }
        if let value = plan.ptychographyPurePhaseObject {
            ptychographyPurePhaseObject = value
        }
        if let value = plan.ptychographyFixProbeCenterOfMass {
            ptychographyFixProbeCenterOfMass = value
        }
        if let value = plan.ptychographyConstrainProbeAmplitude {
            ptychographyConstrainProbeAmplitude = value
        }
        if let value = plan.ptychographyProbeAmplitudeRadius {
            ptychographyProbeAmplitudeRadius = value
        }
        if let value = plan.ptychographyProbeAmplitudeWidth {
            ptychographyProbeAmplitudeWidth = value
        }
        statusText = "Applied saved controls: \(plan.summary). Re-run explicitly to reconstruct."
    }

    func removeSavedSessionResult(_ saved: SessionResultDescriptor) async {
        guard let descriptor else { return }
        let url = resolvedSessionSidecarURL(for: descriptor)
            ?? BraggVectorEMDWriter.sessionSidecarURL(forSourcePath: descriptor.filePath)
        let calibration = sessionPixelCalibration(descriptor: descriptor)
        let epoch = datasetEpoch
        let token = beginCancellableOperation(
            "Session result removal", status: "Removing \(saved.displayName)…"
        )
        defer { finishCancellableOperation(token) }
        do {
            try await Task.detached(priority: .userInitiated) {
                try BraggVectorEMDWriter.removeResult(
                    kind: saved.kind, qWidth: descriptor.qx, qHeight: descriptor.qy,
                    calibration: calibration, from: url, cancellation: token
                )
            }.value
            guard isCurrentOperation(token), epoch == datasetEpoch else { return }
            let inventory = try await Task.detached(priority: .utility) {
                try BraggVectorEMDWriter.loadInventory(from: url)
            }.value
            guard isCurrentOperation(token), epoch == datasetEpoch else { return }
            sessionInventory = inventory
            if let currentID = inventory.currentResultID,
               let current = inventory.results.first(where: { $0.id == currentID }) {
                await selectSavedSessionResult(current)
            } else {
                resultImage = nil
                resultRGBA = nil
                restoredResultInfo = nil
                resultVersion &+= 1
            }
            statusText = "Removed \(saved.displayName) from \(url.lastPathComponent)"
        } catch BraggVectorEMDWriter.WriterError.cancelled {
            guard isCurrentOperation(token) else { return }
            statusText = "Session result removal cancelled"
        } catch {
            guard isCurrentOperation(token), epoch == datasetEpoch else { return }
            present(error)
        }
    }

    /// Publish calibration independently of the currently displayed result.
    /// Existing maps and BraggVectors are copied into the replacement file.
    func saveCalibrationToSessionSidecar() {
        guard let descriptor else {
            present(SimpleError("No dataset is open."))
            return
        }
        guard let url = writableSessionSidecarURL(for: descriptor) else { return }
        let snapshot = sessionPixelCalibration(descriptor: descriptor)
        let epoch = datasetEpoch
        let token = beginCancellableOperation(
            "Session calibration", status: "Saving calibration…"
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.finishCancellableOperation(token) }
            do {
                try await Task.detached(priority: .userInitiated) {
                    try BraggVectorEMDWriter.mergeCalibration(
                        snapshot, qWidth: descriptor.qx, qHeight: descriptor.qy,
                        to: url, cancellation: token
                    )
                }.value
                guard self.isCurrentOperation(token), self.datasetEpoch == epoch else { return }
                let inventoryTask = Task.detached(priority: .utility) {
                    try BraggVectorEMDWriter.loadInventory(from: url)
                }
                if let inventory = try? await inventoryTask.value {
                    guard self.isCurrentOperation(token), self.datasetEpoch == epoch else { return }
                    self.sessionInventory = inventory
                }
                self.statusText = "Saved calibration → \(url.lastPathComponent)"
            } catch BraggVectorEMDWriter.WriterError.cancelled {
                guard self.isCurrentOperation(token) else { return }
                self.statusText = "Session calibration save cancelled"
            } catch {
                guard self.isCurrentOperation(token) else { return }
                self.present(error)
            }
        }
    }

    /// Construct the py4DSTEM-axis calibration snapshot. This is the sole save
    /// boundary where app detector x/y becomes py4DSTEM qy/qx.
    private func sessionPixelCalibration(descriptor: DatasetDescriptor) -> PixelCalibration {
        var snapshot = PixelCalibration(
            rSize: calibration.rPixelSize,
            rUnits: calibration.rPixelUnits,
            qSize: calibration.qPixelSize,
            qUnits: calibration.qPixelUnits,
            qrFlip: calibration.transposeQR
        )
        snapshot.qrRotationRad = calibration.rotationRad.map(Double.init)
        snapshot.probeSemiangle = calibration.probeRadius.map(Double.init)
        snapshot.ellipseA = calibration.ellipseA
        snapshot.ellipseB = calibration.ellipseB
        snapshot.ellipseTheta = calibration.ellipseTheta

        if let maps = calibration.origin,
           maps.width == descriptor.rx, maps.height == descriptor.ry,
           maps.fittedX.count == descriptor.rx * descriptor.ry,
           maps.fittedY.count == descriptor.rx * descriptor.ry {
            snapshot.originMaps = PixelOriginMaps(
                shape: [descriptor.ry, descriptor.rx],
                fittedQX: maps.fittedY.map(Double.init),
                fittedQY: maps.fittedX.map(Double.init),
                measuredQX: maps.measuredY?.map(Double.init),
                measuredQY: maps.measuredX?.map(Double.init)
            )
        }
        if let mean = calibration.meanOrigin {
            snapshot.qx0Mean = Double(mean.y)
            snapshot.qy0Mean = Double(mean.x)
        } else if calibration.originProvenance != .geometricDefault {
            snapshot.qx0Mean = Double(aperture.centerY)
            snapshot.qy0Mean = Double(aperture.centerX)
        }
        return snapshot
    }

    private var currentScalarResultMetadata:
        (kind: String, displayName: String, valueUnits: String) {
        switch analysisMode {
        case .virtualDetector:
            return ("virtual_\(virtualShape.rawValue.lowercased())",
                    "Virtual detector · \(virtualShape.rawValue)", "intensity")
        case .dpc:
            switch dpcDisplay {
            case .magnitude:  return ("dpc_magnitude", "DPC magnitude", "detector_px")
            case .magnitudeMrad:
                let physical = dpcMilliradiansPerDetectorPixel != nil
                return (physical ? "dpc_magnitude_mrad" : "dpc_magnitude",
                        physical ? "DPC magnitude (mrad)" : "DPC magnitude",
                        physical ? "mrad" : "detector_px")
            case .angle:      return ("dpc_angle", "DPC angle", "rad")
            case .idpc:
                let physical = idpcPhysicalCalibration != nil
                return (
                    physical ? "idpc_phase" : "idpc_qualitative",
                    physical ? "iDPC projected phase" : "iDPC (qualitative)",
                    physical ? "rad" : "detector_px_scan_px"
                )
            case .colorWheel: return ("dpc_color", "DPC color wheel", "rgba")
            }
        case .strain:
            let units: String
            switch strainComponent {
            case .theta: units = "rad"
            case .residual: units = "detector_px"
            case .indexed: units = "boolean"
            case .exx, .eyy, .exy: units = "strain"
            }
            let kind: String
            switch strainComponent {
            case .exx:   kind = "strain_exx"
            case .eyy:   kind = "strain_eyy"
            case .exy:   kind = "strain_exy"
            case .theta: kind = "strain_theta"
            case .residual: kind = "strain_fit_residual"
            case .indexed: kind = "strain_indexed"
            }
            return (kind, "Strain · \(strainComponent.rawValue)", units)
        case .acom:
            let angular: Set<ACOMDisplayMode> = [.inPlane, .phi1, .Phi, .phi2, .disorientation]
            let baseKind: String
            switch acomDisplay {
            case .ipfZ:        baseKind = "acom_ipf_z"
            case .reliability: baseKind = "acom_reliability"
            case .disorientation:
                baseKind = "acom_\(orientationMap?.symmetry.rawValue ?? "symmetry")_fz_angle"
            case .inPlane:     baseKind = "acom_in_plane"
            case .phi1:        baseKind = "acom_phi1"
            case .Phi:         baseKind = "acom_Phi"
            case .phi2:        baseKind = "acom_phi2"
            case .score:       baseKind = "acom_score"
            }
            // All three scopes are named, including full scan. Previously the
            // qualifier was empty only for full scan, so the most complete
            // product was the one whose label said least about how it was made,
            // and preview vs full-scan results were told apart by the *absence*
            // of a word — which silently matched a stale preview in the QC
            // harness and is unresolvable for a user comparing exported PNGs.
            let scope = acomLastRunScope ?? .fullScan
            let kind = "acom_\(scope.resultQualifier)_\(baseKind.dropFirst(5))"
            return (kind, "ACOM \(scope.rawValue.lowercased()) · \(acomDisplay.rawValue)",
                    angular.contains(acomDisplay) ? "rad" : "dimensionless")
        case .disks:
            return ("bragg_vector_map", "Bragg vector map", "log_intensity")
        case .ptychography:
            switch parallaxResultProduct {
            case .correctedPhase:
                return ("parallax_corrected_phase", "Parallax corrected phase",
                        "arbitrary_phase")
            case .subpixel:
                return ("parallax_subpixel_bf", "Parallax subpixel BF",
                        "normalized_intensity")
            case .alignment:
                return ("parallax_alignment", "Parallax aligned BF",
                        "normalized_intensity")
            case .preprocess:
                return ("parallax_preprocess", "Parallax incoherent BF preview",
                        "normalized_intensity")
            case .depth:
                let depth = parallaxDepth?.depthsAngstrom[parallaxDepthSelectedIndex] ?? 0
                return ("parallax_depth", String(format: "Parallax depth %.1f Å", depth),
                        "arbitrary_phase")
            case .iterativePhase:
                return ("ptychography_object_phase", "Ptychography object phase", "rad")
            case .iterativeAmplitude:
                return ("ptychography_object_amplitude", "Ptychography object amplitude",
                        "dimensionless")
            case .iterativeProbePhase:
                return ("ptychography_probe_phase", "Ptychography probe phase", "rad")
            case .iterativeProbeAmplitude:
                return ("ptychography_probe_amplitude", "Ptychography probe amplitude",
                        "dimensionless")
            }
        }
    }

    private var currentScalarPersistenceMetadata:
        (row: Double?, column: Double?, units: String?, provenance: [String: String]) {
        if analysisMode == .dpc, dpcDisplay == .idpc {
            if let physical = idpcPhysicalCalibration {
                return (
                    Double(physical.rowSamplingAngstrom),
                    Double(physical.columnSamplingAngstrom),
                    "A",
                    [
                        "analysis_mode": analysisMode.rawValue,
                        "source_product": "idpc_phase",
                        "quantitative": "true",
                        "boundary": "symmetric_zero_padded",
                        "padding_factor": "2",
                        "regularization": "0.0001",
                        "reciprocal_angstrom_per_detector_pixel": String(
                            physical.reciprocalAngstromPerDetectorPixel
                        ),
                        "com_to_phase_gradient": "2pi_q",
                    ]
                )
            }
            return (
                calibration.rPixelSize, calibration.rPixelSize,
                calibration.rPixelUnits,
                [
                    "analysis_mode": analysisMode.rawValue,
                    "source_product": "idpc_qualitative",
                    "quantitative": "false",
                    "boundary": "symmetric_zero_padded",
                    "padding_factor": "2",
                    "regularization": "0.0001",
                ]
            )
        }
        if analysisMode == .strain, let map = strainMap {
            let diagnostics = map.diagnostics
            return (
                calibration.rPixelSize, calibration.rPixelSize,
                calibration.rPixelUnits,
                [
                    "analysis_mode": analysisMode.rawValue,
                    "source_product": "strain_\(strainComponent.rawValue)",
                    "basis_mode": diagnostics.automaticBasis ? "consensus" : "manual",
                    "basis_support_fraction": String(diagnostics.basisSupportFraction),
                    "basis_support_count": String(diagnostics.basisSupportCount),
                    "basis_observation_count": String(diagnostics.basisObservationCount),
                    "basis_residual_pixels": String(diagnostics.basisResidualPixels),
                    "basis_condition_number": String(diagnostics.basisConditionNumber),
                    "indexing_tolerance_pixels": String(diagnostics.indexingTolerancePixels),
                    "indexed_fraction": String(map.indexedFraction),
                    "local_residual_median_pixels": String(
                        diagnostics.localResidualMedianPixels
                    ),
                    "reference_mode": diagnostics.referenceMaskApplied
                        ? "selected-region" : "whole-scan",
                    "reference_inliers": String(map.referencePositionCount),
                    "reference_candidates": String(diagnostics.referenceCandidateCount),
                    "reference_rejected": String(diagnostics.referenceRejectedCount),
                    "reference_g1": "\(map.refG1.x),\(map.refG1.y)",
                    "reference_g2": "\(map.refG2.x),\(map.refG2.y)",
                ]
            )
        }
        if analysisMode == .acom, let map = orientationMap {
            var provenance = acomLastRunSemantics?.provenance ?? [:]
            provenance.merge([
                "analysis_mode": analysisMode.rawValue,
                "source_product": "acom_\(acomDisplay.rawValue)",
                "crystal_symmetry": map.symmetry.rawValue,
                "matching_backend": map.matchingBackend.rawValue,
                "template_count": String(map.templateCount),
                "quality": (acomLastRunQuality ?? acomQuality).rawValue,
                "run_scope": (acomLastRunScope ?? .fullScan).resultQualifier,
                "matched_position_count": String(
                    acomLastMatchedPositionCount ?? map.width * map.height
                ),
                "friedel_angle_period_degrees": "180",
            ], uniquingKeysWith: { _, new in new })
            return (
                calibration.rPixelSize, calibration.rPixelSize,
                calibration.rPixelUnits,
                provenance
            )
        }
        if analysisMode == .disks {
            return (
                calibration.qPixelSize, calibration.qPixelSize,
                calibration.qPixelUnits,
                [
                    "analysis_mode": analysisMode.rawValue,
                    "source_product": "bragg_vector_map",
                    "coordinate_space": "reciprocal",
                ]
            )
        }
        guard analysisMode == .ptychography else {
            return (
                calibration.rPixelSize, calibration.rPixelSize,
                calibration.rPixelUnits, ["analysis_mode": analysisMode.rawValue]
            )
        }
        switch parallaxResultProduct {
        case .preprocess:
            let sampling = parallaxPreprocess?.calibration.scanSamplingAngstrom
            return (sampling, sampling, "A", ["source_product": "parallax_preprocess"])
        case .alignment:
            let sampling = parallaxPreprocess?.calibration.scanSamplingAngstrom
            return (sampling, sampling, "A", [
                "source_product": "parallax_alignment",
                "levels": parallaxAlignment?.completedBins.map(String.init)
                    .joined(separator: ",") ?? "",
            ])
        case .subpixel:
            guard let result = parallaxSubpixel else { return (nil, nil, nil, [:]) }
            return (result.outputSamplingAngstrom, result.outputSamplingAngstrom, "A", [
                "source_product": "parallax_subpixel_bf",
                "upsample_factor": String(result.upsampleFactor),
                "kde_sigma_px": String(result.kdeSigmaPixels),
                "interpolation": result.lanczosOrder.map { "lanczos_\($0)" } ?? "bilinear",
                "position_iterations": String(max(0, result.positionCorrectionScores.count - 1)),
                "sinc_lowpass": String(result.lowpassFilter),
            ])
        case .correctedPhase:
            guard let result = parallaxCorrection else { return (nil, nil, nil, [:]) }
            let lowpass = result.qLowpassInvAngstrom.map { String($0) } ?? "off"
            let highpass = result.qHighpassInvAngstrom.map { String($0) } ?? "off"
            let provenance: [String: String] = [
                "source_product": "parallax_corrected_phase",
                "full_fit": String(result.usedFullFit),
                "q_lowpass_inv_a": lowpass,
                "q_highpass_inv_a": highpass,
            ]
            return (result.samplingAngstrom, result.samplingAngstrom, "A", provenance)
        case .depth:
            guard let result = parallaxDepth,
                  result.depthsAngstrom.indices.contains(parallaxDepthSelectedIndex) else {
                return (nil, nil, nil, [:])
            }
            let informationLimit = result.informationLimitInvAngstrom
                .map { String($0) } ?? "off"
            let provenance: [String: String] = [
                "source_product": "parallax_depth",
                "depth_angstrom": String(result.depthsAngstrom[parallaxDepthSelectedIndex]),
                "full_fit": String(result.usedFullFit),
                "information_limit_inv_a": informationLimit,
                "information_power": String(result.informationPower),
            ]
            return (result.samplingAngstrom, result.samplingAngstrom, "A", provenance)
        case .iterativePhase, .iterativeAmplitude,
             .iterativeProbePhase, .iterativeProbeAmplitude:
            guard let result = singleslicePtychography else {
                return (nil, nil, nil, [:])
            }
            let sourceProduct: String
            switch parallaxResultProduct {
            case .iterativePhase: sourceProduct = "ptychography_object_phase"
            case .iterativeAmplitude: sourceProduct = "ptychography_object_amplitude"
            case .iterativeProbePhase: sourceProduct = "ptychography_probe_phase"
            case .iterativeProbeAmplitude: sourceProduct = "ptychography_probe_amplitude"
            default: sourceProduct = "ptychography_object_phase"
            }
            let options = result.options
            return (
                result.objectSamplingRowAngstrom,
                result.objectSamplingColumnAngstrom,
                "A",
                [
                    "source_product": sourceProduct,
                    "engine": "singleslice",
                    "method": options.method.provenanceName,
                    "projection_parameter": String(options.projectionParameter),
                    "iterations": String(result.errorHistory.count),
                    "final_error": result.errorHistory.last.map { String($0) } ?? "",
                    "step_size": String(options.stepSize),
                    "normalization_minimum": String(options.normalizationMinimum),
                    "fix_probe": String(options.fixProbe),
                    "constrain_object_amplitude": String(options.constrainObjectAmplitude),
                    "pure_phase_object": String(options.purePhaseObject),
                    "fix_probe_com": String(options.fixProbeCenterOfMass),
                    "constrain_probe_amplitude": String(options.constrainProbeAmplitude),
                    "probe_amplitude_radius": String(options.probeAmplitudeRelativeRadius),
                    "probe_amplitude_width": String(options.probeAmplitudeRelativeWidth),
                ]
            )
        }
    }

    var currentResultValueUnits: String {
        (restoredResultInfo ?? navigationResultInfo ?? currentScalarResultMetadata).valueUnits
    }

    var currentResultDisplayName: String {
        (restoredResultInfo ?? navigationResultInfo ?? currentScalarResultMetadata).displayName
    }

    var currentResultKind: String {
        (restoredResultInfo ?? navigationResultInfo ?? currentScalarResultMetadata).kind
    }

    var currentResultPersistenceMetadata:
        (row: Double?, column: Double?, units: String?, provenance: [String: String]) {
        let base = restoredResultPixelInfo
            ?? navigationResultPixelInfo
            ?? currentScalarPersistenceMetadata
        var provenance = base.provenance
        provenance["display_domain"] = (
            restoredResultDomain ?? navigationResultDomain ?? activeResultDomain
        ).rawValue
        if provenance["quantitative_status"] == nil {
            provenance["quantitative_status"] = quantitativeStatus(
                for: currentResultKind, units: currentResultValueUnits
            ).rawValue
        }
        return (base.row, base.column, base.units, provenance)
    }

    private var exportBaseName: String {
        let file = descriptor.map { ($0.fileName as NSString).deletingPathExtension } ?? "mac4DSTEM"
        return file
    }

    // MARK: - Rendering helpers

    static func publicationFigure(
        image: CGImage, title: String, caption: String,
        valueRange: (low: Double, high: Double)?, valueUnits: String,
        colormap: ColormapKind
    ) -> CGImage {
        let margin: CGFloat = 18
        let captionHeight: CGFloat = 58
        let colorbarWidth: CGFloat = valueRange == nil ? 0 : 76
        let size = NSSize(
            width: CGFloat(image.width) + margin * 2 + colorbarWidth,
            height: CGFloat(image.height) + margin * 2 + captionHeight
        )
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return image
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSColor.black.setFill()
        NSRect(origin: .zero, size: size).fill()
        let imageRect = NSRect(
            x: margin, y: margin + captionHeight,
            width: CGFloat(image.width), height: CGFloat(image.height)
        )
        NSImage(cgImage: image, size: imageRect.size).draw(in: imageRect)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        (title as NSString).draw(
            in: NSRect(x: margin, y: 25, width: size.width - margin * 2, height: 24),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: NSColor.white, .paragraphStyle: paragraph,
            ]
        )
        (caption as NSString).draw(
            in: NSRect(x: margin, y: 7, width: size.width - margin * 2, height: 17),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: NSColor(calibratedWhite: 0.78, alpha: 1),
                .paragraphStyle: paragraph,
            ]
        )
        if let range = valueRange {
            let lut = Colormaps.lutRGBA(colormap, count: 256)
            let barX = imageRect.maxX + 14
            let barY = imageRect.minY
            let barHeight = imageRect.height
            for index in 0..<256 {
                let offset = index * 4
                NSColor(
                    red: CGFloat(lut[offset]) / 255,
                    green: CGFloat(lut[offset + 1]) / 255,
                    blue: CGFloat(lut[offset + 2]) / 255, alpha: 1
                ).setFill()
                NSRect(x: barX, y: barY + CGFloat(index) / 256 * barHeight,
                       width: 14, height: max(1, barHeight / 256 + 0.5)).fill()
            }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: NSColor.white,
            ]
            (String(format: "%.4g", range.high) as NSString).draw(
                at: NSPoint(x: barX + 19, y: barY + barHeight - 12),
                withAttributes: attributes
            )
            (String(format: "%.4g", range.low) as NSString).draw(
                at: NSPoint(x: barX + 19, y: barY), withAttributes: attributes
            )
            (valueUnits as NSString).draw(
                in: NSRect(x: barX, y: barY - 17, width: 65, height: 14),
                withAttributes: attributes
            )
        }
        return bitmap.cgImage ?? image
    }

    /// Normalized [0,1] scalar pixels → packed RGBA via the colormap LUT,
    /// with the same contrast window the shader applies on screen. Negative
    /// sentinel pixels (FloatImage.invalidDisplayValue) render as the same
    /// masked gray the Metal shader uses.
    private static func applyColormap(_ pixels: [Float], colormap: ColormapKind,
                                      lo: Float, hi: Float, gamma: Float) -> [UInt8] {
        let lut = Colormaps.lutRGBA(colormap, count: 256)
        var out = [UInt8](repeating: 255, count: pixels.count * 4)
        let span = max(hi - lo, 1e-6)
        for (i, raw) in pixels.enumerated() {
            if raw < 0 {
                out[4 * i] = 82; out[4 * i + 1] = 82; out[4 * i + 2] = 87
                continue
            }
            let clipped = min(max((raw - lo) / span, 0), 1)
            let v = pow(clipped, 1 / max(gamma, 0.05))
            let li = Int((v * 255).rounded()) * 4
            out[4 * i]     = lut[li]
            out[4 * i + 1] = lut[li + 1]
            out[4 * i + 2] = lut[li + 2]
        }
        return out
    }

    /// Burn a 1-2-5 scale bar into the bottom-left corner of an export.
    /// Small maps are integer-upscaled (nearest neighbor, so data pixels stay
    /// exact) to ≥512 px wide first, keeping the bar and label legible.
    /// `unitsPerDataPixel` nil → uncalibrated, bar labelled in data px.
    static func burnScaleBar(on base: CGImage,
                             unitsPerDataPixel: Double?,
                             unitLabel: String) -> CGImage {
        let scale = max(1, Int((512.0 / Double(base.width)).rounded(.up)))
        let outW = base.width * scale
        let outH = base.height * scale
        guard let ctx = CGContext(data: nil, width: outW, height: outH,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return base }
        ctx.interpolationQuality = .none   // nearest-neighbor upscale
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: outW, height: outH))

        // Bar sized to a nice 1-2-5 value near 1/5 of the image width.
        let unitsPerOutPixel = (unitsPerDataPixel ?? 1) / Double(scale)
        let nice = ScaleBarView.nice125(unitsPerOutPixel * Double(outW) / 5)
        let barLength = CGFloat(nice / unitsPerOutPixel)
        let margin = CGFloat(max(10, outH / 30))
        let barHeight = CGFloat(max(3, outH / 150))
        let fontSize = CGFloat(max(11, outH / 28))

        let text = "\(ScaleBarView.format(nice)) \(unitLabel)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let textSize = text.size(withAttributes: attributes)

        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns

        // Legibility backing behind bar + label (CG origin is bottom-left).
        let pad: CGFloat = 6
        let backing = CGRect(x: margin - pad, y: margin - pad,
                             width: max(barLength, textSize.width) + 2 * pad,
                             height: barHeight + 4 + textSize.height + 2 * pad)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
        ctx.fill(backing)

        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: margin, y: margin, width: barLength, height: barHeight))
        text.draw(at: NSPoint(x: margin, y: margin + barHeight + 4),
                  withAttributes: attributes)

        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage() ?? base
    }

    private static func cgImage(rgba: [UInt8], width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0, rgba.count == width * height * 4,
              let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(width: width, height: height,
                       bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)
    }

    private static func savePNG(_ image: CGImage, suggestedName: String, state: AppState) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = suggestedName
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL,
                                                         UTType.png.identifier as CFString,
                                                         1, nil) else {
            state.present(SimpleError("Could not create the PNG file."))
            return
        }
        CGImageDestinationAddImage(dest, image, nil)
        if CGImageDestinationFinalize(dest) {
            state.statusText = "Exported \(url.lastPathComponent)"
        } else {
            state.present(SimpleError("Writing the PNG failed."))
        }
    }
}
