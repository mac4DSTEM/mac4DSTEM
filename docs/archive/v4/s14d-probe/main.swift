import Foundation
import Metal
import Accelerate
import Darwin

// S14-D probe: fixtures + datasets through the SHIPPED kernel (measureOrigins) and its parameterised copy (s14d.metal). Scratch code.
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

struct OriginParamsX { var ry: UInt32; var rx: UInt32; var qy: UInt32; var qx: UInt32; var r: Float; var rscale: Float; var passes: UInt32; var nofloor: UInt32 }

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


struct Cand { let name: String; let k: Float; let passes: UInt32; let nofloor: UInt32; let seeded: Bool }
// block-seed candidates: shipped window/passes first
func blockCands(extraD: Float?) -> [Cand] {
    var c: [Cand] = [Cand(name: "ship", k: 1.2, passes: 4, nofloor: 0, seeded: false)]
    for k: Float in [1.5, 1.75, 2.0, 2.5, 3.0] { c.append(Cand(name: "k\(k)", k: k, passes: 4, nofloor: 0, seeded: false)) }
    c.append(Cand(name: "p1", k: 1.2, passes: 1, nofloor: 0, seeded: false))
    c.append(Cand(name: "py1", k: 1.2, passes: 1, nofloor: 1, seeded: false))
    c.append(Cand(name: "p10", k: 1.2, passes: 10, nofloor: 0, seeded: false))
    c.append(Cand(name: "p30", k: 1.2, passes: 30, nofloor: 0, seeded: false))
    if let d = extraD { c.append(Cand(name: "D", k: d, passes: 4, nofloor: 0, seeded: false)) }
    return c
}
let seededCands: [Cand] = [1.2, 2.0, 3.0].map { Cand(name: "G\($0)", k: $0, passes: 4, nofloor: 0, seeded: true) }

func readF32(_ path: String) -> [Float] {
    let d = try! Data(contentsOf: URL(fileURLWithPath: path))
    return d.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
}

@main
struct S14D {
    static func main() async throws {
        startWatchdog()
        let env = ProcessInfo.processInfo.environment
        let outDir = env["S14D_OUT"] ?? "."
        let mode = env["S14D_MODE"] ?? "data"
        let device = MetalEngine.shared.device
        let lib = try device.makeLibrary(URL: URL(fileURLWithPath: "s14d.metallib"))
        func pso(_ n: String) -> MTLComputePipelineState { try! device.makeComputePipelineState(function: lib.makeFunction(name: n)!) }
        let psoBlk = pso("measureOrigin_blk"), psoSeeded = pso("measureOrigin_seeded")

        if mode == "fixture" {
            // args: name  (files out/fixt_<name>.f32 and .truth.txt, 250x250)
            for name in CommandLine.arguments.dropFirst() {
                let cube = readF32("\(outDir)/fixt_\(name).f32"); let qy = 250, qx = 250
                let n = cube.count / (qy * qx)
                let truth = try String(contentsOfFile: "\(outDir)/fixt_\(name).truth.txt", encoding: .utf8).split(separator: "\n").map { $0.split(separator: " ").map { Float($0)! } }
                var mean = [Float](repeating: 0, count: qy * qx)
                for p in 0..<n { for i in 0..<(qy * qx) { mean[i] += cube[p * qy * qx + i] / Float(n) } }
                let probe = OriginCalibration.probeSize(dp: mean, qy: qy, qx: qx)!
                let r = probe.r
                print(String(format: "=== %@ n=%d app probeSize r %.4f centre (%.3f, %.3f)  win_shipped %.3f", name, n, r, probe.x0, probe.y0, max(1.2 * r, r + 1.5)))
                let buf = device.makeBuffer(bytes: cube, length: cube.count * 4, options: .storageModeShared)!
                // shipped kernel, unmodified
                let ship = try MetalEngine.shared.measureOrigins(cube: buf, cubeOffset: 0, params: OriginParams(ry: 1, rx: UInt32(n), qy: UInt32(qy), qx: UInt32(qx), r: r, rscale: 1.2))
                dump(ship, "\(outDir)/fx_\(name).SHIPPED.f32")
                func run(_ c: Cand, seeds: MTLBuffer?) -> [Float] {
                    let o = device.makeBuffer(length: n * 8, options: .storageModeShared)!
                    var p = OriginParamsX(ry: 1, rx: UInt32(n), qy: UInt32(qy), qx: UInt32(qx), r: r, rscale: c.k, passes: c.passes, nofloor: c.nofloor)
                    dispatch(c.seeded ? psoSeeded : psoBlk, ry: 1, rx: n) { e in
                        e.setBuffer(buf, offset: 0, index: 0); e.setBuffer(o, offset: 0, index: 1)
                        e.setBytes(&p, length: MemoryLayout<OriginParamsX>.stride, index: 2)
                        if let s = seeds { e.setBuffer(s, offset: 0, index: 3) } }
                    let q = o.contents().bindMemory(to: Float.self, capacity: n * 2); return Array(UnsafeBufferPointer(start: q, count: n * 2))
                }
                var maxDiff: Float = 0
                let cs = blockCands(extraD: nil)
                for c in cs {
                    let m = run(c, seeds: nil); dump(m, "\(outDir)/fx_\(name).\(c.name).f32")
                    if c.name == "ship" { for i in 0..<(2 * n) { maxDiff = max(maxDiff, abs(m[i] - ship[i])) } }
                }
                print("   probe-copy vs shipped kernel at 4 passes/floor: max |diff| = \(maxDiff) (bitwise-equal required = 0)")
                // gain probe: seeds at truth + (d,0) and (0,d), 1 pass, several windows
                for (dxs, dys, tag) in [(Float(0.25), Float(0), "px"), (Float(-0.25), Float(0), "mx"), (Float(0), Float(0.25), "py"), (Float(0), Float(-0.25), "my"), (Float(0), Float(0), "t0")] {
                    var sd = [Float](); for t in truth { sd += [t[0] + dxs, t[1] + dys] }
                    let sb = device.makeBuffer(bytes: sd, length: sd.count * 4, options: .storageModeShared)!
                    for k: Float in [1.2, 1.5, 2.0, 3.0] {
                        let c = Cand(name: "gain\(tag)_k\(k)", k: k, passes: 1, nofloor: 0, seeded: true)
                        dump(run(c, seeds: sb), "\(outDir)/fx_\(name).\(c.name).f32")
                    }
                    // and 4 passes at the shipped window from the truth: does the truth stay a fixed point?
                    let c4 = Cand(name: "hold\(tag)_k1.2", k: 1.2, passes: 4, nofloor: 0, seeded: true)
                    dump(run(c4, seeds: sb), "\(outDir)/fx_\(name).\(c4.name).f32")
                }
                print("   r=\(r)"); fflush(stdout)
            }
            print("peak phys_footprint \(Int(peakFootprintMB)) MB"); return
        }

        // ---- data / rhoq modes. args: label|path[|datasetPath[|Drscale]]
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
                    d = parts.count > 2 && !parts[2].isEmpty ? try await h.describe(path: parts[2]) : try await h.discoverPrimaryDataset()
                }
            } catch { print("=== \(label): SKIPPED — \(error)"); continue }
            precondition(d.qx <= 512, "MAXQX")
            print("=== \(label)  scan \(d.ry)x\(d.rx)  det \(d.qy)x\(d.qx)")
            let t0 = Date()
            let data = FourDArray(reader: reader, descriptor: d)
            let statistics = try await VirtualDetector.tiledDPStatistics(data: data, descriptor: d)
            guard let probe = OriginCalibration.probeSize(dp: statistics.meanDP, qy: d.qy, qx: d.qx) else { print("   probeNotMeasurable"); continue }
            let r = probe.r
            print(String(format: "   r %.4f win_shipped %.3f probe centre (%.4f, %.4f)", r, max(1.2 * r, r + 1.5), probe.x0, probe.y0))
            if mode == "rhoq" {
                dump(statistics.meanDP, "\(outDir)/\(label).meandp.f32")
                print("   RHOQMETA \(label) \(d.qy) \(d.qx) \(r) \(probe.x0) \(probe.y0)"); continue
            }
            let dRs: Float? = parts.count > 3 && !parts[3].isEmpty ? Float(parts[3]) : nil
            let cands = blockCands(extraD: dRs)
            let gk = gaussKernel(sigma: r)
            let n = d.ry * d.rx
            var meas = [String: [Float]](); var sums = [Float](repeating: 0, count: n)
            for c in cands + seededCands { meas[c.name] = [Float](repeating: 0, count: 2 * n) }
            meas["SHIPPED"] = [Float](repeating: 0, count: 2 * n)
            let rowsPerTile = await data.scanTileRows()
            let ranges: [Range<Int>] = stride(from: 0, to: d.ry, by: rowsPerTile).map { $0..<min(d.ry, $0 + rowsPerTile) }
            var source = TileGPUSource(data: data, descriptor: d, cube: await data.resident(for: d))
            for (ti, range) in ranges.enumerated() {
                let bound = try await source.binding(for: range, prefetching: ti + 1 < ranges.count ? ranges[ti + 1] : nil, label: "s14d tile")
                let m = range.count * d.rx; let base = range.lowerBound * d.rx * 2
                let src = (bound.buffer.contents() + bound.offset).bindMemory(to: Float.self, capacity: m * d.qy * d.qx)
                for i in 0..<m { var s: Float = 0; let o = i * d.qy * d.qx; for j in 0..<(d.qy * d.qx) { s += src[o + j] }; sums[range.lowerBound * d.rx + i] = s }
                let sh = try MetalEngine.shared.measureOrigins(cube: bound.buffer, cubeOffset: bound.offset, params: OriginParams(ry: UInt32(range.count), rx: UInt32(d.rx), qy: UInt32(d.qy), qx: UInt32(d.qx), r: r, rscale: 1.2))
                for i in 0..<(m * 2) { meas["SHIPPED"]![base + i] = sh[i] }
                func run(_ c: Cand, _ seeds: MTLBuffer?) {
                    let o = device.makeBuffer(length: m * 8, options: .storageModeShared)!
                    var p = OriginParamsX(ry: UInt32(range.count), rx: UInt32(d.rx), qy: UInt32(d.qy), qx: UInt32(d.qx), r: r, rscale: c.k, passes: c.passes, nofloor: c.nofloor)
                    dispatch(c.seeded ? psoSeeded : psoBlk, ry: range.count, rx: d.rx) { e in
                        e.setBuffer(bound.buffer, offset: bound.offset, index: 0); e.setBuffer(o, offset: 0, index: 1)
                        e.setBytes(&p, length: MemoryLayout<OriginParamsX>.stride, index: 2)
                        if let s = seeds { e.setBuffer(s, offset: 0, index: 3) } }
                    let q = o.contents().bindMemory(to: Float.self, capacity: m * 2)
                    for i in 0..<(m * 2) { meas[c.name]![base + i] = q[i] }
                }
                for c in cands { run(c, nil) }
                let gSeedBuf = device.makeBuffer(length: m * 8, options: .storageModeShared)!
                let gp = gSeedBuf.contents().bindMemory(to: Float.self, capacity: m * 2)
                let qy = d.qy, qx = d.qx
                nonisolated(unsafe) let gpu = gp; nonisolated(unsafe) let srcu = src
                DispatchQueue.concurrentPerform(iterations: m) { i in
                    let (bx, by) = gaussianArgmax(srcu + i * qy * qx, qy: qy, qx: qx, kernel: gk)
                    gpu[2 * i] = Float(bx); gpu[2 * i + 1] = Float(by)
                }
                for c in seededCands { run(c, gSeedBuf) }
            }
            for (nm, a) in meas { dump(a, "\(outDir)/\(label).\(nm).f32") }
            dump(sums, "\(outDir)/\(label).sum.f32")
            print(String(format: "   total %.1fs  peak footprint %.0f MB  tile rows %d", Date().timeIntervalSince(t0), peakFootprintMB, rowsPerTile))
            // statistics
            func dist(_ a: [Float], _ b: [Float], _ i: Int) -> Float { let dx = a[2*i]-b[2*i], dy = a[2*i+1]-b[2*i+1]; return (dx*dx+dy*dy).squareRoot() }
            let ship = meas["SHIPPED"]!, blk = meas["ship"]!
            var eq = 0; for i in 0..<(2*n) where ship[i] == blk[i] { eq += 1 }
            print("   COPYCHECK shipped-path vs probe-copy(4 passes, floor): equal floats \(eq)/\(2*n)")
            let allNames = cands.map { $0.name } + seededCands.map { $0.name }
            var fits: [String: OriginCalibration.TrimmedFit] = [:]
            for nm in allNames {
                let a = meas[nm]!
                var mx = [Float](repeating: 0, count: n), my = mx
                for i in 0..<n { mx[i] = a[2*i]; my[i] = a[2*i+1] }
                let f = OriginCalibration.fitOriginTrimmed(measuredX: mx, measuredY: my, width: d.rx, height: d.ry, fitFunction: .plane)
                fits[nm] = f
                let maps = OriginMaps(width: d.rx, height: d.ry, measuredX: mx, measuredY: my, fittedX: f.fittedX, fittedY: f.fittedY,
                                      excludedFraction: f.excludedFraction, robustResidual: f.keptResidual, originValidity: f.kept)
                let rms = maps.rmsResidual ?? .nan
                let mfx = f.fittedX.reduce(0, +) / Float(n), mfy = f.fittedY.reduce(0, +) / Float(n)
                let dm = (0..<n).map { dist(a, ship, $0) }.sorted()
                let df = (0..<n).map { i -> Float in let dx = f.fittedX[i]-fits["ship"]!.fittedX[i], dy = f.fittedY[i]-fits["ship"]!.fittedY[i]; return (dx*dx+dy*dy).squareRoot() }.sorted()
                print(String(format: "   CAND %-6@ FIT rms %.4f (%@) excl %.4f meanFit (%.4f, %.4f) | DMEAS vs ship med %.4f p95 %.4f max %.3f | DFIT vs ship med %.4f max %.4f",
                             nm, rms, rms.isFinite && rms <= r ? "PASS" : "BLOCK", f.excludedFraction ?? .nan, mfx, mfy, pctl(dm, 50), pctl(dm, 95), dm.last ?? 0, pctl(df, 50), df.last ?? 0))
            }
            // seed sensitivity: block-seed vs G-seed at the same window
            for (kb, kg) in [("ship", "G1.2"), ("k2.0", "G2.0"), ("k3.0", "G3.0")] {
                let ds = (0..<n).map { dist(meas[kb]!, meas[kg]!, $0) }.sorted()
                print(String(format: "   SEEDSENS %@ vs %@ (block seed vs Gaussian seed, same window): median %.4f p95 %.4f max %.3f  >1px %d", kb, kg, pctl(ds, 50), pctl(ds, 95), ds.last ?? 0, ds.filter { $0 > 1 }.count))
            }
            fflush(stdout)
        }
        print("peak phys_footprint \(Int(peakFootprintMB)) MB")
    }
}
