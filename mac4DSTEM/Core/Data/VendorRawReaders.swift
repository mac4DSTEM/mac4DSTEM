//
//  VendorRawReaders.swift
//  Role: EMPAD and Merlin MIB 4D files as `FourDDataSource`s. The files are FormatoKit's: `FormatoMIB.MIBReader(.appScanXY)` and
//        `FormatoEMPAD.EMPADReader` (RosettaSciIO's XML) read the pixels; this file keeps the app's side: the descriptor, the
//        LoadView crops and binning, the refusals the app words (a MIB without its .hdr, a non-square raw-only EMPAD), the EMPAD
//        files the kit does not recognise (scan_resolution_x/y XML, raw-only square scans), and `MappingLiveness` before every
//        read of a mapped file.
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

/// EMPAD v1 reader contract: little-endian float32 frames of 130×128 values,
/// with the final two detector rows treated as a per-frame footer. Non-square
/// scans require the vendor XML companion; square raw-only scans follow the
/// conservative py4DSTEM fallback.
///
/// An XML the app's own reading cannot take and FormatoEMPAD can (`pix_x`/`pix_y`, a `scan_xN_yN.raw` name) is read by the kit. An XML with
/// `scan_parameters mode="acquire"` and `scan_resolution_x/y` (the app's precedence, under any file name), a raw file with no XML, and
/// anything the kit refuses, are read here, frame by frame, as before.
package actor EMPADReader: FourDDataSource {
    private static let rawHeight = 130
    private static let width = 128
    private static let imageHeight = 128
    private static let frameBytes = rawHeight * width * MemoryLayout<Float>.size

    /// Where the frames are read from.
    private enum Source: Sendable {
        /// FormatoEMPAD's lazy array over the mapped raw file (scan axes of size 1 are squeezed out of it), and the disk watch of that mapping.
        case kit(array: any FormatoLazyArray, hasScanY: Bool, hasScanX: Bool, liveness: MappingLiveness)
        /// This file's own frame reads.
        case frames
    }

    private let rawPath: String
    private let scanHeight: Int
    private let scanWidth: Int
    private let source: Source
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

        // The kit, only for an XML the app's own reading cannot take: where the XML carries `scan_resolution_x/y` the app's precedence
        // is the old one (its own parse, no chance of a silent transpose against the kit's `pix_x`/`pix_y`). The raw file must be the
        // very one the app would map (the kit resolves `raw_file`'s whole path; the app its last component). The disk watch is opened
        // BEFORE the kit maps the file. Whatever the kit refuses, the app's own reading below judges and words, as before.
        if let xml = sourceXML, (try? Self.parseXML(xml)) == nil, let rawFile = try? Self.rawFileAttribute(xml) {
            let directory = xml.deletingLastPathComponent()
            let appRaw = directory.appendingPathComponent(URL(fileURLWithPath: rawFile).lastPathComponent).standardizedFileURL.path
            let kitRaw = URL(fileURLWithPath: rawFile, relativeTo: directory).standardizedFileURL.path
            if appRaw == kitRaw, let liveness = try? vendorLiveness(path: appRaw),
               let reader = try? FormatoEMPAD.EMPADReader(path: xml.path),
               !reader.signal.axes.contains(where: { $0.name == "series_count" }) {
                let axes = reader.signal.axes
                let y = axes.first(where: { $0.name == "scan_y" }), x = axes.first(where: { $0.name == "scan_x" })
                rawPath = appRaw
                scanHeight = y?.size ?? 1
                scanWidth = x?.size ?? 1
                source = .kit(array: reader.signal.array, hasScanY: y != nil, hasScanX: x != nil, liveness: liveness)
                return
            }
        }

        // The app's own reading.
        let height: Int, width: Int, raw: String
        if let xml = sourceXML {
            // delete at FormatoEMPAD 0.6: scan_resolution_x/y of scan_parameters mode="acquire" (kit ask)
            let metadata = try Self.parseXML(xml)
            raw = xml.deletingLastPathComponent().appendingPathComponent(metadata.rawFile).path
            height = metadata.scanY
            width = metadata.scanX
        } else {
            guard url.pathExtension.lowercased() == "raw" else {
                throw VendorRawError.unsupported("EMPAD input must be a .xml or .raw file.")
            }
            raw = path
            let bytes = try Self.fileSize(path)
            guard bytes % Self.frameBytes == 0 else {
                throw VendorRawError.malformed("EMPAD byte count is not a multiple of a 130×128 float32 frame.")
            }
            let frameCount = bytes / Self.frameBytes
            let side = Int(Double(frameCount).squareRoot().rounded())
            guard side > 0, side * side == frameCount else {
                throw VendorRawError.unsupported("raw-only EMPAD scan has \(frameCount) frames; add its XML companion to define a non-square scan.")
            }
            height = side
            width = side
        }

        let expected = try Self.checkedProduct([height, width, Self.frameBytes])
        let actual = try Self.fileSize(raw)
        guard expected == actual else {
            throw VendorRawError.malformed("EMPAD XML describes \(width)×\(height) frames (\(expected) bytes), but the raw file has \(actual) bytes.")
        }
        rawPath = raw
        scanHeight = height
        scanWidth = width
        source = .frames
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

    /// One check per public read; latches on the first failure. Only a mapped file needs it.
    private func requireDiskAlive() throws {
        guard case .kit(_, _, _, let liveness) = source else { return }
        if !diskGone, !liveness.isAlive() { diskGone = true }
        if diskGone { throw VendorRawError.volumeGone(displayFileName(rawPath)) }
    }

    /// `viewRows` x `viewColumns` positions of the view, each over `readDetectorCrop` (or the whole image), BEFORE binning.
    private func block(_ view: LoadView, viewRows: Range<Int>, viewColumns: Range<Int>) throws -> [Float] {
        try requireDiskAlive()
        switch source {
        case .kit(let array, let hasScanY, let hasScanX, _):
            return try vendorSlab(array, view: view, viewRows: viewRows, viewColumns: viewColumns,
                                  detector: (Self.imageHeight, Self.width), hasScanY: hasScanY, hasScanX: hasScanX, path: rawPath)
        case .frames:
            var out = [Float]()
            for viewY in viewRows {
                for viewX in viewColumns {
                    out.append(contentsOf: try frame(view, sourceY: view.sourceScanY(viewY), sourceX: view.sourceScanX(viewX)))
                }
            }
            return out
        }
    }

    /// One frame read from the raw file, cropped (the READ crop: trimmed to a whole number of bins).
    private func frame(_ view: LoadView, sourceY: Int, sourceX: Int) throws -> [Float] {
        let frame = sourceY * scanWidth + sourceX
        let data = try Self.read(path: rawPath, offset: frame * Self.frameBytes,
                                 count: Self.imageHeight * Self.width * 4)
        // Decode only the rows the view keeps: the bytes were read either way,
        // but the cropped-out pixels are never converted or allocated.
        let crop = view.readDetectorCrop
        let rows = crop.map { $0.yOffset..<($0.yOffset + $0.height) } ?? 0..<Self.imageHeight
        let columns = crop.map { $0.xOffset..<($0.xOffset + $0.width) } ?? 0..<Self.width
        return data.withUnsafeBytes { bytes in
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

    private static func parseXML(_ url: URL) throws -> (rawFile: String, scanX: Int, scanY: Int) {
        let rawFile = URL(fileURLWithPath: try rawFileAttribute(url)).lastPathComponent
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
/// unflipped values as Float32. A file the kit refuses but this app's reader always took (a header size other than 384 or 768, a
/// header with no width and height, a detector that disagrees with its assembly) is read here, frame by frame, as before.
package actor MIBReader: FourDDataSource {
    /// Where the frames are read from.
    private enum Source: Sendable {
        case kit(array: any FormatoLazyArray, liveness: MappingLiveness)
        /// delete at FormatoKit 0.6.0: MIB header sizes other than 384/768 and headers without width and height (kit ask)
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
        // The stored pixel code of the first frame header.
        let head = try EMPADReader.read(path: path, offset: 0, count: min(4096, try EMPADReader.fileSize(path)))
        let fields = head.firstIndex(of: 0).map {
            String(decoding: head[..<$0], as: UTF8.self).split(separator: ",", omittingEmptySubsequences: false)
        }
        dtype = fields.flatMap { $0.count > 6 ? String($0[6]) : nil } ?? "U16"

        // The kit first; the descriptor is opened BEFORE the kit maps the file.
        let watch = try? vendorLiveness(path: path)
        var refusal = "its disk could not be watched"
        if let watch {
            do {
                let kit = try FormatoMIB.MIBReader(path: path, convention: .appScanXY)
                let shape = kit.signal.array.shape
                if shape.count == 4 {
                    (scanHeight, scanWidth, detectorHeight, detectorWidth) = (shape[0], shape[1], shape[2], shape[3])
                    source = .kit(array: kit.signal.array, liveness: watch)
                    return
                }
                refusal = "the frames are not scan-shaped"
            } catch {
                refusal = "\(error)"
            }
        }
        kitRefusal = refusal

        // The app's own reading.
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
