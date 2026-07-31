import Foundation

/// The slice of a source document that belongs to one lesson.
///
/// Exists because the extractor is document-scoped while a lesson is day-scoped. Running extraction
/// over a whole weekly packet gives every weekday lesson the entire week — measured at 20
/// instructional steps for a single day — so a lesson must know its own portion before any field
/// can be populated from it.
///
/// `headingLabel` and `lessonTitle` are the durable identity; the offsets are a cached derivation.
/// Extraction can change (re-import, a different OCR pass), which would silently invalidate stored
/// offsets, so they are always validated against the heading before use and recomputed when stale.
/// This follows the same stored-with-fallback pattern as `placementEligibility`, `inferredSubject`
/// and `lessonKey`, each of which needed one after stranding pre-existing data.
struct LessonSourceSpan: Codable, Equatable {
    /// Preserved where known. Source association elsewhere still resolves by display name through
    /// `"Proposed from …"` notes, which is serviceable but weaker than an ID.
    var sourceID: UUID?
    var sourceDisplayName: String
    /// The delimiter that opened this span, e.g. "Monday: Place value review".
    var headingLabel: String
    var lessonTitle: String
    var startOffset: Int?
    var endOffset: Int?

    /// Returns this span's text, preferring cached offsets but only when they still point at the
    /// heading that defined the span. Otherwise rescans.
    func resolvedText(in extractedText: String) -> String? {
        if let start = startOffset, let end = endOffset,
           start >= 0, end <= extractedText.count, start < end {
            let lower = extractedText.index(extractedText.startIndex, offsetBy: start)
            let upper = extractedText.index(extractedText.startIndex, offsetBy: end)
            let slice = String(extractedText[lower..<upper])
            if slice.hasPrefix(headingLabel) { return slice }
        }
        return LessonSourceSpanDetector.detect(in: extractedText)
            .first { $0.headingLabel == headingLabel }?
            .resolvedTextIgnoringValidation(in: extractedText)
    }

    fileprivate func resolvedTextIgnoringValidation(in extractedText: String) -> String? {
        guard let start = startOffset, let end = endOffset,
              start >= 0, end <= extractedText.count, start < end else { return nil }
        let lower = extractedText.index(extractedText.startIndex, offsetBy: start)
        let upper = extractedText.index(extractedText.startIndex, offsetBy: end)
        return String(extractedText[lower..<upper])
    }
}

enum LessonSourceSpanDetector {
    /// Deliberately narrow: only a weekday heading opens a span, matching the weekday logic
    /// `CoursePacingPlan.starter` already uses to derive lesson titles, so the two agree about
    /// where a lesson begins. No `Lesson N:` variant, no page-based splitting, no inference.
    ///
    /// Scans the original string rather than a trimmed, blank-filtered line array, because that
    /// transformation loses the character positions the offsets must index into.
    static func detect(in extractedText: String) -> [LessonSourceSpan] {
        var headings: [(offset: Int, label: String, title: String)] = []
        var offset = 0
        for rawLine in extractedText.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if let colonIndex = line.firstIndex(of: ":") {
                let prefix = String(line[..<colonIndex]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let title = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if weekdayNames.contains(prefix), !title.isEmpty {
                    // Offset of the trimmed heading within the original text.
                    let leading = rawLine.count - rawLine.drop(while: { $0.isWhitespace }).count
                    headings.append((offset + leading, line, title))
                }
            }
            offset += rawLine.count + 1
        }

        let total = extractedText.count
        return headings.enumerated().map { index, heading in
            let end = index + 1 < headings.count ? headings[index + 1].offset : total
            return LessonSourceSpan(
                sourceID: nil,
                sourceDisplayName: "",
                headingLabel: heading.label,
                lessonTitle: heading.title,
                startOffset: heading.offset,
                endOffset: end
            )
        }
    }

    private static let weekdayNames: Set<String> = ["monday", "tuesday", "wednesday", "thursday", "friday"]
}
