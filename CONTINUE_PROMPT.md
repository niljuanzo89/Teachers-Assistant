# Continuation Prompt

Paste everything below the line into a fresh Claude Code session opened on
`/Users/nils/Documents/Program Development Folder/LessonPlanner`.

---

You are continuing development of **LessonPlanner**, a local-first native macOS
teacher-planning app in Swift/SwiftUI. I am the owner. Work has been in progress across
several sessions and is fully documented — do not start over, and do not re-derive decisions
that are already recorded.

## First, orient yourself

Read these, in this order, before touching anything:

1. `CLAUDE.md` — environment, build/test commands, architecture rules, traps, open items.
2. `CONTINUITY_LOG.md` — my standing operating protocol, plus a step-level log of the last
   three batches **including a dead-ends list**. Do not retry anything on that list.
3. `MODEL_HANDOFF.txt` — full product intent, architecture decisions, and IP boundaries.
4. `BUILD_LOG.md` — long-form milestone history and the current capability inventory.

## What this product is

A teacher imports curriculum and schedule documents. The app extracts text (with OCR
fallback), builds course pacing, and populates a weekly planner. Each **approved**
`LessonRecord` drives three aligned outputs — an HTML lesson plan, a PPTX slide deck, and an
HTML differentiation guide — collected into a weekly package.

It is a generic product shell, not a curriculum-specific tool, and it must remain fully
useful with generative AI switched off. AI is an optional enrichment path, never a
dependency.

## How I want you to work

- Work in batches of **up to 20 numbered steps**. Log every step to `CONTINUITY_LOG.md` as a
  new batch entry when the batch ends.
- **Before starting a batch, tell me the compute level** (low / medium / high) **and the model
  shape** (single sufficient / dual helpful / dual recommended).
- **Stop and notify me** — do not push through — when a judgment call is mine, when
  verification needs my eyes or my accounts, when a credential or OS permission is missing,
  or when the same approach has failed twice. Tell me exactly what to do to unblock it.
- Log **dead ends with the reason**. An unrecorded dead end gets retried by the next model.
- **Confirm a file actually landed on disk before logging that it was written.** An earlier
  session logged a documentation rewrite that never saved, and the docs sat out of sync for a
  day.

## Environment — you can do more than the previous sessions could

Earlier work ran in a sandbox with **no Swift toolchain and no GUI**, so every build, test,
and screenshot had to be delegated to Codex, and `git` was blocked entirely. You are in Claude
Code with a real shell on my Mac. Build, test, run `git`, and launch the app directly. Use a
second model only when an independent opinion is genuinely valuable, not out of habit.

```sh
swift test -Xswiftc -gnone

xcodebuild -project LessonPlanner.xcodeproj -scheme LessonPlanner \
  -configuration Debug -derivedDataPath /private/tmp/LessonPlannerDerivedData \
  build CODE_SIGNING_ALLOWED=NO
```

Baseline is **93 tests passing**.

## Three traps that have already bitten this project

1. **`swift test` without `-Xswiftc -gnone`** can die during dSYM generation with
   `Operation not permitted` and report **zero tests run**. Zero tests is a failure, not a
   pass.
2. **`LessonPlanner.xcodeproj` uses explicit file references, not synchronized groups.** A new
   source file is invisible to the Xcode target until you add four entries to
   `project.pbxproj` (PBXBuildFile, PBXFileReference, PBXGroup children,
   PBXSourcesBuildPhase). SwiftPM auto-discovers files, so **`swift test` will pass while the
   Xcode build fails.** `WeeklyGridLayout.swift` (IDs `...015`) is the worked example.
3. **Never trust a build result without checking the binary's timestamp.** A previous
   background build returned a PID and an empty log while a stale binary made it look
   successful.

## Where things stand

**Recently completed and test-verified:**

- The weekly planning grid no longer uses a fixed row height. Rows size to their tallest cell
  with an 88pt floor, so crowded cells no longer clip lesson cards mid-card and sparse rows no
  longer hold tall blank bands. The nested per-cell `ScrollView` was removed — it captured
  scroll-wheel events away from the grid and hid clipped content with no affordance.
- Slot identity was being recomputed by exact hour-and-minute in three separate places, so a
  block starting 9:45 Monday and 9:50 Wednesday produced two nearly empty rows. That logic now
  lives in one pure, tested type, `Sources/LessonPlanner/WeeklyGridLayout.swift`, which
  clusters start times within a 15-minute tolerance. Clustering anchors on the first start in
  each cluster, not the previous one, so 8:00 → 8:14 → 8:28 → 8:42 cannot chain into a single
  row. 8 tests cover it.

## Start here — three unverified items, in order

**1. Put the project under version control. Do this before anything else — there is currently
no rollback path for any of the work above.**

```sh
cd "/Users/nils/Documents/Program Development Folder/LessonPlanner"
rm -rf .git        # a partial .git may exist from a sandbox that could not clean up
git init
git add -A && git commit -m "Initial commit: LessonPlanner local-first macOS teacher planning app"
```

A correct `.gitignore` is already in place — it excludes `.build/`, `DerivedData/`,
`xcuserdata/`, `.DS_Store`, and generated `.pptx` files, and keeps `Design Screenshots/`
tracked as the visual QA record.

**2. Validate the hand-edited `project.pbxproj`.** Four entries were added to register
`WeeklyGridLayout.swift`, but this has never been confirmed with a real Xcode build. Run
`xcodebuild` and check it compiles. `swift test` passing does **not** prove this.

**3. Confirm the weekly grid visually.** No screenshot capture has ever succeeded here —
several attempts failed on window registration and session timeouts. Build and launch:

```sh
open -n /private/tmp/LessonPlannerDerivedData/Build/Products/Debug/LessonPlanner.app \
  --env LESSONPLANNER_DESIGN_CAPTURE=1 --env LESSONPLANNER_INITIAL_TAB=week
```

Open **This Week** and compare against
`Design Screenshots/2026-07-28/07-this-week-cell-flow-compact.png`, confirming that:

- lesson cards in crowded cells are fully visible rather than sliced through the middle;
- sparse and empty rows have collapsed instead of holding a tall blank band;
- row borders still align across the Time column and every day column;
- blocks that start a few minutes apart across days now share one row.

Save the result to `Design Screenshots/<today>/`. **Capture the window only, never the full
screen** — full-screen capture can pick up unrelated sensitive content.

## Then propose the next batch

Once those three are settled, tell me the compute level and model shape and propose the next
batch. My current priority order:

1. **Template layout/master inheritance in `PowerPointTemplateInspector`** — the inspector
   reads slide-level XML but does not resolve placeholders inherited from slide layouts and
   masters. This is the largest gap between the exporter and the release gates in
   `POWERPOINT_EXPORTER_STRATEGY_ADR.md`. *High compute, dual model recommended — Open XML
   inheritance is subtle and worth a second opinion.*
2. **Source-readiness screen** — classify extracted content as embedded text, OCR text,
   uncertain text, diagram, handwriting, or math notation, and give me an explicit review path
   for anything unreliable. *Medium-to-high, dual helpful.*
3. **Document Intake polish** — make the import → weekly-plan path feel like there are no
   steps between A and B, with a clear "import complete, weekly plan ready" success state.
   *Low-to-medium, single sufficient.*
4. **PowerPoint and Google Slides round-trip review** of a generated deck. *Needs me.*

## Boundaries — non-negotiable

- No school-owned or proprietary curriculum, student data, school templates, or employer-owned
  fixtures in code, tests, screenshots, or documentation.
- Do not send source material to a hosted model without my explicit authorization in the
  current task.
- Do not make AI mandatory for any core workflow.
- `SlideDeckBridge.swift` is a personal-only legacy bridge depending on an owner-local Node
  runtime. Do not extend it and do not treat it as sellable architecture. The native Swift
  Open XML exporter is the supported path.
- Do not generate outputs from unapproved lessons, and do not auto-approve generated drafts.
