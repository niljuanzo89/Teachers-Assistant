import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum WorkspaceTab: Hashable {
    case today, week, planning, sourceImport, workspace

    static var initialDesignCaptureTab: WorkspaceTab {
        switch ProcessInfo.processInfo.environment["LESSONPLANNER_INITIAL_TAB"]?.lowercased() {
        case "week", "this-week": .week
        case "planning", "planning-preview": .planning
        case "source", "source-import", "document-intake", "intake": .sourceImport
        case "workspace", "settings": .workspace
        default: .today
        }
    }
}

struct WorkspaceView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedTab: WorkspaceTab = WorkspaceTab.initialDesignCaptureTab
    @State private var isShowingProfileManager = false

    var body: some View {
        VStack(spacing: 12) {
            ActiveTeacherProfileBanner {
                isShowingProfileManager = true
            }
            if store.weeklyPlanningPromptStatus.isDue {
                WeeklyPlanningPromptBanner {
                    selectedTab = .week
                    store.markWeeklyPlanningPromptHandled()
                } dismiss: {
                    store.markWeeklyPlanningPromptHandled()
                }
            }
            TabView(selection: $selectedTab) {
                DailyPlanView()
                    .tabItem { Label("Today", systemImage: "calendar") }
                    .tag(WorkspaceTab.today)
                WeeklyPlannerView()
                    .tabItem { Label("This Week", systemImage: "calendar.badge.clock") }
                    .tag(WorkspaceTab.week)
                DraftLessonView()
                    .tabItem { Label("Planning Preview", systemImage: "doc.text") }
                    .tag(WorkspaceTab.planning)
                SourceImportView(selectedTab: $selectedTab)
                    .tabItem { Label("Document Intake", systemImage: "doc.viewfinder") }
                    .tag(WorkspaceTab.sourceImport)
                ConfigurationSummaryView()
                    .tabItem { Label("Workspace", systemImage: "folder") }
                    .tag(WorkspaceTab.workspace)
            }
        }
        .padding(20)
        .sheet(isPresented: $isShowingProfileManager) {
            LocalTeacherProfileManagerSheet()
                .environmentObject(store)
        }
    }
}

private struct ActiveTeacherProfileBanner: View {
    @EnvironmentObject private var store: AppStore
    var openProfileManager: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: store.activeTeacherProfile == nil ? "person.crop.circle" : "person.crop.circle.badge.checkmark")
                .foregroundStyle(store.activeTeacherProfile == nil ? Color.secondary : Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.activeTeacherProfile?.displayName ?? "Unprofiled local data")
                    .font(.headline)
                Text(profileDetail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(store.activeTeacherProfile == nil ? "Set up profile" : "Switch profile") {
                openProfileManager()
            }
        }
        .padding(10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var profileDetail: String {
        guard let activeProfile = store.activeTeacherProfile else {
            return "Single-user local workflow"
        }
        let gradeOrSubject = activeProfile.gradeOrSubject.isEmpty ? "No grade or subject set" : activeProfile.gradeOrSubject
        return "\(activeProfile.role) • \(gradeOrSubject) • Local testing profile"
    }
}

private struct LocalTeacherProfileManagerSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var newTeacherName = ""
    @State private var newTeacherRole = "Teacher"
    @State private var newTeacherGradeOrSubject = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Local test profiles")
                        .font(.title2.bold())
                    Text("Use these profiles to test separate teacher workspaces on this Mac.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            GroupBox("Active profile") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Use profile", selection: Binding<UUID?>(
                        get: { store.activeTeacherProfileID },
                        set: { selectedID in
                            let profile = selectedID.flatMap { id in store.teacherProfiles.first { $0.id == id } }
                            store.switchTeacherProfile(profile)
                        }
                    )) {
                        Text("Unprofiled local data").tag(UUID?.none)
                        ForEach(store.teacherProfiles) { profile in
                            Text(profile.displayName).tag(Optional(profile.id))
                        }
                    }
                    if let activeProfile = store.activeTeacherProfile {
                        Label("\(activeProfile.role) • \(activeProfile.gradeOrSubject.isEmpty ? "No grade or subject set" : activeProfile.gradeOrSubject)", systemImage: "person.crop.circle.badge.checkmark")
                            .foregroundStyle(Color.accentColor)
                    } else {
                        Label("Single-user local workflow", systemImage: "person.crop.circle")
                            .foregroundStyle(.secondary)
                    }
                    Text("Switching profiles reloads documents, pacing, lessons, weekly plans, and generated-output history from that profile's local cache.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            GroupBox("Create a test teacher") {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Teacher name", text: $newTeacherName)
                    TextField("Role", text: $newTeacherRole)
                    TextField("Grade or subject", text: $newTeacherGradeOrSubject)
                    HStack {
                        Button("Create and use profile") {
                            store.createLocalTeacherProfile(
                                displayName: newTeacherName,
                                role: newTeacherRole,
                                gradeOrSubject: newTeacherGradeOrSubject
                            )
                            newTeacherName = ""
                            newTeacherRole = "Teacher"
                            newTeacherGradeOrSubject = ""
                        }
                        .disabled(newTeacherName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Spacer()
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(24)
        .frame(minWidth: 520)
    }
}

private struct WeeklyPlanningPromptBanner: View {
    @EnvironmentObject private var store: AppStore
    var openWeeklyPlanner: () -> Void
    var dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.badge")
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Weekly planning prompt")
                    .font(.headline)
                if let duePromptDate = store.weeklyPlanningPromptStatus.duePromptDate {
                    Text("It is time to prepare the weekly package for \(duePromptDate, format: .dateTime.weekday(.wide).month().day().hour().minute()).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Open weekly planner", action: openWeeklyPlanner)
            Button("Dismiss", action: dismiss)
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct SourceImportView: View {
    @EnvironmentObject private var store: AppStore
    @Binding private var selectedTab: WorkspaceTab
    @State private var selectedSourceID: UUID?
    @State private var reviewedText = ""
    @State private var lessonTitle = ""
    @State private var lessonObjective = ""
    @State private var actionMessage: String?
    @State private var proposalJSON = ""
    @State private var isGeneratingCodexDraft = false

    private var selectedSource: ImportedSource? {
        store.importedSources.first { $0.id == selectedSourceID }
    }

    fileprivate init(selectedTab: Binding<WorkspaceTab>) {
        _selectedTab = selectedTab
    }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Document intake").font(.largeTitle.bold())
                    Spacer()
                    Button("Add documents…") { chooseDocumentItems() }
                }
                Text("Choose PDF or Word documents together, or select a folder. Readable files are sorted and used to update pacing and this week's plan automatically.")
                    .foregroundStyle(.secondary)
                Text("In the picker, use Command-click for separate files, or choose a folder to bring in everything supported inside it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ImportedSourceRoleSummaryView(sources: store.importedSources)
                List {
                    ForEach(store.importedSources, id: \.id) { source in
                        Button {
                            selectedSourceID = source.id
                            loadSelection(source.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(source.reference.displayName).lineLimit(1)
                                HStack {
                                    Text(source.effectiveSetupRole.displayName)
                                    Text("•")
                                    Text(source.extractionMethod.displayName)
                                }
                                .font(.caption)
                                .foregroundStyle(source.extractionMethod == .ocrRequired ? Color.orange : Color.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(selectedSourceID == source.id ? Color.accentColor.opacity(0.15) : Color.clear)
                    }
                }
            }
            .frame(width: 300)

            if let source = selectedSource {
                VStack(alignment: .leading, spacing: 12) {
                    Text(source.reference.displayName).font(.title2.bold())
                    Picker("Document role", selection: Binding(
                        get: { source.effectiveSetupRole },
                        set: { store.updateImportedSourceRole(id: source.id, role: $0) }
                    )) {
                        ForEach(ImportedSourceRole.allCases) { role in
                            Text(role.displayName).tag(role)
                        }
                    }
                    Text(source.effectiveSetupRole.supportsCoursePacing ? "This document can help build course pacing." : "This document will stay available for lesson planning, but will not drive course pacing.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    SourceReadinessView(report: SourceReadinessReport.analyze(source))
                    if source.extractionMethod == .ocrRequired {
                        ContentUnavailableView("OCR required", systemImage: "text.viewfinder", description: Text("This PDF contains no selectable text. Local OCR is the next Phase 2 slice; no lesson will be created from an empty extraction."))
                    } else {
                        if let confidence = source.confidence {
                            Text("OCR confidence: \(confidence, format: .percent.precision(.fractionLength(0))). Unreadable details may be omitted; edit the text only where needed.")
                                .foregroundStyle(.orange)
                        } else {
                            Text("Readable text is used automatically. Edit this text only if something important is missing or incorrect.").foregroundStyle(.secondary)
                        }
                        TextEditor(text: $reviewedText)
                            .font(.body.monospaced())
                            .border(.quaternary)
                        HStack {
                            Button("Save text edits") {
                                store.saveSourceReview(id: source.id, text: reviewedText)
                                actionMessage = "Text edits saved."
                            }
                            Text(source.extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No readable text" : "Ready to use")
                                .foregroundStyle(.secondary)
                        }
                        Divider()
                        TextField("Lesson title", text: $lessonTitle)
                        TextField("Learning objective (optional)", text: $lessonObjective)
                        Button("Create draft lesson from source") {
                            store.createDraftLesson(from: source, title: lessonTitle, objective: lessonObjective)
                            actionMessage = "Draft created. Opening Planning Preview…"
                            selectedTab = .planning
                        }
                        .disabled(source.extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        DisclosureGroup("Optional AI-assisted draft") {
                            Text("Personal workflow: this button sends the readable source text to your signed-in Codex CLI account, then creates an editable draft. Nothing is approved automatically.")
                                .font(.footnote).foregroundStyle(.secondary)
                            HStack {
                                Button("Generate AI draft with Codex CLI") { generateCodexDraft(source) }
                                    .disabled(source.extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGeneratingCodexDraft)
                                if isGeneratingCodexDraft { ProgressView().controlSize(.small) }
                            }
                            HStack {
                                Button("Copy JSON extraction prompt") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(store.lessonDraftPrompt(for: source), forType: .string)
                                    actionMessage = "Extraction prompt copied locally."
                                }
                                .disabled(source.extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                Button("Create draft from JSON") { createDraftFromProposal(source) }
                                    .disabled(proposalJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || source.extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                            TextEditor(text: $proposalJSON)
                                .font(.body.monospaced())
                                .frame(minHeight: 150)
                                .border(.quaternary)
                        }
                        if let actionMessage {
                            Label(actionMessage, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ContentUnavailableView("Choose setup documents", systemImage: "doc.badge.plus", description: Text("Add pacing guides, curriculum maps, calendars, assessment schedules, and lesson materials from files or a folder."))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func chooseDocumentItems() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = supportedDocumentTypes + [.folder]
        if panel.runModal() == .OK {
            store.importDocumentItems(panel.urls)
            selectedSourceID = store.importedSources.first?.id
            loadSelection(selectedSourceID)
            actionMessage = "Documents added. Readable setup documents updated pacing and this week's planner."
        }
    }

    private var supportedDocumentTypes: [UTType] {
        var types: [UTType] = [.pdf]
        if let docx = UTType(filenameExtension: "docx") {
            types.append(docx)
        }
        return types
    }

    private func loadSelection(_ id: UUID?) {
        guard let id, let source = store.importedSources.first(where: { $0.id == id }) else { return }
        reviewedText = source.extractedText
        lessonTitle = source.reference.displayName.replacingOccurrences(of: ".pdf", with: "", options: [.caseInsensitive])
        lessonObjective = ""
        actionMessage = nil
        proposalJSON = ""
    }

    private func createDraftFromProposal(_ source: ImportedSource) {
        do {
            let proposal = try JSONDecoder().decode(LessonDraftProposal.self, from: Data(proposalJSON.utf8))
            store.createDraftLesson(from: proposal, source: source)
            actionMessage = "AI-assisted draft created. Opening Planning Preview…"
            selectedTab = .planning
        } catch {
            actionMessage = "The pasted text is not valid lesson-draft JSON yet."
        }
    }

    private func generateCodexDraft(_ source: ImportedSource) {
        isGeneratingCodexDraft = true
        actionMessage = "Generating a draft with Codex CLI…"
        Task {
            do {
                let proposal = try await store.generateCodexDraft(from: source)
                store.createDraftLesson(from: proposal, source: source)
                actionMessage = "AI-assisted draft created. Opening Planning Preview…"
                selectedTab = .planning
            } catch {
                actionMessage = error.localizedDescription
            }
            isGeneratingCodexDraft = false
        }
    }
}

private struct ImportedSourceRoleSummaryView: View {
    var sources: [ImportedSource]

    private var report: ImportedSourceIntakeReport { ImportedSourceIntakeReport.analyze(sources) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(report.title, systemImage: report.canBuildCoursePacing ? "checkmark.circle" : "tray.and.arrow.down")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(report.canBuildCoursePacing ? Color.green : Color.primary)
            Text(report.pacingStatus)
                .font(.footnote)
                .foregroundStyle(report.canBuildCoursePacing ? Color.secondary : Color.orange)
            FlowRoleCounts(report: report)
        }
        .padding(10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct FlowRoleCounts: View {
    var report: ImportedSourceIntakeReport

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(ImportedSourceRole.allCases) { role in
                let count = report.roleCounts[role, default: 0]
                if count > 0 {
                    Text("\(role.displayName): \(count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct SourceReadinessView: View {
    var report: SourceReadinessReport

    private var tint: Color {
        switch report.level {
        case .readyForReview: .green
        case .carefulReviewRequired: .orange
        case .visualReviewRequired, .blocked: .red
        }
    }

    var body: some View {
        GroupBox("Source readiness") {
            VStack(alignment: .leading, spacing: 6) {
                Label(report.level.title, systemImage: report.level == .readyForReview ? "checkmark.circle" : "exclamationmark.triangle")
                    .foregroundStyle(tint)
                Text(report.summary).font(.footnote)
                if !report.risks.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Review focus")
                            .font(.footnote.weight(.semibold))
                        ForEach(report.risks) { risk in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(risk.title)
                                    .font(.footnote.weight(.semibold))
                                Text(risk.reviewInstruction)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                ForEach(report.checks, id: \.self) { check in
                    Text("• \(check)").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct DailyPlanView: View {
    @EnvironmentObject private var store: AppStore
    @State private var blockTitle = ""
    @State private var blockType = "Instruction"
    @State private var start = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: .now) ?? .now
    @State private var end = Calendar.current.date(bySettingHour: 8, minute: 45, second: 0, of: .now) ?? .now
    @State private var taskTitle = ""

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Today")
                    .font(.largeTitle.bold())
                Text(store.dailyPlan.date, format: .dateTime.weekday(.wide).month().day())
                    .foregroundStyle(.secondary)

                GroupBox("Schedule") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(store.dailyPlan.scheduleBlocks) { block in
                            HStack {
                                Text(block.start, format: .dateTime.hour().minute())
                                    .monospacedDigit()
                                Text(block.title).bold()
                                Spacer()
                                Text(block.type).foregroundStyle(.secondary)
                            }
                        }
                        Divider()
                        TextField("Block title", text: $blockTitle)
                        TextField("Block type", text: $blockType)
                        HStack {
                            DatePicker("Start", selection: $start, displayedComponents: .hourAndMinute)
                            DatePicker("End", selection: $end, displayedComponents: .hourAndMinute)
                            Button("Add") {
                                let title = blockTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !title.isEmpty else { return }
                                store.addScheduleBlock(title: title, start: start, end: end, type: blockType)
                                blockTitle = ""
                            }
                        }
                    }
                    .padding(4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 12) {
                Text("Checklist").font(.title2.bold())
                ForEach(store.dailyPlan.tasks) { task in
                    Toggle(isOn: Binding(
                        get: { task.status == .complete },
                        set: { _ in store.toggleTask(task) }
                    )) {
                        Text(task.title)
                    }
                }
                HStack {
                    TextField("Add a task", text: $taskTitle)
                    Button("Add") { store.addTask(title: taskTitle); taskTitle = "" }
                }
            }
            .frame(width: 300, alignment: .leading)
        }
    }
}

struct WeeklyPlannerView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedLessonID: UUID?
    @State private var selectedAssignmentID: UUID?
    @State private var planningWeekDate = Date.now
    @State private var lessonDate = Date.now
    @State private var start = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: .now) ?? .now
    @State private var end = Calendar.current.date(bySettingHour: 8, minute: 45, second: 0, of: .now) ?? .now
    @State private var assignmentPlanningNotes = ""
    @State private var editLessonDate = Date.now
    @State private var editStart = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: .now) ?? .now
    @State private var editEnd = Calendar.current.date(bySettingHour: 8, minute: 45, second: 0, of: .now) ?? .now
    @State private var editAssignmentPlanningNotes = ""
    @State private var teacherFocus = ""
    @State private var preparationNotes = ""
    @State private var studentSupportNotes = ""
    @State private var weeklyCheckInNote = ""
    @State private var latestOutput: GeneratedOutputRecord?
    @State private var isGeneratingWeeklyPackage = false
    @State private var generatingWeeklyOutputKeys: Set<String> = []
    @State private var pacingActionMessage: String?

    private var approvedLessons: [LessonRecord] { store.lessons.filter { $0.status == .approved } }
    private var readiness: WeeklyPackageReadinessReport { store.weeklyPackageReadinessReport }

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                Text("This week").font(.largeTitle.bold())
                Text("Week of \(store.weeklyPlan.weekOf, format: .dateTime.month().day().year())")
                    .foregroundStyle(.secondary)
                Text("Imported planning documents can populate this week automatically. Use this page to adjust lesson timing, notes, and the weekly package.")
                    .foregroundStyle(.secondary)
                Label("Weekly prompt: \(store.weeklyPlanningPromptPreference.summary)", systemImage: store.weeklyPlanningPromptPreference.isEnabled ? "bell" : "bell.slash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let nextPromptDate = store.weeklyPlanningPromptPreference.nextPromptDate(after: .now) {
                    Text("Next prompt target: \(nextPromptDate, format: .dateTime.weekday(.wide).month().day().hour().minute()).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                DatePicker("Planning week", selection: $planningWeekDate, displayedComponents: .date)
                    .onChange(of: planningWeekDate) { _, date in
                        store.setWeeklyPlanWeek(of: date)
                        lessonDate = store.weeklyPlan.weekOf
                        loadPlanningBrief()
                        loadWeeklyPacingRefinement()
                    }
                WeeklyPackageReadinessView(report: readiness)
                WeeklyPacingSuggestionView(report: store.weeklyPacingSuggestionReport) { suggestion in
                    applyPacingSuggestion(suggestion)
                } createDraft: { suggestion in
                    store.createDraftLesson(from: suggestion)
                    pacingActionMessage = "Draft lesson created from pacing. Review and approve it before scheduling."
                }
                if let pacingActionMessage {
                    Label(pacingActionMessage, systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                }

                GroupBox("Weekly pacing check-in") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("What changed this week?", text: $weeklyCheckInNote, axis: .vertical)
                            .lineLimit(2...4)
                        Button("Draft pacing refinement") {
                            store.proposeWeeklyPacingRefinement(from: weeklyCheckInNote)
                            loadWeeklyPacingRefinement()
                        }
                        .disabled(weeklyCheckInNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if let proposal = store.weeklyPlan.pacingRefinementProposal {
                            VStack(alignment: .leading, spacing: 4) {
                                Label(proposal.status.displayName, systemImage: proposal.status == .accepted ? "checkmark.circle" : "pencil.and.list.clipboard")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(proposal.status == .accepted ? Color.green : Color.secondary)
                                Text(proposal.proposedAdjustmentSummary)
                                    .font(.footnote.weight(.semibold))
                                if let affectedPacingArea = proposal.affectedPacingArea {
                                    Text("Area: \(affectedPacingArea)")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                if let suggestedDateShiftDays = proposal.suggestedDateShiftDays {
                                    Text("Suggested shift: \(suggestedDateShiftDays) instructional day(s)")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Text(proposal.pacingImpactNotes)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                if proposal.status == .draft {
                                    Button("Accept pacing refinement") {
                                        store.acceptWeeklyPacingRefinement()
                                        loadWeeklyPacingRefinement()
                                    }
                                }
                            }
                        }
                    }
                    .padding(4)
                }

                GroupBox("Weekly planning brief") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Teacher focus for the week", text: $teacherFocus, axis: .vertical)
                        TextField("Preparation notes", text: $preparationNotes, axis: .vertical)
                        TextField("Student support notes", text: $studentSupportNotes, axis: .vertical)
                        Button("Save weekly brief") {
                            store.updateWeeklyPlanningBrief(
                                teacherFocus: teacherFocus,
                                preparationNotes: preparationNotes,
                                studentSupportNotes: studentSupportNotes
                            )
                        }
                    }
                    .padding(4)
                }

                GroupBox("Schedule an approved lesson") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Lesson", selection: $selectedLessonID) {
                            Text("Choose an approved lesson").tag(UUID?.none)
                            ForEach(approvedLessons) { lesson in
                                Text(lesson.title).tag(Optional(lesson.id))
                            }
                        }
                        DatePicker("Lesson day", selection: $lessonDate, displayedComponents: .date)
                        HStack {
                            DatePicker("Start", selection: $start, displayedComponents: .hourAndMinute)
                            DatePicker("End", selection: $end, displayedComponents: .hourAndMinute)
                        }
                        TextField("Weekly note for this lesson", text: $assignmentPlanningNotes, axis: .vertical)
                        if end <= start {
                            Label("End time must be after start time.", systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                        Button("Add to weekly plan") {
                            guard let selectedLessonID else { return }
                            store.addWeeklyAssignment(
                                lessonID: selectedLessonID,
                                date: lessonDate,
                                start: start,
                                end: end,
                                planningNotes: assignmentPlanningNotes
                            )
                            assignmentPlanningNotes = ""
                        }
                        .disabled(selectedLessonID == nil || end <= start)
                    }
                    .padding(4)
                }

                if let selectedAssignment {
                    GroupBox("Edit scheduled lesson") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(lessonTitle(for: selectedAssignment))
                                .font(.footnote.weight(.semibold))
                            DatePicker("Lesson day", selection: $editLessonDate, displayedComponents: .date)
                            HStack {
                                DatePicker("Start", selection: $editStart, displayedComponents: .hourAndMinute)
                                DatePicker("End", selection: $editEnd, displayedComponents: .hourAndMinute)
                            }
                            TextField("Weekly note for this lesson", text: $editAssignmentPlanningNotes, axis: .vertical)
                            if editEnd <= editStart {
                                Label("End time must be after start time.", systemImage: "exclamationmark.triangle")
                                    .font(.footnote)
                                    .foregroundStyle(.orange)
                            }
                            HStack {
                                Button("Save scheduled lesson") {
                                    store.updateWeeklyAssignment(
                                        selectedAssignment,
                                        date: editLessonDate,
                                        start: editStart,
                                        end: editEnd,
                                        planningNotes: editAssignmentPlanningNotes
                                    )
                                    loadSelectedAssignment()
                                }
                                .disabled(editEnd <= editStart)
                                Button("Cancel") { selectedAssignmentID = nil }
                            }
                        }
                        .padding(4)
                    }
                }

                HStack {
                    Button("Generate weekly package") {
                        isGeneratingWeeklyPackage = true
                        Task {
                            latestOutput = await store.generateWeeklyPackageHTML()
                            isGeneratingWeeklyPackage = false
                        }
                    }
                    .disabled(isGeneratingWeeklyPackage || !readiness.canGenerate)
                    if isGeneratingWeeklyPackage { ProgressView().controlSize(.small) }
                    if let latestOutput {
                        Label("Created \(latestOutput.displayName)", systemImage: "checkmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.green)
                        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: latestOutput.filePath)]) }
                    }
                }
            }
            .frame(width: 420, alignment: .leading)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Weekly plan").font(.title2.bold())
                    Spacer()
                    Text("\(store.weeklyPlan.assignments.count) lesson(s)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if store.weeklyPlan.assignments.isEmpty {
                    ContentUnavailableView("No lessons scheduled", systemImage: "calendar.badge.plus", description: Text("Add planning documents in Document Intake; readable files can populate this week automatically."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    WeeklyPlanningGridView(
                        days: weekDays,
                        assignments: store.weeklyPlan.assignments,
                        selectedAssignmentID: selectedAssignmentID,
                        lessonTitle: lessonTitle(for:),
                        outputLinks: outputLinks(for:),
                        isGeneratingOutput: isGeneratingWeeklyOutput(assignment:kind:),
                        outputAction: handleWeeklyOutputAction(assignment:kind:),
                        editAssignment: { assignment in
                            selectedAssignmentID = assignment.id
                            loadSelectedAssignment()
                        },
                        removeAssignment: { assignment in
                            store.removeWeeklyAssignment(assignment)
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            store.refreshWeeklyPlannerFromReadableDocuments()
            planningWeekDate = store.weeklyPlan.weekOf
            lessonDate = store.weeklyPlan.weekOf
            selectedLessonID = approvedLessons.first?.id
            loadPlanningBrief()
            loadWeeklyPacingRefinement()
        }
        .onChange(of: selectedAssignmentID) { _, _ in loadSelectedAssignment() }
    }

    private var selectedAssignment: WeeklyLessonAssignment? {
        guard let selectedAssignmentID else { return nil }
        return store.weeklyPlan.assignments.first { $0.id == selectedAssignmentID }
    }

    private var weekDays: [Date] {
        (0..<5).compactMap { offset in
            Calendar.current.date(byAdding: .day, value: offset, to: store.weeklyPlan.weekOf)
        }
    }

    private func lessonTitle(for assignment: WeeklyLessonAssignment) -> String {
        store.lessons.first(where: { $0.id == assignment.lessonRecordID })?.title ?? "Lesson no longer available"
    }

    private func outputLinks(for assignment: WeeklyLessonAssignment) -> LessonOutputLinkSet {
        LessonOutputLinkSet.latest(for: assignment.lessonRecordID, in: store.generatedOutputs)
    }

    private func lesson(for assignment: WeeklyLessonAssignment) -> LessonRecord? {
        store.lessons.first { $0.id == assignment.lessonRecordID }
    }

    private func isGeneratingWeeklyOutput(assignment: WeeklyLessonAssignment, kind: GeneratedOutputKind) -> Bool {
        generatingWeeklyOutputKeys.contains(weeklyOutputKey(assignment: assignment, kind: kind))
    }

    private func handleWeeklyOutputAction(assignment: WeeklyLessonAssignment, kind: GeneratedOutputKind) {
        let links = outputLinks(for: assignment)
        if let output = links.output(for: kind) {
            NSWorkspace.shared.open(URL(fileURLWithPath: output.filePath))
            return
        }
        guard let lesson = lesson(for: assignment) else { return }
        let key = weeklyOutputKey(assignment: assignment, kind: kind)
        generatingWeeklyOutputKeys.insert(key)
        switch kind {
        case .lessonPlanHTML:
            latestOutput = store.generateLessonPlanHTML(for: lesson)
            generatingWeeklyOutputKeys.remove(key)
        case .differentiationGuideHTML:
            latestOutput = store.generateDifferentiationGuideHTML(for: lesson)
            generatingWeeklyOutputKeys.remove(key)
        case .slideDeckPPTX:
            Task {
                latestOutput = await store.generateSlideDeckPPTX(for: lesson)
                generatingWeeklyOutputKeys.remove(key)
            }
        case .weeklyPlanHTML:
            generatingWeeklyOutputKeys.remove(key)
        }
    }

    private func weeklyOutputKey(assignment: WeeklyLessonAssignment, kind: GeneratedOutputKind) -> String {
        "\(assignment.id.uuidString)-\(kind.rawValue)"
    }

    private func loadPlanningBrief() {
        let brief = store.weeklyPlan.planningBrief ?? .empty
        teacherFocus = brief.teacherFocus
        preparationNotes = brief.preparationNotes
        studentSupportNotes = brief.studentSupportNotes
    }

    private func loadWeeklyPacingRefinement() {
        weeklyCheckInNote = store.weeklyPlan.pacingRefinementProposal?.checkInNote ?? ""
    }

    private func loadSelectedAssignment() {
        guard let selectedAssignment else { return }
        editLessonDate = selectedAssignment.date
        editStart = selectedAssignment.start
        editEnd = selectedAssignment.end
        editAssignmentPlanningNotes = selectedAssignment.planningNotes ?? ""
    }

    private func applyPacingSuggestion(_ suggestion: WeeklyPacingSuggestion) {
        guard let lessonRecordID = suggestion.lessonRecordID else { return }
        selectedLessonID = lessonRecordID
        lessonDate = suggestion.suggestedDate
        assignmentPlanningNotes = suggestion.planningNote
    }
}

private struct WeeklyPackageReadinessView: View {
    var report: WeeklyPackageReadinessReport

    var body: some View {
        GroupBox("Weekly package readiness") {
            VStack(alignment: .leading, spacing: 6) {
                Label(report.title, systemImage: report.canGenerate ? "checkmark.circle" : "exclamationmark.triangle")
                    .foregroundStyle(report.canGenerate ? Color.green : Color.orange)
                Text("\(report.completeOutputLessonCount) of \(report.scheduledLessonCount) scheduled lessons already have all three outputs.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                WeeklyOutputSummaryView(summary: report.outputSummary)
                ForEach(report.issues) { issue in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(issue.title)
                            .font(.footnote.weight(.semibold))
                        Text(issue.instruction)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct WeeklyPacingSuggestionView: View {
    var report: WeeklyPacingSuggestionReport
    var useSuggestion: (WeeklyPacingSuggestion) -> Void
    var createDraft: (WeeklyPacingSuggestion) -> Void

    var body: some View {
        GroupBox("Pacing suggestions") {
            VStack(alignment: .leading, spacing: 8) {
                Label(report.title, systemImage: report.canSuggestFromPacing ? "point.topleft.down.curvedto.point.bottomright.up" : "calendar.badge.exclamationmark")
                    .foregroundStyle(report.canSuggestFromPacing ? Color.secondary : Color.orange)
                Text(report.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ForEach(report.suggestions) { suggestion in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(suggestion.pacingLessonTitle)
                                .font(.footnote.weight(.semibold))
                            Text("\(suggestion.unitTitle) / \(suggestion.moduleTitle)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(suggestion.suggestedDate, format: .dateTime.weekday(.wide).month().day()) • \(suggestion.status.displayName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let lessonRecordTitle = suggestion.lessonRecordTitle {
                                Text("Matches approved lesson: \(lessonRecordTitle)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if suggestion.status == .readyToSchedule {
                            Button("Use") { useSuggestion(suggestion) }
                        } else if suggestion.status == .needsApprovedLesson {
                            Button("Create draft") { createDraft(suggestion) }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct WeeklyOutputSummaryView: View {
    var summary: WeeklyOutputSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(summary.generationLine)
                .font(.footnote)
                .foregroundStyle(summary.missingOutputCount == 0 ? Color.secondary : Color.orange)
            HStack(spacing: 10) {
                summaryPill("Plan", count: summary.lessonPlanCount)
                summaryPill("Deck", count: summary.slideDeckCount)
                summaryPill("Guide", count: summary.differentiationGuideCount)
            }
        }
    }

    private func summaryPill(_ title: String, count: Int) -> some View {
        Text("\(title) \(count)/\(summary.scheduledLessonCount)")
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.12), in: Capsule())
            .foregroundStyle(.secondary)
    }
}

private struct WeeklyPlanningGridView: View {
    private enum Metrics {
        static let timeColumnWidth: CGFloat = 104
        static let dayColumnWidth: CGFloat = 260
        static let headerHeight: CGFloat = 64
        /// Rows size themselves to their tallest cell. This is only the floor for a
        /// sparse or empty row so the grid keeps a readable rhythm.
        static let minRowHeight: CGFloat = 88
    }

    var days: [Date]
    var assignments: [WeeklyLessonAssignment]
    var selectedAssignmentID: UUID?
    var lessonTitle: (WeeklyLessonAssignment) -> String
    var outputLinks: (WeeklyLessonAssignment) -> LessonOutputLinkSet
    var isGeneratingOutput: (WeeklyLessonAssignment, GeneratedOutputKind) -> Bool
    var outputAction: (WeeklyLessonAssignment, GeneratedOutputKind) -> Void
    var editAssignment: (WeeklyLessonAssignment) -> Void
    var removeAssignment: (WeeklyLessonAssignment) -> Void

    var body: some View {
        // Built once per redraw and passed down. Rebuilding it per cell would re-cluster
        // every assignment for every day column.
        let layout = WeeklyGridLayout(assignments: assignments)

        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    WeeklyPlanningHeaderCell(title: "Time", width: Metrics.timeColumnWidth, height: Metrics.headerHeight)
                    ForEach(days, id: \.self) { day in
                        WeeklyPlanningHeaderCell(
                            title: day.formatted(.dateTime.weekday(.wide)),
                            subtitle: day.formatted(.dateTime.month().day()),
                            width: Metrics.dayColumnWidth,
                            height: Metrics.headerHeight
                        )
                    }
                }

                if layout.slots.isEmpty {
                    HStack(spacing: 0) {
                        WeeklyPlanningTimeCell(text: "", width: Metrics.timeColumnWidth, minHeight: Metrics.minRowHeight)
                        Text("No lessons have been scheduled for this week.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(width: Metrics.dayColumnWidth * CGFloat(days.count), alignment: .center)
                            .frame(minHeight: Metrics.minRowHeight, alignment: .center)
                            .border(Color.secondary.opacity(0.28), width: 0.5)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(layout.slots) { slot in
                        HStack(alignment: .top, spacing: 0) {
                            WeeklyPlanningTimeCell(
                                text: slot.label,
                                width: Metrics.timeColumnWidth,
                                minHeight: Metrics.minRowHeight
                            )
                            ForEach(days, id: \.self) { day in
                                WeeklyPlanningTableCell(
                                    assignments: layout.assignments(
                                        from: assignments,
                                        forDay: day,
                                        slot: slot,
                                        titleForSorting: lessonTitle
                                    ),
                                    width: Metrics.dayColumnWidth,
                                    minHeight: Metrics.minRowHeight,
                                    selectedAssignmentID: selectedAssignmentID,
                                    lessonTitle: lessonTitle,
                                    outputLinks: outputLinks,
                                    isGeneratingOutput: isGeneratingOutput,
                                    outputAction: outputAction,
                                    editAssignment: editAssignment,
                                    removeAssignment: removeAssignment
                                )
                            }
                        }
                        // Let the row take the intrinsic height of its tallest cell instead of a
                        // fixed height that clipped crowded cells and padded sparse ones.
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .overlay {
                Rectangle()
                    .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
            }
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

}

private struct WeeklyPlanningHeaderCell: View {
    var title: String
    var subtitle: String?
    var width: CGFloat
    var height: CGFloat

    init(title: String, subtitle: String? = nil, width: CGFloat, height: CGFloat) {
        self.title = title
        self.subtitle = subtitle
        self.width = width
        self.height = height
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.title3.weight(.semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 9)
        .frame(width: width, alignment: .topLeading)
        .frame(height: height, alignment: .topLeading)
        .background(Color(red: 0.92, green: 0.95, blue: 0.96))
        .border(Color.secondary.opacity(0.35), width: 0.5)
    }
}

private struct WeeklyPlanningTimeCell: View {
    var text: String
    var width: CGFloat
    var minHeight: CGFloat

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color(red: 0.0, green: 0.41, blue: 0.53))
            .multilineTextAlignment(.leading)
            .padding(9)
            .frame(width: width, alignment: .topLeading)
            // minHeight keeps sparse rows readable; maxHeight lets the border stretch to
            // match the tallest cell in the row.
            .frame(minHeight: minHeight, maxHeight: .infinity, alignment: .topLeading)
            .border(Color.secondary.opacity(0.35), width: 0.5)
    }
}

private struct WeeklyPlanningTableCell: View {
    var assignments: [WeeklyLessonAssignment]
    var width: CGFloat
    var minHeight: CGFloat
    var selectedAssignmentID: UUID?
    var lessonTitle: (WeeklyLessonAssignment) -> String
    var outputLinks: (WeeklyLessonAssignment) -> LessonOutputLinkSet
    var isGeneratingOutput: (WeeklyLessonAssignment, GeneratedOutputKind) -> Bool
    var outputAction: (WeeklyLessonAssignment, GeneratedOutputKind) -> Void
    var editAssignment: (WeeklyLessonAssignment) -> Void
    var removeAssignment: (WeeklyLessonAssignment) -> Void

    var body: some View {
        Group {
            if assignments.isEmpty {
                Color.clear
            } else {
                // A plain VStack, not a nested ScrollView: the cell now grows to fit its
                // cards, so nothing is clipped and the scroll wheel keeps reaching the
                // surrounding grid instead of being captured per cell.
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(assignments) { assignment in
                        WeeklyAssignmentCompactCard(
                            assignment: assignment,
                            isSelected: selectedAssignmentID == assignment.id,
                            title: lessonTitle(assignment),
                            links: outputLinks(assignment),
                            isGeneratingOutput: { kind in isGeneratingOutput(assignment, kind) },
                            outputAction: { kind in outputAction(assignment, kind) },
                            editAssignment: { editAssignment(assignment) },
                            removeAssignment: { removeAssignment(assignment) }
                        )
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: width, alignment: .topLeading)
        .frame(minHeight: minHeight, maxHeight: .infinity, alignment: .topLeading)
        .border(Color.secondary.opacity(0.35), width: 0.5)
    }
}

private struct WeeklyAssignmentCompactCard: View {
    var assignment: WeeklyLessonAssignment
    var isSelected: Bool
    var title: String
    var links: LessonOutputLinkSet
    var isGeneratingOutput: (GeneratedOutputKind) -> Bool
    var outputAction: (GeneratedOutputKind) -> Void
    var editAssignment: () -> Void
    var removeAssignment: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button(action: editAssignment) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 6) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 4)
                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let notes = assignment.planningNotes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if assignment.end <= assignment.start {
                        Label("Invalid time", systemImage: "exclamationmark.triangle")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .buttonStyle(.plain)
            .help("Click to edit this scheduled lesson")

            HStack(spacing: 8) {
                WeeklyAssignmentOutputControlsView(
                    links: links,
                    isGenerating: isGeneratingOutput,
                    action: outputAction
                )
                Spacer(minLength: 4)
                HStack(spacing: 8) {
                    Button(action: editAssignment) {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.plain)
                    .help("Edit scheduled lesson")

                    Button(role: .destructive, action: removeAssignment) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .help("Remove from week")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .contain)
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.white.opacity(0.001))
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.18), lineWidth: isSelected ? 1.5 : 0.5)
        }
    }
}

private struct WeeklyAssignmentOutputControlsView: View {
    var links: LessonOutputLinkSet
    var isGenerating: (GeneratedOutputKind) -> Bool
    var action: (GeneratedOutputKind) -> Void

    var body: some View {
        HStack(spacing: 6) {
            outputButton("Plan", kind: .lessonPlanHTML, isReady: links.lessonPlanHTML != nil)
            outputButton("Deck", kind: .slideDeckPPTX, isReady: links.slideDeckPPTX != nil)
            outputButton("Guide", kind: .differentiationGuideHTML, isReady: links.differentiationGuideHTML != nil)
        }
        .font(.caption2)
    }

    private func outputButton(_ title: String, kind: GeneratedOutputKind, isReady: Bool) -> some View {
        Button {
            action(kind)
        } label: {
            Label(title, systemImage: isGenerating(kind) ? "clock" : (isReady ? "checkmark.circle" : "plus.circle"))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(isReady ? Color.green.opacity(0.10) : Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 4))
        .foregroundStyle(isReady ? Color.green : Color.accentColor)
        .disabled(isGenerating(kind))
        .help(isReady ? "Open \(title)" : "Generate \(title)")
    }
}

private extension LessonOutputLinkSet {
    func output(for kind: GeneratedOutputKind) -> GeneratedOutputRecord? {
        switch kind {
        case .lessonPlanHTML: lessonPlanHTML
        case .slideDeckPPTX: slideDeckPPTX
        case .differentiationGuideHTML: differentiationGuideHTML
        case .weeklyPlanHTML: nil
        }
    }
}

struct DraftLessonView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedLessonID: UUID?
    @State private var lesson: LessonRecord?
    @State private var materialsText = ""
    @State private var newStepTitle = ""
    @State private var newStepNotes = ""
    @State private var printablePrompt = ""
    @State private var latestOutput: GeneratedOutputRecord?
    @State private var isGeneratingSlideDeck = false

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Lessons").font(.title.bold())
                    Spacer()
                    Button("New") {
                        store.saveDraftLesson(title: "Untitled lesson", objective: "")
                    }
                }
                List(store.lessons, selection: $selectedLessonID) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title).lineLimit(1)
                        Text(item.status.rawValue.capitalized)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(item.id)
                }
                .onChange(of: selectedLessonID) { _, id in loadLesson(id) }
            }
            .frame(width: 250)

            Divider()

            if let binding = lessonBinding {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("Lesson editor").font(.largeTitle.bold())
                        Spacer()
                        Picker("Status", selection: binding.status) {
                            Text("Draft").tag(LessonStatus.draft)
                            Text("Reviewed").tag(LessonStatus.reviewed)
                            Text("Approved").tag(LessonStatus.approved)
                        }
                        .frame(width: 180)
                    }
                    Text("Edit and review this record before output generation. It remains local and traceable to its source.")
                        .foregroundStyle(.secondary)

                    if binding.sourceTextSnapshot.wrappedValue?.isEmpty == false {
                        Button("Fill empty fields from labeled source text") {
                            let updated = store.fillEmptyLessonFieldsFromSource(binding.wrappedValue)
                            lesson = updated
                            materialsText = updated.materials.joined(separator: "\n")
                        }
                        .help("Uses only explicit labels such as Objective, Materials, Assessment, or Differentiation. It does not infer missing content.")
                    }

                    if let warnings = binding.aiReviewWarnings.wrappedValue, !warnings.isEmpty {
                        GroupBox("AI review warnings") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(warnings, id: \.self) { warning in
                                    Label(warning, systemImage: "exclamationmark.triangle")
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }

                    GroupBox("Core lesson") {
                        VStack(alignment: .leading, spacing: 12) {
                        TextField("Lesson title", text: binding.title)
                        TextField("Subject", text: binding.subject)
                        TextField("Grade or age range", text: binding.gradeOrAgeRange)
                        TextField("Learning objective", text: binding.objective, axis: .vertical)
                        }
                    }

                    GroupBox("Instructional sequence") {
                        VStack(alignment: .leading, spacing: 12) {
                        ForEach(binding.instructionalSequence.wrappedValue, id: \.id) { step in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.title).bold()
                                if !step.notes.isEmpty { Text(step.notes).foregroundStyle(.secondary) }
                            }
                        }
                        TextField("Step title", text: $newStepTitle)
                        TextField("Step notes", text: $newStepNotes)
                        Button("Add step") { addStep() }
                            .disabled(newStepTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }

                    GroupBox("Materials and assessment") {
                        VStack(alignment: .leading, spacing: 12) {
                        TextField("Materials (one per line)", text: $materialsText, axis: .vertical)
                        TextField("Assessment or success check", text: binding.assessmentSummary, axis: .vertical)
                        }
                    }

                    GroupBox("Differentiation") {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Scaffolds, groups, extensions, and printable resources", text: binding.differentiationSummary, axis: .vertical)
                            TextField("Student printable prompt (optional)", text: $printablePrompt, axis: .vertical)
                        }
                    }

                    GroupBox("Source provenance") {
                        if binding.sourceReferences.wrappedValue.isEmpty {
                            Text("This is a manually created lesson record.").foregroundStyle(.secondary)
                        } else {
                            ForEach(binding.sourceReferences.wrappedValue, id: \.self) { source in
                            Text(source).font(.footnote).textSelection(.enabled)
                            }
                        }
                    }

                    LessonOutputControls(
                        lesson: binding,
                        latestOutput: $latestOutput,
                        isGeneratingSlideDeck: $isGeneratingSlideDeck,
                        saveLesson: saveLesson
                    )
                    if let currentOutput = latestOutput {
                        OutputReviewRow(output: currentOutput) { reviewed in
                            latestOutput = reviewed
                        }
                    }
                }
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ContentUnavailableView("Select or create a lesson", systemImage: "book.closed", description: Text("Imported sources become editable lesson records here."))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { selectMostRecentLesson() }
        .onChange(of: store.mostRecentLessonID) { _, id in
            guard let id else { return }
            selectedLessonID = id
            loadLesson(id)
        }
        .onChange(of: store.lessons.count) { _, _ in
            guard let id = store.mostRecentLessonID else { return }
            selectedLessonID = id
            loadLesson(id)
        }
    }

    private var lessonBinding: Binding<LessonRecord>? {
        guard lesson != nil else { return nil }
        return Binding(
            get: { lesson ?? LessonRecord.draft() },
            set: { lesson = $0 }
        )
    }

    private func selectMostRecentLesson() {
        let id = store.mostRecentLessonID ?? store.lessons.last?.id
        selectedLessonID = id
        loadLesson(id)
    }

    private func loadLesson(_ id: UUID?) {
        guard let id, let stored = store.lessons.first(where: { $0.id == id }) else {
            lesson = nil
            return
        }
        lesson = stored
        materialsText = stored.materials.joined(separator: "\n")
        newStepTitle = ""
        newStepNotes = ""
        printablePrompt = stored.printableResourcePrompt ?? ""
        latestOutput = nil
    }

    private func addStep() {
        guard var updated = lesson else { return }
        let title = newStepTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        updated.instructionalSequence.append(InstructionalStep(id: UUID(), title: title, notes: newStepNotes.trimmingCharacters(in: .whitespacesAndNewlines)))
        lesson = updated
        newStepTitle = ""
        newStepNotes = ""
    }

    private func saveLesson() {
        guard var updated = lesson else { return }
        updated.materials = materialsText
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        updated.printableResourcePrompt = printablePrompt
        lesson = updated
        store.updateLesson(updated)
    }
}

private struct LessonExportReadinessView: View {
    var report: LessonExportReadinessReport

    var body: some View {
        GroupBox("Export readiness") {
            VStack(alignment: .leading, spacing: 8) {
                Label(report.title, systemImage: report.isReady ? "checkmark.circle" : "exclamationmark.triangle")
                    .foregroundStyle(report.isReady ? Color.secondary : Color.orange)
                if !report.blockingIssues.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Required before output")
                            .font(.footnote.weight(.semibold))
                        ForEach(report.blockingIssues) { issue in
                            readinessRow(issue)
                        }
                    }
                }
                if !report.advisoryIssues.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Review before sharing")
                            .font(.footnote.weight(.semibold))
                        ForEach(report.advisoryIssues) { issue in
                            readinessRow(issue)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func readinessRow(_ issue: LessonExportReadinessIssue) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(issue.title)
                .font(.footnote.weight(.semibold))
            Text(issue.instruction)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct LessonOutputControls: View {
    @EnvironmentObject private var store: AppStore
    @Binding var lesson: LessonRecord
    @Binding var latestOutput: GeneratedOutputRecord?
    @Binding var isGeneratingSlideDeck: Bool
    var saveLesson: () -> Void
    private var readiness: LessonExportReadinessReport { LessonExportReadinessReport.analyze(lesson) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LessonExportReadinessView(report: readiness)
            HStack {
                Button("Save lesson") { saveLesson() }
                if lesson.status != .approved {
                    Button("Mark approved") {
                        lesson.status = .approved
                        saveLesson()
                    }
                }
                Button("Generate HTML plan") {
                    saveLesson()
                    latestOutput = store.generateLessonPlanHTML(for: lesson)
                }
                .disabled(lesson.status != .approved || !readiness.isReady)
                Button("Generate differentiation guide") {
                    saveLesson()
                    latestOutput = store.generateDifferentiationGuideHTML(for: lesson)
                }
                .disabled(lesson.status != .approved || !readiness.isReady)
                Button("Generate PowerPoint deck") {
                    saveLesson()
                    let approvedLesson = lesson
                    isGeneratingSlideDeck = true
                    Task {
                        latestOutput = await store.generateSlideDeckPPTX(for: approvedLesson)
                        isGeneratingSlideDeck = false
                    }
                }
                .disabled(lesson.status != .approved || !readiness.isReady || isGeneratingSlideDeck || !store.slideDeckAvailability.isAvailable)
                if isGeneratingSlideDeck { ProgressView().controlSize(.small) }
            }
            Label(store.slideDeckAvailability.title, systemImage: store.slideDeckAvailability.isAvailable ? "checkmark.circle" : "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(store.slideDeckAvailability.isAvailable ? Color.secondary : Color.orange)
            Text(store.slideDeckAvailability.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let template = store.activePresentationTemplate {
                Label("Using presentation template: \(template.displayName)", systemImage: "rectangle.on.rectangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct PresentationTemplateReadinessView: View {
    var report: PresentationTemplateReadinessReport

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(report.title, systemImage: report.canUseTemplateMetadata ? "checkmark.circle" : "exclamationmark.triangle")
                .foregroundStyle(report.canUseTemplateMetadata ? Color.green : Color.orange)
            if let template = report.template {
                Text(template.displayName)
                    .font(.footnote.weight(.semibold))
                Text("\(report.mappedFieldCount) mapped fields, \(report.requiredMappedFieldCount) required mappings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("\(report.inventorySlideCount) inventoried slides, \(report.frameMapCount) frame-map entries.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(report.issues) { issue in
                VStack(alignment: .leading, spacing: 2) {
                    Text(issue.title)
                        .font(.footnote.weight(.semibold))
                    Text(issue.instruction)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct CoursePacingReadinessView: View {
    var report: CoursePacingReadinessReport

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(report.title, systemImage: report.canGovernWeeklyPlanning ? "checkmark.circle" : "exclamationmark.triangle")
                .foregroundStyle(report.canGovernWeeklyPlanning ? Color.green : Color.orange)
            Text("\(report.unitCount) units, \(report.moduleCount) modules, \(report.lessonCount) lessons, \(report.estimatedInstructionalDays) estimated instructional days.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ForEach(report.issues) { issue in
                VStack(alignment: .leading, spacing: 2) {
                    Text(issue.title)
                        .font(.footnote.weight(.semibold))
                    Text(issue.instruction)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct LocalWorkflowQAView: View {
    var report: LocalWorkflowQAReport

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                report.isReadyForEndToEndQA ? "Ready for local end-to-end QA" : "Local QA steps remaining",
                systemImage: report.isReadyForEndToEndQA ? "checkmark.seal" : "checklist"
            )
            .foregroundStyle(report.isReadyForEndToEndQA ? Color.green : Color.orange)
            ForEach(report.items) { item in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.footnote.weight(.semibold))
                        Text(item.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: item.status == .ready ? "checkmark.circle" : "circle")
                        .foregroundStyle(item.status == .ready ? Color.green : Color.orange)
                }
            }
        }
    }
}

private struct PacingSummaryLine: View {
    var title: String
    var detail: String
    var systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
        }
    }
}

private struct CoursePacingUnitSummaryRow: View {
    var unit: CoursePacingUnit
    var isSelected: Bool
    var edit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(unit.title)
                    .font(.footnote.weight(.semibold))
                Text("\(unit.modules.count) modules, \(unit.modules.flatMap(\.lessons).count) lessons, \(unit.estimatedInstructionalDays) estimated days")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(dateSummary(startDate: unit.startDate, endDate: unit.endDate))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if !unit.assessmentWindows.isEmpty {
                    Text("Assessments: \(unit.assessmentWindows.joined(separator: ", "))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Button(isSelected ? "Editing" : "Edit") { edit() }
                .disabled(isSelected)
        }
        .padding(.vertical, 4)
    }
}

private struct SelectedCoursePacingUnitHeader: View {
    var unit: CoursePacingUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(unit.title)
                .font(.headline)
            HStack(alignment: .top, spacing: 24) {
                PacingSummaryLine(
                    title: "Timing",
                    detail: dateSummary(startDate: unit.startDate, endDate: unit.endDate),
                    systemImage: "calendar"
                )
                PacingSummaryLine(
                    title: "Structure",
                    detail: "\(unit.modules.count) modules, \(unit.modules.flatMap(\.lessons).count) lessons",
                    systemImage: "list.bullet.rectangle"
                )
                PacingSummaryLine(
                    title: "Skipped days",
                    detail: unit.skippedDays.isEmpty ? "None recorded" : "\(unit.skippedDays.count) day(s)",
                    systemImage: "calendar.badge.minus"
                )
            }
        }
        .padding(10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private func dateSummary(startDate: Date?, endDate: Date?) -> String {
    switch (startDate, endDate) {
    case let (start?, end?):
        "\(start.formatted(date: .abbreviated, time: .omitted)) to \(end.formatted(date: .abbreviated, time: .omitted))"
    case let (start?, nil):
        "Starts \(start.formatted(date: .abbreviated, time: .omitted))"
    case let (nil, end?):
        "Ends \(end.formatted(date: .abbreviated, time: .omitted))"
    case (nil, nil):
        "Dates not set"
    }
}

private struct CoursePacingModuleEditorRow: View {
    var unitID: UUID
    var module: CoursePacingModule
    var save: (UUID, UUID, String, Date?, Date?, Int, String) -> Void
    var saveLesson: (UUID, UUID, UUID, String, Date?, Date?, Int, String, String) -> Void
    @State private var title: String
    @State private var hasStartDate: Bool
    @State private var startDate: Date
    @State private var hasEndDate: Bool
    @State private var endDate: Date
    @State private var estimatedDays: Int
    @State private var notes: String

    init(
        unitID: UUID,
        module: CoursePacingModule,
        save: @escaping (UUID, UUID, String, Date?, Date?, Int, String) -> Void,
        saveLesson: @escaping (UUID, UUID, UUID, String, Date?, Date?, Int, String, String) -> Void
    ) {
        self.unitID = unitID
        self.module = module
        self.save = save
        self.saveLesson = saveLesson
        _title = State(initialValue: module.title)
        _hasStartDate = State(initialValue: module.startDate != nil)
        _startDate = State(initialValue: module.startDate ?? Date.now)
        _hasEndDate = State(initialValue: module.endDate != nil)
        _endDate = State(initialValue: module.endDate ?? module.startDate ?? Date.now)
        _estimatedDays = State(initialValue: max(1, module.estimatedInstructionalDays))
        _notes = State(initialValue: module.notes)
    }

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Module title", text: $title)
                Toggle("Has start date", isOn: $hasStartDate)
                if hasStartDate {
                    DatePicker("Start date", selection: $startDate, displayedComponents: .date)
                }
                Toggle("Has end date", isOn: $hasEndDate)
                if hasEndDate {
                    DatePicker("End date", selection: $endDate, displayedComponents: .date)
                }
                Stepper("Estimated instructional days: \(estimatedDays)", value: $estimatedDays, in: 1...250)
                TextField("Module notes", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
                if dateRangeInvalid {
                    Label("End date must be on or after start date.", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                Button("Save module pacing") {
                    save(unitID, module.id, title, hasStartDate ? startDate : nil, hasEndDate ? endDate : nil, estimatedDays, notes)
                }
                .disabled(dateRangeInvalid)
                ForEach(module.lessons) { lesson in
                    CoursePacingLessonEditorRow(unitID: unitID, moduleID: module.id, lesson: lesson, save: saveLesson)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(module.title)
                    .font(.footnote.weight(.semibold))
                Text("\(module.lessons.count) lessons, \(module.estimatedInstructionalDays) estimated days • \(dateSummary(startDate: module.startDate, endDate: module.endDate))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dateRangeInvalid: Bool {
        hasStartDate && hasEndDate && Calendar.current.startOfDay(for: endDate) < Calendar.current.startOfDay(for: startDate)
    }
}

private struct CoursePacingLessonEditorRow: View {
    var unitID: UUID
    var moduleID: UUID
    var lesson: CoursePacingLesson
    var save: (UUID, UUID, UUID, String, Date?, Date?, Int, String, String) -> Void
    @State private var title: String
    @State private var hasStartDate: Bool
    @State private var startDate: Date
    @State private var hasEndDate: Bool
    @State private var endDate: Date
    @State private var estimatedDays: Int
    @State private var dependencyNotes: String
    @State private var sourceNotes: String

    init(unitID: UUID, moduleID: UUID, lesson: CoursePacingLesson, save: @escaping (UUID, UUID, UUID, String, Date?, Date?, Int, String, String) -> Void) {
        self.unitID = unitID
        self.moduleID = moduleID
        self.lesson = lesson
        self.save = save
        _title = State(initialValue: lesson.title)
        _hasStartDate = State(initialValue: lesson.startDate != nil)
        _startDate = State(initialValue: lesson.startDate ?? Date.now)
        _hasEndDate = State(initialValue: lesson.endDate != nil)
        _endDate = State(initialValue: lesson.endDate ?? lesson.startDate ?? Date.now)
        _estimatedDays = State(initialValue: max(1, lesson.estimatedInstructionalDays))
        _dependencyNotes = State(initialValue: lesson.dependencyNotes)
        _sourceNotes = State(initialValue: lesson.sourceNotes)
    }

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Lesson title", text: $title)
                Toggle("Has start date", isOn: $hasStartDate)
                if hasStartDate {
                    DatePicker("Start date", selection: $startDate, displayedComponents: .date)
                }
                Toggle("Has end date", isOn: $hasEndDate)
                if hasEndDate {
                    DatePicker("End date", selection: $endDate, displayedComponents: .date)
                }
                Stepper("Estimated instructional days: \(estimatedDays)", value: $estimatedDays, in: 1...60)
                TextField("Dependency notes", text: $dependencyNotes, axis: .vertical)
                    .lineLimit(2...4)
                TextField("Source notes", text: $sourceNotes, axis: .vertical)
                    .lineLimit(2...4)
                if dateRangeInvalid {
                    Label("End date must be on or after start date.", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                Button("Save lesson pacing") {
                    save(unitID, moduleID, lesson.id, title, hasStartDate ? startDate : nil, hasEndDate ? endDate : nil, estimatedDays, dependencyNotes, sourceNotes)
                }
                .disabled(dateRangeInvalid)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(lesson.title)
                    .font(.footnote.weight(.semibold))
                Text("\(lesson.estimatedInstructionalDays) estimated day(s) • \(dateSummary(startDate: lesson.startDate, endDate: lesson.endDate))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dateRangeInvalid: Bool {
        hasStartDate && hasEndDate && Calendar.current.startOfDay(for: endDate) < Calendar.current.startOfDay(for: startDate)
    }
}

private struct OutputReviewRow: View {
    @EnvironmentObject private var store: AppStore
    var output: GeneratedOutputRecord
    var onReviewed: ((GeneratedOutputRecord) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Created \(output.displayName)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(output.kind.displayName)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let review = output.review {
                Label("Reviewed \(review.reviewedAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "eye")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if !review.reviewerNotes.isEmpty {
                    Text(review.reviewerNotes)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(GeneratedOutputReview.checklist(for: output.kind), id: \.self) { item in
                        Text("• \(item)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            HStack {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: output.filePath)])
                }
                if output.review == nil {
                    Button("Mark reviewed") {
                        if let reviewed = store.markGeneratedOutputReviewed(output) {
                            onReviewed?(reviewed)
                        }
                    }
                }
            }
        }
    }
}

struct ConfigurationSummaryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedPacingUnitID: UUID?
    @State private var unitTitle = ""
    @State private var unitHasStartDate = false
    @State private var unitStartDate = Date.now
    @State private var unitHasEndDate = false
    @State private var unitEndDate = Date.now
    @State private var unitEstimatedDays = 1
    @State private var unitAssessmentWindowsText = ""
    @State private var unitNotes = ""
    @State private var skippedDayDate = Date.now

    var body: some View {
        Form {
            Text("Workspace configuration").font(.largeTitle.bold())
            Section("Local testing profiles") {
                if let activeProfile = store.activeTeacherProfile {
                    LabeledContent("Active profile", value: activeProfile.displayName)
                    LabeledContent("Role", value: activeProfile.role)
                    LabeledContent("Grade or subject", value: activeProfile.gradeOrSubject.isEmpty ? "Not set" : activeProfile.gradeOrSubject)
                    Text("This is a local testing profile. Its documents, pacing, lessons, weekly plans, and generated-output history are stored separately on this Mac.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Use unprofiled local data for the current single-user workflow, or create local test teachers to simulate account separation without a real login system.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text("Use the profile button at the top of the app to create or switch local test teachers.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let configuration = store.configuration {
                LabeledContent("Workspace", value: configuration.workspaceName)
                LabeledContent("Location", value: configuration.workspaceReference.path)
                LabeledContent("Output folder", value: configuration.outputFolderReference?.path ?? "Not selected")
                Section("PowerPoint export") {
                    Picker("Exporter", selection: Binding(
                        get: { store.slideDeckExporterPreference },
                        set: { store.setSlideDeckExporter($0) }
                    )) {
                        ForEach(SlideDeckExporterPreference.allCases) { exporter in
                            Text(exporter.displayName).tag(exporter)
                        }
                    }
                    Text(store.slideDeckExporterPreference.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Label(store.slideDeckAvailability.title, systemImage: store.slideDeckAvailability.isAvailable ? "checkmark.circle" : "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(store.slideDeckAvailability.isAvailable ? Color.secondary : Color.orange)
                    Text(store.slideDeckAvailability.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Weekly planning prompt") {
                    Toggle("Prompt each week", isOn: Binding(
                        get: { store.weeklyPlanningPromptPreference.isEnabled },
                        set: {
                            var preference = store.weeklyPlanningPromptPreference
                            preference.isEnabled = $0
                            store.setWeeklyPlanningPrompt(preference)
                        }
                    ))
                    Picker("Day", selection: Binding(
                        get: { store.weeklyPlanningPromptPreference.day },
                        set: {
                            var preference = store.weeklyPlanningPromptPreference
                            preference.day = $0
                            store.setWeeklyPlanningPrompt(preference)
                        }
                    )) {
                        ForEach(WeeklyPlanningPromptDay.allCases) { day in
                            Text(day.displayName).tag(day)
                        }
                    }
                    DatePicker("Time", selection: Binding(
                        get: { promptTimeDate(for: store.weeklyPlanningPromptPreference) },
                        set: { date in
                            var preference = store.weeklyPlanningPromptPreference
                            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                            preference.hour = components.hour ?? preference.hour
                            preference.minute = components.minute ?? preference.minute
                            store.setWeeklyPlanningPrompt(preference)
                        }
                    ), displayedComponents: .hourAndMinute)
                    if let nextPromptDate = store.weeklyPlanningPromptPreference.nextPromptDate(after: .now) {
                        Text("Next prompt target: \(nextPromptDate, format: .dateTime.weekday(.wide).month().day().hour().minute()). Reminder delivery will be connected after the app workflow is finalized.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Prompt delivery is off. Reminder delivery will be connected after the app workflow is finalized.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Course pacing setup") {
                    CoursePacingReadinessView(report: store.coursePacingReadinessReport)
                    if let plan = configuration.coursePacingPlan {
                        LabeledContent("Status", value: plan.reviewStatus.displayName)
                        LabeledContent("Sources", value: plan.sourceReferenceNames.isEmpty ? "No readable setup documents linked" : plan.sourceReferenceNames.joined(separator: ", "))
                        LabeledContent("Structure", value: "\(plan.unitCount) units, \(plan.moduleCount) modules, \(plan.lessonCount) lessons")
                        ForEach(plan.units) { unit in
                            CoursePacingUnitSummaryRow(
                                unit: unit,
                                isSelected: selectedPacingUnitID == unit.id
                            ) {
                                loadPacingUnitEditor(unit)
                            }
                        }
                        if let selectedUnit {
                            GroupBox("Edit pacing unit") {
                                VStack(alignment: .leading, spacing: 8) {
                                    SelectedCoursePacingUnitHeader(unit: selectedUnit)
                                    TextField("Unit title", text: $unitTitle)
                                    Toggle("Has start date", isOn: $unitHasStartDate)
                                    if unitHasStartDate {
                                        DatePicker("Start date", selection: $unitStartDate, displayedComponents: .date)
                                    }
                                    Toggle("Has end date", isOn: $unitHasEndDate)
                                    if unitHasEndDate {
                                        DatePicker("End date", selection: $unitEndDate, displayedComponents: .date)
                                    }
                                    Stepper("Estimated instructional days: \(unitEstimatedDays)", value: $unitEstimatedDays, in: 1...250)
                                    TextField("Assessment windows, one per line", text: $unitAssessmentWindowsText, axis: .vertical)
                                        .lineLimit(2...5)
                                    TextField("Unit pacing notes", text: $unitNotes, axis: .vertical)
                                        .lineLimit(2...4)
                                    if unitDateRangeInvalid {
                                        Label("End date must be on or after start date.", systemImage: "exclamationmark.triangle")
                                            .font(.footnote)
                                            .foregroundStyle(.orange)
                                    }
                                    HStack {
                                        Button("Save unit pacing") {
                                            store.updateCoursePacingUnit(
                                                unitID: selectedUnit.id,
                                                title: unitTitle,
                                                startDate: unitHasStartDate ? unitStartDate : nil,
                                                endDate: unitHasEndDate ? unitEndDate : nil,
                                                estimatedInstructionalDays: unitEstimatedDays,
                                                assessmentWindows: unitAssessmentWindowsText.components(separatedBy: .newlines),
                                                notes: unitNotes
                                            )
                                            reloadSelectedPacingUnit()
                                        }
                                        .disabled(unitDateRangeInvalid)
                                        Button("Close") { selectedPacingUnitID = nil }
                                    }
                                    Divider()
                                    DatePicker("Skipped day", selection: $skippedDayDate, displayedComponents: .date)
                                    Button("Add skipped day") {
                                        store.addSkippedDayToCoursePacingUnit(unitID: selectedUnit.id, date: skippedDayDate)
                                        reloadSelectedPacingUnit()
                                    }
                                    ForEach(selectedUnit.skippedDays, id: \.self) { date in
                                        HStack {
                                            Text(date, format: .dateTime.weekday(.wide).month().day().year())
                                                .font(.footnote)
                                            Spacer()
                                            Button("Remove") {
                                                store.removeSkippedDayFromCoursePacingUnit(unitID: selectedUnit.id, date: date)
                                                reloadSelectedPacingUnit()
                                            }
                                        }
                                    }
                                    if !selectedUnit.modules.isEmpty {
                                        Divider()
                                        Text("Modules and lessons")
                                            .font(.footnote.weight(.semibold))
                                        ForEach(selectedUnit.modules) { module in
                                            CoursePacingModuleEditorRow(
                                                unitID: selectedUnit.id,
                                                module: module,
                                                save: { unitID, moduleID, title, startDate, endDate, estimatedDays, notes in
                                                    store.updateCoursePacingModule(
                                                        unitID: unitID,
                                                        moduleID: moduleID,
                                                        title: title,
                                                        startDate: startDate,
                                                        endDate: endDate,
                                                        estimatedInstructionalDays: estimatedDays,
                                                        notes: notes
                                                    )
                                                    reloadSelectedPacingUnit()
                                                },
                                                saveLesson: { unitID, moduleID, lessonID, title, startDate, endDate, estimatedDays, dependencyNotes, sourceNotes in
                                                    store.updateCoursePacingLesson(
                                                        unitID: unitID,
                                                        moduleID: moduleID,
                                                        lessonID: lessonID,
                                                        title: title,
                                                        startDate: startDate,
                                                        endDate: endDate,
                                                        estimatedInstructionalDays: estimatedDays,
                                                        dependencyNotes: dependencyNotes,
                                                        sourceNotes: sourceNotes
                                                    )
                                                    reloadSelectedPacingUnit()
                                                }
                                            )
                                        }
                                    }
                                }
                            }
                        }
                        TextField("Teacher refinement notes for pacing changes", text: Binding(
                            get: { store.configuration?.coursePacingPlan?.teacherRefinementNotes ?? "" },
                            set: { store.updateCoursePacingRefinementNotes($0) }
                        ), axis: .vertical)
                        .lineLimit(2...4)
                        HStack {
                            Button("Approve pacing") { store.approveCoursePacingPlan() }
                                .disabled(plan.reviewStatus == .approved)
                            Button("Rebuild starter pacing from readable sources") {
                                store.createStarterCoursePacingPlanFromReviewedSources()
                            }
                        }
                    } else {
                        Text("Import readable setup documents first. Then create a draft pacing model from the readable text.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Create starter pacing from readable sources") {
                            store.createStarterCoursePacingPlanFromReviewedSources()
                        }
                    }
                }
                Section("Registered source folders") {
                    if configuration.sourceRegistrations.isEmpty {
                        Text("No source folders registered yet.").foregroundStyle(.secondary)
                    }
                    ForEach(configuration.sourceRegistrations) { source in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(source.displayName)
                                Text(source.reference.path).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Remove") { store.removeSourceRegistration(source.id) }
                        }
                    }
                }
                Section("Registered templates") {
                    if configuration.outputTemplates.isEmpty {
                        Text("No templates registered yet.").foregroundStyle(.secondary)
                    }
                    ForEach(configuration.outputTemplates) { template in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(template.displayName)
                                Text(template.kind.rawValue).foregroundStyle(.secondary)
                                if let mappings = template.slotMappings, !mappings.isEmpty {
                                    Text("\(mappings.count) mapped lesson fields")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Remove") { store.removeOutputTemplate(template.id) }
                        }
                    }
                    Button("Add weekly-plan template…") { chooseTemplate() }
                    Button("Add presentation template…") { choosePresentationTemplate() }
                }
                Section("Presentation template readiness") {
                    PresentationTemplateReadinessView(report: store.presentationTemplateReadinessReport)
                    if let template = store.activePresentationTemplate {
                        Button("Inspect presentation template") {
                            store.inspectPresentationTemplateLayout(templateID: template.id)
                        }
                    }
                }
                Section("Local workflow QA") {
                    LocalWorkflowQAView(report: store.localWorkflowQAReport)
                }
                Section("Release readiness") {
                    ForEach(store.releaseReadinessReport.items) { item in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.footnote.weight(.semibold))
                                Text(item.detail)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: releaseIcon(for: item.status))
                                .foregroundStyle(releaseColor(for: item.status))
                        }
                    }
                }
                Section("Generated output history") {
                    if store.generatedOutputs.isEmpty {
                        Text("No generated outputs yet.").foregroundStyle(.secondary)
                    }
                    ForEach(Array(store.generatedOutputs.prefix(12))) { output in
                        OutputReviewRow(output: output)
                    }
                }
                Button("Choose output folder…") { chooseOutputFolder() }
                Text("Phase 1 registers these locations only. It does not read or modify their contents.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { store.replaceOutputFolder(with: url) }
    }

    private func chooseTemplate() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.html]
        if panel.runModal() == .OK, let url = panel.url { store.registerWeeklyPlanTemplate(url) }
    }

    private func choosePresentationTemplate() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if let powerpointType = UTType(filenameExtension: "pptx") {
            panel.allowedContentTypes = [powerpointType]
        }
        if panel.runModal() == .OK, let url = panel.url { store.registerPresentationTemplate(url) }
    }

    private var selectedUnit: CoursePacingUnit? {
        guard let selectedPacingUnitID else { return nil }
        return store.configuration?.coursePacingPlan?.units.first { $0.id == selectedPacingUnitID }
    }

    private func loadPacingUnitEditor(_ unit: CoursePacingUnit) {
        selectedPacingUnitID = unit.id
        unitTitle = unit.title
        unitHasStartDate = unit.startDate != nil
        unitStartDate = unit.startDate ?? Date.now
        unitHasEndDate = unit.endDate != nil
        unitEndDate = unit.endDate ?? unit.startDate ?? Date.now
        unitEstimatedDays = max(1, unit.estimatedInstructionalDays)
        unitAssessmentWindowsText = unit.assessmentWindows.joined(separator: "\n")
        unitNotes = unit.notes
        skippedDayDate = unit.startDate ?? Date.now
    }

    private func reloadSelectedPacingUnit() {
        guard let selectedUnit else { return }
        loadPacingUnitEditor(selectedUnit)
    }

    private var unitDateRangeInvalid: Bool {
        unitHasStartDate && unitHasEndDate && Calendar.current.startOfDay(for: unitEndDate) < Calendar.current.startOfDay(for: unitStartDate)
    }

    private func promptTimeDate(for preference: WeeklyPlanningPromptPreference) -> Date {
        var components = DateComponents()
        components.hour = preference.hour
        components.minute = preference.minute
        return Calendar.current.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    private func releaseIcon(for status: ReleaseReadinessStatus) -> String {
        switch status {
        case .ready: "checkmark.circle"
        case .attention: "exclamationmark.triangle"
        case .blocked: "xmark.octagon"
        }
    }

    private func releaseColor(for status: ReleaseReadinessStatus) -> Color {
        switch status {
        case .ready: .green
        case .attention: .orange
        case .blocked: .red
        }
    }
}
