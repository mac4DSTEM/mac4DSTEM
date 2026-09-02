//
//  SessionGatesTests.swift
//  v2 S7 — the policy-owner seam. Two families of "may I?" question:
//
//  1. "May I use the origin fit quantitatively?" — asked by Q calibration AND
//     physical iDPC through the same gate. The defect S7 fixes is that iDPC
//     derived this from `hasFittedOrigin` alone, so a fit refused for a Q
//     measurement was still admitted into "iDPC projected phase (rad)".
//  2. "May I rewrite the session sidecar?" — refused after a failed crop
//     restore, because every rewrite restates the CURRENT view and would
//     erase the recorded crop while relabelling the preserved results
//     (S5 Gate B-lite finding F9).
//
//  Wiring tests go through a REAL AppState (the S5/F8 lesson: pure-type tests
//  leave every wiring line deletable with the suite green).
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class SessionGatesTests: XCTestCase {

    /// An AppState whose sidecar bookmarks live in a suite-private store.
    /// The saves below persist a grant keyed by the demo's CONSTANT file
    /// path; through the real `UserDefaults` that grant leaks into every
    /// other demo-opening test — including parallel worker processes, which
    /// share the persisted domain (measured 2026-08-25: foreign recipes and
    /// `sessionSidecar`-stamped Q scales in unrelated suites).
    private func isolatedAppState() throws -> AppState {
        let suite = "mac4dstem.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        return AppState(sessionSidecar: SessionSidecarLocator(defaults: defaults))
    }

    // MARK: - Origin-fit gate

    /// Origin maps with a controlled RMS residual, same construction as
    /// `QCalibrationOriginGateTests` (alternating-sign offsets so the RMS is
    /// exactly `residual`).
    private func origin(residual: Float, centre: Float, scan: Int) -> OriginMaps {
        let count = scan * scan
        let signs = (0..<count).map { Float($0 % 2 == 0 ? 1 : -1) }
        return OriginMaps(
            width: scan, height: scan,
            measuredX: signs.map { centre + $0 * residual },
            measuredY: [Float](repeating: centre, count: count),
            fittedX: [Float](repeating: centre, count: count),
            fittedY: [Float](repeating: centre, count: count)
        )
    }

    private func install(residual: Float, on state: AppState) {
        let scan = state.descriptor.map { max($0.rx, $0.ry) } ?? 12
        let centre = Float(state.descriptor.map { $0.qx } ?? 64) / 2
        state.calibration.originProvenance = .fitted
        state.calibration.probeRadius = 4.5
        state.calibration.origin = origin(residual: residual, centre: centre, scan: scan)
    }

    func testOriginGateIsTheCalibrationJudgement() {
        let gates = SessionGates()
        var calibration = Calibration()
        XCTAssertNil(gates.originQuantitativeRefusal(for: calibration),
                     "An empty calibration has no residual to judge and must not refuse")

        calibration.probeRadius = 4.5
        calibration.origin = origin(residual: 10, centre: 32, scan: 12)
        let refusal = gates.originQuantitativeRefusal(for: calibration)
        XCTAssertNotNil(refusal, "RMS 10 px against a 4.5 px probe must refuse")
        XCTAssertEqual(refusal, calibration.originFitRefusal,
                       "The gate must BE the Core judgement, not a second derivation")

        calibration.origin = origin(residual: 1, centre: 32, scan: 12)
        XCTAssertNil(gates.originQuantitativeRefusal(for: calibration),
                     "RMS 1 px against a 4.5 px probe is quantitative")
    }

    /// THE S7 defect, through the real gate: the same origin fit that Q
    /// calibration refuses must also demote physical iDPC to qualitative.
    /// The first half (good fit ⇒ physical available) is the control that
    /// stops a gate-that-refuses-everything from passing the second half.
    func testPhysicalIDPCTakesTheSameOriginGateAsQCalibration() async throws {
        let state = AppState()
        await state.openDemoFixture(calibrated: true)
        state.calibration.rotationRad = 0.3
        install(residual: 0.9, on: state)
        XCTAssertNotNil(state.idpcPhysicalCalibration,
                        "With a quantitative fit, rotation and both pixel scales, physical iDPC must be available")
        XCTAssertNil(state.idpcOriginFitRefusal)

        // One number changes — the same move QCalibrationOriginGateTests
        // makes — and BOTH quantitative claims must fall together.
        install(residual: 4.5 * 2.32, on: state)
        XCTAssertNil(state.idpcPhysicalCalibration,
                     "An origin fit refused for Q measurement must not integrate a projected phase in radians")
        let refusal = state.idpcOriginFitRefusal
        XCTAssertNotNil(refusal, "The DPC controls must be able to say WHY it is qualitative")
        XCTAssertTrue(refusal?.contains("probe radius") == true,
                      "The refusal must quote the judgement: \(refusal ?? "nil")")
        // One JUDGEMENT, one owner: the iDPC surface and the Q gate must both
        // quote `Calibration.originFitJudgement` verbatim. The remedies
        // legitimately differ — "enter the scale manually" un-blocks a Q
        // measurement and does nothing for iDPC (Gate B, 2026-08-25) — so
        // the iDPC text must NOT carry the manual-scale clause.
        let judgement = try XCTUnwrap(state.calibration.originFitJudgement)
        XCTAssertTrue(refusal?.contains(judgement) == true,
                      "The iDPC refusal must carry the shared judgement verbatim")
        XCTAssertTrue(state.gates.originQuantitativeRefusal(for: state.calibration)?
            .contains(judgement) == true,
                      "The Q gate must carry the same judgement verbatim")
        XCTAssertFalse(refusal?.contains("enter the scale manually") == true,
                       "iDPC must not print the Q-surface's remedy — manual scale entry cannot restore physical iDPC")
    }

    // MARK: - Sidecar rewrite gate

    func testSidecarRewriteRefusalLifecycle() {
        let gates = SessionGates()
        XCTAssertNil(gates.sidecarRewriteRefusal(),
                     "With no failed restore there is nothing to refuse")

        gates.noteSidecarRestoreFailed(.unreadable, message: "EPERM story.")
        let unreadable = gates.sidecarRewriteRefusal()
        XCTAssertNotNil(unreadable)
        XCTAssertTrue(unreadable?.contains("EPERM story.") == true,
                      "The refusal must carry the restore failure it is protecting")
        XCTAssertTrue(unreadable?.contains("Change…") == true,
                      "The unreadable case's remedy is re-granting access: \(unreadable ?? "nil")")

        gates.noteSidecarRestoreFailed(.doesNotFit, message: "Wrong file story.")
        let doesNotFit = gates.sidecarRewriteRefusal()
        XCTAssertTrue(doesNotFit?.contains("Move the sidecar aside") == true,
                      "The does-not-fit case's remedy is different: \(doesNotFit ?? "nil")")

        gates.clearSidecarRestoreFailure()
        XCTAssertNil(gates.sidecarRewriteRefusal())
    }

    /// The wiring: with the flag set, every sidecar REWRITE entry point must
    /// refuse before touching the file. A grant is adopted first so that,
    /// under the mutation that deletes a gate check, the save actually writes
    /// (and the test fails on the file's existence) instead of hanging in the
    /// first-save panel.
    func testCalibrationSaveRefusesAfterFailedRestore() async throws {
        let state = try isolatedAppState()
        await state.openDemoFixture(calibrated: true)
        let descriptor = try XCTUnwrap(state.descriptor)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("s7-gate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sidecar = directory.appendingPathComponent("demo.mac4dstem.h5")
        state.sessionSidecar.adopt(sidecar, for: descriptor)

        state.gates.noteSidecarRestoreFailed(.unreadable, message: "refused read.")
        state.saveCalibrationToSessionSidecar()
        // The refusal is synchronous — before the operation Task is spawned.
        XCTAssertTrue(state.errorMessage?.contains("could not restore") == true,
                      "The save must refuse with the restore failure named: \(state.errorMessage ?? "nil")")
        // Give any (wrongly) spawned write a chance to run before asserting.
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecar.path),
                       "A refused save must not have rewritten the sidecar")

        // The control: clearing the failure lets the same save proceed.
        state.gates.clearSidecarRestoreFailure()
        state.errorMessage = nil
        state.saveCalibrationToSessionSidecar()
        // Wait for the app's OWN post-save inventory read to finish (the
        // status line is set after it), not just for the file to exist —
        // tearing the directory down under a live HDF5 read is the standing
        // concurrent-HDF5 crash (S5's lesson).
        try await waitUntil("the allowed save publishes the sidecar") {
            state.statusText.contains("Saved calibration")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecar.path))
    }

    func testResultSaveAndRemovalRefuseAfterFailedRestore() async throws {
        let state = try isolatedAppState()
        await state.openDemoFixture(calibrated: true)
        let descriptor = try XCTUnwrap(state.descriptor)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("s7-gate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sidecar = directory.appendingPathComponent("demo.mac4dstem.h5")
        state.sessionSidecar.adopt(sidecar, for: descriptor)

        state.navigation.analysisMode = .virtualDetector
        await state.runVirtualDetector()
        XCTAssertNotNil(state.resultImage, "The virtual image is the result being saved")

        // Save once WITHOUT the flag so removal has something to refuse over.
        state.saveCurrentResultToSessionSidecar()
        try await waitUntil("the first result save publishes") {
            FileManager.default.fileExists(atPath: sidecar.path)
        }
        try await waitUntil("the inventory reflects the save") {
            !state.sessionInventory.results.isEmpty
        }
        let saved = try XCTUnwrap(state.sessionInventory.results.first)
        let bytesAfterSave = try XCTUnwrap(
            try FileManager.default.attributesOfItem(atPath: sidecar.path)[.size] as? Int
        )

        state.gates.noteSidecarRestoreFailed(.doesNotFit, message: "wrong region.")
        state.errorMessage = nil
        state.saveCurrentResultToSessionSidecar()
        XCTAssertTrue(state.errorMessage?.contains("could not restore") == true,
                      "The result save must refuse: \(state.errorMessage ?? "nil")")

        state.errorMessage = nil
        await state.removeSavedSessionResult(saved)
        XCTAssertTrue(state.errorMessage?.contains("could not restore") == true,
                      "Removal rebuilds the file and must refuse too: \(state.errorMessage ?? "nil")")
        try await Task.sleep(nanoseconds: 200_000_000)
        let bytesNow = try XCTUnwrap(
            try FileManager.default.attributesOfItem(atPath: sidecar.path)[.size] as? Int
        )
        XCTAssertEqual(bytesNow, bytesAfterSave,
                       "Neither refused rewrite may have touched the file")
    }

    // MARK: - The flag's set/clear wiring

    /// The does-not-fit branch of `recordedLoadSpecification` must set the
    /// gate (it used to report only into `statusText`, the channel S1
    /// measured as unreadable), and a fitting specification must not.
    func testRecordedSpecificationDoesNotFitSetsTheGate() async throws {
        let state = AppState()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("s7-restore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourcePath = directory.appendingPathComponent("cube.h5").path
        let sidecar = BraggVectorEMDWriter.sessionSidecarURL(forSourcePath: sourcePath)

        // A sidecar recording a 40-row scan crop, against a 12-row source.
        let oversized = LoadSpecification(
            scanCrop: AxisCrop(yOffset: 0, xOffset: 0, height: 40, width: 40),
            detectorCrop: nil, detectorBin: 1
        )
        try BraggVectorEMDWriter.mergeCalibration(
            PixelCalibration(), qWidth: 64, qHeight: 64,
            to: sidecar, loadSpecification: oversized
        )
        let small = DatasetDescriptor(
            filePath: sourcePath, datasetPath: "/data",
            shape: [12, 12, 64, 64], dtypeDescription: "float32", chunkShape: nil
        )
        let restored = await state.recordedLoadSpecification(
            forSourcePath: sourcePath, source: small
        )
        XCTAssertNil(restored, "A specification that does not fit must be dropped, not clamped")
        XCTAssertEqual(state.gates.sidecarRestoreFailure?.kind, .doesNotFit,
                       "The drop must arm the rewrite gate, not only statusText")
        XCTAssertNotNil(state.gates.sidecarRewriteRefusal())

        // The control: a fitting crop restores and never arms the gate.
        state.gates.clearSidecarRestoreFailure()
        let fitting = LoadSpecification(
            scanCrop: AxisCrop(yOffset: 0, xOffset: 0, height: 6, width: 6),
            detectorCrop: nil, detectorBin: 1
        )
        try BraggVectorEMDWriter.mergeCalibration(
            PixelCalibration(), qWidth: 64, qHeight: 64,
            to: sidecar, loadSpecification: fitting
        )
        let restoredFitting = await state.recordedLoadSpecification(
            forSourcePath: sourcePath, source: small
        )
        XCTAssertEqual(restoredFitting, fitting)
        XCTAssertNil(state.gates.sidecarRestoreFailure)
    }

    /// v2 S7's `try?` audit, end to end: a specification attribute that
    /// EXISTS and cannot be decoded must refuse (`malformedAttribute`), never
    /// read as "no crop recorded" — which is what `.flatMap(decoded)` made of
    /// it, reopening a cropped session silently at full extent. The file is
    /// corrupted for real: the attribute's JSON bytes are overwritten in
    /// place (same length, so the HDF5 structure stays valid).
    func testAMangledSpecificationAttributeRefusesInsteadOfReadingAsNoCrop() async throws {
        let state = AppState()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("s7-mangled-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourcePath = directory.appendingPathComponent("cube.h5").path
        let sidecar = BraggVectorEMDWriter.sessionSidecarURL(forSourcePath: sourcePath)

        let spec = LoadSpecification(
            scanCrop: AxisCrop(yOffset: 0, xOffset: 0, height: 6, width: 6),
            detectorCrop: nil, detectorBin: 1
        )
        try BraggVectorEMDWriter.mergeCalibration(
            PixelCalibration(), qWidth: 64, qHeight: 64,
            to: sidecar, loadSpecification: spec
        )
        let json = try XCTUnwrap(spec.jsonString)
        var bytes = try Data(contentsOf: sidecar)
        let range = try XCTUnwrap(
            bytes.range(of: Data(json.utf8)),
            "The fixture needs the attribute's bytes to be findable in the file"
        )
        bytes.replaceSubrange(
            range, with: Data(repeating: UInt8(ascii: "#"), count: json.count)
        )
        try bytes.write(to: sidecar)

        XCTAssertThrowsError(try BraggVectorEMDWriter.loadSession(from: sidecar)) { error in
            guard case BraggVectorEMDWriter.WriterError.malformedAttribute = error else {
                return XCTFail("Expected malformedAttribute, got \(error)")
            }
        }
        // The wiring: the open path reports it as an unreadable restore —
        // durable channel armed, rewrites refused — not as a full-extent open.
        let small = DatasetDescriptor(
            filePath: sourcePath, datasetPath: "/data",
            shape: [12, 12, 64, 64], dtypeDescription: "float32", chunkShape: nil
        )
        let restored = await state.recordedLoadSpecification(
            forSourcePath: sourcePath, source: small
        )
        XCTAssertNil(restored)
        XCTAssertEqual(state.gates.sidecarRestoreFailure?.kind, .unreadable,
                       "A mangled attribute is an unreadable restore, not a quiet full-extent one")
    }

    func testDiscardPartialLoadClearsTheGate() async {
        let state = AppState()
        state.gates.noteSidecarRestoreFailed(.unreadable, message: "stale.")
        await state.discardPartialLoad()
        XCTAssertNil(state.gates.sidecarRestoreFailure,
                     "The flag must never outlive the dataset it describes")
    }

    // MARK: - Helper

    private func waitUntil(
        _ what: String, timeoutSeconds: Double = 5,
        _ condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while !condition() {
            if Date() > deadline { XCTFail("Timed out waiting for \(what)"); return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
