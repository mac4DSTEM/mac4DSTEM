//
//  DiffractionGroupsProduct.swift
//  Role: owns the classical diffraction-grouping result and its run controls
//        (docs/ai-ml/README.md §6 — PCA + k-means on box-binned patterns,
//        the baseline before any learned encoder). Mirrors StrainProduct's
//        seam: `AppState+DiffractionGroups.swift` is the only writer; views
//        read `diffractionGroups.…` directly, with no forwarding properties
//        on AppState itself.
//

import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif
import Observation

@Observable
@MainActor
package final class DiffractionGroupsProduct {

    // Explicit so the default initializer is `package` (synthesized ones are internal). // v2.5 step 2c
    package nonisolated init() {}

    /// Run controls, read by the settings panel and by
    /// `AppState.runDiffractionGroups()`. Deliberately NOT cleared on
    /// dataset activation — matches `StrainProduct`'s run controls, so a
    /// setting the user picked survives switching datasets.
    package var settings = DiffractionEmbedding.Settings()

    /// The retained result of the last successful run. Survives task
    /// navigation like `StrainProduct.map`; only `publish`/`clear` replace it.
    package private(set) var result: DiffractionEmbedding.Result?

    /// The scan position `AppState.showSimilarityToCurrentPosition()` last
    /// computed against, so the settings panel can name it beside the
    /// similarity map it published.
    package var referencePosition: Int?

    /// The settings the retained `result` was actually computed with — not
    /// the live `settings`, which the user may have changed since.
    ///
    /// Two things read it. The panel's provenance rows, which must name the
    /// binned size and seed of the RUN (`Result` carries neither). And
    /// `isStale`: raising Groups from 4 to 8 left the k=4 group sizes on
    /// screen under `Groups 8` with nothing saying they belonged to an
    /// earlier run (owner's drive 2026-09-06, `drive-groups` defect 5).
    package private(set) var lastRunSettings: DiffractionEmbedding.Settings?

    /// Whether the readout describes a run made with settings that have since
    /// changed — the same "retained, but its inputs moved" verdict
    /// `TaskProductState.staleDiskSettings` carries for the Bragg-disk chain,
    /// expressed here against this task's own inputs.
    package var isStale: Bool {
        guard let lastRunSettings else { return false }
        return lastRunSettings != settings
    }

    /// Publish a computed result.
    ///
    /// The similarity reference SURVIVES a rerun on the same scan. It is an
    /// index into the scan grid, and re-running with a different k does not
    /// move it; nilling it unconditionally left the published similarity
    /// product in Results named for a coordinate the panel could no longer
    /// show (owner's drive 2026-09-06, `drive-groups` defect 4). Only a result
    /// of a DIFFERENT scan shape can invalidate the index, and that is the one
    /// case still cleared here.
    /// `ranWith` is the settings snapshot the RUN took, passed in rather than
    /// re-read from `settings` here, so a value edited while the run was in
    /// flight cannot be recorded as the one that produced the result.
    package func publish(
        _ newResult: DiffractionEmbedding.Result, ranWith: DiffractionEmbedding.Settings
    ) {
        if let previous = result,
           previous.scanWidth != newResult.scanWidth
            || previous.scanHeight != newResult.scanHeight {
            referencePosition = nil
        }
        result = newResult
        lastRunSettings = ranWith
    }

    /// The published group map's display name — the pane title, the Session
    /// row, the Results entry and the sidecar entry all read it, so the k must
    /// be in it: the literal `Diffraction groups (k)` made a k=4 run and a k=8
    /// run indistinguishable everywhere they were listed (owner's drive
    /// 2026-09-06, `drive-groups` defect 2). Extracted here so it is pinned by
    /// a test rather than by a string in an orchestration method.
    package nonisolated static func groupMapDisplayName(groups: Int) -> String {
        "Diffraction groups (k = \(groups))"
    }

    /// Dataset activation: the result and its reference position die with
    /// the dataset; `settings` survives (see above).
    package func clear() {
        result = nil
        lastRunSettings = nil
        referencePosition = nil
    }
}
