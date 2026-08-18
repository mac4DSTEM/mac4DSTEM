import Foundation

actor SyntheticSource: FourDDataSource {
    let descriptor: DatasetDescriptor
    private(set) var largestTile = 0

    init(_ descriptor: DatasetDescriptor) { self.descriptor = descriptor }

    func discoverPrimaryDataset() throws -> DatasetDescriptor { descriptor }

    nonisolated func loadPushdown(for view: LoadView) -> LoadPushdown { .none }

    func readPattern(_ view: LoadView, ry: Int, rx: Int) throws -> [Float] {
        try readScanRow(view, ry: ry).withUnsafeBufferPointer { row in
            let count = view.descriptor.qy * view.descriptor.qx
            return Array(row[(rx * count)..<((rx + 1) * count)])
        }
    }

    func readScanRow(_ view: LoadView, ry: Int) throws -> [Float] {
        try makeTile(view, yRange: ry..<(ry + 1)).pixels
    }

    func readScanTile(_ view: LoadView,
                      yRange: Range<Int>) throws -> FourDScanTile {
        try makeTile(view, yRange: yRange)
    }

    /// Values are a function of the SOURCE index, so a crop of this fixture is
    /// a subset of the same numbers rather than a differently-numbered cube.
    private func makeTile(_ view: LoadView,
                          yRange: Range<Int>) throws -> FourDScanTile {
        let descriptor = view.descriptor
        guard yRange.lowerBound >= 0, yRange.upperBound <= descriptor.ry,
              !yRange.isEmpty else { throw NSError(domain: "tile", code: 1) }
        largestTile = max(largestTile, yRange.count)
        let (detectorY, detectorX) = view.specification.detectorOffset
        var pixels = [Float]()
        pixels.reserveCapacity(yRange.count * descriptor.rx * descriptor.qy * descriptor.qx)
        for y in yRange {
            for x in 0..<descriptor.rx {
                for qy in 0..<descriptor.qy {
                    for qx in 0..<descriptor.qx {
                        pixels.append(Float(
                            view.sourceScanY(y) * 10_000 + view.sourceScanX(x) * 1_000
                                + (detectorY + qy) * 10 + (detectorX + qx)
                        ))
                    }
                }
            }
        }
        return FourDScanTile(yRange: yRange, scanWidth: descriptor.rx,
                             detectorHeight: descriptor.qy,
                             detectorWidth: descriptor.qx, pixels: pixels)
    }

    func readDoubleAttribute(_ name: String, onObjectPath path: String) -> Double? { nil }
    func pixelCalibration() -> PixelCalibration? { nil }
    func maximumTileRows() -> Int { largestTile }
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw NSError(domain: "preprocessing-export-test", code: 1,
                                    userInfo: [NSLocalizedDescriptionKey: message]) }
}

@main
struct Harness {
    static func main() async throws {
        guard CommandLine.arguments.count == 3 else {
            throw NSError(domain: "arguments", code: 1)
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        let cancelled = URL(fileURLWithPath: CommandLine.arguments[2])
        let descriptor = DatasetDescriptor(
            filePath: "synthetic.dm4", datasetPath: "/synthetic",
            shape: [3, 4, 5, 7], dtypeDescription: "float32", chunkShape: nil
        )
        let source = SyntheticSource(descriptor)
        var calibration = PixelCalibration(
            rSize: 2.5, rUnits: "A", qSize: 0.25, qUnits: "A^-1", qrFlip: true
        )
        let qx = (0..<12).map { Double(8 + $0) }
        let qy = (0..<12).map { Double(20 + $0) }
        calibration.originMaps = PixelOriginMaps(
            shape: [3, 4], fittedQX: qx, fittedQY: qy,
            measuredQX: qx.map { $0 + 0.25 }, measuredQY: qy.map { $0 - 0.5 }
        )
        calibration.qx0Mean = qx.reduce(0, +) / 12
        calibration.qy0Mean = qy.reduce(0, +) / 12
        calibration.probeSemiangle = 6
        calibration.qrRotationRad = 0.3
        calibration.ellipseA = 1.1
        calibration.ellipseB = 0.9
        calibration.ellipseTheta = 0.2

        // The guided sheet derives readiness from the app-frame calibration,
        // then passes the same values across the py4DSTEM boundary below.
        var appCalibration = Calibration()
        appCalibration.originProvenance = .fileMaps
        appCalibration.probeRadius = 6
        appCalibration.ellipseA = 1.1
        appCalibration.ellipseB = 0.9
        appCalibration.ellipseTheta = 0.2
        appCalibration.rotationRad = 0.3
        appCalibration.transposeQR = true
        appCalibration.qPixelSize = 0.25
        appCalibration.qPixelUnits = "A^-1"
        appCalibration.rPixelSize = 2.5
        appCalibration.rPixelUnits = "A"
        let readiness = CalibrationReadinessReport.make(
            calibration: appCalibration,
            provenance: CalibrationProvenance(
                probe: .importedFile, ellipse: .importedFile,
                rotation: .importedFile, qScale: .importedFile,
                rScale: .importedFile
            )
        )
        try require(readiness.isReady, "complete fixture did not traverse readiness")

        let options = CalibratedDataCubeExportOptions(
            scanY: 1..<3, scanX: 1..<4, qBin: 2, tileRows: 1
        )
        let summary = try await BraggVectorEMDWriter.writeCalibratedDataCube(
            source: source, view: LoadView(fullExtentOf: descriptor),
            calibration: calibration,
            options: options, to: output
        )
        try require(summary.shape == [2, 3, 2, 3], "wrong output shape")
        try require(summary.discardedQRows == 1 && summary.discardedQColumns == 1,
                    "wrong discarded-edge report")
        let maximumTileRows = await source.maximumTileRows()
        try require(maximumTileRows == 1, "writer exceeded its tile bound")

        let reader = try H5Reader(path: output.path)
        let exported = try await reader.discoverPrimaryDataset()
        try require(exported.shape == summary.shape, "native reader shape mismatch")
        try require(exported.chunkShape == [1, 1, 2, 3], "unexpected HDF5 chunks")
        for outY in 0..<2 {
            let row = try await reader.readScanRow(LoadView(fullExtentOf: exported), ry: outY)
            var expected = [Float]()
            for sourceX in 1..<4 {
                for qy in 0..<2 {
                    for qx in 0..<3 {
                        var sum: Float = 0
                        for by in 0..<2 {
                            for bx in 0..<2 {
                                sum += Float((outY + 1) * 10_000 + sourceX * 1_000
                                             + (qy * 2 + by) * 10 + qx * 2 + bx)
                            }
                        }
                        expected.append(sum)
                    }
                }
            }
            try require(row == expected, "binned tile values differ at row \(outY)")
        }

        guard let restored = await reader.pixelCalibration() else {
            throw NSError(domain: "calibration", code: 1)
        }
        try require(restored.rSize == 2.5 && restored.qSize == 0.5,
                    "pixel-size transform mismatch")
        try require(restored.probeSemiangle == 3, "probe-radius transform mismatch")
        try require(restored.ellipseA == 1.1 && restored.ellipseB == 0.9,
                    "dimensionless ellipse changed")
        let selected = [5, 6, 7, 9, 10, 11]
        let expectedQX = selected.map { (qx[$0] + 0.5) / 2 - 0.5 }
        let expectedQY = selected.map { (qy[$0] + 0.5) / 2 - 0.5 }
        try require(restored.originMaps?.shape == [2, 3], "origin crop shape mismatch")
        try require(restored.originMaps?.fittedQX == expectedQX, "qx origin transform mismatch")
        try require(restored.originMaps?.fittedQY == expectedQY, "qy origin transform mismatch")

        try Data("preserve-me".utf8).write(to: cancelled)
        let before = try Data(contentsOf: cancelled)
        let token = AnalysisCancellationToken()
        token.cancel()
        do {
            _ = try await BraggVectorEMDWriter.writeCalibratedDataCube(
                source: source, view: LoadView(fullExtentOf: descriptor),
            calibration: calibration,
                options: options, to: cancelled, cancellation: token
            )
            throw NSError(domain: "cancellation", code: 1)
        } catch BraggVectorEMDWriter.WriterError.cancelled {}
        let after = try Data(contentsOf: cancelled)
        try require(after == before,
                    "cancelled export replaced the destination")
        print("preprocessing-export-test: native checks passed")
    }
}
