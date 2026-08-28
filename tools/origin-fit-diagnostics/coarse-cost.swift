import Foundation
import Metal

struct OriginParams { var ry: UInt32; var rx: UInt32; var qy: UInt32; var qx: UInt32; var r: Float; var rscale: Float }

@main
struct Bench {
    static func main() throws {
        let dev = MTLCreateSystemDefaultDevice()!
        let q = dev.makeCommandQueue()!
        let libURL = URL(fileURLWithPath: "default.metallib")
        let lib = try dev.makeLibrary(URL: libURL)
        let psoV0 = try dev.makeComputePipelineState(function: lib.makeFunction(name: "measureOrigin")!)
        let psoV1 = try dev.makeComputePipelineState(function: lib.makeFunction(name: "measureOriginStride1")!)

        // The four training datasets' REAL shapes, from the campaign report
        // (2026-08-28). Scan extent matters: `measureOrigin` is dispatched once
        // per TILE by VirtualDetector.tiledMeasuredOrigins, not once per scan,
        // and dispatch2D derives the threadgroup grid from the tile's height —
        // so timing at the wrong grid measures occupancy, not work. The tile
        // height is computed below with FourDArray.scanTileRows' own formula
        // rather than hardcoded, because it depends on THIS machine's RAM.
        let cases: [(name: String, qy: Int, qx: Int, r: Float, ry: Int, rx: Int)] = [
            ("Si_SiGe   128x128 r=5.03  bin=5",  128, 128, 5.0264, 50, 200),
            ("sim_Au    125x125 r=6.10  bin=6",  125, 125, 6.0963, 100, 84),
            ("Particle1 128x128 r=10.62 bin=11", 128, 128, 10.6244, 90, 45),
            ("WS2       128x128 r=1.86  bin=2",  128, 128, 1.8594, 128, 128),
        ]

        // FourDArray.scanTileRows(maximumRows:) verbatim (FourDArray.swift:365-400).
        func tileRows(ry: Int, rx: Int, qy: Int, qx: Int) -> Int {
            let bytesPerRow = rx * qy * qx * MemoryLayout<Float>.stride
            let gpuBudget = max(1, Int(dev.recommendedMaxWorkingSetSize) / 8)
            let hostBudget = max(1, Int(ProcessInfo.processInfo.physicalMemory) / 24)
            let budget = min(gpuBudget, hostBudget)
            return max(1, min(ry, max(1, budget / max(1, bytesPerRow))))
        }

        func time(_ pso: MTLComputePipelineState, _ cube: MTLBuffer, _ out: MTLBuffer,
                  _ p: OriginParams, iterations: Int) -> (best: Double, median: Double) {
            var samples: [Double] = []
            for _ in 0..<iterations {
                var pp = p
                let start = DispatchTime.now().uptimeNanoseconds
                let cb = q.makeCommandBuffer()!
                let enc = cb.makeComputeCommandEncoder()!
                enc.setComputePipelineState(pso)
                enc.setBuffer(cube, offset: 0, index: 0)
                enc.setBuffer(out, offset: 0, index: 1)
                enc.setBytes(&pp, length: MemoryLayout<OriginParams>.stride, index: 2)
                // MetalEngine.dispatch2D verbatim (MetalEngine.swift:353-368).
                let w = min(pso.threadExecutionWidth, Int(p.rx))
                let h = max(1, min(pso.maxTotalThreadsPerThreadgroup / w, Int(p.ry)))
                enc.dispatchThreads(MTLSize(width: Int(p.rx), height: Int(p.ry), depth: 1),
                                    threadsPerThreadgroup: MTLSize(width: w, height: h, depth: 1))
                enc.endEncoding()
                cb.commit(); cb.waitUntilCompleted()
                samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
            }
            let sorted = samples.sorted()
            return (sorted[0], sorted[sorted.count / 2])
        }

        print("Coarse-step cost: shipped binned-block argmax (stride = bin) vs the")
        print("translation-equivariant stride-1 window (OriginMeasure.metal:47,49).")
        print("Median of 15 dispatches (best also shown), whole measureOrigin kernel.")
        print("Dispatched at the app's real TILE grid, not the whole scan — see the note in this file.\n")
        for c in cases {
            let patPix = c.qy * c.qx
            // The grid the app actually dispatches: one tile, not the scan.
            let rows = tileRows(ry: c.ry, rx: c.rx, qy: c.qy, qx: c.qx)
            let n = rows * c.rx
            let cube = dev.makeBuffer(length: n * patPix * MemoryLayout<Float>.stride,
                                      options: .storageModeShared)!
            let ptr = cube.contents().bindMemory(to: Float.self, capacity: n * patPix)
            // Synthetic: a bright disk of radius r, jittered per position, plus
            // four weaker Bragg disks. Coarse-loop COST is data-independent;
            // the content only exercises the CoM window realistically.
            for i in 0..<n {
                let cx = Float(c.qx)/2 + Float((i % 7)) - 3, cy = Float(c.qy)/2 + Float((i % 5)) - 2
                for y in 0..<c.qy {
                    for x in 0..<c.qx {
                        let dx = Float(x) - cx, dy = Float(y) - cy
                        let d = (dx*dx + dy*dy).squareRoot()
                        ptr[i*patPix + y*c.qx + x] = d <= c.r ? 1000 : (d <= c.r*3 ? 40 : 1)
                    }
                }
            }
            let out = dev.makeBuffer(length: n * 2 * MemoryLayout<Float>.stride, options: .storageModeShared)!
            let p = OriginParams(ry: UInt32(rows), rx: UInt32(c.rx), qy: UInt32(c.qy), qx: UInt32(c.qx),
                                 r: c.r, rscale: 1.2)
            // Sanity: the variant must still MEASURE origins, not just run
            // slower. Compare both kernels' output against the disk centre
            // this synthetic pattern was built around.
            func origins(_ pso: MTLComputePipelineState) -> [Float] {
                _ = time(pso, cube, out, p, iterations: 1)
                let o = out.contents().bindMemory(to: Float.self, capacity: n*2)
                return Array(UnsafeBufferPointer(start: o, count: n*2))
            }
            let o0 = origins(psoV0), o1 = origins(psoV1)
            var e0: Float = 0, e1: Float = 0, d01: Float = 0
            for i in 0..<n {
                let cx = Float(c.qx)/2 + Float((i % 7)) - 3, cy = Float(c.qy)/2 + Float((i % 5)) - 2
                e0 = max(e0, max(abs(o0[2*i]-cx), abs(o0[2*i+1]-cy)))
                e1 = max(e1, max(abs(o1[2*i]-cx), abs(o1[2*i+1]-cy)))
                d01 = max(d01, max(abs(o0[2*i]-o1[2*i]), abs(o0[2*i+1]-o1[2*i+1])))
            }
            _ = time(psoV0, cube, out, p, iterations: 3)   // warm up
            let r0 = time(psoV0, cube, out, p, iterations: 15)
            let r1 = time(psoV1, cube, out, p, iterations: 15)
            let t0 = r0.median, t1 = r1.median
            let bin = max(1, Int((c.r).rounded()))
            print(String(format: "%@\n   tile %d rows x %d = %d positions (scan is %dx%d; tile height from this machine's RAM)\n   shipped %8.2f ms  (%6.1f us/pattern)  [best %6.1f]\n   stride1 %8.2f ms  (%6.1f us/pattern)  [best %6.1f]   ratio %5.2fx   (bin^2 = %d)",
                         c.name, rows, c.rx, n, c.ry, c.rx,
                         t0, t0*1000/Double(n), r0.best*1000/Double(n),
                         t1, t1*1000/Double(n), r1.best*1000/Double(n), t1/t0, bin*bin))
            print(String(format: "   max err vs true disk centre: shipped %.3f px, stride1 %.3f px; max |shipped-stride1| %.3f px",
                         e0, e1, d01))
        }
    }
}
