import Foundation

/// Deterministic, in-memory 4D-STEM fixture used by UI automation and design
/// walkthroughs. It never appears in normal launches and performs no file I/O.
actor DemoFourDDataSource: FourDDataSource {
    static let descriptor = DatasetDescriptor(
        filePath: "/Demo/mac4DSTEM Demo.h5",
        datasetPath: "/demo/data",
        shape: [12, 12, 64, 64],
        dtypeDescription: "float32 · deterministic demo",
        chunkShape: [1, 12, 64, 64]
    )

    private var rowCache: [Int: [Float]] = [:]
    private let includesCalibration: Bool

    init(includesCalibration: Bool = true) {
        self.includesCalibration = includesCalibration
    }

    func discoverPrimaryDataset() throws -> DatasetDescriptor { Self.descriptor }

    func readPattern(
        _ descriptor: DatasetDescriptor, ry: Int, rx: Int
    ) throws -> [Float] {
        guard ry >= 0, ry < descriptor.ry, rx >= 0, rx < descriptor.rx else {
            throw DemoError.outOfBounds
        }
        return pattern(scanY: ry, scanX: rx, descriptor: descriptor)
    }

    func readScanRow(_ descriptor: DatasetDescriptor, ry: Int) throws -> [Float] {
        guard ry >= 0, ry < descriptor.ry else { throw DemoError.outOfBounds }
        if let cached = rowCache[ry] { return cached }
        var row: [Float] = []
        row.reserveCapacity(descriptor.rx * descriptor.qy * descriptor.qx)
        for x in 0..<descriptor.rx {
            row.append(contentsOf: pattern(scanY: ry, scanX: x, descriptor: descriptor))
        }
        rowCache[ry] = row
        return row
    }

    func readScanTile(
        _ descriptor: DatasetDescriptor, yRange: Range<Int>
    ) throws -> FourDScanTile {
        guard yRange.lowerBound >= 0, yRange.upperBound <= descriptor.ry else {
            throw DemoError.outOfBounds
        }
        var pixels: [Float] = []
        pixels.reserveCapacity(
            yRange.count * descriptor.rx * descriptor.qy * descriptor.qx
        )
        for y in yRange { pixels.append(contentsOf: try readScanRow(descriptor, ry: y)) }
        return FourDScanTile(
            yRange: yRange, scanWidth: descriptor.rx,
            detectorHeight: descriptor.qy, detectorWidth: descriptor.qx,
            pixels: pixels
        )
    }

    func readDoubleAttribute(_ name: String, onObjectPath path: String) -> Double? {
        name == "accelerating_voltage" ? 200 : nil
    }

    func pixelCalibration() -> PixelCalibration? {
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

    enum DemoError: Error { case outOfBounds }
}
