//
//  ModelPackageWriterTests.swift
//  The writer that turns trained weights into a package the UNCHANGED `LearnedDiskDetector.load` runs
//  (C3 pre-registration §2, §3 step 4), and the trained-model store around it.
//
//  Round trip: the bundled weights written back must change no byte of weight.bin, give the bundled tree
//  hash, and give the loaded model the bundled model's heatmap on a fixture pattern. Break tests: negating
//  the 1x1 head's kernel must change the hash and the heatmap (a writer that wrote nothing, or wrote at the
//  wrong offset, would leave the heatmap equal and the round trip could not tell it from a good one).
//

import XCTest
import DSTEMCore
import DSTEMTraining

final class ModelPackageWriterTests: XCTestCase {

    func testTheBundledWeightsReadWithTheRecordedLayout() throws {
        let w = try DetectorWeights.load(fromPackage: try TrainingTestSupport.bundledPackage)
        XCTAssertEqual(w.w.count, 15); XCTAssertEqual(w.b.count, 14)
        XCTAssertEqual(w.parameters.map(\.count), DetectorWeights.elementCounts)
        XCTAssertEqual(w.w[14].count, 12, "the 1x1 head: 12 in-channels, 1 out")
        XCTAssertTrue(w.parameters.allSatisfy { $0.allSatisfy(\.isFinite) })
        XCTAssertGreaterThan(w.w[0].map(abs).max() ?? 0, 0)
    }

    func testWritingTheBundledWeightsBackChangesNoByte() throws {
        let bundled = try TrainingTestSupport.bundledPackage
        let dest = try TrainingTestSupport.tempDirectory(self).appendingPathComponent("copy.mlpackage")
        try ModelPackageWriter.write(weights: try DetectorWeights.load(fromPackage: bundled), toCopyOf: bundled, at: dest)
        let a = try Data(contentsOf: DetectorWeights.weightBinURL(inPackage: bundled))
        let b = try Data(contentsOf: DetectorWeights.weightBinURL(inPackage: dest))
        XCTAssertEqual(a.count, b.count)
        XCTAssertTrue(a == b, "fp16 -> Float -> fp16 is exact; a single differing byte means the writer moved something")
        XCTAssertEqual(try LearnedDiskDetector.sha256(ofAsset: dest), try LearnedDiskDetector.sha256(ofAsset: bundled))
        XCTAssertThrowsError(try ModelPackageWriter.write(weights: try DetectorWeights.load(fromPackage: bundled), toCopyOf: bundled, at: dest),
                             "an existing destination is refused, never overwritten")
    }

    func testTheLoadedCopyGivesTheBundledHeatmapAndAPerturbedCopyDoesNot() async throws {
        let bundled = try TrainingTestSupport.bundledPackage
        let fixture = try LearnedSwiftFixture.load()
        let base = try await LearnedSwiftFixture.loadDetector()
        let dir = try TrainingTestSupport.tempDirectory(self)
        let weights = try DetectorWeights.load(fromPackage: bundled)

        let same = dir.appendingPathComponent("same.mlpackage")
        try ModelPackageWriter.write(weights: weights, toCopyOf: bundled, at: same)
        let copy = try await LearnedDiskDetector.load(assetURL: same)

        var negated = weights
        negated.w[14] = negated.w[14].map { -$0 }
        let flipped = dir.appendingPathComponent("flipped.mlpackage")
        try ModelPackageWriter.write(weights: negated, toCopyOf: bundled, at: flipped)
        let other = try await LearnedDiskDetector.load(assetURL: flipped)
        XCTAssertNotEqual(other.assetSHA256, base.assetSHA256)

        let n3 = 3 * 256 * 256
        var inputs = [Float16](repeating: 0, count: base.batch * n3)
        inputs.replaceSubrange(0 ..< n3, with: fixture.inputsRef[0])
        func first(_ h: [Float16]) -> [Float] { h[0 ..< 256 * 256].map { Float($0) } }
        let hb = first(try await base.heatmaps(inputs: inputs))
        let hc = first(try await copy.heatmaps(inputs: inputs))
        let ho = first(try await other.heatmaps(inputs: inputs))
        XCTAssertGreaterThan(hb.max() ?? 0, 0.5, "the pattern has disks: the comparison is not between two empty maps")
        XCTAssertEqual(copy.assetSHA256, base.assetSHA256)
        XCTAssertEqual(zip(hb, hc).map { abs($0 - $1) }.max() ?? 1, 0, "the round-tripped model's heatmap equals the bundled one's")
        XCTAssertGreaterThan(zip(hb, ho).map { abs($0 - $1) }.max() ?? 0, 0.05, "a changed head kernel changes the heatmap")
    }

    func testAPackageOfAnotherLayoutIsRefusedNotCorrupted() throws {
        let bundled = try TrainingTestSupport.bundledPackage
        let dir = try TrainingTestSupport.tempDirectory(self)
        let broken = dir.appendingPathComponent("broken.mlpackage")
        try FileManager.default.copyItem(at: bundled, to: broken)
        let bin = DetectorWeights.weightBinURL(inPackage: broken)
        var data = try Data(contentsOf: bin)
        data[64] = 0   // first blob's sentinel byte
        try data.write(to: bin)
        XCTAssertThrowsError(try DetectorWeights.load(fromPackage: broken))
        let dest = dir.appendingPathComponent("out.mlpackage")
        XCTAssertThrowsError(try ModelPackageWriter.write(weights: try DetectorWeights.load(fromPackage: bundled), toCopyOf: broken, at: dest))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path), "a failed write leaves no half-written package")
    }
}

final class TrainedModelStoreTests: XCTestCase {

    private func record(sha: String, parent: String, date: Date = Date()) -> TrainedModelRecord {
        TrainedModelRecord(
            sha256: sha, parentSHA256: parent, labelsSHA256: "ab" + String(repeating: "0", count: 62),
            datasetFile: "/data/bullseye.h5", datasetPath: "/4DSTEM_experiment/data/datacubes/polyAu_4DSTEM/data",
            heldOut: [ScanPosition(ry: 1, rx: 1)], trained: [ScanPosition(ry: 2, rx: 3), ScanPosition(ry: 0, rx: 0)],
            recipe: TrainingRecipe(), finalStepLoss: 0.0031,
            active: .init(modelSHA256: parent, score: DetectionScore(matched: 30, truth: 40, predicted: 45), heldOutPositions: 12, radiusPx: 2, threshold: 0.7),
            candidate: .init(modelSHA256: sha, score: DetectionScore(matched: 33, truth: 40, predicted: 44), heldOutPositions: 12, radiusPx: 2, threshold: 0.7),
            date: date)
    }

    func testSaveListFindAndRemove() throws {
        let bundled = try TrainingTestSupport.bundledPackage
        let root = try TrainingTestSupport.tempDirectory(self).appendingPathComponent("DiskDetectorModels")
        let staging = try TrainingTestSupport.tempDirectory(self)
        let store = try TrainedModelStore(root: root, trash: { try FileManager.default.removeItem(at: $0) })
        XCTAssertEqual(store.list(), [])

        // a model that differs from the bundled one by one weight, so its hash is its own
        var w = try DetectorWeights.load(fromPackage: bundled)
        w.b[0][0] += 0.25
        let staged = staging.appendingPathComponent("candidate.mlpackage")
        try ModelPackageWriter.write(weights: w, toCopyOf: bundled, at: staged)
        let parent = try LearnedDiskDetector.sha256(ofAsset: bundled), sha = try LearnedDiskDetector.sha256(ofAsset: staged)
        XCTAssertNotEqual(sha, parent)

        // a record naming the wrong hash is refused, and nothing is moved
        XCTAssertThrowsError(try store.save(record: record(sha: parent, parent: parent), packageAt: staged, compiled: nil))
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.path))

        let r = record(sha: sha, parent: parent)
        let entry = try store.save(record: r, packageAt: staged, compiled: nil)
        XCTAssertEqual(entry.sha8, String(sha.prefix(8)))
        XCTAssertEqual(entry.directory.lastPathComponent, String(sha.prefix(8)))
        XCTAssertEqual(try LearnedDiskDetector.sha256(ofAsset: entry.packageURL), sha, "the stored package is the trained one")
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path), "saving moves the package")
        XCTAssertNil(entry.compiledURL)

        let listed = store.list()
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed[0].record.sha256, sha)
        XCTAssertEqual(listed[0].record.parentSHA256, parent)
        XCTAssertEqual(listed[0].record.heldOut, [ScanPosition(ry: 1, rx: 1)])
        XCTAssertEqual(listed[0].record.candidate?.score, DetectionScore(matched: 33, truth: 40, predicted: 44))
        XCTAssertEqual(listed[0].record.recipe, TrainingRecipe())
        XCTAssertEqual(store.entry(sha256: sha)?.sha8, entry.sha8)
        XCTAssertEqual(store.entry(sha256: String(sha.prefix(12)))?.sha8, entry.sha8)
        XCTAssertNil(store.entry(sha256: String(sha.prefix(4))), "a prefix shorter than 8 digits identifies nothing")
        XCTAssertNil(store.entry(sha256: parent))

        try store.remove(entry)
        XCTAssertFalse(FileManager.default.fileExists(atPath: entry.directory.path))
        XCTAssertEqual(store.list(), [])
    }

    func testListIsNewestFirstAndSkipsFoldersWithoutARecord() throws {
        let root = try TrainingTestSupport.tempDirectory(self)
        let store = try TrainedModelStore(root: root, trash: { _ in })
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        for (name, age) in [("aaaaaaaa", 1000.0), ("bbbbbbbb", 10.0)] {
            let dir = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let sha = name + String(repeating: "0", count: 56)
            try enc.encode(record(sha: sha, parent: "p", date: Date(timeIntervalSinceNow: -age))).write(to: dir.appendingPathComponent("record.json"))
        }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("cccccccc"), withIntermediateDirectories: true)
        XCTAssertEqual(store.list().map(\.sha8), ["bbbbbbbb", "aaaaaaaa"])
    }
}
