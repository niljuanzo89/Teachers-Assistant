# CLAUDE.md — LessonPlanner

Read this first. If you are starting a fresh session, `CONTINUE_PROMPT.md` is a
ready-to-paste continuation prompt covering orientation, working agreement, and the exact
next tasks. Then read `CONTINUITY_LOG.md` (operating protocol + recent work + dead ends),
then `MODEL_HANDOFF.txt` (product intent, architecture, boundaries).

## What this is

A local-first native macOS teacher-planning app in Swift/SwiftUI. A teacher imports curriculum
and schedule documents; the app builds course pacing and a weekly planner; each approved lesson
drives three aligned outputs — an HTML lesson plan, a PPTX slide deck, and an HTML
differentiation guide — collected into a weekly package.

It is a **generic product shell**, not a curriculum-specific tool. It must stay useful with
generative AI switched off.

## Environment — you can do more here than the previous environment could

This project was previously worked on from a sandbox with **no Swift toolchain and no GUI**,
which forced every build, test, and screenshot through a Codex bridge. In Claude Code you have
a real shell on the owner's Mac. You can build, test, run `git`, and inspect output directly.
**You do not need Codex for routine build and test work.** Use it only when a genuine second
opinion is wanted (see `codex-critic` / `codex-bridge` skills).

## Build and test

```sh
cd "/Users/nils/Documents/Program Development Folder/LessonPlanner"

# Tests — the -gnone flag matters, see below
swift test -Xswiftc -gnone

# Full form used previously when caches misbehaved
CLANG_MODULE_CACHE_PATH=/private/tmp/lessonplanner-clang-cache \
SWIFTPM_CACHE_PATH=/private/tmp/lessonplanner-swiftpm-cache \
swift test --disable-sandbox --scratch-path /private/tmp/lessonplanner-build -Xswiftc -gnone

# Xcode build
xcodebuild -project LessonPlanner.xcodeproj -scheme LessonPlanner \
  -configuration Debug -derivedDataPath /private/tmp/LessonPlannerDerivedData \
  build CODE_SIGNING_ALLOWED=NO
```

**`-Xswiftc -gnone` is not optional in some sandboxes.** Without it `swift test` can die during
dSYM generation with `generate-dSYM command failed / Operation not permitted` and report **zero
tests run** — which reads like a pass if you skim. If you see 0 tests, that is a failure.

Current baseline: **93 tests passing.**

## ⚠️ Adding a new source file requires editing project.pbxproj by hand

`LessonPlanner.xcodeproj` uses **explicit file references**, not Xcode 16 file-system
synchronized groups. SwiftPM (`swift test`) auto-discovers new files, so **tests will pass while
the Xcode app build fails** with "cannot find X in scope."

When you add a file under `Sources/LessonPlanner/`, add four entries to
`LessonPlanner.xcodeproj/project.pbxproj`, following the existing sequential ID pattern
(`A0000000000000000000NNNN` for build files, `A1000000000000000000NNNN` for file references):

1. A `PBXBuildFile` entry.
2. A `PBXFileReference` entry.
3. The file reference added to the `PBXGroup` children list.
4. The build file added to the `PBXSourcesBuildPhase` files list.

`WeeklyGridLayout.swift` (IDs `...015`) is the most recent worked example — copy its shape.
**Always follow a pbxproj edit with a real `xcodebuild` run.** `swift test` will not catch a
mistake here.

## Architecture — the load-bearing rules

- **Native SwiftUI, local-first.** Not a web app. Application data stays on the machine.
- **One approved `LessonRecord` drives every output.** Nothing is generated from a draft.
- **Approval gates outputs.** No auto-approval of generated drafts.
- **AI is optional.** The Codex CLI draft adapter is a personal convenience, never a requirement.
- **Native Swift Open XML is the supported PowerPoint path** (`NativePowerPointExporter.swift`).
  `SlideDeckBridge.swift` is a personal-only legacy bridge depending on an owner-local Node
  runtime — do not extend it and do not treat it as sellable architecture.
- **Schedules are not lessons.** Source classification must keep instructional fields empty for
  schedule-type sources.
- **PDF visual content is not text.** Handwriting, diagrams, and math notation must never be
  silently treated as reliably extracted.

## Boundaries — non-negotiable

- No school-owned or proprietary curriculum, student data, school templates, or employer-owned
  fixtures in code, tests, screenshots, or docs.
- Do not send source material to a hosted model without explicit authorization in the current
  task.

## Working agreement

Defined in full in `CONTINUITY_LOG.md`. In short:

- Work in batches of **up to 20 numbered steps**; log every step.
- **Stop and notify** when human judgment, human eyes, a credential, or an OS permission is
  needed — and when the same approach has failed twice.
- **Declare compute (low/medium/high) and model shape (single / dual helpful / dual recommended)
  before starting a batch.**
- Log **dead ends** with the reason. An unrecorded dead end gets retried by the next model.
- Confirm a file actually landed on disk before logging that it was written.

## Key files

| File | Role |
|---|---|
| `Sources/LessonPlanner/Models/AppModels.swift` | Codable domain models (~1,660 lines) |
| `Sources/LessonPlanner/AppStore.swift` | App state and workflow (~1,510 lines) |
| `Sources/LessonPlanner/Views/WorkspaceView.swift` | Main workspace, all five tabs (~2,340 lines) |
| `Sources/LessonPlanner/WeeklyGridLayout.swift` | Pure, testable weekly-grid row clustering |
| `Sources/LessonPlanner/NativePowerPointExporter.swift` | Supported PPTX writer |
| `Sources/LessonPlanner/PowerPointTemplateInspector.swift` | Template slide-XML inspection |
| `Sources/LessonPlanner/LessonPlanRenderer.swift` | Deterministic HTML renderers |
| `Tests/LessonPlannerTests/LessonPlannerTests.swift` | Full suite, 93 tests |

## Running the app for visual QA

```sh
open -n /private/tmp/LessonPlannerDerivedData/Build/Products/Debug/LessonPlanner.app \
  --env LESSONPLANNER_DESIGN_CAPTURE=1 --env LESSONPLANNER_INITIAL_TAB=week
```

`LESSONPLANNER_INITIAL_TAB` accepts `today|week|planning|intake|workspace`.
`LESSONPLANNER_DESIGN_CAPTURE=1` opens at a larger review size without affecting normal launch.

Screenshots go in `Design Screenshots/<date>/`. **Capture the window only, never the full
screen** — full-screen capture can pick up unrelated sensitive content.

## State as of 2026-07-29

**Done and test-verified:** weekly grid rows size to their tallest cell (no clipping, no blank
bands); nearby start times cluster into one row instead of one row per exact minute.

**Open — needs the owner or a real terminal:**

1. `git init` was never completed. A partial `.git/` may still exist and may need
   `rm -rf .git` before `git init && git add -A && git commit`. **Do this first** — there is
   currently no rollback path for anything.
2. The `project.pbxproj` edit registering `WeeklyGridLayout.swift` is **unverified**. Run
   `xcodebuild` and confirm it compiles before trusting it.
3. Visual confirmation of the weekly grid changes has never succeeded. Launch the app, open
   **This Week**, and compare against
   `Design Screenshots/2026-07-28/07-this-week-cell-flow-compact.png`.
4. PowerPoint and Google Slides round-trip review of a generated deck.
5. Template layout/master inheritance in `PowerPointTemplateInspector` — the largest remaining
   gap before the exporter meets its release gates.
