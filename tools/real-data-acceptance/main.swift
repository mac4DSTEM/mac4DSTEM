import Foundation

// `Aperture` now lives in Core/Analysis/VirtualDetector.swift (2026-09-02);
// the local mirror this file carried is gone.

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
        var skipped: [String] = []
        for path in CommandLine.arguments.dropFirst() {
            let start = Date()
            let reader = try H5Reader(path: path)

            // A FILE WITH NO DATACUBE IS AN INPUT, NOT AN ERROR (#43).
            //
            // The glob feeds this harness every `*.h5` in the training
            // directory, and saving a session in the app writes a
            // `<name>.mac4dstem.h5` sidecar right next to the cube it came from.
            // Those hold BraggVectors and saved results, not a 4D datacube, so
            // `discoverPrimaryDataset` throws — and a throw out of `main` is a
            // Swift runtime trap: exit 133 and a page-long stack trace listing
            // every HDF5 path it probed, after two real cubes have already
            // printed PASS. It reads as a late regression in the app; it is a
            // file the tool was always going to meet.
            //
            // Only `noDatasetFound` is skipped. Anything else — an unreadable
            // file, a malformed dataset — still throws, because those are
            // genuine failures and quieting them would be widening a gate.
            let descriptor: DatasetDescriptor
            do {
                descriptor = try await reader.discoverPrimaryDataset()
            } catch H5Error.noDatasetFound {
                let name = (path as NSString).lastPathComponent
                skipped.append(name)
                FileHandle.standardError.write(
                    Data("SKIP: \(name) has no 4D datacube (session sidecar or results-only file)\n".utf8)
                )
                continue
            } catch H5Error.sessionSidecarOpened {
                // v2 S4: the reader now RECOGNISES its own sidecars before
                // falling through to `noDatasetFound`, so the sidecars this
                // glob was always going to meet arrive as this case. Same
                // input-not-error rule as #43 above; without this catch the
                // throw would trap `main` (exit 133) after real cubes had
                // already printed PASS — the exact regression #43 fixed.
                let name = (path as NSString).lastPathComponent
                skipped.append(name)
                FileHandle.standardError.write(
                    Data("SKIP: \(name) is a mac4DSTEM session sidecar\n".utf8)
                )
                continue
            }
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
        // A run that measured nothing must not report success, and THIS guard
        // is what covers it: if every file was skipped, `run.sh` aborts here on
        // the non-zero exit and `compare.py` never runs at all. Three guards,
        // each covering a different case, stated because a previous version of
        // this comment credited compare.py with two it does not provide:
        //   here                        the harness skipped every file
        //   compare.py `if not expected` expected.json was emptied — the
        //                               missing-dataset check is VACUOUS then,
        //                               because nothing is pinned to be missing
        //   compare.py `missing`         a pinned cube vanished from a report
        //                               that still has other entries
        guard !reports.isEmpty else {
            fail("no file produced a report; skipped \(skipped.count): \(skipped.joined(separator: ", "))")
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(reports))
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
