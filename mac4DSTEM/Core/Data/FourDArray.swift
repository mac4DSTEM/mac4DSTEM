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
        // A resident cube holds the whole cube as one FLAT, CONTIGUOUS copy, so
        // any scan-row range slices out correctly regardless of how the buffer
        // was filled. (An earlier version of this comment said the tile was
        // "filled from these same tiles", which is false — `makeResident` picks
        // its own fill tiling and consumers pass their own `maximumRows`. The
        // fill tiling is not load-bearing, and saying it was invited a future
        // reader to depend on it.)
        //
        // Serving from here skips the disk WITHOUT changing the CALLER's
        // tiling, so every cross-tile reduction (tiledDPStatistics' weighted
        // mean, tiledDiffraction's running sum) combines the same partials in
        // the same order and returns the same floats it would have streaming.
        // Without this, an open that preloads the cube would then read the whole
        // cube again for its first analysis pass — the longest phase of the open
        // happening twice.
        if let residentCube,
           residentCube.matches(descriptor, specification: loadSpecification) {
            return tile(yRange: yRange, from: residentCube)
        }
        let tile = try await reader.readScanTile(descriptor, yRange: yRange)
        let expected = yRange.count * descriptor.rx * descriptor.qy * descriptor.qx
        guard tile.yRange == yRange, tile.pixels.count == expected else {
            throw FourDError.allocationFailed
        }
        return tile
    }

    // MARK: - Residency

    private var residentCube: ResidentCube?
    /// What the caller has asked for. `.automatic` is the shipped default and
    /// currently resolves to streaming, because the admission threshold is not
    /// measured yet — see `ResidencyAdmission.measuredWorkingSetFraction`.
    private(set) var residencyRequest: Residency = .automatic

    /// Which view of the source this array reads. `.fullExtent` until L3's
    /// crop-on-read sets it.
    private(set) var loadSpecification: LoadSpecification = .fullExtent

    /// The resident cube, or nil when this array is streaming.
    func resident() -> ResidentCube? { residentCube }

    /// The resident cube **only if it holds exactly what `descriptor` and this
    /// array's current specification describe**.
    ///
    /// Callers on the compute side should use this rather than `resident()`:
    /// the specification is part of a buffer's identity, and two equal-sized
    /// crops at different offsets are indistinguishable by descriptor alone.
    func resident(for descriptor: DatasetDescriptor) -> ResidentCube? {
        guard let residentCube,
              residentCube.matches(descriptor, specification: loadSpecification)
        else { return nil }
        return residentCube
    }

    var isResident: Bool { residentCube != nil }

    /// Bytes currently held resident (0 when streaming).
    var residentByteCount: Int { residentCube?.byteCount ?? 0 }

    /// Bumped by anything that invalidates an in-flight preload. A preload
    /// captures it, re-checks after every suspension, and refuses to publish a
    /// buffer whose generation has moved on.
    ///
    /// **This is not theoretical.** Actors are reentrant: `makeResident`
    /// suspends at every `readScanTile`, and `releaseResident()` or
    /// `setResidencyRequest(.streamed)` run in those windows. Without the
    /// generation check the preload then re-published the cube *behind*
    /// `DatasetResidency`'s back, leaving the Performance panel reading
    /// "Streaming" while the array held gigabytes — an inversion of the exact
    /// property `DatasetResidencyTests` claims to defend. Found by adversarial
    /// review 2026-08-17; no test reached it, because every test preloaded to
    /// completion before touching anything.
    private var residencyGeneration = 0

    /// One preload at a time. Two concurrent calls both passed the `residentCube
    /// == nil` check and both allocated a full cube — on a machine where the
    /// admission rule had just decided that ONE fits. The second caller is
    /// refused rather than queued: it would allocate a buffer identical to the
    /// one already being filled.
    private var preloadInFlight = false

    func setResidencyRequest(_ mode: Residency) {
        residencyRequest = mode
        if mode == .streamed { releaseResident() }
    }

    /// Read the whole cube into one float32 buffer.
    ///
    /// Returns `false` when the cube is not admitted or cannot be allocated —
    /// **not** an error. Invariant I6: every path degrades to streaming, so a
    /// machine that cannot hold the cube still opens the file. Only cancellation
    /// and a malformed read throw.
    ///
    /// `progress` reports the fraction of scan rows actually copied. The
    /// denominator is the cube, which is known exactly, so this phase is
    /// legitimately determinate (invariant I5) — and on a multi-gigabyte cube it
    /// is the longest single phase of the whole open, so reporting it silently
    /// would reintroduce the stall L1 removed, one layer down.
    ///
    /// `maximumRows` forces the fill tiling, exactly as `maximumTileRows` does
    /// for the parity paths. **It exists because without it the fill loop's
    /// destination offset was dead code in every test that existed**: the
    /// default budget is a working-set eighth (~683 MB), so both test fixtures
    /// preloaded in a single tile, `filled` was always 0, and rewriting line
    /// `base + filled * …` to `base + 0` left all 22 harness assertions and the
    /// whole unit suite green. On a real multi-gigabyte cube the fill is a dozen
    /// tiles and that arithmetic decides whether every subsequent analysis reads
    /// the right bytes. Adversarial review, 2026-08-17.
    @discardableResult
    func makeResident(
        maximumRows: Int? = nil,
        cancellation: AnalysisCancellationToken? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> Bool {
        if let residentCube,
           residentCube.matches(descriptor, specification: loadSpecification) { return true }
        guard !preloadInFlight else { return false }
        guard ResidencyAdmission.shouldAdmit(
            residencyRequest,
            descriptor: descriptor,
            workingSetSize: MetalEngine.shared.device.recommendedMaxWorkingSetSize,
            maximumBufferLength: MetalEngine.shared.device.maxBufferLength
        ) else { return false }

        let byteCount = descriptor.byteCountAsFloat32
        let floatCount = byteCount / MemoryLayout<Float>.stride
        guard byteCount > 0, floatCount > 0,
              let buffer = MetalEngine.shared.device.makeBuffer(
                length: byteCount, options: .storageModeShared
              )
        else { return false }
        buffer.label = "Resident cube \(descriptor.fileName)"

        residentCube = nil
        residencyGeneration &+= 1
        let generation = residencyGeneration
        preloadInFlight = true
        defer { preloadInFlight = false }

        let floatsPerScanRow = descriptor.rx * descriptor.qy * descriptor.qx
        let base = buffer.contents().bindMemory(to: Float.self, capacity: floatCount)
        let rowsPerTile = max(1, min(descriptor.ry, maximumRows ?? scanTileRows()))
        var filled = 0
        while filled < descriptor.ry {
            guard cancellation?.isCancelled != true else { throw CancellationError() }
            let upper = min(descriptor.ry, filled + rowsPerTile)
            let range = filled..<upper
            let tile = try await reader.readScanTile(descriptor, yRange: range)
            // Re-checked after every suspension, not just at the end: a release
            // or a `.streamed` request that arrived while this read was in
            // flight must win, and continuing to fill a buffer nobody wants
            // wastes the memory the caller just asked us to give back.
            guard generation == residencyGeneration else { return false }
            guard tile.yRange == range,
                  tile.pixels.count == range.count * floatsPerScanRow else {
                throw FourDError.allocationFailed
            }
            tile.pixels.withUnsafeBufferPointer { source in
                guard let start = source.baseAddress else { return }
                (base + filled * floatsPerScanRow).update(from: start, count: source.count)
            }
            filled = upper
            progress?(Double(filled) / Double(descriptor.ry))
        }
        // Published only once every byte is in place AND nothing has invalidated
        // this preload: a cancelled, superseded or failed preload must leave the
        // array streaming, never holding a half-filled buffer that would compute
        // a confident wrong answer, and never resurrecting a cube the caller
        // released while the read was running.
        guard generation == residencyGeneration else { return false }
        residentCube = ResidentCube(
            buffer: buffer, descriptor: descriptor,
            specification: loadSpecification
        )
        return true
    }

    /// Drop the resident cube and return to streaming. Safe at any time — the
    /// next tiled pass simply reads from disk again, and any preload in flight
    /// is invalidated rather than allowed to re-publish afterwards.
    func releaseResident() {
        residentCube = nil
        residencyGeneration &+= 1
    }

    private func tile(yRange: Range<Int>, from cube: ResidentCube) -> FourDScanTile {
        let floatsPerScanRow = descriptor.rx * descriptor.qy * descriptor.qx
        let floatCount = cube.byteCount / MemoryLayout<Float>.stride
        let base = cube.buffer.contents().bindMemory(to: Float.self, capacity: floatCount)
        let pixels = Array(UnsafeBufferPointer(
            start: base + yRange.lowerBound * floatsPerScanRow,
            count: yRange.count * floatsPerScanRow
        ))
        return FourDScanTile(
            yRange: yRange, scanWidth: descriptor.rx,
            detectorHeight: descriptor.qy, detectorWidth: descriptor.qx,
            pixels: pixels
        )
    }

    /// Rows that fit within a conservative eighth of Metal's recommended
    /// working set. Tiled passes double-buffer (one tile processing, one
    /// prefetching), so two resident tiles at this halved per-tile budget
    /// keep total staging within the prior single-tile quarter-of-working-set
    /// bound. `maximumRows` lets parity tests force tiny tiles.
    func scanTileRows(maximumRows: Int? = nil) -> Int {
        let bytesPerRow = descriptor.rx * descriptor.qy * descriptor.qx
            * MemoryLayout<Float>.stride
        let budget = max(1, Int(MetalEngine.shared.device.recommendedMaxWorkingSetSize) / 8)
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
