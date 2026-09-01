//
//  ParallaxDepthSectioning.swift
//  Source-locked py4DSTEM Parallax.depth_section implementation.
//

import Foundation

nonisolated struct ParallaxDepthOptions: Equatable, Sendable {
    var depthsAngstrom: [Double] = stride(from: -256.0, through: 256.0, by: 16.0)
        .map { $0 }
    var useFullFit = true
    var informationLimitInvAngstrom: Double? = nil
    var informationPower: Double = 1
    var maxWorkingBytes = 1_073_741_824
}

nonisolated struct ParallaxDepthResult: Sendable {
    let depthsAngstrom: [Double]
    /// Contiguous `[depth, padded row, padded column]` float32 planes.
    let paddedStack: [Float]
    let paddedHeight: Int
    let paddedWidth: Int
    let scanHeight: Int
    let scanWidth: Int
    let samplingAngstrom: Double
    let usedFullFit: Bool
    let informationLimitInvAngstrom: Double?
    let informationPower: Double

    var planeCount: Int { depthsAngstrom.count }

    func croppedPlane(at index: Int) -> FloatImage? {
        guard depthsAngstrom.indices.contains(index) else { return nil }
        let top = (paddedHeight - scanHeight) / 2
        let left = (paddedWidth - scanWidth) / 2
        let plane = index * paddedHeight * paddedWidth
        var pixels = [Float](repeating: 0, count: scanHeight * scanWidth)
        for row in 0..<scanHeight {
            let source = plane + (top + row) * paddedWidth + left
            pixels.replaceSubrange(
                row * scanWidth..<(row + 1) * scanWidth,
                with: paddedStack[source..<(source + scanWidth)]
            )
        }
        return FloatImage(width: scanWidth, height: scanHeight, pixels: pixels)
    }
}

nonisolated enum ParallaxDepthSectioner {
    enum DepthError: LocalizedError, Equatable {
        case invalidInput(String)
        case memoryLimit(bytes: Int, limit: Int)
        case fftUnavailable
        case cancelled

        var errorDescription: String? {
            switch self {
            case .invalidInput(let detail):
                return "Cannot depth-section the parallax result: \(detail)."
            case .memoryLimit(let bytes, let limit):
                return "Parallax depth sectioning needs about \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)), above its \(ByteCountFormatter.string(fromByteCount: Int64(limit), countStyle: .file)) limit. Reduce the depth count or crop/bin first."
            case .fftUnavailable:
                return "Could not create the exact-shape FFT used for depth sectioning."
            case .cancelled:
                return "Parallax depth sectioning was cancelled."
            }
        }
    }

    static func section(
        preprocessing: ParallaxPreprocessResult,
        alignment: ParallaxAlignmentResult,
        fit: ParallaxHigherOrderAberrationFitResult,
        options: ParallaxDepthOptions = .init(),
        cancellation: AnalysisCancellationToken? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> ParallaxDepthResult {
        try checkCancellation(cancellation)
        let width = alignment.stackWidth, height = alignment.stackHeight
        let count = width * height
        let bfCount = preprocessing.brightFieldPixelCount
        guard alignment.isComplete, count > 0,
              alignment.shiftedStack.count == bfCount * count,
              preprocessing.probeAnglesMrad.count == bfCount,
              fit.terms.count == fit.coefficientsAngstrom.count else {
            throw DepthError.invalidInput("alignment, fit, or probe arrays are inconsistent")
        }
        guard !options.depthsAngstrom.isEmpty,
              options.depthsAngstrom.allSatisfy({ $0.isFinite }),
              preprocessing.calibration.scanSamplingAngstrom.isFinite,
              preprocessing.calibration.scanSamplingAngstrom > 0,
              options.informationPower.isFinite, options.informationPower > 0,
              options.maxWorkingBytes > 0,
              options.informationLimitInvAngstrom == nil
                || (options.informationLimitInvAngstrom!.isFinite
                    && options.informationLimitInvAngstrom! > 0) else {
            throw DepthError.invalidInput("depths, sampling, filter, or memory limit are invalid")
        }
        guard options.depthsAngstrom.count <= Int.max / count else {
            throw DepthError.invalidInput("depth-stack dimensions overflow")
        }
        let outputCount = options.depthsAngstrom.count * count
        guard outputCount <= Int.max / MemoryLayout<Float>.stride else {
            throw DepthError.invalidInput("depth-stack byte size overflows")
        }
        let outputBytes = outputCount * MemoryLayout<Float>.stride
        let scratchBytes = count * MemoryLayout<Float>.stride * 5
        let workingBytes = outputBytes + scratchBytes
        guard workingBytes <= options.maxWorkingBytes else {
            throw DepthError.memoryLimit(bytes: workingBytes, limit: options.maxWorkingBytes)
        }
        guard let fft = FFT2D(nx: width, ny: height) else {
            throw DepthError.fftUnavailable
        }

        let sampling = preprocessing.calibration.scanSamplingAngstrom
        let wavelength = preprocessing.calibration.wavelengthAngstrom
        var ctf = [Float](repeating: 0, count: count)
        var envelope = [Float](repeating: 1, count: count)
        for row in 0..<height {
            let kRow = Double(FFT2D.fftfreq(row, height)) / sampling
            for column in 0..<width {
                let kColumn = Double(FFT2D.fftfreq(column, width)) / sampling
                let frequency2 = kRow * kRow + kColumn * kColumn
                let chi: Double
                if options.useFullFit {
                    let alpha = sqrt(frequency2) * wavelength
                    let theta = atan2(kColumn, kRow)
                    var value: Double = 0
                    for (term, coefficient) in zip(
                        fit.terms, fit.coefficientsAngstrom
                    ) {
                        let radial = pow(alpha, Double(term.radialOrder + 1))
                            / Double(term.radialOrder + 1)
                        if term.angularOrder == 0 {
                            value += radial * coefficient
                        } else if term.component == 0 {
                            value += radial
                                * cos(Double(term.angularOrder) * theta) * coefficient
                        } else {
                            value += radial
                                * sin(Double(term.angularOrder) * theta) * coefficient
                        }
                    }
                    chi = value * 2 * .pi / wavelength
                } else {
                    chi = .pi * wavelength * fit.lowOrder.c1Angstrom * frequency2
                }
                let sine = sin(chi)
                let index = row * width + column
                ctf[index] = sine > 0 ? 1 : (sine < 0 ? -1 : 0)
                if let limit = options.informationLimitInvAngstrom {
                    envelope[index] = Float(1 / (
                        1 + pow(frequency2, options.informationPower)
                            / pow(limit, 2 * options.informationPower)
                    ))
                }
            }
        }
        ctf[0] = 0

        var stack = [Float](repeating: 0, count: outputCount)
        for (depthIndex, depth) in options.depthsAngstrom.enumerated() {
            try checkCancellation(cancellation)
            var accumulated = [Float](repeating: 0, count: count)
            for bf in 0..<bfCount {
                if bf & 3 == 0 { try checkCancellation(cancellation) }
                let plane = bf * count
                var real = Array(alignment.shiftedStack[plane..<(plane + count)])
                var imaginary = [Float](repeating: 0, count: count)
                fft.transform(re: &real, im: &imaginary, forward: true)
                let angleRow = Double(preprocessing.probeAnglesMrad[bf].qx) / 1_000
                let angleColumn = Double(preprocessing.probeAnglesMrad[bf].qy) / 1_000
                let shiftRows = -angleRow * depth / sampling
                let shiftColumns = -angleColumn * depth / sampling
                for row in 0..<height {
                    let frequencyRow = Double(FFT2D.fftfreq(row, height))
                    for column in 0..<width {
                        let frequencyColumn = Double(FFT2D.fftfreq(column, width))
                        let phase = -2 * Double.pi * (
                            frequencyRow * shiftRows + frequencyColumn * shiftColumns
                        )
                        let cosine = Float(cos(phase)), sine = Float(sin(phase))
                        let index = row * width + column
                        let multiplier = ctf[index] * envelope[index]
                        let oldReal = real[index], oldImaginary = imaginary[index]
                        real[index] = (oldReal * cosine - oldImaginary * sine) * multiplier
                        imaginary[index] = (oldReal * sine + oldImaginary * cosine) * multiplier
                    }
                }
                fft.transform(re: &real, im: &imaginary, forward: false)
                for index in 0..<count { accumulated[index] += real[index] }
            }
            let scale = 1 / Float(bfCount)
            let destination = depthIndex * count
            for index in 0..<count { stack[destination + index] = accumulated[index] * scale }
            progress?(Double(depthIndex + 1) / Double(options.depthsAngstrom.count))
        }
        try checkCancellation(cancellation)
        return ParallaxDepthResult(
            depthsAngstrom: options.depthsAngstrom, paddedStack: stack,
            paddedHeight: height, paddedWidth: width,
            scanHeight: preprocessing.scanHeight, scanWidth: preprocessing.scanWidth,
            samplingAngstrom: sampling, usedFullFit: options.useFullFit,
            informationLimitInvAngstrom: options.informationLimitInvAngstrom,
            informationPower: options.informationPower
        )
    }

    private static func checkCancellation(
        _ cancellation: AnalysisCancellationToken?
    ) throws {
        if cancellation?.isCancelled == true { throw DepthError.cancelled }
    }
}
