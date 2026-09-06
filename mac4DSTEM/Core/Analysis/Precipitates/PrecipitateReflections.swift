//
//  PrecipitateReflections.swift
//  Role: Step 1 of the precipitate chain (docs/ai-ml/precipitates.md §2) —
//        propose the scan's MAX-pattern local maxima outside the beam and
//        classify each as on- or off- the matrix lattice. Nothing here picks
//        "the precipitate reflections" on its own: both classes are returned
//        (`onMatrixLattice`) so the UI, and the owner, can see the reasoning
//        before anything downstream (virtual imaging, segmentation) runs.
//
//  Coordinates: (row, col) into `maxPattern`, matching py4DSTEM's (qx, qy)
//  detector convention already used elsewhere in the app
//  (docs/architecture.md; docs/ai-ml/precipitates.md §5).
//

import Foundation

package nonisolated enum PrecipitateReflections {

    /// A local maximum of the scan's MAX diffraction pattern.
    package nonisolated struct Candidate: Sendable, Equatable, Identifiable {
        package let id: Int
        package let row: Int
        package let col: Int
        package let intensity: Float
        package let radiusFromBeam: Float
        /// True when a matrix basis was supplied and this position sits
        /// within `Settings.latticeTolerance` of some integer combination
        /// h·g1 + k·g2. The precipitate reflections are the ones for which
        /// this is false.
        package let onMatrixLattice: Bool

        /// The inspector row's identity, in its OWN namespace.
        ///
        /// The reflection list and the object list are two `ForEach`es inside
        /// one `Section` of the same grouped `Form`, and a SwiftUI container
        /// identifies its rows by the id value, not per-`ForEach`. Keyed on
        /// the bare `Int` id the two overlapped — candidates 0…23, objects
        /// 1…44 — and the objects table drew the reflection rows for 1…23,
        /// hiding objects #1…#23 (owner's drive 2026-09-06,
        /// `drive-precipitates` defect 6; `fix-b/gateD-P6.md`).
        package nonisolated var rowIdentity: String { "precipitate.reflection.\(id)" }

        // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
        package nonisolated init(
            id: Int, row: Int, col: Int, intensity: Float,
            radiusFromBeam: Float, onMatrixLattice: Bool
        ) {
            self.id = id
            self.row = row
            self.col = col
            self.intensity = intensity
            self.radiusFromBeam = radiusFromBeam
            self.onMatrixLattice = onMatrixLattice
        }
    }

    package nonisolated struct Settings: Sendable, Equatable {
        /// Radius (detector px) around the beam centre excluded from the
        /// candidate search.
        package var beamExclusionRadius: Float = 3
        /// Minimum intensity, as a fraction of the brightest OFF-BEAM
        /// maximum, for a maximum to be reported at all.
        package var relativeThreshold: Float = 0.02
        /// Maximum distance (detector px) from an integer lattice combination
        /// for a position to count as "on the matrix lattice".
        package var latticeTolerance: Float = 1.5
        /// Cap on the number of returned candidates (brightest kept).
        package var maximumCount: Int = 24

        // Bare init (not a full memberwise init, unlike `Candidate`): callers
        // start from the defaults above and mutate the fields they need,
        // matching the API contract this type was specified against.
        package nonisolated init() {}
    }

    /// The one-line summary of a proposal run, in the app's voice.
    ///
    /// `offLatticeCount` is nil when **no matrix basis was available**, in
    /// which case `find` tagged every candidate `onMatrixLattice == false`
    /// without testing anything. Reporting "N off the matrix lattice" there
    /// claims a filter that never ran: the drive read
    /// "24 reflections proposed, 24 off the matrix lattice" on a run made with
    /// `matrixBasis: nil`, while ten of the 24 sat on the matrix ring at
    /// 16.6–19.8 px (owner's drive 2026-09-06, `drive-precipitates` step 3b
    /// and defect 3). v1 always passes nil — §2 step 1's two-clicked-basis
    /// input is not built — so this is the string the user actually sees.
    package nonisolated static func proposalSummary(count: Int, offLatticeCount: Int?) -> String {
        guard let offLatticeCount else {
            return "\(count) reflections proposed · no lattice basis: "
                + "all \(count) listed, none tested against the matrix lattice"
        }
        return "\(count) reflections proposed, \(offLatticeCount) off the matrix lattice"
    }

    /// Integer combination search bound for the lattice test: h, k in
    /// [-12, 12] reaches a 25x25 grid of candidate lattice points, far beyond
    /// any basis vector length seen near the beam in practice
    /// (docs/ai-ml/precipitates.md §2 step 1: matrix disks at ~18 px on a
    /// 64-px detector).
    private static let latticeSearchBound = 12

    /// Local maxima (3x3 neighbourhood, ties kept) of `maxPattern` outside
    /// the beam exclusion radius, above `relativeThreshold` times the
    /// brightest surviving off-beam maximum, sorted by intensity descending
    /// and capped at `maximumCount`. When `matrixBasis` is supplied, each
    /// candidate is tagged `onMatrixLattice` by nearest-integer-combination
    /// search; without a basis every candidate is tagged `false`.
    package nonisolated static func find(
        maxPattern: FloatImage,
        beamCentre: (x: Float, y: Float),
        matrixBasis: (g1: (x: Float, y: Float), g2: (x: Float, y: Float))?,
        settings: Settings
    ) -> [Candidate] {
        let width = maxPattern.width, height = maxPattern.height
        guard width >= 3, height >= 3 else { return [] }
        let pixels = maxPattern.pixels
        let exclusion2 = settings.beamExclusionRadius * settings.beamExclusionRadius

        struct Raw { let row: Int; let col: Int; let intensity: Float; let radius: Float }
        var maxima: [Raw] = []
        for row in 1..<(height - 1) {
            for col in 1..<(width - 1) {
                let i = row * width + col
                let v = pixels[i]
                guard v.isFinite else { continue }
                var isMaximum = true
                neighbourLoop: for dy in -1...1 {
                    for dx in -1...1 where !(dx == 0 && dy == 0) {
                        if pixels[i + dy * width + dx] > v {
                            isMaximum = false
                            break neighbourLoop
                        }
                    }
                }
                guard isMaximum else { continue }
                let dx = Float(col) - beamCentre.x
                let dy = Float(row) - beamCentre.y
                let r2 = dx * dx + dy * dy
                guard r2 > exclusion2 else { continue }
                maxima.append(Raw(row: row, col: col, intensity: v, radius: r2.squareRoot()))
            }
        }
        guard let brightest = maxima.map(\.intensity).max(), brightest > 0 else { return [] }
        let threshold = settings.relativeThreshold * brightest
        var accepted = maxima.filter { $0.intensity >= threshold }
        accepted.sort { $0.intensity > $1.intensity }
        if accepted.count > settings.maximumCount {
            accepted.removeLast(accepted.count - settings.maximumCount)
        }

        func onLattice(row: Int, col: Int) -> Bool {
            guard let basis = matrixBasis else { return false }
            let dx = Float(col) - beamCentre.x
            let dy = Float(row) - beamCentre.y
            var closest = Float.greatestFiniteMagnitude
            for h in -latticeSearchBound...latticeSearchBound {
                for k in -latticeSearchBound...latticeSearchBound {
                    let px = Float(h) * basis.g1.x + Float(k) * basis.g2.x
                    let py = Float(h) * basis.g1.y + Float(k) * basis.g2.y
                    let ex = px - dx, ey = py - dy
                    let distance = (ex * ex + ey * ey).squareRoot()
                    if distance < closest { closest = distance }
                }
            }
            return closest <= settings.latticeTolerance
        }

        return accepted.enumerated().map { index, raw in
            Candidate(
                id: index, row: raw.row, col: raw.col, intensity: raw.intensity,
                radiusFromBeam: raw.radius,
                onMatrixLattice: onLattice(row: raw.row, col: raw.col)
            )
        }
    }
}
