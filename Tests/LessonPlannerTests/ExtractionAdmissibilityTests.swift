import XCTest
@testable import LessonPlanner

/// Batch 051 — the invariant admissibility core, tested against hand-written proposals.
///
/// Every rejection case here is modelled on a failure that was **actually measured**, not
/// imagined: the HMH publisher document returned a real quote belonging to a sub-activity, an
/// objective that ran 1,900 characters through five sections, and a word problem in place of an
/// assessment. A verifier that cannot refuse those is not worth having.
final class ExtractionAdmissibilityTests: XCTestCase {

    private let text = """
    Lesson 1: Multiplication as Equal Groups
    Objective: Students will represent multiplication as equal groups.
    Materials: counters, chart paper, exit tickets
    Part\tTime\tTeacher and Student Actions
    Warm-Up\t5 min\tShow 3 plates with 4 counters on each plate.
    Exit Ticket\t5 min\tDraw equal groups for 4 x 3 and write the product.
    Formative Assessment: Check whether students make equal-sized groups.
    """

    private var document: SourceDocumentModel { SourceDocumentModel.build(from: text) }

    private func blockID(containing needle: String) -> String {
        document.blocks.first { $0.rawText.contains(needle) }?.id ?? "missing"
    }

    private func proposal(
        _ field: LessonFieldExtractor.Field,
        _ candidates: [ExtractedFieldCandidate],
        schemaVersion: String = ExtractionProposal.currentSchemaVersion
    ) -> ExtractionProposal {
        ExtractionProposal(
            proposalID: "test", schemaVersion: schemaVersion, producer: "test",
            candidates: [field: candidates]
        )
    }

    private func candidate(_ value: String, quoting quote: String, blocks: [String]) -> ExtractedFieldCandidate {
        ExtractedFieldCandidate(value: .text(value), citation: SourceCitation(blockIDs: blocks, quote: quote))
    }

    // MARK: - Admission

    func testAWellFormedCandidateIsAdmittedWithAComputedSpan() {
        let quote = "Objective: Students will represent multiplication as equal groups."
        let result = ExtractionAdmissibility.admit(
            proposal(.objective, [candidate("Students will represent multiplication as equal groups.",
                                            quoting: quote, blocks: [blockID(containing: "Objective:")])]),
            against: document
        )
        let admitted = result.fields[.objective]
        XCTAssertEqual(admitted?.value, .text("Students will represent multiplication as equal groups."))
        // The span is derived by the verifier, never supplied — so it must point at the quote.
        XCTAssertEqual(document.text(at: admitted!.span), quote)
    }

    /// Whitespace is collapsed before comparison because a table row is tab-separated in canonical
    /// text but any sane extractor quotes it with spaces.
    func testAQuoteInsideATableRowIsAdmitted() {
        let row = blockID(containing: "Warm-Up")
        let result = ExtractionAdmissibility.admit(
            proposal(.steps, [ExtractedFieldCandidate(
                value: .steps([LessonFieldExtractor.ExtractedStep(
                    title: "Warm-Up", notes: "Show 3 plates with 4 counters on each plate."
                )]),
                citation: SourceCitation(blockIDs: [row], quote: "Warm-Up 5 min Show 3 plates with 4 counters on each plate.")
            )]),
            against: document
        )
        XCTAssertNotNil(result.fields[.steps], "rejections: \(result.rejections)")
    }

    // MARK: - Rejection

    func testAnInventedBlockIDIsRejected() {
        let result = ExtractionAdmissibility.admit(
            proposal(.objective, [candidate("Anything", quoting: "Anything", blocks: ["b9999"])]),
            against: document
        )
        XCTAssertNil(result.fields[.objective])
        XCTAssertEqual(result.rejections[.objective], [.unknownBlockID])
    }

    func testAQuoteThatIsNotInTheCitedBlockIsRejected() {
        let result = ExtractionAdmissibility.admit(
            proposal(.objective, [candidate("Students will multiply fluently.",
                                            quoting: "Students will multiply fluently.",
                                            blocks: [blockID(containing: "Materials:")])]),
            against: document
        )
        XCTAssertEqual(result.rejections[.objective], [.quoteNotFound])
    }

    /// The check that makes fabrication impossible rather than merely unlikely: a model can cite a
    /// real sentence and return a polished paraphrase as the value.
    func testAParaphrasedValueIsRejectedEvenWithARealQuote() {
        let quote = "Objective: Students will represent multiplication as equal groups."
        let result = ExtractionAdmissibility.admit(
            proposal(.objective, [candidate("Students will model multiplication using equal groupings.",
                                            quoting: quote, blocks: [blockID(containing: "Objective:")])]),
            against: document
        )
        XCTAssertNil(result.fields[.objective])
        XCTAssertEqual(result.rejections[.objective], [.valueNotInQuote])
    }

    /// Non-adjacent blocks would let a quote span text the author never wrote next to each other.
    func testNonContiguousBlocksAreRejected() {
        let result = ExtractionAdmissibility.admit(
            proposal(.objective, [candidate("x", quoting: "x",
                                            blocks: [blockID(containing: "Objective:"),
                                                     blockID(containing: "Formative Assessment:")])]),
            against: document
        )
        XCTAssertEqual(result.rejections[.objective], [.blocksNotContiguous])
    }

    func testAnAmbiguousQuoteIsRejectedRatherThanGuessed() {
        let repeated = SourceDocumentModel.build(from: "Exit Ticket\nExit Ticket\n")
        let result = ExtractionAdmissibility.admit(
            ExtractionProposal(
                proposalID: "t", schemaVersion: "1", producer: "test",
                candidates: [.assessment: [ExtractedFieldCandidate(
                    value: .text("Exit Ticket"),
                    citation: SourceCitation(blockIDs: ["b0", "b1"], quote: "Exit Ticket")
                )]]
            ),
            against: repeated
        )
        XCTAssertEqual(result.rejections[.assessment], [.quoteAmbiguous])
    }

    /// The measured HMH failure: an objective that ran 1,900 characters through five sections.
    func testAnAbsurdlyLongValueIsRejected() {
        let long = String(repeating: "a sentence that keeps going and going. ", count: 60)
        let document = SourceDocumentModel.build(from: long)
        let result = ExtractionAdmissibility.admit(
            ExtractionProposal(
                proposalID: "t", schemaVersion: "1", producer: "test",
                candidates: [.objective: [ExtractedFieldCandidate(
                    value: .text(long.trimmingCharacters(in: .whitespaces)),
                    citation: SourceCitation(blockIDs: ["b0"], quote: long.trimmingCharacters(in: .whitespaces))
                )]]
            ),
            against: document
        )
        XCTAssertEqual(result.rejections[.objective], [.implausibleShape])
    }

    func testAnUnknownSchemaVersionRejectsEverything() {
        let result = ExtractionAdmissibility.admit(
            proposal(.objective, [candidate("x", quoting: "x", blocks: ["b0"])], schemaVersion: "99"),
            against: document
        )
        XCTAssertTrue(result.fields.isEmpty)
        XCTAssertEqual(result.rejections[.objective], [.unsupportedSchemaVersion])
    }

    func testMoreCandidatesThanAllowedIsAContractViolation() {
        let one = candidate("Students will represent multiplication as equal groups.",
                            quoting: "Objective: Students will represent multiplication as equal groups.",
                            blocks: [blockID(containing: "Objective:")])
        let result = ExtractionAdmissibility.admit(
            proposal(.objective, [one, one, one]), against: document
        )
        XCTAssertEqual(result.rejections[.objective], [.tooManyCandidates])
    }

    /// Whitespace collapsing exists for table rows, where cells are tab-separated in canonical
    /// text and quoted with spaces by any realistic extractor. It must not extend to line breaks:
    /// otherwise an extractor could quote an objective *and* the assessment beneath it as one
    /// contiguous string and have it admitted.
    func testAQuoteMatchedOnlyByCollapsingALineBreakIsRejected() {
        let objectiveBlock = blockID(containing: "Objective:")
        let materialsBlock = blockID(containing: "Materials:")
        let acrossTheBoundary = "equal groups. Materials: counters"
        let result = ExtractionAdmissibility.admit(
            proposal(.objective, [candidate(acrossTheBoundary, quoting: acrossTheBoundary,
                                            blocks: [objectiveBlock, materialsBlock])]),
            against: document
        )
        XCTAssertNil(result.fields[.objective])
        XCTAssertEqual(result.rejections[.objective], [.quoteNotFound])
    }

    /// The absurd-shape guard did nothing for `.steps`: only the count and the title were checked,
    /// so a note could be arbitrarily long provided it sat inside a large quote.
    func testAnAbsurdlyLongStepNoteIsRejected() {
        let long = String(repeating: "and then the class continues working through the task. ", count: 20)
        let document = SourceDocumentModel.build(from: "Warm-Up\t\(long)")
        let result = ExtractionAdmissibility.admit(
            ExtractionProposal(
                proposalID: "t", schemaVersion: "1", producer: "test",
                candidates: [.steps: [ExtractedFieldCandidate(
                    value: .steps([LessonFieldExtractor.ExtractedStep(
                        title: "Warm-Up", notes: long.trimmingCharacters(in: .whitespaces)
                    )]),
                    citation: SourceCitation(blockIDs: ["b0"], quote: "Warm-Up \(long)")
                )]]
            ),
            against: document
        )
        XCTAssertEqual(result.rejections[.steps], [.implausibleShape])
    }

    // MARK: - Ranking and exclusivity

    func testARejectedFirstCandidateFallsThroughToTheSecond() {
        let quote = "Objective: Students will represent multiplication as equal groups."
        let result = ExtractionAdmissibility.admit(
            proposal(.objective, [
                candidate("Invented text", quoting: "Invented text", blocks: ["b9999"]),
                candidate("Students will represent multiplication as equal groups.",
                          quoting: quote, blocks: [blockID(containing: "Objective:")])
            ]),
            against: document
        )
        XCTAssertEqual(result.fields[.objective]?.value, .text("Students will represent multiplication as equal groups."))
        XCTAssertEqual(result.rejections[.objective], [.unknownBlockID], "the first candidate's failure is still recorded")
    }

    /// Two fields resolving to the same span means the app cannot tell which is right. Keeping the
    /// higher-ranked one would import the extractor's confidence into a layer whose job is not to
    /// trust it — so both drop, and both get another turn with their remaining candidates.
    func testTwoFieldsClaimingOneSpanBothDrop() {
        let assessmentRow = blockID(containing: "Formative Assessment:")
        let quote = "Formative Assessment: Check whether students make equal-sized groups."
        let shared = candidate("Check whether students make equal-sized groups.",
                               quoting: quote, blocks: [assessmentRow])
        let result = ExtractionAdmissibility.admit(
            ExtractionProposal(
                proposalID: "t", schemaVersion: "1", producer: "test",
                candidates: [.assessment: [shared], .differentiation: [shared]]
            ),
            against: document
        )
        XCTAssertNil(result.fields[.assessment])
        XCTAssertNil(result.fields[.differentiation])
        XCTAssertEqual(result.rejections[.assessment], [.spanConflict])
        XCTAssertEqual(result.rejections[.differentiation], [.spanConflict])
    }

    /// A conflict must not blank a field that has a defensible second candidate.
    func testAConflictedFieldRecoversWithItsNextCandidate() {
        let assessmentBlock = blockID(containing: "Formative Assessment:")
        let materialsBlock = blockID(containing: "Materials:")
        let sharedQuote = "Formative Assessment: Check whether students make equal-sized groups."
        let shared = candidate("Check whether students make equal-sized groups.",
                               quoting: sharedQuote, blocks: [assessmentBlock])
        let ownMaterials = ExtractedFieldCandidate(
            value: .list(["counters", "chart paper", "exit tickets"]),
            citation: SourceCitation(blockIDs: [materialsBlock],
                                     quote: "Materials: counters, chart paper, exit tickets")
        )
        let result = ExtractionAdmissibility.admit(
            ExtractionProposal(
                proposalID: "t", schemaVersion: "1", producer: "test",
                candidates: [.assessment: [shared], .materials: [shared, ownMaterials]]
            ),
            against: document
        )
        XCTAssertNil(result.fields[.assessment], "it had nothing else to offer")
        XCTAssertEqual(result.fields[.materials]?.value, .list(["counters", "chart paper", "exit tickets"]))
    }
}
