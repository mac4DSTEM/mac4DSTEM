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

    /// Publish a computed result. A fresh grouping invalidates any similarity
    /// map computed against the PREVIOUS result's coordinate space.
    package func publish(_ newResult: DiffractionEmbedding.Result) {
        result = newResult
        referencePosition = nil
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
        referencePosition = nil
    }
}
