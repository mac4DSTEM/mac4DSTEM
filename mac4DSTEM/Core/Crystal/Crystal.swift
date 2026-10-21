//
//  Crystal.swift
//  Role: The app's spellings over the kit's crystal types. The preset crystals (the cubic and hexagonal families, the named
//        elements, beta'' and 2H-WS2, the cubic-structure editor's cells) are DiffractoKit's `CrystalPresets` (0.7.1); the
//        lattice algebra, the kinematic reflection list and the scattering factors are its `UnitCell`, `CrystalStructure
//        .kinematicReflections`, `ElectronScatteringFactors`. This file keeps the read-only field names the template,
//        library and matcher code still reads.
//
//  Units: distances in Å, scattering vectors |g| in Å⁻¹ (no 2π factor, matching py4DSTEM). Structure factors are in
//  Å⁻² (f_e in Å over V in Å³); py4DSTEM's "A" names f_e's unit, not F's.
//

import Foundation
import simd
import DiffractoCore
import DiffractoScattering

// MARK: - Thin conveniences over the kit's types (the app's old `Reflection` and `Crystal` spellings)

extension KinematicReflection {
    // The app's old `Reflection` field names, so the template, library and matcher code that reads reflections is
    // unchanged by the switch. Read-only views of the kit's fields; nothing is computed.
    package nonisolated var h: Int { reflection.hkl.h }
    package nonisolated var k: Int { reflection.hkl.k }
    package nonisolated var l: Int { reflection.hkl.l }
    package nonisolated var g: SIMD3<Double> { reflection.g }
    package nonisolated var gLength: Double { reflection.gLength }
    package nonisolated var structureFactorRe: Double { structureFactor.real }
    package nonisolated var structureFactorIm: Double { structureFactor.imaginary }
    package nonisolated var intensity: Double { structureFactor.intensity }
}

extension CrystalStructure {
    /// Atomic numbers of this structure's sites that have no electron scattering factor (the table covers Z = 1 to 103,
    /// the kit's element list 1 to 118). `kinematicReflections` throws `KinematicError.unsupportedElements` for the
    /// same elements; this is the pre-flight the callers that must name a phase or refuse before a long job use.
    package nonisolated var unsupportedElements: [Int] {
        Array(Set(sites.map(\.z).filter { !ElectronScatteringFactors.isSupported(z: $0) })).sorted()
    }
}
