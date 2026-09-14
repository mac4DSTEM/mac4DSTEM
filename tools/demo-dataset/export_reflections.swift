//
//  tools/demo-dataset/export_reflections.swift
//  Emits, for a fixed set of (crystal, zone axis) pairs, the zero-order-Laue-
//  zone reflections projected into the detector plane — the geometry input
//  `make_demo.py` stamps into the synthetic AlMgSi_demo.h5 cube (see
//  demo-dataset-brief.md). Uses the repo's own `Crystal.reflections(kMax:)`
//  and `Crystal.aluminum` / `Crystal.betaDoublePrime` so the simulated
//  spot positions and intensities cannot drift from what the app itself
//  would compute for the same structures.
//
//  `detectorBasis` below is copied from
//  mac4DSTEM/Core/Analysis/OrientationResult.swift:91-96 (as of 2026-09-14),
//  not linked from it: this is a generator, not a gate, and pulling in
//  OrientationResult.swift's own dependency chain here would be unrelated
//  weight for six lines of pure geometry (brief's own allowance).
//
//  Build (no app target, no signing):
//    xcrun swiftc -O -package-name mac4DSTEM -o export export_reflections.swift \
//      <repo>/mac4DSTEM/Core/Crystal/Crystal.swift \
//      <repo>/mac4DSTEM/Core/Crystal/ScatteringFactors.swift
//
//  Output: one JSON object on stdout, keyed by "<phase>_<uvw>", each an array
//  of {h,k,l,qx,qy,intensity} — qx,qy in Å⁻¹ at in-plane rotation 0 (grain and
//  precipitate rotations are applied later, in make_demo.py, per the shared
//  `PhaseReferenceLibrary.rotate` formula); intensity relative to the
//  strongest reflection kept for that (phase, zone axis).
//

import Foundation
import simd

// MARK: - detectorBasis (copied, see header)

enum CopiedACOMOrientation {
    static func detectorBasis(zoneAxis n: SIMD3<Double>) -> simd_double3x3 {
        let reference: SIMD3<Double> = abs(n.x) < 0.9 ? [1, 0, 0] : [0, 1, 0]
        let e1 = simd_normalize(simd_cross(n, reference))
        let e2 = simd_cross(n, e1)
        return simd_double3x3(columns: (e1, e2, n))
    }
}

// MARK: - Zone-axis direction (real-space, normalised over latReal)

func cartesianZoneAxis(_ uvw: SIMD3<Int>, crystal: Crystal) -> SIMD3<Double>? {
    let v = Double(uvw.x) * crystal.latReal[0]
        + Double(uvw.y) * crystal.latReal[1]
        + Double(uvw.z) * crystal.latReal[2]
    let n = simd_length(v)
    guard n.isFinite, n > 1e-12 else { return nil }
    return v / n
}

// MARK: - One (crystal, zone axis) entry

struct OutReflection: Codable {
    let h: Int, k: Int, l: Int
    let qx: Double, qy: Double
    let intensity: Double
}

func reflectionsFor(crystal: Crystal, uvw: SIMD3<Int>, kMax: Double,
                     zolzTolerance: Double, minIntensityFraction: Double) -> [OutReflection] {
    guard let n = cartesianZoneAxis(uvw, crystal: crystal) else { return [] }
    let basis = CopiedACOMOrientation.detectorBasis(zoneAxis: n)
    let e1 = basis.columns.0, e2 = basis.columns.1

    let all = crystal.reflections(kMax: kMax)
    var kept: [(OutReflection, Double)] = []
    var strongest = 0.0
    for r in all {
        let sg = simd_dot(r.g, n)
        guard abs(sg) <= zolzTolerance else { continue }
        let qx = simd_dot(r.g, e1)
        let qy = simd_dot(r.g, e2)
        strongest = max(strongest, r.intensity)
        kept.append((OutReflection(h: r.h, k: r.k, l: r.l, qx: qx, qy: qy, intensity: r.intensity), r.intensity))
    }
    guard strongest > 0 else { return [] }
    let floor = minIntensityFraction * strongest
    return kept.filter { $0.1 >= floor }
        .map { OutReflection(h: $0.0.h, k: $0.0.k, l: $0.0.l, qx: $0.0.qx, qy: $0.0.qy,
                              intensity: $0.1 / strongest) }
}

// MARK: - Main
// (a `@main` type rather than top-level statements, so this file can keep
// its descriptive name — top-level code compiles only from a literal
// `main.swift`.)

@main
enum ExportReflections {
    static func main() {
        let kMax = 0.9
        let zolzTolerance = 0.02   // Å⁻¹, per demo-dataset-brief.md §Reflections
        let minIntensityFraction = 0.02

        let jobs: [(name: String, crystal: Crystal, uvw: SIMD3<Int>)] = [
            ("Al_001", .aluminum, SIMD3(0, 0, 1)),
            ("Al_011", .aluminum, SIMD3(0, 1, 1)),
            ("Al_111", .aluminum, SIMD3(1, 1, 1)),
            ("betaDoublePrime_010", .betaDoublePrime, SIMD3(0, 1, 0)),
            ("betaDoublePrime_001", .betaDoublePrime, SIMD3(0, 0, 1)),
        ]

        var out: [String: [OutReflection]] = [:]
        for job in jobs {
            let refs = reflectionsFor(crystal: job.crystal, uvw: job.uvw, kMax: kMax,
                                       zolzTolerance: zolzTolerance,
                                       minIntensityFraction: minIntensityFraction)
            out[job.name] = refs
            FileHandle.standardError.write("\(job.name): \(refs.count) reflections\n".data(using: .utf8)!)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try! encoder.encode(out)
        FileHandle.standardOutput.write(data)
    }
}
