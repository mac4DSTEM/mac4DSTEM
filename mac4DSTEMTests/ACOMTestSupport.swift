//
//  ACOMTestSupport.swift
//  The ACOM tests build synthetic patterns from the same projection the template library uses. That projection is
//  DiffractoKit's (`ACOMTemplateLibrary.project`); this is the former app spelling of the call (kit reflection list in,
//  `(r, azim, weight)` out) so the tests read as they did.
//

import Foundation
import DiffractoOrientation
import DSTEMCore
import DiffractoScattering
import simd
@testable import mac4DSTEM

extension OrientationPlan {
    static func project(reflections: [KinematicReflection], zoneAxis n: SIMD3<Double>,
                        sgWidth: Double, sgMax: Double,
                        wavelengthAngstrom: Double? = nil,
                        intensityPower: Double = 0.25,
                        radialPower: Double = 0) -> [(r: Double, azim: Double, weight: Double)] {
        let settings = ACOMTemplateSettings(
            sgWidth: sgWidth, sgMax: sgMax, intensityPower: intensityPower, radialPower: radialPower,
            excitation: wavelengthAngstrom.map { .appCurvature(wavelengthAngstrom: $0) } ?? .flat)
        return ACOMTemplateLibrary.project(
            reflections: reflections.map { ACOMReflection(g: $0.g, intensity: $0.intensity) },
            zoneAxis: n, settings: settings
        ).map { (r: $0.r, azim: $0.azimuth, weight: $0.weight) }
    }
}
