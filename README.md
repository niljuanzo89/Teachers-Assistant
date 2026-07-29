# LessonPlanner

Native, local-first macOS scaffold for the Phase 1 teacher-planning application.

## Current scope

- First-boot workspace setup.
- Local configuration and persistent folder/template references.
- Daily schedule blocks and checklist items.
- Weekly planning schedule that can generate a linked weekly package.
- Weekly planning brief fields for teacher focus, preparation notes, and student support notes.
- Per-scheduled-lesson planning notes inside the weekly schedule.
- Editable scheduled lesson entries for correcting day, time, and weekly notes after placement.
- Weekly schedule time validation for scheduled lesson entries.
- Manually created draft lesson records.
- Approved lesson outputs: HTML plan, differentiation guide, and PowerPoint deck.
- Weekly package generation creates missing lesson outputs for scheduled approved lessons and links to all three output types.
- Generated weekly package includes the saved weekly planning brief when the teacher has entered one.
- Generated weekly package includes per-scheduled-lesson notes when the teacher enters them.
- Weekly package readiness guidance shows whether the schedule is ready and which scheduled lessons already have plan, deck, and guide outputs.
- Weekly output summary shows Plan/Deck/Guide counts and whether missing outputs will be generated before the hub is written.
- Weekly planning prompt preference stores the teacher's chosen day/time and shows the next prompt target.
- In-app weekly planning prompt banner appears when that saved prompt target is due.
- Local testing profiles can simulate multiple teachers without real login, cloud identity, or production account infrastructure.
- Active local testing profile is visible across the workspace to reduce profile/cache confusion during QA.
- Local test profiles can be created or switched from a dedicated top-level profile panel.
- Document intake accepts multiple PDF/DOCX files or folders from one picker, scans folders, and sorts imported files into setup roles for pacing and planning.
- Document intake can automatically turn readable setup documents into starter course pacing, approved lesson placeholders, and weekly planner assignments.
- Existing readable imports can backfill the weekly planner on app/profile load if pacing was not already created.
- Readable imports are usable by default; manual text edits are optional when extracted text needs correction or a blank field needs filling.
- Course pacing setup can create a starter pacing model from readable setup documents and store approved unit, module, lesson, and timing parameters.
- Course pacing setup prefers readable pacing-related documents such as pacing guides, curriculum maps, calendars, and assessment schedules.
- Course pacing setup uses summary rows and selected-unit headers to make unit/module/lesson editing easier to scan.
- Weekly pacing suggestions can populate the selected weekly plan from approved course pacing.
- Weekly pacing suggestions can create approved lesson placeholders when a pacing item does not yet match an existing approved lesson.
- Weekly check-in notes can draft structured pacing refinement proposals that require teacher acceptance before updating course pacing notes.
- Accepted pacing refinements can shift dated unit start/end dates while preserving the teacher-visible note trail.
- Course pacing supports optional unit, module, and lesson dates; weekly suggestions use the most specific available pacing date.
- Workspace includes a course pacing unit editor for manual teacher-reviewed timing, assessment, note, and skipped-day changes.
- Workspace includes course pacing module and lesson editors for more specific manual timing and dependency changes.
- Course pacing editors validate unit, module, and lesson date ranges before saving.
- Native PowerPoint export is the default app path; the personal development-runtime bridge remains available from Workspace settings for QA.
- Slide-deck output records the active registered presentation template and carries template mapping provenance in deck notes.
- Presentation-template readiness guidance distinguishes mapped-template provenance from true layout preservation.
- Presentation-template layout-plan records can store source-slide inventory, output frame mapping, and fidelity-review status.
- Presentation-template inspection can create first-pass slide-inventory and frame-map candidates from readable `.pptx` slide XML, including normal compressed packages.
- Workspace release-readiness checklist for local QA milestones.
- Workspace includes a local workflow QA checklist for phase-exit testing of the end-to-end prototype path.
- Presentation-template registration with default lesson-field slot mappings for future template fidelity work.

No school-specific materials are included. Local teacher profiles, AI-assisted draft generation, and the personal PowerPoint bridge are owner-controlled local development workflows, not customer-facing defaults. The current autonomous stopping point is human-guided local workflow QA and PowerPoint/Google Slides output review.

## Run and test

Open `Package.swift` in Xcode, or run from this folder:

```sh
swift run
swift test
```
