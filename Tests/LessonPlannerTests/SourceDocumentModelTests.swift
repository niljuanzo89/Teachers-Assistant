import XCTest
@testable import LessonPlanner

/// Batch H — the addressable document model the extractor contract will answer against.
///
/// This layer adds identity, offsets, and (eventually) section ancestry. Its acceptance criterion
/// is that it changes **nothing**: the deterministic parser sees exactly the same sequence of
/// lines it saw before, so any later difference in extraction is attributable to the extractor
/// rather than to this.
final class SourceDocumentModelTests: XCTestCase {

    private let sample = """
    Lesson 1: Multiplication as Equal Groups
    Objective: Students will represent multiplication as equal groups.

    Part\tTime\tTeacher and Student Actions
    Warm-Up\t5 min\tShow 3 plates with 4 counters on each plate.
    • Ask how many counters there are altogether.
    1. Record the repeated addition sentence.
    """

    func testBlocksAreOneToOneWithLinesIncludingBlanks() {
        let model = SourceDocumentModel.build(from: sample)
        XCTAssertEqual(
            model.lines, SourceTextLine.parse(sample),
            "the parser must see exactly what it saw before this layer existed"
        )
        XCTAssertEqual(model.blocks.count, sample.components(separatedBy: .newlines).count)
    }

    func testEveryBlockRangePointsAtItsOwnRawText() {
        let model = SourceDocumentModel.build(from: sample)
        for block in model.blocks {
            XCTAssertEqual(
                model.text(at: block.range), block.rawText,
                "block \(block.id) claims a range that does not hold its text"
            )
        }
    }

    /// The distinction that makes citation checking possible: a row's canonical text is
    /// tab-separated, while its display form joins cells with spaces. Validating against the
    /// wrong one would fail on every table row in a document.
    func testATableRowKeepsTabsInRawTextAndCellsInItsLine() {
        let model = SourceDocumentModel.build(from: sample)
        guard let row = model.blocks.first(where: { $0.kind == .tableRow && $0.rawText.contains("Warm-Up") }) else {
            return XCTFail("no table row found")
        }
        XCTAssertTrue(row.rawText.contains("\t"), "raw text lost the cell separators")
        XCTAssertEqual(row.line.headingCell, "Warm-Up")
        XCTAssertEqual(row.line.valueCell, "Show 3 plates with 4 counters on each plate.")
        XCTAssertFalse(row.line.text.contains("\t"), "display text should be joined, not tabbed")
    }

    func testKindsAreAssigned() {
        let model = SourceDocumentModel.build(from: sample)
        let kinds = Dictionary(grouping: model.blocks, by: \.kind).mapValues(\.count)
        XCTAssertEqual(kinds[.blank], 1)
        XCTAssertEqual(kinds[.tableRow], 2)
        XCTAssertEqual(kinds[.listItem], 2, "a bulleted and a numbered line")
        XCTAssertNotNil(kinds[.paragraph])
    }

    func testBlankBlocksAreNotOfferedAsEvidence() {
        let model = SourceDocumentModel.build(from: sample)
        XCTAssertFalse(model.citableBlocks.contains { $0.kind == .blank })
        XCTAssertEqual(model.citableBlocks.count, model.blocks.count - 1)
    }

    /// IDs are ordinal rather than content-derived precisely because real documents repeat
    /// themselves — two identical rows must remain separately addressable.
    func testRepeatedTextStaysSeparatelyAddressable() {
        let model = SourceDocumentModel.build(from: "Exit Ticket\nExit Ticket\n")
        XCTAssertEqual(model.blocks[0].rawText, model.blocks[1].rawText)
        XCTAssertNotEqual(model.blocks[0].id, model.blocks[1].id)
        XCTAssertNotEqual(model.blocks[0].range, model.blocks[1].range)
    }

    func testLookupByIDAndOutOfRangeSafety() {
        let model = SourceDocumentModel.build(from: sample)
        XCTAssertEqual(model.block(id: "b0")?.rawText, "Lesson 1: Multiplication as Equal Groups")
        XCTAssertNil(model.block(id: "b999"))
        // A stale or invented citation must be refused, not trap. (An inverted range needs no
        // test: `Range` cannot be constructed with lowerBound > upperBound.)
        XCTAssertNil(model.text(at: 0..<(sample.count + 50)))
        XCTAssertNil(model.text(at: (sample.count + 10)..<(sample.count + 20)))
    }

    /// Codex caught this in review. Swift counts `\r\n` as one `Character`, but
    /// `components(separatedBy: .newlines)` splits on unicode scalars and treats it as two — so
    /// Windows-authored text produced a phantom empty line and pushed every later block's range
    /// past the end of the document. It looks fine until a citation is checked.
    func testCRLFTextProducesCorrectBlocksAndOffsets() {
        let model = SourceDocumentModel.build(from: "Objective: Compare numbers.\r\nMaterials: cubes\r\n")

        XCTAssertEqual(model.blocks.first?.rawText, "Objective: Compare numbers.")
        XCTAssertEqual(model.citableBlocks.count, 2, "a phantom line appeared: \(model.blocks.map(\.rawText))")
        for block in model.blocks {
            XCTAssertEqual(model.text(at: block.range), block.rawText, "block \(block.id)")
        }
        XCTAssertFalse(model.canonicalText.contains("\r"))
    }

    /// The pressure case for the admissibility layer: a citation quotes part of a wide table row,
    /// so the verifier has to locate a value *inside* a block rather than accept the whole block.
    func testAQuoteCanBeLocatedInsideAWideTableRow() {
        let model = SourceDocumentModel.build(
            from: "Part\tTime\tActions\nWarm-Up\t5 min\tShow 3 plates with 4 counters.\n"
        )
        guard let row = model.citableBlocks.last else { return XCTFail("no row") }
        let quote = "Show 3 plates with 4 counters."

        // Present in the raw text, and locatable at a real offset within the document.
        XCTAssertTrue(row.rawText.contains(quote))
        guard let local = row.rawText.range(of: quote) else { return XCTFail("quote not found") }
        let start = row.range.lowerBound + row.rawText.distance(from: row.rawText.startIndex, to: local.lowerBound)
        XCTAssertEqual(model.text(at: start..<(start + quote.count)), quote)

        // And the row's other cells are *not* the value — the reason a block ID alone is not a
        // sufficient citation.
        XCTAssertEqual(row.line.valueCell, quote)
        XCTAssertNotEqual(row.line.headingCell, quote)
    }

    /// Offsets have to survive multi-byte characters, since real curriculum text carries curly
    /// quotes, dashes and fractions.
    func testOffsetsSurviveNonASCIIText() {
        let text = "Objective: “Compare” — using ½ and ¼.\nMaterials: fraction strips\n"
        let model = SourceDocumentModel.build(from: text)
        for block in model.blocks {
            XCTAssertEqual(model.text(at: block.range), block.rawText, "block \(block.id)")
        }
    }
}
