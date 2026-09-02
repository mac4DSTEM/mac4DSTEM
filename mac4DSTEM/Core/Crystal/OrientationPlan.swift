//
//  OrientationPlan.swift
//  Role: The ACOM template library. For a crystal, sample candidate zone-axis
//        (beam) orientations, project the excited reflections of each to a
//        simulated diffraction pattern, and store a POLAR representation
//        (radial |g| × azimuthal angle) plus its per-ring azimuthal FFT.
//
//  This is a simplified, self-consistent polar-correlation route (the same
//  principle as py4DSTEM's crystal_ACOM.py, without the spherical-harmonic
//  machinery): because in-plane rotation is recovered by a 1D FFT along the
//  azimuthal axis during matching, the plan only samples the 2 DOF of the beam
//  direction. In-plane rotation is free at match time.
//
//  Geometry: radial bins are in the same units as the matched peaks' radii
//  (Å⁻¹ if the detector is Q-calibrated; see OrientationMatcher for the pixel
//  → Å⁻¹ scale). Current crystals are cubic, so zone axes are sampled
//  directly in the m-3m [001]-[101]-[111] fundamental sector.
//

import Foundation
import simd

/// Shared polar-image geometry.
package nonisolated struct PolarGeometry {
    package let nRadial: Int
    package let nAzimuthal: Int          // power of two (azimuthal FFT length)
    package let radialScale: Double      // radial units per bin

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package init(nRadial: Int, nAzimuthal: Int, radialScale: Double) {
        self.nRadial = nRadial
        self.nAzimuthal = nAzimuthal
        self.radialScale = radialScale
    }
}

/// One projected reflection of a template, in the template's polar frame:
/// radius in the plan's radial units (Å⁻¹), azimuth in radians. Retained so a
/// matched template can be projected back onto the diffraction pattern.
package nonisolated struct TemplateSpot: Sendable {
    package let r: Float
    package let azim: Float
    package let weight: Float

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package init(r: Float, azim: Float, weight: Float) {
        self.r = r
        self.azim = azim
        self.weight = weight
    }
}

/// The library, with per-template azimuthal FFTs precomputed for matching.
package nonisolated struct OrientationPlan {
    package let geometry: PolarGeometry
    package let symmetry: ACOMCrystalSymmetry
    package let zoneAxes: [SIMD3<Double>]
    /// py4DSTEM-style detector bases: lab x/y/z columns in crystal coordinates.
    package let detectorBases: [simd_double3x3]
    /// Per template: the projected reflections the polar image was built from.
    /// The overlay that verifies a match by eye draws exactly these spots.
    package let templateSpots: [[TemplateSpot]]
    /// Per template: real polar image [nRadial*nAzimuthal] (mean-subtracted,
    /// unit-normalized) — kept for inspection/visualization.
    package let templates: [[Float]]
    /// All template azimuthal FFTs in one contiguous
    /// `[template, radial, azimuthal]` allocation. This layout is shared by the
    /// optimized CPU matcher and the batched Metal backend.
    package let templateFFTRe: [Float]
    package let templateFFTIm: [Float]
    /// Exponent applied to spot weights before they are deposited into the
    /// polar image. The default 0.25 is py4DSTEM's own default, READ FROM ITS
    /// SOURCE, not fitted here: `References/py4DSTEM-dev/py4DSTEM/process/
    /// diffraction/crystal_ACOM.py`, `orientation_plan(...)` declares
    /// `power_intensity: float = 0.25` (line 33) for the templates and
    /// `power_intensity_experiment: float = 0.25` (line 34) for the
    /// experimental image; they are applied at lines 809/816 and 1062
    /// respectively. 1 keeps raw intensities, so
    /// the brightest ring dominates the correlation; values below 1 compress
    /// the dynamic range so weak reflections still carry azimuthal detail. The
    /// matcher reads this so the experimental image is weighted identically.
    package let intensityPower: Double
    /// Radial width (Å⁻¹) each spot is spread over when deposited, py4DSTEM's
    /// `corr_kernel_size`. The matcher reads this so the experimental image is
    /// built with exactly the same kernel as the templates.
    package let radialKernelInvAngstrom: Double
    /// How far apart two zone axes must be before they count as different
    /// orientations rather than two samples of one (radians). Used only to
    /// pick the runner-up that the reliability metric is measured against —
    /// see `selectOrientation` in OrientationMatcher.swift.
    package let distinctOrientationRad: Double

    package var count: Int { zoneAxes.count }

    // MARK: Generation

    /// Build a plan for `crystal`. `zoneAxisCount` sets the sampling density
    /// (≈ hemisphere points); `sgWidth`/`sgMax` are the excitation-error
    /// tolerances (Å⁻¹) selecting which reflections are "excited" at a zone axis.
    package static func generate(crystal: Crystal,
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
                         radialKernelInvAngstrom: Double = 0.08,
                         distinctOrientationDeg: Double = 10,
                         cancellation: AnalysisCancellationToken? = nil) -> OrientationPlan? {
        guard cancellation?.isCancelled != true else { return nil }
        guard let fft = FFT1D(n: nAzimuthal) else { return nil }
        let geo = PolarGeometry(nRadial: nRadial, nAzimuthal: nAzimuthal,
                                radialScale: kMax / Double(nRadial))
        let reflections = crystal.reflections(kMax: kMax)
        guard !reflections.isEmpty else { return nil }
        let axes = symmetry.sampleFundamentalZone(count: zoneAxisCount)
        let bases = axes.map(ACOMOrientation.detectorBasis)

        var templates: [[Float]] = []
        var allSpots: [[TemplateSpot]] = []
        var fftRe: [Float] = []
        var fftIm: [Float] = []
        templates.reserveCapacity(axes.count)
        allSpots.reserveCapacity(axes.count)
        fftRe.reserveCapacity(axes.count * nRadial * nAzimuthal)
        fftIm.reserveCapacity(axes.count * nRadial * nAzimuthal)

        for n in axes {
            if cancellation?.isCancelled == true { return nil }
            let spots = project(reflections: reflections, zoneAxis: n,
                                sgWidth: sgWidth, sgMax: sgMax,
                                wavelengthAngstrom: wavelengthAngstrom,
                                intensityPower: intensityPower)
            var polar = buildPolar(spots: spots, geometry: geo,
                                   azimBlurBins: azimBlurBins,
                                   radialKernelInvAngstrom: radialKernelInvAngstrom)
            normalizeUnit(&polar)
            let (re, im) = ringFFTs(polar, geo: geo, fft: fft)
            templates.append(polar)
            allSpots.append(spots.map {
                TemplateSpot(r: Float($0.r), azim: Float($0.azim), weight: Float($0.weight))
            })
            fftRe.append(contentsOf: re); fftIm.append(contentsOf: im)
        }

        return OrientationPlan(geometry: geo, symmetry: symmetry,
                               zoneAxes: axes, detectorBases: bases,
                               templateSpots: allSpots,
                               templates: templates, templateFFTRe: fftRe, templateFFTIm: fftIm,
                               intensityPower: intensityPower,
                               radialKernelInvAngstrom: radialKernelInvAngstrom,
                               distinctOrientationRad:
                                   distinctOrientationDeg * .pi / 180)
    }

    // MARK: Projection (zone axis → polar spots)

    /// Project a crystal's reflections for beam direction `zoneAxis` (unit
    /// vector): excited reflections (small |g·n|) map to (radius, azimuth) in
    /// the plane perpendicular to the beam, weighted by intensity × a Gaussian
    /// of the excitation error.
    ///
    /// `wavelengthAngstrom` selects the excitation-error model. Without it the
    /// Ewald sphere is flat (sg = g·n), which is odd under g → −g while the
    /// Gaussian weight is even — so every template comes out EXACTLY
    /// π-periodic in azimuth, the matcher's azimuthal correlation has two
    /// identical maxima 180° apart, and the reported in-plane angle is only
    /// determined modulo 180°. With a wavelength the sphere's curvature is
    /// included, sg = g·n + λ|g|²/2, which is even in g and therefore excites
    /// g and −g by different amounts — that asymmetry is what breaks the tie.
    ///
    /// DEVIATION (sign): py4DSTEM writes sg = (2g_z − λ|g|²)/(2 − 2λg_z) with
    /// k₀ = [0,0,−1/λ] (`Crystal.excitation_errors`). Its lab z is the
    /// NEGATIVE of this plan's zone axis — the two lab frames differ by the
    /// x↔y swap plus a z flip — so in terms of g·n the curvature term changes
    /// sign. Both forms are the same physics; only the frame differs.
    ///
    /// The curvature alone is not enough: with raw (power 1) intensities the
    /// brightest ring dominates the correlation and swamps the asymmetry. See
    /// `intensityPower`, which is what makes it visible.
    package static func project(reflections: [Reflection], zoneAxis n: SIMD3<Double>,
                        sgWidth: Double, sgMax: Double,
                        wavelengthAngstrom: Double? = nil,
                        intensityPower: Double = 0.25)
        -> [(r: Double, azim: Double, weight: Double)] {
        // In-plane basis is shared with the stored orientation matrix so the
        // Euler result cannot reconstruct a subtly different reference axis.
        let basis = ACOMOrientation.detectorBasis(zoneAxis: n)
        let e1 = basis.columns.0
        let e2 = basis.columns.1

        var spots: [(r: Double, azim: Double, weight: Double)] = []
        spots.reserveCapacity(reflections.count)
        let curvature = (wavelengthAngstrom ?? 0) / 2
        for refl in reflections {
            let sg = simd_dot(refl.g, n) + curvature * simd_length_squared(refl.g)
            if abs(sg) > sgMax { continue }
            // py4DSTEM raises the excited intensity as a whole, not the
            // structure factor alone: power(struct_factor * Ig, power_intensity).
            let excited = refl.intensity * exp(-(sg / sgWidth) * (sg / sgWidth))
            let w = intensityPower == 1 ? excited : pow(excited, intensityPower)
            let x = simd_dot(refl.g, e1)
            let y = simd_dot(refl.g, e2)
            spots.append((r: (x * x + y * y).squareRoot(), azim: atan2(y, x), weight: w))
        }
        return spots
    }

    // MARK: Polar image (shared with the matcher)

    /// Deposit spots into a [nRadial × nAzimuthal] image, apply a circular
    /// azimuthal Gaussian blur, and subtract each ring's mean (removes the DC
    /// term that would otherwise dominate the correlation).
    ///
    /// `radialKernelInvAngstrom` is py4DSTEM's `corr_kernel_size` (default
    /// 0.08 Å⁻¹, `crystal_ACOM.py`): the radial width over which a spot is
    /// spread. Zero reduces to nearest-bin deposition, which is exact for
    /// synthetic peaks — template and pattern round identically — but brittle
    /// on real peaks, where measurement and Q-calibration error move a peak
    /// across a bin edge and it stops overlapping its own template entirely.
    package static func buildPolar(spots: [(r: Double, azim: Double, weight: Double)],
                           geometry geo: PolarGeometry,
                           azimBlurBins: Double,
                           radialKernelInvAngstrom: Double = 0) -> [Float] {
        var img = [Float](repeating: 0, count: geo.nRadial * geo.nAzimuthal)
        let twoPi = 2 * Double.pi
        // σ in bins; ±3σ covers the kernel to <0.5% of its mass.
        let sigmaBins = radialKernelInvAngstrom / geo.radialScale
        let reach = sigmaBins > 0 ? max(1, Int((3 * sigmaBins).rounded())) : 0
        for s in spots {
            let exact = s.r / geo.radialScale
            let rb = Int(exact.rounded())
            if rb + reach < 0 || rb - reach >= geo.nRadial { continue }
            var a = s.azim.truncatingRemainder(dividingBy: twoPi)
            if a < 0 { a += twoPi }
            let ab = Int((a / twoPi * Double(geo.nAzimuthal)).rounded()) % geo.nAzimuthal
            if reach == 0 {
                if rb >= 0 && rb < geo.nRadial {
                    img[rb * geo.nAzimuthal + ab] += Float(s.weight)
                }
                continue
            }
            // Spread over neighbouring shells by the spot's true (unrounded)
            // radius, so sub-bin position is preserved instead of discarded.
            for bin in (rb - reach)...(rb + reach) where bin >= 0 && bin < geo.nRadial {
                let d = (Double(bin) - exact) / sigmaBins
                img[bin * geo.nAzimuthal + ab] += Float(s.weight * exp(-0.5 * d * d))
            }
        }
        if azimBlurBins > 0 { blurAzimuthal(&img, geo: geo, sigmaBins: azimBlurBins) }
        // Per-ring mean subtraction.
        for r in 0..<geo.nRadial {
            let base = r * geo.nAzimuthal
            var mean: Float = 0
            for a in 0..<geo.nAzimuthal { mean += img[base + a] }
            mean /= Float(geo.nAzimuthal)
            for a in 0..<geo.nAzimuthal { img[base + a] -= mean }
        }
        return img
    }

    /// Azimuthal FFT of every radial ring, ring-major layout.
    package static func ringFFTs(_ polar: [Float], geo: PolarGeometry, fft: FFT1D)
        -> (re: [Float], im: [Float]) {
        var outRe = [Float](repeating: 0, count: geo.nRadial * geo.nAzimuthal)
        var outIm = [Float](repeating: 0, count: geo.nRadial * geo.nAzimuthal)
        var re = [Float](repeating: 0, count: geo.nAzimuthal)
        var im = [Float](repeating: 0, count: geo.nAzimuthal)
        for r in 0..<geo.nRadial {
            let base = r * geo.nAzimuthal
            for a in 0..<geo.nAzimuthal { re[a] = polar[base + a]; im[a] = 0 }
            fft.transform(re: &re, im: &im, forward: true)
            for a in 0..<geo.nAzimuthal { outRe[base + a] = re[a]; outIm[base + a] = im[a] }
        }
        return (outRe, outIm)
    }

    // MARK: Helpers

    private static func blurAzimuthal(_ img: inout [Float], geo: PolarGeometry, sigmaBins: Double) {
        let radius = max(1, Int((3 * sigmaBins).rounded()))
        var taps = [Float](repeating: 0, count: 2 * radius + 1)
        var s: Float = 0
        for i in -radius...radius {
            let v = exp(-Float(i * i) / Float(2 * sigmaBins * sigmaBins))
            taps[i + radius] = v; s += v
        }
        for i in 0..<taps.count { taps[i] /= s }
        let na = geo.nAzimuthal
        var ring = [Float](repeating: 0, count: na)
        for r in 0..<geo.nRadial {
            let base = r * na
            for a in 0..<na {
                var acc: Float = 0
                for t in -radius...radius {
                    let aa = ((a + t) % na + na) % na        // circular
                    acc += img[base + aa] * taps[t + radius]
                }
                ring[a] = acc
            }
            for a in 0..<na { img[base + a] = ring[a] }
        }
    }

    package static func normalizeUnit(_ img: inout [Float]) {
        var norm: Float = 0
        for v in img { norm += v * v }
        norm = norm.squareRoot()
        if norm > 0 { for i in 0..<img.count { img[i] /= norm } }
    }


    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package init(geometry: PolarGeometry, symmetry: ACOMCrystalSymmetry, zoneAxes: [SIMD3<Double>], detectorBases: [simd_double3x3], templateSpots: [[TemplateSpot]], templates: [[Float]], templateFFTRe: [Float], templateFFTIm: [Float], intensityPower: Double, radialKernelInvAngstrom: Double, distinctOrientationRad: Double) {
        self.geometry = geometry
        self.symmetry = symmetry
        self.zoneAxes = zoneAxes
        self.detectorBases = detectorBases
        self.templateSpots = templateSpots
        self.templates = templates
        self.templateFFTRe = templateFFTRe
        self.templateFFTIm = templateFFTIm
        self.intensityPower = intensityPower
        self.radialKernelInvAngstrom = radialKernelInvAngstrom
        self.distinctOrientationRad = distinctOrientationRad
    }
}
