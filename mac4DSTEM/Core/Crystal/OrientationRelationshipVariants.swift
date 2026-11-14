//
//  OrientationRelationshipVariants.swift
//  Role: an orientation relationship typed as a paper states it ("[2 1 0] ∥ [1 -1 0]", one pair) stands for all its variants in the
//        matrix: the pairs the matrix's symmetry about its zone axis makes of it (mac4DSTEM#342). Typed as one pair, Thronsen A's
//        T1 and θ′ relationships gave one variant each and 84.48 % agreement; the parity setup lists the second pair by hand
//        ([2 1 0] ∥ [1 1 0]) and reaches 98.59 %.
//

import Foundation
import DiffractoCore
import DiffractoOrientation

package nonisolated enum OrientationRelationshipVariants {
    /// `relationships` with each pair's matrix vector replaced by its images under the matrix's proper point-group rotations that keep
    /// the matrix zone axis (`matrixZone`, a direction) on itself or its opposite. A direction [uvw] maps as R·[uvw], a plane (hkl) as
    /// Rᵀ·(hkl) (the set over the group is the same as with R⁻ᵀ). Pairs equal up to the sign of the matrix vector are one: the
    /// consistency check compares azimuths modulo 180°. Order: each typed pair, then its new images, as found.
    package static func expanded(_ relationships: [OrientationRelationship], matrix: CrystalStructure,
                                 matrixZone: SIMD3<Int>) -> [OrientationRelationship] {
        guard !relationships.isEmpty, matrixZone != .zero else { return relationships }
        let rotations = uniqueRotations(matrix.operations.map(\.rotation)).filter { r in
            r.determinant == 1 && { let z = apply(r, matrixZone); return z == matrixZone || z == SIMD3<Int>.zero &- matrixZone }()
        }
        var out: [OrientationRelationship] = []
        var seen = Set<String>()
        for pair in relationships {
            for r in [IntegerMatrix.identity] + rotations {
                // A new image is written with its first non-zero index positive; the typed pair stays as typed.
                let typed = r.rows == IntegerMatrix.identity.rows
                let image: LatticeVector
                switch pair.matrix {
                case .direction(let v): image = .direction(typed ? v : canonical(apply(r, v)))
                case .plane(let h): image = .plane(typed ? h : canonical(apply(r.transposed, h)))
                }
                let key = "\(pair.candidate)|\(signless(image))"
                if seen.insert(key).inserted { out.append(OrientationRelationship(candidate: pair.candidate, matrix: image)) }
            }
        }
        return out
    }

    /// "(002) ∥ (200)", "[2 1 0] ∥ [1 1 0]": a pair as the phase rows write it.
    package static func text(_ pair: OrientationRelationship) -> String {
        func v(_ x: LatticeVector) -> String {
            switch x {
            case .direction(let d): return "[\(d.x) \(d.y) \(d.z)]"
            case .plane(let h): return "(\(h.x) \(h.y) \(h.z))"
            }
        }
        return "\(v(pair.candidate)) ∥ \(v(pair.matrix))"
    }

    private static func apply(_ r: IntegerMatrix, _ v: SIMD3<Int>) -> SIMD3<Int> {
        SIMD3((r.rows[0] &* v).wrappedSum(), (r.rows[1] &* v).wrappedSum(), (r.rows[2] &* v).wrappedSum())
    }

    private static func uniqueRotations(_ all: [IntegerMatrix]) -> [IntegerMatrix] {
        var out: [IntegerMatrix] = []
        for r in all where !out.contains(where: { $0.rows == r.rows }) { out.append(r) }
        return out
    }

    /// The vector with its first non-zero index made positive.
    private static func canonical(_ x: SIMD3<Int>) -> SIMD3<Int> {
        let first = [x.x, x.y, x.z].first { $0 != 0 } ?? 0
        return first < 0 ? SIMD3<Int>.zero &- x : x
    }

    /// v and −v are one key.
    private static func signless(_ v: LatticeVector) -> String {
        switch v {
        case .direction(let x): return "d\(canonical(x))"
        case .plane(let x): return "p\(canonical(x))"
        }
    }
}
