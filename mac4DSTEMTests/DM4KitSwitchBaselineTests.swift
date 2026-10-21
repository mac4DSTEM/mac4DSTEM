import XCTest
import CryptoKit
import DSTEMCore
import FormatoDM

/// The DM4Reader onto FormatoKit 0.7.0's `DM4Datacube` switch (2026-10-21, D12: readers are tested exact).
/// `Fixtures/DM4/dm4-baseline-2026-10-21.json` was written by the app's own DM4 parser and gather (`DM4Reader.swift` at a4c8a610)
/// BEFORE it was deleted: for each synthetic file below (every pixel type, detector-fastest and scan-fastest storage, a rank-3
/// scan-shaped object, calibration forms, unnamed and thumbnail entries) and, when present on this machine, for the real files
/// of `References/`, the descriptor, calibration, load-pushdown and a SHA-256 of every pattern, scan row and tile read through the
/// full-extent view and through a scan-cropped, detector-cropped and 2x2-binned view. The kit's gather must reproduce every byte.
final class DM4KitSwitchBaselineTests: XCTestCase {

    // MARK: Synthetic DM4 writer (version 4; structure fields big-endian, values little-endian)

    private indirect enum Node {
        case int(String, Int32)
        case float(String, Float)
        case string18(String, String)
        case ushortText(String, String)               // GMS's own: a ushort array holding the characters
        case group(String, [Node])                    // "" label = unnamed (one-based position)
        case array(String, elementType: UInt64, count: Int, bytes: [UInt8])
    }

    private nonisolated static func u16be(_ v: Int) -> [UInt8] { [UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
    private nonisolated static func u64be(_ v: UInt64) -> [UInt8] { (0..<8).map { UInt8((v >> UInt64(56 - 8 * $0)) & 0xFF) } }
    private nonisolated static func le(_ v: UInt64, _ n: Int) -> [UInt8] { (0..<n).map { UInt8((v >> UInt64(8 * $0)) & 0xFF) } }
    private nonisolated static let delim: [UInt8] = [37, 37, 37, 37]
    private nonisolated static func head(_ tag: UInt8, _ label: String) -> [UInt8] {
        [tag] + u16be(label.utf8.count) + Array(label.utf8) + u64be(0)
    }

    private nonisolated static func encode(_ node: Node) -> [UInt8] {
        switch node {
        case .int(let l, let v):
            return head(21, l) + delim + u64be(1) + u64be(3) + le(UInt64(UInt32(bitPattern: v)), 4)
        case .float(let l, let v):
            return head(21, l) + delim + u64be(1) + u64be(6) + le(UInt64(v.bitPattern), 4)
        case .string18(let l, let s):
            let bytes = Array(s.utf8)
            return head(21, l) + delim + u64be(2) + u64be(18) + u64be(UInt64(bytes.count)) + bytes
        case .ushortText(let l, let s):
            let units = Array(s.utf16)
            return head(21, l) + delim + u64be(3) + u64be(20) + u64be(4) + u64be(UInt64(units.count))
                + units.flatMap { le(UInt64($0), 2) }
        case .group(let l, let kids):
            return head(20, l) + [1, 0] + u64be(UInt64(kids.count)) + kids.flatMap(encode)
        case .array(let l, let type, let count, let bytes):
            return head(21, l) + delim + u64be(3) + u64be(20) + u64be(type) + u64be(UInt64(count)) + bytes
        }
    }

    private nonisolated static func file(_ rootChildren: [Node]) -> Data {
        let body: [UInt8] = [1, 0] + u64be(UInt64(rootChildren.count)) + rootChildren.flatMap(encode)
        return Data([0, 0, 0, 4] + u64be(0) + [0, 0, 0, 1] + body)
    }

    // MARK: Pixel types

    /// `DataType` code, the array tag's element type code, bytes per pixel.
    private nonisolated static func pixelType(_ name: String) -> (code: Int32, element: UInt64, size: Int) {
        switch name {
        case "int16": return (1, 2, 2)
        case "float32": return (2, 6, 4)
        case "uint8": return (6, 8, 1)
        case "int32": return (7, 3, 4)
        case "int8": return (9, 10, 1)
        case "uint16": return (10, 4, 2)
        case "uint32": return (11, 5, 4)
        default: return (12, 7, 8)       // float64
        }
    }

    /// Deterministic pixels that use the whole range of the type (signs, values past 2^24, awkward doubles, NaN, -0, subnormals).
    private nonisolated static func pixels(_ name: String, count: Int) -> [UInt8] {
        var state: UInt64 = 0x9E3779B97F4A7C15 &+ UInt64(count)
        func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state >> 11
        }
        var out = [UInt8](); out.reserveCapacity(count * 8)
        for i in 0..<count {
            let r = next()
            switch name {
            case "int16": out += le(r & 0xFFFF, 2)
            case "uint16": out += le(r & 0xFFFF, 2)
            case "uint8", "int8": out += le(r & 0xFF, 1)
            case "int32": out += le(r & 0xFFFF_FFFF, 4)
            case "uint32": out += le(r & 0xFFFF_FFFF, 4)
            case "float32":
                let special: [UInt32] = [0x7FC0_0001, 0x8000_0000, 0x0000_0001, 0x7F80_0000, 0xFF80_0000]
                out += le(UInt64(i % 97 == 5 ? special[(i / 97) % special.count] : Float(Int32(truncatingIfNeeded: r) / 3).bitPattern), 4)
            default:
                out += le(i % 89 == 7 ? 0x7FF8_0000_0000_0001 : (Double(Int64(bitPattern: r)) / 7.0).bitPattern, 8)
            }
        }
        return out
    }

    // MARK: Cases

    private struct Case {
        var name: String
        var type = "int16"
        /// `Dimensions.0...` in file order, fastest first.
        var dims: [Int32]
        var units: [String]? = nil
        var scales: [Float] = [1, 1, 1, 1]
        var scanShape: (x: Float, y: Float)? = nil        // a rank-3 object's "Scan shape X/Y" tags
        var voltage: Float? = 300_000
        var unitsAsUShort = false
        var imageListPrefix: [Node] = []                  // earlier ImageList entries (a thumbnail, a 2D image)
    }

    private nonisolated static func build(_ c: Case) -> Data {
        let t = pixelType(c.type)
        let count = c.dims.reduce(1) { $0 * Int($1) }
        var imageData: [Node] = [
            .int("DataType", t.code),
            .group("Dimensions", c.dims.enumerated().map { .int("\($0.offset)", $0.element) }),
        ]
        if let units = c.units {
            imageData.append(.group("Calibrations", [.group("Dimension", units.enumerated().map { i, u in
                .group("\(i)", [.float("Origin", 0), .float("Scale", c.scales[i]),
                                c.unitsAsUShort ? .ushortText("Units", u) : .string18("Units", u)])
            })]))
        }
        imageData.append(.array("Data", elementType: t.element, count: count, bytes: pixels(c.type, count: count)))
        var tags: [Node] = []
        if let v = c.voltage { tags.append(.group("Microscope Info", [.float("Voltage", v)])) }
        if let s = c.scanShape { tags.append(.group("Acquisition", [.float("Scan shape X", s.x), .float("Scan shape Y", s.y)])) }
        let object = Node.group("", [.group("ImageData", imageData), .group("ImageTags", tags)])
        return file([.group("ImageList", c.imageListPrefix + [object])])
    }

    private nonisolated static func cases() -> [Case] {
        var out = [Case]()
        let types = ["int16", "float32", "uint8", "int32", "int8", "uint16", "uint32", "float64"]
        for type in types {
            out.append(Case(name: "detector-fastest-\(type)", type: type, dims: [7, 5, 4, 3],
                            units: ["1/nm", "1/nm", "nm", "nm"], scales: [0.04, 0.04, 2.5, 2.5]))
        }
        for type in ["uint16", "float32", "int32", "float64", "uint8"] {
            out.append(Case(name: "scan-fastest-\(type)", type: type, dims: [9, 5, 3, 7],
                            units: ["nm", "nm", "1/nm", "1/nm"], scales: [1.5, 1.5, 0.02, 0.02]))
        }
        out.append(Case(name: "scan-fastest-few-positions", type: "uint16", dims: [3, 2, 4, 5],
                        units: ["nm", "nm", "mrad", "mrad"], scales: [2, 2, 0.5, 0.5]))
        out.append(Case(name: "scan-fastest-ushort-units", type: "int16", dims: [6, 7, 3, 4],
                        units: ["µm", "um", "1/Å", "1/nm"], scales: [0.5, 0.5, 0.1, 0.1], unitsAsUShort: true))
        out.append(Case(name: "no-calibration", type: "uint16", dims: [6, 4, 3, 2], units: nil, voltage: nil))
        out.append(Case(name: "contradictory", type: "int16", dims: [2, 2, 2, 2], units: ["nm", "nm", "nm", "nm"]))
        out.append(Case(name: "mixed-pair", type: "int16", dims: [2, 3, 4, 5], units: ["nm", "1/nm", "1/nm", "1/nm"]))
        out.append(Case(name: "partial-units", type: "int16", dims: [2, 3, 4, 5], units: ["nm", "pixel", "1/nm", "1/nm"]))
        out.append(Case(name: "both-reciprocal", type: "int16", dims: [2, 3, 4, 5], units: ["1/nm", "1/nm", "mrad", "mrad"]))
        out.append(Case(name: "reciprocal-leading", type: "float32", dims: [5, 4, 3, 3], units: ["mrad", "mrad", "nm", "nm"],
                        scales: [0.3, 0.3, 4, 4]))
        out.append(Case(name: "rank3-uint16", type: "uint16", dims: [7, 5, 12], units: ["1/nm", "1/nm", ""],
                        scales: [0.05, 0.05, 1, 1], scanShape: (4, 3)))
        out.append(Case(name: "rank3-float32", type: "float32", dims: [7, 5, 12], units: ["1/nm", "1/nm", "nm"],
                        scales: [0.05, 0.05, 2, 1], scanShape: (3, 4)))
        out.append(Case(name: "rank3-no-scan-tags", type: "uint16", dims: [7, 5, 12], units: nil))
        // Earlier objects the walk must pass over: a 2D image and a thumbnail-like small cube.
        let small = Node.group("", [.group("ImageData", [
            .int("DataType", 1), .group("Dimensions", [.int("0", 2), .int("1", 2)]),
            .array("Data", elementType: 2, count: 4, bytes: [1, 0, 2, 0, 3, 0, 4, 0]),
        ])])
        out.append(Case(name: "after-a-2d-image", type: "uint16", dims: [4, 3, 2, 2], units: ["1/nm", "1/nm", "nm", "nm"],
                        scales: [0.1, 0.1, 3, 3], imageListPrefix: [small]))
        return out
    }

    // MARK: Snapshots

    private func hex(_ digest: SHA256.Digest) -> String { digest.map { String(format: "%02x", $0) }.joined() }

    private func sha(_ floats: [Float]) -> String {
        floats.withUnsafeBytes { hex(SHA256.hash(data: $0)) }
    }

    private func bits(_ value: Double?) -> Any { value.map { String($0.bitPattern, radix: 16) } ?? NSNull() }

    private func views(of descriptor: DatasetDescriptor) throws -> [(String, LoadView)] {
        var out = [("full", LoadView(fullExtentOf: descriptor))]
        let ry = descriptor.ry, rx = descriptor.rx, qy = descriptor.qy, qx = descriptor.qx
        let h = ((qy - 1) / 2) * 2, w = ((qx - 1) / 2) * 2
        if ry >= 2, rx >= 3, h >= 2, w >= 2 {
            out.append(("reduced", try LoadView(source: descriptor, specification: LoadSpecification(
                scanCrop: AxisCrop(yOffset: 1, xOffset: 1, height: ry - 1, width: rx - 2),
                detectorCrop: AxisCrop(yOffset: 1, xOffset: 1, height: h, width: w), detectorBin: 2))))
        }
        return out
    }

    /// Every number a scientist or the pipeline could read from `path`, as strings and hashes.
    private func snapshot(path: String, large: Bool) async throws -> [String: Any] {
        var out = [String: Any]()
        let reader: DM4Reader
        do { reader = try await DM4Reader(path: path) } catch {
            return ["error": "\(error)"]
        }
        let d = try await reader.discoverPrimaryDataset()
        out["shape"] = d.shape; out["dtype"] = d.dtypeDescription; out["path"] = d.datasetPath
        out["chunkShape"] = d.chunkShape.map { "\($0)" } ?? "nil"
        let view = LoadView(fullExtentOf: d)
        out["pushdown"] = "\(reader.loadPushdown(for: view))"
        out["voltage"] = bits(await reader.voltage)
        out["q"] = [bits(await reader.qPixelSize), await reader.qPixelUnits ?? "nil"]
        out["r"] = [bits(await reader.rPixelSize), await reader.rPixelUnits ?? "nil"]
        out["note"] = await reader.calibrationNote ?? "nil"
        let pc = await reader.pixelCalibration()
        out["pixelCalibration"] = pc.map { "\(bits($0.rSize)) \($0.rUnits ?? "nil") \(bits($0.qSize)) \($0.qUnits ?? "nil")" } ?? "nil"

        for (name, view) in try views(of: d) {
            let rows = view.descriptor.ry, cols = view.descriptor.rx
            var all = SHA256(), rowsHash = SHA256(), tileHash = SHA256()
            var patternCount = 0
            // Patterns: every position of a small cube; the corners and the centre of a large one.
            let positions: [(Int, Int)] = large
                ? [(0, 0), (0, cols - 1), (rows - 1, 0), (rows - 1, cols - 1), (rows / 2, cols / 2), (1, 2)]
                : (0..<rows).flatMap { y in (0..<cols).map { (y, $0) } }
            for (y, x) in positions {
                let p = try await reader.readPattern(view, ry: y, rx: x)
                p.withUnsafeBytes { all.update(bufferPointer: $0) }; patternCount += p.count
            }
            let rowSet = large ? [0, rows - 1] : Array(0..<rows)
            for y in rowSet {
                let r = try await reader.readScanRow(view, ry: y)
                r.withUnsafeBytes { rowsHash.update(bufferPointer: $0) }
            }
            // Tiles: the whole scan in chunks of up to 4 rows (so a large file is never one buffer), and a middle slice.
            var y = 0
            while y < rows {
                let upper = min(rows, y + 4)
                let t = try await reader.readScanTile(view, yRange: y..<upper)
                XCTAssertEqual(t.pixels.count, (upper - y) * cols * view.descriptor.qy * view.descriptor.qx)
                t.pixels.withUnsafeBytes { tileHash.update(bufferPointer: $0) }
                y = upper
            }
            out["\(name).patterns"] = [patternCount, hex(all.finalize())]
            out["\(name).rows"] = hex(rowsHash.finalize())
            out["\(name).tiles"] = hex(tileHash.finalize())
            if rows >= 3 {
                let t = try await reader.readScanTile(view, yRange: 1..<(rows - 1))
                out["\(name).middleTile"] = sha(t.pixels)
            }
        }
        return out
    }

    // MARK: Baseline file

    /// One file per test (tests run in parallel): `Fixtures/DM4/<fixture>-2026-10-21.json`.
    private func check(_ results: [String: [String: Any]], fixture: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/DM4/\(fixture)-2026-10-21.json")
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys, .prettyPrinted]).write(to: url)
            XCTFail("baseline written to \(url.path)", file: file, line: line); return
        }
        let base = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: [String: Any]]
        for (name, new) in results {
            guard let old = base[name] else { XCTFail("\(name): not in the baseline", file: file, line: line); continue }
            XCTAssertEqual(Set(new.keys), Set(old.keys), "\(name): keys", file: file, line: line)
            for (key, value) in old {
                let a = try JSONSerialization.data(withJSONObject: [value], options: [.sortedKeys])
                let b = try JSONSerialization.data(withJSONObject: [new[key] ?? NSNull()], options: [.sortedKeys])
                XCTAssertEqual(a, b, "\(name).\(key): \(String(describing: new[key])) vs baseline \(value)", file: file, line: line)
            }
        }
    }

    // MARK: Tests

    private var directory: URL!
    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mac4dstem-dm4-switch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }

    func testSyntheticFilesReadByteForByteAsTheAppsOwnParserReadThem() async throws {
        var results = [String: [String: Any]]()
        for c in Self.cases() {
            let url = directory.appendingPathComponent("\(c.name).dm4")
            try Self.build(c).write(to: url)
            var snap = try await snapshot(path: url.path, large: false)
            if let error = snap["error"] as? String { snap["error"] = error.replacingOccurrences(of: directory.path, with: "") }
            results[c.name] = snap
        }
        let frozen = results
        try check(frozen, fixture: "synthetic")
    }

    func testRefusalsKeepTheirKinds() async throws {
        var results = [String: [String: Any]]()
        func kind(_ name: String, _ data: Data) async throws {
            let url = directory.appendingPathComponent(name)
            try data.write(to: url)
            do { _ = try await DM4Reader(path: url.path); results["refusal-\(name)"] = ["kind": "opened"] }
            catch let e as DM4Error {
                let text = "\(e)"
                results["refusal-\(name)"] = ["kind": text.components(separatedBy: "(").first ?? text]
            } catch { results["refusal-\(name)"] = ["kind": "other: \(type(of: error))"] }
        }
        // Big-endian byte order.
        try await kind("big-endian.dm4", Data([0, 0, 0, 4] + Self.u64be(0) + [0, 0, 0, 0, 1, 0] + Self.u64be(0)))
        // No object at all.
        try await kind("empty.dm4", Self.file([.int("Anything", 1)]))
        // A truncated pixel payload.
        var truncated = Self.build(Case(name: "t", type: "uint16", dims: [3, 2, 2, 2]))
        truncated.removeLast(8)
        try await kind("truncated.dm4", truncated)
        // Dimensions whose product overflows.
        let overflow = Self.file([.group("ImageList", [.group("", [.group("ImageData", [
            .int("DataType", 1),
            .group("Dimensions", (0..<4).map { .int("\($0)", 1_048_576) }),
            .array("Data", elementType: 2, count: 0, bytes: []),
        ])])])])
        try await kind("overflow.dm4", overflow)
        // 200 nested groups.
        var deep = Data([0, 0, 0, 4] + Self.u64be(0) + [0, 0, 0, 1] + [1, 0] + Self.u64be(1))
        for i in 0..<200 { deep += Data(Self.head(20, "G\(i)") + [1, 0] + Self.u64be(1)) }
        try await kind("deep.dm4", deep)
        // A pixel type nothing reads (RGB, 23) in a 4D object.
        try await kind("rgb.dm4", Self.file([.group("ImageList", [.group("", [.group("ImageData", [
            .int("DataType", 23), .group("Dimensions", (0..<4).map { .int("\($0)", 2) }),
            .array("Data", elementType: 4, count: 16, bytes: [UInt8](repeating: 0, count: 32)),
        ])])])]))
        // A file that is not there, and one that cannot be read: the reader names the file, never the folder.
        do { _ = try await DM4Reader(path: directory.appendingPathComponent("absent.dm4").path) } catch {
            let message = error.localizedDescription
            XCTAssertTrue(message.contains("absent.dm4"), message)
            XCTAssertFalse(message.contains(directory.lastPathComponent), message)
            results["refusal-absent"] = ["message": message]
        }
        try check(results, fixture: "refusals")
    }

    // MARK: Real files (skipped when absent)

    private static let references = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("References")

    private func realFile(_ relative: String, large: Bool = true) async throws {
        let path = Self.references.appendingPathComponent(relative).path
        try XCTSkipUnless(FileManager.default.fileExists(atPath: path), "\(relative) is not on this machine")
        let snap = try await snapshot(path: path, large: large)
        let name = (relative as NSString).lastPathComponent
        try check(["real:" + name: snap], fixture: name)
    }

    func testAlMgSi4DEDX() async throws { try await realFile("demo-edx/AlMgSi_4D_EDX.dm4") }
    func testAlMgSiRegistrationMismatch() async throws { try await realFile("demo-edx/AlMgSi_4D_EDX_regmismatch.dm4") }
    func testTheTinyDemoFixture() async throws {
        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/demo-edx-tiny.dm4").path
        try check(["real:demo-edx-tiny.dm4": try await snapshot(path: path, large: false)], fixture: "demo-edx-tiny")
    }
    /// A rank-3 object (400, 512, 512) that the app reshapes to 20 x 20 by its "Scan shape X/Y" tags.
    func testSmallDatacubeRank3() async throws { try await realFile("../CuboKit/py4dstem-test-data/small_datacube.dm4") }

    /// Not an assertion: the timings printed for the switch's record (best of three, whole scan as one tile, and a single pattern).
    func testPrintTimings() async throws {
        for relative in ["demo-edx/AlMgSi_4D_EDX.dm4", "../CuboKit/py4dstem-test-data/small_datacube.dm4"] {
            let path = Self.references.appendingPathComponent(relative).path
            guard FileManager.default.fileExists(atPath: path) else { continue }
            let t0 = Date()
            let reader = try await DM4Reader(path: path)
            let d = try await reader.discoverPrimaryDataset()
            let open = Date().timeIntervalSince(t0)
            let view = LoadView(fullExtentOf: d)
            var best = Double.infinity, pat = Double.infinity
            for _ in 0..<3 {
                let a = Date()
                let tile = try await reader.readScanTile(view, yRange: 0..<min(d.ry, relative.hasPrefix("demo") ? d.ry : 4))
                best = min(best, Date().timeIntervalSince(a)); XCTAssertFalse(tile.pixels.isEmpty)
                let b = Date()
                _ = try await reader.readPattern(view, ry: d.ry / 2, rx: d.rx / 2)
                pat = min(pat, Date().timeIntervalSince(b))
            }
            let line = "PERF \((relative as NSString).lastPathComponent) shape \(d.shape) \(d.dtypeDescription): open \(open) s, tile best \(best) s, pattern best \(pat) s"
            print(line)
            // XCTest's stdout is not in the xcodebuild log: the numbers are also appended to a file when MAC4DSTEM_PERF_LOG names one.
            if let log = ProcessInfo.processInfo.environment["MAC4DSTEM_PERF_LOG"] ?? UserDefaults.standard.string(forKey: "perfLog"),
               let handle = FileHandle(forWritingAtPath: log) ?? { FileManager.default.createFile(atPath: log, contents: nil); return FileHandle(forWritingAtPath: log) }() {
                handle.seekToEndOfFile(); handle.write(Data((line + "\n").utf8)); try? handle.close()
            }
        }
    }
}
