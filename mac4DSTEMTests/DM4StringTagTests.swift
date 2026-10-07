import XCTest
import DSTEMCore

/// Open-items "DM4 string tags (type 18) read one length too many" (2026-10-05).
/// A type-18 data tag's info array is `[18, length]`, and exactly `length`
/// bytes follow it and nothing else. rosettasciio
/// (`digitalmicrograph/_api.py`: `parse_string_definition` reads the length as
/// the info array's second entry; `read_string` consumes `length` bytes) agrees.
/// `DM4Reader` read a further u32 after the info array, so the walk desynced
/// from the next tag. The synthetic cube writes its axis units as type-18
/// strings BEFORE the Data tag; the units and the following scale numbers must
/// read back exactly through `pixelCalibration()`, and the cube must still
/// decode as written.
final class DM4StringTagTests: XCTestCase {

    // MARK: Synthetic DM4 writer (version 4, little-endian, the cube of `FinalPolishDTests`)

    private indirect enum Node {
        case int(String, Int32)
        case float(String, Float)
        case string18(String, String)          // type-18: info [18, byte count], then the UTF-8 bytes
        case group(String, [Node])             // "" label = unnamed
        case int16Array(String, [Int16])       // the Data tag: info [20, 2 (int16), count], then the values
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
        case .group(let l, let kids):
            return head(20, l) + [1, 0] + u64be(UInt64(kids.count)) + kids.flatMap(encode)
        case .int16Array(let l, let values):
            return head(21, l) + delim + u64be(3) + u64be(20) + u64be(2) + u64be(UInt64(values.count))
                + values.flatMap { le(UInt64(UInt16(bitPattern: $0)), 2) }
        }
    }

    /// Root: version 4, root length, byte order 1, then one group "ImageData" holding
    /// DataType, Dimensions, Calibrations (type-18 units), and the Data tag.
    /// Dimensions 0,1 (detector, fastest first) are mrad; 2,3 (scan) are nm and µm.
    /// Ry = 2, Rx = 2, Qy = 2, Qx = 3; int16 values 0..<24 in storage order.
    private nonisolated static func cube() -> Data {
        let imageData: Node = .group("ImageData", [
            .int("DataType", 1),
            .group("Dimensions", [.int("0", 3), .int("1", 2), .int("2", 2), .int("3", 2)]),
            .group("Calibrations", [.group("Dimension", [
                .group("0", [.float("Origin", 0), .float("Scale", 0.25), .string18("Units", "mrad")]),
                .group("1", [.float("Origin", 0), .float("Scale", 0.125), .string18("Units", "mrad")]),
                .group("2", [.float("Origin", 0), .float("Scale", 0.5), .string18("Units", "nm")]),
                .group("3", [.float("Origin", 0), .float("Scale", 2), .string18("Units", "µm")]),
            ])]),
            .int16Array("Data", (0..<24).map { Int16($0) }),
        ])
        let body: [UInt8] = [1, 0] + u64be(1) + encode(imageData)
        return Data([0, 0, 0, 4] + u64be(0) + [0, 0, 0, 1] + body)
    }

    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mac4dstem-dm4-string-tags-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: Tests

    /// The type-18 units are read to their exact length, the scale numbers after
    /// them are intact, and the Data tag after them decodes to the values written.
    func testType18UnitsBeforeTheDataTagReadBackAndTheCubeStillDecodes() async throws {
        let url = directory.appendingPathComponent("string-tags.dm4")
        try Self.cube().write(to: url)

        let reader = try await DM4Reader(path: url.path)
        let ds = try await reader.discoverPrimaryDataset()
        XCTAssertEqual(ds.shape, [2, 2, 2, 3], "the Dimensions tags after the string tags parse")

        let calibration = await reader.pixelCalibration()
        XCTAssertEqual(calibration?.qUnits, "mrad", "the detector units string reads back exactly")
        XCTAssertEqual(calibration?.rUnits, "nm", "the scan units string reads back exactly")
        XCTAssertEqual(calibration?.qSize, 0.25, "the Scale after a string tag is intact (detector)")
        XCTAssertEqual(calibration?.rSize, 0.5, "the Scale after a string tag is intact (scan)")

        let view = LoadView(fullExtentOf: ds)
        let pattern = try await reader.readPattern(view, ry: 1, rx: 0)
        XCTAssertEqual(pattern, [12, 13, 14, 15, 16, 17], "the Data tag after the string tags decodes as written")
    }
}
