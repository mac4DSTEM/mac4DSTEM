//
//  PrecipitateClassificationProduct.swift
//  Role: owns the retained spatial result of a class map — objects, per-class
//        pixel counts and density. AppState composes this owner without
//        forwarding properties. `AppState+PhaseMapping.swift` is the first
//        writer, over the vector-matched phase map; the pre-registered
//        full-diffraction-pattern classification route
//        (`docs/v3-features.md#precipitate-classification` §2) would be a
//        second writer of the same owner, still unbuilt.
//

import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif
import Observation

/// The Session boundary for `docs/v3-features.md#precipitate-classification` §3.
///
/// It owns only a published `ClassMapObjects` value — it does not classify
/// anything itself, publish a view, or export. It makes no validation claim
/// of its own either: a writer's own result carries whatever validation
/// status its source already has (today, the phase map's `validation:
/// "none"`), and this type does not add or remove one.
@Observable
@MainActor
package final class PrecipitateClassificationProduct {

    // Explicit so the default initializer is `package` (synthesized ones are internal).
    package nonisolated init() {}

    /// The result of a successful classified scan. Only `publish` and
    /// `clear` replace it, so it cannot outlive the dataset it describes.
    package private(set) var result: PrecipitateSegmentation.ClassMapObjects?

    /// The reader's minimum object size in scan pixels; 1 keeps every
    /// object. Smaller objects stay listed and drawn (dimmed) but leave the
    /// counted statistics (`PrecipitateObjectReport`). A property of the
    /// dataset the reader judges, never a shipped cut: the published truth's
    /// own cuts were 4, 782 and 10 px on its dataset. Kept across datasets,
    /// as a reader analysing a series expects.
    package var minimumObjectAreaPx: Int = 1 {
        didSet { if minimumObjectAreaPx < 1 { minimumObjectAreaPx = 1 } }
    }

    /// True while a classification is computing off the main actor.
    package private(set) var isComputing = false
    private var generation = 0

    /// Publish a spatial result computed by whichever route produced it —
    /// today, `AppState.publishPrecipitateClassificationFromPhaseMap()`.
    package func publish(_ newResult: PrecipitateSegmentation.ClassMapObjects) {
        generation &+= 1
        isComputing = false
        result = newResult
    }

    /// Start a background computation; its token must still be current when
    /// it finishes, or the result is dropped.
    package func beginComputation() -> Int {
        generation &+= 1
        isComputing = true
        return generation
    }

    /// Publish a background result only if nothing newer (another run, a
    /// clear) happened since `beginComputation` returned `token`. Returns
    /// whether it was published.
    @discardableResult
    package func publish(_ newResult: PrecipitateSegmentation.ClassMapObjects,
                         ifCurrent token: Int) -> Bool {
        guard token == generation else { return false }
        isComputing = false
        result = newResult
        return true
    }

    /// Dataset activation drops a result whose scan coordinates and calibrated
    /// area belong to the previous dataset, and any computation still in
    /// flight for it. The minimum object size is a reader preference and is
    /// kept.
    package func clear() {
        generation &+= 1
        isComputing = false
        result = nil
    }
}
