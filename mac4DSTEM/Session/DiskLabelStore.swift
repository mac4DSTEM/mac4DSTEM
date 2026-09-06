//
//  DiskLabelStore.swift
//  Role: v3-plan §3a step 5's seam — the one owner of the confirmed/rejected
//        learned-disk-detection patterns (docs/v3-plan.md §3a "Owner of
//        state": "the session sidecar", decided 2026-09-06). Held by AppState
//        with no forwarding properties; views read `diskLabels.…`.
//
//  A label is a scan position + detector settings a person judged by eye: the
//  learned candidates at that position were either right (confirmed) or wrong
//  (rejected). The store is deliberately dumb — it records verdicts and hands
//  them back; it runs no detector and reads no pixels. `AppState+DiskLabels`
//  is the seam that fills in `filePath`/`scanX`/`scanY`/`peaks` from the live
//  session and persists the result into the session sidecar HDF5 (the
//  plan's owner) and, on request, into a local export folder for fine-tuning.
//

import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif
import Observation

@Observable
@MainActor
package final class DiskLabelStore {

    // Explicit so the default initializer is `package` (synthesized ones are internal).
    package nonisolated init() {}

    /// One person's verdict on the learned candidates at one scan position,
    /// under one detector configuration.
    package struct Label: Sendable, Codable, Identifiable, Equatable {
        package let id: UUID
        /// The dataset this position was labelled on — an absolute path, the
        /// same identity `RecentDataset`/`DatasetRecoveryRecord` use. Carried
        /// per-label (not just per-store) because a fine-tuning export
        /// (`exportForFineTuning`) must say which cube each pattern came
        /// from, and because a label decoded back from a sidecar is only
        /// meaningful for the dataset that sidecar sits beside.
        package var filePath: String
        package var scanX: Int
        package var scanY: Int
        /// `DetectorClass.provenanceID` ("classical" / "learned") — a label
        /// only ever judges the LEARNED detector's candidates in practice
        /// (v3-plan §3a), but the field is not narrowed to that one case: a
        /// verdict is meaningless without saying which detector produced the
        /// candidates it judges, the same reason `detectionProvenance`
        /// carries `detector_class` on every full-scan result.
        package var detectorClass: String
        /// `LearnedDetectionSession.assetSHA256` at the moment of labelling —
        /// which weights made the candidates this verdict judges. Every
        /// retrain is a new hash (v3-plan §3a), so a label is worthless
        /// without it: "confirmed" against weights nobody can identify later
        /// is not evidence of anything.
        package var weightsHash: String
        /// The learned pick threshold in effect when the candidates were
        /// generated — a candidate list is only reproducible together with
        /// the threshold that filtered the heatmap into it.
        package var threshold: Float
        package var verdict: Verdict
        /// The learned candidates themselves, in detector pixels — exactly
        /// `AppState.currentPeaks` at the moment of labelling, so a fine-
        /// tuning export carries the actual positions judged rather than a
        /// verdict with nothing to train against.
        package var peaks: [Peak]
        package var notedAt: Date

        // Explicit so the memberwise initializer is `package` (synthesized ones are internal).
        package init(
            id: UUID = UUID(), filePath: String, scanX: Int, scanY: Int,
            detectorClass: String, weightsHash: String, threshold: Float,
            verdict: Verdict, peaks: [Peak], notedAt: Date
        ) {
            self.id = id
            self.filePath = filePath
            self.scanX = scanX
            self.scanY = scanY
            self.detectorClass = detectorClass
            self.weightsHash = weightsHash
            self.threshold = threshold
            self.verdict = verdict
            self.peaks = peaks
            self.notedAt = notedAt
        }

        package enum Verdict: String, Sendable, Codable {
            case confirmed
            case rejected
        }

        /// One candidate disk, in detector pixels — `BraggPeak` minus the
        /// `Sendable`-but-not-`Codable` friction: `BraggPeak` lives in
        /// `Core/Analysis/DiskDetection.swift` as a hot-path compute type
        /// with no reason to carry `Codable`, and a label needs to survive
        /// JSON round-trips. A label's `peaks` are constructed from
        /// `BraggPeak`s field-for-field at the call site (`AppState+DiskLabels`).
        package struct Peak: Sendable, Codable, Equatable {
            package var x: Float
            package var y: Float
            package var intensity: Float

            package init(x: Float, y: Float, intensity: Float) {
                self.x = x
                self.y = y
                self.intensity = intensity
            }
        }

        /// Same scan position, same file, same detector — a second verdict
        /// at this position replaces the first rather than accumulating a
        /// history nobody reads. Weights/threshold are NOT part of the key:
        /// re-labelling the same position after a retrain (a new
        /// `weightsHash`) still means "this is now my verdict for this
        /// position," not "and also keep the old one."
        fileprivate var matchKey: String { "\(filePath)|\(scanX)|\(scanY)|\(detectorClass)" }
    }

    /// Every recorded label, most-recently-touched order is NOT guaranteed —
    /// `record` replaces in place, so a re-confirmed position keeps its
    /// original array position. Nothing here currently needs the ordering;
    /// said explicitly so a future reader does not assume it.
    package private(set) var labels: [Label] = []

    /// Record `label`, replacing any existing label at the same file + scan
    /// position + detector class (see `Label.matchKey`).
    package func record(_ label: Label) {
        if let index = labels.firstIndex(where: { $0.matchKey == label.matchKey }) {
            labels[index] = label
        } else {
            labels.append(label)
        }
    }

    package func remove(id: Label.ID) {
        labels.removeAll { $0.id == id }
    }

    /// Dataset activation: labels belong to the dataset whose sidecar they
    /// came from, so a reopen with no sidecar (or a different dataset
    /// entirely) must not leave the previous one's labels on screen.
    /// `AppState.loadDiskLabelsFromSessionSidecar` calls this unconditionally
    /// before repopulating, which is what makes "no sidecar found" and "wrong
    /// dataset's labels" the same safe empty state rather than two states
    /// only one of which is handled.
    package func clear() {
        labels.removeAll()
    }

    package func count(for verdict: Label.Verdict) -> Int {
        labels.filter { $0.verdict == verdict }.count
    }

    /// The label at this scan position, if one has been recorded — not
    /// filtered by file, because in practice this store holds only the
    /// active dataset's labels (`clear()` above runs on every activation
    /// before the active sidecar's own labels are loaded back in). A caller
    /// that ever needs to hold two datasets' labels at once must filter on
    /// `filePath` itself; nothing here does that today.
    package func label(at scanX: Int, scanY: Int) -> Label? {
        labels.first { $0.scanX == scanX && $0.scanY == scanY }
    }

    // MARK: - Persistence (session sidecar)

    /// One JSON array of `Label`, the whole store in one blob.
    ///
    /// **Why one blob and not one HDF5 dataset row per label**: the sidecar
    /// already carries two other pieces of structured session state this way
    /// — the load specification and the replay record
    /// (`BraggVectorEMDWriter`'s `mac4dstem_load_specification` and
    /// `mac4dstem_replay_record` string attributes) — a few hundred labels at
    /// a few tens of bytes each is a trivial string, and a bespoke HDF5
    /// schema (a labels group, a peaks dataset per label, a scan-position
    /// index) buys nothing a session sidecar this size needs. It costs
    /// something to say clearly what it is NOT: a training-data format. The
    /// fine-tuning export (`exportForFineTuning`) is the format meant to be
    /// read by the training tooling in `tools/disk-detector/`; this one is
    /// meant to be read back by this same type on the next launch.
    package func encodedJSON() throws -> Data {
        try JSONEncoder().encode(labels)
    }

    /// The inverse of `encodedJSON()` — decodes the array this type would
    /// have written, for `AppState.loadDiskLabelsFromSessionSidecar` to feed
    /// back through `record(_:)` one at a time (so the same replace-in-place
    /// rule applies to a restore as to a live label).
    package static func decode(_ data: Data) throws -> [Label] {
        try JSONDecoder().decode([Label].self, from: data)
    }

    // MARK: - Fine-tuning export

    /// Write every recorded label to `<folderURL>/<datasetName>-<stamp>.json`
    /// (`stamp` = `yyyyMMdd-HHmm`) as `{version: 1, dataset, labels}` — the
    /// format v3-plan §3a's fine-tuning step reads (docs/v3-plan.md §3a: "a
    /// fine-tuning export writes them to a local, gitignored folder under
    /// `tools/disk-detector/`"). This store never writes into the repo
    /// itself — the app has no repo path, and would not be right to assume
    /// one even if it did (docs/v3-plan.md §3a: "they are the owner's data").
    /// `AppState.exportDiskLabelsForFineTuning` writes to
    /// `~/Documents/mac4DSTEM/disk-labels/`; the owner copies from there into
    /// `tools/disk-detector/labels/` (gitignored) when a run is ready.
    package func exportForFineTuning(to folderURL: URL, datasetName: String) throws -> URL {
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let stamp = Self.exportStamp.string(from: Date())
        let url = folderURL.appendingPathComponent("\(datasetName)-\(stamp).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(FineTuningExport(version: 1, dataset: datasetName, labels: labels))
        try data.write(to: url, options: .atomic)
        return url
    }

    private static let exportStamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmm"
        return f
    }()

    private struct FineTuningExport: Encodable {
        let version: Int
        let dataset: String
        let labels: [Label]
    }
}
