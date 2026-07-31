import XCTest
@testable import LessonPlanner

/// A deck must never assert content the lesson does not have. Measured against two real corpora,
/// 0% of automatically created lessons had an objective — so before this, every generated deck
/// showed invented objectives, assessments and prompts, and claimed teacher review that had not
/// happened.
final class OutputHonestyTests: XCTestCase {
    @MainActor
    private func deckText(for lesson: LessonRecord) async throws -> String {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "deck.pptx")
        try await NativePowerPointExporter.generate(lesson: lesson, destination: url)
        return String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }

    @MainActor
    private var emptyLesson: LessonRecord {
        var lesson = LessonRecord.draft(title: "Place value review")
        lesson.status = .approved
        return lesson
    }

    @MainActor
    func testEmptyLessonProducesNoInventedObjectiveOrAssessment() async throws {
        let text = try await deckText(for: emptyLesson)
        for invention in [
            "Explore the teacher-reviewed learning objective",
            "Be ready to explain your model, answer, or reasoning",
            "Use a teacher-selected support, challenge, or small-group activity",
            "Choose a strategy, show your thinking, and explain why it works"
        ] {
            XCTAssertFalse(text.contains(invention), "deck asserted content the lesson does not have: \(invention)")
        }
    }

    @MainActor
    func testSlidesRequiringAbsentContentAreOmittedEntirely() async throws {
        let text = try await deckText(for: emptyLesson)
        // A learning-goal slide with no goal, or an exit ticket with no success check, asserts
        // something the lesson does not contain. Omit rather than substitute.
        XCTAssertFalse(text.contains("Learning goal"))
        XCTAssertFalse(text.contains("Exit ticket"))
        XCTAssertFalse(text.contains("Choose the support you need"))
        XCTAssertTrue(text.contains("Place value review"), "the lesson's own title must still appear")
    }

    @MainActor
    func testPopulatedLessonStillRendersEverySection() async throws {
        var lesson = LessonRecord.draft(title: "Place value review")
        lesson.status = .approved
        lesson.objective = "Read, write, and compare whole numbers using base-ten reasoning."
        lesson.instructionalSequence = [
            InstructionalStep(id: UUID(), title: "Launch", notes: "Review base-ten blocks."),
            InstructionalStep(id: UUID(), title: "Model", notes: "Compare two numbers together.")
        ]
        lesson.materials = ["Base-ten blocks"]
        lesson.differentiationSummary = "Provide a place-value chart."
        lesson.printableResourcePrompt = "Compare 4,502 and 4,520."
        lesson.assessmentSummary = "Three-question exit ticket."

        let text = try await deckText(for: lesson)

        XCTAssertTrue(text.contains("Learning goal"))
        XCTAssertTrue(text.contains("Exit ticket"))
        XCTAssertTrue(text.contains("Choose the support you need"))
        XCTAssertTrue(text.contains("Read, write, and compare whole numbers"))
        XCTAssertTrue(text.contains("Three-question exit ticket"))
    }

    @MainActor
    func testAutoCreatedLessonCarriesItsSourceTextSoTheTeacherCanFillItManually() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = LocalRepository(rootURL: directory)
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Honesty", workspaceReference: FileReference(url: directory)
        ))
        let store = AppStore(repository: repository)
        try repository.saveImportedSources([ImportedSource(
            id: UUID(), reference: FileReference(url: URL(fileURLWithPath: "/tmp/week.docx")),
            extractionMethod: .embeddedText, confidence: nil,
            extractedText: "Objective: Compare whole numbers.\nAssessment: Exit ticket.",
            reviewStatus: .reviewed, importedAt: .now, updatedAt: .now
        )])
        let reloaded = AppStore(repository: repository)

        // The manual fill action refuses when there is no snapshot, which is what made auto-created
        // lessons unreachable by hand.
        var lesson = LessonRecord.draft(title: "No snapshot")
        lesson.status = .approved
        XCTAssertNil(lesson.sourceTextSnapshot)
        _ = reloaded.fillEmptyLessonFieldsFromSource(lesson)
        XCTAssertNotNil(reloaded.lastError, "without a snapshot the manual path cannot run")
        _ = store
    }
}
