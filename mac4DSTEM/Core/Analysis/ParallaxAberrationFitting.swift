//
//  ParallaxAberrationFitting.swift
//  The app's bridge to CuboKit 0.4.0's
//  CuboParallax.ParallaxAberrationFitter (the arithmetic: polar-decomposition low-order fit, Cartesian higher-order fit, gradient basis).
//
//  The fit's option and result value types (ParallaxPhysicalShift, ParallaxAberrationTerm, ParallaxAberrationFitMethod, the low-order and
//  higher-order options and results) are CuboParallax's own, used directly. The enum below keeps the app's stage error and
//  the preprocessing/alignment-result bridge.
//

import CuboParallax
import Foundation

package nonisolated enum ParallaxAberrationFitter {
    package enum FitError: LocalizedError, Equatable {
        case alignmentIncomplete
        case invalidInput(String)
        case singularAngleGeometry
        case singularPolarDecomposition

        package var errorDescription: String? {
            switch self {
            case .alignmentIncomplete:
                return "Complete every parallax alignment-bin level before fitting aberrations."
            case .invalidInput(let detail):
                return "Cannot fit parallax aberrations: \(detail)."
            case .singularAngleGeometry:
                return "The selected probe angles do not span two reciprocal-space directions."
            case .singularPolarDecomposition:
                return "The measured parallax shift transform has a singular polar decomposition."
            }
        }
    }

    /// Port of py4DSTEM `_aberration_fit_polar_decomposition` (CuboParallax's `fitLowOrder`).
    ///
    /// The probe angles are the preprocessing's stored `probeAnglesMrad` / 1000, which are already on CuboParallax's
    /// `ParallaxBasisConvention.selectedCentroid` origin (the centroid of the selected bright-field pixels); the kit's
    /// `basisAngles(... convention: .selectedCentroid)` would recompute the same values.
    package static func fitLowOrder(
        preprocessing: ParallaxPreprocessResult,
        alignment: ParallaxAlignmentResult,
        options: ParallaxLowOrderAberrationOptions = .init()
    ) throws -> ParallaxAberrationFitResult {
        guard alignment.isComplete else { throw FitError.alignmentIncomplete }
        let sampling = preprocessing.calibration.scanSamplingAngstrom
        return try bridged {
            try CuboParallax.ParallaxAberrationFitter.fitLowOrder(
                probeAngles: radians(preprocessing.probeAnglesMrad),
                pixelShifts: alignment.totalShifts.map {
                    CuboParallax.ParallaxShift(row: Double($0.row), column: Double($0.column))
                },
                scanSampling: CuboParallax.ParallaxShift(row: sampling, column: sampling),
                options: options
            )
        }
    }

    package static func defaultTerms(
        maxRadialOrder: Int = 3,
        maxAngularOrder: Int = 4,
        minRadialOrder: Int = 2,
        minAngularOrder: Int = 0
    ) throws -> [ParallaxAberrationTerm] {
        try bridged {
            try CuboParallax.ParallaxAberrationFitter.defaultTerms(
                maxRadialOrder: maxRadialOrder, maxAngularOrder: maxAngularOrder,
                minRadialOrder: minRadialOrder, minAngularOrder: minAngularOrder
            )
        }
    }

    /// Default recursive higher-order fit from py4DSTEM `aberration_fit` (CuboParallax's `fitHigherOrder`), with the gradient basis
    /// evaluated at the angles the affine fit used (`.selectedCentroid`).
    ///
    /// DEVIATION (lane R4, 2026-10-01; graphene cube, `tools/harnesses/parallax-aberration-test` linear-field case): py4DSTEM's (2,1) coma pair
    /// reads 619 / 599 Å there and ours reads 0. Both implementations hand this fit an EXACTLY linear shift field (the alignment
    /// projects its shifts onto k with no intercept, parallax.py:1380-1384; here `fitDefaultShiftBasis`), so no coma or trefoil is
    /// observable. py4DSTEM's non-zero value is an artefact of its own origins: it evaluates the gradient basis on the ROI fft grid
    /// (origin ROI//2, utils.py:1551-1556) but regresses on angles centred on mean(xy_inds) (parallax.py:473-478), 0.325 px = 0.34 mrad
    /// apart on graphene; the pair is exactly linear in that offset (0 -> 0, 0.325 px -> 619 / 599 Å) and py4DSTEM's fitter run on OUR
    /// shifts returns the same 619 / 599 Å. We evaluate the basis at the angles the affine fit used, so a linear field returns 0 and a zero
    /// residual. That 0 means UNOBSERVABLE, not measured zero: the higher-order terms are only as good as the field's non-linearity, which
    /// the default alignment (regularize_shifts False; py4DSTEM's True keeps an intercept) removes.
    package static func fitHigherOrder(
        preprocessing: ParallaxPreprocessResult,
        alignment: ParallaxAlignmentResult,
        options: ParallaxHigherOrderAberrationOptions = .init()
    ) throws -> ParallaxHigherOrderAberrationFitResult {
        guard alignment.isComplete else { throw FitError.alignmentIncomplete }
        let sampling = preprocessing.calibration.scanSamplingAngstrom
        let angles = radians(preprocessing.probeAnglesMrad)
        var kit = options
        kit.basisConvention = .selectedCentroid
        return try bridged {
            try CuboParallax.ParallaxAberrationFitter.fitHigherOrder(
                probeAngles: angles,
                pixelShifts: alignment.totalShifts.map {
                    CuboParallax.ParallaxShift(row: Double($0.row), column: Double($0.column))
                },
                scanSampling: CuboParallax.ParallaxShift(row: sampling, column: sampling),
                basisAngles: angles, options: kit
            )
        }
    }

    /// Row-major `[sample, term]` pairs of (dchi/du, dchi/dv). The derivatives
    /// intentionally omit the phase-only global scale, matching py4DSTEM.
    package static func gradientSamples(
        probeAnglesMrad: [ParallaxVector],
        rotationRad: Double,
        terms: [ParallaxAberrationTerm]
    ) throws -> [(Double, Double)] {
        try bridged {
            try CuboParallax.ParallaxAberrationFitter.gradientSamples(
                probeAngles: radians(probeAnglesMrad), rotationRad: rotationRad,
                terms: terms
            )
        }
    }

    // MARK: Conversions between the app's types and CuboParallax's

    private static func radians(_ mrad: [ParallaxVector]) -> [CuboParallax.ParallaxShift] {
        mrad.map {
            CuboParallax.ParallaxShift(row: Double($0.qx) / 1_000, column: Double($0.qy) / 1_000)
        }
    }

    private static func bridged<T>(_ body: () throws -> T) throws -> T {
        do { return try body() } catch let error as CuboParallax.ParallaxAberrationFitter.FitError {
            switch error {
            case .invalidInput(let detail): throw FitError.invalidInput(detail)
            case .singularAngleGeometry: throw FitError.singularAngleGeometry
            case .singularPolarDecomposition: throw FitError.singularPolarDecomposition
            }
        } catch {
            throw FitError.invalidInput(parallaxKitReason(error))
        }
    }
}

/// Plain-language reason for an error the CuboParallax kit raised (its `ParallaxError`, `ParallaxAlignmentError`), so no kit type
/// reaches a status line or a stage's own error enum.
package nonisolated func parallaxKitReason(_ error: Error) -> String {
    if let error = error as? CuboParallax.ParallaxError {
        switch error {
        case .invalidInput: return "the dimensions, orders or sampling are inconsistent"
        case .degenerateData: return "an image has no positive weight, or the geometry is singular"
        case .nonfiniteValues: return "an input or a result is NaN or infinite"
        case .stackTooLarge: return "the bright-field stack would not fit in the memory allowed"
        }
    }
    if let error = error as? CuboParallax.ParallaxAlignmentError {
        switch error {
        case .invalidDimensions: return "the image dimensions are invalid"
        case .inconsistentShape: return "the image lengths differ from the dimensions"
        case .invalidUpsampleFactor: return "the upsample factor is outside 3...64"
        case .nonfiniteValues: return "an input or a result is NaN or infinite"
        case .degenerateCorrelation: return "a constant image has no identifiable shift"
        }
    }
    return error.localizedDescription
}
