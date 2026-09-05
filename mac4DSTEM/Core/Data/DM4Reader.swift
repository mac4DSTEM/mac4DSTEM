//
//  DM4Reader.swift
//  Role: Read Gatan DigitalMicrograph .dm4 (and .dm3) 4D-STEM files. Parses the
//        tag tree to locate the datacube + calibration, memory-maps the file,
//        and serves CBED patterns / scan rows converted to Float32 — the same
//        interface H5Reader provides (see FourDDataSource).
//
//  Implements docs/dm4-format.md (verified against openNCEM ncempy.io.dm).
//  Structure fields are big-endian; primitive values are little-endian
//  (byteord == 1, required). The data blob is never copied into RAM — patterns
//  are sliced from the mapping on demand.
//

import Foundation

package enum DM4Error: LocalizedError {
    case cannotOpen(String)
    case notLittleEndian
    case noDatacube
    case unsupportedDataType(Int)
    case truncated

    package var errorDescription: String? {
        switch self {
        case .cannotOpen(let detail): return "Could not open DM file: \(detail)"
        case .notLittleEndian: return "This DM file is big-endian (Mac-authored); only little-endian DM files are supported."
        case .noDatacube: return "No 4D (or scan-shaped 3D) datacube was found in this DM file."
        case .unsupportedDataType(let t): return "Unsupported DM image data type \(t)."
        case .truncated: return "The DM file ended unexpectedly while parsing."
        }
    }
}

package actor DM4Reader: FourDDataSource {

    /// Which logical pair occupies the two fastest-changing DM dimensions.
    /// Most DM cubes put detector pixels first, while some Gatan STEM-SI files
    /// (including Si-SiGe.dm4) put scan positions first.
    private enum StorageLayout {
        case detectorFastest
        case scanFastest
    }

    /// The parsed layout, readable from the nonisolated `loadPushdown`.
    /// Written once by `parse()` inside `init`, before any caller can hold
    /// the reader; the lock is what makes that claim checkable rather than
    /// a `nonisolated(unsafe)` promise.
    private nonisolated final class LayoutCell: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: StorageLayout?
        var value: StorageLayout? {
            get { lock.lock(); defer { lock.unlock() }; return stored }
            set { lock.lock(); stored = newValue; lock.unlock() }
        }
    }

    private let data: Data
    package let filePath: String
    private let layoutCell = LayoutCell()

    private var descriptor: DatasetDescriptor?
    private var dataOffset = 0        // byte offset of the datacube blob
    private var imageDataType = 0     // Gatan ImageData.DataType code
    private var elementSize = 0       // bytes per pixel
    private var ry = 0, rx = 0, qy = 0, qx = 0
    private var storageLayout = StorageLayout.detectorFastest {
        didSet { layoutCell.value = storageLayout }
    }

    // Best-effort calibration.
    package private(set) var voltage: Double?
    package private(set) var qPixelSize: Double?
    package private(set) var qPixelUnits: String?
    package private(set) var rPixelSize: Double?
    package private(set) var rPixelUnits: String?
    /// Why the file's pixel calibration was NOT imported, when its four axis
    /// units could not name one real-space pair and one reciprocal pair. The
    /// cube still opens, in the legacy detector-fastest layout, with no pixel
    /// sizes — py4DSTEM's own answer to a Gatan file whose calibration is
    /// invalid (`read_dm.py`, "the calibrations can be invalid"). Refusing the
    /// file was the 2026-09-05 first cut and was reversed the same day: a
    /// wrong calibration is the user's to override, a closed file is not.
    package private(set) var calibrationNote: String?

    // Async so the init is actor-isolated and may call parse(), which
    // mutates actor state; a synchronous actor init is nonisolated and
    // such a call is an error in Swift 6 language mode.
    package init(path: String) async throws {
        // The underlying error travels with the refusal (v2 S7 audit): the
        // old `try?` collapsed EPERM, ENOENT and a short read into one
        // pathless "cannot open". The `.mappedIfSafe` semantics themselves —
        // and whether a NAS mount makes this a hidden full read — are S9's
        // Gate D experiment (docs/v2-release.md §8); do not change the
        // mapping option here.
        do {
            self.data = try Data(contentsOf: URL(fileURLWithPath: path),
                                 options: .mappedIfSafe)
        } catch {
            throw DM4Error.cannotOpen(
                "\(displayFileName(path)) — \(error.localizedDescription)")
        }
        self.filePath = path
        try parse()
    }

    // MARK: FourDDataSource

    package func discoverPrimaryDataset() throws -> DatasetDescriptor {
        guard let descriptor else { throw DM4Error.noDatacube }
        return descriptor
    }

    /// Detector-fastest DM4 is one contiguous blob of patterns, so a *scan*
    /// crop is a seek and genuinely skips bytes; a *detector* crop decodes
    /// only the kept rows, but the excluded columns share pages with the kept
    /// ones, and `LoadPushdown` is a boolean that rounds down (adversarial
    /// review, 2026-08-18). Scan-fastest storage spreads every pattern across
    /// the whole blob, so there neither crop skips I/O. The layout is parsed
    /// in `init`, and `layoutCell` is how this nonisolated method sees it.
    package nonisolated func loadPushdown(for view: LoadView) -> LoadPushdown {
        layoutCell.value == .scanFastest ? .none : .scanOnly
    }

    /// Byte offset of the first pixel of source pattern (`sourceY`, `sourceX`).
    private func frameOffset(sourceY: Int, sourceX: Int) -> Int {
        dataOffset + (sourceY * rx + sourceX) * (qy * qx) * elementSize
    }

    /// One source pattern, detector crop applied. Decoded row by row when
    /// cropped, so the cropped-out columns are never converted to Float — the
    /// memory saving is real even though the I/O saving is not.
    private func pattern(_ view: LoadView, sourceY: Int, sourceX: Int) throws -> [Float] {
        if storageLayout == .scanFastest {
            return view.binned(
                try scanFastestGather(view, positions: [(sourceY, sourceX)]),
                patternCount: 1)
        }
        let base = frameOffset(sourceY: sourceY, sourceX: sourceX)
        guard let crop = view.readDetectorCrop else {
            return view.binned(try decode(byteOffset: base, count: qy * qx),
                               patternCount: 1)
        }
        // Decoded straight into one buffer rather than one array per row: a
        // 512-row crop over a 256x256 scan is ~34 million rows, and a fresh
        // heap allocation each would dominate the read. Found by adversarial
        // review 2026-08-18, before any caller could reach it.
        var out = [Float](repeating: 0, count: crop.height * crop.width)
        for row in 0..<crop.height {
            let rowStart = base + ((crop.yOffset + row) * qx + crop.xOffset) * elementSize
            try decode(byteOffset: rowStart, count: crop.width,
                       into: &out, at: row * crop.width)
        }
        return view.binned(out, patternCount: 1)
    }

    /// Element strides of the two detector axes in scan-fastest storage. The
    /// scan plane (`ry * rx` elements) is the contiguous unit; which detector
    /// axis steps by one plane and which by a whole detector row is THE
    /// orientation question still under Gate D (`open-items.md`, "Scan-fastest
    /// DM4 detector pair may be transposed"). Today's model: fastest-first tags
    /// `[Rx, Ry, Qy, Qx]`, so `qy` steps by one plane and `qx` by `qy` planes.
    /// Flipping that model is this one property plus the shape line in
    /// `locateDatacube`; every read path below goes through here.
    private var scanFastestStrides: (qy: Int, qx: Int) {
        (qy: ry * rx, qx: qy * ry * rx)
    }

    /// Gather patterns from scan-fastest storage, `positions` being source
    /// scan positions in output order. Returns `[position][outY][outX]` over
    /// `readDetectorCrop` (or the whole detector), BEFORE binning.
    ///
    /// One pattern is strided across the whole blob here, so the naive
    /// pattern-at-a-time loop — the 2026-09-05 first cut — walked a 1.2 MB
    /// stride per detector pixel and took 19 s for the 560 MB `Si-SiGe.dm4`.
    /// This is a blocked transpose instead: for a block of 32 detector
    /// columns and 32 scan positions, the 32 source cache lines are each
    /// reused 32 times and every output run is contiguous, so a full-cube
    /// read is bounded by memory bandwidth, not by cache misses.
    private func scanFastestGather(
        _ view: LoadView, positions: [(y: Int, x: Int)]
    ) throws -> [Float] {
        let cropY = view.readDetectorCrop?.yOffset ?? 0
        let cropX = view.readDetectorCrop?.xOffset ?? 0
        let height = view.readDetectorCrop?.height ?? qy
        let width = view.readDetectorCrop?.width ?? qx
        let strides = scanFastestStrides
        let count = positions.count
        guard count > 0 else { return [] }

        // Element offset of each position inside a detector pixel's scan
        // plane; the same for every detector pixel.
        let planeOffsets = positions.map { $0.y * rx + $0.x }
        guard let farthest = planeOffsets.max(), planeOffsets.min()! >= 0 else {
            throw DM4Error.truncated
        }
        // Never hand back zero-filled pixels as if they were read: the last
        // element this gather touches must lie inside the mapping.
        let lastElement = (cropX + width - 1) * strides.qx
            + (cropY + height - 1) * strides.qy + farthest
        let (lastByte, o1) = lastElement.multipliedReportingOverflow(by: elementSize)
        let (byteEnd, o2) = lastByte.addingReportingOverflow(elementSize)
        let (end, o3) = dataOffset.addingReportingOverflow(byteEnd)
        guard !o1, !o2, !o3, end <= data.count else { throw DM4Error.truncated }

        var out = [Float](repeating: 0, count: count * height * width)
        let block = 32
        // Which detector axis walks the file in the larger steps. A gather of
        // fewer positions than one block has no cache line to reuse, and the
        // pattern browser's single pattern touches every page of the file
        // whatever the order — so there the loop follows STORAGE order (major
        // stride outermost), which turns 215 040 random page touches into a
        // sequential sweep. Measured on `Si-SiGe.dm4`: one pattern 3.7 s → 0.04 s.
        let majorIsX = strides.qx >= strides.qy
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            let origin = base + dataOffset
            func sweep<T>(_: T.Type, _ toFloat: (T) -> Float) {
                out.withUnsafeMutableBufferPointer { out in
                    let (majorCount, minorCount) = majorIsX ? (width, height) : (height, width)
                    for major in 0..<majorCount {
                        for minor in 0..<minorCount {
                            let (outY, outX) = majorIsX ? (minor, major) : (major, minor)
                            let element = (cropY + outY) * strides.qy + (cropX + outX) * strides.qx
                            for p in 0..<count {
                                out[(p * height + outY) * width + outX] = toFloat(origin.loadUnaligned(
                                    fromByteOffset: (element + planeOffsets[p]) * MemoryLayout<T>.size,
                                    as: T.self))
                            }
                        }
                    }
                }
            }
            func transpose<T>(_: T.Type, _ toFloat: (T) -> Float) {
                if count < block { return sweep(T.self, toFloat) }
                out.withUnsafeMutableBufferPointer { out in
                    for outY in 0..<height {
                        let rowBase = (cropY + outY) * strides.qy
                        var x0 = 0
                        while x0 < width {
                            let x1 = min(x0 + block, width)
                            var p0 = 0
                            while p0 < count {
                                let p1 = min(p0 + block, count)
                                for p in p0..<p1 {
                                    let sourceBase = rowBase + planeOffsets[p]
                                    let outBase = (p * height + outY) * width
                                    for outX in x0..<x1 {
                                        let element = sourceBase + (cropX + outX) * strides.qx
                                        out[outBase + outX] = toFloat(origin.loadUnaligned(
                                            fromByteOffset: element * MemoryLayout<T>.size, as: T.self))
                                    }
                                }
                                p0 = p1
                            }
                            x0 = x1
                        }
                    }
                }
            }
            switch imageDataType {
            case 1:  transpose(Int16.self) { Float($0) }
            case 10: transpose(UInt16.self) { Float($0) }
            case 7:  transpose(Int32.self) { Float($0) }
            case 11: transpose(UInt32.self) { Float($0) }
            case 6:  transpose(UInt8.self) { Float($0) }
            case 9:  transpose(Int8.self) { Float($0) }
            case 2:  transpose(Float.self) { $0 }
            case 12: transpose(Double.self) { Float($0) }
            default: break
            }
        }
        return out
    }

    /// True when a whole view scan row is one contiguous run of source bytes:
    /// no detector crop, and the full source scan width. Then the tile is a
    /// single decode, which is the shipped streaming path.
    private func rowsAreContiguous(_ view: LoadView) -> Bool {
        storageLayout == .detectorFastest
            && view.readDetectorCrop == nil
            && view.specification.scanOffset.x == 0
            && view.descriptor.rx == rx
    }

    package func readPattern(_ view: LoadView, ry scanY: Int, rx scanX: Int) throws -> [Float] {
        try view.requireSource(shape: [ry, rx, qy, qx])
        guard scanY >= 0, scanY < view.descriptor.ry,
              scanX >= 0, scanX < view.descriptor.rx else {
            throw DM4Error.truncated
        }
        return try pattern(view, sourceY: view.sourceScanY(scanY),
                           sourceX: view.sourceScanX(scanX))
    }

    package func readScanRow(_ view: LoadView, ry scanY: Int) throws -> [Float] {
        try view.requireSource(shape: [ry, rx, qy, qx])
        guard scanY >= 0, scanY < view.descriptor.ry else { throw DM4Error.truncated }
        return try scanRow(view, viewY: scanY)
    }

    /// The source positions of a run of view rows, in output order.
    private func sourcePositions(_ view: LoadView, rows: Range<Int>) -> [(y: Int, x: Int)] {
        rows.flatMap { viewY in
            (0..<view.descriptor.rx).map { viewX in
                (y: view.sourceScanY(viewY), x: view.sourceScanX(viewX))
            }
        }
    }

    private func scanRow(_ view: LoadView, viewY: Int) throws -> [Float] {
        let sourceY = view.sourceScanY(viewY)
        if storageLayout == .scanFastest {
            return view.binned(
                try scanFastestGather(view, positions: sourcePositions(view, rows: viewY..<(viewY + 1))),
                patternCount: view.descriptor.rx)
        }
        if rowsAreContiguous(view) {
            let rowPix = rx * qy * qx
            let raw = try decode(byteOffset: dataOffset + sourceY * rowPix * elementSize,
                                 count: rowPix)
            return view.binned(raw, patternCount: rx)
        }
        if storageLayout == .detectorFastest && view.readDetectorCrop == nil {
            // Still one contiguous run — a sub-range of patterns within the row.
            let patPix = qy * qx
            let start = frameOffset(sourceY: sourceY,
                                    sourceX: view.specification.scanOffset.x)
            let raw = try decode(byteOffset: start, count: view.descriptor.rx * patPix)
            return view.binned(raw, patternCount: view.descriptor.rx)
        }
        var out = [Float]()
        out.reserveCapacity(view.descriptor.rx * view.descriptor.qy * view.descriptor.qx)
        for viewX in 0..<view.descriptor.rx {
            out.append(contentsOf: try pattern(view, sourceY: sourceY,
                                               sourceX: view.sourceScanX(viewX)))
        }
        return out
    }

    package func readScanTile(_ view: LoadView,
                      yRange: Range<Int>) throws -> FourDScanTile {
        try view.requireSource(shape: [ry, rx, qy, qx])
        let lower = max(0, yRange.lowerBound)
        let upper = min(view.descriptor.ry, yRange.upperBound)
        let range = lower..<max(lower, upper)
        let pixels: [Float]
        if rowsAreContiguous(view) {
            let rowPix = rx * qy * qx
            let start = dataOffset
                + view.sourceScanY(lower) * rowPix * elementSize
            let raw = try decode(byteOffset: start, count: range.count * rowPix)
            pixels = view.binned(raw, patternCount: range.count * rx)
        } else if storageLayout == .scanFastest {
            // One pass for the whole tile: the blocked gather amortises each
            // source cache line over every position in the tile.
            pixels = view.binned(
                try scanFastestGather(view, positions: sourcePositions(view, rows: range)),
                patternCount: range.count * view.descriptor.rx)
        } else {
            var buffer = [Float]()
            buffer.reserveCapacity(
                range.count * view.descriptor.rx * view.descriptor.qy * view.descriptor.qx
            )
            for viewY in range {
                buffer.append(contentsOf: try scanRow(view, viewY: viewY))
            }
            pixels = buffer
        }
        return FourDScanTile(
            yRange: range, scanWidth: view.descriptor.rx,
            detectorHeight: view.descriptor.qy, detectorWidth: view.descriptor.qx,
            pixels: pixels
        )
    }

    package func readDoubleAttribute(_ name: String, onObjectPath path: String) -> Double? {
        let lower = name.lowercased()
        if lower.contains("voltage") || lower.contains("beam_energy") || lower.contains("kv") {
            return voltage
        }
        return nil
    }

    package func pixelCalibration() -> PixelCalibration? {
        guard qPixelSize != nil || rPixelSize != nil else { return nil }
        return PixelCalibration(rSize: rPixelSize, rUnits: rPixelUnits,
                                qSize: qPixelSize, qUnits: qPixelUnits)
    }

    // MARK: Pixel decode (little-endian → Float)

    private func decode(byteOffset start: Int, count: Int) throws -> [Float] {
        var out = [Float](repeating: 0, count: count)
        try decode(byteOffset: start, count: count, into: &out, at: 0)
        return out
    }

    /// Decode `count` values into an existing buffer at `destination`, so a
    /// row-by-row cropped read does not allocate per row.
    private func decode(byteOffset start: Int, count: Int,
                        into out: inout [Float], at destination: Int) throws {
        let need = count * elementSize
        // A slice past the mapping means a truncated file; never hand back
        // zero-filled pixels as if they were read.
        guard start >= 0, start + need <= data.count else { throw DM4Error.truncated }
        guard destination >= 0, destination + count <= out.count else {
            throw DM4Error.truncated
        }
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            let p = base + start
            let d = destination
            switch imageDataType {
            case 1:  for i in 0..<count { out[d + i] = Float(p.loadUnaligned(fromByteOffset: i * 2, as: Int16.self)) }
            case 10: for i in 0..<count { out[d + i] = Float(p.loadUnaligned(fromByteOffset: i * 2, as: UInt16.self)) }
            case 7:  for i in 0..<count { out[d + i] = Float(p.loadUnaligned(fromByteOffset: i * 4, as: Int32.self)) }
            case 11: for i in 0..<count { out[d + i] = Float(p.loadUnaligned(fromByteOffset: i * 4, as: UInt32.self)) }
            case 6:  for i in 0..<count { out[d + i] = Float(p.loadUnaligned(fromByteOffset: i, as: UInt8.self)) }
            case 9:  for i in 0..<count { out[d + i] = Float(p.loadUnaligned(fromByteOffset: i, as: Int8.self)) }
            case 2:  for i in 0..<count { out[d + i] = p.loadUnaligned(fromByteOffset: i * 4, as: Float.self) }
            case 12: for i in 0..<count { out[d + i] = Float(p.loadUnaligned(fromByteOffset: i * 8, as: Double.self)) }
            default: break
            }
        }
    }

    private static func pixelSize(_ dataType: Int) -> Int {
        switch dataType {
        case 6, 9: return 1
        case 1, 10: return 2
        case 2, 7, 11: return 4
        case 12: return 8
        default: return 0
        }
    }

    /// Byte size of a tag encoded-type (§2.1).
    private static func tagTypeSize(_ code: Int) -> Int {
        switch code {
        case 2, 4: return 2
        case 3, 5, 6: return 4
        case 7, 11, 12: return 8
        case 8, 9, 10: return 1
        default: return 0
        }
    }

    // MARK: Parse

    private var dmVersion = 4
    private var numbers: [String: Double] = [:]        // path → scalar value
    private var strings: [String: String] = [:]        // path → string (e.g. units)
    private var dataArrays: [(path: String, offset: Int, bytes: Int)] = []

    private func parse() throws {
        var reader = ByteReader(data)
        dmVersion = Int(reader.u32be())
        _ = reader.special(dmVersion)                  // root length
        let byteord = reader.u32be()
        guard byteord == 1 else { throw DM4Error.notLittleEndian }

        try walkGroup(&reader, prefix: "")
        guard !reader.overran else { throw DM4Error.truncated }
        try locateDatacube()
    }

    private func walkGroup(_ reader: inout ByteReader, prefix: String, depth: Int = 0) throws {
        // Bound recursion so a maliciously/corruptly deep tag tree fails
        // with .truncated instead of overflowing the call stack.
        guard depth <= 64 else { throw DM4Error.truncated }
        _ = reader.u8()                                // is_sorted
        _ = reader.u8()                                // is_open
        let nTags = Int(reader.special(dmVersion))
        for siblingIndex in 0..<nTags {
            guard !reader.overran, reader.remaining >= 3 else { throw DM4Error.truncated }
            let tag = reader.u8()
            if tag == 0 { break }
            let labelLen = Int(reader.u16be())
            // Gatan permits an entry label to be empty. Such entries are not
            // anonymous: they are named by their one-based position inside
            // this group (the same convention ncempy's fileDM parser uses).
            // Keeping an empty string collapses sibling ImageList objects and
            // Dimension entries onto one path, making a valid cube invisible.
            let label = labelLen > 0
                ? reader.string(labelLen)
                : String(siblingIndex + 1)
            let path = prefix.isEmpty ? label : prefix + "." + label
            if dmVersion == 4 { _ = reader.special(dmVersion) }   // per-entry byte count

            if tag == 21 {
                try readDataTag(&reader, path: path, label: label)
            } else if tag == 20 {
                try walkGroup(&reader, prefix: path, depth: depth + 1)
            }
        }
    }

    private func readDataTag(_ reader: inout ByteReader, path: String, label: String) throws {
        let delim = reader.bytes(4)
        guard delim == [37, 37, 37, 37] else { throw DM4Error.truncated }
        let ninfo = Int(reader.special(dmVersion))
        // Malformed counts would otherwise drive a huge allocation below.
        guard ninfo >= 0, ninfo <= 4096 else { throw DM4Error.truncated }
        var info = [UInt64](); info.reserveCapacity(ninfo)
        for _ in 0..<ninfo { info.append(reader.special(dmVersion)) }
        guard let encType = info.first.map(Int.init) else { return }

        switch encType {
        case 2...12:
            let value = reader.value(encType)
            numbers[path] = value

        case 18:                                        // string
            let len = Int(reader.u32be())
            _ = reader.bytes(len)

        case 15:                                        // struct — skip its data
            let nFields = info.count >= 3 ? Int(info[2]) : 0
            var structBytes = 0
            for f in 0..<nFields {
                let idx = 3 + f * 2 + 1
                if idx < info.count { structBytes += Self.tagTypeSize(Int(info[idx])) }
            }
            _ = reader.bytes(structBytes)

        case 20:                                        // array
            let elementType = info.count >= 2 ? Int(info[1]) : 0
            var elemSize = 0
            var lengthIndex = 2
            if elementType == 15 {                      // array of struct
                let nFields = info.count >= 4 ? Int(info[3]) : 0
                for f in 0..<nFields {
                    let idx = 4 + f * 2 + 1
                    if idx < info.count { elemSize += Self.tagTypeSize(Int(info[idx])) }
                }
                lengthIndex = 4 + nFields * 2
            } else {
                elemSize = Self.tagTypeSize(elementType)
            }
            let length = lengthIndex < info.count ? Int(info[lengthIndex]) : 0
            let nbytes = length * elemSize
            let start = reader.offset
            if label == "Data" {
                dataArrays.append((path: path, offset: start, bytes: nbytes))
            } else if nbytes < 1000, elementType == 4 {
                // Units etc.: array of ushort → ASCII string.
                let s = decodeUnits(&reader, length: length)
                strings[path] = s
                reader.seek(start + nbytes)             // ensure aligned
                break
            }
            reader.seek(start + nbytes)

        default:
            break
        }
    }

    private func decodeUnits(_ reader: inout ByteReader, length: Int) -> String {
        var chars = [Character]()
        for _ in 0..<length {
            let code = reader.u16le()
            if code > 0, let scalar = Unicode.Scalar(code) { chars.append(Character(scalar)) }
        }
        return String(chars)
    }

    // MARK: Datacube selection

    private func locateDatacube() throws {
        // Prefer the first Data array whose object has > 2 non-singleton dims.
        for array in dataArrays {
            guard array.path.hasSuffix(".Data") else { continue }
            // Keep the trailing dot: "…ImageData." so "…ImageData." + "DataType"
            // / "Dimensions." / "Calibrations…" join correctly.
            let objectPrefix = String(array.path.dropLast("Data".count))
            let dimensionEntries = dimensions(forObject: objectPrefix)
            let dims = dimensionEntries.map(\.size)
            let nonSingleton = dims.filter { $0 > 1 }.count
            guard nonSingleton > 2 else { continue }
            guard let dtype = numbers[objectPrefix + "DataType"].map(Int.init),
                  Self.pixelSize(dtype) > 0 else { continue }

            let shape: [Int]
            let layout: StorageLayout
            let note: String?
            if dims.count >= 4 {
                (layout, note) = storageLayout(
                    objectPrefix: objectPrefix,
                    dimensionIndices: dimensionEntries.map(\.index)
                )
                switch layout {
                case .detectorFastest:
                    // Fastest-first tags [Qx,Qy,Rx,Ry].
                    shape = [dims[3], dims[2], dims[1], dims[0]]
                case .scanFastest:
                    // Fastest-first tags [Rx,Ry,Qy,Qx]. The corresponding
                    // raw C-order is [Qx,Qy,Ry,Rx], not pattern-contiguous.
                    shape = [dims[1], dims[0], dims[2], dims[3]]
                }
            } else if dims.count == 3 {
                // (N_scan, Qy, Qx); recover scan shape from tags.
                guard let scanX = scanShape("Scan shape X"),
                      let scanY = scanShape("Scan shape Y") else { continue }
                shape = [scanY, scanX, dims[1], dims[0]]
                layout = .detectorFastest
                note = nil
            } else {
                continue
            }

            ry = shape[0]; rx = shape[1]; qy = shape[2]; qx = shape[3]
            imageDataType = dtype
            elementSize = Self.pixelSize(dtype)
            dataOffset = array.offset
            storageLayout = layout

            // Sanity: the blob must hold exactly the cube. Chain
            // multiplication with overflow checks so absurd tag-derived
            // dims reject the candidate instead of trapping.
            let (p1, o1) = ry.multipliedReportingOverflow(by: rx)
            let (p2, o2) = p1.multipliedReportingOverflow(by: qy)
            let (p3, o3) = p2.multipliedReportingOverflow(by: qx)
            let (expected, o4) = p3.multipliedReportingOverflow(by: elementSize)
            guard !(o1 || o2 || o3 || o4) else { continue }
            // The mapping must hold the whole cube; only then is a declared
            // array.bytes == 0 (some writers omit it) still tolerated.
            let (end, o5) = dataOffset.addingReportingOverflow(expected)
            guard !o5, end <= data.count else { continue }
            guard array.bytes == expected || array.bytes == 0 else { continue }

            descriptor = DatasetDescriptor(
                filePath: filePath,
                datasetPath: array.path,
                shape: [ry, rx, qy, qx],
                dtypeDescription: dtypeName(dtype),
                chunkShape: nil)

            calibrationNote = note
            extractCalibration(
                objectPrefix: objectPrefix,
                layout: layout,
                dimensionIndices: dimensionEntries.map(\.index),
                pixelSizesTrusted: note == nil
            )
            return
        }
        throw DM4Error.noDatacube
    }

    private func dimensions(forObject prefix: String) -> [(index: Int, size: Int)] {
        // Keys like "<prefix>.Dimensions.<k>" → sorted by k ascending (fastest first).
        let dimPrefix = prefix + "Dimensions."
        let entries = numbers.compactMap { (key, value) -> (Int, Int)? in
            guard key.hasPrefix(dimPrefix) else { return nil }
            let tail = key.dropFirst(dimPrefix.count)
            guard let k = Int(tail) else { return nil }
            return (k, Int(value))
        }
        return entries.sorted { $0.0 < $1.0 }
    }

    private enum AxisDomain: Hashable { case real, reciprocal }

    private func axisDomain(_ units: String?) -> AxisDomain? {
        guard let units else { return nil }
        let normalized = units.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "μ", with: "µ")
        if normalized == "mrad"
            || normalized.contains("1/")
            || normalized.contains("^-1")
            || normalized.contains("⁻¹") {
            return .reciprocal
        }
        if ["nm", "µm", "um", "å", "angstrom", "angstroms"].contains(normalized) {
            return .real
        }
        return nil
    }

    /// Infer axis roles from the dimension calibration rather than from size.
    /// Size is not a safe discriminator: a narrow detector can be smaller than
    /// a large scan. Missing/unknown units preserve the historical
    /// detector-fastest interpretation for compatibility. Known units that
    /// contradict each other (a mixed pair, or both pairs in one domain) also
    /// fall back to that layout, but with the calibration DROPPED and the
    /// reason returned as a note: the file opens, its pixel sizes do not.
    ///
    /// Newer GMS versions also write `ImageTags.Meta Data.Data Order Swapped`,
    /// the tag LiberTEM's reader honours first; `Si-SiGe.dm4` (2018) lacks it,
    /// so it is not yet read here (`open-items.md`).
    private func storageLayout(
        objectPrefix prefix: String, dimensionIndices: [Int]
    ) -> (layout: StorageLayout, note: String?) {
        guard dimensionIndices.count >= 4 else { return (.detectorFastest, nil) }
        let indices = Array(dimensionIndices.prefix(4))
        let units = indices.map {
            strings[prefix + "Calibrations.Dimension.\($0).Units"]
        }
        let contradiction = "Pixel calibration not imported: the DM file's axis units "
            + "(\(units.map { $0 ?? "none" }.joined(separator: ", "))) do not name one "
            + "real-space pair and one diffraction pair. Enter the pixel sizes by hand."
        // nil: not fully known. A pair whose two known units disagree is a
        // contradiction, reported through `contradictory`.
        var contradictory = false
        func pairDomain(_ range: Range<Int>) -> AxisDomain? {
            let domains = range.map { axisDomain(units[$0]) }
            guard domains.allSatisfy({ $0 != nil }) else { return nil }
            let known = Set(domains.compactMap { $0 })
            if known.count > 1 { contradictory = true }
            return known.first
        }
        let leading = pairDomain(0..<2)
        let trailing = pairDomain(2..<4)
        if contradictory { return (.detectorFastest, contradiction) }
        guard let leading, let trailing else { return (.detectorFastest, nil) }
        guard leading != trailing else { return (.detectorFastest, contradiction) }

        // DEVIATION from py4DSTEM: read_dm.py blindly wraps ncempy's reversed
        // shape as [Rx,Ry,Qx,Qy], then drops the calibration when it finds
        // real-space units on the first axis. Gatan STEM-SI files can instead
        // store the scan pair fastest; the calibration domains are the file's
        // explicit evidence for which pair is scan versus diffraction.
        return (leading == .real ? .scanFastest : .detectorFastest, nil)
    }

    private func scanShape(_ needle: String) -> Int? {
        for (key, value) in numbers where key.contains(needle) { return Int(value) }
        return nil
    }

    private func extractCalibration(
        objectPrefix prefix: String,
        layout: StorageLayout,
        dimensionIndices: [Int],
        pixelSizesTrusted: Bool
    ) {
        func scale(_ i: Int) -> Double? { numbers[prefix + "Calibrations.Dimension.\(i).Scale"] }
        func units(_ i: Int) -> String? {
            let u = strings[prefix + "Calibrations.Dimension.\(i).Units"]
            return (u?.isEmpty ?? true) ? nil : u
        }
        if pixelSizesTrusted, dimensionIndices.count >= 3 {
            let leading = dimensionIndices[0]
            let trailing = dimensionIndices[2]
            let qIndex = layout == .detectorFastest ? leading : trailing
            let rIndex = layout == .detectorFastest ? trailing : leading
            qPixelSize = scale(qIndex)
            qPixelUnits = units(qIndex)
            rPixelSize = scale(rIndex)
            rPixelUnits = units(rIndex)
        }
        for (key, value) in numbers where key.contains("Microscope Info.Voltage") {
            voltage = value; break
        }
    }

    private func dtypeName(_ dataType: Int) -> String {
        switch dataType {
        case 1: return "int16"; case 2: return "float32"; case 6: return "uint8"
        case 7: return "int32"; case 9: return "int8"; case 10: return "uint16"
        case 11: return "uint32"; case 12: return "float64"
        default: return "dm-type-\(dataType)"
        }
    }
}

// MARK: - ByteReader

/// A cursor over a Data buffer (assumed to start at index 0). Structure fields
/// are big-endian; `value`/`u16le` read little-endian primitive values.
///
/// BOUNDS: every load is clamp-safe. Reads past the end return 0 and set
/// `overran`, which the parser checks (walkGroup) to throw `.truncated`
/// instead of crashing on malformed/truncated files.
private nonisolated struct ByteReader {
    package let data: Data
    package var offset = 0
    /// True once any read went past the end of the buffer.
    package private(set) var overran = false

    package init(_ data: Data) { self.data = data }

    package var remaining: Int { data.count - offset }

    package mutating func u8() -> UInt8 {
        guard offset >= 0, offset < data.count else { overran = true; offset += 1; return 0 }
        let v = data[data.startIndex + offset]; offset += 1; return v
    }

    package mutating func u16be() -> UInt16 { load(UInt16.self).bigEndian }
    package mutating func u16le() -> UInt16 { load(UInt16.self).littleEndian }
    package mutating func u32be() -> UInt32 { load(UInt32.self).bigEndian }
    package mutating func u64be() -> UInt64 { load(UInt64.self).bigEndian }

    package mutating func special(_ version: Int) -> UInt64 {
        version == 4 ? u64be() : UInt64(u32be())
    }

    package mutating func bytes(_ n: Int) -> [UInt8] {
        guard n >= 0, offset >= 0, offset <= data.count else { overran = true; offset += max(n, 0); return [] }
        let start = data.startIndex + offset
        let end = min(start + n, data.endIndex)
        if end - start < n { overran = true }
        let slice = data[start..<max(start, end)]
        offset += n
        return [UInt8](slice)
    }

    package mutating func string(_ n: Int) -> String {
        String(decoding: bytes(n), as: UTF8.self)
    }

    /// Read one little-endian primitive of the given tag encoded-type as Double.
    package mutating func value(_ encType: Int) -> Double {
        switch encType {
        case 2:  return Double(load(Int16.self).littleEndian)
        case 3:  return Double(load(Int32.self).littleEndian)
        case 4:  return Double(load(UInt16.self).littleEndian)
        case 5:  return Double(load(UInt32.self).littleEndian)
        case 6:  return Double(Float(bitPattern: load(UInt32.self).littleEndian))
        case 7:  return Double(Double(bitPattern: load(UInt64.self).littleEndian))
        case 8:  return Double(u8())
        case 9:  return Double(Int8(bitPattern: u8()))
        case 10: return Double(Int8(bitPattern: u8()))
        case 11: return Double(Int64(bitPattern: load(UInt64.self).littleEndian))
        case 12: return Double(load(UInt64.self).littleEndian)
        default: return 0
        }
    }

    package mutating func seek(_ to: Int) { offset = to }

    private mutating func load<T: FixedWidthInteger>(_ type: T.Type) -> T {
        let size = MemoryLayout<T>.size
        guard offset >= 0, offset + size <= data.count else {
            overran = true; offset += size; return 0
        }
        let v = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: T.self) }
        offset += size
        return v
    }
}
