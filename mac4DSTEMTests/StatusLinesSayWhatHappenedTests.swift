//
//  StatusLinesSayWhatHappenedTests.swift
//  Seen on the 5.3.0 walk through the rooms: a phase map's line that was 24 positions short of the scan, a Quantify that
//  wrote no line, a Merlin header refused without a hint, a probe radius of 22,84 px taken on a 128 px detector.
//

import XCTest
import DSTEMCore
import DSTEMSession
import ShellLayout
@testable import mac4DSTEM

final class StatusLinesSayWhatHappenedTests: XCTestCase {
    private let us = Locale(identifier: "en_US"), german = Locale(identifier: "de_DE")

    /// The demo's numbers: 151 + 2,897 + 0 + 24 = 3,072. Mutation: the no-peak count left out - red.
    func testThePhaseMapsLineAddsUpToTheScan() {
        let line = AppState.phaseMapStatusLine(phases: [(name: "beta", count: 151)], matrix: 2897, notIndexed: 0, noPeaks: 24, locale: us)
        XCTAssertEqual(line, "Phase map: beta 151, matrix 2,897, not indexed 0, no peaks 24")
        XCTAssertEqual(AppState.phaseMapStatusLine(phases: [(name: "beta", count: 151)], matrix: 2897, notIndexed: 0, noPeaks: 24, locale: german),
                       "Phase map: beta 151, matrix 2.897, not indexed 0, no peaks 24")
        XCTAssertEqual(AppState.phaseMapStatusLine(phases: [], matrix: 100, notIndexed: 2, noPeaks: 0, locale: us),
                       "Phase map: no candidate phase found, matrix 100, not indexed 2", "nothing is said of a count of zero")
    }

    func testQuantifyWritesItsOwnLine() {
        XCTAssertEqual(AppState.quantifyStatusLine(region: "Whole map", recordedAt: "Mg 1.65 \u{00B1} 0.34 \u{00B7} Al 96.41 \u{00B1} 0.48", locale: german),
                       "Quantify ✓  Whole map \u{00B7} Mg 1,65 \u{00B1} 0,34 \u{00B7} Al 96,41 \u{00B1} 0,48 at%")
        XCTAssertEqual(AppState.quantifyStatusLine(region: "Region 1 \u{00B7} drawn region", recordedAt: "", locale: us),
                       "Quantify: Region 1 \u{00B7} drawn region, no at% computed")
    }

    /// A Merlin header stands for its data: the single file, else the first part of a multi-file save (mac4DSTEM#262).
    func testAMerlinHeaderIsAnsweredWithItsDataFile() {
        let parts = ["default.hdr", "default10.mib", "default2.mib", "default1.mib", "notes.txt", "other1.mib"]
        XCTAssertEqual(MerlinHeaderCompanion.mib(forHeader: "default.hdr", among: parts), "default1.mib")
        XCTAssertEqual(MerlinHeaderCompanion.mib(forHeader: "scan.hdr", among: ["scan.hdr", "scan.MIB", "scan1.mib"]), "scan.MIB")
        XCTAssertNil(MerlinHeaderCompanion.mib(forHeader: "scan.hdr", among: ["scan.hdr", "scanner.mib", "other.mib"]))
        XCTAssertTrue(MerlinHeaderCompanion.refusal(header: "scan.hdr", folderWasReadable: false).contains("Pick one of the .mib files"))
        XCTAssertTrue(MerlinHeaderCompanion.refusal(header: "scan.hdr", folderWasReadable: true).contains("scan1.mib"))
    }

    /// The same folder through the app's own open: the header of the public multi-file save opens as the set. Skips without the data.
    func testThePublicMerlinSetOpensFromItsHeader() async throws {
        let data = ProcessInfo.processInfo.environment["MACEM_DATA"] ?? "/nonexistent"
        let header = URL(fileURLWithPath: data).appendingPathComponent("4dstem/public/zenodo-5113449-srtio3-merlin/20200518 165148/default.hdr")
        guard FileManager.default.fileExists(atPath: header.path) else { throw XCTSkip("no Merlin set at \(header.path)") }
        let reader = try await AppState.makeReader(for: header)
        let descriptor = try await reader.discoverPrimaryDataset()
        XCTAssertEqual(descriptor.shape, [128, 128, 256, 256])
    }

    func testAProbeRadiusAboveAQuarterOfTheDetectorIsRefusedWithTheReason() throws {
        XCTAssertNil(AppState.probeRadiusRefusal(radius: 2.84, qy: 128, qx: 128))
        XCTAssertNil(AppState.probeRadiusRefusal(radius: 32, qy: 128, qx: 128), "a quarter itself is taken")
        let refusal = try XCTUnwrap(AppState.probeRadiusRefusal(radius: 22.84, qy: 128, qx: 66, locale: german))
        XCTAssertTrue(refusal.contains("22,84") && refusal.contains("66 px") && refusal.contains("16,5"), refusal)
    }

    /// Calibrate Origin in the Prepare room: the room's own image is computed again on the new origin and writes its line,
    /// and the line that stays is the origin's. Seen on screen: "Virtual detector ✓" replaced it within the second, also with
    /// a first fix that asked the origin's cancellation token (the rerun retires that token) - red with either.
    @MainActor
    func testCalibrateOriginsLineOutlivesTheRoomsRerun() async {
        let state = AppState()
        await state.openDemoFixture(calibrated: false)
        state.navigation.analysisMode = .virtualDetector
        await state.calibrateOrigin()
        XCTAssertTrue(state.statusText.hasPrefix("Origin ✓"), state.statusText)
    }

    /// Disks that exist and are not the ones a task may use: the requirement says why. After a reopen it read "Detect
    /// Bragg disks first" beside a session that listed its disks.
    func testTheDiskRequirementSaysWhyExistingDisksAreNotUsed() {
        var readiness = ProductWorkflowReadiness()
        XCTAssertEqual(readiness.diskRequirementTitle, "Detect Bragg disks first", "no disks at all")
        readiness.disksNotUsableReason = AppState.disksNotUsableReason(hasDisks: true, settingsAreStale: true, storedDisksNote: nil)
        XCTAssertEqual(readiness.diskRequirementTitle, "Detect Bragg disks again: the detection settings changed since these disks were found")
        readiness.disksNotUsableReason = AppState.disksNotUsableReason(
            hasDisks: false, settingsAreStale: false,
            storedDisksNote: "Stored disks not used — they were detected on a different view than the one loaded now")
        XCTAssertEqual(readiness.diskRequirementTitle,
                       "Detect Bragg disks again: the session's disks were not taken, they were detected on a different view than the one loaded now")
        XCTAssertNil(AppState.disksNotUsableReason(hasDisks: true, settingsAreStale: false, storedDisksNote: nil), "current disks need no reason")
        readiness.hasBraggVectors = true
        XCTAssertEqual(readiness.diskRequirementTitle, "Detect Bragg disks first", "a satisfied row keeps its plain title")
    }

    func testAWindowWithoutACubeDoesNotSayStreaming() {
        XCTAssertEqual(OperationMetricsFormat.glance(engine: "Apple M3", residentMB: 402, residency: nil), "Apple M3 · 402 MB")
        XCTAssertEqual(OperationMetricsFormat.glance(engine: "Apple M3", residentMB: 402, residency: false), "Apple M3 · 402 MB · streaming")
    }

    func testTheSessionSavePanelSpeaksPlainly() {
        XCTAssertEqual(AppState.SessionSavePanelWording.title, "Save Session")
        for word in ["sidecar", "Sidecar", "companion"] {
            XCTAssertFalse((AppState.SessionSavePanelWording.title + AppState.SessionSavePanelWording.message).contains(word), word)
        }
    }

    func testTheUnsetVoltageSaysWhatNeedsIt() {
        XCTAssertTrue(PrepareSettings.voltageNotSetNote.contains("Reconstruction"))
    }
}
