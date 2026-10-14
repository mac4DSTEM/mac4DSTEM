// Ring-fit two-start Gate D, step (i), prep: the Bragg-vector map the app's Fit sees in Disks mode, built with the app's own code.
// Mirrors AppState+Calibration.swift:144-162: calibration.origin = the sidecar's fitted maps (appOriginMaps: fittedX = qy0, fittedY = qx0),
// ellipse nil, referenceOrigin = calibration.meanOrigin (Calibration.swift:943, a sequential Float sum), then
// BraggVectors.calibrated(with:referenceOrigin:) (DiskDetection.swift:711) and .map(qy:qx:) (DiskDetection.swift:746).
// usage: bvm <peaks.bin> <fittedX.f32> <fittedY.f32> <scanW> <scanH> <detW=qx> <detH=qy> <out.f32>
// peaks.bin: Int32 counts[scanW*scanH] (row-major [ry][rx]), then Float32 x[N], y[N], intensity[N] (x = column, y = row).
import Foundation

func g(_ v: Float) -> String { String(format: "%.9g", v) }
let a = CommandLine.arguments
guard a.count == 9, let sw = Int(a[4]), let sh = Int(a[5]), let qx = Int(a[6]), let qy = Int(a[7]) else {
    print("usage: bvm <peaks.bin> <fittedX.f32> <fittedY.f32> <scanW> <scanH> <detW> <detH> <out.f32>"); exit(64)
}
func floats(_ path: String) -> [Float] {
    let d = try! Data(contentsOf: URL(fileURLWithPath: path))
    return d.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
}
let raw = try! Data(contentsOf: URL(fileURLWithPath: a[1]))
let n = sw * sh
var counts = [Int32](repeating: 0, count: n)
_ = counts.withUnsafeMutableBytes { raw.copyBytes(to: $0, from: 0..<(4 * n)) }
let total = counts.reduce(0) { $0 + Int($1) }
precondition(raw.count == 4 * n + 12 * total, "peaks.bin size mismatch")
let body = raw.subdata(in: (4 * n)..<raw.count)
let all = body.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
var peaks = [[BraggPeak]](repeating: [], count: n)
var k = 0
for s in 0..<n {
    let c = Int(counts[s]); var list = [BraggPeak](); list.reserveCapacity(c)
    for i in 0..<c { list.append(BraggPeak(x: all[k + i], y: all[total + k + i], intensity: all[2 * total + k + i])) }
    peaks[s] = list; k += c
}
let fx = floats(a[2]), fy = floats(a[3])
precondition(fx.count == n && fy.count == n)
var cal = Calibration()
cal.origin = OriginMaps(width: sw, height: sh, measuredX: nil, measuredY: nil, fittedX: fx, fittedY: fy)
cal.ellipseA = nil; cal.ellipseB = nil; cal.ellipseTheta = nil
let mean = cal.meanOrigin
print("meanOrigin x(col)=\(mean.map { g($0.x) } ?? "nil") y(row)=\(mean.map { g($0.y) } ?? "nil")")
let origin = mean ?? (x: Float(qx) / 2, y: Float(qy) / 2)
let vectors = BraggVectors(scanWidth: sw, scanHeight: sh, peaks: peaks)
let bvm = vectors.calibrated(with: cal, referenceOrigin: origin).map(qy: qy, qx: qx)
let px = bvm.pixels
precondition(px.count == qx * qy)
px.withUnsafeBufferPointer { try! Data(buffer: $0).write(to: URL(fileURLWithPath: a[8])) }
let sum = px.reduce(Float(0), +)
let rawSum = peaks.reduce(Float(0)) { $0 + $1.reduce(Float(0)) { $0 + $1.intensity } }
let c = vectors.calibrated(with: cal, referenceOrigin: origin)
var outside = 0
for list in c.peaks { for p in list { let x0 = Int(p.x.rounded(.down)), y0 = Int(p.y.rounded(.down)); if x0 < 0 || x0 + 1 >= qx || y0 < 0 || y0 + 1 >= qy { outside += 1 } } }
print("BVM peaks=\(total) rawIntensitySum=\(g(rawSum)) mapSum=\(g(sum)) peaksTouchingEdgeOrOutside=\(outside) allFinite=\(px.allSatisfy { $0.isFinite }) max=\(g(px.max() ?? 0))")
