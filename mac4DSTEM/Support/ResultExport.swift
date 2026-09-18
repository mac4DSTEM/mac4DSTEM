//
//  ResultExport.swift
//  Role: Minimal result export — PNG of the current real-space result or
//        diffraction pattern (rendered exactly as displayed: colormap, log
//        scale, contrast window), CSV of detected Bragg peaks, and a native
//        py4DSTEM 0.14 / EMD 1.0 BraggVectors HDF5 sidecar.
//

import AppKit
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif
import ImageIO
import UniformTypeIdentifiers

extension AppState {

    private func refreshSessionInventory(from url: URL, isCurrent: () -> Bool) async -> String? {
        do {
            let inventory = try await Task.detached(priority: .utility) {
                try BraggVectorEMDWriter.loadInventory(from: url)
            }.value
            guard isCurrent() else { return nil }
            sessionInventory = inventory
            return nil
        } catch { return Self.errorDetail(error) }
    }

    /// Export a calibrated, optionally cropped/Q-binned py4DSTEM DataCube.
    /// Publication is atomic and the source dataset is never opened for write.
    func exportCalibratedDataCube(options: CalibratedDataCubeExportOptions) {
        // The export reads through the loaded view, so the reader is never
        // handed a shape without its position in the file. A reduced view
        // exports since v2 S10 — the view's patterns and the session's
        // (view-frame) calibration are in the same frame by construction, and
        // the writer refuses the mismatches it can detect; see
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
        // The recipe travels with the exported file, re-expressed in the
        // exported file's OWN detector frame (v2 S10) — a further export bin
        // re-references it exactly the way the promote replay does, through
        // the one shared role table. One unmappable step drops the whole
        // recipe (a recipe replays a coherent pipeline or nothing — S5), and
        // the summary says what was left out and why rather than the
        // attribute going silently missing.
        //
        // THE FRAME GUARD FIRST (S10 Gate B finding 1): `mapForExport`
        // assumes the record is CURRENT-VIEW-frame, and the session record's
        // frame can legitimately differ — a promoted session keeps its
        // rehearsal-frame recipe (`promoteToFullExtent`'s re-adopt), and a
        // sidecar restore adopts the SIDECAR'S frame, which a reconfigure
        // can put out of step with the opened view. Mapping either through
        // the current view's bin would stamp positions in a frame the file
        // is not in — fabricated provenance. Equality against the live
        // view's frame is exact: a recipe recorded in this session on this
        // view always matches (recordReplayStep uses the same derivation),
        // and everything else refuses by name. Composing across three
        // frames is real math for a session that wants it; recorded in
        // docs/open-items.md, not improvised here.
        let (mappedRecipe, recipeOmission) = ReplayRecordFrameMap.exportableRecipe(
            record: replay.recordForSaving,
            recordedFrame: replay.parameterFrame,
            currentSpecification: loadedView.specification,
            exportBin: options.qBin
        )
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
                        options: options, to: url,
                        sourceFileName: descriptor.fileName,
                        replayRecord: mappedRecipe,
                        cancellation: token,
                        progress: progressUpdate
                    )
                }.value
                guard self.isCurrentOperation(token), self.datasetEpoch == epoch else { return }
                let dropped = summary.discardedQRows + summary.discardedQColumns
                var suffix = dropped == 0
                    ? ""
                    : " (trimmed \(summary.discardedQRows) Q row, \(summary.discardedQColumns) Q column)"
                if let recipeOmission {
                    // A partial truth stated whole: the file exists and is
                    // correct; the recipe attribute is absent, and this is
                    // the one carrier of why.
                    suffix += " · recipe not carried: \(recipeOmission)"
                }
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

    /// First save uses a standard panel, defaulted beside the source dataset.
    /// That user action grants sandbox access to create the companion, and the
    /// grant is remembered by `AppState.sessionSidecar` (S1's seam) so later
    /// opens can read it. The bookmark is stored only after atomic publication:
    /// Foundation cannot bookmark the not-yet-existing URL NSSavePanel returns.
    ///
    /// Location and grant logic used to live here, in a `resolvedSessionSidecarURL`
    /// that consulted its cache BEFORE looking at the descriptor — so once any
    /// dataset's bookmark resolved, every later dataset was handed that same
    /// sidecar. Both moved into `App/SessionSidecarLocator.swift`, which keys the
    /// cache by source path. // v2 S1
    /// Persist the grant for a sidecar the app has just published.
    ///
    /// **Both publish paths must call this, and one of them did not.** Found by
    /// Track B row F1.3h on 2026-08-19: `saveCalibrationToSessionSidecar` wrote
    /// the file — crop and all — and never stored a bookmark, so the grant lived
    /// exactly as long as the launch. Its sibling
    /// `saveCurrentResultToSessionSidecar` had always stored one. The two paths
    /// were indistinguishable to the user and differed only in that.
    ///
    /// Worse, the refusal S1 added tells the user to *"Save the session once
    /// (File ▸ Save Calibration to Session Sidecar)… which grants access for
    /// future opens"* — naming the one path that did not. The app printed a
    /// remedy that could not work.
    ///
    /// Called only AFTER atomic publication: Foundation cannot bookmark a URL
    /// that does not exist yet, which is why this is a separate step rather than
    /// part of `writableSessionSidecarURL`. // v2 S1
    private func rememberSidecarGrant(_ url: URL, for descriptor: DatasetDescriptor, what: String) {
        do {
            try sessionSidecar.remember(url, for: descriptor)
        } catch {
            statusText = "Saved \(what); choose the sidecar again after relaunch"
            errorMessage = "\(what) was saved to \(url.lastPathComponent), but mac4DSTEM could not "
                + "remember access for a future launch: \(Self.errorDetail(error))"
        }
    }

    /// Error text that names the failure, not just restates its human summary:
    /// the domain and code, plus the underlying error where the real cause
    /// hides. The sidecar-grant and recent-file "could not remember access"
    /// reports read identically to a real sandbox denial without this. The
    /// cause of one such report (2026-09-17, `docs/open-items.md`) was
    /// `errSecCSStaticCodeChanged` (-67034), which a bare `localizedDescription`
    /// ("The file couldn't be opened") never showed. Same shape as
    /// `Core/ML/LearnedDiskDetector.swift`'s runtime-error text. Delegates to
    /// `Session/SessionSidecarLocator.swift`'s `sessionErrorDetail` — that
    /// file needs the identical formatting and `Session/` may not depend on
    /// `App/`, so the canonical body lives there and this is the `App/`-side
    /// name every existing call site already uses.
    static func errorDetail(_ error: Error) -> String { sessionErrorDetail(error) }

    private func writableSessionSidecarURL(for descriptor: DatasetDescriptor) -> URL? {
        if let granted = sessionSidecar.grant(for: descriptor) { return granted }
        let suggested = BraggVectorEMDWriter.sessionSidecarURL(
            forSourcePath: descriptor.filePath
        )
        guard let url = runSidecarSavePanel(
            title: "Choose Session Sidecar",
            message: "Choose the companion file mac4DSTEM may update and reopen.",
            suggesting: suggested
        ) else {
            statusText = "Session sidecar save cancelled"
            return nil
        }
        sessionSidecar.adopt(url, for: descriptor)
        return url
    }

    /// Export the current real-space result (virtual image / DPC / strain /
    /// ACOM map) as a PNG, rendered as displayed, with the scale bar burned in.
    func exportResultImage() {
        let source: (bytes: [UInt8], width: Int, height: Int)
        // support-export-07 (S22e): masked pixels normalize to the negative
        // invalid-display sentinel; when any exist the burned figure carries
        // a "no data" legend beside its colorbar.
        var masksNoData = false
        // v2.5 step 3 (adapter step 3, plan §9d): the pixels come from the same
        // product the caption below describes — `displayedProduct` — never from
        // the raw fields, so the two halves of one export cannot disagree
        // (they could under the ACOM region reference before this).
        guard let product = displayedProduct else {
            present(SimpleError("No result image to export yet."))
            return
        }
        switch product.payload {
        case .rgba(let rgba):
            source = (rgba.rgba, rgba.width, rgba.height)
        case .scalar(let image):
            let norm = image.normalized(symmetric: resultColormap.isDiverging)
            masksNoData = norm.contains { $0 < 0 }
            let bytes = Self.applyColormap(norm, colormap: resultColormap,
                                           lo: displayRangeLo, hi: displayRangeHi,
                                           gamma: resultGamma)
            source = (bytes, image.width, image.height)
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
            valueUnits: currentResultValueUnits, colormap: resultColormap,
            masksNoData: masksNoData
        )
        // The FULL provenance record travels in the PNG metadata beside the
        // burned caption (v2 S7): everything the figure renders, plus the
        // persistence provenance the caption can only excerpt.
        Self.savePNG(
            final, suggestedName: exportBaseName + "_result.png", state: self,
            properties: Self.pngProperties(
                title: currentResultDisplayName,
                record: exportedImageProvenanceRecord()
            )
        )
    }

    /// The machine-readable half of the exported figure's provenance (v2 S7).
    /// Internal so the tests can pin its content without a save panel.
    func exportedImageProvenanceRecord() -> [String: Any] {
        let pixel = currentResultPersistenceMetadata
        var record: [String: Any] = [
            "title": currentResultDisplayName,
            "caption": publicationCaption,
            "value_units": currentResultValueUnits,
            "provenance": pixel.provenance,
            "load_specification":
                loadedView.specification.provenanceSummary ?? "whole file",
        ]
        if let row = pixel.row { record["pixel_size_row"] = row }
        if let column = pixel.column { record["pixel_size_column"] = column }
        if let units = pixel.units { record["pixel_units"] = units }
        if let file = descriptor?.fileName { record["source_file"] = file }
        // Finite values only: `JSONSerialization` rejects NaN/inf outright,
        // and one degenerate range value would silently drop the ENTIRE
        // metadata record from the file (Gate B, 2026-08-25). A missing
        // range key is honest; a missing record is not.
        if let range = resultDisplayedValueRange,
           range.low.isFinite, range.high.isFinite {
            record["display_range_low"] = range.low
            record["display_range_high"] = range.high
        }
        if !realSpaceDisplayIsDefault {
            for (key, value) in realSpaceDisplayProvenance {
                record[key] = value
            }
        }
        // NO origin-fit keys. This record covers EVERY displayed product,
        // including ones no origin was involved in, and it is built at export
        // time — so v2 S13's version stamped a residual and an excluded
        // fraction onto virtual images and CBED patterns alike, describing
        // whatever calibration happened to be loaded when Save was pressed
        // (Gate B, 2026-08-28). The owner's §6a disclosure is carried where it
        // can be true: on screen, and on the strain bundle, which snapshots it
        // at compute time.
        return record
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
        // strain_frame and qr_rotation_deg: a strain figure must name the
        // frame ON ITS FACE — the caption is the one carrier that survives a
        // screenshot (v2 S8).
        for key in ["source_product", "basis_mode", "matching_backend", "reference_mode",
                    "strain_frame", "qr_rotation_deg",
                    // `origin_reference` and `origin_fit_positions_used_fraction`
                    // were here in v2 S13's version. They come from
                    // `product.provenance`, so for the strain bundle they are
                    // now the compute-time snapshot and would be safe — but the
                    // caption is BURNT INTO THE PIXELS, and it is drawn for
                    // every product, most of which carry no such snapshot. A
                    // claim that cannot be corrected afterwards is the last
                    // place to put one that might be wrong (Gate B, 2026-08-28).
                    ] {
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
    /// The presentation-frame provenance keys every strain carrier shares —
    /// the displayed-result metadata and the scientific bundle — composed in
    /// ONE place so two exports can never disagree about the frame. // v2 S8
    /// The origin-fit keys every product derived from a re-centred Bragg
    /// vector shares, composed in ONE place — the same shape as
    /// `strainFrameProvenance` and for the same reason. // v2 S13
    ///
    /// The release owner's §6(a) decision, 2026-08-28: a trimmed calibration is
    /// admitted and **the excluded fraction is carried on the product**, so it
    /// travels with the result through export and reopen instead of living in a
    /// log. `origin_reference` is the other half — a number derived against the
    /// detector's geometric middle and one derived against a measured beam
    /// centre are not the same claim, and until S13 nothing said which it was.
    var originFitProvenance: [String: String] {
        var keys: [String: String] = [:]
        if let descriptor {
            let origin = calibrationSession.calibration.referenceOrigin(
                detectorQX: descriptor.qx, detectorQY: descriptor.qy,
                apertureCentre: (x: aperture.centerX, y: aperture.centerY)
            )
            keys["origin_reference"] = origin.kind.rawValue
            keys["origin_reference_is_measured"] =
                origin.kind.isMeasuredBeamCentre ? "true" : "false"
        }
        if let residual = calibrationSession.calibration.judgedOriginResidual, residual.isFinite {
            keys["origin_fit_residual_px"] = String(residual)
        }
        if let excluded = calibrationSession.calibration.origin?.excludedFraction, excluded.isFinite {
            keys["origin_fit_excluded_fraction"] = String(excluded)
            keys["origin_fit_positions_used_fraction"] = String(1 - excluded)
        }
        return keys
    }

    var strainFrameProvenance: [String: String] {
        let frame = strainPresentationFrame
        var keys: [String: String] = ["strain_frame": frame.provenanceValue]
        switch frame {
        case .scan(let rotationRad, let transposed):
            keys["qr_rotation_rad"] = String(rotationRad)
            keys["qr_rotation_deg"] = String(format: "%.1f", rotationRad * 180 / .pi)
            keys["qr_transposed"] = transposed ? "true" : "false"
        case .detector:
            keys["strain_frame_reason"] = "qr_rotation_not_calibrated"
        }
        return keys
    }

    func scientificBundleMaps() -> [ScalarResultMap]? {
        let sampling = (calibrationSession.calibration.rPixelSize, calibrationSession.calibration.rPixelUnits)
        var bundle: [ScalarResultMap] = []
        if let map = strain.map {
            // The tensor components are exported in the presentation frame —
            // exactly what the screen shows — with the frame and the applied
            // rotation named in provenance (v2 S8). Diagnostics (residual,
            // validity) are frame-free and come from the base map.
            let presented = map.presented(in: strainPresentationFrame)
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
            provenance.merge(strainFrameProvenance) { current, _ in current }
            // The snapshot taken when the map was computed, NOT the live
            // calibration — see `StrainProduct.originProvenance`. // Gate B
            provenance.merge(strain.originProvenance) { current, _ in current }
            // The weighting DEVIATION from py4DSTEM, carried outward rather
            // than living only in a source comment (S11, 2026-08-28).
            // `StrainMapping.fitLattice` minimizes Σ w·r² where py4DSTEM's
            // `fit_lattice_vectors` minimizes Σ w²·r²; measured effect on
            // sim_Au is ~5e-3 median per strain component against a ~2e-4
            // agreement floor when the estimators are matched — 25× the floor
            // and comparable to real strain signals, so a reader comparing this
            // bundle against py4DSTEM numbers has to be told.
            provenance["strain_weighting"] = "w_r2"
            provenance["strain_weighting_py4dstem"] = "w2_r2"
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
                field("strain_exx", "Strain ε_xx", "strain", masked(presented.exx)),
                field("strain_eyy", "Strain ε_yy", "strain", masked(presented.eyy)),
                field("strain_exy", "Strain ε_xy", "strain", masked(presented.exy)),
                field("strain_theta", "Lattice rotation θ", "rad", masked(presented.theta)),
                field("strain_validity", "Strain validity", "boolean", map.mask.map { $0 ? 1 : 0 }),
                field("strain_fit_residual", "Local fit residual", "detector_px",
                      masked(map.localResidualPixels)),
            ]
        }
        if let map = acomSession.orientationMap, let semantics = acomSession.lastRunSemantics {
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
            // The origin-fit keys come from `semantics.originProvenance`, the
            // compute-time snapshot (2026-09-05) — never from the live
            // calibration, which is the defect Gate B found on 2026-08-28:
            // keys describing an origin the map was not computed against.
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
        if strain.map != nil, !included.contains("strain") { omitted.append("strain") }
        if acomSession.orientationMap != nil, acomSession.lastRunSemantics != nil,
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
        let qSize = calibrationSession.calibration.qPixelSize
        let final = Self.burnScaleBar(on: cg,
                                      unitsPerDataPixel: qSize,
                                      unitLabel: qSize != nil ? (calibrationSession.calibration.qPixelUnits ?? "1/nm") : "px")
        Self.savePNG(final, suggestedName: exportBaseName + "_cbed.png", state: self)
    }

    /// Panel-free construction seam: export tests exercise the exact scalar
    /// payload handed to the sidecar writer, including its units and encoding.
    func currentScalarResultMapForPersistence() -> ScalarResultMap? {
        guard let image = resultImage else { return nil }
        // v2.5 step 3b-8: the sidecar map is built from the product when one is
        // published (always, now); the chain below is the pre-product path.
        let metadata: (kind: String, displayName: String, valueUnits: String) =
            publishedProduct.map { ($0.kind, $0.displayName, $0.valueUnits) }
            ?? currentScalarResultMetadata
        let persistence: (
            row: Double?, column: Double?, units: String?, provenance: [String: String]
        )
        if publishedProduct != nil {
            persistence = currentResultPersistenceMetadata
        } else {
            persistence = currentResultPersistenceMetadata
        }
        return ScalarResultMap(
            width: image.width, height: image.height, pixels: image.pixels,
            kind: metadata.kind, displayName: metadata.displayName,
            valueUnits: metadata.valueUnits,
            pixelSizeRow: persistence.row,
            pixelSizeColumn: persistence.column,
            pixelUnits: persistence.units,
            provenance: persistence.provenance
        )
    }

    /// Save the current scalar or scan-shaped scientific RGBA result to the stable companion
    /// `<source>.mac4dstem.h5`. Existing BraggVectors are preserved when the
    /// current session has none, and a current detection replaces the saved
    /// vectors together with the map in one atomic publication.
    func saveCurrentResultToSessionSidecar() {
        guard let descriptor else { return }
        // Same rewrite gate as the calibration save — see
        // `saveCalibrationToSessionSidecar`. // v2 S7
        if let refusal = gates.sidecarRewriteRefusal() {
            present(SimpleError(refusal))
            return
        }
        let scalarMap: ScalarResultMap?
        let rgbaMap: RGBAResultMap?
        let metadata: (kind: String, displayName: String, valueUnits: String) =
            publishedProduct.map { ($0.kind, $0.displayName, $0.valueUnits) }
            ?? currentScalarResultMetadata
        if let map = currentScalarResultMapForPersistence() {
            scalarMap = map
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
                // Captured on the MainActor before the detached write: the
                // view the products belong to, and the session recipe. Every
                // rewrite restates BOTH — a result save that omitted the
                // specification silently erased the crop attribute from the
                // sidecar (found by S5). // v2 S5
                let specification = loadedView.specification
                let recipe = replay.recordForSaving
                try await Task.detached(priority: .userInitiated) {
                    if let scalarMap {
                        try BraggVectorEMDWriter.mergeResultMap(
                            scalarMap, vectors: vectors,
                            qWidth: descriptor.qx, qHeight: descriptor.qy,
                            calibration: pixelCalibration, to: url,
                            loadSpecification: specification, replayRecord: recipe,
                            cancellation: token, progress: progressUpdate
                        )
                    } else if let rgbaMap {
                        try BraggVectorEMDWriter.mergeRGBAResultMap(
                            rgbaMap, vectors: vectors,
                            qWidth: descriptor.qx, qHeight: descriptor.qy,
                            calibration: pixelCalibration, to: url,
                            loadSpecification: specification, replayRecord: recipe,
                            cancellation: token, progress: progressUpdate
                        )
                    }
                }.value
                guard self.isCurrentOperation(token), self.datasetEpoch == epoch else { return }
                let inventoryRefreshError = await self.refreshSessionInventory(from: url) {
                    self.isCurrentOperation(token) && self.datasetEpoch == epoch
                }
                guard self.isCurrentOperation(token), self.datasetEpoch == epoch else { return }
                // The published target now exists and can back a bookmark.
                self.statusText = inventoryRefreshError.map {
                    "Saved \(metadata.displayName), but Results could not be refreshed: \($0)"
                } ?? "Saved \(metadata.displayName) → \(url.lastPathComponent)"
                self.rememberSidecarGrant(url, for: descriptor, what: metadata.displayName)
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
        let url = sessionSidecar.location(for: descriptor)
        let epoch = datasetEpoch
        do {
            switch saved.storage {
            case .scalarFloat32:
                let map = try await Task.detached(priority: .utility) {
                    try BraggVectorEMDWriter.loadResultMap(id: saved.id, from: url)
                }.value
                guard epoch == datasetEpoch, let map else { return }
                publishRestoredProduct(   // v2.5 step 3b-6
                    kind: map.kind, displayName: map.displayName, valueUnits: map.valueUnits,
                    payload: .scalar(FloatImage(width: map.width, height: map.height, pixels: map.pixels)),
                    pixelSizeRow: map.pixelSizeRow, pixelSizeColumn: map.pixelSizeColumn,
                    pixelUnits: map.pixelUnits, provenance: map.provenance)
            case .rgba8:
                let map = try await Task.detached(priority: .utility) {
                    try BraggVectorEMDWriter.loadRGBAResultMap(id: saved.id, from: url)
                }.value
                guard epoch == datasetEpoch, let map else { return }
                publishRestoredProduct(   // v2.5 step 3b-6
                    kind: map.kind, displayName: map.displayName, valueUnits: map.valueUnits,
                    payload: .rgba(RGBAImage(width: map.width, height: map.height, rgba: map.rgba)),
                    pixelSizeRow: map.pixelSizeRow, pixelSizeColumn: map.pixelSizeColumn,
                    pixelUnits: map.pixelUnits, provenance: map.provenance)
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
        let url = sessionSidecar.location(for: descriptor)
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
        guard let product = publishedProduct, product.origin == .restoredFromSidecar else {
            return nil
        }
        let plan = SessionControlRehydration.parse(
            kind: product.kind, provenance: product.provenance
        )
        return plan.isEmpty ? nil : plan
    }

    func applySelectedSavedControls() {
        guard let plan = selectedSavedControlRehydration else { return }
        if let value = plan.kdeUpsampleFactor { phaseContrast.parallaxKDEUpsampleFactor = value }
        if let value = plan.kdeSigmaPixels { phaseContrast.parallaxKDESigmaPixels = value }
        if let value = plan.kdeLanczosOrder { phaseContrast.parallaxKDELanczosOrder = value }
        if let value = plan.positionIterations {
            phaseContrast.parallaxPositionCorrectionIterations = value
        }
        if let value = plan.kdeLowpass { phaseContrast.parallaxKDELowpass = value }
        if let value = plan.qLowpassInvAngstrom { phaseContrast.parallaxQLowpassInvAngstrom = value }
        if let value = plan.qHighpassInvAngstrom { phaseContrast.parallaxQHighpassInvAngstrom = value }
        if let value = plan.depthAngstrom {
            phaseContrast.parallaxDepthStartAngstrom = value
            phaseContrast.parallaxDepthEndAngstrom = value
            phaseContrast.parallaxDepthPlaneCount = 1
        }
        if let value = plan.depthUseFullFit { phaseContrast.parallaxDepthUseFullFit = value }
        if let value = plan.depthInformationLimit {
            phaseContrast.parallaxDepthInformationLimit = value
        }
        if let value = plan.depthInformationPower { phaseContrast.parallaxDepthInformationPower = value }
        if let value = plan.ptychographyIterations { ptychography.iterations = value }
        if let value = plan.ptychographyMethod {
            switch value {
            case "gradient-descent": ptychography.method = .gradientDescent
            case "difference-map_alternating-projections":
                ptychography.method = .differenceMapAlternatingProjections
            default: break
            }
        }
        if let value = plan.ptychographyStepSize { ptychography.stepSize = value }
        if let value = plan.ptychographyProjectionParameter {
            ptychography.projectionParameter = value
        }
        if let value = plan.ptychographyNormalizationMinimum {
            ptychography.normalizationMinimum = value
        }
        if let value = plan.ptychographyFixProbe { ptychography.fixProbe = value }
        if let value = plan.ptychographyConstrainObjectAmplitude {
            ptychography.constrainObjectAmplitude = value
        }
        if let value = plan.ptychographyPurePhaseObject {
            ptychography.purePhaseObject = value
        }
        if let value = plan.ptychographyFixProbeCenterOfMass {
            ptychography.fixProbeCenterOfMass = value
        }
        if let value = plan.ptychographyConstrainProbeAmplitude {
            ptychography.constrainProbeAmplitude = value
        }
        if let value = plan.ptychographyProbeAmplitudeRadius {
            ptychography.probeAmplitudeRadius = value
        }
        if let value = plan.ptychographyProbeAmplitudeWidth {
            ptychography.probeAmplitudeWidth = value
        }
        statusText = "Applied saved controls: \(plan.summary). Re-run explicitly to reconstruct."
    }

    func removeSavedSessionResult(_ saved: SessionResultDescriptor) async {
        guard let descriptor else { return }
        // Removal rebuilds the file, so it is a rewrite too — same gate as
        // the two save paths. // v2 S7
        if let refusal = gates.sidecarRewriteRefusal() {
            present(SimpleError(refusal))
            return
        }
        let url = sessionSidecar.location(for: descriptor)
        let calibration = sessionPixelCalibration(descriptor: descriptor)
        let epoch = datasetEpoch
        let token = beginCancellableOperation(
            "Session result removal", status: "Removing \(saved.displayName)…"
        )
        defer { finishCancellableOperation(token) }
        do {
            // Removal rebuilds the file too — it restates the view and the
            // recipe like every other rewrite. // v2 S5
            let specification = loadedView.specification
            let recipe = replay.recordForSaving
            try await Task.detached(priority: .userInitiated) {
                try BraggVectorEMDWriter.removeResult(
                    kind: saved.kind, qWidth: descriptor.qx, qHeight: descriptor.qy,
                    calibration: calibration, from: url,
                    loadSpecification: specification, replayRecord: recipe,
                    cancellation: token
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
                publishedProduct = nil
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

    // MARK: - Save Session Sidecar As… (v2 S4)

    // `SidecarCopyOutcome` and `copySidecarFile` moved to
    // `SessionSidecarLocator` (C7 session 4, budget relocation) — pure
    // Foundation file work with no AppState dependency.

    /// The one sidecar save panel, shared by the first-save path
    /// (`writableSessionSidecarURL`) and Save As — the S1 lesson in panel
    /// form: two hand-built copies of the grant sequence is how one of them
    /// ends up missing a step. Returns the chosen URL with its security scope
    /// started, or nil on cancel (the caller words its own cancel status).
    private func runSidecarSavePanel(title: String, message: String, suggesting suggested: URL) -> URL? {
        let panel = NSSavePanel()
        panel.title = title
        panel.message = message
        panel.directoryURL = suggested.deletingLastPathComponent()
        panel.nameFieldStringValue = SessionSidecarFormat.savePanelSeedName(for: suggested)
        panel.allowedContentTypes = [UTType(filenameExtension: "h5") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        return url
    }

    /// Re-offer the save panel that `writableSessionSidecarURL` only shows
    /// while no grant exists. Before S1 no bookmark ever resolved, so that
    /// panel appeared on every save; S1 made grants resolve, which armed the
    /// early return and made a misplaced sidecar PERMANENTLY misplaced —
    /// observed 2026-08-19 (three saves, no panel), and it withdrew Track B
    /// row F1.3i by construction. This is the way home.
    func saveSessionSidecarAs() {
        guard let descriptor else {
            present(SimpleError("No dataset is open."))
            return
        }
        let current = sessionSidecar.location(for: descriptor)
        guard let url = runSidecarSavePanel(
            title: "Save Session Sidecar As",
            message: "Choose the companion file mac4DSTEM keeps this dataset's session in. Existing saved results are copied across.",
            suggesting: current
        ) else {
            statusText = "Session sidecar unchanged"
            return
        }
        adoptSessionSidecar(at: url, movingFrom: current, for: descriptor)
    }

    /// The panel-free half: copy what exists, retarget the seam, persist the
    /// grant when there is a file to bookmark, and re-read the inventory from
    /// the file the inspector will now be describing. Internal so the wiring
    /// is testable — the S1 lesson about tests that cannot reach the call site.
    func adoptSessionSidecar(at url: URL, movingFrom current: URL, for descriptor: DatasetDescriptor) {
        let outcome = SessionSidecarLocator.copySidecarFile(from: current, to: url)
        // Same-file detection by the SAME identity test `copySidecarFile`
        // uses, not by path string: a symlink or case-differing spelling of
        // one file would otherwise skip the re-grant below while the copy
        // correctly did nothing — the grant then never persists and the
        // remedy silently fails on reopen. One question, one derivation
        // (Gate B, 2026-08-25).
        let sameFile: Bool = {
            if url.standardizedFileURL == current.standardizedFileURL { return true }
            if let chosen = try? url.resourceValues(
                   forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier,
               let existing = try? current.resourceValues(
                   forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier,
               chosen.isEqual(existing) { return true }
            return false
        }()
        if case .nothingToCopy = outcome, sameFile {
            // Choosing the SAME existing file is not a no-op: the panel pick
            // is a sandbox grant, and re-granting access to a sidecar the app
            // could not read is the remedy the unreadable-restore refusal
            // names (`SessionGates.sidecarRewriteRefusal`). Discarding it
            // here left that remedy printed but unworkable — the F1.3h shape
            // again, a message naming a path that cannot work. // v2 S7
            if FileManager.default.fileExists(atPath: url.path) {
                sessionSidecar.adopt(url, for: descriptor)
                rememberSidecarGrant(url, for: descriptor, what: "Session sidecar")
                statusText = "Session sidecar unchanged — access to "
                    + "\(url.lastPathComponent) re-granted; reopen the dataset "
                    + "to restore its recorded session"
            } else {
                statusText = "Session sidecar unchanged — the same file was chosen"
            }
            return
        }
        sessionSidecar.adopt(url, for: descriptor)
        switch outcome {
        case .copied:
            // Foundation can only bookmark a URL that exists — which it now
            // does. The `nothingToCopy` branch leaves persistence to the next
            // real save, exactly as a first-ever save does.
            rememberSidecarGrant(url, for: descriptor, what: "Session sidecar")
            statusText = "Session sidecar is now \(url.lastPathComponent) — copied from "
                + "\(current.lastPathComponent); the previous file was not deleted"
        case .nothingToCopy:
            // Known limit, stated in the message: with no file to bookmark,
            // the retarget lives in memory and survives only until the next
            // dataset change — the first real save persists it.
            statusText = "Session sidecar will be \(url.lastPathComponent) from the next save in this session"
        case .failed(let reason):
            // Honest split outcome: the retarget stands (that is the user's
            // stated intent), the copy did not happen, and the message says
            // which half is which rather than pretending either way.
            statusText = "Session sidecar is now \(url.lastPathComponent), but the existing file could not be copied"
            errorMessage = "New session saves go to \(url.lastPathComponent), but the existing "
                + "sidecar \(current.lastPathComponent) could not be copied across: \(reason)"
        }
        // The inspector's tree is drawn from `sessionInventory` under the name
        // from the seam — re-read it from the NEW location so a failed copy
        // shows an empty section rather than the old file's results under the
        // new file's name (a tree describing a file that does not exist).
        let epoch = datasetEpoch
        Task { @MainActor [weak self] in
            guard let self else { return }
            let isCurrent = { self.datasetEpoch == epoch && self.sessionSidecar.location(for: descriptor) == url }
            let inventoryRefreshError = await self.refreshSessionInventory(from: url, isCurrent: isCurrent)
            guard isCurrent() else { return }
            if let inventoryRefreshError {
                self.sessionInventory = .empty
                self.statusText = "Session sidecar location changed, but Results could not be read: \(inventoryRefreshError)"
            }
        }
    }

    /// Publish calibration independently of the currently displayed result.
    /// Existing maps and BraggVectors are copied into the replacement file.
    func saveCalibrationToSessionSidecar() {
        guard let descriptor else {
            present(SimpleError("No dataset is open."))
            return
        }
        // Every sidecar rewrite restates the current view, so a rewrite after
        // a failed crop restore would erase the recorded crop and mislabel
        // the preserved results (S5 finding F9). One gate, asked at every
        // rewrite entry point. // v2 S7
        if let refusal = gates.sidecarRewriteRefusal() {
            present(SimpleError(refusal))
            return
        }
        guard let url = writableSessionSidecarURL(for: descriptor) else { return }
        let snapshot = sessionPixelCalibration(descriptor: descriptor)
        let epoch = datasetEpoch
        // The view these values were calibrated in. A calibration measured on a
        // binned cube is in that cube's detector pixels, so saving it without
        // saying which view it came from would make it unreadable later — the
        // labelling half of invariant I3.
        let specification = loadedView.specification
        // The recipe travels with every publish, captured on the MainActor
        // before the detached write. // v2 S5
        let recipe = replay.recordForSaving
        // Labels ride along the same way (C7 session 4); nil (an empty
        // store) tells `mergeCalibration` to preserve what the sidecar has.
        let labelsJSON: String?
        do {
            labelsJSON = diskCentreLabels.isEmpty
                ? nil : String(decoding: try diskCentreLabels.encodedJSON(), as: UTF8.self)
        } catch {
            present(error)
            return
        }
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
                        to: url, loadSpecification: specification,
                        replayRecord: recipe, diskCentreLabelsJSON: labelsJSON,
                        cancellation: token
                    )
                }.value
                guard self.isCurrentOperation(token), self.datasetEpoch == epoch else { return }
                let inventoryRefreshError = await self.refreshSessionInventory(from: url) {
                    self.isCurrentOperation(token) && self.datasetEpoch == epoch
                }
                guard self.isCurrentOperation(token), self.datasetEpoch == epoch else { return }
                self.statusText = inventoryRefreshError.map {
                    "Saved calibration, but Results could not be refreshed: \($0)"
                } ?? "Saved calibration → \(url.lastPathComponent)"
                self.rememberSidecarGrant(url, for: descriptor, what: "Calibration")
            } catch BraggVectorEMDWriter.WriterError.cancelled {
                guard self.isCurrentOperation(token) else { return }
                self.statusText = "Session calibration save cancelled"
            } catch {
                guard self.isCurrentOperation(token) else { return }
                self.present(error)
            }
        }
    }

    /// Write the current labels to Documents/mac4DSTEM/disk-labels/ (C7
    /// session 4) as a standalone file — `label_centres.py`'s own JSON, for
    /// moving into `tools/disk-detector/labels/`. Distinct from "Save to
    /// Sidecar", which keeps the labels beside the dataset.
    func exportDiskCentreLabels() -> AnalysisRunOutcome {
        guard let descriptor else {
            return .failed("No dataset is open.")
        }
        guard !diskCentreLabels.isEmpty else {
            return .failed("No disk-centre labels yet — click some centres first")
        }
        guard let documentsURL = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first else {
            return .failed("Could not locate this app's Documents folder")
        }
        let folder = documentsURL.appendingPathComponent("mac4DSTEM/disk-labels", isDirectory: true)
        let datasetName = URL(fileURLWithPath: descriptor.filePath)
            .deletingPathExtension().lastPathComponent
        do {
            let url = try diskCentreLabels.exportForFineTuning(to: folder, datasetName: datasetName)
            statusText = "Exported disk-centre labels → \(url.lastPathComponent)"
            return .published
        } catch {
            return .failed("Could not export disk-centre labels: \(error.localizedDescription)")
        }
    }

    /// The diffraction pane's click while "Label centres on click" is on:
    /// add a centre, or remove the nearest one within 3 px. Refuses outside
    /// `.current` display (Mean/Max have no single scan position) and while
    /// the toggle is off.
    func toggleDiskCentre(atPatternRow row: Float, col: Float) -> AnalysisRunOutcome {
        guard let descriptor else {
            return .failed("No dataset is open.")
        }
        // The pane's tap catcher maps its border to −0.5 / q − 0.5 (Gate B, 2026-09-08).
        guard row >= 0, col >= 0, row < Float(descriptor.qy), col < Float(descriptor.qx) else {
            return .failed("That click landed outside the pattern")
        }
        guard patternDisplayMode == .current else {
            return .failed("Switch the pattern display to Current — Mean and Max have no single scan position to label")
        }
        guard diskCentreLabels.labelling else {
            return .failed("Turn on \"Label centres on click\" in Disk detection first")
        }
        let centre = DiskCentreLabelStore.Centre(row: row, col: col)
        let rx = selectedScan.x, ry = selectedScan.y
        if !diskCentreLabels.removeNearest(to: centre, within: 3, ry: ry, rx: rx) {
            diskCentreLabels.add(centre, ry: ry, rx: rx)
        }
        let n = diskCentreLabels.centres(ry: ry, rx: rx).count
        statusText = "Scan (\(ry), \(rx)): \(n) centre\(n == 1 ? "" : "s")"
        return .published
    }

    // `exportableRecipe` moved to `ReplayRecordFrameMap` in
    // `Session/ReplayPlan.swift` (C7 session 4, budget relocation) — it was
    // already pure and already called straight into that type.

    /// Construct the py4DSTEM-axis calibration snapshot. This is the sole save
    /// boundary where app detector x/y becomes py4DSTEM qy/qx.
    private func sessionPixelCalibration(descriptor: DatasetDescriptor) -> PixelCalibration {
        var snapshot = PixelCalibration(
            rSize: calibrationSession.calibration.rPixelSize,
            rUnits: calibrationSession.calibration.rPixelUnits,
            qSize: calibrationSession.calibration.qPixelSize,
            qUnits: calibrationSession.calibration.qPixelUnits,
            qrFlip: calibrationSession.calibration.transposeQR
        )
        snapshot.qrRotationRad = calibrationSession.calibration.rotationRad.map(Double.init)
        snapshot.probeSemiangle = calibrationSession.calibration.probeRadius.map(Double.init)
        snapshot.ellipseA = calibrationSession.calibration.ellipseA
        snapshot.ellipseB = calibrationSession.calibration.ellipseB
        snapshot.ellipseTheta = calibrationSession.calibration.ellipseTheta

        if let maps = calibrationSession.calibration.origin,
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
        if let mean = calibrationSession.calibration.meanOrigin {
            snapshot.qx0Mean = Double(mean.y)
            snapshot.qy0Mean = Double(mean.x)
        } else if let recorded = calibrationSession.calibration.recordedMeanOrigin {
            // v2 S13: the recorded beam centre now has a home of its own, so a
            // `.fileMean`/`.sessionMean` session round-trips the ORIGIN rather
            // than wherever the user last dragged the aperture.
            snapshot.qx0Mean = Double(recorded.y)
            snapshot.qy0Mean = Double(recorded.x)
        } else if calibrationSession.calibration.originProvenance != .geometricDefault {
            snapshot.qx0Mean = Double(aperture.centerY)
            snapshot.qy0Mean = Double(aperture.centerX)
        }
        return snapshot
    }

    var currentScalarPersistenceMetadata:   // internal since v2.5 step 3c: publishLegacy reads it
        (row: Double?, column: Double?, units: String?, provenance: [String: String]) {
        if navigation.analysisMode == .dpc, dpc.dpcDisplay == .idpc {
            if let physical = idpcPhysicalCalibration {
                return (
                    Double(physical.rowSamplingAngstrom),
                    Double(physical.columnSamplingAngstrom),
                    "A",
                    [
                        "analysis_mode": navigation.analysisMode.rawValue,
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
            // WHY it is qualitative travels with the product (v2 S7, Gate B):
            // "quantitative": "false" alone cannot distinguish "the
            // calibration is incomplete" from "every requirement is met and
            // the origin fit was judged unreliable — and its origins were
            // still subtracted from the CoM field". A reader of the exported
            // file needs that difference to know whether to trust contrast.
            var provenance: [String: String] = [
                "analysis_mode": navigation.analysisMode.rawValue,
                "source_product": "idpc_qualitative",
                "quantitative": "false",
                "boundary": "symmetric_zero_padded",
                "padding_factor": "2",
                "regularization": "0.0001",
            ]
            if let judgement = calibrationSession.calibration.originFitJudgement {
                provenance["qualitative_reason"] = "origin_fit_not_quantitative"
                provenance["origin_fit_judgement"] = judgement
                provenance["origins_subtracted"] =
                    calibrationSession.calibration.hasFittedOrigin ? "fitted_per_position" : "none"
            } else {
                provenance["qualitative_reason"] = "calibration_incomplete"
            }
            return (
                calibrationSession.calibration.rPixelSize, calibrationSession.calibration.rPixelSize,
                calibrationSession.calibration.rPixelUnits,
                provenance
            )
        }
        if navigation.analysisMode == .strain, let map = strain.map {
            let diagnostics = map.diagnostics
            var provenance: [String: String] = [
                "analysis_mode": navigation.analysisMode.rawValue,
                "source_product": "strain_\(strain.component.rawValue)",
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
                // Detector-frame measurement primitives regardless of the
                // presentation frame — they locate g₁/g₂ on the pattern.
                "reference_g1": "\(map.refG1.x),\(map.refG1.y)",
                "reference_g2": "\(map.refG2.x),\(map.refG2.y)",
            ]
            // The frame the tensor components are expressed in — never
            // implied (v2 S8). Rad for machine parity with py4DSTEM's
            // QR_rotation, degrees for the human reading the caption.
            provenance.merge(strainFrameProvenance) { current, _ in current }
            return (
                calibrationSession.calibration.rPixelSize, calibrationSession.calibration.rPixelSize,
                calibrationSession.calibration.rPixelUnits,
                provenance
            )
        }
        if navigation.analysisMode == .acom, let map = acomSession.orientationMap {
            var provenance = acomSession.lastRunSemantics?.provenance ?? [:]
            provenance.merge([
                "analysis_mode": navigation.analysisMode.rawValue,
                "source_product": "acom_\(acomSession.display.rawValue)",
                "crystal_symmetry": map.symmetry.rawValue,
                "matching_backend": map.matchingBackend.rawValue,
                "template_count": String(map.templateCount),
                "quality": (acomSession.lastRunQuality ?? acomSession.quality).rawValue,
                "run_scope": (acomSession.lastRunScope ?? .fullScan).resultQualifier,
                "matched_position_count": String(
                    acomSession.lastMatchedPositionCount ?? map.width * map.height
                ),
                "friedel_angle_period_degrees": "180",
            ], uniquingKeysWith: { _, new in new })
            return (
                calibrationSession.calibration.rPixelSize, calibrationSession.calibration.rPixelSize,
                calibrationSession.calibration.rPixelUnits,
                provenance
            )
        }
        if navigation.analysisMode == .disks {
            var provenance = ["analysis_mode": navigation.analysisMode.rawValue,
                              "source_product": "bragg_vector_map", "coordinate_space": "reciprocal"]
            // C7: the detector's identity travels with the map; the Model row shows the same hash.
            for key in ["detector_class", "learned_threshold", "learned_model_sha256"] {
                provenance[key] = braggVectors?.detectionProvenance[key]
            }
            let q = calibrationSession.calibration
            return (q.qPixelSize, q.qPixelSize, q.qPixelUnits, provenance)
        }
        guard navigation.analysisMode == .ptychography else {
            return (
                calibrationSession.calibration.rPixelSize, calibrationSession.calibration.rPixelSize,
                calibrationSession.calibration.rPixelUnits, ["analysis_mode": navigation.analysisMode.rawValue]
            )
        }
        switch phaseContrast.parallaxResultProduct {
        case .preprocess:
            let sampling = phaseContrast.parallaxPreprocess?.calibration.scanSamplingAngstrom
            return (sampling, sampling, "A", ["source_product": "parallax_preprocess"])
        case .alignment:
            let sampling = phaseContrast.parallaxPreprocess?.calibration.scanSamplingAngstrom
            return (sampling, sampling, "A", [
                "source_product": "parallax_alignment",
                "levels": phaseContrast.parallaxAlignment?.completedBins.map(String.init)
                    .joined(separator: ",") ?? "",
            ])
        case .subpixel:
            guard let result = phaseContrast.parallaxSubpixel else { return (nil, nil, nil, [:]) }
            return (result.outputSamplingAngstrom, result.outputSamplingAngstrom, "A", [
                "source_product": "parallax_subpixel_bf",
                "upsample_factor": String(result.upsampleFactor),
                "kde_sigma_px": String(result.kdeSigmaPixels),
                "interpolation": result.lanczosOrder.map { "lanczos_\($0)" } ?? "bilinear",
                "position_iterations": String(max(0, result.positionCorrectionScores.count - 1)),
                "sinc_lowpass": String(result.lowpassFilter),
            ])
        case .correctedPhase:
            guard let result = phaseContrast.parallaxCorrection else { return (nil, nil, nil, [:]) }
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
            guard let result = phaseContrast.parallaxDepth,
                  result.depthsAngstrom.indices.contains(phaseContrast.parallaxDepthSelectedIndex) else {
                return (nil, nil, nil, [:])
            }
            let informationLimit = result.informationLimitInvAngstrom
                .map { String($0) } ?? "off"
            let provenance: [String: String] = [
                "source_product": "parallax_depth",
                "depth_angstrom": String(result.depthsAngstrom[phaseContrast.parallaxDepthSelectedIndex]),
                "full_fit": String(result.usedFullFit),
                "information_limit_inv_a": informationLimit,
                "information_power": String(result.informationPower),
            ]
            return (result.samplingAngstrom, result.samplingAngstrom, "A", provenance)
        case .iterativePhase, .iterativeAmplitude,
             .iterativeProbePhase, .iterativeProbeAmplitude:
            guard let result = phaseContrast.singleslicePtychography else {
                return (nil, nil, nil, [:])
            }
            let sourceProduct: String
            switch phaseContrast.parallaxResultProduct {
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
        publishedProduct?.valueUnits ?? currentScalarResultMetadata.valueUnits
    }

    var currentResultDisplayName: String {
        publishedProduct?.displayName ?? currentScalarResultMetadata.displayName
    }

    var currentResultKind: String {
        publishedProduct?.kind ?? currentScalarResultMetadata.kind
    }

    var currentResultPersistenceMetadata:
        (row: Double?, column: Double?, units: String?, provenance: [String: String]) {
        // v2.5 step 3b-7: the published product is the source; the legacy
        // chain below serves nothing once every site publishes (it does) and
        // goes with deletion condition 1.
        if let product = publishedProduct {
            var provenance = product.provenance
            provenance["display_domain"] = product.domain.rawValue
            if provenance["quantitative_status"] == nil {
                provenance["quantitative_status"] = product.quantitativeStatus.rawValue
            }
            if publishedProduct?.origin != .restoredFromSidecar,
               product.kind == "dpc_angle", product.valueUnits == "rad",
               provenance[ScalarResultMap.dpcAngleEncodingKey] == nil {
                provenance[ScalarResultMap.dpcAngleEncodingKey] =
                    ScalarResultMap.dpcAngleRadiansEncoding
            }
            return (product.sampling.row, product.sampling.column, product.sampling.units, provenance)
        }
        let base = currentScalarPersistenceMetadata
        var provenance = base.provenance
        provenance["display_domain"] = activeResultDomain.rawValue
        if provenance["quantitative_status"] == nil {
            provenance["quantitative_status"] = quantitativeStatus(
                for: currentResultKind, units: currentResultValueUnits
            ).rawValue
        }
        if publishedProduct?.origin != .restoredFromSidecar,
           navigation.analysisMode == .dpc, dpc.dpcDisplay == .angle,
           currentResultKind == "dpc_angle", currentResultValueUnits == "rad",
           provenance[ScalarResultMap.dpcAngleEncodingKey] == nil {
            provenance[ScalarResultMap.dpcAngleEncodingKey] =
                ScalarResultMap.dpcAngleRadiansEncoding
        }
        return (base.row, base.column, base.units, provenance)
    }

    private var exportBaseName: String {
        let file = descriptor.map { ($0.fileName as NSString).deletingPathExtension } ?? "mac4DSTEM"
        return file
    }

}
