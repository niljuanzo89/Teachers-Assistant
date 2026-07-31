import Foundation

/// Whether an imported document may occupy a block in the weekly planner, and if not, which
/// other pathway it belongs to. Deliberately separate from `ImportedSourceRole`, which answers
/// "what kind of setup document is this?" — a question built for sorting planning documents.
/// Collapsing the two is what let a practice worksheet become a scheduled lesson: 315 of 316
/// documents in a real curriculum folder classified as `lessonMaterial`, and every one of them
/// then became its own schedulable lesson record.
enum LessonPlacementEligibility: String, Codable, CaseIterable, Identifiable {
    /// Has the shape of a teachable lesson.
    case placeableLesson
    /// Does not teach a lesson but *enumerates* several — a weekly content packet or unit lesson
    /// list ("Monday: Place value review"). Central to how the content lane learns a sequence, so
    /// it must be able to contribute lessons even though it is not itself a lesson page. An
    /// earlier version of this classifier omitted this category and wrongly binned such packets
    /// as `inert`, which broke the app's primary import path.
    case lessonSequence
    /// Real instructional value, but supports a lesson rather than being one — reteach,
    /// challenge, practice, vocabulary, assessment. Feeds the differentiation guide.
    case supportingMaterial
    /// Pacing guide, calendar, curriculum map. Drives scheduling parameters, not blocks.
    case planningDocument
    /// Usable for neither purpose (cover page, index, unreadable). Kept and visible so the
    /// teacher can see it was received, but referenced by nothing.
    case inert

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .placeableLesson: "Lesson"
        case .lessonSequence: "Lesson list"
        case .supportingMaterial: "Supporting material"
        case .planningDocument: "Planning document"
        case .inert: "Not used"
        }
    }

    var canOccupyScheduleBlock: Bool { self == .placeableLesson }

    /// Whether this document may contribute lessons to the course pacing sequence. Broader than
    /// `canOccupyScheduleBlock`: a lesson page, lesson list, or true scope-and-sequence may
    /// establish a sequence. The pacing builder independently skips documents that yield no
    /// named lessons, which keeps schedules and generic planning references from manufacturing
    /// placeholder records while preserving legitimate scope-and-sequence files.
    var canContributeLessonSequence: Bool {
        self != .supportingMaterial && self != .inert
    }
}

/// Which differentiation category a supporting material serves. Gives the differentiation guide
/// real structure without inventing categories from prose — `LessonRecord.differentiationSummary`
/// is a single free-text field and cannot be honestly split on its own.
enum DifferentiationRole: String, Codable, CaseIterable, Identifiable {
    case support
    case extensionChallenge
    case practice
    case vocabulary
    case assessment
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .support: "Access and support"
        case .extensionChallenge: "Extension and challenge"
        case .practice: "Student practice"
        case .vocabulary: "Language and vocabulary"
        case .assessment: "Success check"
        case .other: "Other material"
        }
    }
}

/// A module/lesson identifier parsed from a document, used to attach supporting material to the
/// lesson it belongs to. A far stronger signal than subject-keyword scoring: measured across a
/// real 316-document import, 45% carried a resolvable identifier in the filename or text, versus
/// keyword matching that mis-assigned math content to an English block.
struct DocumentLessonKey: Codable, Equatable, Hashable {
    var module: Int?
    var lesson: Int
}

struct DocumentPlacementClassification: Equatable {
    var eligibility: LessonPlacementEligibility
    var differentiationRole: DifferentiationRole?
    var lessonKey: DocumentLessonKey?
    /// Plain-language reason, surfaced to the teacher. An automated decision that silently
    /// excludes a document from the planner has to be able to explain itself.
    var rationale: String
}

enum DocumentPlacementClassifier {
    /// Order matters and encodes the bias this classifier is built around: **when in doubt, not
    /// a lesson.** A missed lesson shows up as an empty block the teacher notices immediately; a
    /// false positive silently corrupts the planner, which is the failure actually reported.
    ///
    /// Filename artifact markers are checked before lesson shape because they are unambiguous
    /// ("reteach", "answer key"). Body-text markers are checked *after* lesson shape, because a
    /// genuine teacher-edition lesson legitimately contains the words "practice" and
    /// "assessment" as section headings and must not be demoted for it.
    static func classify(displayName: String, extractedText: String) -> DocumentPlacementClassification {
        let trimmedText = extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = displayName.lowercased()
        let lessonKey = lessonKey(displayName: displayName, extractedText: trimmedText)

        let planningText = "\(name) \(trimmedText.prefix(3_000).lowercased())"

        // 1. Schedules and calendars govern the scaffold; their rows are never lessons.
        if let phrase = schedulePlanningPhrase(in: planningText) {
            return DocumentPlacementClassification(
                eligibility: .planningDocument,
                differentiationRole: nil,
                lessonKey: lessonKey,
                rationale: "Reads as a planning document (\"\(phrase)\"); it sets scheduling parameters rather than filling a block."
            )
        }

        // 2. Nothing readable means nothing to place or attach.
        guard !trimmedText.isEmpty else {
            return DocumentPlacementClassification(
                eligibility: .inert,
                differentiationRole: nil,
                lessonKey: lessonKey,
                rationale: "No usable text could be read from this file, so it is kept on file but not used."
            )
        }

        // 3. An unambiguous artifact name settles it before any lesson-shape test runs.
        if let role = differentiationRole(inFileName: name) {
            return DocumentPlacementClassification(
                eligibility: .supportingMaterial,
                differentiationRole: role,
                lessonKey: lessonKey,
                rationale: "The file name identifies this as \(role.displayName.lowercased()) material, so it supports a lesson instead of filling a block."
            )
        }

        let sequenceCount = enumeratedLessonCount(in: trimmedText)
        if let phrase = sequencePlanningPhrase(in: planningText), sequenceCount == nil {
            return DocumentPlacementClassification(
                eligibility: .planningDocument,
                differentiationRole: nil,
                lessonKey: lessonKey,
                rationale: "Reads as a planning document (\"\(phrase)\"); no explicit lesson list was found."
            )
        }

        // A legitimate weekly packet may be shorter than the normal body-text floor. Its two
        // dated entries are a stronger signal than length, so inspect them before rejecting it.
        if let count = sequenceCount, trimmedText.count < minimumUsableTextLength {
            return DocumentPlacementClassification(
                eligibility: .lessonSequence,
                differentiationRole: nil,
                lessonKey: lessonKey,
                rationale: "Reads as a short lesson list: found \(count) lesson entries."
            )
        }

        guard trimmedText.count >= minimumUsableTextLength else {
            return DocumentPlacementClassification(
                eligibility: .inert,
                differentiationRole: nil,
                lessonKey: lessonKey,
                rationale: "No usable text or lesson structure could be read from this short file, so it is kept on file but not used."
            )
        }

        // 4. Positive evidence of lesson shape, reusing the same extraction the lesson editor
        //    uses so the gate and the editor can never disagree about what a lesson looks like.
        let inferred = LessonStructureInferencer.fillingGaps(
            in: LessonFieldExtractor.extract(from: trimmedText), from: trimmedText
        )
        let hasObjective = !(inferred.objective ?? "").isEmpty
        let hasSequence = inferred.steps.count >= minimumPhasesForLessonShape
        if hasObjective || hasSequence {
            var evidence: [String] = []
            if hasObjective { evidence.append("a learning objective") }
            if hasSequence { evidence.append("\(inferred.steps.count) instructional steps") }
            return DocumentPlacementClassification(
                eligibility: .placeableLesson,
                differentiationRole: nil,
                lessonKey: lessonKey,
                rationale: "Reads as a lesson: found \(evidence.joined(separator: " and "))."
            )
        }

        // 5. Not a lesson itself, but enumerates several — a content packet or unit lesson list.
        if let count = sequenceCount {
            return DocumentPlacementClassification(
                eligibility: .lessonSequence,
                differentiationRole: nil,
                lessonKey: lessonKey,
                rationale: "Reads as a lesson list: found \(count) lesson entries, so it sets the sequence rather than filling a block itself."
            )
        }

        // 6. No lesson shape, but the body identifies a supporting purpose.
        if let role = differentiationRole(inBodyText: trimmedText) {
            return DocumentPlacementClassification(
                eligibility: .supportingMaterial,
                differentiationRole: role,
                lessonKey: lessonKey,
                rationale: "No lesson structure was found, and the content reads as \(role.displayName.lowercased()) material."
            )
        }

        // 7. Readable, but neither a lesson nor recognizable material.
        return DocumentPlacementClassification(
            eligibility: .inert,
            differentiationRole: nil,
            lessonKey: lessonKey,
            rationale: "No learning objective, instructional sequence, or recognizable material type was found, so this is kept on file but not used."
        )
    }

    /// Deliberately NOT delegated to `ImportedSourceRole.infer`. That function matches bare
    /// substrings including "benchmark", "holiday", and "break", so an ordinary math lesson
    /// mentioning "benchmark fractions" is read as an assessment schedule and would be diverted
    /// out of the planner entirely. Caught by this classifier's own tests. Planning documents
    /// announce themselves with specific multi-word phrases, so require one.
    ///
    /// `ImportedSourceRole.infer`'s over-matching is a real defect in its own right — it is the
    /// same failure that classified 315 of 316 documents as `lessonMaterial` — but it is load
    /// bearing for the existing pacing pathway and should be tightened as its own change, with
    /// its own verification, rather than as a side effect of this work.
    private static let schedulePlanningPhrases = [
        "instructional calendar", "district calendar", "school calendar", "daily schedule",
        "class schedule", "instructional schedule", "assessment calendar", "assessment schedule",
        "quiz schedule", "instructional days"
    ]

    private static let sequencePlanningPhrases = [
        "pacing guide", "scope and sequence", "scope & sequence", "year at a glance",
        "year-at-a-glance", "curriculum map", "standards map", "course map", "unit sequence"
    ]

    private static func schedulePlanningPhrase(in haystack: String) -> String? {
        schedulePlanningPhrases.first { haystack.contains($0) }
    }

    private static func sequencePlanningPhrase(in haystack: String) -> String? {
        sequencePlanningPhrases.first { haystack.contains($0) }
    }

    /// Below this, extraction has effectively failed — a page of running heads and a page number.
    private static let minimumUsableTextLength = 120

    /// One heading is not a sequence; a real lesson has at least a couple of phases. Guards
    /// against a single "Practice" heading on a worksheet reading as instructional structure.
    private static let minimumPhasesForLessonShape = 2

    /// Filename markers, strongest first. Ordered so that a more specific purpose wins over a
    /// generic one — a "reteach practice page" is support material, not general practice.
    private static let fileNameMarkers: [(DifferentiationRole, [String])] = [
        (.support, ["reteach", "rteach", "intervention", "interven", "tier2", "tier 2", "tier3", "tier 3", "scaffold", "support"]),
        (.extensionChallenge, ["chlg", "challenge", "enrich", "extension", "extend", "gifted", "advanced"]),
        (.vocabulary, ["vocab", "glossary", "word wall", "wordwall"]),
        (.assessment, ["answer key", "answerkey", "ansky", "solution", "quiz", "test", "exam", "assessment", "rubric", "checklist"]),
        (.practice, ["practice", "prctc", "homework", "worksheet", "blackline", "handout", "activity sheet"]),
        (.other, ["family letter", "parent letter", "letter home", "home letter", "correlation", "standards alignment"])
    ]

    private static func differentiationRole(inFileName name: String) -> DifferentiationRole? {
        for (role, markers) in fileNameMarkers where markers.contains(where: { name.contains($0) }) {
            return role
        }
        return nil
    }

    /// Body-text markers, checked only after a lesson-shape test has already failed. These are
    /// generic pedagogical section names — the same class of generic domain vocabulary
    /// `ImportedSourceRole.infer` already keys on ("pacing guide", "scope and sequence"), not
    /// any publisher's proprietary content.
    ///
    /// Measured against a real import, an earlier and much narrower version of this list left
    /// 154 of 316 documents classified `inert` — and sampling them showed they were not junk at
    /// all. They were small-group option pages, exit tickets, and warm-up problems: precisely the
    /// highest-value differentiation material in the folder. A document that fails the lesson
    /// test is far more often a usable piece of a lesson than it is genuinely unusable, so this
    /// list is deliberately generous where the phrase names a recognizable teaching artifact.
    private static let bodyMarkers: [(DifferentiationRole, [String])] = [
        (.support, [
            "small-group option", "small group option", "small-group activities", "small groups",
            "reteach", "intervention lesson", "additional support", "on track", "differentiated support"
        ]),
        (.extensionChallenge, [
            "ready for more", "challenge problem", "enrichment activity", "for students ready", "extend the lesson"
        ]),
        (.assessment, [
            "exit ticket", "answer key", "answers will vary", "sample answer",
            "scoring guide", "scoring rubric", "check understanding"
        ]),
        (.practice, [
            "problem of the day", "warm-up", "warm up", "independent practice", "guided practice",
            "practice and homework", "more practice"
        ]),
        (.vocabulary, ["vocabulary cards", "glossary", "word list", "academic vocabulary"]),
        (.other, [
            "dear family", "dear parent", "letter to the family",
            "video tutorials", "interactive examples", "online resources"
        ])
    ]

    private static func differentiationRole(inBodyText text: String) -> DifferentiationRole? {
        let haystack = text.prefix(4_000).lowercased()
        for (role, markers) in bodyMarkers where markers.contains(where: { haystack.contains($0) }) {
            return role
        }
        return nil
    }

    /// A document enumerating several lesson titles — day-keyed ("Monday: Place value review"),
    /// numbered ("Lesson 3: Rounding"), or a unit list. Requires at least this many entries so a
    /// single incidental "Lesson 2:" line in prose cannot make a worksheet look like a sequence.
    private static let minimumEnumeratedLessons = 2

    private static func enumeratedLessonCount(in text: String) -> Int? {
        let patterns = [
            #"^\s*(?:mon|tues|wednes|thurs|fri|satur|sun)day\s*[:\-]\s*\S.*$"#,
            #"^\s*(?:lesson|day)\s*\d{1,2}\s*[:\-]\s*\S.*$"#
        ]
        var total = 0
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .anchorsMatchLines]) else { continue }
            total += regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
        }
        return total >= minimumEnumeratedLessons ? total : nil
    }

    /// Prefers the filename, which is usually a deliberate, compact identifier, then falls back
    /// to the document's opening text. Returns nil rather than guessing when neither is present —
    /// an unattached material is a one-click fix for the teacher, whereas a wrong attachment puts
    /// the wrong support sheet on the wrong lesson.
    static func lessonKey(displayName: String, extractedText: String) -> DocumentLessonKey? {
        if let key = parseLessonKey(in: displayName) { return key }
        return parseLessonKey(in: String(extractedText.prefix(3_000)))
    }

    private static func parseLessonKey(in text: String) -> DocumentLessonKey? {
        let patterns = [
            #"(?:module|mod|unit)\s*_?-?\s*(\d{1,2})\D{0,20}?(?:lesson|lsn|ls)\s*_?-?\s*(\d{1,2})"#,
            #"m\s*_?-?(\d{1,2})\s*_?-?\s*l\s*_?-?(\d{1,2})"#
        ]
        for pattern in patterns {
            if let match = firstCaptures(pattern, in: text, count: 2),
               let module = Int(match[0]), let lesson = Int(match[1]) {
                return DocumentLessonKey(module: module, lesson: lesson)
            }
        }
        if let match = firstCaptures(#"(?:lesson|lsn)\s*_?-?\s*(\d{1,2})"#, in: text, count: 1),
           let lesson = Int(match[0]) {
            return DocumentLessonKey(module: nil, lesson: lesson)
        }
        return nil
    }

    private static func firstCaptures(_ pattern: String, in text: String, count: Int) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > count
        else { return nil }
        var captures: [String] = []
        for index in 1...count {
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            captures.append(String(text[range]))
        }
        return captures
    }
}
