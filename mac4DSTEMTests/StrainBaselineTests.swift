import XCTest
import DSTEMCore
@testable import mac4DSTEM

/// The CuboStrain 0.6.0 consensus switch (2026-10-21): `estimateLatticeBasis` takes its support/residual/condition/tolerance from
/// `LatticeStrain.chooseBasisConsensusResult` and the reference's inliers from `referenceMADResult`. The baseline
/// (`Fixtures/Strain/strain-baseline-2026-10-21.json`) was written by the app's own re-scoring and `robustReferenceIndices`
/// at e333ec41/7b84cdaa, before they were deleted. Float32 throughout; compared within 1e-6 relative (the kit runs the same
/// Float32 source, so a mismatch beyond rounding is a bug, not noise).
final class StrainBaselineTests: XCTestCase {

    private static let origin = (x: Float(60), y: Float(64))

    /// A 12 x 10 scan: a square-ish lattice that varies smoothly, a distorted block, three positions with spurious peaks.
    static func vectors() -> BraggVectors {
        let w = 12, h = 10
        var state: UInt64 = 0x57A1
        func rnd() -> Float {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float((state >> 33) % 1_000_000) / 1_000_000 - 0.5
        }
        let hk: [(Float, Float)] = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1), (2, 0), (0, 2), (-2, 0), (0, -2)]
        var peaks = [[BraggPeak]]()
        for y in 0..<h { for x in 0..<w {
            var a: (Float, Float) = (12.0 + 0.02 * Float(x), 0.1 * rnd())
            var b: (Float, Float) = (0.1 * rnd(), 11.5 + 0.015 * Float(y))
            if x >= 8 && y >= 6 { a = (13.4 + 0.05 * rnd(), 0.4); b = (-0.3, 10.6 + 0.05 * rnd()) }   // distorted block
            var list = hk.map { hh, kk in
                BraggPeak(x: origin.x + hh * a.0 + kk * b.0 + 0.05 * rnd(), y: origin.y + hh * a.1 + kk * b.1 + 0.05 * rnd(),
                          intensity: 50 + 40 * (rnd() + 0.5))
            }
            if (x + 3 * y) % 17 == 0 { list.append(BraggPeak(x: origin.x + 5.3, y: origin.y - 7.9, intensity: 30)) }
            if (x * y) % 29 == 5 { list.removeLast(7) }   // too few peaks: unindexed
            peaks.append(list)
        } }
        return BraggVectors(scanWidth: w, scanHeight: h, peaks: peaks)
    }

    private static var baselineURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Strain/strain-baseline-2026-10-21.json")
    }

    private static func snapshot(_ m: StrainMap) -> [String: Any] {
        let d = m.diagnostics
        return [
            "refG1": [m.refG1.x, m.refG1.y].map(Double.init), "refG2": [m.refG2.x, m.refG2.y].map(Double.init),
            "referencePositionCount": m.referencePositionCount, "indexedFraction": Double(m.indexedFraction),
            "exx": m.exx.map(Double.init), "eyy": m.eyy.map(Double.init), "exy": m.exy.map(Double.init),
            "theta": m.theta.map(Double.init), "mask": m.mask,
            "diag": [
                "obs": d.basisObservationCount, "support": d.basisSupportCount, "fraction": Double(d.basisSupportFraction),
                "residual": Double(d.basisResidualPixels), "condition": Double(d.basisConditionNumber),
                "tolerance": Double(d.indexingTolerancePixels), "median": Double(d.localResidualMedianPixels),
                "candidates": d.referenceCandidateCount, "rejected": d.referenceRejectedCount,
                "refused": d.refusedLocalFitCount,
            ] as [String: Any],
        ]
    }

    func testStrainMapsAndDiagnosticsMatchTheBaselineWrittenByTheAppsOwnCode() throws {
        let v = Self.vectors()
        let n = v.scanWidth * v.scanHeight
        var mask = [Bool](repeating: false, count: n)
        for y in 0..<6 { for x in 0..<8 { mask[y * v.scanWidth + x] = true } }
        let auto = try XCTUnwrap(StrainMapper.compute(bragg: v, originX: Self.origin.x, originY: Self.origin.y, minNumPeaks: 5))
        let masked = try XCTUnwrap(StrainMapper.compute(bragg: v, originX: Self.origin.x, originY: Self.origin.y, minNumPeaks: 5,
                                                          referenceMask: mask))
        let snaps = ["auto": Self.snapshot(auto), "masked": Self.snapshot(masked)]
        if !FileManager.default.fileExists(atPath: Self.baselineURL.path) {
            try JSONSerialization.data(withJSONObject: snaps, options: [.sortedKeys]).write(to: Self.baselineURL)
            XCTFail("baseline written to \(Self.baselineURL.path)"); return
        }
        let base = try JSONSerialization.jsonObject(with: Data(contentsOf: Self.baselineURL)) as! [String: [String: Any]]
        for (name, new) in snaps {
            let old = base[name]!
            func close(_ a: Any, _ b: Any, _ what: String) {
                if let a = a as? [Double], let b = b as? [Double] {
                    XCTAssertEqual(a.count, b.count, what)
                    for (x, y) in zip(a, b) { XCTAssertEqual(x, y, accuracy: 1e-6 * max(1, abs(y)), "\(name) \(what)") }
                } else if let a = a as? Double, let b = b as? Double {
                    XCTAssertEqual(a, b, accuracy: 1e-6 * max(1, abs(b)), "\(name) \(what)")
                } else if let a = a as? Int, let b = b as? Int { XCTAssertEqual(a, b, "\(name) \(what)") }
                else if let a = a as? [Bool], let b = b as? [Bool] { XCTAssertEqual(a, b, "\(name) \(what)") }
                else if let a = a as? NSNumber, let b = b as? NSNumber { XCTAssertEqual(a, b, "\(name) \(what)") }
                else { XCTFail("type mismatch for \(what)") }
            }
            for key in ["refG1", "refG2", "referencePositionCount", "indexedFraction", "exx", "eyy", "exy", "theta", "mask"] {
                close(new[key]!, old[key]!, key)
            }
            let nd = new["diag"] as! [String: Any], od = old["diag"] as! [String: Any]
            for (key, value) in od { close(nd[key]!, value, "diag." + key) }
        }
    }
}
