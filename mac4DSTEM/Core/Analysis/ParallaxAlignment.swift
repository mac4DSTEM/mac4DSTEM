//
//  ParallaxAlignment.swift
//  Immutable coarse-to-fine alignment levels from py4DSTEM
//  Parallax.reconstruct, including factor-8 matrix-DFT refinement.
//

import Accelerate
import Foundation

package nonisolated struct ParallaxScanShift: Equatable, Sendable {
    /// Shift along the first / scan-row axis.
    package let row: Float
    /// Shift along the second / scan-column axis.
    package let column: Float

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package init(row: Float, column: Float) {
        self.row = row
        self.column = column
    }
}

package nonisolated struct ParallaxAlignmentGroup: Equatable, Sendable {
    package let rowBin: Int
    package let columnBin: Int
    package let memberIndices: [Int]

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package init(rowBin: Int, columnBin: Int, memberIndices: [Int]) {
        self.rowBin = rowBin
        self.columnBin = columnBin
        self.memberIndices = memberIndices
    }
}

package nonisolated struct ParallaxAlignmentOptions: Equatable, Sendable {
    // Explicit so the default initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package init() {}

    /// Nil selects the first (coarsest) value in py4DSTEM's default schedule.
    package var alignmentBin: Int? = nil
    package var centeredAlignmentBins = false
    package var runningAverage = true
    /// Values above 2 use py4DSTEM's matrix-DFT subpixel refinement. The
    /// compatibility `alignOneLevel` entry point retains integer peaks by
    /// default; the interactive continuation path explicitly selects 8.
    package var upsampleFactor = 1
    /// Peak resident bytes: immutable input stack + output stack/masks + FFT work.
    package var maxWorkingBytes = 1_073_741_824
}

package nonisolated struct ParallaxAlignmentResult: Sendable {
    package let alignmentBin: Int
    package let alignmentSchedule: [Int]
    package let completedBins: [Int]
    package let upsampleFactor: Int
    package let groups: [ParallaxAlignmentGroup]
    /// Wrapped correlation peaks, one per radially ordered group.
    package let groupShifts: [ParallaxScanShift]
    /// Default py4DSTEM k-vector least-squares shifts after median centering.
    package let totalShifts: [ParallaxScanShift]
    package let shiftedStack: [Float]
    package let shiftedMasks: [Float]
    package let reconstructionMask: [Float]
    package let alignedBF: [Float]
    package let errorHistory: [Float]
    package let scanHeight: Int
    package let scanWidth: Int
    package let stackHeight: Int
    package let stackWidth: Int

    package var currentError: Float { errorHistory.last ?? .nan }

    package var isComplete: Bool { completedBins == alignmentSchedule }

    package var nextAlignmentBin: Int? {
        guard completedBins.count < alignmentSchedule.count,
              Array(alignmentSchedule.prefix(completedBins.count)) == completedBins else {
            return nil
        }
        return alignmentSchedule[completedBins.count]
    }

    package var maximumShiftPixels: Float {
        totalShifts.reduce(0) { partial, shift in
            max(partial, hypot(shift.row, shift.column))
        }
    }

    package var previewImage: FloatImage {
        let top = (stackHeight - scanHeight) / 2
        let left = (stackWidth - scanWidth) / 2
        var pixels = [Float](repeating: 0, count: scanHeight * scanWidth)
        for y in 0..<scanHeight {
            let source = (top + y) * stackWidth + left
            pixels.replaceSubrange(
                (y * scanWidth)..<((y + 1) * scanWidth),
                with: alignedBF[source..<(source + scanWidth)]
            )
        }
        return FloatImage(width: scanWidth, height: scanHeight, pixels: pixels)
    }

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package init(alignmentBin: Int, alignmentSchedule: [Int], completedBins: [Int], upsampleFactor: Int, groups: [ParallaxAlignmentGroup], groupShifts: [ParallaxScanShift], totalShifts: [ParallaxScanShift], shiftedStack: [Float], shiftedMasks: [Float], reconstructionMask: [Float], alignedBF: [Float], errorHistory: [Float], scanHeight: Int, scanWidth: Int, stackHeight: Int, stackWidth: Int) {
        self.alignmentBin = alignmentBin
        self.alignmentSchedule = alignmentSchedule
        self.completedBins = completedBins
        self.upsampleFactor = upsampleFactor
        self.groups = groups
        self.groupShifts = groupShifts
        self.totalShifts = totalShifts
        self.shiftedStack = shiftedStack
        self.shiftedMasks = shiftedMasks
        self.reconstructionMask = reconstructionMask
        self.alignedBF = alignedBF
        self.errorHistory = errorHistory
        self.scanHeight = scanHeight
        self.scanWidth = scanWidth
        self.stackHeight = stackHeight
        self.stackWidth = stackWidth
    }
}

package nonisolated enum ParallaxAligner {
    package enum AlignmentError: LocalizedError, Equatable {
        case invalidInput(String)
        case memoryLimit(bytes: Int, limit: Int)
        case fftUnavailable
        case singularShiftBasis
        case alignmentComplete
        case cancelled

        package var errorDescription: String? {
            switch self {
            case .invalidInput(let detail):
                return "Cannot align the parallax preview: \(detail)."
            case .memoryLimit(let bytes, let limit):
                return "Parallax alignment needs about \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)), above the \(ByteCountFormatter.string(fromByteCount: Int64(limit), countStyle: .file)) alignment limit. Crop/bin the dataset first."
            case .fftUnavailable:
                return "Could not create the exact-shape FFT used for parallax alignment."
            case .singularShiftBasis:
                return "The selected bright-field pixels do not span two reciprocal-space directions."
            case .alignmentComplete:
                return "Every parallax alignment-bin level is already complete. Reset alignment to start again."
            case .cancelled:
                return "Parallax alignment was cancelled."
            }
        }
    }

    /// py4DSTEM's default `2 ** arange(ceil(log2(min)), ceil(log2(max)))[::-1]`.
    package static func defaultBinSchedule(
        detectorIndices: [ParallaxDetectorIndex], minimumBin: Int = 1
    ) -> [Int] {
        guard !detectorIndices.isEmpty else { return [] }
        let rows = detectorIndices.map(\.qx)
        let columns = detectorIndices.map(\.qy)
        let diameter = max((rows.max()! - rows.min()!),
                           (columns.max()! - columns.min()!)) + 1
        let minimum = max(1, minimumBin)
        let minPower = Int(ceil(log2(Double(minimum))))
        let maxPower = Int(ceil(log2(Double(diameter))))
        guard minPower < maxPower else { return [minimum] }
        return Array((minPower..<maxPower).reversed()).map { 1 << $0 }
    }

    package static func groups(
        detectorIndices: [ParallaxDetectorIndex],
        alignmentBin: Int,
        centered: Bool = false
    ) -> [ParallaxAlignmentGroup] {
        guard !detectorIndices.isEmpty, alignmentBin > 0 else { return [] }
        let medianRow = median(detectorIndices.map { Float($0.qx) })
        let medianColumn = median(detectorIndices.map { Float($0.qy) })
        let binShift: Float = centered ? 0 : 0.5
        var membership: [BinCoordinate: [Int]] = [:]
        for (index, detector) in detectorIndices.enumerated() {
            let row = Int(((Float(detector.qx) - medianRow) / Float(alignmentBin)
                           + binShift).rounded(.toNearestOrEven))
            let column = Int(((Float(detector.qy) - medianColumn) / Float(alignmentBin)
                              + binShift).rounded(.toNearestOrEven))
            membership[BinCoordinate(row: row, column: column), default: []].append(index)
        }
        // np.unique(axis=0) is lexicographic; argsort(radius²) then visits
        // center-out. The lexicographic tie break is deterministic and matches
        // the checked-in NumPy fixture for equal radii.
        return membership.keys.sorted {
            let lhsRadius = $0.row * $0.row + $0.column * $0.column
            let rhsRadius = $1.row * $1.row + $1.column * $1.column
            if lhsRadius != rhsRadius { return lhsRadius < rhsRadius }
            if $0.row != $1.row { return $0.row < $1.row }
            return $0.column < $1.column
        }.map {
            ParallaxAlignmentGroup(
                rowBin: $0.row, columnBin: $0.column,
                memberIndices: membership[$0]!
            )
        }
    }

    package static func alignOneLevel(
        preprocessing: ParallaxPreprocessResult,
        options: ParallaxAlignmentOptions = ParallaxAlignmentOptions(),
        cancellation: AnalysisCancellationToken? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> ParallaxAlignmentResult {
        let schedule = defaultBinSchedule(
            detectorIndices: preprocessing.detectorIndices
        )
        guard let alignmentBin = options.alignmentBin ?? schedule.first else {
            throw AlignmentError.invalidInput("no alignment bin is available")
        }
        return try alignLevel(
            preprocessing: preprocessing, previous: nil,
            alignmentBin: alignmentBin, schedule: schedule, options: options,
            cancellation: cancellation, progress: progress
        )
    }

    /// Continue the source-locked coarse-to-fine schedule from the last fully
    /// published level. No previous arrays are mutated while the next level is
    /// being computed.
    package static func alignNextLevel(
        preprocessing: ParallaxPreprocessResult,
        previous: ParallaxAlignmentResult? = nil,
        options: ParallaxAlignmentOptions = ParallaxAlignmentOptions(),
        cancellation: AnalysisCancellationToken? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> ParallaxAlignmentResult {
        let schedule = defaultBinSchedule(
            detectorIndices: preprocessing.detectorIndices
        )
        guard !schedule.isEmpty else {
            throw AlignmentError.invalidInput("no alignment bin is available")
        }
        let completed = previous?.completedBins ?? []
        guard completed.count <= schedule.count,
              Array(schedule.prefix(completed.count)) == completed,
              (previous?.alignmentSchedule ?? schedule) == schedule else {
            throw AlignmentError.invalidInput(
                "the prior alignment does not match the current bin schedule"
            )
        }
        guard completed.count < schedule.count else {
            throw AlignmentError.alignmentComplete
        }
        return try alignLevel(
            preprocessing: preprocessing, previous: previous,
            alignmentBin: schedule[completed.count], schedule: schedule,
            options: options, cancellation: cancellation, progress: progress
        )
    }

    private static func alignLevel(
        preprocessing: ParallaxPreprocessResult,
        previous: ParallaxAlignmentResult?,
        alignmentBin: Int,
        schedule: [Int],
        options: ParallaxAlignmentOptions,
        cancellation: AnalysisCancellationToken?,
        progress: (@Sendable (Double) -> Void)?
    ) throws -> ParallaxAlignmentResult {
        try checkCancellation(cancellation)
        let count = preprocessing.brightFieldPixelCount
        let planeCount = preprocessing.stackHeight * preprocessing.stackWidth
        guard count > 0,
              preprocessing.normalizedStack.count == count * planeCount,
              preprocessing.incoherentBF.count == planeCount,
              preprocessing.edgeWindow.count
                == preprocessing.scanHeight * preprocessing.scanWidth else {
            throw AlignmentError.invalidInput("preprocessing arrays are inconsistent")
        }
        guard options.maxWorkingBytes > 0 else {
            throw AlignmentError.invalidInput("the working-memory limit is not positive")
        }
        guard alignmentBin > 0 else {
            throw AlignmentError.invalidInput("the alignment bin is not positive")
        }
        guard options.upsampleFactor == 1 || options.upsampleFactor > 2 else {
            throw AlignmentError.invalidInput(
                "the correlation upsample factor must be 1 or greater than 2"
            )
        }
        if let previous {
            guard previous.scanHeight == preprocessing.scanHeight,
                  previous.scanWidth == preprocessing.scanWidth,
                  previous.stackHeight == preprocessing.stackHeight,
                  previous.stackWidth == preprocessing.stackWidth,
                  previous.shiftedStack.count == count * planeCount,
                  previous.shiftedMasks.count == count * planeCount,
                  previous.totalShifts.count == count,
                  previous.alignedBF.count == planeCount else {
                throw AlignmentError.invalidInput(
                    "the prior alignment arrays do not match preprocessing"
                )
            }
        }
        let levelGroups = groups(
            detectorIndices: preprocessing.detectorIndices,
            alignmentBin: alignmentBin,
            centered: options.centeredAlignmentBins
        )
        guard !levelGroups.isEmpty else {
            throw AlignmentError.invalidInput("no bright-field groups were formed")
        }

        let stackBytes = preprocessing.stackByteCount
        let fftWorkBytes = planeCount * MemoryLayout<Float>.stride * 12
        let (threeStacks, overflow1) = stackBytes.multipliedReportingOverflow(by: 3)
        let (peakBytes, overflow2) = threeStacks.addingReportingOverflow(fftWorkBytes)
        guard !overflow1, !overflow2 else {
            throw AlignmentError.invalidInput("working dimensions overflow")
        }
        guard peakBytes <= options.maxWorkingBytes else {
            throw AlignmentError.memoryLimit(bytes: peakBytes, limit: options.maxWorkingBytes)
        }
        guard let fft = FFT2D(nx: preprocessing.stackWidth,
                              ny: preprocessing.stackHeight) else {
            throw AlignmentError.fftUnavailable
        }

        let inputStack = previous?.shiftedStack ?? preprocessing.normalizedStack
        let inputMasks = previous?.shiftedMasks
        let priorShifts = previous?.totalShifts ?? [ParallaxScanShift](
            repeating: ParallaxScanShift(row: 0, column: 0), count: count
        )
        var referenceRe = previous?.alignedBF ?? preprocessing.incoherentBF
        var referenceIm = [Float](repeating: 0, count: planeCount)
        fft.transform(re: &referenceRe, im: &referenceIm, forward: true)
        var rawShifts = [ParallaxScanShift](
            repeating: ParallaxScanShift(row: 0, column: 0), count: count
        )
        var groupShifts = [ParallaxScanShift]()
        groupShifts.reserveCapacity(levelGroups.count)
        let totalUnits = max(1, levelGroups.count + count)
        var completedUnits = 0

        for (groupNumber, group) in levelGroups.enumerated() {
            try checkCancellation(cancellation)
            var groupRe = [Float](repeating: 0, count: planeCount)
            for member in group.memberIndices {
                let source = member * planeCount
                for pixel in 0..<planeCount {
                    groupRe[pixel] += inputStack[source + pixel]
                }
            }
            let inverseCount = 1 / Float(group.memberIndices.count)
            var scale = inverseCount
            vDSP_vsmul(groupRe, 1, &scale, &groupRe, 1,
                       vDSP_Length(planeCount))
            var groupIm = [Float](repeating: 0, count: planeCount)
            fft.transform(re: &groupRe, im: &groupIm, forward: true)

            let shift = correlationShift(
                referenceRe: referenceRe, referenceIm: referenceIm,
                movingRe: groupRe, movingIm: groupIm, fft: fft,
                upsampleFactor: options.upsampleFactor
            )
            groupShifts.append(shift)
            for member in group.memberIndices { rawShifts[member] = shift }

            if options.runningAverage {
                applyShiftOperator(
                    re: &groupRe, im: &groupIm,
                    rowShift: shift.row, columnShift: shift.column,
                    width: preprocessing.stackWidth, height: preprocessing.stackHeight
                )
                let previousWeight = Float(groupNumber) / Float(groupNumber + 1)
                let newWeight = 1 / Float(groupNumber + 1)
                for pixel in 0..<planeCount {
                    referenceRe[pixel] = referenceRe[pixel] * previousWeight
                        + groupRe[pixel] * newWeight
                    referenceIm[pixel] = referenceIm[pixel] * previousWeight
                        + groupIm[pixel] * newWeight
                }
            }
            completedUnits += 1
            progress?(Double(completedUnits) / Double(totalUnits))
        }

        let candidateShifts = zip(priorShifts, rawShifts).map { pair in
            ParallaxScanShift(
                row: pair.0.row + pair.1.row,
                column: pair.0.column + pair.1.column
            )
        }
        let fittedShifts = try fitDefaultShiftBasis(
            reciprocalVectors: preprocessing.reciprocalVectors,
            rawShifts: candidateShifts
        )
        let incrementalShifts = zip(fittedShifts, priorShifts).map { pair in
            ParallaxScanShift(
                row: pair.0.row - pair.1.row,
                column: pair.0.column - pair.1.column
            )
        }
        var shiftedStack = [Float](repeating: 0,
                                   count: inputStack.count)
        var shiftedMasks = [Float](repeating: 0,
                                   count: inputStack.count)
        let baseMask = paddedMask(preprocessing)
        for bf in 0..<count {
            try checkCancellation(cancellation)
            let source = bf * planeCount
            let shiftedImage = fourierShift(
                Array(inputStack[source..<(source + planeCount)]),
                shift: incrementalShifts[bf], fft: fft,
                width: preprocessing.stackWidth, height: preprocessing.stackHeight
            )
            let mask = inputMasks.map {
                Array($0[source..<(source + planeCount)])
            } ?? baseMask
            let shiftedMask = fourierShift(
                mask, shift: incrementalShifts[bf], fft: fft,
                width: preprocessing.stackWidth, height: preprocessing.stackHeight
            )
            shiftedStack.replaceSubrange(source..<(source + planeCount), with: shiftedImage)
            shiftedMasks.replaceSubrange(source..<(source + planeCount), with: shiftedMask)
            completedUnits += 1
            progress?(Double(completedUnits) / Double(totalUnits))
        }
        try checkCancellation(cancellation)

        let medianRow = Int(median(fittedShifts.map(\.row)).rounded(.toNearestOrEven))
        let medianColumn = Int(median(fittedShifts.map(\.column)).rounded(.toNearestOrEven))
        let centeredShifts = fittedShifts.map {
            ParallaxScanShift(row: $0.row - Float(medianRow),
                              column: $0.column - Float(medianColumn))
        }
        if medianRow != 0 || medianColumn != 0 {
            shiftedStack = rollPlanes(
                shiftedStack, planeCount: planeCount, count: count,
                width: preprocessing.stackWidth, height: preprocessing.stackHeight,
                rowShift: -medianRow, columnShift: -medianColumn
            )
            shiftedMasks = rollPlanes(
                shiftedMasks, planeCount: planeCount, count: count,
                width: preprocessing.stackWidth, height: preprocessing.stackHeight,
                rowShift: -medianRow, columnShift: -medianColumn
            )
        }

        let stackMean = Float(
            Double(preprocessing.normalizedStack.reduce(0, +))
                / Double(preprocessing.normalizedStack.count)
        )
        let maskSum = preprocessing.edgeWindow.reduce(0, +) * Float(count)
        guard stackMean.isFinite, stackMean > 0, maskSum > 0 else {
            throw AlignmentError.invalidInput("normalization statistics are not positive")
        }
        var reconstructionMask = [Float](repeating: 0, count: planeCount)
        var aligned = [Float](repeating: 0, count: planeCount)
        for pixel in 0..<planeCount {
            var maskAverage: Float = 0
            var weightedAverage: Float = 0
            for bf in 0..<count {
                let index = bf * planeCount + pixel
                maskAverage += shiftedMasks[index]
                weightedAverage += shiftedStack[index] * shiftedMasks[index]
            }
            maskAverage /= Float(count)
            weightedAverage /= Float(count)
            reconstructionMask[pixel] = maskAverage
            let maskInverse = 1 - min(max(maskAverage, 0), 1)
            aligned[pixel] = (stackMean * maskInverse + weightedAverage)
                / (maskAverage + maskInverse)
        }
        var errorSum: Double = 0
        for bf in 0..<count {
            let plane = bf * planeCount
            for pixel in 0..<planeCount {
                errorSum += Double(
                    abs(shiftedStack[plane + pixel] - aligned[pixel])
                        * shiftedMasks[plane + pixel]
                )
            }
        }
        let error = Float(errorSum / Double(maskSum) / Double(stackMean))
        try checkCancellation(cancellation)
        progress?(1)
        var completedBins = previous?.completedBins ?? []
        completedBins.append(alignmentBin)
        var errorHistory = previous?.errorHistory ?? [preprocessing.initialError]
        errorHistory.append(error)
        return ParallaxAlignmentResult(
            alignmentBin: alignmentBin, alignmentSchedule: schedule,
            completedBins: completedBins,
            upsampleFactor: options.upsampleFactor, groups: levelGroups,
            groupShifts: groupShifts, totalShifts: centeredShifts,
            shiftedStack: shiftedStack, shiftedMasks: shiftedMasks,
            reconstructionMask: reconstructionMask, alignedBF: aligned,
            errorHistory: errorHistory,
            scanHeight: preprocessing.scanHeight, scanWidth: preprocessing.scanWidth,
            stackHeight: preprocessing.stackHeight, stackWidth: preprocessing.stackWidth
        )
    }

    private struct BinCoordinate: Hashable {
        package let row: Int
        package let column: Int
    }

    private static func correlationShift(
        referenceRe: [Float], referenceIm: [Float],
        movingRe: [Float], movingIm: [Float], fft: FFT2D,
        upsampleFactor: Int
    ) -> ParallaxScanShift {
        var correlationRe = [Float](repeating: 0, count: referenceRe.count)
        var correlationIm = [Float](repeating: 0, count: referenceRe.count)
        for index in referenceRe.indices {
            // reference * conjugate(moving)
            correlationRe[index] = referenceRe[index] * movingRe[index]
                + referenceIm[index] * movingIm[index]
            correlationIm[index] = referenceIm[index] * movingRe[index]
                - referenceRe[index] * movingIm[index]
        }
        if upsampleFactor > 2 {
            let peak = MatrixDFTCorrelation.refinedPeak(
                correlationRe: correlationRe, correlationIm: correlationIm,
                width: fft.nx, height: fft.ny, fft: fft,
                upsampleFactor: upsampleFactor
            )
            return ParallaxScanShift(
                row: wrappedShift(value: peak.row, size: fft.ny),
                column: wrappedShift(value: peak.column, size: fft.nx)
            )
        }
        fft.transform(re: &correlationRe, im: &correlationIm,
                      forward: false, scaleInverse: true)
        var peak = 0
        for index in 1..<correlationRe.count where correlationRe[index] > correlationRe[peak] {
            peak = index
        }
        let row = peak / fft.nx
        let column = peak % fft.nx
        return ParallaxScanShift(
            row: wrappedShift(index: row, size: fft.ny),
            column: wrappedShift(index: column, size: fft.nx)
        )
    }

    private static func fitDefaultShiftBasis(
        reciprocalVectors: [ParallaxVector], rawShifts: [ParallaxScanShift]
    ) throws -> [ParallaxScanShift] {
        guard reciprocalVectors.count == rawShifts.count else {
            throw AlignmentError.invalidInput("shift basis length differs")
        }
        var xx: Double = 0, xy: Double = 0, yy: Double = 0
        var xRow: Double = 0, yRow: Double = 0
        var xColumn: Double = 0, yColumn: Double = 0
        for (vector, shift) in zip(reciprocalVectors, rawShifts) {
            let x = Double(vector.qx), y = Double(vector.qy)
            xx += x * x; xy += x * y; yy += y * y
            xRow += x * Double(shift.row); yRow += y * Double(shift.row)
            xColumn += x * Double(shift.column); yColumn += y * Double(shift.column)
        }
        let determinant = xx * yy - xy * xy
        guard determinant.isFinite,
              abs(determinant) > max(1e-20, (xx + yy) * 1e-12) else {
            throw AlignmentError.singularShiftBasis
        }
        let rowX = (yy * xRow - xy * yRow) / determinant
        let rowY = (-xy * xRow + xx * yRow) / determinant
        let columnX = (yy * xColumn - xy * yColumn) / determinant
        let columnY = (-xy * xColumn + xx * yColumn) / determinant
        return reciprocalVectors.map {
            ParallaxScanShift(
                row: Float(Double($0.qx) * rowX + Double($0.qy) * rowY),
                column: Float(Double($0.qx) * columnX + Double($0.qy) * columnY)
            )
        }
    }

    private static func fourierShift(
        _ input: [Float], shift: ParallaxScanShift, fft: FFT2D,
        width: Int, height: Int
    ) -> [Float] {
        var re = input
        var im = [Float](repeating: 0, count: input.count)
        fft.transform(re: &re, im: &im, forward: true)
        applyShiftOperator(re: &re, im: &im,
                           rowShift: shift.row, columnShift: shift.column,
                           width: width, height: height)
        fft.transform(re: &re, im: &im, forward: false, scaleInverse: true)
        return re
    }

    private static func applyShiftOperator(
        re: inout [Float], im: inout [Float],
        rowShift: Float, columnShift: Float, width: Int, height: Int
    ) {
        for rowFrequency in 0..<height {
            let fy = FFT2D.fftfreq(rowFrequency, height)
            for columnFrequency in 0..<width {
                let fx = FFT2D.fftfreq(columnFrequency, width)
                let index = rowFrequency * width + columnFrequency
                let angle = -2 * Float.pi * (fy * rowShift + fx * columnShift)
                let cosine = cos(angle), sine = sin(angle)
                let oldRe = re[index], oldIm = im[index]
                re[index] = oldRe * cosine - oldIm * sine
                im[index] = oldRe * sine + oldIm * cosine
            }
        }
    }

    private static func paddedMask(_ preprocessing: ParallaxPreprocessResult) -> [Float] {
        var mask = [Float](repeating: 0,
                           count: preprocessing.stackHeight * preprocessing.stackWidth)
        let top = (preprocessing.stackHeight - preprocessing.scanHeight) / 2
        let left = (preprocessing.stackWidth - preprocessing.scanWidth) / 2
        for row in 0..<preprocessing.scanHeight {
            let source = row * preprocessing.scanWidth
            let destination = (top + row) * preprocessing.stackWidth + left
            mask.replaceSubrange(
                destination..<(destination + preprocessing.scanWidth),
                with: preprocessing.edgeWindow[source..<(source + preprocessing.scanWidth)]
            )
        }
        return mask
    }

    private static func rollPlanes(
        _ input: [Float], planeCount: Int, count: Int,
        width: Int, height: Int, rowShift: Int, columnShift: Int
    ) -> [Float] {
        var output = [Float](repeating: 0, count: input.count)
        for plane in 0..<count {
            let base = plane * planeCount
            for row in 0..<height {
                let sourceRow = positiveModulo(row - rowShift, height)
                for column in 0..<width {
                    let sourceColumn = positiveModulo(column - columnShift, width)
                    output[base + row * width + column]
                        = input[base + sourceRow * width + sourceColumn]
                }
            }
        }
        return output
    }

    private static func wrappedShift(index: Int, size: Int) -> Float {
        let half = Float(size) / 2
        return positiveModulo(Float(index) + half, Float(size)) - half
    }

    private static func wrappedShift(value: Float, size: Int) -> Float {
        let half = Float(size) / 2
        return positiveModulo(value + half, Float(size)) - half
    }

    private static func positiveModulo(_ value: Int, _ modulus: Int) -> Int {
        let remainder = value % modulus
        return remainder >= 0 ? remainder : remainder + modulus
    }

    private static func positiveModulo(_ value: Float, _ modulus: Float) -> Float {
        let remainder = value.truncatingRemainder(dividingBy: modulus)
        return remainder >= 0 ? remainder : remainder + modulus
    }

    private static func median(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }

    private static func checkCancellation(
        _ cancellation: AnalysisCancellationToken?
    ) throws {
        if cancellation?.isCancelled == true { throw AlignmentError.cancelled }
    }
}
