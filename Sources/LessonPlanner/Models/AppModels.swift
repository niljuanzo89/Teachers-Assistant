import Foundation

enum SourceKind: String, Codable, CaseIterable, Identifiable {
    case curriculum, pacing, calendar, schedule, template, other
    var id: String { rawValue }
}

enum ImportedSourceRole: String, Codable, CaseIterable, Identifiable {
    case pacingGuide
    case curriculumMap
    case instructionalCalendar
    case assessmentSchedule
    case lessonMaterial
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pacingGuide: "Pacing guide"
        case .curriculumMap: "Curriculum map"
        case .instructionalCalendar: "Instructional calendar"
        case .assessmentSchedule: "Assessment schedule"
        case .lessonMaterial: "Lesson material"
        case .other: "Other setup document"
        }
    }

    var supportsCoursePacing: Bool {
        switch self {
        case .pacingGuide, .curriculumMap, .instructionalCalendar, .assessmentSchedule: true
        case .lessonMaterial, .other: false
        }
    }

    var intakeCategory: ImportedSourceIntakeCategory {
        switch self {
        case .pacingGuide, .curriculumMap, .instructionalCalendar, .assessmentSchedule:
            .planning
        case .lessonMaterial:
            .content
        case .other:
            .other
        }
    }

    static func infer(displayName: String, extractedText: String) -> ImportedSourceRole {
        let combined = "\(displayName) \(extractedText.prefix(2_000))".lowercased()

        if containsAny(["pacing guide", "scope and sequence", "scope & sequence", "year at a glance", "unit sequence", "instructional days"], in: combined) {
            return .pacingGuide
        }
        if containsAny(["curriculum map", "standards map", "course map", "essential standards", "priority standards"], in: combined) {
            return .curriculumMap
        }
        if containsAny(["daily schedule", "sample daily schedule", "class schedule", "instructional schedule", "school calendar", "instructional calendar", "district calendar", "holiday", "break", "no school", "early release"], in: combined) {
            return .instructionalCalendar
        }
        if containsAny(["assessment calendar", "assessment schedule", "benchmark", "unit test", "interim assessment", "quiz schedule"], in: combined) {
            return .assessmentSchedule
        }
        if containsAny(["lesson", "worksheet", "student handout", "teacher guide", "activity", "practice"], in: combined) {
            return .lessonMaterial
        }
        return .other
    }

    private static func containsAny(_ needles: [String], in haystack: String) -> Bool {
        needles.contains { haystack.contains($0) }
    }
}

enum ImportedSourceIntakeCategory: String, Codable, CaseIterable, Identifiable {
    case planning
    case content
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .planning: "Planning"
        case .content: "Content"
        case .other: "Other"
        }
    }
}

enum TemplateKind: String, Codable, CaseIterable, Identifiable {
    case weeklyPlanHTML, detailedLessonPlan, presentation, differentiationGuide
    var id: String { rawValue }
}

enum SlideDeckExporterPreference: String, Codable, CaseIterable, Identifiable {
    case nativeOpenXML
    case personalBridge

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nativeOpenXML: "Native PowerPoint exporter"
        case .personalBridge: "Personal PowerPoint bridge"
        }
    }

    var detail: String {
        switch self {
        case .nativeOpenXML:
            "Built into the app. This is the sellable-version path and does not depend on a local development runtime."
        case .personalBridge:
            "Uses this Mac's local development presentation runtime. Useful for personal QA while the native exporter matures."
        }
    }
}

enum WeeklyPlanningPromptDay: Int, Codable, CaseIterable, Identifiable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .sunday: "Sunday"
        case .monday: "Monday"
        case .tuesday: "Tuesday"
        case .wednesday: "Wednesday"
        case .thursday: "Thursday"
        case .friday: "Friday"
        case .saturday: "Saturday"
        }
    }
}

struct WeeklyPlanningPromptPreference: Codable, Equatable {
    var isEnabled: Bool
    var day: WeeklyPlanningPromptDay
    var hour: Int
    var minute: Int

    static let `default` = WeeklyPlanningPromptPreference(isEnabled: true, day: .friday, hour: 15, minute: 30)

    var timeLabel: String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let date = Calendar.current.date(from: components) ?? Date(timeIntervalSince1970: 0)
        return date.formatted(date: .omitted, time: .shortened)
    }

    var summary: String {
        isEnabled ? "\(day.displayName) at \(timeLabel)" : "Weekly planning prompt off"
    }

    func nextPromptDate(after date: Date, calendar: Calendar = .current) -> Date? {
        guard isEnabled else { return nil }
        let startOfToday = calendar.startOfDay(for: date)
        for offset in 0...7 {
            guard let candidateDay = calendar.date(byAdding: .day, value: offset, to: startOfToday),
                  calendar.component(.weekday, from: candidateDay) == day.rawValue
            else { continue }
            var components = calendar.dateComponents([.year, .month, .day], from: candidateDay)
            components.hour = hour
            components.minute = minute
            components.second = 0
            guard let candidate = calendar.date(from: components), candidate > date else { continue }
            return candidate
        }
        return nil
    }

    func mostRecentPromptDate(onOrBefore date: Date, calendar: Calendar = .current) -> Date? {
        guard isEnabled else { return nil }
        let startOfToday = calendar.startOfDay(for: date)
        for offset in 0...7 {
            guard let candidateDay = calendar.date(byAdding: .day, value: -offset, to: startOfToday),
                  calendar.component(.weekday, from: candidateDay) == day.rawValue
            else { continue }
            var components = calendar.dateComponents([.year, .month, .day], from: candidateDay)
            components.hour = hour
            components.minute = minute
            components.second = 0
            guard let candidate = calendar.date(from: components), candidate <= date else { continue }
            return candidate
        }
        return nil
    }
}

struct WeeklyPlanningPromptStatus: Equatable {
    var preference: WeeklyPlanningPromptPreference
    var duePromptDate: Date?
    var nextPromptDate: Date?
    var lastHandledAt: Date?

    var isDue: Bool { duePromptDate != nil }

    static func evaluate(
        preference: WeeklyPlanningPromptPreference,
        lastHandledAt: Date?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> WeeklyPlanningPromptStatus {
        let recentPromptDate = preference.mostRecentPromptDate(onOrBefore: now, calendar: calendar)
        let duePromptDate: Date?
        if let recentPromptDate, lastHandledAt.map({ $0 >= recentPromptDate }) != true {
            duePromptDate = recentPromptDate
        } else {
            duePromptDate = nil
        }
        return WeeklyPlanningPromptStatus(
            preference: preference,
            duePromptDate: duePromptDate,
            nextPromptDate: preference.nextPromptDate(after: now, calendar: calendar),
            lastHandledAt: lastHandledAt
        )
    }
}

struct WeeklyScheduleScaffoldBlock: Equatable, Identifiable {
    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int
    var label: String

    var id: String {
        "\(startHour)-\(startMinute)-\(endHour)-\(endMinute)-\(label)"
    }

    var timeLabel: String {
        let start = Self.formattedTime(hour: startHour, minute: startMinute)
        let end = Self.formattedTime(hour: endHour, minute: endMinute)
        return "\(start)\n\(end)"
    }

    private static func formattedTime(hour: Int, minute: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let date = Calendar.current.date(from: components) ?? Date(timeIntervalSinceReferenceDate: 0)
        return date.formatted(.dateTime.hour().minute())
    }
}

enum WeeklyScaffoldBuildResult: Equatable {
    case built(blockCount: Int)
    case noReadableSchedule

    var message: String {
        switch self {
        case .built(let blockCount):
            "\(blockCount) daily schedule block(s) are ready. Add content files to fill them with lessons."
        case .noReadableSchedule:
            "No readable daily schedule blocks were found yet. Add a daily schedule under Planning."
        }
    }
}

struct TeacherProfile: Codable, Equatable, Identifiable {
    let id: UUID
    var displayName: String
    var role: String
    var gradeOrSubject: String
    var isLocalTestingProfile: Bool
    var createdAt: Date
    var updatedAt: Date

    static func localTestProfile(displayName: String, role: String = "Teacher", gradeOrSubject: String = "") -> TeacherProfile {
        TeacherProfile(
            id: UUID(),
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Local Test Teacher" : displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            role: role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Teacher" : role.trimmingCharacters(in: .whitespacesAndNewlines),
            gradeOrSubject: gradeOrSubject.trimmingCharacters(in: .whitespacesAndNewlines),
            isLocalTestingProfile: true,
            createdAt: .now,
            updatedAt: .now
        )
    }
}

enum LessonTemplateField: String, Codable, CaseIterable, Identifiable {
    case title
    case subject
    case gradeOrAgeRange
    case objective
    case instructionalSequence
    case materials
    case differentiationSummary
    case printableResourcePrompt
    case assessmentSummary

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .title: "Title"
        case .subject: "Subject"
        case .gradeOrAgeRange: "Grade"
        case .objective: "Objective"
        case .instructionalSequence: "Instructional sequence"
        case .materials: "Materials"
        case .differentiationSummary: "Differentiation"
        case .printableResourcePrompt: "Student practice"
        case .assessmentSummary: "Assessment"
        }
    }
}

struct TemplateSlotMapping: Codable, Equatable, Identifiable {
    let id: UUID
    var slotName: String
    var lessonField: LessonTemplateField
    var required: Bool

    static let defaultPresentationMappings: [TemplateSlotMapping] = [
        TemplateSlotMapping(id: UUID(), slotName: "lesson.title", lessonField: .title, required: true),
        TemplateSlotMapping(id: UUID(), slotName: "lesson.objective", lessonField: .objective, required: true),
        TemplateSlotMapping(id: UUID(), slotName: "lesson.steps", lessonField: .instructionalSequence, required: true),
        TemplateSlotMapping(id: UUID(), slotName: "lesson.materials", lessonField: .materials, required: false),
        TemplateSlotMapping(id: UUID(), slotName: "lesson.differentiation", lessonField: .differentiationSummary, required: false),
        TemplateSlotMapping(id: UUID(), slotName: "lesson.practice", lessonField: .printableResourcePrompt, required: false),
        TemplateSlotMapping(id: UUID(), slotName: "lesson.assessment", lessonField: .assessmentSummary, required: true)
    ]
}

struct PresentationTemplateSlideInventoryItem: Codable, Equatable, Identifiable {
    let id: UUID
    var sourceSlideNumber: Int
    var reusableRole: String
    var placeholderCount: Int
    var notes: String
}

struct PresentationTemplateFrameMapEntry: Codable, Equatable, Identifiable {
    let id: UUID
    var outputSlideNumber: Int
    var sourceSlideNumber: Int
    var narrativeRole: String
    var mappedSlotNames: [String]
    var notes: String
}

/// One resolved placeholder shape (from `PowerPointTemplateInspector.resolvePlaceholders`)
/// addressed structurally by `shapeID`, so layout-preserving export can locate exactly
/// which shape to write content into without re-deriving placeholder geometry. Distinct
/// from `PresentationTemplateFrameMapEntry.mappedSlotNames`, which is a heuristic guess at
/// the slide's narrative role — this is the real, ECMA-376-accurate placeholder identity.
struct PresentationTemplatePlaceholderAssignment: Codable, Equatable, Identifiable {
    let id: UUID
    var sourceSlideNumber: Int
    var shapeID: Int
    var shapeName: String?
    var effectiveType: String
    var effectiveIdx: Int
    var lessonField: LessonTemplateField?
}

struct PresentationTemplateLayoutPlan: Codable, Equatable {
    var slideInventory: [PresentationTemplateSlideInventoryItem]
    var frameMap: [PresentationTemplateFrameMapEntry]
    var placeholderAssignments: [PresentationTemplatePlaceholderAssignment]
    var fidelityReviewCompleted: Bool
    var updatedAt: Date

    /// `placeholderAssignments` was added after this app had already written layout plans to
    /// disk. Swift's synthesized decoder treats a missing key as a hard failure, so without
    /// this every previously-saved workspace became unreadable and the app fell back to the
    /// setup wizard as though the teacher's data had been erased. Any field added to a
    /// persisted model from here on needs the same treatment — see `decodeIfPresent` below.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        slideInventory = try container.decode([PresentationTemplateSlideInventoryItem].self, forKey: .slideInventory)
        frameMap = try container.decode([PresentationTemplateFrameMapEntry].self, forKey: .frameMap)
        placeholderAssignments = try container.decodeIfPresent(
            [PresentationTemplatePlaceholderAssignment].self, forKey: .placeholderAssignments
        ) ?? []
        fidelityReviewCompleted = try container.decode(Bool.self, forKey: .fidelityReviewCompleted)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    init(
        slideInventory: [PresentationTemplateSlideInventoryItem],
        frameMap: [PresentationTemplateFrameMapEntry],
        placeholderAssignments: [PresentationTemplatePlaceholderAssignment],
        fidelityReviewCompleted: Bool,
        updatedAt: Date
    ) {
        self.slideInventory = slideInventory
        self.frameMap = frameMap
        self.placeholderAssignments = placeholderAssignments
        self.fidelityReviewCompleted = fidelityReviewCompleted
        self.updatedAt = updatedAt
    }
}

struct FileReference: Codable, Equatable, Identifiable {
    let id: UUID
    var displayName: String
    var path: String
    var bookmarkData: Data?

    init(url: URL) {
        id = UUID()
        displayName = url.lastPathComponent
        path = url.path
        bookmarkData = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    }
}

struct SourceRegistration: Codable, Equatable, Identifiable {
    let id: UUID
    var displayName: String
    var kind: SourceKind
    var reference: FileReference
    var notes: String
    var addedAt: Date
}

struct OutputTemplateRegistration: Codable, Equatable, Identifiable {
    let id: UUID
    var displayName: String
    var kind: TemplateKind
    var reference: FileReference
    var preserveLayout: Bool
    var slotMappings: [TemplateSlotMapping]?
    var layoutPlan: PresentationTemplateLayoutPlan?
    var addedAt: Date
}

enum CoursePacingReviewStatus: String, Codable, CaseIterable, Identifiable {
    case draft
    case approved

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .draft: "Draft pacing"
        case .approved: "Approved pacing"
        }
    }
}

struct CoursePacingLesson: Codable, Equatable, Identifiable {
    let id: UUID
    var sequence: Int
    var title: String
    var startDate: Date? = nil
    var endDate: Date? = nil
    var estimatedInstructionalDays: Int
    var dependencyNotes: String
    var sourceNotes: String
}

struct CoursePacingModule: Codable, Equatable, Identifiable {
    let id: UUID
    var sequence: Int
    var title: String
    var startDate: Date? = nil
    var endDate: Date? = nil
    var estimatedInstructionalDays: Int
    var lessons: [CoursePacingLesson]
    var notes: String
}

struct CoursePacingUnit: Codable, Equatable, Identifiable {
    let id: UUID
    var sequence: Int
    var title: String
    var startDate: Date?
    var endDate: Date?
    var estimatedInstructionalDays: Int
    var modules: [CoursePacingModule]
    var assessmentWindows: [String]
    var skippedDays: [Date]
    var notes: String
}

/// Who owns a persisted artifact: the teacher, or the app's automatic derivation from imported
/// documents. This exists so a rebuild can prove what it is allowed to regenerate.
///
/// Before this, the app identified its own work by matching English sentences — an auto-created
/// lesson by a phrase in `aiReviewWarnings`, an auto-built pacing plan by a phrase in
/// `teacherRefinementNotes`, and an automatic placement by `planningNotes.hasPrefix("Pacing:")`.
/// Those heuristics are retained only as a fallback for records written before this field existed
/// (see each type's `effectiveOrigin`); nothing new should depend on them.
enum RecordOrigin: String, Codable, Equatable {
    /// Created or subsequently edited by the teacher. Never regenerated or discarded by a rebuild.
    case teacherAuthored
    /// Produced by automatic derivation from imported documents. Safe to regenerate.
    case autoDerived
}

struct CoursePacingPlan: Codable, Equatable, Identifiable {
    let id: UUID
    var sourceReferenceNames: [String]
    var units: [CoursePacingUnit]
    var teacherRefinementNotes: String
    var reviewStatus: CoursePacingReviewStatus
    var createdAt: Date
    var updatedAt: Date
    /// Optional so plans saved before this field existed still decode; `effectiveOrigin` classifies
    /// those from the legacy note text.
    var origin: RecordOrigin? = nil

    /// Falls back to the pre-provenance marker so an existing auto-built plan is still recognised
    /// as regenerable. A plan with neither the field nor the marker is treated as the teacher's.
    var effectiveOrigin: RecordOrigin {
        if let origin { return origin }
        return teacherRefinementNotes.contains(Self.legacyAutoBuiltMarker) ? .autoDerived : .teacherAuthored
    }

    static let legacyAutoBuiltMarker = "Auto-built from readable document intake"

    var unitCount: Int { units.count }
    var moduleCount: Int { units.flatMap(\.modules).count }
    var lessonCount: Int { units.flatMap(\.modules).flatMap(\.lessons).count }

    var estimatedInstructionalDays: Int {
        units.reduce(0) { total, unit in
            let moduleTotal = unit.modules.reduce(0) { moduleSum, module in
                let lessonTotal = module.lessons.reduce(0) { $0 + max(0, $1.estimatedInstructionalDays) }
                return moduleSum + max(module.estimatedInstructionalDays, lessonTotal)
            }
            return total + max(unit.estimatedInstructionalDays, moduleTotal)
        }
    }

    static func starter(from sources: [ImportedSource]) -> CoursePacingPlan {
        let reviewedSources = sources.filter { !$0.extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var units: [CoursePacingUnit] = []

        for source in reviewedSources {
            let lines = source.extractedText
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let unitTitle = firstHeading(in: lines, prefixes: ["unit", "module"]) ?? source.reference.displayName
            let lessonTitles = lessonTitleCandidates(in: lines)
            // A readable page is not automatically a lesson. Creating a placeholder for every
            // page without a real title was the upstream fragment factory. Skip both the lesson
            // and its otherwise-empty unit/module, since neither gives a teacher useful work.
            guard !lessonTitles.isEmpty else { continue }
            let lessons = lessonTitles.enumerated().map { index, title in
                CoursePacingLesson(
                    id: UUID(),
                    sequence: index + 1,
                    title: title,
                    estimatedInstructionalDays: 1,
                    dependencyNotes: "",
                    sourceNotes: "Proposed from \(source.reference.displayName)"
                )
            }
            let module = CoursePacingModule(
                id: UUID(),
                sequence: 1,
                title: firstHeading(in: lines, prefixes: ["module"]) ?? "Module 1",
                estimatedInstructionalDays: max(lessons.count, 1),
                lessons: lessons,
                notes: ""
            )
            units.append(CoursePacingUnit(
                id: UUID(),
                sequence: units.count + 1,
                title: unitTitle,
                startDate: nil,
                endDate: nil,
                estimatedInstructionalDays: max(lessons.count, 1),
                modules: [module],
                assessmentWindows: headingCandidates(in: lines, prefixes: ["assessment", "quiz", "test"]),
                skippedDays: [],
                notes: "Review dates, instructional-day count, skipped days, and dependencies before approval."
            ))
        }

        let contributingSourceNames = Set<String>(units.flatMap(\.modules).flatMap(\.lessons).compactMap { lesson in
            let prefix = "Proposed from "
            guard lesson.sourceNotes.hasPrefix(prefix) else { return nil }
            return String(lesson.sourceNotes.dropFirst(prefix.count))
        })
        return CoursePacingPlan(
            id: UUID(),
            sourceReferenceNames: reviewedSources.map(\.reference.displayName).filter(contributingSourceNames.contains),
            units: units,
            teacherRefinementNotes: "",
            reviewStatus: .draft,
            createdAt: .now,
            updatedAt: .now,
            origin: .autoDerived
        )
    }

    private static func firstHeading(in lines: [String], prefixes: [String]) -> String? {
        headingCandidates(in: lines, prefixes: prefixes).first
    }

    private static func lessonTitleCandidates(in lines: [String]) -> [String] {
        let genericLabels = Set([
            "lesson focus", "lesson materials", "day", "session", "component", "plan",
            "student objective", "quick check", "subject / day"
        ])
        let weekdayNames = Set(["monday", "tuesday", "wednesday", "thursday", "friday"])
        var candidates = headingCandidates(in: lines, prefixes: ["lesson", "day", "session"]).filter {
            !genericLabels.contains($0.lowercased())
        }

        for (index, line) in lines.enumerated() {
            let lowercased = line.lowercased()
            if let colonIndex = line.firstIndex(of: ":") {
                let prefix = String(line[..<colonIndex]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let title = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if weekdayNames.contains(prefix), !title.isEmpty {
                    candidates.append(title)
                }
            } else if weekdayNames.contains(lowercased), index + 1 < lines.count {
                let nextLine = lines[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
                if !nextLine.isEmpty, !genericLabels.contains(nextLine.lowercased()) {
                    candidates.append(nextLine)
                }
            }
        }

        var seen: Set<String> = []
        return candidates.compactMap { title in
            let normalized = title
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            guard !normalized.isEmpty, !seen.contains(normalized) else { return nil }
            seen.insert(normalized)
            return title.count > 120 ? String(title.prefix(120)) : title
        }
    }

    private static func headingCandidates(in lines: [String], prefixes: [String]) -> [String] {
        lines.compactMap { line in
            let lowercased = line.lowercased()
            guard let prefix = prefixes.first(where: { lowercased.hasPrefix($0) }) else { return nil }
            let afterPrefix = lowercased.dropFirst(prefix.count)
            // "Day, can ..." and "Days ..." are ordinary worksheet prose, not lesson
            // headings. A heading label must end or be followed by whitespace, a number, or a
            // conventional separator before it may contribute a lesson title.
            guard afterPrefix.isEmpty
                || afterPrefix.first?.isWhitespace == true
                || afterPrefix.first?.isNumber == true
                || afterPrefix.first == ":"
                || afterPrefix.first == "-"
            else { return nil }
            return line.count > 120 ? String(line.prefix(120)) : line
        }
    }
}

enum CoursePacingReadinessIssue: String, Equatable, Identifiable {
    case noPacingPlan
    case draftNeedsApproval
    case noUnits
    case noLessons
    case missingTiming

    var id: String { rawValue }

    var isBlocking: Bool {
        switch self {
        case .noPacingPlan, .draftNeedsApproval, .noUnits, .noLessons: true
        case .missingTiming: false
        }
    }

    var title: String {
        switch self {
        case .noPacingPlan: "Create course pacing"
        case .draftNeedsApproval: "Approve pacing before it governs planning"
        case .noUnits: "Add units"
        case .noLessons: "Add lesson sequence"
        case .missingTiming: "Refine dates and timing"
        }
    }

    var instruction: String {
        switch self {
        case .noPacingPlan:
            "Import and review setup documents, then create a starter pacing plan."
        case .draftNeedsApproval:
            "The teacher should review unit, module, lesson, and timing assumptions before approval."
        case .noUnits:
            "The pacing model needs at least one unit."
        case .noLessons:
            "At least one module should include lesson-level pacing."
        case .missingTiming:
            "Add date ranges, skipped days, assessment windows, or refinement notes so weekly planning has useful governing timing."
        }
    }
}

struct CoursePacingReadinessReport: Equatable {
    var issues: [CoursePacingReadinessIssue]
    var unitCount: Int
    var moduleCount: Int
    var lessonCount: Int
    var estimatedInstructionalDays: Int

    var blockingIssues: [CoursePacingReadinessIssue] { issues.filter(\.isBlocking) }
    var advisoryIssues: [CoursePacingReadinessIssue] { issues.filter { !$0.isBlocking } }
    var canGovernWeeklyPlanning: Bool { blockingIssues.isEmpty }

    var title: String {
        canGovernWeeklyPlanning ? "Pacing can guide weekly planning" : "Finish course pacing setup"
    }

    static func analyze(_ plan: CoursePacingPlan?) -> CoursePacingReadinessReport {
        guard let plan else {
            return CoursePacingReadinessReport(issues: [.noPacingPlan], unitCount: 0, moduleCount: 0, lessonCount: 0, estimatedInstructionalDays: 0)
        }
        var issues: [CoursePacingReadinessIssue] = []
        if plan.reviewStatus != .approved { issues.append(.draftNeedsApproval) }
        if plan.units.isEmpty { issues.append(.noUnits) }
        if plan.lessonCount == 0 { issues.append(.noLessons) }
        let hasDatedUnit = plan.units.contains { $0.startDate != nil || $0.endDate != nil }
        let hasAssessmentWindow = plan.units.contains { !$0.assessmentWindows.isEmpty }
        let hasRefinementNotes = !plan.teacherRefinementNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !hasDatedUnit && !hasAssessmentWindow && !hasRefinementNotes {
            issues.append(.missingTiming)
        }
        return CoursePacingReadinessReport(
            issues: issues,
            unitCount: plan.unitCount,
            moduleCount: plan.moduleCount,
            lessonCount: plan.lessonCount,
            estimatedInstructionalDays: plan.estimatedInstructionalDays
        )
    }
}

enum WeeklyPacingSuggestionStatus: String, Equatable {
    case readyToSchedule
    case alreadyScheduled
    case needsApprovedLesson

    var displayName: String {
        switch self {
        case .readyToSchedule: "Ready to schedule"
        case .alreadyScheduled: "Already scheduled"
        case .needsApprovedLesson: "Needs matching approved lesson"
        }
    }
}

struct WeeklyPacingSuggestion: Equatable, Identifiable {
    var id: String
    var unitTitle: String
    var moduleTitle: String
    var pacingLessonTitle: String
    var sourceNotes: String = ""
    var suggestedDate: Date
    var estimatedInstructionalDay: Int
    var estimatedInstructionalDays: Int
    var lessonRecordID: UUID?
    var lessonRecordTitle: String?
    var status: WeeklyPacingSuggestionStatus

    var planningNote: String {
        "Pacing: \(unitTitle) / \(moduleTitle) / \(pacingLessonTitle)"
    }
}

struct WeeklyPacingSuggestionReport: Equatable {
    var title: String
    var detail: String
    var suggestions: [WeeklyPacingSuggestion]
    var canSuggestFromPacing: Bool

    static func analyze(
        weeklyPlan: WeeklyPlan,
        pacingPlan: CoursePacingPlan?,
        lessons: [LessonRecord],
        calendar: Calendar = .current
    ) -> WeeklyPacingSuggestionReport {
        guard let pacingPlan else {
            return WeeklyPacingSuggestionReport(
                title: "Course pacing not set up",
                detail: "Create and approve course pacing before weekly suggestions are available.",
                suggestions: [],
                canSuggestFromPacing: false
            )
        }
        guard pacingPlan.reviewStatus == .approved else {
            return WeeklyPacingSuggestionReport(
                title: "Course pacing needs approval",
                detail: "Review and approve the pacing model before it guides weekly planning.",
                suggestions: [],
                canSuggestFromPacing: false
            )
        }

        // Scheduling eligibility, not approval. A pending-review lesson still belongs on the week;
        // whether it may generate outputs is a separate question answered at generation time.
        let approvedLessons = lessons.filter(\.status.isSchedulable)
        let scheduledLessonIDs = Set(weeklyPlan.assignments.map(\.lessonRecordID))
        let weekInterval = DateInterval(start: weeklyPlan.weekOf, end: calendar.date(byAdding: .day, value: 7, to: weeklyPlan.weekOf) ?? weeklyPlan.weekOf.addingTimeInterval(604_800))
        let flattened = flatten(pacingPlan: pacingPlan, calendar: calendar)
        let suggestions = flattened.compactMap { item -> WeeklyPacingSuggestion? in
            let undatedDayOffset = min(max(item.lesson.sequence - 1, 0), 4)
            let suggestedDate = item.suggestedDate ?? calendar.date(byAdding: .day, value: undatedDayOffset, to: weeklyPlan.weekOf) ?? weeklyPlan.weekOf
            if item.suggestedDate != nil && !weekInterval.contains(suggestedDate) {
                return nil
            }
            let matchedLesson = approvedLessons.first { lesson in
                let lessonTitle = normalized(lesson.title)
                let pacingTitle = normalized(item.lesson.title)
                guard !lessonTitle.isEmpty, !pacingTitle.isEmpty else { return false }
                return lessonTitle.contains(pacingTitle) || pacingTitle.contains(lessonTitle)
            }
            let status: WeeklyPacingSuggestionStatus
            if let matchedLesson, scheduledLessonIDs.contains(matchedLesson.id) {
                status = .alreadyScheduled
            } else if matchedLesson != nil {
                status = .readyToSchedule
            } else {
                status = .needsApprovedLesson
            }
            return WeeklyPacingSuggestion(
                id: "\(item.unit.id.uuidString)-\(item.module.id.uuidString)-\(item.lesson.id.uuidString)",
                unitTitle: item.unit.title,
                moduleTitle: item.module.title,
                pacingLessonTitle: item.lesson.title,
                sourceNotes: item.lesson.sourceNotes,
                suggestedDate: suggestedDate,
                estimatedInstructionalDay: item.overallSequence,
                estimatedInstructionalDays: item.lesson.estimatedInstructionalDays,
                lessonRecordID: matchedLesson?.id,
                lessonRecordTitle: matchedLesson?.title,
                status: status
            )
        }

        let title = suggestions.isEmpty ? "No pacing suggestions for this week" : "\(suggestions.count) pacing suggestions"
        let detail = suggestions.isEmpty
            ? "Approved pacing exists, but no dated or next unscheduled pacing lessons were found for this week."
            : "Suggestions come from the approved pacing model and can be placed on the weekly schedule automatically."
        return WeeklyPacingSuggestionReport(title: title, detail: detail, suggestions: suggestions, canSuggestFromPacing: true)
    }

    private struct FlattenedPacingLesson {
        var unit: CoursePacingUnit
        var module: CoursePacingModule
        var lesson: CoursePacingLesson
        var overallSequence: Int
        var suggestedDate: Date?
    }

    private static func flatten(pacingPlan: CoursePacingPlan, calendar: Calendar) -> [FlattenedPacingLesson] {
        var sequence = 0
        var result: [FlattenedPacingLesson] = []
        for unit in pacingPlan.units.sorted(by: { $0.sequence < $1.sequence }) {
            var unitDayOffset = 0
            for module in unit.modules.sorted(by: { $0.sequence < $1.sequence }) {
                var moduleDayOffset = 0
                for lesson in module.lessons.sorted(by: { $0.sequence < $1.sequence }) {
                    sequence += 1
                    let suggestedDate = lesson.startDate
                        ?? module.startDate.flatMap { calendar.date(byAdding: .day, value: moduleDayOffset, to: calendar.startOfDay(for: $0)) }
                        ?? unit.startDate.flatMap { calendar.date(byAdding: .day, value: unitDayOffset, to: calendar.startOfDay(for: $0)) }
                    result.append(FlattenedPacingLesson(unit: unit, module: module, lesson: lesson, overallSequence: sequence, suggestedDate: suggestedDate))
                    let lessonDays = max(1, lesson.estimatedInstructionalDays)
                    unitDayOffset += lessonDays
                    moduleDayOffset += lessonDays
                }
            }
        }
        return result
    }

    private static func normalized(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && $0 != "lesson" }
            .joined(separator: " ")
    }
}

struct AppConfiguration: Codable, Equatable {
    var schemaVersion: Int = 1
    var workspaceName: String
    var workspaceReference: FileReference
    var outputFolderReference: FileReference?
    var sourceRegistrations: [SourceRegistration] = []
    var outputTemplates: [OutputTemplateRegistration] = []
    var slideDeckExporter: SlideDeckExporterPreference?
    var weeklyPlanningPrompt: WeeklyPlanningPromptPreference?
    var weeklyPlanningPromptLastHandledAt: Date?
    var coursePacingPlan: CoursePacingPlan?
    var createdAt: Date = .now
    var updatedAt: Date = .now
}

struct PlanningProgressSnapshot: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var savedAt: Date
    var configuration: AppConfiguration?
    var dailyPlan: DailyPlan
    var weeklyPlan: WeeklyPlan
    var lessons: [LessonRecord]
    var importedSources: [ImportedSource]
    var generatedOutputs: [GeneratedOutputRecord]
    /// Optional so snapshots taken before attachments existed still decode; a restore from one of
    /// those simply leaves attachments untouched rather than clearing them.
    var lessonMaterialAttachments: [LessonMaterialAttachment]? = nil

    var displayName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "Saved progress" : trimmedName
    }
}

enum LessonStatus: String, Codable, CaseIterable {
    /// Derived automatically from pacing and source intake: eligible to occupy a slot on the week,
    /// but its content has not been reviewed by a teacher and it cannot generate outputs.
    ///
    /// Auto-created lessons were previously stamped `.approved` so the scheduling pass would find
    /// them — the approval was a mechanism, not a judgement, and it meant an unreviewed shell could
    /// generate a lesson plan, deck, and differentiation guide. Deliberately *not* called "placed":
    /// the record is created before placement is attempted and placement can still fail when no
    /// schedule block matches, so that name would assert something not yet true.
    case pendingReview
    case draft, reviewed, approved, generated

    /// Whether a lesson in this state may occupy a slot on the weekly planner. Broader than
    /// approval on purpose: this is "where does it sit", not "is it good".
    var isSchedulable: Bool { self != .draft }

    /// Whether outputs may be generated. Deliberately still approval-only — this is what makes
    /// `pendingReview` mean something operationally rather than being a decorative label.
    var allowsOutputGeneration: Bool { self == .approved || self == .generated }
}

enum SourceExtractionMethod: String, Codable, CaseIterable {
    case embeddedText
    case localOCR
    case ocrRequired

    var displayName: String {
        switch self {
        case .embeddedText: "Text extracted locally"
        case .localOCR: "OCR extracted locally"
        case .ocrRequired: "OCR required"
        }
    }
}

enum SourceReviewStatus: String, Codable, CaseIterable {
    case imported
    case reviewed
}

struct ImportedSource: Codable, Equatable, Identifiable {
    let id: UUID
    var reference: FileReference
    var setupRole: ImportedSourceRole? = nil
    var extractionMethod: SourceExtractionMethod
    var confidence: Double?
    var extractedText: String
    var reviewStatus: SourceReviewStatus
    var importedAt: Date
    var updatedAt: Date
    /// Whether this document may occupy a planner block, and if not, which pathway it belongs
    /// to. Optional on purpose — Swift decodes Optional properties with `decodeIfPresent`, so
    /// documents imported before this field existed still load and simply fall back to being
    /// classified on demand. See the CRITICAL PERSISTENCE RULE in MODEL_HANDOFF.txt.
    var placementEligibility: LessonPlacementEligibility? = nil
    /// Which differentiation category this serves, when it is supporting material.
    var differentiationRole: DifferentiationRole? = nil
    /// Module/lesson identifier used to attach supporting material to the right lesson.
    var lessonKey: DocumentLessonKey? = nil
    /// Subject inferred once from labels or a standards code at import time. Optional so files
    /// saved before this field existed remain decodable.
    var inferredSubject: String? = nil

    var effectiveSetupRole: ImportedSourceRole {
        setupRole ?? ImportedSourceRole.infer(displayName: reference.displayName, extractedText: extractedText)
    }

    /// Classifies on demand when the stored value is absent, so previously-imported documents
    /// behave correctly without a migration pass.
    var effectivePlacementEligibility: LessonPlacementEligibility {
        placementEligibility ?? DocumentPlacementClassifier.classify(
            displayName: reference.displayName, extractedText: extractedText
        ).eligibility
    }

    /// The document's subject, computed on read when nothing was stored.
    ///
    /// `inferredSubject` is only stamped at import, so it is nil for every document imported before
    /// the field existed. This keeps that case consistent rather than silently losing the value.
    ///
    /// Treat this as **opportunistic, not a primary signal**. Measured against a real 316-document
    /// curriculum import it resolved nothing at all: those files carry no standards codes and no
    /// `Subject:` label, which are the only two things subject inference keys on. Schedule-block
    /// matching is carried in practice by `SubjectVocabulary` content scoring, which placed 15 of
    /// 15 lessons correctly with no stored subject. This remains worth having because other
    /// publishers and districts do label subjects and cite standards — but do not build on it as
    /// though it reliably yields a subject.
    ///
    /// A stored value wins, but only if it is actually a value: a blank or whitespace-only string
    /// is treated as absent rather than as a subject, so hand-edited or older JSON carrying `""`
    /// still resolves. Stale-but-present values deliberately still win — defining staleness is the
    /// job of derivation versioning, not of this accessor.
    var effectiveInferredSubject: String? {
        if let stored = inferredSubject?.trimmingCharacters(in: .whitespacesAndNewlines), !stored.isEmpty {
            return stored
        }
        return LessonFieldExtractor.extractWithStructuralInference(from: extractedText).subject
    }

    /// The module/lesson identifier this document belongs to, computed on read when nothing was
    /// stored.
    ///
    /// The third field to need this treatment, after `effectivePlacementEligibility` and
    /// `effectiveInferredSubject`: anything stamped only at import is nil for every document
    /// imported before that field existed, so attachment matching would silently find nothing on
    /// an existing profile. Any future import-time field should ship with its fallback.
    var effectiveLessonKey: DocumentLessonKey? {
        lessonKey ?? DocumentPlacementClassifier.lessonKey(
            displayName: reference.displayName, extractedText: extractedText
        )
    }

    /// The single gate the planner must consult. Nothing but a placeable lesson may be scheduled.
    var canProposeScheduledLesson: Bool {
        effectivePlacementEligibility.canOccupyScheduleBlock
    }

    var canContributeLessonSequence: Bool {
        effectivePlacementEligibility.canContributeLessonSequence
    }
}

struct ImportedSourceIntakeReport: Equatable {
    var totalCount: Int
    var reviewedCount: Int
    var pacingReadyCount: Int
    var scheduleBlockCount: Int
    var roleCounts: [ImportedSourceRole: Int]

    var canBuildCoursePacing: Bool { pacingReadyCount > 0 }
    var hasScheduleScaffold: Bool { scheduleBlockCount > 0 }

    var title: String {
        totalCount == 0 ? "No documents imported yet" : "\(totalCount) document(s) imported"
    }

    var pacingStatus: String {
        if hasScheduleScaffold {
            return "\(scheduleBlockCount) daily schedule block(s) detected. Content can now be placed into the weekly planner."
        }
        if canBuildCoursePacing {
            return "\(pacingReadyCount) readable planning document(s) found. Add a daily schedule so lessons have fixed time blocks."
        }
        if reviewedCount > 0 {
            return "Readable documents are available, but no daily schedule has been detected yet"
        }
        return "Import a readable daily schedule and pacing guide to start the planner scaffold"
    }

    static func analyze(_ sources: [ImportedSource]) -> ImportedSourceIntakeReport {
        var roleCounts: [ImportedSourceRole: Int] = [:]
        for source in sources {
            roleCounts[source.effectiveSetupRole, default: 0] += 1
        }
        let reviewedSources = sources.filter { !$0.extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let scheduleSources = reviewedSources.filter { source in
            source.effectiveSetupRole == .instructionalCalendar
                || source.reference.displayName.lowercased().contains("schedule")
                || source.extractedText.lowercased().contains("sample daily schedule")
        }
        let scheduleBlockCount = scheduleSources.reduce(0) { count, source in
            count + Self.detectScheduleBlockCount(in: source.extractedText)
        }
        return ImportedSourceIntakeReport(
            totalCount: sources.count,
            reviewedCount: reviewedSources.count,
            pacingReadyCount: reviewedSources.filter { $0.effectiveSetupRole.supportsCoursePacing }.count,
            scheduleBlockCount: scheduleBlockCount,
            roleCounts: roleCounts
        )
    }

    private static func detectScheduleBlockCount(in text: String) -> Int {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let timePattern = #"^(\d{1,2}):(\d{2})\s*(AM|PM|am|pm)?\s*[-–]\s*(\d{1,2}):(\d{2})\s*(AM|PM|am|pm)?$"#
        let regex = try? NSRegularExpression(pattern: timePattern)
        return lines.filter { line in
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            return regex?.firstMatch(in: line, range: range) != nil
        }.count
    }
}

enum SourceReadinessLevel: String, Equatable {
    case readyForReview
    case carefulReviewRequired
    case visualReviewRequired
    case blocked

    var title: String {
        switch self {
        case .readyForReview: "Ready for teacher review"
        case .carefulReviewRequired: "Careful text review required"
        case .visualReviewRequired: "Visual and math review required"
        case .blocked: "Text review required before planning"
        }
    }
}

enum SourceContentRisk: String, Equatable, Identifiable {
    case ocr
    case mathNotation
    case visualLayout

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ocr: "OCR transcription"
        case .mathNotation: "Math notation"
        case .visualLayout: "Visual layout"
        }
    }

    var reviewInstruction: String {
        switch self {
        case .ocr:
            "Compare the extracted text to the original PDF for missing words, substituted letters, line breaks, names, numbers, and punctuation."
        case .mathNotation:
            "Compare equations, symbols, fractions, exponents, and operators to the original PDF before using the source for planning."
        case .visualLayout:
            "Compare diagrams, tables, figures, captions, page order, labels, and spatial relationships to the original PDF."
        }
    }
}

struct SourceReadinessReport: Equatable {
    var level: SourceReadinessLevel
    var summary: String
    var checks: [String]
    var risks: [SourceContentRisk]

    static func analyze(_ source: ImportedSource) -> SourceReadinessReport {
        let trimmedText = source.extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasLikelyMathMarkers = likelyContainsMathNotation(trimmedText)
        let hasLikelyVisualLayoutMarkers = likelyContainsVisualLayoutMarkers(trimmedText)
        var risks: [SourceContentRisk] = []

        if source.extractionMethod == .ocrRequired || trimmedText.isEmpty {
            return SourceReadinessReport(
                level: .blocked,
                summary: "No usable text is available yet. Do not create a lesson until the teacher has supplied or corrected the source text.",
                checks: ["This file appears to need OCR or manual transcription.", "Handwriting, diagrams, and page layout are not automatically understood."],
                risks: [.ocr, .visualLayout]
            )
        }

        if hasLikelyMathMarkers {
            risks.append(.mathNotation)
        }

        if source.extractionMethod == .localOCR {
            let confidence = source.confidence ?? 0
            let confidenceMessage = "Local OCR confidence: \(Int((confidence * 100).rounded()))%."
            risks.insert(.ocr, at: 0)
            if confidence < 0.85 || hasLikelyVisualLayoutMarkers {
                risks.append(.visualLayout)
            }
            return SourceReadinessReport(
                level: confidence < 0.85 || risks.contains(.mathNotation) || risks.contains(.visualLayout) ? .visualReviewRequired : .carefulReviewRequired,
                summary: "This source was read from page images. Confirm names, numbers, symbols, and instructional wording before using it.",
                checks: [confidenceMessage, "Check diagrams, handwriting, tables, equations, and fraction notation against the original page."],
                risks: risks
            )
        }

        if hasLikelyVisualLayoutMarkers {
            risks.append(.visualLayout)
        }

        if !risks.isEmpty {
            return SourceReadinessReport(
                level: .visualReviewRequired,
                summary: "Selectable text was found, but it may contain math or visual symbols that need comparison with the original PDF.",
                checks: ["Check equations, fraction notation, diagrams, tables, and image captions before creating a lesson."],
                risks: risks
            )
        }

        return SourceReadinessReport(
            level: .readyForReview,
            summary: "Selectable text was found locally. Review it for completeness before creating a lesson.",
            checks: ["Images, diagrams, and page layout may not be included in extracted text."],
            risks: []
        )
    }

    private static func likelyContainsMathNotation(_ text: String) -> Bool {
        if ["√", "≈", "≠", "≤", "≥", "÷", "×", "±", "∑", "π", "^"].contains(where: { text.contains($0) }) {
            return true
        }
        return text.range(of: #"\b\d+\s*/\s*\d+\b"#, options: .regularExpression) != nil
    }

    private static func likelyContainsVisualLayoutMarkers(_ text: String) -> Bool {
        if ["□", "�"].contains(where: { text.contains($0) }) {
            return true
        }
        return text.range(of: #"\b(diagram|table|figure|chart|caption|graph|image|label)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

struct InstructionalStep: Codable, Equatable, Identifiable {
    let id: UUID
    var title: String
    var notes: String
}

struct LessonRecord: Codable, Equatable, Identifiable {
    let id: UUID
    var status: LessonStatus
    var title: String
    var subject: String
    var gradeOrAgeRange: String
    var objective: String
    var sourceReferences: [String]
    var sourceTextSnapshot: String?
    var aiReviewWarnings: [String]?
    var instructionalSequence: [InstructionalStep]
    var materials: [String]
    var differentiationSummary: String
    var printableResourcePrompt: String?
    var assessmentSummary: String
    var createdAt: Date
    var updatedAt: Date
    /// Optional so records saved before this field existed still decode; `effectiveOrigin`
    /// classifies those from the legacy warning text.
    var origin: RecordOrigin? = nil

    /// Falls back to the pre-provenance marker. Deliberately biased toward `.teacherAuthored`:
    /// wrongly regenerating a teacher's lesson destroys their work, while wrongly preserving an
    /// auto-derived one merely leaves a stale record they can delete.
    var effectiveOrigin: RecordOrigin {
        if let origin { return origin }
        let warnings = aiReviewWarnings ?? []
        return warnings.contains { $0.contains(Self.legacyAutoCreatedMarker) } ? .autoDerived : .teacherAuthored
    }

    static let legacyAutoCreatedMarker = "Auto-created from readable planning documents"

    static func draft(title: String = "Untitled lesson") -> LessonRecord {
        LessonRecord(
            id: UUID(), status: .draft, title: title, subject: "", gradeOrAgeRange: "",
            objective: "", sourceReferences: [], sourceTextSnapshot: nil, aiReviewWarnings: nil, instructionalSequence: [], materials: [],
            differentiationSummary: "", printableResourcePrompt: "", assessmentSummary: "", createdAt: .now, updatedAt: .now
        )
    }
}

enum LessonExportReadinessIssue: String, Equatable, Identifiable {
    case missingTitle
    case missingObjective
    case missingInstructionalSequence
    case missingAssessment
    case missingSubjectOrGrade
    case missingMaterials
    case missingDifferentiation

    var id: String { rawValue }

    var isBlocking: Bool {
        switch self {
        case .missingTitle, .missingObjective, .missingInstructionalSequence, .missingAssessment: true
        case .missingSubjectOrGrade, .missingMaterials, .missingDifferentiation: false
        }
    }

    var title: String {
        switch self {
        case .missingTitle: "Add a lesson title"
        case .missingObjective: "Add a learning objective"
        case .missingInstructionalSequence: "Add instructional steps"
        case .missingAssessment: "Add an assessment or success check"
        case .missingSubjectOrGrade: "Add subject and grade"
        case .missingMaterials: "Review materials"
        case .missingDifferentiation: "Review differentiation supports"
        }
    }

    var instruction: String {
        switch self {
        case .missingTitle:
            "Outputs need a clear title for filenames, slide titles, and plan headers."
        case .missingObjective:
            "Add the teacher-reviewed learning goal before creating classroom-facing outputs."
        case .missingInstructionalSequence:
            "Add at least one teacher-reviewed instructional step before generating lesson materials."
        case .missingAssessment:
            "Add how the teacher will check understanding before generating final outputs."
        case .missingSubjectOrGrade:
            "Subject and grade help outputs label the lesson clearly."
        case .missingMaterials:
            "Materials can be blank, but review whether students or the teacher need listed tools."
        case .missingDifferentiation:
            "Differentiation can be blank, but review whether supports, extensions, or small-group notes are needed."
        }
    }
}

struct LessonExportReadinessReport: Equatable {
    var issues: [LessonExportReadinessIssue]

    var blockingIssues: [LessonExportReadinessIssue] { issues.filter(\.isBlocking) }
    var advisoryIssues: [LessonExportReadinessIssue] { issues.filter { !$0.isBlocking } }
    var isReady: Bool { blockingIssues.isEmpty }

    var title: String {
        isReady ? "Ready for output generation" : "Finish required lesson fields"
    }

    static func analyze(_ lesson: LessonRecord) -> LessonExportReadinessReport {
        func blank(_ value: String) -> Bool {
            value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        var issues: [LessonExportReadinessIssue] = []
        if blank(lesson.title) || lesson.title == "Untitled lesson" { issues.append(.missingTitle) }
        if blank(lesson.objective) { issues.append(.missingObjective) }
        if lesson.instructionalSequence.filter({ !blank($0.title) || !blank($0.notes) }).isEmpty {
            issues.append(.missingInstructionalSequence)
        }
        if blank(lesson.assessmentSummary) { issues.append(.missingAssessment) }
        if blank(lesson.subject) || blank(lesson.gradeOrAgeRange) { issues.append(.missingSubjectOrGrade) }
        if lesson.materials.filter({ !blank($0) }).isEmpty { issues.append(.missingMaterials) }
        if blank(lesson.differentiationSummary) { issues.append(.missingDifferentiation) }
        return LessonExportReadinessReport(issues: issues)
    }
}

struct LessonDraftProposal: Codable, Equatable, Sendable {
    var title: String
    var subject: String
    var gradeOrAgeRange: String
    var objective: String
    var instructionalSteps: [String]
    var materials: [String]
    var differentiationSummary: String
    var printableResourcePrompt: String
    var assessmentSummary: String
    var sourceType: String?
    var reviewWarnings: [String]?
}

enum GeneratedOutputKind: String, Codable, CaseIterable {
    case lessonPlanHTML
    case weeklyPlanHTML
    case differentiationGuideHTML
    case slideDeckPPTX

    var displayName: String {
        switch self {
        case .lessonPlanHTML: "Lesson plan (HTML)"
        case .weeklyPlanHTML: "Weekly plan (HTML)"
        case .differentiationGuideHTML: "Differentiation guide (HTML)"
        case .slideDeckPPTX: "Slide deck (PowerPoint)"
        }
    }
}

struct GeneratedOutputRecord: Codable, Equatable, Identifiable {
    let id: UUID
    var lessonRecordID: UUID?
    var kind: GeneratedOutputKind
    var displayName: String
    var filePath: String
    var templateDisplayName: String?
    var createdAt: Date
    var review: GeneratedOutputReview?
}

struct GeneratedOutputReview: Codable, Equatable {
    var reviewedAt: Date
    var reviewerNotes: String

    static let defaultChecklist = [
        "Opened the generated file.",
        "Checked layout, wrapping, and editable text.",
        "Confirmed classroom-facing content was teacher reviewed."
    ]

    static func checklist(for kind: GeneratedOutputKind) -> [String] {
        var checklist = defaultChecklist
        if kind == .slideDeckPPTX {
            checklist.append("Opened the deck in PowerPoint or a compatible viewer.")
            checklist.append("Confirmed speaker notes keep source provenance.")
            checklist.append("Confirmed presentation-template provenance and mapping notes when a template was used.")
            checklist.append("If a presentation template is registered, checked that output does not claim true layout preservation unless template fidelity QA was completed.")
            checklist.append("If using Google Slides, checked upload conversion fidelity.")
        }
        return checklist
    }
}

struct LessonOutputLinkSet: Equatable {
    var lessonPlanHTML: GeneratedOutputRecord?
    var slideDeckPPTX: GeneratedOutputRecord?
    var differentiationGuideHTML: GeneratedOutputRecord?

    var isComplete: Bool {
        lessonPlanHTML != nil && slideDeckPPTX != nil && differentiationGuideHTML != nil
    }

    static func latest(for lessonID: UUID, in outputs: [GeneratedOutputRecord]) -> LessonOutputLinkSet {
        LessonOutputLinkSet(
            lessonPlanHTML: latest(kind: .lessonPlanHTML, lessonID: lessonID, in: outputs),
            slideDeckPPTX: latest(kind: .slideDeckPPTX, lessonID: lessonID, in: outputs),
            differentiationGuideHTML: latest(kind: .differentiationGuideHTML, lessonID: lessonID, in: outputs)
        )
    }

    private static func latest(kind: GeneratedOutputKind, lessonID: UUID, in outputs: [GeneratedOutputRecord]) -> GeneratedOutputRecord? {
        outputs
            .filter { $0.kind == kind && $0.lessonRecordID == lessonID }
            .sorted { $0.createdAt > $1.createdAt }
            .first
    }
}

struct WeeklyOutputSummary: Equatable {
    var scheduledLessonCount: Int
    var lessonPlanCount: Int
    var slideDeckCount: Int
    var differentiationGuideCount: Int

    var completeLessonCount: Int

    var missingOutputCount: Int {
        max(0, (scheduledLessonCount * 3) - lessonPlanCount - slideDeckCount - differentiationGuideCount)
    }

    var statusLine: String {
        "\(completeLessonCount) of \(scheduledLessonCount) lessons have all three outputs."
    }

    var generationLine: String {
        missingOutputCount == 0
            ? "All scheduled lesson outputs are ready to link."
            : "\(missingOutputCount) missing outputs will be created before the weekly package is written."
    }

    static func analyze(plan: WeeklyPlan, lessons: [LessonRecord], generatedOutputs: [GeneratedOutputRecord]) -> WeeklyOutputSummary {
        let lessonByID = Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) })
        let scheduledLessons = Array(Set(plan.assignments.map(\.lessonRecordID)))
            .compactMap { lessonByID[$0] }
            .filter(\.status.isSchedulable)
        let linkSets = scheduledLessons.map { LessonOutputLinkSet.latest(for: $0.id, in: generatedOutputs) }
        return WeeklyOutputSummary(
            scheduledLessonCount: scheduledLessons.count,
            lessonPlanCount: linkSets.filter { $0.lessonPlanHTML != nil }.count,
            slideDeckCount: linkSets.filter { $0.slideDeckPPTX != nil }.count,
            differentiationGuideCount: linkSets.filter { $0.differentiationGuideHTML != nil }.count,
            completeLessonCount: linkSets.filter(\.isComplete).count
        )
    }
}

enum WeeklyPackageReadinessIssue: String, Equatable, Identifiable {
    case noScheduledLessons
    case scheduledLessonMissing
    case unapprovedScheduledLesson
    case invalidScheduledTimeRange
    case incompleteOutputs

    var id: String { rawValue }

    var isBlocking: Bool {
        switch self {
        case .noScheduledLessons, .scheduledLessonMissing, .unapprovedScheduledLesson, .invalidScheduledTimeRange: true
        case .incompleteOutputs: false
        }
    }

    var title: String {
        switch self {
        case .noScheduledLessons: "Schedule at least one lesson"
        case .scheduledLessonMissing: "Resolve missing scheduled lessons"
        case .unapprovedScheduledLesson: "Approve scheduled lessons"
        case .invalidScheduledTimeRange: "Fix scheduled lesson times"
        case .incompleteOutputs: "Generate missing lesson outputs"
        }
    }

    var instruction: String {
        switch self {
        case .noScheduledLessons:
            "Add approved lessons to the weekly schedule before creating the weekly package."
        case .scheduledLessonMissing:
            "One or more scheduled lessons no longer exists in the lesson list."
        case .unapprovedScheduledLesson:
            "Only approved lessons can be included in the weekly package."
        case .invalidScheduledTimeRange:
            "Every scheduled lesson needs an end time after its start time."
        case .incompleteOutputs:
            "The weekly package can create missing lesson plans, slide decks, and differentiation guides before linking them."
        }
    }
}

struct WeeklyPackageReadinessReport: Equatable {
    var issues: [WeeklyPackageReadinessIssue]
    var scheduledLessonCount: Int
    var completeOutputLessonCount: Int
    var outputSummary: WeeklyOutputSummary

    var blockingIssues: [WeeklyPackageReadinessIssue] { issues.filter(\.isBlocking) }
    var advisoryIssues: [WeeklyPackageReadinessIssue] { issues.filter { !$0.isBlocking } }
    var canGenerate: Bool { blockingIssues.isEmpty }

    var title: String {
        canGenerate ? "Ready to generate weekly package" : "Finish weekly package setup"
    }

    static func analyze(plan: WeeklyPlan, lessons: [LessonRecord], generatedOutputs: [GeneratedOutputRecord]) -> WeeklyPackageReadinessReport {
        let lessonByID = Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) })
        let scheduledLessonIDs = Array(Set(plan.assignments.map(\.lessonRecordID)))
        var issues: [WeeklyPackageReadinessIssue] = []

        if scheduledLessonIDs.isEmpty {
            issues.append(.noScheduledLessons)
        }
        if scheduledLessonIDs.contains(where: { lessonByID[$0] == nil }) {
            issues.append(.scheduledLessonMissing)
        }
        let scheduledLessons = scheduledLessonIDs.compactMap { lessonByID[$0] }
        if scheduledLessons.contains(where: { $0.status != .approved }) {
            issues.append(.unapprovedScheduledLesson)
        }
        if plan.assignments.contains(where: { $0.end <= $0.start }) {
            issues.append(.invalidScheduledTimeRange)
        }

        let outputSummary = WeeklyOutputSummary.analyze(plan: plan, lessons: lessons, generatedOutputs: generatedOutputs)
        if outputSummary.scheduledLessonCount > 0 && outputSummary.completeLessonCount < outputSummary.scheduledLessonCount {
            issues.append(.incompleteOutputs)
        }

        return WeeklyPackageReadinessReport(
            issues: issues,
            scheduledLessonCount: scheduledLessonIDs.count,
            completeOutputLessonCount: outputSummary.completeLessonCount,
            outputSummary: outputSummary
        )
    }
}

enum PresentationTemplateReadinessIssue: String, Equatable, Identifiable {
    case noPresentationTemplate
    case missingSlotMappings
    case missingRequiredMappings
    case layoutInventoryPending
    case frameMapPending
    case fidelityQAPending

    var id: String { rawValue }

    var isBlockingMetadataUse: Bool {
        switch self {
        case .noPresentationTemplate, .missingSlotMappings, .missingRequiredMappings: true
        case .layoutInventoryPending, .frameMapPending, .fidelityQAPending: false
        }
    }

    var title: String {
        switch self {
        case .noPresentationTemplate: "Register a presentation template"
        case .missingSlotMappings: "Add lesson-field mappings"
        case .missingRequiredMappings: "Map required lesson fields"
        case .layoutInventoryPending: "Run template layout inventory"
        case .frameMapPending: "Create template frame map"
        case .fidelityQAPending: "Complete template fidelity QA"
        }
    }

    var instruction: String {
        switch self {
        case .noPresentationTemplate:
            "Register a teacher-owned PowerPoint template before template-aware deck export."
        case .missingSlotMappings:
            "The template needs named mappings from lesson fields to template slots."
        case .missingRequiredMappings:
            "Required fields must include title, objective, instructional sequence, and assessment."
        case .layoutInventoryPending:
            "Record every reusable source slide, its role, and inherited placeholder count before layout-preserving export."
        case .frameMapPending:
            "Map each intended output slide to a source template slide before copying and editing template structure."
        case .fidelityQAPending:
            "Assign a template placeholder to every required lesson field, then confirm the frame map."
        }
    }
}

struct PresentationTemplateReadinessReport: Equatable {
    var template: OutputTemplateRegistration?
    var issues: [PresentationTemplateReadinessIssue]
    var mappedFieldCount: Int
    var requiredMappedFieldCount: Int
    var inventorySlideCount: Int
    var frameMapCount: Int

    var blockingMetadataIssues: [PresentationTemplateReadinessIssue] {
        issues.filter(\.isBlockingMetadataUse)
    }

    var canUseTemplateMetadata: Bool { blockingMetadataIssues.isEmpty }
    var isReadyForLayoutPreservation: Bool { canUseTemplateMetadata && issues.isEmpty }

    /// Required lesson fields (title, objective, instructional sequence, assessment) that
    /// don't yet have a template placeholder assigned to them — drives both the "Confirm
    /// frame map" action's guard and the read-only summary shown in the Workspace UI.
    var unassignedRequiredFields: [LessonTemplateField] {
        let requiredFields = TemplateSlotMapping.defaultPresentationMappings.filter(\.required).map(\.lessonField)
        let assignedFields = Set((template?.layoutPlan?.placeholderAssignments ?? []).compactMap(\.lessonField))
        return requiredFields.filter { !assignedFields.contains($0) }
    }

    var title: String {
        if isReadyForLayoutPreservation { return "Template layout preservation ready" }
        if canUseTemplateMetadata { return "Template provenance ready" }
        return "Template setup incomplete"
    }

    static func analyze(configuration: AppConfiguration?) -> PresentationTemplateReadinessReport {
        guard let template = configuration?.outputTemplates.first(where: { $0.kind == .presentation }) else {
            return PresentationTemplateReadinessReport(
                template: nil,
                issues: [.noPresentationTemplate],
                mappedFieldCount: 0,
                requiredMappedFieldCount: 0,
                inventorySlideCount: 0,
                frameMapCount: 0
            )
        }

        let mappings = template.slotMappings ?? []
        var issues: [PresentationTemplateReadinessIssue] = []
        if mappings.isEmpty {
            issues.append(.missingSlotMappings)
        }

        let requiredFields = Set(TemplateSlotMapping.defaultPresentationMappings.filter(\.required).map(\.lessonField))
        let mappedRequiredFields = Set(mappings.filter(\.required).map(\.lessonField))
        if !requiredFields.isSubset(of: mappedRequiredFields) {
            issues.append(.missingRequiredMappings)
        }
        let inventorySlideCount = template.layoutPlan?.slideInventory.count ?? 0
        let frameMapCount = template.layoutPlan?.frameMap.count ?? 0
        if inventorySlideCount == 0 {
            issues.append(.layoutInventoryPending)
        }
        if frameMapCount == 0 {
            issues.append(.frameMapPending)
        }
        if template.layoutPlan?.fidelityReviewCompleted != true {
            issues.append(.fidelityQAPending)
        }

        return PresentationTemplateReadinessReport(
            template: template,
            issues: issues,
            mappedFieldCount: mappings.count,
            requiredMappedFieldCount: mappedRequiredFields.count,
            inventorySlideCount: inventorySlideCount,
            frameMapCount: frameMapCount
        )
    }
}

enum ReleaseReadinessStatus: String, Equatable {
    case ready
    case attention
    case blocked
}

struct ReleaseReadinessItem: Equatable, Identifiable {
    let id: String
    var title: String
    var detail: String
    var status: ReleaseReadinessStatus
}

struct ReleaseReadinessReport: Equatable {
    var items: [ReleaseReadinessItem]

    var blockers: [ReleaseReadinessItem] { items.filter { $0.status == .blocked } }
    var attentionItems: [ReleaseReadinessItem] { items.filter { $0.status == .attention } }
    var isReadyForPersonalQA: Bool { blockers.isEmpty }

    static func analyze(configuration: AppConfiguration?, lessons: [LessonRecord], generatedOutputs: [GeneratedOutputRecord]) -> ReleaseReadinessReport {
        var items: [ReleaseReadinessItem] = []

        items.append(ReleaseReadinessItem(
            id: "workspace",
            title: "Workspace configured",
            detail: configuration == nil ? "Complete setup before release-style QA." : "Workspace metadata is available.",
            status: configuration == nil ? .blocked : .ready
        ))

        items.append(ReleaseReadinessItem(
            id: "output-folder",
            title: "Output folder selected",
            detail: configuration?.outputFolderReference == nil ? "Choose an output folder for generated lesson packages." : "Generated files have a configured destination.",
            status: configuration?.outputFolderReference == nil ? .blocked : .ready
        ))

        let exporter = configuration?.slideDeckExporter ?? .nativeOpenXML
        items.append(ReleaseReadinessItem(
            id: "native-exporter",
            title: "Native PowerPoint exporter",
            detail: exporter == .nativeOpenXML ? "Native exporter is the default path." : "Personal bridge is selected; switch back before customer-style QA.",
            status: exporter == .nativeOpenXML ? .ready : .attention
        ))

        let hasApprovedLesson = lessons.contains { $0.status == .approved }
        items.append(ReleaseReadinessItem(
            id: "approved-lesson",
            title: "Approved lesson available",
            detail: hasApprovedLesson ? "At least one approved lesson can be used for output QA." : "Approve a generic lesson before release-style output QA.",
            status: hasApprovedLesson ? .ready : .attention
        ))

        let reviewedDeck = generatedOutputs.contains { $0.kind == .slideDeckPPTX && $0.review != nil }
        items.append(ReleaseReadinessItem(
            id: "reviewed-deck",
            title: "PowerPoint output reviewed",
            detail: reviewedDeck ? "A generated PowerPoint deck has a manual review record." : "Generate and manually review a native PowerPoint deck.",
            status: reviewedDeck ? .ready : .attention
        ))

        let hasPresentationTemplate = configuration?.outputTemplates.contains { $0.kind == .presentation } ?? false
        items.append(ReleaseReadinessItem(
            id: "presentation-template",
            title: "Presentation template registered",
            detail: hasPresentationTemplate ? "A presentation template is registered for future mapping work." : "Register a generic teacher-owned presentation template when template fidelity work begins.",
            status: hasPresentationTemplate ? .ready : .attention
        ))

        let templateReadiness = PresentationTemplateReadinessReport.analyze(configuration: configuration)
        items.append(ReleaseReadinessItem(
            id: "template-layout-fidelity",
            title: "Template layout fidelity",
            detail: templateReadiness.isReadyForLayoutPreservation ? "Template layout preservation has passed fidelity readiness." : "Template provenance can be tracked, but true layout preservation still needs inventory, frame mapping, and fidelity QA.",
            status: templateReadiness.isReadyForLayoutPreservation ? .ready : .attention
        ))

        return ReleaseReadinessReport(items: items)
    }
}

struct LocalWorkflowQAReport: Equatable {
    var items: [ReleaseReadinessItem]

    var attentionItems: [ReleaseReadinessItem] { items.filter { $0.status != .ready } }
    var isReadyForEndToEndQA: Bool { attentionItems.isEmpty }

    static func analyze(
        activeTeacherProfile: TeacherProfile?,
        importedSources: [ImportedSource],
        pacingReport: CoursePacingReadinessReport,
        weeklyPackageReport: WeeklyPackageReadinessReport,
        lessons: [LessonRecord],
        generatedOutputs: [GeneratedOutputRecord]
    ) -> LocalWorkflowQAReport {
        let intakeReport = ImportedSourceIntakeReport.analyze(importedSources)
        let hasApprovedLesson = lessons.contains { $0.status == .approved }
        let hasWeeklyHub = generatedOutputs.contains { $0.kind == .weeklyPlanHTML }

        return LocalWorkflowQAReport(items: [
            ReleaseReadinessItem(
                id: "local-profile",
                title: "Local test profile selected",
                detail: activeTeacherProfile.map { "Testing as \($0.displayName)." } ?? "Use Workspace to select or create a local test teacher before multi-user QA.",
                status: activeTeacherProfile == nil ? .attention : .ready
            ),
            ReleaseReadinessItem(
                id: "setup-documents",
                title: "Readable setup documents available",
                detail: intakeReport.pacingStatus,
                status: intakeReport.canBuildCoursePacing ? .ready : .attention
            ),
            ReleaseReadinessItem(
                id: "course-pacing",
                title: "Course pacing approved",
                detail: pacingReport.canGovernWeeklyPlanning ? "Approved pacing can guide weekly planning." : pacingReport.title,
                status: pacingReport.canGovernWeeklyPlanning ? .ready : .attention
            ),
            ReleaseReadinessItem(
                id: "approved-lessons",
                title: "Approved lesson available",
                detail: hasApprovedLesson ? "At least one approved lesson can generate the three outputs." : "Create and approve at least one lesson before package QA.",
                status: hasApprovedLesson ? .ready : .attention
            ),
            ReleaseReadinessItem(
                id: "weekly-schedule",
                title: "Weekly schedule ready",
                detail: weeklyPackageReport.canGenerate ? "The selected week is ready for package generation." : weeklyPackageReport.title,
                status: weeklyPackageReport.canGenerate ? .ready : .attention
            ),
            ReleaseReadinessItem(
                id: "weekly-hub",
                title: "Weekly hub generated",
                detail: hasWeeklyHub ? "A weekly hub file exists in generated-output history." : "Generate the weekly package after the schedule is ready.",
                status: hasWeeklyHub ? .ready : .attention
            )
        ])
    }
}

struct WeeklyLessonAssignment: Codable, Equatable, Identifiable {
    let id: UUID
    var lessonRecordID: UUID
    var date: Date
    var start: Date
    var end: Date
    var planningNotes: String?
    /// Optional so assignments saved before this field existed still decode; `effectiveOrigin`
    /// classifies those from the legacy note prefix.
    var origin: RecordOrigin? = nil

    /// Falls back to the pre-provenance marker. An assignment the teacher placed or moved by hand
    /// has no such prefix and is therefore treated as theirs, which is the safe direction.
    var effectiveOrigin: RecordOrigin {
        if let origin { return origin }
        return (planningNotes ?? "").hasPrefix(Self.legacyAutoPlacementPrefix) ? .autoDerived : .teacherAuthored
    }

    static let legacyAutoPlacementPrefix = "Pacing:"
}

struct WeeklyPlanningBrief: Codable, Equatable {
    var teacherFocus: String
    var preparationNotes: String
    var studentSupportNotes: String
    var updatedAt: Date

    static let empty = WeeklyPlanningBrief(
        teacherFocus: "",
        preparationNotes: "",
        studentSupportNotes: "",
        updatedAt: .now
    )

    var hasContent: Bool {
        !teacherFocus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !preparationNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !studentSupportNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum WeeklyPacingRefinementStatus: String, Codable, Equatable {
    case draft
    case accepted

    var displayName: String {
        switch self {
        case .draft: "Draft refinement"
        case .accepted: "Accepted refinement"
        }
    }
}

struct WeeklyPacingRefinementProposal: Codable, Equatable, Identifiable {
    let id: UUID
    var checkInNote: String
    var proposedAdjustmentSummary: String
    var pacingImpactNotes: String
    var affectedPacingArea: String?
    var suggestedDateShiftDays: Int?
    var status: WeeklyPacingRefinementStatus
    var createdAt: Date
    var acceptedAt: Date?

    static func draft(from checkInNote: String, weekOf: Date) -> WeeklyPacingRefinementProposal? {
        let trimmed = checkInNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lowercased = trimmed.lowercased()
        let summary: String
        let impact: String
        let affectedArea: String
        let dateShift: Int

        if ["lost", "missed", "cancel", "assembly", "snow", "sick", "substitute"].contains(where: { lowercased.contains($0) }) {
            summary = "Consider slowing pacing for this week."
            impact = "Review whether upcoming pacing lessons should move later or whether one planned lesson should become review, reteach, or catch-up time."
            affectedArea = "Upcoming lessons and assessment timing"
            dateShift = 1
        } else if ["ahead", "finished early", "faster", "extra day"].contains(where: { lowercased.contains($0) }) {
            summary = "Consider advancing pacing for this week."
            impact = "Review whether the next pacing lesson can move earlier or whether the gained time should become enrichment, assessment review, or student practice."
            affectedArea = "Next pacing lesson"
            dateShift = -1
        } else if ["behind", "slow", "reteach", "confused", "need more", "struggled"].contains(where: { lowercased.contains($0) }) {
            summary = "Consider adding support time before moving ahead."
            impact = "Review whether the pacing model should add reteach time, reduce the week target, or delay the next assessment window."
            affectedArea = "Current module and next assessment window"
            dateShift = 1
        } else {
            summary = "Review weekly pacing adjustment."
            impact = "Use this check-in note to decide whether the approved pacing model needs a timing note, date change, or schedule adjustment."
            affectedArea = "Teacher-selected pacing area"
            dateShift = 0
        }

        return WeeklyPacingRefinementProposal(
            id: UUID(),
            checkInNote: trimmed,
            proposedAdjustmentSummary: summary,
            pacingImpactNotes: "Week of \(weekOf.formatted(date: .abbreviated, time: .omitted)): \(impact)",
            affectedPacingArea: affectedArea,
            suggestedDateShiftDays: dateShift,
            status: .draft,
            createdAt: .now,
            acceptedAt: nil
        )
    }
}

struct WeeklyPlan: Codable, Equatable {
    var weekOf: Date
    var planningBrief: WeeklyPlanningBrief?
    var pacingRefinementProposal: WeeklyPacingRefinementProposal? = nil
    var assignments: [WeeklyLessonAssignment]
    var updatedAt: Date

    static func empty(for weekOf: Date) -> WeeklyPlan {
        WeeklyPlan(weekOf: weekOf, planningBrief: .empty, pacingRefinementProposal: nil, assignments: [], updatedAt: .now)
    }
}

enum TaskStatus: String, Codable, CaseIterable {
    case open, complete
}

struct ScheduleBlock: Codable, Equatable, Identifiable {
    let id: UUID
    var title: String
    var start: Date
    var end: Date
    var type: String
    var linkedLessonRecordID: UUID?
    var notes: String
}

struct DailyTask: Codable, Equatable, Identifiable {
    let id: UUID
    var title: String
    var status: TaskStatus
    var dueTime: Date?
    var linkedLessonRecordID: UUID?
    var notes: String
}

struct DailyPlan: Codable, Equatable {
    var date: Date
    var scheduleBlocks: [ScheduleBlock]
    var tasks: [DailyTask]
    var dailyNotes: String
    var updatedAt: Date

    static func empty(for date: Date = .now) -> DailyPlan {
        DailyPlan(date: date, scheduleBlocks: [], tasks: [], dailyNotes: "", updatedAt: .now)
    }
}

/// What the last automatic placement pass actually did. Reported so a teacher is never left to
/// infer from an empty planner whether the app found nothing, placed nothing, or declined to guess.
struct AutoPlacementSummary: Equatable {
    var placedCount: Int
    var unplacedForMissingBlockMatch: Int

    var hasUnplaced: Bool { unplacedForMissingBlockMatch > 0 }

    var summaryLine: String {
        let placed = "\(placedCount) lesson\(placedCount == 1 ? "" : "s") scheduled."
        guard hasUnplaced else { return placed }
        return placed + " \(unplacedForMissingBlockMatch) left unscheduled because no matching "
            + "subject block was found — those blocks were left unchanged."
    }
}

/// What an explicit rebuild of derived planning data would do, or has just done. Computed before
/// execution so the teacher confirms against real counts rather than a vague warning — this
/// operation removes records, and generated output files already written to their output folder
/// are outside the snapshot safety net entirely.
struct DerivedRebuildPreview: Equatable {
    var removableLessons: Int
    var removablePlacements: Int
    var preservedTeacherLessons: Int
    /// Auto-derived lessons kept because a generated lesson plan, deck, or differentiation guide
    /// points at them. A teacher who generated and possibly printed materials has invested in that
    /// lesson, and the files on disk would be orphaned by deleting it.
    var preservedOutputLinkedLessons: Int
    /// Auto-derived lessons kept because a teacher-placed or teacher-moved assignment references
    /// them. Deleting these would produce exactly the dangling state
    /// `WeeklyPackageReadinessReport` already reports as a missing scheduled lesson.
    var preservedAssignmentLinkedLessons: Int
    var preservedTeacherPlacements: Int
    var pacingUnitsBefore: Int
    var pacingLessonsBefore: Int
    /// True when the active pacing plan is the teacher's. A rebuild refuses rather than discarding
    /// hand-edited dates, skipped days, and refinement notes.
    var isBlockedByTeacherAuthoredPacing: Bool

    var preservedLessonTotal: Int {
        preservedTeacherLessons + preservedOutputLinkedLessons + preservedAssignmentLinkedLessons
    }

    var summaryLine: String {
        if isBlockedByTeacherAuthoredPacing {
            return "This course pacing plan has your own edits, so it will not be rebuilt automatically."
        }
        var parts = ["\(removableLessons) auto-created lesson\(removableLessons == 1 ? "" : "s") and \(removablePlacements) automatic placement\(removablePlacements == 1 ? "" : "s") will be rebuilt from your imported documents."]
        if preservedLessonTotal > 0 || preservedTeacherPlacements > 0 {
            parts.append("\(preservedLessonTotal) lesson\(preservedLessonTotal == 1 ? "" : "s") and \(preservedTeacherPlacements) placement\(preservedTeacherPlacements == 1 ? "" : "s") you created, edited, or generated materials for will be kept, including where they sit in your week.")
        }
        return parts.joined(separator: " ")
    }
}

/// A contiguous run of pages within a source document, 1-based and inclusive.
///
/// Structured rather than a display string because the printable packet merges *actual pages*. A
/// free-text "pp. 12-13" cannot be executed, and a workbook attached to several lessons without a
/// range would merge the entire workbook into each one.
struct PageRange: Codable, Equatable, Hashable {
    var first: Int
    var last: Int

    var pageCount: Int { max(0, last - first + 1) }
    var isValid: Bool { first >= 1 && last >= first }

    /// 0-based indices for PDFKit, clamped to what the document actually contains so a stale or
    /// over-long range cites fewer pages rather than crashing.
    func zeroBasedIndices(inDocumentOfLength length: Int) -> [Int] {
        guard isValid, length > 0 else { return [] }
        let lower = min(first - 1, length - 1)
        let upper = min(last - 1, length - 1)
        guard lower <= upper else { return [] }
        return Array(lower...upper)
    }

    var displayText: String { first == last ? "p. \(first)" : "pp. \(first)-\(last)" }
}

/// Links a supporting material to the lesson it serves, in a differentiation role.
///
/// Kept as its own record rather than a field on `LessonRecord` so one material can support several
/// lessons, and so the *relationship* carries its own provenance: a teacher's manual attachment
/// must survive a rebuild that regenerates automatic ones. That provenance is genuinely distinct
/// from `ImportedSource.origin` (which describes the document) and `LessonRecord.origin` (which
/// describes the lesson) — it describes the link between them.
struct LessonMaterialAttachment: Codable, Equatable, Identifiable {
    let id: UUID
    var lessonRecordID: UUID
    var importedSourceID: UUID
    var role: DifferentiationRole
    /// Pages to merge into a printable packet. Nil means the pages are unknown, in which case the
    /// material is **cited rather than merged** — merging a whole document because no range was
    /// resolved is worse than telling the teacher which file to open.
    var pageRanges: [PageRange]?
    /// Human-facing label, e.g. a publisher's own page numbering when it differs from PDF order.
    var pageLabel: String?
    var origin: RecordOrigin?
    var attachedAt: Date

    /// Defaults to `.autoDerived`: an attachment with no recorded origin was created by automatic
    /// matching, since manual attachment did not exist before this field. Note this is the opposite
    /// default from `LessonRecord.effectiveOrigin`, and deliberately so — there, guessing "teacher"
    /// protects work from deletion; here, guessing "teacher" would wrongly freeze a bad automatic
    /// attachment that a rebuild should be free to correct.
    var effectiveOrigin: RecordOrigin { origin ?? .autoDerived }

    /// Whether this attachment can contribute pages to a packet, as opposed to only a citation.
    var isMergeable: Bool { (pageRanges ?? []).contains(where: \.isValid) }
}
