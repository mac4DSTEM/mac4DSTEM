// Lane P5 (ring-fit Gate D, step 2, 2026-10-14): the ellipse Fit on the Au_ref mean pattern, per registered annulus.
// usage: p5 <au_mean.f32>   (64 x 64 float32 little-endian, row-major; centreRow = centerQX, centreCol = centerQY)
// One line per call. The default-argument fitBestAvailable is the verdict; the acceptSparseCoverage run is information only.
import Foundation

func g(_ v: Double) -> String { String(format: "%.9g", v) }

guard CommandLine.arguments.count >= 2 else { print("usage: p5 <au_mean.f32>"); exit(64) }
let path = CommandLine.arguments[1]
let data = try Data(contentsOf: URL(fileURLWithPath: path))
let pixels = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
precondition(pixels.count == 64 * 64, "expected 64 x 64 float32, got \(pixels.count) values")
let pattern = DiffractionPattern(qy: 64, qx: 64, pixels: pixels)
let allFinite = pixels.allSatisfy { $0.isFinite }
print("P5 input=\(path) values=\(pixels.count) allFinite=\(allFinite) min=\(g(Double(pixels.min() ?? 0))) max=\(g(Double(pixels.max() ?? 0))) centreRow=28.47 centreCol=34.43")

let centreRow = 28.47, centreCol = 34.43
let annuli: [(tag: String, inner: Double, outer: Double)] = [
    ("A1:5-13", 5, 13), ("A2:13-21", 13, 21), ("A3:21-30", 21, 30), ("A4:30-38", 30, 38),
    ("W1:4-14", 4, 14), ("W2:12-22", 12, 22), ("W3:20-31", 20, 31), ("W4:29-39", 29, 39),
]

func describe(_ tag: String, _ result: Result<EllipseCalibrationFit, Error>) -> String {
    switch result {
    case .failure(let error):
        return "P5 \(tag) THREW \(error)"
    case .success(let fit):
        var line = "P5 \(tag) model=\(fit.model == .conic ? "conic" : "profile") a=\(g(fit.a)) b=\(g(fit.b)) theta=\(g(fit.theta)) centerQX=\(g(fit.centerQX)) centerQY=\(g(fit.centerQY)) normalizedResidual=\(g(fit.normalizedResidual)) conicResidual=\(g(fit.conicResidual)) occupiedAngularBins=\(fit.occupiedAngularBins) sampleCount=\(fit.sampleCount) sparseCoverage=\(fit.sparseCoverage)"
        if let p = fit.profile {
            line += " profile: I0=\(g(p.centralIntensity)) I1=\(g(p.ringIntensity)) centralSigma=\(g(p.centralSigma)) innerSigma=\(g(p.innerSigma)) outerSigma=\(g(p.outerSigma)) background=\(g(p.background))"
        } else {
            line += " fallbackReason=\(fit.profileFallbackReason ?? "nil")"
        }
        return line
    }
}

for (tag, inner, outer) in annuli {
    let seed = Result {
        try EllipseCalibration.fit1D(pattern: pattern, centerQX: centreRow, centerQY: centreCol,
                                     innerRadius: inner, outerRadius: outer, maximumResidual: 0.4)
    }
    print(describe("\(tag) fn=fit1D", seed))
    let best = Result {
        try EllipseCalibration.fitBestAvailable(pattern: pattern, centerQX: centreRow, centerQY: centreCol,
                                                innerRadius: inner, outerRadius: outer)
    }
    print(describe("\(tag) fn=fitBestAvailable", best))
    if case .failure(let error) = best, let fitError = error as? EllipseCalibration.FitError,
       case .insufficientAngularCoverage = fitError {
        let sparse = Result {
            try EllipseCalibration.fitBestAvailable(pattern: pattern, centerQX: centreRow, centerQY: centreCol,
                                                    innerRadius: inner, outerRadius: outer, acceptSparseCoverage: true)
        }
        print(describe("\(tag) fn=fitBestAvailable INFO-ONLY acceptSparseCoverage=true", sparse))
    }
    fflush(stdout)
}
