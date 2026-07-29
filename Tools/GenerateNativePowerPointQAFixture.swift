import Foundation

@main
struct GenerateNativePowerPointQAFixture {
    @MainActor
    static func main() async throws {
        let destination = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Native PowerPoint Exporter QA Deck.pptx")
        var lesson = LessonRecord.draft(title: "Fraction Strategies")
        lesson.status = .approved
        lesson.subject = "Math"
        lesson.gradeOrAgeRange = "Grade 4"
        lesson.objective = "Compare equivalent fractions using visual models."
        lesson.sourceReferences = ["/Local QA/Fraction Strategies Source.pdf"]
        lesson.instructionalSequence = [
            InstructionalStep(id: UUID(), title: "Model 1/2 and 2/4 with fraction strips", notes: "Align strips and name equal-sized wholes."),
            InstructionalStep(id: UUID(), title: "Name what stays the same and what changes", notes: ""),
            InstructionalStep(id: UUID(), title: "Practice matching equivalent pairs", notes: "Students justify each match with a drawing or tool."),
            InstructionalStep(id: UUID(), title: "Explain one comparison using a drawing", notes: ""),
            InstructionalStep(id: UUID(), title: "Share and revise explanations", notes: "")
        ]
        lesson.materials = ["fraction strips", "whiteboard", "student notebooks"]
        lesson.differentiationSummary = "Use larger visual models for support; add unlike-denominator comparisons for extension."
        lesson.printableResourcePrompt = "Draw two fraction models that show equivalent fractions. Label the numerator, denominator, and whole."
        lesson.assessmentSummary = "Exit ticket: draw or describe why 1/2 and 2/4 are equivalent."

        try await NativePowerPointExporter.generate(lesson: lesson, destination: destination)
        print(destination.path)
    }
}
