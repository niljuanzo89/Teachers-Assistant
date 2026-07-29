import Foundation

struct LessonOutputContent {
    struct Step: Equatable {
        var title: String
        var notes: String

        var displayText: String {
            if title.isEmpty { return notes }
            if notes.isEmpty { return title }
            return "\(title) — \(notes)"
        }
    }

    var title: String
    var objective: String
    var subject: String
    var gradeOrAgeRange: String
    var steps: [Step]
    var materials: [String]
    var differentiation: String
    var printablePrompt: String
    var assessment: String
    var sourceReferences: [String]

    init(lesson: LessonRecord) {
        title = Self.clean(lesson.title, fallback: "Lesson")
        objective = Self.clean(lesson.objective, fallback: "Explore the teacher-reviewed learning objective.")
        subject = Self.clean(lesson.subject)
        gradeOrAgeRange = Self.clean(lesson.gradeOrAgeRange)
        steps = lesson.instructionalSequence.compactMap { step in
            let title = Self.clean(step.title)
            let notes = Self.clean(step.notes)
            guard !title.isEmpty || !notes.isEmpty else { return nil }
            return Step(title: title, notes: notes)
        }
        materials = lesson.materials.map { Self.clean($0) }.filter { !$0.isEmpty }
        differentiation = Self.clean(
            lesson.differentiationSummary,
            fallback: "Use a teacher-selected support, challenge, or small-group activity."
        )
        printablePrompt = Self.clean(
            lesson.printableResourcePrompt ?? "",
            fallback: "Choose a strategy, show your thinking, and explain why it works."
        )
        assessment = Self.clean(
            lesson.assessmentSummary,
            fallback: "Be ready to explain your model, answer, or reasoning."
        )
        sourceReferences = lesson.sourceReferences.map { Self.clean($0) }.filter { !$0.isEmpty }
    }

    var metadataLines: [String] {
        [
            subject.isEmpty ? nil : "Subject: \(subject)",
            gradeOrAgeRange.isEmpty ? nil : "Grade: \(gradeOrAgeRange)"
        ].compactMap { $0 }
    }

    func stepLines(range: Range<Int>, emptyMessage: String) -> [String] {
        let subset = steps.indices
            .filter { range.contains($0) }
            .map { steps[$0] }
        return bulletLines(for: subset, emptyMessage: emptyMessage)
    }

    func practiceStepGroups(startingAt startIndex: Int, size: Int) -> [[String]] {
        let remaining = steps.indices
            .filter { $0 >= startIndex }
            .map { steps[$0] }
        let groups = Self.chunk(remaining, size: size).map {
            bulletLines(for: $0, emptyMessage: "")
        }.filter { !$0.isEmpty }
        return groups.isEmpty ? [[]] : groups
    }

    private func bulletLines(for steps: [Step], emptyMessage: String) -> [String] {
        let lines = steps.map(\.displayText).filter { !$0.isEmpty }.map { "• \($0)" }
        if !lines.isEmpty { return lines }
        return emptyMessage.isEmpty ? [] : ["• \(emptyMessage)"]
    }

    private static func clean(_ value: String, fallback: String = "") -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func chunk<T>(_ values: [T], size: Int) -> [[T]] {
        guard size > 0 else { return [values] }
        return stride(from: 0, to: values.count, by: size).map { start in
            Array(values[start..<Swift.min(start + size, values.count)])
        }
    }
}
