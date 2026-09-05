// bullseye-parity-probe.swift — app side of the 2026-09-05 parity: the file-probe FLAT kernel through the
// production DiskDetector on 90 strided positions of polyAu_4DSTEM, one line per peak (ry rx x y intensity).
// Compile like run.sh compiles main.swift (swap the file name); pair the output with bullseye-parity-compare.py.
// Diagnostic, never gates; needs References/training_dataset/calibrationData_bullseyeProbe.h5 (absolute path).
// so a python script can pair them with py4DSTEM's (bullseye_parity_dump.py).

@main
struct BullseyeParity {
    static func main() async throws {
        setvbuf(stdout, nil, _IONBF, 0)
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count >= 1 else { print("usage: parity <bullseye.h5> [minRel]"); exit(64) }
        let minRel = args.count > 1 ? Float(args[1]) ?? 0.05 : 0.05
        let reader = try H5Reader(path: args[0])
        let d = try await reader.discoverPrimaryDataset()
        FileHandle.standardError.write(Data("cube \(d.datasetPath) \(d.shape)\n".utf8))
        let probes = try await reader.probeCandidates(detectorQY: d.qy, detectorQX: d.qx)
        guard let candidate = probes.first else { print("FAIL: no probe candidate"); exit(1) }
        FileHandle.standardError.write(Data("probe \(candidate.path) slices \(candidate.sliceCount)\n".utf8))
        let probe = DiffractionPattern(qy: candidate.qy, qx: candidate.qx, pixels: try await reader.readProbe(candidate))
        guard let size = OriginCalibration.probeSize(dp: probe.pixels, qy: probe.qy, qx: probe.qx) else {
            print("FAIL: probe size"); exit(1)
        }
        FileHandle.standardError.write(Data(String(format: "probe r %.3f centre (%.3f, %.3f)\n", size.r, size.x0, size.y0).utf8))
        // py4DSTEM's reference used origin=(125,125), the template's integer centre; use the same.
        guard let kernel = ProbeKernel.measured(pattern: probe, originX: 125, originY: 125, radius: size.r,
                                                mode: .flat, source: .fileProbe, probePath: candidate.path) else {
            print("FAIL: kernel"); exit(1)
        }
        guard let detector = DiskDetector(kernel: kernel) else { print("FAIL: detector"); exit(1) }
        var params = DiskDetectionParams()
        params.minPeakSpacing = 8
        params.edgeBoundary = 6
        params.minRelativeIntensity = minRel
        params.subpixel = .poly          // py4DSTEM default in the reference run was multicorr; poly first, then compare
        params.sigmaCC = 2
        let view = LoadView(fullExtentOf: d)
        for ry in stride(from: 0, to: d.ry, by: 10) {
            for rx in stride(from: 0, to: d.rx, by: 10) {
                let pattern = try await reader.readPattern(view, ry: ry, rx: rx)
                let peaks = pattern.withUnsafeBufferPointer { detector.detect(pattern: $0.baseAddress!, params: params) }
                for p in peaks { print("\(ry) \(rx) \(p.x) \(p.y) \(p.intensity)") }
            }
        }
    }
}
