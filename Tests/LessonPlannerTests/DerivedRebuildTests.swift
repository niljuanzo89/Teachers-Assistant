import XCTest
@testable import LessonPlanner

/// The rebuild is the only path that regenerates derived planning data, so its protection rules
/// are load-bearing for data safety. Every test here covers a case where deleting an artifact the
/// app technically derived would still destroy or orphan the teacher's work.
final class DerivedRebuildTests: XCTestCase {
    private func makeRepository() throws -> LocalRepository {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return LocalRepository(rootURL: directory)
    }

    @MainActor
    private func makeStore(_ repository: LocalRepository) throws -> AppStore {
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Rebuild", workspaceReference: FileReference(url: repository.rootURL)
        ))
        return AppStore(repository: repository)
    }

    private func autoLesson(_ title: String) -> LessonRecord {
        var lesson = LessonRecord.draft(title: title)
        lesson.origin = .autoDerived
        lesson.status = .approved
        return lesson
    }

    @MainActor
    func testPreviewCountsRemovableAndPreservedWithoutChangingAnything() throws {
        let repository = try makeRepository()
        let store = try makeStore(repository)
        var teacherLesson = LessonRecord.draft(title: "Mine")
        teacherLesson.origin = .teacherAuthored
        store.replaceLessonsForTesting([autoLesson("Auto one"), autoLesson("Auto two"), teacherLesson])

        let preview = store.previewDerivedRebuild()

        XCTAssertEqual(preview.removableLessons, 2)
        XCTAssertEqual(preview.preservedTeacherLessons, 1)
        XCTAssertEqual(store.lessons.count, 3, "preview must not mutate anything")
    }

    @MainActor
    func testAutoLessonWithAGeneratedOutputIsPreserved() throws {
        let repository = try makeRepository()
        let store = try makeStore(repository)
        let lesson = autoLesson("Has a printed deck")
        store.replaceLessonsForTesting([lesson])
        // A generated file already exists in the teacher's output folder; deleting the lesson
        // would orphan it, and the snapshot safety net does not cover files on disk.
        store.replaceGeneratedOutputsForTesting([GeneratedOutputRecord(
            id: UUID(), lessonRecordID: lesson.id, kind: .slideDeckPPTX,
            displayName: "deck.pptx", filePath: "/tmp/deck.pptx", templateDisplayName: nil, createdAt: .now
        )])

        let preview = store.previewDerivedRebuild()
        XCTAssertEqual(preview.removableLessons, 0)
        XCTAssertEqual(preview.preservedOutputLinkedLessons, 1)

        store.rebuildDerivedPlanningData()
        XCTAssertTrue(store.lessons.contains { $0.id == lesson.id }, "a lesson with generated materials must survive a rebuild")
    }

    @MainActor
    func testAutoLessonReferencedByATeacherPlacedAssignmentIsPreserved() throws {
        let repository = try makeRepository()
        let store = try makeStore(repository)
        let lesson = autoLesson("Teacher scheduled this by hand")
        store.replaceLessonsForTesting([lesson])
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        store.weeklyPlan.assignments = [WeeklyLessonAssignment(
            id: UUID(), lessonRecordID: lesson.id, date: date, start: date,
            end: date.addingTimeInterval(2_700), planningNotes: "Moved for the assembly",
            origin: .teacherAuthored
        )]

        let preview = store.previewDerivedRebuild()
        XCTAssertEqual(preview.removableLessons, 0)
        XCTAssertEqual(preview.preservedAssignmentLinkedLessons, 1)
        XCTAssertEqual(preview.preservedTeacherPlacements, 1)

        store.rebuildDerivedPlanningData()
        XCTAssertTrue(store.lessons.contains { $0.id == lesson.id },
                      "deleting this lesson would leave the teacher's own placement pointing at nothing")
        XCTAssertTrue(store.weeklyPlan.assignments.contains { $0.lessonRecordID == lesson.id },
                      "a teacher-placed assignment must not be removed by a rebuild")
    }

    @MainActor
    func testRebuildRefusesWhenThePacingPlanCarriesTeacherEdits() throws {
        let repository = try makeRepository()
        var configuration = AppConfiguration(
            workspaceName: "Rebuild", workspaceReference: FileReference(url: repository.rootURL)
        )
        var plan = CoursePacingPlan.starter(from: [Self.lessonListSource()])
        plan.origin = .teacherAuthored
        configuration.coursePacingPlan = plan
        try repository.saveConfiguration(configuration)
        let store = AppStore(repository: repository)
        store.replaceLessonsForTesting([autoLesson("Auto")])

        XCTAssertTrue(store.previewDerivedRebuild().isBlockedByTeacherAuthoredPacing)
        let result = store.rebuildDerivedPlanningData()

        XCTAssertNil(result, "a rebuild must refuse rather than discard hand-edited pacing")
        XCTAssertNotNil(store.lastError)
        XCTAssertEqual(store.lessons.count, 1, "nothing may be removed when the rebuild is refused")
    }

    @MainActor
    func testRebuildTakesASnapshotBeforeRemovingAnything() throws {
        let repository = try makeRepository()
        let store = try makeStore(repository)
        store.replaceLessonsForTesting([autoLesson("Auto")])

        store.rebuildDerivedPlanningData()

        XCTAssertFalse(store.progressSnapshots.isEmpty, "the operation must remain revertible")
    }

    private static func lessonListSource() -> ImportedSource {
        ImportedSource(
            id: UUID(), reference: FileReference(url: URL(fileURLWithPath: "/tmp/unit.docx")),
            extractionMethod: .embeddedText, confidence: nil,
            extractedText: "Unit 1: Fractions\nLesson 1: Equivalent fractions\nLesson 2: Compare fractions",
            reviewStatus: .reviewed, importedAt: .now, updatedAt: .now
        )
    }
}
