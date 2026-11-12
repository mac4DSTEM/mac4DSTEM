//
//  StatusLinesSayWhatHappenedTests.swift
//  Seen on the 5.3.0 walk through the rooms: a phase map's line that was 24 positions short of the scan, a Quantify that
//  wrote no line, a Merlin header refused without a hint, a probe radius of 22,84 px taken on a 128 px detector.
//

import XCTest
import DSTEMCore
import DSTEMSession
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

    func testTheUnsetVoltageSaysWhatNeedsIt() {
        XCTAssertTrue(PrepareSettings.voltageNotSetNote.contains("Reconstruction"))
    }
}
