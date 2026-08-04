//
//  acom-groundtruth/BraggTypes.swift
//  Role: minimal, field-identical stand-ins for `BraggPeak`/`BraggVectors`
//        (defined in mac4DSTEM/Core/Analysis/DiskDetection.swift), so this
//        harness can link OrientationMatcher.swift without pulling in the
//        842-line disk-detection pipeline and its own dependency chain
//        (FourDArray, ProbeKernel, calibration, ...) that this CLI never
//        exercises. OrientationMatcher.match(peaks:...) only reads
//        `.x`/`.y`/`.intensity`, and OrientationMatching.matchAll/
//        MetalACOMMatcher only need `BraggVectors` to type-check (this
//        harness never calls either) — both are reproduced verbatim below.
//        Not a copy of app logic, just the two struct declarations.
//

/// One detected Bragg reflection, in detector pixels (x = column, y = row) —
/// same layout as mac4DSTEM/Core/Analysis/DiskDetection.swift's `BraggPeak`.
nonisolated struct BraggPeak: Sendable {
    var x: Float
    var y: Float
    var intensity: Float
}

/// Same layout as DiskDetection.swift's `BraggVectors`; unused by this CLI
/// (it calls `OrientationMatcher.match` per pattern directly) but required
/// for OrientationMatcher.swift's full-scan `matchAll` declarations to
/// type-check.
nonisolated struct BraggVectors: Sendable {
    let scanWidth: Int
    let scanHeight: Int
    let peaks: [[BraggPeak]]
    let detectionProvenance: [String: String]

    init(
        scanWidth: Int, scanHeight: Int, peaks: [[BraggPeak]],
        detectionProvenance: [String: String] = [:]
    ) {
        self.scanWidth = scanWidth
        self.scanHeight = scanHeight
        self.peaks = peaks
        self.detectionProvenance = detectionProvenance
    }
}
