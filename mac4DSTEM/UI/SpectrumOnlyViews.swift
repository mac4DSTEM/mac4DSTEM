import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

// The views of a window that holds only a spectrum image, around the Spectroscopy room (`UI/Spectroscopy/`): what
// its other rooms and tabs say, and the Info tab's section. The room's own views are lane V's, wired in by
// `SpectroscopyRoomHost` / `SpectroscopyInspectorHost` (v5.0 WP2 R2).

/// The Settings tab in a window that holds only a spectrum image: the
/// Spectroscopy room's step, or one line saying there is nothing to set — the
/// 4D rooms' settings (and Results', which are about 4D products) do not apply.
enum SpectrumOnlySettings: Equatable {
    case step
    case note(String)

    static func content(for area: WorkspaceArea) -> SpectrumOnlySettings {
        area == .spectroscopy
            ? .step
            : .note("Nothing to set here for a spectrum image yet.")
    }
}

struct SpectrumOnlySettingsTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutPolicy.inspectorSectionSpacing) {
                switch SpectrumOnlySettings.content(for: appState.navigation.workspaceArea) {
                case .step: WorkspaceSettings()
                case .note(let text):
                    InspectorNote(text).accessibilityIdentifier("inspector.spectrumOnly.note")
                }
            }
            .padding()
        }
        .environment(\.inspectorScope, "settings")
    }
}

/// A 4D room in a window that holds only a spectrum image. The sidebar
/// disables these rooms and `selectWorkspace` declines them, so this is the
/// backstop, not a destination.
struct FourDRoomUnavailable: View {
    var body: some View {
        ContentUnavailableView(
            "No 4D-STEM scan in this window",
            systemImage: "square.stack.3d.up.slash",
            description: Text("This window holds a spectrum image only.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("workspace.noFourDCube")
    }
}

/// Results in a spectrum-only window, until quantification (WP3) produces any.
struct SpectrumOnlyResultsPlaceholder: View {
    var body: some View {
        ContentUnavailableView(
            "No Results Yet",
            systemImage: WorkspaceArea.results.systemImage,
            description: Text("Quantified regions of this spectrum image will appear here.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("results.spectrumOnly.empty")
    }
}

/// The Info tab for a spectrum image: what the file says it is, as stored.
struct SpectrumImageInfoSection: View {
    let metadata: SpectrumImageMetadata

    var body: some View {
        InspectorSection("Spectrum image") {
            InspectorValueRow("File", metadata.fileName)
            InspectorValueRow("Scan", "\(metadata.scanWidth) × \(metadata.scanHeight) px", mono: true)
            if let size = metadata.scanPixelSize, let unit = metadata.scanPixelUnit {
                InspectorValueRow("Pixel size", "\(size.formatted(.number.precision(.significantDigits(1...4)))) \(unit)", mono: true)
            }
            InspectorValueRow("Channels", "\(metadata.channelCount)", mono: true)
            InspectorValueRow("Energy axis", SpectroscopyPlaceholderFormat.energyAxis(metadata), mono: true)
            InspectorValueRow("Dispersion", SpectroscopyPlaceholderFormat.dispersion(metadata), mono: true)
            InspectorValueRow("Offset", SpectroscopyPlaceholderFormat.offset(metadata), mono: true)
            if let f = metadata.frames { InspectorValueRow("Frames", "\(f)", mono: true) }
            if let i = metadata.instrument { InspectorValueRow("Instrument", i) }
            if let b = metadata.beamEnergyKeV { InspectorValueRow("Beam", "\(b.formatted()) keV", mono: true) }
            if let stage = SpectroscopyPlaceholderFormat.stage(metadata) { InspectorValueRow("Stage", stage, mono: true) }
            ForEach(Array(metadata.detectors.enumerated()), id: \.offset) { _, d in
                InspectorValueRow(d.name, SpectroscopyPlaceholderFormat.detector(d), mono: true)
            }
            // No live-time row: the reader records the segments' LiveTime/RealTime as read, semantics unverified (cumulative in
            // one file, per frame in another; 4,7 s on a 43-frame SI is not the acquisition's live time). `liveTime(_:)` waits for
            // the reader change the sheet's row 4a names.
            if let note = metadata.registrationNote { InspectorNote(note) }
        }
    }
}

enum SpectroscopyPlaceholderFormat {
    /// A spectrum image beside a 4D cube is not registered to its scan: the
    /// registration record (M2, ADR 053 item 4) comes with WP3, and until then
    /// no pixel of one may be read as a pixel of the other.
    static func registrationNote(hasFourDCube: Bool) -> String? {
        hasFourDCube ? "Not registered to the 4D scan: the registration record comes with WP3." : nil
    }

    /// "az 45° · el 18° · 0.7 sr (as stored)": only what the file wrote.
    static func detector(_ d: SpectrumDetectorSegment) -> String {
        [d.azimuthDegrees.map { String(format: "az %.0f°", $0) }, d.elevationDegrees.map { String(format: "el %.0f°", $0) },
         d.solidAngle.map { "\($0.formatted()) sr" }].compactMap { $0 }.joined(separator: " · ")
    }

    /// "64 × 64 px · 2048 channels · 0–20.48 keV".
    static func summary(_ m: SpectrumImageMetadata) -> String {
        "\(m.scanWidth) × \(m.scanHeight) px · \(m.channelCount) channels · \(energyAxis(m))"
    }

    /// The axis as the file states it, first channel to the end of the last.
    static func energyAxis(_ m: SpectrumImageMetadata) -> String {
        let start = m.energyOffsetEV / 1000
        let end = (m.energyOffsetEV + Double(m.channelCount) * m.energyDispersionEV) / 1000
        return "\(start.formatted(.number.precision(.fractionLength(0...3))))–"
            + "\(end.formatted(.number.precision(.fractionLength(0...3)))) keV"
    }

    /// A number in the person's locale with a narrow no-break space for the thousands (as the results table groups counts),
    /// a true minus, and no digits past `fraction`.
    static func number(_ v: Double, fraction: ClosedRange<Int>, locale: Locale) -> String {
        let body = ResultFormat.grouped(abs(v), fraction: fraction, locale: locale)
        let isZero = ResultFormat.grouped(0, fraction: fraction, locale: locale) == body
        return v < 0 && !isZero ? "\u{2212}" + body : body
    }

    /// "20 eV/ch": the file's dispersion.
    static func dispersion(_ m: SpectrumImageMetadata, locale: Locale = .current) -> String {
        number(m.energyDispersionEV, fraction: 0...3, locale: locale) + " eV/ch"
    }

    /// "\u{2212}1 932 eV": the file's offset (energy of the first channel).
    static func offset(_ m: SpectrumImageMetadata, locale: Locale = .current) -> String {
        number(m.energyOffsetEV, fraction: 0...2, locale: locale) + " eV"
    }

    /// "\u{03B1} 7,3\u{00B0} \u{00B7} \u{03B2} 0,0\u{00B0}": the stage tilts the file wrote; nil when it wrote neither.
    static func stage(_ m: SpectrumImageMetadata, locale: Locale = .current) -> String? {
        let parts = [("\u{03B1}", m.alphaTiltDegrees), ("\u{03B2}", m.betaTiltDegrees)].compactMap { name, v in
            v.map { "\(name) \(number($0, fraction: 1...1, locale: locale))\u{00B0}" }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    /// "4 187,7 s \u{00B7} real 1 423,1 s": the detectors' live time (a range when the segments differ), then the real time when
    /// the file has one; nil when no detector carries a live time (semantics as stored, unverified).
    static func liveTime(_ m: SpectrumImageMetadata, locale: Locale = .current) -> String? {
        func span(_ values: [Double]) -> String? {
            guard let lo = values.min(), let hi = values.max() else { return nil }
            let a = number(lo, fraction: 1...1, locale: locale)
            return lo == hi ? a : a + "\u{2013}" + number(hi, fraction: 1...1, locale: locale)
        }
        guard let live = span(m.detectors.compactMap(\.liveTime)) else { return nil }
        let real = span(m.detectors.compactMap(\.realTime)).map { " \u{00B7} real \($0) s" } ?? ""
        return live + " s" + real
    }
}
