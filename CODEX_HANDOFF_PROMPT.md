You are picking up work on **LessonPlanner**, a local-first native macOS SwiftUI teacher-planning app.

Repo (run with this as cwd): `/Users/nils/Documents/Program Development Folder/LessonPlanner`

Read `CLAUDE.md`, then `MODEL_HANDOFF.txt`, then the last ~5 entries of `CONTINUITY_LOG.md` before writing any code. They contain the operating protocol, architecture, and the dead ends not to retry.

---

## Where things stand

A teacher imported a daily schedule (worked correctly), then a folder of 316 math curriculum PDFs. The weekly planner scattered: lessons landed in the English Language Arts block and at times that were not blocks at all. Required behavior: **math content fills only Math blocks; every other block stays an untouched placeholder.**

This was substantially fixed and **verified against the owner's real 316-document import** (not fixtures):

- 0 placements at the previously invented 9:00 AM slot (that was the engine of the scatter)
- 23 of 24 placements land in the Math block; every placement lands in one of the teacher's 12 real blocks
- `AutoPlacementSummary` now reports unplaced lessons with a reason instead of dropping them silently

Current HEAD: `00c9ed4`. Full suite: **162 tests, 0 failures.** Real `xcodebuild` succeeds.

The fix (`AppStore.scheduledTimeRange`) returns nil — meaning "do not place" — only when the teacher **has** imported schedule blocks and none confidently match. The 9:00 AM default is retained when no schedule has been imported, because there is nothing to contradict then. That conditional is load bearing: making it unconditional breaks a family of tests that legitimately rely on the default. Do not "simplify" it.

---

## Task 1 (highest value): stop `CoursePacingPlan.starter` manufacturing placeholder lessons

`CoursePacingPlan.starter(from:)` — `Sources/LessonPlanner/Models/AppModels.swift:509` — creates a unit/module for **every** readable source, and manufactures a placeholder lesson when it finds no extractable lesson titles. That is the fragment factory: the owner's import produced **173 lesson records**, most of them fragments with titles like `days`, `day. How much does the account receive`, `Lesson 1`.

The placement guarantee now stops these corrupting the planner, but they are still created, still clutter the lesson list, and still cost the teacher review time.

Change it so a source that yields no real lesson titles contributes **no** lesson, at least on the automatic content-import path. Decide deliberately whether it should also contribute no unit/module, and record the reasoning.

Constraint: several existing tests depend on `starter` producing lessons from terse documents. Before weakening or deleting any test, determine whether it encodes required behavior. Precedent: `testContentImportSchedulesTopicalMathLessonsIntoMathBlockOnlyViaTwoStageFlow` looks like an obstacle but is in fact the owner's requirement written as a test — it must keep passing.

## Task 2: rework the document placement prefilter

`Sources/LessonPlanner/DocumentPlacementClassifier.swift` classifies each imported document as `placeableLesson` / `lessonSequence` / `supportingMaterial` / `planningDocument` / `inert`, and also yields a `DifferentiationRole` and a module/lesson `DocumentLessonKey`.

Measured on the owner's real 316 documents: 174 supporting material, 82 placeable lessons, 54 inert, 6 planning documents; lesson key resolved for 143 (45%).

**It is currently inert in production** — referenced only inside `AppModels.swift`, consulted by no code path. An attempt to use it as a prefilter in `AppStore.syncReadableDocumentsIntoWeeklyPlanner` was implemented and reverted twice because it was simultaneously:

- **too strict** — a valid 75-character weekly packet (`Unit 1: Fractions` / `Monday: …` / `Tuesday: …`) fell under a 120-character minimum-text floor before the lesson-list check ran; and a 2-entry list was rejected by a minimum of 3
- **too permissive** — planning documents began contributing lessons they previously did not

Evidence that this matters: the **one remaining misplacement** in the verified run is a fragment titled `"day, can he still meet his goal? Why or why not?"`, proposed from a challenge worksheet whose filename contains `CHLG`. The prefilter would classify that document `supportingMaterial` on its filename marker, so it would never propose a lesson. Fixing the prefilter removes this entire class of failure.

Rework it so both failure directions are handled, then wire it in. `AppStore.swift` carries an in-code comment at the reverted call site explaining the history.

## Task 3: populate `subject` at import

`subject` is empty on all 173 imported lesson records, which is why subject-to-block matching has to fall back to scoring whole-document text — and why a math document containing "write an equation" and "read the problem" can score English.

`LessonStructureInferencer` (`Sources/LessonPlanner/LessonStructureInferencer.swift`) already recovers subject and grade from standards codes, so this should be close to free. Stamp subject once per source document at import rather than re-deriving per fragment at scheduling time. This independently fixes the remaining ELA misplacement.

## Task 4 (small): surface `AutoPlacementSummary` in the UI

`AppStore.lastAutoPlacementSummary` is populated but displayed nowhere. Its `summaryLine` is ready to render. Put it where a teacher sees it after an import.

---

## Rules that are not negotiable

**Persistence.** Adding a **non-optional** field to any Codable model that gets saved to disk makes every previously saved file undecodable — a property default does *not* satisfy Swift's synthesized decoder. This exact mistake made the owner's real workspace unreadable and presented as total data loss. For any new persisted field: make it `Optional`, or write an explicit `init(from:)` using `decodeIfPresent`; add a test that decodes the JSON shape as it existed **before** the change; and launch the app against pre-existing data. `swift test` and `xcodebuild` both pass on this class of bug. See `PresentationTemplateLayoutPlan` for the worked example and the CRITICAL PERSISTENCE RULE in `MODEL_HANDOFF.txt`.

**IP boundary.** No school curriculum, student data, publisher content, or curriculum filenames in source, tests, fixtures, screenshots, or docs. Test fixtures must be hand-written and generic. Reading the owner's real files locally for diagnosis is fine; committing anything derived from them is not.

**New Swift files** require **four** manual entries in `LessonPlanner.xcodeproj/project.pbxproj` (build file, file reference, group child, sources build phase). SwiftPM will build without them and the Xcode build will fail. `DocumentPlacementClassifier.swift` is a recent worked example.

---

## Verification standard

Fixture-only verification has repeatedly produced changes logged as "fixed" that were not — including a subject-matching fix that never worked on real data. **A change to import, extraction, or placement is not verified until it has been run against the owner's real data.**

The harness is cheap. Copy the real profile into a throwaway root, clear the planner so placement re-runs, and drive a real `AppStore` against it from a temporary test — no original PDFs are needed, because extracted text is persisted, and the owner's live data is never touched:

```
BASE=~/Library/Application\ Support/LessonPlanner
SB=/tmp/lp-verify
rm -rf "$SB" && mkdir -p "$SB"
cp "$BASE/active-teacher-profile.json" "$BASE/teacher-profiles.json" "$SB/"
PROFILE=$(python3 -c "import json;print(json.load(open('$SB/active-teacher-profile.json'))['activeTeacherProfileID'])")
mkdir -p "$SB/teacher-data/$PROFILE"
cp "$BASE/teacher-data/$PROFILE/configuration.json" "$BASE/teacher-data/$PROFILE/imported-sources.json" "$SB/teacher-data/$PROFILE/"
rm -rf "$SB/teacher-data/$PROFILE/weekly-plans" "$SB/teacher-data/$PROFILE/lesson-records.json"
```

Then in a temporary test: `AppStore(repository: LocalRepository(rootURL: URL(fileURLWithPath: "/tmp/lp-verify")))` and inspect `store.lessons`, `store.weeklyPlan.assignments`, and `store.lastAutoPlacementSummary`. Assert that every placement start time is one of `store.importedScheduleScaffoldBlocks`. **Delete the temporary test before committing.**

`LESSONPLANNER_DATA_ROOT=<path>` also points the running app at a throwaway data folder, for GUI checks without touching real data.

Commands: `swift build -Xswiftc -gnone` · `swift test -Xswiftc -gnone` · `xcodebuild -scheme LessonPlanner -configuration Debug build`. The `-gnone` flag avoids a dSYM permission failure.

---

## Failure mode to watch for in yourself

If a change fixes some existing tests and breaks others, and the next adjustment reverses which ones — **stop**. That pattern means the design is wrong, not the constants. It happened three times on this feature before an outside review found the actual flaw in minutes. Escalate or step back at the second oscillation, not the fourth. Do not tune thresholds until the suite goes quiet.

Also: sample a bucket before trusting its count. A classification pass once put 154 of 316 documents in "inert" and the number looked clean — sampling showed they were small-group option pages, exit tickets, and warm-up problems, i.e. the most valuable differentiation material in the folder.

---

## When done

Update `CONTINUITY_LOG.md` (batch entry: numbered steps, what was tried, dead ends, what is still open), `BUILD_LOG.md`, and `MODEL_HANDOFF.txt` if state changed. Confirm each doc edit actually landed on disk before recording that it did. Commit per verified batch; `git push origin main` works over SSH.

Report honestly what is verified versus merely built. If something is shipped but not yet consulted by any code path, say so plainly.
