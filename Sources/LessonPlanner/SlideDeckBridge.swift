import Foundation

protocol SlideDeckGenerating {
    @MainActor static var availability: SlideDeckAvailability { get }
    @MainActor static func generate(lesson: LessonRecord, destination: URL, template: OutputTemplateRegistration?) async throws
}

extension SlideDeckGenerating {
    @MainActor static func generate(lesson: LessonRecord, destination: URL) async throws {
        try await generate(lesson: lesson, destination: destination, template: nil)
    }
}

struct SlideDeckAvailability: Equatable {
    var isAvailable: Bool
    var title: String
    var detail: String

    static let ready = SlideDeckAvailability(
        isAvailable: true,
        title: "Personal PowerPoint export ready",
        detail: "The local Node and presentation runtime were found on this Mac."
    )

    static func unavailable(_ detail: String) -> SlideDeckAvailability {
        SlideDeckAvailability(
            isAvailable: false,
            title: "Personal PowerPoint export unavailable",
            detail: detail
        )
    }
}

/// Personal-build bridge for the locally installed presentation runtime.
/// This is deliberately not a customer-facing exporter: it requires the owner
/// to have Codex's development runtime installed on this Mac.
enum SlideDeckBridge: SlideDeckGenerating {
    enum BridgeError: LocalizedError {
        case unavailable(String)
        case missingGenerator
        case processFailed(String)
        case timedOut
        case missingOutput

        var errorDescription: String? {
            switch self {
            case .unavailable(let detail): "PowerPoint export is unavailable on this Mac: \(detail)"
            case .missingGenerator: "The personal PowerPoint generator was not included in this app build."
            case .processFailed(let detail): "PowerPoint generation failed. \(detail)"
            case .timedOut: "PowerPoint generation took too long and was stopped."
            case .missingOutput: "PowerPoint generation completed without creating a deck."
            }
        }
    }

    @MainActor static var availability: SlideDeckAvailability {
        do {
            _ = try locateRuntime()
            guard Bundle.main.url(forResource: "SlideDeckGenerator", withExtension: "mjs") != nil else {
                return .unavailable(BridgeError.missingGenerator.localizedDescription)
            }
            return .ready
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    private struct DeckPayload: Codable {
        struct Step: Codable {
            var title: String
            var notes: String
        }

        var title: String
        var subject: String
        var gradeOrAgeRange: String
        var objective: String
        var instructionalSequence: [Step]
        var materials: [String]
        var differentiationSummary: String
        var assessmentSummary: String
    }

    @MainActor static func generate(lesson: LessonRecord, destination: URL, template: OutputTemplateRegistration?) async throws {
        let runtime = try locateRuntime()
        guard let generator = Bundle.main.url(forResource: "SlideDeckGenerator", withExtension: "mjs") else {
            throw BridgeError.missingGenerator
        }

        let inputURL = FileManager.default.temporaryDirectory
            .appending(path: "lessonplanner-slide-input-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: inputURL) }

        let payload = DeckPayload(
            title: lesson.title,
            subject: lesson.subject,
            gradeOrAgeRange: lesson.gradeOrAgeRange,
            objective: lesson.objective,
            instructionalSequence: lesson.instructionalSequence.map { .init(title: $0.title, notes: $0.notes) },
            materials: lesson.materials,
            differentiationSummary: lesson.differentiationSummary,
            assessmentSummary: lesson.assessmentSummary
        )
        try JSONEncoder().encode(payload).write(to: inputURL, options: .atomic)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)

        try await Task.detached(priority: .userInitiated) {
            try runSynchronously(
                nodeURL: runtime.nodeURL,
                artifactToolURL: runtime.artifactToolURL,
                generatorURL: generator,
                inputURL: inputURL,
                destination: destination,
                timeout: 120
            )
        }.value
        guard FileManager.default.fileExists(atPath: destination.path) else { throw BridgeError.missingOutput }
    }

    private static func runSynchronously(nodeURL: URL, artifactToolURL: URL, generatorURL: URL, inputURL: URL, destination: URL, timeout: TimeInterval) throws {
        let process = Process()
        process.executableURL = nodeURL
        process.arguments = [generatorURL.path, inputURL.path, destination.path]
        var environment = ProcessInfo.processInfo.environment
        environment["LESSONPLANNER_ARTIFACT_TOOL_ENTRY"] = artifactToolURL.path
        process.environment = environment
        let errorPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = errorPipe
        try process.run()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
            throw BridgeError.timedOut
        }
        let errorText = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw BridgeError.processFailed(errorText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private struct Runtime {
        var nodeURL: URL
        var artifactToolURL: URL
    }

    private static func locateRuntime() throws -> Runtime {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let root = home.appending(path: ".cache/codex-runtimes/codex-primary-runtime/dependencies/node")
        let nodeURL = root.appending(path: "bin/node")
        let artifactToolURL = root.appending(path: "node_modules/@oai/artifact-tool/dist/artifact_tool.mjs")
        guard FileManager.default.isExecutableFile(atPath: nodeURL.path) else {
            throw BridgeError.unavailable("the personal Node runtime could not be found")
        }
        guard FileManager.default.fileExists(atPath: artifactToolURL.path) else {
            throw BridgeError.unavailable("the personal presentation runtime could not be found")
        }
        return Runtime(nodeURL: nodeURL, artifactToolURL: artifactToolURL)
    }
}
