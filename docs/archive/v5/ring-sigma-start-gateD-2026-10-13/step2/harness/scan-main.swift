// Lane R scan harness (Gate D, ring-sigma start, 2026-10-13).
// usage: scan <plants-dir> <tier[,tier...]|all>
// Runs EllipseCalibration.fitBestAvailable with DEFAULT arguments, macTEM's centre guess and annulus per plant,
// and prints one ROW line of key=value fields per plant (seed, accepted fit, costs against the true ring's model).
import Foundation

struct Manifest: Decodable {
    struct Case: Decodable {
        let name: String, file: String, tier: String
        let rows: Int, cols: Int
        let r0: Double, c0: Double, R: Double, a: Double, b: Double, eps: Double, theta: Double?
        let noise: Double, gap_deg: Double, sigma: Double
        let inner: Double, outer: Double, guess_row: Double, guess_col: Double
    }
    let cases: [Case]
}

// The 11-parameter model, written from fitAmorphousRing's `predictions`.
func modelAt(_ p: [Double], x: Double, y: Double) -> Double {
    let a = p[8], b = p[9], theta = p[10]
    let st = sin(theta), ct = cos(theta); let a2 = a * a, b2 = b * b
    var A = st * st / b2 + ct * ct / a2, B = 2 * (b2 - a2) * st * ct / (a2 * b2), C = ct * ct / b2 + st * st / a2
    let r = (a + b) / 2; A *= r * r; B *= r * r; C *= r * r
    let dx = x - p[6], dy = y - p[7]
    let e2 = max(0, A * dx * dx + B * dx * dy + C * dy * dy); let delta = sqrt(e2) - r
    let sg = delta < 0 ? 2 * p[3] * p[3] : 2 * p[4] * p[4]
    return p[0] * exp(-e2 / (2 * p[2] * p[2])) + p[1] * exp(-delta * delta / sg) + p[5]
}
func angleError(_ lhs: Double, _ rhs: Double) -> Double {
    let raw = abs(lhs - rhs).truncatingRemainder(dividingBy: .pi)
    return min(raw, .pi - raw)
}
func g(_ v: Double) -> String { String(format: "%.9g", v) }

guard CommandLine.arguments.count >= 3 else { print("usage: scan <plants-dir> <tiers>"); exit(64) }
let dir = URL(fileURLWithPath: CommandLine.arguments[1])
let tiers = CommandLine.arguments[2]
let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: dir.appendingPathComponent("planted.json")))
for c in manifest.cases {
    if tiers != "all" && !tiers.split(separator: ",").contains(where: { String($0) == c.tier }) { continue }
    let data = try Data(contentsOf: dir.appendingPathComponent(c.file))
    let pixels = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    let pattern = DiffractionPattern(qy: c.rows, qx: c.cols, pixels: pixels)
    // The annulus fitAmorphousRing reads: radius > inner and < outer about the CALLER's centre.
    var xs = [Double](), ys = [Double](), vs = [Double]()
    var mn = Double.greatestFiniteMagnitude, mx = -Double.greatestFiniteMagnitude
    for qx in 0..<c.rows { for qy in 0..<c.cols {
        let r = hypot(Double(qx) - c.guess_row, Double(qy) - c.guess_col)
        guard r > c.inner, r < c.outer else { continue }
        let v = Double(pixels[qx * c.cols + qy]); xs.append(Double(qx)); ys.append(Double(qy)); vs.append(v)
        mn = min(mn, v); mx = max(mx, v)
    } }
    let dyn = mx - mn
    let theta = c.theta ?? 0
    func rms(_ p: [Double]) -> Double {
        var s = 0.0
        for i in vs.indices { let e = modelAt(p, x: xs[i], y: ys[i]) - vs[i]; s += e * e }
        return (s / Double(vs.count)).squareRoot()
    }
    let truthP = [0, 1, 10, c.sigma, c.sigma, 0, c.r0, c.c0, c.a, c.b, theta]
    // Truth geometry and ring widths, amplitude and constant FITTED (2-term linear least squares): the true ring's
    // best model on these pixels.
    var sRR = 0.0, sR1 = 0.0, s11 = 0.0, sRv = 0.0, s1v = 0.0
    for i in vs.indices {
        let ring = modelAt(truthP, x: xs[i], y: ys[i])
        sRR += ring * ring; sR1 += ring; s11 += 1; sRv += ring * vs[i]; s1v += vs[i]
    }
    let det = sRR * s11 - sR1 * sR1
    let i1Fit = (sRv * s11 - sR1 * s1v) / det, cFit = (sRR * s1v - sR1 * sRv) / det
    let truthFitP = [0, i1Fit, 10, c.sigma, c.sigma, cFit, c.r0, c.c0, c.a, c.b, theta]

    var f = "ROW|name=\(c.name)|tier=\(c.tier)|noise=\(g(c.noise))|gap=\(g(c.gap_deg))|Rtrue=\(g(c.R))|eps=\(g(c.eps))"
    f += "|ba_true=\(g(c.b / c.a))|theta_true=\(g(theta))|dyn=\(g(dyn))|n=\(vs.count)"
    f += "|cost_truth=\(g(rms(truthP)))|cost_truthfit=\(g(rms(truthFitP)))|truth_i1fit=\(g(i1Fit))|truth_cfit=\(g(cFit))"
    // The conic seed fitBestAvailable starts from.
    do {
        let seed = try EllipseCalibration.fit1D(pattern: pattern, centerQX: c.guess_row, centerQY: c.guess_col,
                                                 innerRadius: c.inner, outerRadius: c.outer, maximumResidual: 0.4)
        f += "|seed_dR=\(g((seed.a + seed.b) / 2 / c.R - 1))|seed_cerr=\(g(hypot(seed.centerQX - c.r0, seed.centerQY - c.c0)))"
        f += "|seed_ba=\(g(seed.b / seed.a))|seed_res=\(g(seed.conicResidual))"
    } catch { f += "|seed=THREW(\(error))" }
    do {
        let fit = try EllipseCalibration.fitBestAvailable(pattern: pattern, centerQX: c.guess_row, centerQY: c.guess_col,
                                                          innerRadius: c.inner, outerRadius: c.outer)
        f += "|status=\(fit.model == .conic ? "conic" : "profile")|dR=\(g((fit.a + fit.b) / 2 / c.R - 1))"
        f += "|ba=\(g(fit.b / fit.a))|dba=\(g(fit.b / fit.a - c.b / c.a))|cerr=\(g(hypot(fit.centerQX - c.r0, fit.centerQY - c.c0)))"
        f += "|a=\(g(fit.a))|b=\(g(fit.b))|theta=\(g(fit.theta))|dtheta=\(g(angleError(fit.theta, theta)))"
        f += "|cx=\(g(fit.centerQX))|cy=\(g(fit.centerQY))|resid=\(g(fit.normalizedResidual))"
        if let pr = fit.profile {
            let p = [pr.centralIntensity, pr.ringIntensity, pr.centralSigma, pr.innerSigma, pr.outerSigma, pr.background,
                     fit.centerQX, fit.centerQY, fit.a, fit.b, fit.theta]
            f += "|I0=\(g(pr.centralIntensity))|I1=\(g(pr.ringIntensity))|I1rel=\(g(pr.ringIntensity / dyn))|s0=\(g(pr.centralSigma))"
            f += "|sin=\(g(pr.innerSigma))|sout=\(g(pr.outerSigma))|c=\(g(pr.background))|cost_fit=\(g(rms(p)))"
        } else {
            f += "|fallback=\(fit.profileFallbackReason ?? "nil")"
        }
    } catch { f += "|status=THREW|err=\(error)" }
    print(f)
    fflush(stdout)
}
