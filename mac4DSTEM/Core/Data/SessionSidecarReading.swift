import Darwin
import Foundation
import FormatoHDF5
import SpectroCore

//
//  SessionSidecarReading.swift
//  Role: read a session sidecar (`<source>.mac4dstem.h5`) back: the minimum-reader gate, the inventory, the calibration, the result
//        maps, the peak grid, the replay record, the lineage and the labels. Split out of BraggVectorEMDWriter.swift (2026-10-20),
//        which keeps the writers, the atomic publish and the `mac4dstem_*` attribute names.
//

nonisolated extension BraggVectorEMDWriter {
    /// Load the complete supported session inventory and the map recorded as
    /// current. Legacy one-slot sidecars are treated as a one-map inventory.
    /// The one minimum-reader check, shared by EVERY reader that hands back
    /// session content — `loadSession` and the two direct result readers
    /// (`loadResultMap(id:)`, `loadRGBAResultMap(id:)`) — both would otherwise
    /// bypass it and restore pixel arrays from a file the gate had refused
    /// (Gate B-lite F5). Absent marker ⇒ the file predates it ⇒ readable by
    /// the rules that applied when it was written; an unparseable value is
    /// treated the same, because refusing on garbage would brick every
    /// sidecar a bit-flip touches while a newer-format file always writes a
    /// clean integer.
    static func enforceMinimumReader(
        on root: hid_t, hdf5 h5: HDF5WriteLibrary, supportedSchema: Int
    ) throws {
        // A marker of the wrong shape or type is garbage like any other
        // unparseable value, so it reads as absent (the rule above), not as
        // the reader's `malformedAttribute` refusal. // S5
        let markerText: String?
        do {
            markerText = try readStringAttribute(minimumReaderAttribute, on: root, hdf5: h5)
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

    /// `supportedSchema` exists so the minimum-reader refusal is testable
    /// against a REAL file through the REAL gate: a test reads a genuinely
    /// cropped sidecar as a schema-5 reader and watches the refusal fire.
    /// Production callers never pass it — the default is the build's truth.
    package static func loadSession(
        from url: URL,
        supportedSchema: Int = SessionSidecarFormat.currentSchema
    ) throws -> SessionSidecarSnapshot {
        HDF5Serial.acquire(); defer { HDF5Serial.release() }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return SessionSidecarSnapshot(
                inventory: .empty, calibration: nil, currentResult: nil,
                currentRGBAResult: nil
            )
        }
        let h5 = try HDF5WriteLibrary.load()
        let fileID = url.path.withCString {
            h5.h5fopen($0, h5FileReadOnly, h5DefaultProperty)
        }
        guard fileID >= 0 else { throw hdf5Failure("opening the session sidecar", h5) }
        defer { _ = h5.h5fclose(fileID) }

        let root = rootPath.withCString { h5.h5gopen2(fileID, $0, h5DefaultProperty) }
        guard root >= 0 else { throw hdf5Failure("opening the session root", h5) }
        defer { _ = h5.h5gclose(root) }

        // THE MINIMUM-READER GATE (v2 S5), checked before anything is
        // restored. A file demanding a newer reader is refused whole, with
        // both numbers named — a partial restore is exactly the "right
        // numbers at wrong positions, no warning" failure the marker exists
        // to prevent.
        try enforceMinimumReader(on: root, hdf5: h5, supportedSchema: supportedSchema)

        let results = try readResultDescriptors(from: root, file: fileID, hdf5: h5)
        let recordedCurrent = try readStringAttribute(currentResultAttribute, on: root, hdf5: h5)
        let currentID = recordedCurrent.flatMap { id in
            results.contains(where: { $0.id == id }) ? id : nil
        } ?? results.last?.id
        let currentDescriptor = currentID.flatMap { id in
            results.first(where: { $0.id == id })
        }
        let currentResult = try currentDescriptor.flatMap { descriptor in
            descriptor.storage == .scalarFloat32
                ? try readResultMap(nodeName: descriptor.id, from: root, hdf5: h5)
                : nil
        }
        let currentRGBAResult = try currentDescriptor.flatMap { descriptor in
            descriptor.storage == .rgba8
                ? try readRGBAResultMap(nodeName: descriptor.id, from: root, hdf5: h5)
                : nil
        }
        let calibration = try readCalibration(from: root, hdf5: h5)
        // Absent attribute ⇒ nil — nothing was recorded. Present-but-
        // undecodable ⇒ REFUSE by name (v2 S7): `.flatMap(decoded)` used to
        // collapse the two, so a mangled specification attribute read as "no
        // crop recorded" and the cropped session reopened silently at full
        // extent — the misread the attribute exists to prevent.
        let specification: LoadSpecification?
        if let json = try readStringAttribute(loadSpecificationAttribute,
                                              on: root, hdf5: h5) {
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
        if let json = try readStringAttribute(replayRecordAttribute, on: root, hdf5: h5) {
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
           let json = try readStringAttribute(lineageAttribute, on: root, hdf5: h5) {
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
            hasBraggVectors: linkExists("\(rootPath)/braggvectors", in: fileID, hdf5: h5),
            hasCalibration: calibration != nil,
            results: results,
            currentResultID: currentID
        )
        // The stamp is read like the minimum-reader marker: garbage is absent.
        let schemaText: String? = (try? readStringAttribute(schemaAttribute, on: root, hdf5: h5)) ?? nil
        let schemaStamp = schemaText.flatMap { Int($0) }
        return SessionSidecarSnapshot(
            inventory: inventory, calibration: calibration,
            currentResult: currentResult, currentRGBAResult: currentRGBAResult,
            loadSpecification: specification, schema: schemaStamp,
            replayRecord: replay,
            lineage: lineage, lineageNote: lineageNote
        )
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

    /// The read half of `writePeakGrid` (2026-09-28, ../_archive/mac4DSTEM/docs/archive/v4/
    /// bragg-restore-registration-2026-09-28.md). Nil when the sidecar has no
    /// peak grid (or no `_braggvectors_shape`, which the detector shape comes
    /// from). Throws on an HDF5 failure or a non-finite peak — never a partial
    /// grid. py4DSTEM's qx is the detector ROW and qy the COLUMN; the app's
    /// `BraggPeak` is x = column, y = row, so the writer's swap is undone here.
    /// float64 → Float32 is exact for values the writer produced from Float32.
    package static func loadPeakGrid(
        from url: URL,
        supportedSchema: Int = SessionSidecarFormat.currentSchema
    ) throws -> StoredPeakGrid? {
        HDF5Serial.acquire(); defer { HDF5Serial.release() }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let h5 = try HDF5WriteLibrary.load()
        let fileID = url.path.withCString {
            h5.h5fopen($0, h5FileReadOnly, h5DefaultProperty)
        }
        guard fileID >= 0 else { throw hdf5Failure("opening the session sidecar", h5) }
        defer { _ = h5.h5fclose(fileID) }
        let root = rootPath.withCString { h5.h5gopen2(fileID, $0, h5DefaultProperty) }
        guard root >= 0 else { throw hdf5Failure("opening the session root", h5) }
        defer { _ = h5.h5gclose(root) }
        try enforceMinimumReader(on: root, hdf5: h5, supportedSchema: supportedSchema)

        guard linkExists("braggvectors/_v_uncal/data", in: root, hdf5: h5) else { return nil }
        let bragg = "braggvectors".withCString { h5.h5gopen2(root, $0, h5DefaultProperty) }
        guard bragg >= 0 else { return nil }
        defer { _ = h5.h5gclose(bragg) }
        let provenance = decodeProvenance(try readStringAttribute(
            "mac4dstem_detection_provenance", on: bragg, hdf5: h5
        ))
        guard let qShape = try readInt64Vector(
            "metadatabundle/_braggvectors_shape/Qshape", from: bragg, count: 2, hdf5: h5
        ), qShape.allSatisfy({ $0 > 0 }) else { return nil }

        let group = "_v_uncal".withCString { h5.h5gopen2(bragg, $0, h5DefaultProperty) }
        guard group >= 0 else { return nil }
        defer { _ = h5.h5gclose(group) }
        let dataset = "data".withCString { h5.h5dopen2(group, $0, h5DefaultProperty) }
        guard dataset >= 0 else { return nil }
        defer { _ = h5.h5dclose(dataset) }
        let space = h5.h5dgetSpace(dataset)
        guard space >= 0 else { throw WriterError.hdf5("opening the peak-grid dataspace") }
        defer { _ = h5.h5sclose(space) }
        guard h5.h5sgetSimpleExtentNdims(space) == 2 else { return nil }
        var rawShape = [hsize_t](repeating: 0, count: 2)
        guard rawShape.withUnsafeMutableBufferPointer({
            h5.h5sgetSimpleExtentDims(space, $0.baseAddress, nil)
        }) == 2,
        rawShape.allSatisfy({ $0 > 0 && $0 <= hsize_t(Int32.max) }) else { return nil }
        let scanHeight = Int(rawShape[0]), scanWidth = Int(rawShape[1])
        let positions = scanHeight * scanWidth

        // The memory type is the writer's own: vlen of {qx, qy, intensity}
        // float64. HDF5 converts by member NAME, so a file that orders the
        // fields differently (py4DSTEM's own) reads the same.
        let compound = h5.h5tcreate(h5CompoundClass, MemoryLayout<EMDPeakRecord>.stride)
        guard compound >= 0 else { throw WriterError.hdf5("creating the peak compound type") }
        defer { _ = h5.h5tclose(compound) }
        guard "qx".withCString({ h5.h5tinsert(compound, $0, 0, h5.nativeDouble) }) >= 0,
              "qy".withCString({ h5.h5tinsert(compound, $0, 8, h5.nativeDouble) }) >= 0,
              "intensity".withCString({ h5.h5tinsert(compound, $0, 16, h5.nativeDouble) }) >= 0 else {
            throw WriterError.hdf5("defining the peak compound fields")
        }
        let variable = h5.h5tvlenCreate(compound)
        guard variable >= 0 else { throw WriterError.hdf5("creating the variable-length peak type") }
        defer { _ = h5.h5tclose(variable) }

        var cells = [H5VariableLength](
            repeating: H5VariableLength(length: 0, pointer: nil), count: positions
        )
        guard cells.withUnsafeMutableBytes({
            h5.h5dread(dataset, variable, h5EntireDataspace, h5EntireDataspace,
                       h5DefaultProperty, $0.baseAddress)
        }) >= 0 else { throw WriterError.hdf5("reading the peak grid") }

        // Every cell's buffer belongs to the library's allocator and is freed
        // exactly once below, on the success path and the throwing one alike
        // (a compound of doubles holds no nested variable-length data, so
        // freeing each cell is the whole of `H5Dvlen_reclaim`).
        defer {
            for cell in cells { if let pointer = cell.pointer { _ = h5.h5freeMemory(pointer) } }
        }
        var peaks = [[BraggPeak]](repeating: [], count: positions)
        for index in 0..<positions {
            let cell = cells[index]
            guard cell.length > 0 else { continue }
            guard let pointer = cell.pointer, cell.length <= Int(Int32.max) else {
                throw WriterError.hdf5("the peak grid holds a malformed cell")
            }
            let records = pointer.assumingMemoryBound(to: EMDPeakRecord.self)
            var cellPeaks = [BraggPeak]()
            cellPeaks.reserveCapacity(cell.length)
            for item in 0..<cell.length {
                let record = records[item]
                // AXIS CONVERSION (inverse of writePeakGrid): qx = row = y, qy = column = x.
                let peak = BraggPeak(
                    x: Float(record.qy), y: Float(record.qx), intensity: Float(record.intensity)
                )
                guard peak.x.isFinite, peak.y.isFinite, peak.intensity.isFinite else {
                    throw WriterError.hdf5("the peak grid holds a non-finite peak")
                }
                cellPeaks.append(peak)
            }
            peaks[index] = cellPeaks
        }
        return StoredPeakGrid(
            vectors: BraggVectors(
                scanWidth: scanWidth, scanHeight: scanHeight, peaks: peaks,
                detectionProvenance: provenance
            ),
            detectorHeight: qShape[0], detectorWidth: qShape[1]
        )
    }

    static func readInt64Vector(
        _ path: String, from parent: hid_t, count: Int, hdf5 h5: HDF5WriteLibrary
    ) throws -> [Int]? {
        guard linkExists(path, in: parent, hdf5: h5) else { return nil }
        let dataset = path.withCString { h5.h5dopen2(parent, $0, h5DefaultProperty) }
        guard dataset >= 0 else { return nil }
        defer { _ = h5.h5dclose(dataset) }
        // A foreign sidecar may hold more elements than `count`; H5Dread fills the whole dataspace, so check first.
        let space = h5.h5dgetSpace(dataset)
        guard space >= 0 else { throw WriterError.hdf5("reading the shape of dataset \(path)") }
        defer { _ = h5.h5sclose(space) }
        guard elementCount(spaceID: space, hdf5: h5) == count else {
            throw WriterError.hdf5("dataset \(path) does not hold exactly \(count) values")
        }
        var values = [Int64](repeating: 0, count: count)
        guard values.withUnsafeMutableBytes({
            h5.h5dread(dataset, h5.nativeLongLong, h5EntireDataspace, h5EntireDataspace,
                       h5DefaultProperty, $0.baseAddress)
        }) >= 0 else { throw WriterError.hdf5("reading dataset \(path)") }
        return values.map { Int($0) }
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
        let h5 = try HDF5WriteLibrary.load()
        let fileID = url.path.withCString {
            h5.h5fopen($0, h5FileReadOnly, h5DefaultProperty)
        }
        guard fileID >= 0 else { throw hdf5Failure("opening the session sidecar", h5) }
        defer { _ = h5.h5fclose(fileID) }
        let root = rootPath.withCString { h5.h5gopen2(fileID, $0, h5DefaultProperty) }
        guard root >= 0 else { throw hdf5Failure("opening the session root", h5) }
        defer { _ = h5.h5gclose(root) }
        try enforceMinimumReader(on: root, hdf5: h5, supportedSchema: supportedSchema)
        let descriptors = try readResultDescriptors(from: root, file: fileID, hdf5: h5)
        guard descriptors.contains(where: {
            $0.id == id && $0.storage == .scalarFloat32
        }) else { return nil }
        return try readResultMap(nodeName: id, from: root, hdf5: h5)
    }

    package static func loadRGBAResultMap(
        id: String, from url: URL,
        supportedSchema: Int = SessionSidecarFormat.currentSchema
    ) throws -> RGBAResultMap? {
        HDF5Serial.acquire(); defer { HDF5Serial.release() }
        guard isSafeNodeName(id), FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let h5 = try HDF5WriteLibrary.load()
        let fileID = url.path.withCString {
            h5.h5fopen($0, h5FileReadOnly, h5DefaultProperty)
        }
        guard fileID >= 0 else { throw hdf5Failure("opening the session sidecar", h5) }
        defer { _ = h5.h5fclose(fileID) }
        let root = rootPath.withCString { h5.h5gopen2(fileID, $0, h5DefaultProperty) }
        guard root >= 0 else { throw hdf5Failure("opening the session root", h5) }
        defer { _ = h5.h5gclose(root) }
        try enforceMinimumReader(on: root, hdf5: h5, supportedSchema: supportedSchema)
        let descriptors = try readResultDescriptors(from: root, file: fileID, hdf5: h5)
        guard descriptors.contains(where: { $0.id == id && $0.storage == .rgba8 }) else {
            return nil
        }
        return try readRGBAResultMap(nodeName: id, from: root, hdf5: h5)
    }

    /// Read one field back from a file `writeScientificBundle` wrote (the per-product data export
    /// reads through this in its test). Reuses the sidecar's own node reader, so the values, units,
    /// pixel sizes and provenance come back exactly as the session reader would give them.
    package static func loadScientificBundleField(
        kind: String, from url: URL
    ) throws -> ScalarResultMap? {
        HDF5Serial.acquire(); defer { HDF5Serial.release() }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let h5 = try HDF5WriteLibrary.load()
        let fileID = url.path.withCString { h5.h5fopen($0, h5FileReadOnly, h5DefaultProperty) }
        guard fileID >= 0 else { throw hdf5Failure("opening the bundle file", h5) }
        defer { _ = h5.h5fclose(fileID) }
        let root = "scientific_bundle_root".withCString { h5.h5gopen2(fileID, $0, h5DefaultProperty) }
        guard root >= 0 else { throw hdf5Failure("opening the bundle root", h5) }
        defer { _ = h5.h5gclose(root) }
        return try readResultMap(nodeName: resultNodeName(forKind: kind), from: root, hdf5: h5)
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
        let h5 = try HDF5WriteLibrary.load()
        let fileID = url.path.withCString {
            h5.h5fopen($0, h5FileReadOnly, h5DefaultProperty)
        }
        guard fileID >= 0 else { throw hdf5Failure("opening the session sidecar", h5) }
        defer { _ = h5.h5fclose(fileID) }
        let root = rootPath.withCString { h5.h5gopen2(fileID, $0, h5DefaultProperty) }
        guard root >= 0 else { throw hdf5Failure("opening the session root", h5) }
        defer { _ = h5.h5gclose(root) }
        try enforceMinimumReader(on: root, hdf5: h5, supportedSchema: SessionSidecarFormat.currentSchema)
        return try readStringAttribute(diskCentreLabelsAttribute, on: root, hdf5: h5)
    }

    static func readResultDescriptors(
        from root: hid_t, file: hid_t, hdf5 h5: HDF5WriteLibrary
    ) throws -> [SessionResultDescriptor] {
        var nodeNames: [String]
        if let manifest = try readStringAttribute(resultNodesAttribute, on: root, hdf5: h5) {
            nodeNames = manifest.split(separator: "\n").map(String.init)
        } else if linkExists("\(rootPath)/\(ScalarResultMap.legacyEMDName)",
                             in: file, hdf5: h5) {
            nodeNames = [ScalarResultMap.legacyEMDName]
        } else {
            nodeNames = []
        }

        var seen = Set<String>()
        var results: [SessionResultDescriptor] = []
        for nodeName in nodeNames where isSafeNodeName(nodeName) && seen.insert(nodeName).inserted {
            guard linkExists("\(rootPath)/\(nodeName)", in: file, hdf5: h5),
                  let descriptor = try readResultDescriptor(
                    nodeName: nodeName, from: root, hdf5: h5
                  ) else { continue }
            results.append(descriptor)
        }
        return results
    }

    static func readCalibration(
        from root: hid_t, hdf5 h5: HDF5WriteLibrary
    ) throws -> PixelCalibration? {
        let group = "metadatabundle/calibration".withCString {
            h5.h5gopen2(root, $0, h5DefaultProperty)
        }
        guard group >= 0 else { return nil }
        defer { _ = h5.h5gclose(group) }

        var calibration = PixelCalibration(
            rSize: try readDoubleDataset("R_pixel_size", from: group, hdf5: h5),
            rUnits: try readStringDataset("R_pixel_units", from: group, hdf5: h5),
            qSize: try readDoubleDataset("Q_pixel_size", from: group, hdf5: h5),
            qUnits: try readStringDataset("Q_pixel_units", from: group, hdf5: h5),
            qrFlip: try readBoolDataset("QR_flip", from: group, hdf5: h5)
        )
        calibration.qx0Mean = try readDoubleDataset("qx0_mean", from: group, hdf5: h5)
        calibration.qy0Mean = try readDoubleDataset("qy0_mean", from: group, hdf5: h5)
        // Row 29: a file ellipse with a non-positive semi-axis is refused whole.
        if let ellipse = Calibration.acceptedEllipse(
            a: try readDoubleDataset("a", from: group, hdf5: h5),
            b: try readDoubleDataset("b", from: group, hdf5: h5),
            theta: try readDoubleDataset("theta", from: group, hdf5: h5)) {
            calibration.ellipseA = ellipse.a
            calibration.ellipseB = ellipse.b
            calibration.ellipseTheta = ellipse.theta
        }
        calibration.qrRotationRad = try readDoubleDataset(
            "QR_rotation", from: group, hdf5: h5
        )
        calibration.qrRotationConvention = try readStringDataset(
            "QR_rotation_convention", from: group, hdf5: h5
        )
        calibration.probeSemiangle = try readDoubleDataset(
            "probe_semiangle", from: group, hdf5: h5
        )
        if let qx0 = try readDoubleMatrix("qx0", from: group, hdf5: h5),
           let qy0 = try readDoubleMatrix("qy0", from: group, hdf5: h5),
           qx0.shape == qy0.shape {
            let measuredQX = try readDoubleMatrix("qx0_meas", from: group, hdf5: h5)
            let measuredQY = try readDoubleMatrix("qy0_meas", from: group, hdf5: h5)
            let measuredPair = measuredQX?.shape == qx0.shape
                && measuredQY?.shape == qx0.shape
            calibration.originMaps = PixelOriginMaps(
                shape: qx0.shape,
                fittedQX: qx0.values,
                fittedQY: qy0.values,
                measuredQX: measuredPair ? measuredQX?.values : nil,
                measuredQY: measuredPair ? measuredQY?.values : nil
            )
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

    /// The three readers below hand `H5Dread` ONE value on the stack, and it writes the WHOLE dataset there: a
    /// foreign or hand-edited sidecar with a 3-element `a` overran it (review 2026-10-02, the stack twin of the
    /// Qshape overrun `readInt64Vector` refuses). Refused by name; an empty dataset too, never read as 0.
    static func requireOneElement(
        _ dataset: hid_t, _ name: String, hdf5 h5: HDF5WriteLibrary
    ) throws {
        let space = h5.h5dgetSpace(dataset)
        guard space >= 0 else { throw WriterError.hdf5("reading the shape of dataset \(name)") }
        defer { _ = h5.h5sclose(space) }
        // HDF5's own count: 1 for a scalar or shape (1,), 0 for a NULL dataspace (h5py.Empty), which also has rank 0
        // and so counts as one value in elementCount — and H5Dread then transfers nothing.
        guard h5.h5sgetSimpleExtentNpoints(space) == 1 else {
            throw WriterError.hdf5("reading dataset \(name), which does not hold exactly one value")
        }
    }

    static func readDoubleDataset(
        _ name: String, from group: hid_t, hdf5 h5: HDF5WriteLibrary
    ) throws -> Double? {
        guard linkExists(name, in: group, hdf5: h5) else { return nil }
        let dataset = name.withCString { h5.h5dopen2(group, $0, h5DefaultProperty) }
        guard dataset >= 0 else { return nil }
        defer { _ = h5.h5dclose(dataset) }
        try requireOneElement(dataset, name, hdf5: h5)
        var value = 0.0
        guard withUnsafeMutablePointer(to: &value, {
            h5.h5dread(dataset, h5.nativeDouble, h5EntireDataspace, h5EntireDataspace,
                       h5DefaultProperty, UnsafeMutableRawPointer($0))
        }) >= 0 else { throw WriterError.hdf5("reading dataset \(name)") }
        return value.isFinite ? value : nil
    }

    static func readBoolDataset(
        _ name: String, from group: hid_t, hdf5 h5: HDF5WriteLibrary
    ) throws -> Bool? {
        guard linkExists(name, in: group, hdf5: h5) else { return nil }
        let dataset = name.withCString { h5.h5dopen2(group, $0, h5DefaultProperty) }
        guard dataset >= 0 else { return nil }
        defer { _ = h5.h5dclose(dataset) }
        try requireOneElement(dataset, name, hdf5: h5)
        var value = false
        guard withUnsafeMutablePointer(to: &value, {
            h5.h5dread(dataset, h5.nativeHBool, h5EntireDataspace, h5EntireDataspace,
                       h5DefaultProperty, UnsafeMutableRawPointer($0))
        }) >= 0 else { throw WriterError.hdf5("reading dataset \(name)") }
        return value
    }

    static func readStringDataset(
        _ name: String, from group: hid_t, hdf5 h5: HDF5WriteLibrary
    ) throws -> String? {
        guard linkExists(name, in: group, hdf5: h5) else { return nil }
        let dataset = name.withCString { h5.h5dopen2(group, $0, h5DefaultProperty) }
        guard dataset >= 0 else { return nil }
        defer { _ = h5.h5dclose(dataset) }
        let type = h5.h5dgetType(dataset)
        guard type >= 0 else { throw WriterError.hdf5("opening dataset type \(name)") }
        defer { _ = h5.h5tclose(type) }
        // Read in the file's OWN type into one pointer: only what the writer writes — one variable-length
        // string — fits it; a fixed-length string or a number would overrun it or land in it as an address.
        // (H5Tis_variable_str is false for every non-string type, so it is the whole type check.)
        try requireOneElement(dataset, name, hdf5: h5)
        guard h5.h5tisVariableStr(type) > 0 else {
            throw WriterError.hdf5("reading dataset \(name), which is not one variable-length string")
        }
        var pointer: UnsafeMutablePointer<CChar>?
        guard withUnsafeMutablePointer(to: &pointer, {
            h5.h5dread(dataset, type, h5EntireDataspace, h5EntireDataspace,
                       h5DefaultProperty, UnsafeMutableRawPointer($0))
        }) >= 0 else { throw WriterError.hdf5("reading dataset \(name)") }
        guard let pointer else { return "" }
        defer { _ = h5.h5freeMemory(pointer) }
        return String(cString: pointer)
    }

    static func readDoubleMatrix(
        _ name: String, from group: hid_t, hdf5 h5: HDF5WriteLibrary
    ) throws -> (shape: [Int], values: [Double])? {
        guard linkExists(name, in: group, hdf5: h5) else { return nil }
        let dataset = name.withCString { h5.h5dopen2(group, $0, h5DefaultProperty) }
        guard dataset >= 0 else { return nil }
        defer { _ = h5.h5dclose(dataset) }
        let space = h5.h5dgetSpace(dataset)
        guard space >= 0 else { throw WriterError.hdf5("opening dataset \(name)") }
        defer { _ = h5.h5sclose(space) }
        guard h5.h5sgetSimpleExtentNdims(space) == 2 else { return nil }
        var rawShape = [hsize_t](repeating: 0, count: 2)
        guard rawShape.withUnsafeMutableBufferPointer({
            h5.h5sgetSimpleExtentDims(space, $0.baseAddress, nil)
        }) == 2,
        rawShape.allSatisfy({ $0 > 0 && $0 <= hsize_t(Int.max) }) else { return nil }
        let shape = rawShape.map(Int.init)
        guard shape[0] <= Int.max / shape[1] else { return nil }
        var values = [Double](repeating: 0, count: shape[0] * shape[1])
        guard values.withUnsafeMutableBytes({
            h5.h5dread(dataset, h5.nativeDouble, h5EntireDataspace, h5EntireDataspace,
                       h5DefaultProperty, $0.baseAddress)
        }) >= 0 else { throw WriterError.hdf5("reading dataset \(name)") }
        guard values.allSatisfy(\.isFinite) else { return nil }
        return (shape, values)
    }

    static func readResultDescriptor(
        nodeName: String, from root: hid_t, hdf5 h5: HDF5WriteLibrary
    ) throws -> SessionResultDescriptor? {
        let group = nodeName.withCString { h5.h5gopen2(root, $0, h5DefaultProperty) }
        guard group >= 0 else { return nil }
        defer { _ = h5.h5gclose(group) }
        let storage = try readStringAttribute("mac4dstem_storage", on: group, hdf5: h5)
            .flatMap(SessionResultStorage.init(rawValue:)) ?? .scalarFloat32
        guard let (width, height) = try readResultShape(
            from: group, storage: storage, hdf5: h5
        ) else {
            return nil
        }
        let kind = try readStringAttribute("mac4dstem_kind", on: group, hdf5: h5)
            ?? "unknown"
        let valueUnits = try readStringAttribute(
            "mac4dstem_value_units", on: group, hdf5: h5
        ) ?? "intensity"
        let provenance = try dpcAngleReadState(
            kind: kind,
            valueUnits: valueUnits,
            provenance: decodeProvenance(try readStringAttribute(
                "mac4dstem_provenance", on: group, hdf5: h5
            ))
        ).provenance
        return SessionResultDescriptor(
            id: nodeName,
            kind: kind,
            displayName: try readStringAttribute(
                "mac4dstem_display_name", on: group, hdf5: h5
            ) ?? "Saved result",
            valueUnits: valueUnits,
            width: width,
            height: height,
            storage: storage,
            pixelSizeRow: try readStringAttribute(
                "mac4dstem_pixel_size_row", on: group, hdf5: h5
            ).flatMap(Double.init),
            pixelSizeColumn: try readStringAttribute(
                "mac4dstem_pixel_size_column", on: group, hdf5: h5
            ).flatMap(Double.init),
            pixelUnits: try readStringAttribute(
                "mac4dstem_pixel_units", on: group, hdf5: h5
            ),
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
        nodeName: String, from root: hid_t, hdf5 h5: HDF5WriteLibrary
    ) throws -> ScalarResultMap? {
        let group = nodeName.withCString { h5.h5gopen2(root, $0, h5DefaultProperty) }
        guard group >= 0 else { return nil }
        defer { _ = h5.h5gclose(group) }
        guard let (width, height) = try readResultShape(
            from: group, storage: .scalarFloat32, hdf5: h5
        ) else {
            return nil
        }
        let dataset = "data".withCString { h5.h5dopen2(group, $0, h5DefaultProperty) }
        guard dataset >= 0 else { return nil }
        defer { _ = h5.h5dclose(dataset) }
        var pixels = [Float](repeating: 0, count: width * height)
        guard pixels.withUnsafeMutableBytes({
            h5.h5dread(dataset, h5.nativeFloat, h5EntireDataspace, h5EntireDataspace,
                       h5DefaultProperty, $0.baseAddress)
        }) >= 0 else { throw WriterError.hdf5("reading the scalar result pixels") }
        let kind = try readStringAttribute("mac4dstem_kind", on: group, hdf5: h5)
            ?? "unknown"
        let valueUnits = try readStringAttribute(
            "mac4dstem_value_units", on: group, hdf5: h5
        ) ?? "intensity"
        let readState = try dpcAngleReadState(
            kind: kind,
            valueUnits: valueUnits,
            provenance: decodeProvenance(try readStringAttribute(
                "mac4dstem_provenance", on: group, hdf5: h5
            ))
        )
        if readState.needsTurnToRadianScale {
            pixels = pixels.map { $0 * (2 * .pi) }
        }
        return ScalarResultMap(
            width: width,
            height: height,
            pixels: pixels,
            kind: kind,
            displayName: try readStringAttribute(
                "mac4dstem_display_name", on: group, hdf5: h5
            ) ?? "Restored result",
            valueUnits: valueUnits,
            pixelSizeRow: try readStringAttribute(
                "mac4dstem_pixel_size_row", on: group, hdf5: h5
            ).flatMap(Double.init),
            pixelSizeColumn: try readStringAttribute(
                "mac4dstem_pixel_size_column", on: group, hdf5: h5
            ).flatMap(Double.init),
            pixelUnits: try readStringAttribute(
                "mac4dstem_pixel_units", on: group, hdf5: h5
            ),
            provenance: readState.provenance
        )
    }

    static func readRGBAResultMap(
        nodeName: String, from root: hid_t, hdf5 h5: HDF5WriteLibrary
    ) throws -> RGBAResultMap? {
        let group = nodeName.withCString { h5.h5gopen2(root, $0, h5DefaultProperty) }
        guard group >= 0 else { return nil }
        defer { _ = h5.h5gclose(group) }
        guard let (width, height) = try readResultShape(
            from: group, storage: .rgba8, hdf5: h5
        ) else { return nil }
        let dataset = "data".withCString { h5.h5dopen2(group, $0, h5DefaultProperty) }
        guard dataset >= 0 else { return nil }
        defer { _ = h5.h5dclose(dataset) }
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        guard rgba.withUnsafeMutableBytes({
            h5.h5dread(dataset, h5.nativeUChar, h5EntireDataspace, h5EntireDataspace,
                       h5DefaultProperty, $0.baseAddress)
        }) >= 0 else { throw WriterError.hdf5("reading the RGBA result pixels") }
        return RGBAResultMap(
            width: width, height: height, rgba: rgba,
            kind: try readStringAttribute("mac4dstem_kind", on: group, hdf5: h5)
                ?? "unknown",
            displayName: try readStringAttribute(
                "mac4dstem_display_name", on: group, hdf5: h5
            ) ?? "Restored RGBA result",
            valueUnits: try readStringAttribute(
                "mac4dstem_value_units", on: group, hdf5: h5
            ) ?? "rgba",
            pixelSizeRow: try readStringAttribute(
                "mac4dstem_pixel_size_row", on: group, hdf5: h5
            ).flatMap(Double.init),
            pixelSizeColumn: try readStringAttribute(
                "mac4dstem_pixel_size_column", on: group, hdf5: h5
            ).flatMap(Double.init),
            pixelUnits: try readStringAttribute(
                "mac4dstem_pixel_units", on: group, hdf5: h5
            ),
            provenance: decodeProvenance(try readStringAttribute(
                "mac4dstem_provenance", on: group, hdf5: h5
            ))
        )
    }

    static func readResultShape(
        from group: hid_t, storage: SessionResultStorage,
        hdf5 h5: HDF5WriteLibrary
    ) throws -> (width: Int, height: Int)? {
        let dataset = "data".withCString { h5.h5dopen2(group, $0, h5DefaultProperty) }
        guard dataset >= 0 else { return nil }
        defer { _ = h5.h5dclose(dataset) }
        let space = h5.h5dgetSpace(dataset)
        guard space >= 0 else { throw WriterError.hdf5("opening the scalar result dataspace") }
        defer { _ = h5.h5sclose(space) }
        let rank = storage == .rgba8 ? 3 : 2
        guard h5.h5sgetSimpleExtentNdims(space) == rank else { return nil }
        var dimensions = [hsize_t](repeating: 0, count: rank)
        guard dimensions.withUnsafeMutableBufferPointer({
            h5.h5sgetSimpleExtentDims(space, $0.baseAddress, nil)
        }) == rank else { throw WriterError.hdf5("reading the result shape") }
        if storage == .rgba8, dimensions[2] != 4 { return nil }
        guard dimensions[0] <= hsize_t(Int.max), dimensions[1] <= hsize_t(Int.max) else {
            return nil
        }
        let height = Int(dimensions[0]), width = Int(dimensions[1])
        guard width > 0, height > 0, width <= Int.max / height else { return nil }
        return (width, height)
    }
}
