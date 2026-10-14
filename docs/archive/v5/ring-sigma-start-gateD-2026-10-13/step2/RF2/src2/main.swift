// RF2 estimator probe (own code). usage: est <dir> <namesfile|all>
// For each plant: conic seed (fit1D as fitBestAvailable calls it), the SAME samples fitAmorphousRing gathers, and the half-maximum ring-sigma start of
// candidate (a) under: the seed as is; theta negated; theta + pi/2; a = b = (a+b)/2 (circular); next to HEAD's start max(1, ringWidth/4).
import Foundation
struct Manifest: Decodable {
    struct Case: Decodable {
        let name: String, file: String, tier: String
        let rows: Int, cols: Int
        let r0: Double, c0: Double, R: Double, a: Double, b: Double
        let theta: Double?
        let noise: Double, gap_deg: Double, sigma: Double
        let inner: Double, outer: Double, guess_row: Double, guess_col: Double
    }
    let cases: [Case]
}
func g(_ v: Double) -> String { String(format: "%.9g", v) }
let dir = URL(fileURLWithPath: CommandLine.arguments[1])
var wanted: Set<String>? = nil
if CommandLine.arguments[2] != "all" {
    let txt = try String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8)
    wanted = Set(txt.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
}
let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: dir.appendingPathComponent("planted.json")))
func variant(_ s: EllipseCalibrationFit, a: Double? = nil, b: Double? = nil, theta: Double? = nil) -> EllipseCalibrationFit {
    EllipseCalibrationFit(centerQX: s.centerQX, centerQY: s.centerQY, a: a ?? s.a, b: b ?? s.b, theta: theta ?? s.theta,
                          normalizedResidual: s.normalizedResidual, conicResidual: s.conicResidual, sampleCount: s.sampleCount,
                          occupiedAngularBins: s.occupiedAngularBins, model: s.model, profile: s.profile,
                          profileFallbackReason: s.profileFallbackReason, sparseCoverage: s.sparseCoverage)
}
for c in manifest.cases {
    if let w = wanted, !w.contains(c.name) { continue }
    let data = try Data(contentsOf: dir.appendingPathComponent(c.file))
    let pixels = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    let pattern = DiffractionPattern(qy: c.rows, qx: c.cols, pixels: pixels)
    var f = "ROW|name=\(c.name)|tier=\(c.tier)|sigma_true=\(g(c.sigma))|R=\(g(c.R))|eps=\(g(c.a / c.b - 1))|inner=\(g(c.inner))|outer=\(g(c.outer))"
    f += "|start_head=\(g(max(1, (c.outer - c.inner) / 4)))"
    do {
        let seed = try EllipseCalibration.fit1D(pattern: pattern, centerQX: c.guess_row, centerQY: c.guess_col,
                                                 innerRadius: c.inner, outerRadius: c.outer, maximumResidual: 0.4)
        var vs = [Double](), xs = [Double](), ys = [Double]()
        for qx in 0..<c.rows { for qy in 0..<c.cols {
            let r = hypot(Double(qx) - c.guess_row, Double(qy) - c.guess_col)
            guard r > c.inner, r < c.outer else { continue }
            let v = Double(pixels[qx * c.cols + qy]); guard v.isFinite else { continue }
            xs.append(Double(qx)); ys.append(Double(qy)); vs.append(v)
        } }
        func est(_ s: EllipseCalibrationFit) -> String {
            EllipseCalibration.halfMaximumRingSigma(values: vs, xs: xs, ys: ys, seed: s, innerRadius: c.inner, outerRadius: c.outer).map { g($0) } ?? "nil"
        }
        f += "|seed_dR=\(g((seed.a + seed.b) / 2 / c.R - 1))|start_a=\(est(seed))|start_negtheta=\(est(variant(seed, theta: -seed.theta)))"
        f += "|start_rot90=\(est(variant(seed, theta: seed.theta + .pi / 2)))|start_circ=\(est(variant(seed, a: (seed.a + seed.b) / 2, b: (seed.a + seed.b) / 2)))"
    } catch { f += "|seed=THREW" }
    print(f); fflush(stdout)
}
