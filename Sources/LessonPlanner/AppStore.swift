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
    /// Links from supporting materials to the lessons they serve. Kept separate from
    /// `importedSources` because one material can support several lessons.
    @Published private(set) var lessonMaterialAttachments: [LessonMaterialAttachment] = []
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
    /// True when a configuration file exists on disk but could not be decoded. Distinct from
    /// `configuration == nil` with no file, which is a genuine first run. Without this
    /// distinction an unreadable workspace renders the setup wizard, and completing that
    /// wizard overwrites the very file that failed to load — turning a recoverable read
    /// error into real data loss.
    @Published private(set) var configurationIsUnreadable = false
    /// Outcome of the most recent automatic placement pass. Silence was its own defect: an import
    /// once created 173 lesson records, placed 24, and reported neither number.
    @Published private(set) var lastAutoPlacementSummary: AutoPlacementSummary?

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

    var hasImportedScheduleScaffold: Bool {
        !importedDailyScheduleBlocks(from: importedSources).isEmpty
    }

    var importedScheduleScaffoldBlocks: [WeeklyScheduleScaffoldBlock] {
        importedDailyScheduleBlocks(from: importedSources).map {
            WeeklyScheduleScaffoldBlock(
                startHour: $0.startHour,
                startMinute: $0.startMinute,
                endHour: $0.endHour,
                endMinute: $0.endMinute,
                label: $0.label
            )
        }
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
            lessonMaterialAttachments = try repository.loadLessonMaterialAttachments()
            progressSnapshots = try repository.loadProgressSnapshots()
            configurationIsUnreadable = false
            lastError = nil
            if syncReadableDocuments {
                syncReadableDocumentsIntoWeeklyPlanner(rebuildExistingPacing: false)
            }
        } catch {
            // A saved workspace that exists but won't decode must never be mistaken for a
            // fresh install; the recovery screen keeps the teacher away from any action that
            // would overwrite it.
            configurationIsUnreadable = repository.hasStoredConfiguration()
            lastError = error.localizedDescription
        }
    }

    /// Re-attempts a failed load — the recovery screen's "Try again" action, for when the
    /// teacher has restored a backup or installed a build that understands the saved file.
    func retryLoadingWorkspace() {
        reload(syncReadableDocuments: false)
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
            generatedOutputs: generatedOutputs,
            lessonMaterialAttachments: lessonMaterialAttachments
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
        lessonMaterialAttachments = []
        lastPresentationTemplatePlaceholderResolution = []
        saveLessonMaterialAttachments()

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

    /// Persists a teacher's replacement pacing plan, transferring ownership to them.
    ///
    /// Named for intent for the same reason as `updateLessonFromTeacherEdit`: a plan's provenance
    /// decides whether `rebuildDerivedPlanningData()` may regenerate over it. This path currently
    /// has no callers, but leaving a generic writer that silently preserves `.autoDerived` would
    /// be the pacing equivalent of the boolean this batch removed.
    func updateCoursePacingPlanFromTeacherEdit(_ plan: CoursePacingPlan) {
        guard var configuration else {
            lastError = "Complete workspace setup before updating course pacing."
            return
        }
        var updatedPlan = plan
        updatedPlan.origin = .teacherAuthored
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
        // A teacher edit takes ownership: `starter` stamps `.autoDerived`, and an explicit origin
        // beats the legacy-notes fallback forever, so without this an edited plan would stay
        // rebuild-owned and a future rebuild would discard the teacher's dates and skipped days.
        plan.origin = .teacherAuthored
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
        // A teacher edit takes ownership: `starter` stamps `.autoDerived`, and an explicit origin
        // beats the legacy-notes fallback forever, so without this an edited plan would stay
        // rebuild-owned and a future rebuild would discard the teacher's dates and skipped days.
        plan.origin = .teacherAuthored
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
        // A teacher edit takes ownership: `starter` stamps `.autoDerived`, and an explicit origin
        // beats the legacy-notes fallback forever, so without this an edited plan would stay
        // rebuild-owned and a future rebuild would discard the teacher's dates and skipped days.
        plan.origin = .teacherAuthored
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
        // A teacher edit takes ownership: `starter` stamps `.autoDerived`, and an explicit origin
        // beats the legacy-notes fallback forever, so without this an edited plan would stay
        // rebuild-owned and a future rebuild would discard the teacher's dates and skipped days.
        plan.origin = .teacherAuthored
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
        // A teacher edit takes ownership: `starter` stamps `.autoDerived`, and an explicit origin
        // beats the legacy-notes fallback forever, so without this an edited plan would stay
        // rebuild-owned and a future rebuild would discard the teacher's dates and skipped days.
        plan.origin = .teacherAuthored
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
        // A teacher edit takes ownership: `starter` stamps `.autoDerived`, and an explicit origin
        // beats the legacy-notes fallback forever, so without this an edited plan would stay
        // rebuild-owned and a future rebuild would discard the teacher's dates and skipped days.
        plan.origin = .teacherAuthored
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
        // A teacher edit takes ownership: `starter` stamps `.autoDerived`, and an explicit origin
        // beats the legacy-notes fallback forever, so without this an edited plan would stay
        // rebuild-owned and a future rebuild would discard the teacher's dates and skipped days.
        plan.origin = .teacherAuthored
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
        // Without this the automatic re-placement guard still treats a hand-moved assignment as
        // its own and relocates it — the precise failure this provenance work exists to stop.
        weeklyPlan.assignments[index].origin = .teacherAuthored
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
        lesson.origin = .teacherAuthored
        lesson.objective = objective
        lessons.append(lesson)
        mostRecentLessonID = lesson.id
        saveLessons()
    }

    func createDraftLesson(from pacingSuggestion: WeeklyPacingSuggestion) {
        var lesson = LessonRecord.draft(title: pacingSuggestion.pacingLessonTitle)
        lesson.origin = .teacherAuthored
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
        importDocument(url, roleOverride: nil)
    }

    private func importDocument(_ url: URL, roleOverride: ImportedSourceRole?) {
        let fileExtension = url.pathExtension.lowercased()
        switch fileExtension {
        case "pdf":
            importPDF(url, roleOverride: roleOverride)
        case "docx":
            importDOCX(url, roleOverride: roleOverride)
        default:
            lastError = PDFTextExtractionError.unsupportedFileType.localizedDescription
        }
    }

    private func importPDF(_ url: URL, roleOverride: ImportedSourceRole?) {
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
        let classification = DocumentPlacementClassifier.classify(displayName: url.lastPathComponent, extractedText: extraction.text)
        let inferred = LessonFieldExtractor.extractWithStructuralInference(from: extraction.text)
        let source = ImportedSource(
            id: UUID(), reference: FileReference(url: url),
            setupRole: roleOverride ?? ImportedSourceRole.infer(displayName: url.lastPathComponent, extractedText: extraction.text),
            extractionMethod: extraction.method,
            confidence: extraction.confidence, extractedText: extraction.text,
            reviewStatus: extraction.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .imported : .reviewed,
            importedAt: .now, updatedAt: .now,
            placementEligibility: classification.eligibility,
            differentiationRole: classification.differentiationRole,
            lessonKey: classification.lessonKey,
            inferredSubject: inferred.subject
        )
        importedSources.insert(source, at: 0)
        saveImportedSources()
    }

    private func importDOCX(_ url: URL, roleOverride: ImportedSourceRole?) {
        do {
            let text = try extractDOCXText(from: url)
            let classification = DocumentPlacementClassifier.classify(displayName: url.lastPathComponent, extractedText: text)
            let inferred = LessonFieldExtractor.extractWithStructuralInference(from: text)
            let source = ImportedSource(
                id: UUID(), reference: FileReference(url: url),
                setupRole: roleOverride ?? ImportedSourceRole.infer(displayName: url.lastPathComponent, extractedText: text),
                extractionMethod: .embeddedText,
                confidence: nil, extractedText: text,
                reviewStatus: .reviewed, importedAt: .now, updatedAt: .now,
                placementEligibility: classification.eligibility,
                differentiationRole: classification.differentiationRole,
                lessonKey: classification.lessonKey,
                inferredSubject: inferred.subject
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

    func importPlanningDocumentItems(_ urls: [URL]) {
        importDocumentItems(urls, roleOverride: nil, shouldSyncPlanner: true)
    }

    func importContentDocumentItems(_ urls: [URL]) {
        guard hasImportedScheduleScaffold else {
            lastError = "Add a readable daily schedule before importing lesson content."
            return
        }
        importDocumentItems(urls, roleOverride: .lessonMaterial, shouldSyncPlanner: true)
    }

    func importDocumentItems(_ urls: [URL]) {
        importDocumentItems(urls, roleOverride: nil, shouldSyncPlanner: true)
    }

    private func importDocumentItems(_ urls: [URL], roleOverride: ImportedSourceRole?, shouldSyncPlanner: Bool) {
        for url in urls {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                importDocumentsInFolder(url, roleOverride: roleOverride, shouldSyncPlanner: false)
            } else {
                importDocument(url, roleOverride: roleOverride)
            }
        }
        if shouldSyncPlanner {
            syncReadableDocumentsIntoWeeklyPlanner(rebuildExistingPacing: true)
        }
    }

    func importDocumentsInFolder(_ folderURL: URL) {
        importDocumentsInFolder(folderURL, roleOverride: nil, shouldSyncPlanner: true)
    }

    private func importDocumentsInFolder(_ folderURL: URL, roleOverride: ImportedSourceRole?, shouldSyncPlanner: Bool) {
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
            importDocument(url, roleOverride: roleOverride)
        }
        if shouldSyncPlanner {
            syncReadableDocumentsIntoWeeklyPlanner(rebuildExistingPacing: true)
        }
    }

    func refreshWeeklyPlannerFromReadableDocuments() {
        syncReadableDocumentsIntoWeeklyPlanner(rebuildExistingPacing: false)
    }

    @discardableResult
    func buildWeeklyScheduleScaffoldFromPlanningDocuments() -> WeeklyScaffoldBuildResult {
        let blockCount = importedScheduleScaffoldBlocks.count
        guard blockCount > 0 else {
            lastError = WeeklyScaffoldBuildResult.noReadableSchedule.message
            return .noReadableSchedule
        }
        refreshWeeklyPlannerFromReadableDocuments()
        lastError = nil
        return .built(blockCount: blockCount)
    }

    /// Lessons an automatic rebuild must not delete, even though the app derived them.
    ///
    /// Artifact-level ownership is the rule, but referential integrity outranks provenance purity:
    /// a teacher-owned artifact keeps alive the record it depends on. Two protections, both
    /// evidence of teacher investment rather than app authorship:
    ///
    /// - a teacher-placed or teacher-moved assignment pointing at the lesson — deleting it would
    ///   create the dangling reference `WeeklyPackageReadinessReport` already reports as a missing
    ///   scheduled lesson;
    /// - any generated output pointing at the lesson, because the corresponding file already
    ///   exists in the teacher's output folder and is outside the snapshot safety net.
    #if DEBUG
    /// Test-only seams. `lessons` and `generatedOutputs` are `private(set)` so production code
    /// cannot bypass their save paths; these let a test construct a starting state directly.
    func replaceLessonsForTesting(_ newLessons: [LessonRecord]) { lessons = newLessons }
    func replaceGeneratedOutputsForTesting(_ outputs: [GeneratedOutputRecord]) { generatedOutputs = outputs }
    #endif

    private func rebuildProtectedLessonIDs() -> (assignmentLinked: Set<UUID>, outputLinked: Set<UUID>) {
        let assignmentLinked = Set(
            weeklyPlan.assignments
                .filter { $0.effectiveOrigin == .teacherAuthored }
                .map(\.lessonRecordID)
        )
        var outputLinked = Set(generatedOutputs.compactMap(\.lessonRecordID))
        // `ScheduleBlock` and `DailyTask` both persist an optional `linkedLessonRecordID`. Nothing
        // populates them today, but the model allows it, and a rebuild that ignored them would
        // leave dangling daily-plan references the moment anything does.
        outputLinked.formUnion(dailyPlan.scheduleBlocks.compactMap(\.linkedLessonRecordID))
        outputLinked.formUnion(dailyPlan.tasks.compactMap(\.linkedLessonRecordID))
        return (assignmentLinked, outputLinked)
    }

    /// Computes what `rebuildDerivedPlanningData()` would do, without changing anything.
    func previewDerivedRebuild() -> DerivedRebuildPreview {
        let plan = configuration?.coursePacingPlan
        let blocked = plan.map { $0.effectiveOrigin == .teacherAuthored } ?? false
        let protectedIDs = rebuildProtectedLessonIDs()

        var removable = 0
        var preservedTeacher = 0
        var preservedOutput = 0
        var preservedAssignment = 0
        for lesson in lessons {
            guard lesson.effectiveOrigin == .autoDerived else { preservedTeacher += 1; continue }
            if protectedIDs.outputLinked.contains(lesson.id) { preservedOutput += 1 }
            else if protectedIDs.assignmentLinked.contains(lesson.id) { preservedAssignment += 1 }
            else { removable += 1 }
        }

        // An automatic placement for a protected lesson is preserved too. The lesson is protected
        // because the teacher invested in it — generated materials, or scheduled it by hand — and
        // silently moving it to a different day still disrupts a real week.
        let protectedLessons = protectedIDs.outputLinked.union(protectedIDs.assignmentLinked)
        let removablePlacements = weeklyPlan.assignments.filter {
            $0.effectiveOrigin == .autoDerived && !protectedLessons.contains($0.lessonRecordID)
        }.count
        return DerivedRebuildPreview(
            removableLessons: removable,
            removablePlacements: removablePlacements,
            preservedTeacherLessons: preservedTeacher,
            preservedOutputLinkedLessons: preservedOutput,
            preservedAssignmentLinkedLessons: preservedAssignment,
            preservedTeacherPlacements: weeklyPlan.assignments.count - removablePlacements,
            pacingUnitsBefore: plan?.units.count ?? 0,
            pacingLessonsBefore: plan?.lessonCount ?? 0,
            isBlockedByTeacherAuthoredPacing: blocked
        )
    }

    /// Regenerates only the planning data the app owns, from documents already imported. No file
    /// access and no re-import: extracted text is already persisted.
    ///
    /// Exists because improving derivation logic otherwise never reaches an existing profile — a
    /// stored pacing plan short-circuits the rebuild path, so a teacher keeps seeing results
    /// produced by code that has since been fixed.
    ///
    /// Returns the preview describing what was done, or nil when the rebuild was refused.
    @discardableResult
    func rebuildDerivedPlanningData() -> DerivedRebuildPreview? {
        let preview = previewDerivedRebuild()
        guard !preview.isBlockedByTeacherAuthoredPacing else {
            lastError = "This course pacing plan includes your own edits, so it was not rebuilt. Clear or replace it first if you want to start from the imported documents again."
            return nil
        }

        // Revertible through the existing restore path. Note this covers app records only —
        // already-generated output files on disk are not captured, which is why lessons with
        // generated outputs are protected from deletion above rather than relying on this.
        saveCurrentProgressSnapshot(named: "Before rebuilding planning data")

        let protectedIDs = rebuildProtectedLessonIDs()
        lessons.removeAll { lesson in
            lesson.effectiveOrigin == .autoDerived
                && !protectedIDs.outputLinked.contains(lesson.id)
                && !protectedIDs.assignmentLinked.contains(lesson.id)
        }
        let protectedLessons = protectedIDs.outputLinked.union(protectedIDs.assignmentLinked)
        weeklyPlan.assignments.removeAll {
            $0.effectiveOrigin == .autoDerived && !protectedLessons.contains($0.lessonRecordID)
        }
        saveLessons()
        saveWeeklyPlan()

        syncReadableDocumentsIntoWeeklyPlanner(rebuildExistingPacing: true)
        lastError = nil
        return preview
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
            // Content folders commonly contain supporting pages alongside lesson material. Only
            // a lesson-shaped source or explicit lesson list may establish pacing; schedules and
            // supporting pages stay available without manufacturing lesson records.
            let lessonMaterialSources = readableSources.filter {
                $0.effectiveSetupRole == .lessonMaterial && $0.canContributeLessonSequence
            }
            let pacingSequenceSources = readableSources.filter { source in
                [.pacingGuide, .curriculumMap].contains(source.effectiveSetupRole)
                    && source.canContributeLessonSequence
            }
            let lessonPlanningSources = lessonMaterialSources.isEmpty ? pacingSequenceSources : lessonMaterialSources
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
        var occupiedAutoSlots = Set(weeklyPlan.assignments.map { autoScheduleSlotKey(date: $0.date, start: $0.start, end: $0.end) })
        var unplacedForMissingBlockMatch = 0
        for suggestion in secondPass.suggestions where suggestion.status == .readyToSchedule || suggestion.status == .alreadyScheduled {
            guard let lessonID = suggestion.lessonRecordID else { continue }
            guard !Self.isPlaceholderPacingTitle(suggestion.pacingLessonTitle) else { continue }
            // No confident block match against a real schedule means no placement, leaving every
            // other block an untouched placeholder. Counted so the teacher is told rather than
            // left to infer from silence.
            guard let preferredTimeRange = scheduledTimeRange(
                for: suggestion, on: suggestion.suggestedDate, scheduleBlocks: scheduleBlocks
            ) else {
                unplacedForMissingBlockMatch += 1
                continue
            }
            if let existingIndex = weeklyPlan.assignments.firstIndex(where: { $0.lessonRecordID == lessonID }) {
                // Provenance, not prose. An assignment the teacher created or moved is theirs and
                // must never be silently relocated by an automatic pass; `effectiveOrigin` still
                // recognises pre-provenance auto placements by their legacy note prefix.
                guard weeklyPlan.assignments[existingIndex].effectiveOrigin == .autoDerived else { continue }
                occupiedAutoSlots.remove(autoScheduleSlotKey(
                    date: weeklyPlan.assignments[existingIndex].date,
                    start: weeklyPlan.assignments[existingIndex].start,
                    end: weeklyPlan.assignments[existingIndex].end
                ))
                let placement = firstAvailableSchedulePlacement(
                    preferredDate: suggestion.suggestedDate,
                    preferredTimeRange: preferredTimeRange,
                    occupiedSlots: occupiedAutoSlots
                )
                weeklyPlan.assignments[existingIndex].date = placement.date
                weeklyPlan.assignments[existingIndex].start = placement.start
                weeklyPlan.assignments[existingIndex].end = placement.end
                weeklyPlan.assignments[existingIndex].planningNotes = suggestion.planningNote
                weeklyPlan.assignments[existingIndex].origin = .autoDerived
                occupiedAutoSlots.insert(autoScheduleSlotKey(date: placement.date, start: placement.start, end: placement.end))
                continue
            }
            let placement = firstAvailableSchedulePlacement(
                preferredDate: suggestion.suggestedDate,
                preferredTimeRange: preferredTimeRange,
                occupiedSlots: occupiedAutoSlots
            )
            weeklyPlan.assignments.append(WeeklyLessonAssignment(
                id: UUID(),
                lessonRecordID: lessonID,
                date: placement.date,
                start: placement.start,
                end: placement.end,
                planningNotes: suggestion.planningNote,
                origin: .autoDerived
            ))
            occupiedAutoSlots.insert(autoScheduleSlotKey(date: placement.date, start: placement.start, end: placement.end))
        }
        weeklyPlan.assignments.sort { $0.date == $1.date ? $0.start < $1.start : $0.date < $1.date }
        saveWeeklyPlan()
        lastAutoPlacementSummary = AutoPlacementSummary(
            placedCount: weeklyPlan.assignments.count,
            unplacedForMissingBlockMatch: unplacedForMissingBlockMatch
        )
    }

    private func ensureApprovedLesson(for suggestion: WeeklyPacingSuggestion) -> UUID {
        let normalizedSuggestionTitle = Self.normalizedLessonTitle(suggestion.pacingLessonTitle)
        if let existing = lessons.first(where: { Self.normalizedLessonTitle($0.title) == normalizedSuggestionTitle }) {
            if existing.status.isSchedulable {
                return existing.id
            }
            var updated = existing
            updated.status = .pendingReview
            // Automatic sync, not a teacher edit — must not promote this record's provenance.
            updateLessonFromAutomaticSync(updated)
            return updated.id
        }

        var lesson = LessonRecord.draft(title: suggestion.pacingLessonTitle)
        var populatedSteps = false
        if let source = sourceDocument(referencedIn: suggestion.sourceNotes) {
            lesson.subject = source.effectiveInferredSubject ?? ""
            // Without this the teacher cannot even fill the lesson in by hand: the "Fill empty
            // fields from labeled source text" action guards on this field being non-empty, so an
            // auto-created lesson was unreachable by both the automatic and the manual path.
            //
            // Scope the snapshot to this lesson's own slice when the document splits cleanly.
            // Still no auto-population of fields here — that is the next batch — but the manual
            // fill action now operates on one day rather than the whole week.
            if let span = resolvedSourceSpan(for: suggestion, in: source),
               let sliced = span.resolvedText(in: source.extractedText) {
                lesson.sourceSpan = span
                lesson.sourceTextSnapshot = sliced
                populatedSteps = Self.populateFields(
                    from: sliced, into: &lesson, allowStructuralInference: true
                )
            } else {
                // Honest degradation: no confident split means the teacher sees the whole document
                // and can judge it themselves, which is what happens for single-page sources.
                lesson.sourceTextSnapshot = source.extractedText
            }
        }
        lesson.sourceReferences = [suggestion.planningNote]
        // Not `.approved`. The approval was only ever a mechanism to make the scheduling pass find
        // this record; scheduling now keys on `isSchedulable`, so the status can tell the truth.
        lesson.status = .pendingReview
        lesson.origin = .autoDerived
        lesson.aiReviewWarnings = ["Auto-created from readable planning documents. Fill any blank or incorrect fields as needed."]
        if !populatedSteps {
            lesson.instructionalSequence = [
                InstructionalStep(
                    id: UUID(),
                    title: suggestion.pacingLessonTitle,
                    notes: "Auto-filled from course pacing. Add details if needed."
                )
            ]
        }
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

    /// Nil means "do not place this lesson."
    ///
    /// The defect behind the reported scatter was never that a 9:00 AM default exists — it is that
    /// the default *overrode a real teacher schedule*. When the teacher has imported schedule
    /// blocks, an unmatched lesson must be left unplaced so its block stays an untouched
    /// placeholder; inventing a 9:00 AM slot puts content at a time that does not exist in their
    /// day and lets collision-shifting spread it across the week. When no schedule has been
    /// imported at all there is nothing to contradict, so the default remains correct and is kept.
    private func scheduledTimeRange(
        for suggestion: WeeklyPacingSuggestion,
        on date: Date,
        scheduleBlocks: [ImportedDailyScheduleBlock]
    ) -> (start: Date, end: Date)? {
        if let block = bestScheduleBlock(for: suggestion, in: scheduleBlocks) {
            return (
                dateAt(hour: block.startHour, minute: block.startMinute, on: date),
                dateAt(hour: block.endHour, minute: block.endMinute, on: date)
            )
        }
        guard scheduleBlocks.isEmpty else { return nil }
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

    private func firstAvailableSchedulePlacement(
        preferredDate: Date,
        preferredTimeRange: (start: Date, end: Date),
        occupiedSlots: Set<String>
    ) -> (date: Date, start: Date, end: Date) {
        let calendar = Calendar.current
        let weekStart = Self.startOfWeek(for: preferredDate)
        let preferredDay = calendar.startOfDay(for: preferredDate)
        let weekdays = (0..<5).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
        let orderedDays = ([preferredDay] + weekdays).reduce(into: [Date]()) { result, day in
            let normalized = calendar.startOfDay(for: day)
            if !result.contains(where: { calendar.isDate($0, inSameDayAs: normalized) }) {
                result.append(normalized)
            }
        }
        let startComponents = calendar.dateComponents([.hour, .minute], from: preferredTimeRange.start)
        let endComponents = calendar.dateComponents([.hour, .minute], from: preferredTimeRange.end)

        for day in orderedDays {
            let start = dateAt(hour: startComponents.hour ?? 9, minute: startComponents.minute ?? 0, on: day)
            let end = dateAt(hour: endComponents.hour ?? 9, minute: endComponents.minute ?? 45, on: day)
            let key = autoScheduleSlotKey(date: day, start: start, end: end)
            if !occupiedSlots.contains(key) {
                return (day, start, end)
            }
        }

        return (preferredDate, preferredTimeRange.start, preferredTimeRange.end)
    }

    private func autoScheduleSlotKey(date: Date, start: Date, end: Date) -> String {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date).timeIntervalSinceReferenceDate
        let startMinutes = calendar.component(.hour, from: start) * 60 + calendar.component(.minute, from: start)
        let endMinutes = calendar.component(.hour, from: end) * 60 + calendar.component(.minute, from: end)
        return "\(Int(day))-\(startMinutes)-\(endMinutes)"
    }

    private func bestScheduleBlock(
        for suggestion: WeeklyPacingSuggestion,
        in blocks: [ImportedDailyScheduleBlock]
    ) -> ImportedDailyScheduleBlock? {
        let titleText = "\(suggestion.unitTitle) \(suggestion.moduleTitle) \(suggestion.pacingLessonTitle) \(suggestion.sourceNotes)".lowercased()
        if let match = Self.matchedScheduleBlock(forSubjectText: titleText, in: blocks) {
            return match
        }
        // Lesson titles are often terse ("Equivalent fractions", "Day 3") and carry no
        // recognizable subject keyword on their own. Fall back to the full extracted text
        // of the source document the lesson was proposed from, which usually does.
        if let source = sourceDocument(referencedIn: suggestion.sourceNotes) {
            if let subject = source.effectiveInferredSubject,
               let match = Self.matchedScheduleBlock(forSubjectText: subject.lowercased(), in: blocks) {
                return match
            }
            return Self.matchedScheduleBlock(forSubjectText: source.extractedText.lowercased(), in: blocks)
        }
        return nil
    }

    private func sourceDocumentText(referencedIn sourceNotes: String) -> String? {
        sourceDocument(referencedIn: sourceNotes)?.extractedText
    }

    /// The slice of `source` belonging to this suggestion, or nil when the document cannot be split
    /// confidently.
    ///
    /// **Fails closed on a cardinality mismatch.** If the number of detected spans does not equal
    /// the number of lessons the pacing plan derived from this same document, every lesson gets the
    /// whole document instead of a guess. A partial or misaligned split is worse than none: it
    /// silently hands one day another day's content, which the teacher has no way to detect.
    private func resolvedSourceSpan(
        for suggestion: WeeklyPacingSuggestion, in source: ImportedSource
    ) -> LessonSourceSpan? {
        let spans = LessonSourceSpanDetector.detect(in: source.extractedText)
        guard !spans.isEmpty else { return nil }

        let lessonsFromThisSource = (configuration?.coursePacingPlan?.units ?? [])
            .flatMap(\.modules)
            .flatMap(\.lessons)
            .filter { $0.sourceNotes == suggestion.sourceNotes }
        guard spans.count == lessonsFromThisSource.count else { return nil }

        guard var match = spans.first(where: {
            Self.normalizedLessonTitle($0.lessonTitle) == Self.normalizedLessonTitle(suggestion.pacingLessonTitle)
        }) else { return nil }
        match.sourceID = source.id
        match.sourceDisplayName = source.reference.displayName
        return match
    }

    private func sourceDocument(referencedIn sourceNotes: String) -> ImportedSource? {
        let prefix = "Proposed from "
        guard sourceNotes.hasPrefix(prefix) else { return nil }
        let displayName = String(sourceNotes.dropFirst(prefix.count))
        return importedSources.first { $0.reference.displayName == displayName }
    }

    private struct SubjectVocabulary {
        var candidates: [String]
        /// Matched as whole words only, so e.g. "art" cannot match inside "chart" or
        /// "partial", and "map" cannot match inside "concept map" for an unrelated subject.
        var wordKeywords: Set<String>
        /// Matched as raw substrings, for keywords that are themselves multi-word phrases
        /// (word-boundary tokenizing would never find "language arts" as one token).
        var phraseKeywords: [String]
    }

    /// Subject-keyword vocabulary used to match a lesson to its schedule block. Deliberately
    /// broader than just the subject's own name — real lesson titles and unit names describe
    /// a *topic* ("Equivalent fractions", "Ecosystems") far more often than they say "Math" or
    /// "Science" outright, so matching on subject name alone misses most realistic content.
    ///
    /// Excludes keywords that are common outside their "home" subject (e.g. "story", "color")
    /// — since the full source-document body is now searched (not just short titles), a
    /// generic keyword is likely to appear somewhere in content about a different subject too.
    private static let subjectVocabularies: [SubjectVocabulary] = [
        SubjectVocabulary(
            candidates: ["english", "ela", "language arts", "reading", "writing"],
            wordKeywords: ["english", "ela", "reading", "writing", "phonics", "vocabulary",
                           "comprehension", "grammar", "spelling", "literacy", "narrative"],
            phraseKeywords: ["language arts"]
        ),
        SubjectVocabulary(
            candidates: ["math"],
            wordKeywords: ["math", "fraction", "fractions", "decimal", "decimals",
                           "multiplication", "division", "addition", "subtraction", "geometry",
                           "algebra", "rounding", "equation", "equations", "measurement",
                           "arithmetic", "counting", "numerator", "denominator"],
            phraseKeywords: ["place value", "word problem", "number sense"]
        ),
        SubjectVocabulary(
            candidates: ["art", "specials"],
            wordKeywords: ["art", "sketchbook", "drawing", "painting", "sculpture", "specials"],
            phraseKeywords: []
        ),
        SubjectVocabulary(
            candidates: ["science"],
            wordKeywords: ["science", "experiment", "observation", "ecosystem", "matter", "energy", "lab"],
            phraseKeywords: []
        ),
        SubjectVocabulary(
            candidates: ["social studies"],
            wordKeywords: ["community", "history", "geography", "government", "culture"],
            phraseKeywords: ["social studies"]
        )
    ]

    /// Scores every subject by keyword-match count and returns the block for the strongest
    /// match, rather than the first category whose *any* keyword appears. A fixed check order
    /// is fragile once the full source-document body is searched: e.g. a math packet that
    /// happens to mention "read the problem" would wrongly win English under first-match-wins
    /// if English were checked first, even though the document is overwhelmingly about
    /// fractions and word problems. Scoring lets the stronger, more specific signal win.
    private static func matchedScheduleBlock(
        forSubjectText subjectText: String,
        in blocks: [ImportedDailyScheduleBlock]
    ) -> ImportedDailyScheduleBlock? {
        let words = Set(subjectText.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })

        var bestVocabulary: SubjectVocabulary?
        var bestScore = 0
        for vocabulary in subjectVocabularies {
            let wordScore = vocabulary.wordKeywords.intersection(words).count
            let phraseScore = vocabulary.phraseKeywords.filter { subjectText.contains($0) }.count
            let score = wordScore + phraseScore
            if score > bestScore {
                bestScore = score
                bestVocabulary = vocabulary
            }
        }
        guard let bestVocabulary else { return nil }
        return blocks.first { block in
            let label = block.label.lowercased()
            return bestVocabulary.candidates.contains { label.contains($0) }
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
        let timePattern = #"^(\d{1,2}):(\d{2})\s*(AM|PM|am|pm)?\s*[-–]\s*(\d{1,2}):(\d{2})\s*(AM|PM|am|pm)?$"#
        let regex = try? NSRegularExpression(pattern: timePattern)
        return lines.enumerated().compactMap { index, line in
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = regex?.firstMatch(in: line, range: range), match.numberOfRanges == 7 else { return nil }
            func stringValue(_ rangeIndex: Int) -> String {
                guard let range = Range(match.range(at: rangeIndex), in: line) else { return "" }
                return String(line[range])
            }
            func intValue(_ rangeIndex: Int) -> Int {
                Int(stringValue(rangeIndex)) ?? 0
            }
            func adjustedHour(_ hour: Int, marker: String) -> Int {
                switch marker.lowercased() {
                case "pm" where hour < 12: return hour + 12
                case "am" where hour == 12: return 0
                default: return hour
                }
            }
            let startMarker = stringValue(3)
            let endMarker = stringValue(6).isEmpty ? startMarker : stringValue(6)
            let label = index + 1 < lines.count ? lines[index + 1] : "Scheduled block"
            return ImportedDailyScheduleBlock(
                startHour: adjustedHour(intValue(1), marker: startMarker),
                startMinute: intValue(2),
                endHour: adjustedHour(intValue(4), marker: endMarker),
                endMinute: intValue(5),
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

    /// Creates a draft from a source, pre-filling every field the source text explicitly
    /// labels. Anything the teacher typed into the title/objective fields wins over an
    /// extracted value; anything the source doesn't explicitly label stays blank for the
    /// teacher to fill in. Before this ran the extractor, a draft created here arrived with
    /// only a title — the extractor existed but was reachable only from a separate button on
    /// the lesson-editor screen, which a teacher had no reason to know they needed to press.
    func createDraftLesson(from source: ImportedSource, title: String, objective: String) {
        let typedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let typedObjective = objective.trimmingCharacters(in: .whitespacesAndNewlines)
        var lesson = LessonRecord.draft(title: typedTitle.isEmpty ? source.reference.displayName : typedTitle)
        lesson.origin = .teacherAuthored
        lesson.objective = typedObjective
        lesson.sourceReferences = [source.reference.path]
        lesson.sourceTextSnapshot = source.extractedText

        let extracted = LessonFieldExtractor.extractWithStructuralInference(from: source.extractedText)
        if lesson.objective.isEmpty { lesson.objective = extracted.objective ?? "" }
        lesson.subject = extracted.subject ?? ""
        lesson.gradeOrAgeRange = extracted.gradeOrAgeRange ?? ""
        lesson.materials = extracted.materials
        lesson.assessmentSummary = extracted.assessment ?? ""
        lesson.differentiationSummary = extracted.differentiation ?? ""
        lesson.instructionalSequence = extracted.steps.map { InstructionalStep(id: UUID(), title: $0.title, notes: $0.notes) }
        lesson.aiReviewWarnings = LessonFieldExtractor.extractionWarnings(for: extracted)
        // Only for fields whose stored value actually came from extraction. A teacher who typed an
        // objective here overrode the extracted one, so marking it inferred would be a lie about
        // their own words.
        var markers = extracted.inferredFields
        if !typedObjective.isEmpty { markers.remove(.objective) }
        lesson.inferredFields = markers.isEmpty ? nil : markers

        lessons.append(lesson)
        mostRecentLessonID = lesson.id
        saveLessons()
    }

    func createDraftLesson(from proposal: LessonDraftProposal, source: ImportedSource) {
        let title = proposal.title.trimmingCharacters(in: .whitespacesAndNewlines)
        var lesson = LessonRecord.draft(title: title.isEmpty ? source.reference.displayName : title)
        lesson.origin = .teacherAuthored
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

    /// Persists a teacher's change and transfers ownership of the record to them.
    ///
    /// Provenance is no longer bookkeeping: `rebuildDerivedPlanningData()` deletes unprotected
    /// `.autoDerived` lessons, so whether a record is marked as the teacher's decides whether it
    /// can be destroyed. That is why this is a named method rather than a boolean argument — a
    /// defaulted parameter guarding deletion eligibility is too easy to get wrong at a call site.
    func updateLessonFromTeacherEdit(_ lesson: LessonRecord) {
        var updated = lesson
        updated.origin = .teacherAuthored
        // A field the teacher rewrote is theirs now, so its "worked out from structure" marker is
        // no longer true. Keyed on the value actually changing rather than on a view reporting an
        // edit, so edit paths added later are covered without having to remember this.
        //
        // Conservative by design in the other direction: a teacher who reads an inferred sequence,
        // agrees with it, and saves without touching it keeps the marker. A stale "inferred" is a
        // far cheaper error than a missing one.
        if let markers = updated.inferredFields, !markers.isEmpty,
           let stored = lessons.first(where: { $0.id == lesson.id }) {
            let unchanged = markers.filter {
                stored.contentFingerprint(for: $0) == updated.contentFingerprint(for: $0)
            }
            updated.inferredFields = unchanged.isEmpty ? nil : unchanged
        }
        writeLesson(updated)
    }

    /// Persists a change made by automatic derivation, **preserving** the record's existing
    /// ownership.
    ///
    /// Contract: this neither promotes to `.teacherAuthored` nor stamps `.autoDerived`. A lesson
    /// the teacher already owns stays theirs even when an automatic pass touches it — approving it
    /// during a sync, for instance, must not quietly make it eligible for deletion, and must not
    /// quietly claim it either.
    func updateLessonFromAutomaticSync(_ lesson: LessonRecord) {
        writeLesson(lesson)
    }

    /// Fills a lesson's content fields from that lesson's own slice of its source document.
    ///
    /// **Strategy is split by field, not uniform.** Measured over the 25 lessons in the owner's
    /// sample packet: label-only extraction fills objective, materials, assessment, and
    /// differentiation at 25/25, and finds instructional steps at 0/25 — that corpus names its
    /// phases "Warm-Up"/"Mini-Lesson"/"Guided Practice" rather than "Procedure", which only
    /// `LessonStructureInferencer` recognizes (it scores 25/25 there). So inference is used for
    /// steps alone; on the four labelled fields it would add judgment risk for no measured gain.
    ///
    /// Only empty fields are written, so a teacher edit always survives a re-run.
    ///
    /// Returns true when instructional steps were populated, so the caller can skip seeding the
    /// placeholder step that would otherwise make this lesson look non-empty forever.
    /// - Parameter allowStructuralInference: whether phase headings may supply instructional
    ///   steps. False for the lesson editor's manual button, whose tooltip promises explicit
    ///   labels only — both paths share this helper so their field rules cannot drift, but that
    ///   sharing must not quietly break the promise the button makes to the teacher.
    ///
    /// Internal rather than private so tests can exercise both modes directly.
    @discardableResult
    static func populateFields(
        from spanText: String, into lesson: inout LessonRecord, allowStructuralInference: Bool
    ) -> Bool {
        // A field a teacher wiped to spaces reads as filled under a raw `.isEmpty` test, which
        // would then block population forever. Same blank semantics as `LessonExportReadinessReport`.
        func blank(_ value: String) -> Bool {
            value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let labeled = LessonFieldExtractor.extract(from: spanText)

        if blank(lesson.subject) { lesson.subject = labeled.subject ?? lesson.subject }
        if blank(lesson.gradeOrAgeRange) { lesson.gradeOrAgeRange = labeled.gradeOrAgeRange ?? lesson.gradeOrAgeRange }
        if blank(lesson.objective) { lesson.objective = labeled.objective ?? lesson.objective }
        if lesson.materials.allSatisfy(blank) { lesson.materials = labeled.materials }
        if blank(lesson.assessmentSummary) { lesson.assessmentSummary = labeled.assessment ?? lesson.assessmentSummary }
        if blank(lesson.differentiationSummary) {
            lesson.differentiationSummary = labeled.differentiation ?? lesson.differentiationSummary
        }

        let sequenceIsBlank = lesson.instructionalSequence
            .allSatisfy { blank($0.title) && blank($0.notes) }
        guard sequenceIsBlank else { return false }
        var steps = labeled.steps
        var inferred: Set<LessonFieldExtractor.Field> = []
        if steps.isEmpty, allowStructuralInference {
            // Take `.steps` and nothing else. `fillingGaps` can also infer an objective, subject,
            // grade, and assessment; those are deliberately discarded here, because the labeled
            // pass above already covers them and an inferred value there would be a guess rather
            // than a reading of document structure.
            let structural = LessonStructureInferencer.fillingGaps(in: labeled, from: spanText)
            if structural.inferredFields.contains(.steps), !structural.steps.isEmpty {
                steps = structural.steps
                inferred.insert(.steps)
            }
        }
        guard !steps.isEmpty else { return false }
        lesson.instructionalSequence = steps.map {
            InstructionalStep(id: UUID(), title: $0.title, notes: $0.notes)
        }
        // Union rather than assign: a later inferred fill must not erase a marker set earlier.
        if !inferred.isEmpty {
            lesson.inferredFields = (lesson.inferredFields ?? []).union(inferred)
        }
        return true
    }

    private func writeLesson(_ lesson: LessonRecord) {
        guard let index = lessons.firstIndex(where: { $0.id == lesson.id }) else { return }
        var updated = lesson
        updated.updatedAt = .now
        lessons[index] = updated
        saveLessons()
    }

    func fillEmptyLessonFieldsFromSource(_ lesson: LessonRecord) -> LessonRecord {
        guard let sourceText = currentSourceText(for: lesson), !sourceText.isEmpty else {
            lastError = "This lesson has no readable source text available."
            return lesson
        }
        var updated = lesson
        // Same helper the automatic path uses, so the two cannot drift apart — but label-only,
        // because this button's tooltip promises exactly that.
        Self.populateFields(from: sourceText, into: &updated, allowStructuralInference: false)
        updateLessonFromTeacherEdit(updated)
        return updated
    }

    /// This lesson's own slice of its source document.
    ///
    /// Re-resolved against the document's *current* text whenever the source is still imported,
    /// because the stored snapshot was taken at placement time; the span carries its heading as
    /// durable identity precisely so a re-import that shifts offsets still lands on the right day.
    /// Falls back to the snapshot when the source is gone.
    private func currentSourceText(for lesson: LessonRecord) -> String? {
        if let span = lesson.sourceSpan,
           let sourceID = span.sourceID,
           let source = importedSources.first(where: { $0.id == sourceID }),
           let resolved = span.resolvedText(in: source.extractedText) {
            return resolved
        }
        return lesson.sourceTextSnapshot
    }

    func generateLessonPlanHTML(for lesson: LessonRecord) -> GeneratedOutputRecord? {
        guard lesson.status.allowsOutputGeneration else {
            lastError = "Review and approve this lesson before generating outputs. Lessons created automatically from your documents start unreviewed."
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
        guard lesson.status.allowsOutputGeneration else {
            lastError = "Review and approve this lesson before generating outputs. Lessons created automatically from your documents start unreviewed."
            return nil
        }
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
        guard lesson.status.allowsOutputGeneration else {
            lastError = "Review and approve this lesson before generating outputs. Lessons created automatically from your documents start unreviewed."
            return nil
        }
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
            // Re-inspecting (e.g. after the template file changed) must not silently discard
            // a teacher's prior placeholder-to-field choices: carry forward the lessonField
            // for any (sourceSlideNumber, shapeID) pair that still exists in the fresh result.
            let previousAssignments = template.layoutPlan?.placeholderAssignments ?? []
            let mergedAssignments = result.placeholderAssignments.map { assignment -> PresentationTemplatePlaceholderAssignment in
                var merged = assignment
                if let previous = previousAssignments.first(where: {
                    $0.sourceSlideNumber == assignment.sourceSlideNumber && $0.shapeID == assignment.shapeID
                }) {
                    merged.lessonField = previous.lessonField
                }
                return merged
            }
            updatePresentationTemplateLayoutPlan(
                templateID: templateID,
                slideInventory: result.slideInventory,
                frameMap: result.frameMap,
                placeholderAssignments: mergedAssignments,
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
        placeholderAssignments: [PresentationTemplatePlaceholderAssignment],
        fidelityReviewCompleted: Bool
    ) {
        guard var configuration,
              let index = configuration.outputTemplates.firstIndex(where: { $0.id == templateID && $0.kind == .presentation })
        else { return }
        configuration.outputTemplates[index].layoutPlan = PresentationTemplateLayoutPlan(
            slideInventory: slideInventory.sorted { $0.sourceSlideNumber < $1.sourceSlideNumber },
            frameMap: frameMap.sorted { $0.outputSlideNumber < $1.outputSlideNumber },
            placeholderAssignments: placeholderAssignments.sorted {
                $0.sourceSlideNumber == $1.sourceSlideNumber
                    ? $0.shapeID < $1.shapeID
                    : $0.sourceSlideNumber < $1.sourceSlideNumber
            },
            fidelityReviewCompleted: fidelityReviewCompleted,
            updatedAt: .now
        )
        self.configuration = configuration
        saveConfiguration()
    }

    /// Assigns (or clears, via `nil`) a lesson field on one resolved template placeholder.
    /// Any change invalidates a prior fidelity-QA confirmation, since that confirmation
    /// reflects a specific mapping state that no longer holds once it's edited.
    func assignPlaceholder(templateID: UUID, assignmentID: UUID, lessonField: LessonTemplateField?) {
        guard var configuration,
              let templateIndex = configuration.outputTemplates.firstIndex(where: { $0.id == templateID && $0.kind == .presentation }),
              var layoutPlan = configuration.outputTemplates[templateIndex].layoutPlan,
              let assignmentIndex = layoutPlan.placeholderAssignments.firstIndex(where: { $0.id == assignmentID })
        else { return }
        layoutPlan.placeholderAssignments[assignmentIndex].lessonField = lessonField
        layoutPlan.fidelityReviewCompleted = false
        layoutPlan.updatedAt = .now
        configuration.outputTemplates[templateIndex].layoutPlan = layoutPlan
        self.configuration = configuration
        saveConfiguration()
    }

    /// The one real, user-completable path to `fidelityReviewCompleted = true`: succeeds
    /// only once every required lesson field (title, objective, instructional sequence,
    /// assessment) has a placeholder assigned to it. Otherwise reports exactly which fields
    /// are still unassigned via `lastError`, rather than silently doing nothing.
    func confirmPresentationTemplateFrameMap(templateID: UUID) {
        guard var configuration,
              let templateIndex = configuration.outputTemplates.firstIndex(where: { $0.id == templateID && $0.kind == .presentation }),
              var layoutPlan = configuration.outputTemplates[templateIndex].layoutPlan
        else { return }

        let requiredFields = Set(TemplateSlotMapping.defaultPresentationMappings.filter(\.required).map(\.lessonField))
        let assignedFields = Set(layoutPlan.placeholderAssignments.compactMap(\.lessonField))
        let missingFields = requiredFields.subtracting(assignedFields)
        guard missingFields.isEmpty else {
            let names = missingFields.map(\.displayName).sorted().joined(separator: ", ")
            lastError = "Assign a template placeholder to every required lesson field before confirming the frame map: \(names)."
            return
        }

        layoutPlan.fidelityReviewCompleted = true
        layoutPlan.updatedAt = .now
        configuration.outputTemplates[templateIndex].layoutPlan = layoutPlan
        self.configuration = configuration
        saveConfiguration()
        lastError = nil
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

    private func saveLessonMaterialAttachments() {
        do {
            try repository.saveLessonMaterialAttachments(lessonMaterialAttachments)
            lastError = nil
        } catch { lastError = error.localizedDescription }
    }

    /// Attaches supporting material to the lesson it belongs to, using the module/lesson identifier
    /// already parsed at import.
    ///
    /// Only auto-derived attachments are recomputed; a teacher's own attachment is left alone, and
    /// material whose identifier does not resolve is deliberately **left unattached** rather than
    /// guessed onto a lesson. Measured coverage on a real import is 45%, so guessing would
    /// mis-attach at scale — and the wrong reteach sheet on the wrong lesson is worse for a teacher
    /// than an unattached one they can place in a click.
    @discardableResult
    func refreshAutomaticMaterialAttachments() -> Int {
        let teacherAttachments = lessonMaterialAttachments.filter { $0.effectiveOrigin == .teacherAuthored }
        let alreadyOwned = Set(teacherAttachments.map { AttachmentKey(lessonID: $0.lessonRecordID, sourceID: $0.importedSourceID) })

        // Index lessons by the pacing identifier their titles were derived from.
        var lessonsByKey: [DocumentLessonKey: [UUID]] = [:]
        for lesson in lessons {
            guard let key = DocumentPlacementClassifier.lessonKey(displayName: lesson.title, extractedText: "") else { continue }
            lessonsByKey[key, default: []].append(lesson.id)
        }

        var automatic: [LessonMaterialAttachment] = []
        for source in importedSources {
            guard source.effectivePlacementEligibility == .supportingMaterial,
                  let key = source.effectiveLessonKey,
                  let candidates = lessonsByKey[key],
                  candidates.count == 1,
                  let lessonID = candidates.first
            else { continue }
            let attachmentKey = AttachmentKey(lessonID: lessonID, sourceID: source.id)
            guard !alreadyOwned.contains(attachmentKey) else { continue }
            automatic.append(LessonMaterialAttachment(
                id: UUID(),
                lessonRecordID: lessonID,
                importedSourceID: source.id,
                role: source.differentiationRole ?? .other,
                pageRanges: nil,
                pageLabel: nil,
                origin: .autoDerived,
                attachedAt: .now
            ))
        }

        lessonMaterialAttachments = teacherAttachments + automatic
        saveLessonMaterialAttachments()
        return automatic.count
    }

    private struct AttachmentKey: Hashable {
        var lessonID: UUID
        var sourceID: UUID
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

/// Deterministic, label-only source-text extraction — deliberately does not infer or invent
/// content. A field is only ever filled when the source text has an explicit heading for it
/// ("Objective:", "Materials:", etc.); everything else is left nil/empty for the teacher to
/// fill in themselves. See the "Fill empty fields from labeled source text" button's own
/// tooltip in WorkspaceView, which states this constraint directly to the teacher.
enum LessonFieldExtractor {
    /// One instructional step. `notes` is populated when a step was recognized as a document
    /// section with body text under it (see `LessonStructureInferencer`); a step parsed from a
    /// plain labeled list is title-only.
    struct ExtractedStep: Equatable {
        var title: String
        var notes: String = ""
    }

    enum Field: String, CaseIterable, Codable {
        case subject, gradeOrAgeRange, objective, materials, assessment, differentiation, steps
    }

    struct Result: Equatable {
        var subject: String?
        var gradeOrAgeRange: String?
        var objective: String?
        var materials: [String] = []
        var assessment: String?
        var differentiation: String?
        var steps: [ExtractedStep] = []
        /// Fields filled by structural inference rather than an explicit label in the source.
        /// Empty for `extract(from:)`, which never infers.
        var inferredFields: Set<Field> = []
    }

    private static let subjectLabels = ["subject", "content area"]
    private static let gradeLabels = ["grade level", "grade", "age range"]
    private static let objectiveLabels = ["learning objective", "lesson objective", "learning goal", "objective", "goal"]
    private static let materialsLabels = ["materials", "resources", "supplies", "what you'll need", "you will need"]
    private static let assessmentLabels = ["formative assessment", "check for understanding", "success check", "exit ticket", "assessment"]
    private static let differentiationLabels = ["differentiated support", "differentiation", "accommodations", "scaffolds", "extensions", "supports"]
    private static let stepsLabels = ["instructional sequence", "instructional plan", "lesson sequence", "procedure", "activities", "steps"]

    /// Rows this extractor does not turn into a field, but which must still *end* the previous
    /// field's value. In a "Component / Plan" table these sit directly under a value with no
    /// blank line and no phase heading between, so without them an assessment runs on and
    /// absorbs the timing row verbatim. Terminators only — nothing reads them.
    private static let terminatorOnlyLabels = [
        "timing", "duration", "pacing", "standards", "standard", "topic", "homework", "reflection"
    ]

    private static var allLabels: [String] {
        subjectLabels + gradeLabels + objectiveLabels + materialsLabels + assessmentLabels
            + differentiationLabels + stepsLabels + terminatorOnlyLabels
    }

    static func extract(from text: String) -> Result {
        // Blank lines are kept (not filtered) — they're the natural end-of-value boundary
        // for a multi-line value under a heading, alongside the start of another label.
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        return Result(
            subject: scalarValue(for: subjectLabels, in: lines),
            gradeOrAgeRange: scalarValue(for: gradeLabels, in: lines),
            objective: scalarValue(for: objectiveLabels, in: lines),
            materials: listValue(for: materialsLabels, in: lines),
            assessment: scalarValue(for: assessmentLabels, in: lines),
            differentiation: scalarValue(for: differentiationLabels, in: lines),
            steps: listValue(for: stepsLabels, in: lines, stopAtPhaseHeadings: false)
                .map { ExtractedStep(title: $0) }
        )
    }

    /// Label-based extraction first, then `LessonStructureInferencer` for whatever the labels
    /// didn't cover — for real curriculum documents that carry structure through phase
    /// headings and standards codes instead of "Objective:"-style labels. Inferred values are
    /// flagged in `Result.inferredFields`. Callers that must not infer (the lesson editor's
    /// "Fill empty fields from labeled source text" button, which promises exactly that in its
    /// tooltip) should keep using `extract(from:)` instead.
    static func extractWithStructuralInference(from text: String) -> Result {
        LessonStructureInferencer.fillingGaps(in: extract(from: text), from: text)
    }

    /// The value for a prose field: the same line's remainder if the label has one, otherwise
    /// every following line up to a blank line or the next recognized label, joined into one
    /// paragraph — so an objective spanning 2-3 lines under its own heading is captured whole
    /// instead of only its first line.
    private static func scalarValue(for labels: [String], in lines: [String]) -> String? {
        guard let (index, remainder) = firstLabelMatch(labels, in: lines) else { return nil }
        if !remainder.isEmpty { return remainder }
        let continuation = continuationLines(after: index, in: lines)
        guard !continuation.isEmpty else { return nil }
        return continuation.joined(separator: " ")
    }

    /// The value for a list field. A single dense line (same-line remainder, or exactly one
    /// continuation line) is split on commas/semicolons, matching a "Materials: strips;
    /// pencils" style list. Multiple continuation lines are each treated as one item instead
    /// (bullet markers stripped, not further comma-split) — the natural shape of a bulleted
    /// or numbered list under a heading, where an individual item can itself contain a comma
    /// ("chart paper, any color").
    private static func listValue(
        for labels: [String], in lines: [String], stopAtPhaseHeadings: Bool = true
    ) -> [String] {
        guard let (index, remainder) = firstLabelMatch(labels, in: lines) else { return [] }
        if !remainder.isEmpty { return splitDenseList(remainder) }
        let continuation = continuationLines(
            after: index, in: lines, stopAtPhaseHeadings: stopAtPhaseHeadings
        )
        if continuation.count == 1 { return splitDenseList(continuation[0]) }
        return continuation.map(stripBulletMarker).filter { !$0.isEmpty }
    }

    private static func splitDenseList(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Finds the first line starting with one of `labels`, matched as a whole label rather
    /// than a substring — "goal" must not match a line starting "Goals for this unit," only
    /// "Goal:" / "Goal -" / "Goal " / a line that is exactly "Goal". Returns the line's index
    /// and whatever follows the label and its separator (":", "-", or whitespace).
    private static func firstLabelMatch(_ labels: [String], in lines: [String]) -> (index: Int, remainder: String)? {
        for (index, rawLine) in lines.enumerated() {
            let decorated = stripLeadingDecoration(rawLine)
            guard !decorated.isEmpty else { continue }
            let lower = decorated.lowercased()
            for label in labels {
                guard lower.hasPrefix(label) else { continue }
                let afterLabel = decorated.index(decorated.startIndex, offsetBy: label.count)
                let boundary = decorated[afterLabel...]
                // The label must end here — at a separator or end of line — so "goal" doesn't
                // match a line starting "Goals for this unit". "*" counts as a separator to
                // allow a bolded heading's closing emphasis ("**Grade Level:** 5").
                let isBoundary = boundary.isEmpty
                    || boundary.first == ":" || boundary.first == "-" || boundary.first == "*"
                    || boundary.first?.isWhitespace == true
                guard isBoundary else { continue }
                let remainder = boundary.trimmingCharacters(in: CharacterSet(charactersIn: ":-* \t"))
                return (index, remainder)
            }
        }
        return nil
    }

    /// Lines immediately after `index` up to (not including) a blank line or the next
    /// recognized label — the natural extent of a value that continues past its heading line.
    /// - Parameter stopAtPhaseHeadings: whether an instructional phase heading ends the value.
    ///   True for every field except the instructional-sequence list, whose *items* are
    ///   legitimately phase names — stopping there would truncate that list to its first entry.
    private static func continuationLines(
        after index: Int, in lines: [String], stopAtPhaseHeadings: Bool = true
    ) -> [String] {
        var collected: [String] = []
        var cursor = index + 1
        while cursor < lines.count {
            let line = lines[cursor]
            if line.isEmpty { break }
            if firstLabelMatch(allLabels, in: [line]) != nil { break }
            if stopAtPhaseHeadings, LessonStructureInferencer.isPhaseHeading(line) { break }
            collected.append(line)
            cursor += 1
        }
        return collected
    }

    /// Strips a leading bullet ("-", "*", "•") or numbered/lettered marker ("1.", "1)", "a)")
    /// from one list-item line, leaving the item's actual text.
    private static func stripBulletMarker(_ line: String) -> String {
        var result = line
        while let first = result.first, "-*•".contains(first) {
            result.removeFirst()
        }
        result = result.trimmingCharacters(in: .whitespaces)
        if let range = result.range(of: #"^\w[\.\)]\s+"#, options: .regularExpression) {
            result.removeSubrange(range)
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Strips leading markdown heading/emphasis marks ("#", "##", "**") so "## Materials" or
    /// "**Materials:**" still matches the plain "materials" label.
    private static func stripLeadingDecoration(_ line: String) -> String {
        var result = line
        while let first = result.first, first == "#" || first == "*" {
            result.removeFirst()
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Tells the teacher two different things they need to know about a generated draft:
    /// which fields were *inferred* from document structure and therefore need checking, and
    /// which came up empty so they know the app found nothing rather than silently dropping
    /// content. Without this, an inferred objective is indistinguishable from one the document
    /// stated outright — the difference matters when the guess is wrong.
    static func extractionWarnings(for result: Result) -> [String]? {
        var warnings: [String] = []

        // Inference is no longer reported here. `LessonRecord.inferredFields` carries it as
        // structured state, and the lesson editor renders it from that — saying it twice, once
        // as prose and once as a banner, reads as two separate problems rather than one fact.
        // Missing fields stay: nothing else records those.
        var missing: [String] = []
        if result.objective == nil { missing.append("learning objective") }
        if result.steps.isEmpty { missing.append("instructional sequence") }
        if result.materials.isEmpty { missing.append("materials") }
        if result.assessment == nil { missing.append("assessment") }
        if result.differentiation == nil { missing.append("differentiation notes") }
        if !missing.isEmpty {
            warnings.append(
                "No \(missing.joined(separator: ", ")) could be found in the source text. These were left blank rather than guessed."
            )
        }

        return warnings.isEmpty ? nil : warnings
    }

    private static func displayName(_ field: Field) -> String {
        switch field {
        case .subject: "subject"
        case .gradeOrAgeRange: "grade"
        case .objective: "learning objective"
        case .materials: "materials"
        case .assessment: "assessment"
        case .differentiation: "differentiation notes"
        case .steps: "instructional sequence"
        }
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
