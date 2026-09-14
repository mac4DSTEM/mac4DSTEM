//
//  PrecipitateStatistics.swift
//  Role: Step 5 of the precipitate chain (docs/ai-ml/precipitates.md §2) —
//        areal number density from an accepted object set. The refusal rule
//        (§5): no calibration, no density — `arealDensity` is nil whenever
//        `pixelSize` is nil or non-positive, never a value computed against
//        an assumed scale.
//
//  Edge objects are excluded from the count and from the length/width
//  summaries regardless of whether the caller accepted them (§2 step 3: "an
//  object crossing the scan edge is flagged, not counted") — `edgeCount`
//  reports how many of the caller's accepted objects were excluded for that
//  reason, so the UI can say why the count is smaller than the accepted set.
//

import Foundation

package nonisolated enum PrecipitateStatistics {

    package nonisolated struct Density: Sendable, Equatable {
        package let acceptedCount: Int
        /// Accepted objects excluded from `acceptedCount` because they touch
        /// the scan edge.
        package let edgeCount: Int
        package let analysedPixels: Int
        package let pixelSize: Double?
        package let pixelUnit: String?
        /// acceptedCount / (analysedPixels x pixelSize^2). Nil without a
        /// pixel size — the refusal rule.
        package let arealDensity: Double?
        package let meanLength: Double?
        package let medianLength: Double?
        package let meanWidth: Double?

        // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
        package nonisolated init(
            acceptedCount: Int, edgeCount: Int, analysedPixels: Int,
            pixelSize: Double?, pixelUnit: String?, arealDensity: Double?,
            meanLength: Double?, medianLength: Double?, meanWidth: Double?
        ) {
            self.acceptedCount = acceptedCount
            self.edgeCount = edgeCount
            self.analysedPixels = analysedPixels
            self.pixelSize = pixelSize
            self.pixelUnit = pixelUnit
            self.arealDensity = arealDensity
            self.meanLength = meanLength
            self.medianLength = medianLength
            self.meanWidth = meanWidth
        }
    }

    /// The inspector's one-line density readout.
    ///
    /// Two things the drive caught, fixed here because both are the same
    /// sentence (owner's drive 2026-09-06, `drive-precipitates` defects 7 and 8):
    ///
    /// - it **names the pixel size it used**, and says so is stale when the
    ///   calibration has moved since. A published density outlived the
    ///   calibration that produced it: clearing the R pixel scale left
    ///   `0.0001511 /nm²` on screen with nothing saying it no longer described
    ///   the session (`07-density-uncalibrated-refusal.png`). Naming the scale
    ///   is the smaller of the two honest fixes — the number stays visible and
    ///   stops claiming a calibration the session no longer has.
    /// - the edge count it prints is `Density.edgeCount`, which now counts the
    ///   objects the edge rule actually removed. It read `0 on edge` beside a
    ///   segmentation summary saying `5 on the edge` because the caller had
    ///   already filtered edge objects out of `accepted`, leaving this type
    ///   nothing to exclude (`08-density-calibrated.png`).
    ///
    /// `currentPixelSize` is the session's R pixel size right now; nil means
    /// the calibration has been cleared.
    package nonisolated static func densitySummary(
        _ density: Density, currentPixelSize: Double?
    ) -> String {
        let counts = "\(density.acceptedCount) accepted · \(density.edgeCount) on edge"
        guard let areal = density.arealDensity, let unit = density.pixelUnit,
              let used = density.pixelSize else {
            return "\(counts) · no calibrated pixel size"
        }
        let scale = String(format: "at %.4g %@/px", used, unit)
        // Exact equality is the right test: `currentPixelSize` and
        // `density.pixelSize` are the SAME stored `Double` whenever the
        // calibration has not been rewritten, so any difference at all means
        // the calibration moved.
        let stale = currentPixelSize != used
        return String(format: "%.4g /%@² · %@ · %@%@",
                      areal, unit as NSString, counts as NSString,
                      scale as NSString,
                      (stale ? " — stale, the calibration has changed since" : "") as NSString)
    }

    /// `accepted` is the set of object ids the user kept. Objects touching
    /// the scan edge are never counted, even when their id is in `accepted`
    /// (see the type's edge-object note); their length/width are likewise
    /// excluded from the summaries, since a foreshortened edge object is not
    /// a genuine measurement of the object's extent.
    package nonisolated static func density(
        objects: [PrecipitateSegmentation.Object],
        accepted: Set<Int>,
        analysedPixels: Int,
        pixelSize: Double?,
        pixelUnit: String?
    ) -> Density {
        let acceptedObjects = objects.filter { accepted.contains($0.id) }
        let counted = acceptedObjects.filter { !$0.touchesEdge }
        let edgeExcluded = acceptedObjects.filter { $0.touchesEdge }

        let lengths = counted.map { Double($0.lengthPx) }.sorted()
        let widths = counted.map { Double($0.widthPx) }

        let meanLength = lengths.isEmpty ? nil : lengths.reduce(0, +) / Double(lengths.count)
        let medianLength: Double?
        if lengths.isEmpty {
            medianLength = nil
        } else if lengths.count % 2 == 1 {
            medianLength = lengths[lengths.count / 2]
        } else {
            medianLength = (lengths[lengths.count / 2 - 1] + lengths[lengths.count / 2]) / 2
        }
        let meanWidth = widths.isEmpty ? nil : widths.reduce(0, +) / Double(widths.count)

        var arealDensity: Double?
        if let pixelSize, pixelSize.isFinite, pixelSize > 0, analysedPixels > 0 {
            arealDensity = Double(counted.count) / (Double(analysedPixels) * pixelSize * pixelSize)
        }

        return Density(
            acceptedCount: counted.count,
            edgeCount: edgeExcluded.count,
            analysedPixels: analysedPixels,
            pixelSize: pixelSize,
            pixelUnit: pixelUnit,
            arealDensity: arealDensity,
            meanLength: meanLength,
            medianLength: medianLength,
            meanWidth: meanWidth
        )
    }
}
