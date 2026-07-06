import Foundation
import Metal

enum FourDError: LocalizedError {
    case tooLargeForGPU(bytes: Int, budget: Int)
    case allocationFailed

    var errorDescription: String? {
        switch self {
        case .tooLargeForGPU(let bytes, let budget):
            let gb = { (x: Int) in String(format: "%.2f GB", Double(x) / 1_073_741_824) }
            return "This dataset (\(gb(bytes))) exceeds the per-pass GPU budget (~\(gb(budget))). "
                 + "Out-of-core tiling is a planned feature; for now try a smaller crop."
        case .allocationFailed:
            return "Could not allocate the GPU buffer for the 4D cube."
        }
    }
}

actor FourDArray {
    private let reader: any FourDDataSource
    let descriptor: DatasetDescriptor

    private var cache: [Int: DiffractionPattern] = [:]
    private var order: [Int] = []
    private let maxCachedPatterns = 96

    // Whole-cube GPU buffer, built once on first analysis and reused.
    private var cube: MTLBuffer?

    init(reader: any FourDDataSource, descriptor: DatasetDescriptor) {
        self.reader = reader
        self.descriptor = descriptor
    }

    func pattern(ry: Int, rx: Int) async throws -> DiffractionPattern {
        let clampedY = min(max(ry, 0), max(descriptor.ry - 1, 0))
        let clampedX = min(max(rx, 0), max(descriptor.rx - 1, 0))
        let cacheKey = key(ry: clampedY, rx: clampedX)

        if let cached = cache[cacheKey] {
            touch(cacheKey)
            return cached
        }

        let pixels = try await reader.readPattern(descriptor, ry: clampedY, rx: clampedX)
        let pattern = DiffractionPattern(qy: descriptor.qy, qx: descriptor.qx, pixels: pixels)
        insert(pattern, for: cacheKey)
        return pattern
    }

    func clearCache() {
        cache.removeAll(keepingCapacity: true)
        order.removeAll(keepingCapacity: true)
    }

    /// Build (once) and return the full 4D cube as one shared-storage GPU
    /// buffer, [Ry*Rx*Qy*Qx] row-major Float. Streamed from disk one scan row
    /// at a time and guarded by a fraction of the GPU working-set budget.
    func cubeBuffer() async throws -> MTLBuffer {
        if let cube { return cube }

        let d = descriptor
        let count = d.ry * d.rx * d.qy * d.qx
        let bytes = count * MemoryLayout<Float>.stride
        let budget = Int(MetalEngine.shared.device.recommendedMaxWorkingSetSize) / 2
        guard bytes < budget else { throw FourDError.tooLargeForGPU(bytes: bytes, budget: budget) }

        // Stream rows directly into one page-aligned allocation and hand it to
        // Metal with bytesNoCopy — avoids the previous [Float] + makeBuffer
        // copy, which doubled peak memory during load.
        let pageSize = Int(getpagesize())
        let allocBytes = (bytes + pageSize - 1) / pageSize * pageSize
        var rawOpt: UnsafeMutableRawPointer?
        guard posix_memalign(&rawOpt, pageSize, allocBytes) == 0, let raw = rawOpt else {
            throw FourDError.allocationFailed
        }
        let dst = raw.bindMemory(to: Float.self, capacity: count)
        let rowPix = d.rx * d.qy * d.qx

        do {
            for ry in 0..<d.ry {
                let row = try await reader.readScanRow(d, ry: ry)
                row.withUnsafeBufferPointer { src in
                    (dst + ry * rowPix).update(from: src.baseAddress!, count: rowPix)
                }
            }
        } catch {
            free(raw)
            throw error
        }

        guard let buffer = MetalEngine.shared.device.makeBuffer(
            bytesNoCopy: raw, length: allocBytes, options: .storageModeShared,
            deallocator: { pointer, _ in free(pointer) }
        ) else {
            free(raw)
            throw FourDError.allocationFailed
        }
        buffer.label = "4D cube (\(d.ry)x\(d.rx)x\(d.qy)x\(d.qx))"
        cube = buffer
        return buffer
    }

    /// Free the resident cube buffer (e.g. when switching datasets).
    func releaseCube() {
        cube = nil
    }

    private func key(ry: Int, rx: Int) -> Int {
        ry * descriptor.rx + rx
    }

    private func touch(_ cacheKey: Int) {
        if let index = order.firstIndex(of: cacheKey) {
            order.remove(at: index)
        }
        order.append(cacheKey)
    }

    private func insert(_ pattern: DiffractionPattern, for cacheKey: Int) {
        cache[cacheKey] = pattern
        touch(cacheKey)

        while order.count > maxCachedPatterns {
            let oldest = order.removeFirst()
            cache[oldest] = nil
        }
    }
}
