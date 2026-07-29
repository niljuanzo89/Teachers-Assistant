import XCTest
@testable import LessonPlanner

final class LessonPlannerTests: XCTestCase {
    private func makeRepository() throws -> LocalRepository {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return LocalRepository(rootURL: directory)
    }

    private func runZip(cwd: URL, destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = cwd
        process.arguments = ["-qr", destination.path, "ppt"]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    private func makeDOCX(at destination: URL, paragraphs: [String]) throws {
        let packageRoot = destination.deletingLastPathComponent().appending(path: "\(UUID().uuidString)-docx")
        let wordFolder = packageRoot.appending(path: "word")
        try FileManager.default.createDirectory(at: wordFolder, withIntermediateDirectories: true)
        let body = paragraphs.map { paragraph in
            "<w:p><w:r><w:t>\(paragraph)</w:t></w:r></w:p>"
        }.joined()
        try """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>\(body)</w:body>
        </w:document>
        """.write(to: wordFolder.appending(path: "document.xml"), atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = packageRoot
        process.arguments = ["-qr", destination.path, "word"]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    private enum TestSlideDeckGenerator: SlideDeckGenerating {
        @MainActor static var availability: SlideDeckAvailability { .ready }

        @MainActor
        static func generate(lesson: LessonRecord, destination: URL, template: OutputTemplateRegistration?) async throws {
            let lines = [
                "title=\(lesson.title)",
                "objective=\(lesson.objective)",
                "steps=\(lesson.instructionalSequence.map(\.title).joined(separator: "|"))",
                "differentiation=\(lesson.differentiationSummary)",
                "assessment=\(lesson.assessmentSummary)",
                "template=\(template?.displayName ?? "")"
            ]
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try lines.joined(separator: "\n").write(to: destination, atomically: true, encoding: String.Encoding.utf8)
        }
    }

    private enum UnavailableSlideDeckGenerator: SlideDeckGenerating {
        @MainActor static var availability: SlideDeckAvailability {
            .unavailable("Test runtime missing.")
        }

        @MainActor
        static func generate(lesson: LessonRecord, destination: URL, template: OutputTemplateRegistration?) async throws {
            XCTFail("Draft generation should not call an unavailable test generator.")
        }
    }

    func testConfigurationRoundTrip() throws {
        let repository = try makeRepository()
        let workspace = URL(fileURLWithPath: "/tmp/workspace")
        let prompt = WeeklyPlanningPromptPreference(isEnabled: true, day: .thursday, hour: 16, minute: 15)
        let pacingPlan = CoursePacingPlan(
            id: UUID(),
            sourceReferenceNames: ["Scope and Sequence.pdf"],
            units: [
                CoursePacingUnit(
                    id: UUID(),
                    sequence: 1,
                    title: "Unit 1",
                    startDate: nil,
                    endDate: nil,
                    estimatedInstructionalDays: 3,
                    modules: [
                        CoursePacingModule(
                            id: UUID(),
                            sequence: 1,
                            title: "Module 1",
                            estimatedInstructionalDays: 3,
                            lessons: [
                                CoursePacingLesson(
                                    id: UUID(),
                                    sequence: 1,
                                    title: "Lesson 1",
                                    estimatedInstructionalDays: 1,
                                    dependencyNotes: "",
                                    sourceNotes: "Test source"
                                )
                            ],
                            notes: ""
                        )
                    ],
                    assessmentWindows: ["Quiz after Lesson 3"],
                    skippedDays: [],
                    notes: ""
                )
            ],
            teacherRefinementNotes: "Keep assessment on Friday.",
            reviewStatus: .approved,
            createdAt: .now,
            updatedAt: .now
        )
        let configuration = AppConfiguration(
            workspaceName: "Test Workspace",
            workspaceReference: FileReference(url: workspace),
            weeklyPlanningPrompt: prompt,
            coursePacingPlan: pacingPlan
        )
        try repository.saveConfiguration(configuration)
        let loaded = try XCTUnwrap(repository.loadConfiguration())
        XCTAssertEqual(loaded.workspaceName, configuration.workspaceName)
        XCTAssertEqual(loaded.workspaceReference.path, configuration.workspaceReference.path)
        XCTAssertEqual(loaded.schemaVersion, configuration.schemaVersion)
        XCTAssertEqual(loaded.weeklyPlanningPrompt, prompt)
        let loadedPacingPlan = try XCTUnwrap(loaded.coursePacingPlan)
        XCTAssertEqual(loadedPacingPlan.sourceReferenceNames, pacingPlan.sourceReferenceNames)
        XCTAssertEqual(loadedPacingPlan.reviewStatus, pacingPlan.reviewStatus)
        XCTAssertEqual(loadedPacingPlan.teacherRefinementNotes, pacingPlan.teacherRefinementNotes)
        XCTAssertEqual(loadedPacingPlan.units, pacingPlan.units)
    }

    func testLocalRepositoryScopesDataToActiveTeacherProfile() throws {
        let repository = try makeRepository()
        let firstProfile = TeacherProfile.localTestProfile(displayName: "Teacher A", gradeOrSubject: "Grade 4")
        let secondProfile = TeacherProfile.localTestProfile(displayName: "Teacher B", gradeOrSubject: "Grade 5")
        try repository.saveTeacherProfiles([firstProfile, secondProfile])

        try repository.saveActiveTeacherProfileID(firstProfile.id)
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Teacher A Workspace",
            workspaceReference: FileReference(url: URL(fileURLWithPath: "/tmp/a"))
        ))

        try repository.saveActiveTeacherProfileID(secondProfile.id)
        XCTAssertNil(try repository.loadConfiguration())
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Teacher B Workspace",
            workspaceReference: FileReference(url: URL(fileURLWithPath: "/tmp/b"))
        ))

        try repository.saveActiveTeacherProfileID(firstProfile.id)
        XCTAssertEqual(try repository.loadConfiguration()?.workspaceName, "Teacher A Workspace")

        try repository.saveActiveTeacherProfileID(secondProfile.id)
        XCTAssertEqual(try repository.loadConfiguration()?.workspaceName, "Teacher B Workspace")
    }

    @MainActor
    func testAppStoreCanCreateAndSwitchLocalTeacherProfiles() throws {
        let repository = try makeRepository()
        let store = AppStore(repository: repository)

        store.createLocalTeacherProfile(displayName: "Teacher A", role: "Teacher", gradeOrSubject: "Algebra")

        XCTAssertEqual(store.teacherProfiles.map(\.displayName), ["Teacher A"])
        XCTAssertEqual(store.activeTeacherProfile?.gradeOrSubject, "Algebra")
        XCTAssertNil(store.configuration)
    }

    @MainActor
    func testAppStoreSavesAndRestoresCurrentProgressSnapshot() throws {
        let repository = try makeRepository()
        let workspace = repository.rootURL.appending(path: "workspace")
        let source = ImportedSource(
            id: UUID(),
            reference: FileReference(url: URL(fileURLWithPath: "/tmp/Scope.pdf")),
            setupRole: .pacingGuide,
            extractionMethod: .embeddedText,
            confidence: nil,
            extractedText: "Unit 1\nLesson 1: Place value",
            reviewStatus: .reviewed,
            importedAt: .now,
            updatedAt: .now
        )
        var configuration = AppConfiguration(
            workspaceName: "Snapshot Workspace",
            workspaceReference: FileReference(url: workspace),
            sourceRegistrations: [
                SourceRegistration(
                    id: UUID(),
                    displayName: "Sources",
                    kind: .curriculum,
                    reference: FileReference(url: URL(fileURLWithPath: "/tmp/sources")),
                    notes: "",
                    addedAt: .now
                )
            ],
            coursePacingPlan: CoursePacingPlan.starter(from: [source])
        )
        configuration.coursePacingPlan?.reviewStatus = .approved
        var lesson = LessonRecord.draft(title: "Place value")
        lesson.status = .approved
        try repository.saveConfiguration(configuration)
        try repository.saveLessons([lesson])
        try repository.saveImportedSources([source])
        try repository.saveGeneratedOutputs([
            GeneratedOutputRecord(
                id: UUID(),
                lessonRecordID: lesson.id,
                kind: .lessonPlanHTML,
                displayName: "place-value.html",
                filePath: "/tmp/place-value.html",
                templateDisplayName: nil,
                createdAt: .now
            )
        ])

        let store = AppStore(repository: repository)
        store.addTask(title: "Prepare manipulatives")
        store.addScheduleBlock(title: "Math", start: .now, end: Date.now.addingTimeInterval(1_800), type: "Instruction")
        XCTAssertEqual(store.weeklyPlan.assignments.count, 1)
        store.saveCurrentProgressSnapshot(named: "Before reset")
        let snapshot = try XCTUnwrap(store.progressSnapshots.first)

        store.clearCurrentDocumentsAndEntries()
        XCTAssertTrue(store.lessons.isEmpty)
        XCTAssertTrue(store.importedSources.isEmpty)
        XCTAssertTrue(store.generatedOutputs.isEmpty)
        XCTAssertTrue(store.dailyPlan.tasks.isEmpty)
        XCTAssertTrue(store.weeklyPlan.assignments.isEmpty)

        store.restoreProgressSnapshot(snapshot)

        XCTAssertEqual(store.lessons.map(\.title), ["Place value"])
        XCTAssertEqual(store.importedSources.map(\.reference.displayName), ["Scope.pdf"])
        XCTAssertEqual(store.generatedOutputs.map(\.displayName), ["place-value.html"])
        XCTAssertEqual(store.dailyPlan.tasks.map(\.title), ["Prepare manipulatives"])
        XCTAssertEqual(store.dailyPlan.scheduleBlocks.map(\.title), ["Math"])
        XCTAssertEqual(store.weeklyPlan.assignments.count, 1)
        XCTAssertEqual(store.configuration?.sourceRegistrations.map(\.displayName), ["Sources"])
        XCTAssertEqual(store.configuration?.coursePacingPlan?.reviewStatus, .approved)
    }

    @MainActor
    func testAppStoreClearsCurrentDocumentsAndEntriesButKeepsWorkspaceShell() throws {
        let repository = try makeRepository()
        let workspace = repository.rootURL.appending(path: "workspace")
        let source = ImportedSource(
            id: UUID(),
            reference: FileReference(url: URL(fileURLWithPath: "/tmp/Scope.pdf")),
            setupRole: .pacingGuide,
            extractionMethod: .embeddedText,
            confidence: nil,
            extractedText: "Unit 1",
            reviewStatus: .reviewed,
            importedAt: .now,
            updatedAt: .now
        )
        var lesson = LessonRecord.draft(title: "Community helpers")
        lesson.status = .approved
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Clear Workspace",
            workspaceReference: FileReference(url: workspace),
            outputFolderReference: FileReference(url: repository.rootURL.appending(path: "outputs")),
            sourceRegistrations: [
                SourceRegistration(
                    id: UUID(),
                    displayName: "Sources",
                    kind: .curriculum,
                    reference: FileReference(url: URL(fileURLWithPath: "/tmp/sources")),
                    notes: "",
                    addedAt: .now
                )
            ],
            coursePacingPlan: CoursePacingPlan.starter(from: [source])
        ))
        try repository.saveLessons([lesson])
        try repository.saveImportedSources([source])
        try repository.saveGeneratedOutputs([
            GeneratedOutputRecord(
                id: UUID(),
                lessonRecordID: lesson.id,
                kind: .slideDeckPPTX,
                displayName: "deck.pptx",
                filePath: "/tmp/deck.pptx",
                templateDisplayName: nil,
                createdAt: .now
            )
        ])

        let store = AppStore(repository: repository)
        store.addTask(title: "Print handouts")
        store.addWeeklyAssignment(lessonID: lesson.id, date: store.weeklyPlan.weekOf, start: .now, end: Date.now.addingTimeInterval(1_800))
        store.clearCurrentDocumentsAndEntries()

        XCTAssertEqual(store.configuration?.workspaceName, "Clear Workspace")
        XCTAssertEqual(store.configuration?.outputFolderReference?.displayName, "outputs")
        XCTAssertTrue(store.configuration?.sourceRegistrations.isEmpty == true)
        XCTAssertNil(store.configuration?.coursePacingPlan)
        XCTAssertTrue(store.lessons.isEmpty)
        XCTAssertTrue(store.importedSources.isEmpty)
        XCTAssertTrue(store.generatedOutputs.isEmpty)
        XCTAssertTrue(store.dailyPlan.tasks.isEmpty)
        XCTAssertTrue(store.weeklyPlan.assignments.isEmpty)
        XCTAssertTrue(try repository.loadLessons().isEmpty)
        XCTAssertTrue(try repository.loadImportedSources().isEmpty)
        XCTAssertTrue(try repository.loadGeneratedOutputs().isEmpty)
    }

    func testCoursePacingStarterExtractsReviewedSetupStructure() throws {
        let source = ImportedSource(
            id: UUID(),
            reference: FileReference(url: URL(fileURLWithPath: "/tmp/Scope and Sequence.pdf")),
            extractionMethod: .embeddedText,
            confidence: nil,
            extractedText: """
            Unit 1: Foundations
            Module 1: Number Sense
            Lesson 1: Introduce place value
            Lesson 2: Compare numbers
            Assessment: Unit quiz
            """,
            reviewStatus: .reviewed,
            importedAt: .now,
            updatedAt: .now
        )

        let plan = CoursePacingPlan.starter(from: [source])

        XCTAssertEqual(plan.reviewStatus, .draft)
        XCTAssertEqual(plan.sourceReferenceNames, ["Scope and Sequence.pdf"])
        XCTAssertEqual(plan.units.first?.title, "Unit 1: Foundations")
        XCTAssertEqual(plan.units.first?.modules.first?.title, "Module 1: Number Sense")
        XCTAssertEqual(plan.lessonCount, 2)
        XCTAssertEqual(plan.estimatedInstructionalDays, 2)
        XCTAssertEqual(plan.units.first?.assessmentWindows, ["Assessment: Unit quiz"])
    }

    func testImportedSourceRoleInferenceSortsSetupDocuments() throws {
        XCTAssertEqual(
            ImportedSourceRole.infer(displayName: "Grade 4 Scope and Sequence.pdf", extractedText: ""),
            .pacingGuide
        )
        XCTAssertEqual(
            ImportedSourceRole.infer(displayName: "District Calendar.pdf", extractedText: "No school on Friday. Winter break."),
            .instructionalCalendar
        )
        XCTAssertEqual(
            ImportedSourceRole.infer(displayName: "Benchmark Schedule.pdf", extractedText: "Interim assessment window in October."),
            .assessmentSchedule
        )
        XCTAssertEqual(
            ImportedSourceRole.infer(displayName: "Lesson 3 Worksheet.pdf", extractedText: "Student handout and practice"),
            .lessonMaterial
        )
    }

    func testImportedSourceIntakeReportCountsPacingReadyDocuments() throws {
        let sources = [
            ImportedSource(
                id: UUID(),
                reference: FileReference(url: URL(fileURLWithPath: "/tmp/Scope and Sequence.pdf")),
                setupRole: .pacingGuide,
                extractionMethod: .embeddedText,
                confidence: nil,
                extractedText: "Unit 1",
                reviewStatus: .reviewed,
                importedAt: .now,
                updatedAt: .now
            ),
            ImportedSource(
                id: UUID(),
                reference: FileReference(url: URL(fileURLWithPath: "/tmp/Lesson Worksheet.pdf")),
                setupRole: .lessonMaterial,
                extractionMethod: .embeddedText,
                confidence: nil,
                extractedText: "Practice",
                reviewStatus: .reviewed,
                importedAt: .now,
                updatedAt: .now
            ),
            ImportedSource(
                id: UUID(),
                reference: FileReference(url: URL(fileURLWithPath: "/tmp/Assessment Schedule.pdf")),
                setupRole: .assessmentSchedule,
                extractionMethod: .embeddedText,
                confidence: nil,
                extractedText: "Benchmark",
                reviewStatus: .imported,
                importedAt: .now,
                updatedAt: .now
            )
        ]

        let report = ImportedSourceIntakeReport.analyze(sources)

        XCTAssertEqual(report.totalCount, 3)
        XCTAssertEqual(report.reviewedCount, 3)
        XCTAssertEqual(report.pacingReadyCount, 2)
        XCTAssertTrue(report.canBuildCoursePacing)
        XCTAssertEqual(report.roleCounts[.lessonMaterial], 1)
    }

    func testLocalWorkflowQAReportFlagsMissingPrototypeSteps() throws {
        let weeklyPlan = WeeklyPlan.empty(for: Date(timeIntervalSince1970: 1_700_000_000))
        let weeklyPackageReport = WeeklyPackageReadinessReport.analyze(plan: weeklyPlan, lessons: [], generatedOutputs: [])
        let report = LocalWorkflowQAReport.analyze(
            activeTeacherProfile: nil,
            importedSources: [],
            pacingReport: CoursePacingReadinessReport.analyze(nil),
            weeklyPackageReport: weeklyPackageReport,
            lessons: [],
            generatedOutputs: []
        )

        XCTAssertFalse(report.isReadyForEndToEndQA)
        XCTAssertEqual(report.items.first?.id, "local-profile")
        XCTAssertEqual(report.items.first?.status, .attention)
        XCTAssertTrue(report.attentionItems.contains { $0.id == "weekly-hub" })
    }

    func testLocalWorkflowQAReportCanReachReadyState() throws {
        var lesson = LessonRecord.draft(title: "Fraction Strategies")
        lesson.status = .approved
        let weekOf = Date(timeIntervalSince1970: 1_700_000_000)
        let weeklyPlan = WeeklyPlan(
            weekOf: weekOf,
            assignments: [
                WeeklyLessonAssignment(
                    id: UUID(),
                    lessonRecordID: lesson.id,
                    date: weekOf,
                    start: weekOf.addingTimeInterval(32_400),
                    end: weekOf.addingTimeInterval(35_100),
                    planningNotes: "Use fraction strips."
                )
            ],
            updatedAt: .now
        )
        let source = ImportedSource(
            id: UUID(),
            reference: FileReference(url: URL(fileURLWithPath: "/tmp/Scope and Sequence.pdf")),
            setupRole: .pacingGuide,
            extractionMethod: .embeddedText,
            confidence: nil,
            extractedText: "Unit 1: Fractions\nLesson 1: Equivalent fractions",
            reviewStatus: .reviewed,
            importedAt: .now,
            updatedAt: .now
        )
        let pacingPlan = CoursePacingPlan(
            id: UUID(),
            sourceReferenceNames: ["Scope and Sequence.pdf"],
            units: [
                CoursePacingUnit(
                    id: UUID(),
                    sequence: 1,
                    title: "Unit 1: Fractions",
                    startDate: weekOf,
                    endDate: weekOf.addingTimeInterval(604_800),
                    estimatedInstructionalDays: 1,
                    modules: [
                        CoursePacingModule(
                            id: UUID(),
                            sequence: 1,
                            title: "Module 1",
                            estimatedInstructionalDays: 1,
                            lessons: [
                                CoursePacingLesson(
                                    id: UUID(),
                                    sequence: 1,
                                    title: "Lesson 1: Equivalent fractions",
                                    startDate: weekOf,
                                    endDate: weekOf,
                                    estimatedInstructionalDays: 1,
                                    dependencyNotes: "",
                                    sourceNotes: "Scope and Sequence.pdf"
                                )
                            ],
                            notes: ""
                        )
                    ],
                    assessmentWindows: ["Exit ticket"],
                    skippedDays: [],
                    notes: "Teacher approved."
                )
            ],
            teacherRefinementNotes: "Ready for local QA.",
            reviewStatus: .approved,
            createdAt: .now,
            updatedAt: .now
        )
        let outputs = [
            GeneratedOutputRecord(id: UUID(), lessonRecordID: lesson.id, kind: .lessonPlanHTML, displayName: "plan.html", filePath: "/tmp/plan.html", templateDisplayName: nil, createdAt: .now),
            GeneratedOutputRecord(id: UUID(), lessonRecordID: lesson.id, kind: .slideDeckPPTX, displayName: "deck.pptx", filePath: "/tmp/deck.pptx", templateDisplayName: nil, createdAt: .now),
            GeneratedOutputRecord(id: UUID(), lessonRecordID: lesson.id, kind: .differentiationGuideHTML, displayName: "guide.html", filePath: "/tmp/guide.html", templateDisplayName: nil, createdAt: .now),
            GeneratedOutputRecord(id: UUID(), lessonRecordID: nil, kind: .weeklyPlanHTML, displayName: "weekly.html", filePath: "/tmp/weekly.html", templateDisplayName: nil, createdAt: .now)
        ]

        let report = LocalWorkflowQAReport.analyze(
            activeTeacherProfile: TeacherProfile.localTestProfile(displayName: "Teacher A"),
            importedSources: [source],
            pacingReport: CoursePacingReadinessReport.analyze(pacingPlan),
            weeklyPackageReport: WeeklyPackageReadinessReport.analyze(plan: weeklyPlan, lessons: [lesson], generatedOutputs: outputs),
            lessons: [lesson],
            generatedOutputs: outputs
        )

        XCTAssertTrue(report.isReadyForEndToEndQA)
        XCTAssertTrue(report.attentionItems.isEmpty)
    }

    @MainActor
    func testStarterCoursePacingPrefersReviewedPacingSetupDocuments() throws {
        let repository = try makeRepository()
        let workspace = repository.rootURL.appending(path: "workspace")
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Generic QA Workspace",
            workspaceReference: FileReference(url: workspace)
        ))
        try repository.saveImportedSources([
            ImportedSource(
                id: UUID(),
                reference: FileReference(url: URL(fileURLWithPath: "/tmp/Lesson Worksheet.pdf")),
                setupRole: .lessonMaterial,
                extractionMethod: .embeddedText,
                confidence: nil,
                extractedText: "Lesson 9: Extra worksheet practice",
                reviewStatus: .reviewed,
                importedAt: .now,
                updatedAt: .now
            ),
            ImportedSource(
                id: UUID(),
                reference: FileReference(url: URL(fileURLWithPath: "/tmp/Scope and Sequence.pdf")),
                setupRole: .pacingGuide,
                extractionMethod: .embeddedText,
                confidence: nil,
                extractedText: "Unit 1: Foundations\nLesson 1: Place value",
                reviewStatus: .reviewed,
                importedAt: .now,
                updatedAt: .now
            )
        ])
        let store = AppStore(repository: repository)

        store.createStarterCoursePacingPlanFromReviewedSources()

        let savedPlan = try XCTUnwrap(repository.loadConfiguration()?.coursePacingPlan)
        XCTAssertEqual(savedPlan.sourceReferenceNames, ["Scope and Sequence.pdf"])
        XCTAssertEqual(savedPlan.units.first?.title, "Unit 1: Foundations")
    }

    func testCoursePacingReadinessRequiresTeacherApproval() throws {
        var plan = CoursePacingPlan(
            id: UUID(),
            sourceReferenceNames: ["Pacing Guide.pdf"],
            units: [
                CoursePacingUnit(
                    id: UUID(),
                    sequence: 1,
                    title: "Unit 1",
                    startDate: nil,
                    endDate: nil,
                    estimatedInstructionalDays: 1,
                    modules: [
                        CoursePacingModule(
                            id: UUID(),
                            sequence: 1,
                            title: "Module 1",
                            estimatedInstructionalDays: 1,
                            lessons: [
                                CoursePacingLesson(
                                    id: UUID(),
                                    sequence: 1,
                                    title: "Lesson 1",
                                    estimatedInstructionalDays: 1,
                                    dependencyNotes: "",
                                    sourceNotes: ""
                                )
                            ],
                            notes: ""
                        )
                    ],
                    assessmentWindows: ["Assessment window"],
                    skippedDays: [],
                    notes: ""
                )
            ],
            teacherRefinementNotes: "",
            reviewStatus: .draft,
            createdAt: .now,
            updatedAt: .now
        )

        var report = CoursePacingReadinessReport.analyze(plan)
        XCTAssertFalse(report.canGovernWeeklyPlanning)
        XCTAssertTrue(report.blockingIssues.contains(.draftNeedsApproval))

        plan.reviewStatus = .approved
        report = CoursePacingReadinessReport.analyze(plan)
        XCTAssertTrue(report.canGovernWeeklyPlanning)
        XCTAssertEqual(report.estimatedInstructionalDays, 1)
    }

    @MainActor
    func testAppStoreUpdatesCoursePacingUnitDetailsAndSkippedDays() throws {
        let repository = try makeRepository()
        let workspace = repository.rootURL.appending(path: "workspace")
        let unitID = UUID()
        let originalStartDate = Date(timeIntervalSince1970: 1_700_000_000)
        let newStartDate = originalStartDate.addingTimeInterval(86_400)
        let newEndDate = newStartDate.addingTimeInterval(172_800)
        let skippedDay = newStartDate.addingTimeInterval(86_400)
        let pacingPlan = CoursePacingPlan(
            id: UUID(),
            sourceReferenceNames: ["Pacing Guide.pdf"],
            units: [
                CoursePacingUnit(
                    id: unitID,
                    sequence: 1,
                    title: "Unit 1",
                    startDate: originalStartDate,
                    endDate: nil,
                    estimatedInstructionalDays: 1,
                    modules: [],
                    assessmentWindows: [],
                    skippedDays: [],
                    notes: ""
                )
            ],
            teacherRefinementNotes: "",
            reviewStatus: .approved,
            createdAt: .now,
            updatedAt: .now
        )
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Generic QA Workspace",
            workspaceReference: FileReference(url: workspace),
            coursePacingPlan: pacingPlan
        ))
        let store = AppStore(repository: repository)

        store.updateCoursePacingUnit(
            unitID: unitID,
            title: "  Revised Unit 1  ",
            startDate: newStartDate,
            endDate: newEndDate,
            estimatedInstructionalDays: 0,
            assessmentWindows: ["  Quiz window  ", "", "Performance task"],
            notes: "  Review fractions first.  "
        )
        store.addSkippedDayToCoursePacingUnit(unitID: unitID, date: skippedDay)
        store.addSkippedDayToCoursePacingUnit(unitID: unitID, date: skippedDay.addingTimeInterval(3_600))
        store.removeSkippedDayFromCoursePacingUnit(unitID: unitID, date: skippedDay)

        let savedUnit = try XCTUnwrap(repository.loadConfiguration()?.coursePacingPlan?.units.first)
        XCTAssertEqual(savedUnit.title, "Revised Unit 1")
        XCTAssertEqual(savedUnit.startDate, newStartDate)
        XCTAssertEqual(savedUnit.endDate, newEndDate)
        XCTAssertEqual(savedUnit.estimatedInstructionalDays, 1)
        XCTAssertEqual(savedUnit.assessmentWindows, ["Quiz window", "Performance task"])
        XCTAssertEqual(savedUnit.notes, "Review fractions first.")
        XCTAssertTrue(savedUnit.skippedDays.isEmpty)
    }

    @MainActor
    func testAppStoreUpdatesCoursePacingModuleAndLessonDetails() throws {
        let repository = try makeRepository()
        let workspace = repository.rootURL.appending(path: "workspace")
        let unitID = UUID()
        let moduleID = UUID()
        let lessonID = UUID()
        let moduleStartDate = Date(timeIntervalSince1970: 1_700_000_000)
        let lessonStartDate = moduleStartDate.addingTimeInterval(86_400)
        let pacingPlan = CoursePacingPlan(
            id: UUID(),
            sourceReferenceNames: ["Pacing Guide.pdf"],
            units: [
                CoursePacingUnit(
                    id: unitID,
                    sequence: 1,
                    title: "Unit 1",
                    startDate: nil,
                    endDate: nil,
                    estimatedInstructionalDays: 1,
                    modules: [
                        CoursePacingModule(
                            id: moduleID,
                            sequence: 1,
                            title: "Module 1",
                            estimatedInstructionalDays: 1,
                            lessons: [
                                CoursePacingLesson(
                                    id: lessonID,
                                    sequence: 1,
                                    title: "Lesson 1",
                                    estimatedInstructionalDays: 1,
                                    dependencyNotes: "",
                                    sourceNotes: ""
                                )
                            ],
                            notes: ""
                        )
                    ],
                    assessmentWindows: [],
                    skippedDays: [],
                    notes: ""
                )
            ],
            teacherRefinementNotes: "",
            reviewStatus: .approved,
            createdAt: .now,
            updatedAt: .now
        )
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Generic QA Workspace",
            workspaceReference: FileReference(url: workspace),
            coursePacingPlan: pacingPlan
        ))
        let store = AppStore(repository: repository)

        store.updateCoursePacingModule(
            unitID: unitID,
            moduleID: moduleID,
            title: "  Revised Module  ",
            startDate: moduleStartDate,
            endDate: nil,
            estimatedInstructionalDays: 0,
            notes: "  Module note.  "
        )
        store.updateCoursePacingLesson(
            unitID: unitID,
            moduleID: moduleID,
            lessonID: lessonID,
            title: "  Revised Lesson  ",
            startDate: lessonStartDate,
            endDate: nil,
            estimatedInstructionalDays: 0,
            dependencyNotes: "  After Lesson 0  ",
            sourceNotes: "  From pacing guide  "
        )

        let savedModule = try XCTUnwrap(repository.loadConfiguration()?.coursePacingPlan?.units.first?.modules.first)
        XCTAssertEqual(savedModule.title, "Revised Module")
        XCTAssertEqual(savedModule.startDate, moduleStartDate)
        XCTAssertEqual(savedModule.estimatedInstructionalDays, 1)
        XCTAssertEqual(savedModule.notes, "Module note.")
        let savedLesson = try XCTUnwrap(savedModule.lessons.first)
        XCTAssertEqual(savedLesson.title, "Revised Lesson")
        XCTAssertEqual(savedLesson.startDate, lessonStartDate)
        XCTAssertEqual(savedLesson.estimatedInstructionalDays, 1)
        XCTAssertEqual(savedLesson.dependencyNotes, "After Lesson 0")
        XCTAssertEqual(savedLesson.sourceNotes, "From pacing guide")
    }

    @MainActor
    func testAppStoreRejectsInvalidCoursePacingDateRanges() throws {
        let repository = try makeRepository()
        let workspace = repository.rootURL.appending(path: "workspace")
        let unitID = UUID()
        let moduleID = UUID()
        let lessonID = UUID()
        let startDate = Date(timeIntervalSince1970: 1_700_000_000)
        let invalidEndDate = startDate.addingTimeInterval(-86_400)
        let pacingPlan = CoursePacingPlan(
            id: UUID(),
            sourceReferenceNames: ["Pacing Guide.pdf"],
            units: [
                CoursePacingUnit(
                    id: unitID,
                    sequence: 1,
                    title: "Unit 1",
                    startDate: startDate,
                    endDate: nil,
                    estimatedInstructionalDays: 1,
                    modules: [
                        CoursePacingModule(
                            id: moduleID,
                            sequence: 1,
                            title: "Module 1",
                            estimatedInstructionalDays: 1,
                            lessons: [
                                CoursePacingLesson(
                                    id: lessonID,
                                    sequence: 1,
                                    title: "Lesson 1",
                                    estimatedInstructionalDays: 1,
                                    dependencyNotes: "",
                                    sourceNotes: ""
                                )
                            ],
                            notes: ""
                        )
                    ],
                    assessmentWindows: [],
                    skippedDays: [],
                    notes: ""
                )
            ],
            teacherRefinementNotes: "",
            reviewStatus: .approved,
            createdAt: .now,
            updatedAt: .now
        )
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Generic QA Workspace",
            workspaceReference: FileReference(url: workspace),
            coursePacingPlan: pacingPlan
        ))
        let store = AppStore(repository: repository)

        store.updateCoursePacingUnit(
            unitID: unitID,
            title: "Invalid Unit",
            startDate: startDate,
            endDate: invalidEndDate,
            estimatedInstructionalDays: 1,
            assessmentWindows: [],
            notes: ""
        )
        XCTAssertEqual(store.lastError, "Pacing end date must be on or after the start date.")
        XCTAssertEqual(try repository.loadConfiguration()?.coursePacingPlan?.units.first?.title, "Unit 1")

        store.updateCoursePacingModule(
            unitID: unitID,
            moduleID: moduleID,
            title: "Invalid Module",
            startDate: startDate,
            endDate: invalidEndDate,
            estimatedInstructionalDays: 1,
            notes: ""
        )
        XCTAssertEqual(try repository.loadConfiguration()?.coursePacingPlan?.units.first?.modules.first?.title, "Module 1")

        store.updateCoursePacingLesson(
            unitID: unitID,
            moduleID: moduleID,
            lessonID: lessonID,
            title: "Invalid Lesson",
            startDate: startDate,
            endDate: invalidEndDate,
            estimatedInstructionalDays: 1,
            dependencyNotes: "",
            sourceNotes: ""
        )
        XCTAssertEqual(try repository.loadConfiguration()?.coursePacingPlan?.units.first?.modules.first?.lessons.first?.title, "Lesson 1")
    }

    func testWeeklyPacingRefinementDraftClassifiesLostTime() throws {
        let weekOf = Date(timeIntervalSince1970: 1_700_000_000)

        let proposal = try XCTUnwrap(WeeklyPacingRefinementProposal.draft(
            from: "We lost a day to an assembly and need to slow down.",
            weekOf: weekOf
        ))

        XCTAssertEqual(proposal.status, .draft)
        XCTAssertEqual(proposal.checkInNote, "We lost a day to an assembly and need to slow down.")
        XCTAssertEqual(proposal.proposedAdjustmentSummary, "Consider slowing pacing for this week.")
        XCTAssertEqual(proposal.affectedPacingArea, "Upcoming lessons and assessment timing")
        XCTAssertEqual(proposal.suggestedDateShiftDays, 1)
        XCTAssertTrue(proposal.pacingImpactNotes.contains("upcoming pacing lessons should move later"))
    }

    @MainActor
    func testAppStoreAcceptsWeeklyPacingRefinementIntoCoursePacing() throws {
        let repository = try makeRepository()
        let workspace = repository.rootURL.appending(path: "workspace")
        let unitStartDate = Date(timeIntervalSince1970: 1_700_000_000)
        let unitEndDate = unitStartDate.addingTimeInterval(172_800)
        let moduleStartDate = unitStartDate.addingTimeInterval(86_400)
        let lessonStartDate = unitStartDate.addingTimeInterval(172_800)
        let pacingPlan = CoursePacingPlan(
            id: UUID(),
            sourceReferenceNames: ["Pacing Guide.pdf"],
            units: [
                CoursePacingUnit(
                    id: UUID(),
                    sequence: 1,
                    title: "Unit 1",
                    startDate: unitStartDate,
                    endDate: unitEndDate,
                    estimatedInstructionalDays: 1,
                    modules: [
                        CoursePacingModule(
                            id: UUID(),
                            sequence: 1,
                            title: "Module 1",
                            startDate: moduleStartDate,
                            endDate: nil,
                            estimatedInstructionalDays: 1,
                            lessons: [
                                CoursePacingLesson(
                                    id: UUID(),
                                    sequence: 1,
                                    title: "Lesson 1",
                                    startDate: lessonStartDate,
                                    endDate: nil,
                                    estimatedInstructionalDays: 1,
                                    dependencyNotes: "",
                                    sourceNotes: ""
                                )
                            ],
                            notes: ""
                        )
                    ],
                    assessmentWindows: ["Unit quiz"],
                    skippedDays: [],
                    notes: ""
                )
            ],
            teacherRefinementNotes: "Original note.",
            reviewStatus: .approved,
            createdAt: .now,
            updatedAt: .now
        )
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Generic QA Workspace",
            workspaceReference: FileReference(url: workspace),
            coursePacingPlan: pacingPlan
        ))
        let store = AppStore(repository: repository)

        store.proposeWeeklyPacingRefinement(from: "Students struggled, so we need more reteach time.")
        store.acceptWeeklyPacingRefinement()

        let savedWeeklyPlan = try XCTUnwrap(repository.loadWeeklyPlan(for: store.weeklyPlan.weekOf))
        XCTAssertEqual(savedWeeklyPlan.pacingRefinementProposal?.status, .accepted)
        let savedPacingPlan = try XCTUnwrap(repository.loadConfiguration()?.coursePacingPlan)
        XCTAssertEqual(savedPacingPlan.units.first?.startDate, unitStartDate.addingTimeInterval(86_400))
        XCTAssertEqual(savedPacingPlan.units.first?.endDate, unitEndDate.addingTimeInterval(86_400))
        XCTAssertEqual(savedPacingPlan.units.first?.modules.first?.startDate, moduleStartDate.addingTimeInterval(86_400))
        XCTAssertEqual(savedPacingPlan.units.first?.modules.first?.lessons.first?.startDate, lessonStartDate.addingTimeInterval(86_400))
        XCTAssertTrue(savedPacingPlan.teacherRefinementNotes.contains("Original note."))
        XCTAssertTrue(savedPacingPlan.teacherRefinementNotes.contains("Consider adding support time before moving ahead."))
        XCTAssertTrue(savedPacingPlan.teacherRefinementNotes.contains("Affected area: Current module and next assessment window."))
        XCTAssertTrue(savedPacingPlan.teacherRefinementNotes.contains("Suggested date shift: 1 instructional day(s)."))
        XCTAssertTrue(savedPacingPlan.teacherRefinementNotes.contains("Applied to 4 pacing date field(s)."))
        XCTAssertTrue(savedPacingPlan.teacherRefinementNotes.contains("Teacher check-in: Students struggled, so we need more reteach time."))
    }

    @MainActor
    func testAppStoreAcceptsGeneralWeeklyPacingRefinementWithoutDateShift() throws {
        let repository = try makeRepository()
        let workspace = repository.rootURL.appending(path: "workspace")
        let unitStartDate = Date(timeIntervalSince1970: 1_700_000_000)
        let pacingPlan = CoursePacingPlan(
            id: UUID(),
            sourceReferenceNames: ["Pacing Guide.pdf"],
            units: [
                CoursePacingUnit(
                    id: UUID(),
                    sequence: 1,
                    title: "Unit 1",
                    startDate: unitStartDate,
                    endDate: nil,
                    estimatedInstructionalDays: 1,
                    modules: [
                        CoursePacingModule(
                            id: UUID(),
                            sequence: 1,
                            title: "Module 1",
                            estimatedInstructionalDays: 1,
                            lessons: [
                                CoursePacingLesson(
                                    id: UUID(),
                                    sequence: 1,
                                    title: "Lesson 1",
                                    estimatedInstructionalDays: 1,
                                    dependencyNotes: "",
                                    sourceNotes: ""
                                )
                            ],
                            notes: ""
                        )
                    ],
                    assessmentWindows: [],
                    skippedDays: [],
                    notes: ""
                )
            ],
            teacherRefinementNotes: "",
            reviewStatus: .approved,
            createdAt: .now,
            updatedAt: .now
        )
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Generic QA Workspace",
            workspaceReference: FileReference(url: workspace),
            coursePacingPlan: pacingPlan
        ))
        let store = AppStore(repository: repository)

        store.proposeWeeklyPacingRefinement(from: "Parent conferences changed the rhythm of the week.")
        store.acceptWeeklyPacingRefinement()

        let savedPacingPlan = try XCTUnwrap(repository.loadConfiguration()?.coursePacingPlan)
        XCTAssertEqual(savedPacingPlan.units.first?.startDate, unitStartDate)
        XCTAssertTrue(savedPacingPlan.teacherRefinementNotes.contains("Suggested date shift: 0 instructional day(s)."))
        XCTAssertTrue(savedPacingPlan.teacherRefinementNotes.contains("No dated pacing fields were changed."))
    }

    func testWeeklyPacingSuggestionsUseApprovedDatedPacing() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let weekOf = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 14)))
        let lessonDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 15)))
        var lesson = LessonRecord.draft(title: "Lesson 1: Shapes")
        lesson.status = .approved
        let pacingPlan = CoursePacingPlan(
            id: UUID(),
            sourceReferenceNames: ["Pacing Guide.pdf"],
            units: [
                CoursePacingUnit(
                    id: UUID(),
                    sequence: 1,
                    title: "Unit 2: Geometry",
                    startDate: lessonDate,
                    endDate: nil,
                    estimatedInstructionalDays: 1,
                    modules: [
                        CoursePacingModule(
                            id: UUID(),
                            sequence: 1,
                            title: "Module 1",
                            estimatedInstructionalDays: 1,
                            lessons: [
                                CoursePacingLesson(
                                    id: UUID(),
                                    sequence: 1,
                                    title: "Lesson 1: Shapes",
                                    estimatedInstructionalDays: 1,
                                    dependencyNotes: "",
                                    sourceNotes: ""
                                )
                            ],
                            notes: ""
                        )
                    ],
                    assessmentWindows: [],
                    skippedDays: [],
                    notes: ""
                )
            ],
            teacherRefinementNotes: "Start Tuesday.",
            reviewStatus: .approved,
            createdAt: .now,
            updatedAt: .now
        )
        let weeklyPlan = WeeklyPlan(weekOf: weekOf, planningBrief: nil, assignments: [], updatedAt: .now)

        let report = WeeklyPacingSuggestionReport.analyze(weeklyPlan: weeklyPlan, pacingPlan: pacingPlan, lessons: [lesson], calendar: calendar)

        XCTAssertTrue(report.canSuggestFromPacing)
        XCTAssertEqual(report.suggestions.count, 1)
        XCTAssertEqual(report.suggestions.first?.suggestedDate, lessonDate)
        XCTAssertEqual(report.suggestions.first?.lessonRecordID, lesson.id)
        XCTAssertEqual(report.suggestions.first?.status, .readyToSchedule)
    }

    func testWeeklyPacingSuggestionsPreferLessonSpecificDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let weekOf = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 14)))
        let unitDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 14)))
        let lessonDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 17)))
        var lesson = LessonRecord.draft(title: "Lesson 2: Attributes")
        lesson.status = .approved
        let pacingPlan = CoursePacingPlan(
            id: UUID(),
            sourceReferenceNames: ["Pacing Guide.pdf"],
            units: [
                CoursePacingUnit(
                    id: UUID(),
                    sequence: 1,
                    title: "Unit 2: Geometry",
                    startDate: unitDate,
                    endDate: nil,
                    estimatedInstructionalDays: 1,
                    modules: [
                        CoursePacingModule(
                            id: UUID(),
                            sequence: 1,
                            title: "Module 1",
                            estimatedInstructionalDays: 1,
                            lessons: [
                                CoursePacingLesson(
                                    id: UUID(),
                                    sequence: 1,
                                    title: "Lesson 2: Attributes",
                                    startDate: lessonDate,
                                    endDate: nil,
                                    estimatedInstructionalDays: 1,
                                    dependencyNotes: "",
                                    sourceNotes: ""
                                )
                            ],
                            notes: ""
                        )
                    ],
                    assessmentWindows: [],
                    skippedDays: [],
                    notes: ""
                )
            ],
            teacherRefinementNotes: "",
            reviewStatus: .approved,
            createdAt: .now,
            updatedAt: .now
        )
        let weeklyPlan = WeeklyPlan(weekOf: weekOf, planningBrief: nil, assignments: [], updatedAt: .now)

        let report = WeeklyPacingSuggestionReport.analyze(weeklyPlan: weeklyPlan, pacingPlan: pacingPlan, lessons: [lesson], calendar: calendar)

        XCTAssertEqual(report.suggestions.first?.suggestedDate, lessonDate)
    }

    func testWeeklyPacingSuggestionsMarkAlreadyScheduledLessons() throws {
        let weekOf = Date(timeIntervalSince1970: 1_700_000_000)
        var lesson = LessonRecord.draft(title: "Lesson 1: Compare numbers")
        lesson.status = .approved
        let assignment = WeeklyLessonAssignment(
            id: UUID(),
            lessonRecordID: lesson.id,
            date: weekOf,
            start: weekOf,
            end: weekOf.addingTimeInterval(2_700),
            planningNotes: nil
        )
        let pacingPlan = CoursePacingPlan(
            id: UUID(),
            sourceReferenceNames: ["Pacing Guide.pdf"],
            units: [
                CoursePacingUnit(
                    id: UUID(),
                    sequence: 1,
                    title: "Unit 1",
                    startDate: nil,
                    endDate: nil,
                    estimatedInstructionalDays: 1,
                    modules: [
                        CoursePacingModule(
                            id: UUID(),
                            sequence: 1,
                            title: "Module 1",
                            estimatedInstructionalDays: 1,
                            lessons: [
                                CoursePacingLesson(
                                    id: UUID(),
                                    sequence: 1,
                                    title: "Lesson 1: Compare numbers",
                                    estimatedInstructionalDays: 1,
                                    dependencyNotes: "",
                                    sourceNotes: ""
                                )
                            ],
                            notes: ""
                        )
                    ],
                    assessmentWindows: ["Unit quiz"],
                    skippedDays: [],
                    notes: ""
                )
            ],
            teacherRefinementNotes: "",
            reviewStatus: .approved,
            createdAt: .now,
            updatedAt: .now
        )
        let weeklyPlan = WeeklyPlan(weekOf: weekOf, planningBrief: nil, assignments: [assignment], updatedAt: .now)

        let report = WeeklyPacingSuggestionReport.analyze(weeklyPlan: weeklyPlan, pacingPlan: pacingPlan, lessons: [lesson])

        XCTAssertEqual(report.suggestions.count, 1)
        XCTAssertEqual(report.suggestions.first?.status, .alreadyScheduled)
    }

    @MainActor
    func testAppStoreCreatesDraftLessonFromPacingSuggestion() throws {
        let repository = try makeRepository()
        let workspace = repository.rootURL.appending(path: "workspace")
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Generic QA Workspace",
            workspaceReference: FileReference(url: workspace)
        ))
        let store = AppStore(repository: repository)
        let suggestion = WeeklyPacingSuggestion(
            id: "unit-module-lesson",
            unitTitle: "Unit 1",
            moduleTitle: "Module 1",
            pacingLessonTitle: "Lesson 3: Equivalent fractions",
            suggestedDate: Date(timeIntervalSince1970: 1_700_000_000),
            estimatedInstructionalDay: 3,
            estimatedInstructionalDays: 1,
            lessonRecordID: nil,
            lessonRecordTitle: nil,
            status: .needsApprovedLesson
        )

        store.createDraftLesson(from: suggestion)

        let savedLesson = try XCTUnwrap(try repository.loadLessons().first)
        XCTAssertEqual(savedLesson.status, .draft)
        XCTAssertEqual(savedLesson.title, "Lesson 3: Equivalent fractions")
        XCTAssertEqual(savedLesson.sourceReferences, ["Pacing: Unit 1 / Module 1 / Lesson 3: Equivalent fractions"])
        XCTAssertEqual(savedLesson.aiReviewWarnings, ["Created from approved course pacing. Add teacher-reviewed lesson content before approval."])
        XCTAssertEqual(store.mostRecentLessonID, savedLesson.id)
    }

    @MainActor
    func testAppStorePersistsStarterCoursePacingFromReviewedSources() throws {
        let repository = try makeRepository()
        let workspace = repository.rootURL.appending(path: "workspace")
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Generic QA Workspace",
            workspaceReference: FileReference(url: workspace)
        ))
        try repository.saveImportedSources([
            ImportedSource(
                id: UUID(),
                reference: FileReference(url: URL(fileURLWithPath: "/tmp/Pacing Guide.pdf")),
                extractionMethod: .embeddedText,
                confidence: nil,
                extractedText: "Unit 2: Geometry\nLesson 1: Shapes\nLesson 2: Attributes",
                reviewStatus: .reviewed,
                importedAt: .now,
                updatedAt: .now
            )
        ])
        let store = AppStore(repository: repository)

        store.createStarterCoursePacingPlanFromReviewedSources()
        store.updateCoursePacingRefinementNotes("Lost one day to assembly.")
        store.approveCoursePacingPlan()

        let savedPlan = try XCTUnwrap(repository.loadConfiguration()?.coursePacingPlan)
        XCTAssertEqual(savedPlan.reviewStatus, .approved)
        XCTAssertEqual(savedPlan.lessonCount, 2)
        XCTAssertEqual(savedPlan.teacherRefinementNotes, "Lost one day to assembly.")
        XCTAssertTrue(store.coursePacingReadinessReport.canGovernWeeklyPlanning)
    }

    @MainActor
    func testAppStoreCreatesStarterCoursePacingFromReadableImportedSourcesWithoutManualReview() throws {
        let repository = try makeRepository()
        let workspace = repository.rootURL.appending(path: "workspace")
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Generic QA Workspace",
            workspaceReference: FileReference(url: workspace)
        ))
        try repository.saveImportedSources([
            ImportedSource(
                id: UUID(),
                reference: FileReference(url: URL(fileURLWithPath: "/tmp/Pacing Guide.docx")),
                setupRole: .pacingGuide,
                extractionMethod: .embeddedText,
                confidence: nil,
                extractedText: "Unit 3: Measurement\nLesson 1: Length\nLesson 2: Area",
                reviewStatus: .imported,
                importedAt: .now,
                updatedAt: .now
            )
        ])
        let store = AppStore(repository: repository)

        store.createStarterCoursePacingPlanFromReviewedSources()

        let savedPlan = try XCTUnwrap(repository.loadConfiguration()?.coursePacingPlan)
        XCTAssertEqual(savedPlan.sourceReferenceNames, ["Pacing Guide.docx"])
        XCTAssertEqual(savedPlan.lessonCount, 2)
    }

    @MainActor
    func testAppStorePersistsWeeklyPlanningPromptPreference() throws {
        let repository = try makeRepository()
        let workspace = repository.rootURL.appending(path: "workspace")
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Generic QA Workspace",
            workspaceReference: FileReference(url: workspace)
        ))
        let store = AppStore(repository: repository)
        let preference = WeeklyPlanningPromptPreference(isEnabled: false, day: .sunday, hour: 9, minute: 45)

        store.setWeeklyPlanningPrompt(preference)

        XCTAssertEqual(store.weeklyPlanningPromptPreference, preference)
        XCTAssertEqual(try repository.loadConfiguration()?.weeklyPlanningPrompt, preference)
    }

    func testWeeklyPlanningPromptComputesNextPromptDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let preference = WeeklyPlanningPromptPreference(isEnabled: true, day: .friday, hour: 15, minute: 30)
        let current = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 28, hour: 11)))

        let nextPrompt = try XCTUnwrap(preference.nextPromptDate(after: current, calendar: calendar))
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: nextPrompt)

        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 7)
        XCTAssertEqual(components.day, 31)
        XCTAssertEqual(components.weekday, WeeklyPlanningPromptDay.friday.rawValue)
        XCTAssertEqual(components.hour, 15)
        XCTAssertEqual(components.minute, 30)
    }

    func testWeeklyPlanningPromptStatusIsDueAfterPromptTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let preference = WeeklyPlanningPromptPreference(isEnabled: true, day: .friday, hour: 15, minute: 30)
        let current = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 31, hour: 16)))

        let status = WeeklyPlanningPromptStatus.evaluate(
            preference: preference,
            lastHandledAt: nil,
            now: current,
            calendar: calendar
        )

        XCTAssertTrue(status.isDue)
        XCTAssertEqual(status.duePromptDate, try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 31, hour: 15, minute: 30))))
    }

    func testWeeklyPlanningPromptStatusIsNotDueAfterHandlingPrompt() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let preference = WeeklyPlanningPromptPreference(isEnabled: true, day: .friday, hour: 15, minute: 30)
        let handled = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 31, hour: 16)))
        let current = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 31, hour: 17)))

        let status = WeeklyPlanningPromptStatus.evaluate(
            preference: preference,
            lastHandledAt: handled,
            now: current,
            calendar: calendar
        )

        XCTAssertFalse(status.isDue)
        XCTAssertNil(status.duePromptDate)
    }

    @MainActor
    func testAppStoreMarksWeeklyPlanningPromptHandled() throws {
        let repository = try makeRepository()
        let workspace = repository.rootURL.appending(path: "workspace")
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Generic QA Workspace",
            workspaceReference: FileReference(url: workspace)
        ))
        let store = AppStore(repository: repository)
        let handled = Date(timeIntervalSince1970: 1_785_000_000)

        store.markWeeklyPlanningPromptHandled(at: handled)

        XCTAssertEqual(try repository.loadConfiguration()?.weeklyPlanningPromptLastHandledAt, handled)
    }

    @MainActor
    func testAppStoreRegistersPresentationTemplateWithDefaultMappings() throws {
        let repository = try makeRepository()
        let workspace = repository.rootURL.appending(path: "workspace")
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Generic QA Workspace",
            workspaceReference: FileReference(url: workspace)
        ))
        let templateURL = repository.rootURL.appending(path: "generic-template.pptx")
        let store = AppStore(repository: repository)

        store.registerPresentationTemplate(templateURL)

        let template = try XCTUnwrap(repository.loadConfiguration()?.outputTemplates.first)
        XCTAssertEqual(template.kind, .presentation)
        XCTAssertEqual(template.slotMappings, TemplateSlotMapping.defaultPresentationMappings)
    }

    func testPowerPointOutputReviewChecklistIncludesCompatibilityChecks() {
        let checklist = GeneratedOutputReview.checklist(for: .slideDeckPPTX)
        XCTAssertTrue(checklist.contains("Opened the deck in PowerPoint or a compatible viewer."))
        XCTAssertTrue(checklist.contains("Confirmed speaker notes keep source provenance."))
        XCTAssertTrue(checklist.contains("Confirmed presentation-template provenance and mapping notes when a template was used."))
        XCTAssertTrue(checklist.contains("If a presentation template is registered, checked that output does not claim true layout preservation unless template fidelity QA was completed."))
        XCTAssertTrue(checklist.contains("If using Google Slides, checked upload conversion fidelity."))
    }

    func testPresentationTemplateReadinessBlocksMissingTemplate() {
        let report = PresentationTemplateReadinessReport.analyze(configuration: nil)

        XCTAssertFalse(report.canUseTemplateMetadata)
        XCTAssertEqual(report.blockingMetadataIssues, [.noPresentationTemplate])
        XCTAssertFalse(report.isReadyForLayoutPreservation)
    }

    func testPresentationTemplateReadinessAllowsDefaultMappingsButKeepsLayoutInventoryPending() {
        let template = OutputTemplateRegistration(
            id: UUID(),
            displayName: "generic-template.pptx",
            kind: .presentation,
            reference: FileReference(url: URL(fileURLWithPath: "/tmp/generic-template.pptx")),
            preserveLayout: true,
            slotMappings: TemplateSlotMapping.defaultPresentationMappings,
            addedAt: .now
        )
        let configuration = AppConfiguration(
            workspaceName: "Generic QA Workspace",
            workspaceReference: FileReference(url: URL(fileURLWithPath: "/tmp/workspace")),
            outputTemplates: [template]
        )

        let report = PresentationTemplateReadinessReport.analyze(configuration: configuration)

        XCTAssertTrue(report.canUseTemplateMetadata)
        XCTAssertEqual(report.mappedFieldCount, TemplateSlotMapping.defaultPresentationMappings.count)
        XCTAssertEqual(report.requiredMappedFieldCount, TemplateSlotMapping.defaultPresentationMappings.filter(\.required).count)
        XCTAssertEqual(report.issues, [.layoutInventoryPending, .frameMapPending, .fidelityQAPending])
        XCTAssertFalse(report.isReadyForLayoutPreservation)
    }

    func testPresentationTemplateReadinessAcceptsInventoryFrameMapAndFidelityQA() {
        let template = OutputTemplateRegistration(
            id: UUID(),
            displayName: "generic-template.pptx",
            kind: .presentation,
            reference: FileReference(url: URL(fileURLWithPath: "/tmp/generic-template.pptx")),
            preserveLayout: true,
            slotMappings: TemplateSlotMapping.defaultPresentationMappings,
            layoutPlan: PresentationTemplateLayoutPlan(
                slideInventory: [
                    PresentationTemplateSlideInventoryItem(id: UUID(), sourceSlideNumber: 1, reusableRole: "Opening", placeholderCount: 2, notes: "")
                ],
                frameMap: [
                    PresentationTemplateFrameMapEntry(id: UUID(), outputSlideNumber: 1, sourceSlideNumber: 1, narrativeRole: "Opening", mappedSlotNames: ["lesson.title"], notes: "")
                ],
                fidelityReviewCompleted: true,
                updatedAt: .now
            ),
            addedAt: .now
        )
        let configuration = AppConfiguration(
            workspaceName: "Generic QA Workspace",
            workspaceReference: FileReference(url: URL(fileURLWithPath: "/tmp/workspace")),
            outputTemplates: [template]
        )

        let report = PresentationTemplateReadinessReport.analyze(configuration: configuration)

        XCTAssertTrue(report.isReadyForLayoutPreservation)
        XCTAssertTrue(report.issues.isEmpty)
        XCTAssertEqual(report.inventorySlideCount, 1)
        XCTAssertEqual(report.frameMapCount, 1)
    }

    func testPresentationTemplateReadinessRequiresFrameMapAndFidelityQA() {
        let template = OutputTemplateRegistration(
            id: UUID(),
            displayName: "generic-template.pptx",
            kind: .presentation,
            reference: FileReference(url: URL(fileURLWithPath: "/tmp/generic-template.pptx")),
            preserveLayout: true,
            slotMappings: TemplateSlotMapping.defaultPresentationMappings,
            layoutPlan: PresentationTemplateLayoutPlan(
                slideInventory: [
                    PresentationTemplateSlideInventoryItem(id: UUID(), sourceSlideNumber: 1, reusableRole: "Opening", placeholderCount: 2, notes: "")
                ],
                frameMap: [],
                fidelityReviewCompleted: false,
                updatedAt: .now
            ),
            addedAt: .now
        )
        let configuration = AppConfiguration(
            workspaceName: "Generic QA Workspace",
            workspaceReference: FileReference(url: URL(fileURLWithPath: "/tmp/workspace")),
            outputTemplates: [template]
        )

        let report = PresentationTemplateReadinessReport.analyze(configuration: configuration)

        XCTAssertTrue(report.canUseTemplateMetadata)
        XCTAssertEqual(report.issues, [.frameMapPending, .fidelityQAPending])
        XCTAssertFalse(report.isReadyForLayoutPreservation)
    }

    @MainActor
    func testPowerPointTemplateInspectorCreatesLayoutCandidatesFromNativeDeck() async throws {
        let repository = try makeRepository()
        let deckURL = repository.rootURL.appending(path: "candidate-template.pptx")
        var lesson = LessonRecord.draft(title: "Fraction Strategies")
        lesson.objective = "Use models to compare fractions."
        lesson.status = .approved
        lesson.instructionalSequence = [
            InstructionalStep(id: UUID(), title: "Launch", notes: "Review equal parts."),
            InstructionalStep(id: UUID(), title: "Model", notes: "Compare benchmark fractions.")
        ]
        lesson.materials = ["Fraction strips"]
        lesson.printableResourcePrompt = "Compare three fraction pairs."
        lesson.assessmentSummary = "Exit ticket."
        try await NativePowerPointExporter.generate(lesson: lesson, destination: deckURL)

        let result = try PowerPointTemplateInspector.inspect(url: deckURL)

        XCTAssertEqual(result.slideInventory.map(\.sourceSlideNumber), [1, 2, 3, 4, 5])
        XCTAssertEqual(result.frameMap.map(\.outputSlideNumber), [1, 2, 3, 4, 5])
        XCTAssertEqual(result.slideInventory.first?.reusableRole, "Opening")
        XCTAssertTrue(result.frameMap.first?.mappedSlotNames.contains("lesson.title") == true)
        XCTAssertTrue(result.frameMap.contains { $0.mappedSlotNames.contains("lesson.assessment") })
    }

    func testPowerPointTemplateInspectorReadsCompressedPowerPointPackage() throws {
        let repository = try makeRepository()
        let packageRoot = repository.rootURL.appending(path: "package")
        let slidesFolder = packageRoot.appending(path: "ppt/slides")
        try FileManager.default.createDirectory(at: slidesFolder, withIntermediateDirectories: true)
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
          <p:cSld><p:spTree><p:sp><p:nvSpPr><p:cNvPr id="2" name="Assessment"/></p:nvSpPr><p:txBody>assessment</p:txBody></p:sp></p:spTree></p:cSld>
        </p:sld>
        """.write(to: slidesFolder.appending(path: "slide1.xml"), atomically: true, encoding: .utf8)
        let destination = repository.rootURL.appending(path: "compressed-template.pptx")
        try runZip(cwd: packageRoot, destination: destination)

        let result = try PowerPointTemplateInspector.inspect(url: destination)

        XCTAssertEqual(result.slideInventory.count, 1)
        XCTAssertEqual(result.slideInventory.first?.reusableRole, "Opening")
        XCTAssertEqual(result.frameMap.first?.sourceSlideNumber, 1)
    }

    func testOOXMLPlaceholderResolutionInheritsGeometryThroughFullChain() {
        let slide = [OOXMLPlaceholderShape(shapeID: 2, shapeName: "Title", type: "title", idx: 0, frame: nil)]
        let layout = [OOXMLPlaceholderShape(shapeID: 4, shapeName: "Title Placeholder", type: "title", idx: 0, frame: nil)]
        let master = [OOXMLPlaceholderShape(shapeID: 6, shapeName: "Title Style", type: "title", idx: 0, frame: OOXMLFrame(x: 111, y: 222, cx: 333, cy: 444))]

        let resolved = OOXMLPlaceholderResolution.resolve(slideShapes: slide, layoutShapes: layout, masterShapes: master)

        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(resolved[0].frameSource, .master)
        XCTAssertEqual(resolved[0].effectiveFrame, OOXMLFrame(x: 111, y: 222, cx: 333, cy: 444))
    }

    func testOOXMLPlaceholderResolutionSlideGeometryOverridesInheritance() {
        let slide = [OOXMLPlaceholderShape(shapeID: 2, shapeName: "Title", type: "title", idx: 0, frame: OOXMLFrame(x: 1, y: 2, cx: 3, cy: 4))]
        let layout = [OOXMLPlaceholderShape(shapeID: 4, shapeName: "Title Placeholder", type: "title", idx: 0, frame: OOXMLFrame(x: 100, y: 200, cx: 300, cy: 400))]

        let resolved = OOXMLPlaceholderResolution.resolve(slideShapes: slide, layoutShapes: layout, masterShapes: [])

        XCTAssertEqual(resolved[0].frameSource, .slide)
        XCTAssertEqual(resolved[0].effectiveFrame, OOXMLFrame(x: 1, y: 2, cx: 3, cy: 4))
    }

    func testOOXMLPlaceholderResolutionFallsBackToTypeMatchWhenIdxUnmatched() {
        // Mirrors a real Google-Slides-export quirk: the slide references an idx the
        // layout doesn't have, so matching must fall back to placeholder type.
        let slide = [OOXMLPlaceholderShape(shapeID: 2, shapeName: "Body", type: "body", idx: 5, frame: nil)]
        let layout = [OOXMLPlaceholderShape(shapeID: 3, shapeName: "Content Placeholder", type: "body", idx: 1, frame: OOXMLFrame(x: 10, y: 20, cx: 30, cy: 40))]

        let resolved = OOXMLPlaceholderResolution.resolve(slideShapes: slide, layoutShapes: layout, masterShapes: [])

        XCTAssertEqual(resolved[0].frameSource, .layout)
        XCTAssertEqual(resolved[0].effectiveFrame, OOXMLFrame(x: 10, y: 20, cx: 30, cy: 40))
        XCTAssertEqual(resolved[0].effectiveIdx, 5, "the slide's own declared idx is preserved even though the match came via type")
    }

    func testOOXMLPlaceholderResolutionBreaksDuplicateIdxTiesByType() {
        // A layout that reuses idx="1" across two different placeholder types (a real,
        // if malformed, pattern) should not resolve to whichever shape happens first.
        let slide = [OOXMLPlaceholderShape(shapeID: 2, shapeName: "Body", type: "body", idx: 1, frame: nil)]
        let layout = [
            OOXMLPlaceholderShape(shapeID: 5, shapeName: "Date Placeholder", type: "dt", idx: 1, frame: OOXMLFrame(x: 1, y: 1, cx: 1, cy: 1)),
            OOXMLPlaceholderShape(shapeID: 6, shapeName: "Body Placeholder", type: "body", idx: 1, frame: OOXMLFrame(x: 50, y: 60, cx: 70, cy: 80))
        ]

        let resolved = OOXMLPlaceholderResolution.resolve(slideShapes: slide, layoutShapes: layout, masterShapes: [])

        XCTAssertEqual(resolved[0].effectiveFrame, OOXMLFrame(x: 50, y: 60, cx: 70, cy: 80))
    }

    func testOOXMLPlaceholderResolutionTreatsCtrTitleAndTitleAsSameSlot() {
        let slide = [OOXMLPlaceholderShape(shapeID: 2, shapeName: "Title", type: "ctrTitle", idx: nil, frame: nil)]
        let layout = [OOXMLPlaceholderShape(shapeID: 5, shapeName: "Title Placeholder", type: "title", idx: 0, frame: OOXMLFrame(x: 7, y: 8, cx: 9, cy: 10))]

        let resolved = OOXMLPlaceholderResolution.resolve(slideShapes: slide, layoutShapes: layout, masterShapes: [])

        XCTAssertEqual(resolved[0].frameSource, .layout)
        XCTAssertEqual(resolved[0].effectiveFrame, OOXMLFrame(x: 7, y: 8, cx: 9, cy: 10))
        XCTAssertEqual(resolved[0].effectiveType, "ctrTitle", "the slide's own declared type is preserved, not normalized")
    }

    func testOOXMLPlaceholderResolutionUnmatchedPlaceholderHasNoFrame() {
        let slide = [OOXMLPlaceholderShape(shapeID: 2, shapeName: "Body", type: "body", idx: 1, frame: nil)]

        let resolved = OOXMLPlaceholderResolution.resolve(slideShapes: slide, layoutShapes: [], masterShapes: [])

        XCTAssertEqual(resolved[0].frameSource, .none)
        XCTAssertNil(resolved[0].effectiveFrame)
        XCTAssertEqual(resolved[0].effectiveType, "body")
        XCTAssertEqual(resolved[0].effectiveIdx, 1)
    }

    func testPowerPointTemplateInspectorResolvesPlaceholdersAcrossSlideLayoutAndMaster() throws {
        let repository = try makeRepository()
        let packageRoot = repository.rootURL.appending(path: "template-package")
        let pptFolder = packageRoot.appending(path: "ppt")
        let slidesFolder = pptFolder.appending(path: "slides")
        let slideRelsFolder = slidesFolder.appending(path: "_rels")
        let layoutsFolder = pptFolder.appending(path: "slideLayouts")
        let layoutRelsFolder = layoutsFolder.appending(path: "_rels")
        let mastersFolder = pptFolder.appending(path: "slideMasters")
        for folder in [slidesFolder, slideRelsFolder, layoutsFolder, layoutRelsFolder, mastersFolder] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }

        // Slide declares a title placeholder with no geometry of its own (must fall all
        // the way through to the master, since the layout below doesn't redefine title)
        // and a body placeholder with no geometry (must inherit from the layout's override).
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
          <p:cSld><p:spTree>
            <p:sp><p:nvSpPr><p:cNvPr id="2" name="Title 1"/><p:cNvSpPr/><p:nvPr><p:ph type="title" idx="0"/></p:nvPr></p:nvSpPr><p:spPr/></p:sp>
            <p:sp><p:nvSpPr><p:cNvPr id="3" name="Body 1"/><p:cNvSpPr/><p:nvPr><p:ph type="body" idx="1"/></p:nvPr></p:nvSpPr><p:spPr/></p:sp>
          </p:spTree></p:cSld>
        </p:sld>
        """.write(to: slidesFolder.appending(path: "slide1.xml"), atomically: true, encoding: .utf8)

        try """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
        </Relationships>
        """.write(to: slideRelsFolder.appending(path: "slide1.xml.rels"), atomically: true, encoding: .utf8)

        // Layout redefines only the body placeholder's geometry; title is left to the master.
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <p:sldLayout xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
          <p:cSld><p:spTree>
            <p:sp><p:nvSpPr><p:cNvPr id="2" name="Body Placeholder"/><p:cNvSpPr/><p:nvPr><p:ph type="body" idx="1"/></p:nvPr></p:nvSpPr>
              <p:spPr><a:xfrm><a:off x="500000" y="1800000"/><a:ext cx="8000000" cy="4000000"/></a:xfrm></p:spPr>
            </p:sp>
          </p:spTree></p:cSld>
        </p:sldLayout>
        """.write(to: layoutsFolder.appending(path: "slideLayout1.xml"), atomically: true, encoding: .utf8)

        try """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="../slideMasters/slideMaster1.xml"/>
        </Relationships>
        """.write(to: layoutRelsFolder.appending(path: "slideLayout1.xml.rels"), atomically: true, encoding: .utf8)

        // Master defines geometry for both the title and body placeholders; only the
        // title's should surface, since the layout overrides body itself.
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <p:sldMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
          <p:cSld><p:spTree>
            <p:sp><p:nvSpPr><p:cNvPr id="2" name="Title Placeholder"/><p:cNvSpPr/><p:nvPr><p:ph type="title" idx="0"/></p:nvPr></p:nvSpPr>
              <p:spPr><a:xfrm><a:off x="1000000" y="1000000"/><a:ext cx="8000000" cy="1200000"/></a:xfrm></p:spPr>
            </p:sp>
            <p:sp><p:nvSpPr><p:cNvPr id="3" name="Body Placeholder"/><p:cNvSpPr/><p:nvPr><p:ph type="body" idx="1"/></p:nvPr></p:nvSpPr>
              <p:spPr><a:xfrm><a:off x="1000000" y="2500000"/><a:ext cx="8000000" cy="3000000"/></a:xfrm></p:spPr>
            </p:sp>
          </p:spTree></p:cSld>
        </p:sldMaster>
        """.write(to: mastersFolder.appending(path: "slideMaster1.xml"), atomically: true, encoding: .utf8)

        let destination = repository.rootURL.appending(path: "layout-inheritance-template.pptx")
        try runZip(cwd: packageRoot, destination: destination)

        let result = try PowerPointTemplateInspector.resolvePlaceholders(url: destination)

        XCTAssertEqual(result.count, 1)
        let placeholders = result[0].placeholders
        XCTAssertEqual(placeholders.count, 2)

        let title = try XCTUnwrap(placeholders.first { $0.effectiveType == "title" })
        XCTAssertEqual(title.shapeID, 2)
        XCTAssertEqual(title.frameSource, .master)
        XCTAssertEqual(title.effectiveFrame, OOXMLFrame(x: 1_000_000, y: 1_000_000, cx: 8_000_000, cy: 1_200_000))

        let body = try XCTUnwrap(placeholders.first { $0.effectiveType == "body" })
        XCTAssertEqual(body.shapeID, 3)
        XCTAssertEqual(body.frameSource, .layout)
        XCTAssertEqual(body.effectiveFrame, OOXMLFrame(x: 500_000, y: 1_800_000, cx: 8_000_000, cy: 4_000_000))
    }

    @MainActor
    func testAppStorePersistsPresentationTemplateLayoutPlan() throws {
        let repository = try makeRepository()
        let workspace = repository.rootURL.appending(path: "workspace")
        let templateURL = repository.rootURL.appending(path: "generic-template.pptx")
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Generic QA Workspace",
            workspaceReference: FileReference(url: workspace)
        ))
        let store = AppStore(repository: repository)
        store.registerPresentationTemplate(templateURL)
        let templateID = try XCTUnwrap(store.activePresentationTemplate?.id)
        let inventory = [
            PresentationTemplateSlideInventoryItem(id: UUID(), sourceSlideNumber: 2, reusableRole: "Lesson body", placeholderCount: 3, notes: "Use for instructional sequence.")
        ]
        let frameMap = [
            PresentationTemplateFrameMapEntry(id: UUID(), outputSlideNumber: 1, sourceSlideNumber: 2, narrativeRole: "Instruction", mappedSlotNames: ["lesson.steps"], notes: "")
        ]

        store.updatePresentationTemplateLayoutPlan(
            templateID: templateID,
            slideInventory: inventory,
            frameMap: frameMap,
            fidelityReviewCompleted: true
        )

        let savedTemplate = try XCTUnwrap(repository.loadConfiguration()?.outputTemplates.first(where: { $0.id == templateID }))
        XCTAssertEqual(savedTemplate.layoutPlan?.slideInventory, inventory)
        XCTAssertEqual(savedTemplate.layoutPlan?.frameMap, frameMap)
        XCTAssertEqual(savedTemplate.layoutPlan?.fidelityReviewCompleted, true)
    }

    @MainActor
    func testAppStoreInspectsPresentationTemplateLayoutPlan() async throws {
        let repository = try makeRepository()
        let workspace = repository.rootURL.appending(path: "workspace")
        let templateURL = repository.rootURL.appending(path: "generic-template.pptx")
        var lesson = LessonRecord.draft(title: "Template Candidate")
        lesson.objective = "Plan from a template."
        lesson.status = .approved
        lesson.instructionalSequence = [InstructionalStep(id: UUID(), title: "Teach", notes: "Use guided practice.")]
        lesson.assessmentSummary = "Check for understanding."
        try await NativePowerPointExporter.generate(lesson: lesson, destination: templateURL)
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Generic QA Workspace",
            workspaceReference: FileReference(url: workspace)
        ))
        let store = AppStore(repository: repository)
        store.registerPresentationTemplate(templateURL)
        let templateID = try XCTUnwrap(store.activePresentationTemplate?.id)

        store.inspectPresentationTemplateLayout(templateID: templateID)

        let savedTemplate = try XCTUnwrap(repository.loadConfiguration()?.outputTemplates.first(where: { $0.id == templateID }))
        XCTAssertEqual(savedTemplate.layoutPlan?.fidelityReviewCompleted, false)
        XCTAssertEqual(savedTemplate.layoutPlan?.slideInventory.count, 3)
        XCTAssertEqual(savedTemplate.layoutPlan?.frameMap.count, 3)

        // NativePowerPointExporter's own decks never use placeholders, so inspecting one
        // should populate one resolution per slide, each with no placeholders — proving the
        // wiring runs cleanly on the no-placeholders case rather than crashing or omitting slides.
        XCTAssertEqual(store.lastPresentationTemplatePlaceholderResolution.count, 3)
        XCTAssertTrue(store.lastPresentationTemplatePlaceholderResolution.allSatisfy { $0.placeholders.isEmpty })
    }

    @MainActor
    func testAppStoreInspectPresentationTemplateLayoutResolvesPlaceholderInheritance() throws {
        let repository = try makeRepository()
        let workspace = repository.rootURL.appending(path: "workspace")
        let packageRoot = repository.rootURL.appending(path: "template-package")
        let slidesFolder = packageRoot.appending(path: "ppt/slides")
        let slideRelsFolder = packageRoot.appending(path: "ppt/slides/_rels")
        let layoutsFolder = packageRoot.appending(path: "ppt/slideLayouts")
        let layoutRelsFolder = packageRoot.appending(path: "ppt/slideLayouts/_rels")
        let mastersFolder = packageRoot.appending(path: "ppt/slideMasters")
        for folder in [slidesFolder, slideRelsFolder, layoutsFolder, layoutRelsFolder, mastersFolder] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }

        // A slide with a title placeholder and no geometry of its own. Its layout (as
        // every real slide has — a slide never references a master directly) doesn't
        // redefine title either, so resolution must fall all the way through to the master.
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
          <p:cSld><p:spTree>
            <p:sp><p:nvSpPr><p:cNvPr id="2" name="Title 1"/><p:cNvSpPr/><p:nvPr><p:ph type="title" idx="0"/></p:nvPr></p:nvSpPr><p:spPr/></p:sp>
          </p:spTree></p:cSld>
        </p:sld>
        """.write(to: slidesFolder.appending(path: "slide1.xml"), atomically: true, encoding: .utf8)

        try """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
        </Relationships>
        """.write(to: slideRelsFolder.appending(path: "slide1.xml.rels"), atomically: true, encoding: .utf8)

        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <p:sldLayout xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
          <p:cSld><p:spTree/></p:cSld>
        </p:sldLayout>
        """.write(to: layoutsFolder.appending(path: "slideLayout1.xml"), atomically: true, encoding: .utf8)

        try """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="../slideMasters/slideMaster1.xml"/>
        </Relationships>
        """.write(to: layoutRelsFolder.appending(path: "slideLayout1.xml.rels"), atomically: true, encoding: .utf8)

        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <p:sldMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
          <p:cSld><p:spTree>
            <p:sp><p:nvSpPr><p:cNvPr id="2" name="Title Placeholder"/><p:cNvSpPr/><p:nvPr><p:ph type="title" idx="0"/></p:nvPr></p:nvSpPr>
              <p:spPr><a:xfrm><a:off x="1000000" y="1000000"/><a:ext cx="8000000" cy="1200000"/></a:xfrm></p:spPr>
            </p:sp>
          </p:spTree></p:cSld>
        </p:sldMaster>
        """.write(to: mastersFolder.appending(path: "slideMaster1.xml"), atomically: true, encoding: .utf8)

        let templateURL = repository.rootURL.appending(path: "real-template.pptx")
        try runZip(cwd: packageRoot, destination: templateURL)
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Generic QA Workspace",
            workspaceReference: FileReference(url: workspace)
        ))
        let store = AppStore(repository: repository)
        store.registerPresentationTemplate(templateURL)
        let templateID = try XCTUnwrap(store.activePresentationTemplate?.id)

        store.inspectPresentationTemplateLayout(templateID: templateID)

        XCTAssertEqual(store.lastPresentationTemplatePlaceholderResolution.count, 1)
        let placeholders = try XCTUnwrap(store.lastPresentationTemplatePlaceholderResolution.first).placeholders
        let title = try XCTUnwrap(placeholders.first)
        XCTAssertEqual(title.effectiveType, "title")
        XCTAssertEqual(title.frameSource, .master)
        XCTAssertEqual(title.effectiveFrame, OOXMLFrame(x: 1_000_000, y: 1_000_000, cx: 8_000_000, cy: 1_200_000))
    }

    func testReleaseReadinessReportFlagsConfiguredNativeWorkspaceWithoutReviewedDeckAsAttention() {
        let configuration = AppConfiguration(
            workspaceName: "Generic QA Workspace",
            workspaceReference: FileReference(url: URL(fileURLWithPath: "/tmp/workspace")),
            outputFolderReference: FileReference(url: URL(fileURLWithPath: "/tmp/outputs"))
        )

        let report = ReleaseReadinessReport.analyze(configuration: configuration, lessons: [], generatedOutputs: [])

        XCTAssertTrue(report.isReadyForPersonalQA)
        XCTAssertTrue(report.items.contains { $0.id == "native-exporter" && $0.status == .ready })
        XCTAssertTrue(report.items.contains { $0.id == "reviewed-deck" && $0.status == .attention })
    }

    func testReleaseReadinessReportFlagsMissingWorkspaceAsBlocked() {
        let report = ReleaseReadinessReport.analyze(configuration: nil, lessons: [], generatedOutputs: [])
        XCTAssertFalse(report.isReadyForPersonalQA)
        XCTAssertTrue(report.blockers.contains { $0.id == "workspace" })
        XCTAssertTrue(report.blockers.contains { $0.id == "output-folder" })
    }

    func testDailyPlanRoundTrip() throws {
        let repository = try makeRepository()
        var plan = DailyPlan.empty(for: Date(timeIntervalSince1970: 1_700_000_000))
        plan.tasks.append(DailyTask(id: UUID(), title: "Review lesson draft", status: .open, dueTime: nil, linkedLessonRecordID: nil, notes: ""))
        try repository.saveDailyPlan(plan)
        let loaded = try XCTUnwrap(repository.loadDailyPlan(for: plan.date))
        XCTAssertEqual(loaded.date.timeIntervalSince1970, plan.date.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(loaded.tasks, plan.tasks)
    }

    func testDraftLessonStartsInDraftStatus() {
        XCTAssertEqual(LessonRecord.draft().status, .draft)
    }

    func testLessonExportReadinessFlagsRequiredAndAdvisoryFields() {
        let report = LessonExportReadinessReport.analyze(LessonRecord.draft())
        XCTAssertFalse(report.isReady)
        XCTAssertEqual(report.blockingIssues, [.missingTitle, .missingObjective, .missingInstructionalSequence, .missingAssessment])
        XCTAssertEqual(report.advisoryIssues, [.missingSubjectOrGrade, .missingMaterials, .missingDifferentiation])
    }

    func testLessonExportReadinessAcceptsCompleteGenericLesson() {
        var lesson = LessonRecord.draft(title: "Fraction Strategies")
        lesson.subject = "Math"
        lesson.gradeOrAgeRange = "Grade 4"
        lesson.objective = "Compare equivalent fractions using visual models."
        lesson.instructionalSequence = [InstructionalStep(id: UUID(), title: "Model equivalent fractions", notes: "")]
        lesson.materials = ["fraction strips"]
        lesson.differentiationSummary = "Use fraction strips or a challenge comparison."
        lesson.assessmentSummary = "Exit ticket with a model and explanation."

        let report = LessonExportReadinessReport.analyze(lesson)
        XCTAssertTrue(report.isReady)
        XCTAssertTrue(report.issues.isEmpty)
    }

    @MainActor
    func testAppStoreReportsSlideDeckAvailability() throws {
        let repository = try makeRepository()
        let store = AppStore(repository: repository, slideDeckGenerator: UnavailableSlideDeckGenerator.self)
        XCTAssertFalse(store.slideDeckAvailability.isAvailable)
        XCTAssertEqual(store.slideDeckAvailability.title, "Personal PowerPoint export unavailable")
        XCTAssertEqual(store.slideDeckAvailability.detail, "Test runtime missing.")
    }

    @MainActor
    func testAppStoreDefaultsToNativePowerPointExporter() throws {
        let repository = try makeRepository()
        let workspace = repository.rootURL.appending(path: "workspace")
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Generic QA Workspace",
            workspaceReference: FileReference(url: workspace)
        ))

        let store = AppStore(repository: repository)
        XCTAssertEqual(store.slideDeckExporterPreference, .nativeOpenXML)
        XCTAssertEqual(store.slideDeckAvailability, NativePowerPointExporter.availability)
    }

    @MainActor
    func testAppStorePersistsSlideDeckExporterPreference() throws {
        let repository = try makeRepository()
        let workspace = repository.rootURL.appending(path: "workspace")
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Generic QA Workspace",
            workspaceReference: FileReference(url: workspace)
        ))

        let store = AppStore(repository: repository)
        store.setSlideDeckExporter(.personalBridge)

        let loaded = try XCTUnwrap(repository.loadConfiguration())
        XCTAssertEqual(loaded.slideDeckExporter, .personalBridge)
        XCTAssertEqual(store.slideDeckExporterPreference, .personalBridge)
        XCTAssertEqual(store.slideDeckAvailability, SlideDeckBridge.availability)
    }

    func testImportedSourceRoundTrip() throws {
        let repository = try makeRepository()
        let source = ImportedSource(
            id: UUID(), reference: FileReference(url: URL(fileURLWithPath: "/tmp/source.pdf")),
            extractionMethod: .embeddedText, confidence: nil, extractedText: "A lesson source", reviewStatus: .reviewed,
            importedAt: .now, updatedAt: .now
        )
        try repository.saveImportedSources([source])
        let loaded = try repository.loadImportedSources()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].extractedText, "A lesson source")
        XCTAssertEqual(loaded[0].extractionMethod, .embeddedText)
    }

    @MainActor
    func testAppStoreImportsDOCXDocuments() throws {
        let repository = try makeRepository()
        let docxURL = repository.rootURL.appending(path: "Scope and Sequence.docx")
        try makeDOCX(at: docxURL, paragraphs: [
            "Unit 1: Fractions",
            "Lesson 1: Equivalent fractions"
        ])
        let store = AppStore(repository: repository)

        store.importDocument(docxURL)

        let imported = try XCTUnwrap(repository.loadImportedSources().first)
        XCTAssertEqual(imported.reference.displayName, "Scope and Sequence.docx")
        XCTAssertEqual(imported.extractionMethod, .embeddedText)
        XCTAssertEqual(imported.reviewStatus, .reviewed)
        XCTAssertEqual(imported.effectiveSetupRole, .pacingGuide)
        XCTAssertTrue(imported.extractedText.contains("Unit 1: Fractions"))
        XCTAssertTrue(imported.extractedText.contains("Lesson 1: Equivalent fractions"))
    }

    @MainActor
    func testAppStoreImportsSupportedDocumentsFromFolder() throws {
        let repository = try makeRepository()
        let folderURL = repository.rootURL.appending(path: "Intake Folder")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try makeDOCX(at: folderURL.appending(path: "Curriculum Map.docx"), paragraphs: [
            "Curriculum map",
            "Unit 2: Geometry"
        ])
        try "Do not import".write(to: folderURL.appending(path: "notes.txt"), atomically: true, encoding: .utf8)
        let store = AppStore(repository: repository)

        store.importDocumentsInFolder(folderURL)

        let imported = try repository.loadImportedSources()
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported.first?.reference.displayName, "Curriculum Map.docx")
        XCTAssertEqual(imported.first?.effectiveSetupRole, .curriculumMap)
    }

    @MainActor
    func testAppStoreImportsMixedDocumentItems() throws {
        let repository = try makeRepository()
        let folderURL = repository.rootURL.appending(path: "Folder Intake")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let directDocx = repository.rootURL.appending(path: "Direct Scope.docx")
        try makeDOCX(at: directDocx, paragraphs: ["Scope and Sequence", "Unit 1"])
        try makeDOCX(at: folderURL.appending(path: "Folder Calendar.docx"), paragraphs: ["Instructional calendar", "No school Friday"])
        let store = AppStore(repository: repository)

        store.importDocumentItems([directDocx, folderURL])

        let imported = try repository.loadImportedSources()
        XCTAssertEqual(imported.count, 2)
        XCTAssertTrue(imported.contains { $0.reference.displayName == "Direct Scope.docx" })
        XCTAssertTrue(imported.contains { $0.reference.displayName == "Folder Calendar.docx" })
        XCTAssertTrue(imported.contains { $0.effectiveSetupRole == .instructionalCalendar })
    }

    @MainActor
    func testDocumentImportAutomaticallyBuildsWeeklyPlanningScaffold() throws {
        let repository = try makeRepository()
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Auto Planner",
            workspaceReference: FileReference(url: repository.rootURL),
            outputFolderReference: FileReference(url: repository.rootURL),
            sourceRegistrations: [],
            outputTemplates: []
        ))
        let docxURL = repository.rootURL.appending(path: "Scope and Sequence.docx")
        try makeDOCX(at: docxURL, paragraphs: [
            "Scope and Sequence",
            "Unit 1: Fractions",
            "Lesson 1: Equivalent fractions",
            "Lesson 2: Compare fractions"
        ])
        let store = AppStore(repository: repository)

        store.importDocumentItems([docxURL])

        let pacingPlan = try XCTUnwrap(repository.loadConfiguration()?.coursePacingPlan)
        XCTAssertEqual(pacingPlan.reviewStatus, .approved)
        XCTAssertEqual(pacingPlan.lessonCount, 2)
        XCTAssertTrue(pacingPlan.teacherRefinementNotes.contains("Auto-built from readable document intake"))
        let approvedLessons = try repository.loadLessons().filter { $0.status == .approved }
        XCTAssertEqual(approvedLessons.count, 2)
        let savedWeeklyPlan = try XCTUnwrap(repository.loadWeeklyPlan(for: store.weeklyPlan.weekOf))
        XCTAssertEqual(savedWeeklyPlan.assignments.count, 2)
        XCTAssertTrue(store.weeklyPackageReadinessReport.canGenerate)
    }

    @MainActor
    func testReloadBackfillsWeeklyPlannerFromExistingImportedWeekPacket() throws {
        let repository = try makeRepository()
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Existing Packet",
            workspaceReference: FileReference(url: repository.rootURL),
            outputFolderReference: FileReference(url: repository.rootURL),
            sourceRegistrations: [],
            outputTemplates: []
        ))
        let sourceURL = repository.rootURL.appending(path: "Science Sample Week and Lesson Plans.docx")
        let scheduleSource = ImportedSource(
            id: UUID(),
            reference: FileReference(url: repository.rootURL.appending(path: "Sample Daily Schedule.docx")),
            setupRole: .instructionalCalendar,
            extractionMethod: .embeddedText,
            confidence: nil,
            extractedText: """
            Sample Daily Schedule
            Time
            Block
            8:35-9:35
            English Language Arts
            9:45-10:45
            Math
            10:45-11:15
            Science or Social Studies
            12:30-1:10
            Specials / Art
            """,
            reviewStatus: .reviewed,
            importedAt: .now,
            updatedAt: .now
        )
        let source = ImportedSource(
            id: UUID(),
            reference: FileReference(url: sourceURL),
            setupRole: .lessonMaterial,
            extractionMethod: .embeddedText,
            confidence: nil,
            extractedText: """
            Science: Week of Sample Lessons
            Day
            Lesson Focus
            Student Objective
            Quick Check
            Monday
            Observation skills
            Distinguish observations from inferences using classroom objects.
            Tuesday
            Tools of scientists
            Select appropriate tools for measuring length, mass, temperature, and time.
            Wednesday
            Question formation
            Turn observations into testable scientific questions.
            Thursday
            Plan a fair test
            Identify variables and controls in a simple classroom investigation.
            Friday
            Mini investigation
            Conduct a simple observation-based investigation and share findings.
            """,
            reviewStatus: .reviewed,
            importedAt: .now,
            updatedAt: .now
        )
        try repository.saveImportedSources([scheduleSource, source])

        let store = AppStore(repository: repository)

        let pacingPlan = try XCTUnwrap(repository.loadConfiguration()?.coursePacingPlan)
        XCTAssertEqual(pacingPlan.reviewStatus, .approved)
        XCTAssertEqual(pacingPlan.lessonCount, 5)
        let approvedLessonTitles = try repository.loadLessons().map(\.title)
        XCTAssertTrue(approvedLessonTitles.contains("Observation skills"))
        XCTAssertTrue(approvedLessonTitles.contains("Mini investigation"))
        let savedWeeklyPlan = try XCTUnwrap(repository.loadWeeklyPlan(for: store.weeklyPlan.weekOf))
        XCTAssertEqual(savedWeeklyPlan.assignments.count, 5)
        XCTAssertEqual(Set(savedWeeklyPlan.assignments.map { Calendar.current.component(.weekday, from: $0.date) }).count, 5)
        XCTAssertTrue(savedWeeklyPlan.assignments.allSatisfy { assignment in
            Calendar.current.component(.hour, from: assignment.start) == 10
                && Calendar.current.component(.minute, from: assignment.start) == 45
                && Calendar.current.component(.hour, from: assignment.end) == 11
                && Calendar.current.component(.minute, from: assignment.end) == 15
        })
        XCTAssertFalse(store.weeklyPacingSuggestionReport.title.contains("not set up"))

        var staleWeeklyPlan = savedWeeklyPlan
        staleWeeklyPlan.assignments = staleWeeklyPlan.assignments.map { assignment in
            var updated = assignment
            var components = Calendar.current.dateComponents([.year, .month, .day], from: assignment.date)
            components.hour = 9
            components.minute = 0
            updated.start = Calendar.current.date(from: components) ?? assignment.start
            components.hour = 9
            components.minute = 45
            updated.end = Calendar.current.date(from: components) ?? assignment.end
            return updated
        }
        try repository.saveWeeklyPlan(staleWeeklyPlan)

        let reloadedStore = AppStore(repository: repository)
        let repairedWeeklyPlan = try XCTUnwrap(repository.loadWeeklyPlan(for: reloadedStore.weeklyPlan.weekOf))
        XCTAssertTrue(repairedWeeklyPlan.assignments.allSatisfy { assignment in
            Calendar.current.component(.hour, from: assignment.start) == 10
                && Calendar.current.component(.minute, from: assignment.start) == 45
        })
    }

    func testOCRSourceKeepsConfidence() throws {
        let repository = try makeRepository()
        let source = ImportedSource(
            id: UUID(), reference: FileReference(url: URL(fileURLWithPath: "/tmp/scan.pdf")),
            extractionMethod: .localOCR, confidence: 0.82, extractedText: "Recognized printed text",
            reviewStatus: .imported, importedAt: .now, updatedAt: .now
        )
        try repository.saveImportedSources([source])
        let loaded = try repository.loadImportedSources()
        XCTAssertEqual(try XCTUnwrap(loaded[0].confidence), 0.82, accuracy: 0.001)
        XCTAssertEqual(loaded[0].reviewStatus, .imported)
    }

    func testSourceReadinessBlocksEmptyExtraction() {
        let source = ImportedSource(
            id: UUID(), reference: FileReference(url: URL(fileURLWithPath: "/tmp/scan.pdf")),
            extractionMethod: .ocrRequired, confidence: nil, extractedText: "", reviewStatus: .imported,
            importedAt: .now, updatedAt: .now
        )
        let report = SourceReadinessReport.analyze(source)
        XCTAssertEqual(report.level, .blocked)
        XCTAssertTrue(report.risks.contains(.ocr))
        XCTAssertTrue(report.risks.contains(.visualLayout))
    }

    func testSourceReadinessFlagsOCRMathForVisualReview() {
        let source = ImportedSource(
            id: UUID(), reference: FileReference(url: URL(fileURLWithPath: "/tmp/math-scan.pdf")),
            extractionMethod: .localOCR, confidence: 0.94, extractedText: "Compare 1/2 ≠ 1/3", reviewStatus: .imported,
            importedAt: .now, updatedAt: .now
        )
        let report = SourceReadinessReport.analyze(source)
        XCTAssertEqual(report.level, .visualReviewRequired)
        XCTAssertTrue(report.risks.contains(.ocr))
        XCTAssertTrue(report.risks.contains(.mathNotation))
    }

    func testSourceReadinessFlagsSelectableFractionsForMathReview() {
        let source = ImportedSource(
            id: UUID(), reference: FileReference(url: URL(fileURLWithPath: "/tmp/fractions.pdf")),
            extractionMethod: .embeddedText, confidence: nil, extractedText: "Students shade 3/4 of the rectangle.",
            reviewStatus: .imported, importedAt: .now, updatedAt: .now
        )
        let report = SourceReadinessReport.analyze(source)
        XCTAssertEqual(report.level, .visualReviewRequired)
        XCTAssertTrue(report.risks.contains(.mathNotation))
    }

    func testSourceReadinessFlagsVisualLayoutMarkersForReview() {
        let source = ImportedSource(
            id: UUID(), reference: FileReference(url: URL(fileURLWithPath: "/tmp/diagram.pdf")),
            extractionMethod: .embeddedText, confidence: nil, extractedText: "Figure 2 shows a table with labeled parts.",
            reviewStatus: .imported, importedAt: .now, updatedAt: .now
        )
        let report = SourceReadinessReport.analyze(source)
        XCTAssertEqual(report.level, .visualReviewRequired)
        XCTAssertTrue(report.risks.contains(.visualLayout))
    }

    func testGeneratedOutputRoundTrip() throws {
        let repository = try makeRepository()
        let output = GeneratedOutputRecord(id: UUID(), lessonRecordID: UUID(), kind: .lessonPlanHTML, displayName: "plan.html", filePath: "/tmp/plan.html", templateDisplayName: "Reference.html", createdAt: .now)
        try repository.saveGeneratedOutputs([output])
        let loaded = try XCTUnwrap(repository.loadGeneratedOutputs().first)
        XCTAssertEqual(loaded.id, output.id)
        XCTAssertEqual(loaded.lessonRecordID, output.lessonRecordID)
        XCTAssertEqual(loaded.kind, output.kind)
        XCTAssertEqual(loaded.filePath, output.filePath)
        XCTAssertEqual(loaded.templateDisplayName, output.templateDisplayName)
        XCTAssertNil(loaded.review)
    }

    func testGeneratedOutputDecodesWithoutReviewMetadata() throws {
        let repository = try makeRepository()
        let json = """
        [{
          "id" : "11111111-1111-1111-1111-111111111111",
          "kind" : "lessonPlanHTML",
          "displayName" : "plan.html",
          "filePath" : "/tmp/plan.html",
          "templateDisplayName" : null,
          "createdAt" : "2026-07-28T16:00:00Z"
        }]
        """
        try FileManager.default.createDirectory(at: repository.rootURL, withIntermediateDirectories: true)
        try json.write(to: repository.rootURL.appending(path: "generated-outputs.json"), atomically: true, encoding: .utf8)

        let loaded = try XCTUnwrap(repository.loadGeneratedOutputs().first)
        XCTAssertEqual(loaded.displayName, "plan.html")
        XCTAssertNil(loaded.review)
    }

    @MainActor
    func testAppStoreMarksGeneratedOutputReviewed() throws {
        let repository = try makeRepository()
        let output = GeneratedOutputRecord(id: UUID(), lessonRecordID: UUID(), kind: .slideDeckPPTX, displayName: "deck.pptx", filePath: "/tmp/deck.pptx", templateDisplayName: nil, createdAt: .now)
        try repository.saveGeneratedOutputs([output])
        let store = AppStore(repository: repository, slideDeckGenerator: TestSlideDeckGenerator.self)

        let reviewed = try XCTUnwrap(store.markGeneratedOutputReviewed(output, notes: "Checked in Google Slides."))
        XCTAssertNotNil(reviewed.review)
        XCTAssertEqual(reviewed.review?.reviewerNotes, "Checked in Google Slides.")
        XCTAssertEqual(try repository.loadGeneratedOutputs().first?.review?.reviewerNotes, "Checked in Google Slides.")
    }

    @MainActor
    func testAppStoreGeneratesSlideDeckRecordForApprovedLesson() async throws {
        let repository = try makeRepository()
        let workspace = repository.rootURL.appending(path: "workspace")
        let outputFolder = repository.rootURL.appending(path: "outputs")
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Generic QA Workspace",
            workspaceReference: FileReference(url: workspace),
            outputFolderReference: FileReference(url: outputFolder)
        ))
        var lesson = LessonRecord.draft(title: "Fraction Strategies")
        lesson.status = .approved
        lesson.objective = "Compare equivalent fractions using visual models."
        lesson.instructionalSequence = [
            InstructionalStep(id: UUID(), title: "Model 1/2 and 2/4", notes: ""),
            InstructionalStep(id: UUID(), title: "Explain the match", notes: "")
        ]
        lesson.differentiationSummary = "Use fraction strips or a challenge comparison."
        lesson.assessmentSummary = "Exit ticket with a model and explanation."

        let store = AppStore(repository: repository, slideDeckGenerator: TestSlideDeckGenerator.self)
        let generatedOutput = await store.generateSlideDeckPPTX(for: lesson)
        let output = try XCTUnwrap(generatedOutput)
        XCTAssertEqual(output.kind, .slideDeckPPTX)
        XCTAssertEqual(output.lessonRecordID, lesson.id)
        XCTAssertEqual(output.displayName, "fraction-strategies-slide-deck.pptx")
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.filePath))
        XCTAssertEqual(try repository.loadGeneratedOutputs().first?.filePath, output.filePath)

        let generatedText = try String(contentsOfFile: output.filePath, encoding: .utf8)
        XCTAssertTrue(generatedText.contains("title=Fraction Strategies"))
        XCTAssertTrue(generatedText.contains("objective=Compare equivalent fractions using visual models."))
        XCTAssertTrue(generatedText.contains("steps=Model 1/2 and 2/4|Explain the match"))
        XCTAssertTrue(generatedText.contains("differentiation=Use fraction strips or a challenge comparison."))
        XCTAssertTrue(generatedText.contains("assessment=Exit ticket with a model and explanation."))
    }

    @MainActor
    func testAppStoreSlideDeckGenerationUsesRegisteredPresentationTemplate() async throws {
        let repository = try makeRepository()
        let workspace = repository.rootURL.appending(path: "workspace")
        let outputFolder = repository.rootURL.appending(path: "outputs")
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Generic QA Workspace",
            workspaceReference: FileReference(url: workspace),
            outputFolderReference: FileReference(url: outputFolder)
        ))
        let templateURL = repository.rootURL.appending(path: "generic-template.pptx")
        var lesson = LessonRecord.draft(title: "Template Aware Deck")
        lesson.status = .approved
        lesson.objective = "Use a registered template mapping."
        lesson.instructionalSequence = [InstructionalStep(id: UUID(), title: "Map fields", notes: "")]
        lesson.assessmentSummary = "Check mapped output."

        let store = AppStore(repository: repository, slideDeckGenerator: TestSlideDeckGenerator.self)
        store.registerPresentationTemplate(templateURL)

        let generatedOutput = await store.generateSlideDeckPPTX(for: lesson)
        let output = try XCTUnwrap(generatedOutput)
        let generatedText = try String(contentsOfFile: output.filePath, encoding: .utf8)

        XCTAssertEqual(output.templateDisplayName, "generic-template.pptx")
        XCTAssertTrue(generatedText.contains("template=generic-template.pptx"))
    }

    @MainActor
    func testAppStoreDefaultSlideDeckGenerationUsesNativeExporter() async throws {
        let repository = try makeRepository()
        let workspace = repository.rootURL.appending(path: "workspace")
        let outputFolder = repository.rootURL.appending(path: "outputs")
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Generic QA Workspace",
            workspaceReference: FileReference(url: workspace),
            outputFolderReference: FileReference(url: outputFolder)
        ))
        var lesson = LessonRecord.draft(title: "Native Default Deck")
        lesson.status = .approved
        lesson.subject = "Math"
        lesson.gradeOrAgeRange = "Grade 4"
        lesson.objective = "Compare equivalent fractions."
        lesson.instructionalSequence = [InstructionalStep(id: UUID(), title: "Model equivalent fractions", notes: "Use fraction strips.")]
        lesson.materials = ["fraction strips"]
        lesson.printableResourcePrompt = "Draw equivalent models."
        lesson.assessmentSummary = "Explain one equivalent fraction pair."

        let store = AppStore(repository: repository)
        let generatedOutput = await store.generateSlideDeckPPTX(for: lesson)
        let output = try XCTUnwrap(generatedOutput)
        let packageText = String(decoding: try Data(contentsOf: URL(fileURLWithPath: output.filePath)), as: UTF8.self)

        XCTAssertEqual(output.kind, .slideDeckPPTX)
        XCTAssertEqual(store.slideDeckExporterPreference, .nativeOpenXML)
        XCTAssertTrue(packageText.contains("ppt/presentation.xml"))
        XCTAssertTrue(packageText.contains("Native Default Deck"))
        XCTAssertTrue(packageText.contains("Student Practice"))
        XCTAssertTrue(packageText.contains("Use fraction strips."))
    }

    @MainActor
    func testNativeDefaultSlideDeckCarriesPresentationTemplateProvenance() async throws {
        let repository = try makeRepository()
        let workspace = repository.rootURL.appending(path: "workspace")
        let outputFolder = repository.rootURL.appending(path: "outputs")
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Generic QA Workspace",
            workspaceReference: FileReference(url: workspace),
            outputFolderReference: FileReference(url: outputFolder)
        ))
        let templateURL = repository.rootURL.appending(path: "generic-template.pptx")
        var lesson = LessonRecord.draft(title: "Native Template Deck")
        lesson.status = .approved
        lesson.objective = "Preserve template provenance."
        lesson.instructionalSequence = [InstructionalStep(id: UUID(), title: "Use mappings", notes: "")]
        lesson.assessmentSummary = "Review speaker notes."

        let store = AppStore(repository: repository)
        store.registerPresentationTemplate(templateURL)

        let generatedOutput = await store.generateSlideDeckPPTX(for: lesson)
        let output = try XCTUnwrap(generatedOutput)
        let packageText = String(decoding: try Data(contentsOf: URL(fileURLWithPath: output.filePath)), as: UTF8.self)

        XCTAssertEqual(output.templateDisplayName, "generic-template.pptx")
        XCTAssertTrue(packageText.contains("Presentation template: generic-template.pptx"))
        XCTAssertTrue(packageText.contains("lesson.title=Title required"))
        XCTAssertTrue(packageText.contains("lesson.assessment=Assessment required"))
    }

    @MainActor
    func testAppStoreRefusesSlideDeckForUnapprovedLesson() async throws {
        let repository = try makeRepository()
        let workspace = repository.rootURL.appending(path: "workspace")
        let outputFolder = repository.rootURL.appending(path: "outputs")
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Generic QA Workspace",
            workspaceReference: FileReference(url: workspace),
            outputFolderReference: FileReference(url: outputFolder)
        ))
        let store = AppStore(repository: repository, slideDeckGenerator: TestSlideDeckGenerator.self)

        let output = await store.generateSlideDeckPPTX(for: LessonRecord.draft(title: "Draft Lesson"))
        XCTAssertNil(output)
        XCTAssertEqual(store.lastError, "Approve the lesson before generating an output.")
        XCTAssertTrue(try repository.loadGeneratedOutputs().isEmpty)
    }

    @MainActor
    func testNativePowerPointExporterCreatesOpenXMLPackageWithEscapedLessonContent() async throws {
        var lesson = LessonRecord.draft(title: "A < B & Fraction Strategies")
        lesson.status = .approved
        lesson.objective = "Compare 1/2 & 2/4 using visual models."
        lesson.subject = "Math"
        lesson.gradeOrAgeRange = "Grade 4"
        lesson.sourceReferences = ["/tmp/source <one>.pdf"]
        lesson.instructionalSequence = [
            InstructionalStep(id: UUID(), title: "Model 1/2 < 2/4", notes: "Check the whole & labels."),
            InstructionalStep(id: UUID(), title: "Explain equivalent fractions", notes: "")
        ]
        lesson.materials = ["fraction strips", "whiteboard"]
        lesson.differentiationSummary = "Use a simpler model or a challenge comparison."
        lesson.printableResourcePrompt = "Draw <two> equivalent models."
        lesson.assessmentSummary = "Exit ticket: explain one equivalent pair."

        let destination = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "native-deck.pptx")

        XCTAssertTrue(NativePowerPointExporter.availability.isAvailable)
        try await NativePowerPointExporter.generate(lesson: lesson, destination: destination)

        let data = try Data(contentsOf: destination)
        XCTAssertEqual(data.prefix(2), Data("PK".utf8))
        let packageText = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(packageText.contains("[Content_Types].xml"))
        XCTAssertTrue(packageText.contains("ppt/presentation.xml"))
        XCTAssertTrue(packageText.contains("ppt/slides/slide1.xml"))
        XCTAssertTrue(packageText.contains("ppt/slides/slide5.xml"))
        XCTAssertTrue(packageText.contains("ppt/notesSlides/notesSlide1.xml"))
        XCTAssertTrue(packageText.contains("<Slides>5</Slides>"))
        XCTAssertTrue(packageText.contains("A &lt; B &amp; Fraction Strategies"))
        XCTAssertTrue(packageText.contains("Compare 1/2 &amp; 2/4 using visual models."))
        XCTAssertTrue(packageText.contains("Model 1/2 &lt; 2/4"))
        XCTAssertTrue(packageText.contains("Check the whole &amp; labels."))
        XCTAssertTrue(packageText.contains("Materials and Supports"))
        XCTAssertTrue(packageText.contains("Student Practice"))
        XCTAssertTrue(packageText.contains("Draw &lt;two&gt; equivalent models."))
        XCTAssertTrue(packageText.contains("Assessment"))
        XCTAssertTrue(packageText.contains("Exit ticket: explain one equivalent pair."))
        XCTAssertTrue(packageText.contains("[Sources]"))
        XCTAssertTrue(packageText.contains("Source reference: /tmp/source &lt;one&gt;.pdf"))
    }

    func testWeeklyPlanRoundTrip() throws {
        let repository = try makeRepository()
        let weekOf = Date(timeIntervalSince1970: 1_700_000_000)
        let assignment = WeeklyLessonAssignment(
            id: UUID(),
            lessonRecordID: UUID(),
            date: weekOf,
            start: weekOf,
            end: weekOf.addingTimeInterval(2_700),
            planningNotes: "Use small-group check-in."
        )
        let brief = WeeklyPlanningBrief(
            teacherFocus: "Fractions and discussion",
            preparationNotes: "Print exit tickets",
            studentSupportNotes: "Small-group model review",
            updatedAt: .now
        )
        let refinement = try XCTUnwrap(WeeklyPacingRefinementProposal.draft(from: "We lost one lesson day.", weekOf: weekOf))
        let plan = WeeklyPlan(weekOf: weekOf, planningBrief: brief, pacingRefinementProposal: refinement, assignments: [assignment], updatedAt: .now)
        try repository.saveWeeklyPlan(plan)
        let loaded = try XCTUnwrap(repository.loadWeeklyPlan(for: weekOf))
        XCTAssertEqual(loaded.planningBrief?.teacherFocus, brief.teacherFocus)
        XCTAssertEqual(loaded.planningBrief?.preparationNotes, brief.preparationNotes)
        XCTAssertEqual(loaded.planningBrief?.studentSupportNotes, brief.studentSupportNotes)
        let loadedRefinement = try XCTUnwrap(loaded.pacingRefinementProposal)
        XCTAssertEqual(loadedRefinement.id, refinement.id)
        XCTAssertEqual(loadedRefinement.checkInNote, refinement.checkInNote)
        XCTAssertEqual(loadedRefinement.proposedAdjustmentSummary, refinement.proposedAdjustmentSummary)
        XCTAssertEqual(loadedRefinement.pacingImpactNotes, refinement.pacingImpactNotes)
        XCTAssertEqual(loadedRefinement.affectedPacingArea, refinement.affectedPacingArea)
        XCTAssertEqual(loadedRefinement.suggestedDateShiftDays, refinement.suggestedDateShiftDays)
        XCTAssertEqual(loadedRefinement.status, refinement.status)
        XCTAssertEqual(loaded.assignments, [assignment])
    }

    @MainActor
    func testAppStorePersistsWeeklyAssignmentPlanningNotes() throws {
        let repository = try makeRepository()
        let workspace = repository.rootURL.appending(path: "workspace")
        let weekOf = Date(timeIntervalSince1970: 1_700_000_000)
        let lessonID = UUID()
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Generic QA Workspace",
            workspaceReference: FileReference(url: workspace)
        ))
        let store = AppStore(repository: repository)
        store.setWeeklyPlanWeek(of: weekOf)

        store.addWeeklyAssignment(
            lessonID: lessonID,
            date: weekOf,
            start: weekOf,
            end: weekOf.addingTimeInterval(2_700),
            planningNotes: "  Pull vocabulary cards first.  "
        )

        XCTAssertEqual(store.weeklyPlan.assignments.first?.planningNotes, "Pull vocabulary cards first.")
        let loaded = try XCTUnwrap(repository.loadWeeklyPlan(for: store.weeklyPlan.weekOf))
        XCTAssertEqual(loaded.assignments.first?.planningNotes, "Pull vocabulary cards first.")
    }

    @MainActor
    func testAppStoreUpdatesWeeklyAssignmentDetails() throws {
        let repository = try makeRepository()
        let workspace = repository.rootURL.appending(path: "workspace")
        let weekOf = Date(timeIntervalSince1970: 1_700_000_000)
        let later = weekOf.addingTimeInterval(86_400)
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Generic QA Workspace",
            workspaceReference: FileReference(url: workspace)
        ))
        let store = AppStore(repository: repository)
        store.setWeeklyPlanWeek(of: weekOf)
        store.addWeeklyAssignment(lessonID: UUID(), date: later, start: later, end: later.addingTimeInterval(2_700), planningNotes: "Later")
        store.addWeeklyAssignment(lessonID: UUID(), date: weekOf, start: weekOf, end: weekOf.addingTimeInterval(2_700), planningNotes: "First")
        let assignment = try XCTUnwrap(store.weeklyPlan.assignments.last)
        let newStart = weekOf.addingTimeInterval(3_600)
        let newEnd = weekOf.addingTimeInterval(5_400)

        store.updateWeeklyAssignment(
            assignment,
            date: weekOf,
            start: newStart,
            end: newEnd,
            planningNotes: "  Updated note.  "
        )

        let updated = try XCTUnwrap(store.weeklyPlan.assignments.first { $0.id == assignment.id })
        XCTAssertEqual(updated.start, newStart)
        XCTAssertEqual(updated.end, newEnd)
        XCTAssertEqual(updated.planningNotes, "Updated note.")
        XCTAssertEqual(store.weeklyPlan.assignments.map(\.planningNotes), ["First", "Updated note."])
        let loaded = try XCTUnwrap(repository.loadWeeklyPlan(for: store.weeklyPlan.weekOf))
        XCTAssertEqual(loaded.assignments.first { $0.id == assignment.id }?.planningNotes, "Updated note.")
    }

    @MainActor
    func testAppStorePersistsWeeklyPlanningBrief() throws {
        let repository = try makeRepository()
        let workspace = repository.rootURL.appending(path: "workspace")
        let weekOf = Date(timeIntervalSince1970: 1_700_000_000)
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Generic QA Workspace",
            workspaceReference: FileReference(url: workspace)
        ))
        let store = AppStore(repository: repository)
        store.setWeeklyPlanWeek(of: weekOf)

        store.updateWeeklyPlanningBrief(
            teacherFocus: "Compare strategies",
            preparationNotes: "Gather manipulatives",
            studentSupportNotes: "Vocabulary review"
        )

        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: weekOf)?.start ?? calendar.startOfDay(for: weekOf)
        let loaded = try XCTUnwrap(repository.loadWeeklyPlan(for: startOfWeek))
        XCTAssertEqual(loaded.planningBrief?.teacherFocus, "Compare strategies")
        XCTAssertEqual(loaded.planningBrief?.preparationNotes, "Gather manipulatives")
        XCTAssertEqual(loaded.planningBrief?.studentSupportNotes, "Vocabulary review")
    }

    func testRendererEscapesLessonContent() {
        var lesson = LessonRecord.draft(title: "A < lesson")
        lesson.objective = "Use < & > safely"
        let html = LessonPlanRenderer.renderHTML(for: lesson)
        XCTAssertTrue(html.contains("A &lt; lesson"))
        XCTAssertTrue(html.contains("Use &lt; &amp; &gt; safely"))
        XCTAssertEqual(LessonPlanRenderer.safeFileStem("A < lesson!"), "a-lesson")
    }

    func testDifferentiationRendererIncludesPrintablePrompt() {
        var lesson = LessonRecord.draft(title: "Practice")
        lesson.printableResourcePrompt = "Explain your <strategy>."
        let html = LessonPlanRenderer.renderDifferentiationGuideHTML(for: lesson)
        XCTAssertTrue(html.contains("Student Practice / Exit Ticket"))
        XCTAssertTrue(html.contains("&lt;strategy&gt;"))
    }

    func testWeeklyRendererIncludesThreeOutputLinksForScheduledLesson() {
        var lesson = LessonRecord.draft(title: "Fraction Strategies")
        lesson.objective = "Compare equivalent fractions."
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let plan = WeeklyPlan(
            weekOf: date,
            assignments: [WeeklyLessonAssignment(id: UUID(), lessonRecordID: lesson.id, date: date, start: date, end: date.addingTimeInterval(2_700), planningNotes: "Use <partner talk> before exit ticket.")],
            updatedAt: .now
        )
        let outputs = [
            GeneratedOutputRecord(id: UUID(), lessonRecordID: lesson.id, kind: .lessonPlanHTML, displayName: "plan.html", filePath: "/tmp/plan.html", templateDisplayName: nil, createdAt: .now),
            GeneratedOutputRecord(id: UUID(), lessonRecordID: lesson.id, kind: .slideDeckPPTX, displayName: "deck.pptx", filePath: "/tmp/deck.pptx", templateDisplayName: nil, createdAt: .now),
            GeneratedOutputRecord(id: UUID(), lessonRecordID: lesson.id, kind: .differentiationGuideHTML, displayName: "guide.html", filePath: "/tmp/guide.html", templateDisplayName: nil, createdAt: .now)
        ]

        let html = LessonPlanRenderer.renderWeeklyHTML(plan: plan, lessons: [lesson], generatedOutputs: outputs)

        XCTAssertTrue(html.contains("Fraction Strategies"))
        XCTAssertTrue(html.contains("Lesson plan"))
        XCTAssertTrue(html.contains("Slide deck"))
        XCTAssertTrue(html.contains("Differentiation guide"))
        XCTAssertTrue(html.contains("Use &lt;partner talk&gt; before exit ticket."))
        XCTAssertTrue(html.contains("file:///tmp/plan.html"))
        XCTAssertTrue(html.contains("file:///tmp/deck.pptx"))
        XCTAssertTrue(html.contains("file:///tmp/guide.html"))
    }

    func testWeeklyRendererIncludesPlanningBrief() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let plan = WeeklyPlan(
            weekOf: date,
            planningBrief: WeeklyPlanningBrief(
                teacherFocus: "Compare <strategies>",
                preparationNotes: "Prep fraction strips & exit tickets",
                studentSupportNotes: "Review vocabulary > benchmark",
                updatedAt: .now
            ),
            assignments: [],
            updatedAt: .now
        )

        let html = LessonPlanRenderer.renderWeeklyHTML(plan: plan, lessons: [])

        XCTAssertTrue(html.contains("Teacher focus"))
        XCTAssertTrue(html.contains("Compare &lt;strategies&gt;"))
        XCTAssertTrue(html.contains("Prep fraction strips &amp; exit tickets"))
        XCTAssertTrue(html.contains("Review vocabulary &gt; benchmark"))
    }

    func testWeeklyPackageReadinessBlocksEmptySchedule() {
        let report = WeeklyPackageReadinessReport.analyze(
            plan: .empty(for: Date(timeIntervalSince1970: 1_700_000_000)),
            lessons: [],
            generatedOutputs: []
        )

        XCTAssertFalse(report.canGenerate)
        XCTAssertEqual(report.blockingIssues, [.noScheduledLessons])
    }

    func testWeeklyPackageReadinessBlocksInvalidScheduledTimes() {
        var lesson = LessonRecord.draft(title: "Fraction Strategies")
        lesson.status = .approved
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let plan = WeeklyPlan(
            weekOf: date,
            assignments: [
                WeeklyLessonAssignment(
                    id: UUID(),
                    lessonRecordID: lesson.id,
                    date: date,
                    start: date.addingTimeInterval(2_700),
                    end: date,
                    planningNotes: nil
                )
            ],
            updatedAt: .now
        )

        let report = WeeklyPackageReadinessReport.analyze(plan: plan, lessons: [lesson], generatedOutputs: [])

        XCTAssertFalse(report.canGenerate)
        XCTAssertTrue(report.blockingIssues.contains(.invalidScheduledTimeRange))
    }

    func testWeeklyPackageReadinessAllowsApprovedLessonWithMissingOutputs() {
        var lesson = LessonRecord.draft(title: "Fraction Strategies")
        lesson.status = .approved
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let plan = WeeklyPlan(
            weekOf: date,
            assignments: [WeeklyLessonAssignment(id: UUID(), lessonRecordID: lesson.id, date: date, start: date, end: date.addingTimeInterval(2_700))],
            updatedAt: .now
        )

        let report = WeeklyPackageReadinessReport.analyze(plan: plan, lessons: [lesson], generatedOutputs: [])

        XCTAssertTrue(report.canGenerate)
        XCTAssertEqual(report.advisoryIssues, [.incompleteOutputs])
        XCTAssertEqual(report.scheduledLessonCount, 1)
        XCTAssertEqual(report.completeOutputLessonCount, 0)
    }

    func testWeeklyPackageReadinessCountsCompleteLessonOutputs() {
        var lesson = LessonRecord.draft(title: "Fraction Strategies")
        lesson.status = .approved
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let plan = WeeklyPlan(
            weekOf: date,
            assignments: [WeeklyLessonAssignment(id: UUID(), lessonRecordID: lesson.id, date: date, start: date, end: date.addingTimeInterval(2_700))],
            updatedAt: .now
        )
        let outputs = [
            GeneratedOutputRecord(id: UUID(), lessonRecordID: lesson.id, kind: .lessonPlanHTML, displayName: "plan.html", filePath: "/tmp/plan.html", templateDisplayName: nil, createdAt: .now),
            GeneratedOutputRecord(id: UUID(), lessonRecordID: lesson.id, kind: .slideDeckPPTX, displayName: "deck.pptx", filePath: "/tmp/deck.pptx", templateDisplayName: nil, createdAt: .now),
            GeneratedOutputRecord(id: UUID(), lessonRecordID: lesson.id, kind: .differentiationGuideHTML, displayName: "guide.html", filePath: "/tmp/guide.html", templateDisplayName: nil, createdAt: .now)
        ]

        let report = WeeklyPackageReadinessReport.analyze(plan: plan, lessons: [lesson], generatedOutputs: outputs)

        XCTAssertTrue(report.canGenerate)
        XCTAssertTrue(report.issues.isEmpty)
        XCTAssertEqual(report.completeOutputLessonCount, 1)
        XCTAssertEqual(report.outputSummary.lessonPlanCount, 1)
        XCTAssertEqual(report.outputSummary.slideDeckCount, 1)
        XCTAssertEqual(report.outputSummary.differentiationGuideCount, 1)
        XCTAssertEqual(report.outputSummary.missingOutputCount, 0)
        XCTAssertEqual(report.outputSummary.generationLine, "All scheduled lesson outputs are ready to link.")
    }

    func testWeeklyOutputSummaryCountsPartialOutputs() {
        var firstLesson = LessonRecord.draft(title: "Fraction Strategies")
        firstLesson.status = .approved
        var secondLesson = LessonRecord.draft(title: "Decimal Strategies")
        secondLesson.status = .approved
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let plan = WeeklyPlan(
            weekOf: date,
            assignments: [
                WeeklyLessonAssignment(id: UUID(), lessonRecordID: firstLesson.id, date: date, start: date, end: date.addingTimeInterval(2_700)),
                WeeklyLessonAssignment(id: UUID(), lessonRecordID: secondLesson.id, date: date.addingTimeInterval(86_400), start: date, end: date.addingTimeInterval(2_700))
            ],
            updatedAt: .now
        )
        let outputs = [
            GeneratedOutputRecord(id: UUID(), lessonRecordID: firstLesson.id, kind: .lessonPlanHTML, displayName: "plan.html", filePath: "/tmp/plan.html", templateDisplayName: nil, createdAt: .now),
            GeneratedOutputRecord(id: UUID(), lessonRecordID: firstLesson.id, kind: .slideDeckPPTX, displayName: "deck.pptx", filePath: "/tmp/deck.pptx", templateDisplayName: nil, createdAt: .now),
            GeneratedOutputRecord(id: UUID(), lessonRecordID: secondLesson.id, kind: .lessonPlanHTML, displayName: "plan-2.html", filePath: "/tmp/plan-2.html", templateDisplayName: nil, createdAt: .now)
        ]

        let summary = WeeklyOutputSummary.analyze(plan: plan, lessons: [firstLesson, secondLesson], generatedOutputs: outputs)

        XCTAssertEqual(summary.scheduledLessonCount, 2)
        XCTAssertEqual(summary.lessonPlanCount, 2)
        XCTAssertEqual(summary.slideDeckCount, 1)
        XCTAssertEqual(summary.differentiationGuideCount, 0)
        XCTAssertEqual(summary.completeLessonCount, 0)
        XCTAssertEqual(summary.missingOutputCount, 3)
        XCTAssertEqual(summary.statusLine, "0 of 2 lessons have all three outputs.")
        XCTAssertEqual(summary.generationLine, "3 missing outputs will be created before the weekly package is written.")
    }

    @MainActor
    func testWeeklyPackageGenerationCreatesAndLinksThreeLessonOutputs() async throws {
        let repository = try makeRepository()
        let workspace = repository.rootURL.appending(path: "workspace")
        let outputFolder = repository.rootURL.appending(path: "outputs")
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Generic QA Workspace",
            workspaceReference: FileReference(url: workspace),
            outputFolderReference: FileReference(url: outputFolder)
        ))
        var lesson = LessonRecord.draft(title: "Weekly Hub Lesson")
        lesson.status = .approved
        lesson.subject = "Math"
        lesson.gradeOrAgeRange = "Grade 4"
        lesson.objective = "Compare equivalent fractions."
        lesson.instructionalSequence = [InstructionalStep(id: UUID(), title: "Model equivalent fractions", notes: "")]
        lesson.materials = ["fraction strips"]
        lesson.differentiationSummary = "Use visual supports."
        lesson.assessmentSummary = "Explain one equivalent pair."
        try repository.saveLessons([lesson])

        let store = AppStore(repository: repository)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        store.setWeeklyPlanWeek(of: date)
        store.addWeeklyAssignment(lessonID: lesson.id, date: date, start: date, end: date.addingTimeInterval(2_700))

        let generatedWeeklyOutput = await store.generateWeeklyPackageHTML()
        let weeklyOutput = try XCTUnwrap(generatedWeeklyOutput)
        let outputKinds = try repository.loadGeneratedOutputs().map(\.kind)
        let weeklyHTML = try String(contentsOfFile: weeklyOutput.filePath, encoding: .utf8)

        XCTAssertTrue(outputKinds.contains(.lessonPlanHTML))
        XCTAssertTrue(outputKinds.contains(.slideDeckPPTX))
        XCTAssertTrue(outputKinds.contains(.differentiationGuideHTML))
        XCTAssertTrue(outputKinds.contains(.weeklyPlanHTML))
        XCTAssertTrue(weeklyHTML.contains("Weekly Hub Lesson"))
        XCTAssertTrue(weeklyHTML.contains("Lesson plan"))
        XCTAssertTrue(weeklyHTML.contains("Slide deck"))
        XCTAssertTrue(weeklyHTML.contains("Differentiation guide"))
    }

    @MainActor
    func testWeeklyPackageGenerationRefusesEmptySchedule() async throws {
        let repository = try makeRepository()
        let workspace = repository.rootURL.appending(path: "workspace")
        let outputFolder = repository.rootURL.appending(path: "outputs")
        try repository.saveConfiguration(AppConfiguration(
            workspaceName: "Generic QA Workspace",
            workspaceReference: FileReference(url: workspace),
            outputFolderReference: FileReference(url: outputFolder)
        ))
        let store = AppStore(repository: repository)

        let output = await store.generateWeeklyPackageHTML()

        XCTAssertNil(output)
        XCTAssertEqual(store.lastError, WeeklyPackageReadinessIssue.noScheduledLessons.instruction)
        XCTAssertTrue(try repository.loadGeneratedOutputs().isEmpty)
    }

    func testLabeledSourceExtractionDoesNotGuessUnlabeledContent() {
        let result = LessonFieldExtractor.extract(from: """
        Objective: Compare two fractions.
        Materials: fraction strips; pencils
        Assessment: Explain your comparison.
        """)
        XCTAssertEqual(result.objective, "Compare two fractions.")
        XCTAssertEqual(result.materials, ["fraction strips", "pencils"])
        XCTAssertEqual(result.assessment, "Explain your comparison.")
        XCTAssertNil(result.differentiation)
    }

    func testLessonDraftProposalDecodesStrictJSONContract() throws {
        let json = """
        {"title":"Fraction comparison","subject":"Math","gradeOrAgeRange":"4","objective":"Compare fractions","instructionalSteps":["Model","Practice"],"materials":["strips"],"differentiationSummary":"Use visuals","printableResourcePrompt":"Compare two fractions.","assessmentSummary":"Exit ticket"}
        """
        let proposal = try JSONDecoder().decode(LessonDraftProposal.self, from: Data(json.utf8))
        XCTAssertEqual(proposal.instructionalSteps, ["Model", "Practice"])
        XCTAssertEqual(proposal.assessmentSummary, "Exit ticket")
    }

    func testScheduleProposalLeavesInstructionalFieldsEmptyAndWarns() {
        let proposal = LessonDraftProposal(title: "Daily schedule", subject: "", gradeOrAgeRange: "", objective: "", instructionalSteps: ["8:00 math"], materials: ["calendar"], differentiationSummary: "", printableResourcePrompt: "", assessmentSummary: "", sourceType: "schedule", reviewWarnings: [])
        let warnings = LessonDraftValidator.warnings(for: proposal)
        XCTAssertTrue(warnings.contains("No explicit learning objective was found."))
        XCTAssertFalse(warnings.contains("No explicit instructional sequence was found."))
    }

    func testCodexDraftSchemaIsValidJSON() throws {
        let data = try XCTUnwrap(CodexCLIAdapter.schema.data(using: .utf8))
        XCTAssertNotNil(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - WeeklyGridLayout

    private func gridCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private func gridAssignment(
        calendar: Calendar,
        day: Int,
        startHour: Int,
        startMinute: Int,
        endHour: Int,
        endMinute: Int
    ) throws -> WeeklyLessonAssignment {
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: day)))
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: day, hour: startHour, minute: startMinute)))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: day, hour: endHour, minute: endMinute)))
        return WeeklyLessonAssignment(
            id: UUID(),
            lessonRecordID: UUID(),
            date: date,
            start: start,
            end: end,
            planningNotes: nil
        )
    }

    func testWeeklyGridLayoutIsEmptyForNoAssignments() {
        let layout = WeeklyGridLayout(assignments: [], calendar: gridCalendar())
        XCTAssertTrue(layout.slots.isEmpty)
    }

    func testWeeklyGridLayoutMergesNearbyStartTimesIntoOneRow() throws {
        let calendar = gridCalendar()
        // Same block on three days, drifting by a few minutes — this previously produced
        // three separate near-empty rows.
        let monday = try gridAssignment(calendar: calendar, day: 27, startHour: 9, startMinute: 45, endHour: 10, endMinute: 45)
        let tuesday = try gridAssignment(calendar: calendar, day: 28, startHour: 9, startMinute: 50, endHour: 10, endMinute: 50)
        let wednesday = try gridAssignment(calendar: calendar, day: 29, startHour: 9, startMinute: 55, endHour: 10, endMinute: 55)

        let layout = WeeklyGridLayout(assignments: [monday, tuesday, wednesday], calendar: calendar)

        XCTAssertEqual(layout.slots.count, 1)
        XCTAssertEqual(layout.slotID(for: monday), layout.slotID(for: tuesday))
        XCTAssertEqual(layout.slotID(for: tuesday), layout.slotID(for: wednesday))
    }

    func testWeeklyGridLayoutKeepsDistinctBlocksApart() throws {
        let calendar = gridCalendar()
        let english = try gridAssignment(calendar: calendar, day: 27, startHour: 8, startMinute: 35, endHour: 9, endMinute: 35)
        let math = try gridAssignment(calendar: calendar, day: 27, startHour: 9, startMinute: 45, endHour: 10, endMinute: 45)
        let science = try gridAssignment(calendar: calendar, day: 27, startHour: 10, startMinute: 45, endHour: 11, endMinute: 15)

        let layout = WeeklyGridLayout(assignments: [english, math, science], calendar: calendar)

        XCTAssertEqual(layout.slots.count, 3)
        // Rows are ordered earliest first.
        XCTAssertEqual(layout.slots.map(\.id), [8 * 60 + 35, 9 * 60 + 45, 10 * 60 + 45])
    }

    func testWeeklyGridLayoutDoesNotChainDriftAcrossTolerance() throws {
        let calendar = gridCalendar()
        // Each step is within tolerance of the previous one, but the span is 45 minutes.
        // Anchoring on the first start in the cluster must prevent these collapsing into
        // a single row.
        let a = try gridAssignment(calendar: calendar, day: 27, startHour: 8, startMinute: 0, endHour: 8, endMinute: 30)
        let b = try gridAssignment(calendar: calendar, day: 28, startHour: 8, startMinute: 14, endHour: 8, endMinute: 44)
        let c = try gridAssignment(calendar: calendar, day: 29, startHour: 8, startMinute: 28, endHour: 8, endMinute: 58)
        let d = try gridAssignment(calendar: calendar, day: 30, startHour: 8, startMinute: 42, endHour: 9, endMinute: 12)

        let layout = WeeklyGridLayout(assignments: [a, b, c, d], calendar: calendar)

        XCTAssertGreaterThan(layout.slots.count, 1)
        XCTAssertNotEqual(layout.slotID(for: a), layout.slotID(for: d))
    }

    func testWeeklyGridLayoutSlotLabelSpansEarliestStartToLatestEnd() throws {
        let calendar = gridCalendar()
        let early = try gridAssignment(calendar: calendar, day: 27, startHour: 9, startMinute: 45, endHour: 10, endMinute: 30)
        let late = try gridAssignment(calendar: calendar, day: 28, startHour: 9, startMinute: 55, endHour: 10, endMinute: 50)

        let layout = WeeklyGridLayout(assignments: [early, late], calendar: calendar)
        let slot = try XCTUnwrap(layout.slots.first)

        XCTAssertEqual(slot.displayStart, early.start)
        XCTAssertEqual(slot.displayEnd, late.end)
    }

    func testWeeklyGridLayoutReturnsOnlyAssignmentsForRequestedDay() throws {
        let calendar = gridCalendar()
        let monday = try gridAssignment(calendar: calendar, day: 27, startHour: 9, startMinute: 45, endHour: 10, endMinute: 45)
        let tuesday = try gridAssignment(calendar: calendar, day: 28, startHour: 9, startMinute: 50, endHour: 10, endMinute: 50)
        let all = [monday, tuesday]

        let layout = WeeklyGridLayout(assignments: all, calendar: calendar)
        let slot = try XCTUnwrap(layout.slots.first)

        let mondayCell = layout.assignments(from: all, forDay: monday.date, slot: slot, titleForSorting: { _ in "" })
        XCTAssertEqual(mondayCell.map(\.id), [monday.id])

        let tuesdayCell = layout.assignments(from: all, forDay: tuesday.date, slot: slot, titleForSorting: { _ in "" })
        XCTAssertEqual(tuesdayCell.map(\.id), [tuesday.id])
    }

    func testWeeklyGridLayoutSortsSameStartAssignmentsByTitle() throws {
        let calendar = gridCalendar()
        let first = try gridAssignment(calendar: calendar, day: 27, startHour: 9, startMinute: 45, endHour: 10, endMinute: 45)
        let second = try gridAssignment(calendar: calendar, day: 27, startHour: 9, startMinute: 45, endHour: 10, endMinute: 45)
        let all = [first, second]
        let titles = [first.id: "Zebra", second.id: "Apple"]

        let layout = WeeklyGridLayout(assignments: all, calendar: calendar)
        let slot = try XCTUnwrap(layout.slots.first)
        let cell = layout.assignments(from: all, forDay: first.date, slot: slot, titleForSorting: { titles[$0.id] ?? "" })

        XCTAssertEqual(cell.map(\.id), [second.id, first.id])
    }

    func testWeeklyGridLayoutRespectsCustomTolerance() throws {
        let calendar = gridCalendar()
        let a = try gridAssignment(calendar: calendar, day: 27, startHour: 9, startMinute: 0, endHour: 9, endMinute: 30)
        let b = try gridAssignment(calendar: calendar, day: 28, startHour: 9, startMinute: 10, endHour: 9, endMinute: 40)

        let merged = WeeklyGridLayout(assignments: [a, b], calendar: calendar, toleranceMinutes: 15)
        XCTAssertEqual(merged.slots.count, 1)

        let split = WeeklyGridLayout(assignments: [a, b], calendar: calendar, toleranceMinutes: 5)
        XCTAssertEqual(split.slots.count, 2)
    }
}
