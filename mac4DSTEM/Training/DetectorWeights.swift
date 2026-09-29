//
//  DetectorWeights.swift
//  Role: the learned disk detector's 29 trainable tensors and where they sit in the shipped package's
//        `weight.bin` (C3 pre-registration §2; the layout is `tools/mpsgraph-training-spike`'s, proven
//        there against the shipped Core ML heatmap to 0.0027 on the GPU).
//
//  weight.bin is a MIL blob file: a 64-byte header, then per blob 64 bytes of metadata (sentinel
//  0xDEADBEEF at +0, byte size at +8, data offset at +16) and the fp16 data. Weights are OIHW, exactly the
//  layout the MPSGraph convolutions take, so nothing is permuted on either read or write. The 1x1 head's
//  bias is an inline immediate in the model spec (frozen, never trained, never written).
//  Parameter order everywhere: w0..w14, then b0..b13.
//

import Foundation

package nonisolated struct DetectorWeights: Equatable, Sendable {
    /// Convolution kernels, OIHW, w[0]..w[14] (w[14] is the 1x1 head).
    package var w: [[Float]]
    /// Biases b[0]..b[13] (the head has none here).
    package var b: [[Float]]
    package init(w: [[Float]], b: [[Float]]) { self.w = w; self.b = b }

    /// (in, out) channels of the 15 convolutions.
    package static let convChannels: [(input: Int, output: Int)] = [
        (3, 12), (12, 12), (12, 24), (24, 24), (24, 48), (48, 48), (48, 96), (96, 96),
        (144, 48), (48, 48), (72, 24), (24, 24), (36, 12), (12, 12), (12, 1),   // the last is the 1x1 head
    ]
    package static func kernelSize(_ i: Int) -> Int { i == 14 ? 1 : 3 }
    /// The head bias, frozen: an fp16 immediate in the spec.
    package static let headBias = Float(Float16(bitPattern: 0xB413))
    package static let parameterCount = 29

    /// Byte offsets of each blob's 64-byte metadata record in `weight.bin`.
    static let weightMeta = [64, 960, 3776, 9152, 19712, 40704, 82432, 165696, 331904, 456576, 498304, 529600, 540160, 548160, 550976]
    static let biasMeta = [832, 3648, 9024, 19584, 40512, 82240, 165440, 331648, 456384, 498112, 529472, 540032, 548032, 550848]

    /// Element counts in parameter order.
    package static var elementCounts: [Int] {
        (0 ..< 15).map { convChannels[$0].output * convChannels[$0].input * kernelSize($0) * kernelSize($0) }
            + (0 ..< 14).map { convChannels[$0].output }
    }
    /// Tensor shapes in parameter order: OIHW kernels, then [1, C, 1, 1] biases.
    package static var shapes: [[Int]] {
        (0 ..< 15).map { [convChannels[$0].output, convChannels[$0].input, kernelSize($0), kernelSize($0)] }
            + (0 ..< 14).map { [1, convChannels[$0].output, 1, 1] }
    }
    /// w then b, flattened in parameter order.
    package var parameters: [[Float]] { w + b }

    package init(parameters: [[Float]]) throws {
        guard parameters.count == Self.parameterCount else { throw DetectorWeightsError.wrongTensorCount(parameters.count) }
        for (i, expected) in Self.elementCounts.enumerated() where parameters[i].count != expected {
            throw DetectorWeightsError.wrongElementCount(tensor: i, expected: expected, got: parameters[i].count)
        }
        self.w = Array(parameters[0 ..< 15]); self.b = Array(parameters[15 ..< 29])
    }

    // MARK: weight.bin

    package static func weightBinURL(inPackage packageURL: URL) -> URL {
        packageURL.appendingPathComponent("Data/com.apple.CoreML/weights/weight.bin")
    }

    /// The blob (byte offset, byte count) a metadata record points at, after checking the sentinel and that
    /// the record holds exactly `count` fp16 values.
    static func blobRange(_ bin: Data, meta: Int, count: Int) throws -> Range<Int> {
        guard meta + 64 <= bin.count else { throw DetectorWeightsError.badBlob(meta: meta, reason: "past the end of weight.bin") }
        func u32(_ o: Int) -> UInt32 { bin.subdata(in: (bin.startIndex + o) ..< (bin.startIndex + o + 4)).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } }
        func u64(_ o: Int) -> UInt64 { bin.subdata(in: (bin.startIndex + o) ..< (bin.startIndex + o + 8)).withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) } }
        guard u32(meta) == 0xDEAD_BEEF else { throw DetectorWeightsError.badBlob(meta: meta, reason: "no blob sentinel") }
        let size = Int(u64(meta + 8)), offset = Int(u64(meta + 16))
        guard size == count * 2 else { throw DetectorWeightsError.badBlob(meta: meta, reason: "holds \(size) bytes, expected \(count * 2)") }
        guard offset >= 0, offset + size <= bin.count else { throw DetectorWeightsError.badBlob(meta: meta, reason: "data past the end of weight.bin") }
        return offset ..< offset + size
    }

    /// Reads the shipped (or a written) package's weights: fp16 to Float, exact.
    package static func load(fromPackage packageURL: URL) throws -> DetectorWeights {
        let bin: Data
        do { bin = try Data(contentsOf: weightBinURL(inPackage: packageURL)) }
        catch { throw DetectorWeightsError.unreadable(packageURL, error) }
        let metas = weightMeta + biasMeta, counts = elementCounts
        var tensors: [[Float]] = []
        for (i, meta) in metas.enumerated() {
            let range = try blobRange(bin, meta: meta, count: counts[i])
            let values = bin.subdata(in: (bin.startIndex + range.lowerBound) ..< (bin.startIndex + range.upperBound))
                .withUnsafeBytes { raw -> [Float] in
                    (0 ..< counts[i]).map { Float(Float16(bitPattern: raw.loadUnaligned(fromByteOffset: $0 * 2, as: UInt16.self))) }
                }
            tensors.append(values)
        }
        return try DetectorWeights(parameters: tensors)
    }
}

package nonisolated enum DetectorWeightsError: Error, CustomStringConvertible, LocalizedError {
    case unreadable(URL, Error)
    case badBlob(meta: Int, reason: String)
    case wrongTensorCount(Int)
    case wrongElementCount(tensor: Int, expected: Int, got: Int)
    package var description: String {
        switch self {
        case .unreadable(let u, let e): return "detector weights: cannot read \(u.path): \(e.localizedDescription)"
        case .badBlob(let m, let r): return "detector weights: blob at \(m) — \(r)"
        case .wrongTensorCount(let n): return "detector weights: \(n) tensors, expected \(DetectorWeights.parameterCount)"
        case .wrongElementCount(let t, let e, let g): return "detector weights: tensor \(t) has \(g) values, expected \(e)"
        }
    }
    package var errorDescription: String? { description }
}
