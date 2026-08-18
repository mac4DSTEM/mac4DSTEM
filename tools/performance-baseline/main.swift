import Foundation
import Darwin
import Metal

// VirtualDetector.swift normally receives this UI value type from AppState.
struct Aperture {
    var centerX: Float
    var centerY: Float
    var inner: Float
    var outer: Float
}

actor SyntheticDataSource: FourDDataSource {
    let descriptor: DatasetDescriptor
    let cube: [Float]

    init(descriptor: DatasetDescriptor, cube: [Float]) {
        self.descriptor = descriptor
        self.cube = cube
    }

    func discoverPrimaryDataset() throws -> DatasetDescriptor { descriptor }

    nonisolated func loadPushdown(for view: LoadView) -> LoadPushdown { .none }

    func readPattern(_ view: LoadView, ry: Int, rx: Int) throws -> [Float] {
        view.pattern(fromFullCube: cube, ry: ry, rx: rx)
    }

    func readScanRow(_ view: LoadView, ry: Int) throws -> [Float] {
        view.scanRow(fromFullCube: cube, ry: ry)
    }

    func readScanTile(
        _ view: LoadView, yRange: Range<Int>
    ) throws -> FourDScanTile {
        view.scanTile(fromFullCube: cube, yRange: yRange)
    }

    func readDoubleAttribute(_ name: String, onObjectPath path: String) -> Double? { nil }
    func pixelCalibration() -> PixelCalibration? { nil }
}

struct Observation {
    let milliseconds: Double
    let checksum: Double
    let residentBytes: Int
}

struct BenchmarkReport {
    let backend: String
    let workload: [String: Any]
    let estimatedWorkingBytes: Int
    let observations: [Observation]

    var json: [String: Any] {
        let ordered = observations.map(\.milliseconds).sorted()
        let median = ordered[ordered.count / 2]
        return [
            "backend": backend,
            "workload": workload,
            "estimated_working_bytes": estimatedWorkingBytes,
            "resident_bytes_observed_max": observations.map(\.residentBytes).max() ?? 0,
            "samples_ms": observations.map(\.milliseconds),
            "median_ms": median,
            "minimum_ms": ordered.first ?? 0,
            "maximum_ms": ordered.last ?? 0,
            "checksum": observations.last?.checksum ?? 0,
        ]
    }
}

func residentBytes() -> Int {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(
        MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size
    )
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? Int(info.resident_size) : 0
}

func timed(_ body: () throws -> Double) rethrows -> Observation {
    let start = DispatchTime.now().uptimeNanoseconds
    let checksum = try body()
    let end = DispatchTime.now().uptimeNanoseconds
    return Observation(
        milliseconds: Double(end - start) / 1_000_000,
        checksum: checksum,
        residentBytes: residentBytes()
    )
}

func timed(_ body: () async throws -> Double) async rethrows -> Observation {
    let start = DispatchTime.now().uptimeNanoseconds
    let checksum = try await body()
    let end = DispatchTime.now().uptimeNanoseconds
    return Observation(
        milliseconds: Double(end - start) / 1_000_000,
        checksum: checksum,
        residentBytes: residentBytes()
    )
}

func measure(
    backend: String,
    workload: [String: Any],
    estimatedWorkingBytes: Int,
    repeats: Int,
    warmups: Int,
    body: () throws -> Double
) rethrows -> BenchmarkReport {
    for _ in 0..<warmups { _ = try body() }
    return try BenchmarkReport(
        backend: backend,
        workload: workload,
        estimatedWorkingBytes: estimatedWorkingBytes,
        observations: (0..<repeats).map { _ in try timed(body) }
    )
}

func measure(
    backend: String,
    workload: [String: Any],
    estimatedWorkingBytes: Int,
    repeats: Int,
    warmups: Int,
    body: () async throws -> Double
) async rethrows -> BenchmarkReport {
    for _ in 0..<warmups { _ = try await body() }
    var observations: [Observation] = []
    for _ in 0..<repeats { observations.append(try await timed(body)) }
    return BenchmarkReport(
        backend: backend,
        workload: workload,
        estimatedWorkingBytes: estimatedWorkingBytes,
        observations: observations
    )
}

func fftBenchmark(
    width: Int, height: Int, roundTrips: Int, repeats: Int, warmups: Int
) -> BenchmarkReport {
    guard let fft = FFT2D(nx: width, ny: height) else { fatalError("FFT setup failed") }
    var real = (0..<(width * height)).map { sin(Float($0) * 0.017) }
    var imaginary = [Float](repeating: 0, count: real.count)
    return measure(
        backend: "Accelerate/vDSP",
        workload: ["width": width, "height": height, "round_trips": roundTrips],
        estimatedWorkingBytes: real.count * MemoryLayout<Float>.stride * 4,
        repeats: repeats,
        warmups: warmups
    ) {
        for _ in 0..<roundTrips {
            fft.transform(re: &real, im: &imaginary, forward: true)
            fft.transform(re: &real, im: &imaginary, forward: false)
        }
        return Double(real.prefix(32).reduce(0, +))
    }
}

func diskDetectionBenchmark(
    sigma: Float, repeats: Int, warmups: Int
) -> BenchmarkReport {
    let qy = 128, qx = 128, patternCount = 24
    guard let kernel = ProbeKernel.synthetic(radius: 8, qy: qy, qx: qx),
          let detector = DiskDetector(kernel: kernel) else {
        fatalError("Disk detector setup failed")
    }
    let patterns = (0..<patternCount).map { patternIndex -> [Float] in
        var pattern = [Float](repeating: 0, count: qy * qx)
        let centers = [(32 + patternIndex % 3, 35), (64, 64), (92, 88 - patternIndex % 4)]
        for y in 0..<qy {
            for x in 0..<qx {
                var value: Float = 0.02 + 0.0001 * Float(x + y)
                for (cx, cy) in centers {
                    let dx = Float(x - cx), dy = Float(y - cy)
                    value += 5 * exp(-(dx * dx + dy * dy) / 72)
                }
                pattern[y * qx + x] = value
            }
        }
        return pattern
    }
    var params = DiskDetectionParams()
    params.sigmaCC = sigma
    params.subpixel = .poly
    params.minPeakSpacing = 10
    params.edgeBoundary = 4
    params.maxNumPeaks = 32
    let gridBytes = qy * qx * MemoryLayout<Float>.stride
    return measure(
        backend: "Accelerate/vDSP + CPU maxima",
        workload: [
            "patterns": patternCount, "qy": qy, "qx": qx,
            "sigma_cc": sigma, "subpixel": "poly",
        ],
        estimatedWorkingBytes: gridBytes * (10 + patternCount),
        repeats: repeats,
        warmups: warmups
    ) {
        var checksum: Double = 0
        for pattern in patterns {
            let peaks = detector.detect(pattern: pattern, params: params)
            checksum += Double(peaks.count)
            checksum += peaks.prefix(4).reduce(0) { $0 + Double($1.x + $1.y + $1.intensity) }
        }
        return checksum
    }
}

func syntheticCube(descriptor: DatasetDescriptor) -> [Float] {
    let detectorCount = descriptor.qy * descriptor.qx
    let scanCount = descriptor.ry * descriptor.rx
    return (0..<(scanCount * detectorCount)).map { index in
        let scan = index / detectorCount
        let q = index % detectorCount
        return 0.5 + 0.25 * sin(Float(q) * 0.013) + Float(scan % 17) * 0.002
    }
}

func selectedDiffractionBenchmark(
    descriptor: DatasetDescriptor,
    cube: [Float],
    repeats: Int,
    warmups: Int
) throws -> BenchmarkReport {
    guard let buffer = MetalEngine.shared.device.makeBuffer(
        bytes: cube,
        length: cube.count * MemoryLayout<Float>.stride,
        options: .storageModeShared
    ) else { fatalError("Metal cube allocation failed") }
    let region = DetectorShape.rectangle(
        xMin: descriptor.rx / 4, xMax: descriptor.rx * 3 / 4,
        yMin: descriptor.ry / 4, yMax: descriptor.ry * 3 / 4
    )
    return try measure(
        backend: "Metal/\(MetalEngine.shared.device.name)",
        workload: [
            "ry": descriptor.ry, "rx": descriptor.rx,
            "qy": descriptor.qy, "qx": descriptor.qx,
            "selected_scan_positions": descriptor.ry / 2 * (descriptor.rx / 2),
        ],
        estimatedWorkingBytes: descriptor.byteCountAsFloat32
            + (descriptor.ry * descriptor.rx + descriptor.qy * descriptor.qx) * 4,
        repeats: repeats,
        warmups: warmups
    ) {
        let result = try VirtualDetector.diffraction(
            cube: buffer, descriptor: descriptor, region: region
        )
        return Double(result.pixels.reduce(0, +))
    }
}

func tileStagingBenchmark(
    descriptor: DatasetDescriptor,
    cube: [Float],
    repeats: Int,
    warmups: Int
) async throws -> BenchmarkReport {
    let tileRows = 4
    let bytesPerTile = tileRows * descriptor.rx * descriptor.qy * descriptor.qx * 4
    return try await measure(
        backend: "FourDArray + Float32 source staging",
        workload: [
            "ry": descriptor.ry, "rx": descriptor.rx,
            "qy": descriptor.qy, "qx": descriptor.qx,
            "tile_rows": tileRows,
        ],
        estimatedWorkingBytes: descriptor.byteCountAsFloat32 + bytesPerTile,
        repeats: repeats,
        warmups: warmups
    ) {
        let source = SyntheticDataSource(descriptor: descriptor, cube: cube)
        let data = FourDArray(reader: source, descriptor: descriptor)
        var checksum: Double = 0
        for lower in stride(from: 0, to: descriptor.ry, by: tileRows) {
            let tile = try await data.scanTile(
                yRange: lower..<min(descriptor.ry, lower + tileRows)
            )
            checksum += Double(tile.pixels.prefix(32).reduce(0, +))
        }
        return checksum
    }
}

func ptychographyInput(
    scanHeight: Int = 8,
    scanWidth: Int = 8,
    detectorHeight: Int = 32,
    detectorWidth: Int = 32,
    objectHeight: Int = 64,
    objectWidth: Int = 64,
    positionStep: Int = 5
) -> SingleslicePtychographyInput {
    let probeCount = detectorHeight * detectorWidth
    let positions = (0..<(scanHeight * scanWidth)).map { index in
        PtychographyPosition(
            row: Float(12 + (index / scanWidth) * positionStep),
            column: Float(12 + (index % scanWidth) * positionStep)
        )
    }
    var probe = [Float](repeating: 0, count: probeCount)
    for row in 0..<detectorHeight {
        for column in 0..<detectorWidth {
            let dr = Float(row - detectorHeight / 2)
            let dc = Float(column - detectorWidth / 2)
            probe[row * detectorWidth + column] = exp(-(dr * dr + dc * dc) / 64)
        }
    }
    return SingleslicePtychographyInput(
        scanHeight: scanHeight,
        scanWidth: scanWidth,
        detectorHeight: detectorHeight,
        detectorWidth: detectorWidth,
        amplitudes: [Float](repeating: 1, count: scanHeight * scanWidth * probeCount),
        positions: positions,
        objectSamplingRowAngstrom: 0.5,
        objectSamplingColumnAngstrom: 0.5,
        initialObject: PtychographyComplexArray(
            width: objectWidth,
            height: objectHeight,
            real: [Float](repeating: 1, count: objectWidth * objectHeight),
            imaginary: [Float](repeating: 0, count: objectWidth * objectHeight)
        ),
        initialProbe: PtychographyComplexArray(
            width: detectorWidth,
            height: detectorHeight,
            real: probe,
            imaginary: [Float](repeating: 0, count: probeCount)
        )
    )
}

func ptychographyBenchmark(
    method: SingleslicePtychographyMethod,
    input: SingleslicePtychographyInput = ptychographyInput(),
    iterations: Int = 5,
    repeats: Int,
    warmups: Int
) throws -> BenchmarkReport {
    var options = SingleslicePtychographyOptions()
    options.method = method
    options.iterations = iterations
    options.normalizationMinimum = 0.1
    let patternCount = input.scanHeight * input.scanWidth
    let probeCount = input.detectorHeight * input.detectorWidth
    let objectCount = input.initialObject.width * input.initialObject.height
    var estimatedFloats = input.amplitudes.count + objectCount * 7 + probeCount * 12
    estimatedFloats += patternCount
        * (input.detectorHeight + input.detectorWidth) * 2
    if method == .differenceMapAlternatingProjections {
        estimatedFloats += input.amplitudes.count * 2
    }
    return try measure(
        backend: "Accelerate/vDSP + scalar CPU updates",
        workload: [
            "method": method.provenanceName,
            "scan_positions": patternCount,
            "detector_height": input.detectorHeight,
            "detector_width": input.detectorWidth,
            "object_height": input.initialObject.height,
            "object_width": input.initialObject.width,
            "iterations": options.iterations,
        ],
        estimatedWorkingBytes: estimatedFloats * MemoryLayout<Float>.stride,
        repeats: repeats,
        warmups: warmups
    ) {
        let result = try SingleslicePtychography.reconstruct(input: input, options: options)
        return Double(result.errorHistory.reduce(0, +))
            + Double(result.object.real.prefix(32).reduce(0, +))
    }
}

func acomPlanBenchmark(repeats: Int, warmups: Int) -> BenchmarkReport {
    measure(
        backend: "Accelerate/vDSP + CPU template generation",
        workload: [
            "templates": 400, "radial_bins": 32, "azimuthal_bins": 128,
            "crystal": "Au FCC", "k_max": 1.2,
        ],
        estimatedWorkingBytes: 400 * 32 * 128 * 3 * MemoryLayout<Float>.stride,
        repeats: repeats,
        warmups: warmups
    ) {
        guard let plan = OrientationPlan.generate(
            crystal: .gold, kMax: 1.2, zoneAxisCount: 400
        ) else { fatalError("ACOM plan generation failed") }
        return Double(plan.count)
            + plan.zoneAxes.prefix(8).reduce(0) { $0 + $1.x + $1.y + $1.z }
    }
}

func syntheticACOMVectors(
    plan: OrientationPlan, crystal: Crystal,
    width: Int, height: Int,
    originX: Float = 64, originY: Float = 64,
    invAngstromPerPixel: Double = 0.01
) -> BraggVectors {
    let reflections = crystal.reflections(kMax: 1.2)
    let peaks = (0..<(width * height)).map { index -> [BraggPeak] in
        let templateIndex = (index * 37 + index / max(1, width)) % plan.count
        let angle = Double((index * 11) % 64) / 64 * Double.pi
        return OrientationPlan.project(
            reflections: reflections,
            zoneAxis: plan.zoneAxes[templateIndex],
            sgWidth: 0.03, sgMax: 0.1
        ).map { spot in
            let azimuth = spot.azim + angle
            let radius = spot.r / invAngstromPerPixel
            return BraggPeak(
                x: originX + Float(radius * cos(azimuth)),
                y: originY + Float(radius * sin(azimuth)),
                intensity: Float(spot.weight)
            )
        }
    }
    return BraggVectors(scanWidth: width, scanHeight: height, peaks: peaks)
}

func acomMatchBenchmark(
    plan: OrientationPlan, vectors: BraggVectors,
    backend: ACOMMatchingBackend,
    repeats: Int, warmups: Int
) -> BenchmarkReport {
    let templateFloats = plan.count * plan.geometry.nRadial * plan.geometry.nAzimuthal * 3
    return measure(
        backend: backend.rawValue,
        workload: [
            "scan_width": vectors.scanWidth,
            "scan_height": vectors.scanHeight,
            "scan_positions": vectors.scanWidth * vectors.scanHeight,
            "templates": plan.count,
            "radial_bins": plan.geometry.nRadial,
            "azimuthal_bins": plan.geometry.nAzimuthal,
        ],
        estimatedWorkingBytes: templateFloats * MemoryLayout<Float>.stride,
        repeats: repeats,
        warmups: warmups
    ) {
        guard let map = OrientationMatching.matchAll(
            bragg: vectors, plan: plan,
            originX: 64, originY: 64,
            invAngstromPerPixel: 0.01,
            backend: backend
        ) else { fatalError("ACOM matching failed") }
        return map.results.enumerated().reduce(0) { partial, item in
            partial + Double(item.element.templateIndex + 1) * Double(item.offset + 1)
                + Double(item.element.inPlaneAngle) * 0.01
                + Double(item.element.score) * 0.001
                + Double(item.element.reliability) * 0.0001
        }
    }
}

@main
struct Baseline {
    static func main() async throws {
        let environment = ProcessInfo.processInfo.environment
        let repeats = max(1, Int(environment["MAC4DSTEM_BENCHMARK_REPEATS"] ?? "3") ?? 3)
        let warmups = max(0, Int(environment["MAC4DSTEM_BENCHMARK_WARMUPS"] ?? "1") ?? 1)

        let descriptor = DatasetDescriptor(
            filePath: "synthetic",
            datasetPath: "/synthetic",
            shape: [24, 24, 96, 96],
            dtypeDescription: "float32",
            chunkShape: [4, 24, 96, 96]
        )
        let cube = syntheticCube(descriptor: descriptor)
        let mediumPtychography = ptychographyInput(
            scanHeight: 12, scanWidth: 12,
            detectorHeight: 48, detectorWidth: 48,
            objectHeight: 96, objectWidth: 96,
            positionStep: 5
        )
        guard let acomPlan = OrientationPlan.generate(
            crystal: .gold, kMax: 1.2, zoneAxisCount: 400
        ) else { fatalError("ACOM benchmark plan failed") }
        let acomSmall = syntheticACOMVectors(
            plan: acomPlan, crystal: .gold, width: 4, height: 3
        )
        let acomMedium = syntheticACOMVectors(
            plan: acomPlan, crystal: .gold, width: 8, height: 6
        )

        let reports: [(String, BenchmarkReport)] = [
            ("fft_radix2", fftBenchmark(
                width: 256, height: 256, roundTrips: 20,
                repeats: repeats, warmups: warmups
            )),
            ("fft_exact_shape", fftBenchmark(
                width: 96, height: 80, roundTrips: 5,
                repeats: repeats, warmups: warmups
            )),
            ("disk_correlation", diskDetectionBenchmark(
                sigma: 0, repeats: repeats, warmups: warmups
            )),
            ("disk_detection", diskDetectionBenchmark(
                sigma: 2, repeats: repeats, warmups: warmups
            )),
            ("selected_area_diffraction", try selectedDiffractionBenchmark(
                descriptor: descriptor, cube: cube, repeats: repeats, warmups: warmups
            )),
            ("tile_staging", try await tileStagingBenchmark(
                descriptor: descriptor, cube: cube, repeats: repeats, warmups: warmups
            )),
            ("ptychography_gradient_descent", try ptychographyBenchmark(
                method: .gradientDescent, repeats: repeats, warmups: warmups
            )),
            ("ptychography_dm_ap", try ptychographyBenchmark(
                method: .differenceMapAlternatingProjections,
                repeats: repeats, warmups: warmups
            )),
            ("ptychography_gradient_descent_medium", try ptychographyBenchmark(
                method: .gradientDescent,
                input: mediumPtychography, iterations: 3,
                repeats: repeats, warmups: warmups
            )),
            ("ptychography_dm_ap_medium", try ptychographyBenchmark(
                method: .differenceMapAlternatingProjections,
                input: mediumPtychography, iterations: 3,
                repeats: repeats, warmups: warmups
            )),
            ("acom_plan_generation", acomPlanBenchmark(
                repeats: repeats, warmups: warmups
            )),
            ("acom_matching_small", acomMatchBenchmark(
                plan: acomPlan, vectors: acomSmall,
                backend: .cpu,
                repeats: repeats, warmups: warmups
            )),
            ("acom_matching_medium_cpu", acomMatchBenchmark(
                plan: acomPlan, vectors: acomMedium,
                backend: .cpu,
                repeats: repeats, warmups: warmups
            )),
            ("acom_matching_medium_metal", acomMatchBenchmark(
                plan: acomPlan, vectors: acomMedium,
                backend: .metal,
                repeats: repeats, warmups: warmups
            )),
        ]

        let report: [String: Any] = [
            "schema": 2,
            "recorded_at": ISO8601DateFormatter().string(from: Date()),
            "machine": Host.current().localizedName ?? "unknown",
            "processor_count": ProcessInfo.processInfo.processorCount,
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "metal_device": MetalEngine.shared.device.name,
            "configuration": ["repeats": repeats, "warmups": warmups],
            "benchmarks": Dictionary(uniqueKeysWithValues: reports.map { ($0.0, $0.1.json) }),
        ]
        let data = try JSONSerialization.data(
            withJSONObject: report, options: [.prettyPrinted, .sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
