//
//  FormatoArrayFloat32.swift
//  Role: a FormatoKit array's elements as Float, the way the app's readers hand pixels to the 4D pipeline (H5Reader, DM4Reader).
//

import Foundation
import FormatoCore

extension FormatoArray {
    /// Every element as Float, in C order, each converted the way a C cast does (round to nearest even; what `H5Dread` into
    /// `H5T_NATIVE_FLOAT` did): float32 is copied as stored. Nil for a colour type, which no 4D source holds.
    package nonisolated func float32Values() -> [Float]? {
        let n = count
        return bytes.withUnsafeBytes { p -> [Float]? in
            switch dataType {
            case .float32:
                return [Float](unsafeUninitializedCapacity: n) { out, count in
                    for i in 0..<n { out[i] = Float(bitPattern: UInt32(littleEndian: p.loadUnaligned(fromByteOffset: 4 * i, as: UInt32.self))) }
                    count = n
                }
            case .float64:
                return [Float](unsafeUninitializedCapacity: n) { out, count in
                    for i in 0..<n { out[i] = Float(Double(bitPattern: UInt64(littleEndian: p.loadUnaligned(fromByteOffset: 8 * i, as: UInt64.self)))) }
                    count = n
                }
            case .uint8:
                return [Float](unsafeUninitializedCapacity: n) { out, count in
                    for i in 0..<n { out[i] = Float(p.loadUnaligned(fromByteOffset: i, as: UInt8.self)) }
                    count = n
                }
            case .int8:
                return [Float](unsafeUninitializedCapacity: n) { out, count in
                    for i in 0..<n { out[i] = Float(p.loadUnaligned(fromByteOffset: i, as: Int8.self)) }
                    count = n
                }
            case .uint16:
                return [Float](unsafeUninitializedCapacity: n) { out, count in
                    for i in 0..<n { out[i] = Float(UInt16(littleEndian: p.loadUnaligned(fromByteOffset: 2 * i, as: UInt16.self))) }
                    count = n
                }
            case .int16:
                return [Float](unsafeUninitializedCapacity: n) { out, count in
                    for i in 0..<n { out[i] = Float(Int16(littleEndian: p.loadUnaligned(fromByteOffset: 2 * i, as: Int16.self))) }
                    count = n
                }
            case .uint32:
                return [Float](unsafeUninitializedCapacity: n) { out, count in
                    for i in 0..<n { out[i] = Float(UInt32(littleEndian: p.loadUnaligned(fromByteOffset: 4 * i, as: UInt32.self))) }
                    count = n
                }
            case .int32:
                return [Float](unsafeUninitializedCapacity: n) { out, count in
                    for i in 0..<n { out[i] = Float(Int32(littleEndian: p.loadUnaligned(fromByteOffset: 4 * i, as: Int32.self))) }
                    count = n
                }
            case .uint64:
                return [Float](unsafeUninitializedCapacity: n) { out, count in
                    for i in 0..<n { out[i] = Float(UInt64(littleEndian: p.loadUnaligned(fromByteOffset: 8 * i, as: UInt64.self))) }
                    count = n
                }
            case .int64:
                return [Float](unsafeUninitializedCapacity: n) { out, count in
                    for i in 0..<n { out[i] = Float(Int64(littleEndian: p.loadUnaligned(fromByteOffset: 8 * i, as: Int64.self))) }
                    count = n
                }
            case .rgb8, .rgba8, .rgb16, .rgba16:
                return nil
            }
        }
    }
}
