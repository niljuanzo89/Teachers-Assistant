import Foundation
import AppKit
import PDFKit
import Vision

enum PDFTextExtractionError: LocalizedError {
    case unreadable
    case ocrFailed
    case unsupportedFileType
    case unreadableWordDocument

    var errorDescription: String? {
        switch self {
        case .unreadable: "The selected PDF could not be read."
        case .ocrFailed: "Text could not be recognized from this scanned PDF."
        case .unsupportedFileType: "Only PDF and DOCX files can be imported right now."
        case .unreadableWordDocument: "The selected Word document could not be read."
        }
    }
}

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var configuration: AppConfiguration?
    @Published var dailyPlan: DailyPlan
    @Published var weeklyPlan: WeeklyPlan
    @Published private(set) var lessons: [LessonRecord] = []
    @Published private(set) var mostRecentLessonID: UUID?
    @Published private(set) var importedSources: [ImportedSource] = []
    @Published private(set) var generatedOutputs: [GeneratedOutputRecord] = []
    @Published private(set) var progressSnapshots: [PlanningProgressSnapshot] = []
    @Published private(set) var teacherProfiles: [TeacherProfile] = []
    @Published private(set) var activeTeacherProfileID: UUID?
    @Published private(set) var slideDeckAvailability: SlideDeckAvailability
    @Published var lastError: String?
    /// Placeholder inheritance resolution from the most recent template inspection.
    /// Transient UI state only, deliberately not part of `AppConfiguration` — recomputed
    /// each time a template is inspected rather than persisted, so it carries none of the
    /// migration risk a saved schema change would.
    @Published private(set) var lastPresentationTemplatePlaceholderResolution: [PresentationTemplatePlaceholderResolution] = []

    private let repository: any LocalRepositoryProtocol
    private let slideDeckGeneratorOverride: (any SlideDeckGenerating.Type)?

    private struct ImportedDailyScheduleBlock {
        var startHour: Int
        var startMinute: Int
        var endHour: Int
        var endMinute: Int
        var label: String
    }

    private var activeSlideDeckGenerator: any SlideDeckGenerating.Type {
        if let slideDeckGeneratorOverride { return slideDeckGeneratorOverride }
        switch configuration?.slideDeckExporter ?? .nativeOpenXML {
        case .nativeOpenXML: return NativePowerPointExporter.self
        case .personalBridge: return SlideDeckBridge.self
        }
    }

    var slideDeckExporterPreference: SlideDeckExporterPreference {
        configuration?.slideDeckExporter ?? .nativeOpenXML
    }

    var weeklyPlanningPromptPreference: WeeklyPlanningPromptPreference {
        configuration?.weeklyPlanningPrompt ?? .default
    }

    var weeklyPlanningPromptStatus: WeeklyPlanningPromptStatus {
        WeeklyPlanningPromptStatus.evaluate(
            preference: weeklyPlanningPromptPreference,
            lastHandledAt: configuration?.weeklyPlanningPromptLastHandledAt
        )
    }

    var activePresentationTemplate: OutputTemplateRegistration? {
        configuration?.outputTemplates.first { $0.kind == .presentation }
    }

    var activeTeacherProfile: TeacherProfile? {
        guard let activeTeacherProfileID else { return nil }
        return teacherProfiles.first { $0.id == activeTeacherProfileID }
    }

    var presentationTemplateReadinessReport: PresentationTemplateReadinessReport {
        PresentationTemplateReadinessReport.analyze(configuration: configuration)
    }

    var releaseReadinessReport: ReleaseReadinessReport {
        ReleaseReadinessReport.analyze(configuration: configuration, lessons: lessons, generatedOutputs: generatedOutputs)
    }

    var localWorkflowQAReport: LocalWorkflowQAReport {
        LocalWorkflowQAReport.analyze(
            activeTeacherProfile: activeTeacherProfile,
            importedSources: importedSources,
            pacingReport: coursePacingReadinessReport,
            weeklyPackageReport: weeklyPackageReadinessReport,
            lessons: lessons,
            generatedOutputs: generatedOutputs
        )
    }

    var weeklyPackageReadinessReport: WeeklyPackageReadinessReport {
        WeeklyPackageReadinessReport.analyze(plan: weeklyPlan, lessons: lessons, generatedOutputs: generatedOutputs)
    }

    var coursePacingReadinessReport: CoursePacingReadinessReport {
        CoursePacingReadinessReport.analyze(configuration?.coursePacingPlan)
    }

    var weeklyPacingSuggestionReport: WeeklyPacingSuggestionReport {
        WeeklyPacingSuggestionReport.analyze(
            weeklyPlan: weeklyPlan,
            pacingPlan: configuration?.coursePacingPlan,
            lessons: lessons
        )
    }

    init(repository: any LocalRepositoryProtocol = LocalRepository(), slideDeckGenerator: (any SlideDeckGenerating.Type)? = nil) {
        self.repository = repository
        self.slideDeckGeneratorOverride = slideDeckGenerator
        dailyPlan = .empty()
        weeklyPlan = .empty(for: Self.startOfWeek(for: .now))
        slideDeckAvailability = NativePowerPointExporter.availability
        reload()
    }

    func reload() {
        reload(syncReadableDocuments: true)
    }

    private func reload(syncReadableDocuments: Bool) {
        do {
            teacherProfiles = try repository.loadTeacherProfiles()
            activeTeacherProfileID = try repository.loadActiveTeacherProfileID()
            configuration = try repository.loadConfiguration()
            slideDeckAvailability = activeSlideDeckGenerator.availability
            dailyPlan = try repository.loadDailyPlan(for: .now) ?? .empty()
            let weekOf = Self.startOfWeek(for: .now)
            weeklyPlan = try repository.loadWeeklyPlan(for: weekOf) ?? .empty(for: weekOf)
            lessons = try repository.loadLessons()
            importedSources = try repository.loadImportedSources()
            generatedOutputs = try repository.loadGeneratedOutputs()
            progressSnapshots = try repository.loadProgressSnapshots()
            lastError = nil
            if syncReadableDocuments {
                syncReadableDocumentsIntoWeeklyPlanner(rebuildExistingPacing: false)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func createLocalTeacherProfile(displayName: String, role: String, gradeOrSubject: String) {
        var profiles = teacherProfiles
        let profile = TeacherProfile.localTestProfile(displayName: displayName, role: role, gradeOrSubject: gradeOrSubject)
        profiles.append(profile)
        do {
            try repository.saveTeacherProfiles(profiles)
            try repository.saveActiveTeacherProfileID(profile.id)
            teacherProfiles = profiles
            activeTeacherProfileID = profile.id
            reload()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func switchTeacherProfile(_ profile: TeacherProfile?) {
        do {
            try repository.saveActiveTeacherProfileID(profile?.id)
            activeTeacherProfileID = profile?.id
            reload()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func saveCurrentProgressSnapshot(named name: String? = nil) {
        let snapshotName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let snapshot = PlanningProgressSnapshot(
            id: UUID(),
            name: snapshotName?.isEmpty == false ? snapshotName! : "Saved progress",
            savedAt: .now,
            configuration: configuration,
            dailyPlan: dailyPlan,
            weeklyPlan: weeklyPlan,
            lessons: lessons,
            importedSources: importedSources,
            generatedOutputs: generatedOutputs
        )
        do {
            try repository.saveProgressSnapshot(snapshot)
            progressSnapshots = try repository.loadProgressSnapshots()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func restoreProgressSnapshot(_ snapshot: PlanningProgressSnapshot) {
        do {
            if let configuration = snapshot.configuration {
                try repository.saveConfiguration(configuration)
            }
            try repository.saveDailyPlan(snapshot.dailyPlan)
            try repository.saveWeeklyPlan(snapshot.weeklyPlan)
            try repository.saveLessons(snapshot.lessons)
            try repository.saveImportedSources(snapshot.importedSources)
            try repository.saveGeneratedOutputs(snapshot.generatedOutputs)
            reload(syncReadableDocuments: false)
            weeklyPlan = snapshot.weeklyPlan
            dailyPlan = snapshot.dailyPlan
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func clearCurrentDocumentsAndEntries() {
        if var configuration {
            configuration.sourceRegistrations = []
            configuration.coursePacingPlan = nil
            configuration.updatedAt = .now
            self.configuration = configuration
            saveConfiguration()
        }
        dailyPlan = .empty()
        weeklyPlan = .empty(for: weeklyPlan.weekOf)
        lessons = []
        mostRecentLessonID = nil
        importedSources = []
        generatedOutputs = []
        lastPresentationTemplatePlaceholderResolution = []

        saveDailyPlan()
        saveWeeklyPlan()
        do {
            try repository.saveLessons([])
            try repository.saveImportedSources([])
            try repository.saveGeneratedOutputs([])
            progressSnapshots = try repository.loadProgressSnapshots()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func completeSetup(workspaceName: String, workspaceURL: URL, outputURL: URL?, templateURL: URL?, sourceURLs: [URL]) {
        var templates: [OutputTemplateRegistration] = []
        if let templateURL {
            templates.append(OutputTemplateRegistration(
                id: UUID(), displayName: templateURL.lastPathComponent, kind: .weeklyPlanHTML,
                reference: FileReference(url: templateURL), preserveLayout: true, slotMappings: nil, addedAt: .now
            ))
        }
        configuration = AppConfiguration(
            workspaceName: workspaceName,
            workspaceReference: FileReference(url: workspaceURL),
            outputFolderReference: outputURL.map(FileReference.init(url:)),
            sourceRegistrations: sourceURLs.map {
                SourceRegistration(id: UUID(), displayName: $0.lastPathComponent, kind: .curriculum, reference: FileReference(url: $0), notes: "", addedAt: .now)
            },
            outputTemplates: templates
        )
        saveConfiguration()
    }

    func setSlideDeckExporter(_ exporter: SlideDeckExporterPreference) {
        guard var configuration else {
            lastError = "Complete workspace setup before changing PowerPoint exporter settings."
            return
        }
        configuration.slideDeckExporter = exporter
        configuration.updatedAt = .now
        self.configuration = configuration
        slideDeckAvailability = activeSlideDeckGenerator.availability
        saveConfiguration()
    }

    func setWeeklyPlanningPrompt(_ preference: WeeklyPlanningPromptPreference) {
        guard var configuration else {
            lastError = "Complete workspace setup before changing weekly planning prompt settings."
            return
        }
        configuration.weeklyPlanningPrompt = preference
        configuration.updatedAt = .now
        self.configuration = configuration
        saveConfiguration()
    }

    func markWeeklyPlanningPromptHandled(at date: Date = .now) {
        guard var configuration else { return }
        configuration.weeklyPlanningPromptLastHandledAt = date
        configuration.updatedAt = .now
        self.configuration = configuration
        saveConfiguration()
    }

    func createStarterCoursePacingPlanFromReviewedSources() {
        guard var configuration else {
            lastError = "Complete workspace setup before creating course pacing."
            return
        }
        let readableSources = importedSources.filter { !$0.extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let pacingSources = readableSources.filter { $0.effectiveSetupRole.supportsCoursePacing }
        let sourcesForPacing = pacingSources.isEmpty ? readableSources : pacingSources
        guard !readableSources.isEmpty else {
            lastError = "Import at least one readable setup document before creating starter course pacing."
            return
        }
        configuration.coursePacingPlan = CoursePacingPlan.starter(from: sourcesForPacing)
        configuration.updatedAt = .now
        self.configuration = configuration
        saveConfiguration()
    }

    func updateCoursePacingPlan(_ plan: CoursePacingPlan) {
        guard var configuration else {
            lastError = "Complete workspace setup before updating course pacing."
            return
        }
        var updatedPlan = plan
        updatedPlan.updatedAt = .now
        configuration.coursePacingPlan = updatedPlan
        configuration.updatedAt = .now
        self.configuration = configuration
        saveConfiguration()
    }

    func updateCoursePacingRefinementNotes(_ notes: String) {
        guard var configuration, var plan = configuration.coursePacingPlan else {
            lastError = "Create a course pacing plan before adding refinement notes."
            return
        }
        plan.teacherRefinementNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        plan.updatedAt = .now
        configuration.coursePacingPlan = plan
        configuration.updatedAt = .now
        self.configuration = configuration
        saveConfiguration()
    }

    func approveCoursePacingPlan() {
        guard var configuration, var plan = configuration.coursePacingPlan else {
            lastError = "Create a course pacing plan before approval."
            return
        }
        plan.reviewStatus = .approved
        plan.updatedAt = .now
        configuration.coursePacingPlan = plan
        configuration.updatedAt = .now
        self.configuration = configuration
        saveConfiguration()
    }

    func updateCoursePacingUnit(
        unitID: UUID,
        title: String,
        startDate: Date?,
        endDate: Date?,
        estimatedInstructionalDays: Int,
        assessmentWindows: [String],
        notes: String
    ) {
        guard var configuration, var plan = configuration.coursePacingPlan else {
            lastError = "Create course pacing before editing a unit."
            return
        }
        guard let unitIndex = plan.units.firstIndex(where: { $0.id == unitID }) else {
            lastError = "The selected pacing unit is no longer available."
            return
        }
        guard Self.isValidDateRange(startDate: startDate, endDate: endDate) else {
            lastError = "Pacing end date must be on or after the start date."
            return
        }
        plan.units[unitIndex].title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled unit" : title.trimmingCharacters(in: .whitespacesAndNewlines)
        plan.units[unitIndex].startDate = startDate
        plan.units[unitIndex].endDate = endDate
        plan.units[unitIndex].estimatedInstructionalDays = max(1, estimatedInstructionalDays)
        plan.units[unitIndex].assessmentWindows = assessmentWindows
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        plan.units[unitIndex].notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        plan.updatedAt = .now
        configuration.coursePacingPlan = plan
        configuration.updatedAt = .now
        self.configuration = configuration
        saveConfiguration()
    }

    func addSkippedDayToCoursePacingUnit(unitID: UUID, date: Date) {
        guard var configuration, var plan = configuration.coursePacingPlan else {
            lastError = "Create course pacing before editing skipped days."
            return
        }
        guard let unitIndex = plan.units.firstIndex(where: { $0.id == unitID }) else {
            lastError = "The selected pacing unit is no longer available."
            return
        }
        let day = Calendar.current.startOfDay(for: date)
        if !plan.units[unitIndex].skippedDays.contains(where: { Calendar.current.isDate($0, inSameDayAs: day) }) {
            plan.units[unitIndex].skippedDays.append(day)
            plan.units[unitIndex].skippedDays.sort()
        }
        plan.updatedAt = .now
        configuration.coursePacingPlan = plan
        configuration.updatedAt = .now
        self.configuration = configuration
        saveConfiguration()
    }

    func removeSkippedDayFromCoursePacingUnit(unitID: UUID, date: Date) {
        guard var configuration, var plan = configuration.coursePacingPlan else {
            lastError = "Create course pacing before editing skipped days."
            return
        }
        guard let unitIndex = plan.units.firstIndex(where: { $0.id == unitID }) else {
            lastError = "The selected pacing unit is no longer available."
            return
        }
        plan.units[unitIndex].skippedDays.removeAll { Calendar.current.isDate($0, inSameDayAs: date) }
        plan.updatedAt = .now
        configuration.coursePacingPlan = plan
        configuration.updatedAt = .now
        self.configuration = configuration
        saveConfiguration()
    }

    func updateCoursePacingModule(
        unitID: UUID,
        moduleID: UUID,
        title: String,
        startDate: Date?,
        endDate: Date?,
        estimatedInstructionalDays: Int,
        notes: String
    ) {
        guard var configuration, var plan = configuration.coursePacingPlan else {
            lastError = "Create course pacing before editing a module."
            return
        }
        guard let unitIndex = plan.units.firstIndex(where: { $0.id == unitID }),
              let moduleIndex = plan.units[unitIndex].modules.firstIndex(where: { $0.id == moduleID })
        else {
            lastError = "The selected pacing module is no longer available."
            return
        }
        guard Self.isValidDateRange(startDate: startDate, endDate: endDate) else {
            lastError = "Pacing end date must be on or after the start date."
            return
        }
        plan.units[unitIndex].modules[moduleIndex].title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled module" : title.trimmingCharacters(in: .whitespacesAndNewlines)
        plan.units[unitIndex].modules[moduleIndex].startDate = startDate
        plan.units[unitIndex].modules[moduleIndex].endDate = endDate
        plan.units[unitIndex].modules[moduleIndex].estimatedInstructionalDays = max(1, estimatedInstructionalDays)
        plan.units[unitIndex].modules[moduleIndex].notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        plan.updatedAt = .now
        configuration.coursePacingPlan = plan
        configuration.updatedAt = .now
        self.configuration = configuration
        saveConfiguration()
    }

    func updateCoursePacingLesson(
        unitID: UUID,
        moduleID: UUID,
        lessonID: UUID,
        title: String,
        startDate: Date?,
        endDate: Date?,
        estimatedInstructionalDays: Int,
        dependencyNotes: String,
        sourceNotes: String
    ) {
        guard var configuration, var plan = configuration.coursePacingPlan else {
            lastError = "Create course pacing before editing a lesson."
            return
        }
        guard let unitIndex = plan.units.firstIndex(where: { $0.id == unitID }),
              let moduleIndex = plan.units[unitIndex].modules.firstIndex(where: { $0.id == moduleID }),
              let lessonIndex = plan.units[unitIndex].modules[moduleIndex].lessons.firstIndex(where: { $0.id == lessonID })
        else {
            lastError = "The selected pacing lesson is no longer available."
            return
        }
        guard Self.isValidDateRange(startDate: startDate, endDate: endDate) else {
            lastError = "Pacing end date must be on or after the start date."
            return
        }
        plan.units[unitIndex].modules[moduleIndex].lessons[lessonIndex].title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled lesson" : title.trimmingCharacters(in: .whitespacesAndNewlines)
        plan.units[unitIndex].modules[moduleIndex].lessons[lessonIndex].startDate = startDate
        plan.units[unitIndex].modules[moduleIndex].lessons[lessonIndex].endDate = endDate
        plan.units[unitIndex].modules[moduleIndex].lessons[lessonIndex].estimatedInstructionalDays = max(1, estimatedInstructionalDays)
        plan.units[unitIndex].modules[moduleIndex].lessons[lessonIndex].dependencyNotes = dependencyNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        plan.units[unitIndex].modules[moduleIndex].lessons[lessonIndex].sourceNotes = sourceNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        plan.updatedAt = .now
        configuration.coursePacingPlan = plan
        configuration.updatedAt = .now
        self.configuration = configuration
        saveConfiguration()
    }

    private static func isValidDateRange(startDate: Date?, endDate: Date?) -> Bool {
        guard let startDate, let endDate else { return true }
        return Calendar.current.startOfDay(for: endDate) >= Calendar.current.startOfDay(for: startDate)
    }

    func addScheduleBlock(title: String, start: Date, end: Date, type: String, notes: String = "") {
        dailyPlan.scheduleBlocks.append(ScheduleBlock(id: UUID(), title: title, start: start, end: end, type: type, linkedLessonRecordID: nil, notes: notes))
        dailyPlan.scheduleBlocks.sort { $0.start < $1.start }
        saveDailyPlan()
    }

    func removeScheduleBlock(_ block: ScheduleBlock) {
        dailyPlan.scheduleBlocks.removeAll { $0.id == block.id }
        saveDailyPlan()
    }

    func addWeeklyAssignment(lessonID: UUID, date: Date, start: Date, end: Date, planningNotes: String = "") {
        weeklyPlan.assignments.append(WeeklyLessonAssignment(
            id: UUID(),
            lessonRecordID: lessonID,
            date: date,
            start: start,
            end: end,
            planningNotes: planningNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
        weeklyPlan.assignments.sort { $0.date == $1.date ? $0.start < $1.start : $0.date < $1.date }
        saveWeeklyPlan()
    }

    func setWeeklyPlanWeek(of date: Date) {
        let weekOf = Self.startOfWeek(for: date)
        if Calendar.current.isDate(weeklyPlan.weekOf, inSameDayAs: weekOf) { return }
        do {
            weeklyPlan = try repository.loadWeeklyPlan(for: weekOf) ?? .empty(for: weekOf)
            lastError = nil
        } catch {
            weeklyPlan = .empty(for: weekOf)
            lastError = error.localizedDescription
        }
    }

    func removeWeeklyAssignment(_ assignment: WeeklyLessonAssignment) {
        weeklyPlan.assignments.removeAll { $0.id == assignment.id }
        saveWeeklyPlan()
    }

    func updateWeeklyAssignment(_ assignment: WeeklyLessonAssignment, date: Date, start: Date, end: Date, planningNotes: String) {
        guard let index = weeklyPlan.assignments.firstIndex(where: { $0.id == assignment.id }) else { return }
        weeklyPlan.assignments[index].date = date
        weeklyPlan.assignments[index].start = start
        weeklyPlan.assignments[index].end = end
        weeklyPlan.assignments[index].planningNotes = planningNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        weeklyPlan.assignments.sort { $0.date == $1.date ? $0.start < $1.start : $0.date < $1.date }
        saveWeeklyPlan()
    }

    func updateWeeklyPlanningBrief(teacherFocus: String, preparationNotes: String, studentSupportNotes: String) {
        weeklyPlan.planningBrief = WeeklyPlanningBrief(
            teacherFocus: teacherFocus.trimmingCharacters(in: .whitespacesAndNewlines),
            preparationNotes: preparationNotes.trimmingCharacters(in: .whitespacesAndNewlines),
            studentSupportNotes: studentSupportNotes.trimmingCharacters(in: .whitespacesAndNewlines),
            updatedAt: .now
        )
        saveWeeklyPlan()
    }

    func proposeWeeklyPacingRefinement(from checkInNote: String) {
        guard configuration?.coursePacingPlan != nil else {
            lastError = "Create course pacing before drafting a weekly pacing refinement."
            return
        }
        guard let proposal = WeeklyPacingRefinementProposal.draft(from: checkInNote, weekOf: weeklyPlan.weekOf) else {
            lastError = "Add a weekly check-in note before drafting a pacing refinement."
            return
        }
        weeklyPlan.pacingRefinementProposal = proposal
        weeklyPlan.updatedAt = .now
        saveWeeklyPlan()
    }

    func acceptWeeklyPacingRefinement() {
        guard var proposal = weeklyPlan.pacingRefinementProposal else {
            lastError = "Draft a weekly pacing refinement before accepting it."
            return
        }
        guard var configuration, var pacingPlan = configuration.coursePacingPlan else {
            lastError = "Create course pacing before accepting a weekly refinement."
            return
        }
        let acceptedAt = Date.now
        proposal.status = .accepted
        proposal.acceptedAt = acceptedAt
        weeklyPlan.pacingRefinementProposal = proposal
        weeklyPlan.updatedAt = acceptedAt

        let shiftedUnitDateCount = applyAcceptedPacingDateShift(proposal, to: &pacingPlan)
        let acceptedNote = [
            proposal.proposedAdjustmentSummary,
            proposal.affectedPacingArea.map { "Affected area: \($0)." },
            proposal.suggestedDateShiftDays.map { "Suggested date shift: \($0) instructional day(s)." },
            shiftedUnitDateCount > 0 ? "Applied to \(shiftedUnitDateCount) pacing date field(s)." : "No dated pacing fields were changed.",
            proposal.pacingImpactNotes,
            "Teacher check-in: \(proposal.checkInNote)"
        ].compactMap(\.self).joined(separator: " ")
        if pacingPlan.teacherRefinementNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pacingPlan.teacherRefinementNotes = acceptedNote
        } else {
            pacingPlan.teacherRefinementNotes += "\n\(acceptedNote)"
        }
        pacingPlan.updatedAt = acceptedAt
        configuration.coursePacingPlan = pacingPlan
        configuration.updatedAt = acceptedAt
        self.configuration = configuration
        saveWeeklyPlan()
        saveConfiguration()
    }

    private func applyAcceptedPacingDateShift(_ proposal: WeeklyPacingRefinementProposal, to pacingPlan: inout CoursePacingPlan) -> Int {
        guard let shiftDays = proposal.suggestedDateShiftDays, shiftDays != 0 else { return 0 }
        var shiftedCount = 0
        for index in pacingPlan.units.indices {
            if let startDate = pacingPlan.units[index].startDate,
               let shiftedStartDate = Calendar.current.date(byAdding: .day, value: shiftDays, to: startDate) {
                pacingPlan.units[index].startDate = shiftedStartDate
                shiftedCount += 1
            }
            if let endDate = pacingPlan.units[index].endDate,
               let shiftedEndDate = Calendar.current.date(byAdding: .day, value: shiftDays, to: endDate) {
                pacingPlan.units[index].endDate = shiftedEndDate
                shiftedCount += 1
            }
            for moduleIndex in pacingPlan.units[index].modules.indices {
                if let startDate = pacingPlan.units[index].modules[moduleIndex].startDate,
                   let shiftedStartDate = Calendar.current.date(byAdding: .day, value: shiftDays, to: startDate) {
                    pacingPlan.units[index].modules[moduleIndex].startDate = shiftedStartDate
                    shiftedCount += 1
                }
                if let endDate = pacingPlan.units[index].modules[moduleIndex].endDate,
                   let shiftedEndDate = Calendar.current.date(byAdding: .day, value: shiftDays, to: endDate) {
                    pacingPlan.units[index].modules[moduleIndex].endDate = shiftedEndDate
                    shiftedCount += 1
                }
                for lessonIndex in pacingPlan.units[index].modules[moduleIndex].lessons.indices {
                    if let startDate = pacingPlan.units[index].modules[moduleIndex].lessons[lessonIndex].startDate,
                       let shiftedStartDate = Calendar.current.date(byAdding: .day, value: shiftDays, to: startDate) {
                        pacingPlan.units[index].modules[moduleIndex].lessons[lessonIndex].startDate = shiftedStartDate
                        shiftedCount += 1
                    }
                    if let endDate = pacingPlan.units[index].modules[moduleIndex].lessons[lessonIndex].endDate,
                       let shiftedEndDate = Calendar.current.date(byAdding: .day, value: shiftDays, to: endDate) {
                        pacingPlan.units[index].modules[moduleIndex].lessons[lessonIndex].endDate = shiftedEndDate
                        shiftedCount += 1
                    }
                }
            }
        }
        return shiftedCount
    }

    func addTask(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        dailyPlan.tasks.append(DailyTask(id: UUID(), title: trimmed, status: .open, dueTime: nil, linkedLessonRecordID: nil, notes: ""))
        saveDailyPlan()
    }

    func toggleTask(_ task: DailyTask) {
        guard let index = dailyPlan.tasks.firstIndex(where: { $0.id == task.id }) else { return }
        dailyPlan.tasks[index].status = task.status == .open ? .complete : .open
        saveDailyPlan()
    }

    func removeTask(_ task: DailyTask) {
        dailyPlan.tasks.removeAll { $0.id == task.id }
        saveDailyPlan()
    }

    func saveDraftLesson(title: String, objective: String) {
        var lesson = LessonRecord.draft(title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled lesson" : title)
        lesson.objective = objective
        lessons.append(lesson)
        mostRecentLessonID = lesson.id
        saveLessons()
    }

    func createDraftLesson(from pacingSuggestion: WeeklyPacingSuggestion) {
        var lesson = LessonRecord.draft(title: pacingSuggestion.pacingLessonTitle)
        lesson.sourceReferences = [pacingSuggestion.planningNote]
        lesson.aiReviewWarnings = ["Created from approved course pacing. Add teacher-reviewed lesson content before approval."]
        lesson.instructionalSequence = [
            InstructionalStep(
                id: UUID(),
                title: "Plan \(pacingSuggestion.pacingLessonTitle)",
                notes: "Use the readable setup documents and teacher judgment to complete this lesson."
            )
        ]
        lessons.append(lesson)
        mostRecentLessonID = lesson.id
        saveLessons()
    }

    func importDocument(_ url: URL) {
        let fileExtension = url.pathExtension.lowercased()
        switch fileExtension {
        case "pdf":
            importPDF(url)
        case "docx":
            importDOCX(url)
        default:
            lastError = PDFTextExtractionError.unsupportedFileType.localizedDescription
        }
    }

    private func importPDF(_ url: URL) {
        guard let document = PDFDocument(url: url) else {
            lastError = PDFTextExtractionError.unreadable.localizedDescription
            return
        }
        let text = document.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let extraction: (method: SourceExtractionMethod, text: String, confidence: Double?)
        if text.isEmpty {
            do {
                let result = try recognizeText(in: document)
                extraction = result.text.isEmpty
                    ? (method: .ocrRequired, text: "", confidence: nil)
                    : (method: .localOCR, text: result.text, confidence: result.confidence)
            } catch {
                lastError = error.localizedDescription
                return
            }
        } else {
            extraction = (method: .embeddedText, text: text, confidence: nil)
        }
        let source = ImportedSource(
            id: UUID(), reference: FileReference(url: url),
            setupRole: ImportedSourceRole.infer(displayName: url.lastPathComponent, extractedText: extraction.text),
            extractionMethod: extraction.method,
            confidence: extraction.confidence, extractedText: extraction.text,
            reviewStatus: extraction.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .imported : .reviewed,
            importedAt: .now, updatedAt: .now
        )
        importedSources.insert(source, at: 0)
        saveImportedSources()
    }

    private func importDOCX(_ url: URL) {
        do {
            let text = try extractDOCXText(from: url)
            let source = ImportedSource(
                id: UUID(), reference: FileReference(url: url),
                setupRole: ImportedSourceRole.infer(displayName: url.lastPathComponent, extractedText: text),
                extractionMethod: .embeddedText,
                confidence: nil, extractedText: text,
                reviewStatus: .reviewed, importedAt: .now, updatedAt: .now
            )
            importedSources.insert(source, at: 0)
            saveImportedSources()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func importDocuments(_ urls: [URL]) {
        for url in urls {
            importDocument(url)
        }
        syncReadableDocumentsIntoWeeklyPlanner(rebuildExistingPacing: true)
    }

    func importDocumentItems(_ urls: [URL]) {
        for url in urls {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                importDocumentsInFolder(url)
            } else {
                importDocument(url)
            }
        }
        syncReadableDocumentsIntoWeeklyPlanner(rebuildExistingPacing: true)
    }

    func importDocumentsInFolder(_ folderURL: URL) {
        let allowedExtensions = Set(["pdf", "docx"])
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            lastError = "The selected folder could not be scanned."
            return
        }
        let urls = enumerator.compactMap { item -> URL? in
            guard let url = item as? URL,
                  allowedExtensions.contains(url.pathExtension.lowercased())
            else { return nil }
            return url
        }
        guard !urls.isEmpty else {
            lastError = "No PDF or DOCX files were found in that folder."
            return
        }
        for url in urls {
            importDocument(url)
        }
        syncReadableDocumentsIntoWeeklyPlanner(rebuildExistingPacing: true)
    }

    func refreshWeeklyPlannerFromReadableDocuments() {
        syncReadableDocumentsIntoWeeklyPlanner(rebuildExistingPacing: false)
    }

    private func syncReadableDocumentsIntoWeeklyPlanner(rebuildExistingPacing: Bool) {
        guard var configuration else { return }
        let readableSources = importedSources.filter { !$0.extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !readableSources.isEmpty else { return }
        let plan: CoursePacingPlan
        if !rebuildExistingPacing, let existingPlan = configuration.coursePacingPlan, !existingPlan.units.isEmpty {
            plan = existingPlan.reviewStatus == .approved ? existingPlan : {
                var approvedPlan = existingPlan
                approvedPlan.reviewStatus = .approved
                approvedPlan.teacherRefinementNotes = appendLine(
                    to: approvedPlan.teacherRefinementNotes,
                    line: "Auto-approved so readable document intake can update the weekly planner. Teachers can edit any blank or incorrect fields."
                )
                configuration.coursePacingPlan = approvedPlan
                configuration.updatedAt = .now
                self.configuration = configuration
                saveConfiguration()
                return approvedPlan
            }()
        } else {
            let lessonPlanningSources = readableSources.filter { source in
                ![ImportedSourceRole.instructionalCalendar, .assessmentSchedule].contains(source.effectiveSetupRole)
            }
            var starterPlan = CoursePacingPlan.starter(from: lessonPlanningSources.isEmpty ? readableSources : lessonPlanningSources)
            guard !starterPlan.units.isEmpty else { return }
            starterPlan.reviewStatus = .approved
            starterPlan.teacherRefinementNotes = appendLine(
                to: starterPlan.teacherRefinementNotes,
                line: "Auto-built from readable document intake. Teachers can edit any blank or incorrect fields."
            )
            configuration.coursePacingPlan = starterPlan
            configuration.updatedAt = .now
            self.configuration = configuration
            saveConfiguration()
            plan = starterPlan
        }

        let firstPass = WeeklyPacingSuggestionReport.analyze(weeklyPlan: weeklyPlan, pacingPlan: plan, lessons: lessons)
        for suggestion in firstPass.suggestions where suggestion.status == .needsApprovedLesson {
            guard !Self.isPlaceholderPacingTitle(suggestion.pacingLessonTitle) else { continue }
            _ = ensureApprovedLesson(for: suggestion)
        }

        let secondPass = WeeklyPacingSuggestionReport.analyze(weeklyPlan: weeklyPlan, pacingPlan: plan, lessons: lessons)
        let scheduleBlocks = importedDailyScheduleBlocks(from: readableSources)
        for suggestion in secondPass.suggestions where suggestion.status == .readyToSchedule || suggestion.status == .alreadyScheduled {
            guard let lessonID = suggestion.lessonRecordID else { continue }
            guard !Self.isPlaceholderPacingTitle(suggestion.pacingLessonTitle) else { continue }
            let timeRange = scheduledTimeRange(for: suggestion, on: suggestion.suggestedDate, scheduleBlocks: scheduleBlocks)
            if let existingIndex = weeklyPlan.assignments.firstIndex(where: { $0.lessonRecordID == lessonID }) {
                let existingNotes = weeklyPlan.assignments[existingIndex].planningNotes ?? ""
                guard existingNotes.hasPrefix("Pacing:") else { continue }
                weeklyPlan.assignments[existingIndex].date = suggestion.suggestedDate
                weeklyPlan.assignments[existingIndex].start = timeRange.start
                weeklyPlan.assignments[existingIndex].end = timeRange.end
                weeklyPlan.assignments[existingIndex].planningNotes = suggestion.planningNote
                continue
            }
            weeklyPlan.assignments.append(WeeklyLessonAssignment(
                id: UUID(),
                lessonRecordID: lessonID,
                date: suggestion.suggestedDate,
                start: timeRange.start,
                end: timeRange.end,
                planningNotes: suggestion.planningNote
            ))
        }
        weeklyPlan.assignments.sort { $0.date == $1.date ? $0.start < $1.start : $0.date < $1.date }
        saveWeeklyPlan()
    }

    private func ensureApprovedLesson(for suggestion: WeeklyPacingSuggestion) -> UUID {
        let normalizedSuggestionTitle = Self.normalizedLessonTitle(suggestion.pacingLessonTitle)
        if let existing = lessons.first(where: { Self.normalizedLessonTitle($0.title) == normalizedSuggestionTitle }) {
            if existing.status == .approved {
                return existing.id
            }
            var updated = existing
            updated.status = .approved
            updateLesson(updated)
            return updated.id
        }

        var lesson = LessonRecord.draft(title: suggestion.pacingLessonTitle)
        lesson.status = .approved
        lesson.sourceReferences = [suggestion.planningNote]
        lesson.aiReviewWarnings = ["Auto-created from readable planning documents. Fill any blank or incorrect fields as needed."]
        lesson.instructionalSequence = [
            InstructionalStep(
                id: UUID(),
                title: suggestion.pacingLessonTitle,
                notes: "Auto-filled from course pacing. Add details if needed."
            )
        ]
        lessons.append(lesson)
        mostRecentLessonID = lesson.id
        saveLessons()
        return lesson.id
    }

    private func defaultLessonStart(on date: Date) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        components.hour = 9
        components.minute = 0
        components.second = 0
        return Calendar.current.date(from: components) ?? date
    }

    private func scheduledTimeRange(
        for suggestion: WeeklyPacingSuggestion,
        on date: Date,
        scheduleBlocks: [ImportedDailyScheduleBlock]
    ) -> (start: Date, end: Date) {
        if let block = bestScheduleBlock(for: suggestion, in: scheduleBlocks) {
            return (dateAt(hour: block.startHour, minute: block.startMinute, on: date), dateAt(hour: block.endHour, minute: block.endMinute, on: date))
        }
        let start = defaultLessonStart(on: date)
        let end = Calendar.current.date(byAdding: .minute, value: 45, to: start) ?? start.addingTimeInterval(2_700)
        return (start, end)
    }

    private func dateAt(hour: Int, minute: Int, on date: Date) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return Calendar.current.date(from: components) ?? date
    }

    private func bestScheduleBlock(
        for suggestion: WeeklyPacingSuggestion,
        in blocks: [ImportedDailyScheduleBlock]
    ) -> ImportedDailyScheduleBlock? {
        let subjectText = "\(suggestion.unitTitle) \(suggestion.moduleTitle) \(suggestion.pacingLessonTitle)".lowercased()
        let candidates: [String]
        if subjectText.contains("english") || subjectText.contains("ela") || subjectText.contains("reading") || subjectText.contains("writing") {
            candidates = ["english", "ela", "language arts", "reading", "writing"]
        } else if subjectText.contains("math") {
            candidates = ["math"]
        } else if subjectText.contains("art") || subjectText.contains("sketchbook") || subjectText.contains("color") {
            candidates = ["art", "specials"]
        } else if subjectText.contains("science") {
            candidates = ["science"]
        } else if subjectText.contains("social studies") || subjectText.contains("community") || subjectText.contains("map") {
            candidates = ["social studies"]
        } else {
            candidates = []
        }
        guard !candidates.isEmpty else { return nil }
        return blocks.first { block in
            let label = block.label.lowercased()
            return candidates.contains { label.contains($0) }
        }
    }

    private func importedDailyScheduleBlocks(from sources: [ImportedSource]) -> [ImportedDailyScheduleBlock] {
        sources
            .filter { source in
                source.effectiveSetupRole == .instructionalCalendar
                    || source.reference.displayName.lowercased().contains("schedule")
                    || source.extractedText.lowercased().contains("sample daily schedule")
            }
            .flatMap { importedDailyScheduleBlocks(from: $0.extractedText) }
    }

    private func importedDailyScheduleBlocks(from text: String) -> [ImportedDailyScheduleBlock] {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let timePattern = #"^(\d{1,2}):(\d{2})\s*[-–]\s*(\d{1,2}):(\d{2})$"#
        let regex = try? NSRegularExpression(pattern: timePattern)
        return lines.enumerated().compactMap { index, line in
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = regex?.firstMatch(in: line, range: range), match.numberOfRanges == 5 else { return nil }
            func intValue(_ rangeIndex: Int) -> Int {
                guard let range = Range(match.range(at: rangeIndex), in: line) else { return 0 }
                return Int(line[range]) ?? 0
            }
            let label = index + 1 < lines.count ? lines[index + 1] : "Scheduled block"
            return ImportedDailyScheduleBlock(
                startHour: intValue(1),
                startMinute: intValue(2),
                endHour: intValue(3),
                endMinute: intValue(4),
                label: label
            )
        }
    }

    private static func normalizedLessonTitle(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && $0 != "lesson" }
            .joined(separator: " ")
    }

    private static func isPlaceholderPacingTitle(_ value: String) -> Bool {
        normalizedLessonTitle(value) == "teacher reviewed sequence needed"
    }

    private func appendLine(to existing: String, line: String) -> String {
        let trimmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? line : "\(trimmed)\n\(line)"
    }

    func saveSourceReview(id: UUID, text: String) {
        guard let index = importedSources.firstIndex(where: { $0.id == id }) else { return }
        importedSources[index].extractedText = text
        if importedSources[index].setupRole == nil || importedSources[index].setupRole == .other {
            importedSources[index].setupRole = ImportedSourceRole.infer(displayName: importedSources[index].reference.displayName, extractedText: text)
        }
        importedSources[index].reviewStatus = .reviewed
        importedSources[index].updatedAt = .now
        saveImportedSources()
        syncReadableDocumentsIntoWeeklyPlanner(rebuildExistingPacing: true)
    }

    func updateImportedSourceRole(id: UUID, role: ImportedSourceRole) {
        guard let index = importedSources.firstIndex(where: { $0.id == id }) else { return }
        importedSources[index].setupRole = role
        importedSources[index].updatedAt = .now
        saveImportedSources()
        syncReadableDocumentsIntoWeeklyPlanner(rebuildExistingPacing: true)
    }

    func createDraftLesson(from source: ImportedSource, title: String, objective: String) {
        var lesson = LessonRecord.draft(title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? source.reference.displayName : title)
        lesson.objective = objective
        lesson.sourceReferences = [source.reference.path]
        lesson.sourceTextSnapshot = source.extractedText
        lessons.append(lesson)
        mostRecentLessonID = lesson.id
        saveLessons()
    }

    func createDraftLesson(from proposal: LessonDraftProposal, source: ImportedSource) {
        let title = proposal.title.trimmingCharacters(in: .whitespacesAndNewlines)
        var lesson = LessonRecord.draft(title: title.isEmpty ? source.reference.displayName : title)
        lesson.subject = proposal.subject
        lesson.gradeOrAgeRange = proposal.gradeOrAgeRange
        lesson.objective = proposal.objective
        let scheduleOnly = proposal.sourceType?.lowercased() == "schedule"
        lesson.instructionalSequence = (scheduleOnly ? [] : proposal.instructionalSteps)
            .map { InstructionalStep(id: UUID(), title: $0.trimmingCharacters(in: .whitespacesAndNewlines), notes: "") }
            .filter { !$0.title.isEmpty }
        lesson.materials = (scheduleOnly ? [] : proposal.materials).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        lesson.differentiationSummary = scheduleOnly ? "" : proposal.differentiationSummary
        lesson.printableResourcePrompt = scheduleOnly ? "" : proposal.printableResourcePrompt
        lesson.assessmentSummary = scheduleOnly ? "" : proposal.assessmentSummary
        lesson.aiReviewWarnings = LessonDraftValidator.warnings(for: proposal) + (scheduleOnly ? ["This source was classified as a schedule. Instructional fields were intentionally left blank."] : [])
        lesson.sourceReferences = [source.reference.path]
        lesson.sourceTextSnapshot = source.extractedText
        lessons.append(lesson)
        mostRecentLessonID = lesson.id
        saveLessons()
    }

    func lessonDraftPrompt(for source: ImportedSource) -> String {
        """
        Analyze the following readable source text and return exactly one valid JSON object—no Markdown, no commentary.

        First classify the source as one of: lesson, schedule, mixed, reference, or unknown.
        Do not invent facts. Use empty strings or empty arrays when the source does not explicitly support a field. A schedule is not a lesson plan: if sourceType is schedule, leave instructionalSteps, materials, differentiationSummary, printableResourcePrompt, and assessmentSummary empty. Use reviewWarnings to explain missing or uncertain information. Keep instructionalSteps concise and instructional, not administrative.

        Required JSON schema:
        {
          "title": "",
          "subject": "",
          "gradeOrAgeRange": "",
          "objective": "",
          "instructionalSteps": [""],
          "materials": [""],
          "differentiationSummary": "",
          "printableResourcePrompt": "",
          "assessmentSummary": ""
          ,"sourceType": "unknown"
          ,"reviewWarnings": [""]
        }

        Readable source text:
        \(source.extractedText)
        """
    }

    func generateCodexDraft(from source: ImportedSource) async throws -> LessonDraftProposal {
        let prompt = lessonDraftPrompt(for: source)
        return try await Task.detached(priority: .userInitiated) {
            try CodexCLIAdapter.generateDraft(prompt: prompt)
        }.value
    }

    func updateLesson(_ lesson: LessonRecord) {
        guard let index = lessons.firstIndex(where: { $0.id == lesson.id }) else { return }
        var updated = lesson
        updated.updatedAt = .now
        lessons[index] = updated
        saveLessons()
    }

    func fillEmptyLessonFieldsFromSource(_ lesson: LessonRecord) -> LessonRecord {
        guard let sourceText = lesson.sourceTextSnapshot, !sourceText.isEmpty else {
            lastError = "This lesson has no readable source text available."
            return lesson
        }
        var updated = lesson
        let extracted = LessonFieldExtractor.extract(from: sourceText)
        if updated.subject.isEmpty { updated.subject = extracted.subject ?? updated.subject }
        if updated.gradeOrAgeRange.isEmpty { updated.gradeOrAgeRange = extracted.gradeOrAgeRange ?? updated.gradeOrAgeRange }
        if updated.objective.isEmpty { updated.objective = extracted.objective ?? updated.objective }
        if updated.materials.isEmpty { updated.materials = extracted.materials }
        if updated.assessmentSummary.isEmpty { updated.assessmentSummary = extracted.assessment ?? updated.assessmentSummary }
        if updated.differentiationSummary.isEmpty { updated.differentiationSummary = extracted.differentiation ?? updated.differentiationSummary }
        if updated.instructionalSequence.isEmpty {
            updated.instructionalSequence = extracted.steps.map { InstructionalStep(id: UUID(), title: $0, notes: "") }
        }
        updateLesson(updated)
        return updated
    }

    func generateLessonPlanHTML(for lesson: LessonRecord) -> GeneratedOutputRecord? {
        guard lesson.status == .approved else {
            lastError = "Approve the lesson before generating an output."
            return nil
        }
        guard let outputURL = outputDirectoryURL() else {
            lastError = "Choose an output folder in Workspace before generating an output."
            return nil
        }
        do {
            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd-HHmm"
            let filename = "\(LessonPlanRenderer.safeFileStem(lesson.title))-\(formatter.string(from: .now)).html"
            let fileURL = outputURL.appending(path: filename)
            try LessonPlanRenderer.renderHTML(for: lesson).write(to: fileURL, atomically: true, encoding: .utf8)
            let templateName = configuration?.outputTemplates.first(where: { $0.kind == .weeklyPlanHTML })?.displayName
            let output = GeneratedOutputRecord(id: UUID(), lessonRecordID: lesson.id, kind: .lessonPlanHTML, displayName: filename, filePath: fileURL.path, templateDisplayName: templateName, createdAt: .now)
            generatedOutputs.insert(output, at: 0)
            saveGeneratedOutputs()
            lastError = nil
            return output
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func generateWeeklyPlanHTML() -> GeneratedOutputRecord? {
        guard let outputURL = outputDirectoryURL() else { lastError = "Choose an output folder in Workspace before generating an output."; return nil }
        do {
            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
            let fileURL = outputURL.appending(path: "weekly-lesson-plan-\(weeklyPlan.weekOf.formatted(.iso8601.year().month().day())).html")
            try LessonPlanRenderer.renderWeeklyHTML(plan: weeklyPlan, lessons: lessons, generatedOutputs: generatedOutputs).write(to: fileURL, atomically: true, encoding: .utf8)
            let templateName = configuration?.outputTemplates.first(where: { $0.kind == .weeklyPlanHTML })?.displayName
            let output = GeneratedOutputRecord(id: UUID(), lessonRecordID: nil, kind: .weeklyPlanHTML, displayName: fileURL.lastPathComponent, filePath: fileURL.path, templateDisplayName: templateName, createdAt: .now)
            generatedOutputs.insert(output, at: 0)
            saveGeneratedOutputs()
            lastError = nil
            return output
        } catch { lastError = error.localizedDescription; return nil }
    }

    func generateWeeklyPackageHTML() async -> GeneratedOutputRecord? {
        let readiness = weeklyPackageReadinessReport
        guard readiness.canGenerate else {
            lastError = readiness.blockingIssues.first?.instruction ?? "Finish weekly package setup before generating."
            return nil
        }
        let scheduledLessonIDs = Array(Set(weeklyPlan.assignments.map(\.lessonRecordID)))
        let scheduledLessons = lessons.filter { scheduledLessonIDs.contains($0.id) && $0.status == .approved }
        for lesson in scheduledLessons {
            if latestGeneratedOutput(kind: .lessonPlanHTML, for: lesson.id) == nil {
                _ = generateLessonPlanHTML(for: lesson)
            }
            if latestGeneratedOutput(kind: .differentiationGuideHTML, for: lesson.id) == nil {
                _ = generateDifferentiationGuideHTML(for: lesson)
            }
            if latestGeneratedOutput(kind: .slideDeckPPTX, for: lesson.id) == nil {
                _ = await generateSlideDeckPPTX(for: lesson)
            }
        }
        return generateWeeklyPlanHTML()
    }

    func generateDifferentiationGuideHTML(for lesson: LessonRecord) -> GeneratedOutputRecord? {
        guard lesson.status == .approved else { lastError = "Approve the lesson before generating an output."; return nil }
        guard let outputURL = outputDirectoryURL() else { lastError = "Choose an output folder in Workspace before generating an output."; return nil }
        do {
            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
            let fileURL = outputURL.appending(path: "\(LessonPlanRenderer.safeFileStem(lesson.title))-differentiation-guide.html")
            try LessonPlanRenderer.renderDifferentiationGuideHTML(for: lesson).write(to: fileURL, atomically: true, encoding: .utf8)
            let output = GeneratedOutputRecord(id: UUID(), lessonRecordID: lesson.id, kind: .differentiationGuideHTML, displayName: fileURL.lastPathComponent, filePath: fileURL.path, templateDisplayName: nil, createdAt: .now)
            generatedOutputs.insert(output, at: 0)
            saveGeneratedOutputs()
            lastError = nil
            return output
        } catch { lastError = error.localizedDescription; return nil }
    }

    func generateSlideDeckPPTX(for lesson: LessonRecord) async -> GeneratedOutputRecord? {
        guard lesson.status == .approved else { lastError = "Approve the lesson before generating an output."; return nil }
        guard let outputURL = outputDirectoryURL() else { lastError = "Choose an output folder in Workspace before generating an output."; return nil }
        let fileURL = outputURL.appending(path: "\(LessonPlanRenderer.safeFileStem(lesson.title))-slide-deck.pptx")
        let presentationTemplate = activePresentationTemplate
        do {
            try await activeSlideDeckGenerator.generate(lesson: lesson, destination: fileURL, template: presentationTemplate)
            generatedOutputs.removeAll { $0.lessonRecordID == lesson.id && $0.kind == .slideDeckPPTX && $0.filePath == fileURL.path }
            let output = GeneratedOutputRecord(id: UUID(), lessonRecordID: lesson.id, kind: .slideDeckPPTX, displayName: fileURL.lastPathComponent, filePath: fileURL.path, templateDisplayName: presentationTemplate?.displayName, createdAt: .now)
            generatedOutputs.insert(output, at: 0)
            saveGeneratedOutputs()
            lastError = nil
            return output
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func markGeneratedOutputReviewed(_ output: GeneratedOutputRecord, notes: String = "") -> GeneratedOutputRecord? {
        guard let index = generatedOutputs.firstIndex(where: { $0.id == output.id }) else {
            lastError = "Generated output is no longer in history."
            return nil
        }
        generatedOutputs[index].review = GeneratedOutputReview(
            reviewedAt: .now,
            reviewerNotes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        saveGeneratedOutputs()
        lastError = nil
        return generatedOutputs[index]
    }

    private func latestGeneratedOutput(kind: GeneratedOutputKind, for lessonID: UUID) -> GeneratedOutputRecord? {
        generatedOutputs
            .filter { $0.kind == kind && $0.lessonRecordID == lessonID }
            .sorted { $0.createdAt > $1.createdAt }
            .first
    }

    private func saveLessons() {
        do {
            try repository.saveLessons(lessons)
            lastError = nil
        } catch { lastError = error.localizedDescription }
    }

    func removeSourceRegistration(_ id: UUID) {
        guard var configuration else { return }
        configuration.sourceRegistrations.removeAll { $0.id == id }
        self.configuration = configuration
        saveConfiguration()
    }

    func removeOutputTemplate(_ id: UUID) {
        guard var configuration else { return }
        configuration.outputTemplates.removeAll { $0.id == id }
        self.configuration = configuration
        saveConfiguration()
    }

    func replaceOutputFolder(with url: URL) {
        guard var configuration else { return }
        configuration.outputFolderReference = FileReference(url: url)
        self.configuration = configuration
        saveConfiguration()
    }

    func registerWeeklyPlanTemplate(_ url: URL) {
        guard var configuration else { return }
        configuration.outputTemplates.append(OutputTemplateRegistration(
            id: UUID(), displayName: url.lastPathComponent, kind: .weeklyPlanHTML,
            reference: FileReference(url: url), preserveLayout: true, slotMappings: nil, addedAt: .now
        ))
        self.configuration = configuration
        saveConfiguration()
    }

    func registerPresentationTemplate(_ url: URL) {
        guard var configuration else { return }
        configuration.outputTemplates.append(OutputTemplateRegistration(
            id: UUID(), displayName: url.lastPathComponent, kind: .presentation,
            reference: FileReference(url: url), preserveLayout: true,
            slotMappings: TemplateSlotMapping.defaultPresentationMappings,
            addedAt: .now
        ))
        self.configuration = configuration
        saveConfiguration()
    }

    func inspectPresentationTemplateLayout(templateID: UUID) {
        guard let template = configuration?.outputTemplates.first(where: { $0.id == templateID && $0.kind == .presentation }) else { return }
        let url = URL(fileURLWithPath: template.reference.path)
        do {
            let result = try PowerPointTemplateInspector.inspect(url: url)
            updatePresentationTemplateLayoutPlan(
                templateID: templateID,
                slideInventory: result.slideInventory,
                frameMap: result.frameMap,
                fidelityReviewCompleted: false
            )
            // Best-effort enrichment: a template that fails placeholder resolution (no
            // discoverable layouts/masters) still has a usable slide inventory above, so
            // this degrades to an empty result rather than failing the whole inspection.
            lastPresentationTemplatePlaceholderResolution = (try? PowerPointTemplateInspector.resolvePlaceholders(url: url)) ?? []
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func updatePresentationTemplateLayoutPlan(
        templateID: UUID,
        slideInventory: [PresentationTemplateSlideInventoryItem],
        frameMap: [PresentationTemplateFrameMapEntry],
        fidelityReviewCompleted: Bool
    ) {
        guard var configuration,
              let index = configuration.outputTemplates.firstIndex(where: { $0.id == templateID && $0.kind == .presentation })
        else { return }
        configuration.outputTemplates[index].layoutPlan = PresentationTemplateLayoutPlan(
            slideInventory: slideInventory.sorted { $0.sourceSlideNumber < $1.sourceSlideNumber },
            frameMap: frameMap.sorted { $0.outputSlideNumber < $1.outputSlideNumber },
            fidelityReviewCompleted: fidelityReviewCompleted,
            updatedAt: .now
        )
        self.configuration = configuration
        saveConfiguration()
    }

    private func saveConfiguration() {
        guard var configuration else { return }
        configuration.updatedAt = .now
        self.configuration = configuration
        do {
            try repository.saveConfiguration(configuration)
            lastError = nil
        } catch { lastError = error.localizedDescription }
    }

    private func saveDailyPlan() {
        dailyPlan.updatedAt = .now
        do {
            try repository.saveDailyPlan(dailyPlan)
            lastError = nil
        } catch { lastError = error.localizedDescription }
    }

    private func saveWeeklyPlan() {
        weeklyPlan.updatedAt = .now
        do { try repository.saveWeeklyPlan(weeklyPlan); lastError = nil }
        catch { lastError = error.localizedDescription }
    }

    private func saveImportedSources() {
        do {
            try repository.saveImportedSources(importedSources)
            lastError = nil
        } catch { lastError = error.localizedDescription }
    }

    private func saveGeneratedOutputs() {
        do {
            try repository.saveGeneratedOutputs(generatedOutputs)
        } catch { lastError = error.localizedDescription }
    }

    private func outputDirectoryURL() -> URL? {
        guard let configuration else { return nil }
        if let output = configuration.outputFolderReference { return URL(fileURLWithPath: output.path) }
        return URL(fileURLWithPath: configuration.workspaceReference.path).appending(path: "LessonPlanner Outputs")
    }

    private static func startOfWeek(for date: Date) -> Date {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    private func recognizeText(in document: PDFDocument) throws -> (text: String, confidence: Double) {
        var recognizedPages: [String] = []
        var confidences: [VNConfidence] = []

        for index in 0..<document.pageCount {
            guard let page = document.page(at: index), let image = render(page: page) else { continue }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([request])
            let observations = request.results ?? []
            let lines = observations.compactMap { observation -> String? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                confidences.append(candidate.confidence)
                return candidate.string
            }
            if !lines.isEmpty { recognizedPages.append(lines.joined(separator: "\n")) }
        }

        guard !recognizedPages.isEmpty else { return ("", 0) }
        let confidence = confidences.isEmpty ? 0 : Double(confidences.reduce(0, +)) / Double(confidences.count)
        return (recognizedPages.joined(separator: "\n\n"), confidence)
    }

    private func extractDOCXText(from url: URL) throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path, "word/document.xml"]
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw PDFTextExtractionError.unreadableWordDocument
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let xml = String(data: data, encoding: .utf8) else {
            throw PDFTextExtractionError.unreadableWordDocument
        }

        let withParagraphBreaks = xml
            .replacingOccurrences(of: "</w:p>", with: "\n")
            .replacingOccurrences(of: "</w:tr>", with: "\n")
            .replacingOccurrences(of: "</w:tc>", with: "\t")
            .replacingOccurrences(of: "<w:tab/>", with: "\t")
            .replacingOccurrences(of: "<w:br/>", with: "\n")
        let withoutTags = withParagraphBreaks.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let decoded = withoutTags
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
        let lines = decoded
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else {
            throw PDFTextExtractionError.unreadableWordDocument
        }
        return lines.joined(separator: "\n")
    }

    private func render(page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let targetSize = NSSize(width: bounds.width * 2, height: bounds.height * 2)
        let image = NSImage(size: targetSize)
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        guard let context = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return nil
        }
        context.saveGState()
        context.scaleBy(x: 2, y: 2)
        page.draw(with: .mediaBox, to: context)
        context.restoreGState()
        image.unlockFocus()
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}

enum LessonFieldExtractor {
    struct Result {
        var subject: String?
        var gradeOrAgeRange: String?
        var objective: String?
        var materials: [String] = []
        var assessment: String?
        var differentiation: String?
        var steps: [String] = []
    }

    static func extract(from text: String) -> Result {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        func value(for labels: [String]) -> String? {
            for (index, line) in lines.enumerated() {
                let lower = line.lowercased()
                for label in labels where lower.hasPrefix(label) {
                    let remainder = line.dropFirst(label.count).trimmingCharacters(in: CharacterSet(charactersIn: ":- "))
                    if !remainder.isEmpty { return remainder }
                    if index + 1 < lines.count { return lines[index + 1] }
                }
            }
            return nil
        }
        let materialText = value(for: ["materials", "resources"])
        let stepText = value(for: ["procedure", "instructional sequence", "steps"])
        return Result(
            subject: value(for: ["subject"]),
            gradeOrAgeRange: value(for: ["grade", "age range"]),
            objective: value(for: ["learning objective", "objective", "goal"]),
            materials: materialText?.split(whereSeparator: { $0 == "," || $0 == ";" }).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } ?? [],
            assessment: value(for: ["assessment", "success check", "exit ticket"]),
            differentiation: value(for: ["differentiation", "supports", "accommodations"]),
            steps: stepText?.split(whereSeparator: { $0 == ";" || $0 == "•" }).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } ?? []
        )
    }
}

enum LessonDraftValidator {
    static func warnings(for proposal: LessonDraftProposal) -> [String] {
        var warnings = proposal.reviewWarnings ?? []
        if proposal.objective.isEmpty { warnings.append("No explicit learning objective was found.") }
        if proposal.instructionalSteps.isEmpty, proposal.sourceType?.lowercased() != "schedule" { warnings.append("No explicit instructional sequence was found.") }
        if proposal.sourceType?.lowercased() == "mixed" { warnings.append("This source mixes schedule and lesson content; verify each field before approval.") }
        return Array(Set(warnings.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })).sorted()
    }
}

enum CodexCLIError: LocalizedError, Sendable {
    case unavailable
    case failed(String)
    case invalidResponse
    case timedOut

    var errorDescription: String? {
        switch self {
        case .unavailable: "Codex CLI was not found. Install or sign in to Codex CLI before using this personal-workflow feature."
        case .failed(let message): "Codex CLI could not create a draft. \(message)"
        case .invalidResponse: "Codex CLI returned a response that did not match the lesson-draft format."
        case .timedOut: "Codex CLI did not finish within two minutes. The draft was not created. Try a shorter source excerpt or run it again."
        }
    }
}

enum CodexCLIAdapter {
    static func generateDraft(prompt: String) throws -> LessonDraftProposal {
        guard let executableURL = executableURL else { throw CodexCLIError.unavailable }
        let temporaryDirectory = FileManager.default.temporaryDirectory.appending(path: "LessonPlanner-Codex-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let schemaURL = temporaryDirectory.appending(path: "lesson-draft-schema.json")
        let outputURL = temporaryDirectory.appending(path: "lesson-draft.json")
        try schema.data(using: .utf8)?.write(to: schemaURL, options: .atomic)

        let process = Process()
        process.executableURL = executableURL
        process.currentDirectoryURL = temporaryDirectory
        process.arguments = ["exec", "--ephemeral", "--skip-git-repo-check", "--sandbox", "read-only", "--output-schema", schemaURL.path, "--output-last-message", outputURL.path, prompt]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        let deadline = Date().addingTimeInterval(120)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.25)
        }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
            throw CodexCLIError.timedOut
        }
        let errorText = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw CodexCLIError.failed(errorText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard let data = try? Data(contentsOf: outputURL), let proposal = try? JSONDecoder().decode(LessonDraftProposal.self, from: data) else {
            throw CodexCLIError.invalidResponse
        }
        return proposal
    }

    private static var executableURL: URL? {
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
        return candidates.map(URL.init(fileURLWithPath:)).first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static let schema = """
    {
      "type": "object",
      "additionalProperties": false,
      "required": ["title", "subject", "gradeOrAgeRange", "objective", "instructionalSteps", "materials", "differentiationSummary", "printableResourcePrompt", "assessmentSummary", "sourceType", "reviewWarnings"],
      "properties": {
        "title": {"type": "string"}, "subject": {"type": "string"}, "gradeOrAgeRange": {"type": "string"}, "objective": {"type": "string"},
        "instructionalSteps": {"type": "array", "items": {"type": "string"}}, "materials": {"type": "array", "items": {"type": "string"}},
        "differentiationSummary": {"type": "string"}, "printableResourcePrompt": {"type": "string"}, "assessmentSummary": {"type": "string"},
        "sourceType": {"type": "string", "enum": ["lesson", "schedule", "mixed", "reference", "unknown"]}, "reviewWarnings": {"type": "array", "items": {"type": "string"}}
      }
    }
    """
}
