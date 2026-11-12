//
//  AgentDoorScanMap.swift
//  Role: The scan map in scan coordinates for an agent (issue #206). `get_result_image` is the exported figure (margins, colour
//        bar, caption, the display's rotation), so a scan position cannot be read off it. `get_scan_map` draws the displayed
//        result alone, unrotated, each scan position a k × k block, so that the position an agent picks on it is the one
//        `select_scan_position` takes. The selected position is outlined.
//

import CoreGraphics
import Foundation
import ShellAgentDoor
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

extension Mac4DSTEMAgentDoor {
    static let scanMapTools: [AgentTool] = [
        AgentTool(name: "get_scan_map", title: "Scan map in scan coordinates",
                  summary: "The displayed result (the virtual image in Bragg Disks, or a map) alone, in scan coordinates, for picking "
                      + "a position: not rotated or mirrored, no margins or colour bar. Each scan position is a k × k block of pixels, "
                      + "k = picture width ÷ scan columns (get_window's scan size): position (x, y) is the block whose top-left pixel "
                      + "is (x·k, y·k), x to the right, y down, as select_scan_position takes them. The selected position is outlined "
                      + "in magenta.",
                  input: .window) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            do {
                let map = try state.agentScanMapRGBA()
                let k = AppState.agentScanMapScale(width: map.width, height: map.height)
                let selected = state.selectedScan
                let bytes = AppState.agentScanMapPicture(map.bytes, width: map.width, height: map.height, scale: k,
                                                         outline: (x: selected.x, y: selected.y))
                return AgentJSON.picture(AppState.cgImage(rgba: bytes, width: map.width * k, height: map.height * k))
            } catch {
                return .refusal(status: 404, message: error.localizedDescription)
            }
        },
    ]
}

extension AppState {
    /// The displayed result's colours, one RGBA pixel per scan position, row by row from y = 0, as the figure colours them but
    /// before the display's rotation or mirror.
    func agentScanMapRGBA() throws -> (bytes: [UInt8], width: Int, height: Int) {
        guard let product = displayedProduct else {
            throw SimpleError("No scan map yet: compute the virtual image (Bragg Disks shows one once the dataset is open).")
        }
        switch product.payload {
        case .rgba(let rgba):
            return (rgba.rgba, rgba.width, rgba.height)
        case .scalar(let image):
            let norm = image.normalized(symmetric: resultPresentation.resultColormap.isDiverging)
            let bytes = Self.applyColormap(norm, colormap: resultPresentation.resultColormap,
                                           lo: resultPresentation.displayRangeLo, hi: resultPresentation.displayRangeHi,
                                           gamma: resultPresentation.resultGamma)
            return (bytes, image.width, image.height)
        }
    }

    /// Picture pixels per scan position: about 1024 pixels on the longer side, 1 to 16.
    nonisolated static func agentScanMapScale(width: Int, height: Int) -> Int {
        max(1, min(16, 1024 / max(width, height, 1)))
    }

    /// `rgba` (one pixel per position) drawn with each position as a `scale` × `scale` block, and a one-pixel magenta frame just
    /// around the block of `outline` (inside the picture's edges).
    nonisolated static func agentScanMapPicture(_ rgba: [UInt8], width: Int, height: Int, scale: Int,
                                                outline: (x: Int, y: Int)?) -> [UInt8] {
        let outWidth = width * scale, outHeight = height * scale
        var out = [UInt8](repeating: 0, count: outWidth * outHeight * 4)
        for py in 0..<outHeight {
            let sy = py / scale
            for px in 0..<outWidth {
                let source = (sy * width + px / scale) * 4, target = (py * outWidth + px) * 4
                out[target] = rgba[source]
                out[target + 1] = rgba[source + 1]
                out[target + 2] = rgba[source + 2]
                out[target + 3] = 255
            }
        }
        guard let outline, (0..<width).contains(outline.x), (0..<height).contains(outline.y) else { return out }
        let left = outline.x * scale - 1, right = (outline.x + 1) * scale, top = outline.y * scale - 1, bottom = (outline.y + 1) * scale
        func paint(_ px: Int, _ py: Int) {
            guard (0..<outWidth).contains(px), (0..<outHeight).contains(py) else { return }
            let target = (py * outWidth + px) * 4
            out[target] = 255; out[target + 1] = 0; out[target + 2] = 255; out[target + 3] = 255
        }
        for px in left...right { paint(px, top); paint(px, bottom) }
        for py in top...bottom { paint(left, py); paint(right, py) }
        return out
    }
}
