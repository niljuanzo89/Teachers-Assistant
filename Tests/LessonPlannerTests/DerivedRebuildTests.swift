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
    func testAutomaticPlacementOfAProtectedLessonKeepsItsSlot() throws {
        // A lesson protected because the teacher generated materials for it should not have its
        // day and time silently regenerated: the summary promises it is kept, week position
        // included, and moving it still disrupts a real week.
        let repository = try makeRepository()
        let store = try makeStore(repository)
        let lesson = autoLesson("Has a printed deck")
        store.replaceLessonsForTesting([lesson])
        store.replaceGeneratedOutputsForTesting([GeneratedOutputRecord(
            id: UUID(), lessonRecordID: lesson.id, kind: .slideDeckPPTX,
            displayName: "deck.pptx", filePath: "/tmp/deck.pptx", templateDisplayName: nil, createdAt: .now
        )])
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let placement = WeeklyLessonAssignment(
            id: UUID(), lessonRecordID: lesson.id, date: date, start: date,
            end: date.addingTimeInterval(2_700), planningNotes: "Pacing: Module 1", origin: .autoDerived
        )
        store.weeklyPlan.assignments = [placement]

        XCTAssertEqual(store.previewDerivedRebuild().removablePlacements, 0)
        store.rebuildDerivedPlanningData()

        let kept = store.weeklyPlan.assignments.first { $0.lessonRecordID == lesson.id }
        XCTAssertEqual(kept?.id, placement.id, "the placement itself must survive, not be regenerated")
        XCTAssertEqual(kept?.start, placement.start)
    }

    @MainActor
    func testDailyPlanLinkProtectsAnAutoDerivedLesson() throws {
        // Nothing populates `linkedLessonRecordID` today, but the model allows it and a rebuild
        // that ignored it would leave dangling daily-plan references the moment anything does.
        let repository = try makeRepository()
        let store = try makeStore(repository)
        let lesson = autoLesson("Linked from today's plan")
        store.replaceLessonsForTesting([lesson])
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        store.dailyPlan.scheduleBlocks = [ScheduleBlock(
            id: UUID(), title: "Math", start: date, end: date.addingTimeInterval(2_700),
            type: "lesson", linkedLessonRecordID: lesson.id, notes: ""
        )]

        XCTAssertEqual(store.previewDerivedRebuild().removableLessons, 0)
        store.rebuildDerivedPlanningData()

        XCTAssertTrue(store.lessons.contains { $0.id == lesson.id },
                      "a lesson linked from the daily plan must not be deleted")
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

    @MainActor
    func testLegacySourceWithoutStoredSubjectStillPlacesIntoItsSubjectBlock() throws {
        // Public-behaviour coverage for the subject fallback: this source carries no stored
        // inferredSubject, exactly like every document imported before that field existed. Without
        // the on-demand fallback, matching would drop to whole-document text scoring, which is
        // what once put math content into the English block.
        let repository = try makeRepository()
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Legacy subject", workspaceReference: FileReference(url: repository.rootURL)
        ))
        let scheduleURL = repository.rootURL.appending(path: "Daily Schedule.docx")
        let contentURL = repository.rootURL.appending(path: "Unit Packet.docx")
        try makeDOCX(at: scheduleURL, paragraphs: [
            "Sample Daily Schedule", "8:35 AM - 9:35 AM", "Reading", "9:45 AM - 10:45 AM", "Math"
        ])
        try makeDOCX(at: contentURL, paragraphs: [
            "Grade 5 Mathematics",
            "5.NF.1 Add and subtract fractions with unlike denominators.",
            "Monday: Equivalent fractions",
            "Tuesday: Comparing fractions"
        ])
        let store = AppStore(repository: repository)
        store.importPlanningDocumentItems([scheduleURL])
        XCTAssertTrue(store.hasImportedScheduleScaffold)
        store.importContentDocumentItems([contentURL])

        // Simulate a pre-existing import: strip the stored subject the way legacy data has it.
        let stripped = store.importedSources.map { source -> ImportedSource in
            var copy = source
            copy.inferredSubject = nil
            return copy
        }
        try repository.saveImportedSources(stripped)
        let reloaded = AppStore(repository: repository)
        XCTAssertTrue(reloaded.importedSources.allSatisfy { $0.inferredSubject == nil })

        reloaded.rebuildDerivedPlanningData()

        let calendar = Calendar.current
        XCTAssertFalse(reloaded.weeklyPlan.assignments.isEmpty, "legacy sources must still schedule")
        XCTAssertTrue(
            reloaded.weeklyPlan.assignments.allSatisfy {
                calendar.component(.hour, from: $0.start) == 9 && calendar.component(.minute, from: $0.start) == 45
            },
            "math content must land in the Math block, leaving the Reading block untouched"
        )
    }

    private func makeDOCX(at destination: URL, paragraphs: [String]) throws {
        let packageRoot = destination.deletingLastPathComponent().appending(path: "\(UUID().uuidString)-docx")
        let wordFolder = packageRoot.appending(path: "word")
        try FileManager.default.createDirectory(at: wordFolder, withIntermediateDirectories: true)
        let body = paragraphs.map { "<w:p><w:r><w:t>\($0)</w:t></w:r></w:p>" }.joined()
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>\(body)</w:body></w:document>
        """.write(to: wordFolder.appending(path: "document.xml"), atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = packageRoot
        process.arguments = ["-qr", destination.path, "word"]
        try process.run()
        process.waitUntilExit()
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
