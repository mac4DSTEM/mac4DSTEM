//
//  AppState+LabelImport.swift
//  Role: the file panel behind "Import Labels…" (T3). The decision (cube path, scan bounds, replace) is
//        `DiskCentreLabelStore.importLabels`; this only picks the file and reads it. No stored state here.
//

import AppKit
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif
import UniformTypeIdentifiers

extension AppState {
    func importDiskCentreLabels() {
        guard let descriptor else { return }
        let panel = NSOpenPanel()
        panel.title = "Import Disk-Centre Labels"
        panel.message = "Choose a labels file written by Export Labels…. It replaces the current labels."
        panel.prompt = "Import"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importDiskCentreLabels(from: url, descriptor: descriptor)
    }

    /// The panel-free half, so a test can drive it.
    func importDiskCentreLabels(from url: URL, descriptor: DatasetDescriptor) {
        let data: Data
        do { data = try Data(contentsOf: url) } catch {
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
