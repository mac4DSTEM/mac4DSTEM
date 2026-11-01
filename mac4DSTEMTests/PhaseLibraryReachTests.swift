import XCTest
import DiffractoCore
import DiffractoOrientation
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// The phase-mapping reference library is built to the detector's reach, at most Max |q|. Each entry keeps its 48
/// strongest reflections (`maximumVectorsPerEntry`); built to a fixed 1.6 Å⁻¹ on a detector that records far less, part
/// of those 48 are reflections the detector cannot see, in place of ones it records, and the end-on β″ [010]
/// precipitates of the public Al-Mg-Si demo all came back "not indexed" (96 of 96).
@MainActor
final class PhaseLibraryReachTests: XCTestCase {

    override func tearDown() {
        AppState.probeKernelBeforeLanding = nil
        super.tearDown()
    }

    private var beta: CrystalModel {
        CrystalModel(id: "preset_betaDoublePrime", displayName: "betaDoublePrime",
                     structure: CrystalPresets.betaDoublePrime, symmetry: .monoclinic, source: .builtIn)
    }

    func testTheLibraryRangeIsTheDetectorReachAtMostMaxQ() {
        // The demo detector (0.762 Å⁻¹ to the edge) under the default Max |q| 1.6: the reach.
        XCTAssertEqual(OrientationPlan.kMax(originX: 63.5, originY: 63.5, detectorColumns: 128, detectorRows: 128,
                                            invAngstromPerPixel: 0.012, maximum: 1.6), 0.762, accuracy: 1e-12)
        // A detector that reaches further keeps Max |q|, not the orientation plan's 1.2.
        XCTAssertEqual(OrientationPlan.kMax(originX: 255.5, originY: 255.5, detectorColumns: 512, detectorRows: 512,
                                            invAngstromPerPixel: 0.012, maximum: 1.6), 1.6)
        // No readable reach: Max |q|.
        XCTAssertEqual(OrientationPlan.kMax(originX: -3, originY: 10, detectorColumns: 64, detectorRows: 64,
                                            invAngstromPerPixel: 0.02, maximum: 1.6), 1.6)
        XCTAssertEqual(OrientationPlan.kMax(originX: 32, originY: 32, detectorColumns: 64, detectorRows: 64,
                                            invAngstromPerPixel: .nan, maximum: 1.6), 1.6)
    }

    /// Planted on the in-app demo detector (64 px at 0.02 Å⁻¹/px, 0.62 Å⁻¹ to the edge): an Al [001] matrix
    /// everywhere and end-on β″ [010] in a 4 x 4 block, every spot the detector records exactly where the kit projects
    /// it. The Al-Mg-Si preset at the default Max |q| 1.6 Å⁻¹ must find the block. Red before the fix (the library at
    /// 1.6 Å⁻¹): the block came back "not indexed". The preset's classifier (known variants) scores every surviving
    /// vector by its nearest reference; with the library at 1.6 Å⁻¹ only 26 of the 52 surviving vectors have their own
    /// reference in the entry (score 0.128 Å⁻¹ against the 0.07 cut-off), at the reach 40 (0.041). Break it by
    /// returning `setting` from `phaseLibraryKMax`.
    func testEndOnPrecipitatesCutAtTheDetectorEdgeAreIndexed() async throws {
        let state = AppState()
        var spec = LoadSpecification()
        spec.scanCrop = AxisCrop(yOffset: 0, xOffset: 0, height: 8, width: 8)
        await state.openDemoFixture(specification: spec)
        let d = try XCTUnwrap(state.descriptor, state.statusText)
        state.navigation.analysisMode = .disks
        _ = await state.runDiskDetection()   // the step the staleness check reads; its peaks are replaced below
        let detected = try XCTUnwrap(state.resultPresentation.braggVectors, state.statusText)
        let origin = state.calibratedBraggVectors(detected, descriptor: d).origin.point
        let scale = state.acomScaleSemantics.invAngstromPerPixel
        XCTAssertEqual(scale, 0.02, accuracy: 1e-9, "precondition: the fixture's Q scale")
        XCTAssertEqual(state.phaseMapping.reference.kMaxInvAngstrom, 1.6, "precondition: the default Max |q|")

        // Every spot of a projection the detector records (1 px inside the edge), at in-plane rotation 0: the Al spots
        // above the library's 5 % floor, and every β″ [010] spot (54 here).
        let edge = min(Double(origin.x), Double(origin.y), Double(d.qx - 1) - Double(origin.x),
                       Double(d.qy - 1) - Double(origin.y)) - 1
        func spots(_ crystal: CrystalStructure, _ axis: SIMD3<Int>, floor: Double) throws -> [BraggPeak] {
            var all = PhaseReferenceSettings()
            all.kMaxInvAngstrom = 1.6
            all.maximumVectorsPerEntry = 0
            all.minimumIntensityFraction = floor
            let reflections = try PhaseReferenceLibrary.reflections(of: crystal, kMaxInvAngstrom: 1.6)
            return PhaseReferenceLibrary.projectedVectors(reflections: reflections, crystal: crystal, zoneAxis: axis,
                                                          settings: all)
                .filter { $0.length / scale <= edge }
                .sorted { $0.relativeIntensity > $1.relativeIntensity }   // brightest first, as the disk detector lists them
                .map { BraggPeak(x: origin.x + Float($0.q.x / scale), y: origin.y + Float($0.q.y / scale),
                                 intensity: Float($0.relativeIntensity)) }
        }
        let direct = BraggPeak(x: origin.x, y: origin.y, intensity: 10)
        let matrix = try spots(CrystalPresets.aluminum, SIMD3(0, 0, 1), floor: 0.05)
        let precipitate = try spots(CrystalPresets.betaDoublePrime, SIMD3(0, 1, 0), floor: 0)
        XCTAssertGreaterThan(precipitate.count, 48, "precondition: more β″ [010] spots on the detector than an entry keeps")
        func inBlock(_ x: Int, _ y: Int) -> Bool { (2...5).contains(x) && (2...5).contains(y) }
        var peaks: [[BraggPeak]] = []
        for y in 0..<d.ry { for x in 0..<d.rx {
            peaks.append([direct] + matrix + (inBlock(x, y) ? precipitate : []))
        } }
        state.resultPresentation.setBraggVectors(BraggVectors(scanWidth: d.rx, scanHeight: d.ry, peaks: peaks))

        state.phaseMapping.applyAlMgSiPreset(precipitate: beta)
        state.navigation.analysisMode = .phaseMapping
        let outcome = await state.runPhaseMapping()
        XCTAssertEqual(outcome, .published, state.statusText)
        let map = try XCTUnwrap(state.phaseMapping.map)
        let run = try XCTUnwrap(state.phaseMapping.lastRun)
        XCTAssertEqual(run.libraryKMaxInvAngstrom, 0.02 * (edge + 1), accuracy: 1e-6, "built to the detector's reach")
        XCTAssertEqual(run.reference.kMaxInvAngstrom, 1.6, "Max |q| itself is not changed")
        XCTAssertFalse(state.phaseMapping.isStale, "a run at the reach is current for the settings it ran with")
        var found = 0, matrixKept = 0
        for y in 0..<d.ry { for x in 0..<d.rx {
            let r = map.results[y * d.rx + x]
            if inBlock(x, y) {
                if r.verdict == .indexed && r.phaseIndex == 1 { found += 1 }
            } else if r.verdict == .matrix {
                matrixKept += 1
            }
        } }
        XCTAssertEqual(found, 16, "end-on β″ [010] positions indexed as β″ [010]")
        XCTAssertEqual(matrixKept, d.rx * d.ry - 16, "matrix positions")
    }
}

/// The public Al-Mg-Si demo through the app: disk detection, then phase mapping with the Al-Mg-Si preset at the default
/// Max |q|. Needs the file: `TEST_RUNNER_MAC4DSTEM_DEMO_H5=<path to a COPY of AlMgSi_demo.h5>` with `truth.json` beside
/// it (opening writes a session file next to the file); skipped without it (CI has no data).
///
/// Measured 2026-10-31 in grain A (Al [001], the matrix): with the library at 1.6 Å⁻¹ the 96 end-on β″ [010]
/// positions (truth code 1) were all "not indexed" and 50 matrix positions too; at the detector's reach (0.762 Å⁻¹) all
/// 96 are β″ [010], those 50 matrix, and the 108 β″ [001] positions (code 2) β″ [001] either way.
@MainActor
final class AlMgSiDemoPhaseMappingTests: XCTestCase {

    func testEndOnPrecipitatesAreIndexedInGrainA() async throws {
        guard let path = ProcessInfo.processInfo.environment["MAC4DSTEM_DEMO_H5"] else {
            throw XCTSkip("MAC4DSTEM_DEMO_H5 not set")
        }
        let truthURL = URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("truth.json")
        let truth = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: truthURL)) as? [String: Any])
        let codes = try XCTUnwrap(truth["precipitate_map"] as? [[NSNumber]]).map { $0.map(\.intValue) }

        let state = AppState()
        await state.openFileAsync(url: URL(fileURLWithPath: path))
        let d = try XCTUnwrap(state.descriptor, state.statusText)
        await state.calibrateOrigin()
        state.navigation.analysisMode = .disks
        _ = await state.runDiskDetection()
        XCTAssertNotNil(state.resultPresentation.braggVectors, state.statusText)
        state.phaseMapping.applyAlMgSiPreset(precipitate: CrystalModel(
            id: "preset_betaDoublePrime", displayName: "betaDoublePrime",
            structure: CrystalPresets.betaDoublePrime, symmetry: .monoclinic, source: .builtIn))
        let outcome = await state.runPhaseMapping()
        XCTAssertEqual(outcome, .published, state.statusText)
        let map = try XCTUnwrap(state.phaseMapping.map)
        XCTAssertEqual(try XCTUnwrap(state.phaseMapping.lastRun).libraryKMaxInvAngstrom, 0.762, accuracy: 1e-3)
        var endOn = 0, endOnFound = 0, inPlane = 0, inPlaneFound = 0, matrix = 0, matrixKept = 0
        for y in 0..<d.ry { for x in 0...54 {   // grain A, columns 0-54
            let r = map.results[y * d.rx + x]
            switch codes[y][x] {
            case 1:
                endOn += 1
                if r.verdict == .indexed && r.phaseIndex == 1 { endOnFound += 1 }
            case 2:
                inPlane += 1
                if r.verdict == .indexed && r.phaseIndex == 2 { inPlaneFound += 1 }
            default:
                guard !(y >= 90 && x <= 9) else { continue }   // the vacuum corner
                matrix += 1
                if r.verdict == .matrix { matrixKept += 1 }
            }
        } }
        XCTAssertEqual(endOn, 96)
        XCTAssertEqual(endOnFound, 96, "end-on β″ [010] (all 'not indexed' with the library at 1.6 Å⁻¹)")
        XCTAssertEqual(inPlaneFound, inPlane, "β″ [001]")
        // 50 matrix positions next to the needles read β″ [001] at either range (their patterns hold both).
        XCTAssertGreaterThanOrEqual(matrixKept, matrix - 50, "matrix positions")
    }
}
