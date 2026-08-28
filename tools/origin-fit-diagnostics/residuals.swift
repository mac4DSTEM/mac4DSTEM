import Foundation

// App-layer value type VirtualDetector's aperture overload needs, mirrored
// from tools/training-dataset-campaign/main.swift so the production source
// compiles standalone.
struct Aperture {
    var centerX: Float
    var centerY: Float
    var inner: Float
    var outer: Float
}

func pct(_ sorted: [Float], _ p: Double) -> Float {
    guard !sorted.isEmpty else { return .nan }
    let i = min(sorted.count - 1, max(0, Int((p / 100.0) * Double(sorted.count - 1).rounded())))
    return sorted[i]
}
func medianOf(_ v: [Float]) -> Float {
    let s = v.sorted(); let m = s.count / 2
    return s.count.isMultiple(of: 2) ? (s[m-1] + s[m]) / 2 : s[m]
}
func rms(_ mx: [Float], _ my: [Float], _ fx: [Float], _ fy: [Float]) -> Float {
    var s: Float = 0
    for i in mx.indices { let dx = mx[i]-fx[i], dy = my[i]-fy[i]; s += dx*dx + dy*dy }
    return (s / Float(mx.count)).squareRoot()
}

/// Ordinary least-squares plane a + b*x + c*y over the given scan indices.
func planeFit(_ v: [Float], _ idx: [Int], width: Int) -> (Float, Float, Float) {
    var sxx = 0.0, sxy = 0.0, syy = 0.0, sx = 0.0, sy = 0.0, s1 = 0.0
    var sv = 0.0, svx = 0.0, svy = 0.0
    for i in idx {
        let x = Double(i % width), y = Double(i / width), val = Double(v[i])
        s1 += 1; sx += x; sy += y; sxx += x*x; sxy += x*y; syy += y*y
        sv += val; svx += val*x; svy += val*y
    }
    // Solve the 3x3 normal equations by Cramer's rule.
    let m = [[s1, sx, sy], [sx, sxx, sxy], [sy, sxy, syy]]
    let r = [sv, svx, svy]
    func det3(_ a: [[Double]]) -> Double {
        a[0][0]*(a[1][1]*a[2][2]-a[1][2]*a[2][1])
      - a[0][1]*(a[1][0]*a[2][2]-a[1][2]*a[2][0])
      + a[0][2]*(a[1][0]*a[2][1]-a[1][1]*a[2][0])
    }
    let d = det3(m)
    guard abs(d) > 1e-9 else { return (Float(sv/max(s1,1)), 0, 0) }
    func replaceColumn(_ a: [[Double]], _ c: Int, _ col: [Double]) -> [[Double]] {
        var b = a; for i in 0..<3 { b[i][c] = col[i] }; return b
    }
    return (Float(det3(replaceColumn(m,0,r))/d),
            Float(det3(replaceColumn(m,1,r))/d),
            Float(det3(replaceColumn(m,2,r))/d))
}

@main
struct Probe {
    static func main() async throws {
        for path in Array(CommandLine.arguments.dropFirst()) {
            let name = URL(fileURLWithPath: path).lastPathComponent
            // A session sidecar sitting beside a training dataset is the
            // ordinary case, not an error — H5Reader refuses it by design
            // (backlog #43). Skip and carry on rather than killing the run.
            let reader: H5Reader
            let d: DatasetDescriptor
            do {
                reader = try H5Reader(path: path)
                d = try await reader.discoverPrimaryDataset()
            } catch {
                print("=== \(name): SKIPPED — \(error)")
                continue
            }
            let data = FourDArray(reader: reader, descriptor: d)
            guard let fit = try await OriginCalibration.tiledRun(
                data: data, descriptor: d, fitFunction: .plane
            ) else { print("\(name): no origin fit"); continue }
            guard let mx = fit.origin.measuredX, let my = fit.origin.measuredY else {
                print("\(name): no measured maps"); continue
            }
            let fx = fit.origin.fittedX, fy = fit.origin.fittedY
            let r = fit.probeRadius
            var resid = [Float](); resid.reserveCapacity(mx.count)
            for i in mx.indices { resid.append(((mx[i]-fx[i])*(mx[i]-fx[i]) + (my[i]-fy[i])*(my[i]-fy[i])).squareRoot()) }
            let sorted = resid.sorted()
            let rmsPlane = rms(mx, my, fx, fy)
            // robust centre: median of measured, and residual about it
            let cx = medianOf(mx), cy = medianOf(my)
            var robustResid = [Float]()
            for i in mx.indices { robustResid.append(((mx[i]-cx)*(mx[i]-cx) + (my[i]-cy)*(my[i]-cy)).squareRoot()) }
            let robSorted = robustResid.sorted()
            let medRob = medianOf(robustResid)
            let madRob = medianOf(robustResid.map { abs($0 - medRob) })
            // inlier set: within 3 * (1.4826*MAD) of the robust centre
            let sigmaRob = 1.4826 * madRob
            let cutoff = medRob + 3 * sigmaRob
            var inlier = [Int]()
            for i in robustResid.indices where robustResid[i] <= cutoff { inlier.append(i) }
            let inMx = inlier.map { mx[$0] }, inMy = inlier.map { my[$0] }
            let inFx = inlier.map { fx[$0] }, inFy = inlier.map { fy[$0] }
            let rmsInlierVsPlane = rms(inMx, inMy, inFx, inFy)
            // refit a plane on inliers only? approximate with constant on inliers
            let inCx = inMx.reduce(0,+)/Float(inMx.count), inCy = inMy.reduce(0,+)/Float(inMy.count)
            let rmsInlierConst = rms(inMx, inMy, [Float](repeating: inCx, count: inMx.count),
                                     [Float](repeating: inCy, count: inMy.count))
            let overCount = resid.filter { $0 > r }.count
            let over2Count = resid.filter { $0 > 2*r }.count
            print("=== \(name)  scan \(d.ry)x\(d.rx)  det \(d.qy)x\(d.qx)  probeR \(String(format:"%.3f", r))")
            print("  plane RMS            \(String(format:"%.4f", rmsPlane))   gate = RMS <= probeR -> \(rmsPlane <= r ? "PASS" : "BLOCK")")
            print("  residual percentiles p10 \(String(format:"%.4f", pct(sorted,10)))  p50 \(String(format:"%.4f", pct(sorted,50)))  p75 \(String(format:"%.4f", pct(sorted,75)))  p90 \(String(format:"%.4f", pct(sorted,90)))  p95 \(String(format:"%.4f", pct(sorted,95)))  p99 \(String(format:"%.4f", pct(sorted,99)))  max \(String(format:"%.4f", sorted.last ?? .nan))")
            print("  median/RMS ratio     \(String(format:"%.4f", pct(sorted,50)/rmsPlane))   (Rayleigh scatter ~0.83; heavy-tail outliers << 0.83)")
            print("  positions > probeR   \(overCount)/\(resid.count) = \(String(format:"%.1f%%", 100*Double(overCount)/Double(resid.count)))   > 2*probeR: \(over2Count) = \(String(format:"%.1f%%", 100*Double(over2Count)/Double(resid.count)))")
            print("  robust centre        (\(String(format:"%.3f", cx)), \(String(format:"%.3f", cy)))  median dist \(String(format:"%.4f", medRob))  MAD \(String(format:"%.4f", madRob))  p90 \(String(format:"%.4f", pct(robSorted,90)))")
            print("  inliers (<= med+3s)  \(inlier.count)/\(mx.count) = \(String(format:"%.1f%%", 100*Double(inlier.count)/Double(mx.count)))")
            print("  inlier RMS vs plane  \(String(format:"%.4f", rmsInlierVsPlane))  -> gate would \(rmsInlierVsPlane <= r ? "PASS" : "BLOCK")")
            print("  inlier RMS vs const  \(String(format:"%.4f", rmsInlierConst))  -> gate would \(rmsInlierConst <= r ? "PASS" : "BLOCK")")
            // --- trimmed iterative plane refit -------------------------------
            var keep = Array(mx.indices)
            var trimmedRMS = Float.nan
            var trimmedFx = fx, trimmedFy = fy
            for round in 1...3 {
                let (ax, bx2, cx2) = planeFit(mx, keep, width: d.rx)
                let (ay, by2, cy2) = planeFit(my, keep, width: d.rx)
                var pfx = [Float](repeating: 0, count: mx.count)
                var pfy = [Float](repeating: 0, count: my.count)
                for i in mx.indices {
                    let x = Float(i % d.rx), y = Float(i / d.rx)
                    pfx[i] = ax + bx2*x + cx2*y
                    pfy[i] = ay + by2*x + cy2*y
                }
                var rr = [Float]()
                for i in mx.indices { rr.append(((mx[i]-pfx[i])*(mx[i]-pfx[i]) + (my[i]-pfy[i])*(my[i]-pfy[i])).squareRoot()) }
                let med = medianOf(rr)
                let sig = 1.4826 * medianOf(rr.map { abs($0 - med) })
                let cut = med + 3*sig
                keep = rr.indices.filter { rr[$0] <= cut }
                let kx = keep.map { mx[$0] }, ky = keep.map { my[$0] }
                let kfx = keep.map { pfx[$0] }, kfy = keep.map { pfy[$0] }
                trimmedRMS = rms(kx, ky, kfx, kfy)
                // The SHIPPED gate (Calibration.originFitIsQuantitative) reads
                // OriginMaps.rmsResidual, which is over ALL scan positions.
                // RMS(kept) is over the subset trimming selected for having
                // small residuals, so comparing it to probeRadius would be
                // circular. Report both, and label which one the gate sees.
                let trimmedRMSAll = rms(mx, my, pfx, pfy)
                trimmedFx = pfx; trimmedFy = pfy
                print("  trim round \(round)      kept \(keep.count)/\(mx.count) = \(String(format:"%.1f%%", 100*Double(keep.count)/Double(mx.count)))  RMS(kept) \(String(format:"%.4f", trimmedRMS))  |  RMS(ALL, trimmed fit) \(String(format:"%.4f", trimmedRMSAll)) -> SHIPPED GATE would \(trimmedRMSAll <= r ? "PASS" : "BLOCK")")
            }
            var shift = [Float]()
            for i in mx.indices {
                shift.append(((fx[i]-trimmedFx[i])*(fx[i]-trimmedFx[i]) + (fy[i]-trimmedFy[i])*(fy[i]-trimmedFy[i])).squareRoot())
            }
            let shiftSorted = shift.sorted()
            print("  shipped vs trimmed   fitted-origin shift over the WHOLE map: p50 \(String(format:"%.3f", pct(shiftSorted,50))) px  p95 \(String(format:"%.3f", pct(shiftSorted,95))) px  max \(String(format:"%.3f", shiftSorted.last ?? .nan)) px")
            let midIndex = (d.ry/2) * d.rx + (d.rx/2)
            print("  centre shift         plane (\(String(format:"%.3f", fx[midIndex])), \(String(format:"%.3f", fy[midIndex]))) -> trimmed (\(String(format:"%.3f", trimmedFx[midIndex])), \(String(format:"%.3f", trimmedFy[midIndex])))  = \(String(format:"%.3f px", ((fx[midIndex]-trimmedFx[midIndex])*(fx[midIndex]-trimmedFx[midIndex]) + (fy[midIndex]-trimmedFy[midIndex])*(fy[midIndex]-trimmedFy[midIndex])).squareRoot()))")
            // histogram in units of probeR
            var bins = [Int](repeating: 0, count: 9)
            for v in resid {
                let b = min(8, Int(v / (0.5*r)))
                bins[b] += 1
            }
            let labels = ["0-0.5r","0.5-1r","1-1.5r","1.5-2r","2-2.5r","2.5-3r","3-3.5r","3.5-4r",">4r"]
            print("  histogram (units of probeR):")
            for (i,b) in bins.enumerated() where b > 0 {
                print("     \(labels[i].padding(toLength: 8, withPad: " ", startingAt: 0)) \(b)")
            }
        }
    }
}
