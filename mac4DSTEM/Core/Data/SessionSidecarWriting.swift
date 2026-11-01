import Foundation
import FormatoCore
import FormatoHDF5
import SpectroCore

//
//  SessionSidecarWriting.swift
//  Role: build a session sidecar file: what the file MEANS to this app (which attributes it carries, which saved objects survive a
//        rewrite, the lineage and replay rules) over FormatoKit 0.8.0's `HDF5NewFile.write` and `HDF5WriteSession` (the EMD header and
//        root, the calibration, the scalar and RGBA result nodes, the BraggVectors object, `copyObject` for what the file it replaces
//        carries over). The scratch build and the atomic publish are the kit's. Split out of BraggVectorEMDWriter.swift (2026-10-20).
//

nonisolated extension BraggVectorEMDWriter {
    /// Builds the whole sidecar into `session` (the kit's scratch file; the kit publishes it over the destination). `existing` is the
    /// sidecar being rewritten, read through `HDF5Reader` and copied from object by object.
    static func writeFile(
        into session: HDF5WriteSession,
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
        source: SessionSourceStamp?,
        diskCentreLabelsJSON: String?,
        supportedSchema: Int,
        vectorsWithoutRecipe: Bool = false,
        cancellation: AnalysisCancellationToken?,
        progress: (@Sendable (Double) -> Void)?
    ) throws {
        // An existing sidecar that cannot be opened (locked by a read/write reader such as HDFView, damaged,
        // unreadable) is an ERROR, never "no file": treating it as absent built a fresh file and renamed it over
        // every saved result, the vectors, the labels and the recipe (review 2026-10-02 a4).
        var existingFile: SidecarFile?
        if let source = existing {
            existingFile = try SidecarFile(opening: source, operation: "opening the existing session sidecar")
        }

        // Match emdfile's default without silently embedding the Mac account name (`authoringUser` empty).
        try session.writeEMDFileHeader(EMDFileHeader(authoringProgram: "mac4DSTEM", authoringUser: "", uuid: UUID().uuidString))
        try session.createEMDRoot(SessionSidecarFormat.rootGroupName)

        var existingResults: [SessionResultDescriptor] = []
        if let existingFile, existingFile.isGroup(rootPath) {
            // A rewrite is a read followed by a write: a file whose
            // marker demands a newer reader must be REFUSED here too,
            // or a save would silently drop the newer content this
            // build cannot see and then stamp the marker back DOWN —
            // a mangled file claiming to be safely readable
            // (Gate B-lite F6). The publish is atomic, so a refusal
            // leaves the original untouched. // v2 S5
            try enforceMinimumReader(existingFile, supportedSchema: supportedSchema)
            existingResults = try readResultDescriptors(existingFile)
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
        if replayRecord?.isEmpty ?? true, let existingFile, existingFile.isGroup(rootPath) {
            preservedReplayJSON = try existingFile.stringAttribute(replayRecordAttribute, at: rootPath)
            if replayRecord == nil {
                do {
                    preservedLineageJSON = try existingFile.stringAttribute(lineageAttribute, at: rootPath)
                } catch WriterError.malformedAttribute {
                    // An unreadable lineage cannot be carried forward and
                    // must not block an unrelated save; the reader refuses
                    // such a file by name, so it was never being used.
                    preservedLineageJSON = nil
                }
            }
        }
        // Preserve existing disk-centre labels the same way, for the same
        // reason (C7 session 4): a calibration save is not a labelling
        // session, and a caller that passes nil here is saying nothing about
        // labels, not "there are none."
        var preservedLabelsJSON: String?
        if diskCentreLabelsJSON == nil, let existingFile, existingFile.isGroup(rootPath) {
            preservedLabelsJSON = try existingFile.stringAttribute(diskCentreLabelsAttribute, at: rootPath)
        }
        // The source stamp, by the same rule: the caller's wins, else the file's own is carried over (read like the
        // reader reads it: an unreadable one is absent, not a reason to refuse the save).
        var preservedSourceJSON: String?
        if source == nil, let existingFile, existingFile.isGroup(rootPath) {
            preservedSourceJSON = (try? existingFile.stringAttribute(sourceAttribute, at: rootPath)) ?? nil
        }

        let braggPath = "\(rootPath)/braggvectors"
        let canCopyBragg = vectors == nil && existingFile?.exists(braggPath) == true
        try session.writeEMDCalibration(
            emdCalibration(calibration), inRoot: rootPath,
            targetPath: vectors != nil || canCopyBragg ? "/braggvectors" : nil, booleanStorage: .uint8
        )

        if let vectors {
            try checkCancellation(cancellation)
            var groupAttributes: [String: String] = [:]
            if let provenance = encodeProvenance(vectors.detectionProvenance) {
                groupAttributes["mac4dstem_detection_provenance"] = provenance
            }
            // Vectors handed to a save belong to the view the save records (detected on it, or restored onto it
            // only when that view matched). Unstated (nil), the root's view stands for them, as before.
            if let json = loadSpecification?.jsonString {
                groupAttributes[peaksViewAttribute] = json
            }
            // The kit's `.appImageXY` is this app's axis conversion: the peak's x is the detector column, y the row, and py4DSTEM's
            // stored qx is the row.
            let peaks = vectors.peaks.map { cell in
                cell.map { FormatoHDF5.BraggPeak(qx: Double($0.x), qy: Double($0.y), intensity: Double($0.intensity)) }
            }
            try session.writeBraggVectors(
                peaks: peaks,
                scan: BraggGridShape(rows: vectors.scanHeight, columns: vectors.scanWidth),
                detector: BraggGridShape(rows: qHeight, columns: qWidth),
                inRoot: rootPath, nodeName: "braggvectors", convention: .appImageXY, groupAttributes: groupAttributes,
                cancelled: { cancellation?.isCancelled == true }
            )
            progress?(1)
        } else if canCopyBragg, let existing {
            try checkCancellation(cancellation)
            try session.copyObject(from: existing, braggPath, to: braggPath)
            // A carried grid keeps the view it was detected on. A grid written before the stamp takes the view the
            // file it comes from records (`recordedView`), so a save from another view cannot relabel it.
            // A stamp or root specification that cannot be read leaves the grid as it was: the save goes on, and the
            // reader refuses a mangled stamp by name on the next restore.
            if let existingFile,
               ((try? existingFile.stringAttribute(peaksViewAttribute, at: braggPath)) ?? nil) == nil,
               let view = try? Self.recordedView(of: existingFile), let json = view.jsonString {
                try session.setVariableLengthTextAttribute(peaksViewAttribute, on: braggPath, json)
            }
        }

        // Preserve root children that this schema does not understand (for
        // example emdfile Plot nodes or third-party analysis objects). Known
        // mutable objects are rebuilt/copied below; unknown objects move as
        // opaque HDF5 objects so an app save is not destructive to external
        // tooling.
        if let existing, let existingFile, existingFile.isGroup(rootPath) {
            let reserved = Set(["metadatabundle", "braggvectors"] + existingResults.map(\.id))
            for name in existingFile.children(of: rootPath) where !reserved.contains(name) {
                try checkCancellation(cancellation)
                try session.copyObject(from: existing, "\(rootPath)/\(name)", to: "\(rootPath)/\(name)")
            }
        }

        var resultNodeNames: [String] = []
        var copiedNodeNames = Set<String>()
        let replacementKind = map?.kind ?? rgbaMap?.kind ?? removingKind
        if let existing {
            for descriptor in existingResults where descriptor.kind != replacementKind {
                try checkCancellation(cancellation)
                let targetName = resultNodeName(forKind: descriptor.kind)
                guard copiedNodeNames.insert(targetName).inserted else { continue }
                try session.copyObject(from: existing, "\(rootPath)/\(descriptor.id)", to: "\(rootPath)/\(targetName)")
                resultNodeNames.append(targetName)
            }
        }
        if let map {
            try checkCancellation(cancellation)
            let nodeName = resultNodeName(forKind: map.kind)
            try session.writeEMDScalarMap(scalarEMDMap(map, nodeName: nodeName, calibration: calibration), inRoot: rootPath)
            resultNodeNames.append(nodeName)
            progress?(1)
        }
        if let rgbaMap {
            try checkCancellation(cancellation)
            let nodeName = resultNodeName(forKind: rgbaMap.kind)
            try session.writeEMDRGBAMap(rgbaEMDMap(rgbaMap, nodeName: nodeName, calibration: calibration), inRoot: rootPath)
            resultNodeNames.append(nodeName)
            progress?(1)
        }
        func setText(_ name: String, _ value: String) throws {
            try session.setVariableLengthTextAttribute(name, on: rootPath, value)
        }
        if let specification = loadSpecification, !specification.isFullExtent,
           let json = specification.jsonString {
            // Written whenever a session is published from a reduced view, even
            // with no results yet: the specification is what makes a product
            // traceable to *file + view*, and a calibration saved from a binned
            // cube is already a product of that view.
            try setText(loadSpecificationAttribute, json)
        }
        // The schema attribute is the file's IDENTITY marker, not a result
        // manifest, so it is written on every file this writer produces —
        // a calibration-only sidecar is still a sidecar. Tying it to the
        // result-nodes condition below left exactly this shape (8.9 kB,
        // calibration only, opened twice on 2026-08-19) unrecognisable to the
        // open path's sidecar check.
        // Nothing reads this attribute to mean "has results"; the inventory
        // reads `resultNodesAttribute`.
        try setText(schemaAttribute, sessionSchemaVersion)
        // The minimum-reader marker, on every file: the oldest schema
        // that interprets THIS file without misreading it — 6 when a reduced
        // specification is recorded (dangerous to ignore), 5 otherwise, so a
        // marker-checking reader never refuses a file it could read safely.
        try setText(minimumReaderAttribute, String(minimumReaderSchema(for: loadSpecification)))
        // Which source this session belongs to: additive, so the minimum-reader marker above does not move with it.
        if let json = source?.jsonString ?? preservedSourceJSON { try setText(sourceAttribute, json) }
        // The replay record: the caller's live record wins; failing that, the
        // record the existing file already carried survives the rewrite.
        let recordJSON = replayRecord.flatMap { $0.isEmpty ? nil : $0.jsonString }
        let recordToWrite = recordJSON ?? preservedReplayJSON
        if let json = recordToWrite { try setText(replayRecordAttribute, json) }
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
                try setText(lineageAttribute, candidate)
            case .failure(let omission):
                lineageOmission = omission.description
            }
        } else if replayRecord?.lineage != nil {
            lineageOmission = "The lineage was not saved — it could not be encoded."
        }
        // Disks with no recipe behind them (`disksWithoutRecipeAttribute`):
        // fresh vectors carry the caller's word; copied vectors carry the word
        // of the file they are copied from, which says so either by this
        // marker or by predating the replay record (no record, stamp below 6
        // or none). Never inferred from the record being written: a current
        // session's disks without a disk step stay refused, as before.
        let disksWithoutRecipe: Bool
        if vectors != nil {
            disksWithoutRecipe = vectorsWithoutRecipe
        } else if canCopyBragg, let existingFile {
            disksWithoutRecipe = existingDisksLackRecipe(existingFile)
        } else {
            disksWithoutRecipe = false
        }
        if disksWithoutRecipe {
            try setText(disksWithoutRecipeAttribute, "restored from a session saved before the replay record")
        }
        // Same rule as the replay record immediately above: the caller's
        // live value wins, otherwise the labels already on the file survive
        // the rewrite. // C7 session 4
        if let json = diskCentreLabelsJSON ?? preservedLabelsJSON { try setText(diskCentreLabelsAttribute, json) }
        if !resultNodeNames.isEmpty {
            try setText(resultNodesAttribute, resultNodeNames.joined(separator: "\n"))
            try setText(currentResultAttribute, resultNodeNames.last!)
        }
        progress?(1)
        try checkCancellation(cancellation)   // after the last progress tick: a cancel raised by it still stops before the publish
    }

    /// True when the stored disks of `file` have no recipe behind them: it carries the marker, or it predates the replay
    /// record (`SessionPeakRestore.predatesReplayRecord`'s rule, read like the reader reads the stamp: garbage is absent).
    static func existingDisksLackRecipe(_ file: SidecarFile) -> Bool {
        if ((try? file.stringAttribute(disksWithoutRecipeAttribute, at: rootPath)) ?? nil) != nil { return true }
        if ((try? file.stringAttribute(replayRecordAttribute, at: rootPath)) ?? nil) != nil { return false }
        let stamp = ((try? file.stringAttribute(schemaAttribute, at: rootPath)) ?? nil).flatMap { Int($0) }
        guard let stamp else { return true }
        return stamp < SessionViewRecord.firstSchemaThatRecordsTheView
    }

    /// The app's calibration as the kit's EMD calibration (py4DSTEM's `Calibration` entries). The rotation in degrees is the kit's
    /// `radians * 180 / pi`; `QR_flip` is written as the app always wrote it (`booleanStorage: .uint8`, the callers pass it).
    static func emdCalibration(_ calibration: PixelCalibration) -> EMDCalibration {
        EMDCalibration(
            qPixelSize: calibration.qSize, qPixelUnits: calibration.qUnits,
            rPixelSize: calibration.rSize, rPixelUnits: calibration.rUnits,
            qrFlip: calibration.qrFlip, qrRotation: calibration.qrRotationRad,
            qrRotationConvention: calibration.qrRotationConvention,
            qx0Mean: calibration.qx0Mean, qy0Mean: calibration.qy0Mean,
            ellipseA: calibration.ellipseA, ellipseB: calibration.ellipseB, ellipseTheta: calibration.ellipseTheta,
            probeSemiangle: calibration.probeSemiangle,
            originMaps: calibration.originMaps.map {
                EMDOriginMaps(shape: $0.shape, fittedQX: $0.fittedQX, fittedQY: $0.fittedQY,
                              measuredQX: $0.measuredQX, measuredQY: $0.measuredQY)
            }
        )
    }

    /// A scalar result as the kit's `RealSlice` node: `data` float32, `dim0`/`dim1` from `mapAxes`, the app's attributes and metadata.
    static func scalarEMDMap(_ map: ScalarResultMap, nodeName: String, calibration: PixelCalibration) -> EMDScalarMap {
        EMDScalarMap(
            nodeName: nodeName, width: map.width, height: map.height, values: map.pixels,
            axes: mapAxes(rowStep: map.pixelSizeRow, columnStep: map.pixelSizeColumn, units: map.pixelUnits, calibration: calibration),
            annotations: mapAnnotations(
                kind: map.kind, displayName: map.displayName, valueUnits: map.valueUnits, storage: .scalarFloat32,
                pixelSizeRow: map.pixelSizeRow, pixelSizeColumn: map.pixelSizeColumn, pixelUnits: map.pixelUnits,
                provenance: map.provenance))
    }

    /// An RGBA result as the kit's `Array` node (`data` uint8, `height x width x 4`), with the storage also in its metadata.
    static func rgbaEMDMap(_ map: RGBAResultMap, nodeName: String, calibration: PixelCalibration) -> EMDRGBAMap {
        EMDRGBAMap(
            nodeName: nodeName, width: map.width, height: map.height, rgba: map.rgba,
            axes: mapAxes(rowStep: map.pixelSizeRow, columnStep: map.pixelSizeColumn, units: map.pixelUnits, calibration: calibration),
            annotations: mapAnnotations(
                kind: map.kind, displayName: map.displayName, valueUnits: map.valueUnits, storage: .rgba8,
                pixelSizeRow: map.pixelSizeRow, pixelSizeColumn: map.pixelSizeColumn, pixelUnits: map.pixelUnits,
                provenance: map.provenance, storageInMetadata: true))
    }

    /// The axes of a result map: the map's own step, else the session's real-space step, else 1 (and the same for the units).
    private static func mapAxes(rowStep: Double?, columnStep: Double?, units: String?,
                                calibration: PixelCalibration) -> EMDMapAxes {
        EMDMapAxes(rowStep: rowStep ?? calibration.rSize ?? 1, columnStep: columnStep ?? calibration.rSize ?? 1,
                   units: units ?? calibration.rUnits ?? "pixels")
    }

    /// The `mac4dstem_*` attributes on a result's group and its `metadatabundle/mac4dstem` entries: what the app's schema says about a node.
    private static func mapAnnotations(
        kind: String, displayName: String, valueUnits: String, storage: SessionResultStorage,
        pixelSizeRow: Double?, pixelSizeColumn: Double?, pixelUnits: String?, provenance: [String: String],
        storageInMetadata: Bool = false
    ) -> EMDMapAnnotations {
        var attributes: [String: HDF5AttributeValue] = [
            "mac4dstem_kind": .text(kind), "mac4dstem_display_name": .text(displayName),
            "mac4dstem_value_units": .text(valueUnits), "mac4dstem_storage": .text(storage.rawValue),
        ]
        if let pixelSizeRow { attributes["mac4dstem_pixel_size_row"] = .text(String(pixelSizeRow)) }
        if let pixelSizeColumn { attributes["mac4dstem_pixel_size_column"] = .text(String(pixelSizeColumn)) }
        if let pixelUnits { attributes["mac4dstem_pixel_units"] = .text(pixelUnits) }
        var metadata = ["kind": kind, "display_name": displayName, "value_units": valueUnits]
        if storageInMetadata { metadata["storage"] = storage.rawValue }
        if let json = encodeProvenance(provenance) {
            attributes["mac4dstem_provenance"] = .text(json)
            metadata["provenance"] = json
        }
        return EMDMapAnnotations(groupAttributes: attributes, metadataName: "mac4dstem", metadata: metadata)
    }

    /// The view an existing sidecar's peak grid was detected on, when the grid does not say: the file's specification
    /// attribute, else the whole file. That is the writer's own statement from schema 6 on, and the reading the restore
    /// gives a schema-5 file that records no view (`SessionPeakRestore`: a reduced view was always recorded, so an
    /// unrecorded one is the whole file). A mangled specification is refused by name, as the reader refuses it.
    static func recordedView(of file: SidecarFile) throws -> LoadSpecification {
        guard let json = try file.stringAttribute(loadSpecificationAttribute, at: rootPath) else { return .fullExtent }
        guard let decoded = LoadSpecification.decoded(from: json) else {
            throw WriterError.malformedAttribute(name: loadSpecificationAttribute)
        }
        return decoded
    }
}
