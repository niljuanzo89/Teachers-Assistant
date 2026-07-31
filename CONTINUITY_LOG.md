# LessonPlanner — Continuity Log

**Purpose.** This file is the running, step-level record of work on LessonPlanner. Its job
is to let work travel between models with complete continuity: any model picking this
project up should be able to read `MODEL_HANDOFF.txt` for *state* and this file for
*what just happened and why*, then continue without re-deriving decisions or repeating
dead ends.

Read order for a model joining this project:

1. `MODEL_HANDOFF.txt` — product intent, architecture, boundaries, current state.
2. `CONTINUITY_LOG.md` (this file) — most recent batch first; what was tried, what worked.
3. `BUILD_LOG.md` — long-form chronological milestones and capability inventory.

---

## Operating protocol

This protocol is the owner's standing instruction. Follow it unless the owner says otherwise.

### 1. Work in batches of up to 20 steps

Take up to 20 steps per turn. A "step" is a discrete unit of work: a code edit, a build, a
test run, a file created, a verification performed. Number them and log each one.

Stop early — before 20 — if any of the stop conditions below are met. Do not pad a batch
to reach 20, and do not run past 20 to finish "just one more thing."

### 1b. Standing workflow: plan → review → implement → review (owner instruction, 2026-07-30)

For each substantive batch, in order:

1. **Formulate the plan** — concrete steps, the risks, and what could break.
2. **Send the plan to Codex for pre-execution review.** Do not start implementing until it comes
   back. Ask it to push back on scope and design, not just approve.
3. **Implement**, incorporating the review.
4. **Send the completed work to Codex for post-execution review**, and use that debrief to confirm
   what the next step should be.

This was adopted after external review twice caught defects a green test suite did not: Batch 033
(three self-directed attempts oscillated; review found the flaw immediately) and Batch 036/037
(provenance was implemented for lessons only, leaving pacing plans and weekly assignments still
rebuild-owned after a teacher edit — a data-loss path). Treat a passing suite as necessary but not
sufficient evidence.

### 2. Stop when human intervention is needed

Stop work immediately and notify the owner when:

- A judgment call belongs to the owner (product direction, visual design, pricing, scope).
- Verification requires human eyes or a human account — visual QA, PowerPoint or Google
  Slides review, anything needing a Google/Microsoft login.
- A step requires a permission, credential, or OS-level grant the model does not have.
- Proceeding would risk data loss, or would touch school-owned/proprietary material.
- Two reasonable paths diverge and the choice materially changes the product.
- The same approach has failed twice; do not attempt a third time without input.

When stopping, the notification must state: what was completed, what is blocked, the exact
steps the owner needs to take, and what will resume once they are done.

### 3. Declare compute and model shape before each batch

Before starting a new turn of work, state:

- **Compute required** — low / medium / high.
  - *Low*: reading, doc edits, small localized code changes, single build or test run.
  - *Medium*: multi-file feature work, new tests, design that needs a few iterations.
  - *High*: architectural change, new subsystem, cross-cutting refactor, release work.
- **Model shape** — single model sufficient / dual helpful / dual recommended.
  - *Single*: well-specified work with a clear correct answer.
  - *Dual helpful*: benefits from a second opinion but is not correctness-critical.
  - *Dual recommended*: correctness-critical, security-relevant, architectural, or work
    that cannot be verified by the authoring model alone.

### 4. Division of labor between models

- **Claude** (this environment) has file access to the project folder but runs a **Linux**
  sandbox with **no Swift toolchain, no Xcode, and no GUI**. It cannot build, test, run, or
  screenshot the app.
- **Codex** runs locally on the owner's Mac and **can** build, test, launch, and capture.
- Therefore: Claude authors and reasons; Codex builds, tests, and verifies. Any claim that
  code "works" must be backed by a Codex run, not by Claude's reading of the code.
- Codex MCP calls time out on long operations (a full `xcodebuild` will usually exceed the
  window). Break Codex work into small, single-purpose requests.

### 5. Logging rules

- Append a batch entry to this file for every turn of work, newest at the bottom.
- Log failed approaches and *why* they failed. A dead end that is not recorded will be
  retried by the next model.
- Update `MODEL_HANDOFF.txt` when project state or a standing decision changes.
- Update `BUILD_LOG.md` at material milestones.
- Commit each completed, verified batch locally. Push to GitHub every 2-3 committed batches,
  before risky work, before a handoff to another model, or whenever the owner explicitly asks
  for a sync. If command-line GitHub authentication is blocked, use GitHub Desktop and log
  the blocker instead of letting auth troubleshooting consume the batch.
- **Confirm a file actually landed on disk before logging that it was written.** A prior
  session logged a handoff rewrite that was never saved, leaving the docs out of sync for
  a day.

### 6. Standing boundaries

- No school-owned or proprietary curriculum, student data, school templates, or
  employer-owned fixtures in code, tests, screenshots, or docs.
- Do not send source material to a hosted model without explicit authorization in the
  current task.
- Do not make AI mandatory for any core workflow.
- Do not treat personal developer bridges as sellable architecture.

---

## Batch log

### Batch 001 — 2026-07-29 — Weekly planner cell overflow, handoff reconciliation

**Compute:** medium. **Model shape:** dual — Claude authored, Codex built and tested.

**Goal.** Ascertain true project state, fix the reported weekly planner cell overflow,
reconcile documentation discrepancies.

| # | Step | Result |
|---|------|--------|
| 1 | Read `MODEL_HANDOFF.txt` at folder root | Stale — dated 2026-07-27, described 13 tests and the Node/Codex bridge as the PowerPoint path |
| 2 | Inventory `LessonPlanner/` and read `BUILD_LOG.md` tail | Real state far ahead: native exporter, weekly hub, course pacing, 85 tests |
| 3 | Attempt to reach the old Codex project path via Glob | Not reachable; treated the Program Development Folder copy as authoritative |
| 4 | Enumerate sources and line counts | 11 Swift files; `WorkspaceView.swift` largest at ~2,363 lines |
| 5 | Grep for the weekly planner grid views | Found `WeeklyPlanningGridView` and its cell types |
| 6 | Read `WeeklyPlanningGridView` through `WeeklyAssignmentCompactCard` | Found fixed `Metrics.rowHeight = 176` and a nested per-cell `ScrollView` |
| 7 | Read `Design Screenshots/2026-07-28/07-this-week-cell-flow-compact.png` | Confirmed both defects visually |
| 8 | Diagnose | Cards clipped mid-card in crowded cells; sparse rows held tall blank bands; nested scroll view captured wheel events and hid clipping with no affordance |
| 9 | Edit `Metrics`: `rowHeight` 176 → `minRowHeight` 88 | Done |
| 10 | Add `.fixedSize(horizontal: false, vertical: true)` to each row `HStack` | Done |
| 11 | Convert `WeeklyPlanningTimeCell` to `minHeight` + `.frame(minHeight:maxHeight:.infinity)` | Done |
| 12 | Convert `WeeklyPlanningTableCell` the same way; remove nested `ScrollView` + `LazyVStack` | Done |
| 13 | Confirm no Swift toolchain in the Claude sandbox | Confirmed Linux, no `swift`/`xcodebuild` — verification must go to Codex |
| 14 | Ask Codex for full build + test + critique + screenshot | MCP timeout — request too large |
| 15 | Ask Codex for `swift test` only | Failed at dSYM generation, "Operation not permitted", 0 tests run — **environment issue, not a code failure** |
| 16 | Ask Codex to retry with `-Xswiftc -gnone` | **85 tests passed, 0 failures**, no compile errors from the edit |
| 17 | Ask Codex to build, launch, and capture the This Week screen | Timed out; created an empty `Design Screenshots/2026-07-29/`; session then expired |
| 18 | Discover `BUILD_LOG.md` claims a 2026-07-29 handoff refresh | Both handoff copies were still the 2026-07-27 version — **the logged rewrite never reached disk** |
| 19 | Owner supplied the missing refreshed handoff as an upload | Installed it rather than duplicating the work |
| 20 | Merge today's changes into the handoff and sync both copies | Both copies byte-identical; `BUILD_LOG.md` given two new entries |

**Outcome.** Overflow fix implemented and test-verified. Handoff and build log reconciled.

**Dead ends — do not repeat.**

- Fixed row heights in the weekly grid. Tried 2026-07-28, caused the clipping and blank-band
  defects. Superseded.
- Nested per-cell `ScrollView` in the weekly grid. Captures scroll-wheel events away from the
  grid and hides clipped content with no affordance. Removed.
- Large multi-part Codex requests. They exceed the MCP timeout window. Keep each request to
  one build, one test run, or one capture.
- Bare `swift test` in this environment. Fails at dSYM generation and misleadingly reports
  zero tests. Always pass `-Xswiftc -gnone`.

**Left open.**

1. Visual confirmation of the intrinsic-row-height fix — needs a successful capture or the
   owner's eyes.
2. Project is not under version control.
3. Weekly grid still emits one row per distinct start time, matching exact hour and minute.
   Logged, not changed; intrinsic heights make the extra rows cheap.

---

### Batch 002 — 2026-07-29 — Protocol setup, version control attempt, visual verification attempt

**Compute:** low. **Model shape:** dual — Claude authored, Codex attempted build/launch/capture.

**Goal.** Install the owner's operating protocol as the working basis, put the project under
version control, and close the open visual-confirmation loop from Batch 001.

| # | Step | Result |
|---|------|--------|
| 1 | Create `CONTINUITY_LOG.md` with the operating protocol | Done — batches of 20, stop conditions, compute/model disclosure, division of labor, logging rules |
| 2 | Add read-order and protocol pointer to `MODEL_HANDOFF.txt`, both copies | Done, copies byte-identical |
| 3 | Write `.gitignore` | Done — excludes `.build/`, `DerivedData/`, `xcuserdata/`, `.DS_Store`, generated `.pptx`; keeps `Design Screenshots/` tracked |
| 4 | `git init` + `git add` from the Claude sandbox | **Failed.** Mount forbids unlinking; git could not clean its own temp objects. Left a partial `.git/` and a stale `index.lock` |
| 5 | Ask Codex to clear the lock and commit | **Failed.** Codex `workspace-write` deliberately protects `.git/` from agent writes |
| 6 | Diagnose both failures | Two independent causes, neither fixable from inside a model. Declined to escalate Codex to `danger-full-access` to defeat a safety guardrail for a task the owner can do in four lines |
| 7 | Owner confirmed the authoritative working paths | Matches the paths already in use; no change needed |
| 8 | Launch `xcodebuild` in the background via Codex (`nohup`, log to `/private/tmp/lp-build.log`) | Started, PID 25218 — this pattern avoids the MCP timeout that killed Batch 001 step 17 |
| 9 | Poll build to completion | Process finished; `LessonPlanner.app` present in DerivedData |
| 10 | Launch in design-capture mode and capture the This Week window | **Failed.** The LessonPlanner window never appeared in the Quartz window list |
| 11 | Stop per the two-failure rule | Batch halted at 11 of 20 steps; two blockers escalated to the owner |

**Outcome.** Protocol installed. Version control and visual confirmation both blocked on the
owner. Batch stopped early by design rather than run to 20.

**Dead ends — do not repeat.**

- `git` write operations from the Claude sandbox against this mount. Unlink is not permitted;
  git cannot even clean up after itself. All git work must happen in the owner's Terminal.
- Asking Codex to modify `.git/` under `workspace-write`. It is guarded on purpose. Do not
  route around it by escalating the sandbox.
- Launching the app via `open -n --env` and capturing through Quartz *in this session*. The
  window did not register. Worked on 2026-07-28, so it is environment-dependent, not a code
  defect. Try no more than once before handing back to the owner.

**Still open.**

1. **Version control** — owner must run the four Terminal lines in the notification below.
2. **Visual confirmation of the intrinsic-row-height fix** — still unverified by eye. This is
   the last thing standing between Batch 001 and "done."
3. Weekly grid still emits one row per distinct start time (exact hour + minute match).

---

### Batch 003 — 2026-07-29 — Weekly grid time-slot consolidation, Claude Code migration prep

**Compute:** medium. **Model shape:** dual — Claude authored, Codex ran the test suite.

**Goal.** Stop the weekly grid emitting one row per distinct start time, and prepare the
project to move into Claude Code without re-briefing.

| # | Step | Result |
|---|------|--------|
| 1 | Check whether git was committed | Still uncommitted; kept all edits surgical and hand-reversible |
| 2 | Re-read `timeSlots`, `assignments(for:slotStart:)`, `timeRangeLabel(for:)` | Slot identity was computed by exact hour+minute in **three** separate places |
| 3 | Design clustering | Greedy sweep anchored on the *first* start in each cluster, 15-minute tolerance |
| 4 | Create `Sources/LessonPlanner/WeeklyGridLayout.swift` | Pure, SwiftUI-free, testable. Owns slot identity in one place |
| 5 | Point the grid's empty check at `layout.slots` | Done |
| 6 | Replace the row `ForEach` with `ForEach(layout.slots)`, label from `slot.label` | Done |
| 7 | Delete `timeSlots`, `assignments(for:slotStart:)`, `timeRangeLabel(for:)` | Three duplicated implementations of slot identity removed |
| 8 | Spot a performance flaw in the first cut | `layout` as a computed property re-clustered every assignment for every day column |
| 9 | Hoist `let layout = WeeklyGridLayout(...)` to the top of `body` | Built once per redraw, passed down |
| 10 | Check test target import style | `@testable import LessonPlanner`, so `internal` types are reachable |
| 11 | Add 8 `WeeklyGridLayout` tests | Empty input, merging, distinct blocks, drift-chaining, label span, day filtering, title tie-break, custom tolerance |
| 12 | Check whether `.xcodeproj` uses synchronized groups | **It does not** — explicit file references only |
| 13 | Recognize the trap | `swift test` would pass while the Xcode app build failed — new files are invisible to the app target |
| 14 | Back up `project.pbxproj`, add 4 entries for the new file | `PBXBuildFile`, `PBXFileReference`, group children, sources build phase |
| 15 | Codex: run the suite | **93 tests passed, 0 failures**, no compile errors |
| 16 | Codex: background `xcodebuild` to validate the pbxproj edit | Returned a PID but wrote no log |
| 17 | Investigate | Log had 1 line; built binary timestamped Jul 28 — **the background build never ran** |
| 18 | Conclude and stop per two-failure rule | Background builds do not survive the Codex session. pbxproj edit remains **unverified** |
| 19 | Write `CLAUDE.md` | Environment, commands, the pbxproj trap, architecture rules, boundaries, working agreement, open items |
| 20 | Add Claude Code migration section to `MODEL_HANDOFF.txt`, both copies | Read order now starts at CLAUDE.md; copies byte-identical |

**Outcome.** Grid now clusters nearby start times into one row. Slot identity lives in one
tested type instead of three copies. Project is ready to pick up in Claude Code.

**Dead ends — do not repeat.**

- Backgrounding a long build through Codex (`nohup ... &`). The process does not survive the
  session; you get a PID and an empty log, and a stale binary makes it look like it worked.
  **Check the binary timestamp before believing a build result.**
- Computing `WeeklyGridLayout` as a computed property read from inside the view body. It
  re-clusters per cell. Build it once at the top of `body`.
- Adding a source file without editing `project.pbxproj`. `swift test` passes; the Xcode
  build breaks. There are no synchronized groups in this project.

**Still open.**

1. **git** — still not initialized. No rollback path exists for any of this work.
2. **`project.pbxproj` edit is unverified** — needs one real `xcodebuild` run.
3. **Visual confirmation** of Batch 001 and Batch 003 grid changes — never succeeded.
4. Template layout/master inheritance in `PowerPointTemplateInspector` — largest remaining
   gap before the exporter meets its release gates.

---

### Batch 004 — 2026-07-29 — Claude Code migration: version control, pbxproj validation, visual confirmation

**Compute:** low. **Model shape:** single — Claude Code has a real shell on the owner's Mac
and could build, test, launch, and capture directly; no second model was needed.

**Goal.** Close the three items left open at the end of Batch 003: get the project under
version control, validate the hand-edited `project.pbxproj` with a real `xcodebuild`, and get
the first-ever successful visual confirmation of the weekly grid intrinsic-height fix.

| # | Step | Result |
|---|------|--------|
| 1 | Check for an existing `.git` before acting | Found one, dated today, zero commits, no remote — safe to use as-is, no need for `rm -rf` |
| 2 | Check for a live git process before touching `index.lock` | `ps aux` showed none; the lock was a stale empty file from a prior failed attempt |
| 3 | Remove the stale lock, `git add -A` | 41 files staged; `.gitignore` correctly excluded `.build/`, `Design Screenshots/` generated `.pptx`, etc. |
| 4 | Review staged file list before committing | Clean — source, docs, screenshots only, no build artifacts |
| 5 | `git commit` | `1c38146` — root commit, 41 files, 12181 insertions |
| 6 | `git log` / `git status` | Confirmed: 1 commit, clean working tree |
| 7 | `swift test -Xswiftc -gnone` as a pre-check | 93 tests passed, 0 failures — matches documented baseline |
| 8 | Clear `/private/tmp/LessonPlannerDerivedData`, run real `xcodebuild` | **BUILD SUCCEEDED**; log shows `Compiling WeeklyGridLayout.swift` — the pbxproj edit is confirmed working |
| 9 | Check the built binary's timestamp against wall clock (per the Batch 003 stale-binary trap) | Binary timestamped the same minute as the build — not stale |
| 10 | Launch app via `open -n --env LESSONPLANNER_DESIGN_CAPTURE=1 --env LESSONPLANNER_INITIAL_TAB=week` | Process started (pid confirmed via `ps`) |
| 11 | Try `osascript ... System Events` to check window list | **Failed** — `osascript is not allowed assistive access (-1728)`. Accessibility permission not granted, as before |
| 12 | List on-screen windows via a small Swift/CoreGraphics script instead (`CGWindowListCopyWindowInfo`, no Accessibility needed) | LessonPlanner's main window existed with the correct design-capture bounds (1500×1002) but `onscreen=false` |
| 13 | Attempt `screencapture -l <windowID>` anyway | **Failed** — "could not create image from window". This is the same failure mode as Batch 002 step 10 |
| 14 | Sanity-check that `screencapture` and the console session work at all | Full-screen capture succeeded (3420×2214); `CGSessionCopyCurrentDictionary` showed an active, unlocked console session — so the failure was specific to this window, not the environment |
| 15 | Try `osascript -e 'tell application "LessonPlanner" to activate'` (Apple Events, not Accessibility) before recapturing the window list | Window now reported `onscreen=true` with its real title `"LessonPlanner"` |
| 16 | Retry `screencapture -l <windowID>` | **Succeeded** — window-only PNG saved to `Design Screenshots/2026-07-29/08-this-week-intrinsic-height.png` |
| 17 | Visually compare against `Design Screenshots/2026-07-28/07-this-week-cell-flow-compact.png` | Crowded cells (2 stacked cards) fully visible, Plan/Deck/Guide controls intact; the old fixed-height totally-blank "9:00–9:45" row is gone — the new single-card row is visibly shorter than the two-card rows around it; grid lines still align across Time and all day columns |
| 18 | Quit the launched app instance (`kill`) | Confirmed no longer running |
| 19 | Delete scratch Swift window-listing scripts and the full-screen sanity-check PNG (never viewed, deleted immediately — could have contained unrelated desktop content) | Done |
| 20 | Stage and commit the new screenshot | Pending as final step of this batch |

**Outcome.** All three items closed. Version control is live with a clean baseline commit.
The `project.pbxproj` edit is now proven correct by a real Xcode build, not just `swift test`.
The weekly grid intrinsic-height fix has its first successful visual confirmation, and it
does what Batch 001/003 intended.

**Dead ends resolved (not dead ends after all).**

- The window-capture failure recorded as a dead end in Batch 002 ("window did not register...
  environment-dependent") had a real cause: the window was not frontmost/on-screen yet.
  `tell application "LessonPlanner" to activate` (a plain Apple Event, not Accessibility)
  brings it forward, after which `CGWindowListCopyWindowInfo` reports `onscreen=true` and
  `screencapture -l <id>` succeeds. **Future sessions: always `activate` the app before
  attempting a window-ID screenshot capture.**

**Dead ends confirmed still valid.**

- `osascript ... tell application "System Events"` for window enumeration still fails with
  `-1728` (assistive access not granted). Use the Apple-Events-only `activate` command plus a
  small Swift/CoreGraphics script instead — neither needs Accessibility permission.

**Still open.**

1. Template layout/master inheritance in `PowerPointTemplateInspector` — largest remaining
   gap before the exporter meets its release gates (owner priority #1, high compute, dual
   model recommended).
2. Source-readiness screen (embedded/OCR/uncertain/diagram/handwriting/math classification)
   — owner priority #2, medium-to-high compute, dual helpful.
3. Document Intake polish — owner priority #3, low-to-medium compute, single sufficient.
4. PowerPoint/Google Slides round-trip review of a generated deck — needs the owner directly.

---

### Batch 005 — 2026-07-29 — Template layout/master placeholder inheritance

**Compute:** high. **Model shape:** dual recommended — Claude authored and implemented;
Codex (only, per owner's session-scoped instruction — Gemini/Grok not used) gave an
independent read on the ECMA-376 inheritance/matching rules before implementation and a
correctness-only review of the actual diff afterward.

**Goal.** Close owner priority #1: extend `PowerPointTemplateInspector` to resolve
placeholder shapes inherited from slide layouts and masters, for arbitrary customer-owned
`.pptx` templates a teacher might import (not our own generated decks — `NativePowerPointExporter`
uses plain absolutely-positioned text boxes, no `<p:ph>` placeholders at all).

| # | Step | Result |
|---|------|--------|
| 1 | Read `PowerPointTemplateInspector.swift`, the ADR, and `AppModels.swift`'s template types | Current inspector only string-counts `<p:ph` occurrences on the slide XML; never reads `_rels`, layouts, or masters |
| 2 | Read `NativePowerPointExporter.swift`'s slide/layout/master output | Confirmed: our own decks don't use placeholders — this work is entirely about reading arbitrary imported templates |
| 3 | Read existing `PowerPointTemplateInspector` tests and the `runZip` fixture-building helper | Established the test pattern to follow |
| 4 | Codex consult #1 (new thread, no repo access — first attempt with `cwd` set timed out) — ECMA-376 `<p:ph>` defaults, idx/type matching rules, spPr inheritance granularity, Keynote/Google-Slides export quirks | Missing `type` defaults to `obj`; missing `idx` defaults to `0`; idx-preferred matching with type fallback; `title`/`ctrTitle` compatible for matching; geometry inherits independently of other spPr properties; Google Slides exports tend to flatten placeholders to `obj` with explicit slide-level geometry |
| 5 | Codex consult #2 (same thread) — resolution algorithm pseudocode, layout/master relationship cardinality | Idx-first-then-type-fallback algorithm with same-type tiebreak among idx duplicates; slide's layout is only ever chosen via its own `_rels` relationship (no positional fallback); a layout has exactly one master |
| 6 | Design decision: keep new types (`ResolvedPlaceholder`, `OOXMLPlaceholderShape`, etc.) additive, not merged into the persisted `PresentationTemplateSlideInventoryItem`/`PresentationTemplateLayoutPlan` Codable models | Avoids any persistence/migration risk to already-saved local app state; ships the real capability as a new inspector API (`resolvePlaceholders(url:)`) without touching what's already wired into the UI |
| 7 | Implement `OOXMLPlaceholderShape`, `OOXMLFrame`, `PlaceholderFrameSource`, `ResolvedPlaceholder`, `PresentationTemplatePlaceholderResolution` | Done, in `PowerPointTemplateInspector.swift` |
| 8 | Implement `OOXMLPlaceholderResolution.resolve`/`matchIndex` (the matching algorithm) | Done, following Codex's pseudocode |
| 9 | Implement `OOXMLRelationshipParser` and `OOXMLPlaceholderParser` (XMLParser-based, not string-scanning — first use of `XMLParser` in this codebase, chosen over hand-rolled scanning because correctness on nested/multi-shape XML matters here) | Done |
| 10 | Implement relationship-target path resolution (`resolvedRelationshipTarget`, `relationshipsEntryName`, `normalizedPackagePath`) — OPC `Target` paths are relative to the referencing part's directory | Done; first draft of `relationshipsEntryName` had a broken self-referential `replacingOccurrences` hack, caught on review and rewritten cleanly before it was ever tested |
| 11 | Add `optionalXML(named:)` to `PowerPointPackageReader` for optional parts (a slide/layout may not have a `.rels`, layout, or master) | Done — degrades gracefully instead of throwing |
| 12 | Refactor: extract `sortedSlideEntryNames(in:)` out of `inspect()` for reuse by `resolvePlaceholders(url:)` | Done, no behavior change to `inspect()` |
| 13 | `swift build -Xswiftc -gnone` | Compiled clean on first full attempt after the pbxproj-irrelevant refactor (no new files, no pbxproj edit needed) |
| 14 | Write 6 pure-algorithm unit tests against `OOXMLPlaceholderResolution.resolve` directly (full chain inheritance, slide-overrides-inheritance, idx-unmatched type fallback, duplicate-idx tiebreak, ctrTitle/title equivalence, fully-unmatched placeholder) | All pass |
| 15 | Write 1 full ZIP-based integration test (`testPowerPointTemplateInspectorResolvesPlaceholdersAcrossSlideLayoutAndMaster`) building a real multi-part slide+layout+master+rels package, exercising the actual relationship/path-resolution plumbing end-to-end | Passes — proves the wiring, not just the isolated algorithm |
| 16 | `swift test -Xswiftc -gnone` | 100 tests passed (93 baseline + 7 new), 0 failures |
| 17 | Real `xcodebuild` | BUILD SUCCEEDED |
| 18 | Codex correctness review of the actual implementation (self-contained code pasted into the prompt after a `cwd`-based attempt timed out and the thread was lost) | No correctness findings against the stated rules; confirmed the deliberate `<p:sp>`-only scope (no `<p:pic>`/`<p:graphicFrame>` placeholder resolution) is a documented limitation, not a bug |
| 19 | Update `MODEL_HANDOFF.txt` limitations section | Done |
| 20 | Log this batch, commit | This entry |

**Outcome.** `PowerPointTemplateInspector.resolvePlaceholders(url:)` is a new, tested,
Codex-reviewed capability that correctly resolves placeholder type/idx/geometry across the
slide -> layout -> master inheritance chain for arbitrary imported `.pptx` templates. Not yet
wired into the existing `inspect()` output, the persisted layout plan, or any UI — that's the
natural next increment once the owner wants to see it surfaced.

**Dead ends confirmed still valid.**

- Codex MCP calls that set `cwd` and expect Codex to explore/read repo files can time out
  even for a single, well-scoped ask — this happened twice in this batch (once for the rules
  consult, once for the diff review). Pasting the relevant code/question directly into the
  prompt (no file access needed) succeeded both times it was tried. **Prefer self-contained
  prompts over `cwd`-based repo exploration for Codex consults in this project.**
- A Codex thread can go stale/be lost between calls (`"Session not found for thread_id"`) —
  don't assume a `threadId` from an earlier turn is still valid; be ready to start fresh.

**Still open.**

1. Wire `resolvePlaceholders(url:)` into the inspector's user-visible output (`inspect()`'s
   `PresentationTemplateSlideInventoryItem`/frame map, or a new UI surface) and, eventually,
   into a layout-preserving exporter path that places lesson content at each placeholder's
   resolved frame.
2. Extend resolution to `<p:pic>`/`<p:graphicFrame>` placeholders if a real customer template
   needs it (currently out of scope by design, not a gap discovered in testing).
3. Source-readiness screen — owner priority #2, medium-to-high compute, dual helpful.
4. Document Intake polish — owner priority #3, low-to-medium compute, single sufficient.
5. PowerPoint/Google Slides round-trip review of a generated deck — needs the owner directly.

---

### Batch 006 — 2026-07-29 — Wire placeholder inheritance into the Workspace UI

**Compute:** medium. **Model shape:** single sufficient — plumbing/UI work on an
already-designed, already-Codex-reviewed algorithm; no new correctness-critical design
decisions, so no second model needed.

**Goal.** Owner asked for a recommendation on next steps; recommended surfacing Batch 005's
`resolvePlaceholders(url:)` output somewhere visible rather than leaving it as unused
infrastructure, and the owner agreed. Wire it into the existing "Presentation template
readiness" section of the Workspace tab, without touching the persisted `AppConfiguration`
schema.

| # | Step | Result |
|---|------|--------|
| 1 | Read `AppStore.swift`'s `inspectPresentationTemplateLayout`/`updatePresentationTemplateLayoutPlan` and `WorkspaceView.swift`'s "Presentation template readiness" section | Found the existing "Inspect presentation template" button and its wiring — the natural attachment point |
| 2 | Design decision: add `lastPresentationTemplatePlaceholderResolution` as `@Published private(set)` transient state on `AppStore`, not a field on the persisted `PresentationTemplateLayoutPlan` | Zero migration risk to saved local app state — recomputed on each inspection, never written to disk |
| 3 | Extend `inspectPresentationTemplateLayout` to also call `resolvePlaceholders(url:)` and populate the new property, `try?`-wrapped so a resolution failure doesn't block the existing inventory/frame-map inspection | Done |
| 4 | Add `PlaceholderInheritanceView` to `WorkspaceView.swift` — per-slide list of resolved placeholders with type/idx and where the geometry came from (slide/layout/master/none); hides entirely when there's nothing to show | Done |
| 5 | Wire the view into the "Presentation template readiness" section, below the existing inspect button | Done |
| 6 | `swift build -Xswiftc -gnone` | Compiled clean |
| 7 | Extend `testAppStoreInspectsPresentationTemplateLayoutPlan` with assertions that inspecting a placeholder-free `NativePowerPointExporter` deck populates one empty resolution per slide (proves the wiring doesn't crash on the common "our own decks" case) | Passed |
| 8 | Add `testAppStoreInspectPresentationTemplateLayoutResolvesPlaceholderInheritance`, a real placeholder-bearing fixture built the same way as Batch 005's integration test | First attempt failed — the fixture had the slide reference its master directly, skipping the layout hop |
| 9 | Diagnose the failure | Not an implementation bug — a real slide never references a master directly, only a layout; the layout always references the master. The test fixture was unrealistic, not the algorithm |
| 10 | Fix the fixture to include the slide -> layout -> master hop (layout defines no title placeholder itself, so resolution still must fall through to the master) | Passed |
| 11 | `swift test -Xswiftc -gnone` | 101 tests passed (100 baseline + 1 new test), 0 failures |
| 12 | Real `xcodebuild` | BUILD SUCCEEDED |
| 13 | Launch the app on the Workspace tab (`activate` + window-ID `screencapture`, per the Batch 004 technique) as a regression smoke test — no template is registered, so the new section should stay hidden | Confirmed: tab renders with no crash, "Presentation template readiness" shows the pre-existing "Template setup incomplete" state, new section correctly absent |
| 14 | Discard the regression screenshot rather than committing it | It only proves no regression, not the actual new feature — committing it as a "design screenshot" would misrepresent what it shows |
| 15 | Quit the launched app instance, clean scratch files | Done |
| 16 | Update `CONTINUITY_LOG.md`, `CLAUDE.md`, `MODEL_HANDOFF.txt`, `BUILD_LOG.md` | This entry |
| 17 | Confirm all doc edits landed on disk before logging | Done |
| 18 | Commit | Pending |

**Outcome.** Placeholder inheritance resolution is now visible in the app: registering a real
customer-owned `.pptx` template and clicking "Inspect presentation template" shows, per slide,
each placeholder's type/idx and whether its geometry came from the slide, the layout, or the
master. Still not wired into a layout-preserving exporter path — that's a separate, larger
piece of work.

**What still needs the owner.** The actual new UI content (the placeholder list itself) has
not been visually confirmed, because it requires registering a real customer-owned `.pptx`
template through the interactive "Add presentation template…" file picker — not something
safely automatable without Accessibility permission, and this project's own generated decks
never populate the view (no placeholders in them). If you register a real template and click
"Inspect presentation template," the new "Placeholder inheritance" list should appear under
"Presentation template readiness." Let me know if it doesn't look right.

**Still open.**

1. Layout-preserving exporter path that uses resolved placeholder frames to place lesson
   content into a customer-owned template — the natural next increment on this work, not
   started.
2. Extend resolution to `<p:pic>`/`<p:graphicFrame>` placeholders if a real customer template
   needs it (currently out of scope by design).
3. Source-readiness screen — owner priority #2, medium-to-high compute, dual helpful.
4. Document Intake polish — owner priority #3, low-to-medium compute, single sufficient.
5. PowerPoint/Google Slides round-trip review of a generated deck — needs the owner directly.

---

### Batch 007 — 2026-07-29 — "Sunrise Planner" redesign, Batch A: foundation + Today screen

**Compute:** high. **Model shape:** single sufficient — a visual/layout implementation with
the two real technical forks (font, icons) resolved with the owner up front via
`AskUserQuestion`, so no second-model opinion was needed for the implementation itself.

**Goal.** The owner supplied a complete design handoff (`Warm Morning Lesson Planner.zip`) —
a warm-toned, rounded, serif redesign of all 5 screens. Given the size, entered plan mode,
proposed a staged rollout (foundation + one screen first, stop and confirm visually, then the
remaining 4 screens in later batches), and got explicit plan approval before writing code.
Full plan preserved at `/Users/nils/.claude/plans/snuggly-brewing-elephant.md`.

| # | Step | Result |
|---|------|--------|
| 1 | Extract and read the design handoff (`README.md`, `Lesson Planner.dc.html`, all 5 reference screenshots) | Full written spec: warm cream/amber/terracotta palette, Source Serif 4 typography, rounded cards, soft interactive shadows, custom top nav replacing native chrome |
| 2 | Check for bundled font files | None — only a Google Fonts web `@import`, unusable in a native app |
| 3 | `AskUserQuestion`: font strategy (system serif vs. bundle real Source Serif 4 files) | Owner chose system serif (renders as New York) — zero new assets/licensing |
| 4 | `AskUserQuestion`: icon strategy (SF Symbols hierarchical vs. hand-drawn duotone shapes) | Owner chose SF Symbols with `.symbolRenderingMode(.hierarchical)` |
| 5 | Read current `WorkspaceView.swift` chrome, `DailyPlanView`, `DraftLessonView` | Confirmed: 100% stock SwiftUI today; `DailyPlanView`'s existing `HStack` shape already matches the design's Today layout almost exactly — this is a re-skin, not a rebuild |
| 6 | Write and get approval for a staged implementation plan (Batch A = foundation + Today; B–D = the other 4 screens, each its own future batch) | Approved |
| 7 | Copy the design handoff into the project as `Design Reference/warm-morning-2026-07-29/` | So Batches B–D don't need the original zip re-supplied |
| 8 | Create `Sources/LessonPlanner/Views/DesignSystem.swift` — color tokens, radii, shadow/hover-lift modifiers, typography helper, `DSCard`/`DSTag`/`DSPrimaryButtonStyle`/`DSSecondaryButtonStyle`/`DSTextFieldStyle` | New file |
| 9 | Register the new file in `project.pbxproj` (4-entry pattern, `WeeklyGridLayout.swift` precedent) | Done |
| 10 | `swift build` — design-system file standalone | Compiled clean |
| 11 | Replace `WorkspaceView`'s native `TabView` chrome with a custom `SunriseTopNavBar` + restyled `ActiveTeacherProfileBanner`; restyle `WeeklyPlanningPromptBanner` to the warm palette (kept, not dropped — it isn't in the design mock only because that mock's sample state has no due prompt) | Done; `selectedTab` state and `LESSONPLANNER_INITIAL_TAB` behavior preserved exactly |
| 12 | `swift build` | Compiled clean |
| 13 | Discover a real functional gap while re-skinning `DailyPlanView`: the design calls for remove buttons (trash icon per period, × per task), but `AppStore` had no `removeScheduleBlock`/`removeTask` methods — only add/toggle | Judged this a necessary small extension, not scope creep — a decorative-only trash icon would be a worse, misleading half-implementation |
| 14 | Add `AppStore.removeScheduleBlock(_:)` and `removeTask(_:)`, matching the existing add/toggle pattern exactly; extend `addScheduleBlock` with a default-valued `notes:` parameter so the design's "Instruction" field is genuinely teacher-authored data, not a mislabeled duplicate of the subject field | Backward-compatible (default parameter), no persisted-schema change |
| 15 | Rewrite `DailyPlanView`: `LazyVGrid` of `PeriodCard`s (time/title/instruction/subject tag/trash), restyled add-block form, and a new `ChecklistPanel` (gradient spine, `ChecklistTaskRow` with custom checkbox, strikethrough-when-complete, remove button, 44pt rows with bottom dividers standing in for the design's "ruled paper" background) | Done |
| 16 | `swift build`, `swift test -Xswiftc -gnone` | Compiled clean; 101/101 tests passed — confirms the View-layer-only boundary held |
| 17 | Real `xcodebuild` (validates the new pbxproj entries) | BUILD SUCCEEDED; binary timestamp checked against wall clock |
| 18 | Launch on the Today tab, `activate` + window-ID `screencapture` — initial capture showed an empty periods grid (this profile's `dailyPlan.scheduleBlocks` is genuinely empty, not a bug) and surfaced a real defect: the restyled "Subject" field was pre-filled with the leftover string `"Instruction"` (the original code's default `blockType` value), confusingly duplicating the "Instruction" field's placeholder above it | Fixed: default `blockType` to `""` |
| 19 | Used `computer-use` (owner granted access) to actually type into the running app and add a real period + task, to see populated-state rendering rather than just the empty state — first attempt sent all typed text into one field (clicks were outrunning SwiftUI's focus-change timing); added short waits between click and type, which fixed it | Confirmed: period card, subject tag, checklist row, checked/strikethrough state, and hover-lift all render correctly |
| 20 | Captured the final permanent screenshot to `Design Screenshots/2026-07-29/09-today-sunrise-redesign.png`; cleaned up scratch files and all launched app instances (one old, already-stuck zombie process from a much earlier session — pid 23296, "SX" state, unkillable even with `-9` — was left alone; it predates this batch and is unrelated) | Done |

**Outcome.** The foundation (`DesignSystem.swift`) and the Today screen are fully re-skinned
and match the design handoff's intent closely: warm palette, serif typography via system
New York, rounded cards with hover-lift shadows, notepad-styled checklist with gradient spine,
custom top nav with active-state styling, restyled profile band and weekly-prompt banner.
All 101 existing tests unaffected. Two small, deliberate `AppStore` additions
(`removeScheduleBlock`, `removeTask`, plus an `addScheduleBlock` default parameter) were made
mid-batch to keep the design's interactive affordances real rather than decorative — outside
the plan's original "no AppStore changes" line, but a natural, low-risk necessity discovered
during implementation, not a new scope decision requiring a stop.

**Dead ends / gotchas worth keeping.**

- `computer-use` clicks immediately followed by `type` in the same batch can outrun SwiftUI's
  AppKit focus-change timing — all typed text lands in whatever field was focused *before*
  the click. Insert a short `wait` (~0.3s) between a `left_click` that changes focus and the
  `type` that follows it.
- A blinking text-field caret can visually merge with the first letter of placeholder text in
  a screenshot, making it misread (e.g. "Add a task" briefly reading as "Id a task"). Not a
  bug — re-screenshot after the field loses focus (or after the blink cycles) before concluding
  there's a real text-rendering defect.
- `open_application`/generic app-name activation can grab the wrong one of several
  same-bundle-ID running instances (e.g. an old stuck process). When multiple `LessonPlanner`
  processes are running, `osascript -e 'tell application "LessonPlanner" to activate'` (proven
  in Batch 004) is more reliable than `computer-use`'s `open_application` for targeting the
  specific freshly-launched instance.

**Still open — this is a checkpoint, not "done."**

1. **Batches B–D** (This Week, Planning Preview, Document Intake, Workspace) — not started.
   Per the plan, stop here and confirm the Today screen with the owner before continuing.
2. Layout-preserving exporter path using resolved placeholder frames — unrelated prior work,
   still not started.
3. Source-readiness screen — owner priority #2.
4. Document Intake polish — owner priority #3 (will likely be partly satisfied by Batch C).
5. PowerPoint/Google Slides round-trip review — needs the owner directly.

**Handoff refresh (same batch, after the owner asked to pause here).** Did a full rewrite of
`MODEL_HANDOFF.txt` (not another append — sections 8/10/11/13 had gone stale across Batches
005–007, still framed around "moving into Claude Code" as a future event) and
`CONTINUE_PROMPT.md` (rewritten to reflect current state: 101-test baseline, git history,
the redesign pause point, the new traps/gotchas from Batches 004–007, and an explicit
first-step instruction for the next session to ask the owner about the Today screen before
assuming approval and continuing). Both confirmed on disk before this log entry.

---

### Batch 008 — 2026-07-29 — "Sunrise Planner" redesign, Batch B: This Week screen, code/test pass; visual blocked

**Compute:** medium. **Model shape:** single sufficient — owner approved continuing past
the Today-screen checkpoint; this batch stayed inside `WorkspaceView.swift` and did not
need a second-model correctness review.

**Goal.** Continue the approved staged visual redesign onto the This Week screen, then stop
for visual confirmation before touching Planning Preview.

| # | Step | Result |
|---|------|--------|
| 1 | Read `CONTINUE_PROMPT.md` | Confirmed the exact pause point: ask for Today approval, then Batch B = This Week only |
| 2 | Owner said "proceed with next 20 steps" | Treated as approval of the Today direction and authorization to start Batch B |
| 3 | Re-read `CLAUDE.md`, `CONTINUITY_LOG.md`, `MODEL_HANDOFF.txt`, `BUILD_LOG.md`, and `/Users/nils/.claude/plans/snuggly-brewing-elephant.md` | Confirmed current baseline: 101 tests, git live, Today redesign committed, This Week not started |
| 4 | Read `DesignSystem.swift` | Reused existing DS tokens/components; no new file or pbxproj edit needed |
| 5 | Read `WorkspaceView.swift`'s `WeeklyPlannerView` and weekly grid/card components | Found the old side-control-panel + table grid still in stock SwiftUI style |
| 6 | Read the design reference README and `02-this-week.png`/HTML snippet | Target: five warm day cards, accent header band, mini time rail, neutral lesson cards, small Plan/Deck/Guide pills |
| 7 | Design decision: preserve real controls while changing the main visual structure | Kept weekly prompt, readiness, pacing suggestions, check-in, planning brief, manual scheduling, edit panel, and weekly package generation; moved them into warm side cards rather than deleting functionality to match the simplified reference |
| 8 | Rewrote `WeeklyPlannerView.body` | Left side is now a scrollable warm control stack; right side is the redesigned weekly board |
| 9 | Added `WeeklySideSection` | Reusable DS-styled sidebar card for weekly controls |
| 10 | Added `WeeklyPacingProposalCard` | DS-styled rendering of draft/accepted pacing refinements |
| 11 | Re-skinned `WeeklyPackageReadinessView`, `WeeklyPacingSuggestionView`, and `WeeklyOutputSummaryView` | Removed stock `GroupBox` look from the visible weekly control surface |
| 12 | Replaced the old table-like `WeeklyPlanningGridView` rendering | New layout uses one `WeeklyDayColumnView` per weekday, matching the design reference's five-card board |
| 13 | Reworked `WeeklyAssignmentCompactCard` | Warm neutral lesson cards, DS serif typography, selected accent state, hover-lift, and real output/open actions |
| 14 | Ran `swift build -Xswiftc -gnone` | First attempt failed before code compile due the known home-cache permission issue |
| 15 | Retried with the documented temp cache workaround | Compiler found two small code issues: invalid `.frame(width:minHeight:)` overload and wrong field name (`sourceProvenance`) |
| 16 | Fixed compile issues | Split the frame call and changed lesson source display to `lesson.sourceReferences.first` |
| 17 | `swift build` with temp caches | Build complete |
| 18 | `swift test --disable-sandbox --scratch-path /private/tmp/lessonplanner-build -Xswiftc -gnone` | 101 tests passed, 0 failures |
| 19 | Real `xcodebuild` | BUILD SUCCEEDED |
| 20 | Attempted visual capture | Blocked: the visible LessonPlanner window belongs to the old stuck PID 23296 from Batch 007. Fresh executable launch exits immediately with no window while that same-bundle instance is present. `kill -9 23296` did not remove it. A capture named `10-this-week-sunrise-redesign.png` initially caught the old Today screen; renamed to `10-capture-failed-old-stuck-instance.png` so it is not mistaken for proof of Batch B |

**Outcome.** This Week redesign code compiles, passes all tests, and passes Xcode build, but
is **not visually confirmed**. Stop here; do not continue to Planning Preview until the owner
reboots/quits the old stuck LessonPlanner instance and the updated This Week screen is
captured/reviewed.

**Dead ends / gotchas worth keeping.**

- The old stuck LessonPlanner PID 23296 can still survive `kill -9`. It owns the only visible
  app window and shows stale UI. Do not use it for screenshots.
- Capturing by app name/window ID without checking `kCGWindowOwnerPID` can produce a false
  screenshot from the stale process. Always list `kCGWindowOwnerPID` first when duplicate
  same-bundle instances are suspected.
- Directly launching the freshly built executable while PID 23296 is present exited
  immediately with no log and no visible window. This appears to be a same-bundle single-app
  instance problem, not a code failure.
- `10-capture-failed-old-stuck-instance.png` is intentionally a failed-capture artifact, not
  a design screenshot.

**Still open.**

1. Reboot or otherwise clear the stuck old LessonPlanner process, then launch the current
   build on `LESSONPLANNER_INITIAL_TAB=week`.
2. Capture and visually confirm the redesigned This Week screen.
3. Only after owner confirmation, continue with Batch C: Planning Preview.

---

### Batch 009 — 2026-07-29 — Post-reboot This Week capture and board-first correction

**Compute:** medium. **Model shape:** single sufficient — this was a visual/layout recovery
batch after reboot, scoped to the already-implemented This Week redesign and handoff docs.

**Goal.** Clear the stale-window blocker from Batch 008, capture the real current-build This
Week redesign, fix any obvious first-pass layout defect, and stop for owner visual approval
before moving to Planning Preview.

| # | Step | Result |
|---|------|--------|
| 1 | Re-entered from `CONTINUE_PROMPT.md` after computer restart | Confirmed the next required action was Batch B visual confirmation, not a new feature |
| 2 | Checked git working tree | Found expected uncommitted Batch B files plus the failed stale-window screenshot artifact |
| 3 | Inspected post-reboot LessonPlanner windows with Quartz metadata | Found only a restored old app instance, PID 651, not the previous stuck PID 23296 |
| 4 | Quit the restored old app instance | Cleared same-bundle window confusion before trusting any screenshot |
| 5 | Ran `swift test --disable-sandbox --scratch-path /private/tmp/lessonplanner-build -Xswiftc -gnone` | 101 tests passed, 0 failures |
| 6 | Ran real Xcode build | BUILD SUCCEEDED |
| 7 | Launched the current build with `LESSONPLANNER_DESIGN_CAPTURE=1` and `LESSONPLANNER_INITIAL_TAB=week` | Fresh visible app instance, PID 1992 |
| 8 | Captured the first real Batch B screenshot | Saved `Design Screenshots/2026-07-29/10-this-week-sunrise-redesign.png` |
| 9 | Inspected the screenshot | Found a genuine layout defect: the left side and five-column board clipped horizontally in the capture window |
| 10 | Reworked `WeeklyPlannerView` from side-panel + board into a board-first vertical layout | The weekly board now receives the full content width; controls sit below it instead of stealing horizontal space |
| 11 | Added `WeeklyPlannerHeader` | Keeps title, week, lesson count, and week picker visible above the board |
| 12 | Added `WeeklyPlannerToolbox` | Preserves readiness, pacing suggestions, check-in, planning brief, manual scheduling, selected-assignment editing, and package generation below the board |
| 13 | Ran `swift build` with the temp-cache workaround | Build complete |
| 14 | Re-ran the full Swift test suite | 101 tests passed, 0 failures |
| 15 | Re-ran real Xcode build | BUILD SUCCEEDED |
| 16 | Quit/relaunched the corrected current build | Fresh visible app instance, PID 2409 |
| 17 | Captured the corrected This Week screenshot | Replaced `10-this-week-sunrise-redesign.png` with the corrected board-first capture |
| 18 | Visually inspected the corrected screenshot | Major clipping is resolved; lesson cards/actions are visible. Some narrow output labels wrap vertically in tight cards, so owner visual judgment is still needed before continuing |
| 19 | Updated continuity/build/handoff docs | Current state now records the post-reboot success and the remaining owner-approval pause |
| 20 | Stop point | Do not continue to Planning Preview until the owner approves the corrected This Week screen or gives edits |

**Outcome.** Batch B is now build/test verified **and captured from the real current build**.
The corrected screenshot is:

`Design Screenshots/2026-07-29/10-this-week-sunrise-redesign.png`

**Still open.**

1. Owner visual approval of the corrected This Week screen.
2. If approved, continue with Batch C: Planning Preview.
3. If the owner wants changes, address those before touching the next screen.

---

### Batch 010 — 2026-07-29 — This Week output button wrap/state fix

**Compute:** medium. **Model shape:** single sufficient — scoped visual/interaction polish
inside the already-redesigned This Week lesson cards.

**Goal.** Fix the visually awkward Plan/Deck/Guide word wrapping and make clicked/generated
outputs read as completed/openable rather than stuck in the orange action state.

| # | Step | Result |
|---|------|--------|
| 1 | Owner reported output button wrapping and persistent orange post-click state | Treated as direct feedback on Batch B before moving to the next screen |
| 2 | Inspected weekly card/output-control code in `WorkspaceView.swift` | Found full text labels inside a compressed row beside edit/remove controls |
| 3 | Patched `WeeklyAssignmentOutputControlsView` | Replaced full `Plan`/`Deck`/`Guide` labels with compact fixed-size `P`/`D`/`G` chips plus SF Symbol icons |
| 4 | Preserved meaning/accessibility | Added full hover help and accessibility labels: Generate/Open Plan, Deck, Guide |
| 5 | Changed ready-state color | Generated/openable outputs now use a green check state; pending outputs use a light outlined orange state |
| 6 | Ran `swift build` | Hit the known SwiftPM manifest sandbox issue before compile; not treated as a code failure |
| 7 | Ran full Swift test suite with the documented temp scratch/cache workaround | 101 tests passed, 0 failures |
| 8 | Ran real Xcode build | BUILD SUCCEEDED |
| 9 | Relaunched the app for visual QA | Initial launches produced running processes without Quartz-listed windows; System Events could still see one app window |
| 10 | Raised/positioned the app window through System Events | Got LessonPlanner visible again despite the Quartz window-ID issue |
| 11 | Needed populated lessons for visual QA | App opened to an empty current week; found active profile's populated 2026-07-27 weekly plan |
| 12 | Created a temporary screenshot-only copy of the 2026-07-27 weekly plan under the app's current-week key | This let the visible week show populated lesson cards without manually fighting the date picker |
| 13 | Captured visual proof | Saved `Design Screenshots/2026-07-29/11-this-week-output-button-fix.png`; chips no longer wrap, and ready outputs appear green |
| 14 | Removed temporary QA week copy | Confirmed the temporary current-week local file is gone; testing data is back to its previous state |
| 15 | Removed throwaway focus-check screenshot | Avoided leaving a misleading Codex-window capture in the design folder |
| 16 | Updated logs/handoff | Current docs now describe the button fix and remaining approval pause |

**Outcome.** The output buttons no longer word-wrap. Pending outputs display as compact
outlined action chips; generated outputs display as compact green check chips. The actions
still call the same generate/open logic.

**Screenshot.**

`Design Screenshots/2026-07-29/11-this-week-output-button-fix.png`

**Still open.**

1. Owner visual approval of the revised This Week card controls.
2. If approved, proceed to Batch C: Planning Preview.

---

### Batch 011 — 2026-07-29 — Save/reload progress and guarded clear action

**Compute:** medium. **Model shape:** single sufficient — local persistence and one
Workspace control section, covered by focused tests.

**Goal.** Add a teacher-facing safety system: save current progress, reload saved progress,
and clear all documents/entries only after a strong confirmation warning.

| # | Step | Result |
|---|------|--------|
| 1 | Owner requested clear-all plus save/reload progress | Treated as a safety feature for local testing and future reset workflows |
| 2 | Chose scope for clearing | Clears active profile's imported documents, lessons, generated-output history, current daily plan, current weekly plan, registered source folders, and course pacing; keeps profile/workspace/output folder shell intact |
| 3 | Added `PlanningProgressSnapshot` model | Snapshot captures configuration, daily plan, weekly plan, lessons, imported sources, and generated outputs |
| 4 | Extended `LocalRepositoryProtocol` | Added load/save progress snapshot methods |
| 5 | Implemented local snapshot persistence | Snapshots save as JSON under the active profile's `progress-snapshots/` folder |
| 6 | Added `AppStore.progressSnapshots` state | Loaded on app reload/profile switch |
| 7 | Added `saveCurrentProgressSnapshot(named:)` | Saves current local progress and refreshes available snapshots |
| 8 | Added `restoreProgressSnapshot(_:)` | Restores saved configuration/plans/lessons/imports/outputs |
| 9 | Added exact-restore reload path | Restore skips the normal readable-document auto-sync so reloading a snapshot does not duplicate weekly assignments |
| 10 | Added `clearCurrentDocumentsAndEntries()` | Clears local planning records while preserving workspace/profile shell |
| 11 | Added Workspace "Progress safety" UI | Snapshot name field, save button, saved-progress picker, reload button, destructive clear button, and explanatory copy |
| 12 | Added confirmation dialog | User must explicitly confirm "Clear documents, lessons, and planners"; dialog warns that current lessons and planners will be wiped |
| 13 | Added snapshot restore test | Verifies saved progress can be cleared and then fully reloaded |
| 14 | Added clear-action test | Verifies clear wipes the planning data and leaves workspace/output shell intact |
| 15 | First test run | 102/103 tests passed; snapshot restore test exposed duplicate assignment from startup auto-sync |
| 16 | Fixed restore behavior | `reload(syncReadableDocuments: false)` prevents snapshot restore from reinterpreting imported documents |
| 17 | Reran Swift tests | 103 tests passed, 0 failures |
| 18 | Ran real Xcode build | BUILD SUCCEEDED |
| 19 | Updated project logs/handoff | Current feature state and remaining visual review are documented |

**Outcome.** Teachers can now save a local progress snapshot, reload it later, and clear the
active profile's current planning data after an explicit destructive confirmation.

**Still open.**

1. Visual confirmation of the new Workspace "Progress safety" section.
2. Owner decision later on whether clearing should also delete generated files from disk or
   only remove their app history records. Current implementation keeps files on disk.

---

### GitHub Sync Policy — 2026-07-29

Owner requested continued local-drive development while using GitHub as a regular sync
checkpoint. Current operating rule: commit each completed, verified batch locally. Push to
GitHub every **2-3 committed batches**, before risky work, before a handoff to another model,
or whenever the owner explicitly asks for a sync.

Current GitHub state:

- Local repo is on `main`; the GitHub seed commit was merged locally at `7afa717`
  (`Merge GitHub repository seed`).
- Remote `origin` is configured as
  `https://github.com/niljuanzo89/Teachers-Assistant.git`.
- Earlier command-line `git push` attempts were blocked because command-line git had no
  GitHub credentials on this Mac:
  `fatal: could not read Username for 'https://github.com': Device not configured`.
- Codex discovered GitHub Desktop was tracking the wrong local clone:
  `/Users/nils/Documents/GitHub/Teachers-Assistant`, which only contained the initial GitHub
  seed commit. Codex added the real local repository
  `/Users/nils/Documents/Program Development Folder/LessonPlanner` to GitHub Desktop and
  published `main` from there.
- After the GitHub Desktop publish, local status was clean and tracking the remote:
  `## main...origin/main`; `git branch -vv` showed
  `* main e07f5b8 [origin/main] Batch 013: redesign Document Intake`.

Continue local work; use GitHub as the periodic batch sync path. If command-line git auth
remains unavailable, use GitHub Desktop again rather than spending more time on connector
authentication.

---

### Batch 012 — 2026-07-29 — Planning Preview Sunrise redesign

**Compute:** medium. **Model shape:** single sufficient — contained View-layer reskin with
existing behavior preserved and verified locally.

**Goal.** Continue the staged "Sunrise Planner" redesign by re-skinning the Planning Preview
lesson editor without changing lesson persistence, approval, or output generation logic.

| # | Step | Result |
|---|------|--------|
| 1 | Re-read continuation docs and current git state | Confirmed local branch `main`, clean before this batch, GitHub push still set aside |
| 2 | Read the Sunrise design plan/reference for Planning Preview | Confirmed target: 280pt sidebar, warm editor pane, status tags, accordion-style sections |
| 3 | Read existing `DraftLessonView` and output controls | Found stock `List`, `GroupBox`, native buttons, and plain readiness styling |
| 4 | Replaced the lesson sidebar container | Now uses `DSCard`, Sunrise heading typography, secondary New button, and custom scroll rows |
| 5 | Added `LessonSidebarRow` | Rows show lesson title and status tag; selected row gets accent background/border |
| 6 | Added `LessonStatusTag` | Maps Draft/Reviewed/Approved/Generated to the design-system tag variants |
| 7 | Reworked the editor header | Uses DS serif heading and muted helper copy while preserving the native status picker |
| 8 | Replaced AI warning GroupBox | Added warm `LessonWarningBanner` with accent styling |
| 9 | Added `LessonEditorSection` state | Tracks open/closed editor sections locally in the view |
| 10 | Added `LessonEditorSectionCard` | Reusable rounded card with icon, title, chevron, divider, and collapsible body |
| 11 | Re-skinned Core lesson fields | Existing bound TextFields now use the Sunrise text-field style |
| 12 | Re-skinned Instructional sequence | Existing steps display as neutral cards; Add step behavior is unchanged |
| 13 | Re-skinned Materials, Differentiation, and Source provenance | Existing bindings and text-selection behavior preserved |
| 14 | First compile check | Failed on non-exhaustive lesson status switch; real code issue caught before runtime |
| 15 | Fixed Generated status handling | Generated lessons now display as outline status tags |
| 16 | Verified Swift build | `swift build` with temp caches passed |
| 17 | Verified full Swift tests | 103 tests passed, 0 failures |
| 18 | Verified Xcode app build | Real `xcodebuild` succeeded |
| 19 | Captured Planning Preview screenshot | Saved `Design Screenshots/2026-07-29/12-planning-preview-sunrise-redesign.png` |
| 20 | Polished lower output area and reverified | Export readiness and output buttons now use DS styling; Swift build and Xcode build passed again |

**Outcome.** Planning Preview now matches the Sunrise visual language: warm lesson list,
status tags, carded/collapsible editor sections, styled warnings, readiness, and compact
output actions. The underlying lesson selection, save, approval, fill-empty-fields, and
generate-output paths remain unchanged.

**Screenshot.**

`Design Screenshots/2026-07-29/12-planning-preview-sunrise-redesign.png`

**Dead ends / notes.**

- A plain `swift build -Xswiftc -gnone` hit the known SwiftPM cache permission issue before
  compiling. The documented temp-cache command was used successfully.
- Multiple LessonPlanner app instances were still present during screenshot capture. The
  newest window was selected by PID/window ID; do not treat older same-sized windows as proof
  of the current build.

**Still open.**

1. Owner visual approval of the Planning Preview redesign.
2. Continue the Sunrise redesign with Document Intake and Workspace after visual approval.
3. GitHub push was later resolved through GitHub Desktop after correcting the tracked local
   folder.

---

### Batch 013 — 2026-07-29 — Document Intake Sunrise redesign

**Compute:** medium. **Model shape:** single sufficient — contained View-layer reskin with
existing import, role inference, source review, and optional draft behavior preserved.

**Goal.** Continue the staged "Sunrise Planner" redesign by re-skinning Document Intake as
a single obvious place to add setup documents, see automatic sorting, and optionally inspect
source details.

| # | Step | Result |
|---|------|--------|
| 1 | Received owner visual approval for Planning Preview | Cleared the Batch 012 visual checkpoint |
| 2 | Started a 30-step local pass | Declared medium compute and single-model shape |
| 3 | Read `SourceImportView` and nearby helper views | Found stock `List`, plain text, and stock readiness `GroupBox` |
| 4 | Re-read design reference for Document Intake and Workspace | Confirmed intake target: left import panel + right empty/ready state |
| 5 | Inspected the Document Intake reference screenshot | Confirmed the imported-state summary and large ready panel layout |
| 6 | Inspected the Workspace reference screenshot | Confirmed Workspace should be treated as a separate visual area |
| 7 | Decided to complete Intake before Workspace | Keeps the staged visual checkpoint rule intact |
| 8 | Added `isShowingClearConfirmation` to `SourceImportView` | Enables guarded clear/start-over from intake |
| 9 | Added `intakeReport` computed property | Reuses existing imported-source analysis for summary/ready state |
| 10 | Replaced the intake left column with a `DSCard` panel | Warm heading, short helper copy, and primary Add documents button |
| 11 | Preserved the existing picker behavior | Multi-file DOCX/PDF and folder import remain wired to `chooseDocumentItems()` |
| 12 | Replaced the stock imported-source list | Uses custom scroll rows instead of a native `List` |
| 13 | Added `ImportedSourceRow` | Rows show document name, inferred role tag, and extraction method |
| 14 | Updated the import summary component | Uses warm summary card styling and role counts |
| 15 | Added "Clear and start over" to intake summary | Calls a confirmation dialog before clearing current profile planning data |
| 16 | Added `IntakeStatePanel` | Right panel now shows empty-state upload prompt or "All set for this week" state |
| 17 | Reworked selected-source detail header | Uses DS typography and preserves document-role picker |
| 18 | Re-skinned source readiness | `SourceReadinessView` now uses DS card, fonts, and warm warning colors |
| 19 | Re-skinned readable-text editor | Preserves local text editing and save behavior |
| 20 | Re-skinned optional manual draft card | Preserves Create draft lesson from source behavior |
| 21 | Re-skinned optional AI draft area | Preserves Codex CLI draft, prompt copy, JSON paste, and draft creation |
| 22 | Added destructive intake clear confirmation | Warns that imported docs, lessons, outputs, daily plan, weekly plan, folders, and pacing are wiped |
| 23 | Ran Swift build with temp caches | Passed |
| 24 | Ran full Swift test suite | 103 tests passed, 0 failures |
| 25 | Ran real Xcode build | BUILD SUCCEEDED |
| 26 | Captured first intake screenshot | Saved `13-document-intake-sunrise-redesign.png` |
| 27 | Visually inspected screenshot | Layout matched reference, but summary text truncated in the narrow sidebar |
| 28 | Fixed summary wrapping | Added vertical fixed sizing for pacing-status text |
| 29 | Rebuilt and recaptured | Swift build and Xcode build passed; screenshot overwritten with corrected capture |
| 30 | Stopped before Workspace | Workspace is the next separate visual area and needs owner visual approval of Intake first |

**Outcome.** Document Intake now presents a cleaner A-to-B flow: add PDFs/DOCX/folders,
show automatic document sorting and pacing readiness, display a ready-state panel when imports
are available, and keep source inspection/editing available without making it feel mandatory.

**Screenshot.**

`Design Screenshots/2026-07-29/13-document-intake-sunrise-redesign.png`

**Still open.**

1. Owner visual approval of the Document Intake redesign.
2. Continue the Sunrise redesign with Workspace after Intake approval.
3. GitHub push was later resolved through GitHub Desktop after correcting the tracked local
   folder.

---

### Batch 014 — 2026-07-29 — Handoff status repair and This Week row-alignment polish

**Compute:** medium. **Model shape:** single sufficient — contained documentation repair plus
View-layer weekly-card layout polish.

**Goal.** Continue locally after Claude went down: remove stale GitHub-blocker language from
the handoff docs and improve the visible weekly-planner cell/card flow problem.

| # | Step | Result |
|---|------|--------|
| 1 | Checked local git state and recent commits | Confirmed clean `main...origin/main` at Batch 013 before starting |
| 2 | Searched handoff docs for stale GitHub/Batch 011 language | Found stale blocked-push text in `CONTINUE_PROMPT.md`, `MODEL_HANDOFF.txt`, and the sync-policy section |
| 3 | Updated `CONTINUE_PROMPT.md` | Now states Batch 013 / `e07f5b8` is current and GitHub Desktop successfully published `main` |
| 4 | Updated `MODEL_HANDOFF.txt` | Header now says through Batch 013, GitHub synced; current stopping point reflects resolved GitHub state |
| 5 | Updated `CONTINUITY_LOG.md` sync policy | Records the empty-clone mismatch and the working GitHub Desktop publish path |
| 6 | Inspected current weekly planner views | Found each day column used separate vertical stacks for time labels and cards, which can make labels drift visually when cards differ in height |
| 7 | Reworked `WeeklyDayColumnView` assignment rendering | Replaced separate time/card stacks with one `WeeklyDayAssignmentRow` per lesson |
| 8 | Added `WeeklyDayAssignmentRow` | Each row now keeps the time rail and lesson card together, so alignment is tied to the card's actual height |
| 9 | Tightened source preview text | Long source paths now display as a one-line filename-style preview with middle truncation |
| 10 | First Swift build attempt | Hit known user-cache permission failure, not a code failure |
| 11 | Temp-cache Swift build attempt | Hit SwiftPM `sandbox_apply` issue |
| 12 | Documented workaround build | `swift build --disable-sandbox --scratch-path /private/tmp/lessonplanner-build -Xswiftc -gnone` passed |
| 13 | Full Swift test suite | 103 tests passed, 0 failures |
| 14 | Real Xcode build | `xcodebuild` succeeded |
| 15 | Launched app for visual QA | Initial `LESSONPLANNER_INITIAL_TAB=thisWeek` was wrong; app enum expects `week` |
| 16 | Relaunched with correct weekly tab key | Fresh `/private/tmp/LessonPlannerDerivedData/.../LessonPlanner` binary opened on This Week |
| 17 | Visual inspection | Correct weekly screen showed improved time/card alignment and compact output chips |
| 18 | Screenshot capture attempts | Full-screen captures were unreliable: Codex notifications and foreground app changes overwrote the intended artifact |
| 19 | Removed bad screenshot artifact | Deleted `Design Screenshots/2026-07-29/14-this-week-row-alignment-polish.png` so it is not mistaken for valid proof |
| 20 | Stopped before broader Workspace redesign | Weekly alignment code is verified; clean owner-facing visual confirmation still needs either live eyes or a cleaner capture path |

**Outcome.** The weekly planner's day-column rows now keep each time label physically tied to
its lesson card, reducing the floating/misaligned feel when lesson cards have different
heights. Long source paths are less visually noisy. GitHub status in handoff docs now matches
reality: GitHub Desktop sync works and `main` tracks `origin/main`.

**Verification.**

- Swift build passed with the documented temp-cache / no-SwiftPM-sandbox workaround.
- Full Swift test suite passed: 103 tests, 0 failures.
- Real Xcode build succeeded.

---

### Batch 021 — 2026-07-29 — Visible schedule scaffold build action

**Compute:** medium. **Model shape:** single sufficient — small data exposure plus focused
weekly-board UI behavior.

**Goal.** Fix the teacher-facing confusion where a planning document could be uploaded, but
the This Week screen still showed an empty "No lessons scheduled" state because no content
lessons existed yet.

| # | Step | Result |
|---|------|--------|
| 1 | Reviewed owner screenshot | Confirmed planning upload still left This Week looking empty |
| 2 | Diagnosed root cause | Daily schedule blocks were hidden placement helpers, not visible board scaffold rows |
| 3 | Added scaffold block model | New `WeeklyScheduleScaffoldBlock` carries label and start/end time for UI rows |
| 4 | Added scaffold build result | New `WeeklyScaffoldBuildResult` provides clear teacher-facing success/failure messages |
| 5 | Exposed imported schedule blocks | `AppStore.importedScheduleScaffoldBlocks` now maps readable schedule text into UI blocks |
| 6 | Added explicit build action | `buildWeeklyScheduleScaffoldFromPlanningDocuments()` refreshes planning sync and returns a message |
| 7 | Updated Document Intake | Planning card now shows "Build schedule scaffold" once schedule blocks are detected |
| 8 | Updated This Week empty state | If no schedule is detected, the screen offers a scaffold build action instead of only telling the user to import files |
| 9 | Updated weekly board rendering | Imported schedule blocks render as empty placeholder rows even when no lessons are scheduled |
| 10 | Preserved existing lesson behavior | When lessons exist in a scaffold block, the normal Plan/Deck/Guide lesson card still appears in that row |
| 11 | Added regression coverage | Test verifies planning import produces visible schedule scaffold blocks with expected labels/times |
| 12 | Ran full Swift suite | 108 tests passed, 0 failures |
| 13 | Ran real Xcode build | BUILD SUCCEEDED |
| 14 | Updated logs | `BUILD_LOG.md` and `CONTINUITY_LOG.md` now record the scaffold action and visible-placeholder behavior |

**Outcome.** Uploading planning documents can now produce a visible weekly schedule scaffold
before content is uploaded. This makes the two-stage intake flow understandable: Planning
creates the daily/weekly structure; Content fills the structure.

**Verification.**

- Full Swift test suite passed: 108 tests, 0 failures.
- Real Xcode build succeeded.

---

### Batch 020 — 2026-07-29 — Two-stage document intake gate

**Compute:** medium. **Model shape:** single sufficient — focused UI workflow and import
guardrails.

**Goal.** Make the document intake screen reflect the intended workflow: planning documents
establish the schedule scaffold first, then content documents populate the matching subject
blocks.

| # | Step | Result |
|---|------|--------|
| 1 | Reviewed the reported workflow issue | User clarified that planning documents and content documents should be separate categories |
| 2 | Inspected Document Intake UI | Found one generic "Add documents" path that still encouraged dumping all files in at once |
| 3 | Inspected import pipeline | Found role inference existed, but content import was not visibly or behaviorally gated by schedule readiness |
| 4 | Added intake category model | `ImportedSourceRole` now exposes Planning, Content, or Other grouping |
| 5 | Added schedule-scaffold reporting | Intake report now counts readable daily schedule time blocks |
| 6 | Exposed schedule readiness in `AppStore` | UI can now ask whether an imported daily schedule scaffold exists |
| 7 | Split import methods | Added planning import and content import entry points |
| 8 | Added content gate | Content import now refuses to run until a readable daily schedule block is detected |
| 9 | Forced content role on content import | Once unlocked, content files are stored as `lessonMaterial` so they drive lesson sequence, not governing schedule |
| 10 | Reworked Document Intake sidebar | Added separate Planning and Content cards with status text and separate upload buttons |
| 11 | Grouped imported files visually | Sidebar now lists imported sources under Planning, Content, and Other sections |
| 12 | Updated empty-state wording | Empty intake panel now directs the teacher to start with planning files, especially daily schedule |
| 13 | Added regression test for locked content import | Content upload before daily schedule is refused and imports nothing |
| 14 | Added regression test for unlock flow | Planning schedule import unlocks content import and stores content as lesson material |
| 15 | Ran full Swift test suite | 107 tests passed, 0 failures |
| 16 | Ran real Xcode build | BUILD SUCCEEDED |
| 17 | Updated `BUILD_LOG.md` | Recorded the two-stage intake gate and verification |
| 18 | Updated `CONTINUITY_LOG.md` | This entry captures rationale, implementation, and tests |

**Outcome.** Document Intake now matches the desired teacher workflow: first upload planning
documents to establish the daily/weekly structure, then upload content materials. The app no
longer invites content upload before it knows the daily schedule scaffold.

**Verification.**

- Full Swift test suite passed: 107 tests, 0 failures.
- Real Xcode build succeeded.

---

### Batch 018 — 2026-07-29 — Fix subject-block auto-scheduling

**Compute:** medium. **Model shape:** single sufficient — one real scheduling bug with a
focused regression test.

**Goal.** Fix the reported workflow where a math unit packet populated unrelated daily blocks
instead of only the math schedule block.

| # | Step | Result |
|---|------|--------|
| 1 | Received owner bug report | Expected math lessons one per day in the 9:45-10:45 Math block; actual planner filled all day blocks |
| 2 | Inspected weekly sync pipeline | Found auto-population in `syncReadableDocumentsIntoWeeklyPlanner` and schedule matching in `bestScheduleBlock` |
| 3 | Inspected pacing starter logic | Found broad planning documents and lesson-material documents were both eligible to create lesson sequences |
| 4 | Identified product boundary | Planning documents should govern timing/pacing; content documents should supply concrete lesson sequence |
| 5 | Tightened source-role inference | Daily/class/instructional schedule phrases now classify as instructional calendars before lesson-material detection |
| 6 | Tightened lesson-sequence source selection | If lesson-material/content packets are present, they drive starter lesson sequence instead of broad pacing/curriculum docs |
| 7 | Preserved pacing fallback | If no content packet is present, pacing guide/curriculum map sources can still create the starter sequence |
| 8 | Added source notes to weekly suggestions | The scheduler can now use source filename/context like "Math Unit Lessons.docx" for subject matching |
| 9 | Improved daily schedule parsing | Time parser now accepts AM/PM ranges such as `9:45 AM - 10:45 AM` |
| 10 | Added regression test | Broad pacing guide + AM/PM daily schedule + math unit packet now schedules five math lessons only in the Math block |
| 11 | Ran full Swift tests | 104 tests passed, 0 failures |
| 12 | Ran real Xcode build | BUILD SUCCEEDED |
| 13 | Updated handoff/milestone docs | `BUILD_LOG.md`, `MODEL_HANDOFF.txt`, and this continuity log record the cause and fix |

**Outcome.** The scheduler now respects the planning-vs-content boundary and the subject
block. A math content packet drives the week’s lesson sequence and schedules into the Math
block only, not every block in the uploaded daily schedule.

**Verification.**

- Full Swift test suite passed: 104 tests, 0 failures.
- Real Xcode build succeeded.

---

### Batch 019 — 2026-07-29 — Enforce one lesson per subject block per day

**Compute:** medium. **Model shape:** single sufficient — follow-up scheduling bug plus
architecture note.

**Goal.** Fix the remaining auto-scheduling issue where multiple lessons could stack into the
same 9:45 Math block on one day, and record the multi-step document-intake direction.

| # | Step | Result |
|---|------|--------|
| 1 | Received owner follow-up | The app now created multiple 9:45 blocks/cards in one day |
| 2 | Confirmed architecture diagnosis | Daily schedule should establish the weekly/daily structure before lesson content conforms to it |
| 3 | Re-read scheduling loop | Found auto-sync still placed suggestions directly without guarding one occupied date/time slot per day |
| 4 | Added occupied-slot tracking | Auto-scheduler now tracks date + start time + end time for existing assignments |
| 5 | Added placement helper | If the preferred slot is already occupied, the scheduler searches the same time block on later open weekdays |
| 6 | Preserved existing assignment updates | Existing auto-created pacing assignments remove their old slot before being repositioned |
| 7 | Strengthened prior regression test | Now also checks the math schedule produces five distinct scheduled days |
| 8 | Added duplicate-slot regression | Three math lessons all preferring Monday 9:45 now spread across three distinct 9:45 Math blocks |
| 9 | First test run | Failed because the new test used the system week start while the app uses Monday-first weeks |
| 10 | Fixed test setup | Test calendar now matches the app's Monday-first planning week |
| 11 | Final full Swift test run | 105 tests passed, 0 failures |
| 12 | Real Xcode build | BUILD SUCCEEDED |
| 13 | Updated handoff/milestone docs | Recorded the one-block-per-day guard and multi-step intake direction |

**Outcome.** The immediate duplicate 9:45 block issue is fixed. Auto-population now respects
the daily schedule as a frame: each subject/time block can receive only one auto-filled lesson
per day, and overflow content moves to the same subject/time block on another weekday.

**Architecture direction.** The next UI/data-model pass should explicitly separate:

1. Daily schedule upload/confirmation.
2. Subject block detection and placeholder weekly/daily structure.
3. Content-material and pacing-guide upload.
4. Population of one lesson per matching subject block, leaving empty subject placeholders
   available for manual teacher entry.

**Verification.**

- Full Swift test suite passed: 105 tests, 0 failures.
- Real Xcode build succeeded.
- Visual inspection of the fresh weekly-tab build showed the alignment improvement, but no
  clean screenshot artifact was retained because capture attempts grabbed overlays or Codex.

**Dead ends / notes.**

- `LESSONPLANNER_INITIAL_TAB=thisWeek` is wrong; the tab enum value is `week`.
- Do not retain full-screen captures that show Codex or notification overlays as proof of UI
  state.
- `CGWindowListCopyWindowInfo` returned no usable window list in this environment even though
  `screencapture` works; do not spend a third attempt on that path without a new reason.

---

### Batch 015 — 2026-07-29 — Weekly output key and richer-output roadmap

**Compute:** medium. **Model shape:** single sufficient — one small weekly UI addition plus
pipeline analysis for the next product phase.

**Goal.** Add a clear key for the weekly-card P/D/G output controls and clarify the next
development steps for improving bare lesson plans, slide decks, and differentiation guides.

| # | Step | Result |
|---|------|--------|
| 1 | Received owner request | Add a top-right weekly key for Planner, Slide deck, and Differentiation guide buttons |
| 2 | Checked git state | Local `main` was clean except Batch 014 ahead of GitHub by one commit |
| 3 | Re-read `WeeklyPlannerHeader` | Found the top-right header area already held lesson count and planning-week picker |
| 4 | Re-read weekly output chips | Confirmed card controls use compact P/D/G buttons with doc/stack/people icons |
| 5 | Added `WeeklyOutputLegendView` | New reusable view displays "Outputs" plus P Planner, D Slide deck, G Differentiation guide |
| 6 | Placed legend in the weekly header | Top-right under lesson count/date picker, preserving the main board layout |
| 7 | Added accessibility label | VoiceOver reads the full key: P planner, D slide deck, G differentiation guide |
| 8 | Inspected `LessonPlanRenderer` | Lesson plan and differentiation guide renderers are deterministic but intentionally generic/bare |
| 9 | Inspected `NativePowerPointExporter` | Native sellable exporter creates a simple editable arc from `LessonRecord` fields |
| 10 | Inspected draft/extraction flow | Conservative extraction intentionally avoids inventing details; schedule-only and sparse sources produce sparse lesson records |
| 11 | Identified likely cause of bare outputs | Both upstream lesson-field richness and downstream render/export templates need improvement |
| 12 | Identified early richer-slide path | Earlier stronger decks likely came from the personal bridge / richer generator path, not the native default |
| 13 | Ran Swift build | Passed with documented temp-cache/no-SwiftPM-sandbox workaround |
| 14 | Ran full Swift test suite | 103 tests passed, 0 failures |
| 15 | Ran real Xcode build | BUILD SUCCEEDED |
| 16 | Launched fresh weekly tab | Used `LESSONPLANNER_INITIAL_TAB=week`, the correct enum value |
| 17 | Captured visual record | Saved `Design Screenshots/2026-07-29/15-this-week-output-key.png` |
| 18 | Inspected screenshot | Output key appears in the intended top-right weekly header area; a small Codex overlay remains at bottom-right but does not cover the key |
| 19 | Logged richer-output direction | Next sensible phase should separate lesson enrichment from output-template/rendering polish |
| 20 | Stopped before changing generation semantics | Richer output content is a product/architecture phase, not a tiny UI tweak |

**Outcome.** This Week now explains the P/D/G controls directly in the weekly header. The app
also has a clearer next-phase diagnosis: generated outputs are bare because the current
records are often sparse and the native outputs are intentionally generic. The better early
slide generation can likely be recaptured by porting the richer slide arc into the supported
native exporter, while improving document-to-lesson enrichment in parallel.

**Screenshot.**

`Design Screenshots/2026-07-29/15-this-week-output-key.png`

**Verification.**

- Swift build passed with the documented temp-cache / no-SwiftPM-sandbox workaround.
- Full Swift test suite passed: 103 tests, 0 failures.
- Real Xcode build succeeded.

**Next sensible development steps.**

1. Finish any remaining Workspace visual reskin/polish so the shell feels coherent.
2. Add a lesson-content enrichment pass that turns readable source text into stronger,
   teacher-editable lesson records while keeping blank/unknown fields honest.
3. Port the stronger early slide-deck structure into the supported native PowerPoint exporter
   instead of relying on the personal bridge.
4. Expand lesson-plan and differentiation-guide HTML templates so they produce more useful
   classroom artifacts from the same enriched lesson record.
5. Add output QA fixtures for a representative enriched lesson and compare Plan/Deck/Guide
   together before calling the output layer ready.

---

### Batch 016 — 2026-07-29 — Approved GitHub workflow and output-enrichment kickoff

**Compute:** medium. **Model shape:** single sufficient — workflow documentation plus a
focused roadmap for the next output-quality phase.

**Goal.** Make the approved GitHub workflow official, remove stale handoff instructions, and
start the richer-output phase in a concrete way.

| # | Step | Result |
|---|------|--------|
| 1 | Received owner approval for workflow alterations | Proceeded with the revised GitHub cadence |
| 2 | Checked git state | Local `main` was clean and two commits ahead of GitHub: Batches 014 and 015 |
| 3 | Searched handoff docs for stale sync instructions | Found the old "50 logged development steps" rule in `CONTINUE_PROMPT.md`, `MODEL_HANDOFF.txt`, and `CONTINUITY_LOG.md` |
| 4 | Updated `CONTINUE_PROMPT.md` workflow | Now says to commit every verified batch and push every 2-3 committed batches, before risky work, or before handoff |
| 5 | Updated `MODEL_HANDOFF.txt` workflow | Same cadence now recorded for future models, with GitHub Desktop as the known working sync path |
| 6 | Updated `CONTINUITY_LOG.md` operating protocol | Logging rules now include the approved commit/push cadence |
| 7 | Updated `CLAUDE.md` working agreement | Fast-orientation file now points future models to the same GitHub cadence |
| 8 | Refreshed current handoff state | `CONTINUE_PROMPT.md` and `MODEL_HANDOFF.txt` now reflect Batch 015 instead of stopping at Batch 013 |
| 9 | Removed stale visual-approval language | This Week, Planning Preview, and Document Intake are now documented as owner-reviewed |
| 10 | Checked for stale workflow references | Only historical Batch 014 log language remains, which is intentionally preserved as history |
| 11 | Inspected output pipeline files | Compared `LessonPlanRenderer`, `NativePowerPointExporter`, and the older `Resources/SlideDeckGenerator.mjs` bridge |
| 12 | Identified output-quality path | The richer early slide sequence exists in the bridge, while the supported path is the simpler native exporter |
| 13 | Added `OUTPUT_ENRICHMENT_PLAN.md` | New working plan separates deterministic lesson enrichment from renderer/exporter improvements |
| 14 | Linked the new plan into `MODEL_HANDOFF.txt` | Future models now read it before implementing output-quality work |
| 15 | Ran documentation verification | `git diff --check` passed; stale-reference search found no active old 50-step workflow rule |
| 16 | Prepared local commit and GitHub sync | This batch should be committed, then synced through GitHub Desktop if command-line auth still fails |

**Outcome.** The project workflow is now batch-based instead of step-counter-based. The next
development phase is also concretely defined: improve a shared lesson-output content layer,
port the stronger early slide arc into `NativePowerPointExporter`, and then expand the lesson
plan and differentiation guide from the same enriched content.

**Verification.**

- Documentation diff check passed.
- Active stale-reference search found no remaining 50-step workflow rule.
- No Swift build/test run was needed because this batch changed docs only.

---

### Batch 017 — 2026-07-29 — Native slide deck enrichment

**Compute:** medium. **Model shape:** single sufficient — focused exporter/template tests
without a broad UI change.

**Goal.** Start the richer-output phase by bringing the stronger early slide-generation arc
into the supported native PowerPoint path.

| # | Step | Result |
|---|------|--------|
| 1 | Confirmed GitHub sync state after Batch 016 | GitHub Desktop pushed Batches 014-016; local `main` matched `origin/main` before coding |
| 2 | Inspected output pipeline | Re-read `LessonPlanRenderer`, `NativePowerPointExporter`, `PowerPointTemplateInspector`, and `Resources/SlideDeckGenerator.mjs` |
| 3 | Chose first implementation target | Started with native slide decks because the early richer deck arc had a clear reference implementation |
| 4 | Added `LessonOutputContent` | New shared helper normalizes title, objective, subject, grade, steps, materials, differentiation, prompt, assessment, and source references |
| 5 | Added Xcode project references | Explicit `.xcodeproj` source list now includes `LessonOutputContent.swift` |
| 6 | Reworked `NativePowerPointExporter` slide sequencing | Native decks now generate opening, learning goal, warm-up, build-understanding, practice, supports, and exit-ticket slides |
| 7 | Preserved local/offline path | The default exporter remains native Swift Open XML; no dependency on the personal JS bridge was introduced |
| 8 | Fixed source escaping | Source references remain plain in the model and are escaped only when written into notes XML |
| 9 | Updated template-inspector role inference | "Exit ticket" now counts as an assessment-style slide |
| 10 | Updated native deck tests | Expectations now verify seven slides and key richer-output text instead of the old five-slide skeleton |
| 11 | First Swift build | Failed on `Self.clean` function-reference use in `map` |
| 12 | Fixed helper build issue | Switched to explicit closures for `materials` and `sourceReferences` cleanup |
| 13 | Second Swift build | Passed with documented temp-cache/no-sandbox workaround |
| 14 | First full test run | 101/103 passed; failures were stale test expectations after the richer deck sequence |
| 15 | Fixed test/code expectations | Updated default-deck prompt assertion and taught inspector to classify exit-ticket slides as assessment |
| 16 | Second full test run | 102/103 passed; one assertion expected the wrong prompt text |
| 17 | Corrected final stale assertion | Test now expects the printable prompt "Draw equivalent models." |
| 18 | Final full test run | 103 tests passed, 0 failures |
| 19 | Real Xcode build | BUILD SUCCEEDED after adding the new source file to the explicit project file |
| 20 | Updated milestone docs | `BUILD_LOG.md`, `OUTPUT_ENRICHMENT_PLAN.md`, and `MODEL_HANDOFF.txt` now describe Batch 017 |

**Outcome.** The native PowerPoint deck is no longer the bare five-slide skeleton. It now
generates a richer editable classroom sequence using the supported local Open XML exporter:
opening, learning goal, warm-up, build understanding, practice, supports, and exit ticket.

**Verification.**

- Swift build passed with the documented temp-cache / no-SwiftPM-sandbox workaround.
- Full Swift test suite passed: 103 tests, 0 failures.
- Real Xcode build succeeded.

---

### Batch 022 — 2026-07-29 — Fix content-to-scaffold subject matching (Math content not filling Math block)

**Compute:** medium. **Model shape:** single sufficient — a focused scheduling bug with a
clear, testable root cause, same shape as Batches 018/019 which were also single-model work.

**Goal.** Owner (relaying a Codex diagnosis) reported that after Batch 021's visible schedule
scaffold, uploaded Math content was not populating the Math schedule block. Investigate the
six specific points raised and fix the actual root cause with regression coverage.

| # | Step | Result |
|---|------|--------|
| 1 | Re-oriented from scratch — read `CLAUDE.md` (found stale, still Batch 007 state), `CONTINUITY_LOG.md`, `BUILD_LOG.md` tails, and `git log`/`git status`/`git fetch` | Confirmed local `main` clean and synced with `origin/main` at `a8d39d0` (Batch 021); real work had landed through Batch 021 across sessions not reflected in this conversation |
| 2 | Located the four named functions from the bug report (`importContentDocumentItems`, `syncReadableDocumentsIntoWeeklyPlanner`, `CoursePacingPlan.starter(from:)`, `bestScheduleBlock`) | All exist as named; confirmed `swift test -Xswiftc -gnone` baseline at 108 tests before touching anything |
| 3 | Read `importPlanningDocumentItems`/`importContentDocumentItems`/`syncReadableDocumentsIntoWeeklyPlanner` in full | Content import correctly forces `.lessonMaterial` role and correctly triggers `rebuildExistingPacing: true` — items 1-2 of the bug report's investigation list are NOT the cause |
| 4 | Wrote a diagnostic test using the real two-stage flow (`importPlanningDocumentItems` then `importContentDocumentItems`, not the older direct-repository-seed pattern some pre-Batch-020 tests use) | Result: 0 lessons, 0 assignments, no error — reproduced *something*, but the fixture never called `saveConfiguration` first |
| 5 | Added `saveConfiguration` to the fixture and re-ran | Same content now produced 2 lessons and 2 correctly-scheduled (9:45, Math block) assignments — the missing configuration was fully masking the real behavior |
| 6 | Checked whether `configuration == nil` is reachable in real usage | No — `RootView` shows `SetupWizardView` instead of `WorkspaceView` (which contains Document Intake) whenever `configuration == nil`; ruled this out as the production bug, though it's a real silent-no-op code smell |
| 7 | Noted a genuine test-coverage gap | Batch 020's `testPlanningImportUnlocksContentImportAfterScheduleDetection` and Batch 021's `testPlanningImportBuildsVisibleScheduleScaffoldBlocks` never call `saveConfiguration` and never assert on `lessons`/`weeklyPlan.assignments` — they only check import roles and scaffold-block listings, so neither actually exercised (or could have caught a regression in) the scheduling outcome |
| 8 | Re-ran the diagnostic test with realistic content — filename "Fractions Unit Packet.docx", lesson titles "Equivalent fractions" / "Comparing fractions", no literal "math" anywhere | **Reproduced the real bug**: lessons created, but scheduled at a generic 9:00 AM default instead of the Math block's declared 9:45-10:45 — exactly matches the reported symptom from the teacher's point of view |
| 9 | Read `bestScheduleBlock` in full | Subject matching checks a narrow, mostly-just-the-subject-name keyword list against only `unitTitle`/`moduleTitle`/`pacingLessonTitle`/`sourceNotes` (source *filename* only, not full text) — realistic content frequently doesn't contain the literal subject word anywhere in those short fields |
| 10 | Designed the fix: (a) broaden each subject's keyword list to topic vocabulary, not just the subject name; (b) add a fallback that scans the *full extracted text* of the originating `ImportedSource` (found by parsing `sourceNotes`'s "Proposed from X" filename back against `importedSources`) when the short-field match finds nothing | — |
| 11 | Implemented `matchedScheduleBlock(forSubjectText:in:)` and `sourceDocumentText(referencedIn:)`, rewired `bestScheduleBlock` to try title-based matching first, then the full-text fallback | Done, in `AppStore.swift` |
| 12 | `swift build -Xswiftc -gnone` | Compiled clean |
| 13 | Re-ran the reproduction test | Fixed — "Equivalent fractions"/"Comparing fractions" now schedule at 9:45, matching the Math block |
| 14 | Ran full Swift test suite | 109 tests passed (108 baseline + the still-in-progress diagnostic test), 0 failures — no regressions from the broadened keyword lists |
| 15 | Converted the diagnostic test into a proper regression test (removed prints, added real assertions) and added two more: a reverse/negative case (topical Reading content schedules into Reading, not Math) and a case dedicated to the full-source-text fallback specifically (lesson titles as generic as "Day 1"/"Day 2", subject only in the document body) | 3 tests total: `testContentImportSchedulesTopicalMathLessonsIntoMathBlockOnlyViaTwoStageFlow`, `testContentImportSchedulesReadingLessonsIntoReadingBlockNotMath`, `testContentImportFallsBackToSourceBodyTextWhenLessonTitlesAreGeneric` |
| 16 | Ran full Swift test suite | 111 tests passed, 0 failures |
| 17 | Ran real Xcode build | BUILD SUCCEEDED; binary timestamp checked against wall clock |
| 18 | Owner asked for a Codex review before finalizing. Sent the full diff to Codex (self-contained prompt, no `cwd` — matches the documented gotcha that `cwd`-based exploration times out in this project) | Codex found a real, High-severity issue: once the *full source-document body* is searched (not just short titles), a fixed "check English first, then Math, then Art..." order is fragile — a math worksheet's body can easily contain one incidental English-flavored word before the text ever reaches its much stronger math vocabulary, so whichever subject happens to be checked first can silently win. Also flagged that raw substring matching let "art" match inside "chart"/"partial" and "map" match inside "concept map" regardless of actual subject |
| 19 | Rewrote `matchedScheduleBlock` in response: word-boundary keyword matching (tokenize the text, check exact-word set membership) instead of raw substring `contains`, plus a short multi-word-phrase list for phrases tokenizing can't catch ("word problem", "language arts"); the winning subject is now the one with the *highest keyword-match count*, not the first one checked. Removed a few keywords too generic to be a reliable signal in full body text ("map", "color", "story") rather than special-casing around them | Done, in `AppStore.swift` |
| 20 | `swift build`, full test suite (112 tests, 0 failures — the 4th new test added to prove the ambiguous-signal case), real `xcodebuild` (BUILD SUCCEEDED, fresh binary confirmed), updated `BUILD_LOG.md`/`MODEL_HANDOFF.txt`/this entry, confirmed all doc edits landed on disk | Pending final commit + GitHub sync as the close of this batch |

**Outcome.** Content-to-scaffold population now works for realistic content that doesn't
happen to contain the literal subject-name keyword anywhere in its filename or lesson titles
— which is the common case, not an edge case. Verified in both directions (Math content stays
out of Reading, Reading content stays out of Math), for the full-source-text fallback path
specifically, and — after the Codex review round — for content whose body contains an
incidental word from a different subject's vocabulary alongside a much stronger true signal.

**Dead ends / notes.**

- The bug report's investigation points 1, 2, 3, 5, and 6 (content-role forcing, sync
  triggering, pacing-plan extraction, scaffold-placeholder bridging, and the visible-scaffold
  rendering path) were all individually verified correct and are NOT where the bug lived.
  Only point 4 (`bestScheduleBlock`'s matching) was the actual root cause. Don't re-investigate
  the other five without new evidence.
- `configuration == nil` silently no-ops `syncReadableDocumentsIntoWeeklyPlanner` with no
  error shown. Confirmed unreachable in production (`RootView` gates `WorkspaceView` behind a
  non-nil configuration), so left unfixed rather than adding defensive code for an
  unreachable path — but any new test that seeds `AppStore` state directly must remember to
  call `saveConfiguration` first, or it will silently exercise nothing downstream of intake
  and falsely appear to pass.
- Two existing tests (`testPlanningImportUnlocksContentImportAfterScheduleDetection`,
  `testPlanningImportBuildsVisibleScheduleScaffoldBlocks`) still don't assert on scheduling
  outcomes — left as-is since they're testing a different, narrower concern (the import gate
  and the scaffold listing respectively) and the new tests now cover the scheduling outcome
  via the same real entry points. Worth strengthening later if this area breaks again.
- **First-draft-only mistake, caught by review, worth remembering:** a fixed if/else-if check
  order over keyword categories is fine when matching only short, curated titles, but becomes
  a real correctness risk the moment the match scope widens to full free-text document bodies
  — free text is far more likely to contain an incidental word from the "wrong" category. Any
  future free-text classification in this codebase should score/count matches per category
  rather than stopping at the first category with any hit.

**Still open.**

1. Workspace screen still needs the "Sunrise Planner" visual treatment (owner's UI-redesign
   track, separate from this bug fix).
2. Weekly planner cell/word-wrapping — owner flagged "minor visual issues" as still possibly
   present; not investigated this batch since it wasn't the reported problem.
3. Output-enrichment roadmap (`OUTPUT_ENRICHMENT_PLAN.md`) — lesson-plan/differentiation-guide
   template expansion, per Batch 015/016's next-steps list.
4. `CLAUDE.md` is stale (still describes Batch 007 state) — should be refreshed in a
   documentation-focused batch; not done here to keep this batch scoped to the actual bug fix.

**GitHub sync status.** Committed locally at `0f53ad5`. `git push origin main` failed —
"could not read Username for 'https://github.com': Device not configured" (no command-line
credentials in this environment, matching earlier-documented state). Requested computer-use
access to GitHub Desktop to push through the documented working sync path; the owner denied
that access request. Left as a local-only commit, one ahead of `origin/main` — needs the
owner to push (via GitHub Desktop or by supplying command-line credentials) whenever
convenient. Did not spend further batch time on auth troubleshooting, per the standing
instruction to log the blocker rather than chase it.

---

### Batch 023 — 2026-07-29 — "Sunrise Planner" redesign, Batch E: Workspace screen (final screen)

**Compute:** high. **Model shape:** single sufficient — mechanical re-skin following the
`DS` pattern already established and proven across Batches A–D; no new design judgment calls.

**Goal.** Re-skin the Workspace tab — the last of the app's 5 screens still on the original
stock-SwiftUI look — completing the full "Sunrise Planner" visual redesign.

| # | Step | Result |
|---|------|--------|
| 1 | Re-oriented: confirmed local `main` still 2 commits ahead of `origin/main` (unchanged since Batch 022), working tree clean | No new upstream changes to reconcile |
| 2 | Read the approved plan (`~/.claude/plans/snuggly-brewing-elephant.md`) | Confirmed Batches B-D (This Week, Planning Preview, Document Intake) already done and owner-reviewed per Batch 012-014/016 log entries; only Workspace remained |
| 3 | Read `ConfigurationSummaryView` in full (~457 lines) | The screen has grown far past the original design handoff's simple "document library" concept — it's now a dense settings/admin screen: local profiles, progress safety (save/reload/clear), workspace paths, PowerPoint export preference, weekly prompt config, a full course-pacing unit/module/lesson editor, source folders, templates, presentation-template readiness, local workflow QA, release readiness, and generated-output history |
| 4 | Scoping decision | Apply the `DS` visual language to the screen's structure and primary controls (converting the native `Form`/`Section` layout to the same `ScrollView` + `DSCard` pattern used by the other 4 screens), but leave native controls without a `DS` equivalent (Picker, Stepper, DatePicker, the destructive-clear `confirmationDialog`) untouched, and leave the screen's existing small subcomponent views (`CoursePacingReadinessView`, `LocalWorkflowQAView`, `OutputReviewRow`, etc.) in their native styling rather than touching ~10 additional structs in the same batch |
| 5 | Rewrote `ConfigurationSummaryView.body`: `Form`/`Section` → `ScrollView` + `VStack` of `DSCard`-wrapped sections, each with a `sectionHeader` helper; restyled buttons to `.dsPrimary`/`.dsSecondary`, text fields to `.ds`, added a `workspaceRow` label/value helper for the many `LabeledContent`-style rows | Done, in `WorkspaceView.swift` — all business-logic helper functions (`chooseOutputFolder`, pacing-unit editing, etc.) left untouched |
| 6 | `swift build -Xswiftc -gnone` | Compiled clean on the first attempt |
| 7 | `swift test -Xswiftc -gnone` | 112/112 tests passed, unaffected — pure View-layer change, as expected |
| 8 | Real `xcodebuild` | BUILD SUCCEEDED (no new files, no pbxproj edit needed — only an existing, already-registered file changed) |
| 9 | Launched on the Workspace tab, `activate` + window-ID `screencapture`, saved `Design Screenshots/2026-07-29/10-workspace-sunrise-redesign.png` | Confirmed nav/profile band/cards/typography all correctly match the established style |
| 10 | Caught and fixed a naming collision myself before showing the owner: the page title and the first section header were both literally "Workspace," reading as a duplicate | Renamed the section header to "Workspace location" |
| 11 | Rebuilt, relaunched, used `computer-use` to scroll through the rest of the screen for a full visual check | The active profile ("Nick") turned out to have real, large-scale imported curriculum data (315 units, 869 source filenames referencing what is clearly a licensed math curriculum) — safe to view live for my own verification, but I did not save any screenshot of that state, since project boundaries prohibit proprietary curriculum references in any tracked screenshot |
| 12 | Created a throwaway local test profile ("QA Preview") to get a clean, generic-only view of every remaining section without real curriculum data | Confirmed via the app's own "Local testing profiles" feature, which exists exactly for this |
| 13 | The new profile's workspace-folder picker defaulted into the real curriculum's folder tree; navigated to the home folder and created a fresh, empty `LessonPlanner QA Preview` folder instead, rather than selecting anything under the existing curriculum folder | Kept the QA workspace folder pointed at genuinely empty, generic content |
| 14 | Scrolled through the entire screen with the clean profile: Local testing profiles, Progress safety, Workspace location, PowerPoint export, Weekly planning prompt, Course pacing setup (empty state), Registered source folders (empty state), Registered templates (empty state), Presentation template readiness, Local workflow QA, Release readiness, Generated output history (empty state) | All 11 cards render correctly and consistently with the established design language; native subcomponents (status icons, checklists) read fine inside the new card chrome |
| 15 | Owner needed screen control back mid-verification; stopped computer-use immediately and continued the rest of the batch (logging, docs, build/test, commit) without it — none of the remaining steps needed screen control | Confirmed no computer-use calls after this point |
| 16 | Cleaned up: quit the launched app instance, deleted the empty `LessonPlanner QA Preview` folder from disk (created this session, safe to remove) | Done. Left the "QA Preview" local test profile itself in the app — harmless local test-profile data, same as any other test profile |
| 17 | Final `swift test -Xswiftc -gnone` | 112/112 tests passed |
| 18 | Updated `BUILD_LOG.md`, `MODEL_HANDOFF.txt`, `CLAUDE.md` (flagged stale in Batch 022 — natural point to refresh since the redesign it describes as "in progress" is now complete), `CONTINUITY_LOG.md` (this entry) | See below |
| 19 | Confirmed all doc edits landed on disk, committed | See below |
| 20 | Report to the owner and stop for visual approval — this is the redesign's final screen; per the standing rule, do not consider the whole initiative "done" until the owner has looked at it | This message |

**Outcome.** The "Sunrise Planner" visual redesign is now complete across all 5 screens
(Today, This Week, Planning Preview, Document Intake, Workspace). Every screen shares the
same design-system foundation (`DesignSystem.swift`, unchanged since Batch 007) and the same
custom top nav/profile band. 112/112 tests unaffected throughout the entire redesign
initiative — it was a View-layer-only effort from Batch 007 through this batch, exactly as
the original plan scoped it.

**Dead ends / notes.**

- `computer-use` scroll actions occasionally landed on desktop icons behind the app window
  ("would land on zoom.us, not in allowlist") after the window appeared to shift position
  between actions. Re-running `osascript -e 'tell application "LessonPlanner" to activate'`
  before the next action reliably fixed it. Not investigated further since it was an
  intermittent capture/targeting quirk, not an app bug — scrolling at a coordinate safely
  inside the card content (not near the window edge) also seemed to help.
- When a real local test profile has meaningful production-scale data, don't rely on it for
  screenshots meant to be saved to the repo — create a throwaway empty test profile instead.
  The app's own "Local testing profiles" feature (already built for isolating test workspaces)
  is the right tool for this, not a special case.
- Owner can reclaim screen/computer-use control mid-task at any point; the rest of a batch
  (docs, build, test, git) rarely depends on it once visual verification is done — plan
  computer-use-dependent steps early in a batch, not interleaved throughout, so a mid-batch
  interruption doesn't block finishing the rest.

**Still open.**

1. **Needs the owner's visual approval** — this is the last screen of the redesign; stop here
   per the standing rule rather than declaring the whole initiative done unilaterally.
2. GitHub sync — still 2 commits ahead of `origin/main` from Batch 022, plus whatever this
   batch adds; push still needs the owner (see Batch 022's sync-status note above).
3. The "Sources" field in "Course pacing setup" renders as one long comma-joined string of
   every source filename — pre-existing behavior (identical under the old `Form`/
   `LabeledContent` layout), not introduced by this redesign, but genuinely hard to read once
   a course pacing plan has hundreds of sources. Worth a future polish pass (e.g. a collapsed
   count + expandable list) — not done here to keep this batch scoped to the visual redesign.
4. Output-enrichment roadmap (`OUTPUT_ENRICHMENT_PLAN.md`) — still the next substantive
   product-work track once the redesign is signed off.

### Batch 024 — 2026-07-29 — Workspace path cleanup, boundary trace-check, and a validated test template

**Compute:** high. **Model shape:** single sufficient — mechanical UI edit, forensic
grep/strings audit, and hand-authored OOXML; no architectural judgment calls.

**Goal.** Three owner requests from a review of the Batch 023 Workspace redesign: (1) drop the
raw file-path display if it isn't load-bearing, (2) prove licensed curriculum material used
only for local testing leaves no trace in the tracked repo, (3) clarify and, if reasonable,
produce the "template" needed to test placeholder-inheritance resolution.

| # | Step | Result |
|---|------|--------|
| 1 | Confirmed `outputFolderReference` is functionally load-bearing (`AppStore.swift` sets it from the folder picker and falls back to a `LessonPlanner Outputs` subfolder when nil — it decides where generated decks/guides save) before removing anything | Kept the "Choose output folder…" button; only the raw `.path` string display was removable |
| 2 | Rewrote `workspaceLocationsCard` in `WorkspaceView.swift`: dropped the `Location`/`Output folder` raw-path rows, replaced with one plain-language sentence that reflects whether a custom output folder is set; renamed section header "Workspace location" → "Workspace settings" | `swift build -Xswiftc -gnone` compiled clean |
| 3 | Boundary trace-check: `git grep -il` across tracked text for curriculum/publisher identifiers (`im_nl`, `im_pse`, `HMH`, `Illustrative Math`, `TeacherEdition`, `g5_im`, etc.) | Only hit: `SELLABLE_POWERPOINT_EXPORTER_BOUNDARY.md`'s own boundary rule (benign, expected) |
| 4 | Ran `strings` on every PNG match from a broader case-insensitive grep across `Design Screenshots/` | All matches were coincidental compressed-binary byte sequences ("HmhH", "=HmH"), not real embedded text — no leak |
| 5 | `git log --all --diff-filter=A --name-only` filtered for `.docx`/`.pdf`/`.pptx`/curriculum-name matches across full history | Zero results — no such file was ever committed, at any point, on any branch |
| 6 | Confirmed architecturally that `LocalRepository` stores all app data under `~/Library/Application Support/`, structurally outside the git-tracked project folder — real curriculum content a teacher imports for testing never enters the repo's working tree in the first place | Reported this finding to the owner as the structural reason the trace-check keeps coming back clean |
| 7 | Clarified the "template" ask: it's a PowerPoint slide template (.pptx) needed to exercise `PowerPointTemplateInspector.resolvePlaceholders(url:)` with genuine slide→layout→master inheritance — explained why a generator library (`pptxgenjs`) wouldn't produce real inheritance, and that hand-authoring valid OOXML directly was the right approach | Loaded the `pptx` skill for its `validate.py` script and reference guidance |
| 8 | Hand-wrote a complete 2-slide "Sunrise Lesson Plan Template" OOXML package (content types, rels, theme, slide master, 2 layouts, 2 slides) using the app's own warm Sunrise palette, deliberately designed so Slide 1's placeholders inherit geometry from Layout 1, Slide 2's title has geometry nowhere but the master, and Slide 2's body inherits from Layout 2 | Package built at scratch path; zipped to `.pptx` |
| 9 | Ran `scripts/office/validate.py` | FAILED — 7 schema errors in `theme1.xml`: missing `dk2`/`lt2` color entries, missing `ea`/`cs` font children, incomplete `effectStyleLst` |
| 10 | Rewrote `theme1.xml` to be fully schema-complete (full `dk1/lt1/dk2/lt2/accent1-6/hlink/folHlink` color scheme, `ea`/`cs` typeface children on both major and minor fonts, 3-entry `effectStyleLst`) | Re-zipped, re-ran `validate.py` — **"All validations PASSED!"** |
| 11 | Attempted `soffice`/`markitdown` visual and content QA per the `pptx` skill's standard process | Neither tool is installed on this machine — skipped automated render QA; relied on direct XML read (already confirmed correct text, no placeholder leftovers) plus the schema pass |
| 12 | Asked the owner how to proceed given no local render QA; owner chose: register the template in the live app and verify placeholder resolution directly | `AskUserQuestion` |
| 13 | Requested screen access, registered `Sunrise Lesson Plan Template.pptx` via the app's file picker | "7 mapped lesson fields", "Template provenance ready" |
| 14 | Clicked "Inspect presentation template" | Placeholder inheritance panel showed exactly the 3 designed paths: Slide 1 title/subtitle "geometry inherited from the layout"; Slide 2 title "geometry inherited from the master"; Slide 2 body "geometry inherited from the layout" — full slide→layout→master resolution confirmed correct |
| 15 | Noticed the running app was still the pre-Batch-023-fix stale binary (still showing raw paths) — owner reclaimed screen control before a rebuild happened | Deferred the rebuild to steps 16-18, which don't need the screen |
| 16 | `swift test -Xswiftc -gnone` | 112/112 passed |
| 17 | Real `xcodebuild -scheme LessonPlanner -configuration Debug build` | BUILD SUCCEEDED |
| 18 | Owner briefly returned screen access; quit the stale app instance, relaunched the freshly built binary, navigated to Workspace | Visually confirmed the "Workspace settings" card no longer shows raw paths — matches step 2's intent |
| 19 | `git status`/`git diff` review before committing | Only `WorkspaceView.swift` changed; diff matches intent exactly |
| 20 | Updated `CONTINUITY_LOG.md` (this entry); committed | See below |

**Outcome.** Workspace screen no longer surfaces raw filesystem paths while keeping the
functionally load-bearing "Choose output folder…" control. Boundary trace-check came back
fully clean via three independent methods (tracked-file grep, binary `strings` scan, full git
history audit), with the architectural reason (`LocalRepository` writes outside the repo)
identified as the root cause the check keeps passing. A schema-valid, generically-branded
`.pptx` slide template now exists and has been used to directly confirm
`PowerPointTemplateInspector.resolvePlaceholders` correctly resolves all three inheritance
paths (layout-override ×2, master-fallback ×1) — the placeholder-inheritance feature is now
proven correct against a real file, not just unit-test fixtures.

**Dead ends / notes.**

- This machine has neither `soffice` (LibreOffice) nor `markitdown` installed, so the `pptx`
  skill's standard visual-render and content-QA steps aren't available here. Direct XML
  inspection plus `validate.py`'s schema pass was the fallback, and was sufficient for this
  template's purpose (testing a Swift XML reader, not shipping a polished deck) — but a future
  task that needs to *see* a rendered deck will need one of those tools installed first.
- The theme XML pattern in `NativePowerPointExporter.swift` (the app's own exporter) is the
  same simplified shape that failed `validate.py` here — missing `dk2`/`lt2`, `ea`/`cs`, and a
  complete `effectStyleLst`. It has apparently never been strictly schema-validated. Not fixed
  in this batch (out of scope — the exporter's decks open fine in real PowerPoint/Google
  Slides, which are lenient about these omissions), but worth a future validation pass since a
  stricter consumer could reject it.
- Screen control can be reclaimed and returned mid-batch more than once; splitting a batch's
  computer-use-dependent steps into two short windows (register+inspect, then a quick
  rebuild-verify) worked fine as long as everything in between (build, test) needed no screen.

**Still open.**

1. GitHub sync — still ahead of `origin/main`; push still needs the owner.
2. Install `soffice`/`markitdown` locally if future pptx-skill work needs visual/content QA.
3. Consider validating `NativePowerPointExporter.swift`'s theme against the same schema
   `validate.py` checks, since it shares the gap found in this batch's first template attempt.
4. Output-enrichment roadmap (`OUTPUT_ENRICHMENT_PLAN.md`) — still the next substantive
   product-work track.

### Batch 025 — 2026-07-29 — Layout-preserving PowerPoint export, Batch 1: structural frame map

**Compute:** high (routed via the `codex-router` skill's classification, per the owner's
standing instruction). **Model shape:** Claude-native for this batch — architecture/data-model
decisions, not bulk code generation; the mechanical `.pptx`-editing implementation is scoped
to a future Codex-delegated batch once its interface is locked down here. **Constraint:** the
owner was on a Zoom call; this batch was scoped to avoid computer-use/screen-control entirely
(pure Swift source edits plus `swift build`/`swift test`/`xcodebuild` via Bash).

**Goal.** First step of "layout-preserving PowerPoint export" — placing approved lesson
content into a customer-owned template's real placeholder frames. An Explore subagent had
mapped the existing code first: `PowerPointTemplateInspector.resolvePlaceholders(url:)` (the
slide→layout→master inheritance resolver) is solid and already proven correct (Batch 024), but
the Workspace UI's "frame map" was built by `inspect(url:)` via keyword-guessing on slide XML
text — completely disconnected from the real resolver sitting in the same file — and nothing
in the shipped app ever set `fidelityReviewCompleted = true`, so the "Complete template
fidelity QA" readiness item could never actually be satisfied through real use.

| # | Step | Result |
|---|------|--------|
| 1 | Read `PowerPointTemplateInspector.swift`, `AppModels.swift`, `AppStore.swift`, and `WorkspaceView.swift` in full for the exact current shape of every type/function involved | Confirmed the Explore agent's findings precisely, with line numbers |
| 2 | Added `PresentationTemplatePlaceholderAssignment` (`AppModels.swift`): `sourceSlideNumber`, `shapeID`, `shapeName`, `effectiveType`, `effectiveIdx`, `lessonField: LessonTemplateField?` — a structural, ECMA-376-accurate placeholder identity, distinct from the heuristic `mappedSlotNames` string list | New model, addressable by shape ID for future content placement |
| 3 | Added `placeholderAssignments: [PresentationTemplatePlaceholderAssignment]` to `PresentationTemplateLayoutPlan` | |
| 4 | Added `unassignedRequiredFields` computed property to `PresentationTemplateReadinessReport`; reworded the `.fidelityQAPending` issue instruction to describe the real action needed | |
| 5 | `PowerPointTemplateInspector.inspect(url:)` now also calls `resolvePlaceholders(url:)` internally and populates `placeholderAssignments` directly from the real resolved placeholders (skipping any placeholder with no shape ID, since it can't be structurally addressed later) — the heuristic slide-inventory/frame-map generation is left as-is (still useful as informational role-guessing text), but the new field is 100% structural | Two real data representations now coexist without one replacing the other's purpose |
| 6 | `AppStore.inspectPresentationTemplateLayout` now merges freshly-resolved assignments with the template's prior `placeholderAssignments` by `(sourceSlideNumber, shapeID)`, carrying forward any `lessonField` a teacher already chose — re-inspecting a changed template file no longer silently discards prior work | |
| 7 | `AppStore.updatePresentationTemplateLayoutPlan` signature extended with `placeholderAssignments:` | |
| 8 | Added `AppStore.assignPlaceholder(templateID:assignmentID:lessonField:)` — sets/clears one placeholder's lesson field; any edit resets `fidelityReviewCompleted` to `false`, since a stale confirmation must not survive a mapping change | |
| 9 | Added `AppStore.confirmPresentationTemplateFrameMap(templateID:)` — the one real, user-completable path to `fidelityReviewCompleted = true`. Succeeds only once every required lesson field (title, objective, instructional sequence, assessment) has an assigned placeholder; otherwise reports exactly which fields are missing via `lastError` (already wired to a global alert in `RootView.swift`) | Fixes the "can never be satisfied" bug found in the Batch 024 research |
| 10 | Added a "Placeholder assignments" section to `WorkspaceView.swift`'s `presentationTemplateCard`: one row per resolved placeholder (slide/shape name/type/idx) with a `Picker` bound to `assignPlaceholder`, plus a "Confirm frame map" button wired to `confirmPresentationTemplateFrameMap` | New, minimal UI — functional but not yet visually verified (see below) |
| 11 | Updated 2 existing tests' direct `PresentationTemplateLayoutPlan(...)` constructions and 1 `updatePresentationTemplateLayoutPlan` call site for the new required parameter | |
| 12 | Added an assertion to `testAppStoreInspectPresentationTemplateLayoutResolvesPlaceholderInheritance` confirming the structural assignment (shapeID 2, type "title", idx 0, unassigned lessonField) is derived correctly from the real hand-built template package already used in that test | |
| 13 | Added 3 new tests: `testAssignPlaceholderSetsLessonFieldAndResetsFidelityReview`, `testConfirmPresentationTemplateFrameMapRequiresAllRequiredFieldsAssigned` (asserts the specific missing-field names in `lastError`), `testConfirmPresentationTemplateFrameMapSucceedsWhenAllRequiredFieldsAssigned` | |
| 14 | Extended the real-template inheritance test with a re-inspect step: assign a placeholder, re-run `inspectPresentationTemplateLayout`, confirm the assignment survives and `fidelityReviewCompleted` correctly resets to `false` | Proves the merge-preserve logic from step 6 |
| 15 | `swift build -Xswiftc -gnone` | Compiled clean |
| 16 | `swift test -Xswiftc -gnone` | First run: 1 failure — `testConfirmPresentationTemplateFrameMapSucceedsWhenAllRequiredFieldsAssigned` failed because the test's own setup left `slideInventory`/`frameMap` empty, independently tripping `.layoutInventoryPending`/`.frameMapPending` regardless of placeholder assignments. Fixed the test data (added realistic inventory/frame-map entries), re-ran: **115/115 passed** (112 baseline + 3 new) |
| 17 | Real `xcodebuild -scheme LessonPlanner -configuration Debug build` | BUILD SUCCEEDED — confirms the new SwiftUI `Picker`/`Button` code is valid, without ever opening the app on screen |
| 18 | Updated `CONTINUITY_LOG.md` (this entry) | |

**Outcome.** The frame-map system is no longer two disconnected representations — every
resolved template placeholder is now structurally addressable (`sourceSlideNumber` +
`shapeID`), and a teacher (via the new Workspace UI) or a future automated flow can assign each
one to a lesson field and confirm the mapping through a real, testable action. The previously
permanently-stuck "Complete template fidelity QA" readiness item can now genuinely reach
"ready." This unblocks the next batch: a `.pptx` package editor that reads these assignments
and actually writes lesson content into the resolved placeholder frames of a copied template
slide — the one piece of this feature identified as completely missing.

**Dead ends / notes.**

- Caught before committing: an early draft of `testConfirmPresentationTemplateFrameMapSucceedsWhenAllRequiredFieldsAssigned`
  only populated `placeholderAssignments` and left `slideInventory`/`frameMap` empty, which
  fails `isReadyForLayoutPreservation` for an unrelated reason (inventory/frame-map issues,
  not placeholder-assignment issues) — a reminder that `PresentationTemplateReadinessReport`
  has three independent gates (mappings, inventory/frame-map, fidelity QA) that a test
  exercising one must not accidentally leave failing on another.
- This entire batch was done with zero `computer-use`/screen-control calls, per the owner's
  request while on a Zoom call — confirms the project's own prior note (Batch 023) that most
  of a batch's steps don't actually depend on screen access once a task is scoped as
  architecture/code rather than visual verification.
- The new Workspace UI (`placeholderAssignmentSection`) is unverified visually — it compiles
  and passes a real Xcode build, but has not been screenshotted or clicked through. Do this
  before considering the feature done end-to-end.

**Still open.**

1. **Batch 026 (Codex-delegated, per the routing plan)**: implement a `.pptx` package
   editor/patcher — copy an existing template archive, duplicate/renumber slide parts per the
   frame map, patch `<p:txBody>` runs in the copied slides with `LessonOutputContent` text at
   each assigned placeholder's resolved geometry, write a valid archive back out. Interface to
   hand Codex: something like
   `PowerPointTemplateComposer.compose(templateURL:frameMap:placeholderAssignments:content:) throws -> Data`.
   Review Codex's diff, then verify with `validate.py`, the real test suite, a real Xcode
   build, and opening the output in the app before considering it done — this is the
   highest-risk part of the whole feature (ZIP/XML corruption bugs are easy to introduce).
2. **Batch 027**: wire `NativePowerPointExporter` (or a new template-aware exporter path) to
   use the Batch 026 composer when a template has `fidelityReviewCompleted = true`, falling
   back to today's from-scratch layout otherwise.
3. Visually verify the new "Placeholder assignments" UI in Workspace (screenshot + a manual
   click-through of the Picker/Confirm flow) — deferred this batch per the no-screen-control
   constraint.
4. GitHub sync — push this batch's commit once ready.
5. Output-enrichment roadmap (`OUTPUT_ENRICHMENT_PLAN.md`) — still on the backlog, independent
   of this initiative.

### Batch 026 — 2026-07-29 — Layout-preserving PowerPoint export, Batch 2: the `.pptx` composer

**Compute:** high, **Codex-delegated** per the routing plan agreed in Batch 025 — this was the
well-specified, algorithm-dense, mechanical piece (ZIP/XML editing against a locked-down
interface), the profile the `codex-router` skill calls out for delegation.

**Goal.** Implement the piece identified as completely missing in Batch 024's research: a
`.pptx` package editor that actually writes approved lesson content into a customer-owned
template's real placeholder shapes, using the `PresentationTemplatePlaceholderAssignment`
data built in Batch 025.

| # | Step | Result |
|---|------|--------|
| 1 | Wrote a single, fully self-contained prompt for Codex (interface signature, exact field-mapping table, ZIP-writer approach, explicit "do not touch" list for `NativePowerPointExporter.swift`/`AppStore.swift`/views/`project.pbxproj`, and 3 required test cases) — kept scope deliberately narrow: edit placeholder text on the template's own existing slides in place, no slide duplication/reordering (that's a later batch) | Lower-risk first version of the highest-risk part of this feature |
| 2 | First attempt via the `mcp__codex__codex` MCP tool timed out at the transport level before any work started (confirmed via `git status` — no files touched) | Not a Codex failure, an MCP RPC timeout on a long-running call |
| 3 | Retried via the `codex` CLI directly (`/Applications/ChatGPT.app/Contents/Resources/codex exec`, found via `find /Applications -iname codex`) run in the background with `-s workspace-write`, writing to a log file instead of waiting on the MCP round-trip | Completed cleanly, no MCP timeout this time |
| 4 | Reviewed every changed/new file in full before trusting any of it (per standing practice — never accept a delegated agent's self-report alone): `git status` confirmed only the 3 expected files touched; `git diff` on `PowerPointTemplateInspector.swift` confirmed the access-widening was exactly `private` → default-internal with zero added `public`, zero behavior change, plus one small well-placed helper (`PowerPointPackageReader.data(named:)`) reused by both the existing `xml(named:)` and the new composer | Clean, precisely scoped diff |
| 5 | Read the new `PowerPointTemplateComposer.swift` in full and traced the correctness of its custom string-based XML editing by hand: the `<p:sp` vs `<p:spPr` boundary-matching logic, the shape/`txBody` range-finding scoped correctly per shape, the paragraph-replacement logic (preserves `<a:bodyPr>`/`<a:lstStyle>`, replaces only `<a:p>` children, inserts new content exactly once at the first paragraph's position), and the re-implemented CRC32/ZIP-writer (byte-for-byte the same well-known format `NativePowerPointExporter.swift`'s own `StoredZipWriter` already uses successfully in production) | No correctness issues found |
| 6 | Read the 3 new tests in full — confirmed they matched the spec, including one Codex added on its own initiative (a title containing `<` and `&` to actually exercise XML escaping, not just happy-path text) | Good test judgment beyond the literal ask |
| 7 | Independently ran `swift build -Xswiftc -gnone` and `swift test -Xswiftc -gnone` myself (not trusting Codex's own build/test report, which had noted it needed `--disable-sandbox` to run in its own environment) | 118/118 passed cleanly in my own environment |
| 8 | Added one temporary, clearly-marked verification-only test composing against the REAL, already schema-validated `Sunrise Lesson Plan Template.pptx` from Batch 024 (not a hand-built fixture), writing the output to a fixed scratch path | Ran via `swift test --filter`, produced a real file |
| 9 | Ran the `pptx` skill's `scripts/office/validate.py --original "Sunrise Lesson Plan Template.pptx"` against the composed output | **"All validations PASSED!"** — full OOXML schema validation, not just XML-text matching |
| 10 | Unzipped the composed output and grepped its `<a:t>` runs directly | Confirmed exact correct text landed in the right placeholders, including a deliberately non-default mapping (assessment → slide 2's title) and a 2-item instructional sequence correctly split into 2 separate `<a:p>` paragraphs |
| 11 | Removed the temporary verification test (it was scratch-only, not part of the deliverable) | `git diff` on the test file now shows only Codex's 3 permanent tests |
| 12 | Registered the new file in `LessonPlanner.xcodeproj/project.pbxproj` myself (Codex was explicitly told not to touch this) — 4 entries per the project's documented explicit-file-reference pattern, new ID `0000000000000018` (confirmed unused first) | |
| 13 | `swift test -Xswiftc -gnone` again after removing the temp test | 118/118 passed |
| 14 | Real `xcodebuild -scheme LessonPlanner -configuration Debug build` | BUILD SUCCEEDED |
| 15 | Updated `CONTINUITY_LOG.md` (this entry) | |

**Outcome.** `PowerPointTemplateComposer.compose(templateURL:placeholderAssignments:content:)`
now exists, is unit-tested, and has been independently proven correct against a real,
previously-validated template — not just hand-built test fixtures. This is the piece Batch 024's
research flagged as completely missing and the highest-risk part of the whole "layout-preserving
export" feature; it's now built, reviewed, and verified from multiple independent angles (unit
tests, manual code review, real-template schema validation, direct content inspection).

**Dead ends / notes.**

- The `mcp__codex__codex` MCP tool timed out on a large, well-specified prompt — confirmed via
  `git status` that nothing had started, so it was safe to simply retry rather than investigate
  further. The CLI fallback (`codex exec -s workspace-write` run via Bash in the background)
  worked cleanly and avoids the MCP transport's timeout ceiling for long-running delegated work.
  Binary path: `/Applications/ChatGPT.app/Contents/Resources/codex` (not `/Applications/Codex.app`
  as an earlier generic fallback pattern assumed — the ChatGPT desktop app hosts it on this Mac).
- Codex reported it needed `--disable-sandbox` to run `swift build`/`swift test` inside its own
  managed sandbox environment (blocked cache paths) — noted but not a concern, since this
  project's standing practice is to always independently re-verify a delegated agent's work in
  the real environment regardless of what it self-reports.
- Deliberately scoped this batch to in-place placeholder-text editing only (no slide
  duplication/reordering), since the current `inspect()`/frame-map pipeline never produces
  more output slides than source slides anyway — this kept the highest-risk part of the feature
  meaningfully smaller and lower-risk than the original Batch 025 write-up implied ("duplicate/
  renumber slide parts"). Slide duplication for lessons needing more slides than the template
  has (e.g. multiple practice slides) is deferred to a future batch, once there's a UI for a
  teacher to actually express that intent.

**Still open.**

1. **Batch 027**: wire `PowerPointTemplateComposer` into the real export flow — likely a new
   case in `AppStore`'s slide-deck generation path, used when `fidelityReviewCompleted = true`
   on the active presentation template, falling back to `NativePowerPointExporter`'s
   from-scratch layout otherwise. Needs a decision on where in the UI a teacher triggers a
   template-aware export vs. the default one.
2. Visually verify the Batch 025 "Placeholder assignments" Workspace UI — still deferred.
3. Slide duplication/reordering for templates with fewer slides than a lesson needs — future
   scope, needs a UI concept first.
4. GitHub sync — push this batch's commit.
5. Output-enrichment roadmap (`OUTPUT_ENRICHMENT_PLAN.md`) — still on the backlog.

### Batch 027 — 2026-07-29 — Layout-preserving PowerPoint export, Batch 3: wire it into export

**Compute:** medium. **Model shape:** Claude-native — the actual wiring was small and
judgment-heavy (fallback/error-propagation semantics), not bulk code generation, so no Codex
delegation was needed for this step.

**Goal.** Wire `PowerPointTemplateComposer` (Batch 026) into the app's real slide-deck
generation flow, so an approved lesson with a confirmed template frame map actually produces
layout-preserving output instead of the generic from-scratch deck.

| # | Step | Result |
|---|------|--------|
| 1 | Traced the existing call path before assuming a new UI trigger was needed | Found exactly one entry point, `AppStore.generateSlideDeckPPTX(for:)`, which already resolves `activePresentationTemplate` and passes it into `activeSlideDeckGenerator.generate(lesson:destination:template:)` — no new UI decision point required, just a branch inside the existing generator |
| 2 | Designed the fallback/error semantics: when the active template's `layoutPlan?.fidelityReviewCompleted == true` (a flag that, per Batch 025, can only become true once every required lesson field has an assigned placeholder — sufficient "ready" signal on its own), use the composer; otherwise keep today's generic from-scratch deck unchanged. **Deliberately do NOT swallow a composer failure into a silent fallback** — a teacher who confirmed template placement expects to see it used, so a failure (e.g. the template file moved or was edited externally) surfaces as a real error via the existing `AppStore.lastError`/`RootView` alert path, not a quietly-substituted generic deck | A genuine design decision, not just wiring |
| 3 | Edited `NativePowerPointExporter.generate(lesson:destination:template:)` — ~15 lines, branches to `PowerPointTemplateComposer.compose(...)` when ready, falls through to the existing `NativePowerPointDeck` path otherwise | `swift build` compiled clean |
| 4 | Added `testAppStoreSlideDeckGenerationUsesComposerWhenFrameMapConfirmed` — confirms real lesson content lands in the correct placeholders of a hand-built 2-slide template, and that the OUTPUT has exactly 2 slides (not the generic exporter's ~7), proving the composer path actually ran | |
| 5 | Added `testAppStoreSlideDeckGenerationSurfacesComposerFailureWithoutSilentFallback` — registers a template pointing at a file that doesn't exist on disk, marks its layout plan confirmed anyway (simulating the file moving after confirmation), and asserts `generateSlideDeckPPTX` returns `nil`, `lastError` is set, and no output was silently written | Confirms the "fail loud, don't mask" decision from step 2 actually holds |
| 6 | `swift test -Xswiftc -gnone` | 120/120 passed (118 baseline + 2 new); confirmed zero regression on the pre-existing "template registered but not confirmed → generic deck with metadata in speaker notes" tests |
| 7 | Went beyond unit tests again for the payoff step of the whole feature: added a temporary verification-only test exercising the FULL `AppStore.generateSlideDeckPPTX` production path (destination naming, output-folder resolution, `GeneratedOutputRecord` creation — not just calling the composer directly) against the real `Sunrise Lesson Plan Template.pptx`, assigning only 2 of its 4 placeholders (title on slide 1, body on slide 2) | Ran via `swift test --filter`, produced a real file |
| 8 | Ran `scripts/office/validate.py --original` against the output, then unzipped and grepped its `<a:t>` runs | **"All validations PASSED!"** — and content confirmed correct *selective* replacement: the 2 assigned placeholders got new text, the 2 unassigned ones (slide 1's subtitle, slide 2's title) kept their original template text exactly as-is |
| 9 | Removed the temporary verification test | `git diff` on the test file now shows only the 2 permanent tests from steps 4-5 |
| 10 | `swift test -Xswiftc -gnone` and real `xcodebuild` again after removing the temp test | 120/120 passed; BUILD SUCCEEDED (no new files this batch, no `project.pbxproj` change needed) |
| 11 | Updated `CONTINUITY_LOG.md` (this entry) | |

**Outcome.** "Layout-preserving PowerPoint export" is now a working, end-to-end feature: a
teacher who registers a customer-owned template, assigns lesson fields to its placeholders,
and confirms the frame map will get real lesson content placed into that template's actual
slides when they generate a deck — verified against a real file at every layer (unit tests,
the full production call path, OOXML schema validation, and direct content inspection). This
closes out the 3-batch arc that started with Batch 024's research finding the feature was
completely unbuilt.

**Dead ends / notes.**

- No new UI was needed for "where does a teacher trigger a template-aware export" — the
  existing single generation entry point already threads the active template through, so the
  "decision" collapsed into "does this template happen to be confirmed," which is exactly the
  state `AppStore.confirmPresentationTemplateFrameMap` (Batch 025) already tracks.
- The temporary Batch 026 lesson (compose against a real, already-validated template for a
  stronger-than-unit-test proof) was repeated here at the full-production-path level, and is
  becoming a recognizable pattern for this project: a hand-built test fixture proves the logic
  is correct in isolation, a real previously-validated file proves it holds up in practice.
  Worth reaching for again on any future PowerPoint-writing work.

**Still open.**

1. Visually verify the Batch 025 "Placeholder assignments" Workspace UI — still deferred, no
   screen-control batch has happened yet since it was built.
2. Slide duplication/reordering for templates with fewer slides than a lesson needs — future
   scope, needs a UI concept first (flagged since Batch 026).
3. GitHub sync — push this batch's commit.
4. Consider whether `GeneratedOutputRecord` should distinguish "layout-preserving" vs.
   "metadata-only" provenance in its own data/UI (currently only `templateDisplayName` is
   tracked, which doesn't say which mode was used) — deliberately deferred this batch to keep
   scope to the wiring itself; a reasonable next small polish item.
5. Output-enrichment roadmap (`OUTPUT_ENRICHMENT_PLAN.md`) — still on the backlog.

### Batch 028 — 2026-07-29 — Output enrichment: apply LessonOutputContent to the HTML renderers

**Compute:** medium. **Model shape:** Claude-native — moderate code volume, but genuinely
judgment-heavy (a fallback-text correctness issue found mid-design, plus a real product-scope
decision about differentiation-guide structure), not a good Codex delegation candidate.

**Goal.** Per `OUTPUT_ENRICHMENT_PLAN.md`'s "First Coding Pass" item 4: apply the shared
`LessonOutputContent` view model (already used by `NativePowerPointExporter` since Batch 017)
to `LessonPlanRenderer`'s lesson-plan and differentiation-guide HTML, and add the richer
sections the plan's Implementation Sequence describes.

| # | Step | Result |
|---|------|--------|
| 1 | Read `OUTPUT_ENRICHMENT_PLAN.md` in full | Confirmed items 1-3 of "First Coding Pass" already done (Batch 017); item 4 (apply the helper to the two HTML renderers) was the next concrete, well-scoped step — not the more speculative Implementation Sequence #1 ("deterministic lesson enrichment layer" that improves extraction quality itself) |
| 2 | Read `LessonPlanRenderer.swift`, `LessonOutputContent.swift`, and `LessonRecord`'s full model shape before writing any code | Found a real bug-in-waiting: `LessonOutputContent`'s constructor bakes in student-facing fallback text for empty fields (e.g. `"Explore the teacher-reviewed learning objective."` for a blank objective) — appropriate for a slide a student might see, but would misrepresent a genuinely unreviewed field as real content if used naively in a teacher-facing review document, directly violating the plan's own stated rule: "Keep unknown fields visibly blank or 'not specified' rather than pretending certainty." |
| 3 | Also found: `LessonRecord.differentiationSummary` is a single free-text field — no separate `accessSupport`/`language`/`extension`/`grouping` fields exist. The plan's Implementation Sequence #4 asks to "separate supports by practical classroom use" into 4 categories, but doing that honestly would require new `LessonRecord` fields plus corresponding editing UI — a real data-model/product decision, not something to fake by parsing free text into categories | Scoped this batch to NOT invent that structure; flagged it explicitly as a future decision instead |
| 4 | Design decision: use `LessonOutputContent` for its genuinely reusable formatting logic (blank-filtering on `materials`/`steps`, consistent trimming) but keep every "is this field specified?" check against the RAW `LessonRecord` field, never against `LessonOutputContent`'s (always-non-empty, fallback-injected) properties | The key correctness decision of this batch |
| 5 | Rewrote `renderHTML(for lesson:)`: switched `Instructional sequence`/`Materials`/`Source provenance` to iterate `LessonOutputContent`'s cleaned `steps`/`materials`/`sourceReferences` (fixes a latent bug — a step with a blank title AND blank notes used to render an empty `<li><strong></strong></li>`, now correctly skipped); added a new "lesson snapshot" quick-stats strip (instructional step / material / source counts) right after the header, the one genuinely new section the plan calls for that wasn't already present and needs no new data | |
| 6 | Rewrote `renderDifferentiationGuideHTML(for lesson:)`: switched materials to the same cleaned list; added grade to the header subtitle (previously subject-only); added a one-line explanatory hint under "Teacher differentiation notes" framing what belongs there (access/support, language/vocabulary, extension/challenge, small-group/partner structures) without splitting into fake sub-boxes | Delivers the plan's intent honestly given the real data shape |
| 7 | `swift build -Xswiftc -gnone` | Compiled clean |
| 8 | Ran the 2 pre-existing renderer tests unchanged | Both passed — confirms the refactor didn't alter escaping or the printable-prompt behavior |
| 9 | Added 6 new tests: snapshot-counts, empty-step-skipping, honest "Not specified" behavior for both renderers (asserts `LessonOutputContent`'s fallback strings never leak into the output — directly tests the step-4 design decision), differentiation subtitle/hint text, and blank-materials-entry filtering | |
| 10 | `swift test -Xswiftc -gnone` | 126/126 passed (120 baseline + 6 new) |
| 11 | Added a temporary visual-QA-only test writing 4 realistic HTML samples (populated lesson-plan, populated differentiation-guide, and a blank-everything version of each) to the scratchpad | Ran via `swift test --filter` |
| 12 | Rendered all 4 samples to full-page screenshots via headless Chrome (`google chrome --headless --screenshot`) rather than computer-use, since the in-app Browser preview pane doesn't support local `file://` URLs interactively and the owner's earlier no-screen-control constraint didn't need to be revisited for this — though the owner did separately confirm mid-batch that their Zoom call had ended | Produced 4 PNGs, read and visually reviewed each |
| 13 | Visual QA: confirmed the populated samples render cleanly (snapshot strip, sections, hint caption all look right) and — critically — confirmed the blank-everything samples show "Not specified" / "No materials listed." / "No differentiation notes have been entered yet." throughout, with correct punctuation when subject/grade are both absent (no dangling "·" separator) | No fabricated-looking content anywhere in either state |
| 14 | Removed the temporary visual-QA test | `git diff` on the test file now shows only the 6 permanent tests from step 9 |
| 15 | `swift test -Xswiftc -gnone` and real `xcodebuild` again after removing the temp test | 126/126 passed; BUILD SUCCEEDED |
| 16 | Updated `OUTPUT_ENRICHMENT_PLAN.md` to mark "First Coding Pass" item 4 done, with the fallback-text and differentiation-category scoping decisions recorded there too | |
| 17 | Updated `CONTINUITY_LOG.md` (this entry) | |

**Outcome.** The lesson-plan and differentiation-guide HTML outputs are now genuinely more
useful without fabricating certainty the app doesn't have: a real bug (empty step bullets) is
fixed, a new at-a-glance snapshot exists, and every blank field still honestly reads as
"not specified" rather than silently picking up `LessonOutputContent`'s student-facing
placeholder text. Verified visually via real rendered screenshots, not just string assertions.

**Dead ends / notes.**

- The in-app Browser preview pane (`mcp__Claude_Browser__*`) rendered a local `file://` URL
  only as a static, non-interactive snapshot (no scrolling, no `get_page_text`/`screenshot`
  support against it) — not useful for reviewing a tall document. The Claude-in-Chrome
  extension also rejected the `file://` scheme outright (mangled it into an invalid
  `https://file:///...` URL and hit an error page). `google chrome --headless --screenshot
  --window-size=W,H "file://...*"` via Bash was the reliable fallback for a full-page capture
  of a local HTML file, and is worth reaching for again for any future local-HTML visual QA.
- Computer-use (Safari, tier "read") DID work for a quick top-of-page look, but can't scroll
  without interaction access — fine for a fast sanity check, not for reviewing an entire tall
  document. Headless Chrome was strictly better here once discovered.
- Deliberately did NOT touch `LessonOutputContent.swift` itself (its fallback text is
  correct and proven for its existing PPTX-exporter consumer) — the fix belongs in how the
  HTML renderers *use* it, not in the shared view model itself. Worth remembering for any
  future output-format work: `LessonOutputContent`'s properties are pre-filled with
  presentation-ready (non-blank) text by design; a consumer that needs to distinguish
  "genuinely blank" from "has content" must check the source `LessonRecord` field directly.

**Still open.**

1. Implementation Sequence #1 from `OUTPUT_ENRICHMENT_PLAN.md` — a deterministic content
   enrichment layer that improves sparse EXTRACTED `LessonRecord` fields from source text
   (this batch only improved rendering of whatever a record already has). Likely the biggest
   remaining lever for genuinely richer output, and a bigger, more speculative piece of work.
2. A true category-split differentiation guide (access/support, language, extension,
   small-group, as separate structured sections) needs new `LessonRecord` fields plus
   corresponding editing UI — a real product/data-model decision for the owner, not made
   unilaterally this batch.
3. GitHub sync — push this batch's commit.
4. Everything still open from Batch 027 (Placeholder-assignments UI visual verification,
   slide duplication/reordering, `GeneratedOutputRecord` provenance distinction).

### Batch 029 — 2026-07-29 — Fix the real "only the title populates" extraction bug

**Compute:** medium. **Model shape:** Claude-native — diagnosis-heavy, and the fix turned out
to be small once the actual cause was found.

**Goal.** The owner reported that importing a source produced a lesson with only the title
filled in, describing it as "a massive problem in this project." Earlier in the same session I
had told them the enrichment layer was "not started" — that was wrong, and worth recording as
a process failure: I had described a roadmap item from the plan document without first checking
whether it existed in the code. It did.

| # | Step | Result |
|---|------|--------|
| 1 | Before scoping anything, traced how a `LessonRecord` is actually created from a source | Found `LessonFieldExtractor` (in `AppStore.swift`) already existed — a deterministic label-based extractor, wired to a "Fill empty fields from labeled source text" button in the lesson editor, with a passing test |
| 2 | Asked the owner what the failure actually looked like rather than guessing further | Answer: "extracts title only sometimes… looks like it's extracting plain text in a giant bundle but only the title populates" — pointing at something upstream of the extractor's parsing quality |
| 3 | Traced every `createDraftLesson` call site in the UI | **Found the real bug**: the primary "Create draft lesson from source" button calls `createDraftLesson(from:title:objective:)`, which never called the extractor at all — it set only the title plus whatever the teacher typed into an objective field that starts blank. The extractor was only reachable from a *different* button on a *different* screen (the lesson editor), which a teacher reaches only after the title-only draft already exists and has no reason to know they must press |
| 4 | Fixed the primary path: `createDraftLesson(from:title:objective:)` now runs extraction and pre-fills every field the source supports; a typed title/objective still wins over an extracted value | |
| 5 | Improved the extractor itself for real document shapes: multi-line values under a heading (previously only the same line or literally the next line — an objective spanning two lines was silently truncated), bulleted/numbered lists where an item may itself contain a comma, more label synonyms, and markdown headings (`## Materials`, `**Grade Level:**`) | |
| 6 | Fixed a genuine matching bug found while adding whole-label boundary checking: the label "goal" previously matched any line *starting* with it, so "Goals for this unit are described in the pacing guide." was captured as the learning objective | Regression test added |
| 7 | Added warnings naming which fields the source didn't support, so a half-filled draft explains itself rather than looking broken | |
| 8 | **Probed against realistic curriculum prose** (a teacher-edition page with "Warm-Up (5 min)" headings and running paragraphs, no `Objective:` labels) to check whether the improvements actually helped in the real case | Extracted **nothing** — confirming the honest ceiling of a label-only approach, and that steps 4-7 alone would not have solved the owner's problem for documents of that shape |
| 9 | Reported that ceiling to the owner plainly rather than declaring the bug fixed, and offered three paths (inspect a real failing document first / structural heuristics / promote the AI path) | Owner chose structural heuristics |
| 10 | Built `LessonStructureInferencer` (new file) — a clearly separated second pass that recognizes: timed phase headings ("Warm-Up (5 min)") and conventional phase names (gradual-release, 5E, workshop) as instructional steps *with body text as notes*; conventional objective phrasing ("Students will…", "SWBAT", "I can…"); and CCSS-math / CCSS-ELA / NGSS standards codes to infer subject and grade | |
| 11 | Kept the existing no-inference promise intact: `extract(from:)` is unchanged and still label-only (the lesson-editor button's tooltip explicitly promises "It does not infer missing content"), with inference available only via a new `extractWithStructuralInference(from:)` used by draft creation | |
| 12 | Made inference honest rather than invisible: `Result.inferredFields` records every heuristically-filled field, and the warnings now distinguish "inferred from structure — check these" from "not found — left blank" | The key design decision; an inferred objective must not be indistinguishable from a stated one |
| 13 | Re-probed the same realistic page | Now extracts subject (Math), grade (Grade 5), objective, assessment, and 3 instructional steps with full multi-paragraph body notes — all correctly flagged as inferred |
| 14 | Added 5 structural-inference tests including two guard tests: labels always beat heuristics, and ordinary prose is never mistaken for a phase heading | |
| 15 | Registered the new file in `project.pbxproj` (4-entry pattern) | |
| 16 | `swift test -Xswiftc -gnone`; real `xcodebuild` | 138/138 passed; BUILD SUCCEEDED, with the new file confirmed compiling in the app target |

**Outcome.** The reported bug is fixed at its actual root (the primary draft path never called
the extractor), and the extractor is now capable enough to populate a realistic teacher-edition
page that previously yielded nothing — while still never presenting a guess as though the
document stated it.

**Dead ends / notes.**

- **Process lesson worth keeping:** I described `OUTPUT_ENRICHMENT_PLAN.md`'s "Implementation
  Sequence #1" as "not started" based on the plan document alone, without grepping for it.
  `LessonFieldExtractor` had existed for many batches. Check the code before reporting the
  status of a roadmap item — the plan is a statement of intent, not a record of what shipped.
- Asking the owner what the failure *looked like* (rather than inferring from the code) is what
  located the bug: "only the title populates" is the signature of a call site that doesn't call
  the extractor, not of an extractor that parses badly. Two very different fixes.
- Probing against realistic messy text before declaring victory is what surfaced the honest
  ceiling of steps 4-7. A tidy test fixture would have shown green and hidden the real gap.
- `phaseHeadingTitle` treats a duration annotation ("(12 min)") as sufficient evidence on its
  own, so an unrecognized phase name still parses. The known-name list is a fallback for
  headings without durations, not the primary signal.

**Still open.**

1. **The inferencer is unvalidated against the owner's actual curriculum PDFs.** It's tested
   against realistic synthetic text, but the highest-value next step is running it on one real
   failing document and tuning from what that shows. Worth asking for one.
2. Materials and differentiation are still label-only — no structural inference. Materials in
   real teacher editions often appear as an unlabeled sidebar list, which needs a positional/
   layout signal the current plain-text pipeline doesn't preserve.
3. GitHub sync — push this batch's commit.
4. Everything still open from Batches 027-028.

### Batch 030 — 2026-07-29 — Regression fix: schema change made saved workspaces unreadable

**Compute:** medium. **Model shape:** Claude-native — urgent diagnosis of a self-inflicted bug.

**Goal.** The owner launched the app and got "The data couldn't be read because it is missing"
with the setup wizard, as though their workspace had been erased. This was a regression I
introduced in Batch 025.

| # | Step | Result |
|---|------|--------|
| 1 | Located the app's real data on disk before touching anything | All files present and intact — nothing had actually been deleted |
| 2 | Inspected the active profile's `configuration.json` | Its saved `layoutPlan` had keys `fidelityReviewCompleted, frameMap, slideInventory, updatedAt` — no `placeholderAssignments` |
| 3 | **Root cause**: Batch 025 added `placeholderAssignments` to `PresentationTemplateLayoutPlan` as a non-optional property. Swift's *synthesized* decoder treats a missing key as a hard failure (a property default does NOT satisfy it), so every layout plan written before Batch 025 became undecodable → `AppConfiguration` failed → `configuration == nil` → setup wizard | The Batch 024 session had registered the Sunrise template with the pre-025 binary, writing exactly such a file |
| 4 | Audited every Codable model change since the last known-good commit | Exactly one problematic addition; the new nested struct was fine |
| 5 | Added an explicit `init(from:)` to `PresentationTemplateLayoutPlan` using `decodeIfPresent` for the new field, plus an explicit memberwise init (a custom init in the struct body suppresses synthesis) | |
| 6 | Added two regression tests: decoding the exact legacy JSON shape, and a full encode/decode round trip | |
| 7 | Verified against the owner's REAL files, not just fixtures — compiled a throwaway harness that decoded every `configuration.json` under Application Support with the fixed model | Initially reported a failure that turned out to be my harness missing the repository's `.iso8601` date strategy; re-ran correctly → the real file decodes, `assignments=0 inventory=2` |
| 8 | Rebuilt and relaunched | App opens straight into the workspace, no error |
| 9 | **Followed the failure one step further**: `load` returns nil only when a file is *absent*; a decode failure throws, leaves `configuration == nil`, and renders `SetupWizardView` — whose "Create workspace" calls `saveConfiguration`, **overwriting the intact-but-unreadable file**. My bug was one click away from real data loss | The genuinely dangerous part, and not something the owner had asked about |
| 10 | Added `hasStoredConfiguration()` to the repository protocol and `AppStore.configurationIsUnreadable` to distinguish "never set up" from "exists but unreadable" | |
| 11 | Added `WorkspaceRecoveryView`, shown ahead of the setup-wizard branch: states plainly that nothing was lost, shows the error and the exact data folder, offers only non-destructive actions ("Try again", "Reveal in Finder"), and explicitly says creating a new workspace is unavailable here and why | |
| 12 | Added 3 tests: unreadable config is not a fresh install, a genuinely missing file still is, and "Try again" recovers once the file is readable | |
| 13 | Added a `LESSONPLANNER_DATA_ROOT` env override (matching the existing `LESSONPLANNER_INITIAL_TAB` convention) so data-state behavior can be exercised against throwaway fixtures | Otherwise the only way to see the recovery screen would have been damaging the owner's real data |
| 14 | Verified the recovery screen visually against a synthetic corrupted data root, then deleted the fixture and relaunched on real data | Both states confirmed correct by screenshot |
| 15 | `swift test`; real `xcodebuild` | 143/143 passed; BUILD SUCCEEDED |

**Outcome.** The reported error is fixed, existing saved workspaces load again, and the failure
mode that made it dangerous — an unreadable workspace presenting as a fresh install — can no
longer destroy data.

**Dead ends / notes.**

- **The rule this batch exists to prevent:** adding a non-optional field to any persisted
  Codable model silently breaks every previously-saved file. A property default (`= []`) does
  NOT satisfy the synthesized decoder. Every future field added to a persisted model needs
  `decodeIfPresent` in an explicit `init(from:)`, and a test decoding the pre-change JSON shape.
- Verifying against a hand-written fixture would have passed while the owner's real file still
  failed. Decoding the actual on-disk files is what proved the fix. Note the harness must
  replicate `LocalRepository`'s `.iso8601` date strategy or it produces a misleading failure.
- Batch 025 ran `swift test` and a real `xcodebuild` and both passed — neither catches a
  persistence-compatibility break, because tests build their own fresh data. Only launching the
  app against pre-existing data would have caught it, and that batch deliberately skipped
  launching (no-screen-control constraint). Worth relaunching the app after any persisted-model
  change even when the batch otherwise needs no visual check.

**Still open.**

1. Push this batch's commit.
2. Everything still open from Batches 027-029, including validating the new extraction
   inferencer against a real curriculum PDF.

### NEXT SESSION PLAN (written 2026-07-29 end of day) — content scatters across non-matching blocks

**Reported by the owner.** A daily-schedule document populated the weekly planner perfectly.
Then math curriculum documents were imported and scattered across the week: lessons landed in
the English Language Arts block and in time slots that are not blocks at all, instead of going
only into Math blocks and leaving every other block untouched.

**Desired behavior (owner's words):** lessons should only go into Math blocks; every other
block stays as an unaltered placeholder.

**Diagnosis — done, grounded in the owner's real saved data, not guessed from the screenshot.**
(Inspected locally only; no curriculum content copied into the repo.)

Findings from the affected profile's `lesson-records.json` / `weekly-plans/*.json`:

1. **173 lesson records were created from the math import, and they are fragments, not
   lessons.** Titles are either generic (`Lesson 1`, `Lesson 2`, `Lesson 1 Name`,
   `Lesson 1—1 Day`) or mid-sentence text captured from the PDF (`days`, `day. How much does
   the account receive`, `LESSON FOCUS AND COHERENCE`, `Lesson Materials: two-color counters,
   square t…`). This is the same defect the owner described earlier as "extracting plain text
   in a giant bundle but only the title populates."
2. **`subject` is empty on all 173 records.** Nothing in the import path ever fills it, so the
   single strongest signal for choosing a schedule block is absent before matching even runs.
3. **`bestScheduleBlock` (AppStore.swift ~1078) therefore has nothing reliable to match on.**
   Its title-based pass sees generic/garbage text. Its fallback then scores the *entire source
   document's* text — which is identical for every fragment from that document, and a math
   document legitimately contains ELA-ish vocabulary ("write an equation", "read the problem"),
   so it can and does score English over Math.
4. **The real damage is the no-match path.** `scheduledTimeRange` (AppStore.swift ~1019) falls
   back to a hard-coded 9:00 AM start with a 45-minute duration when no block matches. 9:00 AM
   is not one of the teacher's blocks, so unmatched content is invented into slots that do not
   exist in their schedule. `firstAvailableSchedulePlacement` then spreads collisions across
   other days, which is what produces the scatter across the whole week.
5. Only 24 of the 173 records were actually placed, so the current behavior is also silently
   dropping most of what it created, with no report to the teacher.

**Plan, in dependency order. Do not start at step 3 — steps 1-2 are what make matching possible.**

1. **Stop placing content that has no confident subject match.** Smallest change with the
   biggest correctness win, and it directly delivers the owner's stated requirement. Replace
   the 9:00 AM fallback in `scheduledTimeRange` with "return no placement," have the caller skip
   the suggestion, and surface a count of what was not placed and why. A block the app is not
   sure about must stay an untouched placeholder — never a guess. Add tests: content with no
   subject signal places nothing and leaves all blocks empty; content with a clear Math signal
   fills only Math blocks.
2. **Populate `subject` during import.** Infer it once per source document (filename plus
   document text) and stamp it on every lesson proposed from that document, rather than
   re-deriving it per fragment at scheduling time. Then match on the record's own `subject`
   first and treat title/body text as a fallback, which is the inverse of today's order. Add a
   test that a math source yields records with `subject == "Math"`.
3. **Fix segmentation so one lesson means one lesson.** 173 fragments from a handful of
   documents is the underlying defect; steps 1-2 stop it from corrupting the planner but do not
   fix it. Requires deciding what actually delimits a lesson in a real teacher-edition PDF
   (module/lesson headings, page structure) and rejecting candidates that are clearly not
   lessons (a bare `days`, a sentence fragment, a materials list). Expect this to be the
   largest piece and to need real curriculum PDFs to validate against.
4. **Report the outcome of an import to the teacher.** "24 of 173 proposed lessons were
   scheduled" must be visible, not silent. Also surface why the rest were skipped.

**Verification requirements for this work, learned the hard way this session:**

- Test against the owner's real curriculum documents locally, not just tidy fixtures. A
  hand-written fixture will pass while the real import still fails — that is exactly how the
  earlier extraction work looked correct while being wrong in practice.
- Relaunch the app and re-import against a throwaway profile (or `LESSONPLANNER_DATA_ROOT`)
  before declaring any of this fixed. Unit tests do not exercise the real import path end to
  end.
- Never commit curriculum filenames, module names, or extracted text.

#### PLAN REVISION (same day, after an owner question) — add a document-level "is this even a lesson?" gate

The owner asked whether the app should decide *whether a fed document is a lesson at all*
before anything gets placed, noting the imported folder held both lessons and non-lessons.
Investigated, and this is not a refinement — it is the largest single cause of the scatter and
it belongs ahead of the other steps.

**Evidence from the owner's real import (inspected locally; no curriculum content copied here):**

- 316 documents were imported. **315 were classified `lessonMaterial`; exactly 1 was anything
  else.** The classifier effectively has one output for curriculum content.
- Why: `ImportedSourceRole.infer` (AppModels.swift) reaches `.lessonMaterial` on a plain
  substring hit for any of `lesson`, `worksheet`, `student handout`, `teacher guide`,
  `activity`, `practice`, tested against the filename plus the first 2,000 characters. In a real
  curriculum folder essentially every artifact contains the word "lesson" — an answer key says
  "Lesson 5 Answer Key", a family letter says "in this lesson", a test says "Lessons 1-5". So
  everything matches, and `.other` is effectively unreachable.
- The folder's actual composition, by generic artifact type: teacher-edition pages, student-
  edition pages, challenge/enrichment sheets, practice/homework pages, reteach/intervention
  sheets, and one planning document. **Most of these are supporting materials, not teachable
  lessons.**

**The deeper modeling error this exposes.** The app currently treats "lesson material" as "a
lesson," so every worksheet, practice page, and challenge sheet becomes its own schedulable
lesson record. That is where 173 fragment lessons came from. A practice page is *material for* a
lesson; it should attach to one, not become one. The existing role enum answers "what kind of
setup document is this?" — a question designed for sorting planning documents (pacing guide vs.
calendar vs. map). It was never designed to answer "is this a teachable lesson, or an artifact
that supports one?" Those are different questions and need different fields.

**Revised step order. This becomes the new step 1; the previously written steps shift down.**

1. **Add a placement-eligibility classification, separate from `ImportedSourceRole`.** At
   minimum three outcomes:
   - *Placeable lesson* — has the shape of a teachable lesson (an objective and/or an
     instructional sequence). Only these may ever be scheduled.
   - *Supporting material* — worksheet, practice page, answer key, challenge/reteach sheet,
     assessment. Must attach to a lesson (or simply be available), never occupy a block.
   - *Planning document* — pacing/calendar/map, which the existing role inference already
     handles well and should keep handling.
   - *Unknown* — never placed; surfaced to the teacher for a decision.
   Classify on document structure, not just keyword presence, and require positive evidence of
   lesson shape before granting *placeable lesson*. Bias toward "not a lesson," because a
   missed lesson is a teacher noticing an empty block, whereas a false positive corrupts the
   planner — which is the failure the owner actually hit.
2. **Only *placeable lesson* documents may propose lessons.** This alone should collapse the
   173 fragments to something near the real lesson count, and it makes the subject-matching and
   segmentation work far easier because they stop being fed answer keys and practice pages.
3. Stop placing content that has no confident subject match (previously step 1). Still needed:
   a genuine lesson whose subject is unclear must leave the block untouched.
4. Populate `subject` at import time (previously step 2).
5. Fix segmentation so one lesson means one lesson (previously step 3) — smaller in scope once
   steps 1-2 stop feeding it non-lessons, but still real.
6. Report import outcomes to the teacher (previously step 4), now including counts per
   classification: how many placeable lessons, how many materials, how many unknown.

**Open question — ANSWERED by the owner the same day.** Supporting materials should feed the
differentiation guide for their corresponding lesson, and be cached so they can be placed into
that lesson's printable resources. The full design scaffold is in OUTPUT_ENRICHMENT_PLAN.md
under "Design scaffold: supporting materials feed the differentiation guide and printable
resources" — including the artifact-type-to-differentiation-role mapping, a proposed
`LessonMaterialAttachment` model, what printable machinery already exists (the differentiation
guide's print-aware practice section is the seed), and one IP decision the owner still needs to
make: whether printables *cite* the publisher's pages (safer default, assumed) or *embed* their
content. That work depends on this classification gate landing first, because the gate is what
identifies a document as supporting material and produces the signal the role mapping reuses.

### Batch 031 — 2026-07-29 — Placement-eligibility classifier (approved plan, step 1)

**Compute:** medium-high. **Model shape:** Claude-native. Owner approved the routing design
("lets go with your suggestion here"), so this is step 1 of that plan.

| # | Step | Result |
|---|------|--------|
| 1 | Marked the routing design APPROVED in OUTPUT_ENRICHMENT_PLAN.md | No longer a proposal |
| 2 | Found that Batch 029's `LessonStructureInferencer` already detects lesson shape (objective, timed phases, standards codes) | Composed the gate from it rather than duplicating the logic, so the gate and the lesson editor can never disagree about what a lesson looks like |
| 3 | New `DocumentPlacementClassifier.swift`: `LessonPlacementEligibility` (placeableLesson / supportingMaterial / planningDocument / inert), `DifferentiationRole`, `DocumentLessonKey`, and a classifier returning eligibility + role + attachment key + a plain-language rationale | Only `.placeableLesson` answers true to `canOccupyScheduleBlock` |
| 4 | Ordered the classifier to encode the bias deliberately: planning phrase → unreadable → **filename artifact marker → lesson shape → body artifact marker** → inert. Filename markers outrank lesson shape (a reteach sheet may well say "Students will…"); body markers rank below it (a real lesson legitimately contains "Practice" as a heading) | |
| 5 | Added `placementEligibility` / `differentiationRole` / `lessonKey` to `ImportedSource` as **Optionals**, so old files decode via `decodeIfPresent`, plus `effectivePlacementEligibility` that classifies on demand and `canProposeScheduledLesson` as the single gate | Follows the CRITICAL PERSISTENCE RULE from Batch 030 |
| 6 | Measured against the owner's real 316-document import via a temporary probe | First pass: 154 of 316 classified `inert` |
| 7 | **Sampled the inert bucket instead of accepting the number.** They were not junk — they were small-group option pages, exit tickets, and warm-up problems, i.e. the highest-value differentiation material in the folder. The body-marker list was far too narrow | The single most valuable check in this batch |
| 8 | Broadened body markers to generic pedagogical section names (small-group options, exit ticket, problem of the day, guided/independent practice, ready for more, on track, vocabulary cards, family letter, video tutorials) | Same class of generic domain vocabulary `ImportedSourceRole.infer` already keys on; no publisher-proprietary content |
| 9 | Wrote 15 tests using only hand-written generic fixtures | |
| 10 | **A test failure exposed a real pre-existing bug**, rather than a bad fixture: a lesson fixture mentioning "benchmark fractions" was classified `planningDocument`, because `ImportedSourceRole.infer` matches the bare substring "benchmark" (also "holiday", "break"). An ordinary math lesson was being diverted out of the planner entirely | |
| 11 | Fixed the cause, not the fixture: this classifier now requires a specific multi-word planning phrase instead of delegating to `infer`. Left `infer` itself alone — it is load bearing for the existing pacing pathway and deserves its own change with its own verification | Documented in-code |
| 12 | Re-measured on real data | See outcome |
| 13 | Removed the probe; registered the new file in `project.pbxproj` (4-entry pattern) | |
| 14 | `swift test`; real `xcodebuild` | 158/158 passed; BUILD SUCCEEDED |

**Outcome, measured on the owner's real 316-document import:**

| Eligibility | Count | Share |
|---|---|---|
| supportingMaterial | 174 | 55% |
| placeableLesson | **82** | 26% |
| inert | 54 | 17% |
| planningDocument | 6 | 2% |

Differentiation roles found: 76 support, 52 practice, 24 extension/challenge, 22 assessment.
Attachment key resolved for 143/316 (45%).

**82 documents are now schedulable, where previously all 316 were** — 315 classified
`lessonMaterial` and every one became a lesson candidate, which is what produced 173 fragment
lessons scattered across the week. The mechanism to prevent that now exists and is measured.

**IMPORTANT — the reported bug is NOT yet fixed in the running app.** This batch built and
validated the gate; nothing yet consults it. `syncReadableDocumentsIntoWeeklyPlanner` still
proposes lessons from every readable source. Wiring `canProposeScheduledLesson` into that path is
the next increment, and it is a behavioral change that must be verified by relaunching the app
and re-importing against a throwaway profile — not by unit tests alone, which is exactly the gap
that let Batch 025's regression reach the owner.

**Dead ends / notes.**

- Trusting the first measured distribution would have shipped a classifier that discarded the
  best differentiation material in the folder as "inert." Sampling a bucket beats counting it.
- The 316 "documents" are per-page PDF extracts, not whole lessons. This reframes the
  segmentation step still open in the plan: the task is **grouping** many small files into the
  lesson they belong to (via `lessonKey`), not splitting large ones. Worth correcting in the plan.

**Still open.**

1. Wire the gate into lesson proposal, then verify by real re-import. This is what fixes the bug.
2. Populate `subject` at import — `LessonStructureInferencer` already recovers it from standards
   codes, so this is now nearly free.
3. `ImportedSourceRole.infer` substring over-matching ("benchmark", "holiday", "break") — its own
   change, with its own verification.
4. `LessonMaterialAttachment` + printable pack, per OUTPUT_ENRICHMENT_PLAN.md.

### Batch 032 — 2026-07-29 — Attempted to wire the gate; stopped deliberately, kept the classifier

**Outcome: the reported scatter bug is still NOT fixed.** This batch attempted step 2 (wiring the
gate into lesson proposal), hit a genuine design conflict, and stopped rather than force it.

**What was attempted.** Two changes: filter pacing-plan sources on the placement gate instead of
`effectiveSetupRole == .lessonMaterial`, and make `scheduledTimeRange` return nil instead of
falling back to a hard-coded 9:00 AM slot, so an unmatched lesson is skipped and its block is left
untouched. Both compiled and both are clearly right in principle.

**Why it did not converge.** Existing tests began failing in a rotating set as thresholds moved:

- A weekly content packet ("Monday: Place value review") is neither a lesson page nor supporting
  material. The classifier had no category for it and binned it `inert`, which would have disabled
  the app's primary content-import path. Fixed properly by adding a `lessonSequence` category.
- A scope-and-sequence classifies as `planningDocument`, yet it is *the* canonical lesson list.
  Fixed by expressing sequence-contribution as an exclusion (`!supportingMaterial && !inert`)
  rather than an allowlist.
- Then the Batch 022 content-import tests failed: their fixtures are terse two-lesson packets with
  no objective and fewer entries than the `lessonSequence` detector's minimum, so they fall to
  `inert` and yield nothing.

At that point each threshold change was fixing some fixtures and breaking others — fixture
chasing, which is the exact failure mode called out earlier in this session. Continuing would have
tuned the classifier to the test suite rather than to reality.

**Decision.** Reverted the behavioral wiring (`AppStore.swift`, `AppModels.swift`) and kept the
classifier improvements, which are additive and consulted by nothing yet. Full suite green at
160/160. `main` is left in a working state with no half-tuned gate.

**The real blocker, which is a product decision and not a coding problem.** How strict should
"this is a lesson" be? Two defensible answers, and they conflict:

- **Strict** (what this batch built): require an objective or a multi-phase sequence. Correct for
  real teacher-edition pages, and it is what keeps 174 worksheets out of the planner. But it
  rejects terse lesson lists, which the app's existing content lane depends on.
- **Permissive**: accept any document that yields plausible lesson titles. Preserves today's
  import path but readmits much of what caused the scatter.

Probable resolution, for the owner to confirm: keep the strict bar for whether a document may
*itself* occupy a block, and treat "yields lesson titles" as a separate, more permissive test for
whether it may *contribute a sequence*. The two concepts are already separated in code
(`canOccupyScheduleBlock` vs `canContributeLessonSequence`); what is unresolved is how permissive
the second should be, and that determines whether the Batch 022 fixtures represent behavior worth
preserving or behavior that was always wrong.

**Also worth noting:** the Batch 022 fixtures encode the assumption that a two-line content packet
should produce scheduled lessons. Whether that is correct is precisely the open question. Do not
delete or weaken those tests to make a gate pass — decide the rule first, then update them
deliberately with a recorded reason.

**Still open.** Unchanged from Batch 031, plus the strictness decision above, which blocks step 2.

### Batch 033 — 2026-07-29 — Strict placement (Codex-reviewed); the scatter bug is fixed

**Compute:** high. **Model shape:** Claude-native implementation + **Codex design review**, at the
owner's request, after this batch's first two attempts failed to converge.

**Owner's decision:** strict. A high bar for occupying a block, with a separate, more permissive
test for contributing a lesson sequence.

**What Codex caught that three of my own attempts had missed.** I had made `scheduledTimeRange`
return nil unconditionally when no block matched. Codex's decisive observation:

> "The bad behavior is not 'default 9:00 exists'; it is 'default 9:00 overrides a real teacher
> schedule.'"

Every fixture that flipped had **no imported schedule** and legitimately relied on the 9:00 AM
default. My rule broke them because it was unconditional. The correct rule is conditional: return
nil only when the teacher *has* imported schedule blocks and none of them match. Codex also
correctly judged all five flipping tests as encoding behavior worth preserving, not stale
behavior — which is why weakening them would have been wrong.

**What shipped.**

1. `scheduledTimeRange` returns `(start, end)?`. Nil when imported schedule blocks exist and none
   confidently match; the 9:00 AM default is retained only when no schedule has been imported at
   all, where there is nothing to contradict.
2. The caller skips a nil placement and counts it, so unmatched lessons leave their blocks as
   untouched placeholders — the owner's stated requirement.
3. `AutoPlacementSummary` on `AppStore` reports placed and unplaced counts. Silence was its own
   defect: an import once created 173 records, placed 24, and reported neither number.

**What was deliberately NOT shipped, and why.** Filtering pacing sources through the placement
classifier (`canContributeLessonSequence`) was implemented and reverted twice. It is
simultaneously too strict — a valid 75-character weekly packet fell under the classifier's
120-character minimum-text floor before the lesson-list check ran — and too permissive, since
planning documents began contributing lessons they previously did not. Tuning it to fit the
fixtures produced a rotating set of failures across three attempts. Per Codex, the hard safety
guarantee belongs at placement, which is where the scatter actually occurred, so the prefilter is
left on `setupRole` with an in-code note. Revisit it as its own change, verified against real
imported documents rather than fixtures.

**Verification.** 162/162 tests passed (160 + 2 new placement-guarantee tests, in a separate
`StrictPlacementTests` suite). Real `xcodebuild` succeeded. The new tests assert both halves of the
rule: with a real schedule, nothing may be placed at the invented 9:00 AM default and every
placement must land in one of the teacher's own blocks; with no schedule imported, default
placement still works.

**Dead ends / notes.**

- Three self-directed attempts at this converged on nothing; one外部 review found the flaw in
  minutes. The tell was rotating fixture failures — when the same change fixes some tests and
  breaks others across several iterations, the design is wrong, not the constants. Escalate at
  the second oscillation, not the fourth.
- Codex's other recommendation, not yet acted on: `CoursePacingPlan.starter(from:)` manufactures a
  placeholder lesson for every readable source with no extractable lesson titles. That is the
  upstream source of the 173 fragments, and no document-level gate can fully compensate for it.
  This is likely the highest-value next change.

**Still open.**

1. **Verify against the owner's real re-import.** Unit tests do not exercise the real import path;
   this must be confirmed by re-importing the real curriculum folder against a throwaway profile
   (`LESSONPLANNER_DATA_ROOT`) before the bug is called closed.
2. `CoursePacingPlan.starter` placeholder manufacturing (above).
3. Revisit the classifier prefilter as its own verified change.
4. Surface `AutoPlacementSummary` in the UI — it is populated but not yet displayed.
5. Everything else still open from Batches 031-032.

### PLAN REVISION 2 (2026-07-29, end of session) — supersedes the earlier ordering

Three things changed during Batches 031-033 that invalidate the original step order.

**1. The placement guarantee, not classification, is what fixed the scatter.** The original plan
made document classification step 1, on the theory that keeping non-lessons out of the candidate
pool was the fix. It was not. The fix was refusing to place a lesson that does not match a real
schedule block (Batch 033). Classification turned out to be neither necessary nor sufficient for
that.

**2. The classifier is currently inert in production.** `DocumentPlacementClassifier` and the
`ImportedSource` fields are referenced only inside `AppModels.swift`. After the prefilter was
reverted, no production path consults them. This is shipped, tested, measured code doing nothing.
That is acceptable — it was built for a purpose that moved — but it must not be mistaken for
working machinery. Its real value now sits in the differentiation pathway (`DifferentiationRole`,
`DocumentLessonKey`), not in gating the planner.

**3. Codex identified the actual upstream cause of the 173 fragments**, which no document-level
gate can fully compensate for: `CoursePacingPlan.starter(from:)` creates a unit/module for every
readable source and manufactures a placeholder lesson when it finds no lesson titles. That is the
fragment factory. This was not in the original plan at all.

**Revised order.**

1. **Verify Batch 033 against a real re-import.** Nothing else should start first. Re-import the
   real curriculum folder against a throwaway data root (`LESSONPLANNER_DATA_ROOT`) and compare
   the resulting weekly planner against the reported failure. If the scatter persists, every
   priority below is wrong and the diagnosis needs revisiting. This is the single highest-value
   action remaining and it is cheap.
2. **Stop `CoursePacingPlan.starter` manufacturing placeholder lessons** from sources with no
   extractable lesson titles, at least on the automatic content-import path. Per Codex, this is
   the highest-value code change left. Expect it to reduce 173 records substantially on its own.
3. **Populate `subject` at import.** `LessonStructureInferencer` already recovers subject and
   grade from standards codes, so this is close to free, and it strengthens block matching so
   fewer genuine lessons end up unplaced by the new strict rule.
4. **Surface `AutoPlacementSummary` in the UI.** Already populated by Batch 033, displayed
   nowhere. Small, and it converts a silent outcome into a visible one.
5. **Differentiation attachments and the printable pack** (OUTPUT_ENRICHMENT_PLAN.md). Now
   unblocked: the classifier supplies `DifferentiationRole` and `DocumentLessonKey`, which is what
   this work needed from it. Note the open owner decision recorded there — cite vs. embed — and
   the 45% attachment-key coverage.
6. **Revisit the classifier prefilter** as its own change, verified against real documents rather
   than fixtures. Lower priority than it looks: with the placement guarantee in place, the
   prefilter is an optimization, not a correctness requirement.
7. `ImportedSourceRole.infer` substring over-matching ("benchmark", "holiday", "break").

**Process adjustments earned this session, worth keeping.**

- "Verified" must mean measured against the owner's real data. Fixture-only verification produced
  at least two batches logged as fixed that were not (Batch 022 subject matching; Batch 025's
  persistence regression). Every batch touching import, extraction, or placement should end with a
  real-data check.
- Relaunch the app after any change to a persisted model. Tests build their own fresh data and
  structurally cannot catch a decoding-compatibility break.
- Escalate to an external review at the **second** oscillation, not the fourth. Rotating fixture
  failures mean the design is wrong, not the constants. Codex found in minutes what three
  self-directed attempts missed.
- Sample a bucket before trusting its count. "154 inert" looked like a clean result and was
  actually the best differentiation material in the folder.

### Batch 034 — 2026-07-29 — Verified the strict-placement fix against the owner's real import

**The reported scatter is substantially fixed.** Verified end to end against a copy of the owner's
real 316-document import, not fixtures.

**Method.** Copied the real profile's `configuration.json` and `imported-sources.json` into a
throwaway data root, deleted its weekly plan and lesson records so placement would re-run from
scratch, and drove a real `AppStore` against it. No original PDFs were needed — the extracted text
is already persisted — and the owner's live data was never touched.

**Result.**

| Measure | Before (reported) | After |
|---|---|---|
| Placements at the invented 9:00 AM slot | present, spread across days | **0** |
| Placements in the Math block (09:45) | partial | **23 of 24** |
| Placements in the ELA block (08:35) | several | **1** |
| Times used that are not real blocks | yes | **none** |
| Unplaced lessons reported to the teacher | 0 of 149 | **3, with a reason** |

Every placement now lands in one of the teacher's own 12 imported blocks. The phantom-slot
mechanism — the actual engine of the scatter — is gone, and `AutoPlacementSummary` reported
"24 lessons scheduled. 3 left unscheduled because no matching subject block was found — those
blocks were left unchanged."

**The one remaining misplacement, identified precisely.** A single lesson still lands in the ELA
block: a fragment titled "day, can he still meet his goal? Why or why not?", proposed from a
challenge worksheet (filename marker `CHLG`). Two separate planned changes would each independently
fix it:

- The **classifier prefilter** would classify that document `supportingMaterial` on its filename
  marker, so it would never propose a lesson at all. This raises the prefilter's priority: it is
  not merely an optimization, it is what removes this exact class of failure.
- **Populating `subject` at import** would tag the lesson as math, so block matching would resolve
  it to the Math block rather than scoring English on incidental vocabulary.

**Also confirmed unchanged:** 173 lesson records are still created from the import. The placement
guarantee stops them corrupting the planner but does not stop them being manufactured — Codex's
`CoursePacingPlan.starter` finding stands as the next code change.

**Adjustment to the plan.** Move the classifier prefilter up: it is now evidenced as the fix for
the last remaining misplacement, not a cleanup. It still must be reworked so it does not
simultaneously exclude valid short packets and admit planning documents — verified against real
documents this time, which is now cheap given the harness in this batch.

### Batch 035 — 2026-07-30 — Activated import filtering and document-level subject stamping

**Compute:** high. **Model shape:** single-model implementation with real-profile verification.

1. Changed `CoursePacingPlan.starter(from:)` so a readable source with no extractable lesson
   titles produces no placeholder lesson and no empty unit/module. This is deliberate: an
   orphaned container is still clutter, not useful pacing work.
2. Found that blank placeholder removal alone did not catch every fragment: worksheet prose such
   as a sentence beginning `Day, ...` was being accepted by a prefix-only heading parser.
   Required a real heading boundary (end, whitespace, number, colon, or dash) after `day`,
   `lesson`, and `session`.
3. Reworked the classifier prefilter: filename-marked supporting material is excluded;
   schedules/calendars remain planning-only; short two-entry weekly packets are recognized before
   the general text-length floor; genuine scope-and-sequence documents still contribute named
   lessons.
4. Added `ImportedSource.inferredSubject` as an optional persisted field and populated it at
   PDF/DOCX import using `LessonStructureInferencer`. New automatic lesson records receive the
   saved source subject; schedule matching consults it before full-text scoring.
5. Added Document Intake feedback using `AutoPlacementSummary.summaryLine`.
6. Added generic regression coverage for short packets, legacy decoding without the new subject
   field, support-page exclusion, standards-derived Math placement, blank-source skipping, and
   malformed `Day` worksheet prose.
7. Ran a temporary test against a copied local profile in `/tmp`, with no original PDFs and no
   writes to the live workspace. After simulating fresh-import metadata, 15/15 placements landed
   in the Math block, all were real schedule blocks, and malformed Day fragments fell to 0.
   Generated lesson records fell from 172 to 162 in that profile copy.
8. Removed the temporary real-data harness before commit; no curriculum content, filenames, or
   extracted text was committed.
9. Verification: permanent Swift suite 167/167 passing; real Debug Xcode build succeeded.

**Dead ends / notes.** The first copied-profile run looked unchanged because the copied
configuration still contained its old pacing plan, so AppStore correctly reused it. Clearing the
course pacing plan in the `/tmp` copy was necessary to exercise the new source-selection path.
Existing already-imported sources do not receive `inferredSubject` retroactively by this batch;
the new behavior applies to future imports. A migration/backfill should be a separate,
explicitly verified decision rather than silently rewriting teacher data.

**Still open.** Improve the remaining page-level records through document grouping
(`DocumentLessonKey`), not more title heuristics. Then attach supporting documents to grouped
lessons for the differentiation attachment/printable-pack workflow. A visual check of the new
import summary remains appropriate before a UI sign-off.

### PLAN REVISION 3 (2026-07-30) — derived-state infrastructure, Codex-reviewed before implementation

**Trigger.** Reviewing Batch 035 showed its improvements do not reach the owner's existing profile.
It was verified by fresh-import simulation (162 records, 15/15 correct placements); re-run against a
copy of the real profile it produced 173 records, 24 placements, malformed `Day…` fragments still
placed, and `inferredSubject` empty on 0 of 316 sources. Cause: `configuration.json` already holds
an auto-built pacing plan (315 units / 869 lessons, approved), and
`syncReadableDocumentsIntoWeeklyPlanner` reuses a non-empty plan rather than rebuilding, so the new
filtering never executes. The owner opening the app today still sees the reported bug.

**Generalized problem.** The app persists derived state (pacing plan, auto-created lesson records,
automatic placements, per-document classification fields) alongside source state, with no
invalidation model. Every future extraction/classification improvement will silently fail to reach
existing profiles the same way. The owner has stated they do not need this profile preserved and
want solid infrastructure.

**Codex review verdict.** The four-step shape is right and *not* over-engineered — provided it is
built incrementally. The over-built version would be a global derivation-version migration that
rewrites everything on launch **before** provenance exists. Two corrections to my draft:

1. **Provenance must land before any versioned rebuild.** Auto-created lessons are identifiable
   only by prose in `aiReviewWarnings` (`AppStore.swift:1034`); the pacing plan's origin only by
   prose in `teacherRefinementNotes`. Codex found a third: automatic placements are detected via
   `planningNotes.hasPrefix("Pacing:")` (`AppStore.swift:975`). All three are too weak for
   migration-grade behavior. Rebuilding against them risks destroying teacher work.
2. **Version per artifact, not one global constant** — `ImportedSource.classificationVersion`,
   `CoursePacingPlan.derivationVersion` + `origin`, `LessonRecord.origin` (+ a stable link back to
   the pacing lesson), `WeeklyLessonAssignment.origin`.

**Codex also corrected my "don't persist the pacing plan at all" idea.** `CoursePacingPlan` already
carries teacher-authored content — dates, skipped days, assessment windows, approval, refinement
notes — so it is not purely derived. The clean end state is *persist the teacher overlay, derive the
machine proposal*, which is too large a jump from here. Provenance first.

**Also worth recording:** the app already mutates on load — `reload()` calls
`syncReadableDocumentsIntoWeeklyPlanner(rebuildExistingPacing: false)` (`AppStore.swift:173`). So
launch-time mutation is not a new risk being introduced; what is missing is a principled
invalidation model. Recompute cost is a non-issue at this scale (316 sources, ~3.6 MB of text, local
string/regex work), but any rebuild that changes visible planner state should report what it did
rather than silently rearranging the week.

**Agreed build order.**

1. **Provenance fields, all optional / default-decoding.** Mandatory infrastructure; everything else
   depends on it. Replaces the three prose heuristics above with explicit origin.
2. **Explicit rebuild command** that removes and regenerates only `autoDerived` pacing, lessons, and
   placements. Use it to repair the owner's profile. This is what makes Batch 035 actually reach
   them.
3. **`inferredSubject` on-demand fallback**, matching the `effectivePlacementEligibility` pattern —
   cheap, and immediately fixes legacy sources without a migration.
4. **Per-artifact derivation versions and stale detection.**
5. **Automatic rebuild-on-load** for clearly auto-derived stale artifacts, with a visible summary.
6. **Later:** split persisted pacing into derived proposal + teacher overlay.

**Most likely breakage, per Codex:** decoding old files with new non-optional fields (see the
CRITICAL PERSISTENCE RULE — all new fields optional); treating a teacher-edited auto-created lesson
as disposable; and moving weekly assignments the teacher manually adjusted.

### Batch 036 — 2026-07-30 — Provenance: derived artifacts can now prove what they are

Step 1 of the Codex-reviewed derived-state plan (PLAN REVISION 3). Mandatory infrastructure: the
explicit rebuild in step 2 cannot be written safely until the app can prove which artifacts it owns.

**Problem.** The app identified its own work by matching English sentences in three places — an
auto-created lesson by a phrase in `aiReviewWarnings`, an auto-built pacing plan by a phrase in
`teacherRefinementNotes`, and an automatic placement by `planningNotes.hasPrefix("Pacing:")`. A
rebuild driven by those would risk destroying teacher-authored work.

**What shipped.**

| # | Change | Note |
|---|---|---|
| 1 | New `RecordOrigin` enum: `.teacherAuthored` / `.autoDerived` | |
| 2 | `origin` added to `LessonRecord`, `CoursePacingPlan`, `WeeklyLessonAssignment` — all **Optional**, per the CRITICAL PERSISTENCE RULE | Files written before the field decode unchanged |
| 3 | `effectiveOrigin` on each, falling back to the legacy prose marker | Existing data is classified correctly with no migration; the prose heuristics survive only as this fallback |
| 4 | Origin stamped at every creation site: auto-created lessons and automatic placements as `.autoDerived`, `CoursePacingPlan.starter` output as `.autoDerived`, both teacher-initiated draft-lesson paths as `.teacherAuthored` | |
| 5 | The automatic re-placement guard now reads provenance instead of `planningNotes.hasPrefix("Pacing:")` | An assignment the teacher moved by hand is no longer silently relocated |
| 6 | `updateLesson(_:markingTeacherEdit:)` promotes an edited record to `.teacherAuthored` | |

**Two deliberate safety choices.**

- `markingTeacherEdit` **defaults to true.** Forgetting it on an automatic path merely leaves a
  record protected from rebuild; forgetting it on a teacher path would let a rebuild destroy their
  work. The default is the direction that preserves. The one genuinely automatic caller
  (`ensureApprovedLesson` promoting an existing lesson to approved) passes `false` explicitly.
- `effectiveOrigin` defaults to `.teacherAuthored` when neither the field nor a legacy marker is
  present, for the same reason.

**Verification.** 175 tests pass (167 + 8 new), real `xcodebuild` succeeded. Against a copy of the
owner's real profile the legacy fallback classified **173/173 lessons, the pacing plan, and 24/24
assignments as `.autoDerived`**, with nothing misclassified in either direction — so the step-2
rebuild will be able to regenerate them safely, and would not have been able to before this batch.

**Still open.** Steps 2-6 of PLAN REVISION 3: explicit rebuild command; `inferredSubject`
on-demand fallback; per-artifact derivation versions; automatic stale rebuild with a visible
summary; and later the derived-proposal / teacher-overlay split.

### Batch 037 — 2026-07-30 — Close the ownership holes Codex found in Batch 036

Batch 036 was sent for external review before step 2 was built on it. The verdict was **"do not
build step 2 on top of this yet"** — the model direction was right, but promotion was implemented
for lessons only, leaving pacing plans and weekly assignments still rebuild-owned after a teacher
edited them. Fixing that here, before the rebuild command exists.

**Holes found and closed.**

| Severity | Hole | Fix |
|---|---|---|
| High | Six teacher-facing pacing mutators (refinement notes, unit, module, lesson, add/remove skipped day) never promoted the plan. Since `starter` stamps `.autoDerived` explicitly and an explicit origin beats the legacy fallback permanently, an edited plan stayed rebuild-owned **forever** — a rebuild would have discarded the teacher's dates and skipped days | All seven teacher save points (including `approveCoursePacingPlan`) now set `.teacherAuthored`; the automatic path uses different locals and is untouched |
| High | `updateWeeklyAssignment` never promoted. A teacher moving a placement through the UI left it `.autoDerived`, so the automatic re-placement guard would still relocate it — **the exact bug this provenance work exists to prevent** | Promotes on edit |
| Medium | `saveDraftLesson`, `createDraftLesson(from pacingSuggestion:)`, and `createDraftLesson(from source:title:objective:)` left `origin` nil, relying on the fallback | All three stamp `.teacherAuthored` explicitly |

**Process failure worth recording.** One of Batch 036's stamps silently did not apply: the edit
script used `assert` on most replacements but not on two, and a non-matching `str.replace` fails
silently. The function had been rewritten since, so the anchor no longer matched. **Every scripted
source edit must assert its anchor matched.** Codex caught the resulting gap; a green test suite did
not, because no test covered that path.

**Verification.** 179 tests pass (175 + 4 new covering each closed hole), real `xcodebuild`
succeeded.

**Deliberately not done, and why.** Codex also recommended replacing
`updateLesson(_:markingTeacherEdit:)` with two explicitly named methods before step 2, on the
grounds that a defaulted boolean is easy to misuse as the codebase grows. That is a reasonable
API-hygiene change but it is not a correctness gap — the default is already the preserving
direction, and every current call site is now covered by a test. Recorded as a follow-up rather
than bundled into a batch that was fixing real data-safety holes.

**Codex's judgement on the model, for step 2's benefit.** `.teacherAuthored` / `.autoDerived` is
sufficient **if step 2's rule is artifact-level** — rebuild only what the app owns, preserve
anything the teacher touched. It is *not* sufficient for field-level merging ("re-derive only the
fields the teacher did not edit"); that needs per-field dirty tracking or the proposal/overlay
split, and a third enum case would not solve it. Step 2 should therefore be artifact-level.

**Still open.** Steps 2-6 of PLAN REVISION 3, plus the explicit-API refactor above.

### Batch 038 — 2026-07-30 — Step 2: explicit rebuild of derived planning data

First batch run under the standing plan → pre-review → implement → debrief workflow.

**Pre-execution review changed the design.** Codex judged the original plan **"not safe as written"**
and required a protection pass before any deletion. Incorporated in full:

| Required change | Why |
|---|---|
| Never delete an auto-derived lesson that any `GeneratedOutputRecord` points at | The generated file already exists in the teacher's output folder and is **outside the snapshot safety net** — snapshots capture app records, not files on disk |
| Never delete an auto-derived lesson referenced by a `.teacherAuthored` assignment | Would create exactly the dangling state `WeeklyPackageReadinessReport` already reports as a missing scheduled lesson. Referential integrity outranks provenance purity |
| Refuse outright when the pacing plan is `.teacherAuthored` | Silently discarding hand-edited dates and skipped days is the worst available outcome |
| A real preview with counts, not a vague warning, before executing | The operation is visibly destructive |
| Cut from scope: stable-key reconciliation, per-artifact versions, automatic rebuild, deleting output files | Kept the batch narrow; reconciliation on normalized titles would be too weak to serve as migration-grade identity |

**What shipped.** `AppStore.previewDerivedRebuild()` computes the operation without mutating
anything; `rebuildDerivedPlanningData()` snapshots first, deletes only unprotected auto-derived
lessons and auto-derived placements, then re-runs the existing sync with `rebuildExistingPacing:
true`. A Workspace button shows the counted preview in a confirmation dialog before anything runs.

**Verification against a copy of the owner's real profile — the point of the whole exercise:**

| | Before | After |
|---|---|---|
| Lesson records | 173 | **162** |
| Pacing units / lessons | 315 / 869 | **54 / 567** |
| Placements | 24 | **15** |
| Placements in the Math block | 23 (+1 in ELA) | **15 of 15** |
| Phantom slots | — | **0** |
| Malformed `Day…` titles | present | **0** |

These are **exactly** Batch 035's fresh-import numbers (162 records, 15 placements). An existing
profile now converges to the same state a fresh import produces, which is the entire purpose of
this step. The ELA misplacement is also gone.

184 tests pass (179 + 5 new, one per protection rule), real `xcodebuild` succeeded.

**Note on the test seams.** `replaceLessonsForTesting` / `replaceGeneratedOutputsForTesting` are
`#if DEBUG` only. `lessons` and `generatedOutputs` are `private(set)` so production code cannot
bypass their save paths; the seams let a test construct a starting state without weakening that.

**Still open.** Steps 3-6 of PLAN REVISION 3 — `inferredSubject` on-demand fallback, per-artifact
derivation versions, automatic stale rebuild with a visible summary, and later the
derived-proposal / teacher-overlay split — plus the `updateLesson` explicit-API refactor.
