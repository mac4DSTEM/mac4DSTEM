//
//  CalibrationReReference.swift
//  Role: Move a calibration from the SOURCE file's frame into the frame of the
//        view actually loaded — or refuse to, with a named reason.
//
//  DEVIATION from py4DSTEM (preprocess.crop_data_diffraction /
//  bin_data_diffraction, References/py4DSTEM-dev/py4DSTEM/preprocess/preprocess.py:139,155):
//  py4DSTEM mutates the datacube in place and leaves the fitted origin (qx0/qy0)
//  referring to the OLD detector frame. `crop_data_diffraction` resets the
//  Qx/Qy dim vectors and stops; `bin_data_diffraction` rescales Q_pixel_size and
//  still leaves the origin behind. Here the origin is a per-scan-position fitted
//  map that feeds disk detection, strain and ACOM, and the ellipse fit and probe
//  radius are in detector pixels — so a silently stale origin would fabricate
//  results rather than merely mislabel them. This app applies the specification
//  at read time and re-references every detector-frame value against the new
//  frame, or invalidates it explicitly. The source file is never modified.
//
//  WHAT A CROP AND A BIN ARE, GEOMETRICALLY, AND WHY THAT DECIDES EVERY RULE.
//  A crop is a PURE TRANSLATION of the detector frame and a PURE SELECTION of
//  scan positions. A bin is a PURE RESCALING of the detector frame. So:
//    * a POSITION      -> subtract the crop offset, then rescale about the
//                         pixel grid (see `binnedCoordinate`);
//    * a LENGTH/RADIUS -> unchanged by a crop, divided by the bin factor;
//    * an ANGLE        -> unchanged by both;
//    * a SAMPLING
//      INTERVAL        -> unchanged by a crop, MULTIPLIED by the bin factor,
//                         because each stored pixel now spans that many;
//    * a value INDEXED
//      BY SCAN POSITION-> crop to the sub-rectangle.
//  Anything that cannot be placed in one of those boxes is invalidated rather
//  than guessed at.
//
//  THE BIN DEVIATION, and it is the reason this file exists at all.
//  py4DSTEM's `bin_data_diffraction` (preprocess.py:154) scales `Q_pixel_size`
//  up by the bin factor and stops. It does NOT rescale the fitted origin, the
//  probe radius, or the ellipse semi-axes — all of which are in detector pixels
//  and all of which just changed size. In py4DSTEM that mislabels; here it would
//  FABRICATE, because the origin is a per-scan-position map feeding disk
//  detection, strain and ACOM. This app rescales all of them, and the intensity
//  consequence of summing (below) is stated rather than absorbed.
//
//  AXIS CONVENTION, because getting it backwards moves every origin along the
//  wrong axis and still produces plausible numbers. `OriginMaps.fittedX/fittedY`
//  are in the APP's detector frame (x = detector column, y = detector row); the
//  single documented conversion from py4DSTEM's (qx = row, qy = column) happens
//  once, in `AppState.activate`. So the detector crop's `xOffset` comes off
//  `fittedX` and its `yOffset` off `fittedY` — not the other way round.
//

import Foundation

/// A calibration value that could not be carried into the loaded view, with the
/// reason a person can act on.
///
/// **There is no "adjusted anyway" case.** Invariant I7 and the refusal rule:
/// a calibration value that cannot be re-referenced is invalidated with a named
/// reason, never clamped, never carried. Clamping an origin into the crop would
/// be the single most dangerous thing this file could do — it would place the
/// beam at a pixel it is not at, and every downstream number would look fine.
package nonisolated struct CalibrationInvalidation: Equatable, Sendable, Identifiable {
    package enum Field: String, Equatable, Sendable {
        case origin = "Beam origin"
        case ellipse = "Ellipse distortion"
        case probeRadius = "Probe radius"
        case scanIndexedResults = "Scan-indexed results"
        // P2 (2026-09-01): a session sidecar's whole calibration, refused
        // because it was recorded on a different reduced view than the one
        // loaded. Label only — the refusal policy lives in
        // `SessionCalibrationFramePolicy` (App/).
        case sessionCalibration = "Session calibration"
    }

    package let field: Field
    /// Why, in the app's own voice — shown to the user and written into
    /// provenance. Says what was dropped and what to do about it.
    package let reason: String

    package var id: String { field.rawValue + reason }

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(field: Field, reason: String) {
        self.field = field
        self.reason = reason
    }
}

/// Re-reference a calibration from the source frame into a view's frame.
///
/// Pure and synchronous: it takes what it is given and returns a new value, so
/// it is testable without a dataset, an actor or a GPU. `AppState` applies the
/// result; it does not contain the rules.
package nonisolated enum CalibrationReReference {

    /// A position in the detector frame, in pixels. The aperture centre is one,
    /// and it lives in `AppState` rather than in `Calibration` — so it is passed
    /// through this function explicitly rather than being translated by the
    /// caller. Every detector-frame rule belongs in one file; splitting them
    /// across two is how a frame convention drifts.
    package struct DetectorPoint: Equatable, Sendable {
        package var x: Float
        package var y: Float

        // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
        package nonisolated init(x: Float, y: Float) {
            self.x = x
            self.y = y
        }
    }

    package struct Outcome: Sendable {
        /// The calibration expressed in the view's frame.
        package var calibration: Calibration

        /// The aperture centre in the view's frame, or **nil when it could not
        /// be carried** — the direct beam is outside the diffraction crop. Nil
        /// means "fall back to the geometric default", never "leave it where it
        /// was": a stale centre is a beam position that is not the beam.
        package var apertureCenter: DetectorPoint?
        /// Provenance after the move. A re-referenced value keeps its
        /// provenance — a translation loses no trust, and the value still came
        /// from wherever it came from. An *invalidated* value loses its entry.
        package var provenance: CalibrationProvenance
        /// Everything that could not be carried, each with its reason.
        package var invalidated: [CalibrationInvalidation]

        /// True when a real-space crop has made existing scan-indexed results
        /// (strain, ACOM, Bragg vectors) refer to an extent that is no longer
        /// loaded.
        package var scanIndexedResultsAreAmbiguous: Bool

        package var isUnchanged: Bool { invalidated.isEmpty && !scanIndexedResultsAreAmbiguous }

        // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
        package nonisolated init(calibration: Calibration, apertureCenter: DetectorPoint? = nil, provenance: CalibrationProvenance, invalidated: [CalibrationInvalidation], scanIndexedResultsAreAmbiguous: Bool) {
            self.calibration = calibration
            self.apertureCenter = apertureCenter
            self.provenance = provenance
            self.invalidated = invalidated
            self.scanIndexedResultsAreAmbiguous = scanIndexedResultsAreAmbiguous
        }
    }

    /// Move `calibration` into `view`'s frame.
    ///
    /// A full-extent view returns its input untouched — the identity that makes
    /// "removing the specification promotes the rehearsal to the full dataset"
    /// literally true (docs/v2-scope.md §6.1).
    package static func apply(
        _ view: LoadView,
        to calibration: Calibration,
        provenance: CalibrationProvenance,
        apertureCenter: DetectorPoint
    ) -> Outcome {
        var calibration = calibration
        var apertureCenter: DetectorPoint? = apertureCenter
        var invalidated: [CalibrationInvalidation] = []
        let specification = view.specification
        let bin = specification.detectorBin

        guard !specification.isFullExtent else {
            return Outcome(calibration: calibration, apertureCenter: apertureCenter,
                           provenance: provenance,
                           invalidated: [], scanIndexedResultsAreAmbiguous: false)
        }

        // ORDER MATTERS, and not for style. The scan crop SELECTS positions and
        // the detector crop TRANSLATES values, so the scan crop runs first: a
        // scan position that is being dropped must not get a vote on whether the
        // origin survives the detector crop. Doing it the other way round would
        // let a beam excursion in a corner of the scan the user just cropped
        // away invalidate the whole calibration.
        if let scanCrop = specification.scanCrop, let origin = calibration.origin {
            if origin.width == view.source.rx, origin.height == view.source.ry {
                calibration.origin = cropped(origin, to: scanCrop)
            } else {
                // The map does not describe this scan, so there is no honest way
                // to take a sub-rectangle of it.
                calibration.origin = nil
                calibration.originProvenance = .geometricDefault
                invalidated.append(.init(
                    field: .origin,
                    reason: "The origin map is \(origin.width) x \(origin.height) but the source scan is \(view.source.rx) x \(view.source.ry), so it cannot be cropped to the loaded region. Re-fit the origin on this view."
                ))
            }
        }

        if let detectorCrop = view.readDetectorCrop {
            // A position moves with the frame, then rescales with the grid.
            if let origin = calibration.origin {
                let shifted = rescaled(
                    shifted(origin, byX: -detectorCrop.xOffset, y: -detectorCrop.yOffset),
                    bin: bin
                )
                // Judged on the FITTED origins, because those are what every
                // analysis uses; the measured arrays are a fit-quality record
                // and are allowed to scatter outside without condemning the fit.
                // Bounds are checked in the final, binned frame. **This is a
                // free choice, not a load-bearing one, and an earlier version of
                // this comment claimed otherwise.** `binnedCoordinate` is affine
                // and maps -0.5 to -0.5 and W-0.5 to W/b-0.5, so "inside the
                // pre-bin rectangle" and "inside the binned rectangle" are the
                // SAME predicate — checking either side of the bin gives an
                // identical answer at every position. Adversarial review
                // 2026-08-18 implemented the pre-bin form and every test stayed
                // green, which is the correct outcome and not a gap.
                //
                // What CAN invalidate an origin is the edge-remainder trim, not
                // the bin: the trim removes detector rows, and a beam sitting in
                // them is genuinely no longer loaded.
                if let outside = firstOutside(shifted, width: view.descriptor.qx,
                                              height: view.descriptor.qy) {
                    calibration.origin = nil
                    calibration.originProvenance = .geometricDefault
                    invalidated.append(.init(
                        field: .origin,
                        reason: "The fitted beam origin at scan position \(outside.position) lands at (\(format(outside.x)), \(format(outside.y))) in the loaded detector, which is outside its \(view.descriptor.qx) x \(view.descriptor.qy) extent — the direct beam is not inside this diffraction crop. Widen the crop or re-fit the origin on this view."
                    ))
                } else {
                    calibration.origin = shifted
                }
            }

            // The aperture centre is the origin's representation in the UI, and
            // it is a position, so it moves with the frame — and is dropped, not
            // clamped, when the beam is outside the crop. On a file that carries
            // only a mean origin (qx0/qy0, no maps) this is the ONLY origin the
            // app has, so forgetting it here would leave the whole app pointed
            // at a detector pixel that is no longer loaded.
            if var center = apertureCenter {
                center.x = binnedCoordinate(center.x - Float(detectorCrop.xOffset), bin: bin)
                center.y = binnedCoordinate(center.y - Float(detectorCrop.yOffset), bin: bin)
                // Same physical extent as `firstOutside`, for the same reason.
                let inside = center.x.isFinite && center.y.isFinite
                    && center.x >= -0.5 && center.x < Float(view.descriptor.qx) - 0.5
                    && center.y >= -0.5 && center.y < Float(view.descriptor.qy) - 0.5
                if inside {
                    apertureCenter = center
                } else {
                    apertureCenter = nil
                    if !invalidated.contains(where: { $0.field == .origin }) {
                        invalidated.append(.init(
                            field: .origin,
                            reason: "The beam centre lands at (\(format(center.x)), \(format(center.y))) in the loaded detector, outside its \(view.descriptor.qx) x \(view.descriptor.qy) extent — the direct beam is not inside this diffraction crop. Widen the crop or re-fit the origin on this view."
                        ))
                    }
                }
            }

            // The RECORDED mean origin is a detector position too, and it must
            // move with the frame exactly as the aperture does.
            //
            // **Gate B, 2026-08-28.** v2 S13 introduced
            // `Calibration.recordedOriginX/Y` as the home for a file's or
            // session's beam centre and did not transform it here. Measured
            // consequence on a 256×256 source cropped to 128×128 at offset
            // (64, 64) with a file beam centre at (130, 126): the aperture
            // correctly became (66, 62) while the recorded origin stayed at
            // (130, 126) — **64 px outside the loaded detector** — and because
            // `.recordedMean` outranks `.apertureCentre` in
            // `Calibration.referenceOrigin`, the stale value beat the one that
            // had been moved. `reciprocalMetrologyRefusal` then admitted it as
            // a measured beam centre, and every Bragg-derived product was
            // re-centred there. This is the same class as the S5 sidecar
            // finding: a value that survives a transform nothing applied to it.
            //
            // Checked independently of the fitted maps: the two can disagree
            // about whether the beam is inside the crop, and a stale recorded
            // origin must not be rescued by maps that happened to survive.
            if let x = calibration.recordedOriginX, let y = calibration.recordedOriginY {
                let movedX = binnedCoordinate(x - Float(detectorCrop.xOffset), bin: bin)
                let movedY = binnedCoordinate(y - Float(detectorCrop.yOffset), bin: bin)
                let inside = movedX.isFinite && movedY.isFinite
                    && movedX >= -0.5 && movedX < Float(view.descriptor.qx) - 0.5
                    && movedY >= -0.5 && movedY < Float(view.descriptor.qy) - 0.5
                if inside {
                    calibration.recordedOriginX = movedX
                    calibration.recordedOriginY = movedY
                } else {
                    calibration.recordedOriginX = nil
                    calibration.recordedOriginY = nil
                    if !invalidated.contains(where: { $0.field == .origin }) {
                        invalidated.append(.init(
                            field: .origin,
                            reason: "The file's recorded beam centre lands at (\(format(movedX)), \(format(movedY))) in the loaded detector, outside its \(view.descriptor.qx) x \(view.descriptor.qy) extent — the direct beam is not inside this diffraction crop. Widen the crop or re-fit the origin on this view."
                        ))
                    }
                }
            }

            // A radius and an angle survive a TRANSLATION unchanged, so a crop
            // alone leaves the ellipse fit and the probe radius untouched.
            // Stated explicitly because "it needed no change" and "it was
            // forgotten" look identical in a diff.
            //
            // Whether the cropped detector still CONTAINS the probe disk or the
            // ellipse's reference ring is a data-quality question, not a
            // calibration-frame one; automated quality checks are deferred
            // (docs/v2-scope.md §3).
        }

        if bin > 1 {
            // Lengths in detector pixels. The detector pixel just got `bin`
            // times bigger, so every length measured in them gets that many
            // times smaller. py4DSTEM rescales NONE of these.
            calibration.probeRadius = calibration.probeRadius.map { $0 / Float(bin) }
            // The ellipse semi-axes are lengths too. Rescaling both leaves
            // `ellipseTransform`'s `e = b / a` — and therefore every corrected
            // offset — bit-identical, so this changes no computed result; it
            // changes the stored numbers from source-frame pixels into
            // view-frame pixels, which is what invariant I3 asks for. `theta` is
            // an angle and does not move.
            calibration.ellipseA = calibration.ellipseA.map { $0 / Double(bin) }
            calibration.ellipseB = calibration.ellipseB.map { $0 / Double(bin) }
            // A sampling interval goes the other way: one stored pixel now spans
            // `bin` of the original, so it covers `bin` times as much reciprocal
            // space. This is the ONE rescaling py4DSTEM does perform
            // (preprocess.py:208), and the app matches it exactly.
            calibration.qPixelSize = calibration.qPixelSize.map { $0 * Double(bin) }
            // `rPixelSize` is real-space sampling and diffraction binning does
            // not touch it. Real-space binning is not offered (docs/v2-scope.md §3).
        }

        // Sampling intervals are unchanged by a CROP in either space: cropping
        // removes pixels, it does not resize them. `rPixelSize`, `rotationRad`
        // and `transposeQR` therefore pass through untouched, and `qPixelSize`
        // is rescaled by the bin block above and by nothing else.

        // A real-space crop renumbers every scan index, so a strain map, an ACOM
        // map or a Bragg-vector set measured on the full extent is AMBIGUOUS,
        // not stale: index (0, 0) means a different physical position now. The
        // caller invalidates them; the rule lives here.
        let scanIndexedAmbiguous = specification.scanCrop != nil
        if scanIndexedAmbiguous {
            invalidated.append(.init(
                field: .scanIndexedResults,
                reason: "Results measured on the full scan are indexed against the old extent, so the same index now names a different position. They were cleared rather than re-labelled — re-run them on this view."
            ))
        }

        // `provenance` passes through unchanged, and that is a decision rather
        // than an oversight. Every value it covers — probe, ellipse, rotation,
        // qScale, rScale — is either invariant under these operations or
        // rescaled exactly, and an exact rescale is not a loss of trust: a
        // `Q_pixel_size` of `file x bin` is still the file's number, expressed
        // in this view's pixels, exactly as a translated origin is still the
        // origin that was fitted.
        //
        // An earlier version of this comment predicted that L4 would be the
        // first thing to clear an entry here. L4 landed and cleared none;
        // the prediction is recorded as wrong rather than quietly deleted.
        return Outcome(calibration: calibration, apertureCenter: apertureCenter,
                       provenance: provenance,
                       invalidated: invalidated,
                       scanIndexedResultsAreAmbiguous: scanIndexedAmbiguous)
    }

    // MARK: - Geometry

    /// Take the scan sub-rectangle. Exact: it selects stored values.
    private static func cropped(_ origin: OriginMaps, to crop: AxisCrop) -> OriginMaps {
        func select(_ values: [Float]) -> [Float] {
            var output = [Float]()
            output.reserveCapacity(crop.height * crop.width)
            for y in 0..<crop.height {
                let row = (crop.yOffset + y) * origin.width + crop.xOffset
                output.append(contentsOf: values[row..<(row + crop.width)])
            }
            return output
        }
        return OriginMaps(
            width: crop.width, height: crop.height,
            measuredX: origin.measuredX.map(select),
            measuredY: origin.measuredY.map(select),
            fittedX: select(origin.fittedX),
            fittedY: select(origin.fittedY)
        )
    }

    /// Map one detector coordinate from the cropped frame into the binned one.
    ///
    /// **The half-pixel matters, and the naive `x / bin` is wrong.** Binned
    /// pixel `j` sums source pixels `j*b … j*b + b - 1`, so its CENTRE sits at
    /// source coordinate `j*b + (b-1)/2`, not at `j*b`. The inverse of that is
    /// `(x + 0.5) / b - 0.5`, which sends the centre of a bin to the centre of
    /// the binned pixel and keeps a position at the middle of the detector at
    /// the middle of the binned detector. `x / b` would displace every origin by
    /// `(b-1) / 2b` px — approaching half a binned pixel, and biased in one
    /// direction, so it would look like a small systematic descan error rather
    /// than like a bug.
    ///
    /// This is the same transform `BraggVectorEMDWriter.transformedCalibration`
    /// already applies on export, and deliberately so: two conventions for the
    /// same operation in one codebase is how they drift apart.
    package static func binnedCoordinate(_ value: Float, bin: Int) -> Float {
        bin > 1 ? (value + 0.5) / Float(bin) - 0.5 : value
    }

    /// The exact inverse of `binnedCoordinate`: map one detector coordinate
    /// from the binned frame back into the unbinned one. A binned position
    /// lands at the CENTRE of its b-pixel block — `(x + 0.5) · b - 0.5` — which
    /// is the only faithful statement of a position that was chosen at binned
    /// precision. Affine and exact: `sourceCoordinate(binnedCoordinate(x)) == x`
    /// up to float rounding, with no clamping and no bias. Added for S10's
    /// recipe re-referencing (view frame → source frame); positions
    /// additionally add the detector-crop offset at the call site, exactly as
    /// `apply` subtracts it. // v2 S10
    package static func sourceCoordinate(_ value: Float, bin: Int) -> Float {
        bin > 1 ? (value + 0.5) * Float(bin) - 0.5 : value
    }

    /// Apply `binnedCoordinate` to every position in a map.
    private static func rescaled(_ origin: OriginMaps, bin: Int) -> OriginMaps {
        guard bin > 1 else { return origin }
        func scale(_ values: [Float]) -> [Float] {
            values.map { binnedCoordinate($0, bin: bin) }
        }
        return OriginMaps(
            width: origin.width, height: origin.height,
            measuredX: origin.measuredX.map(scale),
            measuredY: origin.measuredY.map(scale),
            fittedX: scale(origin.fittedX),
            fittedY: scale(origin.fittedY)
        )
    }

    /// Translate detector positions into the cropped frame.
    private static func shifted(_ origin: OriginMaps, byX dx: Int, y dy: Int) -> OriginMaps {
        let x = Float(dx), y = Float(dy)
        return OriginMaps(
            width: origin.width, height: origin.height,
            measuredX: origin.measuredX.map { $0.map { $0 + x } },
            measuredY: origin.measuredY.map { $0.map { $0 + y } },
            fittedX: origin.fittedX.map { $0 + x },
            fittedY: origin.fittedY.map { $0 + y }
        )
    }

    /// The first fitted origin that is not inside the cropped detector, if any.
    ///
    /// A half-open test against the detector's PHYSICAL extent in pixel-centre
    /// coordinates: `[-0.5, width - 0.5) x [-0.5, height - 0.5)`.
    ///
    /// **Not `[0, width)`, and the difference is not pedantry.** Pixel *centres*
    /// run 0 … width-1, so the surface the pixels cover starts half a pixel
    /// before the first centre. Testing against `[0, width)` treats a continuous
    /// position as if it were an index, and after binning that is reachable by
    /// ordinary data: `binnedCoordinate` maps source 0 to `0.5/b - 0.5`, which
    /// is *negative* for every b > 1. An origin sitting in the first half of the
    /// first source pixel would then be declared off-detector and the whole
    /// calibration invalidated — a refusal that looks principled and is simply
    /// an off-by-half. Found 2026-08-18 by a bin test written to assert
    /// something else.
    ///
    /// **Written in the positive on purpose.** A NaN origin must never pass a
    /// bounds check by being unorderable, and which way round the test is
    /// written decides whether it does. Every comparison against NaN is false,
    /// so the positive form below rejects it — while the equally natural
    /// negated form, `!(x < 0 || x >= width || …)`, *admits* it, because none of
    /// those disjuncts fire. Verified 2026-08-18: writing it that way fails
    /// `testANonFiniteOriginCountsAsOutsideRatherThanPassingTheBoundsCheck`.
    /// The explicit `isFinite` is then belt-and-braces rather than load-bearing;
    /// it is kept because it says the intent out loud.
    private static func firstOutside(
        _ origin: OriginMaps, width: Int, height: Int
    ) -> (position: Int, x: Float, y: Float)? {
        for index in 0..<origin.fittedX.count {
            let x = origin.fittedX[index]
            let y = origin.fittedY[index]
            guard x.isFinite, y.isFinite,
                  x >= -0.5, x < Float(width) - 0.5,
                  y >= -0.5, y < Float(height) - 0.5 else {
                return (index, x, y)
            }
        }
        return nil
    }

    private static func format(_ value: Float) -> String {
        value.isFinite ? String(format: "%.1f", value) : "\(value)"
    }
}
