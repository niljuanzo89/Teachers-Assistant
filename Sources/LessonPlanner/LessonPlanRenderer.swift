import Foundation

enum LessonPlanRenderer {
    static func renderHTML(for lesson: LessonRecord) -> String {
        let steps = lesson.instructionalSequence.isEmpty
            ? "<p class=\"empty\">No instructional steps have been added.</p>"
            : "<ol>\(lesson.instructionalSequence.map(stepHTML).joined())</ol>"
        let materials = listHTML(lesson.materials, emptyMessage: "No materials listed.")
        let sources = listHTML(lesson.sourceReferences.map { URL(fileURLWithPath: $0).lastPathComponent }, emptyMessage: "Manually created lesson record.")

        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(escape(lesson.title)) — Lesson Plan</title>
          <style>
            :root { --ink:#201e1d; --muted:#6f6b69; --paper:#f3f2f2; --surface:#fff; --accent:#0088b0; --line:#d7d3d3; }
            * { box-sizing:border-box; } body { margin:0; background:var(--paper); color:var(--ink); font:15px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif; }
            main { max-width:980px; margin:0 auto; padding:48px 56px 72px; }
            header { display:flex; justify-content:space-between; gap:24px; align-items:flex-start; border-bottom:3px solid var(--accent); padding-bottom:24px; }
            h1 { font:700 38px/1.1 Georgia,serif; margin:0 0 8px; } h2 { font:700 20px/1.2 Georgia,serif; margin:0 0 10px; }
            .meta { color:var(--muted); font-size:13px; text-align:right; } .objective { font-size:18px; margin:26px 0; max-width:76ch; }
            .grid { display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:18px; } section { background:var(--surface); padding:22px; border:1px solid var(--line); border-radius:8px; }
            section.wide { grid-column:1/-1; } ol,ul { margin:0; padding-left:22px; } li + li { margin-top:10px; } .step-notes { color:var(--muted); font-size:14px; } .empty { margin:0; color:var(--muted); font-style:italic; }
            footer { margin-top:28px; color:var(--muted); font-size:12px; } @media print { body{background:white;} main{max-width:none;padding:0;} section{break-inside:avoid;} } @media(max-width:650px){ main{padding:28px 20px;} header{display:block;} .meta{text-align:left;margin-top:12px;} .grid{grid-template-columns:1fr;} }
          </style>
        </head>
        <body><main>
          <header><div><h1>\(escape(lesson.title))</h1><div>Lesson Plan</div></div><div class="meta">\(escape(lesson.subject.isEmpty ? "Subject not specified" : lesson.subject))<br>\(escape(lesson.gradeOrAgeRange.isEmpty ? "Grade not specified" : lesson.gradeOrAgeRange))</div></header>
          <p class="objective"><strong>Learning objective:</strong> \(escape(lesson.objective.isEmpty ? "Not specified" : lesson.objective))</p>
          <div class="grid">
            <section class="wide"><h2>Instructional sequence</h2>\(steps)</section>
            <section><h2>Materials</h2>\(materials)</section>
            <section><h2>Assessment / success check</h2><p>\(escape(lesson.assessmentSummary.isEmpty ? "Not specified" : lesson.assessmentSummary))</p></section>
            <section class="wide"><h2>Differentiation</h2><p>\(escape(lesson.differentiationSummary.isEmpty ? "Not specified" : lesson.differentiationSummary))</p></section>
            <section class="wide"><h2>Source provenance</h2>\(sources)</section>
          </div>
          <footer>Generated locally by LessonPlanner on \(Date.now.formatted(date: .long, time: .shortened)). Review and edit before classroom use.</footer>
        </main></body></html>
        """
    }

    private static func stepHTML(_ step: InstructionalStep) -> String {
        let notes = step.notes.isEmpty ? "" : "<div class=\"step-notes\">\(escape(step.notes))</div>"
        return "<li><strong>\(escape(step.title))</strong>\(notes)</li>"
    }

    private static func listHTML(_ items: [String], emptyMessage: String) -> String {
        guard !items.isEmpty else { return "<p class=\"empty\">\(escape(emptyMessage))</p>" }
        return "<ul>\(items.map { "<li>\(escape($0))</li>" }.joined())</ul>"
    }

    static func safeFileStem(_ text: String) -> String {
        let allowed = text.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        return allowed.trimmingCharacters(in: CharacterSet(charactersIn: "-")).isEmpty ? "lesson-plan" : allowed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    static func renderWeeklyHTML(plan: WeeklyPlan, lessons: [LessonRecord], generatedOutputs: [GeneratedOutputRecord] = []) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE\nMMM d"
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.dateFormat = "h:mm a"
        let days = (0..<5).compactMap { calendar.date(byAdding: .day, value: $0, to: plan.weekOf) }
        let lessonByID = Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) })
        let timeSlots = Dictionary(grouping: plan.assignments, by: { timeFormatter.string(from: $0.start) })
            .compactMap { _, assignments in assignments.map(\.start).min() }
            .sorted()
        let rows = timeSlots.isEmpty ? "<tr><td colspan=\"6\" class=\"empty\">No lessons have been scheduled for this week.</td></tr>" : timeSlots.map { slotStart in
            let matchingForTime = plan.assignments.first { timeFormatter.string(from: $0.start) == timeFormatter.string(from: slotStart) }
            let time = matchingForTime.map { "\(timeFormatter.string(from: $0.start))–\(timeFormatter.string(from: $0.end))" } ?? timeFormatter.string(from: slotStart)
            let cells = days.map { day -> String in
                let assignments = plan.assignments
                    .filter { calendar.isDate($0.date, inSameDayAs: day) && timeFormatter.string(from: $0.start) == timeFormatter.string(from: slotStart) }
                    .sorted { lhs, rhs in
                        let lhsTitle = lessonByID[lhs.lessonRecordID]?.title ?? ""
                        let rhsTitle = lessonByID[rhs.lessonRecordID]?.title ?? ""
                        return lhsTitle < rhsTitle
                    }
                guard !assignments.isEmpty else { return "<td></td>" }
                let blocks = assignments.compactMap { assignment -> String? in
                    guard let lesson = lessonByID[assignment.lessonRecordID] else { return nil }
                    let objective = lesson.objective.isEmpty ? "" : "<span>\(escape(lesson.objective))</span>"
                    let assignmentNotes = weeklyAssignmentNotesHTML(assignment.planningNotes)
                    let outputLinks = LessonOutputLinkSet.latest(for: lesson.id, in: generatedOutputs)
                    return "<div class=\"lesson-block\"><strong>\(escape(lesson.title))</strong>\(objective)\(assignmentNotes)\(weeklyOutputLinks(outputLinks))</div>"
                }.joined()
                return "<td>\(blocks)</td>"
            }.joined()
            return "<tr><th>\(escape(time))</th>\(cells)</tr>"
        }.joined()
        let headers = days.map { "<th>\(escape($0.formatted(.dateTime.weekday(.wide))))<br><span>\(escape($0.formatted(.dateTime.month().day())))</span></th>" }.joined()
        let brief = weeklyPlanningBriefHTML(plan.planningBrief)
        return """
        <!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Weekly Lesson Plan</title><style>
        :root{--ink:#201e1d;--muted:#6f6b69;--paper:#f3f2f2;--surface:#eae9e9;--accent:#0088b0;--accent2:#d6006c;--line:#d7d3d3}*{box-sizing:border-box}body{margin:0;background:var(--paper);color:var(--ink);font:15px/1.45 "Source Serif 4",Georgia,serif}main{width:1600px;max-width:100%;margin:0 auto;padding:56px 64px}header{display:flex;justify-content:space-between;align-items:baseline;margin-bottom:30px}h1{font:600 38px/1.12 Georgia,serif;margin:0}.sub{color:var(--muted);font-size:13px}.brief{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:14px;margin-bottom:24px}.brief section{background:var(--surface);border:1px solid var(--line);padding:16px}.brief h2{font:600 14px/1.2 Georgia,serif;margin:0 0 8px}.brief p{margin:0;color:var(--muted)}table{width:100%;border-collapse:collapse;table-layout:fixed;font-size:14px}th,td{border:1px solid var(--line);padding:10px;vertical-align:top;text-align:left}thead th{font-size:18px;letter-spacing:0;text-transform:none;background:transparent;color:var(--ink);font-weight:600}thead th:first-child{width:90px;font-size:11px;letter-spacing:.08em;text-transform:uppercase;color:var(--muted)}thead th span{display:block;margin-top:3px;font-size:11px;color:var(--muted);font-weight:400}tbody th{width:90px;color:var(--accent);font-size:11px;font-weight:600}td{min-height:104px}.lesson-block+.lesson-block{border-top:1px solid color-mix(in srgb,var(--ink) 8%,transparent);margin-top:10px;padding-top:10px}td strong{display:block;font-weight:600}td span{display:block;margin-top:4px;color:var(--muted);font-size:11px}.assignment-notes{margin:7px 0 0;color:var(--muted);font-size:11px}.links{margin-top:8px;display:flex;gap:10px;flex-wrap:wrap}.links a,.missing{font-size:11px}.links a{color:var(--accent);text-decoration:none}.missing{color:var(--muted)}.empty{text-align:center;color:var(--muted);font-style:italic;padding:32px}@media print{body{background:white}main{max-width:none;padding:0}.links a{color:var(--ink);text-decoration:underline}}@media(max-width:800px){main{padding:28px 20px}.brief{grid-template-columns:1fr}header{display:block}}
        </style></head><body><main><header><div><h1>Weekly Lesson Plan</h1><div class="sub">Week of \(escape(plan.weekOf.formatted(date: .long, time: .omitted)))</div></div><div class="sub">Generated locally by LessonPlanner</div></header>\(brief)<table><thead><tr><th>Time</th>\(headers)</tr></thead><tbody>\(rows)</tbody></table></main></body></html>
        """
    }

    private static func weeklyPlanningBriefHTML(_ brief: WeeklyPlanningBrief?) -> String {
        guard let brief, brief.hasContent else { return "" }
        return """
        <div class="brief">
          \(briefCard(title: "Teacher focus", value: brief.teacherFocus))
          \(briefCard(title: "Preparation notes", value: brief.preparationNotes))
          \(briefCard(title: "Student supports", value: brief.studentSupportNotes))
        </div>
        """
    }

    private static func briefCard(title: String, value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "<section><h2>\(escape(title))</h2><p class=\"empty\">Not specified.</p></section>" }
        return "<section><h2>\(escape(title))</h2><p>\(escape(trimmed))</p></section>"
    }

    private static func weeklyAssignmentNotesHTML(_ notes: String?) -> String {
        let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return "" }
        return "<p class=\"assignment-notes\">\(escape(trimmed))</p>"
    }

    private static func weeklyOutputLinks(_ links: LessonOutputLinkSet) -> String {
        let rows = [
            outputLink(label: "Lesson plan", output: links.lessonPlanHTML),
            outputLink(label: "Slide deck", output: links.slideDeckPPTX),
            outputLink(label: "Differentiation guide", output: links.differentiationGuideHTML)
        ].joined()
        return "<div class=\"links\">\(rows)</div>"
    }

    private static func outputLink(label: String, output: GeneratedOutputRecord?) -> String {
        guard let output else { return "<div class=\"missing\">\(escape(label)): not generated</div>" }
        return "<a href=\"\(fileHref(output.filePath))\">\(escape(label))</a>"
    }

    private static func fileHref(_ path: String) -> String {
        URL(fileURLWithPath: path).absoluteString
    }

    static func renderDifferentiationGuideHTML(for lesson: LessonRecord) -> String {
        let summary = lesson.differentiationSummary.isEmpty ? "No differentiation notes have been entered yet." : escape(lesson.differentiationSummary)
        let prompt = lesson.printableResourcePrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        let studentPrompt = prompt?.isEmpty == false ? escape(prompt!) : escape(lesson.objective.isEmpty ? "Show what you learned in this lesson." : lesson.objective)
        let materials = listHTML(lesson.materials, emptyMessage: "No materials listed.")
        return """
        <!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>\(escape(lesson.title)) — Differentiation Guide</title><style>
        :root{--ink:#201e1d;--muted:#6f6b69;--paper:#f3f2f2;--surface:#fff;--accent:#d6006c;--line:#d7d3d3}*{box-sizing:border-box}body{margin:0;background:var(--paper);color:var(--ink);font:15px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}main{max-width:950px;margin:0 auto;padding:48px 56px}header{border-bottom:3px solid var(--accent);padding-bottom:22px;margin-bottom:24px}h1,h2{font-family:Georgia,serif}h1{font-size:36px;margin:0 0 8px}h2{font-size:21px;margin:0 0 10px}.sub,.muted{color:var(--muted)}section{background:var(--surface);border:1px solid var(--line);border-radius:8px;padding:22px;margin:18px 0}.printable{margin-top:36px;border:2px dashed var(--accent);background:white}.student-lines{height:210px;border-top:1px solid var(--line);background:repeating-linear-gradient(transparent,transparent 33px,#d7d3d3 34px)}ul{margin:0;padding-left:22px}@media print{body{background:white}main{max-width:none;padding:0}.printable{break-before:page;margin-top:0;border:0}.student-lines{height:420px}}
        </style></head><body><main><header><h1>\(escape(lesson.title))</h1><div class="sub">Differentiation Guide · \(escape(lesson.subject.isEmpty ? "Subject not specified" : lesson.subject))</div></header><section><h2>Learning objective</h2><p>\(escape(lesson.objective.isEmpty ? "Not specified" : lesson.objective))</p></section><section><h2>Teacher differentiation notes</h2><p>\(summary)</p></section><section><h2>Materials and resource provenance</h2>\(materials)</section><section><h2>Success check</h2><p>\(escape(lesson.assessmentSummary.isEmpty ? "Not specified" : lesson.assessmentSummary))</p></section><section class="printable"><h2>Student Practice / Exit Ticket</h2><p><strong>Name:</strong> ________________________________ <strong>Date:</strong> __________________</p><p><strong>Prompt:</strong> \(studentPrompt)</p><div class="student-lines"></div></section></main></body></html>
        """
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
