import Foundation

/// One addressable piece of a source document.
///
/// This is the contract an extractor answers *against*: a field's value has to cite the block it
/// came from, so the app can check the citation rather than trust the answer. `SourceTextLine`
/// says what a line *is*; a block adds the three things a citation needs — identity, position in
/// the document, and (later) where it sits in the section hierarchy.
struct SourceBlock: Equatable, Identifiable {
    enum Kind: String, Equatable {
        case blank
        case paragraph
        case tableRow
        case listItem
    }

    /// Stable within one `SourceDocumentModel`, ordinal (`b0`, `b1`, …).
    ///
    /// Deliberately **not** content-derived. Real documents repeat themselves — "5 min",
    /// "Exit Ticket", "Practice" — so a content hash would collide exactly where precision matters.
    var id: String
    var kind: Kind

    /// The exact substring of `canonicalText` at `range`, tabs and all.
    ///
    /// Kept separate from `line` on purpose. `SourceTextLine.text` joins a row's cells with spaces
    /// for display, while the canonical text separates them with tabs — so a validator comparing a
    /// citation against the wrong one of those would fail on every table row in the document.
    /// **Validate against `rawText`; show or prompt with `line`.**
    var rawText: String

    /// Character offsets into `SourceDocumentModel.canonicalText`.
    var range: Range<Int>

    /// PDF only, and not populated yet.
    var page: Int?

    /// Section ancestry, outermost first. **Deliberately empty for now.**
    ///
    /// Heading inference from text shape would manufacture confidence the app has not earned:
    /// DOCX style information is discarded during extraction and PDF layout is flattened, so any
    /// heading here would be a guess dressed as structure. An empty path says "unknown", which is
    /// true. It gets filled when a measured need appears, not before.
    var headingPath: [String]

    /// The parsed line, so a row's cells stay reachable.
    var line: SourceTextLine
}

/// A document as a list of addressable blocks, over the same canonical text everything else uses.
///
/// Transient and derived — `ImportedSource.extractedText` remains the persisted `String`, so no
/// stored data, span offset, or existing consumer changes shape.
struct SourceDocumentModel {
    /// The text every offset in `blocks` points into. Identical to the source's `extractedText`
    /// except that line endings are normalized to LF — see `normalizingLineEndings`.
    var canonicalText: String
    var blocks: [SourceBlock]

    /// Every line becomes a block, **including blank ones**.
    ///
    /// Codex's review suggested skipping blanks. They have to stay: the field extractor uses a
    /// blank line as a value terminator, so dropping them here would silently change extraction
    /// the moment a caller switched to `blocks.map(\.line)`. Keeping them means the block list and
    /// the line list are the same sequence, and this layer adds addressing without altering
    /// behaviour. Blank blocks simply are not offered to an extractor as evidence.
    static func build(from extractedText: String) -> SourceDocumentModel {
        let canonical = Self.normalizingLineEndings(extractedText)
        let lines = canonical.components(separatedBy: .newlines)
        let parsed = SourceTextLine.parse(canonical)
        var blocks: [SourceBlock] = []
        blocks.reserveCapacity(lines.count)

        var offset = 0
        for (index, raw) in lines.enumerated() {
            let length = raw.count
            let line = index < parsed.count ? parsed[index] : .blank
            blocks.append(SourceBlock(
                id: "b\(index)",
                kind: kind(of: line, raw: raw),
                rawText: raw,
                range: offset..<(offset + length),
                page: nil,
                headingPath: [],
                line: line
            ))
            offset += length + 1   // + the newline that `components` consumed
        }
        return SourceDocumentModel(canonicalText: canonical, blocks: blocks)
    }

    /// Collapses CRLF and lone CR to LF before anything measures an offset.
    ///
    /// Without this the arithmetic above is wrong on Windows-authored text, and wrong in a way
    /// that looks fine until a citation is checked. Swift counts `\r\n` as **one** `Character`,
    /// but `components(separatedBy: .newlines)` splits on unicode scalars and so treats it as
    /// **two** separators — yielding a phantom empty line and shifting every subsequent block's
    /// range off the end of the document. Caught by Codex in the Batch 050 debrief.
    private static func normalizingLineEndings(_ text: String) -> String {
        // No `contains("\r")` fast path: Swift treats `\r\n` as a single grapheme cluster, so
        // `"A\r\nB".contains("\r")` is **false** and such a guard skips the very input it exists
        // for. Comparing unicode scalars is the reliable test.
        guard text.unicodeScalars.contains("\r") else { return text }
        return text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private static func kind(of line: SourceTextLine, raw: String) -> SourceBlock.Kind {
        switch line {
        case .blank: return .blank
        case .tableRow: return .tableRow
        case .paragraph(let text):
            let opener = text.prefix(2)
            let bulleted = opener.hasPrefix("•") || opener.hasPrefix("-") || opener.hasPrefix("*")
            let numbered = text.range(of: #"^\d{1,2}[.)]\s"#, options: .regularExpression) != nil
            return bulleted || numbered ? .listItem : .paragraph
        }
    }

    /// Blocks an extractor may cite. Blank lines carry no evidence.
    var citableBlocks: [SourceBlock] { blocks.filter { $0.kind != .blank } }

    func block(id: String) -> SourceBlock? { blocks.first { $0.id == id } }

    /// The text actually at a block's claimed range — the check a citation has to pass.
    /// Returns nil when the range no longer fits the text, rather than trapping.
    func text(at range: Range<Int>) -> String? {
        // `Range` already guarantees lowerBound <= upperBound, so only the document bounds
        // need checking.
        guard range.lowerBound >= 0, range.upperBound <= canonicalText.count else { return nil }
        let start = canonicalText.index(canonicalText.startIndex, offsetBy: range.lowerBound)
        let end = canonicalText.index(canonicalText.startIndex, offsetBy: range.upperBound)
        return String(canonicalText[start..<end])
    }

    /// The lines the deterministic parser consumes. Identical to `SourceTextLine.parse` over the
    /// same text — asserted by test, because "adds structure, changes nothing" is the whole
    /// acceptance criterion for this layer.
    var lines: [SourceTextLine] { blocks.map(\.line) }
}
