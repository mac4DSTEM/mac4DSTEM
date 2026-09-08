//
//  DiskCentreLabels.swift
//  Role: C7 session 4's seam (docs/decisions.md, 2026-09-08 "centres, as one
//        attribute") — the one owner of hand-clicked disk-centre labels: the
//        click-mode toggle, the labelled positions for the dataset currently
//        open, and the JSON that rides the session sidecar beside calibration
//        (`mac4dstem_disk_centre_labels`, `BraggVectorEMDWriter`). Held by
//        AppState with no forwarding properties; views read
//        `diskCentreLabels.…`.
//
//  A label is a set of hand-clicked disk CENTRES at one scan position, in the
//  detector's NATIVE pixel frame — not a model-size crop, so one labels file
//  scores any model size (the same convention `tools/disk-detector/
//  label_centres.py` uses, C7 2026-09-07). The JSON this store reads and
//  writes is exactly that tool's schema, so `tools/disk-detector/evaluate.py`
//  scores app labels and tool labels alike.
//
//  What deliberately does NOT live here: the click gesture and its hit-testing
//  (`UI/ImagePanes.swift`'s `CentreLabelOverlay`), the tap-to-pixel mapping
//  (shared with `PeakOverlay`/`ApertureOverlay`), and the sidecar read/write
//  itself (`AppState`, `Support/ResultExport.swift`) — this type only holds
//  and (de)serialises the labels.
//

import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif
import Observation
import CryptoKit

@Observable
@MainActor
package final class DiskCentreLabelStore {

    // Explicit so the default initializer is `package` (synthesized ones are internal).
    package nonisolated init() {}

    /// One hand-clicked disk centre, in detector pixels: `row` = y, `col` = x.
    /// Encoded as a two-element JSON array `[row, col]`, NOT an object — the
    /// convention `label_centres.py`'s `centres: [[row, col], ...]` uses.
    package struct Centre: Sendable, Codable, Equatable {
        package var row: Float
        package var col: Float

        package init(row: Float, col: Float) {
            self.row = row
            self.col = col
        }

        package init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            row = try container.decode(Float.self)
            col = try container.decode(Float.self)
        }

        package func encode(to encoder: Encoder) throws {
            var container = encoder.unkeyedContainer()
            try container.encode(row)
            try container.encode(col)
        }
    }

    /// One scan position's labels. May carry zero centres — a position the
    /// owner looked at and found nothing to click is still a labelled
    /// position, and `label_centres.py` writes exactly that.
    package struct Position: Sendable, Codable, Equatable {
        package var ry: Int
        package var rx: Int
        package var centres: [Centre]

        package init(ry: Int, rx: Int, centres: [Centre] = []) {
            self.ry = ry
            self.rx = rx
            self.centres = centres
        }
    }

    /// The click-mode toggle (the diffraction pane's "Label centres on
    /// click"). Session-scoped, not dataset-scoped: it survives a dataset
    /// change deliberately, the same way `LearnedDetectionSession`'s
    /// `detectorClass` does — switching datasets to check something and
    /// switching back should not silently drop out of labelling mode.
    package var labelling: Bool = false
    /// `label_centres.py`'s `ingredient` (the ingredients-npz key `evaluate.py`
    /// reads the probe under) and `seed`, carried through a load → save round
    /// trip unchanged; a store that never loaded a tool file writes "app" / 0,
    /// and `evaluate.py --ingredient` names the npz key then (Gate B, 2026-09-08).
    package private(set) var ingredient: String = "app"
    package private(set) var seed: Int = 0

    /// The dataset these labels belong to — the absolute cube path and the
    /// HDF5 dataset path, exactly as `label_centres.py`'s `cube`/`dataset`
    /// fields name them. Set by `reset(filePath:datasetPath:)` on every
    /// dataset activation.
    package private(set) var filePath: String?
    package private(set) var datasetPath: String?

    /// Every labelled position for the current dataset. Kept private so
    /// mutation always goes through `add`/`removeNearest`/`clear`, which
    /// maintain the "one entry per scan position" invariant `centres(ry:rx:)`
    /// relies on.
    package private(set) var positions: [Position] = []

    /// The centres at one scan position, or empty when that position has no
    /// entry yet.
    package func centres(ry: Int, rx: Int) -> [Centre] {
        positions.first(where: { $0.ry == ry && $0.rx == rx })?.centres ?? []
    }

    /// Positions with at least one centre — the "Labelled" count the Disk
    /// centre labels group reports, distinct from `positions.count`, which
    /// would also count zero-centre entries.
    package var labelledPositionCount: Int {
        positions.reduce(0) { $1.centres.isEmpty ? $0 : $0 + 1 }
    }

    /// Every centre across every position.
    package var centreCount: Int {
        positions.reduce(0) { $0 + $1.centres.count }
    }

    package var isEmpty: Bool { centreCount == 0 }

    private func positionIndex(ry: Int, rx: Int, insertingIfMissing: Bool) -> Int? {
        if let index = positions.firstIndex(where: { $0.ry == ry && $0.rx == rx }) {
            return index
        }
        guard insertingIfMissing else { return nil }
        positions.append(Position(ry: ry, rx: rx))
        return positions.count - 1
    }

    /// Add a hand-clicked centre at a scan position, creating the position's
    /// entry if this is its first centre.
    package func add(_ centre: Centre, ry: Int, rx: Int) {
        guard let index = positionIndex(ry: ry, rx: rx, insertingIfMissing: true) else { return }
        positions[index].centres.append(centre)
    }

    /// Remove the centre closest to `centre` at the given position, provided
    /// it lies within `radius` pixels. Returns whether one was removed, so a
    /// caller (the diffraction pane's click handler) can fall back to adding
    /// a new centre when the click missed every existing one.
    package func removeNearest(to centre: Centre, within radius: Float, ry: Int, rx: Int) -> Bool {
        guard let index = positionIndex(ry: ry, rx: rx, insertingIfMissing: false) else { return false }
        var bestOffset: Int?
        var bestDistance = radius
        for (offset, candidate) in positions[index].centres.enumerated() {
            let distance = hypotf(candidate.row - centre.row, candidate.col - centre.col)
            if distance <= bestDistance {
                bestDistance = distance
                bestOffset = offset
            }
        }
        guard let removeOffset = bestOffset else { return false }
        positions[index].centres.remove(at: removeOffset)
        return true
    }

    /// Drop every centre at one scan position (the "Clear This Position"
    /// button). Leaves the position's entry in place, empty, rather than
    /// removing it — a deliberately-empty position is itself information
    /// (see `Position`'s doc comment).
    package func clear(ry: Int, rx: Int) {
        guard let index = positionIndex(ry: ry, rx: rx, insertingIfMissing: false) else { return }
        positions[index].centres.removeAll()
    }

    /// Dataset activation: drop every label and bind to the newly active
    /// dataset. The caller (`AppState`) follows this with a sidecar read
    /// through `load(from:expecting:)` when one exists.
    package func reset(filePath: String, datasetPath: String) {
        self.filePath = filePath
        self.datasetPath = datasetPath
        ingredient = "app"
        seed = 0
        positions = []
    }

    package enum LabelError: LocalizedError {
        case datasetMismatch(expected: String, found: String)
        case malformed(String)

        package var errorDescription: String? {
            switch self {
            case .datasetMismatch(let expected, let found):
                return "the sidecar's disk-centre labels belong to \(found), not \(expected) — labels are meaningful only for the dataset the sidecar sits beside"
            case .malformed(let reason):
                return "the disk-centre labels could not be read: \(reason)"
            }
        }
    }

    /// The wire schema — exactly what `tools/disk-detector/label_centres.py`
    /// writes and `evaluate.py`'s `load_labels` reads. `sha256` is optional on
    /// DECODE (a labels file with no positions yet, or one hand-edited, may
    /// lack it); `encodedJSON()` always populates it.
    private struct Document: Codable {
        var cube: String
        var dataset: String
        var ingredient: String
        var frame: String
        var seed: Int
        var positions: [Position]
        var sha256: String?
    }

    /// Encode the current labels in the exact schema `label_centres.py`
    /// writes: `{cube, dataset, ingredient: "app", frame: "native", seed: 0,
    /// positions, sha256}`.
    ///
    /// `sha256` is a hex SHA-256 over the JSON of `positions` ALONE, computed
    /// here with `JSONEncoder`'s `.sortedKeys` output and no pretty-printing
    /// — a canonical encoding, but **not byte-identical to Python's**
    /// `json.dumps(positions, sort_keys=True)`, whose default separators
    /// include a space after every `,` and `:`. The two languages will
    /// therefore compute different hashes over equal content. That is fine:
    /// `evaluate.py`'s `load_labels` only records the value it finds, it
    /// never recomputes or verifies it.
    package func encodedJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let positionsJSON = try encoder.encode(positions)
        let digest = SHA256.hash(data: positionsJSON)
        let sha256 = digest.map { String(format: "%02x", $0) }.joined()
        let document = Document(
            cube: filePath ?? "",
            dataset: datasetPath ?? "",
            ingredient: ingredient,
            frame: "native",
            seed: seed,
            positions: positions,
            sha256: sha256
        )
        return try encoder.encode(document)
    }

    /// Decode a labels JSON document without touching any store state —
    /// used both by `load(from:expecting:)` and directly by tests.
    package static func decode(
        _ data: Data
    ) throws -> (filePath: String, datasetPath: String, ingredient: String, seed: Int, positions: [Position]) {
        do {
            let document = try JSONDecoder().decode(Document.self, from: data)
            return (document.cube, document.dataset, document.ingredient, document.seed, document.positions)
        } catch let error as LabelError {
            throw error
        } catch {
            throw LabelError.malformed(error.localizedDescription)
        }
    }

    /// Decode `data` and adopt it, but ONLY when its recorded cube path
    /// matches `filePath` — labels clicked against one dataset are meaningless
    /// replayed onto another. On a mismatch (or a malformed document) this
    /// throws and changes nothing: the caller (`AppState`, right after
    /// `reset(filePath:datasetPath:)`) is left with the empty store `reset`
    /// already produced, never a partial or wrong-dataset one.
    package func load(from data: Data, expecting filePath: String) throws {
        let decoded = try Self.decode(data)
        guard decoded.filePath == filePath else {
            throw LabelError.datasetMismatch(expected: filePath, found: decoded.filePath)
        }
        self.filePath = decoded.filePath
        self.datasetPath = decoded.datasetPath
        ingredient = decoded.ingredient
        seed = decoded.seed
        positions = decoded.positions
    }

    /// Write the current labels to `<datasetName>-centres-<stamp>.json` under
    /// `folder`, creating the folder if needed, and return the file's URL.
    /// `stamp` is an ISO 8601 timestamp with the colons stripped (`:` is not
    /// safe in a filename).
    package func exportForFineTuning(to folder: URL, datasetName: String) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "")
        let url = folder.appendingPathComponent("\(datasetName)-centres-\(stamp).json")
        try encodedJSON().write(to: url, options: .atomic)
        return url
    }
}
