import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// ADR 040 decision 2, Gate D `docs/archive/v4/rq-sign-gateD-2026-09-28.md`:
/// the app's internal R–Q angle is the negative of py4DSTEM's on the same
/// file. Every boundary converts through `RQRotationConvention`; internals
/// keep the app's angle. 0.6 rad (34.4°) is asymmetric on purpose: at 0°,
/// 90° or 180° a dropped sign could hide.
private actor RotationFileSource: FourDDataSource {
    let fileRotation: Double?
    init(fileRotation: Double?) { self.fileRotation = fileRotation }
    func discoverPrimaryDataset() throws -> DatasetDescriptor {
        DatasetDescriptor(filePath: "/synthetic/rq-sign.h5", datasetPath: "/data",
                          shape: [4, 4, 8, 8], dtypeDescription: "float32", chunkShape: nil)
    }
    nonisolated func loadPushdown(for view: LoadView) -> LoadPushdown { .none }
    func readPattern(_ view: LoadView, ry: Int, rx: Int) throws -> [Float] { [Float](repeating: 1, count: 64) }
    func readScanRow(_ view: LoadView, ry: Int) throws -> [Float] { [Float](repeating: 1, count: 4 * 64) }
    func readScanTile(_ view: LoadView, yRange: Range<Int>) throws -> FourDScanTile {
        FourDScanTile(yRange: yRange, scanWidth: 4, detectorHeight: 8, detectorWidth: 8,
                      pixels: [Float](repeating: 1, count: yRange.count * 4 * 64))
    }
    func readDoubleAttribute(_ name: String, onObjectPath path: String) -> Double? { nil }
    func pixelCalibration() -> PixelCalibration? { PixelCalibration(qrRotationRad: fileRotation) }
}

final class RQRotationConventionTests: XCTestCase {
    private let appAngle: Float = 0.6

    func testTheConventionIsANegationBothWaysAndDisplaysPy4DSTEMsSign() {
        XCTAssertEqual(RQRotationConvention.py4DSTEM(fromApp: 0.6), -0.6)
        XCTAssertEqual(RQRotationConvention.app(fromPy4DSTEM: -0.6), 0.6)
        XCTAssertEqual(RQRotationConvention.displayDegrees(fromApp: appAngle),
                       -Double(appAngle) * 180 / .pi, accuracy: 1e-9)
    }

    /// P3: a py4DSTEM file's QR_rotation φ becomes the app's −φ, and every
    /// readout shows φ again.
    @MainActor
    func testAPy4DSTEMFilesRotationIsImportedNegatedAndShownAsInTheFile() async throws {
        let state = AppState()
        let source = RotationFileSource(fileRotation: 0.6)
        let descriptor = try await source.discoverPrimaryDataset()
        await state.activate(descriptor: descriptor, reader: source, runInitialAnalysis: false)
        let rotation = try XCTUnwrap(state.calibrationSession.calibration.rotationRad)
        XCTAssertEqual(rotation, -0.6, accuracy: 1e-6, "internal angle is the file's negative")
        let detail = try XCTUnwrap(state.calibrationSession.readiness.items.first { $0.kind == .rotation }?.detail)
        XCTAssertTrue(detail.hasPrefix("34.4°"), "the readiness row shows the file's own angle: \(detail)")
        XCTAssertTrue(StrainPresentationFrame.scan(rotationRad: rotation, transposed: false)
            .displayLabel.contains("R–Q 34.4°"))
    }

    /// P2, write side: the sidecar snapshot carries py4DSTEM's sign and says so.
    @MainActor
    func testTheSidecarSnapshotCarriesPy4DSTEMsSignAndTheMarker() throws {
        let state = AppState()
        let descriptor = DatasetDescriptor(filePath: "/synthetic/rq.h5", datasetPath: "/data",
                                           shape: [4, 4, 8, 8], dtypeDescription: "float32", chunkShape: nil)
        XCTAssertNil(state.sessionPixelCalibration(descriptor: descriptor).qrRotationConvention,
                     "no rotation, no marker")
        state.calibrationSession.calibration.rotationRad = appAngle
        let snapshot = state.sessionPixelCalibration(descriptor: descriptor)
        XCTAssertEqual(try XCTUnwrap(snapshot.qrRotationRad), -Double(appAngle), accuracy: 1e-7)
        XCTAssertEqual(snapshot.qrRotationConvention, RQRotationConvention.marker)
    }

    /// P2 end to end, through the real HDF5 writer and reader (Gate D
    /// refuter, 2026-09-28): the snapshot and the policy are tested
    /// separately above, and a writer that dropped the marker while the
    /// snapshot still converted left every one of those green — the next open
    /// would then read py4DSTEM's sign as a legacy app sign.
    @MainActor
    func testARealSidecarRoundTripKeepsTheAppAngle() throws {
        let state = AppState()
        let descriptor = DatasetDescriptor(filePath: "/synthetic/rq.h5", datasetPath: "/data",
                                           shape: [4, 4, 8, 8], dtypeDescription: "float32", chunkShape: nil)
        state.calibrationSession.calibration.rotationRad = appAngle
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rq-roundtrip-\(UUID().uuidString).h5")
        defer { try? FileManager.default.removeItem(at: url) }
        let vectors = BraggVectors(scanWidth: 4, scanHeight: 4,
                                   peaks: Array(repeating: [BraggPeak(x: 3, y: 3, intensity: 1)], count: 16))
        try BraggVectorEMDWriter.write(vectors: vectors, qWidth: 8, qHeight: 8,
                                       calibration: state.sessionPixelCalibration(descriptor: descriptor), to: url)
        let saved = try XCTUnwrap(BraggVectorEMDWriter.loadSession(from: url).calibration)
        XCTAssertEqual(try XCTUnwrap(saved.qrRotationRad), -Double(appAngle), accuracy: 1e-6,
                       "the file carries py4DSTEM's sign")
        XCTAssertEqual(saved.qrRotationConvention, RQRotationConvention.marker, "and says so")
        let restored = try XCTUnwrap(SessionCalibrationTranslation.translate(
            saved: saved, policy: .identity, view: nil, descriptor: descriptor))
        XCTAssertEqual(try XCTUnwrap(restored.calibration.rotationRad), appAngle, accuracy: 1e-6)
    }

    /// P2, read side: a marked sidecar is converted back; an unmarked one
    /// (written before 2026-09-28 in the app's own sign) is read as-is.
    func testAMarkedSidecarIsConvertedAndALegacyOneIsReadAsIs() throws {
        let descriptor = DatasetDescriptor(filePath: "/synthetic/rq.h5", datasetPath: "/data",
                                           shape: [4, 4, 8, 8], dtypeDescription: "float32", chunkShape: nil)
        var marked = PixelCalibration(qrRotationRad: -Double(appAngle))
        marked.qrRotationConvention = RQRotationConvention.marker
        let fromMarked = try XCTUnwrap(SessionCalibrationTranslation.translate(
            saved: marked, policy: .identity, view: nil, descriptor: descriptor))
        XCTAssertEqual(try XCTUnwrap(fromMarked.calibration.rotationRad), appAngle, accuracy: 1e-7)

        let legacy = PixelCalibration(qrRotationRad: Double(appAngle))
        let fromLegacy = try XCTUnwrap(SessionCalibrationTranslation.translate(
            saved: legacy, policy: .identity, view: nil, descriptor: descriptor))
        XCTAssertEqual(try XCTUnwrap(fromLegacy.calibration.rotationRad), appAngle, accuracy: 1e-7)
    }
}
