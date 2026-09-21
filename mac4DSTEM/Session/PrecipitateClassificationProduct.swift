//
//  PrecipitateClassificationProduct.swift
//  Role: owns the retained spatial result of the pre-registered diffraction
//        classification route. AppState composes this owner without forwarding
//        properties; a future orchestration seam is its only writer.
//

import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif
import Observation

/// The Session boundary for `docs/v3-precipitate-classification.md` §3.
///
/// This is deliberately narrower than the feature registration: it owns only
/// a published `ClassMapObjects` value. It does not classify patterns, choose
/// class roles, attach phase names, publish a view or export, and makes no
/// validation claim. Those operations must wait for the registered
/// owner-adjudicated ship gate.
@Observable
@MainActor
package final class PrecipitateClassificationProduct {

    // Explicit so the default initializer is `package` (synthesized ones are internal).
    package nonisolated init() {}

    /// The result of a successful classified scan. Only `publish` and
    /// `clear` replace it, so it cannot outlive the dataset it describes.
    package private(set) var result: PrecipitateSegmentation.ClassMapObjects?

    /// Publish a spatial result computed by the future classification route.
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
