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
        guard let descriptor, let source = currentDataSourceForExport() else {
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
                        source: source, descriptor: descriptor, calibration: snapshot,
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
    /// That user action grants sandbox access to the companion; later saves and
    /// automatic reopen use the stored security-scoped bookmark.
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
        do {
            try storeSessionBookmark(url, for: descriptor)
        } catch {
            scopedSessionSidecarURL = nil
            url.stopAccessingSecurityScopedResource()
            present(SimpleError("Could not remember access to the session sidecar: \(error.localizedDescription)"))
            return nil
        }
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
        let cg: CGImage?
        if let rgba = resultRGBA {
            cg = Self.cgImage(rgba: rgba.rgba, width: rgba.width, height: rgba.height)
        } else if let image = resultImage {
            let norm = image.normalized(symmetric: colormap.isDiverging)
            let bytes = Self.applyColormap(norm, colormap: colormap,
                                           lo: displayRangeLo, hi: displayRangeHi,
                                           gamma: resultGamma)
            cg = Self.cgImage(rgba: bytes, width: image.width, height: image.height)
        } else {
            present(SimpleError("No result image to export yet."))
            return
        }
        guard let cg else {
            present(SimpleError("Could not render the result image for export."))
            return
        }
        let rSize = calibration.rPixelSize
        let final = Self.burnScaleBar(on: cg,
                                      unitsPerDataPixel: rSize,
                                      unitLabel: rSize != nil ? (calibration.rPixelUnits ?? "nm") : "px")
        Self.savePNG(final, suggestedName: exportBaseName + "_result.png", state: self)
    }

    /// Export the currently displayed diffraction pattern as a PNG, with the
    /// q-space scale bar burned in.
    func exportDiffractionImage() {
        guard let pattern = displayedPattern else {
            present(SimpleError("No diffraction pattern to export yet."))
            return
        }
        let norm = pattern.normalized(useLog: logScale)
        let bytes = Self.applyColormap(norm, colormap: colormap,
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

    /// Save the current scan-shaped scalar or scientific RGBA result to the stable companion
    /// `<source>.mac4dstem.h5`. Existing BraggVectors are preserved when the
    /// current session has none, and a current detection replaces the saved
    /// vectors together with the map in one atomic publication.
    func saveCurrentResultToSessionSidecar() {
        guard let descriptor else { return }
        let scalarMap: ScalarResultMap?
        let rgbaMap: RGBAResultMap?
        let metadata = restoredResultInfo ?? currentScalarResultMetadata
        if let image = resultImage,
           image.width == descriptor.rx, image.height == descriptor.ry {
            scalarMap = ScalarResultMap(
                width: image.width, height: image.height, pixels: image.pixels,
                kind: metadata.kind, displayName: metadata.displayName,
                valueUnits: metadata.valueUnits
            )
            rgbaMap = nil
        } else if let image = resultRGBA,
                  image.width == descriptor.rx, image.height == descriptor.ry {
            scalarMap = nil
            rgbaMap = RGBAResultMap(
                width: image.width, height: image.height, rgba: image.rgba,
                kind: metadata.kind, displayName: metadata.displayName,
                valueUnits: metadata.valueUnits
            )
        } else {
            present(SimpleError("No scan-shaped scalar or RGBA result is available to save."))
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
                self.statusText = "Saved \(metadata.displayName) → \(url.lastPathComponent)"
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
        guard let descriptor,
              saved.width == descriptor.rx, saved.height == descriptor.ry else {
            present(SimpleError("The saved result does not match the active scan shape."))
            return
        }
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
            case .rgba8:
                let map = try await Task.detached(priority: .utility) {
                    try BraggVectorEMDWriter.loadRGBAResultMap(id: saved.id, from: url)
                }.value
                guard epoch == datasetEpoch, let map else { return }
                resultImage = nil
                resultRGBA = RGBAImage(width: map.width, height: map.height, rgba: map.rgba)
                restoredResultInfo = (map.kind, map.displayName, map.valueUnits)
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
            case .idpc:       return ("idpc", "Integrated DPC", "arbitrary")
            case .colorWheel: return ("dpc_color", "DPC color wheel", "rgba")
            }
        case .strain:
            let units = strainComponent == .theta ? "rad" : "strain"
            let kind: String
            switch strainComponent {
            case .exx:   kind = "strain_exx"
            case .eyy:   kind = "strain_eyy"
            case .exy:   kind = "strain_exy"
            case .theta: kind = "strain_theta"
            }
            return (kind, "Strain · \(strainComponent.rawValue)", units)
        case .acom:
            let angular: Set<ACOMDisplayMode> = [.inPlane, .phi1, .Phi, .phi2, .disorientation]
            let kind: String
            switch acomDisplay {
            case .ipfZ:        kind = "acom_ipf_z"
            case .reliability: kind = "acom_reliability"
            case .disorientation: kind = "acom_cubic_fz_angle"
            case .inPlane:     kind = "acom_in_plane"
            case .phi1:        kind = "acom_phi1"
            case .Phi:         kind = "acom_Phi"
            case .phi2:        kind = "acom_phi2"
            case .score:       kind = "acom_score"
            }
            return (kind, "ACOM · \(acomDisplay.rawValue)",
                    angular.contains(acomDisplay) ? "rad" : "dimensionless")
        case .disks:
            return ("bragg_vector_map", "Bragg vector map", "log_intensity")
        case .ptychography:
            return ("ptychography", "Ptychography result", "arbitrary")
        }
    }

    var currentResultValueUnits: String {
        (restoredResultInfo ?? currentScalarResultMetadata).valueUnits
    }

    private var exportBaseName: String {
        let file = descriptor.map { ($0.fileName as NSString).deletingPathExtension } ?? "mac4DSTEM"
        return file
    }

    // MARK: - Rendering helpers

    /// Normalized [0,1] scalar pixels → packed RGBA via the colormap LUT,
    /// with the same contrast window the shader applies on screen.
    private static func applyColormap(_ pixels: [Float], colormap: ColormapKind,
                                      lo: Float, hi: Float, gamma: Float) -> [UInt8] {
        let lut = Colormaps.lutRGBA(colormap, count: 256)
        var out = [UInt8](repeating: 255, count: pixels.count * 4)
        let span = max(hi - lo, 1e-6)
        for (i, raw) in pixels.enumerated() {
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
    private static func burnScaleBar(on base: CGImage,
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
