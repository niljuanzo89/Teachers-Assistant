import XCTest
@testable import LessonPlanner

/// Batch F — enforces the Batch 047 invariant instead of relying on someone remembering it.
///
/// Lesson content must be written through an intent-named method (`updateLessonFromTeacherEdit`
/// or `updateLessonFromAutomaticSync`), because those are what decide provenance and whether an
/// inference marker survives. Provenance in turn decides whether `rebuildDerivedPlanningData`
/// may delete the record. A view that mutates `lessons` directly silently opts out of all of it.
///
/// The invariant held when written only because every path was checked by hand — which lasts
/// exactly until the next view is added. This test is that check, run every time.
final class LessonWritePathTests: XCTestCase {

    /// Only `AppStore` may write the lesson collection.
    private let permittedFile = "AppStore.swift"

    private let forbiddenPatterns = [
        "lessons.append(",
        "lessons[index] =",
        "saveLessons()"
    ]

    func testLessonWritesAreConfinedToAppStore() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // LessonPlannerTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // package root
            .appending(path: "Sources/LessonPlanner")

        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        XCTAssertFalse(files.isEmpty, "found no sources to scan — the path above is wrong")

        var violations: [String] = []
        for file in files where file.lastPathComponent != permittedFile {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for (offset, line) in text.components(separatedBy: .newlines).enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//"), !code.hasPrefix("///") else { continue }
                for pattern in forbiddenPatterns where code.contains(pattern) {
                    violations.append("\(file.lastPathComponent):\(offset + 1) — \(pattern)")
                }
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            """
            Lesson content was written outside AppStore, bypassing the intent-named write methods.
            Route the change through updateLessonFromTeacherEdit (a teacher's change: takes
            ownership of the record and clears inference markers on fields they rewrote) or
            updateLessonFromAutomaticSync (a derivation pass: preserves both).

            \(violations.joined(separator: "\n"))
            """
        )
    }
}
