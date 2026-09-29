//
//  DetectorTrainingSession.swift
//  Role: the one owner of the on-device training flow's state (Phase C4b, ADR 048): the trained-model store
//        and its list, the pending review of a finished run (what the comparison sheet shows), and which
//        stored model was last made active. Held by AppState with no forwarding properties; views read
//        `detectorTraining.…`. The active model ITSELF lives on `LearnedDetectionSession` (Session layer,
//        no training types); this type is its bridge to the store: it installs the hash lookup a replay
//        uses and remembers the choice across launches.
//
//  What deliberately does NOT live here: the run (`AppState+Training.swift`), the compute
//  (`DSTEMTraining`'s `DetectorFineTuning`), the pure rules (`TrainingPolicy`) and the sheet
//  (`UI/DetectorTrainingViews.swift`).
//

import DSTEMSession
import DSTEMTraining
import Foundation
import Observation

@Observable
@MainActor
final class DetectorTrainingSession {

    /// A finished run waiting for the user's decision. The candidate package sits in `stagingDirectory`
    /// until it is saved to the store (Use) or deleted (Keep Current).
    struct Review: Identifiable {
        let id = UUID()
        var outcome: DetectorFineTuningOutcome
        var stagingDirectory: URL
        var datasetFile: String
        var datasetPath: String
        var labelsSHA256: String?
        var offer: TrainingPolicy.Offer
    }

    /// Drives the comparison sheet.
    var review: Review?
    /// True while "Use Fine-Tuned Model" compiles and saves.
    private(set) var isSaving = false
    /// Every stored model, newest first (the Model picker's rows).
    private(set) var entries: [TrainedModelStore.Entry] = []

    @ObservationIgnored private var store: TrainedModelStore?
    private let rootOverride: URL?
    @ObservationIgnored private let trash: (@Sendable (URL) throws -> Void)?

    /// `storeRoot` and `trash` are for tests; the app uses the store's defaults
    /// (`Application Support/mac4DSTEM/DiskDetectorModels`, the user's Trash).
    init(storeRoot: URL? = nil, trash: (@Sendable (URL) throws -> Void)? = nil) {
        rootOverride = storeRoot; self.trash = trash
    }

    /// Staged candidates live under the temp directory with this prefix.
    static let stagingPrefix = "mac4dstem-finetune-"

    /// The store, created on first use. Creating it makes no directory; saving a model does.
    func openStore() throws -> TrainedModelStore {
        if let store { return store }
        let opened = try trash.map { try TrainedModelStore(root: rootOverride, trash: $0) } ?? TrainedModelStore(root: rootOverride)
        store = opened
        return opened
    }

    /// Re-reads the store's list. A missing store is an empty list, never an error.
    func refresh() {
        entries = (try? openStore())?.list() ?? []
    }

    /// The stored model with this tree hash (or a prefix of at least 8 digits).
    func entry(sha256: String) -> TrainedModelStore.Entry? {
        entries.first { $0.record.sha256.hasPrefix(sha256) } ?? (try? openStore())?.entry(sha256: sha256)
    }

    static func activeModel(for entry: TrainedModelStore.Entry) -> LearnedDetectionSession.ActiveModel {
        .init(packageURL: entry.packageURL, compiledURL: entry.compiledURL, origin: LearnedDetectionSession.ActiveModel.originFineTuned,
              parentSHA256: entry.record.parentSHA256, sha256: entry.record.sha256)
    }

    // MARK: Bridge to the active model

    /// Called once by AppState: a replay can find a stored model by its hash, the model chosen last time is
    /// active again if it is still in the store, EVERY later change of the active model is remembered
    /// (including the one a replay makes), and a dataset change drops a pending review.
    func install(in learned: LearnedDetectionSession) {
        Self.sweepStagedCandidates()
        learned.modelLookup = { [weak self] sha in self?.entry(sha256: sha).map(Self.activeModel(for:)) }
        refresh()
        if let sha = remembered(), let stored = entry(sha256: sha),
           FileManager.default.fileExists(atPath: stored.packageURL.path) {
            learned.selectModel(Self.activeModel(for: stored))
        }
        learned.onModelChange = { [weak self] model in self?.remember(model?.sha256) }
        learned.onDatasetCleared = { [weak self] in self?.discardReview() }
    }

    /// Makes `entry` (nil: the bundled model) the active model, app-wide (remembered through `onModelChange`).
    func activate(_ entry: TrainedModelStore.Entry?, in learned: LearnedDetectionSession) {
        learned.selectModel(entry.map(Self.activeModel(for:)))
    }

    /// Moves a stored model to the Trash and makes the bundled model active.
    func remove(_ entry: TrainedModelStore.Entry, in learned: LearnedDetectionSession) throws {
        try openStore().remove(entry)
        refresh()
        if learned.activeModel?.sha256 == entry.record.sha256 { activate(nil, in: learned) }
    }

    /// Candidates staged by a run that never reached a decision (a quit or a crash mid-review) are removed
    /// at the next launch; a live review is dropped when its dataset goes.
    static func sweepStagedCandidates() {
        let fm = FileManager.default, tmp = fm.temporaryDirectory
        for name in (try? fm.contentsOfDirectory(atPath: tmp.path)) ?? [] where name.hasPrefix(stagingPrefix) {
            try? fm.removeItem(at: tmp.appendingPathComponent(name))
        }
    }

    /// The choice rides in a one-line file inside the store's own folder, so it is exactly as durable as the
    /// models it names and nothing outside that folder is touched (a test's `AppState` reads no defaults).
    private var rememberedURL: URL? { (try? openStore())?.root.appendingPathComponent("active.txt") }

    private func remembered() -> String? {
        guard let url = rememberedURL, let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let sha = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return sha.isEmpty ? nil : sha
    }

    private func remember(_ sha256: String?) {
        guard let url = rememberedURL else { return }
        if let sha256 {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(sha256.utf8).write(to: url, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: Review

    func present(_ review: Review) {
        discardReview()
        self.review = review
    }

    /// Drops the pending review and deletes its staged candidate.
    func discardReview() {
        if let review { try? FileManager.default.removeItem(at: review.stagingDirectory) }
        review = nil
    }

    func setSaving(_ saving: Bool) { isSaving = saving }
}
