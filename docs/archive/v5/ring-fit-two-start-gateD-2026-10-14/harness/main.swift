// Ring-fit two-start Gate D, step (i) (2026-10-14): the ellipse Fit on a real pattern, per annulus written before any fit.
// usage: fit <pattern.f32> <rows> <cols> <centreRow> <centreCol> <annuli.txt>
//   pattern: float32 little-endian, row-major (rows = qx, cols = qy, as DiffractionPattern(qy: cols, qx: rows));
//   centreRow = centerQX, centreCol = centerQY (the app's aperture centre convention, AppState+Calibration.swift:179-180);
//   annuli.txt: one "tag inner outer" per line ('#' comments).
// Per annulus: the conic seed (fit1D) and the default-argument fitBestAvailable, the call behind the Fit button.
import Foundation

func g(_ v: Double) -> String { String(format: "%.9g", v) }
let args = CommandLine.arguments
guard args.count == 7, let rows = Int(args[2]), let cols = Int(args[3]),
      let cRow = Double(args[4]), let cCol = Double(args[5]) else {
    print("usage: fit <pattern.f32> <rows> <cols> <centreRow> <centreCol> <annuli.txt>"); exit(64)
}
let data = try Data(contentsOf: URL(fileURLWithPath: args[1]))
let pixels = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
precondition(pixels.count == rows * cols, "expected \(rows) x \(cols) float32, got \(pixels.count)")
let pattern = DiffractionPattern(qy: cols, qx: rows, pixels: pixels)
let annuli: [(String, Double, Double)] = try String(contentsOfFile: args[6], encoding: .utf8)
    .split(separator: "\n").compactMap { line in
        let t = line.split(separator: " ")
        guard t.count >= 3, !t[0].hasPrefix("#"), let i = Double(t[1]), let o = Double(t[2]) else { return nil }
        return (String(t[0]), i, o)
    }
print("FIT input=\(args[1]) rows=\(rows) cols=\(cols) centreRow=\(g(cRow)) centreCol=\(g(cCol)) annuli=\(annuli.count) allFinite=\(pixels.allSatisfy { $0.isFinite })")
for (tag, inner, outer) in annuli {
    var line = "ROW|tag=\(tag)|inner=\(g(inner))|outer=\(g(outer))"
    do {
        // The seed fitBestAvailable refines (EllipseCalibration.swift:417-423: residual cap max(0.4, 0.2)).
        let s = try EllipseCalibration.fit1D(pattern: pattern, centerQX: cRow, centerQY: cCol, innerRadius: inner, outerRadius: outer, maximumResidual: 0.4)
        line += "|seed_a=\(g(s.a))|seed_b=\(g(s.b))|seed_theta=\(g(s.theta))|seed_cx=\(g(s.centerQX))|seed_cy=\(g(s.centerQY))|seed_res=\(g(s.normalizedResidual))"
    } catch { line += "|seed=THREW:\("\(error)".replacingOccurrences(of: "|", with: "/"))" }
    do {
        let f = try EllipseCalibration.fitBestAvailable(pattern: pattern, centerQX: cRow, centerQY: cCol, innerRadius: inner, outerRadius: outer)
        line += "|status=\(f.model == .conic ? "conic" : "profile")|a=\(g(f.a))|b=\(g(f.b))|theta=\(g(f.theta))|cx=\(g(f.centerQX))|cy=\(g(f.centerQY))"
        line += "|resid=\(g(f.normalizedResidual))|conicres=\(g(f.conicResidual))|bins=\(f.occupiedAngularBins)|n=\(f.sampleCount)|sparse=\(f.sparseCoverage)"
        if let p = f.profile {
            line += "|I0=\(g(p.centralIntensity))|I1=\(g(p.ringIntensity))|s0=\(g(p.centralSigma))|sin=\(g(p.innerSigma))|sout=\(g(p.outerSigma))|bg=\(g(p.background))"
        } else { line += "|reason=\((f.profileFallbackReason ?? "nil").replacingOccurrences(of: "|", with: "/"))" }
    } catch { line += "|status=THREW|err=\("\(error)".replacingOccurrences(of: "|", with: "/"))" }
    print(line); fflush(stdout)
}
