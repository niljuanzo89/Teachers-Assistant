import XCTest
@testable import LessonPlanner

/// Provenance is the precondition for any rebuild: it is what lets the app prove which artifacts
/// it owns and may regenerate. These tests cover both halves — that new records are stamped
/// explicitly, and that records written before the field existed are still classified correctly
/// from their legacy prose markers.
final class RecordOriginTests: XCTestCase {
    private func makeRepository() throws -> LocalRepository {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return LocalRepository(rootURL: directory)
    }

    // MARK: - Legacy classification

    func testLegacyAutoCreatedLessonIsRecognizedWithoutTheField() {
        var lesson = LessonRecord.draft(title: "Legacy")
        lesson.aiReviewWarnings = ["Auto-created from readable planning documents. Fill any blank or incorrect fields as needed."]
        XCTAssertNil(lesson.origin)
        XCTAssertEqual(lesson.effectiveOrigin, .autoDerived)
    }

    func testLessonWithNoMarkerDefaultsToTeacherAuthored() {
        // The safe direction: wrongly regenerating a teacher's lesson destroys work, wrongly
        // preserving an auto one merely leaves a stale record they can delete.
        let lesson = LessonRecord.draft(title: "Hand written")
        XCTAssertEqual(lesson.effectiveOrigin, .teacherAuthored)
    }

    func testLegacyAutoBuiltPacingPlanIsRecognizedWithoutTheField() {
        let auto = CoursePacingPlan(
            id: UUID(), sourceReferenceNames: [], units: [],
            teacherRefinementNotes: "Auto-built from readable document intake. Teachers can edit any blank or incorrect fields.",
            reviewStatus: .approved, createdAt: .now, updatedAt: .now
        )
        XCTAssertEqual(auto.effectiveOrigin, .autoDerived)

        let edited = CoursePacingPlan(
            id: UUID(), sourceReferenceNames: [], units: [],
            teacherRefinementNotes: "Reordered units after the winter break.",
            reviewStatus: .approved, createdAt: .now, updatedAt: .now
        )
        XCTAssertEqual(edited.effectiveOrigin, .teacherAuthored)
    }

    func testLegacyAutoPlacementIsRecognizedByItsNotePrefix() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let auto = WeeklyLessonAssignment(id: UUID(), lessonRecordID: UUID(), date: date, start: date, end: date, planningNotes: "Pacing: Module 1 / Lesson 2")
        XCTAssertEqual(auto.effectiveOrigin, .autoDerived)

        let manual = WeeklyLessonAssignment(id: UUID(), lessonRecordID: UUID(), date: date, start: date, end: date, planningNotes: "Moved to Thursday for the assembly")
        XCTAssertEqual(manual.effectiveOrigin, .teacherAuthored)

        let noNotes = WeeklyLessonAssignment(id: UUID(), lessonRecordID: UUID(), date: date, start: date, end: date, planningNotes: nil)
        XCTAssertEqual(noNotes.effectiveOrigin, .teacherAuthored)
    }

    // MARK: - Persistence compatibility

    func testRecordsSavedBeforeOriginExistedStillDecode() throws {
        let legacyLesson = """
        {"id":"1A1A1A1A-0000-4000-8000-000000000001","status":"approved","title":"Legacy lesson",
         "subject":"","gradeOrAgeRange":"","objective":"","sourceReferences":[],
         "instructionalSequence":[],"materials":[],"differentiationSummary":"",
         "assessmentSummary":"","createdAt":"2026-07-01T12:00:00Z","updatedAt":"2026-07-01T12:00:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let lesson = try decoder.decode(LessonRecord.self, from: Data(legacyLesson.utf8))
        XCTAssertNil(lesson.origin)
        XCTAssertEqual(lesson.effectiveOrigin, .teacherAuthored)

        let legacyAssignment = """
        {"id":"1A1A1A1A-0000-4000-8000-000000000002","lessonRecordID":"1A1A1A1A-0000-4000-8000-000000000003",
         "date":"2026-07-01T12:00:00Z","start":"2026-07-01T12:00:00Z","end":"2026-07-01T12:45:00Z",
         "planningNotes":"Pacing: Module 1"}
        """
        let assignment = try decoder.decode(WeeklyLessonAssignment.self, from: Data(legacyAssignment.utf8))
        XCTAssertNil(assignment.origin)
        XCTAssertEqual(assignment.effectiveOrigin, .autoDerived)
    }

    // MARK: - Stamping and promotion

    @MainActor
    func testTeacherEditPromotesAnAutoDerivedLessonSoRebuildCannotClaimIt() throws {
        let repository = try makeRepository()
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Provenance", workspaceReference: FileReference(url: repository.rootURL)
        ))
        let store = AppStore(repository: repository)
        var lesson = LessonRecord.draft(title: "Auto lesson")
        lesson.origin = .autoDerived
        try repository.saveLessons([lesson])

        let reloaded = AppStore(repository: repository)
        var edited = try XCTUnwrap(reloaded.lessons.first)
        XCTAssertEqual(edited.effectiveOrigin, .autoDerived)
        edited.objective = "Teacher rewrote this objective."
        reloaded.updateLessonFromTeacherEdit(edited)

        let saved = try XCTUnwrap(repository.loadLessons().first)
        XCTAssertEqual(saved.effectiveOrigin, .teacherAuthored, "a teacher's edit must take ownership of the record")
        _ = store
    }

    @MainActor
    func testAutomaticApprovalDoesNotPromoteProvenance() throws {
        let repository = try makeRepository()
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Provenance", workspaceReference: FileReference(url: repository.rootURL)
        ))
        var lesson = LessonRecord.draft(title: "Auto lesson")
        lesson.origin = .autoDerived
        try repository.saveLessons([lesson])
        let store = AppStore(repository: repository)

        var updated = try XCTUnwrap(store.lessons.first)
        updated.status = .approved
        store.updateLessonFromAutomaticSync(updated)

        let saved = try XCTUnwrap(repository.loadLessons().first)
        XCTAssertEqual(saved.effectiveOrigin, .autoDerived, "an automatic pass must not claim a record for the teacher")
    }

    // MARK: - Ownership promotion (gaps found by external review of the first attempt)

    @MainActor
    func testTeacherPacingEditPromotesAnAutoDerivedPlan() throws {
        let repository = try makeRepository()
        var plan = CoursePacingPlan.starter(from: [Self.lessonListSource()])
        plan.reviewStatus = .approved
        XCTAssertEqual(plan.origin, .autoDerived)
        var configuration = AppConfiguration(
            workspaceName: "Promotion", workspaceReference: FileReference(url: repository.rootURL)
        )
        configuration.coursePacingPlan = plan
        try repository.saveConfiguration(configuration)
        let store = AppStore(repository: repository)

        store.updateCoursePacingRefinementNotes("Shifted unit 2 after the field trip.")

        let saved = try XCTUnwrap(repository.loadConfiguration()?.coursePacingPlan)
        XCTAssertEqual(saved.effectiveOrigin, .teacherAuthored,
                       "an edited plan must not stay rebuild-owned, or a rebuild would discard the teacher's work")
    }

    @MainActor
    func testTeacherSkippedDayEditAlsoPromotesThePlan() throws {
        let repository = try makeRepository()
        let plan = CoursePacingPlan.starter(from: [Self.lessonListSource()])
        var configuration = AppConfiguration(
            workspaceName: "Promotion", workspaceReference: FileReference(url: repository.rootURL)
        )
        configuration.coursePacingPlan = plan
        try repository.saveConfiguration(configuration)
        let store = AppStore(repository: repository)
        let unitID = try XCTUnwrap(store.configuration?.coursePacingPlan?.units.first?.id)

        store.addSkippedDayToCoursePacingUnit(unitID: unitID, date: Date(timeIntervalSince1970: 1_700_000_000))

        let saved = try XCTUnwrap(repository.loadConfiguration()?.coursePacingPlan)
        XCTAssertEqual(saved.effectiveOrigin, .teacherAuthored)
    }

    @MainActor
    func testMovingAnAutomaticAssignmentMakesItTheTeachersAndProtectsItFromRelocation() throws {
        let repository = try makeRepository()
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Promotion", workspaceReference: FileReference(url: repository.rootURL)
        ))
        let store = AppStore(repository: repository)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let assignment = WeeklyLessonAssignment(
            id: UUID(), lessonRecordID: UUID(), date: date, start: date,
            end: date.addingTimeInterval(2_700), planningNotes: "Pacing: Module 1", origin: .autoDerived
        )
        store.weeklyPlan.assignments = [assignment]

        store.updateWeeklyAssignment(
            assignment, date: date, start: date.addingTimeInterval(3_600),
            end: date.addingTimeInterval(6_300), planningNotes: "Moved for the assembly"
        )

        let moved = try XCTUnwrap(store.weeklyPlan.assignments.first)
        XCTAssertEqual(moved.effectiveOrigin, .teacherAuthored,
                       "a hand-moved assignment must stop being eligible for automatic relocation")
    }

    @MainActor
    func testEveryTeacherInitiatedLessonCreatorStampsOriginExplicitly() throws {
        let repository = try makeRepository()
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Promotion", workspaceReference: FileReference(url: repository.rootURL)
        ))
        let store = AppStore(repository: repository)

        store.saveDraftLesson(title: "Typed by hand", objective: "")
        store.createDraftLesson(from: Self.lessonListSource(), title: "From a source", objective: "")

        XCTAssertEqual(store.lessons.count, 2)
        for lesson in store.lessons {
            XCTAssertEqual(lesson.origin, .teacherAuthored,
                           "teacher-created lessons must be stamped, not left to the fallback")
        }
    }

    private static func lessonListSource() -> ImportedSource {
        ImportedSource(
            id: UUID(), reference: FileReference(url: URL(fileURLWithPath: "/tmp/unit.docx")),
            extractionMethod: .embeddedText, confidence: nil,
            extractedText: "Unit 1: Fractions\nLesson 1: Equivalent fractions\nLesson 2: Compare fractions",
            reviewStatus: .reviewed, importedAt: .now, updatedAt: .now
        )
    }

    @MainActor
    func testAutomaticSyncPreservesOwnershipInBothDirections() throws {
        // Preservation, not merely "does not promote", is this method's contract: an automatic pass
        // must neither claim a teacher's lesson nor release its own into deletion eligibility.
        let repository = try makeRepository()
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Provenance", workspaceReference: FileReference(url: repository.rootURL)
        ))
        var auto = LessonRecord.draft(title: "Auto")
        auto.origin = .autoDerived
        var teacher = LessonRecord.draft(title: "Teacher")
        teacher.origin = .teacherAuthored
        try repository.saveLessons([auto, teacher])
        let store = AppStore(repository: repository)

        for lesson in store.lessons {
            var updated = lesson
            updated.status = .approved
            store.updateLessonFromAutomaticSync(updated)
        }

        let saved = try repository.loadLessons()
        XCTAssertEqual(saved.first { $0.title == "Auto" }?.origin, .autoDerived)
        XCTAssertEqual(saved.first { $0.title == "Teacher" }?.origin, .teacherAuthored)
    }

    @MainActor
    func testTeacherEditTakesOwnershipRegardlessOfPriorOrigin() throws {
        let repository = try makeRepository()
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Provenance", workspaceReference: FileReference(url: repository.rootURL)
        ))
        var auto = LessonRecord.draft(title: "Auto")
        auto.origin = .autoDerived
        try repository.saveLessons([auto])
        let store = AppStore(repository: repository)

        var edited = try XCTUnwrap(store.lessons.first)
        edited.objective = "Teacher rewrote this."
        store.updateLessonFromTeacherEdit(edited)

        XCTAssertEqual(try repository.loadLessons().first?.origin, .teacherAuthored)
    }

    func testStarterStampsTheGeneratedPlanAsAutoDerived() {
        let source = ImportedSource(
            id: UUID(), reference: FileReference(url: URL(fileURLWithPath: "/tmp/unit.docx")),
            extractionMethod: .embeddedText, confidence: nil,
            extractedText: "Unit 1: Fractions\nLesson 1: Equivalent fractions\nLesson 2: Compare fractions",
            reviewStatus: .reviewed, importedAt: .now, updatedAt: .now
        )
        let plan = CoursePacingPlan.starter(from: [source])
        XCTAssertEqual(plan.origin, .autoDerived)
        XCTAssertEqual(plan.effectiveOrigin, .autoDerived)
    }
}
