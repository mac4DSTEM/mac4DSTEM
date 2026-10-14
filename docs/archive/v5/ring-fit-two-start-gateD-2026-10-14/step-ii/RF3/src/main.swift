// RF3 harness (own code). usage: rf3 <dir with planted.json> <namesfile|all>
// Per case: the conic seed (fit1D at fitBestAvailable's own cap 0.4) and the default-argument fitBestAvailable result,
// with the seed's and the fit's departure from truth and the fit's mean-radius departure from the seed.
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
func g(_ v: Double) -> String { String(format: "%.17g", v) }
guard CommandLine.arguments.count >= 3 else { print("usage: rf3 <dir> <namesfile|all>"); exit(64) }
let dir = URL(fileURLWithPath: CommandLine.arguments[1])
let sel = CommandLine.arguments[2]
var wanted: Set<String>? = nil
if sel != "all" {
    let txt = try String(contentsOfFile: sel, encoding: .utf8)
    wanted = Set(txt.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
}
let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: dir.appendingPathComponent("planted.json")))
for c in manifest.cases {
    if let w = wanted, !w.contains(c.name) { continue }
    let data = try Data(contentsOf: dir.appendingPathComponent(c.file))
    let pixels = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    let pattern = DiffractionPattern(qy: c.rows, qx: c.cols, pixels: pixels)
    var f = "ROW|name=\(c.name)|tier=\(c.tier)|R=\(g(c.R))|ba_true=\(g(c.b / c.a))|sigma_true=\(g(c.sigma))|gap=\(g(c.gap_deg))"
    var seedR = Double.nan
    do {
        let s = try EllipseCalibration.fit1D(pattern: pattern, centerQX: c.guess_row, centerQY: c.guess_col,
                                             innerRadius: c.inner, outerRadius: c.outer, maximumResidual: 0.4)
        seedR = (s.a + s.b) / 2
        f += "|seed=ok|seed_dR=\(g(seedR / c.R - 1))|seed_dba=\(g(s.b / s.a - c.b / c.a))|seed_a=\(g(s.a))|seed_b=\(g(s.b))|seed_res=\(g(s.normalizedResidual))"
    } catch { f += "|seed=THREW:\("\(error)".replacingOccurrences(of: "|", with: "/"))" }
    do {
        let fit = try EllipseCalibration.fitBestAvailable(pattern: pattern, centerQX: c.guess_row, centerQY: c.guess_col,
                                                          innerRadius: c.inner, outerRadius: c.outer)
        f += "|status=\(fit.model == .conic ? "conic" : "profile")|dR=\(g((fit.a + fit.b) / 2 / c.R - 1))"
        f += "|dba=\(g(fit.b / fit.a - c.b / c.a))|depart=\(g((fit.a + fit.b) / 2 / seedR - 1))"
        f += "|fa=\(g(fit.a))|fb=\(g(fit.b))|resid=\(g(fit.normalizedResidual))|cres=\(g(fit.conicResidual))"
        if let pr = fit.profile {
            f += "|I1=\(g(pr.ringIntensity))|sin=\(g(pr.innerSigma))|sout=\(g(pr.outerSigma))"
        } else { f += "|fallback=\((fit.profileFallbackReason ?? "nil").replacingOccurrences(of: "|", with: "/"))" }
    } catch { f += "|status=THREW|err=\("\(error)".replacingOccurrences(of: "|", with: "/"))" }
    print(f)
    fflush(stdout)
}
