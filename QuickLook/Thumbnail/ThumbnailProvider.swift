//
//  ThumbnailProvider.swift
//  Role: the Finder thumbnail of a 4D-STEM HDF5 file: the file's own stored image, or one diffraction pattern at the centre scan
//        position (FormatoKit's `Peek`: one decimated frame, never the mean pattern), drawn with CoreGraphics. A thin class: the
//        reading is FormatoKit's, the pixels are `QuickLookRendering` (package DSTEMQuickLook). Quick Look caches thumbnails itself.
//  Budget: one frame, well under a second and 64 MB (measured by FormatoKit's Peek tests); the system kills a longer one.
//

import QuickLookThumbnailing
import FormatoPeek
import DSTEMQuickLook

final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        do {
            let side = Int((max(request.maximumSize.width, request.maximumSize.height) * request.scale).rounded(.up))
            let frame = try Peek.thumbnailFrame(url: request.fileURL, maxPixels: min(max(side, 64), 1024))
            let size = QuickLookRendering.fittedSize(for: frame, within: request.maximumSize)
            guard size.width >= 1, size.height >= 1 else { handler(nil, nil); return }
            handler(QLThumbnailReply(contextSize: size, drawing: { context in
                QuickLookRendering.draw(frame, in: context, size: size)
                return true
            }), nil)
        } catch {
            handler(nil, error)
        }
    }
}
