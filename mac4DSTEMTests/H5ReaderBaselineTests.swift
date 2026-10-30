import XCTest
import CryptoKit
import DSTEMCore

/// H5Reader's private libhdf5 code (`HDF5LegacyProbe`: chunk shape, link walk, float16, enum/bool; `HDF5SlabFile`: the slab read) onto FormatoKit's `HDF5Reader` (0.7.0), then its link walk onto `HDF5Reader.walk` and its slab read onto `HDF5SlabReader` (0.8.0) (2026-10-21,
/// D12: readers are tested exact). `Fixtures/H5Reader/*.json` was written by the app's reader with those shims (a4c8a610) BEFORE
/// they were deleted, over the h5py-written files of `Fixtures/H5Reader/make_fixtures.py` (calibration stored as enum, uint8, int,
/// double and float16 datasets and attributes; float16, big-endian and 64-bit element types; dim vectors; hard, soft, dangling
/// and cyclic links; chunked and rank-3 cubes; nodes that are not cubes) and, when on this machine, over the owner's real files:
/// the discovered node, chunk shape, calibration, probe candidates and a SHA-256 of every pattern, scan row and tile read through
/// the full-extent view and a scan-cropped, detector-cropped, 2x2-binned view.
final class H5ReaderBaselineTests: XCTestCase {

    private static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/H5Reader")

    private func hex(_ digest: SHA256.Digest) -> String { digest.map { String(format: "%02x", $0) }.joined() }
    private func sha(_ floats: [Float]) -> String { floats.withUnsafeBytes { hex(SHA256.hash(data: $0)) } }

    private func views(of d: DatasetDescriptor) throws -> [(String, LoadView)] {
        var out = [("full", LoadView(fullExtentOf: d))]
        let h = ((d.qy - 1) / 2) * 2, w = ((d.qx - 1) / 2) * 2
        if d.ry >= 2, d.rx >= 3, h >= 2, w >= 2 {
            out.append(("reduced", try LoadView(source: d, specification: LoadSpecification(
                scanCrop: AxisCrop(yOffset: 1, xOffset: 1, height: d.ry - 1, width: d.rx - 2),
                detectorCrop: AxisCrop(yOffset: 1, xOffset: 1, height: h, width: w), detectorBin: 2))))
        }
        return out
    }

    /// Reads of one described dataset.
    private func reads(_ reader: H5Reader, _ d: DatasetDescriptor, large: Bool) async throws -> [String: Any] {
        var out = [String: Any]()
        for (name, view) in try views(of: d) {
            let rows = view.descriptor.ry, cols = view.descriptor.rx
            var patterns = SHA256(), rowHash = SHA256(), tiles = SHA256()
            var count = 0
            let positions: [(Int, Int)] = large
                ? [(0, 0), (0, cols - 1), (rows - 1, 0), (rows - 1, cols - 1), (rows / 2, cols / 2)]
                : (0..<rows).flatMap { y in (0..<cols).map { (y, $0) } }
            for (y, x) in positions {
                let p = try await reader.readPattern(view, ry: y, rx: x)
                p.withUnsafeBytes { patterns.update(bufferPointer: $0) }; count += p.count
            }
            for y in (large ? [0, rows - 1] : Array(0..<rows)) {
                try await reader.readScanRow(view, ry: y).withUnsafeBytes { rowHash.update(bufferPointer: $0) }
            }
            var y = 0
            while y < (large ? min(rows, 2) : rows) {
                let upper = min(rows, y + 3)
                try await reader.readScanTile(view, yRange: y..<upper).pixels.withUnsafeBytes { tiles.update(bufferPointer: $0) }
                y = upper
            }
            out["\(name).patterns"] = [count, hex(patterns.finalize())]
            out["\(name).rows"] = hex(rowHash.finalize())
            out["\(name).tiles"] = hex(tiles.finalize())
            // The refusals of a read outside the view.
            do { _ = try await reader.readPattern(view, ry: rows, rx: 0); out["\(name).outside"] = "read" }
            catch { out["\(name).outside"] = "\(error)" }
        }
        return out
    }

    private func clean(_ text: String, _ url: URL) -> String { text.replacingOccurrences(of: url.deletingLastPathComponent().path, with: "") }

    private func snapshot(_ url: URL, large: Bool = false) async -> [String: Any] {
        var out = [String: Any]()
        let reader: H5Reader
        do { reader = try H5Reader(path: url.path) } catch { return ["openError": clean("\(error)", url)] }
        let d: DatasetDescriptor
        do { d = try await reader.discoverPrimaryDataset() } catch { return ["discoverError": clean("\(error)", url)] }
        out["path"] = d.datasetPath; out["shape"] = d.shape; out["dtype"] = d.dtypeDescription
        out["chunk"] = d.chunkShape.map { "\($0)" } ?? "nil"; out["storedRank"] = d.storedRank
        out["pushdown"] = "\(reader.loadPushdown(for: LoadView(fullExtentOf: d)))"
        out["calibration"] = await reader.pixelCalibration().map { "\($0)" } ?? "nil"
        out["voltage"] = await reader.readDoubleAttribute("voltage", onObjectPath: "/").map { "\($0)" } ?? "nil"
        var probes = [String]()
        for (qy, qx) in [(d.qy, d.qx), (5, 6)] {
            do {
                for c in try await reader.probeCandidates(detectorQY: qy, detectorQX: qx) {
                    let image = (try? await reader.readProbe(c)).map { sha($0) } ?? "unreadable"
                    probes.append("\(qy)x\(qx) \(c.path) \(c.sliceCount) \(c.slicesFirst) \(image)")
                }
            } catch { probes.append("error \(error)") }
        }
        out["probes"] = probes
        do { for (k, v) in try await reads(reader, d, large: large) { out[k] = v } } catch { out["readError"] = "\(error)" }
        return out
    }

    private func check(_ results: [String: [String: Any]], fixture: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let url = Self.fixtures.appendingPathComponent("\(fixture)-2026-10-21.json")
        if !FileManager.default.fileExists(atPath: url.path) {
            try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys, .prettyPrinted]).write(to: url)
            XCTFail("baseline written to \(url.path)", file: file, line: line); return
        }
        let base = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: [String: Any]]
        XCTAssertEqual(Set(results.keys), Set(base.keys), "files", file: file, line: line)
        for (name, new) in results {
            guard let old = base[name] else { continue }
            XCTAssertEqual(Set(new.keys), Set(old.keys), "\(name): keys", file: file, line: line)
            for (key, value) in old {
                let a = try JSONSerialization.data(withJSONObject: [value], options: [.sortedKeys])
                let b = try JSONSerialization.data(withJSONObject: [new[key] ?? NSNull()], options: [.sortedKeys])
                XCTAssertEqual(a, b, "\(name).\(key): \(String(describing: new[key])) vs baseline \(value)", file: file, line: line)
            }
        }
    }

    func testFixtureFilesReadByteForByteAsTheShimReaderReadThem() async throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: Self.fixtures.path).filter { $0.hasSuffix(".h5") }.sorted()
        var results = [String: [String: Any]]()
        for name in names where name != "dtypes.h5" { results[name] = await snapshot(Self.fixtures.appendingPathComponent(name)) }
        try check(results, fixture: "files")
    }

    /// Every stored element type, converted to Float the way `H5Dread` into `H5T_NATIVE_FLOAT` converted it.
    func testEveryStoredElementTypeConvertsToFloatAsBefore() async throws {
        let url = Self.fixtures.appendingPathComponent("dtypes.h5")
        let reader = try H5Reader(path: url.path)
        var results = [String: [String: Any]]()
        for name in ["int8", "uint8", "int16", "uint16", "int32", "uint32", "int64", "uint64", "float16", "float32", "float64",
                     "be_i2", "be_u2", "be_i4", "be_f4", "be_f8", "le_i2"] {
            var snap = [String: Any]()
            do {
                let d = try await reader.describe(path: "/dt/\(name)")
                snap["shape"] = d.shape; snap["dtype"] = d.dtypeDescription; snap["chunk"] = d.chunkShape.map { "\($0)" } ?? "nil"
                for (k, v) in try await reads(reader, d, large: false) { snap[k] = v }
            } catch { snap["error"] = "\(error)" }
            results[name] = snap
        }
        try check(results, fixture: "dtypes")
    }

    // MARK: Real files (skipped when absent)

    private static let data = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("References")

    private func real(_ relative: String) async throws {
        let url = Self.data.appendingPathComponent(relative)
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path), "\(relative) is not on this machine")
        let name = url.lastPathComponent
        try check([name: await snapshot(url, large: true)], fixture: "real-" + name.replacingOccurrences(of: " ", with: "_"))
    }

    func testRealAlMgSi() async throws { try await real("training_dataset/Al_Mg_Si_060_STEM SI_preprocessed_unfiltered_bin_4_20260712.h5") }
    func testRealAlMgSiSidecar() async throws { try await real("training_dataset/Al_Mg_Si_060_STEM SI_preprocessed_unfiltered_bin_4_20260712.mac4dstem.h5") }
    func testRealAlMgSiEllipse() async throws { try await real("training_dataset/Al_Mg_Si_060_STEM SI_preprocessed_unfiltered_bin_4_20260712_ellipse-20260925.h5") }
    func testRealAuRef() async throws { try await real("training_dataset/Au_ref_ROI15_preprocessed_unfiltered_bin_4_20241214.h5") }
    func testRealParticle() async throws { try await real("training_dataset/Particle_1_Stack_1_45x90_ss30nm_0p09s_spot8_alpha=0p48_bin2_cl-600mm_300kV_bin8.h5") }
    func testRealSiSiGe() async throws { try await real("training_dataset/Si-SiGe_calibrated.h5") }
    func testRealBullseye() async throws { try await real("training_dataset/calibrationData_bullseyeProbe.h5") }
    func testRealBullseyeSidecar() async throws { try await real("training_dataset/calibrationData_bullseyeProbe.mac4dstem.h5") }
    func testRealDownsampleSiSiGe() async throws { try await real("training_dataset/downsample_Si_SiGe_exp.h5") }
    func testRealPolycrystalWS2() async throws { try await real("training_dataset/polycrystal_2D_WS2.h5") }
    func testRealSimAu() async throws { try await real("training_dataset/sim_Au_data_all_binned.h5") }
    func testRealAuSim() async throws { try await real("../CuboKit/py4dstem-test-data/Au_sim.h5") }
    func testRealDemoEDXSingle() async throws { try await real("demo-edx/AlMgSi_4D_EDX_single.h5") }
    func testRealDemoEDXSidecar() async throws { try await real("demo-edx/AlMgSi_4D_EDX.mac4dstem.h5") }

    /// Not an assertion: timings for the switch's record, appended to MAC4DSTEM_PERF_LOG when set.
    func testPrintTimings() async throws {
        let url = Self.data.appendingPathComponent("../CuboKit/py4dstem-test-data/Au_sim.h5")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path))
        let reader = try H5Reader(path: url.path)
        let t0 = Date()
        let d = try await reader.discoverPrimaryDataset()
        let discover = Date().timeIntervalSince(t0)
        let view = LoadView(fullExtentOf: d)
        var pattern = Double.infinity, rowBest = Double.infinity, tile = Double.infinity
        for _ in 0..<3 {
            let a = Date()
            for i in 0..<50 { _ = try await reader.readPattern(view, ry: i % d.ry, rx: (i * 7) % d.rx) }
            pattern = min(pattern, Date().timeIntervalSince(a) / 50)
            let b = Date()
            _ = try await reader.readScanRow(view, ry: d.ry / 2)
            rowBest = min(rowBest, Date().timeIntervalSince(b))
            let c = Date()
            _ = try await reader.readScanTile(view, yRange: 0..<min(d.ry, 4))
            tile = min(tile, Date().timeIntervalSince(c))
        }
        let line = "PERF Au_sim.h5 shape \(d.shape) \(d.dtypeDescription) chunk \(String(describing: d.chunkShape)): discover \(discover) s, pattern \(pattern) s, row \(rowBest) s, 4-row tile \(tile) s"
        print(line)
        if let log = ProcessInfo.processInfo.environment["MAC4DSTEM_PERF_LOG"] {
            FileManager.default.createFile(atPath: log, contents: nil)
            if let handle = FileHandle(forWritingAtPath: log) {
                handle.seekToEndOfFile(); handle.write(Data((line + "\n").utf8)); try? handle.close()
            }
        }
    }
}
