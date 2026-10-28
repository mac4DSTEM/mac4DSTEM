import ShellInspector
import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// The Results inspector's Figure section: several of the window's images in one labelled file, each with its scale bar, the detector
/// outlined on the pattern and the regions on the EDX maps as the screen draws them. The file is a PNG or TIFF at 1x, 2x or 3x pixels, or
/// a vector PDF, and leaves through SwiftUI's own export panel (`fileExporter`). The images offered are the window's own
/// (`AppState.figureChoices`); the person's ticks sit over each image's default. The drawing is `FigureRendering`; this view only chooses.
struct FigureExportSection: View {
    @Environment(AppState.self) private var appState
    @Environment(AppPreferences.self) private var preferences
    /// The person's ticks over the defaults; an image absent here is as `FigureChoice.isDefault` says.
    @State private var ticks: [String: Bool] = [:]
    /// The "Detector outline" tick; nil follows the pane (the outline is drawn in the Virtual Detector task, which is not a room of its own:
    /// the last room visited would otherwise decide).
    @State private var detector: Bool?
    /// The figure made by the button, held while SwiftUI's export panel is up.
    @State private var file: FigureFile?
    @State private var isExporting = false

    /// The ids ticked: the person's choice where there is one, the default otherwise.
    static func chosen(_ choices: [FigureChoice], ticks: [String: Bool]) -> Set<String> {
        Set(choices.filter { ticks[$0.id] ?? $0.isDefault }.map(\.id))
    }

    static let exportTitle = "Export Figure\u{2026}"
    static let emptyNote = "Make an image, or open a spectrum image, to put it in a figure."
    static let formatHelp = "PNG and TIFF are pixels at the image size; PDF is vector, so the labels, outlines and scale bars stay sharp at any zoom (only the maps are pixels)."
    static let sizeHelp = "Pixels per point of every exported PNG (the result image, the diffraction pattern, the EDS maps and the figure): 2\u{00D7} and 3\u{00D7} are the same picture, sharper, and the file says so (144 or 216 ppi) so a slide is placed at the 1\u{00D7} size."

    var body: some View {
        @Bindable var preferences = preferences
        let choices = appState.figureChoices
        let chosen = Self.chosen(choices, ticks: ticks)
        InspectorSection("Figure") {
            if choices.isEmpty {
                InspectorNote(Self.emptyNote)
            } else {
                ForEach(choices) { choice in
                    InspectorDataRow(choice.label) {
                        Toggle(choice.label, isOn: Binding(get: { chosen.contains(choice.id) }, set: { ticks[choice.id] = $0 }))   // no key-path form: a dictionary default is not hashable
                            .labelsHidden().toggleStyle(.checkbox)
                    }
                    .accessibilityIdentifier("results.figure.\(choice.id)")
                }
                if choices.contains(where: { $0.id == FigureChoice.patternID }) {
                    InspectorRow("Detector outline") {
                        Toggle("Detector outline", isOn: Binding(get: { detector ?? appState.patternExportOverlays.isEmpty == false }, set: { detector = $0 }))
                            .labelsHidden().toggleStyle(.checkbox)
                            .help("Outlines the virtual detector on the diffraction pattern, as the pane draws it. Ticked to begin with in the Virtual Detector task.")
                            .accessibilityIdentifier("results.figure.detector")
                    }
                }
                InspectorRow("Format") {
                    Picker("Format", selection: $preferences.figureFormat) {
                        ForEach(ExportFigureFormat.allCases) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                    .help(Self.formatHelp)
                    .accessibilityIdentifier("results.figure.format")
                }
                InspectorRow("Image size") {
                    Picker("Image size", selection: $preferences.exportScale) {
                        ForEach(ExportImageScale.allCases) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                    .disabled(preferences.figureFormat == .pdf)
                    .help(preferences.figureFormat == .pdf ? "A PDF is vector: it has no pixels to scale." : Self.sizeHelp)
                    .accessibilityIdentifier("results.figure.size")
                }
                if appState.hasSpectrumImage {
                    @Bindable var room = appState.edxRoom
                    InspectorRow("Regions") {
                        Toggle("Regions", isOn: $room.exportRegions)
                            .labelsHidden().toggleStyle(.switch)
                            .help("Outlines the selected region on the EDS maps")
                            .accessibilityIdentifier("results.figure.regions")
                    }
                }
                InspectorActionRow {
                    InspectorAdaptiveButton(Self.exportTitle, systemImage: "square.and.arrow.up",
                                            help: chosen.isEmpty ? "Tick at least one image." : "The ticked images in one labelled file, in the format and size above") {
                        do { file = try appState.figureFile(chosen: chosen, detector: detector); isExporting = true } catch { appState.present(error) }
                    }
                    .disabled(chosen.isEmpty)
                    .accessibilityIdentifier("results.figure.export")
                }
            }
        }
        // SwiftUI's own export panel; its message says what is being saved and at what size.
        .fileExporter(isPresented: $isExporting, document: file, contentTypes: file.map { [$0.contentType] } ?? [], defaultFilename: file?.suggestedName) { result in
            if let file { appState.figureExported(result, file: file) }
            file = nil   // the bytes are not kept once written
        } onCancellation: {
            file = nil
        }
        .fileDialogMessage(file.map { Text($0.message) })
    }
}
