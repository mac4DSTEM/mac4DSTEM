//
//  ExportProvenanceTests.swift
//  v2 S7 — the exported figure's caption and metadata.
//
//  Two defects: the burned-in caption — the provenance record of the exported
//  pixels — was tail-truncated at one 17 pt line, and the PNG carried no
//  machine-readable metadata at all. The caption now wraps (the figure grows),
//  and the full provenance record travels as a JSON `Description` text chunk.
//
//  The metadata test goes through a REAL file on disk: a property dictionary
//  ImageIO silently drops would look exactly like one it wrote, so asserting
//  on the dictionary we PASSED would prove nothing.
//

import XCTest
import ImageIO
@testable import mac4DSTEM

@MainActor
final class ExportProvenanceTests: XCTestCase {

    private func solidImage(width: Int, height: Int) -> CGImage {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )!
        return bitmap.cgImage!
    }

    // MARK: - Caption wrapping

    func testLongCaptionGrowsTheFigureInsteadOfTruncating() {
        let width: CGFloat = 220
        let short = AppState.captionTextHeight("real space", width: width)
        let long = AppState.captionTextHeight(
            String(repeating: "source_product=strain_exx · ", count: 12),
            width: width
        )
        XCTAssertGreaterThan(long, short * 2,
                             "A 12-part caption at 220 pt must wrap onto several lines")

        let image = solidImage(width: 200, height: 100)
        let shortFigure = AppState.publicationFigure(
            image: image, title: "T", caption: "real space",
            valueRange: nil, valueUnits: "", colormap: .viridis
        )
        let longFigure = AppState.publicationFigure(
            image: image, title: "T",
            caption: String(repeating: "source_product=strain_exx · ", count: 12),
            valueRange: nil, valueUnits: "", colormap: .viridis
        )
        XCTAssertEqual(CGFloat(longFigure.height - shortFigure.height), long - short,
                       "The figure must grow by exactly the caption's extra height")
        XCTAssertEqual(longFigure.width, shortFigure.width,
                       "Caption length must never change the figure's width")
    }

    // MARK: - PNG metadata round-trip

    func testProvenanceRecordSurvivesTheActualPNGFile() throws {
        let record: [String: Any] = [
            "title": "Strain εxx",
            "caption": "real space · quantitative",
            "value_units": "strain",
            "pixel_size_row": 0.5,
            "provenance": ["source_product": "strain_exx", "basis_mode": "auto"],
            "load_specification": "scan 0,0 12×12",
        ]
        let properties = try XCTUnwrap(
            AppState.pngProperties(title: "Strain εxx", record: record)
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("s7-metadata-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(
            AppState.writePNG(solidImage(width: 8, height: 8), to: url,
                              properties: properties)
        )

        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let read = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        let png = try XCTUnwrap(read[kCGImagePropertyPNGDictionary] as? [CFString: Any],
                                "The PNG text chunks must survive the write: \(read.keys)")
        let description = try XCTUnwrap(png[kCGImagePropertyPNGDescription] as? String,
                                        "The Description chunk carries the record: \(png.keys)")
        let decoded = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(description.utf8)) as? [String: Any]
        )
        XCTAssertEqual(decoded["title"] as? String, "Strain εxx")
        XCTAssertEqual(decoded["load_specification"] as? String, "scan 0,0 12×12")
        XCTAssertEqual(
            (decoded["provenance"] as? [String: String])?["source_product"], "strain_exx",
            "The nested provenance dictionary must round-trip intact"
        )
        XCTAssertEqual(png[kCGImagePropertyPNGTitle] as? String, "Strain εxx")
    }

    /// The record the export actually builds, from a real result: everything
    /// the figure renders must be in it, plus the persistence provenance the
    /// caption can only excerpt.
    func testExportedRecordCarriesTheFigureFacts() async throws {
        let state = AppState()
        let cropped = LoadSpecification(
            scanCrop: AxisCrop(yOffset: 2, xOffset: 2, height: 8, width: 8),
            detectorCrop: nil, detectorBin: 1
        )
        await state.openDemoFixture(calibrated: true, specification: cropped)
        state.analysisMode = .virtualDetector
        await state.runVirtualDetector()
        XCTAssertNotNil(state.resultImage)

        let record = state.exportedImageProvenanceRecord()
        XCTAssertEqual(record["title"] as? String, state.currentResultDisplayName)
        XCTAssertEqual(record["value_units"] as? String, state.currentResultValueUnits)
        let caption = try XCTUnwrap(record["caption"] as? String)
        XCTAssertFalse(caption.isEmpty)
        XCTAssertNotNil(record["provenance"] as? [String: String],
                        "The persistence provenance dictionary must travel whole")
        let specification = try XCTUnwrap(record["load_specification"] as? String)
        XCTAssertNotEqual(specification, "whole file",
                          "A cropped session's export must say which view produced it")
        XCTAssertNotNil(AppState.pngProperties(
            title: state.currentResultDisplayName, record: record
        ), "The real record must serialize — a record that cannot is one the export silently drops")
    }
}
