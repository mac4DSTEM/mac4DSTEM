//
//  ParallaxPreprocessing.swift
//  Source-locked foundation for py4DSTEM Parallax.preprocess. This slice
//  intentionally stops before cross-correlation and iterative reconstruction.
//

import Foundation

package nonisolated struct ParallaxDetectorIndex: Equatable, Sendable {
    /// py4DSTEM qx: first / detector-row axis (app y).
    package let qx: Int
    /// py4DSTEM qy: second / detector-column axis (app x).
    package let qy: Int

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(qx: Int, qy: Int) {
        self.qx = qx
        self.qy = qy
    }
}

package nonisolated struct ParallaxVector: Equatable, Sendable {
    package let qx: Float
    package let qy: Float

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(qx: Float, qy: Float) {
        self.qx = qx
        self.qy = qy
    }
}

package nonisolated struct ParallaxPhysicalCalibration: Equatable, Sendable {
    package let scanSamplingAngstrom: Double
    package let reciprocalSamplingInvAngstrom: Double
    package let energyEV: Double
    package let wavelengthAngstrom: Double
    package let originQX: Double
    package let originQY: Double
    package let rotationRad: Double
    package let transpose: Bool

    package static func resolve(
        calibration: Calibration,
        apertureCenterX: Float,
        apertureCenterY: Float,
        acceleratingVoltageKV: Double?
    ) throws -> ParallaxPhysicalCalibration {
        if case .geometricDefault = calibration.originProvenance {
            throw ParallaxPreprocessor.PreprocessError.missingCalibration(
                "Calibrate or explicitly set the diffraction origin."
            )
        }
        guard apertureCenterX.isFinite, apertureCenterY.isFinite else {
            throw ParallaxPreprocessor.PreprocessError.missingCalibration(
                "Set a finite diffraction origin."
            )
        }
        guard let rotation = calibration.rotationRad, rotation.isFinite else {
            throw ParallaxPreprocessor.PreprocessError.missingCalibration(
                "Calibrate the R–Q rotation."
            )
        }
        guard let rSize = calibration.rPixelSize,
              rSize.isFinite, rSize > 0,
              let scanSampling = CalibrationUnitConversion.realAngstromPerPixel(
                value: rSize, units: calibration.rPixelUnits
              ) else {
            throw ParallaxPreprocessor.PreprocessError.missingCalibration(
                "Set a positive R pixel size in Å, nm, or pm."
            )
        }
        guard let energyKV = acceleratingVoltageKV,
              energyKV.isFinite, energyKV > 0 else {
            throw ParallaxPreprocessor.PreprocessError.missingCalibration(
                "Set the accelerating voltage in kV."
            )
        }
        let energyEV = energyKV * 1_000
        let wavelength = ParallaxPreprocessor.electronWavelengthAngstrom(energyEV: energyEV)
        guard let qSize = calibration.qPixelSize,
              qSize.isFinite, qSize > 0,
              let reciprocalSampling =
                CalibrationUnitConversion.reciprocalInvAngstromPerPixel(
                    value: qSize, units: calibration.qPixelUnits,
                    wavelengthAngstrom: wavelength
              ) else {
            throw ParallaxPreprocessor.PreprocessError.missingCalibration(
                "Set a positive Q pixel size in Å⁻¹, nm⁻¹, or mrad."
            )
        }
        return ParallaxPhysicalCalibration(
            scanSamplingAngstrom: scanSampling,
            reciprocalSamplingInvAngstrom: reciprocalSampling,
            energyEV: energyEV,
            wavelengthAngstrom: wavelength,
            // One explicit app -> py4DSTEM detector-axis conversion.
            originQX: Double(apertureCenterY),
            originQY: Double(apertureCenterX),
            rotationRad: Double(rotation),
            transpose: calibration.transposeQR ?? false
        )
    }


    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(scanSamplingAngstrom: Double, reciprocalSamplingInvAngstrom: Double, energyEV: Double, wavelengthAngstrom: Double, originQX: Double, originQY: Double, rotationRad: Double, transpose: Bool) {
        self.scanSamplingAngstrom = scanSamplingAngstrom
        self.reciprocalSamplingInvAngstrom = reciprocalSamplingInvAngstrom
        self.energyEV = energyEV
        self.wavelengthAngstrom = wavelengthAngstrom
        self.originQX = originQX
        self.originQY = originQY
        self.rotationRad = rotationRad
        self.transpose = transpose
    }
}

package nonisolated struct ParallaxPreprocessOptions: Equatable, Sendable {
    package var thresholdIntensity: Float = 0.8
    package var edgeBlend: Float = 16
    /// Total padding added to the two scan axes, matching py4DSTEM's default.
    package var paddingY: Int = 32
    package var paddingX: Int = 32
    /// Nil chooses scan-row tiles bounded to roughly 64 MiB.
    package var tileRows: Int? = nil
    package var maxStackBytes: Int = 1_073_741_824

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(thresholdIntensity: Float = 0.8, edgeBlend: Float = 16, paddingY: Int = 32, paddingX: Int = 32, tileRows: Int? = nil, maxStackBytes: Int = 1_073_741_824) {
        self.thresholdIntensity = thresholdIntensity
        self.edgeBlend = edgeBlend
        self.paddingY = paddingY
        self.paddingX = paddingX
        self.tileRows = tileRows
        self.maxStackBytes = maxStackBytes
    }
}

package nonisolated struct ParallaxPreprocessResult: Sendable {
    package let scanHeight: Int
    package let scanWidth: Int
    package let detectorHeight: Int
    package let detectorWidth: Int
    package let stackHeight: Int
    package let stackWidth: Int
    package let calibration: ParallaxPhysicalCalibration
    package let thresholdIntensity: Float
    package let detectorMask: [Bool]
    package let detectorIndices: [ParallaxDetectorIndex]
    package let reciprocalVectors: [ParallaxVector]
    package let probeAnglesMrad: [ParallaxVector]
    package let edgeWindow: [Float]
    /// py4DSTEM layout: [bright-field detector pixel, scan row, scan column].
    package let normalizedStack: [Float]
    /// py4DSTEM `_stack_BF_unshifted`: intensity-normalized virtual-BF
    /// images before the edge window is blended in. Subpixel KDE must use
    /// this lossless product because the blended stack has zero-weight edges.
    package let unshiftedStack: [Float]
    /// Padded incoherent BF initialization (`Parallax.recon_BF`).
    package let incoherentBF: [Float]
    package let initialError: Float

    package var brightFieldPixelCount: Int { detectorIndices.count }
    package var stackByteCount: Int { normalizedStack.count * MemoryLayout<Float>.stride }
    package var residentStackByteCount: Int {
        (normalizedStack.count + unshiftedStack.count) * MemoryLayout<Float>.stride
    }

    package var maximumProbeAngleMrad: Float {
        probeAnglesMrad.reduce(0) { partial, vector in
            max(partial, hypot(vector.qx, vector.qy))
        }
    }

    package var previewImage: FloatImage {
        let top = (stackHeight - scanHeight) / 2
        let left = (stackWidth - scanWidth) / 2
        var pixels = [Float](repeating: 0, count: scanHeight * scanWidth)
        for y in 0..<scanHeight {
            let source = (top + y) * stackWidth + left
            pixels.replaceSubrange(
                (y * scanWidth)..<((y + 1) * scanWidth),
                with: incoherentBF[source..<(source + scanWidth)]
            )
        }
        return FloatImage(width: scanWidth, height: scanHeight, pixels: pixels)
    }

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(scanHeight: Int, scanWidth: Int, detectorHeight: Int, detectorWidth: Int, stackHeight: Int, stackWidth: Int, calibration: ParallaxPhysicalCalibration, thresholdIntensity: Float, detectorMask: [Bool], detectorIndices: [ParallaxDetectorIndex], reciprocalVectors: [ParallaxVector], probeAnglesMrad: [ParallaxVector], edgeWindow: [Float], normalizedStack: [Float], unshiftedStack: [Float], incoherentBF: [Float], initialError: Float) {
        self.scanHeight = scanHeight
        self.scanWidth = scanWidth
        self.detectorHeight = detectorHeight
        self.detectorWidth = detectorWidth
        self.stackHeight = stackHeight
        self.stackWidth = stackWidth
        self.calibration = calibration
        self.thresholdIntensity = thresholdIntensity
        self.detectorMask = detectorMask
        self.detectorIndices = detectorIndices
        self.reciprocalVectors = reciprocalVectors
        self.probeAnglesMrad = probeAnglesMrad
        self.edgeWindow = edgeWindow
        self.normalizedStack = normalizedStack
        self.unshiftedStack = unshiftedStack
        self.incoherentBF = incoherentBF
        self.initialError = initialError
    }
}

package nonisolated enum ParallaxPreprocessor {
    package enum PreprocessError: LocalizedError, Equatable {
        case missingCalibration(String)
        case invalidOptions(String)
        case invalidData(String)
        case stackTooLarge(bytes: Int, limit: Int)
        case cancelled

        package var errorDescription: String? {
            switch self {
            case .missingCalibration(let detail):
                return "Parallax preprocessing needs physical calibration. \(detail)"
            case .invalidOptions(let detail):
                return "Invalid parallax preprocessing options: \(detail)"
            case .invalidData(let detail):
                return "Cannot preprocess parallax data: \(detail)"
            case .stackTooLarge(let bytes, let limit):
                return "The virtual-BF stack needs \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)), above the \(ByteCountFormatter.string(fromByteCount: Int64(limit), countStyle: .file)) preview limit. Crop/bin the dataset first."
            case .cancelled:
                return "Parallax preprocessing was cancelled."
            }
        }
    }

    package static func electronWavelengthAngstrom(energyEV: Double) -> Double {
        // Exact constants/form used by py4DSTEM electron_wavelength_angstrom.
        let mass = 9.109383e-31
        let charge = 1.602177e-19
        let lightSpeed = 299_792_458.0
        let planck = 6.62607e-34
        return planck
            / sqrt(2 * mass * charge * energyEV)
            / sqrt(1 + charge * energyEV / (2 * mass * lightSpeed * lightSpeed))
            * 1e10
    }

    package static func run(
        source: any FourDDataSource,
        view: LoadView,
        calibration: ParallaxPhysicalCalibration,
        options: ParallaxPreprocessOptions = ParallaxPreprocessOptions(),
        cancellation: AnalysisCancellationToken? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> ParallaxPreprocessResult {
        // The view's own shape — a crop is what is being processed, not the
        // file's full extent.
        let descriptor = view.descriptor
        guard descriptor.is4D, descriptor.ry > 0, descriptor.rx > 0,
              descriptor.qy > 0, descriptor.qx > 0 else {
            throw PreprocessError.invalidData("the dataset is not a non-empty 4D cube")
        }
        guard options.thresholdIntensity.isFinite,
              options.thresholdIntensity > 0, options.thresholdIntensity <= 1 else {
            throw PreprocessError.invalidOptions("threshold must be in (0, 1]")
        }
        guard options.edgeBlend.isFinite, options.edgeBlend > 0,
              options.paddingY >= 0, options.paddingX >= 0,
              options.maxStackBytes > 0 else {
            throw PreprocessError.invalidOptions("edge blend, padding, and memory limit must be positive")
        }
        try checkCancellation(cancellation)

        let detectorCount = descriptor.qy * descriptor.qx
        let scanCount = descriptor.ry * descriptor.rx
        let tileRows = resolvedTileRows(descriptor: descriptor, requested: options.tileRows)

        // Pass 1: py4DSTEM `dp_mean = intensities.mean((0,1))`.
        var detectorMean = [Float](repeating: 0, count: detectorCount)
        var processedRows = 0
        for lower in stride(from: 0, to: descriptor.ry, by: tileRows) {
            try checkCancellation(cancellation)
            let upper = min(descriptor.ry, lower + tileRows)
            let tile = try await source.readScanTile(view, yRange: lower..<upper)
            try validate(tile: tile, descriptor: descriptor, range: lower..<upper)
            for localY in 0..<tile.rowCount {
                try checkCancellation(cancellation)
                for x in 0..<descriptor.rx {
                    let base = (localY * descriptor.rx + x) * detectorCount
                    for q in 0..<detectorCount {
                        detectorMean[q] += tile.pixels[base + q]
                    }
                }
                processedRows += 1
                progress?(Double(processedRows) / Double(descriptor.ry * 2))
            }
        }
        let inverseScanCount = 1 / Float(scanCount)
        detectorMean = detectorMean.map { $0 * inverseScanCount }
        guard let maximum = detectorMean.filter(\.isFinite).max(), maximum > 0 else {
            throw PreprocessError.invalidData("the mean diffraction pattern has no positive finite signal")
        }
        let threshold = maximum * options.thresholdIntensity
        let detectorMask = detectorMean.map { $0.isFinite && $0 >= threshold }
        var indices = [ParallaxDetectorIndex]()
        for qx in 0..<descriptor.qy {
            for qy in 0..<descriptor.qx where detectorMask[qx * descriptor.qx + qy] {
                indices.append(ParallaxDetectorIndex(qx: qx, qy: qy))
            }
        }
        guard !indices.isEmpty else {
            throw PreprocessError.invalidData("the bright-field threshold selected no detector pixels")
        }

        let meanQX = Double(indices.reduce(0) { $0 + $1.qx }) / Double(indices.count)
        let meanQY = Double(indices.reduce(0) { $0 + $1.qy }) / Double(indices.count)
        let reciprocalVectors = indices.map {
            ParallaxVector(
                qx: Float((Double($0.qx) - meanQX)
                          * calibration.reciprocalSamplingInvAngstrom),
                qy: Float((Double($0.qy) - meanQY)
                          * calibration.reciprocalSamplingInvAngstrom)
            )
        }
        let probeAngles = reciprocalVectors.map {
            ParallaxVector(
                qx: $0.qx * Float(calibration.wavelengthAngstrom * 1_000),
                qy: $0.qy * Float(calibration.wavelengthAngstrom * 1_000)
            )
        }

        let edgeY = edgeWindowAxis(count: descriptor.ry, blend: options.edgeBlend)
        let edgeX = edgeWindowAxis(count: descriptor.rx, blend: options.edgeBlend)
        var edgeWindow = [Float](repeating: 0, count: scanCount)
        for y in 0..<descriptor.ry {
            for x in 0..<descriptor.rx {
                edgeWindow[y * descriptor.rx + x] = edgeY[y] * edgeX[x]
            }
        }
        let windowSum = edgeWindow.reduce(0, +)
        guard windowSum.isFinite, windowSum > 0 else {
            throw PreprocessError.invalidData("the real-space edge window is empty")
        }

        let stackHeight = descriptor.ry + options.paddingY
        let stackWidth = descriptor.rx + options.paddingX
        let planeCount = try checkedProduct(stackHeight, stackWidth)
        let stackCount = try checkedProduct(planeCount, indices.count)
        let stackBytes = try checkedProduct(stackCount, MemoryLayout<Float>.stride)
        let residentStackBytes = try checkedProduct(stackBytes, 2)
        guard residentStackBytes <= options.maxStackBytes else {
            throw PreprocessError.stackTooLarge(
                bytes: residentStackBytes, limit: options.maxStackBytes
            )
        }

        // Both source products are retained: alignment consumes the blended
        // stack while py4DSTEM's subpixel KDE consumes the unwindowed stack.
        // The input 4D cube remains tiled rather than resident.
        var stack = [Float](repeating: 1, count: stackCount)
        var unshiftedStack = [Float](repeating: 1, count: stackCount)
        var weightedSums = [Float](repeating: 0, count: indices.count)
        let top = options.paddingY / 2
        let left = options.paddingX / 2
        processedRows = 0
        for lower in stride(from: 0, to: descriptor.ry, by: tileRows) {
            try checkCancellation(cancellation)
            let upper = min(descriptor.ry, lower + tileRows)
            let tile = try await source.readScanTile(view, yRange: lower..<upper)
            try validate(tile: tile, descriptor: descriptor, range: lower..<upper)
            for localY in 0..<tile.rowCount {
                try checkCancellation(cancellation)
                let globalY = lower + localY
                for x in 0..<descriptor.rx {
                    let sourceBase = (localY * descriptor.rx + x) * detectorCount
                    let scanIndex = globalY * descriptor.rx + x
                    let window = edgeWindow[scanIndex]
                    let stackPixel = (top + globalY) * stackWidth + left + x
                    for (bf, index) in indices.enumerated() {
                        let raw = tile.pixels[sourceBase + index.qx * descriptor.qx + index.qy]
                        guard raw.isFinite else {
                            throw PreprocessError.invalidData("a selected bright-field pixel is non-finite")
                        }
                        let offset = bf * planeCount + stackPixel
                        stack[offset] = raw
                        unshiftedStack[offset] = raw
                        weightedSums[bf] += raw * window
                    }
                }
                processedRows += 1
                progress?(0.5 + Double(processedRows) / Double(descriptor.ry * 2))
            }
        }
        try checkCancellation(cancellation)

        for bf in 0..<indices.count {
            let weight = weightedSums[bf] / windowSum
            guard weight.isFinite, weight > 0 else {
                throw PreprocessError.invalidData("a selected virtual-BF image has zero weighted intensity")
            }
            let plane = bf * planeCount
            for y in 0..<descriptor.ry {
                for x in 0..<descriptor.rx {
                    let window = edgeWindow[y * descriptor.rx + x]
                    let offset = plane + (top + y) * stackWidth + left + x
                    unshiftedStack[offset] /= weight
                    stack[offset] = 1 - window + window * unshiftedStack[offset]
                }
            }
        }
        try checkCancellation(cancellation)

        let stackMean = Float(Double(stack.reduce(0, +)) / Double(stack.count))
        guard stackMean.isFinite, stackMean > 0 else {
            throw PreprocessError.invalidData("the normalized stack mean is not positive")
        }
        var incoherent = [Float](repeating: stackMean, count: planeCount)
        var errorSum: Double = 0
        for y in 0..<descriptor.ry {
            for x in 0..<descriptor.rx {
                let window = edgeWindow[y * descriptor.rx + x]
                let pixel = (top + y) * stackWidth + left + x
                var average: Float = 0
                for bf in 0..<indices.count {
                    average += stack[bf * planeCount + pixel]
                }
                average /= Float(indices.count)
                let reference = stackMean * (1 - window) + average * window
                incoherent[pixel] = reference
                for bf in 0..<indices.count {
                    errorSum += Double(abs(stack[bf * planeCount + pixel] - reference) * window)
                }
            }
        }
        let initialError = Float(
            errorSum / Double(windowSum * Float(indices.count)) / Double(stackMean)
        )

        try checkCancellation(cancellation)
        progress?(1)
        return ParallaxPreprocessResult(
            scanHeight: descriptor.ry, scanWidth: descriptor.rx,
            detectorHeight: descriptor.qy, detectorWidth: descriptor.qx,
            stackHeight: stackHeight, stackWidth: stackWidth,
            calibration: calibration, thresholdIntensity: options.thresholdIntensity,
            detectorMask: detectorMask, detectorIndices: indices,
            reciprocalVectors: reciprocalVectors, probeAnglesMrad: probeAngles,
            edgeWindow: edgeWindow, normalizedStack: stack,
            unshiftedStack: unshiftedStack,
            incoherentBF: incoherent, initialError: initialError
        )
    }

    private static func edgeWindowAxis(count: Int, blend: Float) -> [Float] {
        (0..<count).map { index in
            let coordinate = -1 + (Float(index) + 0.5) * 2 / Float(count)
            let ramp = min(max((1 - abs(coordinate)) * Float(count) / blend / 2, 0), 1)
            let sine = sin(ramp * .pi / 2)
            return sine * sine
        }
    }

    private static func resolvedTileRows(
        descriptor: DatasetDescriptor, requested: Int?
    ) -> Int {
        if let requested { return max(1, min(descriptor.ry, requested)) }
        let rowBytes = descriptor.rx * descriptor.qy * descriptor.qx
            * MemoryLayout<Float>.stride
        return max(1, min(descriptor.ry, 64 * 1_024 * 1_024 / max(1, rowBytes)))
    }

    private static func validate(
        tile: FourDScanTile, descriptor: DatasetDescriptor, range: Range<Int>
    ) throws {
        let expected = range.count * descriptor.rx * descriptor.qy * descriptor.qx
        guard tile.yRange == range, tile.scanWidth == descriptor.rx,
              tile.detectorHeight == descriptor.qy,
              tile.detectorWidth == descriptor.qx,
              tile.pixels.count == expected else {
            throw PreprocessError.invalidData("the data source returned an inconsistent scan tile")
        }
    }

    private static func checkCancellation(
        _ cancellation: AnalysisCancellationToken?
    ) throws {
        if cancellation?.isCancelled == true { throw PreprocessError.cancelled }
    }

    private static func checkedProduct(_ lhs: Int, _ rhs: Int) throws -> Int {
        let (value, overflow) = lhs.multipliedReportingOverflow(by: rhs)
        if overflow { throw PreprocessError.invalidData("the requested stack dimensions overflow") }
        return value
    }
}
