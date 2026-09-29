//
//  SessionReplayAppStateTests.swift
//  Pins the CALL SITES of v2 S5 — the half the file-level tests cannot see.
//  Gate B-lite F8 measured that every S5 wiring line could be deleted with
//  the suite staying green, the exact gap S1's locator tests once had; these
//  tests reach the wiring through a real AppState on the demo fixture.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class SessionReplayAppStateTests: XCTestCase {

    func testReopenReadsTheSourceAndAppliesTheSidecarSpecificationBeforeRecipeAdoption() async throws {
        let suite = "mac4dstem.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let locator = SessionSidecarLocator(defaults: defaults)
        let source = DemoFourDDataSource()
        let descriptor = try await source.discoverPrimaryDataset()
        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionReplayReopen-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDirectory) }
        let sidecar = workDirectory.appendingPathComponent("demo.mac4dstem.h5")
        locator.adopt(sidecar, for: descriptor)

        var specification = LoadSpecification.fullExtent
        specification.scanCrop = AxisCrop(yOffset: 2, xOffset: 3, height: 6, width: 6)
        specification.detectorBin = 2
        var record = SessionReplayRecord()
        record.record(kind: "virtual_detector",
                      parameters: ["shape": "Circle", "center_x": "16", "center_y": "16",
                                   "inner": "0", "outer": "6"],
                      at: Date(timeIntervalSince1970: 1))
        try BraggVectorEMDWriter.mergeCalibration(
            PixelCalibration(), qWidth: descriptor.qx, qHeight: descriptor.qy,
            to: sidecar, loadSpecification: specification, replayRecord: record
        )

        let state = AppState(sessionSidecar: locator)
        let restoredValue = await state.recordedLoadSpecification(
            forSourcePath: descriptor.filePath, source: descriptor
        )
        let restored = try XCTUnwrap(restoredValue)
        let load = state.beginDatasetLoading("Reopening source…")
        await state.activate(descriptor: descriptor, reader: source,
                             specification: restored, runInitialAnalysis: false)
        state.finishDatasetLoading(owner: load)

        XCTAssertEqual(state.datasetSession.loadView?.source.filePath, descriptor.filePath,
                       "Reopen must read the source descriptor, never a reduced derived cube")
        XCTAssertEqual(state.loadedView.specification, specification,
                       "The sidecar specification is applied to the source before restore")
        XCTAssertEqual(state.replay.record, record)
        XCTAssertEqual(state.replay.parameterFrame, ReplayParameterFrame.of(specification),
                       "Recipe adoption must name the sidecar specification's detector frame")
    }

    func testTheAutomaticPassOnOpenRecordsNothing() async {
        // Opening runs the initial virtual-detector pass with DEFAULT
        // parameters. Recording it would let merely opening a colleague's
        // file overwrite their recorded aperture with defaults on the next
        // save (Gate B-lite F1) — the load-in-flight guard suppresses it.
        let state = AppState()
        await state.openDemoFixture()
        XCTAssertNotNil(state.resultPresentation.resultImage,
                        "The initial analysis must have run for this test to mean anything")
        XCTAssertTrue(state.replay.record.isEmpty,
                      "Merely opening a file must never mutate its recipe")
    }

    func testAnExplicitRunRecordsTheSessionsOwnParameters() async {
        let state = AppState()
        await state.openDemoFixture()
        state.aperture.inner = 3
        state.aperture.outer = 9
        await state.runVirtualDetector()
        XCTAssertEqual(state.replay.record.steps.map(\.kind), ["virtual_detector"])
        let step = state.replay.record.steps.first
        XCTAssertEqual(step?.parameters["inner"], "3.0",
                       "The step must carry the aperture the run actually used")
        XCTAssertEqual(step?.parameters["outer"], "9.0")
    }

    func testACalibrationSaveCarriesTheRecipeIntoTheSidecar() async throws {
        // End-to-end through the app's own save path: the wiring line in
        // ResultExport that threads `replay.recordForSaving` is exactly the
        // kind of defaulted argument whose deletion no writer-level test can
        // see (F8).
        //
        // A suite-private bookmark store (v2 S7): this save persists a grant
        // keyed by the demo's constant path, and through the shared
        // `UserDefaults` it leaked the sidecar — recipe and all — into every
        // concurrently running demo-opening test (`AppState.init`'s note).
        let suite = "mac4dstem.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let state = AppState(sessionSidecar: SessionSidecarLocator(defaults: defaults))
        await state.openDemoFixture()
        await state.runVirtualDetector()
        XCTAssertFalse(state.replay.record.isEmpty)

        let descriptor = try XCTUnwrap(state.descriptor)
        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionReplayAppStateTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDirectory,
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDirectory) }
        let url = workDirectory.appendingPathComponent("demo.mac4dstem.h5")
        // Pre-adopting the grant is what keeps the save panel out of a test.
        state.sessionSidecar.adopt(url, for: descriptor)

        state.setManualQPixelUnits("nm⁻¹")
        state.setManualQPixelSize(0.25)
        state.saveCalibrationToSessionSidecar()
        // Wait for the app's OWN follow-up inventory read to publish, not
        // merely for the file to exist: the bundled HDF5 is Threadsafety: OFF
        // (the standing concurrent-use crash in docs/open-items.md), so this
        // test reading the file while the app's detached inventory task still
        // has it open is exactly that crash — it fired here once, in the full
        // suite's timing. `sessionInventory.hasCalibration` flips only after
        // the app's reader is done with the file.
        for _ in 0..<100 where !state.sessionInventory.hasCalibration {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(state.sessionInventory.hasCalibration,
                      "The calibration save never completed")

        let snapshot = try BraggVectorEMDWriter.loadSession(from: url)
        XCTAssertEqual(snapshot.replayRecord?.steps.map(\.kind), ["virtual_detector"],
                       "The session's recipe must travel with the calibration save")

        let restored = AppState(sessionSidecar: SessionSidecarLocator(defaults: defaults))
        await restored.openDemoFixture()
        XCTAssertEqual(restored.manualQPixelSize, 0.25)
        XCTAssertEqual(restored.manualQPixelUnits, "nm⁻¹")
        let qItem = try XCTUnwrap(restored.calibrationSession.readiness.items.first { $0.kind == .qScale })
        XCTAssertEqual(qItem.status, .ready(.sessionSidecar),
                       "The test must exercise restoration, not the demo's file calibration")
        XCTAssertTrue(PrepareSettings.shouldShowManualScaleEditor(for: qItem.kind, status: qItem.status),
                      "A saved manual scale must remain editable after reopening")
        restored.setManualQPixelSize(0.5)
        XCTAssertEqual(restored.manualQPixelSize, 0.5)
        XCTAssertEqual(restored.calibrationSession.provenance.qScale, .manual)
    }

    // MARK: - L4: rewind (ADR 047 R4) — Gate D
    //
    // Pre-registered in the session scratchpad (l4/prereg.md) BEFORE the code:
    // detect d1 -> strain M1; re-detect with one changed setting d2 -> strain M2;
    // rewind to d1; the controls equal d1's, no node or product is deleted, M2
    // reads stale; Run -> the new strain map is BIT-IDENTICAL to M1. Refuted by:
    // any bit of the re-run map differing, any field of the restored parameters
    // differing, any node lost, M2 reading current, strain running on d2's peaks.

    /// A 4x4 scan crop from the demo's top-left corner: every position shares one
    /// lattice angle (the demo rotates it per 4x4 block), so a whole-scan strain
    /// reference is well posed. Scan crop only — the detector frame stays identity.
    private var uniformLatticeCrop: LoadSpecification {
        var spec = LoadSpecification()
        spec.scanCrop = AxisCrop(yOffset: 0, xOffset: 0, height: 4, width: 4)
        return spec
    }

    private func activeID(_ state: AppState, _ kind: String) -> String? {
        state.replay.lineage.activeNodes().first { $0.kind == kind }?.id
    }

    /// Every number the strain run produced, as bit patterns (NaN payloads and
    /// signed zeros included) — the bit-identical claim is about these.
    private func strainBits(_ state: AppState, _ context: String) throws -> [UInt32] {
        let map = try XCTUnwrap(state.strain.map, "strain did not publish (\(context)): \(state.statusText)")
        return [map.exx, map.eyy, map.exy, map.theta, map.localResidualPixels].flatMap { $0.map(\.bitPattern) }
            + map.mask.map { $0 ? 1 : 0 }
            + [UInt32(map.indexedFraction.bitPattern)]
    }

    private struct RewindScenario {
        let state: AppState
        let p1: DiskDetectionParams
        let m1Bits: [UInt32]
        let disks1: String
        let strain1: String
        let disks2: String
        let strain2: String
        let nodesBeforeRewind: [SessionLineage.Node]
    }

    /// d1 -> M1, then d2 (sigma_cc + 1) -> M2, with the precondition that M2 != M1.
    private func runTwoBranches() async throws -> RewindScenario {
        let state = AppState()
        await state.openDemoFixture(specification: uniformLatticeCrop)
        state.navigation.analysisMode = .disks
        await state.runDiskDetection()
        XCTAssertNotNil(state.resultPresentation.braggVectors, "first detection published nothing: \(state.statusText)")
        let p1 = state.diskDetection.diskParams
        let disks1 = try XCTUnwrap(activeID(state, "disk_detection"))
        state.navigation.analysisMode = .strain
        let first = await state.runStrainMapping()
        XCTAssertEqual(first, .published, state.statusText)
        let m1Bits = try strainBits(state, "first run")
        let strain1 = try XCTUnwrap(activeID(state, "strain"))

        state.navigation.analysisMode = .disks
        state.diskDetection.diskParams.sigmaCC = p1.sigmaCC + 1
        await state.runDiskDetection()
        let disks2 = try XCTUnwrap(activeID(state, "disk_detection"))
        XCTAssertNotEqual(disks2, disks1, "one settings change after a strain map is a new branch, not a collapse")
        state.navigation.analysisMode = .strain
        let second = await state.runStrainMapping()
        XCTAssertEqual(second, .published, state.statusText)
        let strain2 = try XCTUnwrap(activeID(state, "strain"))
        XCTAssertNotEqual(try strainBits(state, "second run"), m1Bits,
                          "precondition: the changed setting must move the strain map, or this test proves nothing")
        return RewindScenario(state: state, p1: p1, m1Bits: m1Bits, disks1: disks1, strain1: strain1,
                              disks2: disks2, strain2: strain2,
                              nodesBeforeRewind: state.replay.lineage.nodes)
    }

    /// THE Gate D experiment. Mutations it catches (each was applied and seen red):
    /// restoring nothing, or all but one key, of the detection parameters (the
    /// re-run map differs — see the companion test); a rewind that deletes or
    /// re-records a node; `recordedReplayStep` ignoring the superseded producer
    /// (M2 or the peaks would read current, and strain would run on d2's peaks).
    func testRewindThenRunReproducesTheFirstStrainMapBitForBit() async throws {
        let s = try await runTwoBranches()
        let state = s.state
        XCTAssertEqual(state.displayedProduct?.provenance["lineage_step"], s.strain2,
                       "the product on screen names the run that made it (R2)")

        let refusal = await state.rewindLineage(to: s.disks1)
        XCTAssertNil(refusal)

        // The controls are d1's, field for field.
        XCTAssertEqual(state.diskDetection.diskParams, s.p1)
        // Nothing was added, edited or deleted: same nodes, and the products stay in memory.
        XCTAssertEqual(state.replay.lineage.nodes, s.nodesBeforeRewind, "node count and every node unchanged")
        XCTAssertNotNil(state.strain.map)
        XCTAssertNotNil(state.resultPresentation.braggVectors)
        // The active path is d1's ancestry plus the strain built on it.
        let active = state.replay.lineage.activeNodes().map(\.id)
        XCTAssertTrue(active.contains(s.disks1) && active.contains(s.strain1), "\(active)")
        XCTAssertFalse(active.contains(s.disks2) || active.contains(s.strain2), "\(active)")
        XCTAssertEqual(state.replay.record.steps.first { $0.kind == "disk_detection" }?.parameters["sigma_cc"],
                       String(s.p1.sigmaCC), "the recipe follows the rewound path")

        // Products off the path read stale, with the existing sentence.
        let disks = ProductWorkflow.productState(
            for: .disks, hasProduct: true,
            recordedStep: state.recordedReplayStep(for: .disks),
            currentSignature: state.currentReplaySignature(for: .disks))
        XCTAssertTrue(disks.staleReason?.contains("Computed with different") == true
                      && disks.staleReason?.contains("sigma_cc") == true, "\(disks)")
        let strainState = ProductWorkflow.productState(
            for: .strain, hasProduct: true,
            recordedStep: state.recordedReplayStep(for: .strain),
            currentSignature: state.currentReplaySignature(for: .strain))
        XCTAssertNotNil(strainState.staleReason, "M2 came from a run that is off the path: \(strainState)")
        // ...and the strain run refuses to build on peaks from the run that left the path.
        let blocked = await state.runStrainMapping()
        guard case .failed(let why) = blocked else { return XCTFail("strain ran on d2's peaks: \(blocked)") }
        XCTAssertTrue(why.contains("Detection settings changed"),
                      "it must refuse BECAUSE the peaks are not the restored settings', not for some other reason: \(why)")
        // The graph says so too.
        let product = state.displayedProduct
        let model = LineageGraphModel(
            lineage: state.replay.lineage, productKind: product?.kind,
            productStep: product?.provenance["lineage_step"], producedSteps: state.replay.producedStep)
        XCTAssertEqual(model.state(of: s.disks2), .branch)
        XCTAssertEqual(model.state(of: s.strain1), .stale)
        XCTAssertEqual(model.state(of: s.disks1), .stale)

        // Run: detect with the restored controls, then strain.
        state.navigation.analysisMode = .disks
        await state.runDiskDetection()
        state.navigation.analysisMode = .strain
        let rerun = await state.runStrainMapping()
        XCTAssertEqual(rerun, .published, state.statusText)
        XCTAssertEqual(try strainBits(state, "after rewind"), s.m1Bits,
                       "the strain map after a rewind and a Run is bit-identical to the first one")
        XCTAssertEqual(state.replay.lineage.nodes.count, s.nodesBeforeRewind.count + 2,
                       "Run branches: a new detection and a new strain node")
        XCTAssertEqual(state.displayedProduct?.provenance["lineage_step"], activeID(state, "strain"))
    }

    /// The mutation for the test above, applied to the scenario: ONE restored
    /// key wrong (what a restore that dropped a key would leave) and the re-run
    /// map is no longer M1 — the bit comparison discriminates a one-key error.
    func testOneWronglyRestoredKeyDoesNotReproduceTheFirstMap() async throws {
        let s = try await runTwoBranches()
        let state = s.state
        let refusal = await state.rewindLineage(to: s.disks1)
        XCTAssertNil(refusal)
        // The perturbed key: neither d1's value nor d2's (p1 + 1), so it cannot
        // coincide with the other branch.
        state.diskDetection.diskParams.sigmaCC = s.p1.sigmaCC + 0.5
        state.navigation.analysisMode = .disks
        await state.runDiskDetection()
        state.navigation.analysisMode = .strain
        await state.runStrainMapping()
        XCTAssertNotEqual(try strainBits(state, "perturbed"), s.m1Bits)
    }

    /// Rewinding back is always possible: nothing was deleted. Mutation it
    /// catches: a rewind that prunes the branch it leaves.
    func testRewindingBackAndForthLosesNothing() async throws {
        let s = try await runTwoBranches()
        let state = s.state
        var refusal = await state.rewindLineage(to: s.disks1)
        XCTAssertNil(refusal)
        refusal = await state.rewindLineage(to: s.strain2)
        XCTAssertNil(refusal)
        XCTAssertEqual(state.replay.lineage.nodes, s.nodesBeforeRewind)
        XCTAssertFalse(state.replay.lineage.isRewound, "back on the fold's own path: no pin")
        XCTAssertEqual(state.diskDetection.diskParams.sigmaCC, s.p1.sigmaCC + 1,
                       "the second branch's detection settings came back")
    }

    /// A run recorded before lineage is refused by name and nothing changes.
    /// Mutation it catches: a v1 rewind that proceeds on an ancestry the file never wrote.
    func testAV1RunRefusesRewindByName() async {
        let state = AppState()
        await state.openDemoFixture(specification: uniformLatticeCrop)
        var record = SessionReplayRecord()
        record.record(kind: "disk_detection",
                      parameters: ["corr_power": "1.0", "sigma_dp": "0.0", "sigma_cc": "2.0", "subpixel": "poly",
                                   "upsample_factor": "16", "min_absolute_intensity": "0.0",
                                   "min_relative_intensity": "0.005", "relative_to_peak": "0",
                                   "min_peak_spacing": "5.0", "edge_boundary": "4", "max_peaks": "70",
                                   "kernel_source": "synthetic"])
        state.replay.adopt(record, recordedOn: .detectorIdentity)
        let before = state.replay.lineage
        let params = state.diskDetection.diskParams
        let refusal = await state.rewindLineage(to: "s1")
        XCTAssertTrue(refusal?.contains("s1") == true && refusal?.contains("before lineage") == true,
                      refusal ?? "no refusal")
        XCTAssertEqual(state.replay.lineage, before)
        XCTAssertEqual(state.diskDetection.diskParams, params, "a refused rewind writes no control")
    }

    // MARK: - L4 refuter fixes: what a rewind restores

    /// A demo session with a synthetic kernel and no detection run, for scenarios
    /// whose nodes are recorded by hand (a rewind reads nodes, not pixels).
    private func handSession() async throws -> (state: AppState, kernel: ProbeKernel) {
        let state = AppState()
        await state.openDemoFixture(specification: uniformLatticeCrop)
        await state.generateProbeKernel()
        let kernel = try XCTUnwrap(state.probeKernel, "no synthetic kernel: \(state.statusText)")
        return (state, kernel)
    }

    private func detectionRecord(_ p: DiskDetectionParams, kernel: ProbeKernel,
                                 detector: [String: String] = ["detector_class": "classical"]) -> [String: String] {
        p.replayParameters(kernel: kernel).merging(detector) { _, new in new }
    }

    @discardableResult
    private func handRecord(_ state: AppState, _ kind: String, _ parameters: [String: String]) -> String {
        state.replay.record(kind: kind, parameters: parameters, under: .detectorIdentity)
    }

    private let consensusStrain = ["reference_mode": "whole-scan", "basis_mode": "consensus",
                                   "resolved_g1_x": "10.0", "resolved_g1_y": "0.0",
                                   "resolved_g2_x": "0.0", "resolved_g2_y": "10.0"]

    /// d2 differs from d1 in ALL twelve detection parameters and in the detector
    /// class; after the rewind every field and the class are d1's. Mutation it
    /// catches (applied, seen red): restore only sigma_cc — the equality on the
    /// whole struct names the first field that was left behind.
    func testRewindRestoresAllTwelveDetectionParametersAndTheDetectorClass() async throws {
        let (state, kernel) = try await handSession()
        var p1 = DiskDetectionParams(corrPower: 0.5, sigmaDP: 1, sigmaCC: 3, subpixel: .poly, upsampleFactor: 8,
                                     minAbsoluteIntensity: 0.1, minRelativeIntensity: 0.01, relativeToPeak: 1,
                                     minPeakSpacing: 7, edgeBoundary: 5, maxNumPeaks: 30)
        p1.relativeReferenceMinimumRadiusPx = 3
        var p2 = DiskDetectionParams(corrPower: 0.9, sigmaDP: 2, sigmaCC: 4, subpixel: .multicorr, upsampleFactor: 32,
                                     minAbsoluteIntensity: 0.2, minRelativeIntensity: 0.02, relativeToPeak: 2,
                                     minPeakSpacing: 9, edgeBoundary: 6, maxNumPeaks: 40)
        p2.relativeReferenceMinimumRadiusPx = 4
        XCTAssertNotEqual(p1.corrPower, p2.corrPower); XCTAssertNotEqual(p1.sigmaDP, p2.sigmaDP)
        XCTAssertNotEqual(p1.sigmaCC, p2.sigmaCC); XCTAssertNotEqual(p1.subpixel, p2.subpixel)
        XCTAssertNotEqual(p1.upsampleFactor, p2.upsampleFactor)
        XCTAssertNotEqual(p1.minAbsoluteIntensity, p2.minAbsoluteIntensity)
        XCTAssertNotEqual(p1.minRelativeIntensity, p2.minRelativeIntensity)
        XCTAssertNotEqual(p1.relativeToPeak, p2.relativeToPeak)
        XCTAssertNotEqual(p1.relativeReferenceMinimumRadiusPx, p2.relativeReferenceMinimumRadiusPx)
        XCTAssertNotEqual(p1.minPeakSpacing, p2.minPeakSpacing)
        XCTAssertNotEqual(p1.edgeBoundary, p2.edgeBoundary)
        XCTAssertNotEqual(p1.maxNumPeaks, p2.maxNumPeaks)

        let d1 = handRecord(state, "disk_detection", detectionRecord(p1, kernel: kernel))
        handRecord(state, "strain", consensusStrain)
        let d2 = handRecord(state, "disk_detection", detectionRecord(p2, kernel: kernel, detector: [
            "detector_class": "learned", "learned_threshold": "0.5", "learned_model_sha256": "abc"]))
        XCTAssertNotEqual(d1, d2)
        state.diskDetection.diskParams = p2
        state.learnedDetection.detectorClass = .learned

        let refusal = await state.rewindLineage(to: d1)
        XCTAssertNil(refusal)
        XCTAssertEqual(state.diskDetection.diskParams, p1, "every one of the twelve fields is d1's")
        XCTAssertEqual(state.learnedDetection.detectorClass, .classical, "and so is the detector class")
    }

    /// The refuter's scenario: an ellipse and a virtual image made BEFORE d1 stay
    /// on the path, s1 (which consumed the ellipse) returns, and the next strain
    /// run records the ellipse edge. Mutation it catches: the old plan that took
    /// every kind outside d1's ancestry off the path.
    func testACalibrationMadeBeforeTheRewoundRunStaysAndTheNextStrainRecordsItsEdge() async throws {
        let (state, kernel) = try await handSession()
        state.calibrationSession.calibration.ellipseA = 12
        state.calibrationSession.calibration.ellipseB = 10
        state.calibrationSession.calibration.ellipseTheta = 0.3
        state.calibrationSession.provenance.ellipse = .measuredInApp
        state.recordEllipseCalibrationRun()
        let e1 = try XCTUnwrap(activeID(state, "calibration_ellipse"))
        let v = handRecord(state, "virtual_detector",
                           Aperture.replayParameters(shape: "Circle", aperture: state.aperture))
        let p1 = state.diskDetection.diskParams
        var p2 = p1; p2.sigmaCC += 1
        let d1 = handRecord(state, "disk_detection", detectionRecord(p1, kernel: kernel))
        let s1 = handRecord(state, "strain", consensusStrain)
        XCTAssertTrue(state.replay.lineage.node(id: s1)?.inputs?.contains { $0.step == e1 } == true, "precondition")
        state.diskDetection.diskParams = p2
        let d2 = handRecord(state, "disk_detection", detectionRecord(p2, kernel: kernel))
        let s2 = handRecord(state, "strain", consensusStrain)

        let refusal = await state.rewindLineage(to: d1)
        XCTAssertNil(refusal)
        let active = state.replay.lineage.activeNodes().map(\.id)
        for kept in [e1, v, d1, s1] { XCTAssertTrue(active.contains(kept), "\(kept) stays or returns: \(active)") }
        XCTAssertFalse(active.contains(d2) || active.contains(s2), "d2 and s2 leave: \(active)")
        XCTAssertEqual(state.calibrationSession.calibration.ellipseA, 12, "the live ellipse was not touched")
        XCTAssertEqual(state.diskDetection.diskParams, p1)

        let next = handRecord(state, "strain", consensusStrain)
        XCTAssertNotEqual(next, s1, "a run after a rewind branches; it does not overwrite the run rewound to")
        XCTAssertTrue(state.replay.lineage.node(id: next)?.inputs?.contains {
            $0.step == e1 && $0.role == "calibration" } == true,
                      "the ellipse the app applies is an input of the run that used it")
    }

    /// The probe kernel is a detection parameter. d1 ran with the synthetic kernel; a
    /// measured one is loaded when the user rewinds; after the rewind the synthetic
    /// kernel is back and the next Detect records d1's kernel. Mutation it catches
    /// (applied, seen red): a rewind that leaves the kernel alone.
    func testRewindAcrossAKernelChangeRebuildsTheSyntheticKernel() async throws {
        let (state, kernel) = try await handSession()
        let p1 = state.diskDetection.diskParams
        let d1 = handRecord(state, "disk_detection", detectionRecord(p1, kernel: kernel))
        handRecord(state, "strain", consensusStrain)
        var p2 = p1; p2.sigmaCC += 1
        handRecord(state, "disk_detection", detectionRecord(p2, kernel: kernel))
        // A measured kernel replaces it.
        let descriptor = try XCTUnwrap(state.descriptor)
        var pixels = [Float](repeating: 0.05, count: descriptor.qy * descriptor.qx)
        for y in 0..<descriptor.qy { for x in 0..<descriptor.qx
            where hypot(Float(x) - 32, Float(y) - 32) < 5 { pixels[y * descriptor.qx + x] = 1 } }
        state.probeKernel = try XCTUnwrap(ProbeKernel.measured(
            pattern: DiffractionPattern(qy: descriptor.qy, qx: descriptor.qx, pixels: pixels),
            originX: 32, originY: 32, radius: 4.5))
        XCTAssertEqual(state.probeKernel?.source, .measured, "precondition")

        let refusal = await state.rewindLineage(to: d1)
        XCTAssertNil(refusal, refusal ?? "")
        XCTAssertEqual(state.probeKernel?.source, .synthetic, "the recorded kernel is back")

        state.navigation.analysisMode = .disks
        await state.runDiskDetection()
        let newest = try XCTUnwrap(state.replay.lineage.nodes.last { $0.kind == "disk_detection" })
        XCTAssertEqual(newest.parameters["kernel_source"], "synthetic")
        XCTAssertEqual(newest.parameters["kernel_source"], state.replay.lineage.node(id: d1)?.parameters["kernel_source"])
        XCTAssertEqual(newest.parameters["kernel_mode"], state.replay.lineage.node(id: d1)?.parameters["kernel_mode"])
    }

    /// A kernel measured from a vacuum ROI is stored nowhere: the rewind refuses,
    /// in a rewind's words, and changes nothing. Mutation it catches: proceed, or
    /// borrow ReplayPlanner's "on the promoted view".
    func testARewindToAMeasuredRoiKernelRefusesByName() async throws {
        let (state, kernel) = try await handSession()
        let p1 = state.diskDetection.diskParams
        var measured = detectionRecord(p1, kernel: kernel)
        measured["kernel_source"] = "measured_roi"
        let d1 = handRecord(state, "disk_detection", measured)
        handRecord(state, "strain", consensusStrain)
        var p2 = p1; p2.sigmaCC += 1
        handRecord(state, "disk_detection", detectionRecord(p2, kernel: kernel))
        state.diskDetection.diskParams = p2
        let lineage = state.replay.lineage
        let refusal = await state.rewindLineage(to: d1)
        let text = try XCTUnwrap(refusal)
        XCTAssertTrue(text.contains("kernel") && text.contains("vacuum"), text)
        XCTAssertFalse(text.contains("promoted view"), "that is replay's wording, not a rewind's: \(text)")
        XCTAssertEqual(state.replay.lineage, lineage)
        XCTAssertEqual(state.diskDetection.diskParams, p2, "a refused rewind writes no control")
    }

    /// The refuter's 1b: manual-basis strains s1 (g_A) and s2 (g_B) on different
    /// detections; rewinding to d1 brings s1 back with ITS basis, so the next Run
    /// computes with g_A and reproduces M1. Mutation it catches (applied, seen red):
    /// restore only the ancestry and the target — the controls stay at g_B.
    func testRewindRestoresTheBasisOfTheStrainItBringsBack() async throws {
        let state = AppState()
        await state.openDemoFixture(specification: uniformLatticeCrop)
        state.navigation.analysisMode = .disks
        await state.runDiskDetection()
        let p1 = state.diskDetection.diskParams
        let d1 = try XCTUnwrap(activeID(state, "disk_detection"))
        state.navigation.analysisMode = .strain
        let automatic = await state.runStrainMapping()
        XCTAssertEqual(automatic, .published, state.statusText)
        let found = try XCTUnwrap(state.strain.map).refG1
        // g_A: a manual basis a hair off the lattice found, so that "the basis
        // it indexed with" and "the lattice it found" are different numbers.
        let gA = (g1x: found.x + 0.05, g1y: found.y, g2x: state.strain.g2X, g2y: state.strain.g2Y)
        state.strain.basisMode = .manual
        state.strain.g1X = gA.g1x; state.strain.g1Y = gA.g1y; state.strain.g2X = gA.g2x; state.strain.g2Y = gA.g2y
        let manualA = await state.runStrainMapping()
        XCTAssertEqual(manualA, .published, state.statusText)
        let m1Bits = try strainBits(state, "manual g_A")
        let s1 = try XCTUnwrap(activeID(state, "strain"))

        state.navigation.analysisMode = .disks
        state.diskDetection.diskParams.sigmaCC = p1.sigmaCC + 1
        await state.runDiskDetection()
        state.navigation.analysisMode = .strain
        state.strain.g1X = gA.g1x + 0.4            // g_B
        let manualB = await state.runStrainMapping()
        XCTAssertEqual(manualB, .published, state.statusText)
        let s2 = try XCTUnwrap(activeID(state, "strain"))
        XCTAssertNotEqual(s1, s2)

        let refusal = await state.rewindLineage(to: d1)
        XCTAssertNil(refusal, refusal ?? "")
        XCTAssertEqual(state.strain.basisMode, .manual)
        XCTAssertEqual(state.strain.g1X, gA.g1x, "s1 returned with the basis it indexed with, not g_B")
        XCTAssertTrue(state.replay.lineage.activeNodes().map(\.id).contains(s1))

        state.navigation.analysisMode = .disks
        await state.runDiskDetection()
        state.navigation.analysisMode = .strain
        let again = await state.runStrainMapping()
        XCTAssertEqual(again, .published, state.statusText)
        XCTAssertEqual(try strainBits(state, "after rewind"), m1Bits, "Run reproduces M1")
    }

    /// The refuter's 1c: replay refuses an ACOM step whose scale is not the one in
    /// force; so does a rewind — and it does not refuse when the scale agrees.
    /// Mutation it catches: drop the scale guard from `rewindLineage`.
    func testARewindToAnAcomRunRefusesOnAScaleMismatch() async throws {
        let (state, kernel) = try await handSession()
        let p1 = state.diskDetection.diskParams
        handRecord(state, "disk_detection", detectionRecord(p1, kernel: kernel))
        let scale = state.acomScaleSemantics.invAngstromPerPixel
        func acom(_ recorded: Double) -> [String: String] {
            ["material": "au_fcc", "scale_inv_angstrom_per_pixel": String(recorded),
             "matching_backend": "cpu", "scope": String(describing: ACOMRunScope.fullScan),
             "quality": String(describing: ACOMQualityPreset.fast)]
        }
        let wrong = handRecord(state, "acom", acom(scale * 2))
        var p2 = p1; p2.sigmaCC += 1
        handRecord(state, "disk_detection", detectionRecord(p2, kernel: kernel))
        state.diskDetection.diskParams = p2
        let before = state.replay.lineage
        let refusal = await state.rewindLineage(to: wrong)
        let text = try XCTUnwrap(refusal)
        XCTAssertTrue(text.contains("scale"), text)
        XCTAssertEqual(state.replay.lineage, before)
        XCTAssertEqual(state.diskDetection.diskParams, p2, "a refused rewind writes no control")

        // The same run recorded at the scale in force rewinds.
        let (agree, agreeKernel) = try await handSession()
        let q1 = agree.diskDetection.diskParams
        handRecord(agree, "disk_detection", detectionRecord(q1, kernel: agreeKernel))
        let good = handRecord(agree, "acom", acom(agree.acomScaleSemantics.invAngstromPerPixel))
        var q2 = q1; q2.sigmaCC += 1
        handRecord(agree, "disk_detection", detectionRecord(q2, kernel: agreeKernel))
        let ok = await agree.rewindLineage(to: good)
        XCTAssertNil(ok, ok ?? "")
        XCTAssertEqual(agree.acomSession.modelSelection, .library("au_fcc"))
    }
}

// MARK: - lineage_step on products (ROADMAP D; ADR 047 R2, R4(3))
//
// The lineage-only product kinds (phase map and its distance companion,
// precipitate objects, diffraction groups) name the run that made them, a
// product whose run left the active path reads stale and stays shown — also
// after a save and a reopen — and an export's edge names the run of the
// product it wrote, not whichever run of that kind is active.

extension SessionReplayAppStateTests {

    /// Any structure that is not Al stands in for the precipitate CIF (as in
    /// `AlMgSiPresetTests`); the demo carries a physical Q scale.
    private func preparePhaseMapping(_ state: AppState) throws {
        let beta = try XCTUnwrap(CrystalModelLibrary.model(id: "mg_hcp"))
        state.phaseMapping.applyAlMgSiPreset(precipitate: beta)
    }

    private func detectDisks(_ state: AppState, _ context: String) async {
        state.navigation.analysisMode = .disks
        await state.runDiskDetection()
        XCTAssertNotNil(state.resultPresentation.braggVectors, "\(context): \(state.statusText)")
    }

    private func mapPhases(_ state: AppState, _ context: String) async throws -> String {
        state.navigation.analysisMode = .phaseMapping
        let outcome = await state.runPhaseMapping()
        XCTAssertEqual(outcome, .published, "\(context): \(state.statusText)")
        return try XCTUnwrap(activeID(state, "phase_mapping"), context)
    }

    /// The verdict the sidebar row and the inspector share, for a mode.
    private func productState(_ state: AppState, _ mode: AnalysisMode) -> TaskProductState {
        ProductWorkflow.productState(
            for: mode, hasProduct: true,
            recordedStep: state.recordedReplayStep(for: mode),
            currentSignature: state.currentReplaySignature(for: mode))
    }

    private var offThePathReason: String { ProductWorkflow.staleReason(changedKeys: []) }

    /// d1 -> pm1, then d2 (sigma_cc + 1; a new node, d1 has a child) -> pm2.
    private func twoPhaseMaps(_ state: AppState) async throws -> (d1: String, pm1: String, d2: String, pm2: String) {
        try preparePhaseMapping(state)
        await detectDisks(state, "first detection")
        let d1 = try XCTUnwrap(activeID(state, "disk_detection"))
        let pm1 = try await mapPhases(state, "first phase map")
        state.diskDetection.diskParams.sigmaCC += 1
        await detectDisks(state, "second detection")
        let d2 = try XCTUnwrap(activeID(state, "disk_detection"))
        XCTAssertNotEqual(d2, d1)
        let pm2 = try await mapPhases(state, "second phase map")
        XCTAssertNotEqual(pm2, pm1)
        return (d1, pm1, d2, pm2)
    }

    /// (a) R2 for the kinds that are not recipe steps. Mutations it catches:
    /// `SessionReplay.record` crediting only recipe kinds; phase mapping or
    /// grouping publishing before recording (the map would name no run, or
    /// the previous one).
    func testThePhaseMapItsCompanionsAndTheGroupMapNameTheRunThatMadeThem() async throws {
        let state = AppState()
        await state.openDemoFixture(specification: uniformLatticeCrop)
        try preparePhaseMapping(state)
        await detectDisks(state, "detection")
        let pm = try await mapPhases(state, "phase map")
        XCTAssertEqual(state.displayedProduct?.kind, "phase_map")
        XCTAssertEqual(state.displayedProduct?.provenance["lineage_step"], pm)

        state.publishPhaseDistanceProduct()
        XCTAssertEqual(state.displayedProduct?.kind, "phase_match_distance")
        XCTAssertEqual(state.displayedProduct?.provenance["lineage_step"], pm)

        let objects = try XCTUnwrap(activeID(state, "precipitate_objects"))
        state.publishPrecipitateObjectsProduct()
        XCTAssertEqual(state.displayedProduct?.kind, "precipitate_objects")
        XCTAssertEqual(state.displayedProduct?.provenance["lineage_step"], objects)

        state.navigation.analysisMode = .diffractionGroups
        let grouped = await state.runDiffractionGroups()
        XCTAssertEqual(grouped, .published, state.statusText)
        XCTAssertEqual(state.displayedProduct?.kind, "diffraction_groups")
        XCTAssertEqual(state.displayedProduct?.provenance["lineage_step"],
                       try XCTUnwrap(activeID(state, "diffraction_groups")))
    }

    /// (b) R4(3): after a rewind to before the run that made the phase map on
    /// screen, the map reads stale with the existing sentence and stays shown.
    /// Mutation it catches: a verdict that ignores the lineage path for a kind
    /// with no settings signature (it read current).
    func testARewindToBeforeThePhaseMapReadsItStaleAndKeepsItShown() async throws {
        let state = AppState()
        await state.openDemoFixture(specification: uniformLatticeCrop)
        let run = try await twoPhaseMaps(state)
        XCTAssertEqual(productState(state, .phaseMapping), .current, "precondition: current before the rewind")

        let refusal = await state.rewindLineage(to: run.d1)
        XCTAssertNil(refusal, refusal ?? "")
        let active = state.replay.lineage.activeNodes().map(\.id)
        XCTAssertFalse(active.contains(run.pm2), "\(active)")
        XCTAssertNotNil(state.phaseMapping.map, "nothing is deleted")
        XCTAssertEqual(state.displayedProduct?.kind, "phase_map", "the map stays shown")
        XCTAssertEqual(state.displayedProduct?.provenance["lineage_step"], run.pm2)
        XCTAssertEqual(productState(state, .phaseMapping).staleReason, offThePathReason)
        let model = LineageGraphModel(
            lineage: state.replay.lineage, productKind: state.displayedProduct?.kind,
            productStep: state.displayedProduct?.provenance["lineage_step"],
            producedSteps: state.replay.producedStep)
        XCTAssertEqual(model.state(of: run.pm1), .stale, "the active phase-mapping run is not the one in memory")

        // Rewinding back puts the map's own run on the path: current again.
        let back = await state.rewindLineage(to: run.pm2)
        XCTAssertNil(back, back ?? "")
        XCTAssertEqual(productState(state, .phaseMapping), .current)
    }

    /// (b) for diffraction groups: the first grouping is saved (so R3 keeps it),
    /// a second one is shown, and a rewind to the first reads the shown one stale.
    func testARewindToAnEarlierGroupingReadsTheShownGroupMapStale() async throws {
        let state = AppState()
        await state.openDemoFixture(specification: uniformLatticeCrop)
        state.navigation.analysisMode = .diffractionGroups
        var outcome = await state.runDiffractionGroups()
        XCTAssertEqual(outcome, .published, state.statusText)
        let g1 = try XCTUnwrap(activeID(state, "diffraction_groups"))
        XCTAssertNotNil(state.markLineageProductSaved(productKind: "diffraction_groups"))
        state.diffractionGroups.settings.seed += 1
        outcome = await state.runDiffractionGroups()
        XCTAssertEqual(outcome, .published, state.statusText)
        let g2 = try XCTUnwrap(activeID(state, "diffraction_groups"))
        XCTAssertNotEqual(g2, g1, "a saved grouping is never collapsed into")
        XCTAssertEqual(productState(state, .diffractionGroups), .current)

        let refusal = await state.rewindLineage(to: g1)
        XCTAssertNil(refusal, refusal ?? "")
        XCTAssertNotNil(state.diffractionGroups.result)
        XCTAssertEqual(state.displayedProduct?.provenance["lineage_step"], g2)
        XCTAssertEqual(productState(state, .diffractionGroups).staleReason, offThePathReason)
    }

    /// Saves the map on screen into the sidecar and waits for the app's own
    /// follow-up read to finish (the HDF5 library is not thread-safe).
    private func saveShownResult(_ state: AppState) async throws {
        state.statusText = ""
        state.saveCurrentResultToSessionSidecar()
        for _ in 0..<200 where !state.statusText.hasPrefix("Saved") {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(state.statusText.hasPrefix("Saved"), "the save never completed: \(state.statusText)")
    }

    /// (c) `lineage_step` survives save -> reopen and names a node of the
    /// restored lineage, on its active path or off it as it was saved. A
    /// restored map is not a task's in-memory product, so no verdict surface
    /// judges it: no run of the reopened session made anything, and the phase
    /// task reads current. Mutations it catches: an unstamped map, or one
    /// stamped with the previous run.
    func testLineageStepRidesTheSaveAndNamesItsNodeInTheRestoredLineage() async throws {
        let suite = "mac4dstem.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LineageStepReopen-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDirectory) }
        let url = workDirectory.appendingPathComponent("demo.mac4dstem.h5")

        let state = AppState(sessionSidecar: SessionSidecarLocator(defaults: defaults))
        await state.openDemoFixture(specification: uniformLatticeCrop)
        let run = try await twoPhaseMaps(state)
        state.sessionSidecar.adopt(url, for: try XCTUnwrap(state.descriptor))

        func reopened() async throws -> AppState {
            let restored = AppState(sessionSidecar: SessionSidecarLocator(defaults: defaults))
            await restored.openDemoFixture(specification: uniformLatticeCrop)
            // Opening shows the automatic virtual image; View the saved map.
            for _ in 0..<100 where !restored.sessionInventory.results.contains(where: { $0.kind == "phase_map" }) {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            let saved = try XCTUnwrap(restored.sessionInventory.results.first { $0.kind == "phase_map" })
            await restored.selectSavedSessionResult(saved)
            let product = try XCTUnwrap(restored.displayedProduct)
            XCTAssertEqual(product.origin, .restoredFromSidecar)
            XCTAssertEqual(product.kind, "phase_map")
            XCTAssertEqual(product.provenance["lineage_step"], run.pm2, "lineage_step rides the save")
            XCTAssertNotNil(restored.replay.lineage.node(id: run.pm2))
            XCTAssertTrue(restored.replay.producedStep.isEmpty, "no run of the reopened session made it")
            return restored
        }

        // On the path when saved: current after reopen.
        try await saveShownResult(state)
        let onPath = try await reopened()
        XCTAssertTrue(onPath.replay.lineage.activeNodes().contains { $0.id == run.pm2 })
        XCTAssertEqual(productState(onPath, .phaseMapping), .current)

        // Off the path when saved (rewound to d1): the restored lineage keeps the
        // rewound path, and the map still names its own run — a branch now.
        let refusal = await state.rewindLineage(to: run.d1)
        XCTAssertNil(refusal, refusal ?? "")
        try await saveShownResult(state)
        let offPath = try await reopened()
        let restoredActive = offPath.replay.lineage.activeNodes().map(\.id)
        XCTAssertFalse(restoredActive.contains(run.pm2), "\(restoredActive)")
        XCTAssertTrue(restoredActive.contains(run.d1) && restoredActive.contains(run.pm1), "\(restoredActive)")
        XCTAssertEqual(offPath.replay.lineage.node(id: run.pm2)?.product,
                       BraggVectorEMDWriter.resultNodeName(forKind: "phase_map"),
                       "the saved map's run is marked as the one the file carries")
    }

    /// The everyday case, no rewind: d1 -> pm1, then detect again (a new node:
    /// d1 has a child). Phase mapping leaves the active path with the peaks it
    /// was built on, so the map in memory reads stale. Mutation it catches:
    /// `recordedReplayStep` answering the producer's step when its kind has no
    /// active node (it read current — the false-fresh at HEAD).
    func testADetectionAfterThePhaseMapReadsItStaleWithoutARewind() async throws {
        let state = AppState()
        await state.openDemoFixture(specification: uniformLatticeCrop)
        try preparePhaseMapping(state)
        await detectDisks(state, "first detection")
        let pm1 = try await mapPhases(state, "phase map")
        XCTAssertEqual(productState(state, .phaseMapping), .current)
        state.diskDetection.diskParams.sigmaCC += 1
        await detectDisks(state, "second detection")
        XCTAssertNil(activeID(state, "phase_mapping"), "the phase map's run left the path with its peaks")
        XCTAssertEqual(state.replay.producedStep["phase_mapping"], pm1)
        XCTAssertNotNil(state.phaseMapping.map)
        XCTAssertEqual(productState(state, .phaseMapping).staleReason, offThePathReason)
    }

    /// (d) The export's input edge names the run of the product it wrote: after
    /// a rewind the in-memory strain map is s2's while s1 is the active strain.
    /// Mutation it catches: linking the sink to the active node of the kind.
    func testAnExportAfterARewindNamesTheRunOfTheProductItWrote() async throws {
        let s = try await runTwoBranches()
        let state = s.state
        let refusal = await state.rewindLineage(to: s.disks1)
        XCTAssertNil(refusal, refusal ?? "")
        XCTAssertEqual(activeID(state, "strain"), s.strain1)

        // The scientific bundle writes the in-memory maps (strain2's run).
        let bundle = try XCTUnwrap(state.recordExportRun(
            format: "emd_scientific_bundle", fileName: "bundle.h5", productKind: "strain_exx"))
        XCTAssertEqual(state.replay.lineage.node(id: bundle)?.inputs,
                       [SessionLineage.Input(step: s.strain2, role: "product")])
        // A PNG passes the name its product carries, and that wins over the
        // in-memory run: here a map naming strain1 (a saved one, viewed again)
        // while the strain held in memory is strain2's.
        let product = try XCTUnwrap(state.displayedProduct)
        XCTAssertEqual(product.provenance["lineage_step"], s.strain2)
        let png = try XCTUnwrap(state.recordExportRun(
            format: "png", fileName: "map.png", productKind: product.kind, productStep: s.strain1))
        XCTAssertEqual(state.replay.lineage.node(id: png)?.inputs,
                       [SessionLineage.Input(step: s.strain1, role: "product")])
    }
}

// MARK: - A calibration change after a run marks its product stale (D068; ADR 047 R4(3))
//
// A strain, ACOM, phase-mapping or DPC run records the calibration nodes it
// consumed (`SessionLineage.inputPolicy`, role `calibration`). When the node of
// a calibration kind the run lists is no longer the one it used — a re-fit, a
// typed value, a newly made calibration — its product reads stale with the
// existing sentence, stays shown, and nothing recomputes. A calibration made
// before the run, or a rewind that puts the run's own calibration back, reads
// current. Rotation has no node and needs none: strain presents in the scan
// frame from the CURRENT rotation at every display (StrainFrame.swift), and
// ACOM and phase mapping do not read it.

extension SessionReplayAppStateTests {

    private func detectAndStrain(_ state: AppState, _ context: String) async throws -> String {
        await detectDisks(state, "\(context): detection")
        state.navigation.analysisMode = .strain
        let outcome = await state.runStrainMapping()
        XCTAssertEqual(outcome, .published, "\(context): \(state.statusText)")
        return try XCTUnwrap(activeID(state, "strain"), context)
    }

    /// The lineage pane's state of a node, as the pane builds it.
    private func graphState(_ state: AppState, _ id: String) -> LineageNodeState {
        LineageGraphModel(
            lineage: state.replay.lineage, productKind: state.displayedProduct?.kind,
            productStep: state.displayedProduct?.provenance["lineage_step"],
            producedSteps: state.replay.producedStep).state(of: id)
    }

    private func calibrationReason(_ key: String) -> String {
        ProductWorkflow.staleReason(changedKeys: [key])
    }

    /// (a) origin. Mutation it catches: a strain signature blind to the
    /// calibration the run consumed (the map read current — D068).
    func testAnOriginRefitAfterStrainReadsTheMapStaleAndKeepsItShown() async throws {
        let state = AppState()
        await state.openDemoFixture(specification: uniformLatticeCrop)
        let s1 = try await detectAndStrain(state, "strain")
        XCTAssertEqual(productState(state, .strain), .current, "precondition")
        let o1 = activeID(state, "calibration_origin")

        await state.calibrateOrigin()   // in Strain: re-shows the map, recomputes nothing
        let o2 = try XCTUnwrap(activeID(state, "calibration_origin"), state.statusText)
        XCTAssertNotEqual(o2, o1, "a re-fit after a run that used the origin is a new node")
        XCTAssertEqual(activeID(state, "strain"), s1, "nothing recomputed")
        XCTAssertNotNil(state.strain.map, "the map stays")
        XCTAssertEqual(productState(state, .strain).staleReason, calibrationReason("origin calibration"))
        XCTAssertEqual(graphState(state, s1), .stale, "the pane agrees with the sidebar")
    }

    /// (a) ellipse, and (c) no false stale: an ellipse typed BEFORE the run is
    /// the run's own (current); one typed after reads stale; a rewind to the
    /// run puts its ellipse back and the map reads current again. Mutations it
    /// catches: the verdict blind to calibration; a verdict that compares
    /// against the newest calibration node instead of the ACTIVE one (the
    /// rewind would keep it stale).
    func testAnEllipseChangeAfterStrainReadsStaleAndRewindingToTheRunReadsCurrent() async throws {
        let state = AppState()
        await state.openDemoFixture(specification: uniformLatticeCrop)
        state.applyManualEllipse(a: 10.1, b: 10, thetaDegrees: 20)
        let e1 = try XCTUnwrap(activeID(state, "calibration_ellipse"), state.statusText)
        let s1 = try await detectAndStrain(state, "strain on e1")
        XCTAssertTrue(state.replay.lineage.node(id: s1)?.inputs?.contains {
            $0.step == e1 && $0.role == "calibration" } == true, "precondition: the run recorded its ellipse")
        XCTAssertEqual(productState(state, .strain), .current, "a calibration made before the run is its own")
        XCTAssertEqual(graphState(state, s1), .current)

        state.applyManualEllipse(a: 10.2, b: 10, thetaDegrees: 20)
        let e2 = try XCTUnwrap(activeID(state, "calibration_ellipse"))
        XCTAssertNotEqual(e2, e1)
        XCTAssertNotNil(state.strain.map)
        XCTAssertEqual(productState(state, .strain).staleReason, calibrationReason("ellipse calibration"))
        XCTAssertEqual(graphState(state, s1), .stale)

        let refusal = await state.rewindLineage(to: s1)
        XCTAssertNil(refusal, refusal ?? "")
        XCTAssertEqual(activeID(state, "calibration_ellipse"), e1)
        XCTAssertEqual(state.calibrationSession.calibration.ellipseA, 10.1)
        XCTAssertEqual(productState(state, .strain), .current, "the run's own ellipse is back")
        XCTAssertEqual(graphState(state, s1), .current)
    }

    /// (a) Q, with its control: phase mapping consumes the Q scale and reads
    /// stale after a Q edit; strain does not (it works in detector pixels on
    /// origin- and ellipse-corrected vectors) and stays current. Mutations it
    /// catches: a verdict blind to Q (the phase map read current); one that
    /// judges every calibration kind for every product (strain read stale).
    func testAQEditReadsThePhaseMapStaleAndLeavesStrainCurrent() async throws {
        let state = AppState()
        await state.openDemoFixture(specification: uniformLatticeCrop)
        try preparePhaseMapping(state)
        _ = try await detectAndStrain(state, "strain")
        let pm = try await mapPhases(state, "phase map")
        XCTAssertEqual(productState(state, .phaseMapping), .current, "precondition")
        XCTAssertEqual(productState(state, .strain), .current, "precondition")

        let q = try XCTUnwrap(state.calibrationSession.calibration.qPixelSize)
        state.setManualQPixelSize(q * 1.01)
        XCTAssertNotNil(activeID(state, "calibration_q"), "the typed Q is a node")
        XCTAssertNotNil(state.phaseMapping.map, "the map stays")
        XCTAssertEqual(productState(state, .phaseMapping).staleReason, calibrationReason("Q calibration"))
        XCTAssertEqual(graphState(state, pm), .stale)
        XCTAssertEqual(productState(state, .strain), .current, "strain does not consume Q")
    }

    /// (b) ACOM consumes origin, ellipse and Q. (A Q edit discards the ACOM
    /// map outright — `ACOMSession.invalidateResult` — so the ellipse is the
    /// change that can leave one on screen.) Mutation it catches: the verdict
    /// blind to calibration for ACOM.
    func testAnEllipseFittedAfterACOMReadsItStale() async throws {
        let (state, kernel) = try await handSession()
        state.acomSession.modelSelection = .library("au_fcc")
        handRecord(state, "disk_detection", detectionRecord(state.diskDetection.diskParams, kernel: kernel))
        let signature = try XCTUnwrap(state.currentReplaySignature(for: .acom), "a resolved model has a signature")
        let a1 = handRecord(state, "acom", signature)
        XCTAssertEqual(productState(state, .acom), .current, "precondition")

        state.applyManualEllipse(a: 10.1, b: 10, thetaDegrees: 20)
        XCTAssertEqual(productState(state, .acom).staleReason, calibrationReason("ellipse calibration"))
        XCTAssertEqual(graphState(state, a1), .stale)
    }

    /// An origin fit while DPC is open no longer recomputes DPC behind the
    /// user's back (a full-cube pass and an unasked node, since bde005d): the
    /// map stays and reads stale. Mutation it catches: the unguarded
    /// `runCurrentAnalysis()` at the end of `calibrateOrigin`.
    func testAnOriginFitInDPCKeepsTheMapAndReadsItStale() async throws {
        let state = AppState()
        await state.openDemoFixture(specification: uniformLatticeCrop)
        await state.calibrateOrigin()   // first fit, outside DPC
        state.navigation.analysisMode = .dpc
        _ = await state.runDPC()
        let d1 = try XCTUnwrap(activeID(state, "dpc"), state.statusText)
        XCTAssertEqual(productState(state, .dpc), .current, "precondition")

        await state.calibrateOrigin()
        XCTAssertEqual(activeID(state, "dpc"), d1, "no recompute, no new DPC node")
        XCTAssertEqual(productState(state, .dpc).staleReason, calibrationReason("origin calibration"))
    }
}
