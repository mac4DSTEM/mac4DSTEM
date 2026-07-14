import Foundation

// VirtualDetector's aperture overload is part of the production source set;
// this benchmark uses only its statistics/origin paths but still supplies the
// small app-layer value type required to compile that source standalone.
struct Aperture {
    var centerX: Float
    var centerY: Float
    var inner: Float
    var outer: Float
}

struct RealACOMReport: Codable {
    let file: String
    let shape: [Int]
    let braggPeakCount: Int
    let scope: String
    let matchedPositionCount: Int
    let templateCount: Int
    let reciprocalScale: Double
    let inputPreparationSeconds: Double
    let acomSetupSeconds: Double
    let cpuSeconds: Double
    let metalSeconds: Double
    let cpuEndToEndSeconds: Double
    let metalEndToEndSeconds: Double
    let cpuOpenToResultSeconds: Double
    let metalOpenToResultSeconds: Double
    let cpuPositionsPerSecond: Double
    let metalPositionsPerSecond: Double
    let cpuSpeedupOverMetal: Double
    let exactTemplateAgreement: Double
    let exactAngleAgreementAmongMatchingTemplates: Double
    let maximumScoreError: Float
    let maximumReliabilityError: Float
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

func note(_ message: String) {
    FileHandle.standardError.write(Data("[real-acom] \(message)\n".utf8))
}

@main
struct RealACOMBenchmark {
    static func main() async throws {
        let actionStart = Date()
        guard let path = CommandLine.arguments.dropFirst().first else {
            fail("usage: real-acom-benchmark data.h5")
        }
        let environment = ProcessInfo.processInfo.environment
        let templateCount = max(
            24, Int(environment["MAC4DSTEM_ACOM_TEMPLATES"] ?? "200") ?? 200
        )
        let previewDimension = max(
            4, Int(environment["MAC4DSTEM_ACOM_PREVIEW_DIMENSION"] ?? "32") ?? 32
        )

        let reader = try H5Reader(path: path)
        let descriptor = try await reader.discoverPrimaryDataset()
        let data = FourDArray(reader: reader, descriptor: descriptor)
        note("origin calibration on \(descriptor.ry)×\(descriptor.rx)×\(descriptor.qy)×\(descriptor.qx)")
        guard let originFit = try await OriginCalibration.tiledRun(
            data: data, descriptor: descriptor, fitFunction: .plane
        ) else { fail("origin calibration did not initialize") }
        guard let kernel = ProbeKernel.synthetic(
            radius: originFit.probeRadius, qy: descriptor.qy, qx: descriptor.qx
        ) else { fail("probe kernel did not initialize") }

        var parameters = DiskDetectionParams()
        let qMin = Float(min(descriptor.qx, descriptor.qy))
        parameters.minPeakSpacing = max(4, (qMin / 8).rounded())
        parameters.edgeBoundary = max(2, Int(qMin / 24))
        note("Bragg detection")
        guard let rawVectors = await DiskDetection.detectAll(
            data: data, descriptor: descriptor, kernel: kernel, params: parameters
        ) else { fail("Bragg detection did not initialize") }
        let inputPreparationSeconds = Date().timeIntervalSince(actionStart)
        let acomActionStart = Date()

        var calibration = Calibration()
        calibration.origin = originFit.origin
        guard let origin = calibration.meanOrigin else { fail("missing fitted origin") }
        let vectors = rawVectors.calibrated(with: calibration, referenceOrigin: origin)
        let crystal = Crystal.aluminum
        guard let firstShell = crystal.reflections(kMax: 2.5).first?.gLength,
              let qEstimate = KnownCrystalQCalibration.estimate(
                bragg: vectors, origin: origin,
                referenceRadiusInvAngstrom: firstShell
              ) else { fail("known-crystal Q calibration failed") }
        guard let plan = OrientationPlan.generate(
            crystal: crystal, kMax: 1.2, zoneAxisCount: templateCount
        ) else { fail("orientation plan did not initialize") }

        let useFullScope = environment["MAC4DSTEM_ACOM_SCOPE"] == "full"
        let selection: ACOMScanSelection = useFullScope
            ? .full : .preview(maxDimension: previewDimension)
        let selected = selection.sourceIndices(
            width: descriptor.rx, height: descriptor.ry
        )
        let acomSetupSeconds = Date().timeIntervalSince(acomActionStart)
        note("CPU match: \(selected.count) positions × \(plan.count) templates")
        let cpuStart = Date()
        guard let cpu = OrientationMatching.matchAll(
            bragg: vectors, plan: plan, originX: origin.x, originY: origin.y,
            invAngstromPerPixel: qEstimate.invAngstromPerPixel,
            backend: .cpu, selection: selection
        ) else { fail("CPU matching failed") }
        let cpuSeconds = Date().timeIntervalSince(cpuStart)

        note("Metal match: \(selected.count) positions × \(plan.count) templates")
        let metalStart = Date()
        guard let metal = OrientationMatching.matchAll(
            bragg: vectors, plan: plan, originX: origin.x, originY: origin.y,
            invAngstromPerPixel: qEstimate.invAngstromPerPixel,
            backend: .metal, selection: selection
        ) else { fail("Metal matching failed") }
        let metalSeconds = Date().timeIntervalSince(metalStart)

        var templateMatches = 0
        var angleMatches = 0
        var maximumScoreError: Float = 0
        var maximumReliabilityError: Float = 0
        for index in selected {
            let lhs = cpu.results[index], rhs = metal.results[index]
            maximumScoreError = max(maximumScoreError, abs(lhs.score - rhs.score))
            maximumReliabilityError = max(
                maximumReliabilityError, abs(lhs.reliability - rhs.reliability)
            )
            guard lhs.templateIndex == rhs.templateIndex else { continue }
            templateMatches += 1
            let rawAngleError = abs(lhs.inPlaneAngle - rhs.inPlaneAngle)
                .truncatingRemainder(dividingBy: .pi)
            let angleError = min(rawAngleError, .pi - rawAngleError)
            if angleError < 1e-6 { angleMatches += 1 }
        }
        let templateAgreement = Double(templateMatches) / Double(selected.count)
        let angleAgreement = templateMatches > 0
            ? Double(angleMatches) / Double(templateMatches) : 0
        guard templateAgreement >= 0.99, angleAgreement >= 0.999,
              maximumScoreError < 2e-4,
              maximumReliabilityError < 2e-4 else {
            fail(
                "CPU/Metal parity: templates \(templateAgreement), angles \(angleAgreement), "
                + "score error \(maximumScoreError), reliability error \(maximumReliabilityError)"
            )
        }

        let count = Double(selected.count)
        let report = RealACOMReport(
            file: URL(fileURLWithPath: path).lastPathComponent,
            shape: descriptor.shape,
            braggPeakCount: vectors.totalPeakCount,
            scope: useFullScope ? "full" : "preview",
            matchedPositionCount: selected.count,
            templateCount: plan.count,
            reciprocalScale: qEstimate.invAngstromPerPixel,
            inputPreparationSeconds: inputPreparationSeconds,
            acomSetupSeconds: acomSetupSeconds,
            cpuSeconds: cpuSeconds,
            metalSeconds: metalSeconds,
            cpuEndToEndSeconds: acomSetupSeconds + cpuSeconds,
            metalEndToEndSeconds: acomSetupSeconds + metalSeconds,
            cpuOpenToResultSeconds: inputPreparationSeconds + acomSetupSeconds + cpuSeconds,
            metalOpenToResultSeconds: inputPreparationSeconds + acomSetupSeconds + metalSeconds,
            cpuPositionsPerSecond: count / cpuSeconds,
            metalPositionsPerSecond: count / metalSeconds,
            cpuSpeedupOverMetal: metalSeconds / cpuSeconds,
            exactTemplateAgreement: templateAgreement,
            exactAngleAgreementAmongMatchingTemplates: angleAgreement,
            maximumScoreError: maximumScoreError,
            maximumReliabilityError: maximumReliabilityError
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(report))
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
