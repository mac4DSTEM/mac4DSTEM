import Foundation

actor FourDArray {
    private let reader: H5Reader
    let descriptor: DatasetDescriptor

    private var cache: [Int: DiffractionPattern] = [:]
    private var order: [Int] = []
    private let maxCachedPatterns = 96

    init(reader: H5Reader, descriptor: DatasetDescriptor) {
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
