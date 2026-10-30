//
//  ParallaxPreprocessing.swift
//  The app's parallax preprocessing: the calibration the physical numbers need, the options and the result types, and the
//  streamed stack builder, which is CuboParallax's `ParallaxPreprocessing.prepare(source:)` (0.7.0) over the app's cube.
//

import CuboCore
import CuboParallax
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

    /// The diffraction origin this calibration carries, as py4DSTEM's
    /// detector axes `(qx, qy)` = (row, column) — D079. Only single-slice
    /// ptychography reads it (`PtychographyPreparation`, the per-pattern
    /// shift); parallax itself never reads `originQX`/`originQY`.
    ///
    /// This is `Calibration.referenceOrigin`, the one derivation every other
    /// consumer (DPC, strain, ACOM, Bragg calibration) already asks: fitted
    /// maps' mean → the file's/session's recorded mean → the aperture the user
    /// placed. `resolve` used to take the aperture centre unconditionally, so
    /// whenever the aperture and the calibration disagreed — the aperture is
    /// assigned directly, bypassing `AppState.updateAperture`, by replay and by
    /// lineage restore — parallax/ptychography and every other analysis used
    /// two different origins. In the ordinary flow they coincide (a fit or a
    /// file load moves the aperture onto the same mean, and a drag through
    /// `updateAperture` displaces the fit so the aperture IS the origin), so no
    /// number moves there. The geometric-middle fallback is unreachable: the
    /// aperture is always supplied, and `resolve` refuses `.geometricDefault`
    /// before asking.
    package static func diffractionOrigin(
        calibration: Calibration, apertureCentre: (x: Float, y: Float)
    ) -> (qx: Double, qy: Double) {
        let origin = calibration.referenceOrigin(
            detectorQX: 0, detectorQY: 0, apertureCentre: apertureCentre
        )
        // One explicit app -> py4DSTEM detector-axis conversion:
        // app x is the detector column (qy), app y the row (qx).
        return (qx: Double(origin.y), qy: Double(origin.x))
    }

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
        let origin = diffractionOrigin(
            calibration: calibration, apertureCentre: (x: apertureCenterX, y: apertureCenterY)
        )
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
            originQX: origin.qx,
            originQY: origin.qy,
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

/// The working-memory ceiling every phase-contrast stage refuses above (2026-09-30). It was a fixed 1 GiB in each
/// options type — the 8 GB Mac's number — so on a 64 GB Mac parallax and ptychography still refused what the machine
/// holds with room to spare (measured: 8.25 GB and 24.6 GB peaks on the 051 cube, honest estimates). Half the physical
/// memory, never below the old 1 GiB: the other half is the cube, the app and the system. A stage that needs more than
/// this is refused with the number, as before; a tool or a test sets its own limit on the options.
package nonisolated enum PhaseContrastMemoryBudget {
    package static let floorBytes = 1_073_741_824
    /// `residentCubeBytes` is the cube the user chose to keep in memory (0 when it is streamed): that cube already
    /// occupies part of the half, so the stages get half of RAM less the cube, never below the floor (2026-10-01).
    /// `heldProductBytes` is what earlier phase-contrast stages still hold while the next one runs (the preprocessed
    /// stacks, the published alignment level), less what that stage counts itself: each stage counts only its own
    /// working set, so without this term preprocess + alignment + a new level reached all of RAM unrefused (review d2,
    /// 2026-10-02). A refusal threshold only — no scientific number moves.
    package static func workingLimitBytes(
        physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory, residentCubeBytes: Int = 0,
        heldProductBytes: Int = 0
    ) -> Int {
        let half = Int(min(physicalMemory / 2, UInt64(Int.max)))
        // Each term is clamped to [0, half], so the difference never overflows.
        let cube = min(half, max(0, residentCubeBytes)), held = min(half, max(0, heldProductBytes))
        return max(floorBytes, half - cube - held)
    }
    package static let workingLimitBytes = workingLimitBytes()
}

package nonisolated struct ParallaxPreprocessOptions: Equatable, Sendable {
    package var thresholdIntensity: Float = 0.8
    package var edgeBlend: Float = 16
    /// Total padding added to the two scan axes, matching py4DSTEM's default.
    package var paddingY: Int = 32
    package var paddingX: Int = 32
    /// Nil chooses scan-row tiles bounded to roughly 64 MiB.
    package var tileRows: Int? = nil
    package var maxStackBytes: Int = PhaseContrastMemoryBudget.workingLimitBytes

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(thresholdIntensity: Float = 0.8, edgeBlend: Float = 16, paddingY: Int = 32, paddingX: Int = 32, tileRows: Int? = nil, maxStackBytes: Int = PhaseContrastMemoryBudget.workingLimitBytes) {
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

    /// py4DSTEM `electron_wavelength_angstrom`: the kit's, NaN for an energy it refuses.
    package static func electronWavelengthAngstrom(energyEV: Double) -> Double {
        (try? ParallaxPreprocessing.electronWavelength(energyEV: energyEV)) ?? .nan
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

        // The view's cube through the kit's source adapter (a fresh `FourDArray`: nothing resident, no cache to skip), the
        // tile rows sized at the READ extent below, both stacks kept (alignment reads the blended one, the subpixel KDE the
        // unwindowed one).
        let cube = try CuboCubeSource(FourDArray(reader: source, view: view), descriptor: descriptor, cancellation: cancellation)
        let sampling = calibration.reciprocalSamplingInvAngstrom
        let kit: ParallaxStreamedPreprocessingResult
        do {
            kit = try await ParallaxPreprocessing.prepare(
                source: cube,
                reciprocalSampling: ParallaxShift(row: sampling, column: sampling), energyEV: calibration.energyEV,
                threshold: Double(options.thresholdIntensity), edgeBlend: Double(options.edgeBlend),
                paddingRows: options.paddingY, paddingColumns: options.paddingX,
                retention: .unwindowed,
                tiling: .rows(resolvedTileRows(view: view, requested: options.tileRows)),
                maximumStackBytes: options.maxStackBytes,
                progress: progress, isCancelled: { cancellation?.isCancelled == true }
            )
        } catch is CancellationError {
            throw PreprocessError.cancelled
        } catch ParallaxError.stackTooLarge(let bytes, let limit) {
            throw PreprocessError.stackTooLarge(bytes: bytes, limit: limit)
        } catch ParallaxError.degenerateData {
            throw PreprocessError.invalidData(
                "the bright-field threshold selected no detector pixels, or a selected virtual-BF image, the mean pattern or the edge window has no positive weight"
            )
        } catch ParallaxError.nonfiniteValues {
            throw PreprocessError.invalidData("a selected bright-field pixel is non-finite")
        } catch ParallaxError.invalidInput {
            throw PreprocessError.invalidData("the stack dimensions or the calibrated sampling are invalid")
        }
        try checkCancellation(cancellation)
        // The kit's vectors are the Float values the old code stored, widened to Double.
        func vector(_ shift: ParallaxShift) -> ParallaxVector {
            ParallaxVector(qx: Float(shift.row), qy: Float(shift.column))
        }
        return ParallaxPreprocessResult(
            scanHeight: descriptor.ry, scanWidth: descriptor.rx,
            detectorHeight: descriptor.qy, detectorWidth: descriptor.qx,
            stackHeight: kit.rows, stackWidth: kit.columns,
            calibration: calibration, thresholdIntensity: options.thresholdIntensity,
            detectorMask: kit.detectorMask,
            detectorIndices: kit.detectorIndices.map { ParallaxDetectorIndex(qx: $0[0], qy: $0[1]) },
            reciprocalVectors: kit.reciprocalVectors.map(vector),
            // MILLIradians (kit: reciprocal vector x wavelength x 1000), where py4DSTEM's `_probe_angles` is radians: every
            // science consumer divides by 1000 first (ParallaxDepthSectioning, ParallaxAberrationFitting).
            probeAnglesMrad: kit.probeAnglesMrad.map(vector),
            edgeWindow: kit.window, normalizedStack: kit.stack, unshiftedStack: kit.unshiftedStack,
            incoherentBF: kit.incoherentImage, initialError: kit.initialError
        )
    }

    /// py4DSTEM `parallax.py:806` `self._stack_mean = xp.mean(self._stack_BF_shifted)`.
    ///
    /// DEVIATION (D021): numpy's float32 mean is pairwise-summed, i.e. accurate
    /// to ~1e-7; this accumulates sequentially in **Double**, which agrees with
    /// it to that level. The previous `stack.reduce(0, +)` inferred `Float` and
    /// froze at 2^24 = 16 777 216 (adding 1.0 to it rounds to nothing), so a
    /// stack of ~1-valued elements longer than that — 100 BF images of 512×512 —
    /// read as `16777216 / count` (0.645 at 26 M) and the incoherent
    /// initialisation and `initialError` were normalised by the wrong number.
    /// `package`, not private, so a test needs no full parallax run.
    package static func stackMean(_ stack: [Float]) -> Float {
        var total = 0.0
        for value in stack { total += Double(value) }
        return Float(total / Double(stack.count))
    }

    /// Rows per streamed tile: 64 MiB tiles at the READ extent, not the view's.
    /// `source` is the reader itself, whose H5 hyperslab and DM4 gather
    /// allocate each tile pre-bin before `LoadView.binned` reduces it; sizing
    /// from the binned descriptor let that transient reach bin² × 64 MiB
    /// (4 GiB at bin 8; pre-release review d1 residual, 2026-10-02). The read
    /// extent is the expression `FourDArray.scanTileRows` uses; at bin 1 it is
    /// the view's, so the rows are unchanged. No number depends on the
    /// grouping: both passes accumulate pattern by pattern in scan order.
    /// `package` so `TileReadBudgetSiblingTests` can pin it.
    package static func resolvedTileRows(
        view: LoadView, requested: Int?
    ) -> Int {
        let descriptor = view.descriptor
        if let requested { return max(1, min(descriptor.ry, requested)) }
        let readHeight = view.readDetectorCrop?.height ?? view.source.qy
        let readWidth = view.readDetectorCrop?.width ?? view.source.qx
        let rowBytes = descriptor.rx * readHeight * readWidth
            * MemoryLayout<Float>.stride
        return max(1, min(descriptor.ry, 64 * 1_024 * 1_024 / max(1, rowBytes)))
    }

    private static func checkCancellation(
        _ cancellation: AnalysisCancellationToken?
    ) throws {
        if cancellation?.isCancelled == true { throw PreprocessError.cancelled }
    }
}
