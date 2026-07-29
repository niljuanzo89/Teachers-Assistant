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

Current baseline: **112 tests passing** (as of Batch 023 — see `CONTINUITY_LOG.md` for the
authoritative, up-to-date count; this file is not always refreshed every batch).

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
- Commit each completed, verified batch locally. Push to GitHub every 2-3 committed batches,
  before risky work, or before a handoff. If command-line auth is blocked, use GitHub
  Desktop and log the blocker.
- **Stop and notify** when human judgment, human eyes, a credential, or an OS permission is
  needed — and when the same approach has failed twice.
- **Declare compute (low/medium/high) and model shape (single / dual helpful / dual recommended)
  before starting a batch.** When compute is high, route through the `codex-router` pattern
  to delegate rather than doing everything solo (owner instruction, added mid-Batch-023).
- For anything visual/interactive (a redesigned screen, a new UI area), **stop for the
  owner's visual confirmation before moving to the next one** — self-verification (screenshots,
  scrolling through every state) is necessary but not sufficient; don't declare it "done."
- Log **dead ends** with the reason. An unrecorded dead end gets retried by the next model.
- Confirm a file actually landed on disk before logging that it was written.

## Key files

| File | Role |
|---|---|
| `Sources/LessonPlanner/Models/AppModels.swift` | Codable domain models |
| `Sources/LessonPlanner/AppStore.swift` | App state and workflow (~1,800 lines) |
| `Sources/LessonPlanner/Views/WorkspaceView.swift` | Main workspace, all five tabs (~3,700 lines) |
| `Sources/LessonPlanner/Views/DesignSystem.swift` | "Sunrise Planner" design-system layer (`DS` tokens, `DSCard`, `DSTag`, button/text-field styles) — added Batch 007 |
| `Sources/LessonPlanner/WeeklyGridLayout.swift` | Pure, testable weekly-grid row clustering |
| `Sources/LessonPlanner/LessonOutputContent.swift` | Shared lesson-output content normalizer, feeds the native slide exporter — added Batch 017 |
| `Sources/LessonPlanner/NativePowerPointExporter.swift` | Supported PPTX writer |
| `Sources/LessonPlanner/PowerPointTemplateInspector.swift` | Template slide-XML inspection + placeholder-inheritance resolution |
| `Sources/LessonPlanner/LessonPlanRenderer.swift` | Deterministic HTML renderers |
| `Tests/LessonPlannerTests/LessonPlannerTests.swift` | Full suite, 112 tests as of Batch 023 |

## Running the app for visual QA

```sh
open -n /private/tmp/LessonPlannerDerivedData/Build/Products/Debug/LessonPlanner.app \
  --env LESSONPLANNER_DESIGN_CAPTURE=1 --env LESSONPLANNER_INITIAL_TAB=week
```

`LESSONPLANNER_INITIAL_TAB` accepts `today|week|planning|intake|workspace`.
`LESSONPLANNER_DESIGN_CAPTURE=1` opens at a larger review size without affecting normal launch.

Screenshots go in `Design Screenshots/<date>/`. **Capture the window only, never the full
screen** — full-screen capture can pick up unrelated sensitive content.

## State as of 2026-07-29 (Batch 023)

This section is a snapshot and goes stale between refreshes — `CONTINUITY_LOG.md` (batch log)
and `MODEL_HANDOFF.txt` (full current state, sections 4/10/11/13) are the sources of truth if
this reads inconsistently with recent work.

**"Sunrise Planner" visual redesign — code-complete across all 5 screens.** The owner supplied
a full design handoff (warm/rounded/serif reskin), preserved at
`Design Reference/warm-morning-2026-07-29/`; plan at
`/Users/nils/.claude/plans/snuggly-brewing-elephant.md`. Font: system serif (New York), not
bundled Source Serif 4. Icons: SF Symbols with `.symbolRenderingMode(.hierarchical)`, not
hand-drawn shapes. Both confirmed with the owner up front. This Week, Planning Preview, and
Document Intake are owner-reviewed and approved. Today (Batch 007) and Workspace (Batch 023)
are built, tested, and self-verified but still need an explicit owner visual sign-off —
**Workspace specifically is the one open stop-and-confirm checkpoint** right now (screenshot:
`Design Screenshots/2026-07-29/10-workspace-sunrise-redesign.png`).

**Two-stage document intake + subject-aware scheduling (Batches 018-022).** Document Intake
splits imports into a Planning lane (schedules, pacing guides, calendars) and a Content lane
(lesson packets, worksheets); Content import is locked until a readable daily schedule block
exists (Batch 020). A "Build schedule scaffold" action then shows empty subject-block
placeholders on This Week even before content exists (Batch 021). Content documents are
matched to the correct schedule block by a scored, word-boundary keyword match against both
the lesson's short fields *and* the source document's full extracted text (Batch 022) — not
by requiring the literal subject name to appear in a title, which was the root cause of a
real "Math content not filling the Math block" bug. Codex-reviewed; see Batch 022's log entry
before changing this matching logic again.

**Template placeholder inheritance (Batches 005-006).**
`PowerPointTemplateInspector.resolvePlaceholders(url:)` resolves placeholder type/idx/
geometry across slide -> layout -> master inheritance for arbitrary imported `.pptx`
templates (ECMA-376 rules, Codex-reviewed). Wired into the Workspace tab's "Placeholder
inheritance" list (transient state, not persisted) — still needs the owner to register a real
`.pptx` template and click "Inspect presentation template" to visually confirm it; this
project's own generated decks have no placeholders to show.

**Native output enrichment (Batch 017).** The native PowerPoint exporter generates a 7-slide
sequence (opening, learning goal, warm-up, build-understanding, practice, supports, exit
ticket) via the shared `LessonOutputContent` normalizer, replacing the old bare 5-slide
skeleton. Lesson-plan/differentiation-guide HTML templates have not yet been upgraded to use
the same enriched content — see `OUTPUT_ENRICHMENT_PLAN.md`.

**Window-capture trick, worth keeping:** `screencapture -l <windowID>` fails with "could not
create image from window" unless the window is frontmost/on-screen. `osascript -e 'tell
application "LessonPlanner" to activate'` (a plain Apple Event — no Accessibility permission
needed) brings it forward first; `System Events` window enumeration still fails with
`-1728` (assistive access not granted) — use `CGWindowListCopyWindowInfo` via a small Swift
script instead.

**Open — needs the owner:**

1. Visual sign-off on the Workspace screen redesign (Batch 023) — see above.
2. Push pending local git commits to GitHub — command-line push is blocked (missing
   credentials); a computer-use request for GitHub Desktop access was denied once (Batch 022).
3. PowerPoint and Google Slides round-trip review of a generated deck (needs a human account/eyes).
4. Visual confirmation of the "Placeholder inheritance" list against a real customer template.
5. A layout-preserving exporter path that actually uses the resolved placeholder frames —
   not started.
