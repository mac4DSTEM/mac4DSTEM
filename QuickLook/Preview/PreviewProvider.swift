//
//  PreviewProvider.swift
//  Role: the spacebar preview of a 4D-STEM HDF5 file: one card (the file's image on the left, its header facts on the right), rendered
//        by SwiftUI's `ImageRenderer` into PNG data and returned as a data-based preview (QLPreviewReply): no view controller, no AppKit.
//        The reading is FormatoKit's `Peek` (header facts and one frame); the card is `QuickLookCard` (package DSTEMQuickLook).
//

import QuickLookUI
import UniformTypeIdentifiers
import FormatoPeek
import DSTEMQuickLook

final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let url = request.fileURL
        let summary = try Peek.summary(url: url)
        let frame = try? Peek.thumbnailFrame(url: url, maxPixels: 720)
        guard let png = await QuickLookCard.pngData(summary: summary, frame: frame, fileName: url.lastPathComponent) else {
            throw CocoaError(.fileReadUnknown)
        }
        return QLPreviewReply(dataOfContentType: .png, contentSize: QuickLookCard.contentSize) { _ in png }
    }
}
