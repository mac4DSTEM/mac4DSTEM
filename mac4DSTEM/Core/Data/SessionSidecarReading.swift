//
//  SessionSidecarReading.swift
//  Role: read a session sidecar (`<source>.mac4dstem.h5`) back: the minimum-reader gate, the inventory, the calibration, the result
//        maps, the peak grid, the replay record, the lineage and the labels. Every read is FormatoKit's `HDF5Reader` (0.5.0) or,
//        for the peak grid, `BraggVectorsEMD.read`; what the file's nodes MEAN, and the refusals worded for them, are the app's.
//        Split out of BraggVectorEMDWriter.swift (2026-10-20), which keeps the writers, the atomic publish and the
//        `mac4dstem_*` attribute names.
//

import Foundation
import FormatoCore
import FormatoHDF5
import SpectroCore

nonisolated extension BraggVectorEMDWriter {

    /// A sidecar (or bundle) file open for reading through `HDF5Reader`: each call opens the file, reads and closes it, under the one
    /// HDF5 lock. The guards of the former handle-based readers are kept, with their wording: a dataset read as a scalar holds
    /// exactly one value, a unit string is one variable-length string, an attribute is one string.
    struct SidecarFile {
        let url: URL
        let reader: HDF5Reader

        /// Opens `url`. A refusal says WHY (libhdf5's reason, or the system's for a denied read), not only that it failed: the
        /// release owner's restore failure (S1, 2026-08-18) read "HDF5 export failed while opening the session sidecar" and
        /// nothing else. `operation` names what was being done.
        init(opening url: URL, operation: String = "opening the session sidecar") throws {
            self.url = url
            do {
                reader = try HDF5Reader(url: url)
            } catch HDF5FileError.library(let detail) {
                throw WriterError.libraryUnavailable(detail)
            } catch HDF5FileError.cannotOpen(let detail), HDF5FileError.notPermitted(let detail) {
                throw WriterError.hdf5("\(operation) — HDF5 reported: \(detail)")
            } catch {
                throw WriterError.hdf5("\(operation) — HDF5 reported: \(error.localizedDescription)")
            }
        }

        /// A kit refusal as the app's `.hdf5` error for `operation`.
        static func failure(_ operation: String, _ error: Error) -> WriterError {
            if case HDF5FileError.library(let detail) = error { return .libraryUnavailable(detail) }
            return .hdf5("\(operation) — HDF5 reported: \(error.localizedDescription)")
        }

        func exists(_ path: String) -> Bool { (try? reader.exists(path)) == true }
        func isGroup(_ path: String) -> Bool { (try? reader.kind(of: path)) == .group }
        func isDataset(_ path: String) -> Bool { (try? reader.kind(of: path)) == .dataset }

        /// The names of the links of the group at `path`.
        func children(of path: String) -> [String] { (try? reader.children(of: path)) ?? [] }

        /// A string attribute: nil when absent; exactly one string, else `malformedAttribute` (an array, a number written by another
        /// tool, an enum, text that is not UTF-8 or is over 4 MiB).
        func stringAttribute(_ name: String, at path: String) throws -> String? {
            let value: HDF5AttributeValue
            do {
                value = try reader.attribute(name, of: path)
            } catch HDF5FileError.notFound {
                return nil
            } catch HDF5FileError.unsupportedType, HDF5FileError.stringTooLong, HDF5FileError.invalidUTF8,
                    HDF5FileError.limitExceeded {
                throw WriterError.malformedAttribute(name: name)
            } catch {
                throw Self.failure("reading attribute \(name)", error)
            }
            switch value {
            case .text(let text): return text
            case .texts(let texts) where texts.count == 1: return texts[0]
            default: throw WriterError.malformedAttribute(name: name)
            }
        }

        /// The scalar dataset `name` of `group`, checked for exactly one value: a foreign or hand-edited sidecar with a 3-element `a`
        /// would otherwise read as one of them (review 2026-10-02, the twin of the Qshape overrun); an empty dataset, or a NULL
        /// dataspace (h5py.Empty), would read as 0.
        private func scalarDataset(_ name: String, in group: String) throws -> (path: String, info: HDF5DatasetInfo)? {
            let path = group + "/" + name
            guard isDataset(path) else { return nil }
            let info: HDF5DatasetInfo
            do {
                info = try reader.datasetInfo(path)
            } catch HDF5FileError.unsupportedType {
                throw WriterError.hdf5("reading dataset \(name), which does not hold exactly one value")
            } catch {
                throw Self.failure("reading the shape of dataset \(name)", error)
            }
            guard (try? FormatoArray.elementCount(info.shape)) == 1 else {
                throw WriterError.hdf5("reading dataset \(name), which does not hold exactly one value")
            }
            return (path, info)
        }

        func doubleDataset(_ name: String, in group: String) throws -> Double? {
            guard let (path, info) = try scalarDataset(name, in: group) else { return nil }
            guard case .numeric = info.type else { throw WriterError.hdf5("reading dataset \(name)") }
            let value: Double
            do { value = try reader.readDataset(path).doubles()[0] } catch {
                throw Self.failure("reading dataset \(name)", error)
            }
            return value.isFinite ? value : nil
        }

        /// A Python bool: the app writes one byte; h5py writes an int8-based enum, which only libhdf5's own int conversion reads.
        func boolDataset(_ name: String, in group: String) throws -> Bool? {
            guard let (path, info) = try scalarDataset(name, in: group) else { return nil }
            switch info.type {
            case .numeric:
                do { return try reader.readDataset(path).doubles()[0] != 0 } catch {
                    throw Self.failure("reading dataset \(name)", error)
                }
            case .unsupported(let kind) where kind == "enum":
                // h5py's bool: an int8-based enum
                do { return try reader.readBooleans(path).first ?? false } catch { throw WriterError.hdf5("reading dataset \(name)") }
            default:
                throw WriterError.hdf5("reading dataset \(name)")
            }
        }

        /// One variable-length string (what the writer writes); a fixed-length string or a number is refused by name.
        func stringDataset(_ name: String, in group: String) throws -> String? {
            guard let (path, info) = try scalarDataset(name, in: group) else { return nil }
            guard case .string(variableLength: true) = info.type else {
                throw WriterError.hdf5("reading dataset \(name), which is not one variable-length string")
            }
            let strings: [String]
            do { strings = try reader.readStrings(path) } catch { throw Self.failure("reading dataset \(name)", error) }
            return strings.first ?? ""
        }

        /// A finite rank-2 dataset, as it is stored; nil when it is not rank 2, has an empty extent or holds a non-finite value.
        func doubleMatrix(_ name: String, in group: String) throws -> (shape: [Int], values: [Double])? {
            let path = group + "/" + name
            guard isDataset(path) else { return nil }
            let info: HDF5DatasetInfo
            do { info = try reader.datasetInfo(path) } catch HDF5FileError.unsupportedType { return nil } catch HDF5FileError.limitExceeded {
                return nil
            } catch { throw Self.failure("opening dataset \(name)", error) }
            guard info.shape.count == 2, info.shape.allSatisfy({ $0 > 0 }), info.shape[0] <= Int.max / info.shape[1] else { return nil }
            guard case .numeric = info.type else { throw WriterError.hdf5("reading dataset \(name)") }
            let values: [Double]
            do { values = try reader.readDataset(path).doubles() } catch { throw Self.failure("reading dataset \(name)", error) }
            guard values.allSatisfy(\.isFinite) else { return nil }
            return (info.shape, values)
        }
    }

    /// The one minimum-reader check, shared by EVERY reader that hands back
    /// session content — `loadSession` and the two direct result readers
    /// (`loadResultMap(id:)`, `loadRGBAResultMap(id:)`) — both would otherwise
    /// bypass it and restore pixel arrays from a file the gate had refused
    /// (Gate B-lite F5). Absent marker ⇒ the file predates it ⇒ readable by
    /// the rules that applied when it was written; an unparseable value is
    /// treated the same, because refusing on garbage would brick every
    /// sidecar a bit-flip touches while a newer-format file always writes a
    /// clean integer.
    static func enforceMinimumReader(_ file: SidecarFile, supportedSchema: Int) throws {
        // A marker of the wrong shape or type is garbage like any other
        // unparseable value, so it reads as absent (the rule above), not as
        // the reader's `malformedAttribute` refusal. // S5
        let markerText: String?
        do {
            markerText = try file.stringAttribute(minimumReaderAttribute, at: rootPath)
        } catch WriterError.malformedAttribute {
            markerText = nil
        }
        if let markerText,
           let minimum = Int(markerText),
           minimum > supportedSchema {
            throw WriterError.sidecarRequiresNewerReader(
                minimum: minimum, supported: supportedSchema
            )
        }
    }

    /// Opens the sidecar and its root group, or the file `loadSession` and the direct readers all start from.
    private static func openSidecar(_ url: URL) throws -> SidecarFile {
        let file = try SidecarFile(opening: url)
        guard file.isGroup(rootPath) else {
            throw WriterError.hdf5("opening the session root — HDF5 reported: there is no group \(rootPath)")
        }
        return file
    }

    /// Load the complete supported session inventory and the map recorded as
    /// current. Legacy one-slot sidecars are treated as a one-map inventory.
    ///
    /// `supportedSchema` exists so the minimum-reader refusal is testable
    /// against a REAL file through the REAL gate: a test reads a genuinely
    /// cropped sidecar as a schema-5 reader and watches the refusal fire.
    /// Production callers never pass it — the default is the build's truth.
    ///
    /// `sourcePath`: the source being opened. When given, a sidecar that belongs to another source is refused whole
    /// (`WriterError.belongsToAnotherSource`, `SessionSourceStamp.check`), before anything is restored; the inventory
    /// reads pass nil.
    package static func loadSession(
        from url: URL,
        forSourcePath sourcePath: String? = nil,
        siblings: [String]? = nil,
        supportedSchema: Int = SessionSidecarFormat.currentSchema
    ) throws -> SessionSidecarSnapshot {
        HDF5Serial.acquire(); defer { HDF5Serial.release() }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return SessionSidecarSnapshot(
                inventory: .empty, calibration: nil, currentResult: nil,
                currentRGBAResult: nil
            )
        }
        let file = try openSidecar(url)

        // THE MINIMUM-READER GATE (v2 S5), checked before anything is
        // restored. A file demanding a newer reader is refused whole, with
        // both numbers named — a partial restore is exactly the "right
        // numbers at wrong positions, no warning" failure the marker exists
        // to prevent.
        try enforceMinimumReader(file, supportedSchema: supportedSchema)

        // Which source wrote it, read like the schema stamp (garbage is absent), and checked before anything is restored.
        let sourceText: String? = (try? file.stringAttribute(sourceAttribute, at: rootPath)) ?? nil
        let source = sourceText.flatMap(SessionSourceStamp.decoded(from:))
        if let sourcePath {
            if case .refused(let sentence) = SessionSourceStamp.check(
                source, sourcePath: sourcePath, sidecarName: url.lastPathComponent,
                siblings: siblings ?? SessionSourceStamp.siblingNames(ofSourcePath: sourcePath)) {
                throw WriterError.belongsToAnotherSource(sentence)
            }
        }

        let results = try readResultDescriptors(file)
        let recordedCurrent = try file.stringAttribute(currentResultAttribute, at: rootPath)
        let currentID = recordedCurrent.flatMap { id in
            results.contains(where: { $0.id == id }) ? id : nil
        } ?? results.last?.id
        let currentDescriptor = currentID.flatMap { id in
            results.first(where: { $0.id == id })
        }
        let currentResult = try currentDescriptor.flatMap { descriptor in
            descriptor.storage == .scalarFloat32
                ? try readResultMap(file, nodeName: descriptor.id, in: rootPath)
                : nil
        }
        let currentRGBAResult = try currentDescriptor.flatMap { descriptor in
            descriptor.storage == .rgba8
                ? try readRGBAResultMap(file, nodeName: descriptor.id, in: rootPath)
                : nil
        }
        let calibration = try readCalibration(file)
        // Absent attribute ⇒ nil — nothing was recorded. Present-but-
        // undecodable ⇒ REFUSE by name (v2 S7): `.flatMap(decoded)` used to
        // collapse the two, so a mangled specification attribute read as "no
        // crop recorded" and the cropped session reopened silently at full
        // extent — the misread the attribute exists to prevent.
        let specification: LoadSpecification?
        if let json = try file.stringAttribute(loadSpecificationAttribute, at: rootPath) {
            guard let decoded = LoadSpecification.decoded(from: json) else {
                throw WriterError.malformedAttribute(name: loadSpecificationAttribute)
            }
            specification = decoded
        } else {
            specification = nil
        }
        // Absent attribute ⇒ nil record — no recipe was recorded, and the
        // snapshot says so rather than asserting an empty one. // v2 S5
        // Present-but-undecodable refuses, as above. // v2 S7
        let replay: SessionReplayRecord?
        if let json = try file.stringAttribute(replayRecordAttribute, at: rootPath) {
            guard let parsed = SessionReplayRecord.parse(json) else {
                throw WriterError.malformedAttribute(name: replayRecordAttribute)
            }
            replay = parsed
        } else {
            replay = nil
        }
        // The lineage (schema 7, ADR 047). Read only by a reader that knows
        // the attribute: `supportedSchema` below 7 models a v4.0.0 reader, which
        // ignores it — the test seam that proves a v7 file still restores there.
        // Present-but-refused ⇒ REFUSE by name (R8), like the two above. A
        // lineage whose projection differs from the record beside it is a foreign
        // or hand-edited file: read as v1, with a note, never merged (R7).
        // Absent ⇒ synthesized IN MEMORY from the record, inputs absent; this
        // function never writes.
        var lineage: SessionLineage?
        var lineageNote: String?
        if supportedSchema >= 7,
           let json = try file.stringAttribute(lineageAttribute, at: rootPath) {
            // The 4 MiB cap is checked on the string after it is read: for a
            // variable-length string HDF5 stores only a 16-byte heap id in the
            // attribute (`H5Aget_storage_size` reports 16 for a 5 MiB string,
            // measured 2026-09-30), so there is no size to check first. What
            // bounds the read is the file itself; a fixed-length string is
            // capped before it is read (`readStringAttribute`).
            switch SessionLineage.validated(json) {
            case .failure(.unsupportedVersion(let version)):
                // A NEWER lineage in a file whose minimum-reader marker says this
                // build can read it: the record beside it is complete and safe,
                // so the file reads as v1 — with a note, never a refusal.
                lineageNote = "This session's lineage is version \(version), newer than this build reads, so it is read as a record from before lineage: order only. Saving will replace it."
            case .failure:
                throw WriterError.malformedAttribute(name: lineageAttribute)
            case .success(let parsed):
                if SessionLineage.sameSteps(parsed.projection().steps, replay?.steps ?? []) {
                    lineage = parsed
                } else {
                    lineageNote = "The lineage in this session does not match its replay record, so it is read as a record from before lineage: order only, nothing merged."
                }
            }
        }
        if lineage == nil, let replay, !replay.isEmpty {
            lineage = SessionLineage.synthesized(
                from: replay, frame: SessionLineage.Frame(specification ?? .fullExtent))
        }
        let inventory = SessionSidecarInventory(
            hasSidecar: true,
            hasBraggVectors: file.exists("\(rootPath)/braggvectors"),
            hasCalibration: calibration != nil,
            results: results,
            currentResultID: currentID
        )
        // The stamp is read like the minimum-reader marker: garbage is absent.
        let schemaText: String? = (try? file.stringAttribute(schemaAttribute, at: rootPath)) ?? nil
        let schemaStamp = schemaText.flatMap { Int($0) }
        var snapshot = SessionSidecarSnapshot(
            inventory: inventory, calibration: calibration,
            currentResult: currentResult, currentRGBAResult: currentRGBAResult,
            loadSpecification: specification, schema: schemaStamp,
            replayRecord: replay,
            lineage: lineage, lineageNote: lineageNote
        )
        snapshot.source = source
        return snapshot
    }

    /// The peaks a sidecar's `braggvectors/_v_uncal` holds, with the detector
    /// shape it was written against. `vectors.detectionProvenance` carries the
    /// `mac4dstem_detection_provenance` attribute (empty when absent or
    /// undecodable — absent provenance asserts nothing, so a caller that needs
    /// it must refuse on the empty dictionary).
    package struct StoredPeakGrid: Sendable {
        package let vectors: BraggVectors
        package let detectorHeight: Int
        package let detectorWidth: Int

        package nonisolated init(vectors: BraggVectors, detectorHeight: Int, detectorWidth: Int) {
            self.vectors = vectors
            self.detectorHeight = detectorHeight
            self.detectorWidth = detectorWidth
        }
    }

    /// The read half of the peak-grid write (now FormatoKit's `writeBraggVectors`; 2026-09-28, the archived notes
    /// bragg-restore-registration-2026-09-28.md). Nil when the sidecar has no
    /// peak grid (or no `_braggvectors_shape`, which the detector shape comes
    /// from). Throws on an HDF5 failure or a non-finite peak — never a partial
    /// grid. py4DSTEM's qx is the detector ROW and qy the COLUMN; the app's
    /// `BraggPeak` is x = column, y = row, so the writer's swap is undone here
    /// (`BraggVectorsEMD.read(convention: .appImageXY)` does it).
    /// float64 → Float32 is exact for values the writer produced from Float32.
    ///
    /// STRICTER than the former reader (FormatoKit's `BraggVectorsEMD.read` does the reading): the scan shape (`Rshape`) must be
    /// present and equal the grid's dimensions, and every entry of the calibration bundle beside it must be a scalar of the kind the
    /// kit expects (a 3-element `a` refuses the GRID, where it used to be ignored — `loadSession` refuses such a file by name
    /// anyway, and the app restores through it first). A file this app wrote always satisfies both.
    package static func loadPeakGrid(
        from url: URL,
        supportedSchema: Int = SessionSidecarFormat.currentSchema
    ) throws -> StoredPeakGrid? {
        HDF5Serial.acquire(); defer { HDF5Serial.release() }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let file = try openSidecar(url)
        try enforceMinimumReader(file, supportedSchema: supportedSchema)

        let braggPath = "\(rootPath)/braggvectors"
        let dataPath = "\(braggPath)/_v_uncal/data"
        guard file.isDataset(dataPath), file.isGroup(braggPath) else { return nil }
        let provenance = decodeProvenance(try file.stringAttribute("mac4dstem_detection_provenance", at: braggPath))
        let shapePath = "\(braggPath)/metadatabundle/_braggvectors_shape/Qshape"
        guard file.isDataset(shapePath) else { return nil }
        let qShape: [Int]
        do {
            let info = try file.reader.datasetInfo(shapePath)
            // A foreign sidecar may hold more elements than two.
            guard (try? FormatoArray.elementCount(info.shape)) == 2 else {
                throw WriterError.hdf5("dataset \(shapePath) does not hold exactly 2 values")
            }
            // A hostile file can hold NaN, infinity or a number no Int holds: refused, never trapped on.
            let values = try file.reader.readDataset(shapePath).doubles()
            let whole = values.compactMap { Int(exactly: $0) }
            guard whole.count == values.count else {
                throw WriterError.hdf5("dataset \(shapePath) holds a value that is not a whole number")
            }
            qShape = whole
        } catch let error as WriterError {
            throw error
        } catch {
            throw SidecarFile.failure("reading dataset \(shapePath)", error)
        }
        guard qShape.allSatisfy({ $0 > 0 }) else { return nil }
        let dataInfo: HDF5DatasetInfo
        do { dataInfo = try file.reader.datasetInfo(dataPath) } catch { return nil }
        guard dataInfo.shape.count == 2, dataInfo.shape.allSatisfy({ $0 > 0 && $0 <= Int(Int32.max) }) else { return nil }

        let stored: BraggVectorsEMD
        do {
            stored = try BraggVectorsEMD.read(path: url.path, groupPath: braggPath, convention: .appImageXY)
        } catch {
            throw WriterError.hdf5("reading the peak grid — \(error)")
        }
        var peaks = [[BraggPeak]](repeating: [], count: stored.peaks.count)
        for (index, cell) in stored.peaks.enumerated() where !cell.isEmpty {
            // appImageXY: the kit's `qx` is the column (x) and `qy` the row (y), as the app's peak.
            peaks[index] = try cell.map { record in
                let peak = BraggPeak(x: Float(record.qx), y: Float(record.qy), intensity: Float(record.intensity))
                guard peak.x.isFinite, peak.y.isFinite, peak.intensity.isFinite else {
                    throw WriterError.hdf5("the peak grid holds a non-finite peak")
                }
                return peak
            }
        }
        return StoredPeakGrid(
            vectors: BraggVectors(
                scanWidth: stored.scan.columns, scanHeight: stored.scan.rows, peaks: peaks,
                detectionProvenance: provenance
            ),
            detectorHeight: qShape[0], detectorWidth: qShape[1]
        )
    }

    package static func loadInventory(from url: URL) throws -> SessionSidecarInventory {
        try loadSession(from: url).inventory
    }

    package static func loadResultMap(from url: URL) throws -> ScalarResultMap? {
        try loadSession(from: url).currentResult
    }

    package static func loadResultMap(
        id: String, from url: URL,
        supportedSchema: Int = SessionSidecarFormat.currentSchema
    ) throws -> ScalarResultMap? {
        HDF5Serial.acquire(); defer { HDF5Serial.release() }
        guard isSafeNodeName(id), FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let file = try openSidecar(url)
        try enforceMinimumReader(file, supportedSchema: supportedSchema)
        let descriptors = try readResultDescriptors(file)
        guard descriptors.contains(where: {
            $0.id == id && $0.storage == .scalarFloat32
        }) else { return nil }
        return try readResultMap(file, nodeName: id, in: rootPath)
    }

    package static func loadRGBAResultMap(
        id: String, from url: URL,
        supportedSchema: Int = SessionSidecarFormat.currentSchema
    ) throws -> RGBAResultMap? {
        HDF5Serial.acquire(); defer { HDF5Serial.release() }
        guard isSafeNodeName(id), FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let file = try openSidecar(url)
        try enforceMinimumReader(file, supportedSchema: supportedSchema)
        let descriptors = try readResultDescriptors(file)
        guard descriptors.contains(where: { $0.id == id && $0.storage == .rgba8 }) else {
            return nil
        }
        return try readRGBAResultMap(file, nodeName: id, in: rootPath)
    }

    /// Read one field back from a file `writeScientificBundle` wrote (the per-product data export
    /// reads through this in its test). Reuses the sidecar's own node reader, so the values, units,
    /// pixel sizes and provenance come back exactly as the session reader would give them.
    package static func loadScientificBundleField(
        kind: String, from url: URL
    ) throws -> ScalarResultMap? {
        HDF5Serial.acquire(); defer { HDF5Serial.release() }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let file = try SidecarFile(opening: url, operation: "opening the bundle file")
        guard file.isGroup("/scientific_bundle_root") else {
            throw WriterError.hdf5("opening the bundle root — HDF5 reported: there is no group /scientific_bundle_root")
        }
        return try readResultMap(file, nodeName: resultNodeName(forKind: kind), in: "/scientific_bundle_root")
    }

    /// The hand-clicked disk-centre labels JSON (C7 session 4), or nil when
    /// the sidecar carries none — a missing file, a file with no such
    /// attribute, and a file that predates this feature all read as nil, the
    /// same "absence is absence" rule `loadSession` applies to the load
    /// specification and replay record. Deliberately NOT part of
    /// `SessionSidecarSnapshot`: this attribute is read on dataset
    /// activation only, never alongside a result restore.
    package static func loadDiskCentreLabelsJSON(from url: URL) throws -> String? {
        HDF5Serial.acquire(); defer { HDF5Serial.release() }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let file = try openSidecar(url)
        try enforceMinimumReader(file, supportedSchema: SessionSidecarFormat.currentSchema)
        return try file.stringAttribute(diskCentreLabelsAttribute, at: rootPath)
    }

    static func readResultDescriptors(_ file: SidecarFile) throws -> [SessionResultDescriptor] {
        var nodeNames: [String]
        if let manifest = try file.stringAttribute(resultNodesAttribute, at: rootPath) {
            nodeNames = manifest.split(separator: "\n").map(String.init)
        } else if file.exists("\(rootPath)/\(ScalarResultMap.legacyEMDName)") {
            nodeNames = [ScalarResultMap.legacyEMDName]
        } else {
            nodeNames = []
        }

        var seen = Set<String>()
        var results: [SessionResultDescriptor] = []
        for nodeName in nodeNames where isSafeNodeName(nodeName) && seen.insert(nodeName).inserted {
            guard file.exists("\(rootPath)/\(nodeName)"),
                  let descriptor = try readResultDescriptor(file, nodeName: nodeName, in: rootPath)
            else { continue }
            results.append(descriptor)
        }
        return results
    }

    static func readCalibration(_ file: SidecarFile) throws -> PixelCalibration? {
        let group = "\(rootPath)/metadatabundle/calibration"
        guard file.isGroup(group) else { return nil }

        var calibration = PixelCalibration(
            rSize: try file.doubleDataset("R_pixel_size", in: group),
            rUnits: try file.stringDataset("R_pixel_units", in: group),
            qSize: try file.doubleDataset("Q_pixel_size", in: group),
            qUnits: try file.stringDataset("Q_pixel_units", in: group),
            qrFlip: try file.boolDataset("QR_flip", in: group)
        )
        calibration.qx0Mean = try file.doubleDataset("qx0_mean", in: group)
        calibration.qy0Mean = try file.doubleDataset("qy0_mean", in: group)
        // Row 29: a file ellipse with a non-positive semi-axis is refused whole.
        if let ellipse = Calibration.acceptedEllipse(
            a: try file.doubleDataset("a", in: group),
            b: try file.doubleDataset("b", in: group),
            theta: try file.doubleDataset("theta", in: group)) {
            calibration.ellipseA = ellipse.a
            calibration.ellipseB = ellipse.b
            calibration.ellipseTheta = ellipse.theta
        }
        calibration.qrRotationRad = try file.doubleDataset("QR_rotation", in: group)
        calibration.qrRotationConvention = try file.stringDataset("QR_rotation_convention", in: group)
        calibration.probeSemiangle = try file.doubleDataset("probe_semiangle", in: group)
        if let qx0 = try file.doubleMatrix("qx0", in: group),
           let qy0 = try file.doubleMatrix("qy0", in: group),
           qx0.shape == qy0.shape {
            let measuredQX = try file.doubleMatrix("qx0_meas", in: group)
            let measuredQY = try file.doubleMatrix("qy0_meas", in: group)
            let measuredPair = measuredQX?.shape == qx0.shape
                && measuredQY?.shape == qx0.shape
            calibration.originMaps = PixelOriginMaps(
                shape: qx0.shape,
                fittedQX: qx0.values,
                fittedQY: qy0.values,
                measuredQX: measuredPair ? measuredQX?.values : nil,
                measuredQY: measuredPair ? measuredQY?.values : nil
            )
            // The gate's window pull, beam stop, Friedel fallback residual and method. Absent on a session saved before
            // 2026-10-31, or unreadable: unknown, which the origin gate does not refuse.
            calibration.originMaps?.readGateAttributes { name in
                (try? file.stringAttribute(name, at: rootPath)) ?? nil
            }
        }
        let hasValue = calibration.rSize != nil || calibration.rUnits != nil
            || calibration.qSize != nil || calibration.qUnits != nil
            || calibration.qrFlip != nil || calibration.qx0Mean != nil
            || calibration.qy0Mean != nil || calibration.originMaps != nil
            || calibration.ellipseA != nil || calibration.ellipseB != nil
            || calibration.ellipseTheta != nil || calibration.qrRotationRad != nil
            || calibration.probeSemiangle != nil
        return hasValue ? calibration : nil
    }

    private static func readResultDescriptor(
        _ file: SidecarFile, nodeName: String, in parent: String
    ) throws -> SessionResultDescriptor? {
        let group = "\(parent)/\(nodeName)"
        guard file.isGroup(group) else { return nil }
        let storage = try file.stringAttribute("mac4dstem_storage", at: group)
            .flatMap(SessionResultStorage.init(rawValue:)) ?? .scalarFloat32
        guard let (width, height) = try readResultShape(file, group: group, storage: storage) else {
            return nil
        }
        let kind = try file.stringAttribute("mac4dstem_kind", at: group)
            ?? "unknown"
        let valueUnits = try file.stringAttribute("mac4dstem_value_units", at: group)
            ?? "intensity"
        let provenance = try dpcAngleReadState(
            kind: kind,
            valueUnits: valueUnits,
            provenance: decodeProvenance(try file.stringAttribute("mac4dstem_provenance", at: group))
        ).provenance
        return SessionResultDescriptor(
            id: nodeName,
            kind: kind,
            displayName: try file.stringAttribute("mac4dstem_display_name", at: group)
                ?? "Saved result",
            valueUnits: valueUnits,
            width: width,
            height: height,
            storage: storage,
            pixelSizeRow: try file.stringAttribute("mac4dstem_pixel_size_row", at: group).flatMap(Double.init),
            pixelSizeColumn: try file.stringAttribute("mac4dstem_pixel_size_column", at: group).flatMap(Double.init),
            pixelUnits: try file.stringAttribute("mac4dstem_pixel_units", at: group),
            provenance: provenance
        )
    }

    /// Normalizes the read-time contract for the one historical DPC encoding
    /// error. Both descriptors and decoded pixels must report the same state;
    /// the sidecar itself remains untouched until the user next saves it.
    static func dpcAngleReadState(
        kind: String, valueUnits: String, provenance: [String: String]
    ) throws -> (provenance: [String: String], needsTurnToRadianScale: Bool) {
        guard kind == "dpc_angle", valueUnits == "rad" else {
            return (provenance, false)
        }
        var normalized = provenance
        switch normalized[ScalarResultMap.dpcAngleEncodingKey] {
        case nil, ScalarResultMap.dpcAngleTurnsEncoding:
            normalized[ScalarResultMap.dpcAngleEncodingKey] =
                ScalarResultMap.dpcAngleRadiansEncoding
            normalized["dpc_angle_migration"] = "normalized_turns_to_radians"
            return (normalized, true)
        case ScalarResultMap.dpcAngleRadiansEncoding:
            return (normalized, false)
        case .some:
            throw WriterError.malformedAttribute(
                name: "mac4dstem_provenance.\(ScalarResultMap.dpcAngleEncodingKey)"
            )
        }
    }

    static func readResultMap(
        _ file: SidecarFile, nodeName: String, in parent: String
    ) throws -> ScalarResultMap? {
        let group = "\(parent)/\(nodeName)"
        guard file.isGroup(group) else { return nil }
        guard let (width, height) = try readResultShape(file, group: group, storage: .scalarFloat32) else {
            return nil
        }
        var pixels: [Float]
        do {
            guard let values = try file.reader.readDataset("\(group)/data").float32Values() else {
                throw WriterError.hdf5("reading the scalar result pixels")
            }
            pixels = values
        } catch let error as WriterError {
            throw error
        } catch {
            throw SidecarFile.failure("reading the scalar result pixels", error)
        }
        guard pixels.count == width * height else { throw WriterError.hdf5("reading the scalar result pixels") }
        let kind = try file.stringAttribute("mac4dstem_kind", at: group)
            ?? "unknown"
        let valueUnits = try file.stringAttribute("mac4dstem_value_units", at: group)
            ?? "intensity"
        let readState = try dpcAngleReadState(
            kind: kind,
            valueUnits: valueUnits,
            provenance: decodeProvenance(try file.stringAttribute("mac4dstem_provenance", at: group))
        )
        if readState.needsTurnToRadianScale {
            pixels = pixels.map { $0 * (2 * .pi) }
        }
        return ScalarResultMap(
            width: width,
            height: height,
            pixels: pixels,
            kind: kind,
            displayName: try file.stringAttribute("mac4dstem_display_name", at: group)
                ?? "Restored result",
            valueUnits: valueUnits,
            pixelSizeRow: try file.stringAttribute("mac4dstem_pixel_size_row", at: group).flatMap(Double.init),
            pixelSizeColumn: try file.stringAttribute("mac4dstem_pixel_size_column", at: group).flatMap(Double.init),
            pixelUnits: try file.stringAttribute("mac4dstem_pixel_units", at: group),
            provenance: readState.provenance
        )
    }

    static func readRGBAResultMap(
        _ file: SidecarFile, nodeName: String, in parent: String
    ) throws -> RGBAResultMap? {
        let group = "\(parent)/\(nodeName)"
        guard file.isGroup(group) else { return nil }
        guard let (width, height) = try readResultShape(file, group: group, storage: .rgba8) else { return nil }
        let rgba: [UInt8]
        do {
            let array = try file.reader.readDataset("\(group)/data")
            if array.dataType == .uint8 {
                rgba = [UInt8](array.bytes)
            } else {
                // libhdf5 converted any stored number to a byte, clipping; the same here.
                rgba = array.doubles().map { UInt8(max(0, min(255, $0.rounded(.towardZero)))) }
            }
        } catch {
            throw SidecarFile.failure("reading the RGBA result pixels", error)
        }
        guard rgba.count == width * height * 4 else { throw WriterError.hdf5("reading the RGBA result pixels") }
        return RGBAResultMap(
            width: width, height: height, rgba: rgba,
            kind: try file.stringAttribute("mac4dstem_kind", at: group)
                ?? "unknown",
            displayName: try file.stringAttribute("mac4dstem_display_name", at: group)
                ?? "Restored RGBA result",
            valueUnits: try file.stringAttribute("mac4dstem_value_units", at: group)
                ?? "rgba",
            pixelSizeRow: try file.stringAttribute("mac4dstem_pixel_size_row", at: group).flatMap(Double.init),
            pixelSizeColumn: try file.stringAttribute("mac4dstem_pixel_size_column", at: group).flatMap(Double.init),
            pixelUnits: try file.stringAttribute("mac4dstem_pixel_units", at: group),
            provenance: decodeProvenance(try file.stringAttribute("mac4dstem_provenance", at: group))
        )
    }

    private static func readResultShape(
        _ file: SidecarFile, group: String, storage: SessionResultStorage
    ) throws -> (width: Int, height: Int)? {
        let path = "\(group)/data"
        guard file.isDataset(path) else { return nil }
        let info: HDF5DatasetInfo
        do {
            info = try file.reader.datasetInfo(path)
        } catch HDF5FileError.unsupportedType {
            return nil
        } catch HDF5FileError.limitExceeded {
            return nil
        } catch {
            throw SidecarFile.failure("opening the scalar result dataspace", error)
        }
        let rank = storage == .rgba8 ? 3 : 2
        guard info.shape.count == rank else { return nil }
        if storage == .rgba8, info.shape[2] != 4 { return nil }
        let height = info.shape[0], width = info.shape[1]
        guard width > 0, height > 0, width <= Int.max / height else { return nil }
        return (width, height)
    }
}
