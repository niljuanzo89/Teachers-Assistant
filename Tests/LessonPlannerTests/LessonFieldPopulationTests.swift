import XCTest
@testable import LessonPlanner

/// Batch D — populating lesson content fields from each lesson's own span.
///
/// The bar here is **correct-to-source**, not fields-non-empty. A version of this that filled
/// every lesson with the whole week's text would pass a non-empty check and still be the bug
/// it is meant to prevent, so every assertion below names the day it expects *and* the day it
/// must not have picked up.
///
/// The fixture mirrors the shape measured in the owner's sample packet — a two-column
/// "Component / Plan" table, flattened by DOCX extraction into a label line followed by a value
/// line — without reproducing any of that material.
final class LessonFieldPopulationTests: XCTestCase {

    private let weekText = """
    Weekly Lesson Plans

    Monday: Place value review
    Component
    Plan
    Objective
    Compare three-digit numbers using base-ten reasoning.
    Materials
    Base-ten blocks, whiteboards, exit ticket
    Warm-Up
    Number talk comparing two three-digit numbers.
    Mini-Lesson
    Connect models, drawings, and written numerals.
    Independent Practice
    Six practice problems with one challenge item.
    Assessment
    Three-question exit ticket on regrouping.
    Timing
    60 minutes: 8 warm-up, 12 mini-lesson, 25 guided, 10 independent, 5 share.
    Differentiation
    Offer manipulatives; extend with four-digit comparisons.

    Tuesday: Rounding to the nearest ten
    Objective
    Round two-digit numbers to the nearest ten on a number line.
    Materials
    Open number lines, counters
    Warm-Up
    Count by tens from a non-zero start.
    Mini-Lesson
    Locate a number between two benchmark tens.
    Independent Practice
    Eight rounding problems.
    Assessment
    Two-question check on midpoint rounding.
    Differentiation
    Provide pre-marked number lines; extend to hundreds.
    """

    @MainActor
    private func makeStore() throws -> (AppStore, ImportedSource, LocalRepository) {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = LocalRepository(rootURL: directory)
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Population", workspaceReference: FileReference(url: directory)
        ))
        let source = ImportedSource(
            id: UUID(), reference: FileReference(url: URL(fileURLWithPath: "/tmp/week.docx")),
            extractionMethod: .embeddedText, confidence: nil, extractedText: weekText,
            reviewStatus: .reviewed, importedAt: .now, updatedAt: .now
        )
        try repository.saveImportedSources([source])
        return (AppStore(repository: repository), source, repository)
    }

    /// A lesson populated from Monday's span carries Monday's values and none of Tuesday's.
    @MainActor
    func testPopulationIsScopedToTheLessonsOwnDay() throws {
        let (store, source, _) = try makeStore()
        let spans = LessonSourceSpanDetector.detect(in: weekText)
        XCTAssertEqual(spans.count, 2, "fixture should split into exactly two days")

        guard var monday = spans.first(where: { $0.lessonTitle.contains("Place value") }),
              let mondayText = monday.resolvedText(in: source.extractedText) else {
            return XCTFail("Monday span not detected")
        }
        monday.sourceID = source.id

        var lesson = LessonRecord.draft(title: "Place value review")
        lesson.sourceSpan = monday
        lesson.sourceTextSnapshot = mondayText
        let filled = store.fillEmptyLessonFieldsFromSource(lesson)

        XCTAssertEqual(filled.objective, "Compare three-digit numbers using base-ten reasoning.")
        XCTAssertEqual(filled.assessmentSummary, "Three-question exit ticket on regrouping.")
        // Split into items, and — the point of the phase-heading terminator — stopping before
        // the Warm-Up row rather than absorbing the rest of the lesson body as "materials".
        XCTAssertEqual(filled.materials, ["Base-ten blocks", "whiteboards", "exit ticket"])
        XCTAssertTrue(filled.differentiationSummary.contains("Offer manipulatives"))

        // The real failure mode is not an empty field, it is a plausible field belonging to
        // another day. Assert the absence explicitly.
        XCTAssertFalse(filled.objective.contains("nearest ten"), "picked up Tuesday's objective")
        XCTAssertFalse(filled.assessmentSummary.contains("midpoint"), "picked up Tuesday's assessment")
        XCTAssertFalse(filled.differentiationSummary.contains("pre-marked"), "picked up Tuesday's differentiation")

        // "Timing" names no field this extractor reads, and is not a phase heading either, so
        // without it in the terminator vocabulary the assessment absorbs the whole timing row.
        XCTAssertFalse(filled.assessmentSummary.contains("60 minutes"), "assessment absorbed the timing row")
    }

    /// Steps come from phase headings, which no label in the extractor's vocabulary matches —
    /// this is the one field the measurement showed needs structural inference.
    @MainActor
    func testInstructionalStepsComeFromPhaseHeadingsAndAreMarkedInferred() throws {
        let (store, source, _) = try makeStore()
        guard var monday = LessonSourceSpanDetector.detect(in: weekText)
            .first(where: { $0.lessonTitle.contains("Place value") }),
              let mondayText = monday.resolvedText(in: source.extractedText) else {
            return XCTFail("Monday span not detected")
        }
        monday.sourceID = source.id

        XCTAssertTrue(
            LessonFieldExtractor.extract(from: mondayText).steps.isEmpty,
            "premise: labels alone find no steps in this shape — if this starts passing, the "
                + "inference fallback below is no longer the thing under test"
        )

        var lesson = LessonRecord.draft(title: "Place value review")
        lesson.sourceSpan = monday
        lesson.sourceTextSnapshot = mondayText
        let filled = store.fillEmptyLessonFieldsFromSource(lesson)

        let titles = filled.instructionalSequence.map(\.title)
        XCTAssertTrue(titles.contains { $0.localizedCaseInsensitiveContains("warm-up") }, "got \(titles)")
        XCTAssertTrue(titles.contains { $0.localizedCaseInsensitiveContains("mini-lesson") }, "got \(titles)")
        XCTAssertEqual(
            filled.inferredFields, [.steps],
            "steps were worked out from structure, so the record must say so — and nothing else "
                + "may be marked inferred, since the other fields came from explicit labels"
        )
    }

    /// A teacher's own wording is never replaced by the document's.
    @MainActor
    func testExistingTeacherValuesAreNotOverwritten() throws {
        let (store, source, _) = try makeStore()
        guard var monday = LessonSourceSpanDetector.detect(in: weekText)
            .first(where: { $0.lessonTitle.contains("Place value") }),
              let mondayText = monday.resolvedText(in: source.extractedText) else {
            return XCTFail("Monday span not detected")
        }
        monday.sourceID = source.id

        var lesson = LessonRecord.draft(title: "Place value review")
        lesson.sourceSpan = monday
        lesson.sourceTextSnapshot = mondayText
        lesson.objective = "My own objective, written by hand."
        let filled = store.fillEmptyLessonFieldsFromSource(lesson)

        XCTAssertEqual(filled.objective, "My own objective, written by hand.")
        XCTAssertFalse(filled.assessmentSummary.isEmpty, "untouched fields should still fill")
    }

    /// Population re-resolves the span against the document's current text, so a re-import that
    /// shifts byte offsets still lands on the right day rather than on a stale slice.
    @MainActor
    func testPopulationFollowsTheSpanWhenTheDocumentShifts() throws {
        let (_, _, repository) = try makeStore()
        guard var monday = LessonSourceSpanDetector.detect(in: weekText)
            .first(where: { $0.lessonTitle.contains("Place value") }) else {
            return XCTFail("Monday span not detected")
        }

        let shifted = "Header added on re-import\nSchool year 2026\n\n" + weekText
        let shiftedSource = ImportedSource(
            id: UUID(), reference: FileReference(url: URL(fileURLWithPath: "/tmp/week.docx")),
            extractionMethod: .embeddedText, confidence: nil, extractedText: shifted,
            reviewStatus: .reviewed, importedAt: .now, updatedAt: .now
        )
        try repository.saveImportedSources([shiftedSource])
        let reloaded = AppStore(repository: repository)
        monday.sourceID = shiftedSource.id

        var lesson = LessonRecord.draft(title: "Place value review")
        lesson.sourceSpan = monday
        // Deliberately stale: the snapshot still holds the pre-shift slice.
        lesson.sourceTextSnapshot = "Objective\nStale text that should not be used."
        let filled = reloaded.fillEmptyLessonFieldsFromSource(lesson)

        XCTAssertEqual(filled.objective, "Compare three-digit numbers using base-ten reasoning.")
        XCTAssertFalse(filled.objective.contains("Stale"), "used the stale snapshot instead of the span")
    }
}
