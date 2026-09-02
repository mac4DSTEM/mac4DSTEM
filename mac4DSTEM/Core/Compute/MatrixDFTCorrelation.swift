//
//  MatrixDFTCorrelation.swift
//  Shared py4DSTEM-compatible subpixel correlation refinement.
//

import Foundation

package nonisolated struct CorrelationPeak: Equatable, Sendable {
    package let row: Float
    package let column: Float

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(row: Float, column: Float) {
        self.row = row
        self.column = column
    }
}

/// Guizar-Sicairos matrix-multiply DFT refinement as used by py4DSTEM's
/// `align_images_fourier` / `upsampled_correlation` path.
package nonisolated enum MatrixDFTCorrelation {
    /// Find the circular-correlation maximum, apply py4DSTEM's three-point
    /// parabolic estimate, round it to a half pixel, and refine it on a small
    /// matrix-DFT patch.
    package static func refinedPeak(
        correlationRe: [Float],
        correlationIm: [Float],
        width: Int,
        height: Int,
        fft: FFT2D,
        upsampleFactor: Int
    ) -> CorrelationPeak {
        precondition(width > 0 && height > 0)
        precondition(correlationRe.count == width * height)
        precondition(correlationIm.count == correlationRe.count)
        precondition(fft.nx == width && fft.ny == height)

        var real = correlationRe
        var imaginary = correlationIm
        fft.transform(re: &real, im: &imaginary, forward: false,
                      scaleInverse: true)
        var maximum = 0
        for index in 1..<real.count where real[index] > real[maximum] {
            maximum = index
        }
        let row = maximum / width
        let column = maximum % width
        let rowOffset = parabolicOffset(
            previous: real[positiveModulo(row - 1, height) * width + column],
            center: real[maximum],
            next: real[positiveModulo(row + 1, height) * width + column]
        )
        let columnOffset = parabolicOffset(
            previous: real[row * width + positiveModulo(column - 1, width)],
            center: real[maximum],
            next: real[row * width + positiveModulo(column + 1, width)]
        )
        return refine(
            correlationRe: correlationRe, correlationIm: correlationIm,
            width: width, height: height,
            initial: CorrelationPeak(
                row: Float(row) + rowOffset,
                column: Float(column) + columnOffset
            ),
            upsampleFactor: upsampleFactor
        )
    }

    /// Refine an existing parabolic peak. This entry point is also shared by
    /// Bragg-disk multicorr, whose initial peak comes from its maxima image.
    package static func refine(
        correlationRe: [Float],
        correlationIm: [Float],
        width: Int,
        height: Int,
        initial: CorrelationPeak,
        upsampleFactor: Int
    ) -> CorrelationPeak {
        guard upsampleFactor > 2 else { return initial }
        precondition(width > 0 && height > 0)
        precondition(correlationRe.count == width * height)
        precondition(correlationIm.count == correlationRe.count)

        let u = Float(upsampleFactor)
        // NumPy uses ties-to-even rounding at both stages.
        var row = ((initial.row * 2).rounded(.toNearestOrEven) / 2)
        var column = ((initial.column * 2).rounded(.toNearestOrEven) / 2)
        row = (row * u).rounded(.toNearestOrEven) / u
        column = (column * u).rounded(.toNearestOrEven) / u

        let patchSize = Int(ceil(1.5 * u))
        let globalShift = floor(Float(patchSize) / 2)
        let patch = dftUpsampleOfConjugate(
            correlationRe: correlationRe, correlationIm: correlationIm,
            width: width, height: height,
            centerRow: globalShift - u * row,
            centerColumn: globalShift - u * column,
            upsampleFactor: upsampleFactor,
            patchSize: patchSize
        )

        var maximum = 0
        for index in 1..<patch.count where patch[index] > patch[maximum] {
            maximum = index
        }
        let peakRow = maximum / patchSize
        let peakColumn = maximum % patchSize
        var subRow = Float(peakRow)
        var subColumn = Float(peakColumn)
        // py4DSTEM falls back to zero polish when the 3x3 patch crosses an
        // edge. Keeping both offsets at zero matches that single try/except.
        if peakRow > 0, peakRow < patchSize - 1,
           peakColumn > 0, peakColumn < patchSize - 1 {
            let center = patch[maximum]
            subRow += parabolicOffset(
                previous: patch[maximum - patchSize], center: center,
                next: patch[maximum + patchSize]
            )
            subColumn += parabolicOffset(
                previous: patch[maximum - 1], center: center,
                next: patch[maximum + 1]
            )
        }
        return CorrelationPeak(
            row: row + (subRow - globalShift) / u,
            column: column + (subColumn - globalShift) / u
        )
    }

    /// real(rowKern · conj(correlation) · colKern). The center is expressed
    /// in upsampled-grid coordinates, matching py4DSTEM's `dftUpsample`.
    private static func dftUpsampleOfConjugate(
        correlationRe: [Float],
        correlationIm: [Float],
        width: Int,
        height: Int,
        centerRow: Float,
        centerColumn: Float,
        upsampleFactor: Int,
        patchSize: Int
    ) -> [Float] {
        var intermediateRe = [Float](repeating: 0,
                                     count: height * patchSize)
        var intermediateIm = [Float](repeating: 0,
                                     count: height * patchSize)
        let columnScale = -2 * Float.pi
            / (Float(width) * Float(upsampleFactor))
        for frequencyColumn in 0..<width {
            let wrappedFrequency = Float(
                frequencyColumn < width / 2
                    ? frequencyColumn : frequencyColumn - width
            )
            for patchColumn in 0..<patchSize {
                let angle = columnScale * wrappedFrequency
                    * (Float(patchColumn) - centerColumn)
                let cosine = cos(angle), sine = sin(angle)
                for sourceRow in 0..<height {
                    let source = sourceRow * width + frequencyColumn
                    let destination = sourceRow * patchSize + patchColumn
                    // conj(correlation) × column kernel
                    intermediateRe[destination] += correlationRe[source] * cosine
                        + correlationIm[source] * sine
                    intermediateIm[destination] += -correlationIm[source] * cosine
                        + correlationRe[source] * sine
                }
            }
        }

        var patch = [Float](repeating: 0, count: patchSize * patchSize)
        let rowScale = -2 * Float.pi
            / (Float(height) * Float(upsampleFactor))
        for patchRow in 0..<patchSize {
            for frequencyRow in 0..<height {
                let wrappedFrequency = Float(
                    frequencyRow < height / 2
                        ? frequencyRow : frequencyRow - height
                )
                let angle = rowScale * (Float(patchRow) - centerRow)
                    * wrappedFrequency
                let cosine = cos(angle), sine = sin(angle)
                for patchColumn in 0..<patchSize {
                    let source = frequencyRow * patchSize + patchColumn
                    patch[patchRow * patchSize + patchColumn]
                        += cosine * intermediateRe[source]
                            - sine * intermediateIm[source]
                }
            }
        }
        return patch
    }

    private static func parabolicOffset(
        previous: Float, center: Float, next: Float
    ) -> Float {
        let denominator = 4 * center - 2 * next - 2 * previous
        let offset = (next - previous) / denominator
        return offset.isFinite ? offset : 0
    }

    private static func positiveModulo(_ value: Int, _ modulus: Int) -> Int {
        let remainder = value % modulus
        return remainder >= 0 ? remainder : remainder + modulus
    }
}
