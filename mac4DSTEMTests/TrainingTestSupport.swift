//
//  TrainingTestSupport.swift
//  Shared helpers for the DSTEMTraining tests (Phase C4a): the bundled package, the fixture's hand-drawn
//  truth in the 256 frame, temporary directories and a thread-safe recorder.
//

import XCTest
import DSTEMCore
import DSTEMTraining

enum TrainingTestSupport {
    static var bundledPackage: URL { get throws {
        let url = LearnedSwiftFixture.assetURL
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("no committed asset at \(url.path)") }
        return url
    } }

    /// A fresh directory under the temp dir, removed by the caller's teardown block.
    static func tempDirectory(_ test: XCTestCase) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mac4dstem-training-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        test.addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private struct TruthFile: Decodable { struct T: Decodable { let centres: [[Double]] }; let truth: [T] }

    /// The fixture's drawn centres of pattern `index`, (row, col), mapped from the native 128 frame into the 256 model frame.
    static func fixtureCentres(_ index: Int, fixture: LearnedSwiftFixture) throws -> [ScorePoint] {
        let url = LearnedSwiftFixture.repo.appendingPathComponent("tools/disk-detector/fixture/expected.json")
        let file = try JSONDecoder().decode(TruthFile.self, from: Data(contentsOf: url))
        let r0 = Double(fixture.expected.fit_offset[0]), c0 = Double(fixture.expected.fit_offset[1])
        return file.truth[index].centres.map { ScorePoint(row: $0[0] - r0, col: $0[1] - c0) }
    }

    /// The fixture's two reference patterns as training samples (their model inputs from Python, their drawn centres).
    static func fixtureSamples(_ fixture: LearnedSwiftFixture) throws -> [TrainingSample] {
        try fixture.expected.inputs_ref_indices.enumerated().map { k, index in
            TrainingSample(position: ScanPosition(ry: 0, rx: index), inputs: fixture.inputsRef[k],
                           centres: try fixtureCentres(index, fixture: fixture))
        }
    }
}

/// Collects values from `@Sendable` callbacks.
nonisolated final class TrainingRecorder<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [T] = []
    func add(_ x: T) { lock.lock(); items.append(x); lock.unlock() }
    var values: [T] { lock.lock(); defer { lock.unlock() }; return items }
}
