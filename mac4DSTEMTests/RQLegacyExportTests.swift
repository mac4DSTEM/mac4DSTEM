import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// ADR 040 residual (open-items "R–Q (ADR 040) residuals"): a datacube this
/// app exported BEFORE 2026-09-28 has `authoring_program = "mac4DSTEM"` and no
/// `QR_rotation_convention` marker. The stamp identifies the writer, not the
/// sign: before the conversion the app imported and exported a py4DSTEM
/// `QR_rotation` raw, so the value may be either sign. The reader therefore
/// passes it through UNCHANGED (today's number, negated once at Open) and
/// labels it; it never converts. 23° is asymmetric on purpose (0°, 90° and
/// 180° would hide a flip). The old-style file is written by the REAL datacube
/// writer with the calibration exactly as the old export handed it in: an
/// angle and no marker.
actor RQLegacyCubeSource: FourDDataSource {
    func discoverPrimaryDataset() throws -> DatasetDescriptor {
        DatasetDescriptor(filePath: "/synthetic/rq-legacy.h5", datasetPath: "/data",
                          shape: [2, 2, 4, 4], dtypeDescription: "float32", chunkShape: nil)
    }
    nonisolated func loadPushdown(for view: LoadView) -> LoadPushdown { .none }
    func readPattern(_ view: LoadView, ry: Int, rx: Int) throws -> [Float] { [Float](repeating: 1, count: 16) }
    func readScanRow(_ view: LoadView, ry: Int) throws -> [Float] { [Float](repeating: 1, count: 2 * 16) }
    func readScanTile(_ view: LoadView, yRange: Range<Int>) throws -> FourDScanTile {
        FourDScanTile(yRange: yRange, scanWidth: 2, detectorHeight: 4, detectorWidth: 4,
                      pixels: [Float](repeating: 1, count: yRange.count * 2 * 16))
    }
    func readDoubleAttribute(_ name: String, onObjectPath path: String) -> Double? { nil }
    func pixelCalibration() -> PixelCalibration? { nil }
}

final class RQLegacyExportTests: XCTestCase {
    let angle: Float = 23 * .pi / 180

    func export(_ calibration: PixelCalibration) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rq-legacy-\(UUID().uuidString).h5")
        let source = RQLegacyCubeSource()
        let descriptor = try await source.discoverPrimaryDataset()
        _ = try await BraggVectorEMDWriter.writeCalibratedDataCube(
            source: source, view: LoadView(fullExtentOf: descriptor), calibration: calibration,
            options: CalibratedDataCubeExportOptions(scanY: 0..<2, scanX: 0..<2), to: url)
        return url
    }

    /// What `H5Reader` hands the Open path for an exported datacube.
    func readBack(_ url: URL) async throws -> PixelCalibration {
        let reader = try H5Reader(path: url.path)
        _ = try await reader.discoverPrimaryDataset()   // pixelCalibration() needs the dataset path
        let calibration = await reader.pixelCalibration()
        return try XCTUnwrap(calibration)
    }

    /// The app's rotation after reopening the datacube as a dataset.
    @MainActor
    func reopenedAppRotation(_ url: URL) async throws -> Float {
        let reader = try H5Reader(path: url.path)
        let descriptor = try await reader.discoverPrimaryDataset()
        let state = AppState()
        await state.activate(descriptor: descriptor, reader: reader, runInitialAnalysis: false)
        return try XCTUnwrap(state.calibrationSession.calibration.rotationRad)
    }

    /// Nothing moves: an unmarked export reopens with today's number (the file's
    /// value read as py4DSTEM's, so negated once) and is labelled.
    @MainActor
    func testAnUnmarkedExportKeepsTodaysNumberAndCarriesTheNote() async throws {
        let url = try await export(PixelCalibration(qrRotationRad: Double(angle)))
        defer { try? FileManager.default.removeItem(at: url) }
        let read = try await readBack(url)
        XCTAssertEqual(try XCTUnwrap(read.qrRotationRad), Double(angle), accuracy: 1e-6,
                       "the value passes through unchanged")
        XCTAssertEqual(read.qrRotationNote, RQRotationConvention.legacyNote)
        let rotation = try await reopenedAppRotation(url)
        XCTAssertEqual(rotation, -angle, accuracy: 1e-6, "today's number: negated once at Open")
    }

    /// The label reaches the user where the rotation is shown: the R–Q row's
    /// detail carries it while the rotation is still the file's (orchestrator,
    /// 2026-09-30 night — the status line alone is overwritten by the next message).
    @MainActor
    func testAnUnmarkedExportShowsItsNoteOnTheRotationRow() async throws {
        let url = try await export(PixelCalibration(qrRotationRad: Double(angle)))
        defer { try? FileManager.default.removeItem(at: url) }
        let reader = try H5Reader(path: url.path)
        let state = AppState()
        await state.activate(descriptor: try await reader.discoverPrimaryDataset(), reader: reader,
                             runInitialAnalysis: false)
        let row = try XCTUnwrap(state.calibrationSession.readiness.items.first { $0.kind == .rotation })
        XCTAssertTrue(row.detail.contains(RQRotationConvention.legacyNote), row.detail)
        // Measured here, the file's caveat no longer applies.
        state.calibrationSession.provenance.rotation = .measuredInApp
        let measured = try XCTUnwrap(state.calibrationSession.readiness.items.first { $0.kind == .rotation })
        XCTAssertFalse(measured.detail.contains(RQRotationConvention.legacyNote))
    }

    /// A marked export (py4DSTEM's sign, since 2026-09-28) carries no note and
    /// reopens with the app angle it was exported from.
    @MainActor
    func testAMarkedExportCarriesNoNoteAndKeepsTheAppAngle() async throws {
        let state = AppState()
        let descriptor = DatasetDescriptor(filePath: "/synthetic/rq.h5", datasetPath: "/data",
                                           shape: [2, 2, 4, 4], dtypeDescription: "float32", chunkShape: nil)
        state.calibrationSession.calibration.rotationRad = angle
        let url = try await export(state.sessionPixelCalibration(descriptor: descriptor))
        defer { try? FileManager.default.removeItem(at: url) }
        let read = try await readBack(url)
        XCTAssertNil(read.qrRotationNote)
        XCTAssertEqual(try XCTUnwrap(read.qrRotationRad), -Double(angle), accuracy: 1e-6)
        let rotation = try await reopenedAppRotation(url)
        XCTAssertEqual(rotation, angle, accuracy: 1e-6)
    }

    /// An export with no rotation has nothing to label.
    func testAnExportWithoutARotationCarriesNoNote() async throws {
        let url = try await export(PixelCalibration(rSize: 1, rUnits: "nm"))
        defer { try? FileManager.default.removeItem(at: url) }
        let read = try await readBack(url)
        XCTAssertNil(read.qrRotationNote)
    }
}
