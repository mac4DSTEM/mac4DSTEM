import Foundation

/// Deterministic, in-memory 4D-STEM fixture used by UI automation and design
/// walkthroughs. It never appears in normal launches and performs no file I/O.
package actor DemoFourDDataSource: FourDDataSource {
    package static let descriptor = DatasetDescriptor(
        filePath: "/Demo/mac4DSTEM Demo.h5",
        datasetPath: "/demo/data",
        shape: [12, 12, 64, 64],
        dtypeDescription: "float32 · deterministic demo",
        chunkShape: [1, 12, 64, 64]
    )

    /// Full source patterns by source scan index.
    private var patternCache: [Int: [Float]] = [:]
    private let includesCalibration: Bool

    package init(includesCalibration: Bool = true) {
        self.includesCalibration = includesCalibration
    }

    package func discoverPrimaryDataset() throws -> DatasetDescriptor { Self.descriptor }

    /// There is no file, so nothing is skipped on disk — the crop is applied
    /// entirely in memory. Declared honestly rather than borrowing HDF5's
    /// `.full`, because this source stands in for a reader in UI automation and
    /// a false pushdown claim would propagate into provenance.
    package nonisolated func loadPushdown(for view: LoadView) -> LoadPushdown { .none }

    package func readPattern(
        _ view: LoadView, ry: Int, rx: Int
    ) throws -> [Float] {
        try view.requireSource(shape: Self.descriptor.shape)
        guard ry >= 0, ry < view.descriptor.ry, rx >= 0, rx < view.descriptor.rx else {
            throw DemoError.outOfBounds
        }
        // Generated at SOURCE coordinates, then sliced. Generating from the view
        // descriptor instead would recentre the probe and rescale the lattice —
        // a cropped demo cube would hold different data rather than a subset of
        // the same data, and every crop-equals-slice assertion would compare two
        // fabrications and pass.
        return view.detectorView(
            of: sourcePattern(scanY: view.sourceScanY(ry), scanX: view.sourceScanX(rx))
        )
    }

    package func readScanRow(_ view: LoadView, ry: Int) throws -> [Float] {
        try view.requireSource(shape: Self.descriptor.shape)
        guard ry >= 0, ry < view.descriptor.ry else { throw DemoError.outOfBounds }
        var row: [Float] = []
        row.reserveCapacity(view.descriptor.rx * view.descriptor.qy * view.descriptor.qx)
        for x in 0..<view.descriptor.rx {
            row.append(contentsOf: try readPattern(view, ry: ry, rx: x))
        }
        return row
    }

    package func readScanTile(
        _ view: LoadView, yRange: Range<Int>
    ) throws -> FourDScanTile {
        try view.requireSource(shape: Self.descriptor.shape)
        guard yRange.lowerBound >= 0, yRange.upperBound <= view.descriptor.ry else {
            throw DemoError.outOfBounds
        }
        var pixels: [Float] = []
        pixels.reserveCapacity(
            yRange.count * view.descriptor.rx * view.descriptor.qy * view.descriptor.qx
        )
        for y in yRange { pixels.append(contentsOf: try readScanRow(view, ry: y)) }
        return FourDScanTile(
            yRange: yRange, scanWidth: view.descriptor.rx,
            detectorHeight: view.descriptor.qy, detectorWidth: view.descriptor.qx,
            pixels: pixels
        )
    }

    /// One full source pattern, cached by scan position. The cache is keyed on
    /// SOURCE coordinates so two different views of this source share it.
    private func sourcePattern(scanY: Int, scanX: Int) -> [Float] {
        let key = scanY * Self.descriptor.rx + scanX
        if let cached = patternCache[key] { return cached }
        let generated = pattern(scanY: scanY, scanX: scanX, descriptor: Self.descriptor)
        patternCache[key] = generated
        return generated
    }

    package func readDoubleAttribute(_ name: String, onObjectPath path: String) -> Double? {
        name == "accelerating_voltage" ? 200 : nil
    }

    package func pixelCalibration() -> PixelCalibration? {
        guard includesCalibration else { return nil }
        let count = Self.descriptor.rx * Self.descriptor.ry
        let center = Double(Self.descriptor.qx) / 2
        return PixelCalibration(
            rSize: 0.5, rUnits: "nm",
            qSize: 0.02, qUnits: "Å⁻¹",
            qrFlip: false,
            qx0Mean: center, qy0Mean: center,
            qrRotationRad: 0,
            probeSemiangle: 4.5,
            originMaps: PixelOriginMaps(
                shape: [Self.descriptor.ry, Self.descriptor.rx],
                fittedQX: [Double](repeating: center, count: count),
                fittedQY: [Double](repeating: center, count: count)
            )
        )
    }

    private func pattern(
        scanY: Int, scanX: Int, descriptor: DatasetDescriptor
    ) -> [Float] {
        let centerX = Double(descriptor.qx) / 2
        let centerY = Double(descriptor.qy) / 2
        let phase = Double(scanX - scanY) * 0.025
        let latticeAngle = Double((scanX / 4) + (scanY / 4)) * 0.10
        var output = [Float](repeating: 0, count: descriptor.qy * descriptor.qx)
        for y in 0..<descriptor.qy {
            for x in 0..<descriptor.qx {
                let dx = Double(x) - centerX - phase
                let dy = Double(y) - centerY + phase * 0.6
                let radius = hypot(dx, dy)
                var value = 1.0 + 95.0 / (1.0 + exp(3.2 * (radius - 4.5)))
                // Two FCC [001] shells: {110} at 45° and {200} on-axis.
                // Their radii match Au at the fixture's 0.02 Å⁻¹/px scale.
                for spot in 0..<4 {
                    let angle = latticeAngle + .pi / 4
                        + Double(spot) * .pi / 2
                    let sx = centerX + 17 * cos(angle)
                    let sy = centerY + 17 * sin(angle)
                    let spotRadius = hypot(Double(x) - sx, Double(y) - sy)
                    value += 55 / (1 + exp(3.2 * (spotRadius - 4.5)))
                }
                for spot in 0..<4 {
                    let angle = latticeAngle + Double(spot) * .pi / 2
                    let sx = centerX + 24.5 * cos(angle)
                    let sy = centerY + 24.5 * sin(angle)
                    let spotRadius = hypot(Double(x) - sx, Double(y) - sy)
                    value += 34 / (1 + exp(3.2 * (spotRadius - 4.5)))
                }
                let texture = sin(Double(x * 7 + y * 11 + scanX * 13 + scanY * 17))
                output[y * descriptor.qx + x] = Float(max(0, value + texture * 0.12))
            }
        }
        return output
    }

    package enum DemoError: Error { case outOfBounds }
}
