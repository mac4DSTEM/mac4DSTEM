// RF refuter harness (own code). usage: rf <dir with planted.json> <tier[,tier]|all> [nameSubstring]
// Runs fitBestAvailable with DEFAULT arguments, the plant's guess and annulus; one ROW per case (key=value fields).
// With -D EXPOSE also prints the ring-sigma start the half-maximum estimator would give (variant a) next to HEAD's.
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
func angErr(_ x: Double, _ y: Double) -> Double {
    let r = abs(x - y).truncatingRemainder(dividingBy: .pi); return min(r, .pi - r)
}
guard CommandLine.arguments.count >= 3 else { print("usage: rf <dir> <tiers> [substr]"); exit(64) }
let dir = URL(fileURLWithPath: CommandLine.arguments[1])
let tiers = CommandLine.arguments[2]
let substr = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : ""
let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: dir.appendingPathComponent("planted.json")))
for c in manifest.cases {
    if tiers != "all" && !tiers.split(separator: ",").contains(where: { String($0) == c.tier }) { continue }
    if !substr.isEmpty && !c.name.contains(substr) { continue }
    let data = try Data(contentsOf: dir.appendingPathComponent(c.file))
    let pixels = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    let pattern = DiffractionPattern(qy: c.rows, qx: c.cols, pixels: pixels)
    let th = c.theta ?? 0
    var f = "ROW|name=\(c.name)|tier=\(c.tier)|noise=\(g(c.noise))|gap=\(g(c.gap_deg))|R=\(g(c.R))|ba_true=\(g(c.b / c.a))|sigma_true=\(g(c.sigma))"
    var seedFit: EllipseCalibrationFit? = nil
    do {
        let seed = try EllipseCalibration.fit1D(pattern: pattern, centerQX: c.guess_row, centerQY: c.guess_col,
                                                 innerRadius: c.inner, outerRadius: c.outer, maximumResidual: 0.4)
        seedFit = seed
        f += "|seed_dR=\(g((seed.a + seed.b) / 2 / c.R - 1))|seed_cerr=\(g(hypot(seed.centerQX - c.r0, seed.centerQY - c.c0)))|seed_cres=\(g(seed.conicResidual))"
    } catch { f += "|seed=THREW" }
    #if EXPOSE
    if let s = seedFit {
        // gather the same samples fitAmorphousRing would (circular annulus about the CALLER's guess)
        var vs = [Double](), xs = [Double](), ys = [Double]()
        for qx in 0..<c.rows { for qy in 0..<c.cols {
            let r = hypot(Double(qx) - c.guess_row, Double(qy) - c.guess_col)
            guard r > c.inner, r < c.outer else { continue }
            let v = Double(pixels[qx * c.cols + qy]); guard v.isFinite else { continue }
            xs.append(Double(qx)); ys.append(Double(qy)); vs.append(v)
        } }
        let st = EllipseCalibration.halfMaximumRingSigma(values: vs, xs: xs, ys: ys, seed: s, innerRadius: c.inner, outerRadius: c.outer)
        f += "|start_a=\(st.map { g($0) } ?? "nil")|start_head=\(g(max(1, (c.outer - c.inner) / 4)))"
    }
    #endif
    do {
        let fit = try EllipseCalibration.fitBestAvailable(pattern: pattern, centerQX: c.guess_row, centerQY: c.guess_col,
                                                          innerRadius: c.inner, outerRadius: c.outer)
        f += "|status=\(fit.model == .conic ? "conic" : "profile")|dR=\(g((fit.a + fit.b) / 2 / c.R - 1))"
        f += "|dba=\(g(fit.b / fit.a - c.b / c.a))|dth=\(g(c.theta == nil ? 0 : angErr(fit.theta, th)))|cerr=\(g(hypot(fit.centerQX - c.r0, fit.centerQY - c.c0)))"
        f += "|resid=\(g(fit.normalizedResidual))"
        if let pr = fit.profile {
            f += "|I1=\(g(pr.ringIntensity))|sin=\(g(pr.innerSigma))|sout=\(g(pr.outerSigma))|s0=\(g(pr.centralSigma))"
        } else { f += "|fallback=\((fit.profileFallbackReason ?? "nil").replacingOccurrences(of: "|", with: "/"))" }
    } catch { f += "|status=THREW|err=\("\(error)".replacingOccurrences(of: "|", with: "/"))" }
    print(f)
    fflush(stdout)
}
