//
//  tools/reduced-export-test — v2 S10's fixture: the reduced-file export.
//
//  THE CLAIM UNDER TEST. A view (detector crop, view bin, scan crop) exports
//  through `writeCalibratedDataCube` into a standalone py4DSTEM DataCube whose
//  calibration is in the FILE'S OWN frame: the origin lands on the beam, the
//  sampling and every pixel length are rescaled by the total bin, and the
//  provenance attributes say where the pixels came from. The arbiter is
//  data-vs-metadata INSIDE the exported file — verify_py4dstem.py computes
//  each pattern's intensity centroid from the exported DATA and compares it
//  to the exported CALIBRATION's origin, so no expected value is derived by
//  the code under test.
//
//  THE CHAIN IS THE REAL ONE. Source-frame calibration →
//  `CalibrationReReference.apply` (the load-time re-reference) → the
//  py4DSTEM-axis snapshot (mirroring `sessionPixelCalibration`'s single
//  documented x/y → qy/qx swap) → the writer. Negative controls therefore
//  name lines in CalibrationReReference and BraggVectorEMDWriter — see
//  run.sh's header for the list.
//
//  DIVISION OF LABOUR with the unit suite: `ReplayPlanTests` owns the recipe
//  frame-mapping MATH (`ReplayRecordFrameMap` is App-layer and cannot compile
//  here); this harness passes records already expressed in the exported
//  frame and pins that the writer STAMPS them and py4DSTEM tolerates them.
//

import Foundation

// Same synthetic-source shape as tools/preprocessing-export-test, with a
// GAUSSIAN BEAM instead of an index ramp: the centroid arbiter needs a
// localized, symmetric feature whose centroid maps affinely under crop, bin
// and block-sum. Sigma 3 px against a crop that keeps ≥ 16 px of margin, so
// truncation error is ~1e-9 px — far below the 0.02 px assertion.
actor GaussianBeamSource: FourDDataSource {
    let descriptor: DatasetDescriptor

    init(_ descriptor: DatasetDescriptor) { self.descriptor = descriptor }

    func discoverPrimaryDataset() throws -> DatasetDescriptor { descriptor }
    nonisolated func loadPushdown(for view: LoadView) -> LoadPushdown { .none }

    // App frame: x = detector column, y = detector row. The beam drifts with
    // the SOURCE scan index so a scan crop selects differently-centred
    // patterns, not copies.
    static func beamX(sourceScanX: Int) -> Double { 24.0 + 0.5 * Double(sourceScanX) }
    static func beamY(sourceScanY: Int) -> Double { 28.0 + 0.25 * Double(sourceScanY) }

    func readPattern(_ view: LoadView, ry: Int, rx: Int) throws -> [Float] {
        try readScanRow(view, ry: ry).withUnsafeBufferPointer { row in
            let count = view.descriptor.qy * view.descriptor.qx
            return Array(row[(rx * count)..<((rx + 1) * count)])
        }
    }

    func readScanRow(_ view: LoadView, ry: Int) throws -> [Float] {
        try readScanTile(view, yRange: ry..<(ry + 1)).pixels
    }

    func readScanTile(_ view: LoadView,
                      yRange: Range<Int>) throws -> FourDScanTile {
        let descriptor = view.descriptor
        guard yRange.lowerBound >= 0, yRange.upperBound <= descriptor.ry,
              !yRange.isEmpty else { throw NSError(domain: "tile", code: 1) }
        var pixels = [Float]()
        pixels.reserveCapacity(yRange.count * descriptor.rx * descriptor.qy * descriptor.qx)
        for y in yRange {
            for x in 0..<descriptor.rx {
                let bx = Self.beamX(sourceScanX: view.sourceScanX(x))
                let by = Self.beamY(sourceScanY: view.sourceScanY(y))
                let base = view.detectorView(
                    of: Self.sourcePattern(beamX: bx, beamY: by,
                                           qy: view.source.qy, qx: view.source.qx)
                )
                pixels.append(contentsOf: base)
            }
        }
        return FourDScanTile(yRange: yRange, scanWidth: descriptor.rx,
                             detectorHeight: descriptor.qy,
                             detectorWidth: descriptor.qx, pixels: pixels)
    }

    nonisolated static func sourcePattern(beamX: Double, beamY: Double,
                                          qy: Int, qx: Int) -> [Float] {
        let sigma = 3.0
        var pattern = [Float](repeating: 0, count: qy * qx)
        for row in 0..<qy {
            for column in 0..<qx {
                let dx = (Double(column) - beamX) / sigma
                let dy = (Double(row) - beamY) / sigma
                pattern[row * qx + column] = Float(1000.0 * exp(-0.5 * (dx * dx + dy * dy)))
            }
        }
        return pattern
    }

    func readDoubleAttribute(_ name: String, onObjectPath path: String) -> Double? { nil }
    func pixelCalibration() -> PixelCalibration? { nil }
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw NSError(domain: "reduced-export-test", code: 1,
                                    userInfo: [NSLocalizedDescriptionKey: message]) }
}

@main
struct Harness {
    static let sourceDescriptor = DatasetDescriptor(
        filePath: "synthetic.h5", datasetPath: "/synthetic",
        shape: [6, 6, 64, 64], dtypeDescription: "float32", chunkShape: nil
    )

    /// The source-frame app calibration the whole chain starts from. The
    /// origin maps ARE the beam positions — the fixture's one ground truth.
    static func sourceCalibration() -> (Calibration, CalibrationReReference.DetectorPoint) {
        var calibration = Calibration()
        var fittedX = [Float]()
        var fittedY = [Float]()
        for sy in 0..<6 {
            for sx in 0..<6 {
                fittedX.append(Float(GaussianBeamSource.beamX(sourceScanX: sx)))
                fittedY.append(Float(GaussianBeamSource.beamY(sourceScanY: sy)))
            }
        }
        calibration.origin = OriginMaps(width: 6, height: 6,
                                        measuredX: nil, measuredY: nil,
                                        fittedX: fittedX, fittedY: fittedY)
        calibration.originProvenance = .fileMaps
        calibration.probeRadius = 6
        calibration.qPixelSize = 0.25
        calibration.qPixelUnits = "A^-1"
        calibration.rPixelSize = 2.0
        calibration.rPixelUnits = "A"
        calibration.rotationRad = 0.3
        calibration.transposeQR = false
        calibration.ellipseA = 1.2
        calibration.ellipseB = 1.0
        calibration.ellipseTheta = 0.2
        // Mean beam across the 6×6 scan: x = 24 + 0.5·2.5, y = 28 + 0.25·2.5.
        return (calibration, .init(x: 25.25, y: 28.625))
    }

    /// The `sessionPixelCalibration` mirror: the ONE app x/y → py4DSTEM qy/qx
    /// swap, applied at the save boundary exactly as the app applies it
    /// (py4DSTEM's qx is the FIRST/row axis = this app's detector y).
    static func pixelSnapshot(_ outcome: CalibrationReReference.Outcome,
                              viewScan: (ry: Int, rx: Int)) throws -> PixelCalibration {
        let calibration = outcome.calibration
        var snapshot = PixelCalibration(
            rSize: calibration.rPixelSize, rUnits: calibration.rPixelUnits,
            qSize: calibration.qPixelSize, qUnits: calibration.qPixelUnits,
            qrFlip: calibration.transposeQR
        )
        snapshot.qrRotationRad = calibration.rotationRad.map(Double.init)
        snapshot.probeSemiangle = calibration.probeRadius.map(Double.init)
        snapshot.ellipseA = calibration.ellipseA
        snapshot.ellipseB = calibration.ellipseB
        snapshot.ellipseTheta = calibration.ellipseTheta
        if let maps = calibration.origin {
            try require(maps.width == viewScan.rx && maps.height == viewScan.ry,
                        "fixture setup: re-referenced maps must be view-scan-shaped")
            snapshot.originMaps = PixelOriginMaps(
                shape: [viewScan.ry, viewScan.rx],
                fittedQX: maps.fittedY.map(Double.init),
                fittedQY: maps.fittedX.map(Double.init)
            )
        }
        if let center = outcome.apertureCenter {
            snapshot.qx0Mean = Double(center.y)
            snapshot.qy0Mean = Double(center.x)
        }
        return snapshot
    }

    struct Case {
        let name: String
        let specification: LoadSpecification
        let options: CalibratedDataCubeExportOptions
        let expectedShape: [Int]
        let recipe: SessionReplayRecord?
    }

    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            throw NSError(domain: "arguments", code: 1)
        }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let source = GaussianBeamSource(sourceDescriptor)
        let crop = AxisCrop(yOffset: 4, xOffset: 8, height: 48, width: 48)

        var cropOnly = LoadSpecification()
        cropOnly.detectorCrop = crop
        var cropBin = LoadSpecification()
        cropBin.detectorCrop = crop
        cropBin.detectorBin = 2
        var scanCropBin = LoadSpecification()
        scanCropBin.scanCrop = AxisCrop(yOffset: 1, xOffset: 2, height: 4, width: 3)
        scanCropBin.detectorCrop = crop
        scanCropBin.detectorBin = 2

        // A recipe already expressed in the EXPORTED file's frame (the
        // App-layer `ReplayRecordFrameMap` owns the mapping and is pinned by
        // ReplayPlanTests; the writer's contract is "stamp what you were
        // handed, verbatim"). Fixed epoch for a deterministic attribute.
        func recipe(centerX: Double, centerY: Double,
                    inner: Double, outer: Double) -> SessionReplayRecord {
            var record = SessionReplayRecord()
            record.record(kind: "virtual_detector", parameters: [
                "shape": "Annulus",
                "center_x": String(centerX), "center_y": String(centerY),
                "inner": String(inner), "outer": String(outer),
            ], at: Date(timeIntervalSince1970: 1_756_000_000))
            return record
        }

        let cases = [
            Case(name: "crop", specification: cropOnly,
                 options: .init(scanY: 0..<6, scanX: 0..<6, qBin: 1, tileRows: 2),
                 expectedShape: [6, 6, 48, 48], recipe: nil),
            Case(name: "cropbin", specification: cropBin,
                 options: .init(scanY: 0..<6, scanX: 0..<6, qBin: 1, tileRows: 2),
                 expectedShape: [6, 6, 24, 24], recipe: nil),
            Case(name: "cropbinexp", specification: cropBin,
                 options: .init(scanY: 0..<6, scanX: 0..<6, qBin: 2, tileRows: 2),
                 expectedShape: [6, 6, 12, 12],
                 recipe: recipe(centerX: 5.875, centerY: 6.0, inner: 1.0, outer: 3.0)),
            // scanY 2..<4 against xOffset 2 + scanX 0: composed offsets
            // (y 3, x 2) DIFFER, so a y↔x swap in the derivation cannot
            // cancel — the Gate B mutation that survived the symmetric
            // (2, 2) first version (S10 finding 4, the S8 lesson again).
            Case(name: "scancrop", specification: scanCropBin,
                 options: .init(scanY: 2..<4, scanX: 0..<3, qBin: 1, tileRows: 1),
                 expectedShape: [2, 3, 24, 24], recipe: nil),
            Case(name: "full", specification: LoadSpecification(),
                 options: .init(scanY: 0..<6, scanX: 0..<6, qBin: 2, tileRows: 2),
                 expectedShape: [6, 6, 32, 32],
                 recipe: recipe(centerX: 12.25, centerY: 13.75, inner: 2.0, outer: 6.0)),
        ]

        for testCase in cases {
            let view = try LoadView(source: sourceDescriptor,
                                    specification: testCase.specification)
            let (appCalibration, apertureCenter) = sourceCalibration()
            let outcome = CalibrationReReference.apply(
                view, to: appCalibration,
                provenance: CalibrationProvenance(),
                apertureCenter: apertureCenter
            )
            try require(outcome.calibration.origin != nil,
                        "\(testCase.name): the fixture beam is inside every view — the re-reference must carry the origin")
            let snapshot = try pixelSnapshot(
                outcome, viewScan: (view.descriptor.ry, view.descriptor.rx))
            let output = directory.appendingPathComponent("\(testCase.name).h5")
            let summary = try await BraggVectorEMDWriter.writeCalibratedDataCube(
                source: source, view: view, calibration: snapshot,
                options: testCase.options, to: output,
                sourceFileName: "synthetic.h5",
                replayRecord: testCase.recipe
            )
            try require(summary.shape == testCase.expectedShape,
                        "\(testCase.name): shape \(summary.shape) != \(testCase.expectedShape)")
            let reader = try H5Reader(path: output.path)
            let exported = try await reader.discoverPrimaryDataset()
            try require(exported.shape == testCase.expectedShape,
                        "\(testCase.name): native reader shape mismatch")
        }

        // R1 — origin maps in a frame that is not this view's scan: REFUSED,
        // never silently dropped or passed through. A source-scan-shaped map
        // handed beside a scan-cropped view is the mismatch the pre-S10
        // blanket refusal existed to prevent.
        do {
            let view = try LoadView(source: sourceDescriptor, specification: scanCropBin)
            let (appCalibration, apertureCenter) = sourceCalibration()
            let outcome = CalibrationReReference.apply(
                view, to: appCalibration, provenance: CalibrationProvenance(),
                apertureCenter: apertureCenter)
            var snapshot = try pixelSnapshot(
                outcome, viewScan: (view.descriptor.ry, view.descriptor.rx))
            snapshot.originMaps = PixelOriginMaps(
                shape: [6, 6],
                fittedQX: [Double](repeating: 10, count: 36),
                fittedQY: [Double](repeating: 10, count: 36))
            do {
                _ = try await BraggVectorEMDWriter.writeCalibratedDataCube(
                    source: source, view: view, calibration: snapshot,
                    options: .init(scanY: 1..<3, scanX: 0..<3, qBin: 1, tileRows: 1),
                    to: directory.appendingPathComponent("refused-shape.h5"))
                throw NSError(domain: "R1", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "R1: wrong-scan-shaped origin maps must refuse"])
            } catch BraggVectorEMDWriter.WriterError.invalidDimensions(let reason) {
                try require(reason.contains("not in this view's frame"),
                            "R1: the refusal must name the frame mismatch, got: \(reason)")
            }
        }

        // R2 — a source-frame origin beside reduced pixels: the bounds net.
        // Skipping the re-reference (what a buggy caller would do) leaves the
        // beam at ~(25, 28.6) source px against a 24×24 exported detector —
        // outside, and the writer must say why rather than write it.
        do {
            let view = try LoadView(source: sourceDescriptor, specification: cropBin)
            let (appCalibration, _) = sourceCalibration()
            var snapshot = PixelCalibration(
                rSize: 2.0, rUnits: "A", qSize: 0.25, qUnits: "A^-1", qrFlip: false)
            snapshot.originMaps = PixelOriginMaps(
                shape: [6, 6],
                fittedQX: appCalibration.origin!.fittedY.map(Double.init),
                fittedQY: appCalibration.origin!.fittedX.map(Double.init))
            snapshot.qx0Mean = 28.625
            snapshot.qy0Mean = 25.25
            do {
                _ = try await BraggVectorEMDWriter.writeCalibratedDataCube(
                    source: source, view: view, calibration: snapshot,
                    options: .init(scanY: 0..<6, scanX: 0..<6, qBin: 1, tileRows: 2),
                    to: directory.appendingPathComponent("refused-bounds.h5"))
                throw NSError(domain: "R2", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "R2: a source-frame origin beside reduced pixels must refuse"])
            } catch BraggVectorEMDWriter.WriterError.invalidDimensions(let reason) {
                try require(reason.contains("outside"),
                            "R2: the refusal must name the out-of-extent origin, got: \(reason)")
            }
        }

        print("reduced-export-test: native checks passed")
    }
}
