import XCTest
import DSTEMCore
import FormatoDM
@testable import SpectroCore

/// v5.0 WP1 lane B: `DM4Experiment` lists every image object of a GMS `.dm4`
/// ("one experiment") and reads a 2D one back. The files are synthetic, built
/// tag by tag the way `FinalPolishDTests` builds its cube, but with the tag
/// layout of the owner's `134_STEM SI.dm4` / `036_STEM SI.dm4` (measured
/// 2026-10-05): unnamed `ImageList` entries, `Experiment keywords.{1,2}`, the
/// rect and survey ID under `SI.Acquisition.Survey Image` on the SI objects,
/// a root `Thumbnails` list. Test constants are deliberately asymmetric (a
/// rect of 14,222,515,569; x and y axes that differ) so a swap cannot hide.
final class DM4ExperimentTests: XCTestCase {

    // MARK: Synthetic DM4 writer

    private indirect enum Node {
        case int(String, Int32)
        case float(String, Float)
        case text(String, String)              // ushort array, as GMS writes strings
        case string18(String, [UInt8])         // type-18 string: info [18, length], then the bytes
        case structTag(String, [Int32])        // struct of int32 fields
        case bigArray(String, count: Int)      // uint8 array, over the 4 KiB keep limit
        case ints(String, [Int32])             // int32 array
        case uints(String, [UInt32])           // uint32 array
        case group(String, [Node])             // "" label = unnamed (one-based position)
        case blob(String, elementType: Int, bytes: [UInt8], count: Int)
        case rawInfo(String, [UInt64])         // a data tag with a hand-written info array and no payload
    }

    private static func u16be(_ v: Int) -> [UInt8] { [UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
    private static func u64be(_ v: UInt64) -> [UInt8] { (0..<8).map { UInt8((v >> UInt64(56 - 8 * $0)) & 0xFF) } }
    private static func le(_ v: UInt64, _ n: Int) -> [UInt8] { (0..<n).map { UInt8((v >> UInt64(8 * $0)) & 0xFF) } }

    private static func head(_ tag: UInt8, _ label: String) -> [UInt8] {
        [tag] + u16be(label.utf8.count) + Array(label.utf8) + u64be(0)
    }
    private static let delim: [UInt8] = [37, 37, 37, 37]

    private static func encode(_ node: Node) -> [UInt8] {
        switch node {
        case .int(let l, let v):
            return head(21, l) + delim + u64be(1) + u64be(3) + le(UInt64(UInt32(bitPattern: v)), 4)
        case .float(let l, let v):
            return head(21, l) + delim + u64be(1) + u64be(6) + le(UInt64(v.bitPattern), 4)
        case .text(let l, let s):
            let units = Array(s.utf16)
            return head(21, l) + delim + u64be(3) + u64be(20) + u64be(4) + u64be(UInt64(units.count))
                + units.flatMap { le(UInt64($0), 2) }
        case .string18(let l, let bytes):
            return head(21, l) + delim + u64be(2) + u64be(18) + u64be(UInt64(bytes.count)) + bytes
        case .structTag(let l, let fields):
            let n = fields.count
            return head(21, l) + delim + u64be(UInt64(3 + 2 * n)) + u64be(15) + u64be(0) + u64be(UInt64(n))
                + (0..<n).flatMap { _ in u64be(0) + u64be(3) }
                + fields.flatMap { le(UInt64(UInt32(bitPattern: $0)), 4) }
        case .bigArray(let l, let count):
            return head(21, l) + delim + u64be(3) + u64be(20) + u64be(8) + u64be(UInt64(count))
                + [UInt8](repeating: 7, count: count)
        case .ints(let l, let a):
            return head(21, l) + delim + u64be(3) + u64be(20) + u64be(3) + u64be(UInt64(a.count))
                + a.flatMap { le(UInt64(UInt32(bitPattern: $0)), 4) }
        case .uints(let l, let a):
            return head(21, l) + delim + u64be(3) + u64be(20) + u64be(5) + u64be(UInt64(a.count))
                + a.flatMap { le(UInt64($0), 4) }
        case .group(let l, let kids):
            return head(20, l) + [1, 0] + u64be(UInt64(kids.count)) + kids.flatMap(encode)
        case .rawInfo(let l, let info):
            return head(21, l) + delim + u64be(UInt64(info.count)) + info.flatMap { u64be($0) }
        case .blob(let l, let t, let bytes, let count):
            return head(21, l) + delim + u64be(3) + u64be(20) + u64be(UInt64(t)) + u64be(UInt64(count)) + bytes
        }
    }

    private static func file(imageList: [Node], extraRoot: [Node] = []) -> Data {
        // Version 4, root length, byte order 1 (little-endian), then the root group body.
        let kids = [Node.group("ImageList", imageList)] + extraRoot
        let body: [UInt8] = [1, 0] + u64be(UInt64(kids.count)) + kids.flatMap(encode)
        return Data([0, 0, 0, 4] + u64be(0) + [0, 0, 0, 1] + body)
    }

    // MARK: Fixture objects

    private typealias Axis = (origin: Float, scale: Float, units: String)
    private static let experiment = "Spectrum Imaging_10/5/2026_10:00:00 AM"
    private static let surveyID: [UInt32] = [11, 12, 13, 14]
    private static let rectValues: [Int32] = [14, 222, 515, 569]

    private static func calibrations(_ axes: [Axis]) -> Node {
        .group("Calibrations", [.group("Dimension", axes.map {
            .group("", [.float("Origin", $0.origin), .float("Scale", $0.scale), .text("Units", $0.units)])
        })])
    }

    private static func keywords(_ label: String?) -> [Node] {
        guard let label else { return [] }
        return [.group("Meta Data", [.group("Experiment keywords", [
            .group("", [.text("Experiment ID", experiment), .text("Label", "Spectrum Imaging")]),
            .group("", [.text("Label", label)]),
        ])])]
    }

    private static func surveyLink(rect: Bool = true, id: [UInt32] = surveyID) -> Node {
        .group("SI", [.group("Acquisition", [.group("Survey Image",
            [.uints("Unique Image ID", id)] + (rect ? [.ints("Spectrum Image Rect", rectValues)] : []))])])
    }

    private static func object(
        name: String, dataType: Int32, dims: [Int32], axes: [Axis],
        blobType: Int, blob: [UInt8], count: Int, tags: [Node], uniqueID: [Int32]? = nil
    ) -> Node {
        var kids: [Node] = [
            .text("Name", name),
            .group("ImageData", [
                .blob("Data", elementType: blobType, bytes: blob, count: count),
                .int("DataType", dataType),
                .group("Dimensions", dims.map { .int("", $0) }),
                calibrations(axes),
            ]),
            .group("ImageTags", tags),
        ]
        if let uniqueID { kids.append(.group("UniqueID", uniqueID.map { .int("", $0) })) }
        return .group("", kids)
    }

    private static func u16s(_ v: [UInt16]) -> [UInt8] { v.flatMap { le(UInt64($0), 2) } }
    private static func f32s(_ v: [Float]) -> [UInt8] { v.flatMap { le(UInt64($0.bitPattern), 4) } }
    private static func i16s(_ v: [Int16]) -> [UInt8] { v.flatMap { le(UInt64(UInt16(bitPattern: $0)), 2) } }

    private static let nm: Axis = (0, 0.5, "nm")
    private static let um: Axis = (0, 0.25, "µm")
    /// Different scale, units and origin from `nm`, so an x/y mix-up shows.
    private static let umY: Axis = (2, 0.75, "µm")
    private static let diffractionValues: [Int16] = (0..<24).map { Int16($0 * 7 - 50) }

    private static func thumbnail(dataType: Int32 = 23) -> Node {
        object(name: "Image Of 001_STEM SI", dataType: dataType, dims: [2, 1],
               axes: [(0, 1, ""), (0, 1, "")], blobType: 8,
               blob: [1, 2, 3, 4, 5, 6, 7, 8], count: 8, tags: [], uniqueID: [1, 1, 1, 1])
    }
    /// Carries, BEFORE the 4D object, a struct tag and an array over the keep limit.
    private static func survey(extraTags: [Node] = []) -> Node {
        object(name: "ADF Image (SI Survey)", dataType: 10, dims: [4, 3], axes: [nm, umY],
               blobType: 4, blob: u16s((0..<12).map { UInt16($0) }), count: 12,
               tags: keywords("Survey") + extraTags, uniqueID: surveyID.map { Int32($0) })
    }
    private static func scanSignal() -> Node {
        object(name: "HAADF Image", dataType: 2, dims: [2, 3], axes: [um, (0, 0.125, "nm")],
               blobType: 6, blob: f32s([0.5, 1.5, 2.5, 3.5, 4.5, 5.5]), count: 6,
               tags: keywords("Scan Signal") + [surveyLink()], uniqueID: [21, 22, 23, 24])
    }
    private static func diffraction() -> Node {
        object(name: "Diffraction SI", dataType: 1, dims: [2, 2, 2, 3],
               axes: [(0, 0.1, "1/nm"), (0, 0.1, "1/nm"), um, um],
               blobType: 2, blob: i16s(diffractionValues), count: 24,
               tags: keywords("Diffraction") + [surveyLink()], uniqueID: [31, 32, 33, 34])
    }
    private static func eds(extraTags: [Node] = []) -> Node {
        object(name: "EDS SI", dataType: 2, dims: [2, 3, 4], axes: [um, um, (20, 0.01, "keV")],
               blobType: 6, blob: f32s((0..<24).map { Float($0) }), count: 24,
               tags: keywords("EDS") + [surveyLink(), .group("EDS", [
                .group("Detector Info", [.float("Azimuthal angle", 45), .float("Elevation angle", 22.5)]),
                .float("Solid angle", 0.7), .float("Live time", 12.5), .float("Real time", 15),
               ])] + extraTags, uniqueID: [41, 42, 43, 44])
    }

    private static let thumbnails: Node = .group("Thumbnails", [.group("", [.int("ImageIndex", 0)])])
    private static let noise: [Node] = [.structTag("Struct", [3, -4, 5]), .bigArray("Big", count: 5000)]

    /// Struct and >4 KiB array BEFORE the 4D object. `withString` adds a type-18 string tag after it.
    private func fullFile(withString: Bool = false) -> Data {
        Self.file(imageList: [Self.thumbnail(), Self.survey(extraTags: Self.noise), Self.scanSignal(),
                              Self.diffraction(),
                              Self.eds(extraTags: withString ? [.string18("Note", Array("hello".utf8))] : [])],
                  extraRoot: [Self.thumbnails])
    }

    private func tempFile(_ data: Data) throws -> String {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("dm4-experiment-\(UUID().uuidString).dm4")
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url.path
    }

    private func int16s(in data: Data, at offset: Int, count: Int) -> [Int16] {
        (0..<count).map { i in data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset + 2 * i, as: Int16.self) } }
    }

    func testTheOldReaderStillOpensTheMultiObjectFileAndAgreesOnTheBlob() async throws {
        // DM4Reader (not changed) must find the same 4D blob DM4Experiment lists, past a struct
        // tag and a >4 KiB array; its first pattern equals the values at DM4Experiment's offset.
        // No type-18 tag in this file: DM4Reader's walk reads a spare u32 after a type-18 info array
        // (see the DEVIATION note in DM4Experiment.swift) and cannot open a file that has one,
        // before OR after the 4D object. That is a separate DM4Reader item, not pinned here.
        let data = fullFile()
        let diff = try XCTUnwrap(DM4Experiment.list(data: data).first { $0.role == .diffraction })
        let reader = try await DM4Reader(path: try tempFile(data))
        let descriptor = try await reader.discoverPrimaryDataset()
        XCTAssertEqual(descriptor.shape, [3, 2, 2, 2])
        XCTAssertEqual(descriptor.dtypeDescription, "int16")
        XCTAssertEqual(descriptor.datasetPath, "ImageList.\(diff.index).ImageData.Data")
        let view = LoadView(fullExtentOf: descriptor)
        let first = try await reader.readPattern(view, ry: 0, rx: 0)
        XCTAssertEqual(first, int16s(in: data, at: diff.dataOffset, count: 4).map(Float.init))
        let later = try await reader.readPattern(view, ry: 2, rx: 1)        // pattern 5 of 6
        XCTAssertEqual(later, int16s(in: data, at: diff.dataOffset + 5 * 4 * 2, count: 4).map(Float.init))
    }
}
