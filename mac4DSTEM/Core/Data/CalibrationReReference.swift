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
//  WHAT A CROP IS, GEOMETRICALLY, AND WHY THAT DECIDES EVERY RULE BELOW.
//  A crop (no bin — that is L4) is a PURE TRANSLATION of the detector frame and
//  a PURE SELECTION of scan positions. So:
//    * a POSITION moves with the frame          -> re-reference by subtracting
//                                                  the crop offset;
//    * a LENGTH, a RADIUS or an ANGLE does not  -> carry unchanged;
//    * a SAMPLING INTERVAL does not             -> carry unchanged (only
//                                                  binning rescales it, L4);
//    * a value INDEXED BY SCAN POSITION         -> crop to the sub-rectangle.
//  Anything that cannot be placed in one of those four boxes is invalidated
//  rather than guessed at.
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
nonisolated struct CalibrationInvalidation: Equatable, Sendable, Identifiable {
    enum Field: String, Equatable, Sendable {
        case origin = "Beam origin"
        case ellipse = "Ellipse distortion"
        case probeRadius = "Probe radius"
        case scanIndexedResults = "Scan-indexed results"
    }

    let field: Field
    /// Why, in the app's own voice — shown to the user and written into
    /// provenance. Says what was dropped and what to do about it.
    let reason: String

    var id: String { field.rawValue + reason }
}

/// Re-reference a calibration from the source frame into a view's frame.
///
/// Pure and synchronous: it takes what it is given and returns a new value, so
/// it is testable without a dataset, an actor or a GPU. `AppState` applies the
/// result; it does not contain the rules.
nonisolated enum CalibrationReReference {

    /// A position in the detector frame, in pixels. The aperture centre is one,
    /// and it lives in `AppState` rather than in `Calibration` — so it is passed
    /// through this function explicitly rather than being translated by the
    /// caller. Every detector-frame rule belongs in one file; splitting them
    /// across two is how a frame convention drifts.
    struct DetectorPoint: Equatable, Sendable {
        var x: Float
        var y: Float
    }

    struct Outcome: Sendable {
        /// The calibration expressed in the view's frame.
        var calibration: Calibration

        /// The aperture centre in the view's frame, or **nil when it could not
        /// be carried** — the direct beam is outside the diffraction crop. Nil
        /// means "fall back to the geometric default", never "leave it where it
        /// was": a stale centre is a beam position that is not the beam.
        var apertureCenter: DetectorPoint?
        /// Provenance after the move. A re-referenced value keeps its
        /// provenance — a translation loses no trust, and the value still came
        /// from wherever it came from. An *invalidated* value loses its entry.
        var provenance: CalibrationProvenance
        /// Everything that could not be carried, each with its reason.
        var invalidated: [CalibrationInvalidation]

        /// True when a real-space crop has made existing scan-indexed results
        /// (strain, ACOM, Bragg vectors) refer to an extent that is no longer
        /// loaded.
        var scanIndexedResultsAreAmbiguous: Bool

        var isUnchanged: Bool { invalidated.isEmpty && !scanIndexedResultsAreAmbiguous }
    }

    /// Move `calibration` into `view`'s frame.
    ///
    /// A full-extent view returns its input untouched — the identity that makes
    /// "removing the specification promotes the rehearsal to the full dataset"
    /// literally true (docs/v2-scope.md §6.1).
    static func apply(
        _ view: LoadView,
        to calibration: Calibration,
        provenance: CalibrationProvenance,
        apertureCenter: DetectorPoint
    ) -> Outcome {
        var calibration = calibration
        var apertureCenter: DetectorPoint? = apertureCenter
        var invalidated: [CalibrationInvalidation] = []
        let specification = view.specification

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

        if let detectorCrop = specification.detectorCrop {
            // A position moves with the frame.
            if let origin = calibration.origin {
                let shifted = shifted(origin, byX: -detectorCrop.xOffset,
                                      y: -detectorCrop.yOffset)
                // Judged on the FITTED origins, because those are what every
                // analysis uses; the measured arrays are a fit-quality record
                // and are allowed to scatter outside without condemning the fit.
                if let outside = firstOutside(shifted, width: detectorCrop.width,
                                              height: detectorCrop.height) {
                    calibration.origin = nil
                    calibration.originProvenance = .geometricDefault
                    invalidated.append(.init(
                        field: .origin,
                        reason: "The fitted beam origin at scan position \(outside.position) lands at (\(format(outside.x)), \(format(outside.y))) in the cropped detector, which is outside its \(detectorCrop.width) x \(detectorCrop.height) extent — the direct beam is not inside this diffraction crop. Widen the crop or re-fit the origin on this view."
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
                center.x -= Float(detectorCrop.xOffset)
                center.y -= Float(detectorCrop.yOffset)
                let inside = center.x.isFinite && center.y.isFinite
                    && center.x >= 0 && center.x < Float(detectorCrop.width)
                    && center.y >= 0 && center.y < Float(detectorCrop.height)
                if inside {
                    apertureCenter = center
                } else {
                    apertureCenter = nil
                    if !invalidated.contains(where: { $0.field == .origin }) {
                        invalidated.append(.init(
                            field: .origin,
                            reason: "The beam centre lands at (\(format(center.x)), \(format(center.y))) in the cropped detector, outside its \(detectorCrop.width) x \(detectorCrop.height) extent — the direct beam is not inside this diffraction crop. Widen the crop or re-fit the origin on this view."
                        ))
                    }
                }
            }

            // A radius and an angle survive a translation unchanged, so the
            // ellipse fit and the probe radius are carried, not re-referenced
            // and not invalidated. Stated explicitly because "it needed no
            // change" and "it was forgotten" look identical in a diff.
            //
            // Whether the cropped detector still CONTAINS the probe disk or the
            // ellipse's reference ring is a data-quality question, not a
            // calibration-frame one; automated quality checks are deferred
            // (docs/v2-scope.md §3).
        }

        // Sampling intervals are unchanged by a crop in either space: cropping
        // removes pixels, it does not resize them. `qPixelSize`, `rPixelSize`,
        // `rotationRad` and `transposeQR` therefore pass through. Only BINNING
        // rescales `qPixelSize`, and that is L4's problem — `LoadView` refuses a
        // bin factor until then, so this file can assume factor 1.

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

        // `provenance` passes through unchanged, and that is a statement, not an
        // oversight: every value it covers — probe, ellipse, rotation, qScale,
        // rScale — is translation-invariant, so none of them lose trust here.
        // L4's bin is what will first need to clear an entry (`qScale`), which
        // is why the parameter exists now rather than being added later.
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
    /// A half-open test against `[0, width) x [0, height)`, matching how every
    /// detector index in this app is bounded.
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
                  x >= 0, x < Float(width), y >= 0, y < Float(height) else {
                return (index, x, y)
            }
        }
        return nil
    }

    private static func format(_ value: Float) -> String {
        value.isFinite ? String(format: "%.1f", value) : "\(value)"
    }
}
