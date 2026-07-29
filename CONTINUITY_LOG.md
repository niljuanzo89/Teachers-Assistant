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

Owner requested continued local-drive development while using GitHub as a periodic sync
checkpoint. New operating rule: after every **50 logged development steps** since the last
GitHub sync/checkpoint, commit appropriate local work and attempt to sync to GitHub.

Current GitHub state:

- Local repo is on `main`; the GitHub seed commit was merged locally at `7afa717`
  (`Merge GitHub repository seed`).
- Remote `origin` is configured as
  `https://github.com/niljuanzo89/Teachers-Assistant.git`.
- `git push` is blocked because command-line git has no GitHub credentials on this Mac:
  `fatal: could not read Username for 'https://github.com': Device not configured`.
- After the owner made the repository public, the GitHub connector could see
  `niljuanzo89/Teachers-Assistant` and reported push/admin permissions. However, the
  available connector tools did not expose a whole-repo branch-ref push path, so command-line
  git authentication is still required for syncing the local project history.

Continue local work; retry connector visibility and/or git push at the next 50-step sync
checkpoint or when the owner adjusts GitHub access.

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
3. GitHub push remains blocked by command-line authentication; keep working locally.
