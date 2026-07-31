import XCTest
@testable import LessonPlanner

/// Attachments are what route the 174 supporting-material documents in a real import into the
/// differentiation guide instead of the planner. The rules that matter are: never guess, never
/// discard a teacher's own attachment, and survive save/restore.
final class MaterialAttachmentTests: XCTestCase {
    private func makeRepository() throws -> LocalRepository {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return LocalRepository(rootURL: directory)
    }

    // MARK: - Page ranges

    func testPageRangeClampsToWhatTheDocumentActuallyHas() {
        // A stale or over-long range must cite fewer pages, never index past the end.
        let range = PageRange(first: 2, last: 99)
        XCTAssertEqual(range.zeroBasedIndices(inDocumentOfLength: 4), [1, 2, 3])
        XCTAssertEqual(range.zeroBasedIndices(inDocumentOfLength: 0), [])
        XCTAssertEqual(PageRange(first: 0, last: 3).zeroBasedIndices(inDocumentOfLength: 5), [],
                       "a range starting before page 1 is invalid, not silently corrected")
    }

    func testAttachmentWithoutPageRangesIsCitedRatherThanMerged() {
        let attachment = LessonMaterialAttachment(
            id: UUID(), lessonRecordID: UUID(), importedSourceID: UUID(), role: .support,
            pageRanges: nil, pageLabel: nil, origin: .autoDerived, attachedAt: .now
        )
        XCTAssertFalse(attachment.isMergeable,
                       "merging a whole document because no range resolved is worse than citing it")
    }

    func testAttachmentOriginDefaultsToAutomatic() {
        // Opposite default from LessonRecord, deliberately: guessing "teacher" here would freeze a
        // bad automatic attachment that a rebuild should be free to correct.
        let attachment = LessonMaterialAttachment(
            id: UUID(), lessonRecordID: UUID(), importedSourceID: UUID(), role: .practice,
            pageRanges: nil, pageLabel: nil, origin: nil, attachedAt: .now
        )
        XCTAssertEqual(attachment.effectiveOrigin, .autoDerived)
    }

    // MARK: - Automatic attachment

    @MainActor
    func testMaterialIsAttachedToTheLessonItsIdentifierResolvesTo() throws {
        let repository = try makeRepository()
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Attachments", workspaceReference: FileReference(url: repository.rootURL)
        ))
        var lesson = LessonRecord.draft(title: "Module 3 Lesson 7")
        lesson.origin = .autoDerived
        try repository.saveLessons([lesson])
        let source = ImportedSource(
            id: UUID(), reference: FileReference(url: URL(fileURLWithPath: "/tmp/m3-lesson7-reteach.pdf")),
            extractionMethod: .embeddedText, confidence: nil,
            extractedText: "Reteach practice for module 3 lesson 7.",
            reviewStatus: .reviewed, importedAt: .now, updatedAt: .now,
            placementEligibility: .supportingMaterial, differentiationRole: .support,
            lessonKey: DocumentLessonKey(module: 3, lesson: 7)
        )
        try repository.saveImportedSources([source])
        let store = AppStore(repository: repository)

        let attached = store.refreshAutomaticMaterialAttachments()

        XCTAssertEqual(attached, 1)
        XCTAssertEqual(store.lessonMaterialAttachments.first?.lessonRecordID, lesson.id)
        XCTAssertEqual(store.lessonMaterialAttachments.first?.role, .support)
    }

    @MainActor
    func testUnresolvableMaterialIsLeftUnattachedRatherThanGuessed() throws {
        let repository = try makeRepository()
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Attachments", workspaceReference: FileReference(url: repository.rootURL)
        ))
        var lesson = LessonRecord.draft(title: "Module 3 Lesson 7")
        lesson.origin = .autoDerived
        try repository.saveLessons([lesson])
        // No lesson key: measured coverage is only 45%, so guessing would mis-attach at scale.
        let source = ImportedSource(
            id: UUID(), reference: FileReference(url: URL(fileURLWithPath: "/tmp/worksheet.pdf")),
            extractionMethod: .embeddedText, confidence: nil, extractedText: "Practice problems.",
            reviewStatus: .reviewed, importedAt: .now, updatedAt: .now,
            placementEligibility: .supportingMaterial, differentiationRole: .practice, lessonKey: nil
        )
        try repository.saveImportedSources([source])
        let store = AppStore(repository: repository)

        XCTAssertEqual(store.refreshAutomaticMaterialAttachments(), 0)
        XCTAssertTrue(store.lessonMaterialAttachments.isEmpty)
    }

    @MainActor
    func testAmbiguousIdentifierMatchingSeveralLessonsAttachesToNone() throws {
        let repository = try makeRepository()
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Attachments", workspaceReference: FileReference(url: repository.rootURL)
        ))
        var a = LessonRecord.draft(title: "Module 3 Lesson 7")
        var b = LessonRecord.draft(title: "Module 3 Lesson 7 continued")
        a.origin = .autoDerived; b.origin = .autoDerived
        try repository.saveLessons([a, b])
        let source = ImportedSource(
            id: UUID(), reference: FileReference(url: URL(fileURLWithPath: "/tmp/m3-lesson7-chlg.pdf")),
            extractionMethod: .embeddedText, confidence: nil, extractedText: "Challenge.",
            reviewStatus: .reviewed, importedAt: .now, updatedAt: .now,
            placementEligibility: .supportingMaterial, differentiationRole: .extensionChallenge,
            lessonKey: DocumentLessonKey(module: 3, lesson: 7)
        )
        try repository.saveImportedSources([source])
        let store = AppStore(repository: repository)

        XCTAssertEqual(store.refreshAutomaticMaterialAttachments(), 0,
                       "an identifier matching more than one lesson is ambiguous; attaching to either would be a guess")
    }

    @MainActor
    func testTeacherAttachmentSurvivesAnAutomaticRefresh() throws {
        let repository = try makeRepository()
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Attachments", workspaceReference: FileReference(url: repository.rootURL)
        ))
        let lessonID = UUID()
        let sourceID = UUID()
        try repository.saveLessonMaterialAttachments([LessonMaterialAttachment(
            id: UUID(), lessonRecordID: lessonID, importedSourceID: sourceID, role: .practice,
            pageRanges: [PageRange(first: 12, last: 13)], pageLabel: "pp. 12-13",
            origin: .teacherAuthored, attachedAt: .now
        )])
        let store = AppStore(repository: repository)
        XCTAssertEqual(store.lessonMaterialAttachments.count, 1, "attachments must load with the profile")

        store.refreshAutomaticMaterialAttachments()

        let kept = try XCTUnwrap(store.lessonMaterialAttachments.first)
        XCTAssertEqual(kept.effectiveOrigin, .teacherAuthored)
        XCTAssertEqual(kept.pageRanges, [PageRange(first: 12, last: 13)])
    }

    // MARK: - Persistence

    func testAttachmentsRoundTripAndSnapshotsFromBeforeTheyExistedStillDecode() throws {
        let repository = try makeRepository()
        let attachment = LessonMaterialAttachment(
            id: UUID(), lessonRecordID: UUID(), importedSourceID: UUID(), role: .assessment,
            pageRanges: [PageRange(first: 1, last: 2)], pageLabel: nil,
            origin: .teacherAuthored, attachedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try repository.saveLessonMaterialAttachments([attachment])
        XCTAssertEqual(try repository.loadLessonMaterialAttachments(), [attachment])

        // A snapshot written before attachments existed must still decode, per the persistence rule.
        let legacySnapshot = """
        {"id":"2B2B2B2B-0000-4000-8000-000000000001","name":"Old","savedAt":"2026-07-01T12:00:00Z",
         "dailyPlan":{"date":"2026-07-01T12:00:00Z","scheduleBlocks":[],"tasks":[],"dailyNotes":"","updatedAt":"2026-07-01T12:00:00Z"},
         "weeklyPlan":{"weekOf":"2026-07-01T12:00:00Z","assignments":[],"updatedAt":"2026-07-01T12:00:00Z"},
         "lessons":[],"importedSources":[],"generatedOutputs":[]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(PlanningProgressSnapshot.self, from: Data(legacySnapshot.utf8))
        XCTAssertNil(snapshot.lessonMaterialAttachments)
    }
}
