import Foundation

/// One line of extracted source text, with the document's table structure still attached.
///
/// Extraction keeps a table row on a single line with tab-separated cells (see
/// `AppStore.flattenWordXML`). This type is where the parser *reads* that structure instead of
/// guessing it back from a keyword list — the guessing is what produced five instances of one
/// defect class across Batches 046-048.
///
/// Transient by design. Nothing here is persisted; `ImportedSource.extractedText` stays a plain
/// `String`, so every existing consumer, every stored span offset, and the review UI are unchanged.
enum SourceTextLine: Equatable {
    case blank
    case paragraph(String)
    case tableRow(cells: [String])

    static func parse(_ text: String) -> [SourceTextLine] {
        text.components(separatedBy: .newlines).map { rawLine in
            guard rawLine.contains("\t") else {
                let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? .blank : .paragraph(trimmed)
            }
            // Trailing empty cells are an artifact of the row's closing tab, not real columns.
            var cells = rawLine.components(separatedBy: "\t")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            while cells.last?.isEmpty == true { cells.removeLast() }
            if cells.allSatisfy(\.isEmpty) { return .blank }
            return .tableRow(cells: cells)
        }
    }

    /// The line as flat text, for the many checks that legitimately do not care about structure.
    var text: String {
        switch self {
        case .blank: return ""
        case .paragraph(let value): return value
        case .tableRow(let cells): return cells.joined(separator: " ")
        }
    }

    var isBlank: Bool { self == .blank }

    /// A row's leading cell — the label or row-heading candidate. Nil for prose.
    var headingCell: String? {
        guard case .tableRow(let cells) = self else { return nil }
        return cells.first
    }

    /// A row's trailing cell — the value. **Not** the concatenation of everything after the first
    /// cell: in a `Part | Time | Actions` table the middle cell is timing, and merging it into the
    /// value is exactly the pollution this type exists to prevent.
    var valueCell: String? {
        guard case .tableRow(let cells) = self, cells.count >= 2 else { return nil }
        return cells.last
    }

    var cellCount: Int {
        guard case .tableRow(let cells) = self else { return 0 }
        return cells.count
    }

    /// A two-cell row is a label/value pair ("Objective | Read, write, and compare..."). A wider
    /// row is tabular data, where the leading cell is a row *heading* rather than a field label —
    /// which is why an "Exit Ticket" row in a three-column procedure table must not be read as the
    /// lesson's assessment. That distinction is structural, so it needs no vocabulary.
    var isLabelValueRow: Bool { cellCount == 2 }

    var cells: [String]? {
        guard case .tableRow(let cells) = self else { return nil }
        return cells
    }
}

/// A contiguous block of table rows — one actual table in the document.
///
/// Rows alone were not enough. Judging a row on its own forced two guesses: a character-count
/// threshold to tell a header from a data row, and a global "two or more wide rows anywhere in the
/// document means these are the phases" rule. The first is a magic number; the second lets an
/// unrelated table elsewhere in the document become the instructional sequence. Both disappear
/// once the table itself is the unit.
struct SourceTableRun {
    /// Index of the first row in the `[SourceTextLine]` this run was found in.
    var startIndex: Int
    var headerCells: [String]?
    var dataRows: [[String]]

    var columnCount: Int { dataRows.first?.count ?? headerCells?.count ?? 0 }

    /// A procedure table: three or more columns and at least two data rows. Two columns is a
    /// label/value table, and a single row is not a sequence.
    var looksLikeProcedure: Bool { columnCount >= 3 && dataRows.count >= 2 }

    /// Whether some column is a duration ("5 min", "10", "45 minutes"). This is what separates a
    /// lesson's procedure table from a pacing grid, whose middle column holds dates — both are
    /// wide tables of prose, and row count alone picks whichever happens to be longer.
    var hasDurationColumn: Bool {
        guard columnCount >= 2 else { return false }
        return (0..<columnCount).contains { column in
            let values = dataRows.compactMap { $0.indices.contains(column) ? $0[column] : nil }
            guard !values.isEmpty else { return false }

            let explicit = values.filter {
                $0.range(of: #"^\d{1,3}\s*(min|mins|minute|minutes|hr|hour|hours)\.?$"#,
                         options: [.regularExpression, .caseInsensitive]) != nil
            }
            if explicit.count * 2 >= values.count { return true }

            // A column of bare numbers is a duration only when its header says so. Without that,
            // a pacing grid's "Lesson" column of 1, 2, 3 reads as timing and the grid impersonates
            // a procedure table — which would name the phases "1", "2", "3".
            guard let header = headerCells, header.indices.contains(column) else { return false }
            let named = header[column].lowercased()
            guard Self.timeHeaderWords.contains(where: named.contains) else { return false }
            let bare = values.filter { $0.range(of: #"^\d{1,3}$"#, options: .regularExpression) != nil }
            return bare.count * 2 >= values.count
        }
    }

    private static let timeHeaderWords = ["time", "min", "duration", "length"]

    /// Contiguous runs of table rows, each split into an optional header and its data rows.
    static func runs(in lines: [SourceTextLine]) -> [SourceTableRun] {
        var runs: [SourceTableRun] = []
        var index = 0
        while index < lines.count {
            guard lines[index].cells != nil else {
                index += 1
                continue
            }
            let start = index
            var rows: [[String]] = []
            while index < lines.count, let cells = lines[index].cells {
                rows.append(cells)
                index += 1
            }
            runs.append(SourceTableRun(start: start, rows: rows))
        }
        return runs
    }

    private init(start: Int, rows: [[String]]) {
        startIndex = start
        // The first row is a header when its cells are consistently *shorter* than the same
        // column below it — relative to this table, so a terse procedure table and a verbose
        // header ("Teacher and Student Actions / Anticipated Responses") are both judged on the
        // same footing rather than against a fixed character count. A table with no header keeps
        // all its rows.
        guard rows.count >= 3, let first = rows.first,
              Self.readsAsHeader(first, above: Array(rows.dropFirst())) else {
            headerCells = nil
            dataRows = rows
            return
        }
        headerCells = first
        dataRows = Array(rows.dropFirst())
    }

    /// A header row names its columns; a data row states something. So the test is sentence
    /// punctuation, not length.
    ///
    /// Length was the first attempt and it fails on exactly the tables this exists for: a header
    /// naming a short column is *longer* than its own data ("Min" over "5", "Lesson" over "1"),
    /// so a length rule refuses to see the header and keeps it as a phase.
    private static func readsAsHeader(_ candidate: [String], above body: [[String]]) -> Bool {
        let sameShape = body.allSatisfy { $0.count == candidate.count }
        guard sameShape, !candidate.allSatisfy(\.isEmpty) else { return false }

        // Judge the *prose* column only. Testing every cell fails on an abbreviated column name —
        // "Est. Time." ends in a period, so an any-cell rule rejects a real header and promotes it
        // to a phase. The sentence/label distinction is only meaningful where sentences live.
        guard let prose = proseColumn(of: body), candidate.indices.contains(prose) else { return false }
        guard !endsASentence(candidate[prose]) else { return false }
        // Require the body to actually read as sentences, so a table of terse values throughout
        // keeps its first row rather than losing it to a header that was never there.
        let sentenceRows = body.filter { $0.indices.contains(prose) && endsASentence($0[prose]) }
        return sentenceRows.count * 2 >= body.count
    }

    /// The column carrying the longest typical content — a table's prose column.
    private static func proseColumn(of body: [[String]]) -> Int? {
        guard let width = body.first?.count, width > 0 else { return nil }
        return (0..<width).max { left, right in
            medianLength(of: body, column: left) < medianLength(of: body, column: right)
        }
    }

    private static func medianLength(of body: [[String]], column: Int) -> Int {
        let lengths = body.compactMap { $0.indices.contains(column) ? $0[column].count : nil }.sorted()
        return lengths.isEmpty ? 0 : lengths[lengths.count / 2]
    }

    private static func endsASentence(_ cell: String) -> Bool {
        guard let last = cell.last else { return false }
        return last == "." || last == "!" || last == "?"
    }
}
