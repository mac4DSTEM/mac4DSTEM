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

    mutating func u16le(_ v: UInt16) {
        bytes.append(UInt8(truncatingIfNeeded: v))
        bytes.append(UInt8(truncatingIfNeeded: v >> 8))
    }

    mutating func i32le(_ v: Int32) {
        let u = UInt32(bitPattern: v)
        bytes.append(UInt8(truncatingIfNeeded: u))
        bytes.append(UInt8(truncatingIfNeeded: u >> 8))
        bytes.append(UInt8(truncatingIfNeeded: u >> 16))
        bytes.append(UInt8(truncatingIfNeeded: u >> 24))
    }

    mutating func f32le(_ v: Float) {
        let u = v.bitPattern
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

func floatTag(_ label: String, _ value: Float) -> [UInt8] {
    var w = ByteWriter()
    w.u8(21)
    w.u16be(UInt16(label.utf8.count))
    w.ascii(label)
    w.u64be(0)
    w.ascii("%%%%")
    w.u64be(1)
    w.u64be(6)                       // encType = float32
    w.f32le(value)
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


func unitsTag(_ units: String) -> [UInt8] {
    var payload = ByteWriter()
    for codeUnit in units.utf16 { payload.u16le(codeUnit) }
    return arrayTag("Units", elementType: 4,
                    length: UInt64(units.utf16.count), payload: payload.bytes)
}

func calibrationDimensions(
    labels: [String], scales: [Float], units: [String]
) -> [UInt8] {
    precondition(labels.count == 4 && scales.count == 4 && units.count == 4)
    var dimensions = [UInt8]()
    for index in 0..<4 {
        dimensions += subgroupEntry(labels[index], nTags: 2)
            + floatTag("Scale", scales[index])
            + unitsTag(units[index])
    }
    return subgroupEntry("Calibrations", nTags: 1)
        + subgroupEntry("Dimension", nTags: 4)
        + dimensions
}

/// The standard `ImageData` object `locateDatacube` looks for: `DataType`
/// (int16 = 1), `Dimensions.{0,1,2,3}` (fastest-first: Qx,Qy,Rx,Ry), and a
/// `Data` array tag holding the pixel blob (element type 2 = int16, 2
/// bytes/elem, matching DataType 1).
func imageDataObject(qx: Int32, qy: Int32, rx: Int32, ry: Int32,
                     dataType: Int32 = 1, arrayElementType: UInt64 = 2,
                     dimensionLabels: [String] = ["0", "1", "2", "3"],
                     calibration: [UInt8]? = nil,
                     dataLength: UInt64, dataPayload: [UInt8]) -> [UInt8] {
    imageDataObject(
        rawDimensions: [qx, qy, rx, ry], dataType: dataType,
        arrayElementType: arrayElementType, dimensionLabels: dimensionLabels,
        calibration: calibration, dataLength: dataLength,
        dataPayload: dataPayload
    )
}

func imageDataObject(rawDimensions: [Int32], dataType: Int32,
                     arrayElementType: UInt64,
                     dimensionLabels: [String],
                     calibration: [UInt8]? = nil,
                     dataLength: UInt64, dataPayload: [UInt8]) -> [UInt8] {
    precondition(rawDimensions.count == 4)
    precondition(dimensionLabels.count == 4)
    let dims = subgroupEntry("Dimensions", nTags: 4)
        + numberTag(dimensionLabels[0], rawDimensions[0])
        + numberTag(dimensionLabels[1], rawDimensions[1])
        + numberTag(dimensionLabels[2], rawDimensions[2])
        + numberTag(dimensionLabels[3], rawDimensions[3])
    let data = arrayTag("Data", elementType: arrayElementType,
                        length: dataLength, payload: dataPayload)
    return subgroupEntry("ImageData", nTags: calibration == nil ? 3 : 4)
        + numberTag("DataType", dataType)
        + dims
        + (calibration ?? [])
        + data
}

