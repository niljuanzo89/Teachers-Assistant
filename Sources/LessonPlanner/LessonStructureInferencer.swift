import Foundation

/// Second-pass extraction for curriculum documents that don't use explicit "Objective:"-style
/// field labels — the common shape of a published teacher edition, where structure is carried
/// by timed phase headings ("Warm-Up (5 min)"), standards codes, and conventional objective
/// phrasing ("Students will…") instead of labels the first pass can key off.
///
/// Unlike `LessonFieldExtractor`, this deliberately DOES make judgment calls. Every value it
/// produces is recorded in `Result.inferredFields` so the teacher is told which fields were
/// inferred from document structure and should be verified, rather than being shown a guess
/// presented as something the document stated outright.
enum LessonStructureInferencer {
    /// Fills only the fields a label pass left empty. Existing labeled values always win —
    /// an explicit "Objective:" in the source is better evidence than any heuristic.
    static func fillingGaps(in labeled: LessonFieldExtractor.Result, from text: String) -> LessonFieldExtractor.Result {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var result = labeled

        if result.objective == nil, let objective = inferredObjective(in: lines) {
            result.objective = objective
            result.inferredFields.insert(.objective)
        }
        if result.steps.isEmpty {
            let phases = inferredPhases(in: lines)
            if !phases.isEmpty {
                result.steps = phases
                result.inferredFields.insert(.steps)
            }
        }
        if let standard = firstStandardCode(in: lines) {
            if result.subject == nil {
                result.subject = standard.subject
                result.inferredFields.insert(.subject)
            }
            if result.gradeOrAgeRange == nil, let grade = standard.grade {
                result.gradeOrAgeRange = grade
                result.inferredFields.insert(.gradeOrAgeRange)
            }
        }
        if result.assessment == nil, let assessment = inferredAssessment(in: lines) {
            result.assessment = assessment
            result.inferredFields.insert(.assessment)
        }

        return result
    }

    // MARK: - Objective

    /// Curriculum writes objectives in a small set of conventional openings. Matching the
    /// opening phrase and taking the rest of its sentence is far more reliable than trying to
    /// judge which sentence "sounds like" an objective.
    private static let objectiveOpenings = [
        "students will be able to", "students will", "students can", "swbat",
        "learners will", "the student will", "i can", "by the end of this lesson"
    ]

    private static func inferredObjective(in lines: [String]) -> String? {
        for line in lines where !line.isEmpty {
            let lower = line.lowercased()
            for opening in objectiveOpenings where lower.contains(opening) {
                guard let range = lower.range(of: opening) else { continue }
                let sentence = String(line[range.lowerBound...])
                return firstSentence(of: sentence)
            }
        }
        return nil
    }

    private static func firstSentence(of text: String) -> String {
        guard let terminator = text.firstIndex(where: { $0 == "." || $0 == "!" || $0 == "?" }) else {
            return text.trimmingCharacters(in: .whitespaces)
        }
        return String(text[...terminator]).trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Instructional phases

    /// Conventional lesson-phase names across the models curriculum publishers actually use
    /// (gradual release, 5E, workshop). A heading only needs to match one of these OR carry a
    /// duration annotation to count as a phase.
    private static let phaseNames: Set<String> = [
        "warm-up", "warm up", "do now", "bell work", "bell ringer", "opening", "launch", "hook",
        "mini-lesson", "mini lesson", "direct instruction", "teaching the lesson", "teach",
        "model", "modeling", "guided practice", "we do", "explore", "investigate",
        "independent practice", "you do", "practice", "apply", "collaborative practice",
        "partner practice", "small group", "small-group instruction", "discussion", "share",
        "closure", "wrap-up", "wrap up", "closing", "summarize", "reflect",
        "engage", "explain", "elaborate", "evaluate", "extend"
    ]

    /// A phase's body runs to the next heading, so a multi-paragraph phase is captured whole.
    /// Capped so a malformed document (or one whose last heading is followed by pages of
    /// back matter) can't sweep its entire tail into a single step.
    private static let maximumPhaseBodyLines = 12

    private static func inferredPhases(in lines: [String]) -> [LessonFieldExtractor.ExtractedStep] {
        var steps: [LessonFieldExtractor.ExtractedStep] = []
        for (index, line) in lines.enumerated() {
            guard let title = phaseHeadingTitle(line) else { continue }
            steps.append(LessonFieldExtractor.ExtractedStep(title: title, notes: phaseBody(after: index, in: lines)))
        }
        return steps
    }

    private static func phaseBody(after index: Int, in lines: [String]) -> String {
        var collected: [String] = []
        var cursor = index + 1
        while cursor < lines.count, collected.count < maximumPhaseBodyLines {
            let line = lines[cursor]
            if phaseHeadingTitle(line) != nil { break }
            // A phase ends at the next labeled row too, not only at the next phase. Without this
            // the last phase in a "Component / Plan" table absorbs every remaining row.
            if LessonFieldExtractor.isRecognizedLabelLine(line) { break }
            if !line.isEmpty { collected.append(line) }
            cursor += 1
        }
        return collected.joined(separator: " ")
    }

    /// Returns the phase title if this line reads as a phase heading. A duration annotation
    /// ("(20 min)") is treated as sufficient evidence on its own, since it reliably marks an
    /// instructional phase even when the phase name isn't one this code knows.
    /// Whether this line reads as an instructional phase heading ("Warm-Up", "Mini-Lesson",
    /// "Launch (10 min)"). Exposed so the label-based extractor can treat one as a value
    /// terminator: in a "Component / Plan" table the phases sit between labeled rows with no
    /// blank line and no recognized label to stop at, so without this a "Materials" list runs
    /// on and absorbs the whole lesson body.
    static func isPhaseHeading(_ line: String) -> Bool { phaseHeadingTitle(line) != nil }

    private static func phaseHeadingTitle(_ line: String) -> String? {
        guard !line.isEmpty, line.count <= 60 else { return nil }
        var candidate = line.trimmingCharacters(in: CharacterSet(charactersIn: "#*: \t"))
        guard !candidate.isEmpty else { return nil }

        let durationPattern = #"\s*\(\s*\d+\s*(?:min|mins|minute|minutes)\.?\s*\)\s*$"#
        let hasDuration = candidate.range(of: durationPattern, options: [.regularExpression, .caseInsensitive]) != nil
        if let range = candidate.range(of: durationPattern, options: [.regularExpression, .caseInsensitive]) {
            candidate.removeSubrange(range)
        }
        candidate = candidate.trimmingCharacters(in: CharacterSet(charactersIn: ":-— \t"))
        guard !candidate.isEmpty else { return nil }

        if hasDuration { return candidate }
        return phaseNames.contains(candidate.lowercased()) ? candidate : nil
    }

    // MARK: - Standards codes

    private struct StandardMatch {
        var subject: String
        var grade: String?
    }

    /// Recognizes the three standards families most likely to appear in a US curriculum
    /// document. A standards code pins down subject reliably and usually grade too, which are
    /// otherwise almost never labeled outright on a lesson page.
    private static func firstStandardCode(in lines: [String]) -> StandardMatch? {
        for line in lines where !line.isEmpty {
            // Math CCSS, e.g. "5.NF.A.2" — grade first.
            if let match = capture(#"\b(K|\d{1,2})\.(?:OA|NBT|NF|MD|G|RP|NS|EE|SP|F)\b"#, in: line) {
                return StandardMatch(subject: "Math", grade: gradeLabel(match))
            }
            // ELA CCSS, e.g. "RL.5.1" — strand first, grade second.
            if let match = capture(#"\b(?:RL|RI|RF|W|SL|L)\.(K|\d{1,2})\.\d"#, in: line) {
                return StandardMatch(subject: "English Language Arts", grade: gradeLabel(match))
            }
            // NGSS, e.g. "5-PS1-1" or "MS-LS1-4" (MS/HS carry no single grade).
            if let match = capture(#"\b(K|\d|MS|HS)-(?:PS|LS|ESS|ETS)\d"#, in: line) {
                let grade = (match == "MS" || match == "HS") ? nil : gradeLabel(match)
                return StandardMatch(subject: "Science", grade: grade)
            }
        }
        return nil
    }

    private static func gradeLabel(_ raw: String) -> String {
        raw == "K" ? "Kindergarten" : "Grade \(raw)"
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges >= 2,
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }

    // MARK: - Assessment

    private static let assessmentMarkers = ["exit ticket", "exit slip", "quick check", "check for understanding"]

    private static func inferredAssessment(in lines: [String]) -> String? {
        for line in lines where !line.isEmpty {
            // A bare heading naming the assessment carries no detail worth copying; the
            // sentence describing what students actually do is what's useful here.
            if phaseHeadingTitle(line) != nil { continue }
            let lower = line.lowercased()
            if assessmentMarkers.contains(where: { lower.contains($0) }) {
                return firstSentence(of: line)
            }
        }
        return nil
    }
}
