//
//  CompositionByClass.swift
//  Role: "Pool by Class" (design rooms-2026-10-21 §3, study items 1 and 2): the existing phase pools (`PoolCatalogue`, masks moved
//        to the spectrum grid by `MaskTransport`) each summed once and fitted with the room's current method, and the result as
//        a composition-by-class CSV. No numerics here: the sum is the source's exact integer sum, the fit is
//        `PooledQuantifier.run`, the pool is the catalogue's. The number stays a pooled fit with a sigma.
//

import Foundation
import SpectroCore
import SpectroEDX

nonisolated struct ClassComposition: Sendable, Equatable {
    struct Row: Sendable, Equatable {
        var element: String
        var weightPercent: Double?, weightSigma: Double?
        var atomicPercent: Double?, atomicSigma: Double?
        var failure: String?
    }
    var className: String
    var pixels: Int
    var counts: UInt64
    var rows: [Row]
    /// The kit's sentence when the pool could not be fitted.
    var failure: String?
    /// The pool's source claim ("none" for a phase map) joined with the quantification's own.
    var validation: String
}

nonisolated enum CompositionByClass {
    struct Pool: Sendable { var name: String; var pixels: Int; var spectrum: [UInt64] }

    /// One fit per pool; a pool the kit cannot fit is a row with its sentence, never a missing class. Cancelling throws.
    static func run(pools: [Pool], axis: EnergyAxis, metadata: SpectrumImageMetadata, method: QuantificationMethod,
                    tables: QuantificationTables?, cancelled: @Sendable () -> Bool = { Task.isCancelled }) throws -> [ClassComposition] {
        var out: [ClassComposition] = []
        for p in pools {
            if cancelled() { throw CancellationError() }
            let total = p.spectrum.reduce(UInt64(0), &+)
            do {
                let input = PooledQuantificationInput(counts: p.spectrum, axis: axis, method: method, metadata: metadata,
                                                      regionName: p.name, pixelCount: p.pixels)
                let fit = try PooledQuantifier.run(input, tables: tables)
                let rows = fit.rows.map {
                    ClassComposition.Row(element: $0.element, weightPercent: $0.weightPercent, weightSigma: $0.weightSigma,
                                         atomicPercent: $0.atomicPercent, atomicSigma: $0.atomicSigma, failure: $0.failure)
                }
                out.append(ClassComposition(className: p.name, pixels: p.pixels, counts: total, rows: rows, failure: fit.abundanceRefusal,
                                            validation: PooledQuantification.abundanceValidation))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                out.append(ClassComposition(className: p.name, pixels: p.pixels, counts: total, rows: [],
                                            failure: (error as? LocalizedError)?.errorDescription ?? "\(error)",
                                            validation: PooledQuantification.abundanceValidation))
            }
        }
        return out
    }

    /// class, pixels pooled, element, wt%, sigma, at%, sigma, method hash; the `#` header names the file, the method and the badge.
    static func csv(_ results: [ClassComposition], imageName: String, method: QuantificationMethod) -> String {
        func num(_ v: Double?) -> String { v.map { String(format: "%.6g", $0) } ?? "" }
        func field(_ s: String) -> String { s.contains(",") || s.contains("\"") ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s }
        var out = ["# mac4DSTEM Spectroscopy composition by class, file: \(imageName)",
                   "# one pooled fit per phase pool (the class's spectrum pixels, summed once); sigma is the pooled fit's",
                   "# validation: none (the phase map and the quantification are both unvalidated)",
                   "# method hash (sha256 of the method JSON): \(method.hash)",
                   "class,pixels_pooled,counts,element,wt_percent,sigma_wt_percent,at_percent,sigma_at_percent,validation,method_hash,note"]
        for c in results {
            if c.rows.isEmpty {
                out.append([field(c.className), "\(c.pixels)", "\(c.counts)", "", "", "", "", "", c.validation, method.hash, field(c.failure ?? "")].joined(separator: ","))
            }
            for r in c.rows {
                out.append([field(c.className), "\(c.pixels)", "\(c.counts)", r.element, num(r.weightPercent), num(r.weightSigma),
                            num(r.atomicPercent), num(r.atomicSigma), c.validation, method.hash,
                            field(r.failure ?? c.failure ?? "")].joined(separator: ","))
            }
        }
        return out.joined(separator: "\n") + "\n"
    }
}
