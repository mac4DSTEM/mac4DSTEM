import Foundation
import Metal

enum FourDError: LocalizedError {
    case allocationFailed

    var errorDescription: String? {
        switch self {
        case .allocationFailed:
            return "Could not allocate or read the requested 4D-STEM tile."
        }
    }
}

actor FourDArray {
    private let reader: any FourDDataSource
    let descriptor: DatasetDescriptor

    private var cache: [Int: DiffractionPattern] = [:]
    private var order: [Int] = []
    private let maxCachedPatterns = 96

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

    func scanTile(yRange: Range<Int>) async throws -> FourDScanTile {
        guard yRange.lowerBound >= 0, yRange.upperBound <= descriptor.ry,
              !yRange.isEmpty else {
            throw FourDError.allocationFailed
        }
        let tile = try await reader.readScanTile(descriptor, yRange: yRange)
        let expected = yRange.count * descriptor.rx * descriptor.qy * descriptor.qx
        guard tile.yRange == yRange, tile.pixels.count == expected else {
            throw FourDError.allocationFailed
        }
        return tile
    }

    /// Rows that fit within a conservative quarter of Metal's recommended
    /// working set. `maximumRows` lets parity tests force tiny tiles.
    func scanTileRows(maximumRows: Int? = nil) -> Int {
        let bytesPerRow = descriptor.rx * descriptor.qy * descriptor.qx
            * MemoryLayout<Float>.stride
        let budget = max(1, Int(MetalEngine.shared.device.recommendedMaxWorkingSetSize) / 4)
        let budgetRows = max(1, budget / max(1, bytesPerRow))
        return max(1, min(descriptor.ry, maximumRows ?? budgetRows))
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
