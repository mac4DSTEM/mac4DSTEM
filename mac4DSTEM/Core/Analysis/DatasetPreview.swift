//
//  DatasetPreview.swift
//  Role: A fast, deliberately incomplete look at a dataset — a real-space image
//        and mean/max diffraction patterns built from a STRIDED SAMPLE of scan
//        positions, cheap enough to show before committing to a full load.
//
//  INVARIANT I4 (docs/load-pipeline-plan.md §4): **a sampled preview is not a
//  result.** It cannot be exported or promoted to a product, and it is visibly
//  marked as sampled with its stride stated.
//
//  That invariant is enforced by TYPE, not by discipline: `DatasetPreview` is
//  its own struct and is deliberately NOT a `FloatImage`/product the result
//  pipeline accepts. Nothing here can reach `AppState.resultImage`, the session
//  sidecar, or `BraggVectorEMDWriter`, because none of them take this type.
//
//  THE TRAP THIS IS DESIGNED AROUND, pre-empted per the L5 prompt: a strided
//  preview and a real virtual image WILL differ, and a user comparing them will
//  file a bug. So `summary` always states the stride and the sampled fraction,
//  and `isSampled` is true whenever any position was skipped. A preview that
//  quietly looked like a result would be worse than no preview.
//
//  WHY A BYTE BUDGET RATHER THAN A FIXED GRID. The cost of a preview is
//  patterns × detector bytes, and detectors here range from 64² to 512². A fixed
//  32×32 sample costs 1 MB on a 64² detector and 256 MB on a 512² one — the
//  second is not a preview, it is a load. Budgeting BYTES and deriving the
//  stride keeps the wait roughly constant across datasets, which is the property
//  a user actually experiences.
//

import Foundation

/// A strided sample of a dataset. Never a result — see I4 above.
package nonisolated struct DatasetPreview: Sendable {
    /// Total detector intensity at each sampled scan position, on the sampled
    /// grid (NOT the full scan grid). Its dimensions are the sample's, so it
    /// must never be compared pixel-for-pixel with a real virtual image.
    package let realSpace: FloatImage
    /// Mean and max diffraction pattern over the sampled positions only.
    package let meanDP: DiffractionPattern
    package let maxDP: DiffractionPattern

    package let strideY: Int
    package let strideX: Int
    package let sampledPositions: Int
    package let totalPositions: Int

    /// True whenever any scan position was skipped.
    package var isSampled: Bool { sampledPositions < totalPositions }

    /// The label that must appear wherever this is drawn (I4).
    ///
    /// States the stride explicitly rather than a percentage, because "every
    /// 6th position" tells a user what they are looking at and "5% sampled"
    /// does not.
    package var summary: String {
        guard isSampled else {
            return "Preview · every position"
        }
        let step = strideY == strideX
            ? "every \(ordinal(strideY)) position"
            : "every \(ordinal(strideY)) row, every \(ordinal(strideX)) column"
        return "Sampled preview · \(step) · "
            + "\(formattedCount(sampledPositions)) of \(formattedCount(totalPositions))"
    }

    /// A position on the SAMPLED grid, converted to source scan coordinates.
    /// The stride multiplication lives here with the stride itself — a view
    /// hand-rolling it is the "missing stride multiplication" defect class
    /// (F1.10), one conversion drift away. // v2 S4
    package func sourcePosition(forSampledX x: Int, sampledY y: Int) -> (ry: Int, rx: Int) {
        (ry: y * strideY, rx: x * strideX)
    }

    private func ordinal(_ value: Int) -> String {
        switch value {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(value)th"
        }
    }

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package init(realSpace: FloatImage, meanDP: DiffractionPattern, maxDP: DiffractionPattern, strideY: Int, strideX: Int, sampledPositions: Int, totalPositions: Int) {
        self.realSpace = realSpace
        self.meanDP = meanDP
        self.maxDP = maxDP
        self.strideY = strideY
        self.strideX = strideX
        self.sampledPositions = sampledPositions
        self.totalPositions = totalPositions
    }
}

// `nonisolated`: pure sampling math called from detached read contexts; under
// MainActor default isolation the un-annotated enum isolated its own statics
// away from its callers. // v2 S3
package nonisolated enum DatasetPreviewBuilder {

    /// Roughly how many bytes the preview may read. 64 MB is a fraction of a
    /// second on local storage at the throughputs measured 2026-08-17
    /// (≈900 MB/s–4 GB/s), and it bounds the wait the same way on a 64² and a
    /// 512² detector.
    package static let defaultByteBudget = 64 << 20

    /// The stride that keeps a preview inside `byteBudget`.
    ///
    /// Deterministic and separated out so it can be tested without any I/O:
    /// the same dataset always produces the same sample, which is what makes a
    /// preview comparable across two opens of the same file.
    package static func stride(
        for descriptor: DatasetDescriptor, byteBudget: Int = defaultByteBudget
    ) -> (y: Int, x: Int) {
        let patternBytes = descriptor.qy * descriptor.qx * MemoryLayout<Float>.stride
        guard descriptor.is4D, patternBytes > 0,
              descriptor.ry > 0, descriptor.rx > 0 else { return (1, 1) }
        let affordable = max(1, byteBudget / patternBytes)
        let total = descriptor.ry * descriptor.rx
        guard total > affordable else { return (1, 1) }
        // One stride for both axes keeps the preview's aspect ratio equal to the
        // scan's. A per-axis stride would distort it, and a distorted preview of
        // real space is worse than a coarse one — the user is looking for
        // features and their shape is the information.
        let step = Int(ceil(sqrt(Double(total) / Double(affordable))))
        return (max(1, step), max(1, step))
    }

    /// How many sampled rows `make` will report progress over — the
    /// denominator of "Sampling a preview · row N of M". One derivation,
    /// shared by both open paths: three hand-rolled copies of this ceiling
    /// division would have to agree with the builder's own loop for the bar
    /// to end at 100%. // v2 S4
    package static func sampledRowCount(
        for descriptor: DatasetDescriptor, byteBudget: Int = defaultByteBudget
    ) -> Int {
        let step = stride(for: descriptor, byteBudget: byteBudget).y
        return max(1, (descriptor.ry + step - 1) / step)
    }

    /// Build the preview by reading only the sampled patterns.
    ///
    /// Deliberately uses `pattern(ry:rx:)` rather than tiles: a tile read would
    /// pull whole scan rows and defeat the point, which is to touch a small,
    /// bounded fraction of a file the user has not yet committed to loading.
    package static func make(
        data: FourDArray,
        descriptor: DatasetDescriptor,
        byteBudget: Int = defaultByteBudget,
        cancellation: AnalysisCancellationToken? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> DatasetPreview {
        guard descriptor.is4D, descriptor.ry > 0, descriptor.rx > 0 else {
            throw FourDError.allocationFailed
        }
        let steps = stride(for: descriptor, byteBudget: byteBudget)
        let sampledYs = Swift.stride(from: 0, to: descriptor.ry, by: steps.y).map { $0 }
        let sampledXs = Swift.stride(from: 0, to: descriptor.rx, by: steps.x).map { $0 }
        let detectorCount = descriptor.qy * descriptor.qx

        var realSpace = [Float](repeating: 0, count: sampledYs.count * sampledXs.count)
        var mean = [Double](repeating: 0, count: detectorCount)
        var maximum = [Float](repeating: -.greatestFiniteMagnitude, count: detectorCount)

        for (row, y) in sampledYs.enumerated() {
            guard cancellation?.isCancelled != true else { throw CancellationError() }
            for (column, x) in sampledXs.enumerated() {
                let pattern = try await data.pattern(ry: y, rx: x)
                guard pattern.pixels.count == detectorCount else {
                    throw FourDError.allocationFailed
                }
                var total: Double = 0
                for index in 0..<detectorCount {
                    let value = pattern.pixels[index]
                    total += Double(value)
                    mean[index] += Double(value)
                    maximum[index] = Swift.max(maximum[index], value)
                }
                realSpace[row * sampledXs.count + column] = Float(total)
            }
            progress?(Double(row + 1) / Double(sampledYs.count))
        }

        let sampled = sampledYs.count * sampledXs.count
        let divisor = Double(Swift.max(1, sampled))
        return DatasetPreview(
            realSpace: FloatImage(
                width: sampledXs.count, height: sampledYs.count, pixels: realSpace
            ),
            meanDP: DiffractionPattern(
                qy: descriptor.qy, qx: descriptor.qx,
                pixels: mean.map { Float($0 / divisor) }
            ),
            maxDP: DiffractionPattern(
                qy: descriptor.qy, qx: descriptor.qx, pixels: maximum
            ),
            strideY: steps.y, strideX: steps.x,
            sampledPositions: sampled,
            totalPositions: descriptor.ry * descriptor.rx
        )
    }
}

/// Core's own thousands formatter. It used to call `AppState.count`, the one
/// upward reference in `Core/`; removed 2026-09-02 so Core builds as the
/// standalone `DSTEMCore` module (`Package.swift`).
package nonisolated func formattedCount(_ value: Int) -> String {
    value.formatted(.number.locale(Locale(identifier: "en_US")))
}
