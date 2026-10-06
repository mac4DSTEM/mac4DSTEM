//
//  RegistrationRecordM2.swift
//  Role: Where the spectrum image's grid sits on the 4D scan's (ADR 053 M2): a 2x3 affine from the
//        4D scan's pixel coordinates to the spectrum image's, the two grid sizes, and the NAME of
//        where the transform came from. The spectrum image stays on its native grid (never resampled);
//        masks travel across this record (`MaskTransport`), spectra never do.
//
//  Coordinates are pixel CENTRES: 4D pixel (x, y) has its centre at (x, y) and covers
//  [x - 1/2, x + 1/2] x [y - 1/2, y + 1/2]; the same for the spectrum grid. The map is
//      u = a00 x + a01 y + a02,    v = a10 x + a11 y + a12.
//  det < 0 (a mirror, the case the simulator plants) is allowed; det = 0 is not a registration.
//
//  Row-major `matrix` = [a00, a01, a02, a10, a11, a12], a flat array so the JSON is plain and
//  byte-stable (sorted keys, no dictionary of unordered fields).
//

import Foundation

package nonisolated struct RegistrationRecordM2: Codable, Equatable, Sendable {

    /// Where the transform came from. A reader of a saved session must be able to tell a measured
    /// registration from a typed one from the simulator's truth.
    package enum Source: String, Codable, CaseIterable, Sendable {
        /// Both signals from ONE acquisition run on one scan grid: the identity, no measurement needed.
        case identityFromOneRun
        /// Computed from the scan rectangles a file states for each signal (GMS spectrum-image rect).
        case fileRect
        /// Typed by the user, or fitted from landmarks the user placed (`fit`).
        case typed
        /// The simulator's planted transform (`tools/demo-edx`); a test, never a measurement.
        case simulatorTruth
    }

    package var matrix: [Double]
    package var source: Source
    /// Free text a reader needs: the file rect's numbers, the landmark residual, the truth file's name.
    package var sourceNote: String
    /// The 4D scan grid (columns, rows).
    package var scanWidth: Int
    package var scanHeight: Int
    /// The spectrum image's native grid (columns, rows).
    package var spectrumWidth: Int
    package var spectrumHeight: Int

    package nonisolated init(matrix: [Double], source: Source, sourceNote: String = "",
                             scanWidth: Int, scanHeight: Int, spectrumWidth: Int, spectrumHeight: Int) {
        precondition(matrix.count == 6, "RegistrationRecordM2: a 2x3 affine has 6 entries")
        self.matrix = matrix
        self.source = source
        self.sourceNote = sourceNote
        self.scanWidth = scanWidth; self.scanHeight = scanHeight
        self.spectrumWidth = spectrumWidth; self.spectrumHeight = spectrumHeight
    }

    /// The identity on one grid: both signals came from one run (`.identityFromOneRun`).
    package static func identity(width: Int, height: Int) -> RegistrationRecordM2 {
        RegistrationRecordM2(matrix: [1, 0, 0, 0, 1, 0], source: .identityFromOneRun,
                             sourceNote: "one acquisition run, one scan grid",
                             scanWidth: width, scanHeight: height, spectrumWidth: width, spectrumHeight: height)
    }

    package var determinant: Double { matrix[0] * matrix[4] - matrix[1] * matrix[3] }
    /// True for a mirror (det < 0), which is a legal registration.
    package var isReflection: Bool { determinant < 0 }
    package var isInvertible: Bool { determinant.isFinite && abs(determinant) > 1e-12 }

    /// 4D pixel-centre coordinates to spectrum pixel-centre coordinates.
    package func apply(x: Double, y: Double) -> (u: Double, v: Double) {
        (matrix[0] * x + matrix[1] * y + matrix[2], matrix[3] * x + matrix[4] * y + matrix[5])
    }

    /// The inverse map, nil when singular.
    package func applyInverse(u: Double, v: Double) -> (x: Double, y: Double)? {
        guard isInvertible else { return nil }
        let d = determinant
        let du = u - matrix[2], dv = v - matrix[5]
        return ((matrix[4] * du - matrix[1] * dv) / d, (-matrix[3] * du + matrix[0] * dv) / d)
    }

    // MARK: - Landmarks

    /// Least-squares affine through landmark pairs (4D pixel centre -> spectrum pixel centre). Needs at
    /// least 3 non-collinear pairs; nil otherwise. The residual (RMS, spectrum pixels) goes in the note.
    package static func fit(landmarks: [(scan: (x: Double, y: Double), spectrum: (u: Double, v: Double))],
                            scanWidth: Int, scanHeight: Int, spectrumWidth: Int, spectrumHeight: Int)
        -> RegistrationRecordM2? {
        guard landmarks.count >= 3 else { return nil }
        // Normal equations for [x y 1] * [a b c]^T = u (and = v): one 3x3 system, two right-hand sides.
        var m = [[Double]](repeating: [Double](repeating: 0, count: 3), count: 3)
        var ru = [Double](repeating: 0, count: 3), rv = [Double](repeating: 0, count: 3)
        for l in landmarks {
            let row = [l.scan.x, l.scan.y, 1]
            for i in 0..<3 {
                for j in 0..<3 { m[i][j] += row[i] * row[j] }
                ru[i] += row[i] * l.spectrum.u
                rv[i] += row[i] * l.spectrum.v
            }
        }
        guard let su = solve3(m, ru), let sv = solve3(m, rv) else { return nil }
        var sq = 0.0
        for l in landmarks {
            let du = su[0] * l.scan.x + su[1] * l.scan.y + su[2] - l.spectrum.u
            let dv = sv[0] * l.scan.x + sv[1] * l.scan.y + sv[2] - l.spectrum.v
            sq += du * du + dv * dv
        }
        let rms = (sq / Double(landmarks.count)).squareRoot()
        return RegistrationRecordM2(
            matrix: su + sv, source: .typed,
            sourceNote: "fitted from \(landmarks.count) landmarks, RMS residual \(String(format: "%.3g", rms)) spectrum px",
            scanWidth: scanWidth, scanHeight: scanHeight, spectrumWidth: spectrumWidth, spectrumHeight: spectrumHeight)
    }

    /// Gauss-Jordan with partial pivoting; nil when singular (collinear landmarks).
    private static func solve3(_ a: [[Double]], _ b: [Double]) -> [Double]? {
        var m = a, r = b
        for c in 0..<3 {
            var p = c
            for i in c..<3 where abs(m[i][c]) > abs(m[p][c]) { p = i }
            guard abs(m[p][c]) > 1e-12 else { return nil }
            m.swapAt(c, p); r.swapAt(c, p)
            for i in 0..<3 where i != c {
                let f = m[i][c] / m[c][c]
                for j in 0..<3 { m[i][j] -= f * m[c][j] }
                r[i] -= f * r[c]
            }
        }
        return (0..<3).map { r[$0] / m[$0][$0] }
    }

    // MARK: - Byte-stable form

    package var canonicalJSON: String {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        // try! is safe: arrays of doubles, strings, ints and an enum of strings.
        return String(decoding: try! e.encode(self), as: UTF8.self)
    }

    package static func decode(_ json: String) -> RegistrationRecordM2? {
        guard let r = try? JSONDecoder().decode(RegistrationRecordM2.self, from: Data(json.utf8)),
              r.matrix.count == 6, r.matrix.allSatisfy(\.isFinite) else { return nil }
        return r
    }
}
