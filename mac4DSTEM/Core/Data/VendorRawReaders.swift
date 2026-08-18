import Foundation

enum VendorRawError: LocalizedError {
    case cannotOpen(String)
    case malformed(String)
    case unsupported(String)
    case truncated(String)

    var errorDescription: String? {
        switch self {
        case .cannotOpen(let path): return "Could not open vendor data file at \(path)."
        case .malformed(let detail): return "Malformed vendor data: \(detail)"
        case .unsupported(let detail): return "Unsupported vendor data layout: \(detail)"
        case .truncated(let detail): return "Vendor data is truncated: \(detail)"
        }
    }
}

/// EMPAD v1 reader contract: little-endian float32 frames of 130×128 values,
/// with the final two detector rows treated as a per-frame footer. Non-square
/// scans require the vendor XML companion; square raw-only scans follow the
/// conservative py4DSTEM fallback.
actor EMPADReader: FourDDataSource {
    private static let rawHeight = 130
    private static let width = 128
    private static let imageHeight = 128
    private static let frameBytes = rawHeight * width * MemoryLayout<Float>.size

    private let rawPath: String
    private let scanHeight: Int
    private let scanWidth: Int

    init(path: String) throws {
        let url = URL(fileURLWithPath: path)
        let sourceXML: URL?
        if url.pathExtension.lowercased() == "xml" {
            sourceXML = url
        } else {
            let companion = url.deletingPathExtension().appendingPathExtension("xml")
            sourceXML = FileManager.default.fileExists(atPath: companion.path) ? companion : nil
        }

        if let xml = sourceXML {
            let metadata = try Self.parseXML(xml)
            let candidate = xml.deletingLastPathComponent().appendingPathComponent(metadata.rawFile)
            rawPath = candidate.path
            scanHeight = metadata.scanY
            scanWidth = metadata.scanX
        } else {
            guard url.pathExtension.lowercased() == "raw" else {
                throw VendorRawError.unsupported("EMPAD input must be a .xml or .raw file.")
            }
            rawPath = path
            let bytes = try Self.fileSize(path)
            guard bytes % Self.frameBytes == 0 else {
                throw VendorRawError.malformed("EMPAD byte count is not a multiple of a 130×128 float32 frame.")
            }
            let frameCount = bytes / Self.frameBytes
            let side = Int(Double(frameCount).squareRoot().rounded())
            guard side > 0, side * side == frameCount else {
                throw VendorRawError.unsupported("raw-only EMPAD scan has \(frameCount) frames; add its XML companion to define a non-square scan.")
            }
            scanHeight = side
            scanWidth = side
        }

        let expected = try Self.checkedProduct([scanHeight, scanWidth, Self.frameBytes])
        let actual = try Self.fileSize(rawPath)
        guard expected == actual else {
            throw VendorRawError.malformed("EMPAD XML describes \(scanWidth)×\(scanHeight) frames (\(expected) bytes), but the raw file has \(actual) bytes.")
        }
    }

    func discoverPrimaryDataset() throws -> DatasetDescriptor {
        DatasetDescriptor(filePath: rawPath, datasetPath: "/EMPAD/raw",
                          shape: [scanHeight, scanWidth, Self.imageHeight, Self.width],
                          dtypeDescription: "float32 little-endian (EMPAD)", chunkShape: nil)
    }

    /// Frames are contiguous, so a scan crop is a seek and skips bytes; a
    /// detector crop within a frame is not, so it is sliced after the frame is
    /// read. One `read` per frame either way — many small strided reads would
    /// cost more than the bytes they saved.
    nonisolated func loadPushdown(for view: LoadView) -> LoadPushdown { .scanOnly }

    func readPattern(_ view: LoadView, ry: Int, rx: Int) throws -> [Float] {
        try view.requireSource(shape: [scanHeight, scanWidth, Self.imageHeight, Self.width])
        guard ry >= 0, ry < view.descriptor.ry, rx >= 0, rx < view.descriptor.rx else {
            throw VendorRawError.malformed("EMPAD scan index is out of bounds.")
        }
        let frame = view.sourceScanY(ry) * scanWidth + view.sourceScanX(rx)
        let data = try Self.read(path: rawPath, offset: frame * Self.frameBytes,
                                 count: Self.imageHeight * Self.width * 4)
        // Decode only the rows the view keeps: the bytes were read either way,
        // but the cropped-out pixels are never converted or allocated. The crop
        // used is the READ crop — trimmed to a whole number of bins — so the
        // edge remainder is never decoded either.
        let crop = view.readDetectorCrop
        let rows = crop.map { $0.yOffset..<($0.yOffset + $0.height) } ?? 0..<Self.imageHeight
        let columns = crop.map { $0.xOffset..<($0.xOffset + $0.width) } ?? 0..<Self.width
        let cropped = data.withUnsafeBytes { bytes in
            var out = [Float]()
            out.reserveCapacity(rows.count * columns.count)
            for row in rows {
                for column in columns {
                    let index = row * Self.width + column
                    let bits = bytes.loadUnaligned(fromByteOffset: index * 4, as: UInt32.self).littleEndian
                    out.append(Float(bitPattern: bits))
                }
            }
            return out
        }
        return view.binned(cropped, patternCount: 1)
    }

    func readScanRow(_ view: LoadView, ry: Int) throws -> [Float] {
        // Validated here rather than only inside the loop: an empty view would
        // otherwise return [] for a foreign source without entering the body,
        // which is a silent answer to a question that should be refused.
        try view.requireSource(shape: [scanHeight, scanWidth, Self.imageHeight, Self.width])
        guard ry >= 0, ry < view.descriptor.ry else {
            throw VendorRawError.malformed("EMPAD scan row is out of bounds.")
        }
        var result: [Float] = []
        result.reserveCapacity(view.descriptor.rx * view.descriptor.qy * view.descriptor.qx)
        for rx in 0..<view.descriptor.rx {
            result.append(contentsOf: try readPattern(view, ry: ry, rx: rx))
        }
        return result
    }

    func readScanTile(_ view: LoadView, yRange: Range<Int>) throws -> FourDScanTile {
        try view.requireSource(shape: [scanHeight, scanWidth, Self.imageHeight, Self.width])
        guard yRange.lowerBound >= 0, yRange.upperBound <= view.descriptor.ry else {
            throw VendorRawError.malformed("EMPAD tile is out of bounds.")
        }
        var pixels: [Float] = []
        pixels.reserveCapacity(
            yRange.count * view.descriptor.rx * view.descriptor.qy * view.descriptor.qx
        )
        for y in yRange { pixels.append(contentsOf: try readScanRow(view, ry: y)) }
        return FourDScanTile(yRange: yRange, scanWidth: view.descriptor.rx,
                             detectorHeight: view.descriptor.qy,
                             detectorWidth: view.descriptor.qx,
                             pixels: pixels)
    }

    func readDoubleAttribute(_ name: String, onObjectPath path: String) -> Double? { nil }
    func pixelCalibration() -> PixelCalibration? { nil }

    private static func parseXML(_ url: URL) throws -> (rawFile: String, scanX: Int, scanY: Int) {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw VendorRawError.malformed("EMPAD XML is not UTF-8.")
        }
        func element(_ name: String, in body: String = "") -> String? {
            let source = body.isEmpty ? text : body
            guard let start = source.range(of: "<\(name)"),
                  let openEnd = source[start.lowerBound...].firstIndex(of: ">"),
                  let close = source.range(of: "</\(name)>", range: openEnd..<source.endIndex) else { return nil }
            return String(source[source.index(after: openEnd)..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let rawTagStart = text.range(of: "<raw_file"),
              let rawTagEnd = text[rawTagStart.lowerBound...].firstIndex(of: ">") else {
            throw VendorRawError.malformed("EMPAD XML has no raw_file element.")
        }
        let rawTag = String(text[rawTagStart.lowerBound...rawTagEnd])
        guard let filenameRange = rawTag.range(of: #"filename\s*=\s*[\"'][^\"']+[\"']"#,
                                               options: .regularExpression),
              let quote = rawTag[filenameRange].firstIndex(where: { $0 == "\"" || $0 == "'" }) else {
            throw VendorRawError.malformed("EMPAD raw_file has no filename attribute.")
        }
        let afterQuote = rawTag.index(after: quote)
        guard let endQuote = rawTag[afterQuote...].firstIndex(of: rawTag[quote]) else {
            throw VendorRawError.malformed("EMPAD raw filename is unterminated.")
        }
        let rawFile = URL(fileURLWithPath: String(rawTag[afterQuote..<endQuote])).lastPathComponent

        let acquireBody: String
        if let scanStart = text.range(of: #"<scan_parameters[^>]*mode\s*=\s*[\"']acquire[\"'][^>]*>"#,
                                      options: .regularExpression),
           let scanEnd = text.range(of: "</scan_parameters>", range: scanStart.upperBound..<text.endIndex) {
            acquireBody = String(text[scanStart.upperBound..<scanEnd.lowerBound])
        } else { acquireBody = text }
        guard let xText = element("scan_resolution_x", in: acquireBody), let scanX = Int(xText), scanX > 0,
              let yText = element("scan_resolution_y", in: acquireBody), let scanY = Int(yText), scanY > 0 else {
            throw VendorRawError.malformed("EMPAD XML has no positive acquire scan_resolution_x/y.")
        }
        return (rawFile, scanX, scanY)
    }

    fileprivate static func fileSize(_ path: String) throws -> Int {
        guard let value = try FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber else {
            throw VendorRawError.cannotOpen(path)
        }
        return value.intValue
    }

    fileprivate static func checkedProduct(_ values: [Int]) throws -> Int {
        var result = 1
        for value in values {
            let next = result.multipliedReportingOverflow(by: value)
            guard !next.overflow else { throw VendorRawError.malformed("dimensions overflow addressable storage") }
            result = next.partialValue
        }
        return result
    }

    fileprivate static func read(path: String, offset: Int, count: Int) throws -> Data {
        guard let handle = FileHandle(forReadingAtPath: path) else { throw VendorRawError.cannotOpen(path) }
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        let data = try handle.read(upToCount: count) ?? Data()
        guard data.count == count else { throw VendorRawError.truncated("expected \(count) bytes at offset \(offset)") }
        return data
    }
}

/// Merlin MIB v1 reader contract: regular per-frame MIB (not packed R64),
/// U08/U16/U32 big-endian payloads, 1x1/2x2/2x2G assemblies, and a companion
/// `.hdr` containing ScanX/ScanY. Headers are skipped independently per frame.
actor MIBReader: FourDDataSource {
    private let path: String
    private let scanHeight: Int
    private let scanWidth: Int
    private let detectorHeight: Int
    private let detectorWidth: Int
    private let headerBytes: Int
    private let bytesPerPixel: Int
    private let dtype: String
    private let frameBytes: Int

    init(path: String) throws {
        self.path = path
        let first = try EMPADReader.read(path: path, offset: 0, count: min(4096, try EMPADReader.fileSize(path)))
        guard let zero = first.firstIndex(of: 0) else {
            throw VendorRawError.malformed("MIB first frame header has no NUL terminator.")
        }
        let fields = String(decoding: first[..<zero], as: UTF8.self).split(separator: ",", omittingEmptySubsequences: false)
        guard fields.count > 10, let offset = Int(fields[2]), offset > 0 else {
            throw VendorRawError.malformed("MIB first frame header has no valid data offset.")
        }
        headerBytes = offset
        let layout = fields[7].trimmingCharacters(in: .whitespacesAndNewlines)
        switch layout {
        case "1x1": detectorHeight = 256; detectorWidth = 256
        case "2x2": detectorHeight = 512; detectorWidth = 512
        case "2x2G": detectorHeight = 514; detectorWidth = 514
        default: throw VendorRawError.unsupported("MIB detector assembly \(layout); expected 1x1, 2x2, or 2x2G.")
        }
        dtype = String(fields[6])
        switch dtype {
        case "U08": bytesPerPixel = 1
        case "U16": bytesPerPixel = 2
        case "U32": bytesPerPixel = 4
        case "R64": throw VendorRawError.unsupported("packed/raw R64 MIB is not in the v1 direct-reader contract; convert it to regular MIB/HDF5 first.")
        default: throw VendorRawError.unsupported("MIB pixel encoding \(dtype); expected U08, U16, or U32.")
        }
        frameBytes = try EMPADReader.checkedProduct([detectorHeight, detectorWidth, bytesPerPixel]) + headerBytes

        let hdrURL = URL(fileURLWithPath: path).deletingPathExtension().appendingPathExtension("hdr")
        guard let hdr = try? String(contentsOf: hdrURL, encoding: .utf8) else {
            throw VendorRawError.unsupported("MIB needs a companion .hdr with ScanX and ScanY so scan shape is never guessed.")
        }
        var values: [String: Int] = [:]
        for line in hdr.split(whereSeparator: \Character.isNewline) {
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            if parts.count == 2, let value = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
                values[parts[0].trimmingCharacters(in: CharacterSet(charactersIn: ": "))] = value
            }
        }
        guard let sx = values["ScanX"], sx > 0, let sy = values["ScanY"], sy > 0 else {
            throw VendorRawError.malformed("MIB companion .hdr has no positive ScanX/ScanY.")
        }
        scanWidth = sx; scanHeight = sy
        let expected = try EMPADReader.checkedProduct([sx, sy, frameBytes])
        let actual = try EMPADReader.fileSize(path)
        guard actual == expected else {
            throw VendorRawError.malformed("MIB .hdr describes \(sx)×\(sy) frames (\(expected) bytes), but the file has \(actual) bytes.")
        }
    }

    func discoverPrimaryDataset() throws -> DatasetDescriptor {
        DatasetDescriptor(filePath: path, datasetPath: "/Merlin/MIB",
                          shape: [scanHeight, scanWidth, detectorHeight, detectorWidth],
                          dtypeDescription: "\(dtype) big-endian (MIB)", chunkShape: nil)
    }

    /// Same as EMPAD: per-frame headers make frames contiguous units, so a scan
    /// crop seeks past whole frames while a detector crop is sliced out of a
    /// frame that had to be read anyway.
    nonisolated func loadPushdown(for view: LoadView) -> LoadPushdown { .scanOnly }

    func readPattern(_ view: LoadView, ry: Int, rx: Int) throws -> [Float] {
        try view.requireSource(shape: [scanHeight, scanWidth, detectorHeight, detectorWidth])
        guard ry >= 0, ry < view.descriptor.ry, rx >= 0, rx < view.descriptor.rx else {
            throw VendorRawError.malformed("MIB scan index is out of bounds.")
        }
        let frame = view.sourceScanY(ry) * scanWidth + view.sourceScanX(rx)
        let count = detectorHeight * detectorWidth
        let data = try EMPADReader.read(path: path, offset: frame * frameBytes + headerBytes,
                                        count: count * bytesPerPixel)
        let crop = view.readDetectorCrop
        let rows = crop.map { $0.yOffset..<($0.yOffset + $0.height) } ?? 0..<detectorHeight
        let columns = crop.map { $0.xOffset..<($0.xOffset + $0.width) } ?? 0..<detectorWidth
        let cropped = data.withUnsafeBytes { bytes in
            var out = [Float]()
            out.reserveCapacity(rows.count * columns.count)
            for row in rows {
                for column in columns {
                    let index = row * detectorWidth + column
                    switch bytesPerPixel {
                    case 1: out.append(Float(bytes.loadUnaligned(fromByteOffset: index, as: UInt8.self)))
                    case 2: out.append(Float(bytes.loadUnaligned(fromByteOffset: index * 2, as: UInt16.self).bigEndian))
                    default: out.append(Float(bytes.loadUnaligned(fromByteOffset: index * 4, as: UInt32.self).bigEndian))
                    }
                }
            }
            return out
        }
        return view.binned(cropped, patternCount: 1)
    }

    func readScanRow(_ view: LoadView, ry: Int) throws -> [Float] {
        // See EMPADReader.readScanRow: validated here, not only inside the loop.
        try view.requireSource(shape: [scanHeight, scanWidth, detectorHeight, detectorWidth])
        guard ry >= 0, ry < view.descriptor.ry else {
            throw VendorRawError.malformed("MIB scan row is out of bounds.")
        }
        var result: [Float] = []
        result.reserveCapacity(view.descriptor.rx * view.descriptor.qy * view.descriptor.qx)
        for rx in 0..<view.descriptor.rx {
            result.append(contentsOf: try readPattern(view, ry: ry, rx: rx))
        }
        return result
    }

    func readScanTile(_ view: LoadView, yRange: Range<Int>) throws -> FourDScanTile {
        try view.requireSource(shape: [scanHeight, scanWidth, detectorHeight, detectorWidth])
        guard yRange.lowerBound >= 0, yRange.upperBound <= view.descriptor.ry else {
            throw VendorRawError.malformed("MIB tile is out of bounds.")
        }
        var pixels: [Float] = []
        pixels.reserveCapacity(
            yRange.count * view.descriptor.rx * view.descriptor.qy * view.descriptor.qx
        )
        for y in yRange { pixels.append(contentsOf: try readScanRow(view, ry: y)) }
        return FourDScanTile(yRange: yRange, scanWidth: view.descriptor.rx,
                             detectorHeight: view.descriptor.qy,
                             detectorWidth: view.descriptor.qx,
                             pixels: pixels)
    }

    func readDoubleAttribute(_ name: String, onObjectPath path: String) -> Double? { nil }
    func pixelCalibration() -> PixelCalibration? { nil }
}
