//
//  CalibrationSession.swift
//  The calibration values, their provenance, the fit settings, the
//  accelerating voltage and the readiness report, owned in one observable
//  place (plan §4 "CalibrationSession"). AppState forwards to it so
//  existing readers keep compiling; the forwarders go as the readers move
//  here. Task-aware readiness is computed on this type.
//

import Foundation
import Observation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif

@Observable
package final class CalibrationSession {
    package var calibration = Calibration()
    package var provenance = CalibrationProvenance()
    package var acceleratingVoltage: Double?
    package var originFitFunction: OriginFitFunction = .plane
    /// How per-position origins are measured before the smooth fit. `.friedel`
    /// is the beamstop-tolerant path (`get_origin_friedel`), opt-in. // v3.1
    package var originMethod: OriginMethod = .centreOfMass
    // Moving the annulus retires a standing "Fit Anyway" offer: its caption
    // names the sectors of the annulus that was refused, not this one (Gate B,
    // 2026-09-15).
    package var ellipseFitInnerRadius: Double = 10 { didSet { ellipseFitAnywayOffer = nil } }
    package var ellipseFitOuterRadius: Double = 30 { didSet { ellipseFitAnywayOffer = nil } }
    package var lastEllipseFit: EllipseCalibrationFit?
    /// Occupied bins of the last ellipse fit refused for coverage, when a
    /// "fit anyway" retry could succeed (between the sparse floor and the
    /// degeneracy bound); nil otherwise. Non-nil is what tells Prepare to
    /// offer the "Fit Anyway" button. Set by `refuseEllipseFit`, cleared by
    /// `applyEllipseFit` and `clear()`.
    package var ellipseFitAnywayOffer: Int?

    /// The file's (or a session sidecar's) RECORDED mean beam centre, set aside by a
    /// centre drag so that Restore returns it — owner, ADR 050 card A1: the drag no longer
    /// destroys the file's own number. `provenance` is what the origin read as when it was
    /// set aside (`.fileMean` / `.sessionMean` when no fitted maps stood above it).
    /// Owner of this slot: this session (not `AppState`); its lifetime is the set-aside
    /// fitted origin's — `AppState.clearSupersededFittedOrigin()` clears both, `clear()` here.
    package struct ParkedRecordedOrigin: Equatable, Sendable {
        package var x: Float
        package var y: Float
        package var provenance: OriginProvenance

        package init(x: Float, y: Float, provenance: OriginProvenance) {
            self.x = x
            self.y = y
            self.provenance = provenance
        }
    }
    package var parkedRecordedOrigin: ParkedRecordedOrigin?

    package init() {}

    /// Take an R–Q rotation fit, or say why not. Returns nil when the fit was
    /// written; the refusal sentence when it was not.
    ///
    /// Lives here rather than in `AppState` so it can be tested at the
    /// boundary where it is enforced: Core's tests never construct a
    /// session, so a guard placed in `AppState` instead can be deleted
    /// without failing any test (Gate B, 2026-09-15) even though it is the
    /// one line deciding whether a refused rotation reaches strain, ACOM
    /// and DPC.
    ///
    /// Writes `transposeQR` with the angle deliberately: the flag rides
    /// with the fit, and a refusal that kept one and dropped the other
    /// would leave the axes swapped against an angle that never applied.
    package func applyRotation(_ result: RotationCalibration.Result) -> String? {
        if let refusal = result.refusalMessage { return refusal }
        calibration.rotationRad = result.rotationRad
        calibration.transposeQR = result.transpose
        provenance.rotation = .measuredInApp
        return nil
    }

    /// Write an accepted ellipse fit, same model as `applyRotation`: the
    /// decision of what an ellipse fit means lands here, where a test can
    /// reach it without an `AppState`. `sparseCoverage` decides the mark
    /// (Gate B precedent, 2026-09-15) — everything else about the fit is
    /// written unconditionally, success clears any standing coverage offer.
    package func applyEllipseFit(_ fit: EllipseCalibrationFit) {
        calibration.ellipseA = fit.a
        calibration.ellipseB = fit.b
        calibration.ellipseTheta = fit.theta
        provenance.ellipse = fit.sparseCoverage ? .fitAnyway : .measuredInApp
        lastEllipseFit = fit
        ellipseFitAnywayOffer = nil
    }

    /// Write an ellipse typed by hand (2026-09-28, owner decision 5): a, b are
    /// py4DSTEM's semi-axes in detector pixels and `thetaDegrees` its tilt of
    /// the semi-major axis from the qx (row) axis, in degrees — the numbers
    /// Prepare's "Correction" line shows, so a displayed ellipse round-trips.
    /// Only b/a and θ reach the correction; a and b size the overlay ring.
    ///
    /// Returns the refusal sentence and writes nothing when a value cannot
    /// be an ellipse — an earlier ellipse stands, as after a refused fit.
    /// Otherwise it replaces the ellipse, marks it `.manual`, and clears the
    /// last fit's model and residual rows, which described another ellipse.
    package func applyManualEllipse(a: Double, b: Double, thetaDegrees: Double) -> String? {
        guard a.isFinite, b.isFinite, a > 0, b > 0 else {
            return "Enter both semi-axes as positive lengths in pixels."
        }
        // py4DSTEM's a is the semi-major axis and θ its tilt
        // (`elliptical_coords.py:76` normalises a, b = max, min), and the
        // app's fit keeps that order. An a < b ellipse would still be
        // corrected exactly, but typing the axes in the wrong order while
        // keeping θ describes another ellipse and leaves a 17.97–21.16 px
        // spread on the owner's cube (Gate B, 2026-09-28): refuse it.
        guard a >= b else {
            return "a is the semi-major axis: enter the longer length as a. If your angle belongs to the shorter axis, swap a and b and add 90° to θ."
        }
        guard thetaDegrees.isFinite else { return "Enter θ in degrees." }
        calibration.ellipseA = a
        calibration.ellipseB = b
        calibration.ellipseTheta = thetaDegrees * .pi / 180
        provenance.ellipse = .manual
        lastEllipseFit = nil
        ellipseFitAnywayOffer = nil
        return nil
    }

    /// A refused ellipse fit writes nothing — an earlier ellipse, if any,
    /// stands — but between the sparse floor and the degeneracy bound the
    /// refusal is one a "fit anyway" retry could overturn, so that is the
    /// only case recorded. Every other refusal (below the floor, more than
    /// one ring, or anything else) clears a stale offer instead.
    package func refuseEllipseFit(_ error: Error) {
        if case EllipseCalibration.FitError.insufficientAngularCoverage(let bins) = error,
           bins >= EllipseCalibration.sparseFloorBins, bins < EllipseCalibration.degeneracyBoundBins {
            ellipseFitAnywayOffer = bins
        } else {
            ellipseFitAnywayOffer = nil
        }
    }

    /// Discard every calibration value and its provenance — the five readiness
    /// rows go back to "Not set" — together with the ellipse fit that produced
    /// one of them. Deliberately NOT the accelerating voltage, the origin-fit
    /// function or the ellipse fit radii: those are acquisition facts and fit
    /// settings, not measurements of this dataset, and `AppState.activate`
    /// reads the voltage off the file *before* it resets the calibration.
    /// `AppState.clearCalibration()` is the caller — a clear reaches further
    /// than this type owns (the Q run, the superseded origin, parallax).
    package func clear() {
        calibration = Calibration()
        provenance = CalibrationProvenance()
        lastEllipseFit = nil
        ellipseFitAnywayOffer = nil
        parkedRecordedOrigin = nil
    }

    /// Is there anything for a clear control to remove? `.unusable` counts: an
    /// origin that failed its own fit gate is present, and clearing it is
    /// exactly what a user does about it.
    package var hasAnyCalibrationValue: Bool {
        lastEllipseFit != nil || readiness.items.contains { $0.status != .missing }
    }

    /// The per-item readiness report, one owner (Core computes it).
    package var readiness: CalibrationReadinessReport {
        CalibrationReadinessReport.make(calibration: calibration, provenance: provenance)
    }

    /// A voltage is usable only when finite and positive; a stored 0 is a
    /// missing value that must never be shown as "0 kV".
    package var hasUsableVoltage: Bool {
        acceleratingVoltage.map { $0.isFinite && $0 > 0 } ?? false
    }

    /// The one quantitative verdict every surface renders: previously the
    /// dataset header, the readiness checklist and export each computed
    /// their own with different rules ("Core calibrated" ignored the
    /// ellipse, "Calibration is complete" ignored the voltage).
    package struct Verdict: Equatable, Sendable {
        package let quantitative: Bool
        /// "<item>: <state>" for everything still in the way, voltage included.
        package let blockers: [String]
        package var summary: String {
            quantitative ? "Quantitative" : "Not quantitative — still needed: " + blockers.joined(separator: ", ")
        }
        package init(quantitative: Bool, blockers: [String]) {
            self.quantitative = quantitative; self.blockers = blockers
        }
    }

    package var verdict: Verdict {
        var blockers = readiness.missingItems.map { "\($0.kind.rawValue): \($0.status.displayName)" }
        if !hasUsableVoltage { blockers.append("Accelerating voltage: Not set") }
        return Verdict(quantitative: blockers.isEmpty, blockers: blockers)
    }
}
