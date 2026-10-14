import SwiftUI
import UniformTypeIdentifiers
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// When the Spectroscopy room's exports and Pin are on, and what they do: one rule for the inspector's buttons and the menu bar's
/// commands (UI audit 2026-10-14, The menu bar). The inspector's Export and Region sections and `DatasetCommands` both call these,
/// so a button and its menu item can never disagree.
@MainActor
enum SpectroscopyMenuRule {
    /// The room's items are in the menu bar while the Spectroscopy room is the one on screen with a spectrum image behind it.
    static func showsItems(area: WorkspaceArea, hasSpectrumImage: Bool) -> Bool { area == .spectroscopy && hasSpectrumImage }

    // Enabled when ...
    /// the results table has its text (after Quantify).
    static func canExportResults(_ model: SpectroscopyRoomModel) -> Bool { ExportSection.resultsExport(model.export) != nil }
    /// the method has its JSON (after Quantify).
    static func canExportMethod(_ model: SpectroscopyRoomModel) -> Bool { ExportSection.methodExport(model.export) != nil }
    /// a spectrum is shown (no fit needed).
    static func canExportSpectrum(_ model: SpectroscopyRoomModel) -> Bool { ExportSection.canExportSpectrum(model.export) }
    /// there is an element map to write (no fit needed).
    static func canExportMaps(_ model: SpectroscopyRoomModel) -> Bool { ExportSection.canExportMaps(model) }
    /// the controller can pin and fewer than three are pinned.
    static func canPin(_ model: SpectroscopyRoomModel) -> Bool { model.onPin != nil && model.pins.count < SpectroscopyRoomModel.maximumPins }

    // Do. Each is a no-op when its rule is off, so a stale menu item cannot write something the button would refuse.
    static func exportResults(_ model: SpectroscopyRoomModel) { if canExportResults(model) { model.pendingExport = ExportSection.resultsExport(model.export) } }
    static func exportMethod(_ model: SpectroscopyRoomModel) { if canExportMethod(model) { model.pendingExport = ExportSection.methodExport(model.export) } }
    static func exportSpectrum(_ model: SpectroscopyRoomModel) { if canExportSpectrum(model) { model.pendingExport = ExportSection.spectrumExport(model) } }
    static func exportMaps(_ model: SpectroscopyRoomModel) { if canExportMaps(model) { model.pickingMapsFolder = true } }
    static func pin(_ model: SpectroscopyRoomModel) { if canPin(model) { model.onPin?() } }
}

/// The room's save panel and folder chooser, presented from the room's host (always on screen with the room) and not from the
/// inspector's Export section: a menu command can start an export while that section is collapsed or scrolled away.
struct SpectroscopyExportPresenters: ViewModifier {
    @Bindable var model: SpectroscopyRoomModel
    @Environment(AppPreferences.self) private var preferences

    func body(content: Content) -> some View {
        content
            .fileExporter(isPresented: Binding(get: { model.pendingExport != nil }, set: { if !$0 { model.pendingExport = nil } }),
                          document: SpectroscopyTextDocument(text: model.pendingExport?.text ?? ""),
                          contentType: model.pendingExport?.isJSON == false ? .commaSeparatedText : .json,
                          defaultFilename: model.pendingExport?.name ?? "spectroscopy") { result in
                switch result {
                case .success(let url): model.exportNote = "Saved \(url.lastPathComponent)"
                case .failure(let error): model.exportNote = "Could not save: \(error.localizedDescription)"
                }
            }
            // A second file panel on the same view loses to the first on some systems, so the folder chooser has a view of its own.
            .background(Color.clear.fileImporter(isPresented: $model.pickingMapsFolder, allowedContentTypes: [.folder]) { result in
                switch result {
                case .success(let folder):
                    do {
                        let written = try MapsExport.writeInNewFolder(try MapsExport.files(model, pixelScale: preferences.exportScale.pixelScale, scheme: FigureColors.scheme(appearance: preferences.appearance)),
                                                                     in: folder, named: MapsExport.folderName(stem: model.export.mapsStem))
                        model.exportNote = MapsExport.note(written: written.names, folder: written.folder)
                        model.exportedFolder = written.folder
                    } catch { model.exportNote = "Could not write the maps: \(error.localizedDescription)"; model.exportedFolder = nil }
                case .failure(let error): model.exportNote = "Could not write the maps: \(error.localizedDescription)"; model.exportedFolder = nil
                }
            })
    }
}
