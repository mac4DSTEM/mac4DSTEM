//
//  OrientationPlan.swift
//  Role: The app's handle on an ACOM template library. The library itself (the beam directions of the fundamental zone,
//        the projection of the excited reflections to a polar image, the per-ring azimuthal FFT) is DiffractoKit's
//        `ACOMTemplateLibrary` since 0.5.0, built with the app's own settings (`ACOMTemplateSettings` defaults: 32 x 128,
//        600 axes, intensity power 0.25, radial power 0; `.appCurvature` for the Ewald sphere). What stays here is the
//        app's policy: the crystal symmetry the model declares (not the kit's own Laue class of the structure), the
//        reflections taken from the model's structure, the refusal text of the Generate button, and cancellation.
//

import Foundation
import DiffractoCore
import DiffractoGeometry
import DiffractoOrientation
import DiffractoScattering
import simd

/// The kit's library with the symmetry policy it was built under.
package nonisolated struct OrientationPlan {
    package let library: ACOMTemplateLibrary
    package let symmetry: ACOMCrystalSymmetry

    package var count: Int { library.count }
    package var geometry: ACOMTemplateLibrary.Geometry { library.geometry }
    package var zoneAxes: [SIMD3<Double>] { library.zoneAxes }
    /// py4DSTEM-style detector bases: lab x/y/z columns in crystal coordinates.
    package var detectorBases: [simd_double3x3] { library.detectorBases }
    /// Per template: the projected reflections the polar image was built from. The overlay that verifies a match by eye
    /// draws exactly these spots.
    package var templateSpots: [[ACOMTemplateSpot]] { library.templateSpots }
    /// Per template: real polar image [nRadial*nAzimuthal] (mean-subtracted, unit-normalized).
    package var templates: [[Float]] { library.templates }
    /// All template azimuthal FFTs in one contiguous `[template, radial, azimuthal]` allocation, read by the Metal backend.
    package var templateFFTRe: [Float] { library.templateFFTRe }
    package var templateFFTIm: [Float] { library.templateFFTIm }
    /// Exponent applied to spot weights (py4DSTEM's `power_intensity`, 0.25); the matcher weights the measured peaks the same.
    package var intensityPower: Double { library.settings.intensityPower }
    /// Radial width (Å⁻¹) each spot is spread over when deposited (py4DSTEM's `corr_kernel_size`).
    package var radialKernelInvAngstrom: Double { library.settings.radialKernel }

    package nonisolated init(library: ACOMTemplateLibrary, symmetry: ACOMCrystalSymmetry) {
        self.library = library
        self.symmetry = symmetry
    }

    /// The radius (Å⁻¹) of the plan's outermost ring: the k range it was built for.
    package nonisolated var kMax: Double { library.geometry.radialScale * Double(library.geometry.nRadial) }

    // MARK: k range

    /// The k range (Å⁻¹) of a plan when the detector reaches further.
    package nonisolated static let maximumKMax = 1.2

    /// The k range of a plan for one detector: the distance from the reference origin to the nearest detector edge (pixel
    /// centres), in Å⁻¹, at most `maximumKMax`. Falls back to `maximumKMax` when the origin is off the detector or the
    /// scale is not a positive number.
    ///
    /// Why the detector decides it (DiffractoKit#65, measured 2026-10-31 on the public Al-Mg-Si demo, 128 px at
    /// 0.012 Å⁻¹/px, so 0.762 Å⁻¹ to the edge): a template ring the detector cannot record makes the exact zone-axis
    /// template lose to a template tilted by a few degrees, whose excitation envelope has already dimmed the outer
    /// reflections the pattern lacks. With the app's 200 beam directions, at 1.2 Å⁻¹ the beam direction came out 5.0° off
    /// [001] and 6.5° off [011] on every matrix position of the two grains; at the detector's reach 0.0° and 1.9° (one
    /// sampling step), the same anywhere from 0.702 to 0.762 Å⁻¹, and on synthetic zone-axis patterns cut at the
    /// detector edge 0.0° at every excitation width from 0.01 to 0.03 (600 directions).
    ///
    /// Not subtracted: the disk detector's edge boundary (no peak within it is reported). It would put the demo at
    /// 0.702 Å⁻¹, a hair above the Al 220 shell (0.698), and a range just below a strong shell drops it from the
    /// templates: below 0.70 the [111] grain, which shows only 220 spots, is lost.
    package nonisolated static func kMax(originX: Double, originY: Double, detectorColumns: Int, detectorRows: Int,
                                         invAngstromPerPixel: Double) -> Double {
        let reachPixels = min(originX, originY, Double(detectorColumns - 1) - originX, Double(detectorRows - 1) - originY)
        guard reachPixels.isFinite, reachPixels > 0, invAngstromPerPixel.isFinite, invAngstromPerPixel > 0 else {
            return maximumKMax
        }
        return min(maximumKMax, reachPixels * invAngstromPerPixel)
    }

    // MARK: Generation

    /// Build a plan for `crystal`. `zoneAxisCount` sets the sampling density; `sgWidth`/`sgMax` are the excitation-error
    /// tolerances (Å⁻¹) selecting which reflections are "excited" at a zone axis. With `wavelengthAngstrom` the Ewald sphere
    /// is curved (`ACOMExcitationModel.appCurvature`), which breaks the π-periodicity of the azimuth; without it the sphere
    /// is flat.
    ///
    /// nil is a cancellation or a refusal: the kit throws `ACOMError` (settings outside their range, no usable reflection,
    /// a structure it refuses), and so does `.identity`, which has no fundamental zone. `refusalReason` names the cause the
    /// Generate button shows.
    ///
    /// Cancellation is polled by the kit before every beam direction (DiffractoKit 0.7.0, `ACOMError.cancelled`), so a token
    /// stops the build inside it; `progress` is the fraction of beam directions done, from the calling thread.
    package static func generate(crystal: CrystalStructure,
                         kMax: Double,
                         nRadial: Int = 32,
                         nAzimuthal: Int = 128,
                         zoneAxisCount: Int = 600,
                         sgWidth: Double = 0.03,
                         sgMax: Double = 0.1,
                         azimBlurBins: Double = 1.5,
                         symmetry: ACOMCrystalSymmetry = .cubic,
                         wavelengthAngstrom: Double? = nil,
                         intensityPower: Double = 0.25,
                         radialPower: Double = 0,
                         radialKernelInvAngstrom: Double = 0.08,
                         distinctOrientationDeg: Double = 10,
                         cancellation: AnalysisCancellationToken? = nil,
                         progress: (@Sendable (Double) -> Void)? = nil) -> OrientationPlan? {
        guard cancellation?.isCancelled != true, let laueClass = symmetry.laueClass else { return nil }
        // A structure the kit refuses (an element outside the scattering table, an invalid or too large cell) has no
        // plan: nil, as an empty reflection list always was. Only the reflections above the |F| cut are kept.
        guard let list = try? crystal.kinematicReflections(kMax: kMax, retainingAll: false), !list.kept.isEmpty
        else { return nil }
        let reflections = list.kept.map { ACOMReflection(g: $0.g, intensity: $0.intensity) }
        let excitation: ACOMExcitationModel
        if let wavelength = wavelengthAngstrom, wavelength > 0 {
            excitation = .appCurvature(wavelengthAngstrom: wavelength)
        } else {
            excitation = .flat
        }
        let settings = ACOMTemplateSettings(
            nRadial: nRadial, nAzimuthal: nAzimuthal, zoneAxisCount: zoneAxisCount, sgWidth: sgWidth, sgMax: sgMax,
            azimuthalBlurBins: azimBlurBins, intensityPower: intensityPower, radialPower: radialPower,
            radialKernel: radialKernelInvAngstrom, distinctOrientationDegrees: distinctOrientationDeg,
            excitation: excitation)
        let isCancelled: (@Sendable () -> Bool)? = cancellation.map { token in { token.isCancelled } }
        guard let library = try? ACOMTemplateLibrary.generate(
            reflections: reflections, kMax: kMax, laueClass: laueClass, settings: settings,
            isCancelled: isCancelled, progress: progress) else { return nil }
        return OrientationPlan(library: library, symmetry: symmetry)
    }

    /// Why `generate` has no plan for `crystal` at `kMax`, in words the Generate button's failure can show: the kit's
    /// refusal of the reflection list (a cell too large for the k range, an invalid cell or structure, an element outside
    /// the scattering table) named by its cause, or an empty list. nil when the list builds, which makes a nil plan a
    /// cancellation. The cost is the same list `generate` builds, so call it only on the failure path.
    package nonisolated static func refusalReason(crystal: CrystalStructure, kMax: Double) -> String? {
        do {
            let list = try crystal.kinematicReflections(kMax: kMax, retainingAll: false)
            return list.kept.isEmpty
                ? "No reflection of this structure lies within the plan's k range (up to \(kMax) Å⁻¹), so there are no templates."
                : nil
        } catch {
            switch error {
            case .reflectionList(.cellTooLargeOrInvalid(let estimate)) where estimate.isFinite:
                return String(format: "This cell is too large for the plan's k range (up to %g Å⁻¹): it holds about %.3g reflections, "
                              + "more than the %d a plan is built from. The range is the detector's reach, so use a smaller cell for this phase.",
                              kMax, estimate, ReflectionList.maximumReflections)
            case .reflectionList(.cellTooLargeOrInvalid):
                return "This phase's cell is not a valid finite lattice, so no reflections and no plan can be built from it."
            default:
                return error.description
            }
        }
    }
}
