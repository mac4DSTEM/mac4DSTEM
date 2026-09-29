//
//  TrainedModelStore.swift
//  Role: where fine-tuned detector models live (C3 pre-registration §3 step 6, D6).
//
//  `Application Support/mac4DSTEM/DiskDetectorModels/<sha8>/` holds `model.mlpackage`, `model.mlmodelc`
//  (a compile cache) and `record.json`. <sha8> is the first 8 hex digits of the package's tree hash — the
//  same `learned_model_sha256` that provenance carries (`LearnedDiskDetector.sha256(ofAsset:)`). The record
//  lists the parent and labels sha, the dataset, the held-out (and training) positions, the recipe, both
//  models' numbers on the held-out positions and the date. Nothing is deleted automatically; `remove`
//  moves a model's folder to the Trash.
//

import DSTEMCore
import Foundation

package nonisolated struct TrainedModelRecord: Codable, Equatable, Sendable {
    /// One model's numbers on the held-out positions, as the comparison sheet shows them.
    package struct HeldOutScore: Codable, Equatable, Sendable {
        package var modelSHA256: String
        package var score: DetectionScore
        package var heldOutPositions: Int
        package var radiusPx: Double
        package var threshold: Float
        package init(modelSHA256: String, score: DetectionScore, heldOutPositions: Int, radiusPx: Double, threshold: Float) {
            self.modelSHA256 = modelSHA256; self.score = score; self.heldOutPositions = heldOutPositions
            self.radiusPx = radiusPx; self.threshold = threshold
        }
    }

    package var schema = 1
    /// Tree hash of the trained package.
    package var sha256: String
    /// Tree hash of the bundled package it was trained from (D4: always the bundled weights).
    package var parentSHA256: String
    /// Hash of the labels file the run used (nil when the labels were never saved to a file).
    package var labelsSHA256: String?
    package var datasetFile: String
    package var datasetPath: String
    package var heldOut: [ScanPosition]
    package var trained: [ScanPosition]
    package var recipe: TrainingRecipe
    package var finalStepLoss: Double?
    /// The model that was active when the run was judged, and the candidate, on the same held-out positions.
    package var active: HeldOutScore?
    package var candidate: HeldOutScore?
    package var runtime = "MPSGraph"
    package var date: Date

    package init(sha256: String, parentSHA256: String, labelsSHA256: String?, datasetFile: String, datasetPath: String,
                 heldOut: [ScanPosition], trained: [ScanPosition], recipe: TrainingRecipe, finalStepLoss: Double?,
                 active: HeldOutScore?, candidate: HeldOutScore?, date: Date = Date()) {
        self.sha256 = sha256; self.parentSHA256 = parentSHA256; self.labelsSHA256 = labelsSHA256
        self.datasetFile = datasetFile; self.datasetPath = datasetPath; self.heldOut = heldOut; self.trained = trained
        self.recipe = recipe; self.finalStepLoss = finalStepLoss; self.active = active; self.candidate = candidate
        self.date = date
    }
}

package nonisolated final class TrainedModelStore: @unchecked Sendable {
    package struct Entry: Equatable, Sendable {
        package var sha8: String
        package var directory: URL
        package var record: TrainedModelRecord
        package var packageURL: URL { directory.appendingPathComponent(TrainedModelStore.packageName) }
        package var compiledURL: URL? {
            let u = directory.appendingPathComponent(TrainedModelStore.compiledName)
            return FileManager.default.fileExists(atPath: u.path) ? u : nil
        }
    }

    package static let packageName = "model.mlpackage"
    package static let compiledName = "model.mlmodelc"
    package static let recordName = "record.json"

    package let root: URL
    private let trash: @Sendable (URL) throws -> Void

    /// `root` defaults to `Application Support/mac4DSTEM/DiskDetectorModels` (inside the sandbox container in
    /// the app). `trash` is injectable so tests never fill the user's Trash.
    package init(root: URL? = nil, trash: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) throws {
        if let root { self.root = root } else { self.root = try Self.defaultRoot() }
        self.trash = trash
    }

    package static func defaultRoot() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("mac4DSTEM/DiskDetectorModels", isDirectory: true)
    }

    package static func sha8(of sha256: String) -> String { String(sha256.prefix(8)) }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; e.dateEncodingStrategy = .iso8601; return e
    }
    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }

    /// Moves a written package (and its compile cache, if any) into `<root>/<sha8>/` and writes `record.json`.
    /// Refuses when the package's tree hash is not `record.sha256`, or the folder already holds a different model.
    @discardableResult
    package func save(record: TrainedModelRecord, packageAt packageURL: URL, compiled: URL?) throws -> Entry {
        let actual = try LearnedDiskDetector.sha256(ofAsset: packageURL)
        guard actual == record.sha256 else { throw TrainedModelStoreError.hashMismatch(recorded: record.sha256, actual: actual) }
        let fm = FileManager.default
        let dir = root.appendingPathComponent(Self.sha8(of: record.sha256), isDirectory: true)
        if let existing = try? Self.decoder().decode(TrainedModelRecord.self, from: Data(contentsOf: dir.appendingPathComponent(Self.recordName))),
           existing.sha256 != record.sha256 {
            throw TrainedModelStoreError.sha8Collision(dir)
        }
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let items: [(URL?, String)] = [(packageURL, Self.packageName), (compiled, Self.compiledName)]
        for (source, name) in items {
            guard let source else { continue }
            let dest = dir.appendingPathComponent(name)
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.moveItem(at: source, to: dest)
        }
        try Self.encoder().encode(record).write(to: dir.appendingPathComponent(Self.recordName), options: .atomic)
        return Entry(sha8: Self.sha8(of: record.sha256), directory: dir, record: record)
    }

    /// Every stored model whose record reads, newest first. A folder without a readable record is skipped.
    package func list() -> [Entry] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: root.path) else { return [] }
        var entries: [Entry] = []
        for name in names where !name.hasPrefix(".") {
            let dir = root.appendingPathComponent(name, isDirectory: true)
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(Self.recordName)),
                  let record = try? Self.decoder().decode(TrainedModelRecord.self, from: data) else { continue }
            entries.append(Entry(sha8: name, directory: dir, record: record))
        }
        return entries.sorted { $0.record.date > $1.record.date }
    }

    /// The stored model whose tree hash is `sha256` (a full hash, or any prefix of at least 8 digits).
    package func entry(sha256: String) -> Entry? {
        guard sha256.count >= 8 else { return nil }
        return list().first { $0.record.sha256.hasPrefix(sha256) }
    }

    /// Moves the model's folder to the Trash.
    package func remove(_ entry: Entry) throws {
        try trash(entry.directory)
    }
}

package nonisolated enum TrainedModelStoreError: Error, CustomStringConvertible, LocalizedError {
    case hashMismatch(recorded: String, actual: String)
    case sha8Collision(URL)
    package var description: String {
        switch self {
        case .hashMismatch(let r, let a): return "model store: the package hashes to \(a.prefix(12))…, the record says \(r.prefix(12))…"
        case .sha8Collision(let u): return "model store: \(u.lastPathComponent) already holds a different model"
        }
    }
    package var errorDescription: String? { description }
}
