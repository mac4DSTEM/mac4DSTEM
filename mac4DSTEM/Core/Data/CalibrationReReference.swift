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
//                         pixel grid (see `FrameTransform.binnedCoordinate`);
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

import CuboCore
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
        /// be carried** — the direct beam is outside the diffraction crop — or
        /// when none was supplied. For a supplied centre, nil means "fall back to
        /// the geometric default", never "leave it where it was": a stale centre
        /// is a beam position that is not the beam.
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
    ///
    /// `apertureCenter` is a position in the SOURCE detector frame, or **nil when
    /// the caller has none to move**. A geometric default ("the middle of the
    /// loaded detector") is a VIEW-frame value: passing it here moved it a second
    /// time — the ring at 7.75 instead of 16 on a 32 px view after bin 2, at the
    /// crop's corner after a centred crop — and, where the shift left the
    /// detector, invented a "beam not inside this crop" refusal for a file that
    /// never recorded a beam. Nil is returned unchanged, with nothing refused.
    package static func apply(
        _ view: LoadView,
        to calibration: Calibration,
        provenance: CalibrationProvenance,
        apertureCenter: DetectorPoint?
    ) -> Outcome {
        var calibration = calibration
        var apertureCenter = apertureCenter
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
            let describesScan = origin.width == view.source.rx && origin.height == view.source.ry
            if describesScan, let cut = cropped(origin, to: scanCrop) {
                calibration.origin = cut
            } else {
                // The map does not describe this scan, or its arrays do not fit its stated
                // size and the crop, so there is no honest way to take a sub-rectangle of it.
                calibration.origin = nil
                calibration.originProvenance = .geometricDefault
                let why = describesScan
                    ? "its stored values do not match its \(origin.width) x \(origin.height) size, so the loaded region cannot be cut from it"
                    : "The origin map is \(origin.width) x \(origin.height) but the source scan is \(view.source.rx) x \(view.source.ry), so it cannot be cropped to the loaded region"
                invalidated.append(.init(
                    field: .origin,
                    reason: (describesScan ? "The origin map is dropped: " : "") + why + ". Re-fit the origin on this view."
                ))
            }
        }

        if let detectorCrop = view.readDetectorCrop {
            // A position moves with the frame, then rescales with the grid.
            if let origin = calibration.origin,
               let result = moved(origin, cropX: detectorCrop.xOffset, cropY: detectorCrop.yOffset, bin: bin,
                                  width: view.descriptor.qx, height: view.descriptor.qy) {
                // Judged on the FITTED origins, because those are what every analysis
                // uses. Bounds are checked in the final, binned frame; what can
                // invalidate an origin is the edge-remainder trim, not the bin.
                if let outside = result.outside {
                    calibration.origin = nil
                    calibration.originProvenance = .geometricDefault
                    invalidated.append(.init(
                        field: .origin,
                        reason: "The fitted beam origin at scan position \(outside.position) lands at (\(format(outside.x)), \(format(outside.y))) in the loaded detector, which is outside its \(view.descriptor.qx) x \(view.descriptor.qy) extent — the direct beam is not inside this diffraction crop. Widen the crop or re-fit the origin on this view."
                    ))
                } else {
                    calibration.origin = result.origin
                }
            } else if calibration.origin != nil {
                calibration.origin = nil
                calibration.originProvenance = .geometricDefault
                invalidated.append(.init(
                    field: .origin,
                    reason: "The fitted beam origin maps (x and y) differ in length, so they cannot be moved into the loaded detector. Re-fit the origin on this view."
                ))
            }

            // The aperture centre is the origin's representation in the UI, and
            // it is a position, so it moves with the frame — and is dropped, not
            // clamped, when the beam is outside the crop. On a file that carries
            // only a mean origin (qx0/qy0, no maps) this is the ONLY origin the
            // app has, so forgetting it here would leave the whole app pointed
            // at a detector pixel that is no longer loaded.
            if var center = apertureCenter {
                center.x = FrameTransform.binnedCoordinate(center.x - Float(detectorCrop.xOffset), bin: bin)
                center.y = FrameTransform.binnedCoordinate(center.y - Float(detectorCrop.yOffset), bin: bin)
                // Same physical extent as `firstOutside`, for the same reason.
                let inside = FrameTransform.isInside(column: center.x, row: center.y,
                                                     width: view.descriptor.qx, height: view.descriptor.qy)
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
                let movedX = FrameTransform.binnedCoordinate(x - Float(detectorCrop.xOffset), bin: bin)
                let movedY = FrameTransform.binnedCoordinate(y - Float(detectorCrop.yOffset), bin: bin)
                let inside = FrameTransform.isInside(column: movedX, row: movedY,
                                                     width: view.descriptor.qx, height: view.descriptor.qy)
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
            calibration.probeRadius = calibration.probeRadius.map { FrameTransform.binnedLength($0, bin: bin) }
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
            calibration.qPixelSize = calibration.qPixelSize.map { FrameTransform.binnedPixelSize($0, bin: bin) }
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
        return Outcome(calibration: calibration, apertureCenter: apertureCenter,
                       provenance: provenance,
                       invalidated: invalidated,
                       scanIndexedResultsAreAmbiguous: scanIndexedAmbiguous)
    }

    // MARK: - Geometry
    //
    // The frame rules (crop offset, pixel-centre bin transform, physical-extent test)
    // live in CuboCore's `FrameTransform`, pinned to this file's former implementation.

    /// Take the scan sub-rectangle. Exact: it selects stored values. Nil when the crop
    /// does not fit the map.
    private static func cropped(_ origin: OriginMaps, to crop: AxisCrop) -> OriginMaps? {
        func select(_ values: [Float]) -> [Float]? {
            FrameTransform.cropMap(values, mapWidth: origin.width, mapHeight: origin.height,
                                   columnOffset: crop.xOffset, rowOffset: crop.yOffset,
                                   width: crop.width, height: crop.height)
        }
        guard let fittedX = select(origin.fittedX), let fittedY = select(origin.fittedY) else { return nil }
        var measuredX: [Float]?, measuredY: [Float]?
        if let values = origin.measuredX {
            guard let cut = select(values) else { return nil }
            measuredX = cut
        }
        if let values = origin.measuredY {
            guard let cut = select(values) else { return nil }
            measuredY = cut
        }
        return OriginMaps(
            width: crop.width, height: crop.height,
            measuredX: measuredX, measuredY: measuredY,
            fittedX: fittedX, fittedY: fittedY
        )
    }

    /// Translate by the detector-crop offset, then bin. The fitted maps are judged
    /// (every position must be inside `width` x `height`, the loaded binned detector);
    /// the measured maps are a fit-quality record and may scatter outside.
    private static func moved(
        _ origin: OriginMaps, cropX dx: Int, cropY dy: Int, bin: Int, width: Int, height: Int
    ) -> (origin: OriginMaps, outside: (position: Int, x: Float, y: Float)?)? {
        guard let fitted = FrameTransform.moveOriginMap(
            columns: origin.fittedX, rows: origin.fittedY, columnOffset: dx, rowOffset: dy,
            bin: bin, width: width, height: height) else { return nil }
        func shift(_ values: [Float]?, by offset: Int) -> [Float]? {
            values.map { $0.map { FrameTransform.binnedCoordinate($0 - Float(offset), bin: bin) } }
        }
        let result = OriginMaps(
            width: origin.width, height: origin.height,
            measuredX: shift(origin.measuredX, by: dx),
            measuredY: shift(origin.measuredY, by: dy),
            fittedX: fitted.columns, fittedY: fitted.rows
        )
        let outside = fitted.firstOutside.map { ($0, fitted.columns[$0], fitted.rows[$0]) }
        return (result, outside)
    }

    private static func format(_ value: Float) -> String {
        value.isFinite ? String(format: "%.1f", value) : "\(value)"
    }
}
