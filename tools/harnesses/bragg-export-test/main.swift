import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

guard CommandLine.arguments.count == 4 else {
    fail("usage: harness OUTPUT CANCEL_OUTPUT SOURCE")
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let cancelOutput = URL(fileURLWithPath: CommandLine.arguments[2])
let source = URL(fileURLWithPath: CommandLine.arguments[3])
let sourceBefore = try Data(contentsOf: source)

// Non-square 2 × 3 scan, non-square 5 × 7 detector, variable list lengths,
// an empty scan position, subpixel coordinates, and nonuniform intensities.
let vectors = BraggVectors(
    scanWidth: 3,
    scanHeight: 2,
    peaks: [
        [BraggPeak(x: 2.5, y: 1.25, intensity: 10),
         BraggPeak(x: 6.125, y: -0.5, intensity: 3.25)],
        [],
        [BraggPeak(x: 0.125, y: 4.75, intensity: 99.5)],
        [BraggPeak(x: 3, y: 2, intensity: 1)],
        [BraggPeak(x: 0, y: 0, intensity: 2),
         BraggPeak(x: 6, y: 4, intensity: 4),
         BraggPeak(x: 2.25, y: 1.5, intensity: 8)],
        [BraggPeak(x: 5.875, y: 3.125, intensity: 7.5)],
    ],
    detectionProvenance: [
        "detection_algorithm": DiskDetectionParams.algorithmID,
        "sigma_cc_px": "2.0",
        "subpixel": "poly",
    ]
)
let calibration = PixelCalibration(
    rSize: 1.75, rUnits: "nm", qSize: 0.03125, qUnits: "A^-1", qrFlip: true
)

try BraggVectorEMDWriter.write(
    vectors: vectors, qWidth: 7, qHeight: 5,
    calibration: calibration, to: output
)
guard FileManager.default.fileExists(atPath: output.path) else {
    fail("normal completion did not publish an output")
}
guard try Data(contentsOf: source) == sourceBefore else {
    fail("source fixture changed during sidecar export")
}
print("PASS: atomic_sidecar source_unchanged")

let sentinel = Data("existing destination must survive cancellation".utf8)
try sentinel.write(to: cancelOutput)
let token = AnalysisCancellationToken()
do {
    try BraggVectorEMDWriter.write(
        vectors: vectors, qWidth: 7, qHeight: 5,
        calibration: calibration, to: cancelOutput,
        cancellation: token
    ) { fraction in
        if fraction > 0 { token.cancel() }
    }
    fail("cancelled export unexpectedly succeeded")
} catch BraggVectorEMDWriter.WriterError.cancelled {
    // Expected.
}
guard try Data(contentsOf: cancelOutput) == sentinel else {
    fail("cancelled export replaced or damaged the prior destination")
}
let leftovers = try FileManager.default.contentsOfDirectory(
    at: cancelOutput.deletingLastPathComponent(),
    includingPropertiesForKeys: nil
).filter { $0.lastPathComponent.hasPrefix(".\(cancelOutput.lastPathComponent).") }
guard leftovers.isEmpty else { fail("cancelled export left a temporary file") }
print("PASS: cancellation_preserves_destination")
print("bragg-export-test Swift phase: all passed")
