//
//  ModelPackageWriter.swift
//  Role: turns trained weights into a Core ML package the app loads unchanged (C3 pre-registration §2,
//        §3 step 4; "C4 uses the on-disk route only").
//
//  The shipped `.mlpackage` is COPIED and its `weight.bin` patched in place: every trained tensor is written
//  as fp16 at the blob offset the shipped file records (`DetectorWeights.load` reads the same offsets), in
//  the same OIHW layout, so the model spec, the manifest, the input/output signature and the flexible batch
//  are the bundled model's own. The head bias is an inline immediate in the spec and stays as shipped.
//  `LearnedDiskDetector.load(assetURL:)` then compiles and loads the copy exactly as it does the
//  bundled one — the Neural Engine runs it at the shipped speed (C2: 1.00x).
//

import CoreML
import Foundation

package nonisolated enum ModelPackageWriter {
    /// Copies `bundledPackage` to `destination` (which must not exist) and writes `weights` into the copy's
    /// `weight.bin` as fp16. Returns `destination`.
    @discardableResult
    package static func write(weights: DetectorWeights, toCopyOf bundledPackage: URL, at destination: URL) throws -> URL {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: destination.path) else { throw ModelPackageWriterError.destinationExists(destination) }
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        do { try fm.copyItem(at: bundledPackage, to: destination) }
        catch { throw ModelPackageWriterError.copyFailed(bundledPackage, error) }
        do {
            let binURL = DetectorWeights.weightBinURL(inPackage: destination)
            var bin = try Data(contentsOf: binURL)
            try patch(&bin, with: weights)
            // the copy inherits the bundle's read-only mode when made from an app resource
            try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: binURL.path)
            try bin.write(to: binURL, options: .atomic)
        } catch {
            try? fm.removeItem(at: destination)
            throw error
        }
        return destination
    }

    /// `bin` with every trained tensor written as fp16 at its recorded blob. Each blob is checked first
    /// (sentinel, byte count) so a package of another layout is refused instead of corrupted.
    static func patch(_ bin: inout Data, with weights: DetectorWeights) throws {
        let metas = DetectorWeights.weightMeta + DetectorWeights.biasMeta
        let tensors = weights.parameters, counts = DetectorWeights.elementCounts
        guard tensors.count == metas.count else { throw DetectorWeightsError.wrongTensorCount(tensors.count) }
        var ranges: [Range<Int>] = []
        for (i, meta) in metas.enumerated() {
            guard tensors[i].count == counts[i] else {
                throw DetectorWeightsError.wrongElementCount(tensor: i, expected: counts[i], got: tensors[i].count)
            }
            ranges.append(try DetectorWeights.blobRange(bin, meta: meta, count: counts[i]))
        }
        bin.withUnsafeMutableBytes { raw in
            for (i, range) in ranges.enumerated() {
                for (j, value) in tensors[i].enumerated() {
                    raw.storeBytes(of: Float16(value).bitPattern, toByteOffset: range.lowerBound + j * 2, as: UInt16.self)
                }
            }
        }
    }

    /// Compiles `package` (`MLModel.compileModel(at:)`) and moves the `.mlmodelc` next to it as
    /// `<package name>.mlmodelc`. The store keeps it so a later load need not recompile; the app's load path
    /// compiles from the `.mlpackage` today.
    package static func compile(packageAt packageURL: URL) async throws -> URL {
        let compiled: URL
        do { compiled = try await MLModel.compileModel(at: packageURL) }
        catch { throw ModelPackageWriterError.compileFailed(packageURL, error) }
        let dest = packageURL.deletingPathExtension().appendingPathExtension("mlmodelc")
        let fm = FileManager.default
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.moveItem(at: compiled, to: dest)
        return dest
    }
}

package nonisolated enum ModelPackageWriterError: Error, CustomStringConvertible, LocalizedError {
    case destinationExists(URL)
    case copyFailed(URL, Error)
    case compileFailed(URL, Error)
    package var description: String {
        switch self {
        case .destinationExists(let u): return "model package: \(u.path) already exists"
        case .copyFailed(let u, let e): return "model package: cannot copy \(u.lastPathComponent): \(e.localizedDescription)"
        case .compileFailed(let u, let e): return "model package: cannot compile \(u.lastPathComponent): \(e.localizedDescription)"
        }
    }
    package var errorDescription: String? { description }
}
