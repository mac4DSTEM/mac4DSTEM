import Foundation

/// Test-only interpretation of calibration hints encoded in training-dataset
/// filenames. This never touches app logic — it only decides what the QC
/// playthrough types into calibration fields that already exist in the UI,
/// and what it writes into the per-datacube log.
///
/// Rules (per the QC playthrough spec):
///  - Accelerating voltage: parsed from a "<number>kV" token; defaults to
///    200 kV when absent, matching References/training_dataset/metadata.md.
///  - Scan step ("ss<number>nm") is the only filename-derived value the test
///    ever types into the app: it directly names an r-space pixel size.
///  - Camera length ("cl-<number>mm") only *constrains* q-space pixel size
///    together with kV and instrument-specific detector constants this test
///    does not have, so it is recorded for the log but never injected as a
///    calibration value.
enum DatacubeFilenameCalibration {
    struct Hints {
        let acceleratingVoltageKV: Double
        let voltageSource: String
        let scanStepNM: Double?
        let cameraLengthMM: Double?
    }

    static func parse(fileName: String) -> Hints {
        let voltageToken = firstMatch(in: fileName, pattern: #"(\d+(?:p\d+)?)\s*kV"#)
        let scanStepToken = firstMatch(in: fileName, pattern: #"ss(\d+(?:p\d+)?)nm"#)
        let cameraLengthToken = firstMatch(in: fileName, pattern: #"cl-?(\d+(?:p\d+)?)mm"#)

        let scanStep = scanStepToken.flatMap(decimal)
        let cameraLength = cameraLengthToken.flatMap(decimal)

        if let voltageToken, let voltage = decimal(voltageToken) {
            return Hints(
                acceleratingVoltageKV: voltage,
                voltageSource: "filename token \"\(voltageToken)kV\" in \(fileName)",
                scanStepNM: scanStep,
                cameraLengthMM: cameraLength
            )
        }
        return Hints(
            acceleratingVoltageKV: 200,
            voltageSource: "default 200 kV (no kV token found in \(fileName); "
                + "matches References/training_dataset/metadata.md convention)",
            scanStepNM: scanStep,
            cameraLengthMM: cameraLength
        )
    }

    private static func decimal(_ token: String) -> Double? {
        Double(token.replacingOccurrences(of: "p", with: "."))
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let captured = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[captured])
    }
}
