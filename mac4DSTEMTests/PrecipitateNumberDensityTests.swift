import XCTest
import DSTEMCore
import DSTEMSession
import ImagoCore
@testable import mac4DSTEM

/// N_V = areal density / typed thickness (suite task 41), on a planted foil. Registration, stated before the first run:
/// 100 x 100 scan, all 10 000 positions analysed, pixel 5 nm, four interior 2 x 2 precipitates that touch neither each other nor the
/// scan edge. Each weighs W·H / ((W − bx − 1)(H − by − 1)) = 10 000 / 97² = 1.062812; N_A = 4 · 1.062812 / (10 000 · 25 nm²)
/// = 1.70050e-5 nm⁻² (the first draft of this line said 1.70052e-5 and 170.052: an arithmetic slip, caught by the formula's own
/// test; the exact value is asserted below); thickness 100 ± 10 nm: P1 N_V = N_A / 100 = 170.050 /µm³; P2 σ = 10 % of it = 17.005 /µm³;
/// P3 no thickness or an unusable one (zero, negative, NaN): no N_V; P4 no scale: no N_V; P5 pixel 50 Å is the same foil: the same N_V;
/// P6 the CSV and the summary carry the same number; P7 the validation word is the kit's, "none".
final class PrecipitateNumberDensityTests: XCTestCase {
    private func foil() -> PrecipitateSegmentation.ClassMapObjects {
        var labels = [Int32](repeating: 0, count: 100 * 100)
        for (r, c) in [(20, 20), (20, 70), (70, 20), (70, 70)] {
            for dr in 0..<2 { for dc in 0..<2 { labels[(r + dr) * 100 + c + dc] = 1 } }
        }
        return PrecipitateSegmentation.classObjects(
            labels: labels, width: 100, height: 100, roles: .init(precipitateClasses: [1], matrix: [0], notIndexed: [9]),
            pixelSize: nil, pixelUnit: nil)
    }

    private func report(pixelSize: Double? = 5, unit: String? = "nm", t: Double? = 100, sigma: Double? = 10) -> PrecipitateObjectReport {
        PrecipitateObjectReport.make(
            objects: foil(), phaseNames: ["Al", "beta"], matrixPhaseIndex: 0, pixelSize: pixelSize, pixelUnit: unit,
            minimumAreaPx: 1, thicknessNm: t, thicknessSigmaNm: sigma)
    }

    func testAPlantedFoilRecoversNVAndItsSigma() throws {
        let s = try XCTUnwrap(report().summaries.first)
        XCTAssertEqual(s.countedObjects, 4)
        let weight = 10_000.0 / (97.0 * 97.0)
        let nA = 4 * weight / (10_000 * 25)                     // per nm²
        XCTAssertEqual(try XCTUnwrap(s.arealDensity), nA, accuracy: 1e-15)
        XCTAssertEqual(try XCTUnwrap(s.nVolumePerUm3), nA / 100 * 1e9, accuracy: 1e-9, "P1: 170.05 /µm³")
        XCTAssertEqual(try XCTUnwrap(s.nVolumeSigmaPerUm3), nA / 100 * 1e9 * 0.1, accuracy: 1e-9, "P2")
        XCTAssertEqual(try XCTUnwrap(s.nVolumePerUm3), 170.050, accuracy: 1e-3)
    }

    /// Mutation: the σ term dropped or the thickness not divided - red.
    func testNoUsableThicknessNoNV() {
        for t in [nil, 0, -5, Double.nan, .infinity] as [Double?] {
            XCTAssertNil(report(t: t).summaries.first?.nVolumePerUm3, "thickness \(String(describing: t))")
        }
        XCTAssertNil(report(pixelSize: nil, unit: nil).summaries.first?.nVolumePerUm3, "P4: no scale, no N_V")
        XCTAssertNil(report(unit: "furlong").summaries.first?.nVolumePerUm3, "a unit the app cannot convert gives no N_V")
    }

    func testTheSameFoilInAngstromIsTheSameNV() throws {
        let nm = try XCTUnwrap(report().summaries.first?.nVolumePerUm3)
        let angstrom = try XCTUnwrap(report(pixelSize: 50, unit: "Å").summaries.first?.nVolumePerUm3)
        XCTAssertEqual(angstrom, nm, accuracy: 1e-9 * nm, "P5")
    }

    func testNoSigmaGivesNoSigmaAndTheTextSaysSo() throws {
        let s = try XCTUnwrap(report(sigma: nil).summaries.first)
        XCTAssertNil(s.nVolumeSigmaPerUm3)
        XCTAssertEqual(PrecipitateThicknessRows.nVolumeText(s), "170 /µm³")
        let withSigma = try XCTUnwrap(report().summaries.first)
        XCTAssertEqual(PrecipitateThicknessRows.nVolumeText(withSigma), "170 ± 17.0 /µm³")
    }

    /// P6: the CSV carries the same number, the thickness and the assumption, and no validation word.
    func testTheCSVAndTheSummaryCarryTheSameNumber() throws {
        let r = report()
        let csv = r.csv()
        let n = try XCTUnwrap(r.summaries.first?.nVolumePerUm3)
        XCTAssertTrue(csv.contains("N_V \(PrecipitateObjectReport.number(n))"), csv)
        XCTAssertTrue(csv.contains("# N_V: areal density / thickness (100 nm +/- 10), assuming the objects span the foil\n"), csv)
        XCTAssertFalse(csv.contains("validation"), csv)
        // Without a thickness the CSV says nothing about N_V.
        XCTAssertFalse(report(t: nil).csv().contains("N_V"))
    }

    /// A report decoded from before N_V existed has none of it, and one that still carries the retired
    /// `numberDensityValidation` key decodes. Mutation: the new fields made non-optional - red.
    func testAnOldSnapshotDecodesWithoutNV() throws {
        let data = try JSONEncoder().encode(report(t: nil))
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["thicknessNm", "thicknessSigmaNm"] { object.removeValue(forKey: key) }
        object["numberDensityValidation"] = "none"
        let decoded = try JSONDecoder().decode(PrecipitateObjectReport.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(decoded.thicknessNm)
        XCTAssertNil(decoded.summaries.first?.nVolumePerUm3)
    }
}
