import XCTest
import CryptoKit
import DSTEMCore

/// v5.0 WP2 lane S: the simulated 4D-STEM + EDX dataset (`tools/demo-edx/`). The fixture is the TINY variant
/// (6 x 4 scan, 16 x 16 detector, 512 channels at 20 eV; 115 kB) written by `sim_edx.py --tiny` in the GMS
/// multi-object layout of `docs/archive/v5/4d-edx-file-structure-2026-10-05.md` §4a, next to its truth file.
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

    func testTheFixtureListsFiveObjectsInOrderUnderOneExperiment() throws {
        let objects = try DM4Experiment.list(path: Self.dm4)
        XCTAssertEqual(objects.map(\.role), [.thumbnail, .survey, .scanSignal, .diffraction, .eds])
        XCTAssertEqual(objects.map(\.index), [1, 2, 3, 4, 5])
        XCTAssertEqual(objects.map(\.name), ["Image Of demo-edx-tiny.dm4", "ADF Image (SI Survey)", "HAADF Image",
                                             "Diffraction SI", "EDS SI"])
        XCTAssertEqual(objects.map(\.dataTypeName), ["rgba8", "uint16", "float32", "float32", "uint32"])
        // Roles come from the root thumbnail list and the Experiment-keywords labels, not from names or types.
        XCTAssertEqual(objects.map(\.roleSource), [.thumbnailIndex, .label, .label, .label, .label])
        // The thumbnail has no Meta Data group, so no Experiment ID; the four other objects share one.
        XCTAssertEqual(DM4Experiment.experimentIDs(in: objects), ["Spectrum Imaging_10/05/2026_10:00:00 AM"])
        XCTAssertEqual(DM4Experiment.objects(inExperiment: "Spectrum Imaging_10/05/2026_10:00:00 AM", of: objects).map(\.index),
                       [2, 3, 4, 5])
        // Dimensions are fastest first: 6 x 4 scan (nx != ny), detector 16 x 16, 512 channels.
        XCTAssertEqual(try object(objects, .survey).dimensions, [64, 64])
        XCTAssertEqual(try object(objects, .scanSignal).dimensions, [6, 4])
        XCTAssertEqual(try object(objects, .diffraction).dimensions, [16, 16, 6, 4])
        XCTAssertEqual(try object(objects, .eds).dimensions, [6, 4, 512])
    }

    func testTheRectAndTheSurveyLinkOfEverySIObjectMatchTheTruth() throws {
        let objects = try DM4Experiment.list(path: Self.dm4)
        let survey = try object(objects, .survey)
        let truthRect = try XCTUnwrap(((try truth()["edx"]) as? [String: Any])?["rect_survey_pixels_top_left_bottom_right"] as? [Double])
        XCTAssertEqual(truthRect, [24, 14, 44, 44])           // top, left, bottom, right: asymmetric on purpose
        for role in [DM4ImageRole.scanSignal, .diffraction, .eds] {
            let si = try object(objects, role)
            let rect = try XCTUnwrap(si.spectrumImageRect, "\(role)")
            XCTAssertEqual([rect.top, rect.left, rect.bottom, rect.right], truthRect, "\(role)")
            XCTAssertEqual(rect.width / rect.height, 6.0 / 4.0, accuracy: 1e-12, "the rect's aspect is the scan's, \(role)")
            XCTAssertEqual(si.surveyImageID, survey.uniqueID, "\(role)")
            XCTAssertEqual(DM4Experiment.survey(for: si, in: objects)?.index, survey.index, "\(role)")
        }
        XCTAssertNil(survey.spectrumImageRect, "the rect sits on the SI objects, not on the survey")
    }

    func testTheEDSObjectCarriesTheDetectorTagsAndTheEnergyAxis() throws {
        let objects = try DM4Experiment.list(path: Self.dm4)
        let eds = try object(objects, .eds)
        let tags = try XCTUnwrap(eds.eds)
        XCTAssertEqual(tags.azimuthDegrees, 45)
        XCTAssertEqual(tags.elevationDegrees, 18)
        XCTAssertEqual(try XCTUnwrap(tags.solidAngle), 0.7, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(tags.realTime), 6 * 4 * 1.0e-3, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(tags.liveTime), 6 * 4 * 1.0e-3 * 0.95, accuracy: 1e-6)
        // Energy axis: E = (i - 23.9) * 0.02 keV on 512 channels (the tiny file's 20 eV pitch).
        let energy = try XCTUnwrap(eds.axes[2])
        XCTAssertEqual(energy.units, "keV")
        XCTAssertEqual(energy.origin, 23.9, accuracy: 1e-5)
        XCTAssertEqual(energy.scale, 0.02, accuracy: 1e-7)
        XCTAssertEqual(try XCTUnwrap(eds.axes[0]).units, "nm")
        XCTAssertEqual(try XCTUnwrap(eds.axes[0]).scale, 5, accuracy: 1e-6)
        let diffraction = try object(objects, .diffraction)
        XCTAssertEqual(try XCTUnwrap(diffraction.axes[0]).units, "1/nm")
        XCTAssertEqual(try XCTUnwrap(diffraction.axes[0]).scale, 0.96, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(diffraction.axes[0]).origin, 7.5, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(diffraction.axes[3]).units, "nm")
    }

    func testTheSurveyAndTheScanImageReadBackEqualToWhatWasWritten() throws {
        let t = try truth()
        let objects = try DM4Experiment.list(path: Self.dm4)
        let survey = try DM4Experiment.readImage(path: Self.dm4, index: try object(objects, .survey).index)
        XCTAssertEqual([survey.width, survey.height], [64, 64])
        var bytes = Data()
        for p in survey.pixels { var v = UInt16(p).littleEndian; bytes.append(Data(bytes: &v, count: 2)) }
        XCTAssertEqual(hex(SHA256.hash(data: bytes)), try hash(t, "survey_uint16"))
        let haadf = try DM4Experiment.readImage(path: Self.dm4, index: try object(objects, .scanSignal).index)
        XCTAssertEqual([haadf.width, haadf.height], [6, 4], "x is the fast axis and the scan is not square")
        var fbytes = Data()
        for p in haadf.pixels { var v = p.bitPattern.littleEndian; fbytes.append(Data(bytes: &v, count: 4)) }
        XCTAssertEqual(hex(SHA256.hash(data: fbytes)), try hash(t, "haadf_ny_nx_float32"))
        // 3D and 4D objects are listed, never decoded here.
        XCTAssertThrowsError(try DM4Experiment.readImage(path: Self.dm4, index: try object(objects, .eds).index))
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

    func testTheEDSBlobIsEnergySlowestAndItsPerRecipeSumsMatchTheTruthMap() throws {
        // Memory order of the EDS SI is (channel, y, x) with x fastest: a swapped nx/ny reads the wrong recipe's counts.
        let t = try truth()
        let objects = try DM4Experiment.list(path: Self.dm4)
        let eds = try object(objects, .eds)
        XCTAssertEqual(eds.dataByteCount, 6 * 4 * 512 * 4)
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: Self.dm4))
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(eds.dataOffset))
        let raw = try XCTUnwrap(try handle.read(upToCount: eds.dataByteCount))
        XCTAssertEqual(raw.count, eds.dataByteCount)
        let counts: [UInt32] = raw.withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) }
        let map = try XCTUnwrap(t["recipe_map"] as? [[Int]])
        XCTAssertEqual(map.count, 4); XCTAssertEqual(map[0].count, 6)
        let names = try XCTUnwrap(t["recipe_names_in_map_order"] as? [String])
        let recipes = try XCTUnwrap(t["recipes"] as? [String: [String: Any]])
        var sums = [Int](repeating: 0, count: names.count)
        for ch in 0..<512 { for y in 0..<4 { for x in 0..<6 {
            sums[map[y][x]] += Int(counts[(ch * 4 + y) * 6 + x])
        } } }
        for (i, name) in names.enumerated() {
            XCTAssertEqual(sums[i], recipes[name]?["realised_total_eds_counts"] as? Int, name)
        }
        let totals = try XCTUnwrap(t["totals_written"] as? [String: Any])
        XCTAssertEqual(counts.reduce(0) { $0 + Int($1) }, totals["eds_counts"] as? Int)
        XCTAssertEqual(names.count, 13, "the tiny scan holds one pixel of every recipe or more")
    }

    /// The full default dataset (`tools/demo-edx/run.sh`, 254 MB) when it is on this machine: same checks at scale.
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
