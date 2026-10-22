//
//  QuickLookCard.swift
//  Role: the Quick Look preview card as one SwiftUI view turned into a PNG with `ImageRenderer` (a data-based preview: no view
//        controller, no AppKit): the image on the left, on the right a short list of what the file's headers say. The rows are plain
//        data (`rows(for:)`) so a test reads them; the view only lays them out.
//  Provenance: shared by the QuickLookPreview extension and the app's unit tests (package target DSTEMQuickLook); macTEM copies it with
//        a header (copies.manifest) until MacEMShell exists.
//

import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import FormatoPeek

public nonisolated enum QuickLookCardContent {
    public struct Row: Sendable, Equatable {
        public let label: String
        public let value: String
    }

    /// What the card lists, in order, skipping what the file does not say. Numbers use a locale-free decimal mark: the card is a picture.
    public static func rows(for s: Peek.Summary) -> [Row] {
        var rows: [Row] = [Row(label: "Format", value: s.format)]
        func add(_ label: String, _ value: String?) { if let value, !value.isEmpty { rows.append(Row(label: label, value: value)) } }
        add("Title", s.title)
        add("Signal", s.signalType)
        if let w = s.scanWidth, let h = s.scanHeight {
            add("Scan", "\(w) \u{00D7} \(h) positions")
            add("Detector", "\(s.width) \u{00D7} \(s.height) px")
        } else {
            add("Size", "\(s.width) \u{00D7} \(s.height) px")
        }
        if let size = s.pixelSize, size.isFinite, size > 0 {
            add(s.scanWidth == nil ? "Pixel size" : "Scan step", number(size) + (s.pixelUnit.map { " " + $0 } ?? ""))
        }
        if let size = s.detectorPixelSize, size.isFinite, size > 0 {
            add("Detector step", number(size) + (s.detectorPixelUnit.map { " " + $0 } ?? ""))
        }
        add("Acquired", s.acquired)
        add("Detector name", s.detector)
        add("Instrument", s.instrument)
        add("Voltage", s.highTensionKV.map { number($0) + " kV" })
        add("Camera length", s.cameraLengthMM.map { number($0) + " mm" })
        add("Magnification", s.magnification.map { number($0) + "\u{00D7}" })
        add("Data type", s.dataType)
        for note in s.notes { add("Note", note) }
        return rows
    }

    private static func number(_ v: Double) -> String {
        v.formatted(.number.precision(.significantDigits(1...5)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
    }
}

public struct QuickLookCard: View {
    public let rows: [QuickLookCardContent.Row]
    public let image: CGImage?
    public let fileName: String

    public init(rows: [QuickLookCardContent.Row], image: CGImage?, fileName: String) {
        self.rows = rows; self.image = image; self.fileName = fileName
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 20) {
            Group {
                if let image {
                    Image(decorative: image, scale: 1).resizable().interpolation(.none).aspectRatio(contentMode: .fit)
                } else {
                    Color.black.opacity(0.85).overlay(Text("No preview image").foregroundStyle(.secondary))
                }
            }
            .frame(width: 360, height: 360)
            .background(Color.black)
            VStack(alignment: .leading, spacing: 6) {
                Text(fileName).font(.title3.weight(.semibold)).lineLimit(2)
                Divider()
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.label).foregroundStyle(.secondary).frame(width: 112, alignment: .leading)
                        Text(row.value).monospacedDigit().lineLimit(2)
                    }
                    .font(.callout)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(20)
        .frame(width: 760, height: 400)
        .background(Color(white: 0.96))
        .environment(\.colorScheme, .light)
    }

    /// The card as PNG data (2x), or nil when rendering fails. Main actor: `ImageRenderer`.
    @MainActor public static func pngData(summary: Peek.Summary, frame: Peek.Frame?, fileName: String) -> Data? {
        let image = frame.flatMap { QuickLookRendering.image(for: $0, within: CGSize(width: 720, height: 720)) }
        let renderer = ImageRenderer(content: QuickLookCard(rows: QuickLookCardContent.rows(for: summary), image: image, fileName: fileName))
        renderer.scale = 2
        guard let cg = renderer.cgImage else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cg, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    public static let contentSize = CGSize(width: 760, height: 400)
}
