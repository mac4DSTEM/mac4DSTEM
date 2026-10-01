import Foundation

package nonisolated enum ScientificSeriesScale: Sendable {
    case linear
    case logarithmic
}

package nonisolated struct ScientificSeriesPoint: Equatable, Sendable {
    package let index: Int
    package let x: Double
    package let y: Double
    package let value: Double

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(index: Int, x: Double, y: Double, value: Double) {
        self.index = index
        self.x = x
        self.y = y
        self.value = value
    }
}

/// Pure, UI-independent plot geometry. Non-finite (and non-positive log)
/// samples split the line instead of poisoning its range.
package nonisolated struct ScientificSeriesGeometry: Equatable, Sendable {
    package let segments: [[ScientificSeriesPoint]]
    package let minimum: Double?
    package let maximum: Double?

    package var points: [ScientificSeriesPoint] { segments.flatMap { $0 } }

    package static func make(values: [Float], scale: ScientificSeriesScale) -> Self {
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

    package func nearestIndex(toUnitX x: Double) -> Int? {
        points.min { abs($0.x - x) < abs($1.x - x) }?.index
    }

    package func point(at index: Int?) -> ScientificSeriesPoint? {
        guard let index else { return nil }
        return points.first { $0.index == index }
    }

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(segments: [[ScientificSeriesPoint]], minimum: Double?, maximum: Double?) {
        self.segments = segments
        self.minimum = minimum
        self.maximum = maximum
    }
}

/// Compact labels for arbitrary-shape persisted scientific results.
package nonisolated enum SessionResultPresentation {
    package static func sampling(row: Double?, column: Double?, units: String?) -> String? {
        guard let row, let column, row.isFinite, column.isFinite,
              row > 0, column > 0 else { return nil }
        let suffix = (units?.isEmpty == false ? CalibrationUnitConversion.displayLabel(units) : "px") + "/px"
        return "sampling \(number(row)) × \(number(column)) \(suffix)"
    }

    package static func provenance(_ values: [String: String], limit: Int = 3) -> String? {
        let order = [
            "depth_angstrom", "upsample_factor", "interpolation", "position_iterations",
            "method", "iterations", "final_error", "step_size",
            "fix_probe", "full_fit",
            "information_limit_inv_a", "q_lowpass_inv_a", "q_highpass_inv_a"
        ]
        let labels: [String: String] = [
            "depth_angstrom": "depth", "upsample_factor": "upsample",
            "interpolation": "kernel", "position_iterations": "position iters",
            "method": "method", "iterations": "iters", "final_error": "error",
            "step_size": "step",
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
            if key == "method" {
                if raw == "gradient-descent" { value = "GD" }
                if raw == "difference-map_alternating-projections" { value = "difference map (no longer offered)" }
            }
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
package nonisolated struct SessionControlRehydration: Equatable, Sendable {
    package var kdeUpsampleFactor: Double?
    package var kdeSigmaPixels: Double?
    package var kdeLanczosOrder: Int?
    package var positionIterations: Int?
    package var kdeLowpass: Bool?
    package var qLowpassInvAngstrom: Double?
    package var qHighpassInvAngstrom: Double?
    package var depthAngstrom: Double?
    package var depthUseFullFit: Bool?
    package var depthInformationLimit: Double?
    package var depthInformationPower: Double?
    package var ptychographyIterations: Int?
    /// Set when the record names the difference map (DM/AP), removed from the app (owner, 2026-10-01): the other controls
    /// of such a record belong to that algorithm, so nothing else is parsed from it. A gradient-descent record has no method
    /// control any more — gradient descent is the only method.
    package var ptychographyRetiredMethod: String?
    package var ptychographyStepSize: Float?
    package var ptychographyNormalizationMinimum: Float?
    package var ptychographyFixProbe: Bool?
    package var ptychographyConstrainObjectAmplitude: Bool?
    package var ptychographyPurePhaseObject: Bool?
    package var ptychographyFixProbeCenterOfMass: Bool?
    package var ptychographyConstrainProbeAmplitude: Bool?
    package var ptychographyProbeAmplitudeRadius: Float?
    package var ptychographyProbeAmplitudeWidth: Float?
    /// The probe the run started from (defocus, C12a/b, higher-order terms). A single-slice record without the keys was
    /// made in focus, so absent keys parse as the zero probe; present-but-malformed keys parse as nil (nothing applied).
    package var ptychographyProbe: RecordedPtychographyProbe?

    package var appliedSettingNames: [String] {
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
        if ptychographyRetiredMethod != nil { names.append("difference map (no longer offered)") }
        if ptychographyStepSize != nil { names.append("step") }
        if ptychographyNormalizationMinimum != nil { names.append("normalization") }
        if ptychographyFixProbe != nil { names.append("probe update") }
        if ptychographyConstrainObjectAmplitude != nil { names.append("object transmission") }
        if ptychographyPurePhaseObject != nil { names.append("pure-phase object") }
        if ptychographyFixProbeCenterOfMass != nil { names.append("probe centering") }
        if ptychographyConstrainProbeAmplitude != nil { names.append("probe support") }
        if ptychographyProbeAmplitudeRadius != nil { names.append("support radius") }
        if ptychographyProbeAmplitudeWidth != nil { names.append("support width") }
        if ptychographyProbe != nil { names.append("probe aberrations") }
        return names
    }

    package var isEmpty: Bool { appliedSettingNames.isEmpty }
    package var summary: String { appliedSettingNames.joined(separator: ", ") }

    package static func parse(kind: String, provenance p: [String: String]) -> Self {
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
        case "ptychography_object_phase", "ptychography_object_amplitude",
             "ptychography_probe_phase", "ptychography_probe_amplitude":
            guard p["engine"] == nil || p["engine"] == "singleslice" else {
                return result
            }
            switch p["method"] {
            case nil, "gradient-descent":
                break
            case "difference-map_alternating-projections":
                result.ptychographyRetiredMethod = "difference-map_alternating-projections"
                return result
            default:
                return result
            }
            result.ptychographyIterations = boundedInt(p["iterations"], range: 1...100_000)
            result.ptychographyStepSize = positiveFloat(p["step_size"])
            result.ptychographyNormalizationMinimum = positiveFloat(
                p["normalization_minimum"]
            )
            result.ptychographyFixProbe = boolean(p["fix_probe"])
            result.ptychographyConstrainObjectAmplitude = boolean(
                p["constrain_object_amplitude"]
            )
            result.ptychographyPurePhaseObject = boolean(p["pure_phase_object"])
            result.ptychographyFixProbeCenterOfMass = boolean(p["fix_probe_com"])
            result.ptychographyConstrainProbeAmplitude = boolean(
                p["constrain_probe_amplitude"]
            )
            result.ptychographyProbeAmplitudeRadius = boundedFloat(
                p["probe_amplitude_radius"], range: 0...0.5
            )
            result.ptychographyProbeAmplitudeWidth = boundedFloat(
                p["probe_amplitude_width"], range: Float.leastNonzeroMagnitude...0.5
            )
            result.ptychographyProbe = RecordedPtychographyProbe(provenance: p)
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

    private static func boundedFloat(
        _ text: String?, range: ClosedRange<Float>
    ) -> Float? {
        guard let value = finiteDouble(text), value >= Double(range.lowerBound),
              value <= Double(range.upperBound) else { return nil }
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

/// The probe a single-slice run started from, as provenance keys (export, sidecar) and back (saved-control rehydration).
/// Plain numbers on purpose: this file is compiled alone into `tools/result-presentation-test`, so it cannot name the Analysis
/// type; `PtychographyProbeAberrations` converts at the app seam (`PtychographySettings`, `ResultExport`).
package nonisolated struct RecordedPtychographyProbe: Equatable, Sendable {
    package struct Term: Equatable, Sendable {
        package var radialOrder: Int
        package var angularOrder: Int
        package var component: Int
        package var coefficientAngstrom: Double

        package init(radialOrder: Int, angularOrder: Int, component: Int, coefficientAngstrom: Double) {
            self.radialOrder = radialOrder
            self.angularOrder = angularOrder
            self.component = component
            self.coefficientAngstrom = coefficientAngstrom
        }
    }

    package static let keys = [
        "probe_defocus_angstrom", "probe_c12a_angstrom", "probe_c12b_angstrom", "probe_higher_order_terms",
    ]

    package var defocusAngstrom: Double
    package var c12aAngstrom: Double
    package var c12bAngstrom: Double
    package var higherOrder: [Term]

    package init(defocusAngstrom: Double = 0, c12aAngstrom: Double = 0, c12bAngstrom: Double = 0, higherOrder: [Term] = []) {
        self.defocusAngstrom = defocusAngstrom
        self.c12aAngstrom = c12aAngstrom
        self.c12bAngstrom = c12bAngstrom
        self.higherOrder = higherOrder
    }

    /// Always written (a zero probe says "in focus" in so many words). Higher-order terms as "m:n:c:coefficient;..." and only
    /// when there are some.
    package var provenanceEntries: [String: String] {
        var entries = [
            "probe_defocus_angstrom": String(defocusAngstrom),
            "probe_c12a_angstrom": String(c12aAngstrom),
            "probe_c12b_angstrom": String(c12bAngstrom),
        ]
        if !higherOrder.isEmpty {
            entries["probe_higher_order_terms"] = higherOrder.map {
                "\($0.radialOrder):\($0.angularOrder):\($0.component):\($0.coefficientAngstrom)"
            }.joined(separator: ";")
        }
        return entries
    }

    /// nil when a key is present but malformed; the zero probe when none of the keys exist (a record from before the probe
    /// was recorded was made in focus).
    package init?(provenance p: [String: String]) {
        if Self.keys.allSatisfy({ p[$0] == nil }) {
            self.init()
            return
        }
        func number(_ key: String) -> Double? {
            guard let text = p[key] else { return 0 }
            guard let value = Double(text), value.isFinite else { return nil }
            return value
        }
        guard let defocus = number("probe_defocus_angstrom"), let c12a = number("probe_c12a_angstrom"),
              let c12b = number("probe_c12b_angstrom") else { return nil }
        var terms = [Term]()
        if let text = p["probe_higher_order_terms"] {
            for item in text.split(separator: ";") {
                let fields = item.split(separator: ":")
                guard fields.count == 4, let m = Int(fields[0]), let n = Int(fields[1]), let c = Int(fields[2]),
                      let value = Double(fields[3]), value.isFinite, m >= 1, n >= 0,
                      c == 0 || (c == 1 && n > 0) else { return nil }
                terms.append(Term(radialOrder: m, angularOrder: n, component: c, coefficientAngstrom: value))
            }
        }
        self.init(defocusAngstrom: defocus, c12aAngstrom: c12a, c12bAngstrom: c12b, higherOrder: terms)
    }
}
