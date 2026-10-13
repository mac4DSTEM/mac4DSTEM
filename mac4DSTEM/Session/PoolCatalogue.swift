//
//  PoolCatalogue.swift
//  Role: The pools a Spectroscopy window can offer from the 4D scan beside its spectrum image (E1, ADR 061 §1 / 065): one
//        per indexed phase, one "Not indexed", one per diffraction group. A pool is a MASK on the spectrum image's grid and
//        nothing else; the room sums the spectrum from it exactly as it does for a drawn region (`SpectrumImage.sum(mask:)`),
//        so a pooled count is an exact integer sum of whole pixels and no pool is ever computed here.
//
//  This is the 4D seam of the pooling: it reads `PhaseMap` and `DiffractionEmbedding.Result` (the 4D layer) and hands the
//  room masks, names, badges and refusal sentences. `Core/Spectroscopy/` is untouched (SpectroKit boundary, ADR 064): the
//  transport is `MaskTransport` and the half-area partition rule is the WP3 one, inherited, not set here.
//
//  Membership: the product's label map (phase: verdict .indexed or .matrix with its phaseIndex, every other position is
//  "Not indexed"; group: `groupOf`, -1 unlabelled) moves through `MaskTransport.transport(labels:classCount:registration:)`
//  and a spectrum pixel joins the class that covers more than half of it; an exact tie joins none. Phase, Not indexed and
//  group pools alike use `TransportedLabels.labels` (a partition) and never `pool(scanMask:)`, which admits ties.
//
//  Refusals are sentences, never a spectrum: no registration, a registration that is singular or maps onto another grid than
//  this image's, a product on another scan size than the registration's 4D scan (both sizes named), and a class that holds no
//  spectrum pixel. A refused source has no region; its sentence is a `PoolNote` the picker shows as a disabled line.
//

import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import SpectroCore
#endif

/// The picker's two pool sections (Not indexed belongs to Phases).
package nonisolated enum PoolSection: String, Sendable { case phases, groups }

/// A source the window cannot pool, or has no product for yet, in one sentence.
package nonisolated struct PoolNote: Equatable, Sendable {
    package var section: PoolSection
    package var text: String
    package nonisolated init(section: PoolSection, text: String) { self.section = section; self.text = text }
}

package nonisolated struct SpectrumPool: Equatable, Sendable, Identifiable {
    package nonisolated enum Kind: String, Sendable { case phase, group, notIndexed }

    /// The region id the session gives it: stable per source, so a re-run keeps the selection.
    package var id: Int
    package var kind: Kind
    package var name: String
    /// The product's own generation when this pool was built (`PhaseMappingProduct.generation`, `DiffractionGroupsProduct.generation`).
    package var sourceGeneration: Int
    package var pixelCount: Int
    /// On the spectrum image's grid, row-major.
    package var mask: PixelMask
    /// The source product's self-reported validation: "none" for a phase map (and for what it did not index); nil for a
    /// diffraction group, which records none and is never called validated.
    package var validation: String?
    /// The picker section.
    package var section: PoolSection { kind == .group ? .groups : .phases }
    /// The badge. `PooledSpectrum.isUnvalidated`'s predicate (`validation == "none"`), NOT `ValidationState.isUnvalidated(nil)`,
    /// which reads a missing validation as unvalidated: a group pool has no phase-map claim to retract and carries no badge.
    package var isUnvalidated: Bool { PoolCatalogue.isUnvalidated(validation: validation) }
}

package nonisolated struct PoolCatalogue: Equatable, Sendable {
    package var pools: [SpectrumPool] = []
    package var notes: [PoolNote] = []

    package nonisolated init(pools: [SpectrumPool] = [], notes: [PoolNote] = []) {
        self.pools = pools; self.notes = notes
    }

    package static let phaseIDBase = 1000
    package static let notIndexedID = 1900
    package static let groupIDBase = 2000
    package static func isPoolID(_ id: Int) -> Bool { id >= phaseIDBase }

    package static let phaseMapValidation = "none"
    package static func isUnvalidated(validation: String?) -> Bool { validation == phaseMapValidation }

    package static let noPhaseMapLine = "Run phase mapping in Crystal Maps to pool by phase."
    package static let noRegistrationLine = "No registration between the 4D scan and this spectrum image: the app states one only for the two objects of one GMS file (same scan)."

    /// The registration the app states: the identity of a GMS joint attach (`sameScanAs4DCube`).
    package static func identityRegistration(width: Int, height: Int) -> RegistrationRecordM2 {
        RegistrationRecordM2(matrix: [1, 0, 0, 0, 1, 0], source: .identityFromOneRun,
                             sourceNote: "same scan, identity; no lag check",
                             scanWidth: width, scanHeight: height, spectrumWidth: width, spectrumHeight: height)
    }

    package nonisolated struct Inputs: Sendable {
        package var hasFourDCube: Bool
        package var registration: RegistrationRecordM2?
        package var spectrumWidth: Int
        package var spectrumHeight: Int
        package var phaseMap: PhaseMap?
        package var phaseGeneration: Int
        package var groups: DiffractionEmbedding.Result?
        package var groupGeneration: Int

        package init(hasFourDCube: Bool, registration: RegistrationRecordM2?, spectrumWidth: Int, spectrumHeight: Int,
                     phaseMap: PhaseMap? = nil, phaseGeneration: Int = 0,
                     groups: DiffractionEmbedding.Result? = nil, groupGeneration: Int = 0) {
            self.hasFourDCube = hasFourDCube; self.registration = registration
            self.spectrumWidth = spectrumWidth; self.spectrumHeight = spectrumHeight
            self.phaseMap = phaseMap; self.phaseGeneration = phaseGeneration
            self.groups = groups; self.groupGeneration = groupGeneration
        }
    }

    /// What the window can offer. Without a 4D cube nothing is offered and nothing is said.
    package static func build(_ i: Inputs) -> PoolCatalogue {
        guard i.hasFourDCube else { return PoolCatalogue() }
        var out = PoolCatalogue()
        // Registration first: it decides whether any product can be pooled, and the refusal is the same sentence for both.
        let registrationRefusal = refusal(of: i.registration, spectrumWidth: i.spectrumWidth, spectrumHeight: i.spectrumHeight)
        if let map = i.phaseMap {
            if let why = registrationRefusal ?? sizeRefusal("The phase map", width: map.width, height: map.height, registration: i.registration) {
                out.notes.append(PoolNote(section: .phases, text: why))
            } else if let registration = i.registration {
                out.add(phases: map, generation: i.phaseGeneration, registration: registration)
            }
        } else {
            out.notes.append(PoolNote(section: .phases, text: registrationRefusal ?? noPhaseMapLine))
        }
        if let result = i.groups {
            if let why = registrationRefusal ?? sizeRefusal("The diffraction groups", width: result.scanWidth, height: result.scanHeight, registration: i.registration) {
                out.notes.append(PoolNote(section: .groups, text: why))
            } else if let registration = i.registration {
                out.add(groups: result, generation: i.groupGeneration, registration: registration)
            }
        }
        return out
    }

    private static func refusal(of registration: RegistrationRecordM2?, spectrumWidth: Int, spectrumHeight: Int) -> String? {
        guard let r = registration else { return noRegistrationLine }
        if !r.isInvertible { return "The registration is singular (det = \(r.determinant)): no pool can be formed." }
        if r.spectrumWidth != spectrumWidth || r.spectrumHeight != spectrumHeight {
            return "The registration maps onto a \(r.spectrumWidth) × \(r.spectrumHeight) grid; the spectrum image is \(spectrumWidth) × \(spectrumHeight)."
        }
        return nil
    }

    /// Width AND height, not the pixel count: a 3 × 5 map and a 5 × 3 image have the same count and are not the same scan.
    private static func sizeRefusal(_ what: String, width: Int, height: Int, registration: RegistrationRecordM2?) -> String? {
        guard let r = registration, r.scanWidth != width || r.scanHeight != height else { return nil }
        return "\(what) is \(width) × \(height) positions; the registration's 4D scan is \(r.scanWidth) × \(r.scanHeight): no pool."
    }

    // MARK: Phases

    private mutating func add(phases map: PhaseMap, generation: Int, registration: RegistrationRecordM2) {
        let phaseCount = map.phaseNames.count
        let notIndexed = phaseCount
        let labels = map.results.map { r -> Int in
            let indexed = r.verdict == .indexed || r.verdict == .matrix
            return indexed && r.phaseIndex >= 0 && Int(r.phaseIndex) < phaseCount ? Int(r.phaseIndex) : notIndexed
        }
        let names = Self.unique(map.phaseNames)
        let classes = names.enumerated().map { (id: Self.phaseIDBase + $0.offset, kind: SpectrumPool.Kind.phase, name: $0.element) }
            + [(id: Self.notIndexedID, kind: SpectrumPool.Kind.notIndexed, name: "Not indexed")]
        append(labels: labels, classes: classes, section: .phases, generation: generation, registration: registration,
               validation: Self.phaseMapValidation, product: "the phase map")
    }

    // MARK: Groups

    private mutating func add(groups result: DiffractionEmbedding.Result, generation: Int, registration: RegistrationRecordM2) {
        let k = result.groupCount
        guard k > 0 else { return }
        let classes = (0..<k).map { (id: Self.groupIDBase + $0, kind: SpectrumPool.Kind.group, name: "Group \($0 + 1)") }
        append(labels: result.groupOf.map { $0 >= 0 && $0 < k ? $0 : -1 }, classes: classes, section: .groups,
               generation: generation, registration: registration, validation: nil, product: "the diffraction groups")
    }

    private mutating func append(labels: [Int], classes: [(id: Int, kind: SpectrumPool.Kind, name: String)], section: PoolSection,
                                 generation: Int, registration: RegistrationRecordM2, validation: String?, product: String) {
        let t: TransportedLabels
        do { t = try MaskTransport.transport(labels: labels, classCount: classes.count, registration: registration) }
        catch { notes.append(PoolNote(section: section, text: "\(error)")); return }
        let membership = t.labels
        for (c, cls) in classes.enumerated() {
            let mask = membership.map { $0 == c }
            let count = mask.reduce(0) { $0 + ($1 ? 1 : 0) }
            guard count > 0 else {
                notes.append(PoolNote(section: section, text: "\(cls.name) covers no spectrum pixel by more than half: no pool."))
                continue
            }
            pools.append(SpectrumPool(id: cls.id, kind: cls.kind, name: cls.name, sourceGeneration: generation,
                                      pixelCount: count, mask: mask, validation: validation))
        }
    }

    /// Two phases may share a CIF's name (θ′ edge-on and face-on): the second is told apart, so a pool and its
    /// Auto ID outcome are never confused.
    private static func unique(_ names: [String]) -> [String] {
        var seen: [String: Int] = [:]
        return names.map { n in
            seen[n, default: 0] += 1
            return seen[n] == 1 ? n : "\(n) (\(seen[n]!))"
        }
    }
}
