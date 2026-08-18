import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

// MARK: - Minimal DM4 byte writer.
// Structure fields (labels, counts, SPECIAL, %%%%, encoded-type ints) are
// big-endian; pixel/primitive values are little-endian. See docs/dm4-format.md.

struct ByteWriter {
    private(set) var bytes: [UInt8] = []

    mutating func u8(_ v: UInt8) { bytes.append(v) }

    mutating func u16be(_ v: UInt16) {
        bytes.append(UInt8(truncatingIfNeeded: v >> 8))
        bytes.append(UInt8(truncatingIfNeeded: v))
    }

    mutating func u32be(_ v: UInt32) {
        bytes.append(UInt8(truncatingIfNeeded: v >> 24))
        bytes.append(UInt8(truncatingIfNeeded: v >> 16))
        bytes.append(UInt8(truncatingIfNeeded: v >> 8))
        bytes.append(UInt8(truncatingIfNeeded: v))
    }

    mutating func u64be(_ v: UInt64) {
        bytes.append(UInt8(truncatingIfNeeded: v >> 56))
        bytes.append(UInt8(truncatingIfNeeded: v >> 48))
        bytes.append(UInt8(truncatingIfNeeded: v >> 40))
        bytes.append(UInt8(truncatingIfNeeded: v >> 32))
        bytes.append(UInt8(truncatingIfNeeded: v >> 24))
        bytes.append(UInt8(truncatingIfNeeded: v >> 16))
        bytes.append(UInt8(truncatingIfNeeded: v >> 8))
        bytes.append(UInt8(truncatingIfNeeded: v))
    }

    mutating func i16le(_ v: Int16) {
        let u = UInt16(bitPattern: v)
        bytes.append(UInt8(truncatingIfNeeded: u))
        bytes.append(UInt8(truncatingIfNeeded: u >> 8))
    }

    mutating func i32le(_ v: Int32) {
        let u = UInt32(bitPattern: v)
        bytes.append(UInt8(truncatingIfNeeded: u))
        bytes.append(UInt8(truncatingIfNeeded: u >> 8))
        bytes.append(UInt8(truncatingIfNeeded: u >> 16))
        bytes.append(UInt8(truncatingIfNeeded: u >> 24))
    }

    mutating func ascii(_ s: String) { bytes.append(contentsOf: Array(s.utf8)) }
    mutating func raw(_ b: [UInt8]) { bytes.append(contentsOf: b) }
}

// MARK: - DM4 tag-tree fragment builders (DM4: SPECIAL fields are u64be)

/// version=4, root length (unused by the parser — it only discards this
/// value), byteord=1 (little-endian data).
func dm4Header() -> [UInt8] {
    var w = ByteWriter()
    w.u32be(4)
    w.u64be(0)
    w.u32be(1)
    return w.bytes
}

/// A tag group's own is_sorted/is_open/nTags fields.
func groupHeader(nTags: Int) -> [UInt8] {
    var w = ByteWriter()
    w.u8(1); w.u8(0); w.u64be(UInt64(nTags))
    return w.bytes
}

/// A "number" data tag: info = [encType]; encType 3 = int32, one
/// little-endian value.
func numberTag(_ label: String, _ value: Int32) -> [UInt8] {
    var w = ByteWriter()
    w.u8(21)
    w.u16be(UInt16(label.utf8.count))
    w.ascii(label)
    w.u64be(0)                       // per-entry byte count; parser discards it
    w.ascii("%%%%")
    w.u64be(1)                       // ninfo
    w.u64be(3)                       // encType = int32
    w.i32le(value)
    return w.bytes
}

/// A subgroup tag entry (kind=20 + label + byte count) immediately followed
/// by that subgroup's own is_sorted/is_open/nTags. Callers append the
/// subgroup's `nTags` children right after this.
func subgroupEntry(_ label: String, nTags: Int) -> [UInt8] {
    var w = ByteWriter()
    w.u8(20)
    w.u16be(UInt16(label.utf8.count))
    w.ascii(label)
    w.u64be(0)
    w.raw(groupHeader(nTags: nTags))
    return w.bytes
}

/// An array data tag: info = [20, elementType, length]. `payload` is the
/// raw little-endian element bytes placed immediately after the header —
/// this is the datacube blob when label == "Data".
func arrayTag(_ label: String, elementType: UInt64, length: UInt64, payload: [UInt8]) -> [UInt8] {
    var w = ByteWriter()
    w.u8(21)
    w.u16be(UInt16(label.utf8.count))
    w.ascii(label)
    w.u64be(0)
    w.ascii("%%%%")
    w.u64be(3)                       // ninfo
    w.u64be(20)                      // encType = array
    w.u64be(elementType)
    w.u64be(length)
    w.raw(payload)
    return w.bytes
}

/// The standard `ImageData` object `locateDatacube` looks for: `DataType`
/// (int16 = 1), `Dimensions.{0,1,2,3}` (fastest-first: Qx,Qy,Rx,Ry), and a
/// `Data` array tag holding the pixel blob (element type 2 = int16, 2
/// bytes/elem, matching DataType 1).
func imageDataObject(qx: Int32, qy: Int32, rx: Int32, ry: Int32,
                      dataLength: UInt64, dataPayload: [UInt8]) -> [UInt8] {
    let dims = subgroupEntry("Dimensions", nTags: 4)
        + numberTag("0", qx) + numberTag("1", qy) + numberTag("2", rx) + numberTag("3", ry)
    let data = arrayTag("Data", elementType: 2, length: dataLength, payload: dataPayload)
    return subgroupEntry("ImageData", nTags: 3)
        + numberTag("DataType", 1)
        + dims
        + data
}

func writeFixture(_ bytes: [UInt8], to url: URL) throws {
    try Data(bytes).write(to: url)
}

// MARK: - Tests

/// Tiny true-4D cube: Ry=2, Rx=2, Qy=2, Qx=3, sequential int16 values.
/// Confirms the A2/A3 edits didn't regress ordinary parsing/decoding.
func testValid(in dir: URL) async throws {
    var pixels = ByteWriter()
    for i in 0..<24 { pixels.i16le(Int16(i)) }
    let body = dm4Header() + groupHeader(nTags: 1)
        + imageDataObject(qx: 3, qy: 2, rx: 2, ry: 2, dataLength: 24, dataPayload: pixels.bytes)
    let url = dir.appendingPathComponent("valid.dm4")
    try writeFixture(body, to: url)

    let reader = try await DM4Reader(path: url.path)
    let ds = try await reader.discoverPrimaryDataset()
    guard ds.shape == [2, 2, 2, 3] else { fail("valid: shape \(ds.shape)") }
    guard ds.dtypeDescription == "int16" else { fail("valid: dtype \(ds.dtypeDescription)") }

    let pattern = try await reader.readPattern(LoadView(fullExtentOf: ds), ry: 1, rx: 0)
    guard pattern == [12, 13, 14, 15, 16, 17] else { fail("valid: readPattern \(pattern)") }

    let row = try await reader.readScanRow(LoadView(fullExtentOf: ds), ry: 0)
    guard row == (0..<12).map(Float.init) else { fail("valid: readScanRow \(row)") }

    let tile = try await reader.readScanTile(LoadView(fullExtentOf: ds), yRange: 0..<2)
    guard tile.pixels == (0..<24).map(Float.init) else { fail("valid: readScanTile \(tile.pixels)") }

    print("PASS: valid tiny 4D cube decodes correct shape and int16 values")
}

/// Same tags, but the pixel payload is cut short. Before the A2 fix this
/// "opened" and served zero-filled patterns; now discovery must reject the
/// candidate (mapping too short for the declared cube) or a read must throw
/// — never a silent, incomplete-but-successful decode.
func testTruncated(in dir: URL) async throws {
    var pixels = ByteWriter()
    for i in 0..<24 { pixels.i16le(Int16(i)) }
    let full = dm4Header() + groupHeader(nTags: 1)
        + imageDataObject(qx: 3, qy: 2, rx: 2, ry: 2, dataLength: 24, dataPayload: pixels.bytes)
    let truncated = Array(full.dropLast(24))   // drop half of the 48-byte blob
    let url = dir.appendingPathComponent("truncated.dm4")
    try writeFixture(truncated, to: url)

    do {
        let reader = try await DM4Reader(path: url.path)
        let ds = try await reader.discoverPrimaryDataset()
        do {
            _ = try await reader.readPattern(LoadView(fullExtentOf: ds), ry: 1, rx: 0)
            fail("truncated: readPattern silently returned data past EOF")
        } catch {
            // Any thrown error here satisfies "no silent success."
        }
    } catch {
        // Any thrown error at open/discovery time also satisfies it.
    }
    print("PASS: truncated pixel payload never yields a silent zero-filled read")
}

/// Dimensions.{0..3} each ~2^20: ry*rx*qy*qx*elementSize overflows Int64.
/// Before the A3 fix this trapped; now the overflowing candidate must be
/// rejected (not crash), leaving no valid datacube.
func testOverflowDims(in dir: URL) async throws {
    let body = dm4Header() + groupHeader(nTags: 1)
        + imageDataObject(qx: 1_048_576, qy: 1_048_576, rx: 1_048_576, ry: 1_048_576,
                          dataLength: 0, dataPayload: [])
    let url = dir.appendingPathComponent("overflow.dm4")
    try writeFixture(body, to: url)

    do {
        _ = try await DM4Reader(path: url.path)
        fail("overflow dims: discovery unexpectedly succeeded")
    } catch DM4Error.noDatacube {
        print("PASS: overflow-scale dims reject via noDatacube, no Int trap")
    } catch {
        fail("overflow dims: wrong error \(error)")
    }
}

/// 200 levels of nested single-child tag groups, then EOF. Before the A3 fix
/// `walkGroup` recursed unboundedly; now depth is capped at 64.
func testDeepNesting(in dir: URL) async throws {
    var body = dm4Header() + groupHeader(nTags: 1)
    for i in 0..<200 { body += subgroupEntry("G\(i)", nTags: 1) }
    let url = dir.appendingPathComponent("deep.dm4")
    try writeFixture(body, to: url)

    do {
        _ = try await DM4Reader(path: url.path)
        fail("deep nesting: discovery unexpectedly succeeded")
    } catch DM4Error.truncated {
        print("PASS: 200 nested tag groups reject via depth cap, no stack overflow")
    } catch {
        fail("deep nesting: wrong error \(error)")
    }
}

@main struct DM4RobustnessHarness {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else { fail("usage: harness workdir") }
        let workDir = URL(fileURLWithPath: CommandLine.arguments[1])

        try await testValid(in: workDir)
        try await testTruncated(in: workDir)
        try await testOverflowDims(in: workDir)
        try await testDeepNesting(in: workDir)

        print("dm4-robustness-test: all passed")
    }
}
