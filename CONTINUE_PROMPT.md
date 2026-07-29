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
2. `CONTINUITY_LOG.md` — my standing operating protocol, plus a step-level log of recent
   batches **including a dead-ends list**. Do not retry anything on that list.
3. `MODEL_HANDOFF.txt` — full product intent, architecture decisions, current state, and IP
   boundaries.
4. `BUILD_LOG.md` — long-form milestone history and the current capability inventory.

Also read `/Users/nils/.claude/plans/snuggly-brewing-elephant.md` — the approved
implementation plan for the visual redesign in progress (see below). Don't re-plan it; follow
it, or ask me if something in it seems stale.

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
- Continue working locally even when GitHub sync is blocked. As an efficiency rule, after
  every **50 logged development steps** since the last GitHub sync/checkpoint, commit the
  current local work if appropriate and attempt to sync to GitHub. If the connector or git
  credentials are still blocked, log the blocker and keep the local repo clean.
- **Before starting a batch, tell me the compute level** (low / medium / high) **and the model
  shape** (single sufficient / dual helpful / dual recommended).
- **Stop and notify me** — do not push through — when a judgment call is mine, when
  verification needs my eyes or my accounts, when a credential or OS permission is missing,
  or when the same approach has failed twice. Tell me exactly what to do to unblock it.
- For anything visual or interactive (a UI redesign, a new screen), **stop for my visual
  confirmation before moving to the next screen/area** — don't redesign everything in one
  pass on spec alone. This is exactly where we paused this session; see below.
- Log **dead ends with the reason**. An unrecorded dead end gets retried by the next model.
- **Confirm a file actually landed on disk before logging that it was written.**

## Environment

You have a real shell on my Mac in Claude Code: build, test, run `git`, and launch the app
directly.

```sh
swift test -Xswiftc -gnone

xcodebuild -project LessonPlanner.xcodeproj -scheme LessonPlanner \
  -configuration Debug -derivedDataPath /private/tmp/LessonPlannerDerivedData \
  build CODE_SIGNING_ALLOWED=NO
```

Baseline is **103 tests passing**. The project is under git — `git log --oneline` for the
current commit history. As of this handoff, local work through Batch 011 is committed at
`e1c9b86` (`Batch 008-011: redesign This Week and add progress safety`). GitHub remote is
configured as `https://github.com/niljuanzo89/Teachers-Assistant.git`, but command-line push
is currently blocked by missing local GitHub credentials and the Codex GitHub connector
currently reports zero visible accounts/repositories from tool calls despite showing
connected in settings. Continue local work and retry GitHub sync after every 50 logged steps
or when credentials/access are fixed.

Use a second model (Codex, via the `codex-bridge` skill) only when an independent opinion is
genuinely valuable — e.g. an unfamiliar file format's exact rules, or a correctness review of
a finished diff — not as a routine step.

## Traps and gotchas already discovered — don't rediscover these

1. **`swift test` without `-Xswiftc -gnone`** can die during dSYM generation with
   `Operation not permitted` and report **zero tests run**. Zero tests is a failure, not a
   pass.
2. **`LessonPlanner.xcodeproj` uses explicit file references, not synchronized groups.** A new
   source file is invisible to the Xcode target until you add four entries to
   `project.pbxproj` (PBXBuildFile, PBXFileReference, PBXGroup children,
   PBXSourcesBuildPhase). SwiftPM auto-discovers files, so **`swift test` will pass while the
   Xcode build fails.** `WeeklyGridLayout.swift` and `DesignSystem.swift` are worked examples.
3. **Never trust a build result without checking the binary's timestamp.** A background build
   can return a PID and an empty log while a stale binary makes it look successful.
4. **`screencapture -l <windowID>` fails with "could not create image from window"** unless
   the target window is frontmost. Run
   `osascript -e 'tell application "LessonPlanner" to activate'` first (a plain Apple Event,
   no Accessibility permission needed) before capturing by window ID. When several
   same-bundle-ID processes are running (a stuck old instance is common in this project),
   this `activate` call — not a generic app-launcher tool — reliably brings the *correct*,
   most-recently-launched instance forward.
5. **If using `computer-use` to type into the app**, insert a short `wait` (~0.3s) between a
   `left_click` that changes text-field focus and the `type` that follows it — SwiftUI's
   focus-change can lag behind the click, and typed text will land in the previously-focused
   field instead.
6. **A blinking text-field caret can visually merge with a placeholder's first letter in a
   screenshot**, making it misread (e.g. "Add a task" briefly reading as "Id a task"). Not a
   bug — re-screenshot after the field loses focus before concluding there's a real defect.
7. **Codex MCP calls that set `cwd` and expect it to explore repo files can time out**, even
   for a single well-scoped ask. Pasting the relevant code/question directly into the prompt
   (no file access needed) is more reliable for this project. Also: a Codex `threadId` from an
   earlier turn can go stale (`"Session not found"`) — be ready to start a fresh thread.

## Where things stand

**Recently completed and verified (through Batch 011):**

- Weekly planning grid: rows size to their tallest cell (88pt floor), nearby start times
  cluster into one row via the tested `WeeklyGridLayout` type. Visually confirmed.
- Version control initialized; the `project.pbxproj` hand-edits are validated by real
  `xcodebuild` runs, not just `swift test`.
- `PowerPointTemplateInspector.resolvePlaceholders(url:)` resolves placeholder type/idx/
  geometry inherited from slide layouts and masters (ECMA-376 rules), for arbitrary
  customer-owned `.pptx` templates — reviewed with Codex for correctness. Wired into the
  Workspace tab as a "Placeholder inheritance" list (transient state, not persisted).
- **"Sunrise Planner" visual redesign, Batch A (foundation + Today screen) — done and
  committed.** I supplied a full design handoff (warm/rounded/serif reskin of all 5 screens);
  Claude built `Sources/LessonPlanner/Views/DesignSystem.swift` (color/radius/shadow tokens,
  reusable card/tag/button/text-field components), replaced the native `TabView` chrome with
  a custom top nav + profile band, and fully re-skinned the Today screen. Typography uses
  system serif (New York), icons stay SF Symbols (hierarchical rendering) — both confirmed
  with me up front rather than assumed. Screenshot:
  `Design Screenshots/2026-07-29/09-today-sunrise-redesign.png`. Design reference preserved
  at `Design Reference/warm-morning-2026-07-29/`.
- **"Sunrise Planner" visual redesign, Batch B (This Week) — implemented, verified, and
  captured after reboot; awaiting owner visual approval.** The stale PID 23296 blocker is no
  longer active after reboot. A first real capture exposed horizontal clipping, so
  `WorkspaceView.swift` was corrected to make the weekly board the full-width primary surface
  and move weekly tools below it. Re-verified afterward: `swift build` passed, `swift test
  --disable-sandbox --scratch-path /private/tmp/lessonplanner-build -Xswiftc -gnone` passed
  101 tests and real `xcodebuild` succeeded. Corrected screenshot:
  `Design Screenshots/2026-07-29/10-this-week-sunrise-redesign.png`.
- **Batch B polish (This Week output buttons) — implemented and visually captured; awaiting
  owner approval.** Owner said the Plan/Deck/Guide text wrapping was visually problematic and
  generated outputs stayed orange after click. `WeeklyAssignmentOutputControlsView` now uses
  compact fixed-size icon + letter chips (`P`, `D`, `G`), with green check styling for
  generated/openable outputs and light outlined orange styling for pending outputs. Full
  hover help/accessibility labels preserve meaning. Verification: 101 tests passed and
  Xcode build succeeded. Screenshot:
  `Design Screenshots/2026-07-29/11-this-week-output-button-fix.png`. Failed stale-window
  artifact remains at `10-capture-failed-old-stuck-instance.png` and must not be used as
  proof.
- **Progress safety controls — implemented and verified; visual confirmation still needed.**
  Workspace now has a "Progress safety" section to save current progress, reload a saved
  progress snapshot, and clear documents/entries behind a destructive confirmation dialog.
  Clear wipes imported documents, lessons, generated-output history, current daily plan,
  current weekly planner, registered source folders, and course pacing while keeping the
  local profile/workspace/output folder shell. It does not delete generated files from disk.
  Snapshot restore deliberately skips readable-document auto-sync so reloading is exact.
  Verification: 103 tests passed and Xcode build succeeded.

**This is a deliberate pause point, not a finished feature.** Planning Preview, Document
Intake, and Workspace still use the *original* stock-SwiftUI look. Do not move to them until
This Week has been visually captured and approved.

## Start here

1. **Ask me to visually approve the latest This Week screenshot and the new Workspace
   Progress safety section** before making more UI
   redesign changes:

   `Design Screenshots/2026-07-29/11-this-week-output-button-fix.png`

   Mention that the output actions now use compact P/D/G icon chips to avoid wrapping, and
   generated outputs turn green rather than staying orange. Also mention that the new
   Progress safety controls are functionally verified but have not yet had owner visual QA.

2. **If I approve or give feedback that doesn't change the approach**: continue with Batch C
   of the redesign — Planning Preview — following
   `/Users/nils/.claude/plans/snuggly-brewing-elephant.md`'s described rollout (foundation is
   already built; each remaining batch re-skins one/two screens onto it). Declare compute
   level and model shape first, as always.

3. **If I want changes to the approach itself** (different font/icon strategy, different
   pacing, different screen order): treat that as a new judgment call, not a deviation from
   the plan — the plan file reflects what was approved *before* I'd seen the result, and my
   in-hand feedback now supersedes it where the two conflict.

## Then, further down my priority list (after the redesign, or in parallel if it makes sense)

1. **Layout-preserving PowerPoint export** — use the placeholder-inheritance resolution
   (`PowerPointTemplateInspector.resolvePlaceholders(url:)`) to actually place approved-lesson
   content into a customer-owned template's resolved placeholder frames, instead of only
   displaying the resolution in the UI. *High compute, dual model recommended if the
   placement/layout logic gets subtle.*
2. **Source-readiness screen** — classify extracted content as embedded text, OCR text,
   uncertain text, diagram, handwriting, or math notation, and give me an explicit review path
   for anything unreliable. *Medium-to-high, dual helpful.*
3. **Document Intake polish** — make the import → weekly-plan path feel like there are no
   steps between A and B, with a clear "import complete, weekly plan ready" success state.
   *Low-to-medium, single sufficient.* (Batch D of the redesign will cover some of this
   visually; the underlying flow/copy work is separate.)
4. **PowerPoint and Google Slides round-trip review** of a generated deck. *Needs me.*
5. **Visual confirmation of the "Placeholder inheritance" list** against a real customer-owned
   `.pptx` template (register one through the interactive file picker and click "Inspect
   presentation template"). *Needs me — this project's own generated decks can't exercise it.*

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
- Do not reintroduce native `TabView` chrome, bundle actual Source Serif 4 font files, or
  hand-draw custom icons for the redesign without checking with me first — these were
  explicit, confirmed decisions this session, not defaults to silently reconsider.
