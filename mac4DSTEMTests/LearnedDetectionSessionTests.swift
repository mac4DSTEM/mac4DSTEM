//
//  LearnedDetectionSessionTests.swift
//  C7 session 2: `LearnedDetectionSession` (`Session/LearnedDetection.swift`)
//  — the detector-class/threshold option, the probe reference, the two
//  compared runs, and the replay glue (`replayParameters`/`replayRefusal`).
//  The asset-loading tests share `LearnedSwiftFixture` with
//  `LearnedDiskDetectorTests.swift` and skip when the asset is not present,
//  the same convention that file uses.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class LearnedDetectionSessionTests: XCTestCase {

    private func vectors(count: Int) -> BraggVectors {
        BraggVectors(scanWidth: 1, scanHeight: 1,
                     peaks: [(0..<count).map { BraggPeak(x: Float($0), y: 0, intensity: 1) }])
    }

    // MARK: record / clear / canCompare

    func testRecordFilesEachClassUnderItsOwnSlot() {
        let session = LearnedDetectionSession()
        XCTAssertFalse(session.canCompare)
        session.record(vectors(count: 3), as: .classical)
        XCTAssertFalse(session.canCompare, "one class alone is not a comparison")
        session.record(vectors(count: 5), as: .learned)
        XCTAssertTrue(session.canCompare)
        XCTAssertEqual(session.lastClassical?.totalPeakCount, 3)
        XCTAssertEqual(session.lastLearned?.totalPeakCount, 5)
    }

    func testClearDropsTheComparedRunsAndTheProbeReferenceButKeepsTheOption() {
        let session = LearnedDetectionSession()
        session.detectorClass = .learned
        session.threshold = 0.42
        session.record(vectors(count: 1), as: .classical)
        session.record(vectors(count: 1), as: .learned)
        session.probeReference = .init(
            pattern: DiffractionPattern(qy: 4, qx: 4, pixels: [Float](repeating: 0, count: 16)),
            centreX: 2, centreY: 2, radius: 1, source: .synthetic
        )
        session.clear()
        XCTAssertNil(session.lastClassical)
        XCTAssertNil(session.lastLearned)
        XCTAssertFalse(session.canCompare)
        XCTAssertNil(session.probeReference, "dataset activation: a stale probe is the wrong shape, not just outdated")
        XCTAssertEqual(session.detectorClass, .learned, "the option is session-scoped, not dataset-scoped")
        XCTAssertEqual(session.threshold, 0.42, "the threshold is session-scoped, not dataset-scoped")
    }

    // MARK: replayParameters

    func testReplayParametersForClassicalCarriesOnlyTheDetectorClass() {
        let session = LearnedDetectionSession()
        XCTAssertEqual(session.replayParameters(for: .classical), ["detector_class": "classical"])
    }

    func testReplayParametersForLearnedAddsThresholdAndHash() {
        let session = LearnedDetectionSession()
        session.threshold = 0.55
        let params = session.replayParameters(for: .learned)
        XCTAssertEqual(params["detector_class"], "learned")
        XCTAssertEqual(params["learned_threshold"], "0.55")
        // Not yet loaded in this test: empty, never omitted or fabricated.
        XCTAssertEqual(params["learned_model_sha256"], "")
    }

    // MARK: syntheticProbe

    func testSyntheticProbeIsOneInsideTheRadiusAndZeroOutside() {
        let qy = 21, qx = 21
        let centre: (x: Float, y: Float) = (10, 10)
        let radius: Float = 5
        let probe = LearnedDetectionSession.syntheticProbe(qy: qy, qx: qx, centre: centre, radius: radius)
        XCTAssertEqual(probe.qy, qy)
        XCTAssertEqual(probe.qx, qx)
        var expectedOnes = 0
        for y in 0..<qy {
            for x in 0..<qx {
                let dx = Float(x) - centre.x, dy = Float(y) - centre.y
                let inside = dx * dx + dy * dy <= radius * radius
                if inside { expectedOnes += 1 }
                XCTAssertEqual(probe.pixels[y * qx + x], inside ? 1 : 0, "(\(x), \(y))")
            }
        }
        XCTAssertGreaterThan(expectedOnes, 0)
        XCTAssertEqual(probe.pixels.filter { $0 == 1 }.count, expectedOnes)
    }

    // MARK: replayRefusal

    func testReplayRefusalForAClassicalRecordSetsClassAndReturnsNil() async {
        let session = LearnedDetectionSession()
        session.detectorClass = .learned   // must be overwritten by the recorded plan
        let reason = await session.replayRefusal(for: .init(detectorClass: .classical))
        XCTAssertNil(reason)
        XCTAssertEqual(session.detectorClass, .classical)
    }

    func testReplayRefusalForALearnedRecordWithTheShippedHashSucceeds() async throws {
        let f = try LearnedSwiftFixture.load()
        guard FileManager.default.fileExists(atPath: LearnedSwiftFixture.assetURL.path) else {
            throw XCTSkip("no committed asset at \(LearnedSwiftFixture.assetURL.path)")
        }
        let session = LearnedDetectionSession()
        let reason = await session.replayRefusal(for: .init(
            detectorClass: .learned, learnedThreshold: 0.6, learnedModelSHA256: f.expected.asset_sha256
        ))
        XCTAssertNil(reason, "reason was: \(reason ?? "")")
        XCTAssertEqual(session.detectorClass, .learned)
        XCTAssertEqual(session.threshold, 0.6)
        XCTAssertEqual(session.assetSHA256, f.expected.asset_sha256)
    }

    func testReplayRefusalForALearnedRecordWithAWrongHashNamesBothPrefixes() async throws {
        guard FileManager.default.fileExists(atPath: LearnedSwiftFixture.assetURL.path) else {
            throw XCTSkip("no committed asset at \(LearnedSwiftFixture.assetURL.path)")
        }
        let f = try LearnedSwiftFixture.load()
        let session = LearnedDetectionSession()
        let wrongHash = "deadbeef" + String(f.expected.asset_sha256.dropFirst(8))
        let reason = await session.replayRefusal(for: .init(
            detectorClass: .learned, learnedThreshold: 0.6, learnedModelSHA256: wrongHash
        ))
        let reason2 = try XCTUnwrap(reason, "a hash mismatch must refuse")
        XCTAssertTrue(reason2.contains(String(wrongHash.prefix(8))), "reason was: \(reason2)")
        XCTAssertTrue(reason2.contains(String(f.expected.asset_sha256.prefix(8))), "reason was: \(reason2)")
        // Gate B 2026-09-08: a refused replay leaves the picker where it was.
        XCTAssertEqual(session.detectorClass, .classical, "a refused learned step must not switch the picker")
        XCTAssertEqual(session.threshold, LearnedDiskDetector.defaultThreshold, "nor apply the recorded threshold")
    }

    // MARK: AppState.runDiskDisagreement (C7 session 3)

    func testRunDiskDisagreementRefusesUntilBothClassesHaveRun() {
        let state = AppState()
        let refusal = AnalysisRunOutcome.failed("Run Detect All Disks with each detector on this dataset first")
        XCTAssertEqual(state.runDiskDisagreement(), refusal)
        state.learnedDetection.record(vectors(count: 1), as: .classical)
        XCTAssertEqual(state.runDiskDisagreement(), refusal)
        XCTAssertNil(state.displayedProduct)
    }

    /// Classical peaks at x 0 and 1; learned at (0.2, 0) and (9, 9): the first
    /// classical pairs (0.2 px), the second is classical-only, (9, 9) is
    /// learned-only. The product is a SCAN map (not the Disk detection mode's
    /// detector domain) carrying the statistics and the compared learned
    /// run's identity.
    func testRunDiskDisagreementPublishesAScanMapWithItsStatistics() throws {
        let state = AppState()
        state.learnedDetection.record(vectors(count: 2), as: .classical)
        state.learnedDetection.record(BraggVectors(
            scanWidth: 1, scanHeight: 1,
            peaks: [[BraggPeak(x: 0.2, y: 0, intensity: 1), BraggPeak(x: 9, y: 9, intensity: 1)]],
            detectionProvenance: ["learned_threshold": "0.7", "learned_model_sha256": "abc123"]
        ), as: .learned)

        XCTAssertEqual(state.runDiskDisagreement(), .published)
        let product = try XCTUnwrap(state.displayedProduct)
        XCTAssertEqual(product.kind, "disk_disagreement")
        XCTAssertEqual(product.domain, .scan)
        guard case .scalar(let image) = product.payload else { return XCTFail("scalar payload expected") }
        XCTAssertEqual(image.pixels, [2])
        XCTAssertEqual(product.provenance["display_domain"], "scan")
        XCTAssertEqual(product.provenance["detector_class"], "classical,learned")
        XCTAssertEqual(product.provenance["disagreement_matched"], "1")
        XCTAssertEqual(product.provenance["disagreement_classical_only"], "1")
        XCTAssertEqual(product.provenance["disagreement_learned_only"], "1")
        XCTAssertEqual(product.provenance["disagreement_positions"], "1/1")
        XCTAssertEqual(product.provenance["disagreement_match_radius_px"], "2.0")
        XCTAssertEqual(product.provenance["disagreement_median_residual_px"], "0.20")
        XCTAssertEqual(product.provenance["learned_model_sha256"], "abc123")
        XCTAssertEqual(product.provenance["learned_threshold"], "0.7")
        XCTAssertTrue(state.statusText.hasPrefix("Disagreement: 1 of 1 positions differ"), state.statusText)
    }
}
