//
//  PtychographyPreparation.swift
//  Bounded bridge from an app FourDDataSource to the first single-slice engine.
//

import Foundation

nonisolated struct PtychographyPreparationOptions: Equatable, Sendable {
    var probeRolloffMrad: Double = 2
    var maxResidentBytes = 1_073_741_824
}

nonisolated enum PtychographyPreparer {
    static func prepare(
        source: any FourDDataSource,
        descriptor: DatasetDescriptor,
        calibration: ParallaxPhysicalCalibration,
        probeRadiusPixels: Float,
        options: PtychographyPreparationOptions = .init(),
        cancellation: AnalysisCancellationToken? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> SingleslicePtychographyInput {
        guard descriptor.is4D, descriptor.ry > 0, descriptor.rx > 0,
              descriptor.qy > 0, descriptor.qx > 0,
              probeRadiusPixels.isFinite, probeRadiusPixels > 0,
              options.probeRolloffMrad.isFinite, options.probeRolloffMrad >= 0,
              options.maxResidentBytes > 0 else {
            throw SingleslicePtychography.ReconstructionError.invalidInput(
                "dataset, probe radius, rolloff, or memory limit is invalid"
            )
        }
        try checkCancellation(cancellation)
        let patternCount = descriptor.ry * descriptor.rx
        let detectorCount = descriptor.qy * descriptor.qx
        guard patternCount <= Int.max / detectorCount else {
            throw SingleslicePtychography.ReconstructionError.invalidInput(
                "amplitude dimensions overflow"
            )
        }
        let amplitudeCount = patternCount * detectorCount
        let amplitudeBytes = amplitudeCount * MemoryLayout<Float>.stride
        guard amplitudeBytes <= options.maxResidentBytes else {
            throw SingleslicePtychography.ReconstructionError.memoryLimit(
                bytes: amplitudeBytes, limit: options.maxResidentBytes
            )
        }
        var amplitudes = [Float](repeating: 0, count: amplitudeCount)
        var totalIntensity: Double = 0
        for scanRow in 0..<descriptor.ry {
            try checkCancellation(cancellation)
            let tile = try await source.readScanTile(
                descriptor, yRange: scanRow..<(scanRow + 1)
            )
            guard tile.pixels.count == descriptor.rx * detectorCount else {
                throw SingleslicePtychography.ReconstructionError.invalidInput(
                    "the data source returned an inconsistent scan row"
                )
            }
            for scanColumn in 0..<descriptor.rx {
                let sourceBase = scanColumn * detectorCount
                let destinationBase = (scanRow * descriptor.rx + scanColumn)
                    * detectorCount
                for row in 0..<descriptor.qy {
                    let sourceRow = Float(row) + Float(calibration.originQX)
                    let rowFloor = Int(floor(sourceRow))
                    let rowFraction = sourceRow - Float(rowFloor)
                    let row0 = wrapped(rowFloor, count: descriptor.qy)
                    let row1 = wrapped(rowFloor + 1, count: descriptor.qy)
                    for column in 0..<descriptor.qx {
                        let sourceColumn = Float(column) + Float(calibration.originQY)
                        let columnFloor = Int(floor(sourceColumn))
                        let columnFraction = sourceColumn - Float(columnFloor)
                        let column0 = wrapped(columnFloor, count: descriptor.qx)
                        let column1 = wrapped(columnFloor + 1, count: descriptor.qx)
                        let value = tile.pixels[sourceBase + row0 * descriptor.qx + column0]
                                * (1 - rowFraction) * (1 - columnFraction)
                            + tile.pixels[sourceBase + row1 * descriptor.qx + column0]
                                * rowFraction * (1 - columnFraction)
                            + tile.pixels[sourceBase + row0 * descriptor.qx + column1]
                                * (1 - rowFraction) * columnFraction
                            + tile.pixels[sourceBase + row1 * descriptor.qx + column1]
                                * rowFraction * columnFraction
                        guard value.isFinite else {
                            throw SingleslicePtychography.ReconstructionError.invalidInput(
                                "a diffraction intensity is non-finite"
                            )
                        }
                        let clipped = max(value, 0)
                        amplitudes[destinationBase + row * descriptor.qx + column]
                            = sqrt(clipped)
                        totalIntensity += Double(clipped)
                    }
                }
            }
            progress?(0.8 * Double(scanRow + 1) / Double(descriptor.ry))
        }
        let meanIntensity = totalIntensity / Double(patternCount)
        guard meanIntensity.isFinite, meanIntensity > 0 else {
            throw SingleslicePtychography.ReconstructionError.invalidInput(
                "mean diffraction intensity is zero"
            )
        }

        let qSampling = calibration.reciprocalSamplingInvAngstrom
        let objectRowSampling = 1 / (qSampling * Double(descriptor.qy))
        let objectColumnSampling = 1 / (qSampling * Double(descriptor.qx))
        let topPadding = Float(descriptor.qy) / 2
        let leftPadding = Float(descriptor.qx) / 2
        var positions = [PtychographyPosition]()
        positions.reserveCapacity(patternCount)
        for row in 0..<descriptor.ry {
            for column in 0..<descriptor.rx {
                positions.append(PtychographyPosition(
                    row: Float(Double(row) * calibration.scanSamplingAngstrom
                               / objectRowSampling) + topPadding,
                    column: Float(Double(column) * calibration.scanSamplingAngstrom
                                  / objectColumnSampling) + leftPadding
                ))
            }
        }
        let maximumRow = positions.map(\.row).max() ?? topPadding
        let maximumColumn = positions.map(\.column).max() ?? leftPadding
        let objectHeight = max(
            descriptor.qy,
            Int((Double(maximumRow + topPadding)).rounded(.toNearestOrEven))
        )
        let objectWidth = max(
            descriptor.qx,
            Int((Double(maximumColumn + leftPadding)).rounded(.toNearestOrEven))
        )
        let objectCount = objectHeight * objectWidth
        let residentBytes = amplitudeBytes
            + (objectCount * 2 + detectorCount * 4) * MemoryLayout<Float>.stride
        guard residentBytes <= options.maxResidentBytes else {
            throw SingleslicePtychography.ReconstructionError.memoryLimit(
                bytes: residentBytes, limit: options.maxResidentBytes
            )
        }

        guard let fft = FFT2D(nx: descriptor.qx, ny: descriptor.qy) else {
            throw SingleslicePtychography.ReconstructionError.fftUnavailable
        }
        let wavelength = calibration.wavelengthAngstrom
        let cutoff = Double(probeRadiusPixels) * qSampling * wavelength
        let rolloff = options.probeRolloffMrad / 1_000
        var probeReal = [Float](repeating: 0, count: detectorCount)
        var probeImaginary = [Float](repeating: 0, count: detectorCount)
        for row in 0..<descriptor.qy {
            let frequencyRow = Double(FFT2D.fftfreq(row, descriptor.qy))
                / objectRowSampling
            for column in 0..<descriptor.qx {
                let frequencyColumn = Double(FFT2D.fftfreq(column, descriptor.qx))
                    / objectColumnSampling
                let alpha = hypot(frequencyRow, frequencyColumn) * wavelength
                let aperture: Double
                if rolloff > 0, alpha > cutoff - rolloff {
                    aperture = alpha > cutoff ? 0
                        : 0.5 * (1 + cos(.pi * (alpha - cutoff + rolloff) / rolloff))
                } else {
                    aperture = alpha < cutoff ? 1 : 0
                }
                probeReal[row * descriptor.qx + column] = Float(aperture)
            }
        }
        fft.transform(re: &probeReal, im: &probeImaginary, forward: false)
        let norm = sqrt(probeReal.indices.reduce(0.0) {
            $0 + Double(probeReal[$1] * probeReal[$1]
                + probeImaginary[$1] * probeImaginary[$1])
        })
        guard norm.isFinite, norm > 0 else {
            throw SingleslicePtychography.ReconstructionError.invalidInput(
                "the calibrated probe aperture is empty"
            )
        }
        var normalization = Float(1 / norm)
        for index in 0..<detectorCount {
            probeReal[index] *= normalization
            probeImaginary[index] *= normalization
        }
        var spectrumReal = probeReal, spectrumImaginary = probeImaginary
        fft.transform(re: &spectrumReal, im: &spectrumImaginary, forward: true)
        let probeIntensity = spectrumReal.indices.reduce(0.0) {
            $0 + Double(spectrumReal[$1] * spectrumReal[$1]
                + spectrumImaginary[$1] * spectrumImaginary[$1])
        }
        normalization = Float(sqrt(meanIntensity / probeIntensity))
        for index in 0..<detectorCount {
            probeReal[index] *= normalization
            probeImaginary[index] *= normalization
        }
        try checkCancellation(cancellation)
        progress?(1)
        return SingleslicePtychographyInput(
            scanHeight: descriptor.ry, scanWidth: descriptor.rx,
            detectorHeight: descriptor.qy, detectorWidth: descriptor.qx,
            amplitudes: amplitudes, positions: positions,
            objectSamplingRowAngstrom: objectRowSampling,
            objectSamplingColumnAngstrom: objectColumnSampling,
            initialObject: PtychographyComplexArray(
                width: objectWidth, height: objectHeight,
                real: [Float](repeating: 1, count: objectCount),
                imaginary: [Float](repeating: 0, count: objectCount)
            ),
            initialProbe: PtychographyComplexArray(
                width: descriptor.qx, height: descriptor.qy,
                real: probeReal, imaginary: probeImaginary
            )
        )
    }

    private static func wrapped(_ value: Int, count: Int) -> Int {
        let remainder = value % count
        return remainder >= 0 ? remainder : remainder + count
    }

    private static func checkCancellation(
        _ cancellation: AnalysisCancellationToken?
    ) throws {
        if cancellation?.isCancelled == true {
            throw SingleslicePtychography.ReconstructionError.cancelled
        }
    }
}
