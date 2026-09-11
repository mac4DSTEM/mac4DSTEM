//
//  PtychographyPreparation.swift
//  Bounded bridge from an app FourDDataSource to the first single-slice engine.
//

import Foundation

package nonisolated struct PtychographyPreparationOptions: Equatable, Sendable {
    // Explicit so the default initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init() {}

    package var probeRolloffMrad: Double = 2
    package var maxResidentBytes = 1_073_741_824
}

package nonisolated enum PtychographyPreparer {
    package static func prepare(
        source: any FourDDataSource,
        view: LoadView,
        calibration: ParallaxPhysicalCalibration,
        probeRadiusPixels: Float,
        options: PtychographyPreparationOptions = .init(),
        cancellation: AnalysisCancellationToken? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> SingleslicePtychographyInput {
        // The view's own shape — a crop is what is being processed, not the
        // file's full extent.
        let descriptor = view.descriptor
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
                view, yRange: scanRow..<(scanRow + 1)
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
        // Scan positions: py4DSTEM's `_calculate_scan_positions_in_pixels`
        // (phase_base_class.py:1893-1917), in its own order — rotate about the
        // positions' mean, then transpose, then shift to non-negative, then to
        // pixels, then pad. Before D002 (Gate D, 2026-09-09) this was a plain
        // axis-aligned raster: `calibration.rotationRad` and `.transpose` were
        // accepted and never read, although `ParallaxPhysicalCalibration
        // .resolve` REFUSES to build without a finite rotation. Measured then:
        // changing the rotation from 0° to 30° left every position bit-
        // identical, while the reference convention moves them by up to 11.16
        // object pixels on a 12x12 scan spanning 35.2 — and that grows with
        // scan extent.
        //
        // AXIS MAPPING. The conclusion holds — py4DSTEM's `positions[:,0]`
        // axis is this app's COLUMN, in BOTH detector and real space, so the
        // two frames differ by one consistent global relabel and a literal
        // transliteration would silently transpose the frame. But the
        // reasoning first written here did NOT establish it (Gate B,
        // 2026-09-11), so it is replaced rather than defended:
        //
        // What does NOT establish it — the rotated `com_measured_x`/`_y`
        // expressions (`_solve_for_center_of_mass_relative_rotation`,
        // phase_base_class.py:1090-1097 untransposed, :1121-1128 transposed).
        // They are symmetric under renaming x and y TOGETHER, so they fix no
        // mapping at all; and the first note cited the transposed branch.
        //
        // What does establish it — the gradient pairing on each side:
        //   py4DSTEM, phase_base_class.py:1099-1108: `com_measured_x` is
        //     differenced along array axis -2, `com_measured_y` along -1.
        //   this app, RotationCalibration.swift:86-95: `x'` (from `a = cx`)
        //     is differenced at `i ± 1` — the scan COLUMN, stride 1 with
        //     `width = rx` — and `y'` at `i ± width`, the scan row.
        // plus the detector side, Shaders/CenterOfMass.metal:59-67, where
        // `sumIX` accumulates over the inner `p.qx` loop: `cx` is the COLUMN.
        //
        // Consequence for the raster below: py4DSTEM's `meshgrid(indexing="ij")`
        // ravels axis-0-major, which under this mapping is COLUMN-major, while
        // this loop emits row-major. That is required, not a deviation — the
        // amplitudes are written at `(scanRow * rx + scanColumn)` above, so the
        // positions must be in the same order.
        //
        // The rotation is py4DSTEM's `AffineTransform(angle:)` applied as
        // `((p - mean) @ M) + mean` with M = [[cos, -sin], [sin, cos]] and p a
        // ROW vector (utils.py:712-734, 759-764) — a rotation by −θ in the
        // column-vector convention, not +θ.
        //
        // DEVIATION: py4DSTEM pads BOTH axes by `region_of_interest_shape[0]/2`
        // (`object_padding_px = (float_padding, float_padding)` then
        // `[0][0]` and `[1][0]`, :1909-1916 — both index 0). This app pads each
        // axis by its own half-extent, which differs only on a non-square
        // detector. Measured (Gate B, 2026-09-11) against py4DSTEM's real
        // `AffineTransform` run over the harness's own cases: the divergence is
        // exactly `(qy - qx)/2` object pixels on the row coordinate — 8.0 px at
        // 32x48, 16.0 px at 48x16, 0 on a square detector. It is a UNIFORM
        // translation of every position along one axis, so relative scan
        // geometry is untouched; what moves is the object canvas origin and
        // `objectHeight` below. Kept as it was: correcting py4DSTEM's quirk is
        // not D002's scope, and changing it would move a number nobody asked
        // about.
        var columnsAngstrom = [Double](repeating: 0, count: patternCount)
        var rowsAngstrom = [Double](repeating: 0, count: patternCount)
        for row in 0..<descriptor.ry {
            for column in 0..<descriptor.rx {
                let index = row * descriptor.rx + column
                columnsAngstrom[index] = Double(column) * calibration.scanSamplingAngstrom
                rowsAngstrom[index] = Double(row) * calibration.scanSamplingAngstrom
            }
        }
        let meanColumn = columnsAngstrom.reduce(0, +) / Double(patternCount)
        let meanRow = rowsAngstrom.reduce(0, +) / Double(patternCount)
        let cosTheta = cos(calibration.rotationRad)
        let sinTheta = sin(calibration.rotationRad)
        for index in 0..<patternCount {
            let u = columnsAngstrom[index] - meanColumn
            let v = rowsAngstrom[index] - meanRow
            columnsAngstrom[index] = meanColumn + u * cosTheta + v * sinTheta
            rowsAngstrom[index] = meanRow - u * sinTheta + v * cosTheta
        }
        // `np.flip(positions, 1)` swaps the two components AND `sampling[::-1]`
        // swaps the pair they are divided by. Local to this conversion: the
        // object's own sampling — and the probe built from it below — are not
        // transposed, exactly as py4DSTEM reassigns only its local `sampling`.
        var columnSampling = objectColumnSampling
        var rowSampling = objectRowSampling
        if calibration.transpose {
            swap(&columnsAngstrom, &rowsAngstrom)
            swap(&columnSampling, &rowSampling)
        }
        // `positions -= np.min(positions, axis=0).clip(-np.inf, 0)`: rotating
        // about the mean can carry a position below zero, and the object grid
        // starts at zero. A no-op when the rotation is zero.
        let columnShift = min(columnsAngstrom.min() ?? 0, 0)
        let rowShift = min(rowsAngstrom.min() ?? 0, 0)
        var positions = [PtychographyPosition]()
        positions.reserveCapacity(patternCount)
        for index in 0..<patternCount {
            positions.append(PtychographyPosition(
                row: Float((rowsAngstrom[index] - rowShift) / rowSampling) + topPadding,
                column: Float((columnsAngstrom[index] - columnShift) / columnSampling)
                    + leftPadding
            ))
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
