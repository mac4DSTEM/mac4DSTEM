//
//  ModelCacheUsageTests.swift
//  mac4DSTEM#179: Settings shows the entries and size of Core ML's e5 bundle cache and of the compiled detector models,
//  which a sandboxed build keeps where Terminal cannot look. Counted on a planted Caches folder.
//

import XCTest
import DSTEMCore

final class ModelCacheUsageTests: XCTestCase {
    /// Core ML's entries sit one level below the per-build folder; the compiled models are the folder's children.
    /// Mutation: count the e5 cache at depth 1 (the build folders, 2) - red; drop a file's bytes - red.
    func testBothCachesAreCountedAndSized() throws {
        let caches = try TrainingTestSupport.tempDirectory(self)
        let fm = FileManager.default
        func file(_ path: String, bytes: Int) throws {
            let url = caches.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(count: bytes).write(to: url)
        }
        for build in ["25A1", "25B2"] {
            for entry in 0..<3 { try file("com.apple.e5rt.e5bundlecache/\(build)/entry\(entry)/bundle.bin", bytes: 10_000) }
        }
        try file("DiskDetectorCompiled/aaaa.mlmodelc/model.mil", bytes: 50_000)
        try file("DiskDetectorCompiled/bbbb.mlmodelc/weights/weight.bin", bytes: 70_000)

        let usage = ModelCacheUsage.measure(appCaches: caches)
        XCTAssertEqual(usage.coreML?.entries, 6)
        XCTAssertEqual(usage.compiledModels?.entries, 2)
        // Allocated sizes are whole blocks, so at least the bytes written and less than a block more per file.
        let coreMLBytes = try XCTUnwrap(usage.coreML?.bytes)
        XCTAssertGreaterThanOrEqual(coreMLBytes, 60_000)
        XCTAssertLessThan(coreMLBytes, 60_000 + 6 * 65_536)
        let compiledBytes = try XCTUnwrap(usage.compiledModels?.bytes)
        XCTAssertGreaterThanOrEqual(compiledBytes, 120_000)
        XCTAssertLessThan(compiledBytes, 120_000 + 2 * 65_536)
    }

    func testAnAbsentCacheReadsNone() throws {
        let usage = ModelCacheUsage.measure(appCaches: try TrainingTestSupport.tempDirectory(self))
        XCTAssertNil(usage.coreML)
        XCTAssertNil(usage.compiledModels)
        XCTAssertEqual(ModelCacheUsage.text(nil), "None")
        XCTAssertTrue(ModelCacheUsage.text(.init(entries: 1, bytes: 0)).hasPrefix("1 entry, "))
    }
}
