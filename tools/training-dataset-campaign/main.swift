import Foundation

// VirtualDetector's aperture overload is part of the production source set.
// The campaign uses DetectorShape directly but supplies the app-layer value
// type so the production source compiles as a standalone optimized harness.
struct Aperture {
    var centerX: Float
    var centerY: Float
    var inner: Float
    var outer: Float
}

struct CampaignStage: Codable {
    let status: String
    let seconds: Double
    let detail: String
    let metrics: [String: Double]

    init(
        _ status: String,
        seconds: Double = 0,
        detail: String,
        metrics: [String: Double] = [:]
    ) {
        self.status = status
        self.seconds = seconds
        self.detail = detail
        self.metrics = metrics
    }
}

struct ImportedCalibrationReport: Codable {
    let qSize: Double?
    let qUnits: String?
    let rSize: Double?
    let rUnits: String?
    let qrFlip: Bool?
    let hasOriginMaps: Bool
}

struct DatasetCampaignReport: Codable {
    let file: String
    let fileBytes: Int64
    let datasetPath: String
    let alternateDatasetPaths: [String]
    let shape: [Int]
    let dtype: String
    let chunkShape: [Int]?
    let voltageKV: Double
    let voltageSource: String
    let importedCalibration: ImportedCalibrationReport
    let stages: [String: CampaignStage]
    let issues: [String]
    let totalSeconds: Double
}

private func elapsed<T>(
    _ body: () async throws -> T
) async rethrows -> (T, Double) {
    let start = Date()
    return (try await body(), Date().timeIntervalSince(start))
}

private func checksum(_ values: [Float]) -> Double {
    values.enumerated().reduce(0) {
        $0 + Double($1.element) * Double(($1.offset % 257) + 1)
    }
}

private func finiteFraction(_ values: [Float]) -> Double {
    guard !values.isEmpty else { return 0 }
    return Double(values.lazy.filter(\.isFinite).count) / Double(values.count)
}

private func originRMS(
    measuredX: [Float], measuredY: [Float],
    fittedX: [Float], fittedY: [Float]
) -> Float {
    guard !measuredX.isEmpty, measuredX.count == measuredY.count,
          measuredX.count == fittedX.count, measuredX.count == fittedY.count else {
        return .nan
    }
    var sum: Float = 0
    for index in measuredX.indices {
        let dx = measuredX[index] - fittedX[index]
        let dy = measuredY[index] - fittedY[index]
        sum += dx * dx + dy * dy
    }
    return (sum / Float(measuredX.count)).squareRoot()
}

private func physicalReciprocalUnits(_ units: String?) -> Bool {
    CalibrationUnitConversion.isPhysicalReciprocalUnit(units)
}

private func physicalRealUnits(_ units: String?) -> Bool {
    CalibrationUnitConversion.realAngstromPerPixel(value: 1, units: units) != nil
}

private func stageSummary(_ image: FloatImage) -> [String: Double] {
    let range = image.minMax
    return [
        "finite_fraction": finiteFraction(image.pixels),
        "minimum": Double(range.0),
        "maximum": Double(range.1),
        "checksum": checksum(image.pixels),
    ]
}

private func fileSize(_ path: String) -> Int64 {
    let attributes = try? FileManager.default.attributesOfItem(atPath: path)
    return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
}

private func safeStem(_ value: String) -> String {
    value.unicodeScalars.map {
        CharacterSet.alphanumerics.contains($0) ? String($0) : "_"
    }.joined()
}

private func pixelCalibration(
    from calibration: Calibration,
    meanOrigin: (x: Float, y: Float)?
) -> PixelCalibration {
    var output = PixelCalibration(
        rSize: calibration.rPixelSize,
        rUnits: calibration.rPixelUnits,
        qSize: calibration.qPixelSize,
        qUnits: calibration.qPixelUnits,
        qrFlip: calibration.transposeQR
    )
    if let meanOrigin {
        // App x/y -> py4DSTEM qy/qx at the format boundary.
        output.qx0Mean = Double(meanOrigin.y)
        output.qy0Mean = Double(meanOrigin.x)
    }
    output.ellipseA = calibration.ellipseA
    output.ellipseB = calibration.ellipseB
    output.ellipseTheta = calibration.ellipseTheta
    output.qrRotationRad = calibration.rotationRad.map(Double.init)
    output.probeSemiangle = calibration.probeRadius.map(Double.init)
    return output
}

private func evaluate(path: String, outputDirectory: URL) async throws
    -> DatasetCampaignReport {
    let campaignStart = Date()
    let fileName = URL(fileURLWithPath: path).lastPathComponent
    var stages: [String: CampaignStage] = [:]
    var issues: [String] = []

    let (reader, openSeconds) = try await elapsed { try H5Reader(path: path) }
    let (descriptor, discoverySeconds) = try await elapsed {
        try await reader.discoverPrimaryDataset()
    }
    stages["open_discovery"] = CampaignStage(
        "pass", seconds: openSeconds + discoverySeconds,
        detail: "Discovered \(descriptor.datasetPath)"
    )

    var alternatePaths: [String] = []
    if fileName == "sim_Au_data_all_binned.h5" {
        let alternate = "/4DSTEM_simulation/4DSTEM_polyAu/data"
        if let alternateDescriptor = try? await reader.describe(path: alternate),
           alternateDescriptor.shape == descriptor.shape {
            alternatePaths.append(alternate)
        }
    }

    let fileVoltage = await reader.readDoubleAttribute(
        "accelerating_voltage", onObjectPath: "/"
    )
    let noteVoltage: Double = fileName.hasPrefix("Particle_1_") ? 300 : 200
    let voltageKV: Double
    let voltageSource: String
    if let fileVoltage, fileVoltage.isFinite, fileVoltage > 0 {
        voltageKV = fileVoltage > 1_000 ? fileVoltage / 1_000 : fileVoltage
        voltageSource = "HDF5 root attribute"
    } else {
        voltageKV = noteVoltage
        voltageSource = "References/training_dataset/metadata.md"
    }
    let imported = await reader.pixelCalibration()
    let importedReport = ImportedCalibrationReport(
        qSize: imported?.qSize, qUnits: imported?.qUnits,
        rSize: imported?.rSize, rUnits: imported?.rUnits,
        qrFlip: imported?.qrFlip, hasOriginMaps: imported?.originMaps != nil
    )

    var calibration = Calibration()
    var provenance = CalibrationProvenance()
    if let imported {
        calibration.qPixelSize = imported.qSize
        calibration.qPixelUnits = imported.qUnits
        calibration.rPixelSize = imported.rSize
        calibration.rPixelUnits = imported.rUnits
        calibration.transposeQR = imported.qrFlip
        calibration.rotationRad = imported.qrRotationRad.map(Float.init)
        calibration.probeRadius = imported.probeSemiangle.map(Float.init)
        calibration.ellipseA = imported.ellipseA
        calibration.ellipseB = imported.ellipseB
        calibration.ellipseTheta = imported.ellipseTheta
        if imported.qSize.map({ $0.isFinite && $0 > 0 }) == true {
            provenance.qScale = .importedFile
        }
        if imported.rSize.map({ $0.isFinite && $0 > 0 }) == true {
            provenance.rScale = .importedFile
        }
    }
    let readiness = CalibrationReadinessReport.make(
        calibration: calibration, provenance: provenance
    )
    let qReportedReady = readiness.items.first { $0.kind == .qScale }?.status.isReady == true
    let rReportedReady = readiness.items.first { $0.kind == .rScale }?.status.isReady == true
    let qPhysical = physicalReciprocalUnits(imported?.qUnits)
    let rPhysical = physicalRealUnits(imported?.rUnits)
    if qReportedReady && !qPhysical {
        issues.append("Q calibration readiness accepts non-physical pixel units")
    }
    if rReportedReady && !rPhysical {
        issues.append("R calibration readiness accepts non-physical pixel units")
    }
    let importedQText = imported?.qSize.map { String($0) } ?? "missing"
    let importedRText = imported?.rSize.map { String($0) } ?? "missing"
    let readinessDetail = "Q \(importedQText) \(imported?.qUnits ?? "")"
        + " · R \(importedRText) \(imported?.rUnits ?? "")"
        + " · voltage \(voltageKV) kV"
    let readinessMismatch = qReportedReady != qPhysical || rReportedReady != rPhysical
    stages["metadata_calibration_readiness"] = CampaignStage(
        readinessMismatch ? "fail"
            : (qPhysical && rPhysical ? "pass" : "expected_prerequisite_block"),
        detail: readinessDetail
    )

    var seen = Set<String>()
    let candidates = [
        (0, 0),
        (0, descriptor.rx - 1),
        (descriptor.ry / 2, descriptor.rx / 2),
        (descriptor.ry - 1, 0),
        (descriptor.ry - 1, descriptor.rx - 1),
    ]
    let positions = candidates.filter { seen.insert("\($0.0),\($0.1)").inserted }
    let (patterns, cbedSeconds) = try await elapsed {
        var values: [Float] = []
        for (y, x) in positions {
            values.append(contentsOf: try await reader.readPattern(
                descriptor, ry: y, rx: x
            ))
        }
        return values
    }
    stages["cbed_navigation"] = CampaignStage(
        finiteFraction(patterns) == 1 ? "pass" : "fail",
        seconds: cbedSeconds,
        detail: "Read \(positions.count) corner/center patterns",
        metrics: [
            "finite_fraction": finiteFraction(patterns),
            "checksum": checksum(patterns),
        ]
    )

    let data = FourDArray(reader: reader, descriptor: descriptor)
    let centerX = Float(descriptor.qx) / 2
    let centerY = Float(descriptor.qy) / 2
    let maximumRadius = Float(min(descriptor.qx, descriptor.qy)) / 2

    let cancellation = AnalysisCancellationToken()
    let cancellationStart = Date()
    var cancellationWorked = false
    do {
        _ = try await VirtualDetector.tiledImage(
            data: data, descriptor: descriptor,
            shape: .circle(centerX: centerX, centerY: centerY,
                           radius: maximumRadius * 0.2),
            maximumTileRows: 1, cancellation: cancellation,
            progress: { fraction in
                if fraction > 0 { cancellation.cancel() }
            }
        )
    } catch is CancellationError {
        cancellationWorked = true
    }
    stages["cancellation"] = CampaignStage(
        cancellationWorked ? "pass" : "fail",
        seconds: Date().timeIntervalSince(cancellationStart),
        detail: cancellationWorked
            ? "Cancelled after the first published tile without a partial result"
            : "Cancellation did not stop publication"
    )

    let (brightField, brightFieldSeconds) = try await elapsed {
        try await VirtualDetector.tiledImage(
            data: data, descriptor: descriptor,
            shape: .circle(centerX: centerX, centerY: centerY,
                           radius: maximumRadius * 0.2)
        )
    }
    stages["virtual_bright_field_restart"] = CampaignStage(
        finiteFraction(brightField.pixels) == 1 ? "pass" : "fail",
        seconds: brightFieldSeconds,
        detail: "Restarted successfully after cancellation",
        metrics: stageSummary(brightField)
    )

    let (annular, annularSeconds) = try await elapsed {
        try await VirtualDetector.tiledImage(
            data: data, descriptor: descriptor,
            shape: .annulus(centerX: centerX, centerY: centerY,
                            inner: maximumRadius * 0.25,
                            outer: maximumRadius * 0.55)
        )
    }
    stages["virtual_annular"] = CampaignStage(
        finiteFraction(annular.pixels) == 1 ? "pass" : "fail",
        seconds: annularSeconds, detail: "ADF-style annular detector",
        metrics: stageSummary(annular)
    )

    let sampling = ProductSampling(
        row: rPhysical ? imported?.rSize : nil,
        column: rPhysical ? imported?.rSize : nil,
        units: rPhysical ? imported?.rUnits : nil
    )
    let brightProduct = DisplayedProduct(
        kind: "campaign_bf", displayName: "Campaign BF",
        payload: .scalar(brightField), domain: .scan, sampling: sampling,
        valueUnits: "intensity", quantitativeStatus: .relative
    )
    let annularProduct = DisplayedProduct(
        kind: "campaign_adf", displayName: "Campaign ADF",
        payload: .scalar(annular), domain: .scan, sampling: sampling,
        valueUnits: "intensity", quantitativeStatus: .relative
    )
    let difference = ProductComparison.difference(brightProduct, annularProduct)
    stages["comparison"] = CampaignStage(
        difference != nil ? "pass" : "fail",
        detail: "Compatible scan-domain products produced an inspectable difference",
        metrics: difference.flatMap {
            if case .scalar(let image) = $0.payload { return stageSummary(image) }
            return nil
        } ?? [:]
    )

    let (originFit, originSeconds) = try await elapsed {
        try await OriginCalibration.tiledRun(
            data: data, descriptor: descriptor, fitFunction: .plane
        )
    }
    guard let originFit, let meanOrigin = originFit.origin.fittedX.isEmpty ? nil : (
        x: originFit.origin.fittedX.reduce(0, +) / Float(originFit.origin.fittedX.count),
        y: originFit.origin.fittedY.reduce(0, +) / Float(originFit.origin.fittedY.count)
    ) else {
        throw NSError(
            domain: "training-dataset-campaign", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Origin calibration returned no result"]
        )
    }
    calibration.probeRadius = originFit.probeRadius
    calibration.origin = originFit.origin
    calibration.originProvenance = .fitted
    provenance.probe = .measuredInApp
    let planeOriginRMS = originFit.origin.rmsResidual
    let originQualityWarning = planeOriginRMS.map {
        $0.isFinite && $0 > originFit.probeRadius
    } ?? false
    if originQualityWarning {
        issues.append("Origin fit RMS exceeds the fitted probe radius; downstream calibration is qualitative")
    }
    let originAdvertisedReady = CalibrationReadinessReport.make(
        calibration: calibration, provenance: provenance
    ).items.first { $0.kind == .originProbe }?.status.isReady == true
    if originQualityWarning && originAdvertisedReady {
        issues.append("Origin/probe readiness failed to enforce the high-residual quality gate")
    }
    var originMetrics: [String: Double] = [
        "probe_radius_px": Double(originFit.probeRadius),
        "origin_x_px": Double(meanOrigin.x),
        "origin_y_px": Double(meanOrigin.y),
        "origin_rms_px": Double(planeOriginRMS ?? .nan),
        "quantitative_readiness": originAdvertisedReady ? 1 : 0,
    ]
    if let measuredX = originFit.origin.measuredX,
       let measuredY = originFit.origin.measuredY {
        for function in [OriginFitFunction.constant, .parabola] {
            let alternative = OriginCalibration.fitOrigin(
                measuredX: measuredX, measuredY: measuredY,
                width: descriptor.rx, height: descriptor.ry,
                fitFunction: function
            )
            originMetrics["\(function.rawValue.lowercased())_rms_px"] = Double(originRMS(
                measuredX: measuredX, measuredY: measuredY,
                fittedX: alternative.fittedX, fittedY: alternative.fittedY
            ))
        }
    }
    stages["origin_calibration"] = CampaignStage(
        originFit.probeRadius.isFinite && originFit.probeRadius > 0
            ? (originQualityWarning
                ? (originAdvertisedReady ? "fail" : "expected_quality_block")
                : "pass")
            : "fail",
        seconds: originSeconds,
        detail: String(
            format: "probe %.3f px · origin (%.3f, %.3f) · RMS %.4f px",
            originFit.probeRadius, meanOrigin.x, meanOrigin.y,
            planeOriginRMS ?? .nan
        ),
        metrics: originMetrics
    )

    let (com, comSeconds) = try await elapsed {
        try await VirtualDetector.tiledCenterOfMass(
            data: data, descriptor: descriptor, center: meanOrigin,
            origins: originFit.origin.interleavedFitted
        )
    }
    let rotationStart = Date()
    let rotation = RotationCalibration.solve(
        com: com, width: descriptor.rx, height: descriptor.ry
    )
    let rotationSeconds = Date().timeIntervalSince(rotationStart)
    if let rotation {
        calibration.rotationRad = rotation.rotationRad
        calibration.transposeQR = rotation.transpose
        provenance.rotation = .measuredInApp
        stages["rotation_calibration"] = CampaignStage(
            "pass", seconds: rotationSeconds,
            detail: String(
                format: "%.2f° · transpose %@ · objective %.6g",
                rotation.rotationRad * 180 / .pi,
                rotation.transpose ? "yes" : "no", rotation.objective
            ),
            metrics: [
                "rotation_degrees": Double(rotation.rotationRad * 180 / .pi),
                "objective": Double(rotation.objective),
            ]
        )
    } else {
        stages["rotation_calibration"] = CampaignStage(
            "fail", seconds: rotationSeconds,
            detail: "Rotation solver returned no result"
        )
    }

    let dpcStart = Date()
    let rotatedCOM = DPC.applyRotation(
        com: com, rotationRad: rotation?.rotationRad ?? 0,
        transpose: rotation?.transpose ?? false
    )
    let magnitude = DPC.magnitudeImage(
        com: rotatedCOM, width: descriptor.rx, height: descriptor.ry
    )
    let angle = DPC.angleImage(
        com: rotatedCOM, width: descriptor.rx, height: descriptor.ry
    )
    let color = DPC.colorWheelRGBA(
        com: rotatedCOM, width: descriptor.rx, height: descriptor.ry
    )
    let idpc = DPC.integrateIDPC(
        com: rotatedCOM, width: descriptor.rx, height: descriptor.ry,
        boundary: .zeroPadded, paddingFactor: 2
    )
    let dpcSeconds = Date().timeIntervalSince(dpcStart) + comSeconds
    let dpcValid = [magnitude, angle, idpc].allSatisfy {
        finiteFraction($0.pixels) == 1 && $0.pixels.count == descriptor.ry * descriptor.rx
    } && color.rgba.count == descriptor.ry * descriptor.rx * 4
    stages["dpc_idpc"] = CampaignStage(
        dpcValid ? "pass_qualitative" : "fail", seconds: dpcSeconds,
        detail: qPhysical && rPhysical
            ? "Finite DPC/iDPC products; quantitative phase still requires fitted origin and rotation (present)"
            : "Finite DPC/iDPC products in explicit qualitative units; physical Q/R sampling is unavailable",
        metrics: [
            "magnitude_checksum": checksum(magnitude.pixels),
            "idpc_checksum": checksum(idpc.pixels),
        ]
    )

    let physicalIDPC = DPC.physicalIDPCCalibration(
        realPixelSize: calibration.rPixelSize,
        realPixelUnits: calibration.rPixelUnits,
        reciprocalPixelSize: calibration.qPixelSize,
        reciprocalPixelUnits: calibration.qPixelUnits,
        voltageKV: voltageKV
    )
    stages["quantitative_idpc"] = CampaignStage(
        physicalIDPC == nil ? "expected_prerequisite_block" : "pass",
        detail: physicalIDPC == nil
            ? "Not quantitatively testable: physical Q and/or R sampling is missing"
            : "Physical iDPC calibration resolved"
    )

    let ellipseStart = Date()
    do {
        let fit = try EllipseCalibration.fitBestAvailable(
            pattern: DiffractionPattern(
                qy: descriptor.qy, qx: descriptor.qx,
                pixels: originFit.meanDP
            ),
            centerQX: Double(meanOrigin.y), centerQY: Double(meanOrigin.x),
            innerRadius: Double(maximumRadius) * 0.35,
            outerRadius: Double(maximumRadius) * 0.90
        )
        calibration.ellipseA = fit.a
        calibration.ellipseB = fit.b
        calibration.ellipseTheta = fit.theta
        provenance.ellipse = .measuredInApp
        stages["ellipse_calibration"] = CampaignStage(
            "pass", seconds: Date().timeIntervalSince(ellipseStart),
            detail: String(
                format: "%@ · a %.3f · b %.3f · residual %.4f",
                fit.model.rawValue, fit.a, fit.b, fit.normalizedResidual
            ),
            metrics: ["residual": fit.normalizedResidual]
        )
    } catch {
        stages["ellipse_calibration"] = CampaignStage(
            "expected_prerequisite_block",
            seconds: Date().timeIntervalSince(ellipseStart),
            detail: error.localizedDescription
        )
    }

    guard let kernel = ProbeKernel.synthetic(
        radius: originFit.probeRadius, qy: descriptor.qy, qx: descriptor.qx
    ) else {
        throw NSError(
            domain: "training-dataset-campaign", code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Probe kernel did not initialize"]
        )
    }
    var diskParameters = DiskDetectionParams()
    let qMinimum = Float(min(descriptor.qx, descriptor.qy))
    diskParameters.minPeakSpacing = max(4, (qMinimum / 8).rounded())
    diskParameters.edgeBoundary = max(2, Int(qMinimum / 24))

    let cancelledDiskToken = AnalysisCancellationToken()
    cancelledDiskToken.cancel()
    let cancelledDisk = await DiskDetection.detectAll(
        data: data, descriptor: descriptor, kernel: kernel,
        params: diskParameters, cancellation: cancelledDiskToken
    )
    stages["bragg_cancellation"] = CampaignStage(
        cancelledDisk == nil ? "pass" : "fail",
        detail: "Pre-cancelled detection did not publish Bragg vectors"
    )

    let (rawVectors, braggSeconds) = await elapsed {
        await DiskDetection.detectAll(
            data: data, descriptor: descriptor, kernel: kernel,
            params: diskParameters
        )
    }
    guard let rawVectors else {
        throw NSError(
            domain: "training-dataset-campaign", code: 4,
            userInfo: [NSLocalizedDescriptionKey: "Bragg detection returned no result"]
        )
    }
    if braggSeconds > 15 {
        issues.append("Bragg detection exceeded the 15 s/file responsiveness target")
    }
    let vectors = rawVectors.calibrated(
        with: calibration, referenceOrigin: meanOrigin
    )
    stages["bragg_detection"] = CampaignStage(
        vectors.totalPeakCount > 0 ? "pass" : "fail",
        seconds: braggSeconds,
        detail: "Detected \(vectors.totalPeakCount) peaks",
        metrics: [
            "peak_count": Double(vectors.totalPeakCount),
            "positions_per_second": Double(descriptor.ry * descriptor.rx) / max(braggSeconds, 1e-9),
        ]
    )

    let strainStart = Date()
    let strain = StrainMapping.compute(
        bragg: vectors, originX: meanOrigin.x, originY: meanOrigin.y
    )
    let strainSeconds = Date().timeIntervalSince(strainStart)
    if let strain {
        stages["strain"] = CampaignStage(
            "pass_operational_not_quantitatively_validated", seconds: strainSeconds,
            detail: String(
                format: "indexed %.1f%% · reference positions %d; no expected strain map supplied",
                strain.indexedFraction * 100, strain.referencePositionCount
            ),
            metrics: [
                "indexed_fraction": Double(strain.indexedFraction),
                "reference_positions": Double(strain.referencePositionCount),
                "basis_condition": Double(strain.diagnostics.basisConditionNumber),
            ]
        )
    } else {
        stages["strain"] = CampaignStage(
            "expected_prerequisite_block", seconds: strainSeconds,
            detail: "No sufficiently supported, well-conditioned lattice basis was found"
        )
    }

    let material: (name: String, crystal: Crystal)?
    if fileName == "sim_Au_data_all_binned.h5" {
        material = ("Au (filename)", .gold)
    } else if fileName == "downsample_Si_SiGe_exp.h5" {
        material = ("Si diamond operational proxy (filename also contains SiGe)", .silicon)
    } else {
        material = nil
    }
    if let material,
       let firstShell = material.crystal.reflections(kMax: 2.5).first?.gLength,
       let qEstimate = KnownCrystalQCalibration.estimate(
            bragg: vectors, origin: meanOrigin,
            referenceRadiusInvAngstrom: firstShell
       ) {
        calibration.qPixelSize = qEstimate.invAngstromPerPixel
        calibration.qPixelUnits = "Å⁻¹"
        provenance.qScale = .measuredInApp
        let acomStart = Date()
        let plan = OrientationPlan.generate(
            crystal: material.crystal, kMax: 1.2, zoneAxisCount: 96
        )
        let selection = ACOMScanSelection.preview(maxDimension: 24)
        let orientation = plan.flatMap {
            OrientationMatching.matchAll(
                bragg: vectors, plan: $0,
                originX: meanOrigin.x, originY: meanOrigin.y,
                invAngstromPerPixel: qEstimate.invAngstromPerPixel,
                backend: .cpu, selection: selection
            )
        }
        let acomSeconds = Date().timeIntervalSince(acomStart)
        if let plan, let orientation {
            let selectedIndices = selection.sourceIndices(
                width: descriptor.rx, height: descriptor.ry
            )
            let valid = selectedIndices.compactMap { index in
                let result = orientation.results[index]
                return result.templateIndex >= 0 ? result : nil
            }
            stages["acom"] = CampaignStage(
                "pass_operational_not_quantitatively_validated", seconds: acomSeconds,
                detail: "\(material.name) · \(valid.count)/\(selectedIndices.count) sampled positions matched · no expected orientation map/simulation parameters supplied",
                metrics: [
                    "q_inv_angstrom_per_px": qEstimate.invAngstromPerPixel,
                    "templates": Double(plan.count),
                    "valid_results": Double(valid.count),
                    "mean_reliability": valid.isEmpty ? 0
                        : Double(valid.reduce(Float(0)) { $0 + $1.reliability }) / Double(valid.count),
                ]
            )
        } else {
            stages["acom"] = CampaignStage(
                "fail", seconds: acomSeconds,
                detail: "Template generation or orientation matching failed"
            )
        }
    } else {
        let detail: String
        if fileName == "polycrystal_2D_WS2.h5" {
            detail = "Not quantitatively testable: the app has no WS₂ crystal preset/custom non-cubic structure model"
        } else if material == nil {
            detail = "Not quantitatively testable: material/crystal and expected orientation map are missing"
        } else {
            detail = "Not quantitatively testable: known-crystal Q calibration could not be established"
        }
        stages["acom"] = CampaignStage(
            "expected_prerequisite_block", detail: detail
        )
    }

    let reconstructionStart = Date()
    do {
        _ = try ParallaxPhysicalCalibration.resolve(
            calibration: calibration,
            apertureCenterX: meanOrigin.x, apertureCenterY: meanOrigin.y,
            acceleratingVoltageKV: voltageKV
        )
        stages["reconstruction"] = CampaignStage(
            "prerequisites_resolved_not_run",
            seconds: Date().timeIntervalSince(reconstructionStart),
            detail: "Physical prerequisites resolved; iterative full-data reconstruction is outside the bounded campaign"
        )
    } catch {
        stages["reconstruction"] = CampaignStage(
            "expected_prerequisite_block",
            seconds: Date().timeIntervalSince(reconstructionStart),
            detail: error.localizedDescription
        )
    }

    let sourceAttributesBefore = try FileManager.default.attributesOfItem(atPath: path)
    let exportStart = Date()
    let sidecar = outputDirectory.appendingPathComponent(
        safeStem(fileName) + ".mac4dstem.h5"
    )
    let cancelledSidecar = outputDirectory.appendingPathComponent(
        safeStem(fileName) + ".cancelled.h5"
    )
    try? FileManager.default.removeItem(at: sidecar)
    try? FileManager.default.removeItem(at: cancelledSidecar)
    let exportCalibration = pixelCalibration(
        from: calibration, meanOrigin: meanOrigin
    )
    let cancelledWrite = AnalysisCancellationToken()
    cancelledWrite.cancel()
    var cancelledWriteWorked = false
    do {
        try BraggVectorEMDWriter.mergeResultMap(
            ScalarResultMap(
                width: brightField.width, height: brightField.height,
                pixels: brightField.pixels, kind: "campaign_virtual_bf",
                displayName: "Campaign virtual BF", valueUnits: "intensity",
                pixelSizeRow: rPhysical ? imported?.rSize : nil,
                pixelSizeColumn: rPhysical ? imported?.rSize : nil,
                pixelUnits: rPhysical ? imported?.rUnits : nil,
                provenance: ["source": fileName, "scope": "full_scan"]
            ),
            vectors: vectors, qWidth: descriptor.qx, qHeight: descriptor.qy,
            calibration: exportCalibration, to: cancelledSidecar,
            cancellation: cancelledWrite
        )
    } catch BraggVectorEMDWriter.WriterError.cancelled {
        cancelledWriteWorked = !FileManager.default.fileExists(
            atPath: cancelledSidecar.path
        )
    }
    try BraggVectorEMDWriter.mergeResultMap(
        ScalarResultMap(
            width: brightField.width, height: brightField.height,
            pixels: brightField.pixels, kind: "campaign_virtual_bf",
            displayName: "Campaign virtual BF", valueUnits: "intensity",
            pixelSizeRow: rPhysical ? imported?.rSize : nil,
            pixelSizeColumn: rPhysical ? imported?.rSize : nil,
            pixelUnits: rPhysical ? imported?.rUnits : nil,
            provenance: ["source": fileName, "scope": "full_scan"]
        ),
        vectors: vectors, qWidth: descriptor.qx, qHeight: descriptor.qy,
        calibration: exportCalibration, to: sidecar
    )
    let reopened = try BraggVectorEMDWriter.loadSession(from: sidecar)
    let loaded = reopened.currentResult
    let nativeRoundTrip = reopened.inventory.hasBraggVectors
        && reopened.inventory.hasCalibration
        && loaded?.width == brightField.width
        && loaded?.height == brightField.height
        && loaded.map { checksum($0.pixels) == checksum(brightField.pixels) } == true
    let sourceAttributesAfter = try FileManager.default.attributesOfItem(atPath: path)
    let sourceUnchanged = (sourceAttributesBefore[.size] as? NSNumber)
            == (sourceAttributesAfter[.size] as? NSNumber)
        && (sourceAttributesBefore[.modificationDate] as? Date)
            == (sourceAttributesAfter[.modificationDate] as? Date)
    stages["save_reopen_emd_export"] = CampaignStage(
        nativeRoundTrip && cancelledWriteWorked && sourceUnchanged ? "pass" : "fail",
        seconds: Date().timeIntervalSince(exportStart),
        detail: "Atomic sidecar, cancellation recovery, native reopen, and source preservation",
        metrics: [
            "sidecar_bytes": Double(fileSize(sidecar.path)),
            "source_unchanged": sourceUnchanged ? 1 : 0,
        ]
    )

    return DatasetCampaignReport(
        file: fileName, fileBytes: fileSize(path),
        datasetPath: descriptor.datasetPath,
        alternateDatasetPaths: alternatePaths,
        shape: descriptor.shape, dtype: descriptor.dtypeDescription,
        chunkShape: descriptor.chunkShape,
        voltageKV: voltageKV, voltageSource: voltageSource,
        importedCalibration: importedReport,
        stages: stages, issues: issues,
        totalSeconds: Date().timeIntervalSince(campaignStart)
    )
}

@main
struct TrainingDatasetCampaign {
    static func main() async throws {
        guard CommandLine.arguments.count >= 3 else {
            FileHandle.standardError.write(Data(
                "usage: harness output-directory data.h5 ...\n".utf8
            ))
            exit(64)
        }
        let outputDirectory = URL(
            fileURLWithPath: CommandLine.arguments[1], isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: outputDirectory, withIntermediateDirectories: true
        )
        var reports: [DatasetCampaignReport] = []
        for path in CommandLine.arguments.dropFirst(2) {
            FileHandle.standardError.write(Data(
                "[campaign] \(URL(fileURLWithPath: path).lastPathComponent)\n".utf8
            ))
            reports.append(try await evaluate(
                path: path, outputDirectory: outputDirectory
            ))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        FileHandle.standardOutput.write(try encoder.encode(reports))
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
