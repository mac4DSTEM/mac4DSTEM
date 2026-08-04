//
//  acom-groundtruth/main.swift
//  Role: standalone CLI wrapping the app's ACOM orientation matcher
//        (Crystal + OrientationPlan + OrientationMatcher, CPU backend) so a
//        Python driver can feed it synthetic diffraction patterns with KNOWN
//        orientations and check what mac4DSTEM's matcher recovers. Read-only
//        on mac4DSTEM/ — this file only links the production sources, it
//        never modifies them.
//
//  Usage: acom-groundtruth input.json > output.json
//
//  Crystal/plan construction mirrors
//  tools/training-dataset-campaign/main.swift's ACOM stage exactly (same
//  kMax/zoneAxisCount/symmetry plumbing into OrientationPlan.generate, same
//  nRadial/nAzimuthal defaults), and the orientation-matrix export mirrors
//  that file's `orientationMatrixRowMajor` construction verbatim (row-major
//  flattening of `EulerAngles.py4DSTEMOrientationMatrix`) so the two are
//  byte-comparable, just nested into 3 rows here instead of a flat 9.
//

import Foundation
import simd

// MARK: - Input schema

private struct InputPeak: Codable {
    let x: Double
    let y: Double
    let intensity: Double
}

private struct MatchInput: Codable {
    let cellAAngstrom: Double
    let siteFractional: [[Double]]
    let siteAtomicNumbers: [Int]
    let kMaxInvAngstrom: Double
    let zoneAxisCount: Int
    let symmetry: String
    let invAngstromPerPixel: Double
    let originX: Double
    let originY: Double
    /// Optional: when present, the plan uses the curved-Ewald excitation-error
    /// model instead of the flat one. Left absent to reproduce the shipped
    /// behaviour exactly.
    let wavelengthAngstrom: Double?
    /// Optional: py4DSTEM's power_intensity. Absent = 1 (shipped behaviour).
    let intensityPower: Double?
    /// Optional: py4DSTEM's corr_kernel_size (Å⁻¹). Absent = 0, i.e. the
    /// original nearest-radial-bin deposition.
    let radialKernelInvAngstrom: Double?
    /// Optional: minimum zone-axis separation (deg) for the reliability
    /// runner-up. Absent = the plan's default.
    let distinctOrientationDeg: Double?
    let patterns: [[InputPeak]]
}

// MARK: - Output schema

private struct MatchOutputResult: Codable {
    let templateIndex: Int
    let score: Double
    let secondScore: Double
    let inPlaneAngle: Double
    let zoneAxis: [Double]
    let orientationMatrixRowMajor: [[Double]]
    /// 1 − second/best, as the app reports it to the user.
    let reliability: Double
}

private struct GeometryOutput: Codable {
    let nRadial: Int
    let nAzimuthal: Int
    let radialScale: Double
}

private struct MatchOutput: Codable {
    let templateCount: Int
    let zoneAxes: [[Double]]
    let geometry: GeometryOutput
    /// Per template: Σ|T(r,φ) − T(r,φ+π)| / Σ|T(r,φ)|. Zero means the template
    /// is exactly π-periodic in azimuth, which makes the matcher's in-plane
    /// correlation have two identical maxima 180° apart — the argmax then has
    /// no information to choose between them.
    let templatePiAsymmetry: [Double]
    let results: [MatchOutputResult]
}

// MARK: - Entry point

@main
struct ACOMGroundTruth {
    static func main() throws {
        guard CommandLine.arguments.count >= 2 else {
            FileHandle.standardError.write(Data(
                "usage: acom-groundtruth input.json > output.json\n".utf8
            ))
            exit(64)
        }
        let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let input = try JSONDecoder().decode(
            MatchInput.self, from: Data(contentsOf: inputURL)
        )

        guard let symmetry = ACOMCrystalSymmetry(rawValue: input.symmetry) else {
            FileHandle.standardError.write(Data(
                "error: unknown symmetry '\(input.symmetry)' (expected cubic/hexagonal/identity)\n".utf8
            ))
            exit(65)
        }

        // Same cubic-cell construction the app uses for its named/custom
        // cubic presets: a = b = c = cellAAngstrom, angles 90°.
        let sites = zip(input.siteFractional, input.siteAtomicNumbers).map { fractional, z in
            AtomSite(z: z, fractional: SIMD3(fractional[0], fractional[1], fractional[2]))
        }
        let crystal = Crystal(
            a: input.cellAAngstrom, b: input.cellAAngstrom, c: input.cellAAngstrom,
            sites: sites
        )

        // Mirrors tools/training-dataset-campaign/main.swift's
        // OrientationPlan.generate(crystal:kMax:zoneAxisCount:symmetry:) call:
        // same kMax/zoneAxisCount/symmetry, default nRadial/nAzimuthal (32/128).
        guard let plan = OrientationPlan.generate(
            crystal: crystal, kMax: input.kMaxInvAngstrom,
            zoneAxisCount: input.zoneAxisCount, symmetry: symmetry,
            wavelengthAngstrom: input.wavelengthAngstrom,
            intensityPower: input.intensityPower ?? 1,
            radialKernelInvAngstrom: input.radialKernelInvAngstrom ?? 0,
            distinctOrientationDeg: input.distinctOrientationDeg ?? 10
        ) else {
            FileHandle.standardError.write(Data(
                "error: OrientationPlan.generate returned nil (no reflections within kMax?)\n".utf8
            ))
            exit(66)
        }

        guard let matcher = OrientationMatcher(plan: plan, symmetry: symmetry) else {
            FileHandle.standardError.write(Data(
                "error: OrientationMatcher init failed\n".utf8
            ))
            exit(67)
        }

        var results: [MatchOutputResult] = []
        results.reserveCapacity(input.patterns.count)
        for pattern in input.patterns {
            let peaks = pattern.map {
                BraggPeak(x: Float($0.x), y: Float($0.y), intensity: Float($0.intensity))
            }
            let result = matcher.match(
                peaks: peaks, originX: Float(input.originX), originY: Float(input.originY),
                invAngstromPerPixel: input.invAngstromPerPixel
            )

            var zoneAxis: [Double] = []
            var matrixRowMajor: [[Double]] = []
            if result.templateIndex >= 0 {
                let axis = plan.zoneAxes[result.templateIndex]
                zoneAxis = [axis.x, axis.y, axis.z]
                // Verbatim from tools/training-dataset-campaign/main.swift's
                // parityACOM export: m.columns.{0,1,2}.{x,y,z} row-major.
                let m = result.euler.py4DSTEMOrientationMatrix
                matrixRowMajor = [
                    [m.columns.0.x, m.columns.1.x, m.columns.2.x],
                    [m.columns.0.y, m.columns.1.y, m.columns.2.y],
                    [m.columns.0.z, m.columns.1.z, m.columns.2.z],
                ]
            }

            results.append(MatchOutputResult(
                templateIndex: result.templateIndex,
                score: Double(result.score),
                secondScore: Double(result.secondScore),
                inPlaneAngle: Double(result.inPlaneAngle),
                zoneAxis: zoneAxis,
                orientationMatrixRowMajor: matrixRowMajor,
                reliability: result.score > 0
                    ? Double(1 - result.secondScore / result.score) : 0
            ))
        }

        let output = MatchOutput(
            templateCount: plan.count,
            zoneAxes: plan.zoneAxes.map { [$0.x, $0.y, $0.z] },
            geometry: GeometryOutput(
                nRadial: plan.geometry.nRadial,
                nAzimuthal: plan.geometry.nAzimuthal,
                radialScale: plan.geometry.radialScale
            ),
            templatePiAsymmetry: plan.templates.map { template in
                let na = plan.geometry.nAzimuthal
                var difference = 0.0, total = 0.0
                for r in 0..<plan.geometry.nRadial {
                    let base = r * na
                    for a in 0..<na {
                        let opposite = template[base + (a + na / 2) % na]
                        difference += abs(Double(template[base + a] - opposite))
                        total += abs(Double(template[base + a]))
                    }
                }
                return total > 0 ? difference / total : 0
            },
            results: results
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        FileHandle.standardOutput.write(try encoder.encode(output))
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
