//
//  CompiledModelCacheTests.swift
//  The detector model is compiled once per weights and kept at one path. Before, every load compiled to a new
//  temporary folder, and Core ML's on-disk cache of device-specialised models
//  (`Caches/<bundle id>/com.apple.e5rt.e5bundlecache`) added entries on every load: 26 GB on the development Mac.
//

import XCTest
import CoreML
import DSTEMCore

final class CompiledModelCacheTests: XCTestCase {

    private let sha = String(repeating: "a", count: 64)

    func testAModelIsCompiledOnceAndKeptAtOnePath() async throws {
        let cache = CompiledModelCache(directory: try TrainingTestSupport.tempDirectory(self))
        let first = try await cache.compiledModel(forAsset: LearnedSwiftFixture.assetURL, sha256: sha)
        XCTAssertEqual(first, cache.location(sha256: sha))
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        // A marker in the kept copy: a second compile would replace the folder and lose it.
        let marker = first.appendingPathComponent("kept-marker")
        try Data().write(to: marker)

        let second = try await cache.compiledModel(forAsset: LearnedSwiftFixture.assetURL, sha256: sha)
        XCTAssertEqual(second, first, "the same weights load from the same path")
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path), "and nothing was compiled again")

        // A kept copy that would not load is replaced, at the same path.
        let again = try await cache.compiledModel(forAsset: LearnedSwiftFixture.assetURL, sha256: sha, recompiling: true)
        XCTAssertEqual(again, first)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        let config = MLModelConfiguration()
        config.computeUnits = .cpuOnly
        XCTAssertNoThrow(try MLModel(contentsOf: again, configuration: config))
    }

    func testTheFolderHoldsAtMostTheLimitAndKeepsTheModelInUse() async throws {
        let directory = try TrainingTestSupport.tempDirectory(self)
        let fm = FileManager.default
        for i in 0..<6 {
            let stale = directory.appendingPathComponent("stale\(i).mlmodelc", isDirectory: true)
            try fm.createDirectory(at: stale, withIntermediateDirectories: true)
            try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: Double(-1000 - i * 100))], ofItemAtPath: stale.path)
        }
        let other = directory.appendingPathComponent("not-a-model.txt")
        try Data().write(to: other)

        let cache = CompiledModelCache(directory: directory)
        let kept = try await cache.compiledModel(forAsset: LearnedSwiftFixture.assetURL, sha256: sha)

        let models = try fm.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".mlmodelc") }.sorted()
        XCTAssertEqual(models.count, CompiledModelCache.limit)
        XCTAssertTrue(models.contains(kept.lastPathComponent), "the model just asked for stays")
        XCTAssertEqual(Set(models).subtracting([kept.lastPathComponent]), ["stale0.mlmodelc", "stale1.mlmodelc", "stale2.mlmodelc"],
                       "the most recently used of the others stay")
        XCTAssertTrue(fm.fileExists(atPath: other.path), "only compiled models are removed")
    }

    /// The app's load, three times. The first may compile and may add to Core ML's cache; the second and the third
    /// load the kept copy, and the third adds nothing the second did not. The printed counts are the record.
    func testRepeatingALoadAddsNothingToCoreMLsCache() async throws {
        let units: MLComputeUnits = LearnedSwiftFixture.hasNeuralEngine ? .cpuAndNeuralEngine : .cpuOnly
        var counts: [Int] = []
        var paths: [URL] = []
        for _ in 0..<3 {
            let detector = try await LearnedDiskDetector.loadForComparison(assetURL: LearnedSwiftFixture.assetURL, computeUnits: units)
            paths.append(detector.compiledURL)
            counts.append(Self.coreMLCacheEntryCount())
        }
        print("Core ML e5 bundle cache entries after loads 1, 2, 3 (compute units \(units.rawValue)): \(counts)")
        XCTAssertEqual(Set(paths).count, 1, "every load opens the one kept compiled model")
        XCTAssertEqual(paths.first, CompiledModelCache.shared.location(sha256: try LearnedDiskDetector.sha256(ofAsset: LearnedSwiftFixture.assetURL)))
        XCTAssertEqual(counts[2], counts[1], "a repeated load added entries to Core ML's cache")
    }

    /// The entries of `Caches/<bundle id>/com.apple.e5rt.e5bundlecache/<OS build>/`; 0 when the folder is absent.
    private static func coreMLCacheEntryCount() -> Int {
        let fm = FileManager.default
        guard let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else { return 0 }
        let root = caches
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.mac4dstem.mac4DSTEM", isDirectory: true)
            .appendingPathComponent("com.apple.e5rt.e5bundlecache", isDirectory: true)
        let builds = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return builds.reduce(0) { $0 + ((try? fm.contentsOfDirectory(atPath: $1.path).count) ?? 0) }
    }
}
