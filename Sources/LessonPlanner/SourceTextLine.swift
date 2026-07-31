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

    /// A data row in a multi-column table: at least three cells, and at least one of them long
    /// enough to be prose rather than a column name. The header row of such a table has short
    /// cells throughout ("Part", "Time", "Teacher and Student Actions"), so this excludes it
    /// without needing to know that the first row is a header.
    var isWideDataRow: Bool {
        guard cellCount >= 3, case .tableRow(let cells) = self else { return false }
        return cells.contains { $0.count >= Self.proseCellLength }
    }

    private static let proseCellLength = 40
}
