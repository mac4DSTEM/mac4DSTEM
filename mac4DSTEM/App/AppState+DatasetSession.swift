import Foundation
#if canImport(DSTEMCore)
import DSTEMCore
import DSTEMSession
#endif

/// Lifecycle orchestration for the `DatasetSession` owner: window-level
/// recovery, navigation and error presentation.
extension AppState {

    func openRecent(_ recent: RecentDataset) {
        do {
            let resolved = try WorkspaceRecoveryStore.resolve(recent.bookmark)
            if recoveryRecord?.datasetID == recent.id { pendingRecovery = recoveryRecord }
            if resolved.stale { refreshStoredBookmark(for: resolved.url, id: recent.id) }
            openFile(url: resolved.url)
        } catch {
            // Two different fates: a volume that is merely NOT MOUNTED keeps
            // its recent-list entry — deleting it would destroy the only
            // place the NAS path is shown, for a dataset that is otherwise
            // fine — while a genuinely dead bookmark is still removed.
            // `.withoutMounting` is what makes the unmounted case reach this
            // catch fast instead of freezing the UI ~30 s per click.
            if let volume = WorkspaceRecoveryStore.unmountedVolumeName(
                forBookmark: recent.bookmark
            ) {
                present(SimpleError(
                    "The volume “\(volume)” is not mounted. Connect it in Finder, then open the dataset again."
                ))
            } else {
                recents.remove(id: recent.id)
                present(SimpleError("This recent dataset is no longer accessible. Open it again to renew permission."))
            }
        }
    }

    func reopenLastDataset() {
        guard let recoveryRecord,
              let recent = recents.entry(withID: recoveryRecord.datasetID) else {
            present(SimpleError("No recoverable dataset is available.")); return
        }
        openRecent(recent)
    }

    func removeRecent(_ recent: RecentDataset) {
        recents.remove(id: recent.id)
        if recoveryRecord?.datasetID == recent.id {
            recoveryRecord = nil
            WorkspaceRecoveryStore.clearRecovery()
        }
    }

    func rememberOpenedDataset(_ url: URL) {
        do {
            let bookmark = try WorkspaceRecoveryStore.bookmark(for: url)
            let id = url.standardizedFileURL.path
            recents.remember(RecentDataset(id: id, displayName: url.lastPathComponent,
                                           bookmark: bookmark, lastOpened: Date()))
            recoveryRecord = DatasetRecoveryRecord(
                datasetID: id, bookmark: bookmark,
                selectedX: selectedScan.x, selectedY: selectedScan.y,
                analysisMode: navigation.analysisMode.rawValue, updated: Date(),
                loadSpecification: loadedView.specification
            )
            WorkspaceRecoveryStore.saveRecovery(recoveryRecord!)
        } catch {
            statusText = "Loaded data, but recent-file access could not be remembered: \(Self.errorDetail(error))"
        }
    }

    private func refreshStoredBookmark(for url: URL, id: String) {
        guard let bookmark = try? WorkspaceRecoveryStore.bookmark(for: url) else { return }
        recents.updateBookmark(bookmark, forID: id)
    }

    func persistRecoveryPosition() {
        guard descriptor != nil, var record = recoveryRecord else { return }
        record.selectedX = selectedScan.x
        record.selectedY = selectedScan.y
        record.analysisMode = navigation.analysisMode.rawValue
        record.updated = Date()
        // Every stamp restates the frame, so a position persisted after a
        // promote is knowably full-extent, not silently reinterpreted by the
        // next crop-restoring relaunch.
        record.loadSpecification = loadedView.specification
        recoveryRecord = record
        WorkspaceRecoveryStore.saveRecovery(record)
    }

    func selectDataset(_ descriptor: DatasetDescriptor) {
        guard let reader = datasetSession.reader else { return }
        Task {
            // Bracketed as a load, the way openFileAsync does it: `activate`
            // preloads the resident cube, and the preload's progress callback
            // is gated on `datasetSession.isLoading`. Without this bracket,
            // switching to a multi-gigabyte dataset sets statusText to
            // "Loaded …" with the bar at 1.0 and then reads the whole cube in
            // complete silence — open-items #36's stall, reintroduced one
            // layer down.
            beginDatasetLoading("Opening \(descriptor.datasetPath)…")
            await activate(descriptor: descriptor, reader: reader)
            finishDatasetLoading()
        }
    }
}
