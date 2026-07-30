import Foundation

protocol LocalRepositoryProtocol {
    func loadTeacherProfiles() throws -> [TeacherProfile]
    func saveTeacherProfiles(_ profiles: [TeacherProfile]) throws
    func loadActiveTeacherProfileID() throws -> UUID?
    func saveActiveTeacherProfileID(_ id: UUID?) throws
    func loadConfiguration() throws -> AppConfiguration?
    func saveConfiguration(_ configuration: AppConfiguration) throws
    /// Whether a configuration file exists for the active profile, regardless of whether it
    /// can currently be decoded. Lets the app tell "this teacher has never set up a
    /// workspace" apart from "this teacher's workspace is on disk but unreadable" — two
    /// states that must not lead to the same screen. See `AppStore.configurationIsUnreadable`.
    func hasStoredConfiguration() -> Bool
    func loadDailyPlan(for date: Date) throws -> DailyPlan?
    func saveDailyPlan(_ plan: DailyPlan) throws
    func loadWeeklyPlan(for weekOf: Date) throws -> WeeklyPlan?
    func saveWeeklyPlan(_ plan: WeeklyPlan) throws
    func loadLessons() throws -> [LessonRecord]
    func saveLessons(_ lessons: [LessonRecord]) throws
    func loadImportedSources() throws -> [ImportedSource]
    func saveImportedSources(_ sources: [ImportedSource]) throws
    func loadGeneratedOutputs() throws -> [GeneratedOutputRecord]
    func saveGeneratedOutputs(_ outputs: [GeneratedOutputRecord]) throws
    func loadProgressSnapshots() throws -> [PlanningProgressSnapshot]
    func saveProgressSnapshot(_ snapshot: PlanningProgressSnapshot) throws
}

private struct ActiveTeacherProfileSelection: Codable, Equatable {
    var activeTeacherProfileID: UUID?
}

struct LocalRepository: LocalRepositoryProtocol {
    let rootURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(rootURL: URL? = nil) {
        self.rootURL = rootURL ?? Self.defaultRootURL()
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadTeacherProfiles() throws -> [TeacherProfile] {
        try load([TeacherProfile].self, from: rootURL.appending(path: "teacher-profiles.json")) ?? []
    }

    func saveTeacherProfiles(_ profiles: [TeacherProfile]) throws {
        try save(profiles, to: rootURL.appending(path: "teacher-profiles.json"))
    }

    func loadActiveTeacherProfileID() throws -> UUID? {
        try load(ActiveTeacherProfileSelection.self, from: rootURL.appending(path: "active-teacher-profile.json"))?.activeTeacherProfileID
    }

    func saveActiveTeacherProfileID(_ id: UUID?) throws {
        try save(ActiveTeacherProfileSelection(activeTeacherProfileID: id), to: rootURL.appending(path: "active-teacher-profile.json"))
    }

    func loadConfiguration() throws -> AppConfiguration? {
        try load(AppConfiguration.self, from: dataRootURL().appending(path: "configuration.json"))
    }

    func hasStoredConfiguration() -> Bool {
        FileManager.default.fileExists(atPath: configurationURL().path)
    }

    /// Where the active profile's configuration lives. Exposed so a recovery screen can tell
    /// the teacher exactly which file to back up or send along when reporting a problem.
    /// Non-throwing on purpose: this is called precisely when reads are already failing, and
    /// pointing at the root data folder is far more useful than surfacing a second error. If
    /// the active-profile selection itself can't be read, the root folder still contains the
    /// teacher-data directory the teacher needs to back up.
    func configurationURL() -> URL {
        let root = (try? dataRootURL()) ?? rootURL
        return root.appending(path: "configuration.json")
    }

    func saveConfiguration(_ configuration: AppConfiguration) throws {
        try save(configuration, to: dataRootURL().appending(path: "configuration.json"))
    }

    func loadDailyPlan(for date: Date) throws -> DailyPlan? {
        try load(DailyPlan.self, from: dataRootURL().appending(path: "daily-plans/\(Self.dayKey(for: date)).json"))
    }

    func saveDailyPlan(_ plan: DailyPlan) throws {
        try save(plan, to: dataRootURL().appending(path: "daily-plans/\(Self.dayKey(for: plan.date)).json"))
    }

    func loadWeeklyPlan(for weekOf: Date) throws -> WeeklyPlan? {
        try load(WeeklyPlan.self, from: dataRootURL().appending(path: "weekly-plans/\(Self.dayKey(for: weekOf)).json"))
    }

    func saveWeeklyPlan(_ plan: WeeklyPlan) throws {
        try save(plan, to: dataRootURL().appending(path: "weekly-plans/\(Self.dayKey(for: plan.weekOf)).json"))
    }

    func loadLessons() throws -> [LessonRecord] {
        try load([LessonRecord].self, from: dataRootURL().appending(path: "lesson-records.json")) ?? []
    }

    func saveLessons(_ lessons: [LessonRecord]) throws {
        try save(lessons, to: dataRootURL().appending(path: "lesson-records.json"))
    }

    func loadImportedSources() throws -> [ImportedSource] {
        try load([ImportedSource].self, from: dataRootURL().appending(path: "imported-sources.json")) ?? []
    }

    func saveImportedSources(_ sources: [ImportedSource]) throws {
        try save(sources, to: dataRootURL().appending(path: "imported-sources.json"))
    }

    func loadGeneratedOutputs() throws -> [GeneratedOutputRecord] {
        try load([GeneratedOutputRecord].self, from: dataRootURL().appending(path: "generated-outputs.json")) ?? []
    }

    func saveGeneratedOutputs(_ outputs: [GeneratedOutputRecord]) throws {
        try save(outputs, to: dataRootURL().appending(path: "generated-outputs.json"))
    }

    func loadProgressSnapshots() throws -> [PlanningProgressSnapshot] {
        let snapshotsURL = try dataRootURL().appending(path: "progress-snapshots")
        guard FileManager.default.fileExists(atPath: snapshotsURL.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(
            at: snapshotsURL,
            includingPropertiesForKeys: nil
        )
        return try files
            .filter { $0.pathExtension == "json" }
            .compactMap { try load(PlanningProgressSnapshot.self, from: $0) }
            .sorted { $0.savedAt > $1.savedAt }
    }

    func saveProgressSnapshot(_ snapshot: PlanningProgressSnapshot) throws {
        try save(snapshot, to: dataRootURL().appending(path: "progress-snapshots/\(snapshot.id.uuidString).json"))
    }

    private func dataRootURL() throws -> URL {
        guard let activeTeacherProfileID = try loadActiveTeacherProfileID() else { return rootURL }
        return rootURL.appending(path: "teacher-data/\(activeTeacherProfileID.uuidString)")
    }

    private func load<T: Decodable>(_ type: T.Type, from url: URL) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try decoder.decode(T.self, from: Data(contentsOf: url))
    }

    private func save<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    /// `LESSONPLANNER_DATA_ROOT` points the app at an alternate data folder, following the
    /// same QA-override convention as `LESSONPLANNER_INITIAL_TAB`. This exists so data-state
    /// behavior (an unreadable workspace, a half-migrated file) can be reproduced against
    /// throwaway fixtures instead of by damaging real teacher data — which was otherwise the
    /// only way to exercise the recovery screen.
    private static func defaultRootURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["LESSONPLANNER_DATA_ROOT"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "LessonPlanner")
    }

    private static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
