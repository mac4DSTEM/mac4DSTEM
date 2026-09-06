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
            return .failed("Show the Max diffraction pattern once so the scan's maximum is known")
        }
        let beamCentre = calibrationSession.calibration.referenceOrigin(
            detectorQX: maxPattern.qx, detectorQY: maxPattern.qy,
            apertureCentre: (x: aperture.centerX, y: aperture.centerY)
        ).point
        let candidates = PrecipitateReflections.find(
            maxPattern: maxPattern.asFloatImage,
            beamCentre: beamCentre,
            matrixBasis: nil,
            settings: precipitates.reflectionSettings
        )
        precipitates.publishReflections(candidates)
        let offLattice = candidates.filter { !$0.onMatrixLattice }.count
        statusText = "\(candidates.count) reflections proposed, \(offLattice) off the matrix lattice"
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
        if navigation.analysisMode != .virtualDetector { navigation.analysisMode = .virtualDetector }
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
              case .scalar(let image) = product.payload else {
            return .failed("Show a virtual image first")
        }
        let settings = precipitates.segmentationSettings
        let validity = product.validityMask
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
        precipitates.publishSegmentation(objects: objects, sourceKind: product.kind, sourceName: product.displayName)
        let edgeCount = objects.filter(\.touchesEdge).count
        publishProduct(
            kind: "precipitate_objects",
            displayName: "Precipitate objects (\(objects.count))",
            valueUnits: "object_id",
            payload: .scalar(labels),
            extraProvenance: [
                "quantitative_status": "categorical",
                "source_product_kind": product.kind,
                "segmentation_mode": "\(settings.mode)",
                "object_count": "\(objects.count)",
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
