import Foundation

// R lane scratch tool: run the app's single-slice engine on a synthetic fixture (synth.py make) and dump the object at checkpoints.
//   dump <fixture.json> <out.json> --method gd|dm [--iterations 32] [--checkpoints 1,2,4,8,16,32] [--clamp 0|1] [--alpha 1]
//        [--probe fixture|app|app-neg]   (app = PtychographyProbe.build at the fixture's defocus, scaled like `prepare`; app-neg = -defocus)
struct Fixture: Decodable {
    let defocusAngstrom: Double, energyEV: Double, semiangleMrad: Double, rolloffMrad: Double
    let qSamplingInvAngstrom: Double, objectSamplingAngstrom: Double, meanIntensity: Double
    let scanShape: [Int], probeShape: [Int], objectShape: [Int]
    let positions: [Float], amplitudes: [Float], probeReal: [Float], probeImag: [Float]
}

func option(_ name: String) -> String? {
    guard let i = CommandLine.arguments.firstIndex(of: name), i + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[i + 1]
}

@main
struct Dump {
    static func main() throws {
        let args = CommandLine.arguments
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
        let positions = stride(from: 0, to: fixture.positions.count, by: 2).map {
            PtychographyPosition(row: fixture.positions[$0], column: fixture.positions[$0 + 1])
        }
        let det = fixture.probeShape[0], canvas = fixture.objectShape[0]
        let probeMode = option("--probe") ?? "fixture"
        var probeReal = fixture.probeReal, probeImag = fixture.probeImag
        if probeMode != "fixture" {
            guard let fft = FFT2D(nx: det, ny: det) else { fatalError("fft") }
            let wavelength = ParallaxPreprocessor.electronWavelengthAngstrom(energyEV: fixture.energyEV)
            let sign: Double = probeMode == "app-neg" ? -1 : 1
            let aberrations = PtychographyProbeAberrations(defocusAngstrom: sign * fixture.defocusAngstrom)
            let built = try PtychographyProbe.build(
                detectorHeight: det, detectorWidth: det,
                rowSamplingAngstrom: fixture.objectSamplingAngstrom, columnSamplingAngstrom: fixture.objectSamplingAngstrom,
                wavelengthAngstrom: wavelength, cutoffRad: fixture.semiangleMrad / 1000, rolloffRad: fixture.rolloffMrad / 1000,
                aberrations: aberrations, fft: fft)
            probeReal = built.real; probeImag = built.imaginary
            // scale like PtychographyPreparer.prepare: mean intensity from the amplitudes, probe intensity from its spectrum
            var total = 0.0
            for a in fixture.amplitudes { total += Double(a * a) }
            let mean = total / Double(positions.count)
            var sr = probeReal, si = probeImag
            fft.transform(re: &sr, im: &si, forward: true)
            var pi = 0.0
            for k in 0..<sr.count { pi += Double(sr[k] * sr[k] + si[k] * si[k]) }
            let s = Float(sqrt(mean / pi))
            for k in 0..<probeReal.count { probeReal[k] *= s; probeImag[k] *= s }
        }
        let input = SingleslicePtychographyInput(
            scanHeight: fixture.scanShape[0], scanWidth: fixture.scanShape[1], detectorHeight: det, detectorWidth: det,
            amplitudes: fixture.amplitudes, positions: positions,
            objectSamplingRowAngstrom: fixture.objectSamplingAngstrom, objectSamplingColumnAngstrom: fixture.objectSamplingAngstrom,
            initialObject: PtychographyComplexArray(width: canvas, height: canvas,
                                                    real: [Float](repeating: 1, count: canvas * canvas), imaginary: [Float](repeating: 0, count: canvas * canvas)),
            initialProbe: PtychographyComplexArray(width: det, height: det, real: probeReal, imaginary: probeImag))
        var options = SingleslicePtychographyOptions()
        options.method = (option("--method") ?? "gd") == "dm" ? .differenceMapAlternatingProjections : .gradientDescent
        options.iterations = Int(option("--iterations") ?? "32")!
        options.projectionParameter = Float(option("--alpha") ?? "1")!
        options.stepSize = Float(option("--step") ?? "0.5")!
        options.normalizationMinimum = Float(option("--norm-min") ?? "1")!
        options.constrainObjectAmplitude = (option("--clamp") ?? "1") == "1"
        options.fixProbe = (option("--fix-probe") ?? "0") == "1"
        let checkpoints = (option("--checkpoints") ?? "1,2,4,8,16,32").split(separator: ",").map { Int($0)! }
        var out: [String: Any] = ["method": options.method.rawValue, "constrainObjectAmplitude": options.constrainObjectAmplitude,
                                  "probe": probeMode, "alpha": Double(options.projectionParameter), "iterations": options.iterations]
        var cps = [[String: Any]]()
        let start = Date()
        for cp in checkpoints where cp <= options.iterations {
            var o = options; o.iterations = cp
            let r = try SingleslicePtychography.reconstruct(input: input, options: o)
            cps.append(["iterations": cp, "real": r.object.real.map(Double.init), "imag": r.object.imaginary.map(Double.init),
                        "errors": r.errorHistory.map(Double.init)])
            if cp == options.iterations { out["errors"] = r.errorHistory.map(Double.init) }
        }
        if out["errors"] == nil {
            let r = try SingleslicePtychography.reconstruct(input: input, options: options)
            out["errors"] = r.errorHistory.map(Double.init)
        }
        out["seconds"] = Date().timeIntervalSince(start)
        out["checkpoints"] = cps
        try JSONSerialization.data(withJSONObject: out).write(to: URL(fileURLWithPath: args[2]))
        print("dump: \(options.method.rawValue) clamp \(options.constrainObjectAmplitude) probe \(probeMode) \(String(format: "%.1f", out["seconds"] as! Double)) s; errors \((out["errors"] as! [Double]).map { String(format: "%.6g", $0) })")
    }
}
