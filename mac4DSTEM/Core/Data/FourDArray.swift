import Foundation
import Metal

package enum FourDError: LocalizedError {
    case allocationFailed

    package var errorDescription: String? {
        switch self {
        case .allocationFailed:
            return "Could not allocate or read the requested 4D-STEM tile."
        }
    }
}

package actor FourDArray {
    private let reader: any FourDDataSource
    /// The source, the specification, and the descriptor derived from both.
    /// Passed to the reader as one value so the three can never disagree.
    package let view: LoadView
    /// What is being processed — the view's shape, which is the source's shape
    /// when no specification is set.
    package let descriptor: DatasetDescriptor
    /// What the reader pushed into its own I/O versus applied in memory, for
    /// *this* view. Carried here so L6 can record it rather than assume it, and
    /// resolved per view because for HDF5 the answer depends on the dataset's
    /// chunking, not only on the format.
    package let loadPushdown: LoadPushdown

    private var cache: [Int: DiffractionPattern] = [:]
    private var order: [Int] = []
    private let maxCachedPatterns = 96

    package init(reader: any FourDDataSource, view: LoadView) {
        self.reader = reader
        self.view = view
        self.descriptor = view.descriptor
        self.loadPushdown = reader.loadPushdown(for: view)
    }

    /// The whole dataset. The shipped path — nothing sets a specification until
    /// L5's configurator, and a crop must not reach the compute path before the
    /// calibration re-reference is proven (docs/load-pipeline-plan.md §6, L3).
    package init(reader: any FourDDataSource, descriptor: DatasetDescriptor) {
        self.init(reader: reader, view: LoadView(fullExtentOf: descriptor))
    }

    package func pattern(ry: Int, rx: Int) async throws -> DiffractionPattern {
        let clampedY = min(max(ry, 0), max(descriptor.ry - 1, 0))
        let clampedX = min(max(rx, 0), max(descriptor.rx - 1, 0))
        let cacheKey = key(ry: clampedY, rx: clampedX)

        if let cached = cache[cacheKey] {
            touch(cacheKey)
            return cached
        }

        // A resident cube holds every pattern already, so browsing diffraction
        // patterns has no reason to go back to disk — before v2 S18 it always
        // did, which made the Performance panel's "Resident" an over-promise:
        // the indicator said memory while scan navigation stayed disk-bound.
        //
        // Not cached: the slice is a ~qy*qx memcpy out of memory we are already
        // holding, so caching it would duplicate up to `maxCachedPatterns`
        // patterns of the resident cube for no saved I/O. Patterns cached
        // BEFORE the cube went resident are still served above — same bytes,
        // since both come from the same view of the same reader.
        if let residentCube,
           residentCube.matches(descriptor, specification: loadSpecification),
           let pattern = self.pattern(ry: clampedY, rx: clampedX, from: residentCube) {
            return pattern
        }

        let pixels = try await reader.readPattern(view, ry: clampedY, rx: clampedX)
        let pattern = DiffractionPattern(qy: descriptor.qy, qx: descriptor.qx, pixels: pixels)
        insert(pattern, for: cacheKey)
        return pattern
    }

    package func clearCache() {
        cache.removeAll(keepingCapacity: true)
        order.removeAll(keepingCapacity: true)
    }

    package func scanTile(yRange: Range<Int>) async throws -> FourDScanTile {
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
        let tile = try await reader.readScanTile(view, yRange: yRange)
        let expected = yRange.count * descriptor.rx * descriptor.qy * descriptor.qx
        guard tile.yRange == yRange, tile.pixels.count == expected else {
            throw FourDError.allocationFailed
        }
        return tile
    }

    // MARK: - Residency

    private var residentCube: ResidentCube?
    /// What the caller has asked for. `.streamed` is the shipped default —
    /// `.automatic` was dropped for v2 (owner decision 2026-08-18); see the
    /// `Residency` enum. Holding a cube takes an explicit `.resident`
    /// request. // v2 S3
    package private(set) var residencyRequest: Residency = .streamed

    /// Which view of the source this array reads. `.fullExtent` unless this
    /// array was built from a cropped `LoadView`.
    package var loadSpecification: LoadSpecification { view.specification }

    /// The resident cube, or nil when this array is streaming.
    package func resident() -> ResidentCube? { residentCube }

    /// The resident cube **only if `descriptor` is what this array is loaded
    /// as**. Callers on the compute side should use this rather than
    /// `resident()`.
    ///
    /// What it catches: a caller asking with a descriptor that is not this
    /// array's view — a stale one from a previous dataset, or a synthetic one
    /// built for a sub-range (`VirtualDetector.tiled` builds those).
    ///
    /// **What it does not catch, and does not need to:** two different crops of
    /// the same file at the same shape. A `LoadView` is fixed for an array's
    /// lifetime — changing the specification *reopens* (docs/v2-scope.md §6.1),
    /// which builds a new array holding a new buffer — so one array can never
    /// hold a buffer for a crop other than its own. The specification comparison
    /// inside `ResidentCube.matches` is therefore defence in depth against a
    /// future stage that makes the view mutable, not a live guard here; saying
    /// otherwise would claim a protection that is not running.
    package func resident(for descriptor: DatasetDescriptor) -> ResidentCube? {
        guard describesThisView(descriptor), let residentCube,
              residentCube.matches(view.descriptor, specification: view.specification)
        else { return nil }
        return residentCube
    }

    /// Value equality against this array's view descriptor, **ignoring
    /// `DatasetDescriptor.id`**: descriptors are re-derived and round-tripped
    /// through sidecars, so comparing the UUID would refuse the fast path for a
    /// descriptor that describes exactly this view — a silent fallback to
    /// streaming, which is the failure mode that shows up as "residency does
    /// nothing" rather than as an error.
    private func describesThisView(_ other: DatasetDescriptor) -> Bool {
        other.filePath == view.descriptor.filePath
            && other.datasetPath == view.descriptor.datasetPath
            && other.shape == view.descriptor.shape
    }

    package var isResident: Bool { residentCube != nil }

    /// Bytes currently held resident (0 when streaming).
    package var residentByteCount: Int { residentCube?.byteCount ?? 0 }

    /// How many tiles have been COPIED out of the resident cube into a Swift
    /// `[Float]` by `scanTile`.
    ///
    /// Observability, not policy. v2 S18 removed that copy from the four tiled
    /// GPU reducers — they bind the cube's buffer at the tile's byte offset
    /// instead (`TileGPUSource`).
    ///
    /// **This counter does NOT prove the copy is gone, and an earlier version of
    /// this comment said it did** (corrected 2026-08-28 by the Gate B second
    /// read, which demonstrated it). Reinstate a staging copy *inside*
    /// `TileGPUSource.binding` — copy the tile's bytes into a fresh
    /// `MTLBuffer`, return it at offset 0 — and every value stays bit-identical
    /// while this counter reads 0 before and 0 after, because that copy never
    /// routes through `tile(yRange:from:)` where the counter lives. What
    /// actually catches it is the `bound.buffer === cube.buffer` identity
    /// assertion in `tools/virtual-detector-residency`, which fires
    /// "TileGPUSource staged a COPY". This counter catches the narrower case:
    /// a reducer going back through `tile(yRange:from:)`.
    ///
    /// (The counter's own positive control is real — deleting the increment
    /// below fails the harness with "The counter is dead, and every 'zero
    /// staging copies' claim below it is vacuous.")
    ///
    /// CPU-side consumers (parallax preprocessing, ptychography preparation,
    /// the EMD writer) legitimately still copy and still increment it.
    package private(set) var residentTileCopies = 0

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

    package func setResidencyRequest(_ mode: Residency) {
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
    package func makeResident(
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
            let tile = try await reader.readScanTile(view, yRange: range)
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
    package func releaseResident() {
        residentCube = nil
        residencyGeneration &+= 1
    }

    /// One pattern sliced out of the resident cube.
    ///
    /// The cube is flat and contiguous in `[ry][rx][qy][qx]` order, so a single
    /// pattern is one contiguous `qy * qx` run at
    /// `(ry * descriptor.rx + rx) * qy * qx` — the VIEW's scan width, which is
    /// the stride `makeResident` fills at, NOT the source's. Returns nil rather than trapping if the
    /// slice does not fit the buffer — the caller then falls back to the
    /// reader, which is the honest behaviour for a cube that is not what this
    /// array thinks it is.
    private func pattern(ry: Int, rx: Int, from cube: ResidentCube) -> DiffractionPattern? {
        let patternFloats = descriptor.qy * descriptor.qx
        let start = (ry * descriptor.rx + rx) * patternFloats
        let floatCount = cube.byteCount / MemoryLayout<Float>.stride
        guard patternFloats > 0, start >= 0, start + patternFloats <= floatCount else {
            return nil
        }
        let base = cube.buffer.contents().bindMemory(to: Float.self, capacity: floatCount)
        let pixels = Array(UnsafeBufferPointer(start: base + start, count: patternFloats))
        return DiffractionPattern(qy: descriptor.qy, qx: descriptor.qx, pixels: pixels)
    }

    private func tile(yRange: Range<Int>, from cube: ResidentCube) -> FourDScanTile {
        residentTileCopies += 1
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
    package func scanTileRows(maximumRows: Int? = nil) -> Int {
        let bytesPerRow = descriptor.rx * descriptor.qy * descriptor.qx
            * MemoryLayout<Float>.stride
        // TWO bounds, and the host one was missing until v2 S9a.
        //
        // The GPU hint is `recommendedMaxWorkingSetSize`, which on Apple
        // Silicon is ~65% of PHYSICAL RAM — so dividing it by 8 sized a tile
        // from the GPU's view of the machine and never from the host's. The
        // tiled pass holds up to three of these at peak (current tile,
        // prefetched next, and the streaming path's staged copy), which put
        // ~2.0 GB transient on an 8 GB machine on a path that legitimately
        // claims to stream. That is the mis-scaling the 8 GB death entry
        // predicted; it is NOT a diagnosis of that death, which is S9b's.
        //
        // The host bound is deliberately PHYSICAL memory, not free memory,
        // and that is a decision rather than an oversight (owner, 2026-08-28).
        // Tile size determines how float partials are grouped, and the four
        // tiled reducers are order-dependent in their low bits — the Gate B
        // second read measured 8.5231 against 8.5035 on a single grouping
        // change. Sizing tiles from FREE memory would make those bits depend
        // on how much RAM happened to be free, so the same data could give
        // different numbers on two runs. Physical memory is a machine
        // constant, so results stay reproducible per machine.
        //
        // Free memory is therefore consulted only to REFUSE, never to resize.
        //
        // physical/24 holds the three-tile peak near 12% of RAM: 341 MB per
        // tile on 8 GB, 683 MB on 16 GB. It binds below the GPU hint on every
        // Apple Silicon configuration, which is the point — the hint was never
        // a statement about what the host can spare.
        let gpuBudget = max(1, Int(MetalEngine.shared.device.recommendedMaxWorkingSetSize) / 8)
        let hostBudget = max(1, Int(ProcessInfo.processInfo.physicalMemory) / 24)
        let budget = min(gpuBudget, hostBudget)
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
