import XCTest
import CryptoKit
import DSTEMCore
@testable import SpectroCore

/// v5.0 WP2 lane S: the simulated 4D-STEM + EDX dataset (`../_archive/mac4DSTEM/tools/demo-edx/`). The fixture is the TINY variant
/// (6 x 4 scan, 16 x 16 detector, 512 channels at 20 eV, a perturbed energy axis, two 30 %-dead rows; 123 kB) written by `sim_edx.py --tiny` in the GMS
/// multi-object layout of `../_archive/mac4DSTEM/docs/archive/v5/4d-edx-file-structure-2026-10-05.md` §4a, next to its truth file.
/// The truth carries the SHA-256 of every array as WRITTEN (C order of the logical shape), so these tests compare
/// what our readers return to what the generator wrote, and the scan is not square (6 != 4) so an axis swap shows.
/// Every layout detail the file asserts is a GUESS until a real GMS 4D + EDS file exists (truth `guesses`).
final class DemoEDXFixtureTests: XCTestCase {

    private static let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures")
    private static var dm4: String { dir.appendingPathComponent("demo-edx-tiny.dm4").path }

    private func truth() throws -> [String: Any] {
        let data = try Data(contentsOf: Self.dir.appendingPathComponent("demo-edx-tiny.truth.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    private func hash(_ truth: [String: Any], _ key: String) throws -> String {
        let hashes = try XCTUnwrap(truth["array_sha256_of_written_arrays_C_order"] as? [String: String])
        return try XCTUnwrap(hashes[key])
    }
    private func hex(_ digest: SHA256.Digest) -> String { digest.map { String(format: "%02x", $0) }.joined() }
    private func object(_ objects: [DM4ImageObject], _ role: DM4ImageRole) throws -> DM4ImageObject {
        try XCTUnwrap(objects.first { $0.role == role }, "no \(role) object")
    }

    func testDM4ReaderOpensTheDiffractionSIAsA4DCubeEqualToWhatWasWritten() async throws {
        let t = try truth()
        let reader = try await DM4Reader(path: Self.dm4)
        let descriptor = try await reader.discoverPrimaryDataset()
        XCTAssertEqual(descriptor.shape, [4, 6, 16, 16], "[ry, rx, qy, qx] with a non-square scan")
        XCTAssertEqual(descriptor.dtypeDescription, "float32")
        XCTAssertEqual(descriptor.datasetPath, "ImageList.4.ImageData.Data")
        let view = LoadView(fullExtentOf: descriptor)
        var hasher = SHA256()
        for ry in 0..<4 {
            for rx in 0..<6 {
                let pattern = try await reader.readPattern(view, ry: ry, rx: rx)
                XCTAssertEqual(pattern.count, 256)
                pattern.withUnsafeBytes { hasher.update(bufferPointer: $0) }   // little-endian host
            }
        }
        XCTAssertEqual(hex(hasher.finalize()), try hash(t, "diffraction_ny_nx_qy_qx_float32"))
        let calibration = try await XCTUnwrap(reader.pixelCalibration())
        XCTAssertEqual(calibration.qUnits, "1/nm")
        XCTAssertEqual(try XCTUnwrap(calibration.qSize), 0.96, accuracy: 1e-6)
        XCTAssertEqual(calibration.rUnits, "nm")
        XCTAssertEqual(try XCTUnwrap(calibration.rSize), 5, accuracy: 1e-6)
    }

    /// The full default dataset (`../_archive/mac4DSTEM/tools/demo-edx/run.sh`, 254 MB) when it is on this machine: same checks at scale.
    func testTheDefaultSimulatedFileWhenPresent() async throws {
        let path = Self.dir.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("References/demo-edx/AlMgSi_4D_EDX.dm4").path
        try XCTSkipUnless(FileManager.default.fileExists(atPath: path), "References/demo-edx not generated")
        let objects = try DM4Experiment.list(path: path)
        XCTAssertEqual(objects.map(\.role), [.thumbnail, .survey, .scanSignal, .diffraction, .eds])
        XCTAssertEqual(DM4Experiment.experimentIDs(in: objects).count, 1)
        XCTAssertEqual(try object(objects, .scanSignal).dimensions, [64, 48])
        XCTAssertEqual(try object(objects, .diffraction).dimensions, [128, 128, 64, 48])
        XCTAssertEqual(try object(objects, .eds).dimensions, [64, 48, 4096])
        let rect = try XCTUnwrap(try object(objects, .eds).spectrumImageRect)
        XCTAssertEqual(rect.width / rect.height, 64.0 / 48.0, accuracy: 1e-12)
        XCTAssertEqual(rect.width, 320); XCTAssertEqual(rect.height, 240)
        let reader = try await DM4Reader(path: path)
        let descriptor = try await reader.discoverPrimaryDataset()
        XCTAssertEqual(descriptor.shape, [48, 64, 128, 128])
        let view = LoadView(fullExtentOf: descriptor)
        let p = try await reader.readPattern(view, ry: 47, rx: 63)
        XCTAssertEqual(p.count, 128 * 128)
        XCTAssertGreaterThan(p.max() ?? 0, 0)
    }
}
