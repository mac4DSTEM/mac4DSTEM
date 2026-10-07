//
//  AppState+LabelImport.swift
//  Role: the import behind "Import Labels…" (T3). The file is picked by the view's `.fileImporter`
//        (UI/MapSettings.swift); the decision (cube path, scan bounds, replace) is
//        `DiskCentreLabelStore.importLabels`; this only reads the picked file. No stored state here.
//

#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif
import Foundation

extension AppState {
    /// The read half of the import. `.fileImporter` hands back a security-scoped URL, so access is held
    /// for the read only and released before the caller decides anything.
    static func readPickedLabelFile(at url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }

    /// The panel-free half, so a test can drive it.
    func importDiskCentreLabels(from url: URL, descriptor: DatasetDescriptor) {
        let data: Data
        do { data = try Self.readPickedLabelFile(at: url) } catch {
            diskCentreLabels.refuseImport("\(url.lastPathComponent): \(error.localizedDescription) — nothing imported.")
            return
        }
        if diskCentreLabels.importLabels(from: data, fileName: url.lastPathComponent,
                                         expecting: descriptor.filePath, datasetPath: descriptor.datasetPath,
                                         frame: DiskCentreLabelStore.frameTag(loadedView.specification),
                                         scanY: descriptor.ry, scanX: descriptor.rx,
                                         detectorY: descriptor.qy, detectorX: descriptor.qx) {
            statusText = "Imported disk-centre labels ← \(url.lastPathComponent) (replaced the current labels)"
        }
    }
}
