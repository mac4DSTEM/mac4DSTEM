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
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif

@Observable
package final class LoadedView {

    // Explicit so the default initializer is `package` (synthesized ones are internal). // v2.5 step 2c
    package init() {}

    /// Which part of the source is loaded. `.fullExtent` is the shipped value —
    /// nothing sets a specification until L5's configurator.
    package private(set) var specification: LoadSpecification = .fullExtent

    /// What the reader pushed into its own I/O for this view, versus applied in
    /// memory. Recorded rather than inferred, so the app never claims an I/O
    /// saving it did not get (`LoadPushdown`).
    package private(set) var pushdown: LoadPushdown = .none

    /// Calibration values that could not be carried into this view, each with
    /// the reason. Empty at full extent, and empty is the honest answer there:
    /// nothing needed moving.
    package private(set) var invalidatedCalibration: [CalibrationInvalidation] = []

    /// P2 (2026-09-01): session-restore outcomes join the same surface as
    /// load-time invalidations — the inspector's "Not carried into this view"
    /// section is the one place a dropped calibration is explained.
    package func appendInvalidated(_ items: [CalibrationInvalidation]) {
        invalidatedCalibration.append(contentsOf: items)
    }

    /// True when a real-space crop made results measured on the full scan
    /// ambiguous — the same index now names a different physical position.
    package private(set) var scanIndexedResultsWereCleared = false

    /// Detector rows and columns dropped as the binning edge remainder.
    ///
    /// **NOT YET SHOWN ANYWHERE.** Nothing in `UI/` reads this type's display
    /// surface — not this, not `summary`, not `binningNotice`, not
    /// `invalidatedCalibration`. The intent is that the user asked for one
    /// extent and got a slightly smaller one, and that difference turns up later
    /// as an unexplained number if nobody says so; the wiring belongs with L5's
    /// configurator, where all of it becomes visible in one Track B pass.
    /// Recorded here rather than implied, because an earlier version of this
    /// comment said "stated, never silent" of a value no view reads.
    package private(set) var discardedDetectorRows = 0
    package private(set) var discardedDetectorColumns = 0

    /// Whether anything at all distinguishes this from opening the file whole.
    package var isFullExtent: Bool { specification.isFullExtent }

    // MARK: - Publishing

    /// Record what was loaded and what the calibration move cost.
    ///
    /// Takes the outcome rather than computing it: the rules live in
    /// `CalibrationReReference`, which is pure and testable without an
    /// `AppState`, a dataset or a GPU. This type is the record, not the policy.
    package func publish(
        view: LoadView,
        pushdown: LoadPushdown,
        outcome: CalibrationReReference.Outcome
    ) {
        self.specification = view.specification
        self.sourceShapeString = view.source.shapeString
        self.discardedDetectorRows = view.discardedDetectorRows
        self.discardedDetectorColumns = view.discardedDetectorColumns
        self.pushdown = pushdown
        invalidatedCalibration = outcome.invalidated
        scanIndexedResultsWereCleared = outcome.scanIndexedResultsAreAmbiguous
    }

    /// A new dataset is a new (absent) view. Reset explicitly rather than
    /// letting the previous file's record survive into the next one — the defect
    /// pattern `DatasetResidency.reset` exists for.
    package func reset() {
        specification = .fullExtent
        sourceShapeString = ""
        discardedDetectorRows = 0
        discardedDetectorColumns = 0
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
    package var summary: String? {
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
        if discardedDetectorRows > 0 || discardedDetectorColumns > 0 {
            parts.append("edge trimmed \(discardedDetectorRows) row(s), \(discardedDetectorColumns) column(s)")
        }
        return "Loaded view · " + parts.joined(separator: " · ")
    }

    /// The source dataset's own shape, for the "instead of" half of the
    /// comparison. Empty when nothing has been loaded.
    package private(set) var sourceShapeString = ""

    /// What binning did to the numbers, in the user's terms — or nil when the
    /// cube is not binned.
    ///
    /// **This has to be said, not implied.** Binning SUMS (py4DSTEM's array
    /// math, reproduced), so every intensity is `bin²` times larger and every
    /// absolute-intensity threshold moves with it — `minRelative` is relative
    /// and survives, but an absolute cut-off carried over from an unbinned run
    /// does not mean the same thing. A binned cube is a different measurement
    /// (invariant I3) and the app says so rather than leaving the user to
    /// discover it from a peak count.
    package var binningNotice: String? {
        let bin = specification.detectorBin
        guard bin > 1 else { return nil }
        var notice = "Diffraction binned \(bin)x: intensities are summed, so they are "
            + "\(bin * bin)x larger than the unbinned data, and the reciprocal pixel "
            + "size is \(bin)x coarser."
        if discardedDetectorRows > 0 || discardedDetectorColumns > 0 {
            notice += " \(discardedDetectorRows) detector row(s) and "
                + "\(discardedDetectorColumns) column(s) were trimmed from the far edge "
                + "so the extent divides by \(bin)."
        }
        return notice
    }
}
