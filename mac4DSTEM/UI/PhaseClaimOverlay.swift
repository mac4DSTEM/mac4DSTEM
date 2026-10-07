//
//  PhaseClaimOverlay.swift
//  Role: on the diffraction pane in the phase-mapping task, ring every detected
//        Bragg disk of the selected scan position in the colour of whoever
//        CLAIMED it — the matrix, a precipitate phase, or nobody.
//
//  The question it answers is the one a phase map's colour cannot: "which of
//  the disks I can see made this pixel that colour?" (owner request
//  2026-09-25; design delegated 2026-09-30).
//
//  Rendering only. The claims come from `PhaseVectorMatcher.claims`, a replay
//  of the matcher's own pairing against the entry the map recorded for this
//  position, so the rings cannot disagree with the map. This file adds the
//  two things Core does not hold: the reference library (kept by
//  `PhaseMappingProduct` beside the run it was built for) and the position's
//  calibrated peaks.
//
//  Visual vocabulary, in keeping with `PatternFitOverlay`, colour on the
//  marks only:
//    coloured solid ring = claimed by that phase (the map's own class colour)
//    light grey ring     = removed as the matrix's
//    dashed white ring   = unexplained: detected, offered, claimed by nothing
//    faint thin ring     = never offered (direct beam / out of range)
//  With no probe kernel there is no disk radius to draw (`PeakOverlayGeometry`),
//  so the same classes are drawn as crosses.
//

import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

// MARK: - Style

/// The look of one claim class. One definition for the rings and the legend.
private struct ClaimStyle {
    let color: Color
    let lineWidth: CGFloat
    let dash: [CGFloat]

    static let matrix = ClaimStyle(color: Color(white: 0.85), lineWidth: 1.4, dash: [])
    static let unexplained = ClaimStyle(color: .white, lineWidth: 1.4, dash: [3, 2.5])
    static let notMatched = ClaimStyle(color: Color(white: 1, opacity: 0.4), lineWidth: 0.8, dash: [])

    static func phase(_ phaseIndex: Int, matrixPhaseIndex: Int) -> ClaimStyle {
        let rgb = PhaseMapPresentation.color(phaseIndex: phaseIndex,
                                             matrixPhaseIndex: matrixPhaseIndex)
        return ClaimStyle(color: Color(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255,
                                       blue: Double(rgb.b) / 255),
                          lineWidth: 2.4, dash: [])
    }

    var stroke: StrokeStyle { StrokeStyle(lineWidth: lineWidth, dash: dash) }

    static func style(for claim: PhaseDiskClaim, matrixPhaseIndex: Int) -> ClaimStyle {
        switch claim {
        case .notMatched: .notMatched
        case .matrix: .matrix
        case .phase(let index): .phase(index, matrixPhaseIndex: matrixPhaseIndex)
        case .unexplained: .unexplained
        }
    }
}

// MARK: - Drawing

/// The rings and their legend. Pure drawing over values.
///
/// Two parts, drawn by two layers: the rings sit in the zoomed layer (they belong to
/// the image), the legend and note in the unzoomed one beside the fit key (P2c, polish
/// drive 2026-10-04). Inside the zoom transform the legend scaled and moved with the pattern.
struct PhaseClaimOverlay: View {
    enum Part: Equatable { case rings, legend }

    let part: Part
    let peaks: [BraggPeak]
    /// One per peak, same order (`PhaseVectorMatcher.claims`).
    let claims: [PhaseDiskClaim]
    let phaseNames: [String]
    let matrixPhaseIndex: Int
    /// nil when no probe kernel exists: the claims are then drawn as crosses.
    let probeRadius: Float?
    let patternWidth: Int
    let patternHeight: Int
    let box: CGSize

    @ViewBuilder
    var body: some View {
        switch part {
        case .rings:
            rings
        case .legend:
            legend
                .padding(6)
                .frame(width: box.width, height: box.height, alignment: .topTrailing)
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Claimed disks")
                .accessibilityValue(legendText)
        }
    }

    private var rings: some View {
        Canvas { context, _ in
            let radius = PeakOverlayGeometry.radius(
                probeRadius: probeRadius,
                patternWidth: patternWidth, patternHeight: patternHeight, box: box)
            // Least informative first, so a claimed ring is never hidden
            // under a neighbour's.
            for rank in 0..<4 {
                for (peak, claim) in zip(peaks, claims) where Self.drawRank(claim) == rank {
                    let style = ClaimStyle.style(for: claim, matrixPhaseIndex: matrixPhaseIndex)
                    let c = PeakOverlayGeometry.center(
                        x: peak.x, y: peak.y,
                        patternWidth: patternWidth, patternHeight: patternHeight, box: box)
                    draw(at: c, radius: radius, style: style, in: &context)
                }
            }
        }
        .frame(width: box.width, height: box.height)
        .allowsHitTesting(false)
        // The legend half carries the label and value for the whole overlay.
        .accessibilityHidden(true)
    }

    private static func drawRank(_ claim: PhaseDiskClaim) -> Int {
        switch claim {
        case .notMatched: 0
        case .matrix: 1
        case .unexplained: 2
        case .phase: 3
        }
    }

    private func draw(at c: CGPoint, radius: CGFloat?, style: ClaimStyle,
                      in context: inout GraphicsContext) {
        var path = Path()
        if let r = radius {
            path.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        } else {
            let h = PeakOverlay.markerHalfSize
            path.move(to: CGPoint(x: c.x - h, y: c.y)); path.addLine(to: CGPoint(x: c.x + h, y: c.y))
            path.move(to: CGPoint(x: c.x, y: c.y - h)); path.addLine(to: CGPoint(x: c.x, y: c.y + h))
        }
        // A dark halo first, so a light ring reads on a bright disk.
        context.stroke(path, with: .color(.black.opacity(0.55)),
                       style: StrokeStyle(lineWidth: style.lineWidth + 1.6))
        context.stroke(path, with: .color(style.color), style: style.stroke)
    }

    // MARK: Legend

    private struct Row: Identifiable {
        let id: String
        let label: String
        let style: ClaimStyle
        let count: Int
    }

    /// Only the classes present, phases first, then matrix, unexplained.
    private var rows: [Row] {
        var phaseCounts: [Int: Int] = [:]
        var matrix = 0, unexplained = 0, notMatched = 0
        for claim in claims {
            switch claim {
            case .phase(let p): phaseCounts[p, default: 0] += 1
            case .matrix: matrix += 1
            case .unexplained: unexplained += 1
            case .notMatched: notMatched += 1
            }
        }
        var out: [Row] = phaseCounts.keys.sorted().map { p in
            Row(id: "phase\(p)",
                label: p >= 0 && p < phaseNames.count ? phaseNames[p] : "Phase \(p)",
                style: .phase(p, matrixPhaseIndex: matrixPhaseIndex),
                count: phaseCounts[p] ?? 0)
        }
        if matrix > 0 {
            let name = matrixPhaseIndex >= 0 && matrixPhaseIndex < phaseNames.count
                ? "\(phaseNames[matrixPhaseIndex]) (matrix)" : "Matrix"
            out.append(Row(id: "matrix", label: name, style: .matrix, count: matrix))
        }
        if unexplained > 0 {
            out.append(Row(id: "unexplained", label: "Unexplained", style: .unexplained,
                           count: unexplained))
        }
        if notMatched > 0 {
            out.append(Row(id: "notMatched", label: "Not matched (direct beam / range)",
                           style: .notMatched, count: notMatched))
        }
        return out
    }

    private var legendText: String {
        rows.map { "\($0.label) \($0.count)" }.joined(separator: ", ")
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(rows) { row in
                HStack(spacing: 5) {
                    Circle()
                        .strokeBorder(row.style.color, style: row.style.stroke)
                        .frame(width: 9, height: 9)
                    Text("\(row.label) · \(row.count)")
                        .lineLimit(1)
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - The layer that feeds it

/// Reads the selected position from the app, rebuilds what Core needs, and
/// hands `PhaseClaimOverlay` the claims. Shown only while the map is current
/// (`!isStale`, same Q scale) — otherwise the rings would be of a different
/// question than the map's.
struct PhaseClaimLayer: View {
    @Environment(AppState.self) private var appState
    let patternWidth: Int
    let patternHeight: Int
    let box: CGSize
    /// Which half this layer draws (see `PhaseClaimOverlay.Part`); the note belongs to the legend half.
    let part: PhaseClaimOverlay.Part

    @State private var claims: [PhaseDiskClaim] = []
    @State private var claimedPeakCount = 0
    @State private var note: String?

    private struct Key: Equatable {
        var run: PhaseMappingProduct.RunRecord?
        var stale: Bool
        var x: Int, y: Int
        var scale: Double
        var peakCount: Int
        /// Origin, ellipse and the fitted maps themselves (`CalibrationKey`:
        /// read on every body pass, so no digest); `refresh` compares the full stamp.
        var calibration: PhaseMappingProduct.CalibrationKey
    }

    private var key: Key {
        Key(run: appState.phaseMapping.lastRun, stale: appState.phaseMapping.isStale,
            x: appState.selectedScan.x, y: appState.selectedScan.y,
            scale: appState.acomScaleSemantics.invAngstromPerPixel,
            peakCount: appState.fitOverlays.storedPeaksAtSelection.count,
            calibration: PhaseMappingProduct.CalibrationKey(
                calibration: appState.calibrationSession.calibration, referenceOrigin: currentReferenceOrigin))
    }

    private var currentReferenceOrigin: (x: Float, y: Float) {
        let calibration = appState.calibrationSession.calibration
        return appState.descriptor.map {
            calibration.referenceOrigin(
                detectorQX: $0.qx, detectorQY: $0.qy,
                apertureCentre: (x: appState.aperture.centerX, y: appState.aperture.centerY)).point
        } ?? (x: 0, y: 0)
    }

    var body: some View {
        let fit = appState.fitOverlays
        let peaks = fit.storedPeaksAtSelection
        Color.clear
            .frame(width: box.width, height: box.height)
            .overlay {
                if let map = appState.phaseMapping.map,
                   !peaks.isEmpty, claims.count == peaks.count, claimedPeakCount == peaks.count {
                    PhaseClaimOverlay(
                        part: part,
                        peaks: peaks, claims: claims,
                        phaseNames: map.phaseNames, matrixPhaseIndex: map.matrixPhaseIndex,
                        probeRadius: appState.probeKernel?.probeRadius,
                        patternWidth: patternWidth, patternHeight: patternHeight, box: box)
                } else if part == .legend,
                          let message = displayedNote(patternShowsPosition: fit.patternShowsSelectedPosition,
                                                      hasPeaks: !peaks.isEmpty) {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.black.opacity(0.48), in: Capsule())
                        .padding(6)
                        .frame(width: box.width, height: box.height, alignment: .topTrailing)
                }
            }
            .allowsHitTesting(false)
            .task(id: key) { await refresh() }
    }

    private func displayedNote(patternShowsPosition: Bool, hasPeaks: Bool) -> String? {
        if !patternShowsPosition {
            return "Claimed disks: single scan position, current pattern only"
        }
        if let note { return note }
        return hasPeaks ? nil : "No detected disks at this position"
    }

    private func refresh() async {
        claims = []; claimedPeakCount = 0; note = nil
        let phaseMapping = appState.phaseMapping
        guard let map = phaseMapping.map, let run = phaseMapping.lastRun,
              let descriptor = appState.descriptor,
              let raw = appState.resultPresentation.braggVectors else { return }
        guard !phaseMapping.isStale else {
            note = "Phase list or settings changed since the map — run again"
            return
        }
        if let refusal = run.claimsRefusal(
            currentInvAngstromPerPixel: appState.acomScaleSemantics.invAngstromPerPixel,
            currentCalibration: PhaseMappingProduct.CalibrationStamp(
                calibration: appState.calibrationSession.calibration, referenceOrigin: currentReferenceOrigin)) {
            note = refusal
            return
        }
        let x = appState.selectedScan.x, y = appState.selectedScan.y
        guard x >= 0, y >= 0, x < map.width, y < map.height,
              raw.scanWidth == map.width, raw.scanHeight == map.height else { return }
        let scan = y * map.width + x
        guard appState.fitOverlays.storedPeaksAtSelection.count == raw.peaks[scan].count else { return }

        // The run's own library, kept by the product when it published: nothing
        // to rebuild when this layer is created again (toggle, room switch).
        guard let library = phaseMapping.lastLibrary,
              library.entries.count == run.libraryEntryCount else {
            note = "Reference library not kept for this map — run again"
            return
        }

        let calibrated = appState.calibratedBraggVectors(raw, descriptor: descriptor,
                                                         positions: [scan])
        let origin = calibrated.origin.point
        let matrixEntry: PhaseOrientationReference? =
            run.matrixEntryIndex >= 0 && run.matrixEntryIndex < library.entries.count
            ? library.entries[run.matrixEntryIndex] : nil
        let peaks = calibrated.vectors.peaks[scan]
        claims = PhaseVectorMatcher.claims(
            peaks: peaks, originX: origin.x, originY: origin.y,
            invAngstromPerPixel: run.invAngstromPerPixel, settings: run.matching,
            matrixEntry: matrixEntry, result: map.results[scan], library: library)
        claimedPeakCount = peaks.count
    }
}
