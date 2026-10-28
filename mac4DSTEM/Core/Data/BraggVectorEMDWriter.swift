import Foundation
import FormatoCore
import FormatoHDF5
import SpectroCore

/// Writes the detected peak grid as a py4DSTEM 0.14 / EMD 1.0 BraggVectors
/// sidecar. The source dataset is never opened for writing. Publication is an
/// atomic rename of a completed sibling temporary file, so cancellation or an
/// HDF5 failure cannot leave a partial result at the requested destination.
package nonisolated enum BraggVectorEMDWriter {
    static let rootPath = "/" + SessionSidecarFormat.rootGroupName
    // Shared with H5Reader's sidecar recognition via SessionSidecarFormat
    // (SpectroKit's HDF5Types.swift) — one constant, both sides. // v2 S4
    static let schemaAttribute = SessionSidecarFormat.schemaAttribute
    static let resultNodesAttribute = "mac4dstem_result_nodes"
    static let currentResultAttribute = "mac4dstem_current_result"
    /// The `LoadSpecification` a session's products were computed under, as
    /// JSON. Absent on a full-extent session — the identity, so a sidecar
    /// written before L6 reads as "the whole file", which is what it was.
    static let loadSpecificationAttribute = "mac4dstem_load_specification"
    /// How an exported reduced DataCube was derived from its source
    /// (`DataCubeDerivation`, v2 S10). On the exported file's `datacube_root`
    /// — deliberately NOT `loadSpecificationAttribute`, whose meaning is
    /// "reopen the SOURCE this way" on a sidecar; this one means "this file's
    /// pixels came from there" and instructs nothing.
    static let derivationAttribute = "mac4dstem_derivation"
    static let minimumReaderAttribute = SessionSidecarFormat.minimumReaderAttribute
    static let replayRecordAttribute = SessionSidecarFormat.replayRecordAttribute
    static let lineageAttribute = SessionSidecarFormat.lineageAttribute
    /// Why the last write left the lineage out, or nil when it wrote it (or had
    /// none). Written inside `writeFile` and read by `takeLineageOmission`,
    /// both under `HDF5Serial` — the lock every sidecar write already holds.
    nonisolated(unsafe) static var lineageOmission: String?

    /// The reason the most recent sidecar write did not carry the lineage, once:
    /// the caller logs it. Nil when the lineage was written, or there was none.
    package static func takeLineageOmission() -> String? {
        HDF5Serial.run {
            defer { lineageOmission = nil }
            return lineageOmission
        }
    }
    /// The hand-clicked disk-centre labels (C7 session 4, 2026-09-08), as the
    /// same JSON archived `tools/disk-detector/label_centres.py` writes — one
    /// attribute on the session root, beside calibration. Additive content,
    /// like the replay record: absent on a file that predates it, and a
    /// calibration save with nothing new to say about labels must carry the
    /// existing value forward rather than erase it (see `writeFile`'s
    /// `preservedLabelsJSON`).
    static let diskCentreLabelsAttribute = "mac4dstem_disk_centre_labels"
    /// Derived, never a literal: "5" famously stayed put across a format
    /// addition (2026-08-18), which is what made the stamp meaningless.
    /// `SessionSidecarFormat.currentSchema` is the one place the number
    /// moves. // v2 S5
    static let sessionSchemaVersion = String(SessionSidecarFormat.currentSchema)

    /// The OLDEST schema a reader may implement and still interpret a file
    /// with this specification without misreading it. Additive content (the
    /// replay record) does not raise it; a reduced specification does —
    /// ignoring one restores scan-indexed results at wrong positions (the
    /// docs/v2-release.md §5 evidence for the marker). // v2 S5
    package static func minimumReaderSchema(for specification: LoadSpecification?) -> Int {
        (specification == nil || specification?.isFullExtent == true) ? 5 : 6
    }

    package enum WriterError: LocalizedError {
        case cancelled
        case invalidDimensions(String)
        /// The hot-pixel filter met a NaN or infinite pixel (or threshold); CuboCore's filter refuses them.
        case hotPixelFilterNeedsFinitePixels
        case libraryUnavailable(String)
        case hdf5(String)
        case publishFailed(String)
        /// The file's minimum-reader marker demands a schema newer than this
        /// build understands. A REFUSAL, never a partial restore: the marker
        /// exists because a v1.0.0 build silently ignored the specification
        /// attribute and restored results at wrong positions — worse than
        /// "cannot read" (docs/v2-release.md §5). // v2 S5
        case sidecarRequiresNewerReader(minimum: Int, supported: Int)
        /// An attribute EXISTS on the sidecar and cannot be decoded. A
        /// refusal, never a silent nil: a mangled specification attribute
        /// that reads as "no crop recorded" reopens a cropped session at
        /// full extent without a word — the exact misread the attribute
        /// exists to prevent — and a mangled recipe reads as "no recipe".
        /// // v2 S7
        case malformedAttribute(name: String)

        package var errorDescription: String? {
            switch self {
            case .cancelled:
                return "The sidecar operation was cancelled."
            case .hotPixelFilterNeedsFinitePixels:
                return "The hot-pixel filter cannot run: the exported pixels include a value that is not finite (NaN or infinity). "
                    + "Switch the hot-pixel filter off or crop away non-finite pixels."
            case .invalidDimensions(let detail):
                return "Cannot write or load the sidecar: \(detail)"
            case .libraryUnavailable(let detail):
                return "Could not load the bundled HDF5 library: \(detail)"
            case .hdf5(let operation):
                // Not "export failed": the same case is raised on the sidecar
                // *read* path, where the 2026-08-18 restore failure reported an
                // export that was never attempted (S1).
                return "HDF5 failed while \(operation)."
            case .publishFailed(let detail):
                return "Could not publish the completed sidecar: \(detail)"
            case .sidecarRequiresNewerReader(let minimum, let supported):
                return "This session sidecar requires mac4DSTEM session schema "
                    + "\(minimum) or newer to read safely; this build supports "
                    + "\(supported). It was probably written by a newer mac4DSTEM — "
                    + "nothing was restored, so nothing can be misread."
            case .malformedAttribute(let name):
                return "The session sidecar's \(name) attribute exists but "
                    + "could not be decoded — the file may be damaged. "
                    + "Nothing was restored, so nothing can be misread."
            }
        }
    }

    /// What a kit write (`HDF5NewFile.write`, `EMDDatacubeWriter`) threw, as this writer's error: the app's own errors and a cancel pass
    /// through, a refusal to replace the source or a failed publish is `publishFailed`, the rest `hdf5` with the reason the kit gives
    /// (libhdf5's, or the system's), so a failure is never only "it failed" (S1, 2026-08-18).
    static func writeFailure(_ operation: String, _ error: Error) -> Error {
        switch error {
        case is WriterError: return error
        case is FormatoCancelled: return WriterError.cancelled
        case HDF5FileError.library(let detail): return WriterError.libraryUnavailable(detail)
        case HDF5FileError.destinationIsSource: return WriterError.publishFailed("Choose a different file: the source is never changed.")
        case HDF5FileError.cannotWrite(let what, let detail) where what == "publishing the file":
            return WriterError.publishFailed(detail)
        default: return WriterError.hdf5("\(operation) — HDF5 reported: \(error.localizedDescription)")
        }
    }

    // try? OK: serializing a [String: String] that
    // `isValidJSONObject` just accepted cannot fail; the guard is belt and
    // braces around an unreachable branch, and nil means "write no
    // provenance attribute", which reads back as an absent one.
    static func encodeProvenance(_ values: [String: String]) -> String? {
        guard !values.isEmpty,
              JSONSerialization.isValidJSONObject(values),
              let data = try? JSONSerialization.data(
                withJSONObject: values, options: [.sortedKeys]
              ) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // try? accepted with a stated limit: a malformed
    // provenance attribute decodes as EMPTY — visibly absent labels, which a
    // reader can see and question. This is the opposite shape from the
    // specification/recipe attributes above, where absent has a load-bearing
    // meaning ("full extent" / "no recipe") and malformed must therefore
    // refuse (`WriterError.malformedAttribute`); absent provenance asserts
    // nothing.
    static func decodeProvenance(_ value: String?) -> [String: String] {
        guard let value, let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: String] else { return [:] }
        return dictionary
    }

    /// Publish several related scalar fields as sibling EMD RealSlice nodes in
    /// one atomic file. This is used for scientifically coherent strain and
    /// orientation bundles; a cancelled or failed write never exposes a
    /// partial collection.
    package static func writeScientificBundle(
        maps: [ScalarResultMap], calibration: PixelCalibration, to destination: URL,
        sourcePath: String? = nil,
        cancellation: AnalysisCancellationToken? = nil
    ) throws {
        HDF5Serial.acquire(); defer { HDF5Serial.release() }
        // Defence in depth (review 2026-10-02 b5/e1): the rename below replaces the destination — never the source
        // dataset or its sidecar. Callers that know the source pass it; the panel-level check is the first line.
        if let sourcePath, let line = exportDestinationRefusal(destination, sourcePath: sourcePath) {
            throw WriterError.publishFailed(line)
        }
        guard !maps.isEmpty else {
            throw WriterError.invalidDimensions("a scientific bundle needs at least one field")
        }
        let shape = (maps[0].width, maps[0].height)
        guard shape.0 > 0, shape.1 > 0,
              maps.allSatisfy({ $0.width == shape.0 && $0.height == shape.1
                  && $0.pixels.count == shape.0 * shape.1 }) else {
            throw WriterError.invalidDimensions("bundle fields must share one non-empty shape")
        }
        guard Set(maps.map(\.kind)).count == maps.count else {
            throw WriterError.invalidDimensions("bundle field kinds must be unique")
        }
        try checkCancellation(cancellation)
        do {
            try HDF5NewFile.write(to: destination, sourcePath: sourcePath) { session in
                try session.writeEMDFileHeader(EMDFileHeader(authoringProgram: "mac4DSTEM", authoringUser: nil, uuid: nil))
                try session.createEMDRoot("scientific_bundle_root", attributes: [
                    "mac4dstem_bundle_schema": .text("1"),
                    "mac4dstem_bundle_fields": .text(maps.map(\.kind).joined(separator: "\n")),
                ])
                try session.writeEMDCalibration(emdCalibration(calibration), inRoot: "/scientific_bundle_root", booleanStorage: .uint8)
                for map in maps {
                    try checkCancellation(cancellation)
                    try session.writeEMDScalarMap(scalarEMDMap(map, nodeName: resultNodeName(forKind: map.kind), calibration: calibration),
                                                  inRoot: "/scientific_bundle_root")
                }
                try checkCancellation(cancellation)
            }
        } catch {
            throw writeFailure("writing the scientific bundle", error)
        }
    }

    /// Stable discoverable companion path used for automatic reload.
    package static func sessionSidecarURL(forSourcePath path: String) -> URL {
        let source = URL(fileURLWithPath: path)
        let stem = source.deletingPathExtension().lastPathComponent
        return source.deletingLastPathComponent()
            .appendingPathComponent(stem + SessionSidecarFormat.nameSuffix, isDirectory: false)
    }

    /// `qHeight` is the detector row count and becomes py4DSTEM Qshape[0];
    /// `qWidth` is the detector column count and becomes Qshape[1].
    package static func write(
        vectors: BraggVectors,
        qWidth: Int,
        qHeight: Int,
        calibration: PixelCalibration,
        to destination: URL,
        cancellation: AnalysisCancellationToken? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws {
        HDF5Serial.acquire(); defer { HDF5Serial.release() }
        try validate(vectors: vectors, qWidth: qWidth, qHeight: qHeight)
        try publish(vectors: vectors, map: nil, rgbaMap: nil,
                    qWidth: qWidth, qHeight: qHeight,
                    calibration: calibration, preserving: nil, to: destination,
                    cancellation: cancellation, progress: progress)
    }

    /// One file under two spellings (a symlink, a case-differing path): by file identity, never by path string.
    package nonisolated static func isSameFile(_ a: URL, _ b: URL) -> Bool {
        let ra = a.standardizedFileURL.resolvingSymlinksInPath(), rb = b.standardizedFileURL.resolvingSymlinksInPath()
        if ra == rb { return true }
        if let x = try? ra.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier,
           let y = try? rb.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier,
           x.isEqual(y) { return true }
        return false
    }

    /// Why a Preprocess export may not publish to `destination`: it is the source file or that source's session
    /// sidecar, and the publish renames over it. nil when the destination is safe.
    package nonisolated static func exportDestinationRefusal(_ destination: URL, sourcePath: String) -> String? {
        let source = URL(fileURLWithPath: sourcePath)
        if isSameFile(destination, source) || isSameFile(destination, sessionSidecarURL(forSourcePath: sourcePath)) {
            return "Choose a different file: the source is never changed."
        }
        return nil
    }

    /// Add or replace the stable scalar result in a session sidecar. If the
    /// existing sidecar contains BraggVectors and no new vectors are supplied,
    /// HDF5 copies that object into the new temporary file before publication.
    package static func mergeResultMap(
        _ map: ScalarResultMap,
        vectors: BraggVectors?,
        qWidth: Int,
        qHeight: Int,
        calibration: PixelCalibration,
        to destination: URL,
        loadSpecification: LoadSpecification? = nil,
        replayRecord: SessionReplayRecord? = nil,
        cancellation: AnalysisCancellationToken? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws {
        HDF5Serial.acquire(); defer { HDF5Serial.release() }
        guard map.width > 0, map.height > 0,
              map.pixels.count == map.width * map.height,
              map.pixelSizeRow == nil
                || (map.pixelSizeRow!.isFinite && map.pixelSizeRow! > 0),
              map.pixelSizeColumn == nil
                || (map.pixelSizeColumn!.isFinite && map.pixelSizeColumn! > 0) else {
            throw WriterError.invalidDimensions("the scalar result map is inconsistent")
        }
        if let vectors { try validate(vectors: vectors, qWidth: qWidth, qHeight: qHeight) }
        guard qWidth > 0, qHeight > 0 else {
            throw WriterError.invalidDimensions("the diffraction shape must be positive")
        }
        let existing = FileManager.default.fileExists(atPath: destination.path)
            ? destination : nil
        // The specification is threaded on EVERY session rewrite, not only the
        // calibration save: the writer rebuilds the whole file, so a result
        // save that omitted it silently ERASED the crop attribute — a reopen
        // then restored results against the full extent (found by S5). // v2 S5
        try publish(vectors: vectors, map: map, rgbaMap: nil,
                    qWidth: qWidth, qHeight: qHeight,
                    calibration: calibration, preserving: existing, to: destination,
                    loadSpecification: loadSpecification, replayRecord: replayRecord,
                    cancellation: cancellation, progress: progress)
    }

    package static func mergeRGBAResultMap(
        _ map: RGBAResultMap,
        vectors: BraggVectors?,
        qWidth: Int,
        qHeight: Int,
        calibration: PixelCalibration,
        to destination: URL,
        loadSpecification: LoadSpecification? = nil,
        replayRecord: SessionReplayRecord? = nil,
        cancellation: AnalysisCancellationToken? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws {
        HDF5Serial.acquire(); defer { HDF5Serial.release() }
        guard map.width > 0, map.height > 0,
              map.rgba.count == map.width * map.height * 4 else {
            throw WriterError.invalidDimensions("the RGBA result map is inconsistent")
        }
        if let vectors { try validate(vectors: vectors, qWidth: qWidth, qHeight: qHeight) }
        guard qWidth > 0, qHeight > 0 else {
            throw WriterError.invalidDimensions("the diffraction shape must be positive")
        }
        let existing = FileManager.default.fileExists(atPath: destination.path)
            ? destination : nil
        // Same rule as mergeResultMap: every rewrite restates the view. // v2 S5
        try publish(vectors: vectors, map: nil, rgbaMap: map,
                    qWidth: qWidth, qHeight: qHeight,
                    calibration: calibration, preserving: existing, to: destination,
                    loadSpecification: loadSpecification, replayRecord: replayRecord,
                    cancellation: cancellation, progress: progress)
    }

    /// Atomically replace the session calibration while preserving every
    /// supported result object already present in the companion file.
    package static func mergeCalibration(
        _ calibration: PixelCalibration,
        qWidth: Int,
        qHeight: Int,
        to destination: URL,
        loadSpecification: LoadSpecification? = nil,
        replayRecord: SessionReplayRecord? = nil,
        // C7 session 4: nil PRESERVES whatever the sidecar already holds
        // under `diskCentreLabelsAttribute` (this writer rebuilds the file on
        // every rewrite, so "say nothing" must mean "carry it forward," the
        // same rule `replayRecord` already follows two lines up) — a
        // calibration save must never be the thing that erases hand-clicked
        // labels. A non-nil value replaces it.
        diskCentreLabelsJSON: String? = nil,
        supportedSchema: Int = SessionSidecarFormat.currentSchema,
        cancellation: AnalysisCancellationToken? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws {
        HDF5Serial.acquire(); defer { HDF5Serial.release() }
        guard qWidth > 0, qHeight > 0 else {
            throw WriterError.invalidDimensions("the diffraction shape must be positive")
        }
        let existing = FileManager.default.fileExists(atPath: destination.path)
            ? destination : nil
        // `supportedSchema` is the same documented test seam as on
        // `loadSession`: the write-side refusal is only exercisable against a
        // real file by lowering what the "build" supports. // v2 S5
        try publish(vectors: nil, map: nil, rgbaMap: nil,
                    qWidth: qWidth, qHeight: qHeight,
                    calibration: calibration, preserving: existing, to: destination,
                    loadSpecification: loadSpecification, replayRecord: replayRecord,
                    diskCentreLabelsJSON: diskCentreLabelsJSON,
                    supportedSchema: supportedSchema,
                    cancellation: cancellation, progress: progress)
    }

    /// Atomically remove one named result while preserving calibration,
    /// BraggVectors, and every other supported scalar/RGBA result.
    package static func removeResult(
        kind: String,
        qWidth: Int,
        qHeight: Int,
        calibration: PixelCalibration,
        from destination: URL,
        loadSpecification: LoadSpecification? = nil,
        replayRecord: SessionReplayRecord? = nil,
        cancellation: AnalysisCancellationToken? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws {
        HDF5Serial.acquire(); defer { HDF5Serial.release() }
        guard qWidth > 0, qHeight > 0,
              FileManager.default.fileExists(atPath: destination.path) else {
            throw WriterError.invalidDimensions("the session sidecar does not exist")
        }
        // Removal also rebuilds the file — it restates the view like every
        // other rewrite, or removing a result would erase the crop. // v2 S5
        try publish(
            vectors: nil, map: nil, rgbaMap: nil,
            qWidth: qWidth, qHeight: qHeight, calibration: calibration,
            preserving: destination, to: destination, removingKind: kind,
            loadSpecification: loadSpecification, replayRecord: replayRecord,
            cancellation: cancellation, progress: progress
        )
    }

    /// Deterministic, HDF5-safe node name. The hash avoids collisions when two
    /// future result kinds sanitize to the same ASCII slug.
    package static func resultNodeName(forKind kind: String) -> String {
        var slug = ""
        var previousUnderscore = false
        for scalar in kind.lowercased().unicodeScalars {
            let value = scalar.value
            let isLetter = value >= 97 && value <= 122
            let isDigit = value >= 48 && value <= 57
            if isLetter || isDigit {
                slug.unicodeScalars.append(scalar)
                previousUnderscore = false
            } else if !previousUnderscore, !slug.isEmpty {
                slug.append("_")
                previousUnderscore = true
            }
        }
        while slug.last == "_" { slug.removeLast() }
        if slug.isEmpty { slug = "map" }

        var hash: UInt32 = 2_166_136_261
        for byte in kind.utf8 {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }
        return "result_\(slug)_\(String(format: "%08x", hash))"
    }

    static func isSafeNodeName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 160 else { return false }
        return name.unicodeScalars.allSatisfy { scalar in
            let value = scalar.value
            return (value >= 97 && value <= 122)
                || (value >= 48 && value <= 57)
                || value == 95
        }
    }

    static func validate(vectors: BraggVectors, qWidth: Int, qHeight: Int) throws {
        guard vectors.scanWidth > 0, vectors.scanHeight > 0,
              vectors.peaks.count == vectors.scanWidth * vectors.scanHeight else {
            throw WriterError.invalidDimensions("the scan grid is inconsistent")
        }
        guard qWidth > 0, qHeight > 0 else {
            throw WriterError.invalidDimensions("the diffraction shape must be positive")
        }
    }

    static func publish(
        vectors: BraggVectors?, map: ScalarResultMap?, rgbaMap: RGBAResultMap?,
        qWidth: Int, qHeight: Int,
        calibration: PixelCalibration, preserving existing: URL?, to destination: URL,
        removingKind: String? = nil,
        loadSpecification: LoadSpecification? = nil,
        replayRecord: SessionReplayRecord? = nil,
        diskCentreLabelsJSON: String? = nil,
        supportedSchema: Int = SessionSidecarFormat.currentSchema,
        cancellation: AnalysisCancellationToken?,
        progress: (@Sendable (Double) -> Void)?
    ) throws {
        try checkCancellation(cancellation)
        // The kit builds the file under a scratch name (the item-replacement folder, so the sandbox allows it and the rename stays on the
        // destination's volume) and publishes it atomically over the destination: a cancel or a failure leaves the original as it was.
        do {
            try HDF5NewFile.write(to: destination) { session in
                try writeFile(
                    into: session, vectors: vectors, map: map, rgbaMap: rgbaMap,
                    qWidth: qWidth, qHeight: qHeight,
                    calibration: calibration, preserving: existing, removingKind: removingKind,
                    loadSpecification: loadSpecification, replayRecord: replayRecord,
                    diskCentreLabelsJSON: diskCentreLabelsJSON, supportedSchema: supportedSchema,
                    cancellation: cancellation, progress: progress
                )
            }
        } catch {
            throw writeFailure("writing the session sidecar", error)
        }
    }

    static func checkCancellation(_ token: AnalysisCancellationToken?) throws {
        if token?.isCancelled == true { throw WriterError.cancelled }
    }
}
