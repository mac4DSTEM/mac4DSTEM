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
//  Since 2026-10-15 the lattice, the reflection list and the detector basis are DiffractoKit's (`Crystal.swift` keeps
//  only the presets); run.sh builds the kit with `kit_module` and links it.
//
//  Build (no app target, no signing): see run.sh.
//
//  Output: one JSON object on stdout, keyed by "<phase>_<uvw>", each an array
//  of {h,k,l,qx,qy,intensity} — qx,qy in Å⁻¹ at in-plane rotation 0 (grain and
//  precipitate rotations are applied later, in make_demo.py, per the shared
//  `PhaseReferenceLibrary.rotate` formula); intensity relative to the
//  strongest reflection kept for that (phase, zone axis).
//

import Foundation
import simd
import DiffractoCore
import DiffractoGeometry
import DiffractoScattering

// MARK: - One (crystal, zone axis) entry

struct OutReflection: Codable {
    let h: Int, k: Int, l: Int
    let qx: Double, qy: Double
    let intensity: Double
}

func reflectionsFor(crystal: CrystalStructure, uvw: SIMD3<Int>, kMax: Double,
                     zolzTolerance: Double, minIntensityFraction: Double) -> [OutReflection] {
    guard let n = ZoneAxis(uvw.x, uvw.y, uvw.z).cartesian(in: crystal.cell) else { return [] }
    let basis = ZoneAxis.detectorBasis(n)
    let e1 = basis.columns.0, e2 = basis.columns.1

    let all = try! crystal.kinematicReflections(kMax: kMax).kept
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

        let jobs: [(name: String, crystal: CrystalStructure, uvw: SIMD3<Int>)] = [
            ("Al_001", Crystal.aluminum, SIMD3(0, 0, 1)),
            ("Al_011", Crystal.aluminum, SIMD3(0, 1, 1)),
            ("Al_111", Crystal.aluminum, SIMD3(1, 1, 1)),
            ("betaDoublePrime_010", Crystal.betaDoublePrime, SIMD3(0, 1, 0)),
            ("betaDoublePrime_001", Crystal.betaDoublePrime, SIMD3(0, 0, 1)),
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
