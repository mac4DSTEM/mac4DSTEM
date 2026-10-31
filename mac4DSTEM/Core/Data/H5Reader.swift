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
    /// One `HDF5SlabReader` per dataset read so far: the file and dataset stay open across the many single-pattern reads, and its
    /// `shape` is the FILE's dims that a slab read checks its view against (released with the actor).
    private var slabReaders: [String: HDF5SlabReader] = [:]
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
        let candidates = try allLinkPaths().sorted {
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

    /// Every link of the file below the root, as absolute paths, in the order `HDF5Reader.walk` gives them: parents before members, a
    /// group entered the first time it is reached by any hard link (object identity, so an alias or a cycle is listed and not entered
    /// again) and a soft or external link listed and not followed. A file the walk cannot read lists nothing (discovery then ends in its
    /// named "no dataset" error); one over the kit's object cap is an error, not a silently shortened list.
    private func allLinkPaths() throws -> [String] {
        do {
            return try reader.walk().map(\.path)
        } catch HDF5FileError.limitExceeded(let detail) {
            throw H5Error.readFailed("link walk: \(detail)")
        } catch {
            return []
        }
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
        for path in try allLinkPaths() where !path.hasPrefix(sidecarRoot) {
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
            guard let floats = try reader.readDataset(candidate.path, maximumBytes: Int.max).float32Values() else {
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
            chunkShape: try Self.chunkShape(path) { try reader.chunkShape(of: path) },
            storedRank: rank
        )
    }

    /// The chunk shape of the dataset at `path`: nil only when the kit answers "not chunked" (contiguous or compact storage); a
    /// failed read of the layout is an error, not a quiet nil that would make the loader assume a contiguous dataset.
    package static func chunkShape(_ path: String, _ lookup: () throws -> [Int]?) throws -> [Int]? {
        do { return try lookup() } catch { throw H5Error.datasetOpenFailed(path) }
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
        let slabReader: HDF5SlabReader
        if let cached = slabReaders[path] {
            slabReader = cached
        } else {
            guard let opened = try? HDF5SlabReader(url: URL(fileURLWithPath: filePath), path: path) else { throw H5Error.datasetOpenFailed(path) }
            slabReaders[path] = opened
            slabReader = opened
        }
        let slab = try hyperslab(view, dims: slabReader.shape, scanY: scanY, scanX: scanX)
        let buffer: [Float]
        do {
            guard let floats = try slabReader.read(start: slab.start, count: slab.count).float32Values() else {
                throw H5Error.readFailed(label)
            }
            buffer = floats
        } catch {
            throw H5Error.readFailed(label)
        }
        let patternCount = buffer.count
            / max(1, (view.readDetectorCrop?.height ?? view.source.qy)
                     * (view.readDetectorCrop?.width ?? view.source.qx))
        return view.binned(buffer, patternCount: patternCount)
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
                // The origin gate's fields this app's calibrated-cube export writes as root attributes beside the maps
                // (`PixelOriginMaps.gateAttributes`). A py4DSTEM file, or an export written before 2026-10-31, has none:
                // unknown, which the gate does not refuse.
                out.originMaps?.readGateAttributes { stringAttribute($0, onPath: "/") }
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

    /// QR_flip: py4DSTEM 0.14 writes it as a bool-enum scalar DATASET (`HDF5Reader.readBooleans`; a uint8, an int or a float is read as
    /// a number and compared with 0, as libhdf5's int conversion did), older emdfile as an ATTRIBUTE of the calibration group.
    private func readQRFlip(calibrationGroup cal: String) -> Bool? {
        if let info = try? reader.datasetInfo(cal + "/QR_flip"), (try? FormatoArray.elementCount(info.shape)) == 1 {
            switch info.type {
            case .unsupported("enum"):
                return (try? reader.readBooleans(cal + "/QR_flip"))?.first
            case .numeric, .unsupported("float16"):
                // The element as libhdf5 converted it to a native int: floats truncate toward zero; "not 0" is the flag.
                if let value = (try? reader.readDataset(cal + "/QR_flip", maximumBytes: Int.max))?.doubles().first, value.isFinite {
                    return value.rounded(.towardZero) != 0
                }
            default: break
            }
        }
        switch try? reader.attribute("QR_flip", of: cal) {
        case .integer(let value)?: return value != 0
        case .integers(let values)? where values.count == 1: return values[0] != 0
        case .real(let value)?: return value.isFinite ? value.rounded(.towardZero) != 0 : nil
        case .reals(let values)? where values.count == 1: return values[0].isFinite ? values[0].rounded(.towardZero) != 0 : nil
        default: return nil    // an h5py bool attribute arrives as .integer since FormatoKit 0.8.0
        }
    }

    private func readScalarDouble(_ path: String) -> Double? {
        readDoubleVector(path, maxCount: 1)?.first
    }

    /// The values of a numeric dataset as Double (float16 included: the kit reads it as float32, exact in Double). Nil for any other type.
    private func storedDoubles(_ path: String, _ info: HDF5DatasetInfo) -> [Double]? {
        switch info.type {
        case .numeric, .unsupported("float16"):
            return (try? reader.readDataset(path, maximumBytes: Int.max))?.doubles()
        default:
            return nil
        }
    }

    /// A numeric dataset of 1…`maxCount` elements, any rank, as Double.
    private func readDoubleVector(_ path: String, maxCount: Int) -> [Double]? {
        guard let info = try? reader.datasetInfo(path),
              let count = try? FormatoArray.elementCount(info.shape), count >= 1, count <= maxCount else { return nil }
        return storedDoubles(path, info)
    }

    /// Read a finite rank-2 double-convertible dataset with an exact shape.
    private func readDoubleMatrix(_ path: String,
                                  expectedShape: [Int]) -> (shape: [Int], values: [Double])? {
        guard expectedShape.count == 2, expectedShape.allSatisfy({ $0 > 0 }) else { return nil }
        guard let info = try? reader.datasetInfo(path), info.shape == expectedShape,
              let values = storedDoubles(path, info) else { return nil }
        guard values.allSatisfy(\.isFinite) else { return nil }
        return (info.shape, values)
    }

    /// Read a 1-element string dataset (variable- or fixed-length).
    private func readStringDataset(_ path: String) -> String? {
        guard let info = try? reader.datasetInfo(path), case .string = info.type,
              (try? FormatoArray.elementCount(info.shape)) == 1,
              let strings = try? reader.readStrings(
                  path, maximumStringBytes: info.type == .string(variableLength: true) ? HDF5Reader.defaultMaximumStringBytes : 4095),
              strings.count == 1 else { return nil }
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

    package func readStringAttribute(_ name: String, onObjectPath path: String = "/") -> String? {
        stringAttribute(name, onPath: path)
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
