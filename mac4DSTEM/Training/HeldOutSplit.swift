//
//  HeldOutSplit.swift
//  Role: which labelled scan positions are held out of fine-tuning (C3 pre-registration §3 step 2, D3).
//
//  By POSITION, never by centre, and by a hash of the position alone: a position is held out when
//  SHA-256("ry,rx") read as a number in [0,1) is below 0.30. Nothing else enters, so a position's side
//  never changes when labels are added, removed or reloaded, and the same position is on the same side
//  in every dataset session. The number is the first 8 digest bytes read big-endian, shifted right by 11
//  to 53 bits and divided by 2^53 (a Double holds it exactly and it can never round up to 1.0).
//

import CryptoKit
import Foundation

/// One scan position (`ry` = scan row, `rx` = scan column).
package nonisolated struct ScanPosition: Hashable, Codable, Sendable, Comparable {
    package var ry: Int
    package var rx: Int
    package init(ry: Int, rx: Int) { self.ry = ry; self.rx = rx }
    package static func < (a: ScanPosition, b: ScanPosition) -> Bool { (a.ry, a.rx) < (b.ry, b.rx) }
}

package nonisolated enum HeldOutSplit {
    /// The registered held-out fraction (D3).
    package static let fraction = 0.30

    /// SHA-256 of the UTF-8 text "ry,rx" as a number in [0,1).
    package static func hashUnit(ry: Int, rx: Int) -> Double {
        let digest = SHA256.hash(data: Data("\(ry),\(rx)".utf8))
        var value: UInt64 = 0
        for byte in digest.prefix(8) { value = (value << 8) | UInt64(byte) }
        return Double(value >> 11) / 9_007_199_254_740_992.0   // 2^53
    }

    package static func isHeldOut(_ position: ScanPosition, fraction: Double = HeldOutSplit.fraction) -> Bool {
        hashUnit(ry: position.ry, rx: position.rx) < fraction
    }

    /// The labelled positions divided into training and held-out, each sorted, duplicates dropped. A
    /// position's side depends on the position only, so the result for a subset is the restriction of the
    /// result for any superset.
    package static func split(_ positions: [ScanPosition], fraction: Double = HeldOutSplit.fraction)
        -> (train: [ScanPosition], heldOut: [ScanPosition]) {
        var train: [ScanPosition] = [], held: [ScanPosition] = []
        for p in Set(positions).sorted() {
            if isHeldOut(p, fraction: fraction) { held.append(p) } else { train.append(p) }
        }
        return (train, held)
    }
}
