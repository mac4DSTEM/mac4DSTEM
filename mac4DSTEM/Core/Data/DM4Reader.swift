//
//  DM4Reader.swift
//  Role: Read Gatan DigitalMicrograph .dm4 (and .dm3) 4D-STEM files as a FourDDataSource (the interface H5Reader provides).
//        The tag tree, the pixel mapping and the gather of patterns, scan rows and tiles as Float32 are FormatoKit's
//        `DM4Datacube(.appCalibratedAxes)` (FormatoKit 0.7.0); this file keeps the app's side: which object is the datacube,
//        the pixel calibration read from its tags, the disk watch (`MappingLiveness`) before every read of a mapped file,
//        and the rank-3 scan-shaped object ("Scan shape X/Y" tags) that the kit does not take.
//
//  Structure fields are big-endian; primitive values are little-endian (byteord == 1, required). The pixels are never
//  copied into RAM whole — slabs are gathered from the mapping on demand.
//

import Foundation
import FormatoCore
import FormatoDM
import SpectroCore

/// Whether the disk a memory-mapped file came from is still there (Slot 4⅞,
/// open-items "DM4 on a disconnected volume").
///
/// MEASURED on a RAM disk (HFS+, `hdiutil detach -force`, macOS 27.0.1; probe
/// and logs in `../_archive/mac4DSTEM/docs/archive/v4/polish-plan-2026-10-02/lane-D-probe/`): a path
/// probe is the wrong tool. `statfs(path)` fails after the yank, but passes again with
/// the SAME `f_fsid`, `st_dev` and `st_ino` once a volume of that name is back
/// with the file copied to the same path, while the old mapping is still dead
/// (the next page touched is a SIGBUS). A descriptor opened BEFORE the yank is
/// dead for good: `fstat` fails with EBADF (`pread` with EIO) after the yank
/// and again after the remount. So the witness is a descriptor, opened before
/// the file is mapped and kept for the reader's life; it also survives the user
/// renaming the file in Finder, which a path probe would report as a loss.
package nonisolated struct MappingLiveness: Sendable {
    /// `true` while the disk answers. The reader latches the first `false`.
    package let isAlive: @Sendable () -> Bool

    package init(_ isAlive: @escaping @Sendable () -> Bool) {
        self.isAlive = isAlive
    }

    /// Opens `path` read-only and keeps the descriptor until the last copy of
    /// this value is gone. THROWS `DM4Error.cannotOpen` when it cannot be
    /// opened: a mapped file whose disk cannot be watched is refused, never
    /// read unguarded (Slot 4⅞ fix round: this returned `nil` and the reader
    /// then mapped the file with no guard at all, a gate that failed silently).
    package static func descriptor(path: String) throws -> MappingLiveness {
        let held = HeldDescriptor(path: path)
        guard held.descriptor >= 0 else {
            throw DM4Error.cannotOpen(
                "\(displayFileName(path)) — its disk could not be watched: "
                + String(cString: strerror(held.failure)))
        }
        return MappingLiveness { held.answers }
    }

    private nonisolated final class HeldDescriptor: Sendable {
        let descriptor: Int32
        /// `errno` of the open, read at once; 0 when it succeeded.
        let failure: Int32
        init(path: String) {
            let fd = open(path, O_RDONLY | O_CLOEXEC)
            descriptor = fd
            failure = fd >= 0 ? 0 : errno
        }
        /// THE REAL PROBE IS UNIT-BLIND (refuter, 2026-10-04): swapping `fstat`
        /// for `fcntl(F_GETFD)` keeps every unit test green and still dies with
        /// a SIGBUS after a forced unmount; only a force-ejected RAM disk shows
        /// it. After ANY change to this class, re-run
        /// `../_archive/mac4DSTEM/docs/archive/v4/polish-plan-2026-10-02/lane-D-probe/drive.sh`.
        var answers: Bool {
            var info = stat()
            return fstat(descriptor, &info) == 0
        }
        deinit { if descriptor >= 0 { close(descriptor) } }
    }
}


package actor DM4Reader: FourDDataSource {

    /// Where the pixels come from.
    private enum Cube: Sendable {
        /// A rank-4 object: FormatoKit's lazy gather (scan-fastest storage included).
        case kit(DM4Datacube)
        /// A rank-3 object reshaped to a scan by its "Scan shape X/Y" tags.
        // delete at FormatoKit <next>: a 3D-to-4D reshape by scan-shape tags in DM4Datacube (kit ask)
        case scanShaped(ScanShapedCube)
    }

    private let cube: Cube
    package let filePath: String
    private let descriptor: DatasetDescriptor
    /// Scan-fastest storage: no scan crop skips I/O. Immutable, so the nonisolated `loadPushdown` reads it.
    private let isScanFastest: Bool

    /// Non-nil only when the file is MAPPED: a file read into memory (a network volume) is valid after its disk is gone and
    /// needs no guard. Owner: this reader; one descriptor per open reader.
    private let liveness: MappingLiveness?
    /// THE LATCH (owner card Q1 = a, 2026-10-04): set by the first read that finds the disk gone, never cleared. A plain "is
    /// the volume there" check would pass again the moment the disk is plugged back in, while the old mapping is still dead.
    private var diskGone = false

    // Best-effort calibration.
    package private(set) var voltage: Double?
    package private(set) var qPixelSize: Double?
    package private(set) var qPixelUnits: String?
    package private(set) var rPixelSize: Double?
    package private(set) var rPixelUnits: String?
    /// Why the file's pixel calibration was NOT imported, when its four axis units could not name one real-space pair and one
    /// reciprocal pair. The cube still opens, in the legacy detector-fastest layout, with no pixel sizes — py4DSTEM's own
    /// answer to a Gatan file whose calibration is invalid (`read_dm.py`, "the calibrations can be invalid"). Refusing the
    /// file was the 2026-09-05 first cut and was reversed the same day: a wrong calibration is the user's to override, a
    /// closed file is not.
    package private(set) var calibrationNote: String?

    // Async so the init is actor-isolated, as before the kit switch (the signature is the callers').
    //
    // `liveness` replaces the real descriptor check, for tests; like the real one it applies only when the file is mapped.
    package init(path: String, liveness injected: MappingLiveness? = nil) async throws {
        // The descriptor is opened BEFORE the file is mapped, so it can only belong to the disk the mapping comes from. If the
        // open below throws, the last copy of it goes out of scope and closes it. `readingOptions` is asked once.
        let options = Self.readingOptions(forPath: path)
        let isMapped = options == .alwaysMapped
        let watch = Result<MappingLiveness?, Error> {
            guard isMapped else { return nil }
            return try injected ?? MappingLiveness.descriptor(path: path)
        }
        // The underlying error travels with the refusal (v2 S7 audit): EPERM, ENOENT and a short read are told apart, only
        // the path above the file is gone.
        do {
            // Mapped and dropped untouched: the open's own Cocoa error, worded as before, and no page is read.
            _ = try Data(contentsOf: URL(fileURLWithPath: path), options: .alwaysMapped)
        } catch {
            throw DM4Error.cannotOpen("\(displayFileName(path)) — \(error.localizedDescription)")
        }
        // The file is mapped but its disk cannot be watched (the descriptor failed while the open above succeeded: EMFILE, a
        // permission race): refuse, never read it unguarded. The open's own error, above, wins whenever both fail.
        liveness = try watch.get()
        filePath = path

        let objects = try DM4Experiment.list(path: path)
        let tree = try DM4Experiment.tagTree(path: path)
        var chosen: (cube: Cube, object: DM4ImageObject, dataType: Int, shape: [Int], scanFastest: Bool, note: String?)?
        for object in objects {
            let dims = object.dimensions
            // `ImageData.DataType` is the tag tree's (the object's own copy is package-level in the kit).
            guard let code = tree.numbers["ImageList.\(object.index).ImageData.DataType"].flatMap({ Int(exactly: $0) }) else { continue }
            // The first object with more than two non-singleton dimensions and a pixel type the kit reads.
            guard dims.filter({ $0 > 1 }).count > 2, DMFile.dataType(code: code) != nil else { continue }
            if dims.count == 4 {
                let kit: DM4Datacube
                do {
                    kit = try DM4Datacube(path: path, objectIndex: object.index, convention: .appCalibratedAxes,
                                          storage: isMapped ? .mapped : .readIntoMemory)
                } catch DM4Error.cannotOpen(let detail) {
                    throw DM4Error.cannotOpen(detail)
                } catch {
                    continue          // a declared length that does not fit the file: the next candidate, as before
                }
                let shape = kit.layout.permutation.map { kit.layout.storedShape[$0] }
                chosen = (.kit(kit), object, code, shape, kit.layout.scanFastest, kit.calibrationNote)
                break
            } else if dims.count == 3 {
                // (N_scan, Qy, Qx); the scan shape comes from the tags.
                //
                // DEVIATION from py4DSTEM, deliberate and unported: for this 3D "TitanX" layout py4DSTEM rolls the data by −2
                // pixels along axis 1, correcting a TitanX detector artefact. This reader does not. The consequence is stated
                // rather than hidden: on a file that really carries that artefact, every q-vector read here sits 2 px from
                // where py4DSTEM would put it, which is a calibration-scale shift, not a rounding one. It is unported because
                // no TitanX file has been available to measure it on, and rolling every 3D file by −2 px on the strength of
                // a comment would silently corrupt the ones that do not need it. `../_archive/mac4DSTEM/docs/dm4-format.md`
                // §3.3 carries the record; the note is here because CLAUDE.md requires a deviation to be readable at the code.
                guard let scanX = Self.scanShape(tree.numbers, "Scan shape X"), let scanY = Self.scanShape(tree.numbers, "Scan shape Y"),
                      scanX > 0, scanY > 0 else { continue }
                guard let flat = try? ScanShapedCube(path: path, options: options, object: object, dataType: code, scanY: scanY, scanX: scanX) else {
                    continue
                }
                chosen = (.scanShaped(flat), object, code, [scanY, scanX, dims[1], dims[0]], false, nil)
                break
            }
        }
        guard let chosen else { throw DM4Error.noDatacube }

        cube = chosen.cube
        isScanFastest = chosen.scanFastest
        calibrationNote = chosen.note
        let object = chosen.object
        descriptor = DatasetDescriptor(
            filePath: path, datasetPath: "ImageList.\(object.index).ImageData.Data", shape: chosen.shape,
            dtypeDescription: Self.dtypeName(chosen.dataType), chunkShape: nil)

        // Calibration, from the object's own dimension tags: pixel sizes only when the unit domains named the pairs.
        let prefix = "ImageList.\(object.index).ImageData."
        let indices = tree.numbers.keys.filter { $0.hasPrefix(prefix + "Dimensions.") }
            .compactMap { Int($0.dropFirst((prefix + "Dimensions.").count)) }.sorted()
        func scale(_ i: Int) -> Double? { tree.numbers[prefix + "Calibrations.Dimension.\(i).Scale"] }
        func units(_ i: Int) -> String? {
            let u = tree.strings[prefix + "Calibrations.Dimension.\(i).Units"]
            return (u?.isEmpty ?? true) ? nil : u
        }
        if chosen.note == nil, indices.count >= 3 {
            let leading = indices[0], trailing = indices[2]
            let qIndex = chosen.scanFastest ? trailing : leading
            let rIndex = chosen.scanFastest ? leading : trailing
            qPixelSize = scale(qIndex)
            qPixelUnits = units(qIndex)
            rPixelSize = scale(rIndex)
            rPixelUnits = units(rIndex)
        }
        voltage = object.voltage ?? tree.numbers.keys.sorted().first { $0.contains("Microscope Info.Voltage") }.flatMap { tree.numbers[$0] }
    }

    /// How the file is held (2026-09-24, open-items "DM4Reader silently reads whole files into RAM off non-local volumes").
    ///
    /// `.mappedIfSafe` maps only on a volume that is local AND not removable, so every external disk falls back to reading the
    /// whole file into anonymous memory. The owner's raw 4D-STEM files are 28 GB on an external SSD, and this Mac has 8 GB of
    /// RAM: that fallback cannot work.
    ///
    /// On any local volume, removable or not, the file is memory-mapped (`.alwaysMapped`): pages come in as patterns are read
    /// and are clean, reclaimable file pages, not anonymous memory. The price is the one py4DSTEM pays: its binned load
    /// (`read_dm.py:100-121`, `mem="RAM"`, `binfactor > 1`) and its `mem="MEMMAP"` (`:123-124`) both read through ncempy's
    /// `np.memmap` (`ncempy/io/dm.py:1195`). If the volume disappears while mapped, the next page touched is a SIGBUS: the app
    /// crashes without a dialog, not a thrown `DM4Error`. Since Slot 4⅞ every read first asks `requireDiskAlive()` and, once
    /// the disk is gone, throws `DM4Error.volumeGone` for the rest of the reader's life; a read already in flight at the
    /// moment of the yank can still crash.
    ///
    /// DEVIATION: ncempy maps on every volume. A network volume (no `MNT_LOCAL`) is not mapped here: the kit reads the
    /// object's pixel bytes into memory once (`DM4DatacubeStorage.readIntoMemory`), because a mapped page the network cannot
    /// deliver is the same SIGBUS, far more likely than an unplugged SSD. Streaming reads that throw instead would fix both,
    /// and are not built.
    ///
    /// `init` asks this once for the storage it chooses; `run-tests.sh inventory` greps for it.
    package nonisolated static func readingOptions(forPath path: String) -> Data.ReadingOptions {
        var info = statfs()
        guard statfs(path, &info) == 0 else { return .mappedIfSafe }
        return (info.f_flags & UInt32(MNT_LOCAL)) != 0 ? .alwaysMapped : .mappedIfSafe
    }

    // MARK: FourDDataSource

    package func discoverPrimaryDataset() throws -> DatasetDescriptor { descriptor }

    /// Detector-fastest DM4 is one contiguous blob of patterns, so a *scan* crop is a seek and genuinely skips bytes; a
    /// *detector* crop decodes only the kept rows, but the excluded columns share pages with the kept ones, and `LoadPushdown`
    /// is a boolean that rounds down (adversarial review, 2026-08-18). Scan-fastest storage spreads every pattern across the
    /// whole blob, so there neither crop skips I/O.
    package nonisolated func loadPushdown(for view: LoadView) -> LoadPushdown {
        isScanFastest ? .none : .scanOnly
    }

    /// One check per public read (not per decode: a tile is many decodes and the check is a syscall). Latches on the first
    /// failure; see `diskGone`.
    private func requireDiskAlive() throws {
        if !diskGone, let liveness, !liveness.isAlive() { diskGone = true }
        if diskGone { throw DM4Error.volumeGone(displayFileName(filePath)) }
    }

    /// `rows` x `columns` source scan positions over the view's READ crop (or the whole detector), as Float, BEFORE binning.
    private func gather(_ view: LoadView, rows: Range<Int>, columns: Range<Int>) throws -> [Float] {
        let source = descriptor
        let start = [rows.lowerBound, columns.lowerBound, view.readDetectorCrop?.yOffset ?? 0, view.readDetectorCrop?.xOffset ?? 0]
        let count = [rows.count, columns.count, view.readDetectorCrop?.height ?? source.qy, view.readDetectorCrop?.width ?? source.qx]
        switch cube {
        case .kit(let kit):
            guard let values = try kit.signal.array.read(start: start, count: count).float32Values() else {
                throw DM4Error.truncated
            }
            return values
        case .scanShaped(let flat):
            return try flat.read(start: start, count: count)
        }
    }

    package func readPattern(_ view: LoadView, ry scanY: Int, rx scanX: Int) throws -> [Float] {
        try requireDiskAlive()
        try view.requireSource(shape: descriptor.shape)
        guard scanY >= 0, scanY < view.descriptor.ry, scanX >= 0, scanX < view.descriptor.rx else {
            throw DM4Error.truncated
        }
        let y = view.sourceScanY(scanY), x = view.sourceScanX(scanX)
        return view.binned(try gather(view, rows: y..<(y + 1), columns: x..<(x + 1)), patternCount: 1)
    }

    package func readScanRow(_ view: LoadView, ry scanY: Int) throws -> [Float] {
        try requireDiskAlive()
        try view.requireSource(shape: descriptor.shape)
        guard scanY >= 0, scanY < view.descriptor.ry else { throw DM4Error.truncated }
        let y = view.sourceScanY(scanY), x = view.sourceScanX(0)
        return view.binned(try gather(view, rows: y..<(y + 1), columns: x..<(x + view.descriptor.rx)),
                           patternCount: view.descriptor.rx)
    }

    package func readScanTile(_ view: LoadView, yRange: Range<Int>) throws -> FourDScanTile {
        try requireDiskAlive()
        try view.requireSource(shape: descriptor.shape)
        let lower = max(0, yRange.lowerBound)
        let upper = min(view.descriptor.ry, yRange.upperBound)
        let range = lower..<max(lower, upper)
        let pixels: [Float]
        if range.isEmpty {
            pixels = []
        } else {
            let y = view.sourceScanY(range.lowerBound), x = view.sourceScanX(0)
            pixels = view.binned(try gather(view, rows: y..<(y + range.count), columns: x..<(x + view.descriptor.rx)),
                                 patternCount: range.count * view.descriptor.rx)
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

    private nonisolated static func scanShape(_ numbers: [String: Double], _ needle: String) -> Int? {
        for (key, value) in numbers where key.contains(needle) { return Int(value) }
        return nil
    }

    private static func dtypeName(_ dataType: Int) -> String {
        switch dataType {
        case 1: return "int16"; case 2: return "float32"; case 6: return "uint8"
        case 7: return "int32"; case 9: return "int8"; case 10: return "uint16"
        case 11: return "uint32"; case 12: return "float64"
        default: return "dm-type-\(dataType)"
        }
    }
}

/// A rank-3 DM object (N_scan, Qy, Qx), mapped, read as the 4D cube `[Ry, Rx, Qy, Qx]` its scan-shape tags give. Frames are
/// contiguous, so a slab is one run per detector row (one run per frame when the detector is not cropped).
// delete at FormatoKit <next>: a 3D-to-4D reshape by scan-shape tags in DM4Datacube (kit ask)
private nonisolated struct ScanShapedCube: Sendable {
    let data: Data
    let offset: Int
    let dataType: Int
    let elementSize: Int
    let rx: Int, qy: Int, qx: Int

    init(path: String, options: Data.ReadingOptions, object: DM4ImageObject, dataType: Int, scanY: Int, scanX: Int) throws {
        guard let type = DMFile.dataType(code: dataType) else { throw DM4Error.unsupportedDataType(dataType) }
        let (qy, qx) = (object.dimensions[1], object.dimensions[0])
        // Chain multiplication with overflow checks so absurd tag-derived dims reject the candidate instead of trapping.
        var expected = type.byteSize
        for n in [scanY, scanX, qy, qx] {
            let (next, overflow) = expected.multipliedReportingOverflow(by: n)
            guard !overflow else { throw DM4Error.truncated }
            expected = next
        }
        let (end, overflow) = object.dataOffset.addingReportingOverflow(expected)
        // A declared array length of 0 (some writers omit it) is still tolerated when the mapping holds the whole cube.
        guard !overflow, object.dataOffset >= 0, object.dataByteCount == expected || object.dataByteCount == 0 else {
            throw DM4Error.truncated
        }
        data = try Data(contentsOf: URL(fileURLWithPath: path), options: options)
        guard end <= data.count else { throw DM4Error.truncated }
        offset = object.dataOffset; self.dataType = dataType; elementSize = type.byteSize
        self.rx = scanX; self.qy = qy; self.qx = qx
    }

    /// `start`, `count`: `[scanY, scanX, detectorY, detectorX]`; the slab as Float, frames in order, each row of the crop after the last.
    func read(start: [Int], count: [Int]) throws -> [Float] {
        var out = [Float](repeating: 0, count: count.reduce(1, *))
        var at = 0
        let wholeRows = start[3] == 0 && count[3] == qx
        for y in 0..<count[0] {
            for x in 0..<count[1] {
                let frame = (start[0] + y) * rx + start[1] + x
                if wholeRows {
                    try decode(byteOffset: offset + (frame * qy + start[2]) * qx * elementSize, count: count[2] * qx, into: &out, at: at)
                    at += count[2] * qx
                } else {
                    for row in 0..<count[2] {
                        try decode(byteOffset: offset + ((frame * qy + start[2] + row) * qx + start[3]) * elementSize,
                                   count: count[3], into: &out, at: at)
                        at += count[3]
                    }
                }
            }
        }
        return out
    }

    /// Little-endian pixels to Float at `destination`, each converted the way a C cast does. A slice past the mapping means a
    /// truncated file; never hand back zero-filled pixels as if they were read.
    private func decode(byteOffset start: Int, count: Int, into out: inout [Float], at destination: Int) throws {
        guard start >= 0, count >= 0, start + count * elementSize <= data.count,
              destination >= 0, destination + count <= out.count else { throw DM4Error.truncated }
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            let p = base + start
            let d = destination
            switch dataType {
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
}
