import Foundation
import Metal
import Accelerate
import Darwin

// S14 probe: block-sum seed (V0, shipped) vs box-argmax seeds (V1 disk-matched, V2 variance-matched)
// vs py4DSTEM's Gaussian-argmax seed (G), all through the shipped refine step, then the SHIPPED
// fitOriginTrimmed. Scratch code; nothing here is in the tree. Args: label|path[|datasetPath] or fixture|demo

// MARK: footprint watchdog (kill > 2500 MB phys_footprint)
func footprintMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
}
nonisolated(unsafe) var peakFootprintMB: Double = 0
func startWatchdog() {
    let t = Thread {
        while true {
            let f = footprintMB()
            if f > peakFootprintMB { peakFootprintMB = f }
            if f > 2500 { print("WATCHDOG: phys_footprint \(f) MB > 2500 — exiting"); fflush(stdout); exit(99) }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }
    t.start()
}

struct OriginParamsX { var ry: UInt32; var rx: UInt32; var qy: UInt32; var qx: UInt32; var r: Float; var rscale: Float; var hw: UInt32 }

func pctl(_ s: [Float], _ p: Double) -> Float {
    guard !s.isEmpty else { return .nan }
    return s[min(s.count - 1, Int((p / 100) * Double(s.count - 1)))]
}
func median(_ v: [Float]) -> Float { let s = v.sorted(); return pctl(s, 50) }

// MARK: Gaussian argmax (scipy gaussian_filter(dp, sigma, mode="nearest", truncate=4) twin)
func gaussKernel(sigma: Float) -> [Float] {
    let R = Int(4.0 * Double(sigma) + 0.5)
    var w = (-R...R).map { exp(-0.5 * Double($0 * $0) / Double(sigma * sigma)) }
    let s = w.reduce(0, +); w = w.map { $0 / s }
    return w.map { Float($0) }
}
func conv1(_ src: UnsafePointer<Float>, rows: Int, len: Int, kernel k: [Float], R: Int,
           dst: UnsafeMutablePointer<Float>, pad: UnsafeMutablePointer<Float>) {
    for r in 0..<rows {
        let row = src + r * len
        for i in 0..<R { pad[i] = row[0] }
        for i in 0..<len { pad[R + i] = row[i] }
        for i in 0..<R { pad[R + len + i] = row[len - 1] }
        vDSP_conv(pad, 1, k, 1, dst + r * len, 1, vDSP_Length(len), vDSP_Length(k.count))
    }
}
func gaussianArgmax(_ pat: UnsafePointer<Float>, qy: Int, qx: Int, kernel k: [Float]) -> (Int, Int) {
    let R = k.count / 2
    var a = [Float](repeating: 0, count: qy * qx)
    var b = [Float](repeating: 0, count: qy * qx)
    var pad = [Float](repeating: 0, count: max(qx, qy) + 2 * R)
    a.withUnsafeMutableBufferPointer { ap in b.withUnsafeMutableBufferPointer { bp in pad.withUnsafeMutableBufferPointer { pp in
        conv1(pat, rows: qy, len: qx, kernel: k, R: R, dst: ap.baseAddress!, pad: pp.baseAddress!)
        for y in 0..<qy { for x in 0..<qx { bp[x * qy + y] = ap[y * qx + x] } }
        conv1(UnsafePointer(bp.baseAddress!), rows: qx, len: qy, kernel: k, R: R, dst: ap.baseAddress!, pad: pp.baseAddress!)
    } } }
    // a is [x][y]
    var best = -Float.greatestFiniteMagnitude, bx = 0, by = 0
    for y in 0..<qy { for x in 0..<qx { let v = a[x * qy + y]; if v > best { best = v; bx = x; by = y } } }
    return (bx, by)
}

// MARK: dispatch
func dispatch(_ pso: MTLComputePipelineState, ry: Int, rx: Int, _ set: (MTLComputeCommandEncoder) -> Void) {
    let cb = MetalEngine.shared.queue.makeCommandBuffer()!
    let enc = cb.makeComputeCommandEncoder()!
    enc.setComputePipelineState(pso)
    set(enc)
    let w = min(pso.threadExecutionWidth, rx)
    let h = max(1, min(pso.maxTotalThreadsPerThreadgroup / w, ry))
    enc.dispatchThreads(MTLSize(width: rx, height: ry, depth: 1), threadsPerThreadgroup: MTLSize(width: w, height: h, depth: 1))
    enc.endEncoding(); cb.commit(); cb.waitUntilCompleted()
    if cb.status != .completed { print("FATAL: GPU dispatch failed \(String(describing: cb.error))"); exit(98) }
}
func timeMedian(_ n: Int, _ f: () -> Void) -> Double {
    for _ in 0..<3 { f() }
    var s: [Double] = []
    for _ in 0..<n {
        let t0 = DispatchTime.now().uptimeNanoseconds; f()
        s.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)
    }
    s.sort(); return s[s.count / 2]
}

func dump(_ a: [Float], _ name: String) {
    let url = URL(fileURLWithPath: name)
    a.withUnsafeBufferPointer { try? Data(buffer: $0).write(to: url) }
}

@main
struct S14 {
    static func main() async throws {
        startWatchdog()
        let outDir = ProcessInfo.processInfo.environment["S14_OUT"] ?? "."
        let device = MetalEngine.shared.device
        let lib = try device.makeLibrary(URL: URL(fileURLWithPath: "s14.metallib"))
        func pso(_ n: String) -> MTLComputePipelineState { try! device.makeComputePipelineState(function: lib.makeFunction(name: n)!) }
        let psoV0seed = pso("measureOrigin_v0seed"), psoBox = pso("measureOrigin_box"),
            psoBoxSeed = pso("measureOrigin_boxseed"), psoSeeded = pso("measureOrigin_seeded"), psoPy = pso("measureOrigin_pyseeded"),
            psoBoxN = pso("measureOrigin_boxn"), psoBoxNSeed = pso("measureOrigin_boxnseed"), psoWide = pso("measureOrigin_wide")
        guard let psoShipped = MetalEngine.shared.measureOriginPSO else { print("no shipped PSO"); exit(97) }

        for arg in CommandLine.arguments.dropFirst() {
            let parts = arg.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            let label = parts[0]
            let reader: any FourDDataSource
            let d: DatasetDescriptor
            do {
                if parts[1] == "fixture" {
                    let src = DemoFourDDataSource(includesCalibration: false)
                    reader = src; d = try await src.discoverPrimaryDataset()
                } else {
                    let h = try H5Reader(path: parts[1])
                    reader = h
                    d = parts.count > 2 && !parts[2].isEmpty ? try await h.describe(path: parts[2])
                                                              : try await h.discoverPrimaryDataset()
                }
            } catch { print("=== \(label): SKIPPED — \(error)"); continue }
            precondition(d.qx <= 512, "MAXQX")
            print("=== \(label)  scan \(d.ry)x\(d.rx)  det \(d.qy)x\(d.qx)  path \(d.datasetPath)")
            let t0 = Date()
            let data = FourDArray(reader: reader, descriptor: d)
            let statistics = try await VirtualDetector.tiledDPStatistics(data: data, descriptor: d)
            guard let probe = OriginCalibration.probeSize(dp: statistics.meanDP, qy: d.qy, qx: d.qx) else {
                print("   probeNotMeasurable"); continue
            }
            let r = probe.r
            let hw1 = max(1, Int(r.rounded())), hw2 = max(1, Int((3.0.squareRoot() * Double(r)).rounded()))
            let bin = max(1, Int(r.rounded()))
            print(String(format: "   r %.4f  bin %d  V1 half-width %d (side %d)  V2 half-width %d (side %d)  stats pass %.1fs",
                         r, bin, hw1, 2 * hw1 + 1, hw2, 2 * hw2 + 1, Date().timeIntervalSince(t0)))
            let gk = gaussKernel(sigma: r)
            let n = d.ry * d.rx
            var seeds = [[Float]](repeating: [Float](repeating: 0, count: 2 * n), count: 5)   // V0 V1 V2 G V1n
            var meas = [[Float]](repeating: [Float](repeating: 0, count: 2 * n), count: 7)    // V0 V1 V2 G PY V1n WIDE
            let rowsPerTile = await data.scanTileRows()
            let ranges: [Range<Int>] = stride(from: 0, to: d.ry, by: rowsPerTile).map { $0..<min(d.ry, $0 + rowsPerTile) }
            var source = TileGPUSource(data: data, descriptor: d, cube: await data.resident(for: d))
            var gCPUSeconds = 0.0
            var timing: [String: Double] = [:]
            var tileN = 0
            for (ti, range) in ranges.enumerated() {
                let bound = try await source.binding(for: range, prefetching: ti + 1 < ranges.count ? ranges[ti + 1] : nil,
                                                     label: "s14 tile")
                let m = range.count * d.rx
                func obuf() -> MTLBuffer { device.makeBuffer(length: m * 2 * 4, options: .storageModeShared)! }
                let pX0 = OriginParams(ry: UInt32(range.count), rx: UInt32(d.rx), qy: UInt32(d.qy), qx: UInt32(d.qx), r: r, rscale: 1.2)
                func px(_ hw: Int) -> OriginParamsX {
                    OriginParamsX(ry: UInt32(range.count), rx: UInt32(d.rx), qy: UInt32(d.qy), qx: UInt32(d.qx), r: r, rscale: 1.2, hw: UInt32(hw))
                }
                let base = range.lowerBound * d.rx * 2
                func store(_ k: Int, _ b: MTLBuffer, _ into: inout [[Float]]) {
                    let p = b.contents().bindMemory(to: Float.self, capacity: m * 2)
                    for i in 0..<(m * 2) { into[k][base + i] = p[i] }
                }
                // V0 seed (shipped coarse step) and V0 refined via the app's own engine path
                let b0s = obuf()
                var p0 = pX0
                dispatch(psoV0seed, ry: range.count, rx: d.rx) { e in
                    e.setBuffer(bound.buffer, offset: bound.offset, index: 0); e.setBuffer(b0s, offset: 0, index: 1)
                    e.setBytes(&p0, length: MemoryLayout<OriginParams>.stride, index: 2) }
                store(0, b0s, &seeds)
                let m0 = try MetalEngine.shared.measureOrigins(cube: bound.buffer, cubeOffset: bound.offset, params: pX0)
                for i in 0..<(m * 2) { meas[0][base + i] = m0[i] }
                // V1, V2 seeds and refined
                for (k, hw) in [(1, hw1), (2, hw2)] {
                    var pp = px(hw)
                    let bs = obuf(), bm = obuf()
                    dispatch(psoBoxSeed, ry: range.count, rx: d.rx) { e in
                        e.setBuffer(bound.buffer, offset: bound.offset, index: 0); e.setBuffer(bs, offset: 0, index: 1)
                        e.setBytes(&pp, length: MemoryLayout<OriginParamsX>.stride, index: 2) }
                    store(k, bs, &seeds)
                    dispatch(psoBox, ry: range.count, rx: d.rx) { e in
                        e.setBuffer(bound.buffer, offset: bound.offset, index: 0); e.setBuffer(bm, offset: 0, index: 1)
                        e.setBytes(&pp, length: MemoryLayout<OriginParamsX>.stride, index: 2) }
                    store(k, bm, &meas)
                }
                do {
                    var pp = px(hw1)
                    let bs = obuf(), bm = obuf()
                    dispatch(psoBoxNSeed, ry: range.count, rx: d.rx) { e in
                        e.setBuffer(bound.buffer, offset: bound.offset, index: 0); e.setBuffer(bs, offset: 0, index: 1)
                        e.setBytes(&pp, length: MemoryLayout<OriginParamsX>.stride, index: 2) }
                    store(4, bs, &seeds)
                    dispatch(psoBoxN, ry: range.count, rx: d.rx) { e in
                        e.setBuffer(bound.buffer, offset: bound.offset, index: 0); e.setBuffer(bm, offset: 0, index: 1)
                        e.setBytes(&pp, length: MemoryLayout<OriginParamsX>.stride, index: 2) }
                    store(5, bm, &meas)
                }
                // G: CPU Gaussian argmax -> seed buffer -> shipped refine
                let gSeedBuf = device.makeBuffer(length: m * 2 * 4, options: .storageModeShared)!
                let gp = gSeedBuf.contents().bindMemory(to: Float.self, capacity: m * 2)
                let tg = Date()
                let src = (bound.buffer.contents() + bound.offset).bindMemory(to: Float.self, capacity: m * d.qy * d.qx)
                let qy = d.qy, qx = d.qx
                nonisolated(unsafe) let gpu = gp
                nonisolated(unsafe) let srcu = src
                DispatchQueue.concurrentPerform(iterations: m) { i in
                    let (bx, by) = gaussianArgmax(srcu + i * qy * qx, qy: qy, qx: qx, kernel: gk)
                    gpu[2 * i] = Float(bx); gpu[2 * i + 1] = Float(by)
                }
                gCPUSeconds += Date().timeIntervalSince(tg)
                for i in 0..<(m * 2) { seeds[3][base + i] = gp[i] }
                let bg = obuf()
                var pg = px(0)
                dispatch(psoSeeded, ry: range.count, rx: d.rx) { e in
                    e.setBuffer(bound.buffer, offset: bound.offset, index: 0); e.setBuffer(bg, offset: 0, index: 1)
                    e.setBytes(&pg, length: MemoryLayout<OriginParamsX>.stride, index: 2); e.setBuffer(gSeedBuf, offset: 0, index: 3) }
                store(3, bg, &meas)
                let bpy = obuf()
                dispatch(psoPy, ry: range.count, rx: d.rx) { e in
                    e.setBuffer(bound.buffer, offset: bound.offset, index: 0); e.setBuffer(bpy, offset: 0, index: 1)
                    e.setBytes(&pg, length: MemoryLayout<OriginParamsX>.stride, index: 2); e.setBuffer(gSeedBuf, offset: 0, index: 3) }
                store(4, bpy, &meas)
                let bwd = obuf()
                dispatch(psoWide, ry: range.count, rx: d.rx) { e in
                    e.setBuffer(bound.buffer, offset: bound.offset, index: 0); e.setBuffer(bwd, offset: 0, index: 1)
                    e.setBytes(&pg, length: MemoryLayout<OriginParamsX>.stride, index: 2); e.setBuffer(gSeedBuf, offset: 0, index: 3) }
                store(6, bwd, &meas)
                // Timing on the first tile only (the app's real tile grid)
                if ti == 0 {
                    tileN = m
                    let o = obuf()
                    func tm(_ name: String, _ ps: MTLComputePipelineState, _ f: @escaping (MTLComputeCommandEncoder) -> Void) {
                        timing[name] = timeMedian(41) { dispatch(ps, ry: range.count, rx: d.rx, f) } * 1000 / Double(m)
                    }
                    var q0 = pX0, q1 = px(hw1), q2 = px(hw2)
                    tm("v0seed", psoV0seed) { e in e.setBuffer(bound.buffer, offset: bound.offset, index: 0); e.setBuffer(o, offset: 0, index: 1); e.setBytes(&q0, length: MemoryLayout<OriginParams>.stride, index: 2) }
                    tm("v0full", psoShipped) { e in e.setBuffer(bound.buffer, offset: bound.offset, index: 0); e.setBuffer(o, offset: 0, index: 1); e.setBytes(&q0, length: MemoryLayout<OriginParams>.stride, index: 2) }
                    tm("v1seed", psoBoxSeed) { e in e.setBuffer(bound.buffer, offset: bound.offset, index: 0); e.setBuffer(o, offset: 0, index: 1); e.setBytes(&q1, length: MemoryLayout<OriginParamsX>.stride, index: 2) }
                    tm("v1full", psoBox) { e in e.setBuffer(bound.buffer, offset: bound.offset, index: 0); e.setBuffer(o, offset: 0, index: 1); e.setBytes(&q1, length: MemoryLayout<OriginParamsX>.stride, index: 2) }
                    tm("v2seed", psoBoxSeed) { e in e.setBuffer(bound.buffer, offset: bound.offset, index: 0); e.setBuffer(o, offset: 0, index: 1); e.setBytes(&q2, length: MemoryLayout<OriginParamsX>.stride, index: 2) }
                    tm("v2full", psoBox) { e in e.setBuffer(bound.buffer, offset: bound.offset, index: 0); e.setBuffer(o, offset: 0, index: 1); e.setBytes(&q2, length: MemoryLayout<OriginParamsX>.stride, index: 2) }
                }
            }
            // dumps
            for (k, nm) in ["v0", "v1", "v2", "g"].enumerated() {
                dump(seeds[k], "\(outDir)/\(label).seed_\(nm).f32"); dump(meas[k], "\(outDir)/\(label).meas_\(nm).f32")
            }
            dump(meas[4], "\(outDir)/\(label).meas_py.f32"); dump(meas[5], "\(outDir)/\(label).meas_v1n.f32"); dump(meas[6], "\(outDir)/\(label).meas_wide.f32"); dump(seeds[4], "\(outDir)/\(label).seed_v1n.f32")
            print(String(format: "   total %.1fs  peak footprint %.0f MB  G CPU %.1fs (%.1f us/pattern all cores)  tile %d rows x %d = %d patterns",
                         Date().timeIntervalSince(t0), peakFootprintMB, gCPUSeconds, gCPUSeconds * 1e6 / Double(n), rowsPerTile, d.rx, tileN))
            // timing table
            func t(_ k: String) -> Double { timing[k] ?? .nan }
            print(String(format: "   TIME us/pattern  coarse-only: V0 %.3f  V1 %.3f (%.2fx)  V2 %.3f (%.2fx) | whole kernel: V0 %.3f  V1 %.3f (%.2fx)  V2 %.3f (%.2fx)",
                         t("v0seed"), t("v1seed"), t("v1seed") / t("v0seed"), t("v2seed"), t("v2seed") / t("v0seed"),
                         t("v0full"), t("v1full"), t("v1full") / t("v0full"), t("v2full"), t("v2full") / t("v0full")))

            // MARK: statistics
            let names = ["V0", "V1", "V2", "G"]
            func dist(_ a: [Float], _ b: [Float], _ i: Int) -> Float {
                let dx = a[2 * i] - b[2 * i], dy = a[2 * i + 1] - b[2 * i + 1]; return (dx * dx + dy * dy).squareRoot()
            }
            func edge(_ s: [Float], _ i: Int) -> Float {
                let x = s[2 * i], y = s[2 * i + 1]
                return min(min(x, Float(d.qx - 1) - x), min(y, Float(d.qy - 1) - y))
            }
            for k in 0..<3 {
                var rawMiss = 0, refMiss = 0, refMissEdge = 0
                for i in 0..<n {
                    if dist(seeds[k], seeds[3], i) > 1 { rawMiss += 1 }
                    if dist(meas[k], meas[3], i) > 1 {
                        refMiss += 1
                        if min(edge(seeds[3], i), edge(seeds[k], i)) < r { refMissEdge += 1 }
                    }
                }
                let df = (0..<n).map { dist(meas[k], meas[3], $0) }.sorted()
                print(String(format: "   MISS %@ vs G: raw seed >1px %d/%d (%.2f%%)  refined >1px %d/%d (%.2f%%; %d with a seed within r of the detector edge)  |meas-G| median %.4f p95 %.4f max %.3f",
                             names[k], rawMiss, n, 100 * Double(rawMiss) / Double(n), refMiss, n, 100 * Double(refMiss) / Double(n), refMissEdge,
                             pctl(df, 50), pctl(df, 95), df.last ?? 0))
            }
            for k in 0..<3 {
                let dpy = (0..<n).map { dist(meas[k], meas[4], $0) }
                let gt1 = dpy.filter { $0 > 1 }.count
                print(String(format: "   MISSPY %@ vs PY (py4DSTEM single pass 1.2r from the Gaussian seed; the 2026-09-05 recorded definition): >1px %d/%d (%.2f%%)",
                             names[k], gt1, n, 100 * Double(gt1) / Double(n)))
            }
            for k in 1..<4 {
                let dv = (0..<n).map { dist(meas[k], meas[0], $0) }.sorted()
                let gt01 = dv.filter { $0 > 0.1 }.count, gt1 = dv.filter { $0 > 1 }.count
                print(String(format: "   DMEAS %@-V0: median %.4f p95 %.4f max %.3f  >0.1px %d  >1px %d",
                             names[k], pctl(dv, 50), pctl(dv, 95), dv.last ?? 0, gt01, gt1))
            }
            // A2 additions: exploratory V1n (replicate-padded box edges) and the WIDE truth proxy
            do {
                let pairs: [(String, Int, Int)] = [("V0", 0, 0), ("V1", 1, 1), ("V2", 2, 2), ("V1n", 4, 5), ("G", 3, 3), ("PY", 3, 4)]
                for (nm, sk, mk) in pairs {
                    let dw = (0..<n).map { dist(meas[mk], meas[6], $0) }.sorted()
                    let gt1 = dw.filter { $0 > 1 }.count
                    var extra = ""
                    if nm == "V1n" {
                        var rawMiss = 0, refMiss = 0, refMissEdge = 0, pyMiss = 0
                        for i in 0..<n {
                            if dist(seeds[4], seeds[3], i) > 1 { rawMiss += 1 }
                            if dist(meas[5], meas[3], i) > 1 { refMiss += 1; if min(edge(seeds[3], i), edge(seeds[4], i)) < r { refMissEdge += 1 } }
                            if dist(meas[5], meas[4], i) > 1 { pyMiss += 1 }
                        }
                        extra = String(format: "  | V1n vs G: raw seed >1px %d, refined >1px %d (%d near edge); vs PY >1px %d of %d", rawMiss, refMiss, refMissEdge, pyMiss, n)
                    }
                    print(String(format: "   WIDEDIST %@ vs WIDE(3r iterated CoM from the Gaussian seed): median %.4f p95 %.4f max %.3f  >1px %d/%d%@",
                                 nm, pctl(dw, 50), pctl(dw, 95), dw.last ?? 0, gt1, n, extra))
                }
                print(String(format: "   PROBECENTRE mean-DP probeSize centre (x0, y0) = (%.4f, %.4f)", probe.x0, probe.y0))
            }
            // fits (shipped fitter)
            var fits: [OriginCalibration.TrimmedFit] = []
            let fitIdx = [0, 1, 2, 3, 5, 6]; let fitNames = ["V0", "V1", "V2", "G", "V1n", "WIDE"]
            for k in fitIdx {
                var mx = [Float](repeating: 0, count: n), my = mx
                for i in 0..<n { mx[i] = meas[k][2 * i]; my[i] = meas[k][2 * i + 1] }
                let f = OriginCalibration.fitOriginTrimmed(measuredX: mx, measuredY: my, width: d.rx, height: d.ry, fitFunction: .plane)
                fits.append(f)
                let maps = OriginMaps(width: d.rx, height: d.ry, measuredX: mx, measuredY: my, fittedX: f.fittedX, fittedY: f.fittedY,
                                      excludedFraction: f.excludedFraction, robustResidual: f.keptResidual, originValidity: f.kept)
                let rms = maps.rmsResidual ?? .nan
                let mfx = f.fittedX.reduce(0, +) / Float(n), mfy = f.fittedY.reduce(0, +) / Float(n)
                print(String(format: "   FIT %@: fullScanRMS %.4f (gate r %.4f, %@)  keptRMS %.4f  excluded %.4f  mean fitted (%.4f, %.4f)",
                             fitNames[fitIdx.firstIndex(of: k)!], rms, r, rms.isFinite && rms <= r ? "PASS" : "BLOCK", f.keptResidual, f.excludedFraction ?? .nan, mfx, mfy))
            }
            for k in 1..<6 {
                let dd = (0..<n).map { i -> Float in
                    let dx = fits[k].fittedX[i] - fits[0].fittedX[i], dy = fits[k].fittedY[i] - fits[0].fittedY[i]
                    return (dx * dx + dy * dy).squareRoot()
                }.sorted()
                let mdx = (fits[k].fittedX.reduce(0, +) - fits[0].fittedX.reduce(0, +)) / Float(n)
                let mdy = (fits[k].fittedY.reduce(0, +) - fits[0].fittedY.reduce(0, +)) / Float(n)
                print(String(format: "   DFIT %@-V0: fitted-origin |d| median %.4f p95 %.4f max %.4f  scan-mean shift (%.4f, %.4f)",
                             fitNames[k], pctl(dd, 50), pctl(dd, 95), dd.last ?? 0, mdx, mdy))
            }
            fflush(stdout)
        }
        print("peak phys_footprint \(Int(peakFootprintMB)) MB")
    }
}
