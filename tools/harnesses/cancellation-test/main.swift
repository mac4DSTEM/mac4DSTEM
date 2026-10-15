import Foundation
import Metal

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

final class ProgressCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() -> Int {
        lock.lock(); defer { lock.unlock() }
        value += 1
        return value
    }
    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return value
    }
}

let basic = AnalysisCancellationToken()
guard !basic.isCancelled else { fail("new token starts cancelled") }
basic.cancel()
basic.cancel()
guard basic.isCancelled else { fail("cancel must be monotonic and idempotent") }
print("PASS: token_monotonic")

let replacement = AnalysisCancellationToken()
guard !replacement.isCancelled else { fail("old cancellation leaked into replacement token") }
print("PASS: replacement_token_independent")

let qy = 16, qx = 16, ry = 128, rx = 1
guard let kernel = ProbeKernel.synthetic(radius: 2.5, width: 1.5, qy: qy, qx: qx) else {
    fail("could not create production probe kernel")
}
var cube = [Float](repeating: 0, count: ry * rx * qy * qx)
for scan in 0..<ry {
    for y in 0..<qy {
        for x in 0..<qx {
            let dx = Float(x - (4 + scan % 8))
            let dy = Float(y - (4 + (scan / 8) % 8))
            cube[(scan * qy + y) * qx + x] = exp(-(dx * dx + dy * dy) / 5)
        }
    }
}
guard let device = MTLCreateSystemDefaultDevice(),
      let buffer = device.makeBuffer(bytes: cube,
                                     length: cube.count * MemoryLayout<Float>.stride,
                                     options: .storageModeShared) else {
    fail("could not allocate Metal test buffer")
}
let descriptor = DatasetDescriptor(
    filePath: "synthetic", datasetPath: "/cube",
    shape: [ry, rx, qy, qx], dtypeDescription: "float32", chunkShape: nil
)
var params = DiskDetectionParams()
params.sigmaCC = 0
params.subpixel = .pixel
params.edgeBoundary = 1
params.minPeakSpacing = 0
params.minRelativeIntensity = 0
params.maxNumPeaks = 4

let beforeStart = AnalysisCancellationToken()
beforeStart.cancel()
let beforeResult = DiskDetection.detectAll(
    cube: buffer, descriptor: descriptor, kernel: kernel, params: params,
    cancellation: beforeStart
)
guard beforeResult == nil else { fail("cancel-before-start returned a partial result") }
print("PASS: cancel_before_start")

let midRun = AnalysisCancellationToken()
let counter = ProgressCounter()
let midResult = DiskDetection.detectAll(
    cube: buffer, descriptor: descriptor, kernel: kernel, params: params,
    cancellation: midRun
) { _ in
    if counter.increment() == 1 { midRun.cancel() }
}
guard midResult == nil else { fail("mid-run cancellation returned a partial result") }
guard counter.count < ry else { fail("all rows completed after mid-run cancellation") }
print("PASS: cancel_mid_run stopped after \(counter.count)/\(ry) row callbacks")

let shortDescriptor = DatasetDescriptor(
    filePath: "synthetic", datasetPath: "/cube",
    shape: [4, rx, qy, qx], dtypeDescription: "float32", chunkShape: nil
)
let normal = AnalysisCancellationToken()
let normalResult = DiskDetection.detectAll(
    cube: buffer, descriptor: shortDescriptor, kernel: kernel, params: params,
    cancellation: normal
)
guard let normalResult, normalResult.peaks.count == 4 else {
    fail("normal completion did not return all scan positions")
}
guard !normal.isCancelled else { fail("normal completion mutated its token") }
print("PASS: normal_completion positions \(normalResult.peaks.count)")
print("cancellation-test: all passed")
