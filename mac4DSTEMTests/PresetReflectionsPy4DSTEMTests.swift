import XCTest
import DiffractoCore
import DiffractoScattering
import DSTEMCore
@testable import mac4DSTEM

/// The family check against an external oracle (2026-10-15, macTEM's refuter finding: compare against py4DSTEM or
/// pymatgen, never the Swift against itself). `Fixtures/py4dstem-preset-reflections.json` is written by
/// `tools/crystal-structures/py4dstem_preset_reflections.py` from the pinned py4DSTEM (f050d207): for nine presets, the
/// kept reflections of `Crystal.calculate_structure_factors(k_max, tol_structure_factor = 1e-4)` at |g| ≤ 1.2 Å⁻¹, with
/// the sites typed from `Crystal.swift`, not computed by any Swift. The app's preset lists (through DiffractoKit) must
/// hold the same hkl sets, the same |g| and the same F.
///
/// Tolerances, fixed before the first run: |g| to 1e-12 relative (both float64); Re F and Im F to 1e-6 of the preset's
/// largest |F| (py4DSTEM accumulates F in complex64, so its error scales with the summands, not with a cancelled sum);
/// a reflection py4DSTEM lists as within 1e-6 of the cut may be missing on either side (there are none today).
final class PresetReflectionsPy4DSTEMTests: XCTestCase {

    private struct Oracle: Decodable {
        struct Preset: Decodable { let reflections: [[Double]]; let borderline: [[Int]] }
        let kMax: Double
        let cut: Double
        let presets: [String: Preset]
    }

    private static let presets: [String: CrystalStructure] = [
        "aluminum": Crystal.aluminum, "gold": Crystal.gold, "nickel": Crystal.nickel, "copper": Crystal.copper,
        "iron": Crystal.iron, "silicon": Crystal.silicon, "magnesium": Crystal.magnesium,
        "betaDoublePrime": Crystal.betaDoublePrime, "tungstenDisulfide": Crystal.tungstenDisulfide,
    ]

    private func oracle() throws -> Oracle {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/py4dstem-preset-reflections.json")
        return try JSONDecoder().decode(Oracle.self, from: Data(contentsOf: url))
    }

    func testEveryPresetHoldsPy4DSTEMsReflectionsGAndF() throws {
        let oracle = try oracle()
        XCTAssertEqual(Set(oracle.presets.keys), Set(Self.presets.keys), "the fixture and the test name the same presets")
        for (name, structure) in Self.presets.sorted(by: { $0.key < $1.key }) {
            let reference = try XCTUnwrap(oracle.presets[name], name)
            let kept = try structure.kinematicReflections(kMax: oracle.kMax, cut: oracle.cut).kept
            struct Key: Hashable { let h, k, l: Int }
            var app: [Key: KinematicReflection] = [:]
            for r in kept { app[Key(h: r.h, k: r.k, l: r.l)] = r }
            var expected: [Key: [Double]] = [:]
            for row in reference.reflections { expected[Key(h: Int(row[0]), k: Int(row[1]), l: Int(row[2]))] = row }
            let borderline = Set(reference.borderline.map { Key(h: $0[0], k: $0[1], l: $0[2]) })

            let missing = Set(expected.keys).subtracting(app.keys).subtracting(borderline)
            let extra = Set(app.keys).subtracting(expected.keys).subtracting(borderline)
            XCTAssertTrue(missing.isEmpty, "\(name): \(missing.count) py4DSTEM reflections the app does not keep, e.g. \(missing.first.map { "\($0)" } ?? "")")
            XCTAssertTrue(extra.isEmpty, "\(name): \(extra.count) reflections py4DSTEM does not keep, e.g. \(extra.first.map { "\($0)" } ?? "")")

            let fMax = reference.reflections.map { ($0[4] * $0[4] + $0[5] * $0[5]).squareRoot() }.max() ?? 0
            var worstG = 0.0, worstF = 0.0
            for (key, row) in expected {
                guard let r = app[key] else { continue }
                worstG = max(worstG, abs(r.gLength - row[3]) / row[3])
                worstF = max(worstF, abs(r.structureFactorRe - row[4]), abs(r.structureFactorIm - row[5]))
            }
            XCTAssertLessThanOrEqual(worstG, 1e-12, "\(name): |g| differs from py4DSTEM by \(worstG) relative")
            XCTAssertLessThanOrEqual(worstF, 1e-6 * fMax, "\(name): F differs from py4DSTEM by \(worstF) (max |F| \(fMax))")
        }
    }
}
