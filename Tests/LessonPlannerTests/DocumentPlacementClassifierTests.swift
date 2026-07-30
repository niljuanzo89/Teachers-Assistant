import XCTest
@testable import LessonPlanner

/// All fixtures here are generic and written by hand. Real curriculum content is never used in
/// tests, per the standing product boundary.
final class DocumentPlacementClassifierTests: XCTestCase {
    private func classify(_ name: String, _ text: String) -> DocumentPlacementClassification {
        DocumentPlacementClassifier.classify(displayName: name, extractedText: text)
    }

    private let lessonBody = """
    Understand Equivalent Fractions
    Students will be able to compare two fractions with unlike denominators using models.
    Warm-Up (5 min)
    Review benchmark fractions with a quick check.
    Explore Together (15 min)
    Model comparing two fractions using fraction strips.
    Independent Work (10 min)
    Students compare three pairs on their own.
    """

    func testLessonShapedDocumentIsPlaceable() {
        let result = classify("unit3-lesson5.pdf", lessonBody)
        XCTAssertEqual(result.eligibility, .placeableLesson)
        XCTAssertTrue(result.eligibility.canOccupyScheduleBlock)
        XCTAssertNil(result.differentiationRole)
    }

    func testFileNameArtifactMarkerOutranksLessonShape() {
        // The bias this classifier is built around: a reteach sheet may well contain
        // "Students will…", but a document named as reteach material must never be schedulable.
        let result = classify("g5-m3-lesson5-reteach.pdf", lessonBody)
        XCTAssertEqual(result.eligibility, .supportingMaterial)
        XCTAssertEqual(result.differentiationRole, .support)
        XCTAssertFalse(result.eligibility.canOccupyScheduleBlock)
    }

    func testSmallGroupOptionsPageRoutesToSupport() {
        let result = classify("page-114.pdf", """
        Small-Group Options
        Use these teacher-guided activities with pulled small groups at the teacher table.
        Materials: counters
        """)
        XCTAssertEqual(result.eligibility, .supportingMaterial)
        XCTAssertEqual(result.differentiationRole, .support)
    }

    func testExitTicketRoutesToAssessment() {
        let result = classify("page-118.pdf", """
        Exit Ticket
        What is the volume of a rectangular prism that is 5 units long, 4 wide, and 3 high?
        Show your reasoning in one sentence so your teacher can check your thinking today.
        """)
        XCTAssertEqual(result.eligibility, .supportingMaterial)
        XCTAssertEqual(result.differentiationRole, .assessment)
    }

    func testWarmUpProblemRoutesToPractice() {
        let result = classify("page-101.pdf", """
        Problem of the Day
        Which is the area of the figure shown below? Choose the best answer from the options.
        A. 7 square units B. 18 square units C. 20 square units D. 21 square units
        """)
        XCTAssertEqual(result.eligibility, .supportingMaterial)
        XCTAssertEqual(result.differentiationRole, .practice)
    }

    func testUnreadableDocumentIsInertAndNotSchedulable() {
        let result = classify("scan001.pdf", "  page 14  ")
        XCTAssertEqual(result.eligibility, .inert)
        XCTAssertFalse(result.eligibility.canOccupyScheduleBlock)
        XCTAssertTrue(result.rationale.contains("No usable text"))
    }

    func testReadableButUnrecognizableDocumentIsInert() {
        let result = classify("front-matter.pdf", String(repeating: "Table of contents entry. ", count: 12))
        XCTAssertEqual(result.eligibility, .inert)
        XCTAssertFalse(result.eligibility.canOccupyScheduleBlock)
    }

    func testPlanningDocumentKeepsItsOwnPathway() {
        let result = classify("year-at-a-glance.pdf", """
        Pacing Guide
        Scope and sequence for the year, with instructional days per unit listed by quarter.
        """)
        XCTAssertEqual(result.eligibility, .planningDocument)
        XCTAssertFalse(result.eligibility.canOccupyScheduleBlock)
    }

    func testEveryRationaleExplainsItself() {
        // An automated decision that excludes a document from the planner has to be able to
        // tell the teacher why, so no classification may return an empty rationale.
        for (name, text) in [("a-reteach.pdf", lessonBody), ("b.pdf", lessonBody), ("c.pdf", "x")] {
            XCTAssertFalse(classify(name, text).rationale.isEmpty)
        }
    }

    func testLessonListIsRecognizedAsASequenceNotALessonOrJunk() {
        // A weekly content packet teaches nothing itself but sets the sequence. An earlier
        // version of this classifier had no such category and binned these as `inert`, which
        // would have disabled the app's primary content-import path.
        let result = classify("04 Math Unit Lessons.docx", """
        Unit 1: Place Value
        Monday: Place value review
        Tuesday: Rounding in context
        Wednesday: Addition strategies
        Thursday: Problem solving
        Friday: Subtraction strategies
        """)
        XCTAssertEqual(result.eligibility, .lessonSequence)
        XCTAssertFalse(result.eligibility.canOccupyScheduleBlock, "a list of lessons is not itself a lesson")
        XCTAssertTrue(result.eligibility.canContributeLessonSequence)
    }

    func testSupportingMaterialAndInertNeverContributeALessonSequence() {
        XCTAssertFalse(classify("lesson5-reteach.pdf", lessonBody).eligibility.canContributeLessonSequence)
        XCTAssertFalse(classify("scan.pdf", " ").eligibility.canContributeLessonSequence)
        // A scope-and-sequence legitimately yields a sequence even though it fills no block.
        let scope = classify("Scope and Sequence.docx", "Scope and Sequence\nUnit 1: Fractions\nLesson 1: Equivalent fractions")
        XCTAssertEqual(scope.eligibility, .planningDocument)
        XCTAssertTrue(scope.eligibility.canContributeLessonSequence)
    }

    // MARK: - Attachment key

    func testLessonKeyParsesModuleAndLessonFromFileName() {
        let key = DocumentPlacementClassifier.lessonKey(displayName: "g5_module3_lesson7_practice.pdf", extractedText: "")
        XCTAssertEqual(key?.module, 3)
        XCTAssertEqual(key?.lesson, 7)
    }

    func testLessonKeyFallsBackToDocumentText() {
        let key = DocumentPlacementClassifier.lessonKey(
            displayName: "page-88.pdf", extractedText: "Module 5 • Lesson 2\nUnderstand Volume")
        XCTAssertEqual(key?.module, 5)
        XCTAssertEqual(key?.lesson, 2)
    }

    func testLessonKeyAcceptsLessonOnlyIdentifier() {
        let key = DocumentPlacementClassifier.lessonKey(displayName: "lesson-4-exit-ticket.pdf", extractedText: "")
        XCTAssertNil(key?.module)
        XCTAssertEqual(key?.lesson, 4)
    }

    func testLessonKeyIsNilRatherThanGuessedWhenAbsent() {
        // A wrong attachment puts the wrong support sheet on the wrong lesson; an absent one is
        // a single click for the teacher. Never guess.
        XCTAssertNil(DocumentPlacementClassifier.lessonKey(displayName: "scan.pdf", extractedText: "Some prose with no identifier."))
    }

    // MARK: - Model integration

    func testImportedSourceGateBlocksNonLessons() {
        func source(_ name: String, _ text: String) -> ImportedSource {
            ImportedSource(
                id: UUID(), reference: FileReference(url: URL(fileURLWithPath: "/tmp/\(name)")),
                extractionMethod: .embeddedText, confidence: nil, extractedText: text,
                reviewStatus: .reviewed, importedAt: .now, updatedAt: .now
            )
        }
        XCTAssertTrue(source("lesson5.pdf", lessonBody).canProposeScheduledLesson)
        XCTAssertFalse(source("lesson5-reteach.pdf", lessonBody).canProposeScheduledLesson)
        XCTAssertFalse(source("blank.pdf", " ").canProposeScheduledLesson)
    }

    func testImportedSourceDecodesFilesSavedBeforeTheseFieldsExisted() throws {
        // Mirrors the persistence rule in MODEL_HANDOFF.txt: sources imported before placement
        // classification existed must still load, and classify on demand.
        let legacyJSON = """
        {
          "id": "9F1E2D3C-0000-4000-8000-000000000001",
          "reference": {"id": "9F1E2D3C-0000-4000-8000-000000000002", "displayName": "lesson5.pdf", "path": "/tmp/lesson5.pdf"},
          "extractionMethod": "embeddedText",
          "extractedText": "placeholder",
          "reviewStatus": "reviewed",
          "importedAt": "2026-07-01T12:00:00Z",
          "updatedAt": "2026-07-01T12:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let source = try decoder.decode(ImportedSource.self, from: Data(legacyJSON.utf8))

        XCTAssertNil(source.placementEligibility)
        XCTAssertNil(source.differentiationRole)
        XCTAssertEqual(source.effectivePlacementEligibility, .inert, "short placeholder text has no lesson shape")
    }
}
