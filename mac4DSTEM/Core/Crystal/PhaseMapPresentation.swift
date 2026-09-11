//
//  PhaseMapPresentation.swift
//  Role: turning a `PhaseMap` into the three things a person needs — a
//        coloured map, a distance map, and one line of evidence for one
//        position. Core, not UI: the colours are part of the result's
//        meaning here (a legend has to match the map exactly), and the
//        harness and the tests both read them.
//
//  Three presentation decisions carry scientific weight and are made here
//  rather than in a view:
//
//  1. THE MATRIX IS NEUTRAL. It is most of the scan and it is not the finding.
//     A saturated colour on 90 % of the pixels makes a map about aluminium.
//  2. "NOT INDEXED" IS HATCHED, NOT COLOURED. It is the honest answer, and it
//     must not be readable as "some phase". A diagonal stripe cannot be
//     mistaken for a member of the palette at any zoom, which a grey cannot
//     promise once someone changes the colour map.
//  3. THE PALETTE IS OKABE-ITO. Eight hues chosen to stay distinguishable
//     under the common colour-vision deficiencies (Okabe & Ito, "Color
//     Universal Design", 2008). A phase map whose two phases are red and
//     green is unreadable to ~8 % of men.
//

import Foundation

package nonisolated enum PhaseMapPresentation {

    package typealias RGB = (r: UInt8, g: UInt8, b: UInt8)

    /// Okabe-Ito, in the order phases are assigned.
    package static let palette: [RGB] = [
        (230, 159, 0),      // orange
        (86, 180, 233),     // sky blue
        (0, 158, 115),      // bluish green
        (240, 228, 66),     // yellow
        (0, 114, 178),      // blue
        (213, 94, 0),       // vermillion
        (204, 121, 167),    // reddish purple
        (140, 140, 140),    // grey, last resort
    ]

    /// Neutral, dark: the matrix is the background of the finding.
    package static let matrixColor: RGB = (58, 58, 64)
    /// The two greys of the "not indexed" hatch.
    package static let notIndexedColors: (RGB, RGB) = ((168, 168, 172), (208, 208, 212))

    /// Colour for a phase. The matrix keeps `matrixColor` whatever its index,
    /// so adding a phase before it in the list cannot recolour the map.
    package static func color(phaseIndex: Int, matrixPhaseIndex: Int) -> RGB {
        if phaseIndex == matrixPhaseIndex { return matrixColor }
        // Candidates are numbered among themselves, so phase 0 as matrix and
        // phase 2 as matrix both give the first candidate the first hue.
        let rank = phaseIndex < matrixPhaseIndex ? phaseIndex : phaseIndex - 1
        return palette[rank % palette.count]
    }

    /// The phase map as an image. Alpha is 0 where there were no peaks, so the
    /// masked swatch in the colorbar means "nothing measured here" and not
    /// "a phase drawn in black".
    package static func image(_ map: PhaseMap) -> RGBAImage {
        var out = [UInt8](repeating: 0, count: max(0, map.width * map.height * 4))
        for y in 0..<map.height {
            for x in 0..<map.width {
                let i = y * map.width + x
                let r = map.results[i]
                var rgb: RGB
                var alpha: UInt8 = 255
                switch r.verdict {
                case .matrix:
                    rgb = matrixColor
                case .indexed:
                    rgb = color(phaseIndex: Int(r.phaseIndex),
                                matrixPhaseIndex: map.matrixPhaseIndex)
                case .notIndexed:
                    // A 6-pixel diagonal stripe: unmistakable at any zoom, and
                    // it survives every colour map because it is two greys and
                    // a shape rather than a hue.
                    rgb = ((x + y) % 6 < 3) ? notIndexedColors.0 : notIndexedColors.1
                case .noData:
                    rgb = (0, 0, 0); alpha = 0
                }
                out[i * 4] = rgb.r; out[i * 4 + 1] = rgb.g
                out[i * 4 + 2] = rgb.b; out[i * 4 + 3] = alpha
            }
        }
        return RGBAImage(width: map.width, height: map.height, rgba: out)
    }

    /// The winning mean distance per position, Å⁻¹ — the quantitative
    /// companion to a categorical map, and the one a reader can argue with.
    /// Matrix and no-data positions are NaN and masked, not zero: zero would
    /// read as a perfect match.
    package static func distanceImage(_ map: PhaseMap) -> FloatImage {
        FloatImage(width: map.width, height: map.height,
                   pixels: map.results.map { $0.verdict == .indexed ? $0.score : .nan })
    }

    /// Positions where `distanceImage` carries a measurement.
    package static func distanceValidity(_ map: PhaseMap) -> [Bool] {
        map.results.map { $0.verdict == .indexed && $0.score.isFinite }
    }

    /// One legend row per phase, plus the two verdicts that are not phases.
    package struct LegendRow: Sendable {
        package let label: String
        package let color: RGB
        package let hatched: Bool
        package let count: Int
        package let fraction: Double
    }

    package static func legend(_ map: PhaseMap) -> [LegendRow] {
        let total = max(1, map.results.count)
        var rows: [LegendRow] = []
        let counts = map.phaseCounts
        for (index, name) in map.phaseNames.enumerated() {
            let count = index < counts.count ? counts[index] : 0
            rows.append(LegendRow(
                label: index == map.matrixPhaseIndex ? "\(name) (matrix)" : name,
                color: color(phaseIndex: index, matrixPhaseIndex: map.matrixPhaseIndex),
                hatched: false, count: count, fraction: Double(count) / Double(total)))
        }
        let notIndexed = map.count(of: .notIndexed)
        rows.append(LegendRow(label: "Not indexed", color: notIndexedColors.0,
                              hatched: true, count: notIndexed,
                              fraction: Double(notIndexed) / Double(total)))
        let noData = map.count(of: .noData)
        if noData > 0 {
            rows.append(LegendRow(label: "No peaks", color: (0, 0, 0), hatched: false,
                                  count: noData, fraction: Double(noData) / Double(total)))
        }
        return rows
    }

    /// The argument for one position's label, in one line, in physical units.
    ///
    /// This is the point of keeping every count on `PhaseVectorResult`. A
    /// phase map that cannot say WHY a pixel is that colour is a picture, not
    /// a measurement — and this repo has already been bitten once by a score
    /// whose resolution was invisible (`archive/v3/phase-discrimination-2026-09-11.md`).
    package static func evidenceLine(_ result: PhaseVectorResult, map: PhaseMap) -> String {
        func name(_ i: Int32) -> String {
            let index = Int(i)
            return map.phaseNames.indices.contains(index) ? map.phaseNames[index] : "?"
        }
        switch result.verdict {
        case .noData:
            return "No peaks at this position."
        case .matrix:
            return "\(name(Int32(map.matrixPhaseIndex))) — "
                + "\(result.removedCount) of \(result.removedCount + result.survivingCount) "
                + "vectors are the matrix's, and \(result.survivingCount) is too few to index."
        case .notIndexed, .indexed:
            var parts: [String] = []
            if result.verdict == .indexed {
                parts.append(name(result.phaseIndex))
            } else {
                parts.append("Not indexed")
            }
            parts.append("\(result.matchedCount) of \(result.survivingCount) vectors")
            if result.score.isFinite {
                parts.append(String(format: "mean %.4f Å⁻¹", result.score))
            }
            if result.removedCount > 0 {
                parts.append("\(result.removedCount) matrix removed")
            }
            if result.runnerUpScore.isFinite {
                parts.append(String(format: "next %@ at %.4f",
                                    name(result.runnerUpPhaseIndex), result.runnerUpScore))
            }
            return parts.joined(separator: " · ")
        }
    }
}
