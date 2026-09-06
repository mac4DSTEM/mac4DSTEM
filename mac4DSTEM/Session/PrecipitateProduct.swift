//
//  PrecipitateProduct.swift
//  Role: docs/ai-ml/precipitates.md §4's seam — the one owner of the
//        precipitate-reflections list, the segmentation settings and result,
//        and the density result. Held by AppState with no forwarding
//        properties; views read `precipitates.…`.
//
//  What deliberately does NOT live here: proposing reflections, placing the
//  virtual detector, running segmentation and computing density — those are
//  AppState orchestration (`AppState+Precipitates.swift`) because they touch
//  the dataset, the aperture, and the published product, which this type does
//  not own. This type only stores the answers and the run controls that
//  survive a dataset change.
//

import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif
import Observation

@Observable
@MainActor
package final class PrecipitateProduct {

    // Explicit so the default initializer is `package` (synthesized ones are internal). // v2.5 step 2c
    package nonisolated init() {}

    // MARK: - Reflections

    /// Run control for `PrecipitateReflections.find`. Survives dataset
    /// activation, like `StrainProduct`'s reference/basis controls — a
    /// setting the owner tuned is not a fact about the open dataset.
    package var reflectionSettings = PrecipitateReflections.Settings()

    /// The proposed list from the last `proposePrecipitateReflections` run.
    /// Product state: dies on `clear()`.
    package private(set) var reflections: [PrecipitateReflections.Candidate] = []

    /// Which proposed reflections the user has confirmed as precipitate
    /// channels (as opposed to matrix disks the finder proposed in error).
    /// Defaulted by `publishReflections` to every candidate NOT on the matrix
    /// lattice — the finder's own judgement, overridable per row.
    package var confirmedReflectionIDs: Set<Int> = []

    /// Replace the reflection list and reset confirmation to the finder's own
    /// on/off-lattice judgement.
    package func publishReflections(_ candidates: [PrecipitateReflections.Candidate]) {
        reflections = candidates
        confirmedReflectionIDs = Set(candidates.filter { !$0.onMatrixLattice }.map(\.id))
    }

    // MARK: - Segmentation

    /// Run control for `PrecipitateSegmentation.segment`. Survives dataset
    /// activation, same reasoning as `reflectionSettings`.
    package var segmentationSettings = PrecipitateSegmentation.Settings()

    /// Which scan-domain product was segmented — provenance for the object
    /// list, not re-derivable once the user has moved on to a different
    /// virtual image. Product state: dies on `clear()`.
    package private(set) var sourceProductKind: String?
    package private(set) var sourceDisplayName: String?

    /// The last segmentation's objects. Product state: dies on `clear()`.
    package private(set) var objects: [PrecipitateSegmentation.Object] = []

    /// User corrections: objects excluded from the count despite passing
    /// segmentation. Product state: dies on `clear()`.
    package var rejectedObjectIDs: Set<Int> = []

    /// The USER's decision alone: every object they have not rejected by
    /// click. Edge objects stay in this set on purpose.
    ///
    /// `PrecipitateStatistics.density` applies the edge rule itself and
    /// reports what it removed as `Density.edgeCount`. Filtering edge objects
    /// out here as well left that function nothing to exclude, so every
    /// density read `0 on edge` beside a segmentation summary saying
    /// `5 on the edge` (owner's drive 2026-09-06, `drive-precipitates`
    /// defect 7). The counted set — the criterion of §5 — is `countedIDs`.
    package var acceptedIDs: Set<Int> {
        Set(objects.filter { !rejectedObjectIDs.contains($0.id) }.map(\.id))
    }

    /// The counting criterion (docs/ai-ml/precipitates.md §5): an object
    /// counts only if the user has not rejected it AND it does not touch the
    /// scan edge (an edge object is truncated, not a real measurement). This
    /// is what `Density.acceptedCount` reports, and what the objects table's
    /// per-row toggle shows.
    package var countedIDs: Set<Int> {
        acceptedIDs.subtracting(objects.filter(\.touchesEdge).map(\.id))
    }

    /// The scan image the last segmentation ran ON, kept so a second Segment
    /// press re-runs the dark-field rather than this feature's own object_id
    /// label image — which is what the displayed product has become by then.
    /// The second press turned 44 objects into 25, `#1 L 126.0 · W 24.9`,
    /// silently replacing the real result (owner's drive 2026-09-06,
    /// `drive-precipitates` defect 9). Product state: dies on `clear()`.
    package private(set) var sourceImage: FloatImage?
    package private(set) var sourceValidity: [Bool] = []

    /// The `DisplayedProduct.kind` this feature publishes its label image
    /// under — named once so the "do not segment my own output" test below
    /// and `AppState.segmentPrecipitates` cannot drift apart.
    package nonisolated static let objectsProductKind = "precipitate_objects"

    /// One segmented image, its validity mask and its provenance.
    package nonisolated struct SegmentationSource: Sendable {
        package let image: FloatImage
        package let validity: [Bool]
        package let kind: String
        package let displayName: String

        package nonisolated init(
            image: FloatImage, validity: [Bool], kind: String, displayName: String
        ) {
            self.image = image
            self.validity = validity
            self.kind = kind
            self.displayName = displayName
        }
    }

    /// Which image a Segment press acts on, given whatever scan product is
    /// currently displayed.
    ///
    /// Normally the displayed product itself. When the displayed product is
    /// this feature's own label image, the run re-uses the source the last
    /// segmentation recorded, so pressing Segment twice on unchanged inputs
    /// reproduces the first result instead of segmenting the object outlines.
    /// Nil means there is nothing honest to segment — the label image is on
    /// screen and no source was recorded (a restored sidecar result, say).
    package func segmentationSource(
        displayedKind: String, displayedName: String,
        displayedImage: FloatImage, displayedValidity: [Bool]
    ) -> SegmentationSource? {
        guard displayedKind == Self.objectsProductKind else {
            return SegmentationSource(
                image: displayedImage, validity: displayedValidity,
                kind: displayedKind, displayName: displayedName
            )
        }
        guard let sourceImage else { return nil }
        return SegmentationSource(
            image: sourceImage, validity: sourceValidity,
            kind: sourceProductKind ?? displayedKind,
            displayName: sourceDisplayName ?? displayedName
        )
    }

    /// Replace the object list from a fresh segmentation run. A new
    /// segmentation invalidates any density computed from the old objects —
    /// `density` is cleared rather than left to describe a list that no
    /// longer exists.
    package func publishSegmentation(
        objects: [PrecipitateSegmentation.Object], source: SegmentationSource
    ) {
        self.objects = objects
        sourceProductKind = source.kind
        sourceDisplayName = source.displayName
        sourceImage = source.image
        sourceValidity = source.validity
        rejectedObjectIDs = []
        density = nil
    }

    /// Toggle one object's accept/reject state (correction by click, §3).
    package func toggleObject(_ id: Int) {
        if rejectedObjectIDs.contains(id) {
            rejectedObjectIDs.remove(id)
        } else {
            rejectedObjectIDs.insert(id)
        }
    }

    // MARK: - Density

    /// The last density computation. Product state: dies on `clear()`.
    package private(set) var density: PrecipitateStatistics.Density?

    package func publishDensity(_ density: PrecipitateStatistics.Density) {
        self.density = density
    }

    /// Dataset activation: the reflection list, the segmentation, and the
    /// density all die with the dataset — none of them describes anything
    /// about a dataset that is no longer open. The run controls
    /// (`reflectionSettings`, `segmentationSettings`) survive: they are
    /// session-scoped tuning, not dataset-scoped results.
    package func clear() {
        reflections = []
        confirmedReflectionIDs = []
        sourceProductKind = nil
        sourceDisplayName = nil
        sourceImage = nil
        sourceValidity = []
        objects = []
        rejectedObjectIDs = []
        density = nil
    }
}
