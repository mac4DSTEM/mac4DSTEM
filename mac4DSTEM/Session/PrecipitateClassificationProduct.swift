//
//  PrecipitateClassificationProduct.swift
//  Role: owns the retained spatial result of a class map — objects, per-class
//        pixel counts and density. AppState composes this owner without
//        forwarding properties. Session S3
//        (`docs/v3-features.md#precipitates-mp-plan`) wired its
//        first writer, `AppState+PhaseMapping.swift`, over the vector-matched
//        phase map; the pre-registered FULL-diffraction-pattern
//        classification route (`docs/v3-features.md#precipitate-classification` §2)
//        would be a second writer of the same owner, still unbuilt.
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

    /// Publish a spatial result computed by whichever route produced it —
    /// today, `AppState.publishPrecipitateClassificationFromPhaseMap()`.
    package func publish(_ newResult: PrecipitateSegmentation.ClassMapObjects) {
        result = newResult
    }

    /// Dataset activation drops a result whose scan coordinates and calibrated
    /// area belong to the previous dataset. No controls exist in this owner
    /// yet, so no preference is preserved here.
    package func clear() {
        result = nil
    }
}
