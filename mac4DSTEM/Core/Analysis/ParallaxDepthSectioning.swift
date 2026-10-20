//
//  ParallaxDepthSectioning.swift
//  py4DSTEM Parallax.depth_section: the app's options, result and memory/cancellation wrapper around CuboKit 0.4.0's
//  CuboParallax.ParallaxDepthSectioning.
//

import CuboParallax
import Foundation

package nonisolated struct ParallaxDepthOptions: Equatable, Sendable {
    // Explicit so the default initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init() {}

    package var depthsAngstrom: [Double] = stride(from: -256.0, through: 256.0, by: 16.0)
        .map { $0 }
    package var useFullFit = true
    package var informationLimitInvAngstrom: Double? = nil
    package var informationPower: Double = 1
    package var maxWorkingBytes = PhaseContrastMemoryBudget.workingLimitBytes
}

package nonisolated struct ParallaxDepthResult: Sendable {
    package let depthsAngstrom: [Double]
    /// Contiguous `[depth, padded row, padded column]` float32 planes.
    package let paddedStack: [Float]
    package let paddedHeight: Int
    package let paddedWidth: Int
    package let scanHeight: Int
    package let scanWidth: Int
    package let samplingAngstrom: Double
    package let usedFullFit: Bool
    package let informationLimitInvAngstrom: Double?
    package let informationPower: Double

    package var planeCount: Int { depthsAngstrom.count }

    package func croppedPlane(at index: Int) -> FloatImage? {
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

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(depthsAngstrom: [Double], paddedStack: [Float], paddedHeight: Int, paddedWidth: Int, scanHeight: Int, scanWidth: Int, samplingAngstrom: Double, usedFullFit: Bool, informationLimitInvAngstrom: Double?, informationPower: Double) {
        self.depthsAngstrom = depthsAngstrom
        self.paddedStack = paddedStack
        self.paddedHeight = paddedHeight
        self.paddedWidth = paddedWidth
        self.scanHeight = scanHeight
        self.scanWidth = scanWidth
        self.samplingAngstrom = samplingAngstrom
        self.usedFullFit = usedFullFit
        self.informationLimitInvAngstrom = informationLimitInvAngstrom
        self.informationPower = informationPower
    }
}

package nonisolated enum ParallaxDepthSectioner {
    package enum DepthError: LocalizedError, Equatable {
        case invalidInput(String)
        case memoryLimit(bytes: Int, limit: Int)
        case cancelled

        package var errorDescription: String? {
            switch self {
            case .invalidInput(let detail):
                return "Cannot depth-section the parallax result: \(detail)."
            case .memoryLimit(let bytes, let limit):
                return "Parallax depth sectioning needs about \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)), above its \(ByteCountFormatter.string(fromByteCount: Int64(limit), countStyle: .file)) limit. Crop/bin first, or reduce the depth count."
            case .cancelled:
                return "Parallax depth sectioning was cancelled."
            }
        }
    }

    /// CuboParallax's `ParallaxDepthSectioning.section` (`.fullFit` or `.defocusOnly` as `useFullFit` says) on the aligned stack, in Double.
    /// The kit takes the whole stack as Double images; the app calls it once per depth plane (cancellation and progress between planes)
    /// and keeps the memory refusal.
    package static func section(
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
        guard outputCount <= Int.max / MemoryLayout<Double>.stride,
              bfCount <= Int.max / count / (3 * MemoryLayout<Double>.stride) else {
            throw DepthError.invalidInput("depth-stack byte size overflows")
        }
        // The kit's peak per call, beside the Float stack the alignment already holds: the stack as Double images (converted once,
        // held for every plane), its complex spectra (two Double planes each, rebuilt per call), one Double plane returned, and the
        // sign / envelope / accumulation scratch; then the whole Float output.
        let doubleBytes = MemoryLayout<Double>.stride
        let workingBytes = bfCount * count * 3 * doubleBytes          // images + spectra
            + outputCount * MemoryLayout<Float>.stride                // the Float stack
            + count * 7 * doubleBytes                                 // returned plane, sign, envelope, mean, transform scratch
        guard workingBytes <= options.maxWorkingBytes else {
            throw DepthError.memoryLimit(bytes: workingBytes, limit: options.maxWorkingBytes)
        }

        let sampling = preprocessing.calibration.scanSamplingAngstrom
        let ctf: CuboParallax.ParallaxDepthCTF = options.useFullFit
            ? .fullFit(
                terms: fit.terms,
                coefficientsAngstrom: fit.coefficientsAngstrom)
            : .defocusOnly(c1Angstrom: fit.lowOrder.c1Angstrom)
        let images: [[Double]] = (0..<bfCount).map { bf in
            alignment.shiftedStack[(bf * count)..<((bf + 1) * count)].map(Double.init)
        }
        let angles = preprocessing.probeAnglesMrad.map {
            CuboParallax.ParallaxShift(row: Double($0.qx) / 1_000, column: Double($0.qy) / 1_000)
        }
        // One kit call per depth plane, so a cancel lands between planes as before. The kit transforms every image forward on each
        // call (a plane's own work is one shift and one inverse FFT per image), so this costs one extra forward FFT per image per plane:
        // about 1.5x the FFT work of a single multi-depth call, measured nowhere on real data (delete at a CuboKit that takes the
        // depth list with a per-plane callback).
        var stack = [Float](repeating: 0, count: outputCount)
        for (depthIndex, depth) in options.depthsAngstrom.enumerated() {
            try checkCancellation(cancellation)
            let planes: [[Double]]
            do {
                planes = try CuboParallax.ParallaxDepthSectioning.section(
                    stack: images, rows: height, columns: width, probeAngles: angles,
                    sampling: CuboParallax.ParallaxShift(row: sampling, column: sampling),
                    wavelength: preprocessing.calibration.wavelengthAngstrom, ctf: ctf,
                    depthsAngstrom: [depth],
                    informationLimit: options.informationLimitInvAngstrom,
                    informationPower: options.informationPower
                )
            } catch {
                throw DepthError.invalidInput(parallaxKitReason(error))
            }
            let destination = depthIndex * count
            for index in 0..<count { stack[destination + index] = Float(planes[0][index]) }
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
