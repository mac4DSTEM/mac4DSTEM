//  Lane C b1 Gate D (2026-10-02), diagnostic only: the app's RotationCalibration and its parallax low-order fit on ONE cube.
//  gated <cube.h5> <qPixel 1/A> <rPixel A> <kV>
import Foundation

func log(_ s: String) { FileHandle.standardOutput.write(Data((s + "\n").utf8)) }

@main
enum Gated {
    static func main() async {
        do { try await run() } catch { log("FAIL: \(error)"); exit(1) }
    }
    static func run() async throws {
        let a = Array(CommandLine.arguments.dropFirst())
        let path = a[0]; let qPixel = Double(a[1])!; let rPixel = Double(a[2])!; let kv = Double(a[3])!
        let reader = try H5Reader(path: path)
        let d = try await reader.discoverPrimaryDataset()
        let view = LoadView(fullExtentOf: d)
        log("dataset ry \(d.ry) rx \(d.rx) qy \(d.qy) qx \(d.qx)")
        let det = d.qy * d.qx
        var com = [Float](repeating: 0, count: 2 * d.ry * d.rx)
        var mean = [Double](repeating: 0, count: det)
        for y in 0..<d.ry {
            let tile = try await reader.readScanTile(view, yRange: y..<(y + 1))
            for x in 0..<d.rx {
                let base = x * det
                var s = 0.0, cx = 0.0, cy = 0.0
                for r in 0..<d.qy { for c in 0..<d.qx {
                    let v = Double(tile.pixels[base + r * d.qx + c]); s += v; cx += v * Double(c); cy += v * Double(r)
                    mean[r * d.qx + c] += v
                } }
                let i = y * d.rx + x
                com[2 * i] = Float(cx / s); com[2 * i + 1] = Float(cy / s)
            }
        }
        // Descan-free synthetic cube: the normalised field is the measured CoM less its mean (py4DSTEM's "plane" fit reduces to this).
        let n = d.ry * d.rx
        var mx: Float = 0, my: Float = 0
        for i in 0..<n { mx += com[2 * i]; my += com[2 * i + 1] }
        mx /= Float(n); my /= Float(n)
        for i in 0..<n { com[2 * i] -= mx; com[2 * i + 1] -= my }
        guard let rot = RotationCalibration.solve(com: com, width: d.rx, height: d.ry) else { log("FAIL: rotation solve nil"); exit(1) }
        let rotDiv = RotationCalibration.solve(com: com, width: d.rx, height: d.ry, maximizeDivergence: true)
        log(String(format: "APP RotationCalibration curl: rotation %.3f deg (app internal) transpose %@ carriesRotation %@ -> displayText (py4DSTEM sign) %@",
                   Double(rot.rotationRad) * 180 / .pi, rot.transpose ? "true" : "false", rot.carriesRotation ? "true" : "false",
                   RQRotationConvention.displayText(fromApp: rot.rotationRad, decimals: 3)))
        if let rotDiv { log(String(format: "APP RotationCalibration divergence: rotation %.3f deg transpose %@",
                                   Double(rotDiv.rotationRad) * 180 / .pi, rotDiv.transpose ? "true" : "false")) }

        var sum = 0.0, ox = 0.0, oy = 0.0
        for r in 0..<d.qy { for c in 0..<d.qx { let v = mean[r * d.qx + c]; sum += v; ox += v * Double(c); oy += v * Double(r) } }
        var calibration = Calibration(originProvenance: .manual)
        calibration.qPixelSize = qPixel; calibration.qPixelUnits = "Å⁻¹"
        calibration.rPixelSize = rPixel; calibration.rPixelUnits = "Å"
        calibration.rotationRad = rot.rotationRad; calibration.transposeQR = rot.transpose
        let physical = try ParallaxPhysicalCalibration.resolve(
            calibration: calibration, apertureCenterX: Float(ox / sum), apertureCenterY: Float(oy / sum), acceleratingVoltageKV: kv)
        var po = ParallaxPreprocessOptions(); po.thresholdIntensity = 0.5; po.edgeBlend = 8   // as make_cube.py's py4DSTEM run
        let pre = try await ParallaxPreprocessor.run(source: reader, view: view, calibration: physical, options: po)
        let schedule = ParallaxAligner.defaultBinSchedule(detectorIndices: pre.detectorIndices)
        var prior: ParallaxAlignmentResult? = nil
        var ao = ParallaxAlignmentOptions(); ao.upsampleFactor = 8
        while (prior?.completedBins.count ?? 0) < schedule.count {
            prior = try ParallaxAligner.alignNextLevel(preprocessing: pre, previous: prior, options: ao)
        }
        let fit = try ParallaxAberrationFitter.fitLowOrder(preprocessing: pre, alignment: prior!)
        log(String(format: "APP parallax fitLowOrder: rotation %.3f deg C1 %.2f C12a %.2f C12b %.2f (BF px %d, bins %@)",
                   fit.rotationRad * 180 / .pi, fit.c1Angstrom, fit.c12aAngstrom, fit.c12bAngstrom,
                   pre.brightFieldPixelCount, "\(schedule)"))
    }
}
