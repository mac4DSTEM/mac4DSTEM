//
//  ObjectJoins.swift
//  Role: composition and strain per precipitate object (suite task 42, design 2026-10-22 §5): the objects' pixels joined with the
//        quantified maps (the Spectroscopy room's wt% / at%, on the spectrum grid, through the session's registration) and with the
//        strain map (on the scan grid). The means are ImagoKit's labelled statistics (`ObjectStatistics.measure`); this file only
//        builds the labels, drops the pixels that carry no value, and says why a value is absent. Pure: no SwiftUI, no AppState.
//
//  A per-object mean is a MEAN OF PER-PIXEL values of badged maps (the maps have no sigma). It is not the pooled fit's composition
//  with a sigma (Pool by Class remains that); the columns say so.
//

import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import ImagoCore
import SpectroCore
import SpectroEDX
#endif
import ShellEDXModel

/// One element's mean composition under an object, from the per-pixel maps.
package nonisolated struct ObjectComposition: Codable, Hashable, Sendable {
    package let symbol: String
    package let weightPercent: Double?
    package let atomicPercent: Double?
    package init(symbol: String, weightPercent: Double?, atomicPercent: Double?) {
        self.symbol = symbol; self.weightPercent = weightPercent; self.atomicPercent = atomicPercent
    }
}

/// An object's mean strain and its spread across the object's pixels, in rows and columns: rr along the rows (y), cc along the columns
/// (x), rc the shear, rotation in degrees (the map's radians). Sigmas are the population spread over the pixels, not a fit error.
package nonisolated struct ObjectStrain: Codable, Hashable, Sendable {
    package let rr: Double, cc: Double, rc: Double, rotationDegrees: Double
    package let sigmaRR: Double, sigmaCC: Double, sigmaRC: Double
    /// Scan positions averaged (those the strain fit covered).
    package let pixels: Int
    package init(rr: Double, cc: Double, rc: Double, rotationDegrees: Double, sigmaRR: Double, sigmaCC: Double, sigmaRC: Double, pixels: Int) {
        self.rr = rr; self.cc = cc; self.rc = rc; self.rotationDegrees = rotationDegrees
        self.sigmaRR = sigmaRR; self.sigmaCC = sigmaCC; self.sigmaRC = sigmaRC; self.pixels = pixels
    }
}

/// What a join gives the report: per object id its values or the reason it has none, and one sentence for the whole join when it
/// could not run at all.
package nonisolated struct ObjectJoinResult<Value: Sendable & Equatable>: Sendable, Equatable {
    package var perObject: [Int: Value]
    /// Objects without a value, with the reason ("under 4 EDS px").
    package var reasons: [Int: String]
    /// Set when the join could not run: the report then shows no columns and the section says this.
    package var unavailable: String?
    package init(perObject: [Int: Value] = [:], reasons: [Int: String] = [:], unavailable: String? = nil) {
        self.perObject = perObject; self.reasons = reasons; self.unavailable = unavailable
    }
}

package nonisolated struct ObjectCompositionValue: Sendable, Equatable {
    package var elements: [ObjectComposition]
    /// EDX pixels averaged, and those under the object the maps could not give a value for (failed fit, masked low counts).
    package var pixels: Int
    package var excluded: Int
}

package nonisolated enum ObjectCompositionJoin {
    /// The sentence the section shows when no quantified spectrum image is there.
    package static let noMapsSentence = "Open the EDS spectrum image of this scan and Quantify it for composition per object."

    /// - Parameters:
    ///   - objects: the class map's objects on the 4D scan grid.
    ///   - maps: the quantified maps (wt% and at% per element, NaN where the fit failed, 0 where masked) on the spectrum grid.
    ///   - registration: where the spectrum grid sits on the scan grid; nil: the spectrum image is not registered to the scan.
    ///   - minimumPixels: an object under this many EDX pixels has no composition (default 4).
    package static func run(objects: PrecipitateSegmentation.ClassMapObjects, maps: EDXQuantificationMaps?,
                            registration: RegistrationRecordM2?, minimumPixels: Int = 4) -> ObjectJoinResult<ObjectCompositionValue> {
        guard let maps, !maps.elements.isEmpty else { return .init(unavailable: noMapsSentence) }
        guard let registration else {
            return .init(unavailable: "This spectrum image is not registered to the 4D scan, so its pixels cannot be matched to the objects.")
        }
        guard registration.spectrumWidth == maps.columns, registration.spectrumHeight == maps.rows,
              registration.scanWidth == objects.width, registration.scanHeight == objects.height else {
            return .init(unavailable: "The registration is for other grids than this scan and these maps.")
        }
        let all = objects.classes.flatMap(\.objects)
        guard !all.isEmpty else { return .init() }
        let w = maps.columns, h = maps.rows
        // Spectrum-grid labels: object index + 1, 0 elsewhere. An identity registration copies; any other transports each object's mask.
        var labels = [Int32](repeating: 0, count: w * h)
        let identity = registration.matrix == [1, 0, 0, 0, 1, 0] && w == objects.width && h == objects.height
        do {
            for (index, object) in all.enumerated() {
                if identity {
                    for i in object.pixelIndices where i >= 0 && i < labels.count { labels[i] = Int32(index + 1) }
                } else {
                    var mask = [Bool](repeating: false, count: objects.width * objects.height)
                    for i in object.pixelIndices where i >= 0 && i < mask.count { mask[i] = true }
                    let moved = try MaskTransport.transport(mask: mask, registration: registration)
                    for (p, inside) in moved.mask(forClass: 0).enumerated() where inside && labels[p] == 0 { labels[p] = Int32(index + 1) }
                }
            }
        } catch {
            return .init(unavailable: (error as? CustomStringConvertible)?.description ?? "\(error)")
        }
        // A pixel carries a value when its fit succeeded and it was not masked (a masked pixel reads 0 in every element).
        var valid = [Bool](repeating: false, count: w * h)
        for p in 0..<w * h {
            guard maps.failures[p] == nil else { continue }
            var sum = 0.0
            for e in maps.elements.indices { sum += maps.atomicPercent[e][p].isFinite ? maps.atomicPercent[e][p] : 0 }
            valid[p] = sum > 0
        }
        let counted = Segmentation.LabelImage(width: w, height: h,
                                              labels: zip(labels, valid).map { $1 ? $0 : 0 }, count: all.count)
        var covered = [Int](repeating: 0, count: all.count + 1)
        for l in labels where l > 0 { covered[Int(l)] += 1 }
        do {
            let weight = try maps.weightPercent.map { try ObjectStatistics.measure(image: $0, labels: counted) }
            let atomic = try maps.atomicPercent.map { try ObjectStatistics.measure(image: $0, labels: counted) }
            var out = ObjectJoinResult<ObjectCompositionValue>()
            for (index, object) in all.enumerated() {
                let label = Int32(index + 1)
                let pixels = atomic.first?.first { $0.label == label }?.count ?? 0
                if pixels < minimumPixels {
                    out.reasons[object.id] = covered[Int(label)] == 0 ? "no EDS pixel under the object" : "under \(minimumPixels) EDS px"
                    continue
                }
                let elements = maps.elements.indices.map { e in
                    ObjectComposition(symbol: maps.elements[e],
                                      weightPercent: weight[e].first { $0.label == label }?.mean,
                                      atomicPercent: atomic[e].first { $0.label == label }?.mean)
                }
                out.perObject[object.id] = ObjectCompositionValue(elements: elements, pixels: pixels, excluded: covered[Int(label)] - pixels)
            }
            return out
        } catch {
            return .init(unavailable: "\(error)")
        }
    }
}

package nonisolated enum ObjectStrainJoin {
    package static let noStrainSentence = "Compute strain in Crystal Maps for strain per object."

    /// `strain` is the presented strain (the frame the strain pane shows); its fit mask says where a value exists.
    package static func run(objects: PrecipitateSegmentation.ClassMapObjects, strain: PresentedStrainMap?) -> ObjectJoinResult<ObjectStrain> {
        guard let strain else { return .init(unavailable: noStrainSentence) }
        guard strain.base.width == objects.width, strain.base.height == objects.height else {
            return .init(unavailable: "The strain map is for another scan than the class map.")
        }
        let all = objects.classes.flatMap(\.objects)
        guard !all.isEmpty else { return .init() }
        let w = objects.width, h = objects.height
        var labels = [Int32](repeating: 0, count: w * h)
        for (index, object) in all.enumerated() {
            for i in object.pixelIndices where i >= 0 && i < labels.count && strain.base.mask[i] { labels[i] = Int32(index + 1) }
        }
        let image = Segmentation.LabelImage(width: w, height: h, labels: labels, count: all.count)
        do {
            func stats(_ values: [Float]) throws -> [ObjectStatistics.Result] {
                try ObjectStatistics.measure(image: values.map(Double.init), labels: image)
            }
            let (exx, eyy, exy, theta) = (try stats(strain.exx), try stats(strain.eyy), try stats(strain.exy), try stats(strain.theta))
            var out = ObjectJoinResult<ObjectStrain>()
            for (index, object) in all.enumerated() {
                let label = Int32(index + 1)
                guard let x = exx.first(where: { $0.label == label }), let y = eyy.first(where: { $0.label == label }),
                      let s = exy.first(where: { $0.label == label }), let t = theta.first(where: { $0.label == label }) else {
                    out.reasons[object.id] = "no strain fit under the object"
                    continue
                }
                // eyy is the row direction, exx the column direction: rows and columns, not x and y.
                out.perObject[object.id] = ObjectStrain(
                    rr: y.mean, cc: x.mean, rc: s.mean, rotationDegrees: t.mean * 180 / .pi,
                    sigmaRR: y.standardDeviation, sigmaCC: x.standardDeviation, sigmaRC: s.standardDeviation, pixels: x.count)
            }
            return out
        } catch {
            return .init(unavailable: "\(error)")
        }
    }
}
