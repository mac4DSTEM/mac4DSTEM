import Foundation

struct LevelFixture: Decodable {
    let alignmentBin: Int
    let groups: [[[Int]]]
    let groupShifts: [[Float]]
    let totalShifts: [Float]
    let shiftedStack: [Float]
    let shiftedMasks: [Float]
    let reconstructionMask: [Float]
    let alignedBF: [Float]
    let error: Float

    private enum CodingKeys: String, CodingKey {
        case alignmentBin, groups, groupShifts, totalShifts, shiftedStack
        case shiftedMasks, reconstructionMask, alignedBF, error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        alignmentBin = try container.decode(Int.self, forKey: .alignmentBin)
        // JSON group rows are [rowBin, columnBin, [members]], which is easier
        // to decode through a small untyped bridge below.
        let raw = try container.decode([RawGroup].self, forKey: .groups)
        groups = raw.map { [[ $0.row ], [ $0.column ], $0.members] }
        groupShifts = try container.decode([[Float]].self, forKey: .groupShifts)
        totalShifts = try container.decode([Float].self, forKey: .totalShifts)
        shiftedStack = try container.decode([Float].self, forKey: .shiftedStack)
        shiftedMasks = try container.decode([Float].self, forKey: .shiftedMasks)
        reconstructionMask = try container.decode([Float].self, forKey: .reconstructionMask)
        alignedBF = try container.decode([Float].self, forKey: .alignedBF)
        error = try container.decode(Float.self, forKey: .error)
    }

    struct RawGroup: Decodable {
        let row: Int
        let column: Int
        let members: [Int]

        init(from decoder: Decoder) throws {
            var values = try decoder.unkeyedContainer()
            row = try values.decode(Int.self)
            column = try values.decode(Int.self)
            members = try values.decode([Int].self)
        }
    }
}

struct Fixture: Decodable {
    let scanShape: [Int]
    let stackShape: [Int]
    let detectorIndices: [[Int]]
    let reciprocalVectors: [Float]
    let edgeWindow: [Float]
    let normalizedStack: [Float]
    let incoherentBF: [Float]
    let initialError: Float
    let defaultSchedule: [Int]
    let intendedContentShifts: [Float]
    let levels: [LevelFixture]
    let multilevel: [LevelFixture]
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw NSError(
            domain: "parallax-alignment-test", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}

func maximumError(_ actual: [Float], _ expected: [Float]) -> Float {
    guard actual.count == expected.count else { return .infinity }
    return zip(actual, expected).reduce(0) { max($0, abs($1.0 - $1.1)) }
}

@main
struct Harness {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw NSError(domain: "arguments", code: 1)
        }
        let fixture = try JSONDecoder().decode(
            Fixture.self,
            from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        )
        let indices = fixture.detectorIndices.map {
            ParallaxDetectorIndex(qx: $0[0], qy: $0[1])
        }
        let vectors = stride(from: 0, to: fixture.reciprocalVectors.count, by: 2).map {
            ParallaxVector(qx: fixture.reciprocalVectors[$0],
                           qy: fixture.reciprocalVectors[$0 + 1])
        }
        let calibration = ParallaxPhysicalCalibration(
            scanSamplingAngstrom: 2, reciprocalSamplingInvAngstrom: 0.05,
            energyEV: 200_000, wavelengthAngstrom: 0.025079,
            originQX: 3, originQY: 3, rotationRad: 0, transpose: false
        )
        let detectorHeight = 7, detectorWidth = 7
        var detectorMask = [Bool](repeating: false,
                                  count: detectorHeight * detectorWidth)
        for index in indices { detectorMask[index.qx * detectorWidth + index.qy] = true }
        let preprocessing = ParallaxPreprocessResult(
            scanHeight: fixture.scanShape[0], scanWidth: fixture.scanShape[1],
            detectorHeight: detectorHeight, detectorWidth: detectorWidth,
            stackHeight: fixture.stackShape[1], stackWidth: fixture.stackShape[2],
            calibration: calibration, thresholdIntensity: 0.8,
            detectorMask: detectorMask, detectorIndices: indices,
            reciprocalVectors: vectors,
            probeAnglesMrad: vectors.map {
                ParallaxVector(qx: $0.qx * 25.079, qy: $0.qy * 25.079)
            },
            edgeWindow: fixture.edgeWindow,
            normalizedStack: fixture.normalizedStack,
            unshiftedStack: fixture.normalizedStack,
            incoherentBF: fixture.incoherentBF,
            initialError: fixture.initialError
        )
        let originalStack = preprocessing.normalizedStack

        try require(
            ParallaxAligner.defaultBinSchedule(detectorIndices: indices)
                == fixture.defaultSchedule,
            "default coarse-to-fine bin schedule differs"
        )
        try require(
            fixture.intendedContentShifts.contains { abs($0) > 0.1 && abs($0.rounded() - $0) > 0.1 }
                && fixture.intendedContentShifts.contains { $0 < 0 }
                && fixture.intendedContentShifts.contains { $0 > 0 },
            "fixture does not exercise known positive/negative fractional shifts"
        )
        print("PASS: default alignment-bin schedule \(fixture.defaultSchedule)")

        for expected in fixture.levels {
            var options = ParallaxAlignmentOptions()
            options.alignmentBin = expected.alignmentBin
            options.maxWorkingBytes = 128 * 1_024 * 1_024
            let actual = try ParallaxAligner.alignOneLevel(
                preprocessing: preprocessing, options: options
            )
            let actualGroups = actual.groups.map {
                [[ $0.rowBin ], [ $0.columnBin ], $0.memberIndices]
            }
            try require(actualGroups == expected.groups,
                        "group membership/order differs at bin \(expected.alignmentBin)")
            let groupShifts = actual.groupShifts.flatMap { [$0.row, $0.column] }
            let expectedGroupShifts = expected.groupShifts.flatMap { $0 }
            try require(maximumError(groupShifts, expectedGroupShifts) < 1e-5,
                        "integer group shifts differ at bin \(expected.alignmentBin)")
            let totalShifts = actual.totalShifts.flatMap { [$0.row, $0.column] }
            try require(maximumError(totalShifts, expected.totalShifts) < 2e-4,
                        "fitted/centered shifts differ at bin \(expected.alignmentBin)")
            let stackError = maximumError(actual.shiftedStack, expected.shiftedStack)
            let maskError = maximumError(actual.shiftedMasks, expected.shiftedMasks)
            let bfError = maximumError(actual.alignedBF, expected.alignedBF)
            try require(stackError < 2e-4, "shifted stack differs: \(stackError)")
            try require(maskError < 2e-4, "shifted masks differ: \(maskError)")
            try require(maximumError(actual.reconstructionMask,
                                     expected.reconstructionMask) < 2e-4,
                        "reconstruction mask differs")
            try require(bfError < 2e-4, "aligned BF differs: \(bfError)")
            try require(abs(actual.currentError - expected.error) < 2e-4,
                        "alignment error differs")
            print("PASS: bin \(expected.alignmentBin) groups/shifts/stack/BF, max \(max(stackError, bfError))")
        }
        try require(preprocessing.normalizedStack == originalStack,
                    "alignment mutated preprocessing input")
        print("PASS: alignment input remains immutable")

        var prior: ParallaxAlignmentResult?
        var completedBins: [Int] = []
        for expected in fixture.multilevel {
            var options = ParallaxAlignmentOptions()
            options.upsampleFactor = 8
            options.maxWorkingBytes = 128 * 1_024 * 1_024
            let actual = try ParallaxAligner.alignNextLevel(
                preprocessing: preprocessing, previous: prior, options: options
            )
            completedBins.append(expected.alignmentBin)
            try require(actual.completedBins == completedBins,
                        "completed-bin state differs")
            try require(actual.alignmentSchedule == fixture.defaultSchedule,
                        "result schedule differs")
            try require(actual.upsampleFactor == 8,
                        "subpixel factor was not retained")
            let actualGroups = actual.groups.map {
                [[ $0.rowBin ], [ $0.columnBin ], $0.memberIndices]
            }
            try require(actualGroups == expected.groups,
                        "multilevel groups differ at bin \(expected.alignmentBin)")
            let groupShifts = actual.groupShifts.flatMap { [$0.row, $0.column] }
            let expectedGroupShifts = expected.groupShifts.flatMap { $0 }
            let groupError = maximumError(groupShifts, expectedGroupShifts)
            try require(groupError < 8e-3,
                        "subpixel group shifts differ: \(groupError)")
            let totalShifts = actual.totalShifts.flatMap { [$0.row, $0.column] }
            let shiftError = maximumError(totalShifts, expected.totalShifts)
            let stackError = maximumError(actual.shiftedStack, expected.shiftedStack)
            let maskError = maximumError(actual.shiftedMasks, expected.shiftedMasks)
            let bfError = maximumError(actual.alignedBF, expected.alignedBF)
            try require(shiftError < 5e-3,
                        "cumulative shifts differ: \(shiftError)")
            try require(stackError < 1e-3,
                        "continued shifted stack differs: \(stackError)")
            try require(maskError < 2e-3,
                        "continued shifted masks differ: \(maskError)")
            try require(maximumError(actual.reconstructionMask,
                                     expected.reconstructionMask) < 2e-3,
                        "continued reconstruction mask differs")
            try require(bfError < 2e-4,
                        "continued aligned BF differs: \(bfError)")
            try require(abs(actual.currentError - expected.error) < 2e-4,
                        "continued error differs")
            try require(actual.errorHistory.count == completedBins.count + 1,
                        "convergence history did not append one level")
            print("PASS: factor-8 bin \(expected.alignmentBin), peak \(groupError), cumulative \(shiftError), stack \(stackError), mask \(maskError), BF \(bfError)")
            prior = actual
        }
        try require(prior?.isComplete == true,
                    "final level did not complete the schedule")
        try require(prior?.nextAlignmentBin == nil,
                    "completed schedule still advertises a next bin")
        do {
            _ = try ParallaxAligner.alignNextLevel(
                preprocessing: preprocessing, previous: prior
            )
            try require(false, "completed schedule accepted another level")
        } catch ParallaxAligner.AlignmentError.alignmentComplete {}

        var subpixel = ParallaxAlignmentOptions()
        subpixel.upsampleFactor = 8
        let resetCoarse = try ParallaxAligner.alignNextLevel(
            preprocessing: preprocessing, options: subpixel
        )
        let firstCoarse = try ParallaxAligner.alignNextLevel(
            preprocessing: preprocessing, options: subpixel
        )
        try require(resetCoarse.completedBins == [fixture.defaultSchedule[0]],
                    "reset did not restart at the coarsest bin")
        try require(maximumError(resetCoarse.shiftedStack,
                                 firstCoarse.shiftedStack) == 0,
                    "fresh starts do not reproduce the coarse result")
        print("PASS: completion boundary and reset reproduce coarse alignment")

        do {
            let first = resetCoarse
            let retainedStack = first.shiftedStack
            let retainedHistory = first.errorHistory
            let levelCancellation = AnalysisCancellationToken()
            do {
                _ = try ParallaxAligner.alignNextLevel(
                    preprocessing: preprocessing, previous: first,
                    options: subpixel, cancellation: levelCancellation
                ) { fraction in
                    if fraction > 0.1 { levelCancellation.cancel() }
                }
                try require(false, "cancelled continuation published a result")
            } catch ParallaxAligner.AlignmentError.cancelled {}
            try require(first.shiftedStack == retainedStack
                            && first.errorHistory == retainedHistory,
                        "cancelled continuation mutated the completed level")
        }
        print("PASS: cancelled continuation retains the completed level")

        let cancelled = AnalysisCancellationToken()
        do {
            _ = try ParallaxAligner.alignOneLevel(
                preprocessing: preprocessing, cancellation: cancelled
            ) { fraction in
                if fraction > 0.1 { cancelled.cancel() }
            }
            try require(false, "cancelled alignment published a result")
        } catch ParallaxAligner.AlignmentError.cancelled {}

        var tiny = ParallaxAlignmentOptions()
        tiny.maxWorkingBytes = 1
        do {
            _ = try ParallaxAligner.alignOneLevel(
                preprocessing: preprocessing, options: tiny
            )
            try require(false, "alignment memory limit was ignored")
        } catch ParallaxAligner.AlignmentError.memoryLimit {}
        print("PASS: cancellation and memory limit reject partial alignment")

        print("parallax-alignment-test: all passed")
    }
}
