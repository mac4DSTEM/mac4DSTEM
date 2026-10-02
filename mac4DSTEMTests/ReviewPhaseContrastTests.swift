//
//  ReviewPhaseContrastTests.swift
//  Lane C (Slot 4¾ pre-release review, 2026-10-02): the ptychography seed status's rotations in one convention (b1, Gate D)
//  and the phase-contrast budget's held term (d2). Each test names the mutation that turns it red.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class ReviewPhaseContrastTests: XCTestCase {
    private let gib: UInt64 = 1_073_741_824

    private func lowOrderFit(rotationDegrees: Double) -> ParallaxAberrationFitResult {
        ParallaxAberrationFitResult(
            measuredShifts: [], fittedShifts: [], rotationRad: rotationDegrees * .pi / 180,
            c1Angstrom: -507.1, c12aAngstrom: 1.2, c12bAngstrom: -3.4,
            rmsResidualAngstrom: 0, forceTranspose: false, forcedRotationAngleDegrees: nil
        )
    }

    // MARK: - b1: one convention for the fit and the calibration

    /// Gate D (lane C report, C/gated/app-37.log): a detector rotation planted at +37° gives the app's calibration +37.10°
    /// (internal sign; Prepare shows -37.10°) and the parallax fit -37.03° (py4DSTEM's sign, = py4DSTEM's own -37.02°). The status
    /// must print the calibration as Prepare does and find the two 0.07° apart, not 74.13°. The 80° case is the owner's real cube
    /// (RQRotationConvention.swift: app -80.1°, py4DSTEM +80.0°), where HEAD printed "160.20° apart" for one branch.
    /// Mutation it catches: printing / comparing the calibrated angle in the app's sign (`Double(rad) * 180 / .pi`).
    func testTheSeedStatusComparesBothRotationsInPy4DSTEMsSign() {
        let state = AppState()
        state.phaseContrast.parallaxAberrationFit = lowOrderFit(rotationDegrees: -37.03)
        state.calibrationSession.calibration.rotationRad = Float(37.10 * Double.pi / 180)
        state.usePtychographyProbeFromParallaxFit()
        XCTAssertTrue(state.statusText.contains("fit rotation -37.03°"), state.statusText)
        XCTAssertTrue(state.statusText.contains("calibrated rotation -37.10°"), state.statusText)
        XCTAssertTrue(state.statusText.contains("0.07° apart"), state.statusText)
        XCTAssertEqual(state.ptychography.defocusAngstrom, 507.1, "defocus = -C1 whatever the rotations say")

        state.phaseContrast.parallaxAberrationFit = lowOrderFit(rotationDegrees: 80.0)
        state.calibrationSession.calibration.rotationRad = Float(-80.1 * Double.pi / 180)
        state.usePtychographyProbeFromParallaxFit()
        XCTAssertTrue(state.statusText.contains("calibrated rotation 80.10°"), state.statusText)
        XCTAssertTrue(state.statusText.contains("0.10° apart"), state.statusText)
        // A genuinely opposite branch still reads as one: calibration 180° from the fit in py4DSTEM's sign.
        state.calibrationSession.calibration.rotationRad = Float(100.0 * Double.pi / 180)   // py4DSTEM -100°, fit +80°
        state.usePtychographyProbeFromParallaxFit()
        XCTAssertTrue(state.statusText.contains("180.00° apart"), state.statusText)
    }

    // MARK: - d2: the budget counts what earlier stages hold

    /// Mutation it catches: `workingLimitBytes` ignoring `heldProductBytes`.
    func testTheWorkingLimitSubtractsWhatEarlierStagesHold() {
        XCTAssertEqual(PhaseContrastMemoryBudget.workingLimitBytes(physicalMemory: 64 * gib, residentCubeBytes: 0,
                                                                   heldProductBytes: Int(10 * gib)), Int(22 * gib))
        XCTAssertEqual(PhaseContrastMemoryBudget.workingLimitBytes(physicalMemory: 64 * gib, residentCubeBytes: Int(20 * gib),
                                                                   heldProductBytes: Int(10 * gib)), Int(2 * gib))
        XCTAssertEqual(PhaseContrastMemoryBudget.workingLimitBytes(physicalMemory: 64 * gib, residentCubeBytes: Int(20 * gib),
                                                                   heldProductBytes: Int.max), Int(gib), "the floor, no overflow")
    }

    /// A small preprocessed stack: 25 bright-field pixels (5 × 5, a four-level schedule) of a 16 × 16 padded plane.
    private func preprocessing() -> ParallaxPreprocessResult {
        let scan = 8, pad = 8, side = scan + pad, plane = side * side
        let indices = (0..<25).map { ParallaxDetectorIndex(qx: 10 + $0 / 5, qy: 10 + $0 % 5) }
        var stack = [Float](); stack.reserveCapacity(indices.count * plane)
        for (k, _) in indices.enumerated() {
            for y in 0..<side { for x in 0..<side {
                stack.append(1 + 0.2 * Float(sin(0.9 * Double(y + k % 3) + 0.4 * Double(x)) * cos(0.5 * Double(y))))
            } }
        }
        let vectors = indices.map { ParallaxVector(qx: Float($0.qx - 12) * 0.01, qy: Float($0.qy - 12) * 0.01) }
        return ParallaxPreprocessResult(
            scanHeight: scan, scanWidth: scan, detectorHeight: 25, detectorWidth: 25, stackHeight: side, stackWidth: side,
            calibration: ParallaxPhysicalCalibration(
                scanSamplingAngstrom: 1, reciprocalSamplingInvAngstrom: 0.01, energyEV: 80_000, wavelengthAngstrom: 0.0418,
                originQX: 12, originQY: 12, rotationRad: 0, transpose: false),
            thresholdIntensity: 0.8, detectorMask: [Bool](repeating: true, count: 25 * 25), detectorIndices: indices,
            reciprocalVectors: vectors, probeAnglesMrad: vectors,
            edgeWindow: [Float](repeating: 1, count: scan * scan), normalizedStack: stack, unshiftedStack: stack,
            incoherentBF: Array(stack[0..<plane]), initialError: 0)
    }

    private func refusedBytes(_ body: () throws -> ParallaxAlignmentResult) -> Int? {
        do { _ = try body(); return nil } catch ParallaxAligner.AlignmentError.memoryLimit(let bytes, _) { return bytes } catch {
            XCTFail("unexpected \(error)"); return nil
        }
    }

    /// Level 2+ reads the prior level's stack AND masks, both alive while the new pair is built: 4S + fft, not 3S + fft. At
    /// exactly HEAD's passing threshold (3S + fft) level 2 must refuse; level 1 (the preprocessed stack is its only input) is
    /// unchanged. Mutation it catches: `inputBytesCounted` returning the preprocessed stack for every level (HEAD's 3S).
    func testAlignmentLevelTwoCountsThePriorItReads() throws {
        let pre = preprocessing()
        let s = pre.stackByteCount, fft = pre.stackHeight * pre.stackWidth * MemoryLayout<Float>.stride * 12
        XCTAssertGreaterThanOrEqual(ParallaxAligner.defaultBinSchedule(detectorIndices: pre.detectorIndices).count, 2)
        var options = ParallaxAlignmentOptions()
        options.maxWorkingBytes = 3 * s + fft
        let level1 = try ParallaxAligner.alignNextLevel(preprocessing: pre, options: options)
        XCTAssertEqual(ParallaxAligner.inputBytesCounted(preprocessing: pre, previous: nil), s)
        XCTAssertEqual(ParallaxAligner.inputBytesCounted(preprocessing: pre, previous: level1), 2 * s)
        XCTAssertEqual(refusedBytes { try ParallaxAligner.alignNextLevel(preprocessing: pre, previous: level1, options: options) },
                       4 * s + fft)
        options.maxWorkingBytes = 4 * s + fft
        XCTAssertNoThrow(try ParallaxAligner.alignNextLevel(preprocessing: pre, previous: level1, options: options))
    }

    /// What the app subtracts plus what the level counts is everything alive during level 2, counted once: the preprocessed
    /// pair, the whole prior level, the new pair and the FFT work. Mutation it catches: `parallaxAlignmentHeldBytes` subtracting
    /// nothing (the level's input counted twice), or `phaseContrastHeldBytes` dropping either product.
    func testTheAppCountsEveryHeldStackOnceDuringAlignment() throws {
        let pre = preprocessing()
        let s = pre.stackByteCount, fft = pre.stackHeight * pre.stackWidth * MemoryLayout<Float>.stride * 12
        let level1 = try ParallaxAligner.alignNextLevel(preprocessing: pre)
        let state = AppState()
        XCTAssertFalse(state.residency.isResident, "the premise: a streamed cube")
        XCTAssertEqual(state.phaseContrastHeldBytes, 0)
        state.phaseContrast.parallaxPreprocess = pre
        XCTAssertEqual(state.phaseContrastHeldBytes, 2 * s)
        XCTAssertEqual(state.parallaxAlignmentHeldBytes, s, "level 1 reads the blended stack; the unshifted one is held")
        state.phaseContrast.parallaxAlignment = level1
        XCTAssertEqual(state.phaseContrastHeldBytes, 2 * s + level1.heldByteCount)
        let half = Int(min(ProcessInfo.processInfo.physicalMemory / 2, UInt64(Int.max)))
        XCTAssertEqual(state.phaseContrastWorkingLimitBytes,
                       max(PhaseContrastMemoryBudget.floorBytes, half - (2 * s + level1.heldByteCount)))
        var tiny = ParallaxAlignmentOptions(); tiny.maxWorkingBytes = 1
        let peak = try XCTUnwrap(refusedBytes {
            try ParallaxAligner.alignNextLevel(preprocessing: pre, previous: level1, options: tiny) })
        XCTAssertEqual(state.parallaxAlignmentHeldBytes + peak, 2 * s + level1.heldByteCount + 2 * s + fft)
    }

    // MARK: - Fix round: a re-preview is not charged for the products it replaces

    /// A re-preview with a preview and an alignment held gets the whole limit (half of RAM, streamed cube), not half − (2S + the
    /// level): without the release a stack that passed once was refused on every second preview once S > half/6. Mutation it
    /// catches: reading the limit before releasing (`let limit = phaseContrastWorkingLimitBytes` first).
    func testARePreviewIsNotChargedForTheProductsItReplaces() throws {
        let pre = preprocessing()
        let level1 = try ParallaxAligner.alignNextLevel(preprocessing: pre)
        let state = AppState()
        XCTAssertFalse(state.residency.isResident, "the premise: a streamed cube")
        state.phaseContrast.parallaxPreprocess = pre
        state.phaseContrast.parallaxAlignment = level1
        let half = Int(min(ProcessInfo.processInfo.physicalMemory / 2, UInt64(Int.max)))
        XCTAssertLessThan(state.phaseContrastWorkingLimitBytes, half, "the premise: the held products reduce the limit")
        let release = state.releaseParallaxProductsForPreview()
        XCTAssertEqual(release.limitBytes, max(PhaseContrastMemoryBudget.floorBytes, half))
        XCTAssertTrue(release.releasedPreview)
        XCTAssertEqual(state.phaseContrastHeldBytes, 0)
        XCTAssertFalse(state.releaseParallaxProductsForPreview().releasedPreview, "nothing left to release")
    }

    /// A source whose patterns are all zero: the preview's run fails on "no positive finite signal", after the release.
    private actor ZeroSource: FourDDataSource {
        nonisolated func loadPushdown(for view: LoadView) -> LoadPushdown { .none }
        func discoverPrimaryDataset() throws -> DatasetDescriptor { DemoFourDDataSource.descriptor }
        func readPattern(_ view: LoadView, ry: Int, rx: Int) throws -> [Float] {
            [Float](repeating: 0, count: view.descriptor.qy * view.descriptor.qx)
        }
        func readScanRow(_ view: LoadView, ry: Int) throws -> [Float] {
            [Float](repeating: 0, count: view.descriptor.rx * view.descriptor.qy * view.descriptor.qx)
        }
        func readScanTile(_ view: LoadView, yRange: Range<Int>) throws -> FourDScanTile {
            FourDScanTile(
                yRange: yRange, scanWidth: view.descriptor.rx,
                detectorHeight: view.descriptor.qy, detectorWidth: view.descriptor.qx,
                pixels: [Float](repeating: 0, count: yRange.count * view.descriptor.rx
                                * view.descriptor.qy * view.descriptor.qx))
        }
        func readDoubleAttribute(_ name: String, onObjectPath path: String) -> Double? { nil }
        func pixelCalibration() -> PixelCalibration? {
            PixelCalibration(rSize: 0.5, rUnits: "nm", qSize: 0.02, qUnits: "A^-1", qrFlip: false)
        }
    }

    /// The app's own preview releases the old products before its run: a re-preview that fails after the physical calibration
    /// resolved leaves nothing held. Mutation it catches: `prepareParallaxPreview` not calling the release (HEAD's
    /// `maxStackBytes = phaseContrastWorkingLimitBytes` with the old products alive).
    func testPrepareParallaxPreviewReleasesTheOldProductsBeforeItsRun() async throws {
        let suite = "mac4dstem.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let state = AppState(sessionSidecar: SessionSidecarLocator(defaults: defaults))
        let load = state.beginDatasetLoading("Opening…")
        await state.activate(descriptor: DemoFourDDataSource.descriptor, reader: ZeroSource(), runInitialAnalysis: false)
        state.finishDatasetLoading(owner: load)
        state.calibrationSession.calibration.originProvenance = .fitted
        state.calibrationSession.calibration.rotationRad = 0
        state.calibrationSession.acceleratingVoltage = 300
        XCTAssertNoThrow(try ParallaxPhysicalCalibration.resolve(
            calibration: state.calibrationSession.calibration, apertureCenterX: state.aperture.centerX,
            apertureCenterY: state.aperture.centerY, acceleratingVoltageKV: 300), "the premise: the run starts")
        let pre = preprocessing()
        state.phaseContrast.parallaxPreprocess = pre
        state.phaseContrast.parallaxAlignment = try ParallaxAligner.alignNextLevel(preprocessing: pre)
        await state.prepareParallaxPreview()
        XCTAssertTrue(state.statusText.contains("no positive finite signal"), "the run started and failed: \(state.statusText)")
        XCTAssertNil(state.phaseContrast.parallaxPreprocess)
        XCTAssertNil(state.phaseContrast.parallaxAlignment)
        XCTAssertEqual(state.phaseContrastHeldBytes, 0)
    }

    /// Mutation it catches: the refusal text naming only a resident cube (HEAD's guard `residentCubeBytes > 0`).
    func testTheRefusalNamesTheHeldStacks() {
        let error = ParallaxAligner.AlignmentError.memoryLimit(bytes: 5_000_000_000, limit: 1_073_741_824)
        let plain = PhaseContrastMemoryBudget.refusalMessage(error, residentCubeBytes: 0)
        let held = PhaseContrastMemoryBudget.refusalMessage(error, residentCubeBytes: 0, heldProductBytes: 2_600_000_000)
        XCTAssertTrue(held.hasPrefix(plain))
        // The size is ByteCountFormatter's, in the test host's locale ("2.6 GB" or "2,6 GB"): asserted around, not on.
        XCTAssertTrue(held.contains("half of RAM less the "), held)
        XCTAssertTrue(held.contains(" the parallax preview and alignment already hold."), held)
        let both = PhaseContrastMemoryBudget.refusalMessage(error, residentCubeBytes: 28_600_000_000, heldProductBytes: 2_600_000_000)
        XCTAssertTrue(both.contains("cube kept in memory and the "), both)
    }
}
