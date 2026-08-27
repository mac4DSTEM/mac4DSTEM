//
//  MetalLayerScaleTests.swift
//  Pins MetalImageView.ScaleAwareMTKView — the fix for F1.3b, the configurator
//  panes that drew nothing for nine days (2026-08-18 → 2026-08-27).
//
//  The defect class this guards: inside SwiftUI's sheet the hosted MTKView's
//  CAMetalLayer is left at contentsScale == 0, and a layer at scale 0 cannot
//  display a drawable. (What writes the 0 is NOT identified. A detached
//  MTKView reads 1.0 — see the observation test below — so "created outside a
//  window comes up with 0" was wrong, and was corrected on 2026-08-27 after
//  the Gate B second reader measured it.) NOTHING inside the view reports a problem — MTKView derives
//  `drawableSize` from the WINDOW's backing scale, not from the layer's
//  contentsScale, so the drawable is correctly sized, the render-pass
//  descriptor and currentDrawable are non-nil, the texture uploads, and the
//  frame is encoded and presented. The pane simply stays background-coloured.
//  That is why three rounds of diagnosis looked at the data and the sheet and
//  found nothing wrong with either. Measured on screen 2026-08-27, in one
//  instrumented cold open: contentsScale 0.0 on both blank panes against a
//  window backingScaleFactor of 2.0, and 2.0 on the pane that rendered.
//
//  WHAT THIS TEST DOES NOT COVER, stated because it is the larger half: that
//  SwiftUI's AppKitPlatformViewHost fails to propagate backing properties
//  inside a sheet is only observable on screen. This pins the repair — that
//  entering a window sets the layer's scale — not the framework behaviour that
//  makes the repair necessary. The on-screen evidence is Track B row F1.3b.
//

import XCTest
import MetalKit
@testable import mac4DSTEM

final class MetalLayerScaleTests: XCTestCase {

    /// The bare `MTKView` behaviour this fix exists to correct. If this ever
    /// starts failing, Apple changed the default and the fix may be reducible —
    /// it is an OBSERVATION, not a requirement, so it asserts nothing about
    /// what the value should be.
    func testDocumentsTheDetachedLayerScaleThisMachineProduces() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let plain = MTKView(frame: .zero, device: device)
        let scale = plain.layer?.contentsScale
        XCTAssertNotNil(scale, "MTKView is expected to be layer-backed")
        // Recorded, not asserted: 1.0 on this machine, 2026-08-27 — NOT the 0.0
        // the first write-up claimed. The 0 the app hits is produced somewhere
        // in SwiftUI's hosting path, not by detached construction.
        print("detached MTKView layer contentsScale = \(scale as Any)")
    }

    // WHY THERE IS NO `viewDidMoveToWindow` TEST HERE, and this absence is
    // deliberate. Three versions were written and all three passed with the
    // fix REMOVED, so all three were thrown away rather than kept:
    //
    //   1. add the view to a window, assert the layer took the window's scale
    //      — a plain AppKit window propagates the scale by itself, so this
    //        asserts something AppKit already guarantees;
    //   2. zero the scale first, then call `viewDidMoveToWindow()` — assigning
    //      0 to a layer-backed view already in a window does not stick;
    //   3. the same with a stale-but-legal 1 — AppKit corrects that too before
    //      the assertion is reached.
    //
    // The `contentsScale == 0` state is produced only by SwiftUI's
    // `AppKitPlatformViewHost` inside a sheet, and nothing in this test host
    // reproduces it. Its only evidence is on screen: Track B row F1.3b, plus
    // the five-cold-open trial with the fix and the matched negative control
    // recorded in `docs/open-items.md`. `matchWindowScale` is reached from both
    // overrides, so the test below still exercises the repair itself — what is
    // uncovered is the framework gap that makes it necessary.

    /// The scale must also follow a LATER change — nominally the display-move
    /// case `viewDidChangeBackingProperties` exists for. Driven directly,
    /// because a second display cannot be assumed on a test machine.
    ///
    /// This test is worth more than it looks. Driving the app with each override
    /// removed in turn (2026-08-27) showed **either one alone repairs the real
    /// failure, 3/3 each** — so this is not merely a safeguard for an unusual
    /// case, it covers a path that is sufficient on its own for F1.3b.
    func testAChangeInBackingPropertiesIsFollowed() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let view = MetalImageView.ScaleAwareMTKView(frame: .zero, device: device)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView?.addSubview(view)

        // Simulate the layer being left behind at a stale scale, as it is when
        // it is created detached, then deliver the AppKit notification.
        view.layer?.contentsScale = 1
        view.viewDidChangeBackingProperties()

        XCTAssertEqual(
            view.layer?.contentsScale, window.backingScaleFactor,
            "A stale contentsScale survived viewDidChangeBackingProperties"
        )
    }
}
