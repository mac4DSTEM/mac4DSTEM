//
//  FourDArray.swift
//  Role: The in-memory data layer between H5Reader and the GPU.
//
//  Two responsibilities:
//   1. `pattern(ry:rx:)` — fetch single CBED patterns with a small LRU cache,
//      so scrubbing the scan position is fast and truly chunked (one pattern
//      per read).
//   2. `cubeBuffer()` — for whole-dataset GPU analysis (virtual detector, DPC),
//      stream the cube row-by-row from disk into ONE MTLBuffer, guarded by a
//      memory budget. Built once, then reused.
//
//  STAGE-2 NOTE: `cubeBuffer()` currently requires the cube to fit in the GPU
//  working set. True out-of-core processing — dispatch the kernel per streamed
//  scan-row tile and accumulate into the result, never holding the full cube —
//  plugs in right here (see MetalEngine.virtualDetector for where tiles feed in).
//

import Foundation
import Metal

enum FourDError: LocalizedError {
    case tooLargeForGPU(bytes: Int, budget: Int)
    var errorDescription: String? {
        switch self {
        case .tooLargeForGPU(let b, let budget):
            let gb = { (x: Int) in String(format: "%.2f GB", Double(x) / 1_073_741_824) }
            return "This dataset (\(gb(b))) exceeds the per-pass GPU budget (~\(gb(budget))). "
                 + "Out-of-core tiling is a planned feature; for now try a smaller crop."
        }
    }
}

actor FourDArray {

    private let reader: H5Reader
    let descriptor: DatasetDescriptor

    // Single-pattern LRU cache
    private var cache: [Int: DiffractionPattern] = [:]
    private var order: [Int] = []                 // most-recent at the end
    private let maxCached = 96

    // Whole-cube GPU buffer (lazy)
    private var cube: MTLBuffer?

    init(reader: H5Reader, descriptor: DatasetDescriptor) {
        self.reader = reader
        self.descriptor = descriptor
    }

    private func key(_ ry: Int, _ rx: Int) -> Int { ry * descriptor.rx + rx }

    // MARK: Single pattern (cached)

    func pattern(ry: Int, rx: Int) async throws -> DiffractionPattern {
        let k = key(ry, rx)
        if let hit = cache[k] {
            touch(k)
            return hit
        }
        let raw = try await reader.readPattern(descriptor, ry: ry, rx: rx)
        let p = DiffractionPattern(qy: descriptor.qy, qx: descriptor.qx, pixels: raw)
        insert(k, p)
        return p
    }

    private func touch(_ k: Int) {
        if let i = order.firstIndex(of: k) { order.remove(at: i) }
        order.append(k)
    }

    private func insert(_ k: Int, _ p: DiffractionPattern) {
        cache[k] = p
        touch(k)
        while order.count > maxCached {
            let evict = order.removeFirst()
            cache[evict] = nil
        }
    }

    // MARK: Whole cube on GPU

    func cubeBuffer() async throws -> MTLBuffer {
        if let c = cube { return c }

        let d = descriptor
        let count = d.ry * d.rx * d.qy * d.qx
        let bytes = count * MemoryLayout<Float>.stride
        let budget = Int(MetalEngine.shared.device.recommendedMaxWorkingSetSize) / 2
        guard bytes < budget else { throw FourDError.tooLargeForGPU(bytes: bytes, budget: budget) }

        var all = [Float](repeating: 0, count: count)
        let patPix = d.qy * d.qx
        let rowPix = d.rx * patPix

        // Stream one scan row at a time (chunk-friendly), copy into `all`.
        for ry in 0..<d.ry {
            let row = try await reader.readScanRow(d, ry: ry)
            all.withUnsafeMutableBufferPointer { dst in
                row.withUnsafeBufferPointer { src in
                    let base = dst.baseAddress!.advanced(by: ry * rowPix)
                    base.update(from: src.baseAddress!, count: rowPix)
                }
            }
        }

        guard let buf = MetalEngine.shared.device.makeBuffer(
            bytes: all, length: bytes, options: .storageModeShared
        ) else { throw H5Error.readFailed("MTLBuffer allocation") }
        buf.label = "4D cube (\(d.shapeString))"
        cube = buf
        return buf
    }

    /// Free the resident cube buffer (e.g. when switching datasets).
    func releaseCube() { cube = nil }
}
