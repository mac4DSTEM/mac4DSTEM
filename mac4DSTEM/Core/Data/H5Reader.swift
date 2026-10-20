import Darwin
import Foundation
import FormatoCore
import FormatoHDF5
import SpectroCore

package enum H5Error: LocalizedError {
    case libraryUnavailable(String)
    case symbolMissing(String)
    case cannotOpenFile(String)
    case noDatasetFound([String])
    /// The opened file is one of this app's own session sidecars — recognised
    /// by its root schema attribute. Hit twice in one afternoon (2026-08-19):
    /// the open panel offers both files of the sharing pair and
    /// they sort adjacently under near-identical names, so this failure mode
    /// is EXPECTED, not exotic — it deserves a sentence, not a dump.
    case sessionSidecarOpened(sidecar: String, suggestedSource: String?)
    case datasetOpenFailed(String)
    case readFailed(String)
    case unsupportedRank(Int)

    package var errorDescription: String? {
        switch self {
        case .libraryUnavailable(let detail):
            return "Could not load the bundled HDF5 library: \(detail)"
        case .symbolMissing(let name):
            return "The HDF5 library is missing required symbol \(name)."
        case .cannotOpenFile(let path):
            return "Could not open \(displayFileName(path)). Is it a valid .h5 file?"
        case .noDatasetFound(let paths):
            // Capped: the full wall (30+ probed paths on a real sidecar) buries
            // the one sentence that matters. The first few say what was tried;
            // the count says the search was thorough.
            let shown = paths.prefix(8)
            let remainder = paths.count - shown.count
            let tail = remainder > 0 ? "\n… and \(remainder) more paths" : ""
            return "No 4D or 3D dataset found. Tried paths:\n"
                + shown.joined(separator: "\n") + tail
        case .sessionSidecarOpened(let sidecar, let suggestedSource):
            // `suggestedSource` is a STEM, never a filename: the sidecar
            // naming rule strips any extension from the source, so asserting
            // ".h5" here would send a .dm4 user hunting for a file that never
            // existed (caught by Gate A before it shipped).
            let first = "\(sidecar) is a mac4DSTEM session sidecar — the companion "
                + "file that stores a session's calibration and results, not a dataset."
            if let suggestedSource {
                return first + " Open the dataset named “\(suggestedSource)” beside it "
                    + "and the saved session loads with it automatically."
            }
            return first + " Open the dataset it was saved beside and the "
                + "saved session loads with it automatically."
        case .datasetOpenFailed(let path):
            return "Failed to open dataset at HDF5 path \(path)."
        case .readFailed(let operation):
            return "HDF5 read failed: \(operation)."
        case .unsupportedRank(let rank):
            return "Dataset rank \(rank) is not supported. Expected rank 3 or 4."
        }
    }
}

/// The app's HDF5 datacube source. Every HDF5 access is FormatoKit's `HDF5Reader` (FormatoKit 0.5.0): the one libhdf5 loader of the
/// process, each call under `HDF5Serial`, no handle held between calls. What the file's layout MEANS (which node is the datacube, a
/// session sidecar, a probe, py4DSTEM's calibration bundle) is this type's.
package actor H5Reader: FourDDataSource {
    private let reader: HDF5Reader
    package let filePath: String
    /// Path of the most recently described dataset — anchor for locating the
    /// py4DSTEM calibration bundle / EMD dim vectors relative to the datacube.
    private var lastDatasetPath: String?
    private var lastDatasetShape: [Int]?
    private var lastStoredRank: Int?
    /// Stored shapes by dataset path, read from the file on first use: a slab read checks its view against the FILE's dims, and one
    /// `HDF5Reader` call opens the file, so the dims are not asked for again on the streaming hot path.
    private var storedShapes: [String: [Int]] = [:]

    package static let candidatePaths: [String] = [
        "/dm_dataset_root/dm_dataset/data",
        "/4DSTEM_experiment/data/datacubes/datacube_0/data",
        "/4DSTEM/data/datacubes/datacube_root/data",
        "/datacube_root/datacube/data",
        "/Experiments/__unnamed__/data",
        "/Experiments/__unnamed__/data/data"
    ]

    package init(path: String) throws {
        do {
            reader = try HDF5Reader(url: URL(fileURLWithPath: path))
        } catch HDF5FileError.library(let detail) {
            throw H5Error.libraryUnavailable(detail)
        } catch {
            throw H5Error.cannotOpenFile(path)
        }
        filePath = path
    }

    package func discoverPrimaryDataset() throws -> DatasetDescriptor {
        let sidecarRoot = "/" + SessionSidecarFormat.rootGroupName
        let attribute = SessionSidecarFormat.schemaAttribute
        let markedAtRootGroup = stringAttribute(attribute, onPath: sidecarRoot) != nil
        let markedAtFileRoot = stringAttribute(attribute, onPath: "/") != nil
        // Each candidate path is a PROBE (v2 S7 audit): "this file has no
        // dataset at that name" is the expected answer for most of them, not
        // a failure to surface. A file-level I/O error would also be swallowed
        // per-candidate, but the file handle was already opened successfully
        // and the fall-through ends in a named "no 4D dataset" error, never a
        // silent success.
        for path in Self.candidatePaths {
            // A file-root schema mark declares the WHOLE file a sidecar. It
            // must therefore win even over a canonical path; otherwise a
            // specially shaped saved product at a canonical name would bypass
            // the location guarantee before the general search sees it.
            if markedAtFileRoot { continue }
            if let descriptor = datacubeCandidate(at: path) { return anchored(descriptor) }
        }

        // EMD 1.0 permits arbitrary root/node names. Visit links only after
        // the fast canonical probes, then ask HDF5 itself which links are 3D/
        // 4D datasets. This avoids baking a particular py4DSTEM root name into
        // interoperability while keeping deterministic preference for `data`.
        let candidates = allLinkPaths().sorted {
            let lhsData = $0.hasSuffix("/data") ? 0 : 1
            let rhsData = $1.hasSuffix("/data") ? 0 : 1
            if lhsData != rhsData { return lhsData < rhsData }
            let lhsDepth = $0.filter { $0 == "/" }.count
            let rhsDepth = $1.filter { $0 == "/" }.count
            return lhsDepth == rhsDepth ? $0 < $1 : lhsDepth < rhsDepth
        }
        // THE PATH ORDER ALONE MAY NOT CHOOSE. `describe` promotes a rank-3
        // array to one scan row, so until 2026-09-04 the first `/data` node of
        // rank 3 or 4 in that order won: a shallow rank-3 sibling — a strain
        // map, a probe stack, a saved RGBA result — outranked a genuine rank-4
        // cube deeper in the file and was returned AS the data, and the pinned
        // real cubes escaped only by where they sat alphabetically. Within this
        // search a node the file itself labels as not-a-cube is refused
        // (`datacubeRejection`), a stored rank-4 cube anywhere beats a
        // promoted rank-3 array anywhere, and the path order breaks ties —
        // the FIRST of two cubes wins, which two pinned real files exercise.
        // The canonical loop above is a different contract for ordinary files:
        // a canonical path is the file's own declaration of where its datacube
        // is, honoured first-match even for a rank-3 there. An explicit
        // file-root sidecar mark overrides that declaration, because it says
        // the whole file is session content. The
        // rank-3 contract stands: a file whose best node is an unlabelled
        // rank-3 array opens as one scan row (`load-spec-test`). Every case is
        // pinned by `tools/harnesses/datacube-discovery-test`; the Gate D/B record is
        // still owed in the live documentation until the full gate completes.
        //
        // A SIDECAR'S OWN ROOT HOLDS SAVED PRODUCTS, NEVER A DATACUBE — a
        // location guarantee independent of what a writer stamped. The label
        // rule is the mechanism-level fix; this stays beside it because the
        // Gate B refuter showed (2026-09-04) that without it a sidecar node
        // carrying neither stamp is again returned as a 4-pixel-detector cube.
        // A file marked at its FILE ROOT declares the whole file a sidecar; one
        // marked at the sidecar root group only speaks for that subtree, so a
        // cube outside it still opens.
        var promoted: DatasetDescriptor?
        for path in candidates where !Self.candidatePaths.contains(path) {
            if markedAtFileRoot { continue }
            if markedAtRootGroup, path.hasPrefix(sidecarRoot + "/") { continue }
            guard let descriptor = datacubeCandidate(at: path) else { continue }
            if descriptor.storedRank == 4 { return anchored(descriptor) }
            if promoted == nil { promoted = descriptor }
        }
        if let promoted { return anchored(promoted) }
        lastDatasetPath = nil
        lastDatasetShape = nil
        lastStoredRank = nil
        // Before answering "no dataset", ask whether this is one of the app's
        // own session sidecars: they contain no datacube BY DESIGN. The writer
        // stamps the schema attribute on its ROOT GROUP, not the file root —
        // the first version of this check read "/" and was caught by its own
        // test; "/" is kept as a fallback so a future writer that stamps the
        // file root is still recognised. Deliberately checked only AFTER the
        // full search fails: a file that carries both the attribute and a real
        // 4D dataset outside the sidecar's own subtree opens as data. The
        // suggestion is the source's STEM, not a filename — the naming rule
        // strips any extension, so the source may be .dm4, .emd, anything. // v2 S4
        if markedAtRootGroup || markedAtFileRoot {
            let name = URL(fileURLWithPath: filePath).lastPathComponent
            let suffix = SessionSidecarFormat.nameSuffix
            let suggested: String? = name.hasSuffix(suffix)
                ? String(name.dropLast(suffix.count))
                : nil
            throw H5Error.sessionSidecarOpened(sidecar: name, suggestedSource: suggested)
        }
        throw H5Error.noDatasetFound(Self.candidatePaths + candidates)
    }

    /// `describe` plus the discovery-boundary judgement: nil when the path is
    /// not a dataset of rank 3 or 4, or when the file labels the node as
    /// something other than a datacube (`datacubeRejection`). // 2026-09-04
    private func datacubeCandidate(at path: String) -> DatasetDescriptor? {
        guard let descriptor = try? describe(path: path) else { return nil }
        let parent = "/" + path.split(separator: "/").dropLast().joined(separator: "/")
        let lastAxisDim = (parent == "/" ? "" : parent) + "/dim\(descriptor.storedRank - 1)"
        // Legacy py4DSTEM v0.12 numbers dims from 1, so its last axis is
        // `dim{rank}`; a slice stack keeps its labels there as strings.
        let legacyLastDim = (parent == "/" ? "" : parent) + "/dim\(descriptor.storedRank)"
        let candidate = DatacubeCandidate(
            path: path, storedRank: descriptor.storedRank,
            lastAxisName: stringAttribute("name", onPath: lastAxisDim),
            units: stringAttribute("units", onPath: path),
            // v0.12 applies this string-label rule only to objects selected
            // from its `data/diffractionslices` and `data/realslices`
            // collections (`read_v0_12.py:352-388`, get_diffractionslice_from_grp
            // and get_realslice_from_grp share the dim3 test). A same-named
            // string sibling in an unrelated modern group is metadata, not a
            // reason to refuse an otherwise genuine cube. `realslices` was
            // missing until 2026-09-05: a strain stack (5, 7, 4) opened as a
            // datacube with a four-pixel detector, and the harness check that
            // pins it had been red since it was committed.
            legacySliceLabels: (path.contains("/data/diffractionslices/")
                                || path.contains("/data/realslices/"))
                && datasetIsStringTyped(legacyLastDim)
        )
        return Self.datacubeRejection(of: candidate) == nil ? descriptor : nil
    }

    /// True when `path` is a dataset whose STORED type is a string — the
    /// pinned legacy v0.12 reader's own test for a slice-label vector
    /// (`read_v0_12.py:365-366`, `"S" in lbls.dtype.str`). A real axis vector
    /// is numeric, so this cannot refuse a genuine dim of any numbering.
    private func datasetIsStringTyped(_ path: String) -> Bool {
        guard let info = try? reader.datasetInfo(path) else { return false }
        if case .string = info.type { return true }
        return false
    }

    /// Discovery describes nodes it then rejects or passes over, and each
    /// `describe` moves the calibration anchor (`lastDatasetPath`); the anchor
    /// must end on the node discovery RETURNS, or on nothing. Before 2026-09-04
    /// the first successful `describe` was always the returned one.
    private func anchored(_ chosen: DatasetDescriptor) -> DatasetDescriptor {
        lastDatasetPath = chosen.datasetPath
        lastDatasetShape = chosen.shape
        lastStoredRank = chosen.storedRank
        return chosen
    }

    /// Every link of the file below the root, as absolute paths: groups are descended (never past depth 64, so a soft-link cycle ends)
    /// and the list stops at 100 000 entries, as the former `H5Lvisit2` collector did.
    // delete at FormatoKit 0.6: a recursive link listing in HDF5Reader (one open per group and per link here)
    private func allLinkPaths() -> [String] {
        let cap = 100_000
        var found: [String] = []
        func visit(_ group: String, depth: Int) {
            guard depth < 64, let names = try? reader.children(of: group) else { return }
            for name in names {
                guard found.count < cap else { return }
                let path = (group == "/" ? "" : group) + "/" + name
                found.append(path)
                if (try? reader.kind(of: path)) == .group { visit(path, depth: depth + 1) }
            }
        }
        visit("/", depth: 0)
        return found
    }

    // MARK: Probe images (FourDDataSource)

    /// Datasets named for a probe — the last path component or its parent
    /// group contains "probe" (py4DSTEM: `probe`, `probe_template`) — on the
    /// detector grid in either layout: legacy v0.12 (Qx, Qy, N), slices LAST
    /// (read_v0_12.py get_diffractionslice_from_grp), or the modern `Probe`
    /// class (2, Qx, Qy), slices FIRST (probe.py:56-71; a Gate B refuter
    /// saved one with py4DSTEM 0.14.17 and got (2, 16, 20)). A rank-3 stack
    /// whose first two dims match is read as slices-last; when only its last
    /// two match, slices-first. Nothing under the session sidecar root is a
    /// probe. Order: shallowest path first, then alphabetical.
    package func probeCandidates(detectorQY qy: Int, detectorQX qx: Int) throws -> [ProbeCandidate] {
        let sidecarRoot = "/" + SessionSidecarFormat.rootGroupName + "/"
        var found: [ProbeCandidate] = []
        for path in allLinkPaths() where !path.hasPrefix(sidecarRoot) {
            let components = path.split(separator: "/").map(String.init)
            guard let last = components.last else { continue }
            let parent = components.count >= 2 ? components[components.count - 2] : ""
            guard last.lowercased().contains("probe") || parent.lowercased().contains("probe") else { continue }
            guard let dims = datasetDimensions(path), dims.count == 2 || dims.count == 3 else { continue }
            if dims[0] == qy, dims[1] == qx {
                found.append(ProbeCandidate(path: path, qy: qy, qx: qx,
                                            sliceCount: dims.count == 3 ? dims[2] : 1, slicesFirst: false))
            } else if dims.count == 3, dims[1] == qy, dims[2] == qx {
                found.append(ProbeCandidate(path: path, qy: qy, qx: qx,
                                            sliceCount: dims[0], slicesFirst: true))
            }
        }
        return found.sorted {
            let l = $0.path.filter { $0 == "/" }.count, r = $1.path.filter { $0 == "/" }.count
            return l == r ? $0.path < $1.path : l < r
        }
    }

    /// Slice 0 of the candidate as a detector-grid pattern: the whole dataset
    /// is read as float; for a (qy, qx, N) stack every pixel's first slice is
    /// taken, for an (N, qy, qx) stack the first qy·qx values are.
    package func readProbe(_ candidate: ProbeCandidate) throws -> [Float] {
        guard let dims = datasetDimensions(candidate.path), dims.count == 2 || dims.count == 3,
              candidate.slicesFirst
                ? (dims.count == 3 && dims[1] == candidate.qy && dims[2] == candidate.qx)
                : (dims[0] == candidate.qy && dims[1] == candidate.qx) else {
            throw H5Error.datasetOpenFailed(candidate.path)
        }
        let buffer: [Float]
        do {
            guard let floats = Self.floats(try reader.readDataset(candidate.path, maximumBytes: Int.max)) else {
                throw H5Error.readFailed("probe image \(candidate.path)")
            }
            buffer = floats
        } catch {
            throw H5Error.readFailed("probe image \(candidate.path)")
        }
        guard dims.count == 3 else { return buffer }
        if candidate.slicesFirst { return Array(buffer[0..<(candidate.qy * candidate.qx)]) }
        let slices = dims[2]
        var pixels = [Float](repeating: 0, count: candidate.qy * candidate.qx)
        for index in pixels.indices { pixels[index] = buffer[index * slices] }
        return pixels
    }

    /// Dimensions of a dataset at `path`, nil when it is not a dataset.
    private func datasetDimensions(_ path: String) -> [Int]? {
        guard let info = try? reader.datasetInfo(path), !info.shape.isEmpty else { return nil }
        return info.shape
    }

    package func describe(path: String) throws -> DatasetDescriptor {
        let info: HDF5DatasetInfo
        do {
            info = try reader.datasetInfo(path)
        } catch HDF5FileError.unsupportedType {
            throw H5Error.unsupportedRank(0)     // a null dataspace: no rank
        } catch {
            throw H5Error.datasetOpenFailed(path)
        }
        let rank = info.shape.count
        guard rank == 3 || rank == 4 else { throw H5Error.unsupportedRank(rank) }
        storedShapes[path] = info.shape

        var shape = info.shape
        if rank == 3 {
            shape = [1, shape[0], shape[1], shape[2]]
        }

        lastDatasetPath = path
        lastDatasetShape = shape
        lastStoredRank = rank
        return DatasetDescriptor(
            filePath: filePath,
            datasetPath: path,
            shape: shape,
            dtypeDescription: Self.describeType(info.type),
            chunkShape: HDF5LegacyProbe.chunkShape(filePath: filePath, datasetPath: path, rank: rank),
            storedRank: rank
        )
    }

    private static func describeType(_ type: HDF5DatasetType) -> String {
        switch type {
        case .numeric(let dataType): dataType.rawValue
        case .string: "string"
        case .unsupported(let name): name
        }
    }

    /// HDF5 pushes every axis of a crop into the hyperslab it already builds —
    /// **on a contiguous dataset**. On a *chunked* one it reads and decompresses
    /// whole chunks, so a crop that stays inside a chunk skips no bytes at all,
    /// and py4DSTEM EMD files are chunked. Measured 2026-08-18, gzip-chunked
    /// (16,16,256,256) f4 with chunks (1,16,256,256), `purge` between runs:
    /// the full detector took 0.137 s and 1/64 of it took 0.135 s.
    ///
    /// So the declaration is per-axis and conservative: a crop is only claimed
    /// to skip I/O on an axis whose chunk extent is smaller than the source, the
    /// case where cropping can exclude entire chunks. Claiming `.full`
    /// unconditionally — which this reader did until an adversarial review
    /// measured it — is exactly the overstatement `LoadPushdown` exists to stop.
    ///
    /// DEVIATION from py4DSTEM (preprocess.crop_data_diffraction,
    /// References/py4DSTEM-dev/py4DSTEM/preprocess/preprocess.py:123): py4DSTEM
    /// slices an already-resident array in place (`datacube.data[:, :, qx0:qx1,
    /// qy0:qy1]`), which is a NumPy view — the full cube stays alive as `.base`,
    /// so you lose access to the full extent while still paying for it. Here the
    /// crop is applied at READ time and the source file is untouched.
    package nonisolated func loadPushdown(for view: LoadView) -> LoadPushdown {
        let source = view.source
        guard let chunk = source.chunkShape, chunk.count == 4 else { return .full }
        return LoadPushdown(
            scanCropSkipsIO: chunk[0] < source.ry || chunk[1] < source.rx,
            detectorCropSkipsIO: chunk[2] < source.qy || chunk[3] < source.qx
        )
    }

    /// Where the requested view starts and how much of it to take, in the
    /// file's own dataspace.
    ///
    /// Rank-3 files were reshaped to `[1, N, Qy, Qx]` in `describe()`; the file
    /// dataspace is still rank 3, so the scan-row axis is dropped and a scan
    /// crop's *x* offset indexes the N axis. Getting that mapping wrong would
    /// read the right number of pixels from the wrong frames, so the bounds
    /// check below is against the file's real dims rather than the descriptor.
    private func hyperslab(
        _ view: LoadView, dims: [Int], scanY: Range<Int>, scanX: Range<Int>
    ) throws -> (start: [Int], count: [Int]) {
        let fileRank = dims.count
        let specification = view.specification
        let (sourceY, sourceX) = specification.scanOffset
        // The READ crop, not the requested one: it is trimmed to a whole number
        // of bins, so the edge remainder is never decoded — and on a CONTIGUOUS
        // dataset never read either, though on a chunked one HDF5 still inflates
        // the whole chunk (see `loadPushdown`). And the extent here
        // is the PRE-bin one — the hyperslab selects pixels, `binned` reduces
        // them; no HDF5 selection can sum.
        let detectorY = view.readDetectorCrop?.yOffset ?? 0
        let detectorX = view.readDetectorCrop?.xOffset ?? 0
        let qy = view.readDetectorCrop?.height ?? view.source.qy
        let qx = view.readDetectorCrop?.width ?? view.source.qx

        let start: [Int]
        let count: [Int]
        if fileRank == 3 {
            guard scanY == 0..<1 else {
                throw H5Error.readFailed("rank-3 dataset has a single scan row; asked for \(scanY)")
            }
            start = [sourceX + scanX.lowerBound, detectorY, detectorX]
            count = [scanX.count, qy, qx]
        } else {
            start = [sourceY + scanY.lowerBound, sourceX + scanX.lowerBound,
                     detectorY, detectorX]
            count = [scanY.count, scanX.count, qy, qx]
        }

        // Bounds against the FILE, not against the descriptor we were handed.
        // A descriptor and a specification that disagree would otherwise select
        // a valid-looking hyperslab of the wrong region, and every length check
        // downstream would pass.
        // The view must describe THIS dataset. Checked from the dims already in
        // hand rather than by re-opening the file, so it costs nothing on the
        // streaming hot path. Rank-3 files carry the same [1, N, Qy, Qx]
        // reshape `describe()` applied.
        let sourceShape = fileRank == 3 ? [1] + dims : dims
        try view.requireSource(shape: sourceShape)
        for axis in 0..<fileRank {
            guard start[axis] >= 0, count[axis] > 0,
                  start[axis] + count[axis] <= dims[axis] else {
                throw H5Error.readFailed(
                    "selection \(start[axis])+\(count[axis]) exceeds axis \(axis) of \(dims[axis])"
                )
            }
        }
        return (start, count)
    }

    private func read(
        _ view: LoadView, scanY: Range<Int>, scanX: Range<Int>, label: String
    ) throws -> [Float] {
        let path = view.source.datasetPath
        let dims: [Int]
        if let cached = storedShapes[path] {
            dims = cached
        } else {
            guard let info = try? reader.datasetInfo(path) else { throw H5Error.datasetOpenFailed(path) }
            storedShapes[path] = info.shape
            dims = info.shape
        }
        let slab = try hyperslab(view, dims: dims, scanY: scanY, scanX: scanX)
        let buffer: [Float]
        do {
            let array = try reader.readDataset(path, start: slab.start, count: slab.count, maximumBytes: Int.max)
            guard let floats = Self.floats(array) else { throw H5Error.readFailed(label) }
            buffer = floats
        } catch {
            throw H5Error.readFailed(label)
        }
        let patternCount = buffer.count
            / max(1, (view.readDetectorCrop?.height ?? view.source.qy)
                     * (view.readDetectorCrop?.width ?? view.source.qx))
        return view.binned(buffer, patternCount: patternCount)
    }

    /// The array as Float, each element converted the way `H5Dread` into `H5T_NATIVE_FLOAT` converts it (a C cast, rounding to
    /// nearest even; float32 is copied as stored). Nil for a colour type, which no HDF5 dataset holds.
    private static func floats(_ array: FormatoArray) -> [Float]? {
        let n = array.count
        return array.bytes.withUnsafeBytes { p -> [Float]? in
            switch array.dataType {
            case .float32:
                return [Float](unsafeUninitializedCapacity: n) { out, count in
                    for i in 0..<n { out[i] = Float(bitPattern: UInt32(littleEndian: p.loadUnaligned(fromByteOffset: 4 * i, as: UInt32.self))) }
                    count = n
                }
            case .float64:
                return [Float](unsafeUninitializedCapacity: n) { out, count in
                    for i in 0..<n { out[i] = Float(Double(bitPattern: UInt64(littleEndian: p.loadUnaligned(fromByteOffset: 8 * i, as: UInt64.self)))) }
                    count = n
                }
            case .uint8:
                return [Float](unsafeUninitializedCapacity: n) { out, count in
                    for i in 0..<n { out[i] = Float(p.loadUnaligned(fromByteOffset: i, as: UInt8.self)) }
                    count = n
                }
            case .int8:
                return [Float](unsafeUninitializedCapacity: n) { out, count in
                    for i in 0..<n { out[i] = Float(p.loadUnaligned(fromByteOffset: i, as: Int8.self)) }
                    count = n
                }
            case .uint16:
                return [Float](unsafeUninitializedCapacity: n) { out, count in
                    for i in 0..<n { out[i] = Float(UInt16(littleEndian: p.loadUnaligned(fromByteOffset: 2 * i, as: UInt16.self))) }
                    count = n
                }
            case .int16:
                return [Float](unsafeUninitializedCapacity: n) { out, count in
                    for i in 0..<n { out[i] = Float(Int16(littleEndian: p.loadUnaligned(fromByteOffset: 2 * i, as: Int16.self))) }
                    count = n
                }
            case .uint32:
                return [Float](unsafeUninitializedCapacity: n) { out, count in
                    for i in 0..<n { out[i] = Float(UInt32(littleEndian: p.loadUnaligned(fromByteOffset: 4 * i, as: UInt32.self))) }
                    count = n
                }
            case .int32:
                return [Float](unsafeUninitializedCapacity: n) { out, count in
                    for i in 0..<n { out[i] = Float(Int32(littleEndian: p.loadUnaligned(fromByteOffset: 4 * i, as: Int32.self))) }
                    count = n
                }
            case .uint64:
                return [Float](unsafeUninitializedCapacity: n) { out, count in
                    for i in 0..<n { out[i] = Float(UInt64(littleEndian: p.loadUnaligned(fromByteOffset: 8 * i, as: UInt64.self))) }
                    count = n
                }
            case .int64:
                return [Float](unsafeUninitializedCapacity: n) { out, count in
                    for i in 0..<n { out[i] = Float(Int64(littleEndian: p.loadUnaligned(fromByteOffset: 8 * i, as: Int64.self))) }
                    count = n
                }
            case .rgb8, .rgba8, .rgb16, .rgba16:
                return nil
            }
        }
    }

    package func readPattern(_ view: LoadView, ry: Int, rx: Int) throws -> [Float] {
        guard ry >= 0, ry < view.descriptor.ry, rx >= 0, rx < view.descriptor.rx else {
            throw H5Error.readFailed("scan position (\(ry), \(rx)) is outside the loaded view")
        }
        return try read(view, scanY: ry..<(ry + 1), scanX: rx..<(rx + 1),
                        label: "pattern at ry \(ry), rx \(rx)")
    }

    /// Read an entire view scan row: all view Rx patterns for a fixed view Ry,
    /// flattened as [Rx * Qy * Qx]. This remains a useful compatibility
    /// primitive; bounded whole-scan consumers prefer `readScanTile`.
    package func readScanRow(_ view: LoadView, ry: Int) throws -> [Float] {
        guard ry >= 0, ry < view.descriptor.ry else {
            throw H5Error.readFailed("scan row \(ry) is outside the loaded view")
        }
        return try read(view, scanY: ry..<(ry + 1), scanX: 0..<view.descriptor.rx,
                        label: "scan row \(ry)")
    }

    package func readScanTile(_ view: LoadView,
                      yRange: Range<Int>) throws -> FourDScanTile {
        guard yRange.lowerBound >= 0, yRange.upperBound <= view.descriptor.ry,
              !yRange.isEmpty else {
            throw H5Error.readFailed("invalid scan tile \(yRange)")
        }
        let pixels = try read(view, scanY: yRange, scanX: 0..<view.descriptor.rx,
                              label: "scan tile \(yRange)")
        return FourDScanTile(
            yRange: yRange, scanWidth: view.descriptor.rx,
            detectorHeight: view.descriptor.qy, detectorWidth: view.descriptor.qx,
            pixels: pixels
        )
    }

    /// Calibration from the file itself, tried in order:
    ///  1. py4DSTEM EMD calibration bundle:
    ///     <datacube-root>/metadatabundle/calibration/{Q,R}_pixel_size (+units,
    ///     QR_flip) — the exact values py4DSTEM would load.
    ///  2. EMD dim vectors dim0…dim3 beside the data (spacing = dim[1]−dim[0],
    ///     units from the dataset attribute) — generic EMD/HyperSpy fallback.
    /// Otherwise nil → manual entry in the Calibration section.
    package func pixelCalibration() -> PixelCalibration? {
        guard let dsPath = lastDatasetPath else { return nil }
        let components = dsPath.split(separator: "/").map(String.init)
        var out = PixelCalibration(rSize: nil, rUnits: nil, qSize: nil, qUnits: nil)

        // 1. py4DSTEM bundle: dataset ".../<group>/data" → "<group parent>".
        // emdfile's Metadata.to_h5 writes scalar/string entries as HDF5
        // *attributes* on the calibration group (only arrays become
        // datasets), so try the dataset form first, then the attribute form.
        if components.count >= 2 {
            let root = "/" + components.dropLast(2).joined(separator: "/")
            let cal = (root == "/" ? "" : root) + "/metadatabundle/calibration"
            func scalar(_ name: String) -> Double? {
                readScalarDouble(cal + "/" + name)
                    ?? readDoubleAttribute(name, onObjectPath: cal)
            }
            func string(_ name: String) -> String? {
                readStringDataset(cal + "/" + name)
                    ?? stringAttribute(name, onPath: cal)
            }
            out.qSize = scalar("Q_pixel_size")
            out.qUnits = string("Q_pixel_units")
            out.rSize = scalar("R_pixel_size")
            out.rUnits = string("R_pixel_units")
            out.qrFlip = readQRFlip(calibrationGroup: cal)
            // Origin (mean of the fitted per-position origins) and elliptical
            // distortion, under py4DSTEM Calibration's own key names. The full
            // per-position qx0/qy0 maps (2D array datasets) are not read here.
            out.qx0Mean = scalar("qx0_mean")
            out.qy0Mean = scalar("qy0_mean")
            // Row 29: a file ellipse with a non-positive semi-axis is refused whole.
            if let ellipse = Calibration.acceptedEllipse(
                a: scalar("a"), b: scalar("b"), theta: scalar("theta")) {
                out.ellipseA = ellipse.a
                out.ellipseB = ellipse.b
                out.ellipseTheta = ellipse.theta
            }
            out.qrRotationRad = scalar("QR_rotation")
            // ADR 040 residual: the value is passed through unchanged; only a
            // note says its sign cannot be proven (see RQRotationConvention).
            if out.qrRotationRad != nil,
               RQRotationConvention.isUnmarkedExportOfThisApp(
                   authoringProgram: stringAttribute("authoring_program", onPath: "/"),
                   convention: string("QR_rotation_convention")) {
                out.qrRotationNote = RQRotationConvention.legacyNote
            }
            out.probeSemiangle = scalar("probe_semiangle")

            // py4DSTEM Metadata writes array-valued calibration entries as
            // datasets. qx0/qy0 are shaped [R_Nx,R_Ny], the same real-space
            // order as this app's [Ry,Rx]; only their detector components are
            // swapped later at the AppState activation boundary.
            if let scanShape = lastDatasetShape.map({ Array($0.prefix(2)) }),
               let qx0 = readDoubleMatrix(cal + "/qx0", expectedShape: scanShape),
               let qy0 = readDoubleMatrix(cal + "/qy0", expectedShape: scanShape) {
                let qx0Measured = readDoubleMatrix(
                    cal + "/qx0_meas", expectedShape: scanShape)?.values
                let qy0Measured = readDoubleMatrix(
                    cal + "/qy0_meas", expectedShape: scanShape)?.values
                out.originMaps = PixelOriginMaps(
                    shape: scanShape,
                    fittedQX: qx0.values,
                    fittedQY: qy0.values,
                    measuredQX: qx0Measured != nil && qy0Measured != nil ? qx0Measured : nil,
                    measuredQY: qx0Measured != nil && qy0Measured != nil ? qy0Measured : nil
                )
            }
        }

        // 2. EMD dim-vector fallback. Stored rank 4 is [Ry, Rx, Qy, Qx], so
        // dim1 = R and dim3 = Q. A promoted rank-3 array was STORED (N, Qy, Qx)
        // with dim0…dim2: its scan axis is dim0 and its detector axis dim2.
        // Reading dim1/dim3 there reported the detector spacing as the
        // real-space pixel size, in reciprocal units, and no Q at all (Gate B
        // refuter, 2026-09-04; pinned by `datacube-discovery-test` c4).
        if out.rSize == nil || out.qSize == nil {
            let parent = "/" + components.dropLast().joined(separator: "/")
            let (rIndex, qIndex) = lastStoredRank == 3 ? (0, 2) : (1, 3)
            func dim(_ i: Int) -> (size: Double, units: String?)? {
                guard let v = readDoubleVector(parent + "/dim\(i)", maxCount: 65536),
                      v.count >= 2, v[1] - v[0] > 0 else { return nil }
                return (v[1] - v[0], stringAttribute("units", onPath: parent + "/dim\(i)"))
            }
            if out.rSize == nil, let d = dim(rIndex) { out.rSize = d.size; out.rUnits = d.units }
            if out.qSize == nil, let d = dim(qIndex) { out.qSize = d.size; out.qUnits = d.units }
        }

        let hasCalibration = out.rSize != nil || out.qSize != nil
            || out.qrFlip != nil || out.qx0Mean != nil || out.qy0Mean != nil
            || out.ellipseA != nil || out.ellipseB != nil || out.ellipseTheta != nil
            || out.qrRotationRad != nil || out.probeSemiangle != nil
            || out.originMaps != nil
        return hasCalibration ? out : nil
    }

    // MARK: Small typed readers (calibration metadata)

    /// QR_flip: h5py stores Python bools as an int8-based enum {FALSE, TRUE}, which `HDF5Reader` refuses by name (`enum`) and which
    /// libhdf5 converts to integer memory types but not to double — both dataset and attribute reads go through an int (py4DSTEM
    /// 0.14 writes it as a bool-enum scalar DATASET). `HDF5Datacube.calibration` would read it but refuses a file whose dim
    /// vectors are not uniform, which this reader accepts, so the integer read is `HDF5LegacyProbe`'s.
    private func readQRFlip(calibrationGroup cal: String) -> Bool? {
        HDF5LegacyProbe.integerScalar(filePath: filePath, path: cal + "/QR_flip", attribute: nil).map { $0 != 0 }
            ?? readScalarDouble(cal + "/QR_flip").map { $0 > 0.5 }
            ?? HDF5LegacyProbe.integerScalar(filePath: filePath, path: cal, attribute: "QR_flip").map { $0 != 0 }
    }

    private func readScalarDouble(_ path: String) -> Double? {
        readDoubleVector(path, maxCount: 1)?.first
    }

    /// A numeric dataset of 1…`maxCount` elements, any rank, as Double.
    private func readDoubleVector(_ path: String, maxCount: Int) -> [Double]? {
        guard let info = try? reader.datasetInfo(path), case .numeric = info.type,
              let count = try? FormatoArray.elementCount(info.shape), count >= 1, count <= maxCount,
              let array = try? reader.readDataset(path, maximumBytes: Int.max) else { return nil }
        return array.doubles()
    }

    /// Read a finite rank-2 double-convertible dataset with an exact shape.
    private func readDoubleMatrix(_ path: String,
                                  expectedShape: [Int]) -> (shape: [Int], values: [Double])? {
        guard expectedShape.count == 2, expectedShape.allSatisfy({ $0 > 0 }) else { return nil }
        guard let info = try? reader.datasetInfo(path), case .numeric = info.type,
              info.shape == expectedShape,
              let array = try? reader.readDataset(path, maximumBytes: Int.max) else { return nil }
        let values = array.doubles()
        guard values.allSatisfy(\.isFinite) else { return nil }
        return (info.shape, values)
    }

    /// Read a 1-element string dataset (variable- or fixed-length).
    private func readStringDataset(_ path: String) -> String? {
        guard let info = try? reader.datasetInfo(path), case .string = info.type,
              (try? FormatoArray.elementCount(info.shape)) == 1,
              let strings = try? reader.readStrings(path, maximumStringBytes: 4095), strings.count == 1 else { return nil }
        return strings[0]
    }

    /// Read a string attribute on the object at `path`; nil unless it holds exactly one string.
    private func stringAttribute(_ name: String, onPath path: String) -> String? {
        switch try? reader.attribute(name, of: path) {
        case .text(let text)?: return text
        case .texts(let texts)? where texts.count == 1: return texts[0]
        default: return nil
        }
    }

    package func readDoubleAttribute(_ name: String, onObjectPath path: String = "/") -> Double? {
        switch try? reader.attribute(name, of: path) {
        case .real(let value)?: return value
        case .integer(let value)?: return Double(value)
        case .reals(let values)? where values.count == 1: return values[0]
        case .integers(let values)? where values.count == 1: return Double(values[0])
        default: return nil
        }
    }
}

/// What `HDF5Reader` does not read, through the library it already loaded (`dlopen` of the kit's candidates, in the kit's order, returns
/// the image the kit maps and never a second copy: `HDF5SingleLibraryTests`): the chunk shape of a dataset (`HDF5DatasetInfo` has none; the
/// inspector shows it and `loadPushdown` judges a crop by it), and a scalar dataset or attribute converted to a native int (h5py's
/// bool enum, which `HDF5Reader` refuses as `enum`).
// delete at FormatoKit 0.6: HDF5DatasetInfo.chunkShape and an enum/bool read in HDF5Reader (kit asks)
private nonisolated enum HDF5LegacyProbe {
    private typealias Open = @convention(c) () -> herr_t
    private typealias SetAuto = @convention(c) (hid_t, UnsafeRawPointer?, UnsafeMutableRawPointer?) -> herr_t
    private typealias FileOpen = @convention(c) (UnsafePointer<CChar>?, UInt32, hid_t) -> hid_t
    private typealias ByName = @convention(c) (hid_t, UnsafePointer<CChar>?, hid_t) -> hid_t
    private typealias Handle = @convention(c) (hid_t) -> hid_t
    private typealias Close = @convention(c) (hid_t) -> herr_t
    private typealias Layout = @convention(c) (hid_t) -> Int32
    private typealias Chunk = @convention(c) (hid_t, Int32, UnsafeMutablePointer<hsize_t>?) -> Int32
    private typealias Points = @convention(c) (hid_t) -> Int64
    private typealias DatasetRead = @convention(c) (hid_t, hid_t, hid_t, hid_t, hid_t, UnsafeMutableRawPointer?) -> herr_t
    private typealias AttributeRead = @convention(c) (hid_t, hid_t, UnsafeMutableRawPointer?) -> herr_t

    private static func library() -> UnsafeMutableRawPointer? {
        let candidates = [ProcessInfo.processInfo.environment["FORMATO_HDF5_PATH"],
            Bundle.main.privateFrameworksURL?.appendingPathComponent("libhdf5.dylib").path,
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("../Frameworks/libhdf5.dylib").standardized.path,
            FormatoHDF5Library.bundledLibraryPath, "libhdf5.dylib"].compactMap { $0 }
        for path in candidates { if let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) { return handle } }
        return nil
    }

    /// Opens the file read-only and calls `body` with the library, the file and a symbol lookup, all under `HDF5Serial`.
    private static func withFile<T>(_ filePath: String, _ body: (UnsafeMutableRawPointer, hid_t) -> T?) -> T? {
        HDF5Serial.run {
            guard let lib = library(), let open = dlsym(lib, "H5open"), let setAuto = dlsym(lib, "H5Eset_auto2"),
                  let fileOpen = dlsym(lib, "H5Fopen"), let fileClose = dlsym(lib, "H5Fclose") else { return nil }
            _ = unsafeBitCast(open, to: Open.self)()
            _ = unsafeBitCast(setAuto, to: SetAuto.self)(0, nil, nil)
            let file = filePath.withCString { unsafeBitCast(fileOpen, to: FileOpen.self)($0, 0, 0) }
            guard file >= 0 else { return nil }
            defer { _ = unsafeBitCast(fileClose, to: Close.self)(file) }
            return body(lib, file)
        }
    }

    static func chunkShape(filePath: String, datasetPath: String, rank: Int) -> [Int]? {
        withFile(filePath) { lib, file in
            func symbol<T>(_ name: String, as type: T.Type) -> T? { dlsym(lib, name).map { unsafeBitCast($0, to: type) } }
            guard let datasetOpen = symbol("H5Dopen2", as: ByName.self), let datasetClose = symbol("H5Dclose", as: Close.self),
                  let createPlist = symbol("H5Dget_create_plist", as: Handle.self), let plistClose = symbol("H5Pclose", as: Close.self),
                  let layout = symbol("H5Pget_layout", as: Layout.self), let chunk = symbol("H5Pget_chunk", as: Chunk.self)
            else { return nil }
            let dataset = datasetPath.withCString { datasetOpen(file, $0, 0) }
            guard dataset >= 0 else { return nil }
            defer { _ = datasetClose(dataset) }
            let plist = createPlist(dataset)
            guard plist >= 0 else { return nil }
            defer { _ = plistClose(plist) }
            guard layout(plist) == 2 else { return nil }     // H5D_CHUNKED
            var dimensions = [hsize_t](repeating: 0, count: rank)
            let count = dimensions.withUnsafeMutableBufferPointer { Int(chunk(plist, Int32(rank), $0.baseAddress)) }
            return count > 0 ? dimensions.prefix(count).map(Int.init) : nil
        }
    }

    /// The one element of the dataset at `path` (or, with `attribute`, of that attribute on the object at `path`) converted by libhdf5
    /// to a native int (32-bit); nil when absent, not one element, or not convertible.
    static func integerScalar(filePath: String, path: String, attribute: String?) -> Int? {
        withFile(filePath) { lib, file in
            func symbol<T>(_ name: String, as type: T.Type) -> T? { dlsym(lib, name).map { unsafeBitCast($0, to: type) } }
            guard let nativeInt = dlsym(lib, "H5T_NATIVE_INT_g")?.assumingMemoryBound(to: hid_t.self).pointee,
                  let points = symbol("H5Sget_simple_extent_npoints", as: Points.self),
                  let spaceClose = symbol("H5Sclose", as: Close.self) else { return nil }
            var value: Int32 = 0
            if let attribute {
                guard let objectOpen = symbol("H5Oopen", as: ByName.self), let objectClose = symbol("H5Oclose", as: Close.self),
                      let attributeOpen = symbol("H5Aopen", as: ByName.self), let attributeClose = symbol("H5Aclose", as: Close.self),
                      let attributeSpace = symbol("H5Aget_space", as: Handle.self),
                      let attributeRead = symbol("H5Aread", as: AttributeRead.self) else { return nil }
                let object = path.withCString { objectOpen(file, $0, 0) }
                guard object >= 0 else { return nil }
                defer { _ = objectClose(object) }
                let handle = attribute.withCString { attributeOpen(object, $0, 0) }
                guard handle >= 0 else { return nil }
                defer { _ = attributeClose(handle) }
                let space = attributeSpace(handle)
                guard space >= 0 else { return nil }
                defer { _ = spaceClose(space) }
                guard points(space) == 1 else { return nil }
                let status = withUnsafeMutableBytes(of: &value) { attributeRead(handle, nativeInt, $0.baseAddress) }
                return status >= 0 ? Int(value) : nil
            }
            guard let datasetOpen = symbol("H5Dopen2", as: ByName.self), let datasetClose = symbol("H5Dclose", as: Close.self),
                  let datasetSpace = symbol("H5Dget_space", as: Handle.self),
                  let datasetRead = symbol("H5Dread", as: DatasetRead.self) else { return nil }
            let dataset = path.withCString { datasetOpen(file, $0, 0) }
            guard dataset >= 0 else { return nil }
            defer { _ = datasetClose(dataset) }
            let space = datasetSpace(dataset)
            guard space >= 0 else { return nil }
            defer { _ = spaceClose(space) }
            guard points(space) == 1 else { return nil }
            let status = withUnsafeMutableBytes(of: &value) { datasetRead(dataset, nativeInt, 0, 0, 0, $0.baseAddress) }
            return status >= 0 ? Int(value) : nil
        }
    }
}
// MARK: Discovery rule (pure, unit-tested without HDF5)

extension H5Reader {
    /// What discovery knows about a node before judging it. The reader fills
    /// it from the file; the rule below is pure so the unit target can pin it.
    package nonisolated struct DatacubeCandidate: Sendable {
        package let path: String
        package let storedRank: Int
        /// `name` attribute of the dim dataset for the LAST axis, `dim{rank-1}`.
        package let lastAxisName: String?
        /// `units` attribute of the data itself.
        package let units: String?
        /// Legacy py4DSTEM v0.12 numbers dims from 1 and keeps a slice stack's
        /// labels in a STRING-typed `dim{rank}` beside the data; true when
        /// that dataset exists and is string-typed.
        package let legacySliceLabels: Bool

        package nonisolated init(path: String, storedRank: Int, lastAxisName: String?, units: String?,
                                 legacySliceLabels: Bool = false) {
            self.path = path
            self.storedRank = storedRank
            self.lastAxisName = lastAxisName
            self.units = units
            self.legacySliceLabels = legacySliceLabels
        }
    }

    /// Why a dataset of rank 3 or 4 is NOT a datacube, from what the file says
    /// about itself; nil when nothing says so. Three signals, each one a
    /// known writer's own mark: emdfile / py4DSTEM put `_labels_` on the dim
    /// of a stack axis (verifiable in the pinned tree only under
    /// `io/legacy/legacy13`, `v13_emd_classes/io.py:390,429`; 0.14.19's live
    /// writer is the unvendored `emdfile` package); legacy v0.12 keeps a slice
    /// stack's labels as strings in a 1-based `dim{rank}` (`read_v0_12.py:365`);
    /// and this app's sidecar writer names the channel axis `RGBA` and stamps
    /// `rgba8` on the pixels. NOT a size heuristic, on purpose — and the reason
    /// is the rank-3 contract, not a fixture: an unlabelled rank-3 array with
    /// nothing better in the file opens as one scan row (`load-spec-test`), so
    /// a floor on a promoted rank-3's last axis would be a magic number tied to
    /// one channel count. (A floor scoped to stored rank 3 WOULD leave every
    /// checked-in rank-4 fixture and real file untouched — the Gate B refuter
    /// built one; it is declined, not impossible.) // 2026-09-04
    package nonisolated static func datacubeRejection(of candidate: DatacubeCandidate) -> String? {
        if candidate.lastAxisName == "_labels_" {
            return "a stacked EMD array: its last axis is labelled slices, not a detector"
        }
        if candidate.legacySliceLabels {
            return "a legacy py4DSTEM v0.12 slice stack: its last dim holds slice labels, not a detector axis"
        }
        if candidate.lastAxisName == "RGBA" || candidate.units == "rgba8" {
            return "an RGBA result map, not a datacube"
        }
        return nil
    }
}
