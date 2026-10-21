//
//  OrientationMatcher.swift
//  Role: ACOM orientation matching in the app. The CPU matcher (a pattern's peaks to a polar image, the azimuthal FFT
//        correlation against every template, the forward and the mirrored pass, the distinct runner-up, the symmetry
//        reduction), the choice of a winner from per-template scores a caller computed (`ACOMMatcher.result(scores:...)`)
//        and the scan loop with its selection, workers, progress, cancellation and the Metal backend are DiffractoKit's (`ACOMMatcher`,
//        `ACOMMatcher.matchAll(peaksAt:backend:)` with `.cpu` or `.metal`, `ACOMScanSelection`, `ACOMScanResults`; 0.7.0). What stays here is the choice of backend and the adapters from the app's `BraggPeak` / `BraggVectors`
//        and `OrientationMap`.
//

import Foundation
import DiffractoOrientation

// MARK: - Adapters from the app's peak type

extension ACOMPeak {
    package nonisolated init(_ peak: BraggPeak) {
        self.init(x: peak.x, y: peak.y, intensity: peak.intensity)
    }
}

extension ACOMMatcher {
    /// The app's `BraggPeak` spellings of the kit matcher's per-pattern calls (same peaks, same numbers).
    package nonisolated func match(peaks: [BraggPeak], originX: Float, originY: Float,
                                   invAngstromPerPixel: Double = 1) -> OrientationResult {
        match(peaks: peaks.map(ACOMPeak.init), originX: originX, originY: originY,
              invAngstromPerPixel: invAngstromPerPixel)
    }

    package nonisolated func templateScores(peaks: [BraggPeak], originX: Float, originY: Float,
                                            invAngstromPerPixel: Double = 1) -> [Float] {
        templateScores(peaks: peaks.map(ACOMPeak.init), originX: originX, originY: originY,
                       invAngstromPerPixel: invAngstromPerPixel)
    }

    package nonisolated func experimentalPolarImage(peaks: [BraggPeak], originX: Float, originY: Float,
                                                    invAngstromPerPixel: Double = 1) -> [Float]? {
        experimentalPolarImage(peaks: peaks.map(ACOMPeak.init), originX: originX, originY: originY,
                               invAngstromPerPixel: invAngstromPerPixel)
    }

    package nonisolated func experimentalFFT(peaks: [BraggPeak], originX: Float, originY: Float,
                                             invAngstromPerPixel: Double = 1) -> (re: [Float], im: [Float])? {
        experimentalFFT(peaks: peaks.map(ACOMPeak.init), originX: originX, originY: originY,
                        invAngstromPerPixel: invAngstromPerPixel)
    }
}

// MARK: - Full-scan matching

package enum OrientationMatching {

    /// Match the requested scan positions against the plan. Full scans, preview and region work only touch their
    /// selected source positions. Progress is the requested work, not the full dataset size.
    package nonisolated static func matchAll(bragg: BraggVectors, plan: OrientationPlan,
                                     originX: Float, originY: Float,
                                     invAngstromPerPixel: Double = 1,
                                     backend: ACOMMatchingBackend = .automatic,
                                     selection: ACOMScanSelection = .full,
                                     refinesInPlaneAngle: Bool = false,
                                     cancellation: AnalysisCancellationToken? = nil,
                                     progress: (@Sendable (Double) -> Void)? = nil) -> OrientationMap? {
        guard cancellation?.isCancelled != true else { return nil }
        let selectedIndices = selection.sourceIndices(
            width: bragg.scanWidth, height: bragg.scanHeight
        )
        guard !selectedIndices.isEmpty else { return nil }
        // `refinesInPlaneAngle` (DiffractoKit 0.9, default off): the CPU scan places the in-plane angle at the vertex of the parabola
        // through the correlation peak; the Metal backend carries the bin.
        guard let matcher = ACOMMatcher(library: plan.library, refinesInPlaneAngle: refinesInPlaneAngle) else { return nil }
        let isCancelled: @Sendable () -> Bool = { cancellation?.isCancelled == true }
        // The kit's scan loop over the whole scan: the selected positions only, workers dealt round-robin, progress in
        // 1 % batches over the selection, cancellation polled before each position. `.automatic` is the CPU reference: the
        // kit's Metal backend (`.metal`, scores equal the CPU's within Float32 rounding, `docs/parity.md` P31 in DiffractoKit)
        // is slower than the vectorised CPU path on the v1 benchmark, so it runs only when the user picks it. The peaks of a position are a lazy
        // view of the app's `BraggPeak`s (DiffractoKit 0.7.0 `matchAll(peaksAt:)`): no `[[ACOMPeak]]` is built.
        guard let scan = matcher.matchAll(
            width: bragg.scanWidth, height: bragg.scanHeight,
            originX: originX, originY: originY, invAngstromPerPixel: invAngstromPerPixel,
            selection: selection, maxWorkers: nil, backend: backend == .metal ? .metal : .cpu,
            isCancelled: isCancelled, progress: progress,
            peaksAt: { bragg.peaks[$0].lazy.map(ACOMPeak.init) }
        ) else { return nil }
        var map = OrientationMap(
            width: bragg.scanWidth, height: bragg.scanHeight,
            matchingBackend: backend == .metal ? .metal : .cpu, symmetry: plan.symmetry, templateCount: plan.count
        )
        map.results = scan.results
        return map
    }
}
