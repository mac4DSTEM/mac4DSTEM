//
//  VendorRawReaders.swift
//  Role: EMPAD and Merlin MIB 4D files as `FourDDataSource`s. The files are FormatoKit's (0.7.0): `FormatoMIB.MIBReader(.appScanXY)` and
//        `FormatoEMPAD.EMPADReader` (RosettaSciIO's XML, `scan_resolution_x/y`, raw-only) read the pixels; this file keeps the app's side:
//        the descriptor, the LoadView crops and binning, the refusals the app words (a MIB without its .hdr, a non-square raw-only EMPAD),
//        the app's precedence of `scan_resolution_x/y` over `pix_x/pix_y`, the header-less MIB the kit does not take, and
//        `MappingLiveness` before every read of a mapped file.
//

import Foundation
import FormatoCore
import FormatoEMPAD
import FormatoMIB

package enum VendorRawError: LocalizedError {
    case cannotOpen(String)
    case malformed(String)
    case unsupported(String)
    case truncated(String)
    /// The disk a mapped file came from is gone (file name only, never the folders above it).
    case volumeGone(String)

    package var errorDescription: String? {
        switch self {
        case .cannotOpen(let path): return "Could not open \(displayFileName(path))."
        case .malformed(let detail): return "Malformed vendor data: \(detail)"
        case .unsupported(let detail): return "Unsupported vendor data layout: \(detail)"
        case .truncated(let detail): return "Vendor data is truncated: \(detail)"
        case .volumeGone(let name):
            return "\(name) is no longer reachable: its disk was disconnected. Reconnect it and reopen."
        }
    }

    /// A kit refusal as the app's error, so `SessionGates.isDataSourceFailure` still sees it.
    fileprivate nonisolated static func from(_ error: Error, path: String) -> VendorRawError {
        switch error {
        case let error as VendorRawError: return error
        case let MIBError.cannotOpen(detail): return .cannotOpen(detail.isEmpty ? path : detail)
        case let MIBError.malformed(detail): return .malformed(detail)
        case let MIBError.unsupported(detail): return .unsupported(detail)
        case let EMPADError.cannotOpen(detail): return .cannotOpen(detail)
        case let cocoa as NSError where cocoa.domain == NSCocoaErrorDomain
            && [NSFileNoSuchFileError, NSFileReadNoSuchFileError, NSFileReadNoPermissionError].contains(cocoa.code): return .cannotOpen(path)
        case let EMPADError.invalidXML(detail): return .malformed(detail)
        case let EMPADError.rawSizeMismatch(expected, actual):
            return .malformed("EMPAD raw file has \(actual) bytes where its header needs \(expected).")
        default: return .truncated(error.localizedDescription)
        }
    }
}

/// One slab of a kit array as Float, `[viewRows][viewColumns][h][w]` over the view's read crop. The array is `[Ry, Rx, Qy, Qx]`
/// with the axes in `present` (scan y, scan x) in it; a refusal of the kit is the app's `VendorRawError`.
private nonisolated func vendorSlab(
    _ array: any FormatoLazyArray, view: LoadView, viewRows: Range<Int>, viewColumns: Range<Int>,
    detector: (height: Int, width: Int), hasScanY: Bool = true, hasScanX: Bool = true, path: String
) throws -> [Float] {
    let cropY = view.readDetectorCrop?.yOffset ?? 0
    let cropX = view.readDetectorCrop?.xOffset ?? 0
    let height = view.readDetectorCrop?.height ?? detector.height
    let width = view.readDetectorCrop?.width ?? detector.width
    var start = [Int](), count = [Int]()
    if hasScanY { start.append(view.sourceScanY(viewRows.lowerBound)); count.append(viewRows.count) }
    else if view.sourceScanY(viewRows.lowerBound) != 0 || viewRows.count != 1 { throw VendorRawError.malformed("scan row is out of bounds.") }
    if hasScanX { start.append(view.sourceScanX(viewColumns.lowerBound)); count.append(viewColumns.count) }
    else if view.sourceScanX(viewColumns.lowerBound) != 0 || viewColumns.count != 1 { throw VendorRawError.malformed("scan column is out of bounds.") }
    start += [cropY, cropX]; count += [height, width]
    do {
        guard let values = try array.read(start: start, count: count).float32Values() else {
            throw VendorRawError.malformed("pixels are not numeric.")
        }
        return values
    } catch {
        throw VendorRawError.from(error, path: path)
    }
}

/// The mapped file's disk watch: opened BEFORE the kit maps the file, so it can only belong to the disk the mapping comes from.
private nonisolated func vendorLiveness(path: String) throws -> MappingLiveness {
    do { return try MappingLiveness.descriptor(path: path) } catch { throw VendorRawError.cannotOpen(path) }
}

/// EMPAD v1 reader contract: little-endian float32 frames of 130×128 values, with the final two detector rows treated as a per-frame
/// footer. The frames are `FormatoEMPAD.EMPADReader`'s lazy array over the mapped raw file; this actor keeps the app's side: which XML
/// fields give the scan, the refusals it words, and `MappingLiveness` before every read.
///
/// The scan: the app's precedence is the XML's `scan_resolution_x/y` (the `scan_parameters mode="acquire"` block, else the whole file),
/// with the raw file beside the XML under its last path component, and the kit reads the frames at that size (`init(rawPath:scanSize:)`).
/// Where the XML carries no such pair the kit reads the XML itself (`pix_x`/`pix_y`, a `scan_xN_yN` name). A raw file with no XML is a
/// square scan whose side is the frame count's root (the kit infers it), as py4DSTEM's fallback.
package actor EMPADReader: FourDDataSource {
    private static let rawHeight = 130
    private static let width = 128
    private static let imageHeight = 128
    private static let frameBytes = rawHeight * width * MemoryLayout<Float>.size

    private let rawPath: String
    private let scanHeight: Int
    private let scanWidth: Int
    /// FormatoEMPAD's lazy array (scan axes of size 1 are squeezed out of it), and which of the two scan axes it has.
    private let array: any FormatoLazyArray
    private let hasScanY: Bool
    private let hasScanX: Bool
    /// The disk watch of the mapping, opened BEFORE the kit maps the file.
    private let liveness: MappingLiveness
    /// THE LATCH (as `DM4Reader`): set by the first read that finds the disk gone, never cleared.
    private var diskGone = false

    package init(path: String) throws {
        let url = URL(fileURLWithPath: path)
        let sourceXML: URL?
        if url.pathExtension.lowercased() == "xml" {
            sourceXML = url
        } else {
            let companion = url.deletingPathExtension().appendingPathExtension("xml")
            sourceXML = FileManager.default.fileExists(atPath: companion.path) ? companion : nil
        }

        let kit: FormatoEMPAD.EMPADReader
        let watch: MappingLiveness
        do {
            if let xml = sourceXML {
                // The raw file is named by the XML: the app maps its last component beside the XML (where scan_resolution gives the
                // scan); the kit resolves the whole `filename` against the XML's folder (where it reads the XML itself).
                let rawFile = try Self.rawFileAttribute(xml)
                let directory = xml.deletingLastPathComponent()
                if let scan = try? Self.scanResolution(xml) {
                    let raw = directory.appendingPathComponent(URL(fileURLWithPath: rawFile).lastPathComponent).standardizedFileURL.path
                    watch = try vendorLiveness(path: raw)
                    kit = try FormatoEMPAD.EMPADReader(rawPath: raw, scanSize: (y: scan.y, x: scan.x))
                } else {
                    watch = try vendorLiveness(path: URL(fileURLWithPath: rawFile, relativeTo: directory).standardizedFileURL.path)
                    kit = try FormatoEMPAD.EMPADReader(path: xml.path)
                    // An image series is not a scan.
                    if kit.signal.axes.contains(where: { $0.name == "series_count" }) {
                        throw VendorRawError.malformed("EMPAD XML describes an image series, not a scan (no positive acquire scan_resolution_x/y).")
                    }
                }
            } else {
                guard url.pathExtension.lowercased() == "raw" else {
                    throw VendorRawError.unsupported("EMPAD input must be a .xml or .raw file.")
                }
                let bytes = try Self.fileSize(path)
                guard bytes % Self.frameBytes == 0 else {
                    throw VendorRawError.malformed("EMPAD byte count is not a multiple of a 130×128 float32 frame.")
                }
                watch = try vendorLiveness(path: path)
                do {
                    kit = try FormatoEMPAD.EMPADReader(rawPath: path)
                } catch EMPADError.invalidXML("Missing scan dimensions") {
                    throw VendorRawError.unsupported("raw-only EMPAD scan has \(bytes / Self.frameBytes) frames; add its XML companion to define a non-square scan.")
                }
            }
        } catch {
            throw VendorRawError.from(error, path: path)
        }
        let axes = kit.signal.axes
        let y = axes.first(where: { $0.name == "scan_y" }), x = axes.first(where: { $0.name == "scan_x" })
        rawPath = kit.rawPath
        scanHeight = y?.size ?? 1
        scanWidth = x?.size ?? 1
        array = kit.signal.array
        hasScanY = y != nil
        hasScanX = x != nil
        liveness = watch
    }

    package func discoverPrimaryDataset() throws -> DatasetDescriptor {
        DatasetDescriptor(filePath: rawPath, datasetPath: "/EMPAD/raw",
                          shape: [scanHeight, scanWidth, Self.imageHeight, Self.width],
                          dtypeDescription: "float32 little-endian (EMPAD)", chunkShape: nil)
    }

    /// Frames are contiguous, so a scan crop is a seek and skips bytes; a
    /// detector crop within a frame is not, so it is sliced after the frame is
    /// read. One `read` per frame either way — many small strided reads would
    /// cost more than the bytes they saved.
    package nonisolated func loadPushdown(for view: LoadView) -> LoadPushdown { .scanOnly }

    /// One check per public read; latches on the first failure.
    private func requireDiskAlive() throws {
        if !diskGone, !liveness.isAlive() { diskGone = true }
        if diskGone { throw VendorRawError.volumeGone(displayFileName(rawPath)) }
    }

    /// `viewRows` x `viewColumns` positions of the view, each over `readDetectorCrop` (or the whole image), BEFORE binning.
    private func block(_ view: LoadView, viewRows: Range<Int>, viewColumns: Range<Int>) throws -> [Float] {
        try requireDiskAlive()
        return try vendorSlab(array, view: view, viewRows: viewRows, viewColumns: viewColumns,
                              detector: (Self.imageHeight, Self.width), hasScanY: hasScanY, hasScanX: hasScanX, path: rawPath)
    }

    package func readPattern(_ view: LoadView, ry: Int, rx: Int) throws -> [Float] {
        try view.requireSource(shape: [scanHeight, scanWidth, Self.imageHeight, Self.width])
        guard ry >= 0, ry < view.descriptor.ry, rx >= 0, rx < view.descriptor.rx else {
            throw VendorRawError.malformed("EMPAD scan index is out of bounds.")
        }
        return view.binned(try block(view, viewRows: ry..<(ry + 1), viewColumns: rx..<(rx + 1)), patternCount: 1)
    }

    package func readScanRow(_ view: LoadView, ry: Int) throws -> [Float] {
        // Validated here rather than only inside the loop: an empty view would
        // otherwise return [] for a foreign source without entering the body,
        // which is a silent answer to a question that should be refused.
        try view.requireSource(shape: [scanHeight, scanWidth, Self.imageHeight, Self.width])
        guard ry >= 0, ry < view.descriptor.ry else {
            throw VendorRawError.malformed("EMPAD scan row is out of bounds.")
        }
        return view.binned(try block(view, viewRows: ry..<(ry + 1), viewColumns: 0..<view.descriptor.rx),
                           patternCount: view.descriptor.rx)
    }

    package func readScanTile(_ view: LoadView, yRange: Range<Int>) throws -> FourDScanTile {
        try view.requireSource(shape: [scanHeight, scanWidth, Self.imageHeight, Self.width])
        guard yRange.lowerBound >= 0, yRange.upperBound <= view.descriptor.ry else {
            throw VendorRawError.malformed("EMPAD tile is out of bounds.")
        }
        let pixels = yRange.isEmpty ? [] : view.binned(
            try block(view, viewRows: yRange, viewColumns: 0..<view.descriptor.rx),
            patternCount: yRange.count * view.descriptor.rx)
        return FourDScanTile(yRange: yRange, scanWidth: view.descriptor.rx,
                             detectorHeight: view.descriptor.qy,
                             detectorWidth: view.descriptor.qx,
                             pixels: pixels)
    }

    package func readDoubleAttribute(_ name: String, onObjectPath path: String) -> Double? { nil }
    package func pixelCalibration() -> PixelCalibration? { nil }

    /// The `filename` attribute of the XML's `raw_file` element, as written.
    private static func rawFileAttribute(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw VendorRawError.malformed("EMPAD XML is not UTF-8.")
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
        return String(rawTag[afterQuote..<endQuote])
    }

    /// The XML's scan, the app's precedence: `scan_resolution_x/y` of the `scan_parameters mode="acquire"` block, else of the whole file.
    private static func scanResolution(_ url: URL) throws -> (x: Int, y: Int) {
        let text = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        func element(_ name: String, in body: String = "") -> String? {
            let source = body.isEmpty ? text : body
            guard let start = source.range(of: "<\(name)"),
                  let openEnd = source[start.lowerBound...].firstIndex(of: ">"),
                  let close = source.range(of: "</\(name)>", range: openEnd..<source.endIndex) else { return nil }
            return String(source[source.index(after: openEnd)..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
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
        return (scanX, scanY)
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
        // try? OK (v2 S7 audit): best-effort close of a read-only handle on
        // the way out; the read's own errors already threw above.
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
/// The frames are `FormatoMIB.MIBReader(path:convention: .appScanXY)`'s: the ScanX/ScanY companion, the full detector assembly, the
/// unflipped values as Float32 (any header size from 384 to 65536; `pixelCode` is the stored code). A file the kit refuses but this app's
/// reader always took (a header with no width and height, a detector that disagrees with its assembly) is read here, frame by frame, as before.
package actor MIBReader: FourDDataSource {
    /// Where the frames are read from.
    private enum Source: Sendable {
        case kit(array: any FormatoLazyArray, liveness: MappingLiveness)
        /// delete at mac4DSTEM/FormatoKit#7: headers without width and height, and a detector that disagrees with its assembly (the kit does not take header-less MIB)
        case frames(headerBytes: Int, bytesPerPixel: Int, frameBytes: Int)
    }

    private let path: String
    private let scanHeight: Int
    private let scanWidth: Int
    private let detectorHeight: Int
    private let detectorWidth: Int
    private let dtype: String
    private let source: Source
    /// THE LATCH (as `DM4Reader`): set by the first read that finds the disk gone, never cleared.
    private var diskGone = false
    /// Why FormatoMIB did not take the file, when the app's own frame reads did; the opener logs it.
    package private(set) var kitRefusal: String?

    package init(path: String) throws {
        self.path = path
        // try? accepted with a stated limit (v2 S7 audit): this collapses
        // "no .hdr" with "an .hdr the sandbox refused" — the .hdr is a
        // SIBLING of the user-picked file, the same access shape as the S1
        // session sidecar, so an EPERM here reads as "missing". The guard
        // still throws a named refusal rather than guessing a scan shape;
        // distinguishing the two belongs to the deferred MIB-out-of-Preview
        // work (docs/v2-release.md §3), which owns this reader's contract.
        let hdrURL = URL(fileURLWithPath: path).deletingPathExtension().appendingPathExtension("hdr")
        guard let hdr = try? String(contentsOf: hdrURL, encoding: .utf8) else {
            throw VendorRawError.unsupported("MIB needs a companion .hdr with ScanX and ScanY so scan shape is never guessed.")
        }
        // The kit first; the descriptor is opened BEFORE the kit maps the file.
        let watch = try? vendorLiveness(path: path)
        var refusal = "its disk could not be watched"
        if let watch {
            do {
                let kit = try FormatoMIB.MIBReader(path: path, convention: .appScanXY)
                let shape = kit.signal.array.shape
                if shape.count == 4 {
                    (scanHeight, scanWidth, detectorHeight, detectorWidth) = (shape[0], shape[1], shape[2], shape[3])
                    dtype = kit.pixelCode
                    source = .kit(array: kit.signal.array, liveness: watch)
                    return
                }
                refusal = "the frames are not scan-shaped"
            } catch {
                refusal = "\(error)"
            }
        }
        kitRefusal = refusal

        // The app's own reading. The stored pixel code is the first frame header's.
        let head = try EMPADReader.read(path: path, offset: 0, count: min(4096, try EMPADReader.fileSize(path)))
        let fields = head.firstIndex(of: 0).map {
            String(decoding: head[..<$0], as: UTF8.self).split(separator: ",", omittingEmptySubsequences: false)
        }
        dtype = fields.flatMap { $0.count > 6 ? String($0[6]) : nil } ?? "U16"
        guard let fields, fields.count > 10, let offset = Int(fields[2]), offset > 0 else {
            throw VendorRawError.malformed("MIB first frame header has no valid data offset.")
        }
        let layout = fields[7].trimmingCharacters(in: .whitespacesAndNewlines)
        switch layout {
        case "1x1": detectorHeight = 256; detectorWidth = 256
        case "2x2": detectorHeight = 512; detectorWidth = 512
        case "2x2G": detectorHeight = 514; detectorWidth = 514
        default: throw VendorRawError.unsupported("MIB detector assembly \(layout); expected 1x1, 2x2, or 2x2G.")
        }
        let bytesPerPixel: Int
        switch dtype {
        case "U08": bytesPerPixel = 1
        case "U16": bytesPerPixel = 2
        case "U32": bytesPerPixel = 4
        case "R64": throw VendorRawError.unsupported("packed/raw R64 MIB is not in the v1 direct-reader contract; convert it to regular MIB/HDF5 first.")
        default: throw VendorRawError.unsupported("MIB pixel encoding \(dtype); expected U08, U16, or U32.")
        }
        let frameBytes = try EMPADReader.checkedProduct([detectorHeight, detectorWidth, bytesPerPixel]) + offset
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
        source = .frames(headerBytes: offset, bytesPerPixel: bytesPerPixel, frameBytes: frameBytes)
    }

    package func discoverPrimaryDataset() throws -> DatasetDescriptor {
        DatasetDescriptor(filePath: path, datasetPath: "/Merlin/MIB",
                          shape: [scanHeight, scanWidth, detectorHeight, detectorWidth],
                          dtypeDescription: "\(dtype) big-endian (MIB)", chunkShape: nil)
    }

    /// Same as EMPAD: per-frame headers make frames contiguous units, so a scan
    /// crop seeks past whole frames while a detector crop is sliced out of a
    /// frame that had to be read anyway.
    package nonisolated func loadPushdown(for view: LoadView) -> LoadPushdown { .scanOnly }

    /// One check per public read of a mapped file; latches on the first failure.
    private func requireDiskAlive() throws {
        guard case .kit(_, let liveness) = source else { return }
        if !diskGone, !liveness.isAlive() { diskGone = true }
        if diskGone { throw VendorRawError.volumeGone(displayFileName(path)) }
    }

    /// `viewRows` x `viewColumns` positions of the view over the read crop, BEFORE binning.
    private func block(_ view: LoadView, viewRows: Range<Int>, viewColumns: Range<Int>) throws -> [Float] {
        try requireDiskAlive()
        switch source {
        case .kit(let array, _):
            return try vendorSlab(array, view: view, viewRows: viewRows, viewColumns: viewColumns,
                                  detector: (detectorHeight, detectorWidth), path: path)
        case .frames(let headerBytes, let bytesPerPixel, let frameBytes):
            var out = [Float]()
            for viewY in viewRows {
                for viewX in viewColumns {
                    let frame = view.sourceScanY(viewY) * scanWidth + view.sourceScanX(viewX)
                    let count = detectorHeight * detectorWidth
                    let data = try EMPADReader.read(path: path, offset: frame * frameBytes + headerBytes,
                                                    count: count * bytesPerPixel)
                    let crop = view.readDetectorCrop
                    let rows = crop.map { $0.yOffset..<($0.yOffset + $0.height) } ?? 0..<detectorHeight
                    let columns = crop.map { $0.xOffset..<($0.xOffset + $0.width) } ?? 0..<detectorWidth
                    data.withUnsafeBytes { bytes in
                        out.reserveCapacity(out.count + rows.count * columns.count)
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
                    }
                }
            }
            return out
        }
    }

    package func readPattern(_ view: LoadView, ry: Int, rx: Int) throws -> [Float] {
        try view.requireSource(shape: [scanHeight, scanWidth, detectorHeight, detectorWidth])
        guard ry >= 0, ry < view.descriptor.ry, rx >= 0, rx < view.descriptor.rx else {
            throw VendorRawError.malformed("MIB scan index is out of bounds.")
        }
        return view.binned(try block(view, viewRows: ry..<(ry + 1), viewColumns: rx..<(rx + 1)), patternCount: 1)
    }

    package func readScanRow(_ view: LoadView, ry: Int) throws -> [Float] {
        // See EMPADReader.readScanRow: validated here, not only inside the loop.
        try view.requireSource(shape: [scanHeight, scanWidth, detectorHeight, detectorWidth])
        guard ry >= 0, ry < view.descriptor.ry else {
            throw VendorRawError.malformed("MIB scan row is out of bounds.")
        }
        return view.binned(try block(view, viewRows: ry..<(ry + 1), viewColumns: 0..<view.descriptor.rx),
                           patternCount: view.descriptor.rx)
    }

    package func readScanTile(_ view: LoadView, yRange: Range<Int>) throws -> FourDScanTile {
        try view.requireSource(shape: [scanHeight, scanWidth, detectorHeight, detectorWidth])
        guard yRange.lowerBound >= 0, yRange.upperBound <= view.descriptor.ry else {
            throw VendorRawError.malformed("MIB tile is out of bounds.")
        }
        let pixels = yRange.isEmpty ? [] : view.binned(
            try block(view, viewRows: yRange, viewColumns: 0..<view.descriptor.rx),
            patternCount: yRange.count * view.descriptor.rx)
        return FourDScanTile(yRange: yRange, scanWidth: view.descriptor.rx,
                             detectorHeight: view.descriptor.qy,
                             detectorWidth: view.descriptor.qx,
                             pixels: pixels)
    }

    package func readDoubleAttribute(_ name: String, onObjectPath path: String) -> Double? { nil }
    package func pixelCalibration() -> PixelCalibration? { nil }
}
