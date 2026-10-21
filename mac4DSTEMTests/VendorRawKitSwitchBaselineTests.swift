import XCTest
import CryptoKit
import DSTEMCore

/// The EMPAD and MIB readers' remaining own reading onto FormatoKit 0.7.0 (EMPAD `scan_resolution_x/y`, raw-only scans, `rawPath`; MIB
/// `pixelCode` and any header size from 384 to 65536), 2026-10-21, D12: readers are tested exact. `Fixtures/VendorRaw/*.json` was written by
/// the readers as they were at a4c8a610 (kit for pix_x/pix_y XML and 384/768-byte MIB headers; their own frame reads for everything else)
/// BEFORE their own parsing and frame reads were deleted: for each synthetic pair below the descriptor and a SHA-256 of every pattern, scan
/// row and tile through a full and a cropped+binned view; for each refusal its kind.
final class VendorRawKitSwitchBaselineTests: XCTestCase {

    private var directory: URL!
    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mac4dstem-vendor-switch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }

    // MARK: Writers

    /// `frames` EMPAD frames: 130 x 128 little-endian float32, the last two rows a footer of negative values; image values are distinct per frame.
    private func writeEMPADRaw(_ name: String, frames: Int) throws {
        var data = Data(capacity: frames * 130 * 128 * 4)
        for frame in 0..<frames {
            for i in 0..<(130 * 128) {
                let v: Float = i >= 128 * 128 ? -Float(frame + 1) : Float(frame * 100_000 + i) * 0.37 + (i % 13 == 0 ? 1e-7 : 0)
                withUnsafeBytes(of: v.bitPattern.littleEndian) { data.append(contentsOf: $0) }
            }
        }
        try data.write(to: directory.appendingPathComponent(name))
    }

    private func write(_ name: String, _ text: String) throws {
        try text.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    /// One MIB frame header of `size` bytes with the given fields.
    private func mibHeader(size: Int, offset: Int? = nil, width: Int = 256, height: Int = 256, code: String = "U16", layout: String = "1x1",
                           withDetector: Bool = true) -> Data {
        let fields: [String] = withDetector
            ? ["MQ1", "000000", String(format: "%05d", offset ?? size), "1", String(width), String(height), code, layout, "12", String(repeating: " ", count: 40),
               "2026-07-14T00:00:00.000000Z", "1250000ns", "0", ""]
            : ["MQ1", "1", String(offset ?? size), "1", "0", "0", code, layout, "0", "2026-07-14 00:00:00", "0.001", "0", "0", "0", "0", "0", "0", "0", "12"]
        var bytes = Array(fields.joined(separator: ",").utf8) + [0]
        precondition(bytes.count <= size, "header text \(bytes.count) > \(size)")
        bytes += [UInt8](repeating: 0, count: size - bytes.count)
        return Data(bytes)
    }

    private func writeMIB(_ name: String, frames: Int, size: Int = 384, width: Int = 256, height: Int = 256, code: String = "U16", layout: String = "1x1",
                          withDetector: Bool = true, scan: (x: Int, y: Int)? = nil, hdr: Bool = true, truncateBy: Int = 0) throws {
        var data = Data()
        let bytesPerPixel = code == "U08" ? 1 : code == "U32" ? 4 : 2
        for frame in 0..<frames {
            data.append(mibHeader(size: size, width: width, height: height, code: code, layout: layout, withDetector: withDetector))
            for i in 0..<(width * height) {
                let v = UInt32((frame * 1000 + i * 7) % (bytesPerPixel == 1 ? 251 : bytesPerPixel == 2 ? 65_521 : 16_000_001))
                switch bytesPerPixel {
                case 1: data.append(UInt8(v))
                case 2: data.append(contentsOf: [UInt8(v >> 8), UInt8(v & 0xFF)])
                default: data.append(contentsOf: [UInt8(v >> 24), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)])
                }
            }
        }
        if truncateBy > 0 { data.removeLast(truncateBy) }
        try data.write(to: directory.appendingPathComponent(name))
        if hdr {
            let s = scan ?? (x: frames, y: 1)
            try write((name as NSString).deletingPathExtension + ".hdr", "ScanX:\t\(s.x)\nScanY:\t\(s.y)\n")
        }
    }

    // MARK: Snapshots

    private func hex(_ digest: SHA256.Digest) -> String { digest.map { String(format: "%02x", $0) }.joined() }

    private func reads(_ source: any FourDDataSource) async throws -> [String: Any] {
        var out = [String: Any]()
        let d = try await source.discoverPrimaryDataset()
        out["shape"] = d.shape; out["dtype"] = d.dtypeDescription; out["path"] = d.datasetPath.hasPrefix("/") ? d.datasetPath : "?"
        out["file"] = (d.filePath as NSString).lastPathComponent
        out["pushdown"] = "\(source.loadPushdown(for: LoadView(fullExtentOf: d)))"
        var views = [("full", LoadView(fullExtentOf: d))]
        let h = ((d.qy - 1) / 2) * 2, w = ((d.qx - 1) / 2) * 2
        if d.ry >= 1, d.rx >= 2, h >= 2, w >= 2 {
            views.append(("reduced", try LoadView(source: d, specification: LoadSpecification(
                scanCrop: AxisCrop(yOffset: 0, xOffset: 1, height: d.ry, width: d.rx - 1),
                detectorCrop: AxisCrop(yOffset: 1, xOffset: 1, height: h, width: w), detectorBin: 2))))
        }
        for (name, view) in views {
            var patterns = SHA256(), rows = SHA256(), tiles = SHA256()
            var count = 0
            for y in 0..<view.descriptor.ry { for x in 0..<view.descriptor.rx {
                let p = try await source.readPattern(view, ry: y, rx: x)
                p.withUnsafeBytes { patterns.update(bufferPointer: $0) }; count += p.count
            } }
            for y in 0..<view.descriptor.ry { try await source.readScanRow(view, ry: y).withUnsafeBytes { rows.update(bufferPointer: $0) } }
            try await source.readScanTile(view, yRange: 0..<view.descriptor.ry).pixels.withUnsafeBytes { tiles.update(bufferPointer: $0) }
            out["\(name).patterns"] = [count, hex(patterns.finalize())]
            out["\(name).rows"] = hex(rows.finalize())
            out["\(name).tiles"] = hex(tiles.finalize())
        }
        return out
    }

    /// The kind of a refusal: the case name of an app or kit error. A file the OS could not open (a Cocoa error, or the app's `cannotOpen`)
    /// is `cannotOpen` whichever layer said so.
    private func kind(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain, [NSFileNoSuchFileError, NSFileReadNoSuchFileError, NSFileReadNoPermissionError].contains(ns.code) { return "cannotOpen" }
        let text = "\(error)"
        return text.components(separatedBy: "(").first ?? text
    }

    private func empad(_ file: String) async -> [String: Any] {
        do { return try await reads(try EMPADReader(path: directory.appendingPathComponent(file).path)) }
        catch { return ["refusal": kind(error)] }
    }

    private func mib(_ file: String) async -> [String: Any] {
        do { return try await reads(try MIBReader(path: directory.appendingPathComponent(file).path)) }
        catch { return ["refusal": kind(error)] }
    }

    private func check(_ results: [String: [String: Any]], fixture: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/VendorRaw/\(fixture)-2026-10-21.json")
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys, .prettyPrinted]).write(to: url)
            XCTFail("baseline written to \(url.path)", file: file, line: line); return
        }
        let base = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: [String: Any]]
        XCTAssertEqual(Set(results.keys), Set(base.keys), "cases", file: file, line: line)
        for (name, new) in results {
            guard let old = base[name] else { continue }
            XCTAssertEqual(Set(new.keys), Set(old.keys), "\(name): keys \(new.keys.sorted())", file: file, line: line)
            for (key, value) in old {
                let a = try JSONSerialization.data(withJSONObject: [value], options: [.sortedKeys])
                let b = try JSONSerialization.data(withJSONObject: [new[key] ?? NSNull()], options: [.sortedKeys])
                XCTAssertEqual(a, b, "\(name).\(key): \(String(describing: new[key])) vs baseline \(value)", file: file, line: line)
            }
        }
    }

    // MARK: EMPAD

    private let acquire = #"<scan_parameters mode="acquire"><scan_resolution_x>3</scan_resolution_x><scan_resolution_y>2</scan_resolution_y></scan_parameters>"#

    func testEMPADPairsReadByteForByteAsBefore() async throws {
        try writeEMPADRaw("empad.raw", frames: 6)
        let raw = #"<raw_file filename="empad.raw"/>"#
        try write("acquire.xml", "<root>\(raw)<type>scan</type>\(acquire)</root>")
        try write("pix.xml", "<root>\(raw)<pix_x>3</pix_x><pix_y>2</pix_y></root>")
        try write("pix_row.xml", "<root>\(raw)<pix_x>6</pix_x><pix_y>1</pix_y></root>")
        try write("pix_column.xml", "<root>\(raw)<pix_x>1</pix_x><pix_y>6</pix_y></root>")
        try write("both.xml", "<root>\(raw)<pix_x>2</pix_x><pix_y>3</pix_y>\(acquire)</root>")
        try write("bare_resolution.xml", "<root>\(raw)<scan_resolution_x>3</scan_resolution_x><scan_resolution_y>2</scan_resolution_y></root>")
        try write("acquire_last.xml", #"<root>\#(raw)<scan_parameters mode="search"><scan_resolution_x>2</scan_resolution_x><scan_resolution_y>3</scan_resolution_y></scan_parameters>\#(acquire)</root>"#)
        try write("acquire_first.xml", #"<root>\#(raw)\#(acquire)<scan_parameters mode="search"><scan_resolution_x>2</scan_resolution_x><scan_resolution_y>3</scan_resolution_y></scan_parameters></root>"#)
        try write("single_quotes.xml", #"<root><raw_file filename='empad.raw'/><scan_parameters mode='acquire'><scan_resolution_x> 3 </scan_resolution_x><scan_resolution_y>2</scan_resolution_y></scan_parameters></root>"#)
        try write("absolute_dir.xml", "<root><raw_file filename=\"/nonexistent/place/empad.raw\"/>\(acquire)</root>")
        try write("relative_dir.xml", "<root><raw_file filename=\"sub/empad.raw\"/>\(acquire)</root>")
        try write("wrong_count.xml", #"<root><raw_file filename="empad.raw"/><scan_parameters mode="acquire"><scan_resolution_x>3</scan_resolution_x><scan_resolution_y>3</scan_resolution_y></scan_parameters></root>"#)
        try write("zero.xml", #"<root><raw_file filename="empad.raw"/><scan_parameters mode="acquire"><scan_resolution_x>0</scan_resolution_x><scan_resolution_y>2</scan_resolution_y></scan_parameters></root>"#)
        try write("no_scan.xml", "<root>\(raw)</root>")
        try write("no_raw.xml", "<root>\(acquire)</root>")
        try write("missing_raw.xml", "<root><raw_file filename=\"gone.raw\"/>\(acquire)</root>")
        try write("not_xml.xml", "this is not xml")
        try writeEMPADRaw("scan_x3_y2.raw", frames: 6)
        try write("scan_x3_y2.xml", #"<root><raw_file filename="scan_x3_y2.raw"/></root>"#)
        try writeEMPADRaw("short.raw", frames: 5)
        try write("short.xml", #"<root><raw_file filename="short.raw"/><scan_parameters mode="acquire"><scan_resolution_x>3</scan_resolution_x><scan_resolution_y>2</scan_resolution_y></scan_parameters></root>"#)
        // The raw file named: its same-stem XML companion is used when present.
        try writeEMPADRaw("paired.raw", frames: 6)
        try write("paired.xml", #"<root><raw_file filename="paired.raw"/><pix_x>3</pix_x><pix_y>2</pix_y></root>"#)
        // Raw-only: a square scan is inferred from the length; anything else is refused.
        try writeEMPADRaw("square4.raw", frames: 4)
        try writeEMPADRaw("square9.raw", frames: 9)
        try writeEMPADRaw("ambiguous.raw", frames: 6)
        try writeEMPADRaw("one.raw", frames: 1)
        try Data(count: 130 * 128 * 4 + 7).write(to: directory.appendingPathComponent("ragged.raw"))
        try writeEMPADRaw("ragged6.raw", frames: 6)
        try Data(count: 3).write(to: directory.appendingPathComponent("ragged6.tail"))
        let handle = try FileHandle(forWritingTo: directory.appendingPathComponent("ragged6.raw"))
        handle.seekToEndOfFile(); handle.write(Data(count: 9)); try handle.close()
        try Data().write(to: directory.appendingPathComponent("empty.raw"))
        try Data([1, 2, 3]).write(to: directory.appendingPathComponent("other.bin"))

        var results = [String: [String: Any]]()
        for file in ["acquire.xml", "pix.xml", "pix_row.xml", "pix_column.xml", "both.xml", "bare_resolution.xml", "acquire_last.xml", "acquire_first.xml",
                     "single_quotes.xml", "absolute_dir.xml", "relative_dir.xml", "wrong_count.xml", "zero.xml", "no_scan.xml", "no_raw.xml", "missing_raw.xml",
                     "not_xml.xml", "scan_x3_y2.xml", "short.xml", "paired.raw", "square4.raw", "square9.raw", "ambiguous.raw", "one.raw", "ragged.raw", "ragged6.raw",
                     "empty.raw", "other.bin", "absent.xml"] {
            results[file] = await empad(file)
        }
        try check(results, fixture: "empad")
        // Pixel values are what the footer-free frames hold: spot check beside the hash.
        let reader = try EMPADReader(path: directory.appendingPathComponent("acquire.xml").path)
        let d = try await reader.discoverPrimaryDataset()
        let p = try await reader.readPattern(LoadView(fullExtentOf: d), ry: 1, rx: 2)
        XCTAssertEqual(p.count, 128 * 128)
        XCTAssertFalse(p.contains { $0 < 0 })
    }

    // MARK: MIB

    func testMIBFilesReadByteForByteAsBefore() async throws {
        try writeMIB("u16.mib", frames: 6, scan: (3, 2))
        try writeMIB("u08.mib", frames: 2, code: "U08")
        try writeMIB("u32.mib", frames: 2, code: "U32")
        try writeMIB("h768.mib", frames: 2, size: 768)
        try writeMIB("h512.mib", frames: 2, size: 512)
        try writeMIB("h4096.mib", frames: 2, size: 4096)
        try writeMIB("h65536.mib", frames: 2, size: 65_536)
        try writeMIB("h512_u08.mib", frames: 2, size: 512, code: "U08")
        try writeMIB("offset_not_size.mib", frames: 2, size: 512)           // offset field equals the size: the common case
        try writeMIB("nodetector_512.mib", frames: 2, size: 512, withDetector: false)
        try writeMIB("nodetector_384.mib", frames: 2, size: 384, withDetector: false)
        try writeMIB("nodetector_u32.mib", frames: 2, size: 512, code: "U32", withDetector: false)
        try writeMIB("assembly_2x2.mib", frames: 1, width: 512, height: 512, layout: "2x2")
        try writeMIB("assembly_2x2g.mib", frames: 1, width: 514, height: 514, layout: "2x2G")
        try writeMIB("assembly_mismatch.mib", frames: 2, width: 128, height: 128, layout: "1x1")      // detector disagrees with its assembly
        try writeMIB("assembly_unknown.mib", frames: 2, layout: "3x3")
        try writeMIB("r64.mib", frames: 2, code: "R64")
        try writeMIB("u64.mib", frames: 2, code: "U64")
        try writeMIB("no_hdr.mib", frames: 2, hdr: false)
        try writeMIB("hdr_mismatch.mib", frames: 2, scan: (3, 1))
        try writeMIB("truncated.mib", frames: 2, truncateBy: 100)
        try writeMIB("ragged_header.mib", frames: 2, size: 512)
        try writeMIB("bad_hdr.mib", frames: 2, hdr: false)
        try write("bad_hdr.hdr", "ScanX:\tnot a number\nScanY:\t1\n")
        try writeMIB("zero_scan.mib", frames: 2, scan: (0, 1))
        try Data([1, 2, 3]).write(to: directory.appendingPathComponent("tiny.mib"))
        try write("tiny.hdr", "ScanX:\t1\nScanY:\t1\n")

        var results = [String: [String: Any]]()
        for file in ["u16.mib", "u08.mib", "u32.mib", "h768.mib", "h512.mib", "h4096.mib", "h65536.mib", "h512_u08.mib", "offset_not_size.mib", "nodetector_512.mib",
                     "nodetector_384.mib", "nodetector_u32.mib", "assembly_2x2.mib", "assembly_2x2g.mib", "assembly_mismatch.mib", "assembly_unknown.mib", "r64.mib", "u64.mib",
                     "no_hdr.mib", "hdr_mismatch.mib", "truncated.mib", "ragged_header.mib", "bad_hdr.mib", "zero_scan.mib", "tiny.mib", "absent.mib"] {
            results[file] = await mib(file)
        }
        try check(results, fixture: "mib")
    }
}
