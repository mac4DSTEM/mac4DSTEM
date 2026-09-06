//
//  AppState+Precipitates.swift
//  Role: docs/ai-ml/precipitates.md's orchestration — propose reflections off
//        the MAX pattern, place the virtual detector on a confirmed
//        reflection (reusing the existing `runVirtualDetector` engine),
//        segment the currently displayed scan image, and compute density.
//        `PrecipitateProduct` (Session/PrecipitateProduct.swift) owns the
//        results and run controls this reads and writes; this file owns
//        nothing itself.
//

import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

extension AppState {

    /// Local maxima of the MAX diffraction pattern that are not on the matrix
    /// lattice — docs/ai-ml/precipitates.md §2 step 1. The beam centre uses
    /// the same derivation order as every other reflection-relative
    /// measurement (`Calibration.referenceOrigin`, mirrored from
    /// `generateMeasuredProbeKernel`): fitted maps → recorded mean →
    /// the aperture the user placed → the geometric middle. `matrixBasis` is
    /// nil in v1 (§2 step 1: two-clicked-basis input is not built yet).
    @discardableResult
    func proposePrecipitateReflections() -> AnalysisRunOutcome {
        guard let maxPattern else {
            // Surfaced, not just returned: the button discarded this string,
            // so pressing Propose Reflections before a Max pattern existed did
            // nothing at all — no alert, no status line, no hint change
            // (owner's drive 2026-09-06, `drive-precipitates` defect 1,
            // capture `03a-propose-no-max-silent.png`). Writing `statusText`
            // puts it in the status bar AND the activity log, because
            // `AppState.statusText`'s `didSet` records it there.
            let reason = "Show the Max diffraction pattern once so the scan's maximum is known"
                + " — Prepare → Compute Mean / Max"
            statusText = reason
            return .failed(reason)
        }
        let beamCentre = calibrationSession.calibration.referenceOrigin(
            detectorQX: maxPattern.qx, detectorQY: maxPattern.qy,
            apertureCentre: (x: aperture.centerX, y: aperture.centerY)
        ).point
        // Named rather than passed inline so the summary below can say whether
        // the off-lattice test ran at all. Nil in v1 — §2 step 1's
        // two-clicked-basis input is not built yet.
        let matrixBasis: (g1: (x: Float, y: Float), g2: (x: Float, y: Float))? = nil
        let candidates = PrecipitateReflections.find(
            maxPattern: maxPattern.asFloatImage,
            beamCentre: beamCentre,
            matrixBasis: matrixBasis,
            settings: precipitates.reflectionSettings
        )
        precipitates.publishReflections(candidates)
        statusText = PrecipitateReflections.proposalSummary(
            count: candidates.count,
            // Without a basis every candidate is tagged `false` untested, so
            // counting them as "off the matrix lattice" reports a filter that
            // never ran (defect 3).
            offLatticeCount: matrixBasis == nil
                ? nil : candidates.filter { !$0.onMatrixLattice }.count
        )
        return .published
    }

    /// One virtual dark-field image per confirmed reflection (§2 step 2): set
    /// the aperture to a small circle centred on the reflection and let the
    /// existing virtual-detector run make the image, exactly as
    /// `applyDetectorPreset` sets the aperture and kicks off the same run.
    /// Radius follows the probe radius when it is known — 0.6× selects one
    /// variant without spilling onto its neighbour on the Al-Si-Mg cube
    /// (docs/ai-ml/precipitates.md §2 step 2) — and a fixed floor otherwise;
    /// never smaller than 2 px so the detector always covers at least one
    /// whole detector pixel.
    func placeVirtualDetector(on candidate: PrecipitateReflections.Candidate) {
        let probeRadius = calibrationSession.calibration.probeRadius
        let radius = max(2, probeRadius.map { $0 * 0.6 } ?? 2.5)
        aperture.centerX = Float(candidate.col)
        aperture.centerY = Float(candidate.row)
        aperture.inner = 0
        aperture.outer = radius
        virtualShape = .circle
        // The task deliberately STAYS on `.precipitates`. `applyDetectorPreset`
        // flips to `.virtualDetector` because it is pressed from Imaging, where
        // that is already the task; doing the same from here moved the room out
        // from under the user — the window title became `Virtual imaging`, the
        // toolbar `Segment` button vanished and the AI Analysis inspector
        // rendered blank while the AI Analysis workspace was still selected
        // (owner's drive 2026-09-06, `drive-precipitates` defect 5, capture
        // `04-detector-placed-darkfield.png`). `runVirtualDetector` never
        // consulted the mode; only the aperture overlay and the live-aperture
        // re-run did, and those now share `AnalysisMode.showsApertureOverlay`
        // so the circle is drawn and editable in this room too.
        Task { await runVirtualDetector() }
    }

    /// Real-space segmentation of the currently displayed scan-domain scalar
    /// product (§2 step 3) — the dark-field image `placeVirtualDetector`
    /// produced, or any other scalar virtual image. Runs off the main actor
    /// like every other CPU-bound analysis (`calibrateEllipse` is the
    /// mirrored pattern): a cancellable token, a detached task, then a
    /// dataset-epoch/cancellation check before publishing.
    @discardableResult
    func segmentPrecipitates() async -> AnalysisRunOutcome {
        guard let product = publishedProduct, product.domain == .scan,
              case .scalar(let displayed) = product.payload else {
            return .failed("Show a virtual image first")
        }
        // Never segment this feature's OWN label image: after a successful run
        // the object_id map IS the displayed scan product, so a second press
        // segmented the object outlines — 44 objects became 25, `#1 L 126.0 ·
        // W 24.9 · A 1900`, replacing the real result with no warning (owner's
        // drive 2026-09-06, `drive-precipitates` defect 9, capture
        // `11a-second-segment-of-label-image.png`). The owner type keeps the
        // image the last run consumed, so a second press on unchanged inputs
        // reproduces the first result.
        guard let source = precipitates.segmentationSource(
            displayedKind: product.kind, displayedName: product.displayName,
            displayedImage: displayed, displayedValidity: product.validityMask
        ) else {
            let reason = "Show the virtual image these objects came from, then Segment"
            statusText = reason
            return .failed(reason)
        }
        let image = source.image
        let settings = precipitates.segmentationSettings
        let validity = source.validity
        let epoch = datasetEpoch
        let cancellation = beginCancellableOperation(
            "Precipitate segmentation", status: "Segmenting precipitates…", totalUnits: 1
        )
        defer { finishCancellableOperation(cancellation) }
        let objects = await Task.detached(priority: .userInitiated) {
            PrecipitateSegmentation.segment(image: image, validity: validity, settings: settings)
        }.value
        guard epoch == datasetEpoch, !cancellation.isCancelled else {
            statusText = "Precipitate segmentation cancelled"
            return .cancelled
        }
        let labels = PrecipitateSegmentation.labelImage(
            objects: objects, width: image.width, height: image.height
        )
        precipitates.publishSegmentation(objects: objects, source: source)
        let edgeCount = objects.filter(\.touchesEdge).count
        publishProduct(
            kind: PrecipitateProduct.objectsProductKind,
            displayName: "Precipitate objects (\(objects.count))",
            valueUnits: "object_id",
            payload: .scalar(labels),
            // docs/ai-ml/precipitates.md §3 wants the count shown "with its
            // assumptions … rather than a bare number", and Results showed
            // none of them: no counts, no criterion, no source (owner's drive
            // 2026-09-06, `drive-precipitates` defect 10, capture
            // `09b-results-workspace.png`). They travel with the product, so
            // the sidecar entry and every export carry them too.
            extraProvenance: [
                "quantitative_status": "categorical",
                "source_product_kind": source.kind,
                "source_product_name": source.displayName,
                "segmentation_mode": "\(settings.mode)",
                "segmentation_ridge_sigma_px": "\(settings.ridgeSigmaPx)",
                "segmentation_threshold_sigmas": "\(settings.thresholdSigmas)",
                "segmentation_minimum_length_px": "\(settings.minimumLengthPx)",
                "segmentation_minimum_area_px": "\(settings.minimumAreaPx)",
                "object_count": "\(objects.count)",
                "edge_object_count": "\(edgeCount)",
                "counting_criterion":
                    "not rejected by the user and not touching the scan edge",
            ]
        )
        statusText = "\(objects.count) precipitate objects, \(edgeCount) on the edge"
        return .published
    }

    /// Areal density over the analysed extent (§2 step 5): accepted count ÷
    /// calibrated analysed area. No calibration, no density — the refusal
    /// rule in docs/ai-ml/precipitates.md §5: a count needs a stated
    /// criterion and a real denominator, or the number is a precise wrong
    /// claim. `analysedPixels` reads the currently displayed scan product's
    /// validity mask, which is the segmented (or re-segmented) image's own
    /// valid-pixel count immediately after `segmentPrecipitates` publishes it.
    @discardableResult
    func computePrecipitateDensity() -> AnalysisRunOutcome {
        guard let product = publishedProduct, product.domain == .scan,
              case .scalar = product.payload else {
            return .failed("Show a virtual image first")
        }
        let analysedPixels = product.validityMask.filter { $0 }.count
        let pixelSize = calibrationSession.calibration.rPixelSize
        let pixelUnit = pixelSize != nil ? calibrationSession.calibration.rPixelUnits : nil
        let density = PrecipitateStatistics.density(
            objects: precipitates.objects,
            accepted: precipitates.acceptedIDs,
            analysedPixels: analysedPixels,
            pixelSize: pixelSize,
            pixelUnit: pixelUnit
        )
        precipitates.publishDensity(density)
        // The density joins the label image's provenance, so what reaches
        // Results, the sidecar and every export is the count WITH its
        // denominator and criterion (§3), not the bare picture of the objects.
        // Same shape as the ACOM reliability gate's post-publish merge in
        // `AppState.swift` — republish the same product with more provenance.
        if product.kind == PrecipitateProduct.objectsProductKind {
            var densityProvenance: [String: String] = [
                "accepted_object_count": "\(density.acceptedCount)",
                "edge_excluded_count": "\(density.edgeCount)",
                "analysed_pixels": "\(density.analysedPixels)",
            ]
            if let areal = density.arealDensity, let unit = density.pixelUnit,
               let used = density.pixelSize {
                densityProvenance["areal_density"] = "\(areal)"
                densityProvenance["areal_density_units"] = "1/\(unit)^2"
                densityProvenance["r_pixel_size"] = "\(used)"
                densityProvenance["r_pixel_units"] = unit
            } else {
                densityProvenance["areal_density"] = "not computed — no calibrated pixel size"
            }
            publishedProduct = DisplayedProduct(
                origin: product.origin, kind: product.kind, displayName: product.displayName,
                payload: product.payload, domain: product.domain,
                validityMask: product.validityMask, qualityFields: product.qualityFields,
                sampling: product.sampling, valueUnits: product.valueUnits,
                quantitativeStatus: product.quantitativeStatus,
                provenance: product.provenance.merging(densityProvenance) { _, density in density },
                overlays: product.overlays)
        }
        if let areal = density.arealDensity {
            statusText = String(
                format: "%d accepted precipitates (%d on the edge) · %.4g / %@²",
                density.acceptedCount, density.edgeCount, Double(areal), (pixelUnit ?? "px") as NSString
            )
        } else {
            statusText = "\(density.acceptedCount) accepted precipitates (\(density.edgeCount) on the edge) · "
                + "no calibrated pixel size, density not computed"
        }
        return .published
    }
}
