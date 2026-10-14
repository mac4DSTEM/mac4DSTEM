// RF2 harness (own code). usage: rf2 <dir with planted.json> <namesfile|all>
// For each case (or each name listed, one per line, exact match) runs fitBestAvailable with DEFAULT arguments, the manifest's
// guess centre and annulus; prints one ROW per case with full-precision (%.17g) results and the full profile parameters.
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
func angErr(_ x: Double, _ y: Double) -> Double {
    let r = abs(x - y).truncatingRemainder(dividingBy: .pi); return min(r, .pi - r)
}
guard CommandLine.arguments.count >= 3 else { print("usage: rf2 <dir> <namesfile|all>"); exit(64) }
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
    let th = c.theta ?? 0
    var f = "ROW|name=\(c.name)|tier=\(c.tier)|R=\(g(c.R))|ba_true=\(g(c.b / c.a))|sigma_true=\(g(c.sigma))"
    do {
        let fit = try EllipseCalibration.fitBestAvailable(pattern: pattern, centerQX: c.guess_row, centerQY: c.guess_col,
                                                          innerRadius: c.inner, outerRadius: c.outer)
        f += "|status=\(fit.model == .conic ? "conic" : "profile")|dR=\(g((fit.a + fit.b) / 2 / c.R - 1))"
        f += "|dba=\(g(fit.b / fit.a - c.b / c.a))|dth=\(g(c.theta == nil ? 0 : angErr(fit.theta, th)))|cerr=\(g(hypot(fit.centerQX - c.r0, fit.centerQY - c.c0)))"
        f += "|resid=\(g(fit.normalizedResidual))|cres=\(g(fit.conicResidual))"
        f += "|cx=\(g(fit.centerQX))|cy=\(g(fit.centerQY))|fa=\(g(fit.a))|fb=\(g(fit.b))|fth=\(g(fit.theta))"
        if let pr = fit.profile {
            f += "|I0=\(g(pr.centralIntensity))|I1=\(g(pr.ringIntensity))|s0=\(g(pr.centralSigma))|sin=\(g(pr.innerSigma))|sout=\(g(pr.outerSigma))|cbg=\(g(pr.background))"
        } else { f += "|fallback=\((fit.profileFallbackReason ?? "nil").replacingOccurrences(of: "|", with: "/"))" }
    } catch { f += "|status=THREW|err=\("\(error)".replacingOccurrences(of: "|", with: "/"))" }
    print(f)
    fflush(stdout)
}
