//
//  SidecarKeptApartTests.swift
//  The open path with `scan.h5`'s sidecar beside `scan.dm4`: the restore is not a dead end. The foreign file is left
//  alone, no save is refused, and this dataset's session goes to, and comes back from, `scan.dm4.mac4dstem.h5`.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class SidecarKeptApartTests: XCTestCase {

    private var folder: URL!
    private var owners: [AppState] = []

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("SidecarKeptApartTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        for owner in owners { OpenDatasetRegistry.withdraw(owner) }
        owners = []
        try? FileManager.default.removeItem(at: folder)
    }

    private func isolatedAppState() throws -> AppState {
        let suite = "mac4dstem.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let state = AppState(sessionSidecar: SessionSidecarLocator(defaults: defaults),
                             recents: RecentDatasets(entries: [], persist: { _ in }))
        state.recoveryRecord = nil   // never restamp the host's real recovery record
        owners.append(state)
        return state
    }

    private func source(_ name: String, bytes: Int) throws -> String {
        let url = folder.appendingPathComponent(name)
        try Data(count: bytes).write(to: url)
        return url.path
    }

    private func descriptor(path: String) -> DatasetDescriptor {
        DatasetDescriptor(
            filePath: path, datasetPath: "/4DSTEM_experiment/data/datacubes/datacube_0/data",
            shape: [4, 5, 8, 8], dtypeDescription: "float32", chunkShape: nil
        )
    }

    private let calibration = PixelCalibration(rSize: 1.0, rUnits: "nm", qSize: 0.01, qUnits: "A^-1", qrFlip: false)

    func testOpeningScanDM4BesideScanH5sSessionIsNotADeadEnd() async throws {
        let h5 = try source("scan.h5", bytes: 40)
        let dm4 = try source("scan.dm4", bytes: 80)
        let shared = folder.appendingPathComponent("scan.mac4dstem.h5")
        try BraggVectorEMDWriter.mergeCalibration(
            calibration, qWidth: 8, qHeight: 8, to: shared,
            source: SessionSourceStamp(sourcePath: h5, shape: [4, 5, 8, 8]))
        let before = try Data(contentsOf: shared)

        let state = try isolatedAppState()
        let recorded = await state.recordedLoadSpecification(forSourcePath: dm4, source: descriptor(path: dm4))

        XCTAssertNil(recorded)
        XCTAssertNil(state.sessionSidecar.unreadableReason, "another source's session is not an unreadable one")
        XCTAssertNil(state.gates.sidecarRewriteRefusal(), "and saving this dataset's session is not refused")
        XCTAssertEqual(state.sessionSidecar.location(forSourcePath: dm4).lastPathComponent, "scan.dm4.mac4dstem.h5")
        XCTAssertEqual(try Data(contentsOf: shared), before, "scan.h5's session is untouched")

        // Once scan.dm4 has its own session, the open reads that one.
        let own = state.sessionSidecar.location(forSourcePath: dm4)
        let other = PixelCalibration(rSize: 2.0, rUnits: "nm", qSize: 0.02, qUnits: "A^-1", qrFlip: false)
        try BraggVectorEMDWriter.mergeCalibration(
            other, qWidth: 8, qHeight: 8, to: own,
            source: SessionSourceStamp(sourcePath: dm4, shape: [4, 5, 8, 8]))
        let fresh = try isolatedAppState()
        let session = await fresh.readSession(forSourcePath: dm4)
        XCTAssertEqual(session?.url.lastPathComponent, "scan.dm4.mac4dstem.h5")
        XCTAssertEqual(try session?.read.get().calibration?.qSize, 0.02)
    }

    /// An unstamped sidecar beside two candidates is still refused as before: nothing says whose it is.
    func testAnUnstampedSharedSidecarIsStillRefused() async throws {
        _ = try source("scan.h5", bytes: 40)
        let dm4 = try source("scan.dm4", bytes: 80)
        try BraggVectorEMDWriter.mergeCalibration(
            calibration, qWidth: 8, qHeight: 8, to: folder.appendingPathComponent("scan.mac4dstem.h5"))

        let state = try isolatedAppState()
        _ = await state.recordedLoadSpecification(forSourcePath: dm4, source: descriptor(path: dm4))

        XCTAssertNotNil(state.sessionSidecar.unreadableReason)
        XCTAssertNotNil(state.gates.sidecarRewriteRefusal())
        XCTAssertEqual(state.sessionSidecar.location(forSourcePath: dm4).lastPathComponent, "scan.mac4dstem.h5")
    }
}
