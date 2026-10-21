// ROADMAP task 6: Open routes by content (FormatoKit's sniff), an .msa spectrum opens in the Spectroscopy room and the room writes
// one back. One routing test per format family, including the refusals and the HDF5-by-signature fallback.

import XCTest
import DSTEMCore
import SpectroCore
@testable import mac4DSTEM

@MainActor
final class FileRoutingTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("routing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func file(_ name: String, _ bytes: [UInt8]) throws -> String {
        let url = dir.appendingPathComponent(name)
        try Data(bytes).write(to: url)
        return url.path
    }
    private let hdf5: [UInt8] = [0x89, 0x48, 0x44, 0x46, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0]

    func testEveryFormatFamilyRoutesByContent() throws {
        XCTAssertEqual(FileRouting.route(path: try file("a.dm4", [0, 0, 0, 4, 0, 0, 0, 0])), .digitalMicrograph)
        XCTAssertEqual(FileRouting.route(path: try file("a.dm3", [0, 0, 0, 3, 0, 0, 0, 0])), .digitalMicrograph)
        XCTAssertEqual(FileRouting.route(path: try file("a.mib", [1, 2, 3, 4])), .merlinMIB)
        XCTAssertEqual(FileRouting.route(path: try file("a.xml", [60, 63])), .empad)
        XCTAssertEqual(FileRouting.route(path: try file("a.raw", [1, 2, 3, 4])), .empad, "the EMPAD data file the kit does not name")
        XCTAssertEqual(FileRouting.route(path: try file("a.h5", hdf5)), .hdf5)
        XCTAssertEqual(FileRouting.route(path: try file("a.emd", hdf5)), .hdf5)
        XCTAssertEqual(FileRouting.route(path: try file("a.msa", Array("#FORMAT : EMSA/MAS Spectral Data File\n".utf8))), .singleSpectrum)
    }

    func testImagesAndUnknownFilesAreRefusedWithASentenceNamingTheFile() throws {
        guard case .refused(let tiff) = FileRouting.route(path: try file("im.tif", [0x49, 0x49, 42, 0, 8, 0, 0, 0])) else { return XCTFail() }
        XCTAssertTrue(tiff.contains("im.tif") && tiff.contains("TIFF"), tiff)
        guard case .refused(let mrc) = FileRouting.route(path: try file("v.mrc", [0, 0, 0, 0, 0, 0, 0, 0])) else { return XCTFail() }
        XCTAssertTrue(mrc.contains("MRC"), mrc)
        guard case .refused(let other) = FileRouting.route(path: try file("notes.txt", Array("hello".utf8))) else { return XCTFail() }
        XCTAssertTrue(other.contains("notes.txt"), other)
        // The kit's dedicated-reader refusal: extension and bytes disagree (a .dm4 that is not DM) falls to the signature check.
        guard case .refused = FileRouting.route(path: try file("fake.dm4", [1, 2, 3, 4, 5, 6, 7, 8])) else { return XCTFail() }
    }

    func testAnUnknownExtensionWithAnHDF5SignatureStillGoesToTheHDF5Reader() throws {
        XCTAssertEqual(FileRouting.route(path: try file("data.py4dstem", hdf5)), .hdf5)
        XCTAssertEqual(FileRouting.route(path: try file("wrongext.dm4", hdf5)), .hdf5, "the bytes win over the extension")
    }

    func testOpenRefusesWhatIsNotA4DDatasetInTheRoutesWords() async throws {
        let tif = try file("im.tif", [0x49, 0x49, 42, 0, 8, 0, 0, 0])
        do { _ = try await AppState.makeReader(for: URL(fileURLWithPath: tif)); XCTFail("a TIFF is not a cube") }
        catch { XCTAssertTrue((error as? LocalizedError)?.errorDescription?.contains("TIFF") == true) }
        let msa = try file("s.msa", Array("x".utf8))
        do { _ = try await AppState.makeReader(for: URL(fileURLWithPath: msa)); XCTFail("a spectrum is not a cube") }
        catch { XCTAssertTrue((error as? LocalizedError)?.errorDescription?.contains("single spectrum") == true) }
    }

    // MARK: .msa through the room

    private func plantedCounts() -> [Double] {
        var out = [Double](repeating: 0, count: 1024)
        for i in 0..<1024 { out[i] = Double(50 + i % 37) }
        out[148] += 4000
        return out
    }

    /// The round trip the task asks for: a planted spectrum written as .msa, opened as a spectrum image, shown by the room,
    /// written by the room's export, and read back with the same counts and axis.
    func testAPlantedMSARoundTripsThroughTheRoomsExport() async throws {
        let counts = plantedCounts()
        let first = try FileRouting.msaData(counts: counts, offsetKeV: -0.04, scaleKeV: 0.01, title: "planted", beamEnergyKeV: 200)
        let path = dir.appendingPathComponent("planted.msa").path
        try first.write(to: URL(fileURLWithPath: path))

        let image = try FileRouting.spectrumImage(msaPath: path)
        XCTAssertEqual(image.sum(mask: nil), counts.map { UInt64($0) })
        XCTAssertEqual(image.energyAxis.offset, -0.04, accuracy: 1e-9)
        XCTAssertEqual(image.energyAxis.scale, 0.01, accuracy: 1e-12)
        XCTAssertEqual(image.metadata.beamEnergyKeV, 200)
        XCTAssertEqual([image.nx, image.ny], [1, 1])

        let state = AppState()
        state.openSpectrumImage(image)
        state.spectroscopyRoom.autoIDOnOpen?.cancel()
        await state.spectroscopyRoom.refresh()?.value
        let export = try XCTUnwrap(ExportSection.spectrumMSAExport(state.spectroscopyRoom.model), "the room offers the shown spectrum as .msa")
        XCTAssertTrue(export.isMSA)
        let second = dir.appendingPathComponent("again.msa")
        try Data(export.text.utf8).write(to: second)
        let back = try FileRouting.spectrumImage(msaPath: second.path)
        XCTAssertEqual(back.sum(mask: nil), counts.map { UInt64($0) }, "counts survive the room's export")
        XCTAssertEqual(back.energyAxis.offset, -0.04, accuracy: 1e-9)
        XCTAssertEqual(back.energyAxis.scale, 0.01, accuracy: 1e-12)
    }

    func testAMSAWithNegativeCountsIsRefused() throws {
        let data = try FileRouting.msaData(counts: [1, -2, 3], offsetKeV: 0, scaleKeV: 0.01, title: "bad", beamEnergyKeV: nil)
        let path = dir.appendingPathComponent("bad.msa").path
        try data.write(to: URL(fileURLWithPath: path))
        XCTAssertThrowsError(try FileRouting.spectrumImage(msaPath: path))
    }
}

// MARK: Velox single spectra (real files under References/, not committed: skipped when absent)

@MainActor
final class VeloxSingleSpectrumTests: XCTestCase {
    private func reference(_ relative: String) throws -> String {
        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("References/velox-parity/" + relative).path
        guard FileManager.default.fileExists(atPath: path) else { throw XCTSkip("References/velox-parity/\(relative) is not on this machine") }
        return path
    }

    /// `fei_emd_spectrum.emd` (Velox v4, one 4096-channel EDX spectrum): a one-pixel spectrum image with the file's axis, its counts
    /// and the beam energy it states; live and real time ride along when the kit maps them.
    func testTheVeloxSpectrumOpensAsAOnePixelImageWithItsTimes() throws {
        let path = try reference("fei_emd_files/fei_emd_spectrum.emd")
        let opened = try XCTUnwrap(FileRouting.veloxSpectrum(path: path), "the kit reads one spectrum from this file")
        XCTAssertEqual([opened.image.nx, opened.image.ny, opened.image.channels], [1, 1, 4096])
        XCTAssertGreaterThan(opened.image.energyAxis.scale, 0)
        XCTAssertGreaterThan(opened.image.sum(mask: nil).reduce(0, +), 0)
        // The kit's single-spectrum reader maps no live or real time for this v4 file (its `Detector` metadata sits elsewhere): the
        // times are nil here and stay a kit ask (`docs/open-items.md`); when the kit maps them they are non-negative and live <= real.
        if let live = opened.liveTimeSeconds, let real = opened.realTimeSeconds { XCTAssertLessThanOrEqual(live, real * 1.0001) }
        XCTAssertGreaterThan(opened.image.metadata.beamEnergyKeV ?? 0, 0, "the file states its beam energy")
        XCTAssertEqual(opened.image.metadata.origin, .veloxEMD)
    }

    func testAnImageOnlyVeloxFileIsNotASingleSpectrum() throws {
        let path = try reference("fei_emd_files/fei_emd_image.emd")
        XCTAssertNil(FileRouting.veloxSpectrum(path: path))
    }
}
