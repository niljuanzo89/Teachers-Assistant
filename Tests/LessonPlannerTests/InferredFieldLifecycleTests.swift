import XCTest
@testable import LessonPlanner

/// Batch E — the lifecycle of an "inferred from document structure" marker.
///
/// The marker is only worth showing a teacher if it means something exact: this field's value was
/// worked out from headings rather than read from a label, **and no human has since rewritten it**.
/// These tests pin both halves, including the cases where clearing it would be wrong.
final class InferredFieldLifecycleTests: XCTestCase {

    @MainActor
    private func makeStore() throws -> (AppStore, LocalRepository) {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = LocalRepository(rootURL: directory)
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Lifecycle", workspaceReference: FileReference(url: directory)
        ))
        return (AppStore(repository: repository), repository)
    }

    @MainActor
    private func storedLesson(in store: AppStore) throws -> LessonRecord {
        try XCTUnwrap(store.lessons.first)
    }

    /// Seeds a lesson whose instructional sequence is marked inferred, persisted so the store
    /// loads it as existing state rather than having it pushed in by the test.
    @MainActor
    private func seedInferredLesson(into repository: LocalRepository) throws -> LessonRecord {
        var lesson = LessonRecord.draft(title: "Place value review")
        lesson.objective = "Compare three-digit numbers."
        lesson.instructionalSequence = [
            InstructionalStep(id: UUID(), title: "Warm-Up", notes: "Number talk."),
            InstructionalStep(id: UUID(), title: "Mini-Lesson", notes: "Connect models.")
        ]
        lesson.inferredFields = [.steps]
        try repository.saveLessons([lesson])
        return lesson
    }

    /// Rewriting an inferred field makes it the teacher's, so the marker must go.
    @MainActor
    func testEditingAnInferredFieldClearsItsMarker() throws {
        let (_, repository) = try makeStore()
        var lesson = try seedInferredLesson(into: repository)
        let store = AppStore(repository: repository)

        lesson.instructionalSequence = [
            InstructionalStep(id: UUID(), title: "My own opening", notes: "Rewritten by hand.")
        ]
        store.updateLessonFromTeacherEdit(lesson)

        XCTAssertNil(try storedLesson(in: store).inferredFields)
    }

    /// Editing a *different* field says nothing about the inferred one.
    @MainActor
    func testEditingAnUnrelatedFieldKeepsTheMarker() throws {
        let (_, repository) = try makeStore()
        var lesson = try seedInferredLesson(into: repository)
        let store = AppStore(repository: repository)

        lesson.objective = "A completely different objective."
        store.updateLessonFromTeacherEdit(lesson)

        XCTAssertEqual(try storedLesson(in: store).inferredFields, [.steps])
    }

    /// The case that motivated comparing content rather than the whole record: approving a lesson
    /// routes through the teacher-edit path, but approving is not rewriting.
    @MainActor
    func testApprovingALessonDoesNotClearMarkers() throws {
        let (_, repository) = try makeStore()
        var lesson = try seedInferredLesson(into: repository)
        let store = AppStore(repository: repository)

        lesson.status = .approved
        store.updateLessonFromTeacherEdit(lesson)

        let stored = try storedLesson(in: store)
        XCTAssertEqual(stored.status, .approved)
        XCTAssertEqual(stored.inferredFields, [.steps], "approval is not authorship of the field")
    }

    /// An automatic pass touching the record is not a teacher vouching for it.
    @MainActor
    func testAutomaticSyncNeverClearsMarkers() throws {
        let (_, repository) = try makeStore()
        var lesson = try seedInferredLesson(into: repository)
        let store = AppStore(repository: repository)

        lesson.instructionalSequence = [InstructionalStep(id: UUID(), title: "Replaced automatically", notes: "")]
        store.updateLessonFromAutomaticSync(lesson)

        XCTAssertEqual(try storedLesson(in: store).inferredFields, [.steps])
    }

    /// Reordering the same steps is still an edit; identical text is not.
    @MainActor
    func testAnIdenticalSaveKeepsTheMarker() throws {
        let (_, repository) = try makeStore()
        let lesson = try seedInferredLesson(into: repository)
        let store = AppStore(repository: repository)

        // A teacher who reads the sequence, agrees, and saves without changing a character keeps
        // the marker. Accepted conservatism: a stale "inferred" is cheaper than a missing one.
        store.updateLessonFromTeacherEdit(lesson)

        XCTAssertEqual(try storedLesson(in: store).inferredFields, [.steps])
    }

    /// The marker is persisted state, not a per-session flag.
    @MainActor
    func testMarkersSurviveSaveAndReload() throws {
        let (_, repository) = try makeStore()
        let lesson = try seedInferredLesson(into: repository)
        let store = AppStore(repository: repository)
        store.updateLessonFromTeacherEdit(lesson)

        let reloaded = AppStore(repository: repository)
        XCTAssertEqual(reloaded.lessons.first?.inferredFields, [.steps])
    }

    /// A teacher's typed objective overrides the extracted one, so marking it inferred would
    /// misdescribe their own words.
    @MainActor
    func testATypedObjectiveIsNeverMarkedInferred() throws {
        let (store, _) = try makeStore()
        let source = ImportedSource(
            id: UUID(), reference: FileReference(url: URL(fileURLWithPath: "/tmp/lesson.docx")),
            extractionMethod: .embeddedText, confidence: nil,
            extractedText: """
            Learning target
            Students will compare three-digit numbers.
            Warm-Up
            Number talk.
            Mini-Lesson
            Connect models.
            """,
            reviewStatus: .reviewed, importedAt: .now, updatedAt: .now
        )

        store.createDraftLesson(from: source, title: "Place value", objective: "My own objective.")

        let lesson = try storedLesson(in: store)
        XCTAssertEqual(lesson.objective, "My own objective.")
        XCTAssertFalse(
            lesson.inferredFields?.contains(.objective) ?? false,
            "a typed objective was marked as inferred"
        )
    }

    /// A later inferred fill must not erase an earlier marker.
    @MainActor
    func testPopulationUnionsMarkersRatherThanReplacingThem() throws {
        var lesson = LessonRecord.draft(title: "Place value review")
        lesson.inferredFields = [.objective]

        let spanText = """
        Materials
        Base-ten blocks
        Warm-Up
        Number talk.
        Mini-Lesson
        Connect models.
        """
        AppStore.populateFields(from: spanText, into: &lesson, allowStructuralInference: true)

        XCTAssertEqual(lesson.inferredFields, [.objective, .steps])
    }
}
