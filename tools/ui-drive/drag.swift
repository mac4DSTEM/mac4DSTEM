// Synthesize a slow left-button mouse drag with CGEvent: from (x0, y) to
// (x1, y) in n steps, screen coordinates (top-left origin). The one way to
// exercise a split-view divider's live tracking loop, which neither
// `setPosition` nor a posted event reaches — how the 2026-09-03 drag crash
// was reproduced (open-items). Needs the Accessibility grant for the shell.
//   swiftc -O -o build/drag tools/ui-drive/drag.swift
//   build/drag 300 483 15 30      # divider at x=300 → 15, 30 steps
import CoreGraphics
import Foundation
let a = CommandLine.arguments.dropFirst().compactMap(Double.init)
guard a.count >= 4 else { print("usage: drag x0 y x1 steps"); exit(2) }
let (x0, y, x1, n) = (a[0], a[1], a[2], Int(a[3]))
func post(_ type: CGEventType, _ x: Double) {
    let e = CGEvent(mouseEventSource: nil, mouseType: type,
                    mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)!
    e.post(tap: .cghidEventTap)
}
post(.mouseMoved, x0); usleep(150_000)
post(.leftMouseDown, x0); usleep(120_000)
for i in 1...n { post(.leftMouseDragged, x0 + (x1 - x0) * Double(i) / Double(n)); usleep(16_000) }
usleep(120_000)
post(.leftMouseUp, x1)
print("dragged \(x0) → \(x1)")
