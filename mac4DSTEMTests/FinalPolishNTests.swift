//
//  FinalPolishNTests.swift
//  Lane N (Slot 4⅞ polish, 2026-10-04; items P1 and P10c, Gate D).
//
//  P1: `NumberEntryField` committed the text it SHOWED on every blur, Return and room switch, even when nothing was
//  typed — so a field whose format shows fewer digits than the stored value has (Defocus 0...1, Exploratory scale 4,
//  learned threshold 2, the ellipse fit radii 0...2) silently stored the rounded value, and the Float-backed disk rows
//  (Double(Float 0.3) != 0.3) re-committed every time. Reproduced on screen (Exploratory scale 0.0125597 -> 0.0126 and
//  the ACOM result discarded by merely leaving the room; lane N drive.md). The rule now: the text the field shows for
//  the current value is not an edit.
//
//  P10c: the Preprocess sheet's Write read the draft without committing a typed-but-uncommitted Threshold (a click on
//  a button does not take focus from a Mac text field), so the file recorded the old threshold. Reproduced on screen.
//
//  Every test names the mutation that turns it red. Decimal strings are compared against the formatter, never
//  literals: the tests run in an explicit German-region locale, so a comma-region Mac and a period-region Mac agree.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class FinalPolishNTests: XCTestCase {
    private typealias Field = NumberEntryField<Double, FloatingPointFormatStyle<Double>>
    private typealias Entry = DecimalEntryFormat<FloatingPointFormatStyle<Double>>

    private let german = Locale(identifier: "en_US@rg=dezzzz")

    private func entry(_ digits: ClosedRange<Int>) -> Entry {
        DecimalEntryFormat(FloatingPointFormatStyle<Double>.number.precision(.fractionLength(digits)).locale(german),
                           locale: german)
    }

    private func fixedEntry(_ digits: Int) -> Entry {
        DecimalEntryFormat(FloatingPointFormatStyle<Double>.number.precision(.fractionLength(digits)).locale(german),
                           locale: german)
    }

    /// The fields whose format shows fewer digits than the value they hold (map P1: "affected fields"), each with the
    /// format the view really uses and a stored value finer than it. The name is the field's.
    private var roundingFields: [(name: String, entry: Entry, stored: Double)] {
        [("Ptychography Defocus, Å (0...1)", entry(0...1), 123.456),
         ("Astigmatism C12, Å (0...1)", entry(0...1), -3.449),
         ("Manual ellipse a, px (0...4)", entry(0...4), 41.234567),
         ("Manual ellipse θ, ° (0...3)", entry(0...3), 12.345678),
         ("Ellipse fit annulus inner, px (0...2)", entry(0...2), 44.625 + 1e-4),
         ("Learned threshold (2)", fixedEntry(2), 0.555),
         ("Exploratory scale, Å⁻¹/px (4)", fixedEntry(4), 0.0125597),
         ("Q scale, Å⁻¹/px (0...6)", entry(0...6), 0.19040012)]
    }

    // MARK: P1

    /// The experiment that discriminates the diagnosis: hand `resolve` the exact text the field shows for a value
    /// its format rounds. Before the fix this was `.set(rounded)` for every field below.
    /// The shown text with spaces around it is still the shown text (resolve trims, as it did).
    /// Mutation: delete the `typed == entry.format(current)` guard in `NumberEntryField.resolve` -> red (eight
    /// `.set(...)` results where `.keep` is asserted); compare the untrimmed text in it -> red on the spaced line.
    func testAnUneditedFieldNeverCommitsItsRoundedDisplay() throws {
        for field in roundingFields {
            let shown = field.entry.format(field.stored)
            let reread = try field.entry.parseStrategy.parse(shown)
            XCTAssertNotEqual(reread, field.stored,
                              "\(field.name): precondition — the format must round \(field.stored) (shown \(shown)), or this test cannot tell")
            XCTAssertEqual(Field.resolve(typed: shown, current: field.stored, emptyClears: false, entry: field.entry),
                           .keep, "\(field.name): shown \(shown) was committed as \(reread)")
            XCTAssertEqual(Field.resolve(typed: "  \(shown) ", current: field.stored, emptyClears: false, entry: field.entry),
                           .keep, "\(field.name): spaces around the shown text")
        }
    }

    /// A Defocus in the thousands of Å is a real ptychography input (format 0...1). The format's own output groups it
    /// ("1.234,6" in a comma region) but the field SHOWS it ungrouped ("1234,6", `DecimalEntryFormat.format`), and the
    /// guard must compare the text the field really holds: every value in the tests above is < 1000, where the two
    /// texts are equal and a guard against the grouped one would pass them all.
    /// Mutation: compare against `entry.inner.format(current)` (the grouped text) in the guard -> red (`.set(1234.6)`
    /// where `.keep`); delete the guard -> red as well.
    func testAnUneditedFieldAboveAThousandNeverCommitsItsRoundedDisplay() throws {
        let e = entry(0...1)
        for stored in [1234.567, -2345.678] {
            let shown = e.format(stored)
            XCTAssertFalse(shown.contains(german.groupingSeparator ?? "."),
                           "precondition: the field shows \(stored) ungrouped (\(shown))")
            XCTAssertNotEqual(e.inner.format(stored), shown,
                              "precondition: the inner format groups \(stored), or this test cannot tell the two texts apart")
            XCTAssertNotEqual(try e.parseStrategy.parse(shown), stored,
                              "precondition: the format must round \(stored) (shown \(shown))")
            XCTAssertEqual(Field.resolve(typed: shown, current: stored, emptyClears: false, entry: e), .keep,
                           "shown \(shown) over \(stored)")
            XCTAssertEqual(Field.resolve(typed: "  \(shown) ", current: stored, emptyClears: false, entry: e), .keep,
                           "spaces around the shown text, \(stored)")
        }
    }

    /// A Float-backed row (`doubleBinding(floatBinding(...))`): the Double the field is given is the Float's exact
    /// value, which no short decimal equals, so the old `parsed != current` re-committed on every blur and every
    /// room switch — and each commit assigned `diskParams` whole, firing the live overlay re-detect.
    /// Mutation: delete the shown-text guard -> red (`.set(0.3)`).
    func testAFloatBackedRowDoesNotRecommitItsOwnDisplay() throws {
        let e = fixedEntry(2)                      // AdjustmentSlider's default format
        for float: Float in [0.3, 0.1, 0.7, 12.34, 0.015] {
            let current = Double(float)
            let shown = e.format(current)
            XCTAssertNotEqual(try e.parseStrategy.parse(shown), current,
                              "precondition: Double(Float(\(float))) is not the decimal it shows (\(shown))")
            XCTAssertEqual(Field.resolve(typed: shown, current: current, emptyClears: false, entry: e), .keep,
                           "Float \(float) shown \(shown)")
        }
    }

    /// An edit still commits: a different number, a different spelling of a finer number, and either separator.
    /// Mutation: the guard returns `.keep` for any non-empty text (or compares only the leading digits) -> red.
    func testATypedEditStillCommits() {
        let e = entry(0...1)
        XCTAssertEqual(Field.resolve(typed: "123,6", current: 123.456, emptyClears: false, entry: e), .set(123.6))
        XCTAssertEqual(Field.resolve(typed: "123.6", current: 123.456, emptyClears: false, entry: e), .set(123.6))
        XCTAssertEqual(Field.resolve(typed: "123,456", current: 100, emptyClears: false, entry: e), .set(123.456),
                       "the full-precision value typed over a rounded one is stored exactly")
        XCTAssertEqual(Field.resolve(typed: "5", current: nil, emptyClears: false, entry: e), .set(5),
                       "a field with no value yet takes its first entry")
    }

    /// The caveat, pinned so it is a decision and not a surprise: while a finer value is stored, typing exactly the
    /// text the field shows is a no-op; any other spelling of that number (trailing zero, other separator) sets it.
    /// Mutation: compare the parsed numbers instead of the texts in the guard -> red on the last line.
    func testTypingExactlyTheDisplayedTextOverAFinerValueIsANoOp() {
        let e = entry(0...2)
        let shown = e.format(0.0275)               // "0,03"
        XCTAssertEqual(Field.resolve(typed: shown, current: 0.0275, emptyClears: false, entry: e), .keep)
        XCTAssertEqual(Field.resolve(typed: shown + "0", current: 0.0275, emptyClears: false, entry: e), .set(0.03),
                       "a different spelling of the number is an edit")
        XCTAssertEqual(Field.resolve(typed: "0.03", current: 0.0275, emptyClears: false, entry: e), .set(0.03))
    }

    // MARK: P10c

    private func rawPending() -> PendingLoad {
        let descriptor = PreprocessFixtureSource.descriptor
        let pending = PendingLoad(source: descriptor, reader: PreprocessFixtureSource(),
                                  url: URL(fileURLWithPath: descriptor.filePath),
                                  accessedSecurityScope: false, fileByteCount: nil)
        var draft = PreprocessDraft(origin: .rawFile)
        draft.hotPixelsEnabled = true
        pending.preprocess = draft
        return pending
    }

    /// The Threshold field's own onCommit (PreprocessSheet.hotPixelSection) writes `pending.preprocess` synchronously;
    /// a typed-but-uncommitted edit is a closure registered in `PendingEdits` until something commits it. Write must
    /// commit it before it reads the draft: the options handed to the writer carry what was typed.
    /// Mutation: remove `PendingEdits.commitAll()` from `PreprocessSheet.draftForWrite` -> red (threshold 8, the default).
    func testWriteCommitsATypedThresholdBeforeItReadsTheDraft() {
        let pending = rawPending()
        XCTAssertEqual(pending.preprocess?.hotPixelThreshold, 8, "the default the drive saw in the file")
        let editID = UUID()
        PendingEdits.register(editID) { pending.preprocess?.hotPixelThreshold = 20 }   // typed "20", no Return
        defer { PendingEdits.forget(editID) }

        let draft = PreprocessSheet.draftForWrite(pending)

        XCTAssertEqual(draft.hotPixelThreshold, 20)
        XCTAssertEqual(draft.options(for: pending.configuration).hotPixelThreshold, 20,
                       "the writer's options — what the file records")
        XCTAssertEqual(pending.preprocess?.hotPixelThreshold, 20, "the sheet's own draft agrees")
    }

    /// With nothing typed the draft is read as it is (no edit is invented), and the seam is idempotent.
    func testWriteWithNothingTypedReadsTheDraftAsItIs() {
        let pending = rawPending()
        let before = pending.preprocess
        XCTAssertEqual(PreprocessSheet.draftForWrite(pending), before)
        XCTAssertEqual(PreprocessSheet.draftForWrite(pending), before)
    }
}
