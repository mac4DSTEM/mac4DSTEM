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

    /// How much of this position's detected signal the matrix explained, or
    /// nil where the question does not apply (nothing detected).
    package static func explainedFraction(_ r: PhaseVectorResult) -> Double? {
        let detected = Int(r.survivingCount) + Int(r.removedCount)
        guard detected > 0 else { return nil }
        return Double(r.removedCount) / Double(detected)
    }

    /// The median explained fraction behind this map's matrix verdicts, or nil
    /// if it has none — the one honest summary of how much the matrix actually
    /// accounted for, reported rather than thresholded.
    ///
    /// NO BAR, AND THE REASON IS MEASURED (2026-09-16). A fixed bar was built
    /// at 0.90, chosen from Thronsen's stride-3 subsample at a 0.1 % detection
    /// threshold, where it flagged 51 of the 61 wrong matrix calls and 7 % of
    /// the right ones. The demo cube, at its shipped threshold, then flagged
    /// **46 % of a map whose every acceptance clause passes at 100 %**
    /// (`demo-partial-20260916.log`). The explained fraction falls as detection
    /// admits more noise, so a bar that means "weak evidence" on one dataset
    /// means "ordinary" on another, and hatching half a correct map is worse
    /// than no mark at all. The quantity is real and is reported; the
    /// threshold was a guess dressed as a measurement and is gone.
    package static func medianMatrixExplainedFraction(_ map: PhaseMap) -> Double? {
        let fracs = map.results
            .filter { $0.verdict == .matrix }
            .compactMap(explainedFraction)
            .sorted()
        guard !fracs.isEmpty else { return nil }
        return fracs[fracs.count / 2]
    }

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

    /// What a finished map says about ITSELF, when the answer is "nothing
    /// matched" — or nil when the map found something.
    ///
    /// A map that is 99 % "not indexed" with zero matrix positions is not a
    /// result about the specimen; it is a result about the settings, and the
    /// two look identical on screen. Measured on the owner's run, 2026-09-12:
    /// β″ 1, matrix 0, not indexed 108 899. The cause was a matrix tolerance
    /// smaller than the detector pixel, and nothing said so.
    ///
    /// The ORDER of the tests is the point — the most specific explanation
    /// first, so the user is not told "check your tolerances" when the real
    /// answer is "there were no peaks".
    package static func diagnosis(_ map: PhaseMap,
                                  resolution: PhaseVectorResolution?) -> String? {
        let total = map.results.count
        guard total > 0 else { return nil }
        let noData = map.count(of: .noData)
        let notIndexed = map.count(of: .notIndexed)
        let matrix = map.count(of: .matrix)
        let indexed = map.count(of: .indexed)

        if noData >= total / 2 {
            return "Over half the scan has no usable peaks. Detect Bragg disks "
                + "with settings that find peaks at every position first."
        }
        // The trigger is "almost nothing was INDEXED, and a lot was refused" —
        // not "almost everything was refused", which the first version asked
        // for and which no map with a healthy matrix can ever satisfy. Caught
        // by its own test, 2026-09-12: a map of 499 matrix, 500 not indexed
        // and 1 indexed is the clearest possible case of "the frame works and
        // the candidates do not", and the first rule returned nil for it.
        //
        // Both halves are needed. A scan that is ALL matrix and nothing else
        // is a clean result about a precipitate-free region, not a failure,
        // and must say nothing.
        guard indexed * 100 <= total, notIndexed + noData >= total / 2 else { return nil }

        if matrix == 0 {
            var text = "Nothing was removed as matrix, anywhere. Every experimental "
                + "vector stayed further from every matrix reference vector than the "
                + "matrix-removal tolerance allows."
            if let resolution, resolution.matrixRemovalPixels < 1 {
                text += String(format: " That tolerance is %.2f of one detector pixel "
                               + "here — smaller than the grid the peaks were measured on.",
                               resolution.matrixRemovalPixels)
            } else {
                text += " Check the matrix phase and its zone axis: a matrix viewed "
                    + "down an axis it is not on presents no reflections to remove."
            }
            return text
        }
        return "Almost nothing was indexed. The matrix was found, so the frame and "
            + "the tolerances are working — it is the candidate phases that do not "
            + "match. Check each one's zone axis."
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
            // TWO ROUTES REACH THIS VERDICT and they are different facts about
            // the specimen, so they may not share a sentence. Removal leaves
            // too little to index (`matchedCount == 0`), or an orientation of
            // the matrix crystal explained the pattern better than any
            // candidate did (`classify` step 5). Gate B caught the second
            // narrated as the first: a challenged position read "0 of 8
            // vectors are the matrix's, and 8 is too few to index" when the
            // matrix had in fact matched 6 of them.
            if result.matchedCount > 0 {
                return "\(name(Int32(map.matrixPhaseIndex))) — on another orientation: it "
                    + "accounts for \(result.matchedCount) of \(result.survivingCount) "
                    + "vectors here, closer than any candidate phase."
            }
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
