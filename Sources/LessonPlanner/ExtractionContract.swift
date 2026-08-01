import Foundation

// MARK: - The contract

/// A field's value, typed rather than stringly.
///
/// Codex's Batch 051 review: `materials` and `steps` are already structured in the extractor's
/// result, so a single `String` payload would force the hosted extractor to flatten them and then
/// force a breaking contract change to get the structure back.
enum ExtractedValue: Equatable {
    case text(String)
    case list([String])
    case steps([LessonFieldExtractor.ExtractedStep])

    /// Every piece of text this value asserts. Each one has to be found in the citation.
    var assertedStrings: [String] {
        switch self {
        case .text(let value): return [value]
        case .list(let items): return items
        case .steps(let steps): return steps.flatMap { [$0.title, $0.notes] }.filter { !$0.isEmpty }
        }
    }

    var isEmpty: Bool { assertedStrings.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
}

/// Where a value came from. **Block IDs plus a quote — never model-supplied offsets.**
///
/// The verifier resolves the quote itself and derives the span, so position is something the app
/// computes rather than something the extractor asserts.
struct SourceCitation: Equatable {
    var blockIDs: [String]
    var quote: String
}

struct ExtractedFieldCandidate: Equatable {
    var value: ExtractedValue
    var citation: SourceCitation
}

/// What any extractor returns — the deterministic grammar or a model. Nothing here is trusted.
struct ExtractionProposal {
    /// Identifies this proposal in logs and test fixtures.
    var proposalID: String
    /// Rejected outright if unrecognised, so an older or newer producer cannot smuggle in a
    /// differently-shaped payload.
    var schemaVersion: String
    /// `"deterministic"`, or a model and prompt version. Recorded with the result so an extraction
    /// can be reproduced or attributed later.
    var producer: String
    /// Ranked best-first, capped at `ExtractionAdmissibility.maximumCandidates`.
    var candidates: [LessonFieldExtractor.Field: [ExtractedFieldCandidate]]

    static let currentSchemaVersion = "1"
}

// MARK: - Admission

/// Why a candidate was refused. Diagnostic and test data, **not UI copy** — Step 3 decides how
/// any of this is worded for a teacher.
enum AdmissionRejection: String, Equatable {
    case unsupportedSchemaVersion
    case tooManyCandidates
    case emptyCitation
    case unknownBlockID
    case duplicateBlockID
    case blocksNotContiguous
    case quoteNotFound
    /// The quote occurs more than once inside the cited blocks, so the span is undetermined.
    case quoteAmbiguous
    /// The value asserts text that is not in its own citation.
    case valueNotInQuote
    case implausibleShape
    /// Another field resolved to exactly this span.
    case spanConflict
    case emptyValue
}

struct AdmittedField: Equatable {
    var value: ExtractedValue
    /// Computed by the verifier from the quote, not supplied by the extractor.
    var span: Range<Int>
    var citation: SourceCitation
}

struct AdmittedExtraction: Equatable {
    var fields: [LessonFieldExtractor.Field: AdmittedField]
    var rejections: [LessonFieldExtractor.Field: [AdmissionRejection]]

    var admittedFieldCount: Int { fields.count }
}

/// The invariant core: what survives contact with the document.
///
/// Built **before** any model, deliberately. If the model arrives first it becomes the source of
/// truth by default, which is the wrong boundary — and a guard written afterwards is a guard that
/// can be skipped under time pressure. Everything here is pure, synchronous, and semantic-free:
/// no section ancestry, no notion of which part of a document "should" hold an objective. Those
/// rules need real model output to write, and are where rules would overfit to one corpus.
enum ExtractionAdmissibility {
    static let maximumCandidates = 2

    /// Coarse guardrails only. Codex: catch the indefensible, not the unusual — a measured 1,900
    /// character objective is absurd under any corpus, while a tight limit would silently blank
    /// correct values, and a safe failure is still a failure.
    private static let maximumTextLength = 600
    private static let maximumEmbeddedNewlines = 2
    private static let maximumListItems = 40
    private static let maximumListItemLength = 200
    private static let maximumSteps = 30
    /// A step's body is legitimately a few sentences; it is not a section. Without this a step
    /// note could be arbitrarily long as long as it appeared inside a large quote, which left the
    /// absurd-shape guard doing nothing for `.steps` (Codex, Batch 051 debrief).
    private static let maximumStepNotesLength = 600

    static func admit(
        _ proposal: ExtractionProposal, against document: SourceDocumentModel
    ) -> AdmittedExtraction {
        var rejections: [LessonFieldExtractor.Field: [AdmissionRejection]] = [:]

        guard proposal.schemaVersion == ExtractionProposal.currentSchemaVersion else {
            for field in proposal.candidates.keys { rejections[field] = [.unsupportedSchemaVersion] }
            return AdmittedExtraction(fields: [:], rejections: rejections)
        }

        // Pass one: the best candidate each field can defend on its own.
        var accepted: [LessonFieldExtractor.Field: AdmittedField] = [:]
        var exhausted: Set<LessonFieldExtractor.Field> = []
        var blocked: [LessonFieldExtractor.Field: Set<Int>] = [:]   // candidate indices ruled out

        func fill() {
            for (field, candidates) in proposal.candidates where accepted[field] == nil && !exhausted.contains(field) {
                guard candidates.count <= maximumCandidates else {
                    rejections[field, default: []].append(.tooManyCandidates)
                    exhausted.insert(field)
                    continue
                }
                var admitted: AdmittedField?
                for (index, candidate) in candidates.enumerated() where !(blocked[field]?.contains(index) ?? false) {
                    switch evaluate(candidate, for: field, against: document) {
                    case .success(let value):
                        admitted = value
                        blocked[field, default: []].insert(index)   // this one is now spent
                    case .failure(let reason):
                        rejections[field, default: []].append(reason)
                        blocked[field, default: []].insert(index)
                        continue
                    }
                    break
                }
                if let admitted { accepted[field] = admitted } else { exhausted.insert(field) }
            }
        }

        fill()

        // Pass two: exclusivity. Two fields resolving to the same span means the app cannot tell
        // which is right, so neither is kept — dropping only the lower-ranked one would import the
        // extractor's confidence into a layer whose whole job is not to trust it. Both fields then
        // get another turn with their remaining candidates.
        for _ in 0...maximumCandidates {
            let spans = Dictionary(grouping: accepted, by: { $0.value.span })
            let conflicts = spans.filter { $0.value.count > 1 }
            guard !conflicts.isEmpty else { break }
            for (_, group) in conflicts {
                for (field, _) in group {
                    rejections[field, default: []].append(.spanConflict)
                    accepted[field] = nil
                }
            }
            fill()
        }

        return AdmittedExtraction(fields: accepted, rejections: rejections)
    }

    private enum Outcome {
        case success(AdmittedField)
        case failure(AdmissionRejection)
    }

    private static func evaluate(
        _ candidate: ExtractedFieldCandidate,
        for field: LessonFieldExtractor.Field,
        against document: SourceDocumentModel
    ) -> Outcome {
        let citation = candidate.citation
        guard !citation.blockIDs.isEmpty, !citation.quote.isEmpty else { return .failure(.emptyCitation) }
        guard !candidate.value.isEmpty else { return .failure(.emptyValue) }
        guard Set(citation.blockIDs).count == citation.blockIDs.count else { return .failure(.duplicateBlockID) }

        // 1. Every cited block exists.
        var indices: [Int] = []
        for id in citation.blockIDs {
            guard let index = document.blocks.firstIndex(where: { $0.id == id }) else {
                return .failure(.unknownBlockID)
            }
            indices.append(index)
        }

        // 2. Cited blocks are contiguous and in document order. Concatenating non-adjacent blocks
        //    would invent adjacency that does not exist in the document, letting a quote span text
        //    the author never wrote next to each other.
        let sorted = indices.sorted()
        guard sorted == indices, sorted.last! - sorted.first! == sorted.count - 1 else {
            return .failure(.blocksNotContiguous)
        }

        // 3. Resolve through canonicalText, so real line breaks between blocks are included rather
        //    than papered over.
        let regionRange = document.blocks[sorted.first!].range.lowerBound..<document.blocks[sorted.last!].range.upperBound
        guard let regionText = document.text(at: regionRange) else { return .failure(.unknownBlockID) }

        // 4. The quote occurs exactly once in that region. More than once and the span is
        //    undetermined, which is a rejection rather than a coin flip.
        //
        //    Matched with whitespace collapsed on both sides, because a table row is tab-separated
        //    in canonical text and any sane extractor will quote it with spaces — requiring an
        //    exact match would reject every row citation in every document. The collapsed offsets
        //    map back to real positions so the resolved span still points into the raw text.
        let region = collapsingWhitespace(regionText)
        let needle = collapsingWhitespace(citation.quote).text
        let occurrences = occurrenceOffsets(of: needle, in: region.text)
        guard let first = occurrences.first else { return .failure(.quoteNotFound) }
        guard occurrences.count == 1 else { return .failure(.quoteAmbiguous) }

        // 5. The value must be contained in its own citation. This is what makes fabrication
        //    impossible rather than merely unlikely: a model can quote a real sentence and return
        //    a tidied paraphrase as the value, and the quote check alone would pass it.
        let haystack = collapsingWhitespace(citation.quote).text
        for asserted in candidate.value.assertedStrings {
            let assertedText = collapsingWhitespace(asserted).text
            guard !assertedText.isEmpty, haystack.contains(assertedText) else {
                return .failure(.valueNotInQuote)
            }
        }

        guard isPlausible(candidate.value) else { return .failure(.implausibleShape) }

        // Map the collapsed match back to real offsets in the document.
        let matchEnd = first + needle.count
        guard first < region.offsets.count, matchEnd - 1 < region.offsets.count else {
            return .failure(.quoteNotFound)
        }
        let start = regionRange.lowerBound + region.offsets[first]
        let end = regionRange.lowerBound + region.offsets[matchEnd - 1] + 1
        return .success(AdmittedField(value: candidate.value, span: start..<end, citation: citation))
    }

    /// Character offsets of every occurrence, so "exactly once" is checkable.
    private static func occurrenceOffsets(of needle: String, in haystack: String) -> [Int] {
        guard !needle.isEmpty else { return [] }
        var offsets: [Int] = []
        var searchStart = haystack.startIndex
        while let found = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
            offsets.append(haystack.distance(from: haystack.startIndex, to: found.lowerBound))
            searchStart = haystack.index(after: found.lowerBound)
        }
        return offsets
    }

    /// Collapses runs of whitespace to a single space, and records where each surviving character
    /// came from, so a match found in collapsed space can be reported as a real span.
    ///
    /// Nothing but whitespace is relaxed — the words themselves must match exactly.
    private static func collapsingWhitespace(_ text: String) -> (text: String, offsets: [Int]) {
        var collapsed = ""
        var offsets: [Int] = []
        var index = 0
        var pendingStart: Int?
        var pendingHasNewline = false
        for character in text {
            if character.isWhitespace {
                if !collapsed.isEmpty {
                    if pendingStart == nil { pendingStart = index }
                    if character.isNewline { pendingHasNewline = true }
                }
            } else {
                if let start = pendingStart {
                    // A run of whitespace containing a line break stays a line break. Collapsing it
                    // to a space would let a quote match *across* a real boundary — an extractor
                    // could quote an objective and the assessment beneath it as one contiguous
                    // string and be admitted. Horizontal whitespace still collapses, which is what
                    // the table-row case actually needs.
                    collapsed.append(pendingHasNewline ? "\n" : " ")
                    offsets.append(start)
                    pendingStart = nil
                    pendingHasNewline = false
                }
                collapsed.append(character)
                offsets.append(index)
            }
            index += 1
        }
        return (collapsed, offsets)
    }

    private static func isPlausible(_ value: ExtractedValue) -> Bool {
        switch value {
        case .text(let text):
            let newlines = text.filter(\.isNewline).count
            return text.count <= maximumTextLength && newlines <= maximumEmbeddedNewlines
        case .list(let items):
            return items.count <= maximumListItems && items.allSatisfy { $0.count <= maximumListItemLength }
        case .steps(let steps):
            return steps.count <= maximumSteps && steps.allSatisfy {
                $0.title.count <= maximumListItemLength && $0.notes.count <= maximumStepNotesLength
            }
        }
    }
}
