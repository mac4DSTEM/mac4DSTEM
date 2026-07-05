//
//  StrainMapping.swift
//  Role: Strain mapping from detected Bragg vectors (py4DSTEM: process/strain).
//        Pipeline per py4DSTEM latticevectors.py:
//
//   1. choose two reference reciprocal-lattice vectors g1, g2
//   2. index every position's Bragg peaks to integer (h, k) about the origin
//      (index_bragg_directions: M = round(β⁻¹·(g − origin)))
//   3. fit the local lattice matrix at each position by intensity-weighted
//      least squares (fit_lattice_vectors)
//   4. take the reference lattice as the mean over valid positions
//      (get_reference_g1g2)
//   5. strain per position = deviation of the local lattice from the
//      reference (get_strain_from_reference_g1g2):
//        β = (M_ref⁻¹ · M_local)ᵀ
//        e_xx = 1 − β₀₀,  e_yy = 1 − β₁₁,
//        e_xy = −(β₀₁ + β₁₀)/2,  θ = (β₀₁ − β₁₀)/2
//
//  Strain is expressed in diffraction-space x/y. Rotating into a chosen real-
//  space axis (py4DSTEM get_rotated_strain_map) is a later refinement, as is
//  a user-selected reference region and manual g1/g2 — here g1/g2 are auto-
//  picked (shortest non-collinear pair) and the reference is the scan mean.
//

import Foundation

enum StrainComponent: String, CaseIterable, Identifiable {
    case exx   = "ε_xx"
    case eyy   = "ε_yy"
    case exy   = "ε_xy"
    case theta = "θ (rotation)"
    var id: String { rawValue }
}

struct StrainMap {
    let width: Int
    let height: Int
    let exx: [Float]
    let eyy: [Float]
    let exy: [Float]
    let theta: [Float]
    let mask: [Bool]                      // false → too few peaks to fit
    let refG1: (x: Float, y: Float)
    let refG2: (x: Float, y: Float)
    let indexedFraction: Float           // fraction of positions successfully fit

    /// One component as a display image; masked positions are set to 0 (the
    /// center of a diverging colormap).
    func component(_ c: StrainComponent) -> FloatImage {
        let source: [Float]
        switch c {
        case .exx:   source = exx
        case .eyy:   source = eyy
        case .exy:   source = exy
        case .theta: source = theta
        }
        var out = source
        for i in 0..<out.count where !mask[i] { out[i] = 0 }
        return FloatImage(width: width, height: height, pixels: out)
    }
}

enum StrainMapping {

    /// Full strain-map computation from a set of Bragg vectors and a diffraction
    /// origin. Returns nil if a lattice basis can't be established.
    nonisolated static func compute(bragg: BraggVectors,
                                    originX: Float, originY: Float,
                                    minNumPeaks: Int = 5) -> StrainMap? {
        let w = bragg.scanWidth, h = bragg.scanHeight
        let n = w * h

        guard let (g1, g2) = chooseLatticeVectors(bragg: bragg, x0: originX, y0: originY)
        else { return nil }

        // Per-position local lattice vectors, from indexing + weighted fit.
        var lg1x = [Float](repeating: 0, count: n)
        var lg1y = [Float](repeating: 0, count: n)
        var lg2x = [Float](repeating: 0, count: n)
        var lg2y = [Float](repeating: 0, count: n)
        var mask = [Bool](repeating: false, count: n)

        // β for indexing: columns are g1, g2. index = β⁻¹ · (peak − origin).
        guard let betaInv = invert2x2(g1.x, g2.x, g1.y, g2.y) else { return nil }

        for idx in 0..<n {
            let peaks = bragg.peaks[idx]
            if peaks.count < minNumPeaks { continue }

            // Index and accumulate the weighted normal equations for the fit
            // of [x0, y0, g1, g2] (basis rows [1, h, k]).
            var hks = [(h: Float, k: Float, x: Float, y: Float, wgt: Float)]()
            hks.reserveCapacity(peaks.count)
            for p in peaks {
                let vx = p.x - originX, vy = p.y - originY
                let hf = betaInv.a * vx + betaInv.b * vy
                let kf = betaInv.c * vx + betaInv.d * vy
                hks.append((h: hf.rounded(), k: kf.rounded(),
                            x: p.x - originX, y: p.y - originY,
                            wgt: max(p.intensity, 0)))
            }
            guard let fit = fitLattice(hks) else { continue }
            lg1x[idx] = fit.g1x; lg1y[idx] = fit.g1y
            lg2x[idx] = fit.g2x; lg2y[idx] = fit.g2y
            mask[idx] = true
        }

        // Reference lattice = mean over valid positions.
        var refG1 = (x: Float(0), y: Float(0))
        var refG2 = (x: Float(0), y: Float(0))
        var valid = 0
        for idx in 0..<n where mask[idx] {
            refG1.x += lg1x[idx]; refG1.y += lg1y[idx]
            refG2.x += lg2x[idx]; refG2.y += lg2y[idx]
            valid += 1
        }
        guard valid > 0 else { return nil }
        let inv = 1 / Float(valid)
        refG1.x *= inv; refG1.y *= inv; refG2.x *= inv; refG2.y *= inv

        // Strain per position vs reference.
        var exx = [Float](repeating: 0, count: n)
        var eyy = [Float](repeating: 0, count: n)
        var exy = [Float](repeating: 0, count: n)
        var theta = [Float](repeating: 0, count: n)
        // M_ref rows are the reference g1, g2.
        guard let mRefInv = invert2x2(refG1.x, refG1.y, refG2.x, refG2.y) else { return nil }

        for idx in 0..<n where mask[idx] {
            // X = M_ref⁻¹ · M_local ; β = Xᵀ.  M_local rows = local g1, g2.
            let m00 = lg1x[idx], m01 = lg1y[idx]
            let m10 = lg2x[idx], m11 = lg2y[idx]
            let x00 = mRefInv.a * m00 + mRefInv.b * m10
            let x01 = mRefInv.a * m01 + mRefInv.b * m11
            let x10 = mRefInv.c * m00 + mRefInv.d * m10
            let x11 = mRefInv.c * m01 + mRefInv.d * m11
            // β = Xᵀ
            let b00 = x00, b01 = x10, b10 = x01, b11 = x11
            exx[idx]   = 1 - b00
            eyy[idx]   = 1 - b11
            exy[idx]   = -(b01 + b10) / 2
            theta[idx] = (b01 - b10) / 2
        }

        return StrainMap(width: w, height: h,
                         exx: exx, eyy: eyy, exy: exy, theta: theta, mask: mask,
                         refG1: refG1, refG2: refG2,
                         indexedFraction: Float(valid) / Float(n))
    }

    // MARK: - Lattice-vector selection

    /// Auto-pick two reference lattice vectors: the shortest peak vector (about
    /// the origin), and the shortest one sufficiently non-collinear with it.
    nonisolated static func chooseLatticeVectors(bragg: BraggVectors,
                                                 x0: Float, y0: Float,
                                                 minRadius: Float = 2)
        -> (g1: (x: Float, y: Float), g2: (x: Float, y: Float))? {
        var vecs: [(x: Float, y: Float, r: Float)] = []
        for positionPeaks in bragg.peaks {
            for p in positionPeaks {
                let vx = p.x - x0, vy = p.y - y0
                let r = (vx * vx + vy * vy).squareRoot()
                if r > minRadius { vecs.append((vx, vy, r)) }
            }
        }
        guard vecs.count >= 2 else { return nil }
        vecs.sort { $0.r < $1.r }

        let g1 = vecs[0]
        // Non-collinear: |sin(angle)| > ~0.34  (≈ 20°..160°).
        for v in vecs {
            let cross = abs(v.x * g1.y - v.y * g1.x)
            if cross / (v.r * g1.r) > 0.34 {
                return ((g1.x, g1.y), (v.x, v.y))
            }
        }
        return nil
    }

    // MARK: - Weighted lattice fit (fit_lattice_vectors)

    /// Intensity-weighted least-squares fit of [origin, g1, g2] to indexed
    /// peaks. Basis row for a peak is [1, h, k]; solves the 3×3 normal
    /// equations for each of the x and y coordinates.
    private nonisolated static func fitLattice(
        _ peaks: [(h: Float, k: Float, x: Float, y: Float, wgt: Float)]
    ) -> (g1x: Float, g1y: Float, g2x: Float, g2y: Float)? {
        // Normal equations MᵀW M (3×3, symmetric) and MᵀW·[x, y] (3×2).
        var ata = [Double](repeating: 0, count: 9)
        var atbx = [Double](repeating: 0, count: 3)
        var atby = [Double](repeating: 0, count: 3)
        for p in peaks {
            let w = Double(p.wgt)
            let b = [1.0, Double(p.h), Double(p.k)]
            for i in 0..<3 {
                atbx[i] += w * b[i] * Double(p.x)
                atby[i] += w * b[i] * Double(p.y)
                for j in 0..<3 { ata[i * 3 + j] += w * b[i] * b[j] }
            }
        }
        guard let cx = solve3(ata, atbx), let cy = solve3(ata, atby) else { return nil }
        // c[0] = origin, c[1] = g1, c[2] = g2 for each coordinate.
        return (g1x: Float(cx[1]), g1y: Float(cy[1]),
                g2x: Float(cx[2]), g2y: Float(cy[2]))
    }

    // MARK: - Linear algebra helpers

    private nonisolated static func invert2x2(_ a: Float, _ b: Float, _ c: Float, _ d: Float)
        -> (a: Float, b: Float, c: Float, d: Float)? {
        // Inverse of [[a, b], [c, d]].
        let det = a * d - b * c
        guard abs(det) > 1e-12 else { return nil }
        let inv = 1 / det
        return (a: d * inv, b: -b * inv, c: -c * inv, d: a * inv)
    }

    /// Solve a 3×3 system by Gaussian elimination with partial pivoting.
    private nonisolated static func solve3(_ aIn: [Double], _ bIn: [Double]) -> [Double]? {
        var a = aIn, b = bIn
        for col in 0..<3 {
            var pivot = col
            for row in (col + 1)..<3 where abs(a[row * 3 + col]) > abs(a[pivot * 3 + col]) {
                pivot = row
            }
            if abs(a[pivot * 3 + col]) < 1e-12 { return nil }
            if pivot != col {
                for k in 0..<3 { a.swapAt(col * 3 + k, pivot * 3 + k) }
                b.swapAt(col, pivot)
            }
            for row in (col + 1)..<3 {
                let f = a[row * 3 + col] / a[col * 3 + col]
                for k in col..<3 { a[row * 3 + k] -= f * a[col * 3 + k] }
                b[row] -= f * b[col]
            }
        }
        var x = [Double](repeating: 0, count: 3)
        for row in stride(from: 2, through: 0, by: -1) {
            var v = b[row]
            for k in (row + 1)..<3 { v -= a[row * 3 + k] * x[k] }
            x[row] = v / a[row * 3 + row]
        }
        return x
    }
}
