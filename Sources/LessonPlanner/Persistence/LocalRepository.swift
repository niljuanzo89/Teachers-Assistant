import Foundation

protocol LocalRepositoryProtocol {
    func loadTeacherProfiles() throws -> [TeacherProfile]
    func saveTeacherProfiles(_ profiles: [TeacherProfile]) throws
    func loadActiveTeacherProfileID() throws -> UUID?
    func saveActiveTeacherProfileID(_ id: UUID?) throws
    func loadConfiguration() throws -> AppConfiguration?
    func saveConfiguration(_ configuration: AppConfiguration) throws
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

    private static func defaultRootURL() -> URL {
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
