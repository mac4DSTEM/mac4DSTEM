import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// mac4DSTEM#204: a HyperSpy file (.hspy / .hdf5) stores its calibration on the axes of the signal, as the attributes `scale`
/// and `units` of the groups axis-0…axis-3 beside the data. The app read none of it, so a HyperSpy scan opened with Q and R
/// "Not set". The files are tiny, written by `Fixtures/HyperSpy/make_hyperspy_fixtures.py` in the layout of two public HyperSpy 4D-STEM
/// files (Zenodo 10.5281/zenodo.2652906 and 10.5281/zenodo.5597738), whose unit spellings they carry.
final class HyperSpyAxesCalibrationTests: XCTestCase {
    private static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/HyperSpy")

    private func calibration(of name: String) async throws -> PixelCalibration? {
        let reader = try H5Reader(path: Self.fixtures.appendingPathComponent(name).path)
        let descriptor = try await reader.discoverPrimaryDataset()   // pixelCalibration() needs the dataset path
        XCTAssertEqual(descriptor.shape, [2, 3, 4, 5])
        return await reader.pixelCalibration()
    }

    func testATitledExperimentGivesItsScalesExactly() async throws {
        let found = try await calibration(of: "angstrom-titled.hdf5")
        let read = try XCTUnwrap(found)
        XCTAssertEqual(read.qSize, 0.026)
        XCTAssertEqual(read.qUnits, "Å^-1")
        XCTAssertEqual(read.rSize, 1.536)
        XCTAssertEqual(read.rUnits, "nm")
        XCTAssertEqual(CalibrationUnitConversion.reciprocalInvAngstromPerPixel(value: try XCTUnwrap(read.qSize), units: read.qUnits), 0.026)
    }

    func testLaTeXUnitsAreReadAsTheUnitTheyName() async throws {
        let found = try await calibration(of: "latex-untitled.hspy")
        let read = try XCTUnwrap(found)
        XCTAssertEqual(read.qSize, 0.01261)
        XCTAssertEqual(read.qUnits, "A^-1")
        XCTAssertEqual(read.rSize, 2.0)
        XCTAssertEqual(read.rUnits, "nm")
        XCTAssertEqual(CalibrationUnitConversion.reciprocalInvAngstromPerPixel(value: try XCTUnwrap(read.qSize), units: read.qUnits), 0.01261)
    }

    /// Axes HyperSpy left at scale 1 and units "<undefined>" are no calibration: the rows stay "Not set".
    func testUndefinedAxesStayNotSet() async throws {
        let read = try await calibration(of: "undefined-axes.hspy")
        XCTAssertNil(read)
    }

    /// What the user sees on open: both scales "from file", in the app's own state.
    @MainActor
    func testOpeningTheFileSetsBothScalesFromTheFile() async throws {
        let reader = try H5Reader(path: Self.fixtures.appendingPathComponent("angstrom-titled.hdf5").path)
        let state = AppState()
        await state.activate(descriptor: try await reader.discoverPrimaryDataset(), reader: reader, runInitialAnalysis: false)
        XCTAssertEqual(state.calibrationSession.calibration.qPixelSize, 0.026)
        XCTAssertEqual(state.calibrationSession.calibration.rPixelSize, 1.536)
        XCTAssertEqual(state.calibrationSession.provenance.qScale, .importedFile)
        XCTAssertEqual(state.calibrationSession.provenance.rScale, .importedFile)
    }
}
