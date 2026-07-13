import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

let empty = ScientificSeriesGeometry.make(values: [], scale: .linear)
require(empty.points.isEmpty && empty.minimum == nil, "empty geometry")

let single = ScientificSeriesGeometry.make(values: [7], scale: .linear)
require(single.points == [ScientificSeriesPoint(index: 0, x: 0.5, y: 0.5, value: 7)],
        "single-value centering")

let linear = ScientificSeriesGeometry.make(values: [3, 5, 7], scale: .linear)
require(linear.points.map(\.x) == [0, 0.5, 1], "linear x mapping")
require(linear.points.map(\.y) == [0, 0.5, 1], "linear y mapping")
require(linear.nearestIndex(toUnitX: 0.74) == 1, "nearest lower selection")
require(linear.nearestIndex(toUnitX: 0.76) == 2, "nearest upper selection")

let gaps = ScientificSeriesGeometry.make(
    values: [1, .nan, 10, .infinity, -1, 100], scale: .logarithmic
)
require(gaps.segments.count == 3, "non-finite/log-invalid gaps")
require(gaps.points.map(\.index) == [0, 2, 5], "valid log indices")
require(gaps.points.map(\.y) == [0, 0.5, 1], "log10 scaling")
require(gaps.nearestIndex(toUnitX: 0.5) == 2, "selection skips gaps")

require(SessionResultPresentation.sampling(row: 0.25, column: 0.5, units: "A")
        == "sampling 0.25 × 0.5 A/px", "sampling label")
require(SessionResultPresentation.sampling(row: nil, column: 1, units: "A") == nil,
        "partial sampling omitted")
let provenance = SessionResultPresentation.provenance([
    "source_product": "ptychography_object_phase", "iterations": "8",
    "final_error": "0.00001234", "step_size": "0.5", "fix_probe": "true"
])
require(provenance == "iters 8 · error 1.23e-05 · step 0.5", "priority provenance")

let kde = SessionControlRehydration.parse(kind: "parallax_subpixel_bf", provenance: [
    "upsample_factor": "2.5", "kde_sigma_px": "0.125",
    "interpolation": "lanczos_2", "position_iterations": "4",
    "sinc_lowpass": "true"
])
require(kde.kdeUpsampleFactor == 2.5 && kde.kdeSigmaPixels == 0.125,
        "KDE numeric controls")
require(kde.kdeLanczosOrder == 2 && kde.positionIterations == 4 && kde.kdeLowpass == true,
        "KDE discrete controls")

let correction = SessionControlRehydration.parse(kind: "ignored", provenance: [
    "source_product": "parallax_corrected_phase", "q_lowpass_inv_a": "off",
    "q_highpass_inv_a": "0.02"
])
require(correction.qLowpassInvAngstrom == 0 && correction.qHighpassInvAngstrom == 0.02,
        "phase filters")

let depth = SessionControlRehydration.parse(kind: "parallax_depth", provenance: [
    "depth_angstrom": "-64.5", "full_fit": "false",
    "information_limit_inv_a": "0.12", "information_power": "1.5"
])
require(depth.depthAngstrom == -64.5 && depth.depthUseFullFit == false,
        "depth plane/CTF")
require(depth.depthInformationLimit == 0.12 && depth.depthInformationPower == 1.5,
        "depth information controls")

let ptycho = SessionControlRehydration.parse(kind: "ptychography_object_amplitude", provenance: [
    "engine": "singleslice", "method": "gradient-descent", "iterations": "12",
    "step_size": "0.25", "normalization_minimum": "0.75", "fix_probe": "yes"
])
require(ptycho.ptychographyIterations == 12 && ptycho.ptychographyStepSize == 0.25,
        "ptychography iterations/step")
require(ptycho.ptychographyNormalizationMinimum == 0.75
        && ptycho.ptychographyFixProbe == true, "ptychography normalization/probe")

let malformed = SessionControlRehydration.parse(kind: "parallax_subpixel_bf", provenance: [
    "upsample_factor": "0.5", "kde_sigma_px": "nan", "interpolation": "lanczos_99",
    "position_iterations": "-1", "sinc_lowpass": "maybe"
])
require(malformed.isEmpty, "malformed/out-of-range provenance rejected")
require(SessionControlRehydration.parse(kind: "legacy_virtual", provenance: [:]).isEmpty,
        "legacy provenance ignored")
require(SessionControlRehydration.parse(kind: "ptychography_object_phase", provenance: [
    "engine": "unsupported", "iterations": "8"
]).isEmpty, "unsupported engine rejected")

print("result presentation: geometry, metadata, and rehydration cases passed")
