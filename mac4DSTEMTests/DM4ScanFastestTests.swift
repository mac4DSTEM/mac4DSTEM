import XCTest
import DSTEMCore

/// `DM4Reader.scanFastestGather`'s blocked transpose (32 or more positions in
/// one gather) had no test. Swift 6 mode rejected its closure (`sending 'out'`);
/// the fix passes the buffer as an inout parameter. This pins that the gather
/// still returns, element for element, the scan-fastest model it documents:
/// the file stores `[Rx, Ry, Qy, Qx]` with `qy` stepping one plane and `qx`
/// `qy` planes, and `readScanRow` hands back `[position][qy][qx]`.
final class DM4ScanFastestTests: XCTestCase {


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
    /// Scan pair (dimensions 0, 1) in nm and diffraction pair in mrad: the
    /// units are what mark the file scan-fastest. 32 x 2 scan, 2 x 3 detector,
    /// int16 values 0..<384 in storage order.
    private nonisolated static func cube(dims: [Int32]) -> Data {
        let count = Int(dims.reduce(1, *))
        func axis(_ i: Int, _ units: String) -> Node {
            .group("\(i)", [.float("Origin", 0), .float("Scale", 1), .string18("Units", units)])
        }
        let imageData: Node = .group("ImageData", [
            .int("DataType", 1),
            .group("Dimensions", dims.enumerated().map { .int("\($0.offset)", $0.element) }),
            .group("Calibrations", [.group("Dimension", [
                axis(0, "nm"), axis(1, "nm"), axis(2, "mrad"), axis(3, "mrad"),
            ])]),
            .int16Array("Data", (0..<count).map { Int16($0) }),
        ])
        // Wrapped as DigitalMicrograph stores an image: ImageList entry N holds ImageData (FormatoKit reads that structure only).
        let body: [UInt8] = [1, 0] + u64be(1) + encode(.group("ImageList", [.group("", [imageData])]))
        return Data([0, 0, 0, 4] + u64be(0) + [0, 0, 0, 1] + body)
    }

    func testAScanRowOfThirtyTwoPositionsGathersEveryElementWhereTheLayoutPutsIt() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mac4dstem-dm4-scanfastest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("scan-fastest.dm4")
        try Self.cube(dims: [32, 2, 2, 3]).write(to: url)

        let reader = try await DM4Reader(path: url.path)
        let ds = try await reader.discoverPrimaryDataset()
        XCTAssertEqual(ds.shape, [2, 32, 2, 3], "scan Ry x Rx, detector Qy x Qx")
        let (ry, rx, qy, qx) = (ds.shape[0], ds.shape[1], ds.shape[2], ds.shape[3])
        let view = LoadView(fullExtentOf: ds)

        let row = try await reader.readScanRow(view, ry: 1)
        XCTAssertEqual(row.count, rx * qy * qx)
        var mismatches = 0
        for x in 0..<rx { for iy in 0..<qy { for ix in 0..<qx {
            let expected = Float((ix * qy + iy) * ry * rx + 1 * rx + x)
            if row[(x * qy + iy) * qx + ix] != expected { mismatches += 1 }
        } } }
        XCTAssertEqual(mismatches, 0, "every element of the 32-position gather sits where the layout puts it")

        // One position takes the in-order sweep, not the blocked transpose; same layout.
        let single = try await reader.readPattern(view, ry: 1, rx: 5)
        var singleMismatches = 0
        for iy in 0..<qy { for ix in 0..<qx {
            if single[iy * qx + ix] != Float((ix * qy + iy) * ry * rx + 1 * rx + 5) { singleMismatches += 1 }
        } }
        XCTAssertEqual(singleMismatches, 0, "the single-position sweep agrees")
    }
}
