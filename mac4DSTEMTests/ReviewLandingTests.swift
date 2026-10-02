//
//  ReviewLandingTests.swift
//  Slot 4¾ review lane E (2026-10-02): results landing in the wrong room or on the wrong dataset.
//  c1 — a Bragg vector map, a diffraction-groups map or a phase map that lands while another room
//       is current keeps its OWN frame, sampling and provenance; Detect All landing off-room holds
//       the vectors and Bragg Disks re-shows them on return.
//  c2 — a probe kernel built for one dataset never lands on the next (epoch), and a kernel whose
//       detector grid differs from the pattern's never reaches DiskDetector's precondition.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class ReviewLandingTests: XCTestCase {

    override func tearDown() async throws {
        AppState.probeKernelBeforeLanding = nil
    }

    private var smallCrop: LoadSpecification {
        var spec = LoadSpecification()
        spec.scanCrop = AxisCrop(yOffset: 0, xOffset: 0, height: 4, width: 4)
        return spec
    }

    private func openedState() async throws -> AppState {
        let state = AppState()
        await state.openDemoFixture(specification: smallCrop)
        _ = try XCTUnwrap(state.descriptor, state.statusText)
        return state
    }

    private func stub(_ kind: String) -> DisplayedProduct {
        DisplayedProduct(
            kind: kind, displayName: kind,
            payload: .scalar(FloatImage(width: 2, height: 2, pixels: [0, 0, 0, 0])), domain: .scan,
            validityMask: nil, qualityFields: [],
            sampling: ProductSampling(row: nil, column: nil, units: nil),
            valueUnits: "x", quantitativeStatus: .relative, provenance: [:], overlays: [])
    }

    /// The R and Q samplings differ on the demo, or the sampling assertions below prove nothing.
    private func assertRAndQDiffer(_ state: AppState) {
        let c = state.calibrationSession.calibration
        XCTAssertTrue(c.rPixelUnits != c.qPixelUnits || c.rPixelSize != c.qPixelSize,
                      "precondition: R and Q sampling must differ: \(String(describing: c.rPixelUnits)) vs \(String(describing: c.qPixelUnits))")
    }

    // MARK: c1

    /// Mutation: showBraggMap publishing without its own domain/sampling/keys (the pre-fix call) ->
    /// domain .scan, R units, analysis_mode "Strain" -> red.
    func testBraggMapShownWhileAnotherRoomIsCurrentKeepsItsOwnLabels() async throws {
        let state = try await openedState()
        assertRAndQDiffer(state)
        let d = try XCTUnwrap(state.descriptor)
        let peaks = [[BraggPeak]](repeating: [BraggPeak(x: 30, y: 30, intensity: 1)], count: d.rx * d.ry)
        let vectors = BraggVectors(scanWidth: d.rx, scanHeight: d.ry, peaks: peaks)
        state.resultPresentation.setBraggVectors(vectors)
        state.navigation.analysisMode = .strain
        state.showBraggMap(vectors, descriptor: d)
        let product = try XCTUnwrap(state.resultPresentation.product)
        let q = state.calibrationSession.calibration
        XCTAssertEqual(product.kind, "bragg_vector_map")
        XCTAssertEqual(product.domain, .detector)
        XCTAssertEqual(product.sampling.units, q.qPixelUnits)
        XCTAssertEqual(product.sampling.row, q.qPixelSize)
        XCTAssertEqual(product.provenance["analysis_mode"], AnalysisMode.disks.rawValue)
        XCTAssertEqual(product.provenance["coordinate_space"], "reciprocal")
        XCTAssertEqual(product.provenance["source_product"], "bragg_vector_map")
    }

    /// In its own room the map's labels are what the `.disks` mode branch gave before (no number moves).
    func testBraggMapInItsOwnRoomMatchesTheModeMetadata() async throws {
        let state = try await openedState()
        let d = try XCTUnwrap(state.descriptor)
        let vectors = BraggVectors(scanWidth: d.rx, scanHeight: d.ry,
                                   peaks: [[BraggPeak]](repeating: [], count: d.rx * d.ry))
        state.resultPresentation.setBraggVectors(vectors)
        state.navigation.analysisMode = .disks
        state.showBraggMap(vectors, descriptor: d)
        let product = try XCTUnwrap(state.resultPresentation.product)
        let mode = state.currentScalarPersistenceMetadata
        XCTAssertEqual(product.sampling, ProductSampling(row: mode.row, column: mode.column, units: mode.units))
        for (key, value) in mode.provenance { XCTAssertEqual(product.provenance[key], value, key) }
        XCTAssertEqual(product.domain, state.activeResultDomain)
    }

    /// Mutation (a): drop the room check at Detect All's landing (always showBraggMap) -> the map is the
    /// product while Imaging is current -> red. Mutation (b): drop the clearing of an older Bragg map ->
    /// the stale stub stays -> red. Return to Bragg Disks shows the NEW map in its own frame.
    func testDetectAllLandingInAnotherRoomIsHeldAndShownOnReturn() async throws {
        let state = try await openedState()
        state.navigation.analysisMode = .virtualDetector
        state.resultPresentation.publish(stub("bragg_vector_map"))   // an older run's map, still showing
        let outcome = await state.runDiskDetection()
        XCTAssertEqual(outcome, .published, state.statusText)
        XCTAssertNotNil(state.resultPresentation.braggVectors)
        XCTAssertNil(state.resultPresentation.product, "a Bragg map was shown under Imaging, or the old one kept")
        state.changeMode(.disks)
        let product = try XCTUnwrap(state.resultPresentation.product)
        XCTAssertEqual(product.kind, "bragg_vector_map")
        XCTAssertEqual(product.domain, .detector)
        XCTAssertEqual(product.payload.dimensions.width, state.descriptor?.qx, "the new map, not the 2 × 2 stub")
    }

    /// Mutation: the groups publish without its own domain/sampling/keys -> under Bragg Disks it takes
    /// .detector, Q units and analysis_mode "Disks" -> red.
    func testDiffractionGroupsLandingUnderBraggDisksKeepsScanLabels() async throws {
        let state = try await openedState()
        assertRAndQDiffer(state)
        state.navigation.analysisMode = .disks
        let outcome = await state.runDiffractionGroups()
        XCTAssertEqual(outcome, .published, state.statusText)
        let product = try XCTUnwrap(state.resultPresentation.product)
        let r = state.calibrationSession.calibration
        XCTAssertEqual(product.kind, "diffraction_groups")
        XCTAssertEqual(product.domain, .scan)
        XCTAssertEqual(product.sampling.units, r.rPixelUnits)
        XCTAssertEqual(product.provenance["analysis_mode"], AnalysisMode.diffractionGroups.rawValue)
        XCTAssertNil(product.provenance["coordinate_space"])
        XCTAssertEqual(product.provenance["quantitative_status"], "categorical")
    }

    /// Mutation: the phase-map publish without its own sampling/keys -> under Bragg Disks Q units and
    /// analysis_mode "Disks", coordinate_space "reciprocal" -> red.
    func testPhaseMapPublishedUnderBraggDisksKeepsScanLabels() async throws {
        let state = try await openedState()
        assertRAndQDiffer(state)
        let beta = try XCTUnwrap(CrystalModelLibrary.model(id: "mg_hcp"))
        state.phaseMapping.applyAlMgSiPreset(precipitate: beta)
        state.navigation.analysisMode = .disks
        _ = await state.runDiskDetection()
        XCTAssertNotNil(state.resultPresentation.braggVectors, state.statusText)
        state.navigation.analysisMode = .phaseMapping
        let outcome = await state.runPhaseMapping()
        XCTAssertEqual(outcome, .published, state.statusText)
        state.navigation.analysisMode = .disks   // e.g. a replay or a re-show while Bragg Disks is current
        state.publishPhaseMapProduct()
        let product = try XCTUnwrap(state.resultPresentation.product)
        let r = state.calibrationSession.calibration
        XCTAssertEqual(product.kind, "phase_map")
        XCTAssertEqual(product.domain, .scan)
        XCTAssertEqual(product.sampling.units, r.rPixelUnits)
        XCTAssertEqual(product.provenance["analysis_mode"], AnalysisMode.phaseMapping.rawValue)
        XCTAssertNil(product.provenance["coordinate_space"])
        XCTAssertEqual(product.provenance["validation"], "none")
    }

    // MARK: c2

    /// A raw-only square EMPAD file (2 × 2 scan of 130 × 128 float32 frames): a bright disk of radius 10
    /// at (64, 64) in the 128 × 128 image every frame — a measurable vacuum probe.
    private func writeVacuumEMPAD() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ReviewLandingTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        var frame = [Float](repeating: 1, count: 130 * 128)
        for y in 0..<128 { for x in 0..<128 where (x - 64) * (x - 64) + (y - 64) * (y - 64) <= 100 { frame[y * 128 + x] = 100 } }
        var bytes = Data()
        for _ in 0..<4 { frame.withUnsafeBufferPointer { bytes.append(Data(buffer: $0)) } }
        let url = dir.appendingPathComponent("vacuum.raw")
        try bytes.write(to: url)
        return url
    }

    private func targetState() -> AppState {
        let state = AppState()
        state.descriptor = DatasetDescriptor(
            filePath: "/tmp/target.h5", datasetPath: "/data", shape: [2, 2, 128, 128],
            dtypeDescription: "float32", chunkShape: nil)
        return state
    }

    /// Precondition for the next test: with no dataset change the vacuum kernel DOES land, so the nil
    /// below is the epoch guard and not a fixture that never builds a kernel.
    func testVacuumKernelLandsWhenTheDatasetIsUnchanged() async throws {
        let url = try writeVacuumEMPAD()
        let state = targetState()
        await state.generateVacuumProbeKernel(fromScan: url)
        XCTAssertNotNil(state.probeKernel, state.statusText)
        XCTAssertNotNil(state.learnedDetection.probeReference)
    }

    /// Mutation: remove the epoch guard in generateVacuumProbeKernel -> A's kernel lands on B -> red.
    func testVacuumKernelBuiltForTheOldDatasetNeverLandsOnTheNext() async throws {
        let url = try writeVacuumEMPAD()
        let state = targetState()
        AppState.probeKernelBeforeLanding = { state.datasetSession.advanceEpochAfterDiscard() }
        await state.generateVacuumProbeKernel(fromScan: url)
        XCTAssertNil(state.probeKernel)
        XCTAssertNil(state.learnedDetection.probeReference)
    }

    /// Mutation: remove the epoch guard in generateProbeKernel -> red.
    func testSyntheticKernelBuiltAcrossADatasetChangeNeverLands() async throws {
        let state = try await openedState()
        state.calibrationSession.calibration.probeRadius = 4
        state.probeKernel = nil
        state.learnedDetection.probeReference = nil
        AppState.probeKernelBeforeLanding = { state.datasetSession.advanceEpochAfterDiscard() }
        await state.generateProbeKernel()
        XCTAssertNil(state.probeKernel)
        XCTAssertNil(state.learnedDetection.probeReference)
        AppState.probeKernelBeforeLanding = nil
        await state.generateProbeKernel()   // precondition: without the change it lands
        XCTAssertNotNil(state.probeKernel, state.statusText)
    }

    /// Mutation: remove the epoch guard in generateMeasuredProbeKernel -> red.
    func testMeasuredKernelBuiltAcrossADatasetChangeNeverLands() async throws {
        let state = try await openedState()
        state.calibrationSession.calibration.probeRadius = 4
        XCTAssertNotNil(state.displayedPattern)
        state.probeKernel = nil
        state.learnedDetection.probeReference = nil
        AppState.probeKernelBeforeLanding = { state.datasetSession.advanceEpochAfterDiscard() }
        await state.generateMeasuredProbeKernel()
        XCTAssertNil(state.probeKernel)
        XCTAssertNil(state.learnedDetection.probeReference)
    }

    /// Mutation: remove the size guard in performLiveDetection -> DiskDetector's precondition traps
    /// (the test process crashes) -> red.
    func testLiveDetectionWithAKernelForAnotherDetectorClearsPeaksInsteadOfTrapping() async throws {
        let state = try await openedState()
        state.navigation.analysisMode = .disks
        let pattern = try XCTUnwrap(state.displayedPattern)
        state.probeKernel = try XCTUnwrap(ProbeKernel.synthetic(radius: 4, qy: pattern.qy * 2, qx: pattern.qx * 2))
        state.currentPeaks = [BraggPeak(x: 1, y: 1, intensity: 1)]
        await state.detectCurrentPattern()
        XCTAssertTrue(state.currentPeaks.isEmpty)
        XCTAssertNil(state.currentDiskDiagnostics)
    }

    /// Mutation: remove the size guard in runDiskDetection -> detectAll traps -> red.
    func testDetectAllWithAKernelForAnotherDetectorRefuses() async throws {
        let state = try await openedState()
        state.navigation.analysisMode = .disks
        let d = try XCTUnwrap(state.descriptor)
        state.probeKernel = try XCTUnwrap(ProbeKernel.synthetic(radius: 4, qy: d.qy * 2, qx: d.qx * 2))
        let outcome = await state.runDiskDetection()
        guard case .failed(let why) = outcome else { return XCTFail("ran: \(outcome)") }
        XCTAssertTrue(why.contains("detector"), why)
        XCTAssertNil(state.resultPresentation.braggVectors)
    }
}
