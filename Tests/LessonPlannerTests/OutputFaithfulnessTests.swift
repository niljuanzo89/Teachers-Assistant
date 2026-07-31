import XCTest
@testable import LessonPlanner

/// Batch F — what a teacher actually receives.
///
/// Earlier batches proved fields get *populated*. These prove the generated plan, guide, and deck
/// carry this lesson's content and nothing else: no adjacent day's material, no same-source
/// over-capture, and no section the source never supported.
final class OutputFaithfulnessTests: XCTestCase {

    /// Two adjacent days, each carrying a token that appears nowhere else, so a bleed is
    /// unmistakable rather than a judgment call.
    private let weekText = """
    Weekly Lesson Plans

    Monday: Place value review
    Objective
    Compare three-digit numbers using zircon reasoning.
    Materials
    Base-ten blocks, whiteboards
    Warm-Up
    Number talk about zircon comparisons.
    Independent Practice
    Six zircon practice problems.
    Assessment
    Three-question zircon exit ticket.
    Timing
    60 minutes: 8 warm-up, 25 guided, 15 independent.
    Differentiation
    Offer zircon manipulatives.

    Tuesday: Rounding to the nearest ten
    Objective
    Round two-digit numbers using marmoset number lines.
    Materials
    Marmoset counters
    Warm-Up
    Count by tens with marmoset cards.
    Independent Practice
    Eight marmoset rounding problems.
    Assessment
    Two-question marmoset check.
    Differentiation
    Provide pre-marked marmoset lines.
    """

    @MainActor
    private func mondayLesson() throws -> LessonRecord {
        let spans = LessonSourceSpanDetector.detect(in: weekText)
        XCTAssertEqual(spans.count, 2, "fixture should split into exactly two days")
        guard let monday = spans.first(where: { $0.lessonTitle.contains("Place value") }),
              let slice = monday.resolvedText(in: weekText) else {
            throw XCTSkip("Monday span not detected")
        }
        var lesson = LessonRecord.draft(title: monday.lessonTitle)
        lesson.sourceSpan = monday
        lesson.sourceTextSnapshot = slice
        AppStore.populateFields(from: slice, into: &lesson, allowStructuralInference: true)
        lesson.status = .approved
        return lesson
    }

    @MainActor
    private func deckText(for lesson: LessonRecord) async throws -> String {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "deck.pptx")
        try await NativePowerPointExporter.generate(lesson: lesson, destination: url)
        return String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }

    /// The defect that motivated this batch: a phase body ran to the next *phase heading* only, so
    /// the last step absorbed the assessment, timing, and differentiation rows beneath it — and the
    /// rendered plan then printed all three twice.
    @MainActor
    func testInferredStepNotesStopAtTheNextLabeledRow() throws {
        let lesson = try mondayLesson()
        let notes = lesson.instructionalSequence.map(\.notes).joined(separator: " ")

        XCTAssertFalse(notes.contains("exit ticket"), "a step absorbed the assessment row: \(notes)")
        XCTAssertFalse(notes.contains("60 minutes"), "a step absorbed the timing row: \(notes)")
        XCTAssertFalse(notes.contains("manipulatives"), "a step absorbed the differentiation row: \(notes)")
        XCTAssertTrue(notes.contains("Six zircon practice problems"), "the step lost its own body")
    }

    /// Every generated surface carries this lesson's day and none of the next one's.
    @MainActor
    func testGeneratedOutputsCarryThisDayAndNotTheNext() async throws {
        let lesson = try mondayLesson()
        let surfaces: [(String, String)] = [
            ("lesson plan", LessonPlanRenderer.renderHTML(for: lesson)),
            ("differentiation guide", LessonPlanRenderer.renderDifferentiationGuideHTML(for: lesson)),
            ("deck", try await deckText(for: lesson))
        ]

        for (name, body) in surfaces {
            XCTAssertTrue(body.contains("zircon"), "\(name) lost this lesson's own content")
            // "marmoset" appears only in Tuesday's span. Any occurrence is contamination.
            XCTAssertFalse(body.contains("marmoset"), "\(name) leaked the adjacent day's content")
        }
    }

    /// An objective is a teacher's goal, not a task a child can do. Substituting it for a missing
    /// student prompt produced a worksheet that looked finished and was not usable.
    @MainActor
    func testTheStudentHandoutIsOmittedRatherThanFilledWithTheObjective() throws {
        var lesson = try mondayLesson()
        lesson.printableResourcePrompt = nil
        let guide = LessonPlanRenderer.renderDifferentiationGuideHTML(for: lesson)

        XCTAssertFalse(guide.contains("Student Practice"), "printed a handout with no prompt to put on it")
        // Deliberately not asserting the objective is absent from the whole document: it belongs
        // in the guide's own "Learning objective" section. The claim is that no *handout* was
        // fabricated around it.
        XCTAssertFalse(guide.contains("<strong>Prompt:</strong>"), "rendered a student prompt with nothing to say")
        XCTAssertTrue(guide.contains("Compare three-digit numbers"), "the objective section should still print")

        lesson.printableResourcePrompt = "Compare 412 and 421. Show your reasoning."
        let withPrompt = LessonPlanRenderer.renderDifferentiationGuideHTML(for: lesson)
        XCTAssertTrue(withPrompt.contains("Student Practice"), "a real prompt should still print")
        XCTAssertTrue(withPrompt.contains("Compare 412 and 421"))
    }

    /// Boilerplate that names every category a lesson *might* differentiate along asserts nothing
    /// about this lesson, and reads as content.
    @MainActor
    func testTheGuideCarriesNoGenericBoilerplate() throws {
        let guide = LessonPlanRenderer.renderDifferentiationGuideHTML(for: try mondayLesson())
        XCTAssertFalse(guide.contains("whatever applies to this lesson"))
        XCTAssertFalse(guide.contains("Access and support, language and vocabulary"))
    }
}
