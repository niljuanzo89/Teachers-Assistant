import XCTest
@testable import LessonPlanner

/// Batch G — reading the document's real structure instead of guessing it back from flat text.
///
/// Measured motivation: on a second document family, the parser returned the **Exit Ticket row of
/// a three-column procedure table** as the lesson's assessment on 10 of 10 lessons — confidently
/// wrong, not blank. It also missed phases whose names the vocabulary had never seen, and glued
/// the table's Time column onto every step's notes. All three came from the same cause: cell and
/// row boundaries were destroyed at extraction.
final class StructuredExtractionTests: XCTestCase {

    /// A Word table row is one line with tab-separated cells. Previously `</w:p>` was replaced
    /// first, and every cell contains a paragraph, so each cell landed on its own line.
    @MainActor
    func testATableRowSurvivesExtractionAsOneLine() {
        let xml = """
        <w:body><w:p><w:r><w:t>Lesson Procedure</w:t></w:r></w:p>\
        <w:tbl><w:tr>\
        <w:tc><w:tcPr/><w:p><w:r><w:t>Warm-Up</w:t></w:r></w:p></w:tc>\
        <w:tc><w:p><w:r><w:t>5 min</w:t></w:r></w:p></w:tc>\
        <w:tc><w:p><w:r><w:t>Show 3 plates with 4 counters.</w:t></w:r></w:p></w:tc>\
        </w:tr></w:tbl></w:body>
        """
        let lines = AppStore.flattenWordXML(xml)
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        XCTAssertEqual(lines.first, "Lesson Procedure")
        XCTAssertEqual(lines.count, 2, "the row should be one line, not three: \(lines)")
        XCTAssertEqual(
            lines.last?.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces) },
            ["Warm-Up", "5 min", "Show 3 plates with 4 counters."]
        )
    }

    /// `<w:tcPr>` starts with the same characters as `<w:tc>` and must not be counted as a cell.
    @MainActor
    func testCellPropertiesAreNotMistakenForACell() {
        let xml = "<w:tbl><w:tr><w:tc><w:tcPr><w:shd/></w:tcPr><w:p><w:r><w:t>Objective</w:t></w:r></w:p></w:tc>"
            + "<w:tc><w:p><w:r><w:t>Compare numbers.</w:t></w:r></w:p></w:tc></w:tr></w:tbl>"
        let row = SourceTextLine.parse(AppStore.flattenWordXML(xml)).first { $0.cellCount > 0 }
        XCTAssertEqual(row?.headingCell, "Objective")
        XCTAssertEqual(row?.valueCell, "Compare numbers.")
    }

    func testParsingDistinguishesProseFromRows() {
        let lines = SourceTextLine.parse("Objective: Compare numbers.\n\nWarm-Up\t5 min\tNumber talk.\t\n")
        XCTAssertEqual(lines[0], .paragraph("Objective: Compare numbers."))
        XCTAssertEqual(lines[1], .blank)
        // The trailing tab that closes a row is not a fourth column.
        XCTAssertEqual(lines[2], .tableRow(cells: ["Warm-Up", "5 min", "Number talk."]))
    }

    /// The measured defect. "Exit Ticket" is a legitimate assessment label, and the procedure
    /// table's Exit Ticket row appears *before* the real `Formative Assessment:` line — so
    /// first-match-wins returned an activity in place of the assessment on every lesson.
    ///
    /// The fix is structural, not vocabulary: a two-cell row is a label/value pair, a wider row is
    /// tabular data whose leading cell is a row heading.
    @MainActor
    func testAProcedureRowIsNotReadAsTheAssessment() {
        let text = """
        Objective: Students will represent multiplication as equal groups.
        Part\tTime\tTeacher and Student Actions
        Warm-Up\t5 min\tShow 3 plates with 4 counters on each plate and ask how many altogether.
        Exit Ticket\t5 min\tDraw equal groups for 4 x 3 and write the product with an answer sentence.
        Formative Assessment: Check whether students make equal-sized groups and connect the model to the equation.
        """
        var lesson = LessonRecord.draft(title: "Equal groups")
        AppStore.populateFields(from: text, into: &lesson, allowStructuralInference: true)

        XCTAssertEqual(
            lesson.assessmentSummary,
            "Check whether students make equal-sized groups and connect the model to the equation."
        )
        XCTAssertFalse(
            lesson.assessmentSummary.contains("Draw equal groups"),
            "returned the Exit Ticket activity in place of the assessment"
        )
    }

    /// Phases now come from the table's own rows, so a phase name the vocabulary has never seen is
    /// still found — and the Time column stays out of the body.
    @MainActor
    func testPhasesComeFromTableRowsWithoutVocabularyOrTimeBleed() {
        let text = """
        Part\tTime\tTeacher and Student Actions
        Warm-Up\t5 min\tShow 3 plates with 4 counters on each plate and ask how many there are.
        Teacher Modeling\t10 min\tModel two examples with drawings and equations for the whole class.
        Small Group Sort\t10 min\tGroups sort equation cards by the structure each one represents.
        """
        var lesson = LessonRecord.draft(title: "Equal groups")
        AppStore.populateFields(from: text, into: &lesson, allowStructuralInference: true)

        let titles = lesson.instructionalSequence.map(\.title)
        // "Teacher Modeling" and "Small Group Sort" are in no phase-name list.
        XCTAssertEqual(titles, ["Warm-Up", "Teacher Modeling", "Small Group Sort"])
        XCTAssertFalse(titles.contains("Part"), "the header row was read as a phase")

        for step in lesson.instructionalSequence {
            XCTAssertFalse(step.notes.contains("min"), "the timing column bled into \(step.title): \(step.notes)")
        }
        XCTAssertTrue(lesson.instructionalSequence.first?.notes.hasPrefix("Show 3 plates") == true)
    }

    /// The other family's shape: a two-column "Component | Plan" table. Its rows must still read as
    /// label/value pairs, and its phase rows must still read as phases.
    @MainActor
    func testTwoColumnLabelTablesStillWork() {
        let text = """
        Component\tPlan
        Objective\tRead, write, and compare whole numbers using base-ten reasoning.
        Materials\tBase-ten blocks, whiteboards, exit ticket
        Warm-Up\tNumber talk using a three-digit comparison prompt.
        Mini-Lesson\tConnect concrete models, drawings, and numbers.
        Assessment\tUse a 3-question exit ticket to identify place-value needs.
        Timing\t60 minutes: 8 number talk, 12 launch, 25 guided.
        """
        var lesson = LessonRecord.draft(title: "Place value review")
        AppStore.populateFields(from: text, into: &lesson, allowStructuralInference: true)

        XCTAssertEqual(lesson.objective, "Read, write, and compare whole numbers using base-ten reasoning.")
        XCTAssertEqual(lesson.materials, ["Base-ten blocks", "whiteboards", "exit ticket"])
        XCTAssertEqual(lesson.assessmentSummary, "Use a 3-question exit ticket to identify place-value needs.")
        XCTAssertEqual(lesson.instructionalSequence.map(\.title), ["Warm-Up", "Mini-Lesson"])
        XCTAssertFalse(
            lesson.instructionalSequence.contains { $0.notes.contains("60 minutes") },
            "the timing row was absorbed into a phase"
        )
    }
}
