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
nonisolated struct PolarGeometry {
    let nRadial: Int
    let nAzimuthal: Int          // power of two (azimuthal FFT length)
    let radialScale: Double      // radial units per bin
}

/// The library, with per-template azimuthal FFTs precomputed for matching.
nonisolated struct OrientationPlan {
    let geometry: PolarGeometry
    let zoneAxes: [SIMD3<Double>]
    /// py4DSTEM-style detector bases: lab x/y/z columns in crystal coordinates.
    let detectorBases: [simd_double3x3]
    /// Per template: real polar image [nRadial*nAzimuthal] (mean-subtracted,
    /// unit-normalized) — kept for inspection/visualization.
    let templates: [[Float]]
    /// Per template: azimuthal FFT of each radial ring, laid out ring-major
    /// [nRadial*nAzimuthal].
    let templateFFTRe: [[Float]]
    let templateFFTIm: [[Float]]

    var count: Int { zoneAxes.count }

    // MARK: Generation

    /// Build a plan for `crystal`. `zoneAxisCount` sets the sampling density
    /// (≈ hemisphere points); `sgWidth`/`sgMax` are the excitation-error
    /// tolerances (Å⁻¹) selecting which reflections are "excited" at a zone axis.
    static func generate(crystal: Crystal,
                         kMax: Double,
                         nRadial: Int = 32,
                         nAzimuthal: Int = 128,
                         zoneAxisCount: Int = 600,
                         sgWidth: Double = 0.03,
                         sgMax: Double = 0.1,
                         azimBlurBins: Double = 1.5,
                         cancellation: AnalysisCancellationToken? = nil) -> OrientationPlan? {
        guard cancellation?.isCancelled != true else { return nil }
        guard let fft = FFT1D(n: nAzimuthal) else { return nil }
        let geo = PolarGeometry(nRadial: nRadial, nAzimuthal: nAzimuthal,
                                radialScale: kMax / Double(nRadial))
        let reflections = crystal.reflections(kMax: kMax)
        guard !reflections.isEmpty else { return nil }
        let axes = CubicOrientationSymmetry.sampleFundamentalZone(count: zoneAxisCount)
        let bases = axes.map(ACOMOrientation.detectorBasis)

        var templates: [[Float]] = []
        var fftRe: [[Float]] = []
        var fftIm: [[Float]] = []
        templates.reserveCapacity(axes.count)

        for n in axes {
            if cancellation?.isCancelled == true { return nil }
            let spots = project(reflections: reflections, zoneAxis: n,
                                sgWidth: sgWidth, sgMax: sgMax)
            var polar = buildPolar(spots: spots, geometry: geo, azimBlurBins: azimBlurBins)
            normalizeUnit(&polar)
            let (re, im) = ringFFTs(polar, geo: geo, fft: fft)
            templates.append(polar); fftRe.append(re); fftIm.append(im)
        }

        return OrientationPlan(geometry: geo, zoneAxes: axes, detectorBases: bases,
                               templates: templates, templateFFTRe: fftRe, templateFFTIm: fftIm)
    }

    // MARK: Projection (zone axis → polar spots)

    /// Project a crystal's reflections for beam direction `zoneAxis` (unit
    /// vector): excited reflections (small |g·n|) map to (radius, azimuth) in
    /// the plane perpendicular to the beam, weighted by intensity × a Gaussian
    /// of the excitation error.
    static func project(reflections: [Reflection], zoneAxis n: SIMD3<Double>,
                        sgWidth: Double, sgMax: Double)
        -> [(r: Double, azim: Double, weight: Double)] {
        // In-plane basis is shared with the stored orientation matrix so the
        // Euler result cannot reconstruct a subtly different reference axis.
        let basis = ACOMOrientation.detectorBasis(zoneAxis: n)
        let e1 = basis.columns.0
        let e2 = basis.columns.1

        var spots: [(r: Double, azim: Double, weight: Double)] = []
        spots.reserveCapacity(reflections.count)
        for refl in reflections {
            let sg = simd_dot(refl.g, n)
            if abs(sg) > sgMax { continue }
            let w = refl.intensity * exp(-(sg / sgWidth) * (sg / sgWidth))
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
    static func buildPolar(spots: [(r: Double, azim: Double, weight: Double)],
                           geometry geo: PolarGeometry,
                           azimBlurBins: Double) -> [Float] {
        var img = [Float](repeating: 0, count: geo.nRadial * geo.nAzimuthal)
        let twoPi = 2 * Double.pi
        for s in spots {
            let rb = Int((s.r / geo.radialScale).rounded())
            if rb < 0 || rb >= geo.nRadial { continue }
            var a = s.azim.truncatingRemainder(dividingBy: twoPi)
            if a < 0 { a += twoPi }
            let ab = Int((a / twoPi * Double(geo.nAzimuthal)).rounded()) % geo.nAzimuthal
            img[rb * geo.nAzimuthal + ab] += Float(s.weight)
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
    static func ringFFTs(_ polar: [Float], geo: PolarGeometry, fft: FFT1D)
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

    static func normalizeUnit(_ img: inout [Float]) {
        var norm: Float = 0
        for v in img { norm += v * v }
        norm = norm.squareRoot()
        if norm > 0 { for i in 0..<img.count { img[i] /= norm } }
    }

}
