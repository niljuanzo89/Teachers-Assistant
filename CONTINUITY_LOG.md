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
