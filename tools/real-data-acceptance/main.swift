import Foundation

struct Aperture {
    var centerX: Float
    var centerY: Float
    var inner: Float
    var outer: Float
}

struct AcceptanceReport: Codable {
    let file: String
    let datasetPath: String
    let shape: [Int]
    let dtype: String
    let finitePatternFraction: Double
    let diskProbeRadiusPixels: Float
    let diskSampleCandidateCounts: [Int]
    let diskSampleAfterAbsoluteCounts: [Int]
    let diskSampleAfterRelativeCounts: [Int]
    let diskSampleAfterSpacingCounts: [Int]
    let diskSamplePeakCounts: [Int]
    let virtualImageMinimum: Float
    let virtualImageMaximum: Float
    let virtualImageMean: Double
    let virtualImageChecksum: Double
    let elapsedSeconds: Double
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8)); exit(1)
}

@main struct RealDataAcceptance {
    static func main() async throws {
        guard CommandLine.arguments.count > 1 else { fail("usage: harness data.h5 ...") }
        var reports: [AcceptanceReport] = []
        for path in CommandLine.arguments.dropFirst() {
            let start = Date()
            let reader = try H5Reader(path: path)
            let descriptor = try await reader.discoverPrimaryDataset()
            guard descriptor.ry > 0, descriptor.rx > 0, descriptor.qy > 0, descriptor.qx > 0 else {
                fail("\(path): empty discovered dimensions")
            }
            let positions = [
                (0, 0), (descriptor.ry / 2, descriptor.rx / 2),
                (descriptor.ry - 1, descriptor.rx - 1),
            ]
            var finite = 0, sampled = 0
            var sampledPatterns: [[Float]] = []
            for (y, x) in positions {
                let pattern = try await reader.readPattern(LoadView(fullExtentOf: descriptor), ry: y, rx: x)
                guard pattern.count == descriptor.qy * descriptor.qx else {
                    fail("\(path): short pattern at \(x),\(y)")
                }
                finite += pattern.filter(\.isFinite).count
                sampled += pattern.count
                sampledPatterns.append(pattern)
            }
            let finiteFraction = Double(finite) / Double(sampled)
            guard finiteFraction >= 0.999 else { fail("\(path): finite fraction \(finiteFraction)") }

            var sampledMaximum = [Float](
                repeating: -.greatestFiniteMagnitude,
                count: descriptor.qy * descriptor.qx
            )
            for pattern in sampledPatterns {
                for index in pattern.indices {
                    sampledMaximum[index] = max(sampledMaximum[index], pattern[index])
                }
            }
            let probe = OriginCalibration.probeSize(
                dp: sampledMaximum, qy: descriptor.qy, qx: descriptor.qx
            )
            guard probe.r.isFinite, probe.r > 0,
                  let kernel = ProbeKernel.synthetic(
                    radius: probe.r, qy: descriptor.qy, qx: descriptor.qx
                  ),
                  let detector = DiskDetector(kernel: kernel) else {
                fail("\(path): sampled-pattern probe/detector initialization failed")
            }
            let diskParameters = DiskDetectionParams.detectorAdapted(
                qy: descriptor.qy, qx: descriptor.qx
            )
            let diskErrors = diskParameters.validationIssues(
                in: DiskDetectionContext(
                    qy: descriptor.qy, qx: descriptor.qx,
                    probeRadius: probe.r
                )
            ).filter { $0.severity == .error }
            guard diskErrors.isEmpty else {
                fail("\(path): adapted disk configuration invalid: \(diskErrors)")
            }
            let diskResults = sampledPatterns.map {
                detector.detectWithDiagnostics(pattern: $0, params: diskParameters)
            }
            guard diskResults.allSatisfy({
                $0.diagnostics.correlationMaximum.isFinite
                    && $0.diagnostics.localMaximumCount >= $0.peaks.count
            }) else {
                fail("\(path): disk diagnostics are non-finite or inconsistent")
            }
            let diskCandidateCounts = diskResults.map {
                $0.diagnostics.localMaximumCount
            }
            let diskAfterAbsoluteCounts = diskResults.map {
                $0.diagnostics.afterAbsoluteThresholdCount
            }
            let diskAfterRelativeCounts = diskResults.map {
                $0.diagnostics.afterRelativeThresholdCount
            }
            let diskAfterSpacingCounts = diskResults.map {
                $0.diagnostics.afterSpacingCount
            }
            let diskPeakCounts = diskResults.map { $0.peaks.count }

            let data = FourDArray(reader: reader, descriptor: descriptor)
            let radius = Float(min(descriptor.qx, descriptor.qy)) * 0.1
            let image = try await VirtualDetector.tiledImage(
                data: data, descriptor: descriptor,
                shape: .circle(centerX: Float(descriptor.qx) / 2,
                               centerY: Float(descriptor.qy) / 2, radius: radius),
                maximumTileRows: 1
            )
            guard image.pixels.count == descriptor.ry * descriptor.rx,
                  image.pixels.allSatisfy(\.isFinite),
                  let minimum = image.pixels.min(), let maximum = image.pixels.max(),
                  maximum > minimum else { fail("\(path): invalid/non-varying virtual image") }
            let mean = image.pixels.reduce(0.0) { $0 + Double($1) } / Double(image.pixels.count)
            let checksum = image.pixels.enumerated().reduce(0.0) {
                $0 + Double($1.element) * Double(($1.offset % 257) + 1)
            }
            let report = AcceptanceReport(
                file: URL(fileURLWithPath: path).lastPathComponent,
                datasetPath: descriptor.datasetPath, shape: descriptor.shape,
                dtype: descriptor.dtypeDescription, finitePatternFraction: finiteFraction,
                diskProbeRadiusPixels: probe.r,
                diskSampleCandidateCounts: diskCandidateCounts,
                diskSampleAfterAbsoluteCounts: diskAfterAbsoluteCounts,
                diskSampleAfterRelativeCounts: diskAfterRelativeCounts,
                diskSampleAfterSpacingCounts: diskAfterSpacingCounts,
                diskSamplePeakCounts: diskPeakCounts,
                virtualImageMinimum: minimum, virtualImageMaximum: maximum,
                virtualImageMean: mean, virtualImageChecksum: checksum,
                elapsedSeconds: Date().timeIntervalSince(start)
            )
            reports.append(report)
            FileHandle.standardError.write(Data(
                "PASS: \(report.file) \(report.shape.map(String.init).joined(separator: "×")) in \(String(format: "%.2f", report.elapsedSeconds)) s\n".utf8
            ))
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(reports))
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
