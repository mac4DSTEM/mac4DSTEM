//
//  LoadedView.swift
//  Role: The state stage L3 ADDS — which part of the source file is loaded, what
//        the reader could push into its own I/O, and what the move into that
//        frame cost the calibration.
//
//  THIS IS THE STAGE'S `AppState` SEAM (docs/development-process.md §7, binding
//  since 2026-08-17). It follows L2's precedent — `App/DatasetResidency.swift` —
//  and for the same reason: the cheapest true seam is state the stage is adding,
//  so it starts owned rather than being prised out of a 188-property facade
//  later. `AppState` HOLDS this; there are no forwarding properties, because
//  forwarding would preserve the view API while keeping the exact property that
//  caused the problem — that every piece of code can reach every piece of state.
//
//  It publishes what was actually applied, never what was requested. Same rule
//  as `DatasetResidency`: a panel that reports the request is a panel that lies
//  the moment the request is refused.
//

import Foundation

@Observable
final class LoadedView {

    /// Which part of the source is loaded. `.fullExtent` is the shipped value —
    /// nothing sets a specification until L5's configurator.
    private(set) var specification: LoadSpecification = .fullExtent

    /// What the reader pushed into its own I/O for this view, versus applied in
    /// memory. Recorded rather than inferred, so the app never claims an I/O
    /// saving it did not get (`LoadPushdown`).
    private(set) var pushdown: LoadPushdown = .none

    /// Calibration values that could not be carried into this view, each with
    /// the reason. Empty at full extent, and empty is the honest answer there:
    /// nothing needed moving.
    private(set) var invalidatedCalibration: [CalibrationInvalidation] = []

    /// True when a real-space crop made results measured on the full scan
    /// ambiguous — the same index now names a different physical position.
    private(set) var scanIndexedResultsWereCleared = false

    /// Whether anything at all distinguishes this from opening the file whole.
    var isFullExtent: Bool { specification.isFullExtent }

    // MARK: - Publishing

    /// Record what was loaded and what the calibration move cost.
    ///
    /// Takes the outcome rather than computing it: the rules live in
    /// `CalibrationReReference`, which is pure and testable without an
    /// `AppState`, a dataset or a GPU. This type is the record, not the policy.
    func publish(
        specification: LoadSpecification,
        pushdown: LoadPushdown,
        outcome: CalibrationReReference.Outcome
    ) {
        self.specification = specification
        self.pushdown = pushdown
        invalidatedCalibration = outcome.invalidated
        scanIndexedResultsWereCleared = outcome.scanIndexedResultsAreAmbiguous
    }

    /// A new dataset is a new (absent) view. Reset explicitly rather than
    /// letting the previous file's record survive into the next one — the defect
    /// pattern `DatasetResidency.reset` exists for.
    func reset() {
        specification = .fullExtent
        pushdown = .none
        invalidatedCalibration = []
        scanIndexedResultsWereCleared = false
    }

    // MARK: - Display

    /// One line for the inspector, or nil when the whole file is loaded.
    ///
    /// Deliberately states the extent in SOURCE pixels — "rows 128–255" and not
    /// "128 rows" — because the number a person needs when deciding whether to
    /// re-run at full extent is *where* they were looking, not how much.
    var summary: String? {
        guard !specification.isFullExtent else { return nil }
        var parts: [String] = []
        if let scan = specification.scanCrop {
            parts.append("scan rows \(scan.yOffset)–\(scan.yOffset + scan.height - 1), columns \(scan.xOffset)–\(scan.xOffset + scan.width - 1)")
        }
        if let detector = specification.detectorCrop {
            parts.append("detector rows \(detector.yOffset)–\(detector.yOffset + detector.height - 1), columns \(detector.xOffset)–\(detector.xOffset + detector.width - 1)")
        }
        if specification.detectorBin > 1 {
            parts.append("binned \(specification.detectorBin)x")
        }
        return "Loaded view · " + parts.joined(separator: " · ")
    }
}
