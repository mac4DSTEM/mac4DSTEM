//
//  ModelCacheUsage.swift
//  Role: how much the learned detector's two caches hold (mac4DSTEM#179). The app is sandboxed, so a signed build keeps
//        both in its container, where neither Terminal nor another app may look: Core ML's cache of device-specialised
//        models (`Caches/<bundle id>/com.apple.e5rt.e5bundlecache`, 26 GB on the development Mac, macEM-suite#87) and the
//        app's own compiled models (`CompiledModelCache`, `Caches/<bundle id>/DiskDetectorCompiled`). Settings shows the
//        two numbers. Read-only: nothing here deletes or writes.
//

import Foundation

package nonisolated struct ModelCacheUsage: Sendable, Equatable {
    /// Entries and bytes of one cache folder.
    package struct Folder: Sendable, Equatable {
        package var entries: Int
        package var bytes: Int64

        package init(entries: Int, bytes: Int64) {
            self.entries = entries
            self.bytes = bytes
        }
    }

    /// Core ML's e5 bundle cache; nil when the folder is absent.
    package var coreML: Folder?
    /// The compiled detector models; nil when the folder is absent.
    package var compiledModels: Folder?

    package init(coreML: Folder?, compiledModels: Folder?) {
        self.coreML = coreML
        self.compiledModels = compiledModels
    }

    /// Both folders under `caches` (the app's Caches folder, `Caches/<bundle id>`).
    package static func measure(appCaches caches: URL) -> ModelCacheUsage {
        ModelCacheUsage(
            // Core ML keeps one folder per OS build and its entries inside it, so entries are counted one level down.
            coreML: measure(caches.appendingPathComponent("com.apple.e5rt.e5bundlecache", isDirectory: true), entryDepth: 2),
            compiledModels: measure(caches.appendingPathComponent("DiskDetectorCompiled", isDirectory: true), entryDepth: 1))
    }

    /// The app's own Caches folder, as `CompiledModelCache.defaultDirectory` names it.
    package static func appCachesDirectory() -> URL? {
        CompiledModelCache.defaultDirectory()?.deletingLastPathComponent()
    }

    /// The items `entryDepth` levels below `folder` (1: its children), and the allocated size of every file under it.
    /// Nil when the folder does not exist; a folder that cannot be read counts what it can.
    package static func measure(_ folder: URL, entryDepth: Int) -> Folder? {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        var entries = 0
        var bytes: Int64 = 0
        let rootDepth = folder.standardizedFileURL.pathComponents.count
        guard let walk = fm.enumerator(at: folder, includingPropertiesForKeys: keys, options: [],
                                       errorHandler: { _, _ in true }) else { return Folder(entries: 0, bytes: 0) }
        for case let url as URL in walk {
            if url.standardizedFileURL.pathComponents.count - rootDepth == entryDepth { entries += 1 }
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            bytes += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return Folder(entries: entries, bytes: bytes)
    }

    /// "48,160 entries, 26 GB", or "None" for an absent folder. Finder's byte style.
    package static func text(_ folder: Folder?) -> String {
        guard let folder else { return "None" }
        let count = folder.entries.formatted() + (folder.entries == 1 ? " entry" : " entries")
        return count + ", " + folder.bytes.formatted(.byteCount(style: .file))
    }
}
