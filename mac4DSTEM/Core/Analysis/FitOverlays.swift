//
//  FitOverlays.swift
//  Role: Pure detector-space geometry for fit-verification overlays — the
//        marks that let a user judge a strain/orientation/calibration fit
//        against the measured diffraction pattern by eye.
//
//  COORDINATES: every output is in RAW detector pixels (the frame of the
//  displayed pattern). Fits live in calibrated space (per-position origins
//  collapsed onto a reference origin, then the py4DSTEM ellipse matrix —
//  see BraggVectors.calibrated). Overlays therefore apply the exact inverse:
//  raw = localOrigin + ellipseUncorrected(calibratedOffset). When neither
//  origin maps nor an ellipse exist, calibrated == raw and this reduces to
//  referenceOrigin + offset, mirroring the forward path's identity case.
//

import Foundation

package nonisolated enum FitOverlays {

    /// A predicted point on the pattern. `weight` is a relative emphasis in
    /// [0, 1] (e.g. template spot intensity), 1 when uniform.
    package struct Marker: Sendable {
        package let x: Float
        package let y: Float
        package let weight: Float

        // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
        package nonisolated init(x: Float, y: Float, weight: Float) {
            self.x = x
            self.y = y
            self.weight = weight
        }
    }

    /// An arrow in raw detector pixels (lattice vector, drawn from the origin).
    package struct Vector: Sendable {
        package let fromX: Float
        package let fromY: Float
        package let toX: Float
        package let toY: Float

        // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
        package nonisolated init(fromX: Float, fromY: Float, toX: Float, toY: Float) {
            self.fromX = fromX
            self.fromY = fromY
            self.toX = toX
            self.toY = toY
        }
    }

    /// Strain-fit overlay for one scan position.
    package struct StrainOverlay: Sendable {
        package let originX: Float
        package let originY: Float
        /// Lattice positions the local fit predicts (h·g1 + k·g2 grid).
        /// Empty when this position has no local fit.
        package let predicted: [Marker]
        package let localG1: Vector?
        package let localG2: Vector?
        package let referenceG1: Vector
        package let referenceG2: Vector
        /// Local per-position fit residual (calibrated px); nil when unfitted.
        package let localResidualPixels: Float?

        // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
        package nonisolated init(originX: Float, originY: Float, predicted: [Marker], localG1: Vector?, localG2: Vector?, referenceG1: Vector, referenceG2: Vector, localResidualPixels: Float?) {
            self.originX = originX
            self.originY = originY
            self.predicted = predicted
            self.localG1 = localG1
            self.localG2 = localG2
            self.referenceG1 = referenceG1
            self.referenceG2 = referenceG2
            self.localResidualPixels = localResidualPixels
        }
    }

    /// Matched-template overlay for one scan position.
    package struct TemplateOverlay: Sendable {
        package let originX: Float
        package let originY: Float
        /// Template reflections at the matched in-plane rotation. Weights are
        /// normalized to the strongest spot.
        package let predicted: [Marker]
        package let reliability: Float
        package let score: Float

        // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
        package nonisolated init(originX: Float, originY: Float, predicted: [Marker], reliability: Float, score: Float) {
            self.originX = originX
            self.originY = originY
            self.predicted = predicted
            self.reliability = reliability
            self.score = score
        }
    }

    // MARK: - Shared inverse-calibration mapping

    /// The per-position origin that `BraggVectors.calibrated` would collapse
    /// from, using its exact map-usability rule.
    package static func localOrigin(
        calibration: Calibration,
        referenceOrigin: (x: Float, y: Float),
        scanIndex: Int, scanWidth: Int, scanHeight: Int
    ) -> (x: Float, y: Float) {
        guard let origins = calibration.origin,
              origins.width == scanWidth, origins.height == scanHeight,
              origins.fittedX.count == scanWidth * scanHeight,
              origins.fittedY.count == scanWidth * scanHeight,
              scanIndex >= 0, scanIndex < scanWidth * scanHeight else {
            return referenceOrigin
        }
        return (origins.fittedX[scanIndex], origins.fittedY[scanIndex])
    }

    /// Map a calibrated-space detector offset onto the raw pattern around the
    /// given local origin (inverse of the forward calibration transform).
    package static func rawPoint(
        calibratedOffsetX: Float, calibratedOffsetY: Float,
        localOrigin: (x: Float, y: Float),
        calibration: Calibration
    ) -> (x: Float, y: Float) {
        let raw = calibration.ellipseUncorrectedOffset(
            dx: calibratedOffsetX, dy: calibratedOffsetY
        )
        return (localOrigin.x + raw.x, localOrigin.y + raw.y)
    }

    // MARK: - Strain

    /// Build the strain-fit overlay for one scan position: the local fitted
    /// lattice (when this position indexed) and the reference lattice vectors,
    /// both mapped back onto the raw pattern.
    package static func strainOverlay(
        map: StrainMap, scanIndex: Int,
        calibration: Calibration, referenceOrigin: (x: Float, y: Float),
        patternWidth: Int, patternHeight: Int,
        maxOrder: Int = 2
    ) -> StrainOverlay? {
        let n = map.width * map.height
        guard scanIndex >= 0, scanIndex < n,
              patternWidth > 0, patternHeight > 0 else { return nil }

        let origin = localOrigin(
            calibration: calibration, referenceOrigin: referenceOrigin,
            scanIndex: scanIndex, scanWidth: map.width, scanHeight: map.height
        )
        func raw(_ offsetX: Float, _ offsetY: Float) -> (x: Float, y: Float) {
            rawPoint(calibratedOffsetX: offsetX, calibratedOffsetY: offsetY,
                     localOrigin: origin, calibration: calibration)
        }
        func vector(_ gx: Float, _ gy: Float) -> Vector {
            let tip = raw(gx, gy)
            return Vector(fromX: origin.x, fromY: origin.y, toX: tip.x, toY: tip.y)
        }

        let referenceG1 = vector(map.refG1.x, map.refG1.y)
        let referenceG2 = vector(map.refG2.x, map.refG2.y)

        guard map.mask[scanIndex] else {
            return StrainOverlay(
                originX: origin.x, originY: origin.y,
                predicted: [], localG1: nil, localG2: nil,
                referenceG1: referenceG1, referenceG2: referenceG2,
                localResidualPixels: nil
            )
        }

        let g1 = (x: map.localG1x[scanIndex], y: map.localG1y[scanIndex])
        let g2 = (x: map.localG2x[scanIndex], y: map.localG2y[scanIndex])
        var predicted: [Marker] = []
        let margin: Float = 2
        for h in -maxOrder...maxOrder {
            for k in -maxOrder...maxOrder where h != 0 || k != 0 {
                let point = raw(Float(h) * g1.x + Float(k) * g2.x,
                                Float(h) * g1.y + Float(k) * g2.y)
                guard point.x >= -margin, point.x <= Float(patternWidth) + margin,
                      point.y >= -margin, point.y <= Float(patternHeight) + margin
                else { continue }
                predicted.append(Marker(x: point.x, y: point.y, weight: 1))
            }
        }
        return StrainOverlay(
            originX: origin.x, originY: origin.y,
            predicted: predicted,
            localG1: vector(g1.x, g1.y), localG2: vector(g2.x, g2.y),
            referenceG1: referenceG1, referenceG2: referenceG2,
            localResidualPixels: map.localResidualPixels[scanIndex]
        )
    }

    // MARK: - ACOM

    /// Project the matched template's reflections back onto the raw pattern at
    /// the matched in-plane rotation. Mirrors the matcher's forward polar
    /// conversion (r = px · invAngstromPerPixel, azim = atan2(dy, dx)); the
    /// reported in-plane angle is the pattern rotation, so predicted azimuth
    /// is template azimuth + inPlaneAngle.
    package static func acomTemplateOverlay(
        result: OrientationResult, plan: OrientationPlan,
        invAngstromPerPixel: Double,
        calibration: Calibration, referenceOrigin: (x: Float, y: Float),
        scanIndex: Int, scanWidth: Int, scanHeight: Int,
        patternWidth: Int, patternHeight: Int
    ) -> TemplateOverlay? {
        guard invAngstromPerPixel > 0, invAngstromPerPixel.isFinite,
              plan.templateSpots.indices.contains(result.templateIndex),
              patternWidth > 0, patternHeight > 0 else { return nil }

        let spots = plan.templateSpots[result.templateIndex]
        let maxWeight = spots.map(\.weight).max() ?? 0
        guard maxWeight > 0 else { return nil }

        let origin = localOrigin(
            calibration: calibration, referenceOrigin: referenceOrigin,
            scanIndex: scanIndex, scanWidth: scanWidth, scanHeight: scanHeight
        )
        let margin: Float = 2
        var predicted: [Marker] = []
        predicted.reserveCapacity(spots.count)
        for spot in spots {
            let radiusPx = Float(Double(spot.r) / invAngstromPerPixel)
            // The direct beam is the origin marker, not a template spot.
            guard radiusPx > 0.5 else { continue }
            let azimuth = spot.azim + result.inPlaneAngle
            let point = rawPoint(
                calibratedOffsetX: radiusPx * cos(azimuth),
                calibratedOffsetY: radiusPx * sin(azimuth),
                localOrigin: origin, calibration: calibration
            )
            guard point.x >= -margin, point.x <= Float(patternWidth) + margin,
                  point.y >= -margin, point.y <= Float(patternHeight) + margin
            else { continue }
            predicted.append(Marker(x: point.x, y: point.y,
                                    weight: spot.weight / maxWeight))
        }
        guard !predicted.isEmpty else { return nil }
        return TemplateOverlay(
            originX: origin.x, originY: origin.y,
            predicted: predicted,
            reliability: result.reliability, score: result.score
        )
    }

    // MARK: - Origin robust trim (real space)

    /// The scan positions the origin fit's robust trim excluded, as data for a
    /// real-space pane to grey (S23; ADR 033's mask, drawn). Row runs, so a
    /// pane fills a few rectangles rather than one per position, and a run never
    /// continues across the row wrap. Pure display of `OriginMaps.originValidity`:
    /// nothing here feeds a number, and the fitted origins of an excluded
    /// position are still valid (they come from the surface the kept positions
    /// define) - the wash says "this measurement was not used", not "no value".
    package struct OriginTrimOverlay: Equatable, Sendable {
        package struct Run: Equatable, Sendable {
            package let y: Int
            package let x: Int
            package let length: Int

            package nonisolated init(y: Int, x: Int, length: Int) {
                self.y = y
                self.x = x
                self.length = length
            }
        }

        package let width: Int
        package let height: Int
        package let excluded: Int
        package let runs: [Run]

        package var total: Int { width * height }

        /// The legend line: counts only, the mask's own statement.
        package var caption: String {
            "\(excluded) of \(total) positions excluded by the origin fit\u{2019}s robust trim"
        }

        package nonisolated init(width: Int, height: Int, excluded: Int, runs: [Run]) {
            self.width = width
            self.height = height
            self.excluded = excluded
            self.runs = runs
        }
    }

    /// nil when there is nothing honest to draw: no origin maps, no mask (an
    /// imported, restored or re-referenced origin has no trim history and this
    /// invents none), a mask that is not this scan's (length or shape), or a
    /// trim that excluded nothing.
    package static func originTrimOverlay(
        origins: OriginMaps?, scanWidth: Int, scanHeight: Int
    ) -> OriginTrimOverlay? {
        guard let origins, let mask = origins.originValidity,
              scanWidth > 0, scanHeight > 0,
              origins.width == scanWidth, origins.height == scanHeight,
              mask.count == scanWidth * scanHeight else { return nil }
        var runs: [OriginTrimOverlay.Run] = []
        var excluded = 0
        for y in 0..<scanHeight {
            var x = 0
            while x < scanWidth {
                guard !mask[y * scanWidth + x] else { x += 1; continue }
                let start = x
                while x < scanWidth, !mask[y * scanWidth + x] { x += 1 }
                runs.append(OriginTrimOverlay.Run(y: y, x: start, length: x - start))
                excluded += x - start
            }
        }
        guard excluded > 0 else { return nil }
        return OriginTrimOverlay(width: scanWidth, height: scanHeight,
                                 excluded: excluded, runs: runs)
    }

    // MARK: - Calibration (origin / ellipse)

    /// Sample the fitted ellipse as a polyline in raw detector pixels.
    /// `theta` stays in py4DSTEM's native frame (qx = app y, qy = app x);
    /// the axis swap to app coordinates happens here, in one place.
    package static func ellipsePolyline(
        centerX: Float, centerY: Float,
        a: Double, b: Double, theta: Double,
        sampleCount: Int = 96
    ) -> [Marker] {
        guard sampleCount > 2, a.isFinite, b.isFinite, theta.isFinite,
              a > 0, b > 0 else { return [] }
        let cosTheta = cos(theta), sinTheta = sin(theta)
        return (0...sampleCount).map { step in
            let t = Double(step) / Double(sampleCount) * 2 * .pi
            let qxOffset = a * cos(t) * cosTheta - b * sin(t) * sinTheta
            let qyOffset = a * cos(t) * sinTheta + b * sin(t) * cosTheta
            return Marker(x: centerX + Float(qyOffset),
                          y: centerY + Float(qxOffset),
                          weight: 1)
        }
    }
}
