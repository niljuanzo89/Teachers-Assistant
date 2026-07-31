import XCTest
@testable import LessonPlanner

/// Acceptance is *correct-to-slice*, not fields-non-empty. A lesson that receives another day's
/// content is worse than one that receives nothing, because the teacher has no way to detect it.
final class LessonSourceSpanTests: XCTestCase {
    private let weekText = """
    Math: Sample Lesson Plans
    Monday: Place value review
    Component
    Plan
    Objective: Read, write, and compare whole numbers.
    Tuesday: Rounding in context
    Component
    Plan
    Objective: Round multi-digit numbers.
    Wednesday: Addition strategies
    Component
    Plan
    Objective: Add multi-digit numbers.
    """

    func testDetectsOneSpanPerWeekdayHeading() {
        let spans = LessonSourceSpanDetector.detect(in: weekText)
        XCTAssertEqual(spans.count, 3)
        XCTAssertEqual(spans.map(\.lessonTitle), ["Place value review", "Rounding in context", "Addition strategies"])
    }

    func testEachSpanContainsOnlyItsOwnDay() {
        let spans = LessonSourceSpanDetector.detect(in: weekText)
        let monday = try! XCTUnwrap(spans.first)
        let text = try! XCTUnwrap(monday.resolvedText(in: weekText))
        XCTAssertTrue(text.contains("Place value review"))
        XCTAssertTrue(text.contains("Read, write, and compare whole numbers"))
        XCTAssertFalse(text.contains("Rounding in context"), "cross-day contamination is the failure this exists to prevent")
        XCTAssertFalse(text.contains("Round multi-digit numbers"))
    }

    func testLastSpanRunsToTheEndOfTheDocument() {
        let spans = LessonSourceSpanDetector.detect(in: weekText)
        let last = try! XCTUnwrap(spans.last)
        let text = try! XCTUnwrap(last.resolvedText(in: weekText))
        XCTAssertTrue(text.contains("Add multi-digit numbers"))
    }

    func testDocumentWithNoWeekdayHeadingsYieldsNoSpans() {
        // The owner's 316 single-page PDFs look like this: already smaller than one lesson, with
        // nothing to split. No spans must mean no population, not a guess.
        XCTAssertTrue(LessonSourceSpanDetector.detect(in: """
        Problem of the Day
        Which is the area of the figure?
        A. 7 square units B. 18 square units
        """).isEmpty)
    }

    func testStaleOffsetsAreRecomputedRatherThanReturningTheWrongSlice() {
        // Offsets are a cached derivation; re-extraction can shift them. The heading is the durable
        // identity, so a span whose offsets no longer point at its heading must rescan.
        var span = try! XCTUnwrap(LessonSourceSpanDetector.detect(in: weekText).first)
        span.startOffset = 0   // now points at "Math: Sample Lesson Plans", not the Monday heading
        span.endOffset = 12
        let text = try! XCTUnwrap(span.resolvedText(in: weekText))
        XCTAssertTrue(text.hasPrefix("Monday: Place value review"), "stale offsets must not silently yield the wrong slice")
    }

    func testSpanSurvivesPersistence() throws {
        let span = LessonSourceSpan(
            sourceID: UUID(), sourceDisplayName: "04 Math.docx",
            headingLabel: "Monday: Place value review", lessonTitle: "Place value review",
            startOffset: 26, endOffset: 140
        )
        var lesson = LessonRecord.draft(title: "Place value review")
        lesson.sourceSpan = span
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(LessonRecord.self, from: try encoder.encode(lesson))
        XCTAssertEqual(decoded.sourceSpan, span)
    }

    func testLessonsSavedBeforeSpansExistedStillDecode() throws {
        let legacy = """
        {"id":"3C3C3C3C-0000-4000-8000-000000000001","status":"approved","title":"Legacy",
         "subject":"","gradeOrAgeRange":"","objective":"","sourceReferences":[],
         "instructionalSequence":[],"materials":[],"differentiationSummary":"",
         "assessmentSummary":"","createdAt":"2026-07-01T12:00:00Z","updatedAt":"2026-07-01T12:00:00Z"}
        """
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let lesson = try decoder.decode(LessonRecord.self, from: Data(legacy.utf8))
        XCTAssertNil(lesson.sourceSpan)
    }
}
