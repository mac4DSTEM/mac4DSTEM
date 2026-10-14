// Lane G search harness (Gate D, ring-fit two-start, step (ii), 2026-10-14): lane F's generator plus an optional
// background tail value += tail * (R / max(r, 1))^2, r the plain distance from the plant centre (applied after the gap).
// usage: search <seed0> <seed1> <noise[,noise...]> [sizes] [radii]      one ROW per plant (lane F's grid, tail 0)
//        search one <size> <R> <eps> <thetaDeg> <gapDeg> <noise> <seed> [tail]
//        search grid <size> <R,..> <eps,..> <thetaDeg,..> <noise,..> <tail,..> <seed0> <seed1> [part parts]   gap 0
// Plants: I = exp(-((rho - 1) R)^2 / (2 s^2)), s = 3, rho the elliptical radius (a along theta in (row, col)),
// R = (a + b)/2, a/b = 1 + eps, optional gap, additive Gaussian noise (SplitMix64 + Box-Muller, Double math, Float pixels).
import Foundation

struct SplitMix64 {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    /// Uniform in (0, 1).
    mutating func uniform() -> Double { (Double(next() >> 11) + 0.5) / 9_007_199_254_740_992.0 }
}

struct Plant {
    var size: Int, radius: Double, eps: Double, thetaDegrees: Double, gap: Double, noise: Double, seed: Int, tail: Double = 0
    var gapStart: Double { Double((47 * seed) % 360) }
    var b: Double { 2 * radius / (2 + eps) }
    var a: Double { b * (1 + eps) }
    var centerQX: Double { Double(size) / 2 + 0.37 + 2.5 * sin(1.3 * Double(seed) + 0.2) }
    var centerQY: Double { Double(size) / 2 - 0.41 + 2.5 * cos(1.9 * Double(seed) + 0.7) }
    var id: String { "n\(size)-R\(Int(radius))-e\(Int((eps * 1000).rounded()))-t\(thetaDegrees)-g\(Int(gap))-s\(Int((noise * 1000).rounded()))-k\(seed)\(tail > 0 ? "-T\(Int((tail * 100).rounded()))" : "")" }

    func render() -> DiffractionPattern {
        let theta = thetaDegrees * .pi / 180
        let sin2 = sin(theta) * sin(theta), cos2 = cos(theta) * cos(theta)
        let A = sin2 / (b * b) + cos2 / (a * a)
        let C = cos2 / (b * b) + sin2 / (a * a)
        let B = 2 * (b * b - a * a) * sin(theta) * cos(theta) / (a * a * b * b)
        let mean = (a + b) / 2
        var rng = SplitMix64(state: UInt64(seed) &+ 1)
        var pixels = [Float](repeating: 0, count: size * size)
        var spare = 0.0
        for qx in 0..<size {
            for qy in 0..<size {
                let dx = Double(qx) - centerQX, dy = Double(qy) - centerQY
                let rho = max(0, A * dx * dx + B * dx * dy + C * dy * dy).squareRoot()
                let distance = (rho - 1) * mean
                var value = exp(-(distance * distance) / (2 * 3.0 * 3.0))
                if gap > 0 {
                    var angle = atan2(dy, dx) * 180 / .pi
                    angle = (angle - gapStart).truncatingRemainder(dividingBy: 360)
                    if angle < 0 { angle += 360 }
                    if angle < gap { value = 0 }
                }
                if tail > 0 {
                    let r = max(hypot(dx, dy), 1)
                    value += tail * (radius / r) * (radius / r)
                }
                if noise > 0 {
                    let index = qx * size + qy
                    if index % 2 == 0 {
                        let u1 = rng.uniform(), u2 = rng.uniform()
                        let r = (-2 * log(u1)).squareRoot()
                        value += noise * r * cos(2 * .pi * u2)
                        spare = noise * r * sin(2 * .pi * u2)
                    } else {
                        value += spare
                    }
                }
                pixels[qx * size + qy] = Float(value)
            }
        }
        return DiffractionPattern(qy: size, qx: size, pixels: pixels)
    }
}

func angleError(_ lhs: Double, _ rhs: Double) -> Double {
    let raw = abs(lhs - rhs).truncatingRemainder(dividingBy: .pi)
    return min(raw, .pi - raw)
}
func g(_ v: Double) -> String { String(format: "%.6g", v) }

// PERTURB (env): added to the centre guess, to see whether a plant's outcome is a basin or a rounding accident.
let perturb = Double(ProcessInfo.processInfo.environment["PERTURB"] ?? "0") ?? 0
func run(_ p: Plant) {
    let pattern = p.render()
    let start = DispatchTime.now()
    var f = "ROW|id=\(p.id)|size=\(p.size)|R=\(Int(p.radius))|eps=\(p.eps)|theta=\(p.thetaDegrees)|gap=\(Int(p.gap))|noise=\(p.noise)|seed=\(p.seed)|tail=\(p.tail)"
    do {
        let fit = try EllipseCalibration.fitBestAvailable(
            pattern: pattern, centerQX: p.centerQX + 1.3 + perturb, centerQY: p.centerQY - 0.9 - perturb,
            innerRadius: p.b - 20, outerRadius: p.a + 20)
        f += "|status=\(fit.model == .conic ? "conic" : "profile")|dR=\(g((fit.a + fit.b) / 2 / p.radius - 1))"
        f += "|dba=\(g(fit.b / fit.a - p.b / p.a))|cerr=\(g(hypot(fit.centerQX - p.centerQX, fit.centerQY - p.centerQY)))"
        f += "|resid=\(g(fit.normalizedResidual))|conicres=\(g(fit.conicResidual))"
        if let pr = fit.profile {
            f += "|I1=\(g(pr.ringIntensity))|sin=\(g(pr.innerSigma))|sout=\(g(pr.outerSigma))"
        } else {
            f += "|reason=\((fit.profileFallbackReason ?? "nil").replacingOccurrences(of: "|", with: "/"))"
        }
    } catch { f += "|status=THREW|err=\("\(error)".replacingOccurrences(of: "|", with: "/"))" }
    let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e6
    f += "|ms=\(g(ms))"
    print(f); fflush(stdout)
}

let args = CommandLine.arguments
if args.count >= 9, args[1] == "one" {
    run(Plant(size: Int(args[2])!, radius: Double(args[3])!, eps: Double(args[4])!, thetaDegrees: Double(args[5])!,
              gap: Double(args[6])!, noise: Double(args[7])!, seed: Int(args[8])!, tail: args.count >= 10 ? Double(args[9])! : 0))
    exit(0)
}
if args.count >= 10, args[1] == "grid" {
    func list(_ t: String) -> [Double] { t.split(separator: ",").map { Double($0)! } }
    let size = Int(args[2])!, k0 = Int(args[8])!, k1 = Int(args[9])!
    let part = args.count >= 12 ? Int(args[10])! : 0, parts = args.count >= 12 ? Int(args[11])! : 1
    var n = 0
    for radius in list(args[3]) { for eps in list(args[4]) { for theta in list(args[5]) { for noise in list(args[6]) {
        for tail in list(args[7]) { for seed in k0..<k1 {
            defer { n += 1 }
            if n % parts != part { continue }
            run(Plant(size: size, radius: radius, eps: eps, thetaDegrees: theta, gap: 0, noise: noise, seed: seed, tail: tail))
        } }
    } } } }
    exit(0)
}
guard args.count >= 4, let k0 = Int(args[1]), let k1 = Int(args[2]) else { print("usage: search <seed0> <seed1> <noises> [sizes]"); exit(64) }
let noises = args[3].split(separator: ",").map { Double($0)! }
let sizes = args.count >= 5 ? args[4].split(separator: ",").map { Int($0)! } : [128, 160, 192]
let radii = args.count >= 6 ? args[5].split(separator: ",").map { Double($0)! } : [40.0, 50.0, 60.0, 70.0]
let thetas: [Double] = [0, 20, 45, 67.5, 90, 112.5, 135, 160]
for noise in noises {
    for size in sizes {
        for radius in radii {
            for eps in [0.0, 0.01, 0.03] {
                let b = 2 * radius / (2 + eps), a = b * (1 + eps)
                // The annulus (outer = a + 20) on the grid (the centre offset, up to 4.2 px with the guess, may clip its far edge).
                guard a + 20 <= Double(size) / 2 else { continue }
                for theta in (eps == 0 ? [0.0] : thetas) {
                    for gap in [0.0, 60.0] {
                        for seed in k0..<k1 {
                            run(Plant(size: size, radius: radius, eps: eps, thetaDegrees: theta, gap: gap, noise: noise, seed: seed))
                        }
                    }
                }
            }
        }
    }
}
