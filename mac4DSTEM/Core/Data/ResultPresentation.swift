import Foundation

nonisolated enum ScientificSeriesScale: Sendable {
    case linear
    case logarithmic
}

nonisolated struct ScientificSeriesPoint: Equatable, Sendable {
    let index: Int
    let x: Double
    let y: Double
    let value: Double
}

/// Pure, UI-independent plot geometry. Non-finite (and non-positive log)
/// samples split the line instead of poisoning its range.
nonisolated struct ScientificSeriesGeometry: Equatable, Sendable {
    let segments: [[ScientificSeriesPoint]]
    let minimum: Double?
    let maximum: Double?

    var points: [ScientificSeriesPoint] { segments.flatMap { $0 } }

    static func make(values: [Float], scale: ScientificSeriesScale) -> Self {
        let transformed: [Double?] = values.map { value in
            let value = Double(value)
            guard value.isFinite else { return nil }
            switch scale {
            case .linear: return value
            case .logarithmic: return value > 0 ? log10(value) : nil
            }
        }
        let finite = transformed.compactMap { $0 }
        guard let minimum = finite.min(), let maximum = finite.max() else {
            return Self(segments: [], minimum: nil, maximum: nil)
        }
        let span = maximum - minimum
        var segments: [[ScientificSeriesPoint]] = []
        var current: [ScientificSeriesPoint] = []
        for (index, transformedValue) in transformed.enumerated() {
            guard let transformedValue else {
                if !current.isEmpty { segments.append(current); current = [] }
                continue
            }
            let x = values.count == 1 ? 0.5 : Double(index) / Double(values.count - 1)
            let y = span > 0 ? (transformedValue - minimum) / span : 0.5
            current.append(ScientificSeriesPoint(
                index: index, x: x, y: y, value: Double(values[index])
            ))
        }
        if !current.isEmpty { segments.append(current) }
        return Self(segments: segments, minimum: minimum, maximum: maximum)
    }

    func nearestIndex(toUnitX x: Double) -> Int? {
        points.min { abs($0.x - x) < abs($1.x - x) }?.index
    }

    func point(at index: Int?) -> ScientificSeriesPoint? {
        guard let index else { return nil }
        return points.first { $0.index == index }
    }
}

/// Compact labels for arbitrary-shape persisted scientific results.
nonisolated enum SessionResultPresentation {
    static func sampling(row: Double?, column: Double?, units: String?) -> String? {
        guard let row, let column, row.isFinite, column.isFinite,
              row > 0, column > 0 else { return nil }
        let suffix = (units?.isEmpty == false ? units! : "px") + "/px"
        return "sampling \(number(row)) × \(number(column)) \(suffix)"
    }

    static func provenance(_ values: [String: String], limit: Int = 3) -> String? {
        let order = [
            "depth_angstrom", "upsample_factor", "interpolation", "position_iterations",
            "iterations", "final_error", "step_size", "fix_probe", "full_fit",
            "information_limit_inv_a", "q_lowpass_inv_a", "q_highpass_inv_a"
        ]
        let labels: [String: String] = [
            "depth_angstrom": "depth", "upsample_factor": "upsample",
            "interpolation": "kernel", "position_iterations": "position iters",
            "iterations": "iters", "final_error": "error", "step_size": "step",
            "fix_probe": "fixed probe", "full_fit": "full CTF",
            "information_limit_inv_a": "info limit", "q_lowpass_inv_a": "low-pass",
            "q_highpass_inv_a": "high-pass"
        ]
        var parts: [String] = []
        for key in order {
            guard parts.count < max(0, limit), let raw = values[key], !raw.isEmpty else { continue }
            var value = raw
            if let number = Double(raw), number.isFinite { value = self.number(number) }
            if key == "depth_angstrom" { value += " Å" }
            if ["information_limit_inv_a", "q_lowpass_inv_a", "q_highpass_inv_a"].contains(key),
               raw != "off" { value += " Å⁻¹" }
            if raw == "true" { value = "yes" }
            if raw == "false" { value = "no" }
            parts.append("\(labels[key] ?? key) \(value)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func number(_ value: Double) -> String {
        let magnitude = abs(value)
        if magnitude != 0, magnitude < 0.001 { return String(format: "%.2e", value) }
        if magnitude >= 1_000 { return String(format: "%.3g", value) }
        return String(format: "%.4g", value)
    }
}

/// A validated, typed subset of schema-v4 provenance that can safely be
/// copied back into controls. It intentionally contains no reconstructed data.
nonisolated struct SessionControlRehydration: Equatable, Sendable {
    var kdeUpsampleFactor: Double?
    var kdeSigmaPixels: Double?
    var kdeLanczosOrder: Int?
    var positionIterations: Int?
    var kdeLowpass: Bool?
    var qLowpassInvAngstrom: Double?
    var qHighpassInvAngstrom: Double?
    var depthAngstrom: Double?
    var depthUseFullFit: Bool?
    var depthInformationLimit: Double?
    var depthInformationPower: Double?
    var ptychographyIterations: Int?
    var ptychographyStepSize: Float?
    var ptychographyNormalizationMinimum: Float?
    var ptychographyFixProbe: Bool?

    var appliedSettingNames: [String] {
        var names: [String] = []
        if kdeUpsampleFactor != nil { names.append("KDE factor") }
        if kdeSigmaPixels != nil { names.append("KDE sigma") }
        if kdeLanczosOrder != nil { names.append("kernel") }
        if positionIterations != nil { names.append("position iterations") }
        if kdeLowpass != nil { names.append("sinc low-pass") }
        if qLowpassInvAngstrom != nil { names.append("phase low-pass") }
        if qHighpassInvAngstrom != nil { names.append("phase high-pass") }
        if depthAngstrom != nil { names.append("depth plane") }
        if depthUseFullFit != nil { names.append("depth CTF") }
        if depthInformationLimit != nil { names.append("information limit") }
        if depthInformationPower != nil { names.append("information power") }
        if ptychographyIterations != nil { names.append("ptychography iterations") }
        if ptychographyStepSize != nil { names.append("step") }
        if ptychographyNormalizationMinimum != nil { names.append("normalization") }
        if ptychographyFixProbe != nil { names.append("probe update") }
        return names
    }

    var isEmpty: Bool { appliedSettingNames.isEmpty }
    var summary: String { appliedSettingNames.joined(separator: ", ") }

    static func parse(kind: String, provenance p: [String: String]) -> Self {
        var result = Self()
        let product = p["source_product"] ?? kind
        switch product {
        case "parallax_subpixel_bf":
            result.kdeUpsampleFactor = positiveDouble(p["upsample_factor"], minimum: 1)
            result.kdeSigmaPixels = nonnegativeDouble(p["kde_sigma_px"])
            if p["interpolation"] == "bilinear" {
                result.kdeLanczosOrder = 0
            } else if let text = p["interpolation"], text.hasPrefix("lanczos_"),
                      let order = Int(text.dropFirst("lanczos_".count)), (1...8).contains(order) {
                result.kdeLanczosOrder = order
            }
            result.positionIterations = boundedInt(p["position_iterations"], range: 0...10_000)
            result.kdeLowpass = boolean(p["sinc_lowpass"])
        case "parallax_corrected_phase":
            result.qLowpassInvAngstrom = filterValue(p["q_lowpass_inv_a"])
            result.qHighpassInvAngstrom = filterValue(p["q_highpass_inv_a"])
        case "parallax_depth":
            result.depthAngstrom = finiteDouble(p["depth_angstrom"])
            result.depthUseFullFit = boolean(p["full_fit"])
            result.depthInformationLimit = filterValue(p["information_limit_inv_a"])
            result.depthInformationPower = positiveDouble(p["information_power"])
        case "ptychography_object_phase", "ptychography_object_amplitude":
            guard p["engine"] == nil || p["engine"] == "singleslice",
                  p["method"] == nil || p["method"] == "gradient-descent" else {
                return result
            }
            result.ptychographyIterations = boundedInt(p["iterations"], range: 1...100_000)
            result.ptychographyStepSize = positiveFloat(p["step_size"])
            result.ptychographyNormalizationMinimum = positiveFloat(
                p["normalization_minimum"]
            )
            result.ptychographyFixProbe = boolean(p["fix_probe"])
        default:
            break
        }
        return result
    }

    private init() {}

    private static func finiteDouble(_ text: String?) -> Double? {
        guard let text, let value = Double(text), value.isFinite else { return nil }
        return value
    }

    private static func positiveDouble(_ text: String?, minimum: Double = 0) -> Double? {
        guard let value = finiteDouble(text), value > 0, value >= minimum else { return nil }
        return value
    }

    private static func nonnegativeDouble(_ text: String?) -> Double? {
        guard let value = finiteDouble(text), value >= 0 else { return nil }
        return value
    }

    private static func positiveFloat(_ text: String?) -> Float? {
        guard let value = finiteDouble(text), value > 0, value <= Double(Float.greatestFiniteMagnitude)
        else { return nil }
        return Float(value)
    }

    private static func boundedInt(_ text: String?, range: ClosedRange<Int>) -> Int? {
        guard let text, let value = Int(text), range.contains(value) else { return nil }
        return value
    }

    private static func boolean(_ text: String?) -> Bool? {
        switch text?.lowercased() {
        case "true", "1", "yes": return true
        case "false", "0", "no": return false
        default: return nil
        }
    }

    /// "off" is the UI's explicit disabled value, represented by zero.
    private static func filterValue(_ text: String?) -> Double? {
        if text?.lowercased() == "off" { return 0 }
        return nonnegativeDouble(text)
    }
}
