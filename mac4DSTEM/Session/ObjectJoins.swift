//
//  ObjectJoins.swift
//  Role: composition and strain per precipitate object (suite task 42, design 2026-10-22 §5). Composition: each object's pixels on the
//        spectrum grid (through the session's registration), the spectrum image's exact integer sum over them, and ONE pooled fit of
//        that summed spectrum with the Spectroscopy room's method (`PooledQuantifier.run`, the fit Pool by Class uses): wt% and at%
//        with the fit's sigma. Strain: the strain map's labelled means (ImagoKit's `ObjectStatistics.measure`). This file builds the
//        masks and labels and says why a value is absent. Pure: no SwiftUI, no AppState.
//
//  Until 5.2.1 an object's composition was the mean of the per-pixel at% maps. At a few counts per pixel that mean is biased (a
//  ratio of small Poisson numbers, with the pixels the fit refused left out): on the Al-Mg-Si demo Mg read 18 at% where the summed
//  spectrum gives 23 and the truth is 23 (mac4DSTEM#113). The pooled fit is the number with a sigma.
//

import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import ImagoCore
import SpectroCore
import SpectroEDX
#endif
import ShellEDXModel

/// One element's composition of an object, from the pooled fit of the object's summed spectrum; the sigmas are that fit's.
package nonisolated struct ObjectComposition: Codable, Hashable, Sendable {
    package let symbol: String
    package let weightPercent: Double?
    package let atomicPercent: Double?
    package let weightSigma: Double?
    package let atomicSigma: Double?
    package init(symbol: String, weightPercent: Double?, atomicPercent: Double?, weightSigma: Double? = nil, atomicSigma: Double? = nil) {
        self.symbol = symbol; self.weightPercent = weightPercent; self.atomicPercent = atomicPercent
        self.weightSigma = weightSigma; self.atomicSigma = atomicSigma
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
    /// EDS pixels under the object (all of them are summed) and the counts of the summed spectrum.
    package var pixels: Int
    package var counts: UInt64
}

package nonisolated enum ObjectCompositionJoin {
    /// The sentence the section shows when no quantified spectrum image is there.
    package static let notQuantifiedSentence = "Open the EDS spectrum image of this scan and Quantify it for composition per object."

    /// What the fits need from the Spectroscopy room once it has quantified: the spectrum image, the room's method and the kit's tables.
    package struct Quantified: Sendable {
        package var source: any SpectrumImageSource
        package var method: QuantificationMethod
        package var tables: QuantificationTables?
        package init(source: any SpectrumImageSource, method: QuantificationMethod, tables: QuantificationTables?) {
            self.source = source; self.method = method; self.tables = tables
        }
    }

    /// - Parameters:
    ///   - objects: the class map's objects on the 4D scan grid.
    ///   - quantified: the quantified spectrum image and the room's method; nil: nothing was quantified.
    ///   - registration: where the spectrum grid sits on the scan grid; nil: the spectrum image is not registered to the scan.
    ///   - minimumPixels: an object under this many EDS pixels has no composition (default 4).
    ///   - cancelled: asked before each object's fit; a cancelled run returns what it has with `unavailable` set.
    package static func run(objects: PrecipitateSegmentation.ClassMapObjects, quantified: Quantified?,
                            registration: RegistrationRecordM2?, minimumPixels: Int = 4,
                            cancelled: @Sendable () -> Bool = { false }) -> ObjectJoinResult<ObjectCompositionValue> {
        guard let quantified else { return .init(unavailable: notQuantifiedSentence) }
        guard let registration else {
            return .init(unavailable: "This spectrum image is not registered to the 4D scan, so its pixels cannot be matched to the objects.")
        }
        let source = quantified.source
        let w = source.nx, h = source.ny
        guard registration.spectrumWidth == w, registration.spectrumHeight == h,
              registration.scanWidth == objects.width, registration.scanHeight == objects.height else {
            return .init(unavailable: "The registration is for other grids than this scan and this spectrum image.")
        }
        let all = objects.classes.flatMap(\.objects)
        guard !all.isEmpty else { return .init() }
        // An identity registration copies each object's pixels; any other transports its mask to the spectrum grid.
        let identity = registration.matrix == [1, 0, 0, 0, 1, 0] && w == objects.width && h == objects.height
        var out = ObjectJoinResult<ObjectCompositionValue>()
        for object in all {
            if cancelled() { return .init(unavailable: "The composition per object was stopped.") }
            var mask = [Bool](repeating: false, count: w * h)
            if identity {
                for i in object.pixelIndices where i >= 0 && i < mask.count { mask[i] = true }
            } else {
                var scan = [Bool](repeating: false, count: objects.width * objects.height)
                for i in object.pixelIndices where i >= 0 && i < scan.count { scan[i] = true }
                do { mask = try MaskTransport.transport(mask: scan, registration: registration).mask(forClass: 0) } catch {
                    return .init(unavailable: (error as? CustomStringConvertible)?.description ?? "\(error)")
                }
            }
            let pixels = mask.reduce(0) { $0 + ($1 ? 1 : 0) }
            guard pixels >= minimumPixels else {
                out.reasons[object.id] = pixels == 0 ? "no EDS pixel under the object" : "under \(minimumPixels) EDS px"
                continue
            }
            // The exact integer sum of the object's spectra, fitted once with the room's method: what Pool by Class does for a phase.
            let spectrum = source.sum(mask: mask)
            do {
                let fit = try PooledQuantifier.run(
                    PooledQuantificationInput(counts: spectrum, axis: source.energyAxis, method: quantified.method, metadata: source.metadata,
                                              regionName: "object \(object.id)", pixelCount: pixels),
                    tables: quantified.tables)
                if let refusal = fit.abundanceRefusal { out.reasons[object.id] = refusal; continue }
                let elements = fit.rows.map {
                    ObjectComposition(symbol: $0.element, weightPercent: $0.weightPercent, atomicPercent: $0.atomicPercent,
                                      weightSigma: $0.weightSigma, atomicSigma: $0.atomicSigma)
                }
                out.perObject[object.id] = ObjectCompositionValue(elements: elements, pixels: pixels, counts: spectrum.reduce(UInt64(0), &+))
            } catch {
                out.reasons[object.id] = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            }
        }
        return out
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
