# LessonPlanner Build Log

## Project purpose

LessonPlanner is a local-first macOS application for turning teacher-reviewed source material into an editable lesson package. The generic product shell does not contain curriculum, student data, school templates, or school-specific configuration.

## Development record

### 2026-07-26 — Phase Zero: product architecture

- Defined a native macOS SwiftUI application rather than a local web app.
- Established one approved lesson record as the source of truth for all outputs.
- Chose local PDF text extraction and teacher review as the default workflow.
- Defined three aligned outputs: lesson plan, slide deck, and differentiation guide with printable material.
- Established that external generative AI is optional, never required for core planning or output generation.

### 2026-07-27 — Phase One: local planner foundation

- Built the native LessonPlanner app shell with daily schedule and checklist support.
- Added persistent local storage for configuration, sources, lessons, daily plans, weekly plans, and generated-output history.
- Added PDF import, locally extracted text review, and manual draft creation.
- Added a reviewed-source workflow: imported text must be reviewed before it can become a lesson draft.

### 2026-07-27 — AI-assisted draft test

- Added an optional personal Codex CLI draft workflow.
- Tested it with a schedule source and added guardrails that classify schedules and intentionally leave instructional fields blank.
- Tested it with a lesson-guide source and confirmed that the resulting draft remained unapproved until teacher review.
- Added visible review warnings for uncertain PDF extraction, source classification, and unsupported assumptions.

### 2026-07-27 — Approved-output test

- Approved one reviewed test lesson after review.
- Generated and verified local HTML lesson-plan and differentiation-guide outputs.
- Generated and visually verified a seven-slide editable PowerPoint prototype from the approved lesson record.
- Deferred image, diagram, handwriting, and scanned-page understanding; PDF text extraction may omit or distort visual content and mathematical notation.

### 2026-07-27 — Personal PowerPoint bridge

- Replaced the one-off PowerPoint prototype script with a parameterized in-app export action for approved lessons.
- The app sends only the approved lesson fields to a bundled local generator script; it does not transmit source text or call a hosted AI service.
- The generator uses the owner’s existing local Codex presentation runtime, produces a seven-slide editable PowerPoint deck, adds local-record provenance to slide notes, and records the result in output history.
- Built the Xcode app successfully and verified the packaged generator with a non-sensitive sample payload. Visual rendering could not run in this environment because its optional PDF rendering dependency is unavailable; structural inspection found seven slides and no out-of-bounds elements.

### 2026-07-28 — Source-readiness guidance

- Added a local source-readiness report to the Import Source workspace.
- The app now distinguishes selectable text, OCR text, empty/OCR-required sources, and likely math/visual-symbol content.
- It explicitly tells the teacher when diagrams, handwriting, page layout, tables, or math notation must be checked against the original PDF rather than being silently trusted as extracted text.

### 2026-07-28 — Structured visual and math review

- Replaced the general source-readiness warning with named review focus categories for OCR transcription, math notation, and visual layout.
- Each category now gives the teacher a concrete comparison task against the original PDF without treating detection as certainty.
- Added tests for OCR/math risk reporting, selectable fraction notation, and visual-layout markers.
- Generated a generic local PowerPoint sample through the personal bridge, rendered it locally, confirmed seven editable slides with source notes, and found no slide overflow.

### 2026-07-28 — PowerPoint exporter resilience

- Hardened the personal PowerPoint generator for longer lesson titles, objectives, differentiation notes, and assessment summaries.
- Added variable instructional-step chunking so longer lessons create continuation practice slides instead of silently dropping later steps.
- Replaced the prominent Google Slides QA deck in the project folder with the hardened generic sample.
- Validated the normal sample as seven slides with seven source-note pages and no overflow; validated a long-text stress sample as eight slides with eight source-note pages and no overflow.

### 2026-07-28 — In-app slide generation path test

- Added an internal slide-generator seam so the app still uses the personal PowerPoint bridge by default while tests can verify the AppStore output path without touching real app-support data.
- Added tests proving approved lessons generate a slide-deck output record with the expected lesson fields and draft lessons are refused before deck generation.

### 2026-07-28 — Personal exporter diagnostics

- Added a personal PowerPoint exporter availability check for the local Node runtime, presentation runtime, and bundled generator script.
- Surfaced the diagnostic in the lesson output controls and disabled the personal PowerPoint button when the bridge is unavailable.
- Split lesson output controls into a smaller SwiftUI view to keep the lesson editor easier for the compiler and future maintenance.

### 2026-07-28 — Lesson export readiness checklist

- Added a derived export-readiness report for approved lesson outputs; it does not change persistence.
- The lesson editor now distinguishes required output fields from advisory review items before generation.
- Output generation buttons remain unavailable until required lesson fields are present, while save and teacher approval remain teacher-controlled actions.
- Added tests for incomplete and complete generic lesson readiness.

### 2026-07-28 — Output manual QA review record

- Added optional review metadata to generated-output history so existing output records remain readable.
- Added a lightweight checklist and “Mark reviewed” action for generated outputs after local visual/manual inspection.
- Added generated-output history review controls in Workspace and review controls for the latest generated lesson output.
- Added tests for legacy output decoding and persisted review marking.

### 2026-07-28 — Sellable exporter boundary

- Added `SELLABLE_POWERPOINT_EXPORTER_BOUNDARY.md` to separate the current personal PowerPoint bridge from a supported customer-facing exporter.
- Documented sellable-version requirements, migration steps, explicit non-goals, and the current personal-exporter validation status.

### 2026-07-28 — Supported exporter strategy decision

- Added `POWERPOINT_EXPORTER_STRATEGY_ADR.md`.
- Chose a native Swift Open XML PowerPoint exporter as the supported sellable path.
- Rejected the current personal bridge, bundled Node, external office automation, and server-side conversion as default customer-facing strategies.
- Linked the decision from the sellable exporter boundary and roadmap.

### 2026-07-28 — Native PowerPoint exporter first slice

- Added `NativePowerPointExporter.swift`, a Swift Open XML `.pptx` package writer that emits a minimal editable PowerPoint lesson deck from an approved lesson record.
- Added core package parts for content types, relationships, presentation, theme, slide master/layout, slide content, and notes with local source provenance markers.
- Added a basic native slide arc covering title/objective, instructional sequence, materials/supports, and assessment.
- Added regression coverage for package creation, expected PresentationML parts, multi-slide lesson-content inclusion, and XML escaping.
- Kept the personal PowerPoint bridge as the default app exporter while the native exporter is hardened toward sellable-version readiness.

### 2026-07-28 — Native PowerPoint exporter QA artifact

- Added `Tools/GenerateNativePowerPointQAFixture.swift` for producing a generic local QA deck from the native exporter.
- Generated `Native PowerPoint Exporter QA Deck.pptx` in the project working folder.
- Rendered the native deck locally to `Native PowerPoint Exporter QA Deck/` and inspected the contact sheet plus a full-size slide.
- Ran the slide overflow check; result passed with no overflow detected.

### 2026-07-28 — Native exporter app wiring

- Added a persisted PowerPoint exporter preference with two choices: native Swift Open XML exporter and personal development-runtime bridge.
- Made the native exporter the default app path for normal workspace use while keeping the personal bridge selectable for QA.
- Added Workspace UI for choosing the exporter and surfacing the active exporter availability.
- Added regression coverage for native default behavior and exporter preference persistence.
- Verified with `swift test` (27 tests passing) and a Debug Xcode build.
- Regenerated `Native PowerPoint Exporter QA Deck.pptx`, rendered it locally, and re-ran the slide overflow check; result passed with no overflow detected.

### 2026-07-28 — Native exporter classroom-content pass

- Extended the native PowerPoint exporter to include instructional-step notes instead of only step titles.
- Added a Student Practice slide when the approved lesson includes a printable/student prompt.
- Added local source-reference paths to slide speaker notes inside the existing `[Sources]` block.
- Added an end-to-end AppStore test proving normal slide-deck generation uses the native exporter by default.
- Updated the generic QA fixture to include step notes, a student-practice prompt, and a non-sensitive local source reference.
- Verified with `swift test` (28 tests passing) and a Debug Xcode build.
- Regenerated `Native PowerPoint Exporter QA Deck.pptx`, rendered five slides locally, created `Native PowerPoint Exporter QA Contact Sheet.png`, inspected the densest slide at full size, and re-ran the slide overflow check; result passed with no overflow detected.

### 2026-07-28 — Release readiness and template foundation

- Added default lesson-field slot mappings for future presentation templates, including title, objective, instructional sequence, materials, differentiation, student practice, and assessment.
- Added presentation-template registration in Workspace; registered templates retain layout-preservation intent and default lesson-field mappings.
- Added a Workspace release-readiness checklist covering setup, output folder, native exporter selection, approved lessons, reviewed PowerPoint outputs, and presentation-template readiness.
- Expanded generated-output review checklists so PowerPoint decks explicitly call for PowerPoint/compatible-viewer opening, speaker-note provenance review, and Google Slides conversion checks when applicable.
- Added tests for presentation-template mapping registration, PowerPoint review checklist content, and release-readiness reporting.
- Verified with `swift test` (32 tests passing) and a Debug Xcode build.

### 2026-07-28 — Weekly package hub alignment

- Updated weekly HTML generation so each scheduled lesson can display links to its three main outputs: lesson plan, slide deck, and differentiation guide.
- Added a weekly package generator that creates missing lesson outputs for scheduled approved lessons before writing the weekly hub document.
- Added a planning-week picker in the weekly planner so the teacher can choose the week being documented.
- Renamed the weekly generation action to “Generate weekly package” to match the final product concept.
- Added tests for weekly output links and end-to-end weekly package generation.
- Updated the roadmap and README to reflect the clarified final goal: weekly planning schedule as the container for the three per-lesson outputs.
- Verified with `swift test` (34 tests passing) and a Debug Xcode build.

### 2026-07-28 — Weekly package readiness and teacher prompts

- Split the weekly planner date inputs into a planning-week date and a lesson-day date so the teacher can document the intended week before assigning lessons inside it.
- Added a weekly package readiness report that blocks generation when the schedule is empty, scheduled lessons are missing, or scheduled lessons are not approved.
- Kept missing per-lesson outputs as an advisory item: the weekly package generator can still create missing lesson plans, slide decks, and differentiation guides before linking them.
- Added per-scheduled-lesson output status indicators for Plan, Deck, and Guide in the weekly schedule list.
- Added tests for empty-schedule blocking, approved lessons with missing outputs, complete output counting, and weekly package generation refusal when no lessons are scheduled.
- Verified with `swift test` (38 tests passing) and a Debug Xcode build.

### 2026-07-28 — Recurring weekly prompt preference

- Added a persisted weekly planning prompt preference with on/off state, weekday, and time.
- Added next-prompt date calculation so the app can show the next intended weekly planning prompt target.
- Surfaced the weekly prompt summary and next prompt target inside the weekly planner.
- Added Workspace controls for changing the weekly prompt day/time without editing configuration files.
- Added tests for preference persistence and next-prompt date calculation.
- Verified with `swift test` (40 tests passing) and a Debug Xcode build.

### 2026-07-28 — In-app weekly prompt surface

- Added weekly prompt due-state evaluation from the saved weekday/time preference and the last handled prompt.
- Added a top-of-workspace in-app weekly planning prompt banner when the teacher's prompt target is due.
- Added prompt actions to open the weekly planner or dismiss the prompt for the current cycle.
- Persisted the last handled prompt timestamp so the prompt does not keep reappearing after the teacher responds.
- Added tests for due prompt detection, handled prompt suppression, and prompt-handled persistence.
- Verified with `swift test` (43 tests passing) and a Debug Xcode build.

### 2026-07-28 — Template-aware slide export first slice

- Extended the slide-deck generator interface so deck export receives the active registered presentation template.
- Made slide-deck output history record the active presentation template display name.
- Added native PowerPoint speaker-note provenance for the active presentation template path and default lesson-field mappings.
- Surfaced the active presentation template in lesson output controls before deck generation.
- Kept true template layout preservation as a later exporter-hardening step; this slice establishes template context, mapping traceability, and output-history linkage.
- Added tests for registered-template deck generation and native PowerPoint template provenance.
- Verified with `swift test` (45 tests passing) and a Debug Xcode build.

### 2026-07-28 — Template fidelity readiness gates

- Reviewed the template-following contract for true PowerPoint template preservation: source-slide inventory, frame mapping, inherited placeholder handling, and fidelity QA are required.
- Added a presentation-template readiness report that distinguishes template provenance readiness from true layout-preservation readiness.
- Added Workspace UI showing mapped fields, required mappings, and the remaining layout-inventory/fidelity gate.
- Expanded PowerPoint output review checklist items for template provenance and avoiding false claims of layout preservation.
- Added release-readiness attention for template layout fidelity until inventory, frame mapping, and QA exist.
- Added tests for missing-template readiness, default-mapping readiness, and the expanded PowerPoint checklist.
- Verified with `swift test` (47 tests passing) and a Debug Xcode build.

### 2026-07-28 — Template layout inventory and frame-map records

- Added persisted presentation-template layout-plan records with slide inventory, frame-map entries, fidelity-review status, and update time.
- Added source-slide inventory items for source slide number, reusable role, inherited placeholder count, and notes.
- Added frame-map entries for output slide number, source slide number, narrative role, mapped slot names, and notes.
- Added AppStore support for saving a registered presentation template's layout plan.
- Updated template readiness so true layout preservation requires required mappings, slide inventory, frame map, and fidelity QA.
- Updated Workspace template readiness display with inventoried-slide and frame-map counts.
- Added tests for complete layout-plan readiness, incomplete frame-map/fidelity readiness, and persisted layout-plan records.
- Verified with `swift test` (50 tests passing) and a Debug Xcode build.

### 2026-07-28 — Presentation template inspection first slice

- Added a lightweight PowerPoint template inspector that reads slide XML entries from registered `.pptx` packages.
- Added support for stored and compressed ZIP entries so normal PowerPoint packages can be inspected for basic slide structure.
- Added initial slide-inventory candidate generation with source slide numbers, inferred reusable roles, placeholder counts, and inspection notes.
- Added initial frame-map candidate generation that links intended output slides back to source template slides and likely lesson slots.
- Added AppStore support for inspecting a registered presentation template and saving the resulting layout plan with fidelity QA still pending.
- Added a Workspace action for inspecting a registered presentation template from the template-readiness section.
- Added tests for inspection candidates from a generated native deck, compressed `.pptx` package reading, and persisted inspection results.
- Added the inspector source file to the Xcode app target.
- Verified with `swift test` (53 tests passing) and a Debug Xcode build.

### 2026-07-28 — Weekly prompted planning brief

- Added a persisted weekly planning brief to the weekly schedule record for teacher focus, preparation notes, and student support notes.
- Added a Weekly Planner input section so the teacher can save prompted planning notes for the selected week.
- Included the weekly planning brief at the top of the generated weekly hub document when the teacher has entered brief content.
- Kept older weekly-plan records compatible by making the brief optional.
- Added tests for weekly brief persistence, AppStore saving, and escaped weekly-hub rendering.
- Verified with `swift test` (55 tests passing) and a Debug Xcode build.

### 2026-07-28 — Scheduled lesson planning notes

- Added optional planning notes to each scheduled weekly lesson assignment.
- Added a Weekly Planner input for a per-lesson weekly note when placing an approved lesson on the schedule.
- Displayed each scheduled lesson's weekly note in the in-app scheduled lesson list.
- Included each scheduled lesson's weekly note inside the generated weekly hub cell for that lesson.
- Added tests for persisted scheduled-lesson notes, trimming, and escaped weekly-hub rendering.
- Verified with `swift test` (56 tests passing) and a Debug Xcode build.

### 2026-07-28 — Weekly output status summary

- Added a weekly output summary that counts ready lesson plans, slide decks, differentiation guides, complete lessons, and missing outputs for the scheduled approved lessons.
- Updated weekly package readiness so the teacher can see how many missing outputs will be created before the weekly hub is written.
- Added compact Plan/Deck/Guide count indicators to the Weekly Planner readiness panel.
- Added a clearer generated-package success row after weekly package creation.
- Added a complete-output checkmark for scheduled lessons that already have all three outputs.
- Added tests for complete and partial weekly output summary counts and generation messaging.
- Verified with `swift test` (57 tests passing) and a Debug Xcode build.

### 2026-07-28 — Editable scheduled lesson entries

- Added AppStore support for updating an existing scheduled weekly lesson's day, start time, end time, and weekly note.
- Added a Weekly Planner edit panel for the selected scheduled lesson so teachers can correct schedule details without deleting and re-adding the lesson.
- Kept scheduled lessons sorted after edits.
- Added tests for persisted scheduled-lesson edits, trimmed notes, and sorted assignment order after updates.
- Verified with `swift test` (58 tests passing) and a Debug Xcode build.

### 2026-07-28 — Weekly schedule time validation

- Added a blocking weekly-package readiness issue for scheduled lessons whose end time is not after the start time.
- Added inline add/edit warnings in the Weekly Planner and disabled schedule save actions while the selected time range is invalid.
- Added an invalid-time warning to existing scheduled lesson rows so older or edited records are visible before generation.
- Added regression coverage proving invalid scheduled times block weekly package generation.
- Verified with `swift test` (59 tests passing) and a Debug Xcode build.

### 2026-07-28 — Course pacing design alignment

- Confirmed the planned design for setup-document-driven course pacing.
- The existing reviewed-source document pipeline should be reused, but the extracted target is a teacher-reviewable pacing model rather than a lesson draft.
- The pacing model should capture governing timing parameters such as units, modules, lessons, date ranges, instructional-day counts, assessment windows, skipped days, and dependencies.
- The approved pacing model should govern weekly planning while remaining editable later as real classroom pacing changes.
- The AI-optional weekly check-in should become the natural conversational surface for proposing pacing and weekly schedule adjustments, with teacher approval required before changes become active.

### 2026-07-28 — Course pacing setup first slice

- Added a persisted course pacing model to workspace configuration with units, modules, lessons, estimated instructional days, assessment windows, skipped days, source references, teacher refinement notes, and draft/approved status.
- Added a starter pacing builder that uses reviewed imported source text to propose unit, module, lesson, and assessment candidates without approving them automatically.
- Added course pacing readiness guidance so draft pacing cannot govern weekly planning until teacher approval.
- Added Workspace UI for creating starter pacing from reviewed sources, reviewing structure counts, adding refinement notes, and approving the pacing model.
- Added regression coverage for pacing persistence, starter extraction, readiness gating, and AppStore save/approval behavior.
- Verified with `swift test` (62 tests passing) and a Debug Xcode build.

### 2026-07-28 — Weekly pacing suggestions first slice

- Added weekly pacing suggestion analysis from the approved course pacing model.
- The suggestion report now distinguishes pacing items that are ready to schedule, already scheduled, or still need a matching approved lesson record.
- Dated pacing units suggest lessons for the selected week; undated pacing suggests the next unscheduled pacing items.
- Added a Weekly Planner pacing-suggestions panel that can pre-fill the normal scheduling controls while still requiring the teacher to add the lesson.
- Added regression coverage for approved dated pacing suggestions and already-scheduled pacing items.
- Verified with `swift test` (64 tests passing) and a Debug Xcode build.

### 2026-07-28 — Draft lessons from pacing suggestions

- Added teacher-controlled draft lesson creation from weekly pacing suggestions that do not yet match an approved lesson record.
- Drafts created from pacing suggestions retain pacing provenance in source references and include a review warning that teacher-reviewed lesson content is still required before approval.
- Added a Weekly Planner action for creating these drafts directly from pacing suggestions.
- Added regression coverage for draft creation, saved lesson status, pacing provenance, review warning, and most-recent lesson selection.
- Verified with `swift test` (65 tests passing) and a Debug Xcode build.

### 2026-07-28 — Weekly check-in pacing refinements

- Added a weekly pacing refinement proposal record to the selected weekly plan.
- Added a Weekly Planner check-in note field that drafts a proposed pacing adjustment from teacher-entered weekly context.
- The first local refinement classifier distinguishes lost time, faster-than-planned progress, added support/reteach time, and general pacing review notes.
- Refinement proposals now include a structured affected pacing area and suggested instructional-day shift.
- Added an explicit teacher acceptance action that appends the accepted refinement to the course pacing record; draft proposals do not change approved pacing.
- Added regression coverage for refinement classification, weekly-plan persistence, and accepting a refinement into course pacing notes.
- Verified with `swift test` (67 tests passing) and a Debug Xcode build.

### 2026-07-28 — Accepted pacing refinement date shifts

- Accepted weekly pacing refinements can now apply their structured suggested day shift to dated course-pacing units.
- Unit start and end dates shift only after teacher acceptance; draft refinements still do not change approved pacing.
- Accepted refinement notes now record whether dated unit fields were changed.
- Zero-day/general refinement proposals preserve the note trail without changing pacing dates.
- Added regression coverage for accepted +1 day shifts and no-shift general refinements.
- Verified with `swift test` (68 tests passing) and a Debug Xcode build.

### 2026-07-28 — Module and lesson pacing dates

- Added optional start/end dates to course pacing modules and pacing lessons.
- Weekly pacing suggestions now prefer lesson-specific dates, then module dates, then unit dates.
- Accepted pacing refinements now shift dated unit, module, and lesson fields when the proposal includes a nonzero day shift.
- Accepted refinement notes now report shifted pacing date fields across all supported pacing levels.
- Added regression coverage for lesson-specific suggestion dates and accepted shifts across unit, module, and lesson dates.
- Verified with `swift test` (69 tests passing) and a Debug Xcode build.

### 2026-07-28 — Course pacing unit editor

- Added AppStore support for teacher-reviewed edits to pacing unit title, start date, end date, estimated instructional days, assessment windows, and notes.
- Added AppStore support for adding and removing skipped days on a pacing unit.
- Added a Workspace course-pacing unit editor that can load a selected unit, save revised timing fields, and manage skipped days.
- Kept skipped-day entries deduplicated by calendar day and sorted.
- Added regression coverage for unit edits, trimmed assessment windows/notes, minimum instructional-day enforcement, and skipped-day add/remove behavior.
- Verified with `swift test` (70 tests passing) and a Debug Xcode build.

### 2026-07-28 — Course pacing module and lesson editors

- Added AppStore support for teacher-reviewed edits to pacing module title, start date, end date, estimated instructional days, and notes.
- Added AppStore support for teacher-reviewed edits to pacing lesson title, start date, end date, estimated instructional days, dependency notes, and source notes.
- Added Workspace module and lesson editor rows inside the selected pacing unit editor.
- Kept module and lesson edits persisted through the same course pacing record and minimum instructional-day guard.
- Added regression coverage for module and lesson detail persistence, trimming, and date updates.
- Verified with `swift test` (71 tests passing) and a Debug Xcode build.

### 2026-07-28 — Course pacing date-range validation

- Added date-range validation to unit, module, and lesson pacing saves.
- The store now refuses pacing edits where an end date is before its start date, preserving the prior pacing record.
- Added visible editor warnings and disabled save buttons for invalid unit, module, and lesson date ranges.
- Added regression coverage for invalid unit, module, and lesson date saves.
- Verified with `swift test` (72 tests passing) and a Debug Xcode build.

### 2026-07-28 — Setup document intake roles

- Reworked source import toward a single teacher-facing document intake area that accepts multiple PDFs at once.
- Added automatic imported-document role assignment for pacing guides, curriculum maps, instructional calendars, assessment schedules, lesson materials, and other setup documents.
- Added a role summary and per-document role picker so the teacher can quickly correct the app's category choice.
- Starter course pacing now prefers reviewed pacing-related setup documents when they are available, instead of mixing lesson-only materials into governing pacing.
- Added regression coverage for setup document role inference and pacing-source preference.
- Verified with `swift test` (74 tests passing) and a Debug Xcode build.

### 2026-07-28 — Local teacher profile testing layer

- Added local test teacher profiles as a development/testing substitute for real login infrastructure.
- Workspace now has a local profile switcher plus fields for creating test teachers with role and grade/subject metadata.
- When a local profile is active, configuration, imported documents, lessons, daily plans, weekly plans, and generated-output history are stored in that profile's own local cache folder.
- The existing unprofiled local workflow remains available so current single-user data is not forced into a profile.
- Added regression coverage for profile-scoped storage and AppStore profile creation/switching.
- Verified with `swift test` (76 tests passing) and a Debug Xcode build.

### 2026-07-28 — Profile and intake status polish

- Added an always-visible active-profile banner so testers can see which local teacher cache is currently open.
- The banner provides a direct switch path back to Workspace profile controls.
- Added a reusable document-intake readiness report for imported document totals, reviewed counts, role counts, and pacing-ready setup documents.
- Updated the document intake summary to show whether reviewed setup documents are ready to build course pacing.
- Added regression coverage for document-intake readiness counts.
- Verified with `swift test` (77 tests passing) and a Debug Xcode build.

### 2026-07-28 — Pacing editor and local QA checklist polish

- Added compact unit summary rows to the course pacing setup so units can be scanned before editing.
- Added a selected-unit summary header with timing, structure, and skipped-day status above the edit controls.
- Module and lesson disclosure labels now show estimated days and date summaries before expanding nested editors.
- Added a local workflow QA checklist for the current prototype phase: local profile, setup documents, approved pacing, approved lesson, weekly schedule, and weekly hub generation.
- Added regression coverage for local workflow QA checklist status.
- Verified with `swift test` (78 tests passing) and a Debug Xcode build.

### 2026-07-28 — Local QA ready-state coverage

- Added regression coverage proving the local workflow QA checklist can reach a fully ready state when profile, setup documents, approved pacing, approved lesson, weekly schedule, three outputs, and weekly hub are present.
- This establishes the autonomous stopping criterion for the current phase: remaining validation is hands-on workflow and output review.
- Verified with `swift test` (79 tests passing) and a Debug Xcode build.

### 2026-07-28 — Profile setup UX fix

- Replaced the profile banner's indirect Workspace navigation with a dedicated local profile manager sheet.
- The top banner now opens profile creation/switching directly, even if Workspace is scrolled to generated output history or readiness sections.
- Simplified the Workspace profile section into a summary that points back to the top profile control instead of duplicating setup fields deep in the page.
- Verified with `swift test` (79 tests passing) and a Debug Xcode build.

### 2026-07-28 — Document intake file and folder expansion

- Renamed the tab from Import Source to Document Intake so the navigation matches the teacher workflow language.
- Document intake now accepts both PDF and DOCX files.
- The file picker supports selecting multiple supported files at once.
- Added folder import that recursively scans a selected folder for PDF and DOCX files while ignoring unsupported files.
- Added local DOCX text extraction through the Word document XML so imported Word documents enter the same review and role-sorting workflow as PDFs.
- Added regression coverage for DOCX import and folder import.
- Verified with `swift test` (81 tests passing) and a Debug Xcode build.

### 2026-07-28 — Document intake picker usability

- Replaced separate file and folder buttons with one Add documents action.
- The picker now accepts supported files and folders in the same flow, so teachers can choose a folder instead of relying on multi-select gestures.
- Added visible guidance that Command-click selects separate files in the picker.
- Added regression coverage for mixed direct-file and folder intake.
- Verified with `swift test` (82 tests passing) and a Debug Xcode build.

### 2026-07-28 — Document approval gate removal

- Removed the per-document approval requirement from intake.
- Readable PDF/DOCX imports are now usable by default for pacing and draft creation.
- Manual text correction remains available through Save text edits, but it is optional.
- Documents with no readable text remain blocked/omitted rather than forcing blank or unreadable fields into planning.
- Starter course pacing now uses readable setup sources rather than requiring each source to be manually reviewed.
- Added regression coverage proving readable imported setup documents can create starter pacing without a manual review click.
- Verified with `swift test` (83 tests passing) and a Debug Xcode build.

### 2026-07-28 — Automatic document-to-weekly-planner sync

- Readable document intake now automatically builds and approves a starter pacing scaffold after files or folders are imported.
- The app auto-creates approved lesson placeholders from current-week pacing suggestions and places them into the weekly planner.
- Missing or unreadable document fields are omitted rather than forcing a teacher approval step; manual text edits and role changes can refresh the scaffold afterward.
- Updated Document Intake language so the teacher-facing flow is upload documents, then review the populated weekly planner.
- Added regression coverage proving DOCX import can create pacing, approved lesson placeholders, and weekly assignments without an extra setup step.
- Verified with `swift test` (84 tests passing).

### 2026-07-28 — Weekly planner import backfill and clearer empty state

- Found a QA issue where an active local test profile could contain imported documents but no saved course pacing record, leaving Weekly Planner stuck on “Course pacing not set up.”
- Added reload-time backfill so existing readable imports can create approved starter pacing, lesson placeholders, and weekly assignments when the app opens or a profile is loaded.
- Improved weekly packet parsing for weekday-based lesson tables such as “Monday / Observation skills” and “Monday: Observation skills.”
- Updated the Weekly Planner empty-state language so it points teachers back to Document Intake instead of requiring unclear manual approval and scheduling steps.
- Added regression coverage for an already-imported weekly packet that backfills five scheduled lessons on reload.
- Verified with `swift test` (85 tests passing).

### 2026-07-28 — Weekly planner grid preview

- Replaced the Weekly Planner scheduled-lesson list with a Monday-Friday grid preview closer to a teacher weekly-plan template.
- Each weekday column now shows scheduled lesson cards with title, time, pacing/source note, compact Plan/Deck/Guide output status, edit, and remove controls.
- Kept the existing weekly controls and package generation panel in place while making the preview area the teacher-facing planning artifact.
- Verified with `swift test` (85 tests passing).

### 2026-07-28 — Weekly template layout alignment

- Updated the Weekly Planner preview to follow the linked `weekly-lesson-plan-1c.standalone.html` structure: a compact table with Time at left and Monday-Friday columns across the top.
- Updated weekly package HTML generation to use the same compact table styling and to preserve multiple lessons in the same day/time cell.
- Retained in-cell Plan/Deck/Guide output status and edit/remove controls in the app preview.
- Verified with `swift test` (85 tests passing).

### 2026-07-28 — Daily schedule driven weekly placement

- Added local parsing for imported daily schedule documents with time ranges and block labels.
- Auto-created weekly assignments now match lesson subjects to schedule blocks such as English Language Arts, Math, Science/Social Studies, and Art instead of defaulting every lesson to 9:00 AM.
- Undated weekly lesson packets now distribute each source’s lesson sequence across Monday-Friday instead of pushing later lessons into Friday.
- Existing auto-created pacing assignments can be repaired on reload when a daily schedule is imported, so stale 9:00 AM entries move into the correct schedule-derived rows.
- Daily schedule and assessment documents shape timing but no longer create lesson placeholder cards.
- Added regression coverage for schedule-derived placement and repair of existing 9:00 AM assignments.
- Verified with `swift test` (85 tests passing).

### 2026-07-28 — Weekly planner card interaction first pass

- Made weekly planner lesson cards clickable so selecting a card opens it in the scheduled-lesson edit panel.
- Added a visible selected-card state so teachers can tell which lesson is being edited.
- Added clearer inline Edit and Remove actions beneath each lesson card while keeping the compact Plan/Deck/Guide output status row.
- Verified with `swift test` (85 tests passing).

### 2026-07-28 — Weekly cell output controls

- Converted the Plan, Deck, and Guide row inside each weekly lesson cell from passive status indicators into working controls.
- If an output exists, the cell control opens the generated file.
- If an output is missing, the cell control generates that specific output for the lesson.
- Added a lightweight generating state for per-cell output actions so deck generation cannot be double-triggered.
- Verified with `swift test` (85 tests passing).

## Current capabilities

- Local daily planner: schedule blocks and checklist items.
- Local testing profiles can simulate multiple teachers without real login, cloud identity, or production account infrastructure.
- Active local testing profile is visible across the workspace to reduce profile/cache confusion during QA.
- Local test profiles can be created or switched from a dedicated top-level profile panel.
- Imported PDF text review and traceable source references.
- Single document intake can import multiple PDF/DOCX files, accept folders in the same picker, scan folders, and sort supported documents into setup roles for pacing and planning.
- Document intake can automatically turn readable setup documents into starter course pacing, approved lesson placeholders, and weekly planner assignments.
- Existing imported documents can backfill the weekly planner on app/profile load if pacing was not already created.
- Draft, review, and approval states for lessons.
- Optional personal AI draft generation through Codex CLI.
- Local lesson-plan HTML and differentiation-guide HTML generation from approved lessons.
- Native PowerPoint lesson-deck export from approved lesson records.
- Weekly package HTML that links scheduled lessons to their lesson plan, slide deck, and differentiation guide outputs.
- Weekly Planner preview uses the linked compact weekly-plan table structure rather than a long technical list.
- Imported daily schedules can drive weekly planner time rows for auto-created assignments.
- Weekly planner lesson cards can be clicked to edit the scheduled lesson.
- Weekly planner cells can generate or open the lesson plan, slide deck, and differentiation guide directly.
- Weekly planning brief fields for teacher focus, preparation notes, and student support notes, included in the generated weekly hub.
- Per-scheduled-lesson planning notes that appear in the weekly schedule and generated weekly hub.
- Editable scheduled lesson entries for correcting day, time, and weekly notes after placement.
- Weekly schedule time validation that blocks package generation when a scheduled lesson ends before or at its start time.
- Weekly output summary counts for ready lesson plans, slide decks, differentiation guides, and missing outputs before package generation.
- Weekly planner readiness guidance that tells the teacher what is blocking package generation and which scheduled lessons already have all three outputs.
- Persisted weekly planning prompt preference with day/time controls and next-prompt target display.
- In-app weekly planning prompt banner that appears when the saved prompt target is due and can open the weekly planner.
- Course pacing setup can create a starter pacing model from readable setup documents and store approved governing timing parameters.
- Course pacing setup prefers readable pacing-related documents such as pacing guides, curriculum maps, calendars, and assessment schedules.
- Course pacing setup uses summary rows and selected-unit headers to make unit/module/lesson editing easier to scan.
- Weekly Planner can use approved course pacing to create and place current-week lesson placeholders automatically.
- Weekly Planner can draft and accept structured pacing refinements from teacher check-in notes without changing approved pacing until acceptance.
- Accepted pacing refinements can shift dated unit start/end dates and record the applied change in pacing notes.
- Course pacing supports optional unit, module, and lesson dates; suggestions use the most specific available date.
- Workspace includes a course pacing unit editor for teacher-reviewed manual changes to unit timing, assessment windows, notes, and skipped days.
- Workspace includes course pacing module and lesson editors for more specific manual timing and dependency changes.
- Course pacing editors validate date ranges before saving unit, module, or lesson timing.
- Template-aware slide export metadata: generated decks can record and carry provenance for the active registered presentation template and default lesson-field mappings.
- Presentation-template readiness guidance that separates mapping/provenance readiness from true layout-preservation readiness.
- Presentation-template layout-plan records for source-slide inventory, output frame mapping, and fidelity-review status.
- Presentation-template inspection that can populate first-pass slide inventory and frame-map candidates from readable `.pptx` slide XML, including normal compressed packages.
- Optional personal PowerPoint bridge remains available for local QA on the owner's Mac.
- Presentation-template registration metadata with default lesson-field mappings.
- Workspace release-readiness checklist for local QA planning.
- Workspace includes a local workflow QA checklist for phase-exit testing of the end-to-end prototype path.

## Current limitations

- Visual PDF content, handwriting, diagrams, and some fraction/equation formatting are not reliably extracted.
- Weekly package generation links to the latest generated outputs and creates missing outputs, but OS-level notification delivery and later UI-specific details are still pending.
- Local teacher profiles are for product testing only; real shared accounts, permissions, identity, sync, and admin controls remain future infrastructure work.
- Course pacing setup has the first persisted teacher-reviewable model, setup document role sorting, weekly suggestions, draft creation from unmatched pacing items, accepted check-in refinements, unit/module/lesson date shifts, unit/module/lesson editors, summary-based scanability, and date-range validation. The remaining current-phase validation is hands-on end-to-end QA before teacher-facing testing.
- The native PowerPoint exporter is intentionally minimal and now carries template provenance/readiness guidance plus layout-plan records and basic template inspection, but it does not yet duplicate, preserve, or fill real customer-owned PowerPoint layouts.
- Template inspection currently reads slide-level XML and proposes candidates; it does not yet resolve inherited placeholders from slide layouts/masters or perform visual fidelity QA.
- The optional personal PowerPoint export relies on the owner’s local Codex development presentation runtime. It is intentionally not a customer-facing dependency.
- Google Slides is supported through PowerPoint upload/conversion testing, not a direct native Google Slides integration.
- No school curriculum, student data, or proprietary template should be embedded in the general product code or test fixtures.

## Planned differences: personal build vs. sellable version

| Area | Personal build | Sellable version |
| --- | --- | --- |
| AI draft generation | Optional bridge to the developer's signed-in Codex CLI account. | Provider-neutral AI adapter with user-controlled credentials, consent, usage limits, and billing boundaries. |
| Slide-deck export | Native Swift Open XML exporter by default; optional personal QA bridge using the local development presentation runtime. | Bundled, supported PowerPoint exporter; no dependency on Codex, Claude, or a developer-installed runtime. |
| Curriculum sources | Individually selected local files, used only by the owner. | Secure per-customer source library, access controls, licensing terms, and clear content provenance. |
| Data storage | Local application-support files and chosen local folders. | Local-first storage plus optional encrypted backup/sync chosen by the customer. |
| PDF understanding | Text extraction with human review; visuals deferred. | Source-readiness pipeline with OCR, confidence indicators, visual/diagram review, and explicit fallbacks. |
| Templates | Generic HTML outputs and prototype slide deck. | Template manager, PowerPoint/Google Slides round-trip tests, versioning, and customer-owned templates. |
| Distribution | Xcode/developer build for personal testing. | Signed and notarized application, installer/update path, support documentation, and license terms. |
| Privacy | Owner-controlled local test workflow. | Clear privacy notice, data-processing controls, AI opt-in, retention settings, and support boundaries. |

## Next implementation steps

1. Run the local workflow QA checklist with a test teacher profile from setup documents through weekly hub generation.
2. Open the generated native deck in PowerPoint and Google Slides for compatibility review.
3. Record human QA findings and fix any workflow or output issues found during that pass.
4. Decide whether the product needs OS-level notifications in addition to the in-app weekly prompt.
5. Extend automated template inspection to resolve inherited placeholders from customer-owned PowerPoint slide layouts and masters.

## Evidence retained locally

- Source code and Xcode project in this `LessonPlanner` folder.
- Local application state in the owner's LessonPlanner application-support folder.
- Generated HTML and PowerPoint test outputs in the configured local output folder.
- This log records product decisions and development milestones; it is not legal advice or a substitute for a contract/IP review.

### 2026-07-28 — Design screenshot capture set

- Added capture-only launch settings so the app can open directly to each main tab at a larger design-review size without changing the normal app launch size.
- Captured window-only PNGs for Today, This Week, Planning Preview, Document Intake, and Workspace.
- Created a contact sheet for quick UI review in `Design Screenshots/2026-07-28`.
- Verified the app with Xcode build and `swift test`; 85 tests passed.

### 2026-07-28 — Weekly planner cell-flow cleanup

- Changed the weekly planner table to use fixed-height time rows so one crowded day no longer stretches the entire schedule into oversized blank bands.
- Added internal scrolling inside populated cells for overloaded schedule blocks.
- Widened day columns and compacted lesson cards by placing Plan, Deck, Guide, edit, and remove controls on one row.
- Captured updated visual QA screenshots in `Design Screenshots/2026-07-28`.
- Verified with Xcode build and `swift test`; 85 tests passed.

### 2026-07-29 — Continuity handoff refresh

- Rewrote `MODEL_HANDOFF.txt` as a current continuation document for another model or developer.
- Added current product goal, app state, major files, solved problems, attempted solutions, workable solutions, known limitations, verification status, and next human/implementation actions.
- Synced the updated handoff to both the LessonPlanner project folder and the outer working folder.

### 2026-07-29 — Weekly planner intrinsic row heights

- Replaced the fixed 176pt weekly-grid row height with an intrinsic row height that sizes
  each row to its tallest cell, floored at 88pt (`Metrics.rowHeight` -> `Metrics.minRowHeight`).
- Each row's `HStack` now takes intrinsic height via `.fixedSize(horizontal: false, vertical: true)`;
  `WeeklyPlanningTimeCell` and `WeeklyPlanningTableCell` take a `minHeight` and use
  `.frame(minHeight:maxHeight:.infinity)` so cell borders stretch to the row height.
- Removed the nested per-cell `ScrollView` and `LazyVStack` in favour of a plain `VStack`.
  The nested scroll view had been capturing scroll-wheel events away from the grid and
  hiding clipped card content with no visible affordance.
- Fixes two defects visible in `Design Screenshots/2026-07-28/07-this-week-cell-flow-compact.png`:
  lesson cards clipped mid-card in crowded cells, and tall empty bands in sparse rows.
- Verified with `swift test`; 85 tests passed, 0 failures. Human visual confirmation of the
  grid is still outstanding.
- Note: `swift test` can fail at dSYM generation with "Operation not permitted" and report
  zero tests. Adding `-Xswiftc -gnone` avoids it. Recorded in MODEL_HANDOFF.txt section 8.

### 2026-07-29 — Handoff sync correction

- The earlier "2026-07-29 — Continuity handoff refresh" entry recorded a rewrite of
  `MODEL_HANDOFF.txt` that never reached disk; both copies were still the 2026-07-27 version.
- Installed the refreshed handoff in both `LessonPlanner/` and the parent working folder,
  and folded in the intrinsic-row-height change, the dSYM test-command workaround, and a
  note that the project is not under version control.
- Added a standing reminder not to log a documentation change without confirming the file
  actually saved.

### 2026-07-29 — Version control, pbxproj validation, first successful visual confirmation

- Moved into Claude Code with a real shell; closed all three items left open at the end of
  Batch 003.
- Initialized git and made the root commit (1c38146, 41 files) — the project now has a
  rollback path for the first time.
- Ran a real `xcodebuild` (not just `swift test`) and confirmed the hand-edited
  `project.pbxproj` entries for `WeeklyGridLayout.swift` build correctly in the Xcode target.
  Checked the built binary's timestamp against the wall clock to rule out a stale-binary
  false positive (per the Batch 003 trap).
- Got the first-ever successful screenshot capture of the app: `screencapture -l <windowID>`
  was failing because the window was not yet frontmost/on-screen; calling
  `osascript -e 'tell application "LessonPlanner" to activate'` first (a plain Apple Event,
  no Accessibility permission needed) fixed it. Captured
  `Design Screenshots/2026-07-29/08-this-week-intrinsic-height.png` and confirmed the
  intrinsic-row-height fix against the 2026-07-28 baseline: crowded cells no longer clip,
  sparse rows no longer hold a fixed-height blank band, and grid lines still align across
  columns.
- `swift test -Xswiftc -gnone`: 93 tests passed, 0 failures.

### 2026-07-29 — Template layout/master placeholder inheritance

- Added `PowerPointTemplateInspector.resolvePlaceholders(url:)`: resolves each slide
  placeholder shape's effective type, index, and geometry by walking slide -> slideLayout ->
  slideMaster, per ECMA-376 inheritance rules (idx-first matching with type-fallback and
  same-type tiebreak among duplicate idx values; `title`/`ctrTitle` treated as one slot for
  matching only; missing type defaults to `obj`, missing idx to `0`; geometry inherits from
  the nearest part that specifies `<a:xfrm>`).
- Scoped to `<p:sp>` text placeholders — picture/graphicFrame placeholders are not resolved,
  a documented limitation rather than a silent gap.
- New OPC relationship-path resolution (`resolvedRelationshipTarget`, `normalizedPackagePath`)
  correctly collapses `..` segments relative to the referencing part's directory, and the new
  XML parsing (`OOXMLPlaceholderParser`, `OOXMLRelationshipParser`) is the first use of
  Foundation's `XMLParser` in this codebase, chosen over hand-rolled string scanning because
  correctness on nested, multi-shape XML matters here.
- This is a new, additive inspector capability — not yet wired into `inspect()`'s existing
  output, the persisted `PresentationTemplateLayoutPlan`, or any UI, to avoid any persistence/
  migration risk to already-saved local app state. Wiring it in is the natural next step.
- Design (ECMA-376 rules, matching algorithm) and a post-implementation correctness review
  were done with an independent second opinion from Codex; no correctness issues found.
- 7 new tests (6 pure-algorithm, 1 full ZIP-package integration test exercising the actual
  relationship/path-resolution plumbing end-to-end). `swift test -Xswiftc -gnone`: 100 tests
  passed, 0 failures. Real `xcodebuild`: BUILD SUCCEEDED.

### 2026-07-29 — Wire placeholder inheritance into the Workspace UI

- `AppStore` now calls `resolvePlaceholders(url:)` alongside the existing `inspect()` call in
  `inspectPresentationTemplateLayout`, populating a new transient (not persisted)
  `lastPresentationTemplatePlaceholderResolution` property.
- Added `PlaceholderInheritanceView` to the Workspace tab's "Presentation template readiness"
  section: per slide, each resolved placeholder's type/idx and whether its geometry came from
  the slide, layout, or master. Hidden entirely when there's nothing to show.
- Deliberately kept out of the persisted `AppConfiguration`/`PresentationTemplateLayoutPlan`
  schema to avoid any migration risk to already-saved local app state.
- 1 new test (`testAppStoreInspectPresentationTemplateLayoutResolvesPlaceholderInheritance`);
  the existing template-inspection test was extended to confirm the wiring degrades cleanly
  (one empty resolution per slide) on `NativePowerPointExporter`'s own placeholder-free decks.
  `swift test -Xswiftc -gnone`: 101 tests passed, 0 failures. Real `xcodebuild`: BUILD SUCCEEDED.
- Regression-checked by launching the app on the Workspace tab: renders with no crash, new
  section correctly absent when no template is registered. The actual placeholder-inheritance
  list has not been visually confirmed — it needs a real customer-owned `.pptx` registered
  through the interactive file picker, which the owner needs to do.

### 2026-07-29 — "Sunrise Planner" redesign, Batch A: foundation + Today screen

- The owner supplied a full design handoff (warm-toned, rounded, serif reskin of all 5
  screens), preserved in the project at `Design Reference/warm-morning-2026-07-29/`.
- Entered plan mode given the scope; proposed and got approval for a staged rollout —
  foundation + one screen first, confirm visually, then the remaining 4 screens as later
  batches. Plan at `/Users/nils/.claude/plans/snuggly-brewing-elephant.md`.
- Two technical forks resolved with the owner before implementation: typography uses
  SwiftUI's system serif (New York) rather than bundling the actual Source Serif 4 files
  (not included in the handoff — only a Google Fonts web import, unusable natively); icons
  stay SF Symbols with `.symbolRenderingMode(.hierarchical)` rather than hand-drawn shapes.
- Added `Sources/LessonPlanner/Views/DesignSystem.swift`: the `DS` namespace (warm palette,
  radii, shadow + hover-lift modifiers, serif typography helper) and reusable `DSCard`,
  `DSTag`, `DSPrimaryButtonStyle`/`DSSecondaryButtonStyle`, `DSTextFieldStyle`.
- Replaced `WorkspaceView`'s native `TabView` chrome with a custom top nav bar and restyled
  the existing profile band and weekly-planning-prompt banner to the warm palette — same
  functionality, new visual language.
- Fully re-skinned the Today screen: periods became a card grid (`PeriodCard`), the checklist
  became a notepad-styled full-height panel (`ChecklistPanel`/`ChecklistTaskRow`) with a
  gradient spine and ruled-row dividers.
- Discovered mid-implementation that the design's remove affordances (trash icon per period,
  × per task) had no backing `AppStore` methods — added `removeScheduleBlock`/`removeTask`
  and a default-valued `notes:` parameter on `addScheduleBlock`, matching the existing add/
  toggle pattern exactly. Small, deliberate, backward-compatible additions, not a schema
  change — needed so the redesign's buttons are real, not decorative.
- Visually confirmed with real data (using owner-granted `computer-use` access to type into
  the running app) against the handoff's reference screenshot; caught and fixed one real bug
  along the way (a leftover default value made the restyled "Subject" field show
  "Instruction" instead of being empty). Screenshot saved to
  `Design Screenshots/2026-07-29/09-today-sunrise-redesign.png`.
- `swift test -Xswiftc -gnone`: 101 tests passed, 0 failures — unaffected, confirming this was
  a View-layer-only change. Real `xcodebuild`: BUILD SUCCEEDED (new file registered in
  `project.pbxproj`).
- This Week, Planning Preview, Document Intake, and Workspace are not yet re-skinned — a
  deliberate stop point to confirm the approach with the owner before continuing.

### 2026-07-29 — "Sunrise Planner" redesign, Batch B: This Week code pass, visual blocked

- Continued the redesign onto the This Week screen after owner approval of the Today-screen
  direction.
- Re-skinned the weekly control surface with DS cards and replaced the old table-like weekly
  grid with a five-day board: warm day cards, accent header bands, mini time rails, neutral
  lesson cards, and Plan/Deck/Guide pills wired to the real output actions.
- Preserved existing weekly functionality: prompt settings, readiness, pacing suggestions,
  weekly check-in, planning brief, manual scheduling, selected-assignment editing, and weekly
  package generation.
- `swift build` with temp caches: passed. `swift test -Xswiftc -gnone`: 101 tests passed,
  0 failures. Real `xcodebuild`: BUILD SUCCEEDED.
- Visual confirmation is blocked by the stale unkillable LessonPlanner process from Batch 007
  (PID 23296). The attempted screenshot caught that old Today screen, so it was renamed to
  `Design Screenshots/2026-07-29/10-capture-failed-old-stuck-instance.png` and must not be
  treated as visual proof.

### 2026-07-29 — "Sunrise Planner" redesign, Batch B follow-up: real This Week capture after reboot

- After the computer restart, cleared the restored old LessonPlanner instance and launched
  the current Xcode-built app directly on the This Week tab.
- Captured the first real Batch B screenshot, found an obvious horizontal clipping issue, and
  corrected the layout by making the weekly board the primary full-width surface with weekly
  tools beneath it instead of in a left side panel.
- Added `WeeklyPlannerHeader` and `WeeklyPlannerToolbox` in `WorkspaceView.swift` to preserve
  all existing weekly functions while giving the five-day board enough room to breathe.
- Re-verified after the correction: `swift build` passed, `swift test --disable-sandbox
  --scratch-path /private/tmp/lessonplanner-build -Xswiftc -gnone` passed 101 tests with
  0 failures, and real `xcodebuild` succeeded.
- Corrected screenshot saved at
  `Design Screenshots/2026-07-29/10-this-week-sunrise-redesign.png`. This is now the real
  current-build capture awaiting owner visual approval before Batch C (Planning Preview).

### 2026-07-29 — "Sunrise Planner" redesign, Batch B polish: compact output chips

- Addressed owner feedback that the lesson-card output actions wrapped vertically and that
  post-click orange state looked visually stuck.
- Replaced text-heavy Plan/Deck/Guide controls with fixed-size icon + letter chips (`P`,
  `D`, `G`) with full hover help and accessibility labels.
- Pending outputs now use a light outlined orange action state; generated/openable outputs
  use a green check state instead of the orange fill.
- Verification: full Swift test suite passed 101 tests with 0 failures, and real Xcode build
  succeeded. A plain `swift build` attempt hit the known SwiftPM manifest sandbox issue before
  compiling and was superseded by the passing test/build runs.
- Visual QA screenshot saved at
  `Design Screenshots/2026-07-29/11-this-week-output-button-fix.png`. A temporary local
  current-week plan copy was created only to repopulate the visible week for the screenshot
  and was removed afterward.

### 2026-07-29 — Progress safety: save/reload snapshots and guarded clear

- Added `PlanningProgressSnapshot`, a local JSON snapshot of the active profile's
  configuration, daily plan, weekly plan, lesson records, imported sources, and generated
  output history.
- Added repository/AppStore support for saving current progress and restoring a saved
  snapshot. Restore deliberately skips readable-document auto-sync so a snapshot reload is
  exact and does not duplicate weekly planner assignments.
- Added a Workspace "Progress safety" section with a snapshot name field, save button,
  saved-progress picker, reload button, and destructive "Clear documents and entries" action.
- Clear action requires a confirmation dialog warning that imported documents, lessons,
  generated-output history, daily plan, weekly planner, registered source folders, and pacing
  will be wiped. It keeps the local profile, workspace name/location, and output folder.
- Added 2 tests for snapshot save/restore and clear behavior. First run exposed an exactness
  issue in restore caused by startup auto-sync; fixed with `reload(syncReadableDocuments:)`.
  Final verification: 103 tests passed, 0 failures; real Xcode build succeeded.

### 2026-07-29 — "Sunrise Planner" redesign, Batch C: Planning Preview

- Re-skinned the Planning Preview lesson editor using the established Sunrise design system:
  warm lesson sidebar, status tags, editor heading, warning banner, collapsible section cards,
  styled text fields, source provenance rows, export readiness, and output action buttons.
- Preserved existing behavior: lesson selection, New lesson, status changes, fill-empty-fields,
  add instructional step, save lesson, approve lesson, and Plan/Guide/Deck generation still
  call the same store methods.
- Added small helper views in `WorkspaceView.swift`: `LessonSidebarRow`, `LessonStatusTag`,
  `LessonWarningBanner`, `LessonEditorSection`, and `LessonEditorSectionCard`.
- First compile caught a non-exhaustive lesson-status switch; fixed by adding `.generated`
  status handling as an outline tag.
- Verification: Swift build with temp caches passed; full Swift test suite passed 103 tests
  with 0 failures; real Xcode build succeeded before and after lower-output-area polish.
- Visual QA screenshot saved at
  `Design Screenshots/2026-07-29/12-planning-preview-sunrise-redesign.png`.

### 2026-07-29 — "Sunrise Planner" redesign, Batch D part 1: Document Intake

- Re-skinned Document Intake around the intended low-friction flow: add documents/folders,
  show automatic sorting and pacing readiness, and present a large "All set for this week"
  ready state when imports are available.
- Preserved the existing multi-file/folder picker, DOCX/PDF support, role inference, source
  role override picker, local text review/editing, optional manual draft creation, and
  optional Codex CLI draft workflow.
- Added custom intake UI helpers in `WorkspaceView.swift`: `ImportedSourceRow` and
  `IntakeStatePanel`; updated `ImportedSourceRoleSummaryView` and `SourceReadinessView` to
  use the Sunrise design system.
- Added a guarded "Clear and start over" action from the intake summary, reusing the existing
  current-profile clear behavior and destructive confirmation.
- Verification: Swift build with temp caches passed; full Swift test suite passed 103 tests
  with 0 failures; real Xcode build succeeded. A first screenshot revealed sidebar summary
  truncation, fixed before the final capture.
- Visual QA screenshot saved at
  `Design Screenshots/2026-07-29/13-document-intake-sunrise-redesign.png`.

### 2026-07-29 — Handoff status repair and This Week row alignment

- Corrected stale handoff language that still described GitHub as blocked through Batch 011.
  The current state is Batch 013 at `e07f5b8`, with GitHub Desktop successfully publishing
  the real LessonPlanner project and local `main` tracking `origin/main`.
- Reworked the This Week day-column lesson layout so each time label and lesson card render
  as a single row instead of separate vertical stacks. This keeps time rails aligned to their
  own cards when card heights vary.
- Shortened long source-path previews in weekly lesson cards to a one-line filename-style
  display with middle truncation.
- Verification: Swift build passed with the documented temp-cache/no-sandbox workaround; full
  Swift test suite passed 103 tests with 0 failures; real Xcode build succeeded.
- Visual inspection of the fresh weekly-tab build showed improved alignment. No screenshot was
  retained because the capture attempts included Codex overlays or the foreground Codex
  window, and false visual artifacts should not be kept as proof.

### 2026-07-29 — Weekly output key and richer-output roadmap

- Added a compact top-right key to the This Week header explaining the weekly card output
  controls: P = Planner, D = Slide deck, G = Differentiation guide.
- Kept the key visually aligned with the existing P/D/G chip style so teachers can understand
  the card controls without leaving the weekly board.
- Reviewed the output-generation path and recorded the likely reason lesson plans, decks, and
  differentiation guides still feel bare: source-to-lesson extraction is intentionally
  conservative, and the supported native renderers/exporter are generic first slices.
- Identified the likely path to recover the stronger early slide-generation quality: port the
  richer slide arc into the supported native PowerPoint exporter while also enriching the
  `LessonRecord` fields from source text in a teacher-editable way.
- Verification: Swift build passed with the documented temp-cache/no-sandbox workaround; full
  Swift test suite passed 103 tests with 0 failures; real Xcode build succeeded.
- Visual record saved at
  `Design Screenshots/2026-07-29/15-this-week-output-key.png`.

### 2026-07-29 — Native slide deck enrichment pass

- Added `LessonOutputContent`, a shared normalization helper for lesson output generation.
  It trims lesson fields, filters empty steps/materials/source references, and supplies
  honest local fallbacks for classroom-output wording.
- Ported the stronger early slide arc into `NativePowerPointExporter`, replacing the generic
  five-slide skeleton with a richer editable sequence: opening, learning goal, warm up,
  build understanding, practice, supports, and exit ticket.
- Kept the PowerPoint path local and native; the older `Resources/SlideDeckGenerator.mjs`
  bridge remains available as reference, but the default output no longer depends on the
  personal presentation runtime.
- Updated PowerPoint inspection so "Exit ticket" slides are treated as assessment-role slides
  for template-layout inventory/mapping.
- Updated tests to verify the seven-slide native deck, key lesson text, prompt text, escaped
  XML content, and template-inspector inventory/frame-map behavior.
- Verification: Swift build passed with the documented temp-cache/no-sandbox workaround; full
  Swift test suite passed 103 tests with 0 failures; real Xcode build succeeded.

### 2026-07-29 — Subject-block scheduling fix

- Fixed a weekly auto-population bug found during real use: after clearing prior sample
  documents and importing a pacing guide, daily schedule, and math unit packet, lessons were
  able to populate unrelated daily blocks instead of only the math block.
- Clarified the import model in code: planning documents govern pacing/time, while content
  documents supply the concrete lesson sequence. When lesson-material/content packets are
  present, they now drive the starter lesson sequence instead of broad planning documents
  creating every subject's lessons.
- Improved daily schedule recognition so "daily schedule", "sample daily schedule", "class
  schedule", and "instructional schedule" are classified as instructional-calendar documents
  before generic lesson-material detection.
- Improved schedule time parsing to handle AM/PM labels such as `9:45 AM - 10:45 AM`.
- Added source-note subject matching so a math unit filename/source can match the Math block
  even when individual lesson titles are "Place value review" or "Rounding in context."
- Added a regression test mirroring the reported workflow: broad pacing guide + AM/PM daily
  schedule + math unit packet produces five math lessons, one per day, all scheduled in the
  9:45-10:45 Math block and not in other blocks.
- Verification: full Swift test suite passed 104 tests with 0 failures; real Xcode build
  succeeded.

### 2026-07-29 — One lesson per subject block guard

- Fixed the follow-up scheduling issue where multiple lessons could still stack into the
  same 9:45 Math block on one day when pacing/content dates pointed to the same date.
- Auto-scheduling now tracks occupied date/time slots and finds the next open weekday slot
  for the same preferred time. This preserves the daily schedule frame: one Math block per
  day means at most one auto-filled Math lesson in that block.
- Added regression coverage for the exact failure mode: several math lessons all initially
  prefer Monday 9:45, and the app spreads them across separate 9:45-10:45 Math blocks on
  different weekdays.
- Confirmed the broader product direction: the intake flow should become multi-step, with
  the daily schedule establishing the weekly/daily structure first, content documents filling
  subject blocks second, and pacing guides governing/refining order/timing rather than
  directly creating duplicate schedule blocks.
- Verification: full Swift test suite passed 105 tests with 0 failures; real Xcode build
  succeeded.

### 2026-07-29 — Two-stage document intake gate

- Split the Document Intake workflow into two explicit lanes: Planning and Content.
- Planning imports now cover daily schedules, pacing guides, curriculum maps, calendars, and
  assessment schedules. Content imports cover lesson packets, unit lessons, worksheets,
  activities, and teacher guides.
- Added a schedule-scaffold readiness signal based on readable daily schedule time blocks.
  The Content import button is disabled until at least one daily schedule block is detected.
- Content imports are now forced into the `lessonMaterial` role once unlocked, so a unit
  packet cannot accidentally become a governing planning document.
- Added regression coverage for the new gate: content import is refused before a daily
  schedule exists, then unlocks after a planning import detects a schedule block.
- Verification: full Swift test suite passed 107 tests with 0 failures; real Xcode build
  succeeded.

### 2026-07-29 — Visible schedule scaffold build action

- Added an explicit "Build schedule scaffold" action after a readable daily schedule has
  been imported in the Planning lane.
- Exposed imported daily schedule blocks to the weekly UI as scaffold rows instead of using
  them only as hidden lesson-placement helpers.
- Updated the This Week view so planning documents can show empty schedule placeholders even
  before lesson content exists. Empty blocks now display their subject label and prompt the
  teacher to add content files or enter the lesson manually.
- Added a regression test verifying that planning import produces visible scaffold blocks
  with the expected labels and times.
- Verification: full Swift test suite passed 108 tests with 0 failures; real Xcode build
  succeeded.

### 2026-07-29 — Fix subject-matching false negatives in content-to-scaffold population

- Fixed the reported bug: uploaded Math content was not filling the Math schedule block
  after the Batch 020/021 two-stage intake flow. Root cause was in `bestScheduleBlock`'s
  subject-matching, not in the two-stage gate, the pacing-plan rebuild, or the visible
  scaffold rendering (all four were individually verified correct with a diagnostic test
  before changing any code).
- `bestScheduleBlock` matched a lesson to its schedule block only by checking a narrow,
  hardcoded keyword list (mostly just the subject's own name, e.g. "math") against the
  lesson's unit/module/lesson title and its source filename. Realistic content very often
  never contains that literal word — a "Fractions Unit Packet.docx" with lessons titled
  "Equivalent fractions" and "Comparing fractions" contains no substring "math" anywhere in
  any of those fields. When no keyword matched, the lesson silently fell back to a generic
  9:00 AM slot instead of the schedule's declared 9:45-10:45 Math block — visually
  indistinguishable, from the teacher's side, from "my content didn't populate the block."
- Fix has two parts: (1) broadened each subject's keyword list to include realistic topic
  vocabulary, not just the subject name itself (math: fraction, decimal, multiplication,
  division, geometry, algebra, place value, rounding, equation, measurement, word problem,
  etc.; similar breadth added for English/reading, art, science, and social studies); (2)
  added a fallback that, when title-based matching still finds nothing, looks up the
  original imported source's full extracted text (not just its filename or short lesson
  titles) and matches against that instead — covering cases as generic as lesson titles
  literally named "Day 1"/"Day 2" where the actual subject only appears in the document body.
- Also confirmed, and left as-is: `configuration` being nil would independently short-circuit
  `syncReadableDocumentsIntoWeeklyPlanner` silently (no error shown). This is real but not
  reachable in production — `RootView` never shows `WorkspaceView`/Document Intake at all
  while `configuration == nil`. It's noted because two of Batch 020/021's own regression
  tests never saved a configuration and therefore never actually exercised the
  scheduling/lesson-creation outcome, only the import-gate and scaffold-listing mechanics —
  a real coverage gap that let this bug ship unnoticed through two batches.
- Added 4 new regression tests exercising the real two-stage production entry points
  (`importPlanningDocumentItems` then `importContentDocumentItems`, not the pre-Batch-020
  direct-repository-seed pattern some earlier tests use): topical math content schedules
  into the Math block and leaves Reading untouched; topical reading content schedules into
  Reading and leaves Math untouched; a dedicated case for the full-source-text fallback
  path specifically (generic "Day 1"/"Day 2" lesson titles, subject only in the document
  body); and an ambiguous-signal case (see below).
- Codex reviewed the fix before it was finalized and found a real problem with the first
  draft: once the full source-document body is searched (not just short titles), a fixed
  "check English, then Math, then Art..." order becomes fragile — a math worksheet's body
  can easily contain an incidental English-flavored word ("read", "story") before the text
  ever reaches its much stronger math vocabulary, so whichever subject was checked *first*
  could silently win regardless of which subject the content actually was. Codex also flagged
  that raw substring matching let "art" match inside "chart"/"partial" and "map" match inside
  "concept map" for any subject.
- Rewrote matching in response: each subject now has a word-boundary keyword set (so "art"
  can no longer match inside "chart") plus a short multi-word-phrase list, and the winning
  subject is the one with the *highest keyword-match count*, not the first one checked.
  Removed a few keywords that were too generic to be a reliable signal from body text  ("map",
  "color", "story") rather than trying to special-case around them.
- Added a fourth regression test for exactly the scenario Codex identified: content whose
  body contains one incidental English-flavored word ("Reading") alongside much stronger,
  specific math vocabulary (fractions, geometry, "word problem" x2) — confirmed this still
  schedules into the Math block. Verified by tracing that this test would have failed under
  the pre-review, first-match-wins implementation.
- Verification: full Swift test suite passed 112 tests with 0 failures (108 baseline + 4
  new); real Xcode build succeeded after the rewrite.

### 2026-07-29 — "Sunrise Planner" redesign complete: Workspace screen (final screen)

- Re-skinned the Workspace tab (`ConfigurationSummaryView`), the last of the app's 5 screens
  still on the original stock-SwiftUI look, completing the full visual redesign started in
  Batch 007.
- The screen had grown well past the original design handoff's simple "document library"
  concept into a dense settings/admin screen (local profiles, progress safety, workspace
  paths, PowerPoint export preference, weekly prompt config, a full course-pacing unit/
  module/lesson editor, source folders, templates, presentation-template readiness, local
  workflow QA, release readiness, generated-output history). Converted its layout from
  native `Form`/`Section` to the same `ScrollView` + `DSCard` pattern used by the other 4
  screens, with buttons/text fields restyled to match — while deliberately leaving native
  controls without a `DS` equivalent (Picker, Stepper, DatePicker, the destructive-clear
  confirmation dialog) and the screen's existing small subcomponent views untouched.
- Caught and fixed a naming collision before showing the owner: the page title and the first
  section header were both literally "Workspace" — renamed the section to "Workspace
  location."
- Visually verified the full screen, including all empty-state cards, using a throwaway
  local test profile created specifically to avoid capturing any screenshot of the real
  local test profile's large-scale, licensed-curriculum-derived data (315 units, 869 source
  filenames) that happened to be present.
- The "Sunrise Planner" redesign is now complete across all 5 screens (Today, This Week,
  Planning Preview, Document Intake, Workspace), sharing one design-system foundation
  (`DesignSystem.swift`) and one custom top nav/profile band. The entire initiative,
  Batch 007 through this batch, was View-layer-only — 112/112 tests unaffected throughout.
- Verification: `swift build`/`swift test -Xswiftc -gnone` — 112 tests passed, 0 failures
  (no new tests needed; pure View-layer change). Real Xcode build succeeded (no new files).
- Awaiting the owner's visual sign-off on this final screen before considering the redesign
  initiative fully closed.

### 2026-07-29 — Workspace path cleanup, boundary trace-check, validated test template

- Removed the raw file-path display from Workspace's "Workspace settings" card (the section
  used to show `configuration.workspaceReference.path` and `configuration.outputFolderReference?.path`
  directly); kept the "Choose output folder…" button since `outputFolderReference` is
  functionally load-bearing (`AppStore` uses it to decide where generated lesson
  plans/decks/guides save, falling back to a default subfolder when unset).
- Ran a full boundary trace-check for licensed curriculum material used only for local
  testing: `git grep`/`strings` across all tracked files and screenshots, plus a full
  `git log --all --diff-filter=A` history audit. Result: clean — no trace anywhere. The
  handful of substring matches found were either the boundary rule's own text or coincidental
  compressed-PNG byte sequences, not real leaked content. `LocalRepository` stores all app
  data under `~/Library/Application Support/`, structurally outside the git-tracked project
  folder, which is the architectural reason this check reliably stays clean.
- Hand-authored a complete, schema-valid, generically-branded `.pptx` slide template
  ("Sunrise Lesson Plan Template") from scratch OOXML (content types, rels, theme, slide
  master, 2 layouts, 2 slides) to test `PowerPointTemplateInspector.resolvePlaceholders(url:)`
  against genuine slide→layout→master inheritance — deliberately covering 2 layout-override
  paths and 1 master-fallback path. First attempt failed the `pptx` skill's schema validator
  on `theme1.xml` (missing `dk2`/`lt2` colors, `ea`/`cs` font children, an incomplete
  `effectStyleLst`); rebuilt the theme to be fully schema-complete and it passed cleanly.
  Registered the template in the running app and confirmed via "Inspect presentation
  template" that all 3 inheritance paths resolve exactly as designed — the placeholder
  resolution feature is now proven correct against a real file, not just unit-test fixtures.
- Verification: `swift test -Xswiftc -gnone` — 112 tests passed, 0 failures. Real
  `xcodebuild -scheme LessonPlanner -configuration Debug build` succeeded. Relaunched the
  freshly built app and visually confirmed the Workspace screen no longer shows raw paths.
- Noted for later: this machine has neither `soffice` (LibreOffice) nor `markitdown`
  installed, so the `pptx` skill's visual-render/content-QA steps weren't available — relied
  on direct XML inspection plus schema validation instead. Also noted `NativePowerPointExporter.swift`'s
  own theme XML shares the same schema gaps the hand-authored template initially failed on;
  not fixed here (real PowerPoint/Google Slides tolerate it), but worth a future validation
  pass.

### 2026-07-29 — GitHub SSH auth fixed; layout-preserving export, step 1: structural frame map

- Diagnosed the session-long GitHub push blocker: no stored credential in the macOS Keychain
  and no SSH key, so HTTPS push had nothing to authenticate with. Generated an SSH keypair,
  had the owner add the public key to their GitHub account, verified GitHub's host key
  fingerprint before trusting it, switched the remote from HTTPS to SSH, and pushed all
  pending commits. `git push origin main` now works with no owner action needed going forward.
- Began "layout-preserving PowerPoint export" (placing approved lesson content into a
  customer-owned template's real placeholder frames). An Explore subagent mapped the existing
  code first and found the placeholder-inheritance resolver solid but the Workspace UI's
  "frame map" built by keyword-guessing on slide XML text, completely disconnected from that
  resolver — and a real bug: nothing in the shipped app could ever set
  `fidelityReviewCompleted = true`, so the "Complete template fidelity QA" readiness item was
  permanently stuck.
- Routed the implementation plan through the `codex-router` skill (per a standing owner
  instruction to delegate high-compute work): this first batch was scoped as Claude-native
  architecture work; the mechanical `.pptx`-editing step is planned as a future
  Codex-delegated batch once its interface is locked down.
- Added `PresentationTemplatePlaceholderAssignment` — a structural, shape-ID-addressed
  placeholder identity, populated directly from `PowerPointTemplateInspector.resolvePlaceholders`
  rather than guessed from text. Added `AppStore.assignPlaceholder` (lets a teacher assign a
  lesson field to a resolved placeholder, invalidating any prior confirmation) and
  `AppStore.confirmPresentationTemplateFrameMap` (the real, user-completable path to
  `fidelityReviewCompleted = true`, gated on all 4 required fields being assigned). Re-
  inspecting a template now preserves prior assignments by matching `(sourceSlideNumber,
  shapeID)` instead of discarding them. Added a "Placeholder assignments" section to the
  Workspace UI with a picker per placeholder and a "Confirm frame map" button.
- Done entirely without computer-use/screen-control, at the owner's request while on a Zoom
  call — confirmed a new SwiftUI UI section can be written, tested, and verified via a real
  Xcode build with zero screen access; visual verification of that new UI is still pending.
- Verification: `swift build`/`swift test -Xswiftc -gnone` — 115 tests passed (112 baseline +
  3 new), 0 failures, after fixing one new test's incomplete setup (it left slideInventory/
  frameMap empty, which independently trips unrelated readiness issues). Real Xcode build
  succeeded.

### 2026-07-29 — Layout-preserving PowerPoint export, part 2: the `.pptx` composer (Codex-delegated)

- Implemented `PowerPointTemplateComposer.compose(templateURL:placeholderAssignments:content:) throws -> Data`
  in a new file, `Sources/LessonPlanner/PowerPointTemplateComposer.swift` — the piece Batch 024's
  research had flagged as completely missing: a `.pptx` package editor that writes real lesson
  content into a customer-owned template's placeholder shapes.
- Delegated the implementation to Codex, per the routing plan set up in the prior batch — this
  was well-specified, algorithm-dense ZIP/XML editing work with a locked-down interface, the
  profile suited to delegation. The `mcp__codex__codex` MCP tool timed out on the first attempt
  (confirmed nothing had been touched); retried via the `codex` CLI directly
  (`/Applications/ChatGPT.app/Contents/Resources/codex exec -s workspace-write`, run in the
  background), which completed cleanly.
- Deliberately scoped narrower than originally sketched: the composer edits placeholder text on
  the template's own existing slides in place and does not duplicate or reorder slides. The
  current frame-map pipeline never needs more output slides than the template already has, so
  this avoided the much higher-risk content-types/relationship-renumbering work for now.
- Independently verified every part of Codex's work rather than trusting its self-report: read
  the full diff (access-level widening in `PowerPointTemplateInspector.swift` was exactly
  `private` → internal, zero behavior change, plus one clean helper reused by existing code);
  read the new composer file in full and hand-traced its custom string-based XML editing
  (boundary-safe `<p:sp>` vs `<p:spPr>` matching, shape/`txBody` range-finding, paragraph
  replacement preserving `bodyPr`/`lstStyle`, a from-scratch ZIP writer matching the same
  well-known format the app's own `NativePowerPointExporter` already uses in production); ran
  `swift build`/`swift test` myself (118/118 passed) rather than trusting Codex's own build
  report (which had needed `--disable-sandbox` in its managed environment).
- Went beyond unit tests for extra confidence given this is the highest-risk part of the whole
  feature: composed a real lesson against the actual, already schema-validated
  `Sunrise Lesson Plan Template.pptx` (Batch 024) via a temporary verification-only test, ran the
  `pptx` skill's `scripts/office/validate.py --original` against the output — **passed full
  OOXML schema validation** — and unzipped/grepped the result to directly confirm the exact
  mapped text landed in the correct placeholders (including a deliberately non-default field
  mapping and a multi-item instructional sequence correctly split into separate paragraphs).
  Removed the temporary test afterward.
- Registered the new file in `LessonPlanner.xcodeproj/project.pbxproj` (the 4-entry
  explicit-file-reference pattern) — Codex was explicitly told not to touch this file.
- Verification: `swift test -Xswiftc -gnone` — 118/118 passed (115 baseline + 3 new). Real
  `xcodebuild` succeeded.
