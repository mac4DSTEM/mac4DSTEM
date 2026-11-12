//
//  TrainingTestSupport.swift
//  Shared helpers for the DSTEMTraining tests (Phase C4a): the bundled package, the fixture's hand-drawn
//  truth in the 256 frame, temporary directories and a thread-safe recorder.
//

import XCTest
import DSTEMTraining

enum TrainingTestSupport {
    static var bundledPackage: URL { get throws {
        let url = LearnedSwiftFixture.assetURL
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("no committed asset at \(url.path)") }
        return url
    } }

    /// A fresh directory under the temp dir, removed by the caller's teardown block. The same block removes what the
    /// test added to Core ML's cache (`CoreMLTestCache`): the models a test compiles live in such a directory.
    static func tempDirectory(_ test: XCTestCase) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mac4dstem-training-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let before = CoreMLTestCache.entries()
        test.addTeardownBlock {
            try? FileManager.default.removeItem(at: dir)
            CoreMLTestCache.removeEntries(addedSince: before)
        }
        return dir
    }

    private struct TruthFile: Decodable { struct T: Decodable { let centres: [[Double]] }; let truth: [T] }

    /// The fixture's drawn centres of pattern `index`, (row, col), mapped from the native 128 frame into the 256 model frame.
    static func fixtureCentres(_ index: Int, fixture: LearnedSwiftFixture) throws -> [ScorePoint] {
        let url = LearnedSwiftFixture.repo.appendingPathComponent("mac4DSTEMTests/Fixtures/DiskDetector/fixture/expected.json")
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

/// Core ML's on-disk cache of device-specialised models, `Caches/<bundle id>/com.apple.e5rt.e5bundlecache/<OS build>/`.
/// The hosted tests run under the app's bundle identifier, so this is the folder of the app on the same Mac.
///
/// Measured 2026-11-12 (mac4DSTEM#178, #180): Core ML adds one entry for every freshly compiled model it loads, whatever
/// the model's path, and never removes one. The app compiles a model once and keeps it (`CompiledModelCache`), so its
/// two kept models have one entry each, launch after launch. A test that compiles a model and loads it added an entry
/// in every run, about 1 MB each. The tests therefore remove what they added.
enum CoreMLTestCache {
    static var root: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.mac4dstem.mac4DSTEM", isDirectory: true)
            .appendingPathComponent("com.apple.e5rt.e5bundlecache", isDirectory: true)
    }

    /// Every entry, in every OS build's folder; empty when the cache does not exist.
    static func entries() -> Set<URL> {
        guard let root else { return [] }
        let fm = FileManager.default
        let builds = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return Set(builds.flatMap { (try? fm.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? [] }
            .map(\.standardizedFileURL))
    }

    /// Removes the entries that are not in `before`, except an entry of a model the app keeps: that one is the app's own,
    /// made once (here when the test run is the first to load the bundled model on this Mac) and reused from then on.
    static func removeEntries(addedSince before: Set<URL>) {
        let keptModels = Data("/DiskDetectorCompiled/".utf8)
        for entry in entries().subtracting(before) where !names(entry, keptModels) {
            try? FileManager.default.removeItem(at: entry)
        }
    }

    /// Whether a file of the entry's compiled program (`*.e5`, which records the path of the model it was built from)
    /// contains `bytes`.
    private static func names(_ entry: URL, _ bytes: Data) -> Bool {
        guard let files = FileManager.default.enumerator(at: entry, includingPropertiesForKeys: nil) else { return false }
        for case let file as URL in files where file.pathExtension == "e5" {
            if let data = try? Data(contentsOf: file, options: .mappedIfSafe), data.range(of: bytes) != nil { return true }
        }
        return false
    }
}

/// Collects values from `@Sendable` callbacks.
nonisolated final class TrainingRecorder<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [T] = []
    func add(_ x: T) { lock.lock(); items.append(x); lock.unlock() }
    var values: [T] { lock.lock(); defer { lock.unlock() }; return items }
}
