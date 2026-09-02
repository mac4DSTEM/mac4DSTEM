//
//  CalibrationSession.swift
//  v2.5 step 4a (2026-09-03): the calibration values, their provenance, the
//  fit settings, the accelerating voltage and the readiness report, owned in
//  one observable place (plan §4 "CalibrationSession"). AppState forwards to
//  it so existing readers keep compiling; the forwarders go as the readers
//  move here. Task-aware readiness (step 4b) is computed on this type.
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
    package var ellipseFitInnerRadius: Double = 10
    package var ellipseFitOuterRadius: Double = 30
    package var lastEllipseFit: EllipseCalibrationFit?

    package init() {}

    /// The per-item readiness report, one owner (Core computes it).
    package var readiness: CalibrationReadinessReport {
        CalibrationReadinessReport.make(calibration: calibration, provenance: provenance)
    }

    /// A voltage is usable only when finite and positive; a stored 0 is a
    /// missing value that must never be shown as "0 kV".
    package var hasUsableVoltage: Bool {
        acceleratingVoltage.map { $0.isFinite && $0 > 0 } ?? false
    }
}
