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
    case ambiguousAxisCalibration([String])
    case unsupportedDataType(Int)
    case truncated

    package var errorDescription: String? {
        switch self {
        case .cannotOpen(let detail): return "Could not open DM file: \(detail)"
        case .notLittleEndian: return "This DM file is big-endian (Mac-authored); only little-endian DM files are supported."
        case .noDatacube: return "No 4D (or scan-shaped 3D) datacube was found in this DM file."
        case .ambiguousAxisCalibration(let units):
            return "The DM file's dimension calibrations do not identify one real-space pair and one diffraction-space pair (units: \(units.joined(separator: ", ")))."
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

    private let data: Data
    package let filePath: String

    private var descriptor: DatasetDescriptor?
    private var dataOffset = 0        // byte offset of the datacube blob
    private var imageDataType = 0     // Gatan ImageData.DataType code
    private var elementSize = 0       // bytes per pixel
    private var ry = 0, rx = 0, qy = 0, qx = 0
    private var storageLayout = StorageLayout.detectorFastest

    // Best-effort calibration.
    package private(set) var voltage: Double?
    package private(set) var qPixelSize: Double?
    package private(set) var qPixelUnits: String?
    package private(set) var rPixelSize: Double?
    package private(set) var rPixelUnits: String?

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

    /// DM4 permits either scan or detector axes to be contiguous. This method
    /// is nonisolated and cannot inspect the parsed layout, so it conservatively
    /// claims neither crop as skipped I/O. Both crops still reduce conversion
    /// and resident-memory work; `.none` only avoids overstating disk savings.
    package nonisolated func loadPushdown(for view: LoadView) -> LoadPushdown { .none }

    /// Byte offset of the first pixel of source pattern (`sourceY`, `sourceX`).
    private func frameOffset(sourceY: Int, sourceX: Int) -> Int {
        dataOffset + (sourceY * rx + sourceX) * (qy * qx) * elementSize
    }

    /// One source pattern, detector crop applied. Decoded row by row when
    /// cropped, so the cropped-out columns are never converted to Float — the
    /// memory saving is real even though the I/O saving is not.
    private func pattern(_ view: LoadView, sourceY: Int, sourceX: Int) throws -> [Float] {
        if storageLayout == .scanFastest {
            return try scanFastestPattern(view, sourceY: sourceY, sourceX: sourceX)
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

    /// Gather one pattern from `[Qx,Qy,Ry,Rx]` C-order storage. In this DM
    /// layout the scan pair is fastest-changing, so a diffraction pattern is
    /// strided across the blob rather than one contiguous frame.
    private func scanFastestPattern(
        _ view: LoadView, sourceY: Int, sourceX: Int
    ) throws -> [Float] {
        let cropY = view.readDetectorCrop?.yOffset ?? 0
        let cropX = view.readDetectorCrop?.xOffset ?? 0
        let height = view.readDetectorCrop?.height ?? qy
        let width = view.readDetectorCrop?.width ?? qx
        var out = [Float](repeating: 0, count: height * width)

        let scanPlane = ry * rx
        let detectorPlane = qy * scanPlane
        let lastElement = (cropX + width - 1) * detectorPlane
            + (cropY + height - 1) * scanPlane
            + sourceY * rx + sourceX
        let (lastByte, byteOverflow) = lastElement.multipliedReportingOverflow(by: elementSize)
        let (byteEnd, sizeOverflow) = lastByte.addingReportingOverflow(elementSize)
        let (end, endOverflow) = dataOffset.addingReportingOverflow(byteEnd)
        guard !byteOverflow, !sizeOverflow, !endOverflow, end <= data.count else {
            throw DM4Error.truncated
        }

        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            func gather(_ value: (Int) -> Float) {
                for outY in 0..<height {
                    let sourceQY = cropY + outY
                    for outX in 0..<width {
                        let sourceQX = cropX + outX
                        let element = sourceQX * detectorPlane
                            + sourceQY * scanPlane + sourceY * rx + sourceX
                        out[outY * width + outX] = value(dataOffset + element * elementSize)
                    }
                }
            }
            switch imageDataType {
            case 1:  gather { Float(base.loadUnaligned(fromByteOffset: $0, as: Int16.self)) }
            case 10: gather { Float(base.loadUnaligned(fromByteOffset: $0, as: UInt16.self)) }
            case 7:  gather { Float(base.loadUnaligned(fromByteOffset: $0, as: Int32.self)) }
            case 11: gather { Float(base.loadUnaligned(fromByteOffset: $0, as: UInt32.self)) }
            case 6:  gather { Float(base.loadUnaligned(fromByteOffset: $0, as: UInt8.self)) }
            case 9:  gather { Float(base.loadUnaligned(fromByteOffset: $0, as: Int8.self)) }
            case 2:  gather { base.loadUnaligned(fromByteOffset: $0, as: Float.self) }
            case 12: gather { Float(base.loadUnaligned(fromByteOffset: $0, as: Double.self)) }
            default: break
            }
        }
        return view.binned(out, patternCount: 1)
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

    private func scanRow(_ view: LoadView, viewY: Int) throws -> [Float] {
        let sourceY = view.sourceScanY(viewY)
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
            if dims.count >= 4 {
                layout = try storageLayout(
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

            extractCalibration(
                objectPrefix: objectPrefix,
                layout: layout,
                dimensionIndices: dimensionEntries.map(\.index)
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
    /// detector-fastest interpretation for compatibility; contradictory known
    /// domains are refused instead of silently swapping scientific axes.
    private func storageLayout(
        objectPrefix prefix: String, dimensionIndices: [Int]
    ) throws -> StorageLayout {
        guard dimensionIndices.count >= 4 else { return .detectorFastest }
        let indices = Array(dimensionIndices.prefix(4))
        let units = indices.map {
            strings[prefix + "Calibrations.Dimension.\($0).Units"]
        }
        func pairDomain(_ range: Range<Int>) throws -> AxisDomain? {
            let domains = range.map { axisDomain(units[$0]) }
            guard domains.allSatisfy({ $0 != nil }) else { return nil }
            let known = Set(domains.compactMap { $0 })
            guard known.count <= 1 else {
                throw DM4Error.ambiguousAxisCalibration(units.map { $0 ?? "unknown" })
            }
            return known.first
        }
        let leading = try pairDomain(0..<2)
        let trailing = try pairDomain(2..<4)
        guard let leading, let trailing else { return .detectorFastest }
        guard leading != trailing else {
            throw DM4Error.ambiguousAxisCalibration(units.map { $0 ?? "unknown" })
        }

        // DEVIATION from py4DSTEM: read_dm.py blindly wraps ncempy's reversed
        // shape as [Rx,Ry,Qx,Qy]. Gatan STEM-SI files can instead store
        // fastest-first [Rx,Ry,Qy,Qx]; the calibration domains are the file's
        // explicit evidence for which pair is scan versus diffraction.
        return leading == .real ? .scanFastest : .detectorFastest
    }

    private func scanShape(_ needle: String) -> Int? {
        for (key, value) in numbers where key.contains(needle) { return Int(value) }
        return nil
    }

    private func extractCalibration(
        objectPrefix prefix: String,
        layout: StorageLayout,
        dimensionIndices: [Int]
    ) {
        func scale(_ i: Int) -> Double? { numbers[prefix + "Calibrations.Dimension.\(i).Scale"] }
        func units(_ i: Int) -> String? {
            let u = strings[prefix + "Calibrations.Dimension.\(i).Units"]
            return (u?.isEmpty ?? true) ? nil : u
        }
        guard dimensionIndices.count >= 3 else { return }
        let leading = dimensionIndices[0]
        let trailing = dimensionIndices[2]
        let qIndex = layout == .detectorFastest ? leading : trailing
        let rIndex = layout == .detectorFastest ? trailing : leading
        qPixelSize = scale(qIndex)
        qPixelUnits = units(qIndex)
        rPixelSize = scale(rIndex)
        rPixelUnits = units(rIndex)
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
