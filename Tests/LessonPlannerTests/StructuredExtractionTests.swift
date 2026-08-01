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

    /// Phases come from **one** table, not from wide rows collected across the document. Without
    /// this, an unrelated grid — a pacing table, a materials matrix — becomes the lesson's
    /// instructional sequence.
    @MainActor
    func testPhasesComeFromOneTableNotFromWideRowsAnywhere() {
        let text = """
        Unit pacing overview
        Lesson\tDate\tFocus
        1\tAugust 3\tMultiplication as equal groups, using counters and drawings to build meaning.
        2\tAugust 4\tArrays as a model, connecting rows and columns to the multiplication equation.
        3\tAugust 5\tNumber lines, using equal jumps to represent repeated addition as multiplying.

        Lesson Procedure
        Part\tTime\tTeacher and Student Actions
        Warm-Up\t5 min\tShow 3 plates with 4 counters on each plate and ask how many altogether.
        Teacher Modeling\t10 min\tModel two examples with drawings and equations for the whole class.
        Guided Practice\t10 min\tStudents use counters to model each product and record an equation.
        Exit Ticket\t5 min\tDraw equal groups for 4 x 3 and write the product in a sentence.
        """
        var lesson = LessonRecord.draft(title: "Equal groups")
        AppStore.populateFields(from: text, into: &lesson, allowStructuralInference: true)

        XCTAssertEqual(
            lesson.instructionalSequence.map(\.title),
            ["Warm-Up", "Teacher Modeling", "Guided Practice", "Exit Ticket"]
        )
        XCTAssertFalse(
            lesson.instructionalSequence.contains { $0.title == "1" || $0.title == "2" },
            "the pacing table was read as the instructional sequence"
        )
    }

    /// A header row is recognised by being shorter than its own column's content, not by a fixed
    /// character count — so a terse procedure table keeps every phase.
    @MainActor
    func testATerseProcedureTableKeepsAllItsPhases() {
        let text = """
        Step\tMin\tWhat happens
        Warm-Up\t5\tNumber talk.
        Launch\t5\tName the structure.
        Practice\t10\tSolve six problems.
        """
        var lesson = LessonRecord.draft(title: "Terse")
        AppStore.populateFields(from: text, into: &lesson, allowStructuralInference: true)

        // Every cell here is far under the 40-character threshold the first implementation used;
        // that version dropped these rows entirely.
        XCTAssertEqual(lesson.instructionalSequence.map(\.title), ["Warm-Up", "Launch", "Practice"])
    }

    /// Predicted by the review panel and confirmed as a live defect before fixing: a column of
    /// bare numbers matched the duration test, so a pacing grid's "Lesson" column of 1, 2, 3 read
    /// as timing. Row count alone was doing the discriminating, and a longer grid would have won —
    /// naming the phases "1", "2", "3".
    func testAPacingGridIsNotMistakenForATimedProcedure() {
        let pacing = SourceTableRun.runs(in: SourceTextLine.parse("""
        Lesson\tDate\tFocus
        1\tAugust 3\tMultiplication as equal groups, using counters to build meaning.
        2\tAugust 4\tArrays as a model, connecting rows and columns to the equation.
        3\tAugust 5\tNumber lines, using equal jumps to represent repeated addition.
        """)).first
        XCTAssertEqual(pacing?.hasDurationColumn, false)

        // Bare numbers still count when the column's own header names time.
        let timed = SourceTableRun.runs(in: SourceTextLine.parse("""
        Step\tMin\tWhat happens
        Warm-Up\t5\tNumber talk about equal groups.
        Launch\t5\tName the structure for the class.
        Practice\t10\tSolve six problems together.
        """)).first
        XCTAssertEqual(timed?.hasDurationColumn, true)
    }

    /// Also predicted by the panel: an abbreviated column name ends in a period, so testing every
    /// cell for sentence punctuation rejected a real header and promoted "Part" to a phase.
    func testAnAbbreviatedColumnNameIsStillAHeader() {
        let run = SourceTableRun.runs(in: SourceTextLine.parse("""
        Part\tEst. Time.\tTeacher and Student Actions
        Warm-Up\t5 min\tShow 3 plates with 4 counters and ask how many altogether.
        Launch\t5 min\tName the structure and record the equation for the class.
        Practice\t10 min\tStudents model each product and record an equation for it.
        """)).first

        XCTAssertEqual(run?.headerCells?.first, "Part")
        XCTAssertEqual(run?.dataRows.first?.first, "Warm-Up", "the header row was read as a phase")
        XCTAssertEqual(run?.dataRows.count, 3)
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
