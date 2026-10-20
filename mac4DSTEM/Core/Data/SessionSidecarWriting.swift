import Darwin
import Foundation
import FormatoHDF5
import SpectroCore

//
//  SessionSidecarWriting.swift
//  Role: build a session sidecar file in a scratch location: the file attributes, the calibration bundle, the result nodes
//        (scalar and RGBA), the BraggVectors object and its peak grid, and the carried-over content of the file it replaces
//        (replay record, lineage, labels, unknown objects). Split out of BraggVectorEMDWriter.swift (2026-10-20); the publish
//        stays there.
//

nonisolated extension BraggVectorEMDWriter {
    static func writeFile(
        at url: URL,
        vectors: BraggVectors?,
        map: ScalarResultMap?,
        rgbaMap: RGBAResultMap?,
        qWidth: Int,
        qHeight: Int,
        calibration: PixelCalibration,
        preserving existing: URL?,
        removingKind: String?,
        loadSpecification: LoadSpecification?,
        replayRecord: SessionReplayRecord?,
        diskCentreLabelsJSON: String?,
        supportedSchema: Int,
        cancellation: AnalysisCancellationToken?,
        progress: (@Sendable (Double) -> Void)?,
        hdf5 h5: HDF5WriteLibrary
    ) throws {
        let fileID = url.path.withCString {
            h5.h5fcreate($0, h5FileTruncate, h5DefaultProperty, h5DefaultProperty)
        }
        guard fileID >= 0 else { throw WriterError.hdf5("creating the temporary file") }
        defer { _ = h5.h5fclose(fileID) }

        // An existing sidecar that cannot be opened (locked by a read/write reader such as HDFView, damaged,
        // unreadable) is an ERROR, never "no file": treating it as absent built a fresh file and renamed it over
        // every saved result, the vectors, the labels and the recipe (review 2026-10-02 a4).
        var existingID: hid_t?
        if let source = existing {
            let id = source.path.withCString {
                h5.h5fopen($0, h5FileReadOnly, h5DefaultProperty)
            }
            guard id >= 0 else { throw hdf5Failure("opening the existing session sidecar", h5) }
            existingID = id
        }
        defer {
            if let existingID { _ = h5.h5fclose(existingID) }
        }

        try writeStringAttribute("emd_group_type", value: "file", on: fileID, hdf5: h5)
        try writeScalarAttribute("version_major", value: Int32(1), type: h5.nativeInt,
                                 on: fileID, hdf5: h5)
        try writeScalarAttribute("version_minor", value: Int32(0), type: h5.nativeInt,
                                 on: fileID, hdf5: h5)
        try writeStringAttribute("UUID", value: UUID().uuidString, on: fileID, hdf5: h5)
        try writeStringAttribute("authoring_program", value: "mac4DSTEM", on: fileID, hdf5: h5)
        // Match emdfile's default without silently embedding the Mac account name.
        try writeStringAttribute("authoring_user", value: "", on: fileID, hdf5: h5)

        let root = try createGroup(SessionSidecarFormat.rootGroupName, in: fileID, hdf5: h5)
        defer { _ = h5.h5gclose(root) }
        try writeNodeAttributes(groupType: "root", pythonClass: "Root", on: root, hdf5: h5)

        var existingResults: [SessionResultDescriptor] = []
        if let existingID {
            let existingRoot = rootPath.withCString {
                h5.h5gopen2(existingID, $0, h5DefaultProperty)
            }
            if existingRoot >= 0 {
                existingResults = try {
                    defer { _ = h5.h5gclose(existingRoot) }
                    // A rewrite is a read followed by a write: a file whose
                    // marker demands a newer reader must be REFUSED here too,
                    // or a save would silently drop the newer content this
                    // build cannot see and then stamp the marker back DOWN —
                    // a mangled file claiming to be safely readable
                    // (Gate B-lite F6). The publish is atomic, so a refusal
                    // leaves the original untouched. // v2 S5
                    try enforceMinimumReader(on: existingRoot, hdf5: h5,
                                             supportedSchema: supportedSchema)
                    return try readResultDescriptors(
                        from: existingRoot, file: existingID, hdf5: h5
                    )
                }()
            }
        }
        // Preserve an existing replay record when this save carries none —
        // same rule as the result nodes above. Without this, a save from a
        // session that ran no analyses (a colleague adjusting calibration)
        // would silently ERASE the recipe the sidecar exists to carry. // v2 S5
        //
        // An EMPTY record counts as nothing to say too (a session whose only
        // runs were calibrations carries a lineage but no replayable step):
        // writing `{"steps":[]}` would assert an empty recipe over a real one.
        // The lineage (schema 7) is preserved on the same condition as the
        // record it is the projection of — and only when the caller hands NO
        // record at all: a save that carries a record without a lineage is a
        // caller that predates it, and the file's lineage would be stale
        // against the record it now holds.
        var preservedReplayJSON: String?
        var preservedLineageJSON: String?
        if replayRecord?.isEmpty ?? true, let existingID {
            let existingRoot = rootPath.withCString {
                h5.h5gopen2(existingID, $0, h5DefaultProperty)
            }
            if existingRoot >= 0 {
                defer { _ = h5.h5gclose(existingRoot) }
                preservedReplayJSON = try readStringAttribute(
                    replayRecordAttribute, on: existingRoot, hdf5: h5
                )
                if replayRecord == nil {
                    do {
                        preservedLineageJSON = try readStringAttribute(
                            lineageAttribute, on: existingRoot, hdf5: h5)
                    } catch WriterError.malformedAttribute {
                        // An unreadable lineage cannot be carried forward and
                        // must not block an unrelated save; the reader refuses
                        // such a file by name, so it was never being used.
                        preservedLineageJSON = nil
                    }
                }
            }
        }
        // Preserve existing disk-centre labels the same way, for the same
        // reason (C7 session 4): a calibration save is not a labelling
        // session, and a caller that passes nil here is saying nothing about
        // labels, not "there are none."
        var preservedLabelsJSON: String?
        if diskCentreLabelsJSON == nil, let existingID {
            let existingRoot = rootPath.withCString {
                h5.h5gopen2(existingID, $0, h5DefaultProperty)
            }
            if existingRoot >= 0 {
                defer { _ = h5.h5gclose(existingRoot) }
                preservedLabelsJSON = try readStringAttribute(
                    diskCentreLabelsAttribute, on: existingRoot, hdf5: h5
                )
            }
        }

        let canCopyBragg = vectors == nil && existingID.map {
            linkExists("\(rootPath)/braggvectors", in: $0, hdf5: h5)
        } == true
        try writeCalibration(
            calibration,
            targetPath: vectors != nil || canCopyBragg ? "/braggvectors" : nil,
            in: root, hdf5: h5
        )

        if let vectors {
            let bragg = try createGroup("braggvectors", in: root, hdf5: h5)
            defer { _ = h5.h5gclose(bragg) }
            try writeNodeAttributes(groupType: "custom", pythonClass: "BraggVectors",
                                    on: bragg, hdf5: h5)
            try writeShapeMetadata(scanHeight: vectors.scanHeight, scanWidth: vectors.scanWidth,
                                   qHeight: qHeight, qWidth: qWidth, in: bragg, hdf5: h5)
            if let provenance = encodeProvenance(vectors.detectionProvenance) {
                try writeStringAttribute(
                    "mac4dstem_detection_provenance", value: provenance,
                    on: bragg, hdf5: h5
                )
            }
            try writePeakGrid(vectors, in: bragg, cancellation: cancellation,
                              progress: progress, hdf5: h5)
        } else if canCopyBragg, let existingID {
            try checkCancellation(cancellation)
            let status = "\(rootPath)/braggvectors".withCString { sourceName in
                "braggvectors".withCString { targetName in
                    h5.h5ocopy(existingID, sourceName, root, targetName,
                               h5DefaultProperty, h5DefaultProperty)
                }
            }
            guard status >= 0 else {
                throw WriterError.hdf5("preserving the existing BraggVectors object")
            }
        }

        // Preserve root children that this schema does not understand (for
        // example emdfile Plot nodes or third-party analysis objects). Known
        // mutable objects are rebuilt/copied below; unknown objects move as
        // opaque HDF5 objects so an app save is not destructive to external
        // tooling.
        if let existingID {
            let existingRoot = rootPath.withCString {
                h5.h5gopen2(existingID, $0, h5DefaultProperty)
            }
            if existingRoot >= 0 {
                defer { _ = h5.h5gclose(existingRoot) }
                let reserved = Set(
                    ["metadatabundle", "braggvectors"] + existingResults.map(\.id)
                )
                for name in childLinkNames(in: existingRoot, hdf5: h5)
                    where !reserved.contains(name) {
                    try checkCancellation(cancellation)
                    let status = name.withCString { sourceName in
                        name.withCString { targetName in
                            h5.h5ocopy(existingRoot, sourceName, root, targetName,
                                       h5DefaultProperty, h5DefaultProperty)
                        }
                    }
                    guard status >= 0 else {
                        throw WriterError.hdf5("preserving external object \(name)")
                    }
                }
            }
        }

        var resultNodeNames: [String] = []
        var copiedNodeNames = Set<String>()
        let replacementKind = map?.kind ?? rgbaMap?.kind ?? removingKind
        if let existingID {
            for descriptor in existingResults where descriptor.kind != replacementKind {
                try checkCancellation(cancellation)
                let targetName = resultNodeName(forKind: descriptor.kind)
                guard copiedNodeNames.insert(targetName).inserted else { continue }
                let sourcePath = "\(rootPath)/\(descriptor.id)"
                let status = sourcePath.withCString { sourceName in
                    targetName.withCString { targetNamePointer in
                        h5.h5ocopy(existingID, sourceName, root, targetNamePointer,
                                   h5DefaultProperty, h5DefaultProperty)
                    }
                }
                guard status >= 0 else {
                    throw WriterError.hdf5("preserving saved result \(descriptor.displayName)")
                }
                resultNodeNames.append(targetName)
            }
        }
        if let map {
            let nodeName = resultNodeName(forKind: map.kind)
            try writeResultMap(map, nodeName: nodeName, calibration: calibration, in: root,
                               cancellation: cancellation, progress: progress, hdf5: h5)
            resultNodeNames.append(nodeName)
        }
        if let rgbaMap {
            let nodeName = resultNodeName(forKind: rgbaMap.kind)
            try writeRGBAResultMap(
                rgbaMap, nodeName: nodeName, calibration: calibration, in: root,
                cancellation: cancellation, progress: progress, hdf5: h5
            )
            resultNodeNames.append(nodeName)
        }
        if let specification = loadSpecification, !specification.isFullExtent,
           let json = specification.jsonString {
            // Written whenever a session is published from a reduced view, even
            // with no results yet: the specification is what makes a product
            // traceable to *file + view*, and a calibration saved from a binned
            // cube is already a product of that view.
            try writeStringAttribute(loadSpecificationAttribute, value: json,
                                     on: root, hdf5: h5)
        }
        // The schema attribute is the file's IDENTITY marker, not a result
        // manifest, so it is written on every file this writer produces —
        // a calibration-only sidecar is still a sidecar. Tying it to the
        // result-nodes condition below left exactly this shape (8.9 kB,
        // calibration only, opened twice on 2026-08-19) unrecognisable to the
        // open path's sidecar check.
        // Nothing reads this attribute to mean "has results"; the inventory
        // reads `resultNodesAttribute`.
        try writeStringAttribute(schemaAttribute, value: sessionSchemaVersion,
                                 on: root, hdf5: h5)
        // The minimum-reader marker, on every file: the oldest schema
        // that interprets THIS file without misreading it — 6 when a reduced
        // specification is recorded (dangerous to ignore), 5 otherwise, so a
        // marker-checking reader never refuses a file it could read safely.
        try writeStringAttribute(
            minimumReaderAttribute,
            value: String(minimumReaderSchema(for: loadSpecification)),
            on: root, hdf5: h5
        )
        // The replay record: the caller's live record wins; failing that, the
        // record the existing file already carried survives the rewrite.
        let recordJSON = replayRecord.flatMap { $0.isEmpty ? nil : $0.jsonString }
        let recordToWrite = recordJSON ?? preservedReplayJSON
        if let json = recordToWrite {
            try writeStringAttribute(replayRecordAttribute, value: json,
                                     on: root, hdf5: h5)
        }
        // The lineage the record is the projection of, when the caller has one
        // (schema 7, ADR 047) — or, for a save that says nothing, the one the
        // file already carries. NEVER written unchecked: it must pass the
        // reader's own validation (a file this build writes must be a file this
        // build reads) and its projection must equal the record being written
        // beside it, or it is omitted and the omission is reported
        // (`takeLineageOmission`). A session whose only runs were calibrations,
        // saved over a file that has a recipe, is the second case: the recipe
        // stays, the calibration nodes are not written.
        let lineageCandidate = replayRecord?.lineage?.jsonString ?? preservedLineageJSON
        lineageOmission = nil
        if let candidate = lineageCandidate {
            switch SessionLineage.writable(
                candidate, alongside: recordToWrite.flatMap(SessionReplayRecord.parse)
            ) {
            case .success:
                try writeStringAttribute(lineageAttribute, value: candidate,
                                         on: root, hdf5: h5)
            case .failure(let omission):
                lineageOmission = omission.description
            }
        } else if replayRecord?.lineage != nil {
            lineageOmission = "The lineage was not saved — it could not be encoded."
        }
        // Same rule as the replay record immediately above: the caller's
        // live value wins, otherwise the labels already on the file survive
        // the rewrite. // C7 session 4
        if let json = diskCentreLabelsJSON ?? preservedLabelsJSON {
            try writeStringAttribute(diskCentreLabelsAttribute, value: json,
                                     on: root, hdf5: h5)
        }
        if !resultNodeNames.isEmpty {
            try writeStringAttribute(resultNodesAttribute,
                                     value: resultNodeNames.joined(separator: "\n"),
                                     on: root, hdf5: h5)
            try writeStringAttribute(currentResultAttribute,
                                     value: resultNodeNames.last!, on: root, hdf5: h5)
        }
        try checkCancellation(cancellation)
        progress?(1)
    }

    static func writeCalibration(
        _ calibration: PixelCalibration, targetPath: String?,
        in root: hid_t, hdf5 h5: HDF5WriteLibrary
    ) throws {
        let bundle = try createGroup("metadatabundle", in: root, hdf5: h5)
        defer { _ = h5.h5gclose(bundle) }
        try writeStringAttribute("emd_group_type", value: "metadatabundle", on: bundle, hdf5: h5)

        let group = try createGroup("calibration", in: bundle, hdf5: h5)
        defer { _ = h5.h5gclose(group) }
        try writeNodeAttributes(groupType: "metadata", pythonClass: "Calibration",
                                on: group, hdf5: h5)

        if var qrFlip = calibration.qrFlip {
            try writeScalarDataset("QR_flip", value: &qrFlip, type: h5.nativeHBool,
                                   metadataType: "bool", in: group, hdf5: h5)
        }
        if var value = calibration.qSize {
            try writeScalarDataset("Q_pixel_size", value: &value, type: h5.nativeDouble,
                                   metadataType: "number", in: group, hdf5: h5)
        }
        if let value = calibration.qUnits {
            try writeStringDataset("Q_pixel_units", value: value, metadataType: "string",
                                   in: group, hdf5: h5)
        }
        if var value = calibration.rSize {
            try writeScalarDataset("R_pixel_size", value: &value, type: h5.nativeDouble,
                                   metadataType: "number", in: group, hdf5: h5)
        }
        if let value = calibration.rUnits {
            try writeStringDataset("R_pixel_units", value: value, metadataType: "string",
                                   in: group, hdf5: h5)
        }
        if var value = calibration.qrRotationRad {
            try writeScalarDataset("QR_rotation", value: &value, type: h5.nativeDouble,
                                   metadataType: "number", in: group, hdf5: h5)
            var degrees = value * 180 / .pi
            try writeScalarDataset("QR_rotation_degrees", value: &degrees,
                                   type: h5.nativeDouble, metadataType: "number",
                                   in: group, hdf5: h5)
            if let convention = calibration.qrRotationConvention {
                try writeStringDataset("QR_rotation_convention", value: convention,
                                       metadataType: "string", in: group, hdf5: h5)
            }
        }
        if var value = calibration.probeSemiangle {
            try writeScalarDataset("probe_semiangle", value: &value, type: h5.nativeDouble,
                                   metadataType: "number", in: group, hdf5: h5)
        }
        if var value = calibration.ellipseA {
            try writeScalarDataset("a", value: &value, type: h5.nativeDouble,
                                   metadataType: "number", in: group, hdf5: h5)
        }
        if var value = calibration.ellipseB {
            try writeScalarDataset("b", value: &value, type: h5.nativeDouble,
                                   metadataType: "number", in: group, hdf5: h5)
        }
        if var value = calibration.ellipseTheta {
            try writeScalarDataset("theta", value: &value, type: h5.nativeDouble,
                                   metadataType: "number", in: group, hdf5: h5)
        }

        let maps = calibration.originMaps
        let mapCount = maps.map { $0.shape.reduce(1, *) }
        let validMaps = maps.flatMap { candidate -> PixelOriginMaps? in
            guard candidate.shape.count == 2,
                  candidate.shape.allSatisfy({ $0 > 0 }),
                  mapCount == candidate.fittedQX.count,
                  mapCount == candidate.fittedQY.count else { return nil }
            return candidate
        }
        let qxMean = calibration.qx0Mean ?? validMaps.map {
            $0.fittedQX.reduce(0, +) / Double($0.fittedQX.count)
        }
        let qyMean = calibration.qy0Mean ?? validMaps.map {
            $0.fittedQY.reduce(0, +) / Double($0.fittedQY.count)
        }
        if var value = qxMean {
            try writeScalarDataset("qx0_mean", value: &value, type: h5.nativeDouble,
                                   metadataType: "number", in: group, hdf5: h5)
        }
        if var value = qyMean {
            try writeScalarDataset("qy0_mean", value: &value, type: h5.nativeDouble,
                                   metadataType: "number", in: group, hdf5: h5)
        }
        if let maps = validMaps {
            try writeDoubleMatrixDataset("qx0", values: maps.fittedQX, shape: maps.shape,
                                         in: group, hdf5: h5)
            try writeDoubleMatrixDataset("qy0", values: maps.fittedQY, shape: maps.shape,
                                         in: group, hdf5: h5)
            if let qxMean, let qyMean {
                try writeDoubleMatrixDataset(
                    "qx0_shift", values: maps.fittedQX.map { $0 - qxMean },
                    shape: maps.shape, in: group, hdf5: h5
                )
                try writeDoubleMatrixDataset(
                    "qy0_shift", values: maps.fittedQY.map { $0 - qyMean },
                    shape: maps.shape, in: group, hdf5: h5
                )
            }
            if let measuredQX = maps.measuredQX,
               let measuredQY = maps.measuredQY,
               measuredQX.count == maps.fittedQX.count,
               measuredQY.count == maps.fittedQY.count {
                try writeDoubleMatrixDataset("qx0_meas", values: measuredQX,
                                             shape: maps.shape, in: group, hdf5: h5)
                try writeDoubleMatrixDataset("qy0_meas", values: measuredQY,
                                             shape: maps.shape, in: group, hdf5: h5)
            }
        }
        if let targetPath {
            try writeStringDataset("_root_treepath", value: "", metadataType: "string",
                                   in: group, hdf5: h5)
            let targets = try createGroup("_target_paths", in: group, hdf5: h5)
            defer { _ = h5.h5gclose(targets) }
            try writeStringAttribute("type", value: "list_of_strings", on: targets, hdf5: h5)
            try writeScalarAttribute("length", value: Int32(1), type: h5.nativeInt,
                                     on: targets, hdf5: h5)
            try writeStringDataset("0", value: targetPath, metadataType: nil,
                                   in: targets, hdf5: h5)
        }
    }

    static func writeResultMap(
        _ map: ScalarResultMap,
        nodeName: String,
        calibration: PixelCalibration,
        in root: hid_t,
        cancellation: AnalysisCancellationToken?,
        progress: (@Sendable (Double) -> Void)?,
        hdf5 h5: HDF5WriteLibrary
    ) throws {
        try checkCancellation(cancellation)
        let group = try createGroup(nodeName, in: root, hdf5: h5)
        defer { _ = h5.h5gclose(group) }
        try writeNodeAttributes(groupType: "array", pythonClass: "RealSlice",
                                on: group, hdf5: h5)
        try writeStringAttribute("mac4dstem_kind", value: map.kind, on: group, hdf5: h5)
        try writeStringAttribute("mac4dstem_display_name", value: map.displayName,
                                 on: group, hdf5: h5)
        try writeStringAttribute("mac4dstem_value_units", value: map.valueUnits,
                                 on: group, hdf5: h5)
        try writeStringAttribute("mac4dstem_storage",
                                 value: SessionResultStorage.scalarFloat32.rawValue,
                                 on: group, hdf5: h5)
        if let value = map.pixelSizeRow {
            try writeStringAttribute("mac4dstem_pixel_size_row", value: String(value),
                                     on: group, hdf5: h5)
        }
        if let value = map.pixelSizeColumn {
            try writeStringAttribute("mac4dstem_pixel_size_column", value: String(value),
                                     on: group, hdf5: h5)
        }
        if let units = map.pixelUnits {
            try writeStringAttribute("mac4dstem_pixel_units", value: units,
                                     on: group, hdf5: h5)
        }
        if let provenance = encodeProvenance(map.provenance) {
            try writeStringAttribute("mac4dstem_provenance", value: provenance,
                                     on: group, hdf5: h5)
        }

        let dimensions = [hsize_t(map.height), hsize_t(map.width)]
        let space = dimensions.withUnsafeBufferPointer {
            h5.h5screateSimple(2, $0.baseAddress, nil)
        }
        guard space >= 0 else { throw WriterError.hdf5("creating the scalar result dataspace") }
        defer { _ = h5.h5sclose(space) }
        let dataset = "data".withCString {
            h5.h5dcreate2(group, $0, h5.nativeFloat, space, h5DefaultProperty,
                          h5DefaultProperty, h5DefaultProperty)
        }
        guard dataset >= 0 else { throw WriterError.hdf5("creating the scalar result data") }
        defer { _ = h5.h5dclose(dataset) }
        guard map.pixels.withUnsafeBytes({
            h5.h5dwrite(dataset, h5.nativeFloat, h5EntireDataspace, h5EntireDataspace,
                        h5DefaultProperty, $0.baseAddress)
        }) >= 0 else { throw WriterError.hdf5("writing the scalar result pixels") }
        // RealSlice 0.14 currently hard-codes its data units to intensity. The
        // actual display/physical units remain in the mac4DSTEM metadata.
        try writeStringAttribute("units", value: "intensity", on: dataset, hdf5: h5)

        let rowStep = map.pixelSizeRow ?? calibration.rSize ?? 1
        let columnStep = map.pixelSizeColumn ?? calibration.rSize ?? 1
        let dimUnits = map.pixelUnits ?? calibration.rUnits ?? "pixels"
        try writeDoubleVectorDataset("dim0", values: [0, rowStep], name: "Rx",
                                     units: dimUnits, in: group, hdf5: h5)
        try writeDoubleVectorDataset("dim1", values: [0, columnStep], name: "Ry",
                                     units: dimUnits, in: group, hdf5: h5)

        let bundle = try createGroup("metadatabundle", in: group, hdf5: h5)
        defer { _ = h5.h5gclose(bundle) }
        try writeStringAttribute("emd_group_type", value: "metadatabundle",
                                 on: bundle, hdf5: h5)
        let metadata = try createGroup("mac4dstem", in: bundle, hdf5: h5)
        defer { _ = h5.h5gclose(metadata) }
        try writeNodeAttributes(groupType: "metadata", pythonClass: "Metadata",
                                on: metadata, hdf5: h5)
        try writeStringDataset("kind", value: map.kind, metadataType: "string",
                               in: metadata, hdf5: h5)
        try writeStringDataset("display_name", value: map.displayName, metadataType: "string",
                               in: metadata, hdf5: h5)
        try writeStringDataset("value_units", value: map.valueUnits, metadataType: "string",
                               in: metadata, hdf5: h5)
        if let provenance = encodeProvenance(map.provenance) {
            try writeStringDataset("provenance", value: provenance,
                                   metadataType: "string", in: metadata, hdf5: h5)
        }
        progress?(1)
    }

    static func writeRGBAResultMap(
        _ map: RGBAResultMap,
        nodeName: String,
        calibration: PixelCalibration,
        in root: hid_t,
        cancellation: AnalysisCancellationToken?,
        progress: (@Sendable (Double) -> Void)?,
        hdf5 h5: HDF5WriteLibrary
    ) throws {
        try checkCancellation(cancellation)
        let group = try createGroup(nodeName, in: root, hdf5: h5)
        defer { _ = h5.h5gclose(group) }
        try writeNodeAttributes(groupType: "array", pythonClass: "Array",
                                on: group, hdf5: h5)
        try writeStringAttribute("mac4dstem_kind", value: map.kind, on: group, hdf5: h5)
        try writeStringAttribute("mac4dstem_display_name", value: map.displayName,
                                 on: group, hdf5: h5)
        try writeStringAttribute("mac4dstem_value_units", value: map.valueUnits,
                                 on: group, hdf5: h5)
        try writeStringAttribute("mac4dstem_storage",
                                 value: SessionResultStorage.rgba8.rawValue,
                                 on: group, hdf5: h5)
        if let value = map.pixelSizeRow {
            try writeStringAttribute("mac4dstem_pixel_size_row", value: String(value),
                                     on: group, hdf5: h5)
        }
        if let value = map.pixelSizeColumn {
            try writeStringAttribute("mac4dstem_pixel_size_column", value: String(value),
                                     on: group, hdf5: h5)
        }
        if let units = map.pixelUnits {
            try writeStringAttribute("mac4dstem_pixel_units", value: units,
                                     on: group, hdf5: h5)
        }
        if let provenance = encodeProvenance(map.provenance) {
            try writeStringAttribute("mac4dstem_provenance", value: provenance,
                                     on: group, hdf5: h5)
        }

        let dimensions = [hsize_t(map.height), hsize_t(map.width), 4]
        let space = dimensions.withUnsafeBufferPointer {
            h5.h5screateSimple(3, $0.baseAddress, nil)
        }
        guard space >= 0 else { throw WriterError.hdf5("creating the RGBA result dataspace") }
        defer { _ = h5.h5sclose(space) }
        let dataset = "data".withCString {
            h5.h5dcreate2(group, $0, h5.nativeUChar, space, h5DefaultProperty,
                          h5DefaultProperty, h5DefaultProperty)
        }
        guard dataset >= 0 else { throw WriterError.hdf5("creating the RGBA result data") }
        defer { _ = h5.h5dclose(dataset) }
        guard map.rgba.withUnsafeBytes({
            h5.h5dwrite(dataset, h5.nativeUChar, h5EntireDataspace, h5EntireDataspace,
                        h5DefaultProperty, $0.baseAddress)
        }) >= 0 else { throw WriterError.hdf5("writing the RGBA result pixels") }
        try writeStringAttribute("units", value: "rgba8", on: dataset, hdf5: h5)

        let rowStep = map.pixelSizeRow ?? calibration.rSize ?? 1
        let columnStep = map.pixelSizeColumn ?? calibration.rSize ?? 1
        let dimUnits = map.pixelUnits ?? calibration.rUnits ?? "pixels"
        try writeDoubleVectorDataset("dim0", values: [0, rowStep], name: "Rx",
                                     units: dimUnits, in: group, hdf5: h5)
        try writeDoubleVectorDataset("dim1", values: [0, columnStep], name: "Ry",
                                     units: dimUnits, in: group, hdf5: h5)
        try writeDoubleVectorDataset("dim2", values: [0, 1], name: "RGBA",
                                     units: "channel", in: group, hdf5: h5)

        let bundle = try createGroup("metadatabundle", in: group, hdf5: h5)
        defer { _ = h5.h5gclose(bundle) }
        try writeStringAttribute("emd_group_type", value: "metadatabundle",
                                 on: bundle, hdf5: h5)
        let metadata = try createGroup("mac4dstem", in: bundle, hdf5: h5)
        defer { _ = h5.h5gclose(metadata) }
        try writeNodeAttributes(groupType: "metadata", pythonClass: "Metadata",
                                on: metadata, hdf5: h5)
        try writeStringDataset("kind", value: map.kind, metadataType: "string",
                               in: metadata, hdf5: h5)
        try writeStringDataset("display_name", value: map.displayName,
                               metadataType: "string", in: metadata, hdf5: h5)
        try writeStringDataset("value_units", value: map.valueUnits,
                               metadataType: "string", in: metadata, hdf5: h5)
        try writeStringDataset("storage", value: SessionResultStorage.rgba8.rawValue,
                               metadataType: "string", in: metadata, hdf5: h5)
        if let provenance = encodeProvenance(map.provenance) {
            try writeStringDataset("provenance", value: provenance,
                                   metadataType: "string", in: metadata, hdf5: h5)
        }
        progress?(1)
    }

    static func writeShapeMetadata(
        scanHeight: Int, scanWidth: Int, qHeight: Int, qWidth: Int,
        in bragg: hid_t, hdf5 h5: HDF5WriteLibrary
    ) throws {
        let bundle = try createGroup("metadatabundle", in: bragg, hdf5: h5)
        defer { _ = h5.h5gclose(bundle) }
        try writeStringAttribute("emd_group_type", value: "metadatabundle", on: bundle, hdf5: h5)

        let shape = try createGroup("_braggvectors_shape", in: bundle, hdf5: h5)
        defer { _ = h5.h5gclose(shape) }
        try writeNodeAttributes(groupType: "metadata", pythonClass: "Metadata",
                                on: shape, hdf5: h5)
        try writeInt64VectorDataset("Rshape", values: [Int64(scanHeight), Int64(scanWidth)],
                                    metadataType: "tuple", in: shape, hdf5: h5)
        try writeInt64VectorDataset("Qshape", values: [Int64(qHeight), Int64(qWidth)],
                                    metadataType: "tuple", in: shape, hdf5: h5)
    }

    static func writePeakGrid(
        _ vectors: BraggVectors,
        in bragg: hid_t,
        cancellation: AnalysisCancellationToken?,
        progress: (@Sendable (Double) -> Void)?,
        hdf5 h5: HDF5WriteLibrary
    ) throws {
        let group = try createGroup("_v_uncal", in: bragg, hdf5: h5)
        defer { _ = h5.h5gclose(group) }
        try writeNodeAttributes(groupType: "custom_pointlistarray", pythonClass: "PointListArray",
                                on: group, hdf5: h5)

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

        let dimensions = [hsize_t(vectors.scanHeight), hsize_t(vectors.scanWidth)]
        let space = dimensions.withUnsafeBufferPointer {
            h5.h5screateSimple(2, $0.baseAddress, nil)
        }
        guard space >= 0 else { throw WriterError.hdf5("creating the peak-grid dataspace") }
        defer { _ = h5.h5sclose(space) }
        let dataset = "data".withCString {
            h5.h5dcreate2(group, $0, variable, space, h5DefaultProperty,
                          h5DefaultProperty, h5DefaultProperty)
        }
        guard dataset >= 0 else { throw WriterError.hdf5("creating the peak-grid dataset") }
        defer { _ = h5.h5dclose(dataset) }

        var cells = [H5VariableLength]()
        cells.reserveCapacity(vectors.peaks.count)
        var allocations = [UnsafeMutablePointer<EMDPeakRecord>]()
        allocations.reserveCapacity(vectors.peaks.count)
        defer {
            for pointer in allocations { pointer.deallocate() }
        }

        for scanY in 0..<vectors.scanHeight {
            try checkCancellation(cancellation)
            for scanX in 0..<vectors.scanWidth {
                try checkCancellation(cancellation)
                let peaks = vectors.peaks[scanY * vectors.scanWidth + scanX]
                guard !peaks.isEmpty else {
                    cells.append(H5VariableLength(length: 0, pointer: nil))
                    continue
                }
                let pointer = UnsafeMutablePointer<EMDPeakRecord>.allocate(capacity: peaks.count)
                allocations.append(pointer)
                for (index, peak) in peaks.enumerated() {
                    // AXIS CONVERSION: py4DSTEM qx is detector row; qy is column.
                    pointer[index] = EMDPeakRecord(
                        qx: Double(peak.y), qy: Double(peak.x),
                        intensity: Double(peak.intensity)
                    )
                }
                cells.append(H5VariableLength(
                    length: peaks.count, pointer: UnsafeMutableRawPointer(pointer)
                ))
            }
            progress?(Double(scanY + 1) / Double(vectors.scanHeight))
        }
        try checkCancellation(cancellation)
        let status = cells.withUnsafeMutableBytes {
            h5.h5dwrite(dataset, variable, h5EntireDataspace, h5EntireDataspace,
                        h5DefaultProperty, $0.baseAddress)
        }
        guard status >= 0 else { throw WriterError.hdf5("writing the peak grid") }
    }
}
