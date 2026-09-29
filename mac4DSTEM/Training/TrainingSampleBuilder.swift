//
//  TrainingSampleBuilder.swift
//  Role: turns hand-labelled scan positions into `TrainingSample`s (Phase C4b; C3 pre-registration §3 step 3).
//
//  The model inputs are the SCAN'S OWN: the same window origins, the same probe crop, the same flat kernel
//  and the same classical correlation channel `LearnedDiskDetector.detectAll` builds for each
//  (position, window) job, through the same `window` / `fillNonFinite` / `correlation` / `modelInputs`
//  calls — a model is trained on exactly what it will be shown. A detector no larger than 256 px is one
//  window (the frame placed by `fitOffset`); a larger one gives one sample per window, so windows without
//  a disk teach the net to leave them empty. Labels are hand-clicked centres in the detector's native
//  pixel frame; each is mapped into its window (`row - row0`, `col - col0`) and dropped when it lies
//  outside the 256 frame.
//

import DSTEMCore
import Foundation

package nonisolated final class TrainingSampleBuilder: @unchecked Sendable {
    package let windows: [(row0: Int, col0: Int)]
    private let qy: Int, qx: Int
    private let probeCrop: [Float]
    private let detector: DiskDetector
    private let params: DiskDetectionParams
    private let S = LearnedDiskDetector.inputSize

    /// Nil when the settings are invalid at the frame size or the probe yields no kernel — the cases in
    /// which `detectAll` returns nil.
    package init?(qy: Int, qx: Int, probe: DiffractionPattern, probeCentre: (x: Float, y: Float), probeRadius: Float,
                  kernelSource: ProbeKernelSource, params: DiskDetectionParams) {
        let S = LearnedDiskDetector.inputSize
        guard qy > 0, qx > 0, probe.qy == qy, probe.qx == qx else { return nil }
        guard !params.validationIssues(in: DiskDetectionContext(qy: S, qx: S, probeRadius: probeRadius))
            .contains(where: { $0.severity == .error }) else { return nil }
        let overlap = LearnedDiskDetector.windowOverlap(probeRadius: probeRadius)
        let rowOrigins = LearnedDiskDetector.windowOrigins(q: qy, probeCentreOnAxis: probeCentre.y, overlap: overlap)
        let colOrigins = LearnedDiskDetector.windowOrigins(q: qx, probeCentreOnAxis: probeCentre.x, overlap: overlap)
        windows = rowOrigins.flatMap { r in colOrigins.map { c in (row0: r, col0: c) } }
        let probeRow0 = qy > S ? min(max(Int(probeCentre.y.rounded(.toNearestOrEven)) - S / 2, 0), qy - S) : rowOrigins[0]
        let probeCol0 = qx > S ? min(max(Int(probeCentre.x.rounded(.toNearestOrEven)) - S / 2, 0), qx - S) : colOrigins[0]
        var crop = [Float](repeating: 0, count: S * S)
        probe.pixels.withUnsafeBufferPointer {
            LearnedDiskDetector.window(of: $0.baseAddress!, qy: qy, qx: qx, row0: probeRow0, col0: probeCol0, into: &crop)
        }
        _ = crop.withUnsafeMutableBufferPointer {
            DiskDetector.fillNonFinite($0.baseAddress!, width: S, height: S, rowStride: S)
        }
        guard let kernel = ProbeKernel.flat(
            pattern: DiffractionPattern(qy: S, qx: S, pixels: crop),
            originX: probeCentre.x - Float(probeCol0), originY: probeCentre.y - Float(probeRow0),
            radius: probeRadius, source: kernelSource),
              let det = DiskDetector(kernel: kernel) else { return nil }
        self.qy = qy; self.qx = qx; self.probeCrop = crop; self.detector = det; self.params = params
    }

    /// The samples of one labelled position: one per window. `centres` are (row, col) in the native frame.
    package func samples(pattern: DiffractionPattern, position: ScanPosition, centres: [ScorePoint]) -> [TrainingSample] {
        guard pattern.qy == qy, pattern.qx == qx else { return [] }
        var crop = [Float](repeating: 0, count: S * S)
        var out: [TrainingSample] = []
        for win in windows {
            pattern.pixels.withUnsafeBufferPointer {
                LearnedDiskDetector.window(of: $0.baseAddress!, qy: qy, qx: qx, row0: win.row0, col0: win.col0, into: &crop)
            }
            _ = crop.withUnsafeMutableBufferPointer {
                DiskDetector.fillNonFinite($0.baseAddress!, width: S, height: S, rowStride: S)
            }
            let corr = crop.withUnsafeBufferPointer { detector.correlation(pattern: $0.baseAddress!, params: params) }
            let inputs = LearnedDiskDetector.modelInputs(pattern: crop, probe: probeCrop, correlation: corr.raw)
            out.append(TrainingSample(position: position, inputs: inputs,
                                      centres: Self.centres(centres, inWindowAt: win.row0, win.col0)))
        }
        return out
    }

    /// The native-frame centres that fall inside the window at (`row0`, `col0`), in the window's own frame.
    package static func centres(_ native: [ScorePoint], inWindowAt row0: Int, _ col0: Int) -> [ScorePoint] {
        let S = Double(LearnedDiskDetector.inputSize)
        return native.compactMap { c in
            let r = c.row - Double(row0), col = c.col - Double(col0)
            return (r >= 0 && r < S && col >= 0 && col < S) ? ScorePoint(row: r, col: col) : nil
        }
    }
}
