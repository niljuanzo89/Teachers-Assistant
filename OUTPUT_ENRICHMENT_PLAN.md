# Output Enrichment Plan

Updated: 2026-07-29

## Goal

Make the three teacher-facing outputs useful enough for real review:

- Lesson plan HTML
- Native PowerPoint slide deck
- Differentiation guide HTML

The app should still work locally and deterministically. AI can improve the result later, but
the core output path cannot depend on hosted AI or teacher-owned source material leaving the
machine.

## Current Diagnosis

The generated outputs are bare for two reasons:

1. Imported source documents often produce sparse `LessonRecord` fields. The current parser is
   intentionally conservative and avoids inventing details.
2. The supported output path is intentionally generic. `NativePowerPointExporter` creates a
   simple editable deck, while the richer early deck arc lives in
   `Resources/SlideDeckGenerator.mjs`, the older personal bridge path.

This means the fix should not be only "better extraction" or only "better templates." The
next phase needs a shared enrichment layer plus upgraded renderers.

## Implementation Sequence

1. Add a deterministic lesson enrichment layer.
   - Input: a `LessonRecord` plus readable source text already stored locally.
   - Output: a richer teacher-editable lesson record or view model.
   - Fill safe defaults only where the teacher can clearly revise them.
   - Keep unknown fields visibly blank or "not specified" rather than pretending certainty.

2. Port the richer slide arc into the native PowerPoint exporter.
   - Use the useful sequence from `Resources/SlideDeckGenerator.mjs`:
     - title / objective
     - learning goal
     - warm up and connect
     - build understanding together
     - practice and explain
     - differentiation support
     - exit ticket
   - Keep speaker notes provenance.
   - Keep decks editable and generated through `NativePowerPointExporter`.

3. Expand the lesson plan HTML template.
   - Add quick-look sections teachers expect:
     - lesson snapshot
     - objective / success criteria
     - materials
     - vocabulary or key concepts when available
     - instructional flow
     - checks for understanding
     - differentiation
     - source provenance

4. Expand the differentiation guide.
   - Separate supports by practical classroom use:
     - access/support
     - language or vocabulary
     - extension/challenge
     - small group or partner structures
     - printable prompt / exit ticket

5. Add output QA fixtures.
   - Use a representative enriched lesson in tests.
   - Verify all three outputs contain the core lesson content.
   - Verify blank/unknown fields do not become fake specifics.
   - Verify PowerPoint output still opens as a valid `.pptx`.

## Product Rules

- Do not reintroduce per-document teacher approval as a required step.
- Document import should remain A-to-B: upload files or folders, then the weekly planner
  should populate automatically when enough pacing/schedule information is available.
- The teacher should be able to manually revise blanks or weak imported fields after the
  automatic pass.
- Keep local profile/save/reload/clear behavior intact.
- Do not send teacher documents to hosted AI without explicit permission in the current task.

## First Coding Pass

Started in Batch 017 with the native slide exporter because it has the clearest existing
comparison:

1. Done: add a small `LessonOutputContent` view model that normalizes title, objective,
   steps, differentiation, assessment, subject, grade, materials, prompt, and source
   references.
2. Done: make `NativePowerPointExporter` use the richer slide sequence from the old bridge.
3. Done: add tests that inspect the generated `.pptx` package for expected slide count and
   key text.
4. Done (2026-07-29, Batch 028): applied `LessonOutputContent` to `LessonPlanRenderer`'s
   two HTML renderers, with one deliberate exception — the "not specified" / empty-state
   checks test the raw `LessonRecord` fields, not `LessonOutputContent`'s properties, since
   that view model's own fallback text ("Explore the teacher-reviewed learning objective.")
   is written for student-facing slides and would misrepresent a genuinely blank field as
   reviewed content in a teacher-facing document. Added a "lesson snapshot" quick-stats strip
   (step/material/source counts) to the lesson plan; added an explanatory hint caption to the
   differentiation guide's notes section instead of splitting into fake sub-categories, since
   `LessonRecord` only has one `differentiationSummary` string today — see "Still open" in
   Batch 028's `CONTINUITY_LOG.md` entry for what a real category split would need.
5. Not started: a deterministic lesson-content enrichment layer (Implementation Sequence #1)
   that actually improves sparse extracted `LessonRecord` fields from source text — this
   coding pass only improved the *rendering* of whatever a `LessonRecord` already has, not
   the underlying extraction quality. Still the biggest lever for genuinely richer output.

## Design scaffold: supporting materials feed the differentiation guide and printable resources

Added 2026-07-29 at the owner's direction, answering the open question about what should happen
to documents classified as *supporting material* (see the PLAN REVISION entry in
CONTINUITY_LOG.md). Design only — nothing here is implemented yet.

**Owner's intent.** Supporting materials should not be discarded and should not occupy schedule
blocks. They should feed the differentiation guide for their corresponding lesson, and be cached
so they can be placed into that lesson's printable resources.

This maps cleanly onto the artifact types found in a real curriculum folder:

| Imported artifact | Differentiation role it serves |
|---|---|
| Reteach / intervention / tier sheets | Access and support |
| Challenge / enrichment / extension sheets | Extension and challenge |
| Practice / homework pages | Student practice, printable |
| Vocabulary / glossary pages | Language and vocabulary |
| Assessment / quiz / exit-ticket pages | Success check |

It also resolves something flagged earlier: `LessonRecord.differentiationSummary` is a single
free-text field, so the differentiation guide could not honestly split into categories. Attached
materials supply that structure without inventing it from prose.

### What exists today

- `LessonRecord.printableResourcePrompt: String?` — a text prompt for a student task.
- The differentiation guide already renders a genuinely print-aware printable section
  ("Student Practice / Exit Ticket": name/date line, the prompt, ruled answer lines, with
  `break-before: page` and taller lines under `@media print`). This is the seed of the
  printable mechanism — it exists, it is just limited to one generated blank page.
- `LessonRecord.sourceReferences: [String]` — untyped file paths, provenance only.

### What does not exist

- Any typed link between an `ImportedSource` and a `LessonRecord`. Nothing can express "this
  worksheet is the reteach material for this lesson."
- Any cache of a material's usable content for reuse in an output.
- Any printable output beyond the single blank practice page.

### Proposed model additions

```
enum DifferentiationRole { case support, extension, practice, vocabulary, assessment, other }

struct LessonMaterialAttachment {
    let id: UUID
    var lessonRecordID: UUID
    var importedSourceID: UUID
    var role: DifferentiationRole
    var attachedAutomatically: Bool   // false once a teacher confirms or changes it
    var cachedExcerpt: String?        // extracted text kept for rendering, see caching note
    var pageReference: String?        // e.g. "pp. 12-13", for cite-don't-copy rendering
}
```

Persisted per profile like other records. Being a separate record rather than a field on
`LessonRecord` keeps a material attachable to more than one lesson and keeps the attachment's
own provenance (auto vs. teacher-confirmed) intact.

**Note for whoever implements this:** every new persisted field needs backward-compatible
decoding — see the CRITICAL PERSISTENCE RULE in MODEL_HANDOFF.txt. That rule exists because a
field added without it made real saved workspaces unreadable.

### Caching

"Cache" here should mean *the extracted text and a page reference*, not a copy of the original
file. The originals already live in the teacher's own folders and are already registered as
`ImportedSource` records with `extractedText`. Storing a second copy inside app data would
duplicate licensed material for no functional gain. Cache the excerpt actually needed for
rendering, keyed by attachment, and re-derive it if the source is re-extracted.

### An IP decision the owner should make before this is built

There is a real difference between:

1. **Citing** — the differentiation guide says "Reteach: print pages 12-13 of *[material name]*",
   with the teacher printing from the publisher's own file.
2. **Embedding** — the app copies the material's content into a new printable it generates.

Option 1 is the safer default and is what this design assumes unless the owner says otherwise.
The teacher's own licensed materials, used with their own class, are legitimate for them to
print; but having the app assemble publisher content into new redistributable documents at scale
is a different act, and it is the teacher's exposure rather than the app's. Worth a deliberate
decision, not a default that emerges from implementation convenience. Either way this concerns
the teacher's local output only — nothing licensed enters the repo, per the standing boundary.

### Printable resources scaffold, staged

1. **Attach and display.** Add the model above, auto-attach materials to lessons using the same
   artifact-type signals the placement-eligibility gate uses, and render them in the
   differentiation guide as grouped, cited lists under real category headings (Access and
   support / Extension and challenge / Practice / Vocabulary). This alone makes the guide
   substantially more useful and needs no new output plumbing.
2. **Teacher control.** Let the teacher confirm, re-role, remove, or manually attach a material.
   Auto-attachment must be a proposal, consistent with the app's existing stance that nothing is
   approved automatically.
3. **Printable pack.** Grow today's single printable section into an assembled pack: a cover
   sheet naming the lesson, then one printable block per attached practice/assessment material,
   each either cited (default) or embedded (if the owner chooses that route). Keep it inside the
   differentiation guide's HTML at first — it already prints correctly — and only promote it to
   its own `GeneratedOutputKind` if the owner wants it as a separately generated artifact.
4. **Weekly rollup.** Optionally surface "materials to print this week" in the weekly package,
   so preparation is one pass instead of per-lesson.

### Dependencies

Steps here depend on the placement-eligibility classification landing first (CONTINUITY_LOG.md,
PLAN REVISION). That gate is what identifies a document as supporting material in the first
place, and it produces the artifact-type signal this design reuses for `DifferentiationRole`.
Building the attachment model before the gate would mean writing the classifier twice.

### Investigated: can the app ignore "non-compliant" files? — measured answer

The owner asked whether the program can be instructed to ignore non-compliant files. Measured
this against their real 316-document import before designing anything, and the data argues
against an import-side ignore rule.

**Findings (full extracted text of all 316 documents):**

- **310 of 316 carry a copyright notice** — 98%.
- **5** contain any reproduction-permission language (blackline/photocopy/"may be reproduced").
- **0** contain explicit prohibition language.

Two conclusions follow directly:

1. **An "ignore copyrighted material" rule would ignore 98% of the folder** and remove the
   app's core value. Nearly everything a teacher legitimately owns and plans from is
   copyrighted. Copyright presence is not non-compliance: a teacher reading their own licensed
   curriculum to plan their own class is ordinary, legitimate use.
2. **A permission-detection gate is not viable** — the signal is effectively absent from these
   documents. Designing around it would mean building a mechanism that almost never fires, and
   whose silence would be misread as "no restrictions found."

**Therefore the control belongs on the output side, not the import side.** The distinction that
actually matters is not *which files the app may read* but *what it does with them*:

| Action | Assessment |
|---|---|
| Extract text locally, plan from it, populate lesson fields | Fine. This is the product. |
| Cite a material in an output ("print pp. 12-13 of X") | Fine. Points the teacher at a file they own. |
| Embed a material's content into a newly generated printable | The action needing care. |

**Recommended design — no import-side compliance filter; an output-side default instead:**

1. **Never embed source content into generated outputs by default.** Cite-only, as already
   assumed by the printable-resources design above. This achieves the owner's goal without
   discarding files they need.
2. **Add a per-material `reproductionPermission` field** — `unknown` (default), `citeOnly`, or
   `teacherConfirmedReproducible`. Only the last permits embedding, and only the teacher can
   set it, because only the teacher knows their license terms. Pre-flag the ~5 documents whose
   text does carry blackline/photocopy language as candidates, but never auto-grant.
3. **Respect machine-readable publisher signals where they genuinely exist.** `PDFDocument`
   exposes `isEncrypted` and `allowsCopying`; a PDF that is copy-protected is an explicit,
   unambiguous signal and should be treated as `citeOnly` with no override. This is a real
   compliance check, unlike copyright-notice presence.

**What an import-side filter should actually exclude** — genuine junk, not "compliance":

- Documents whose extraction produced no usable text (already partly handled via the
  `.blocked` source-readiness level).
- Encrypted PDFs that cannot be read at all.
- Non-lesson artifacts, which the placement-eligibility gate already handles — that gate is the
  right home for "don't schedule this," and it does not require refusing to import the file.

**Net:** the app should keep reading everything the teacher gives it, place only real lessons,
cite materials rather than reproduce them, and require an explicit teacher decision before any
source content is embedded. No file needs to be ignored to get there.

### Routing design: divert non-lesson material to differentiation instead of ignoring it

Clarified with the owner 2026-07-29. Their "non-compliant" meant *material that does not fit
cleanly into a lesson format* — a structural question, not the IP one investigated above. Two
corrections and then the design.

**Correction 1: this material can absolutely be cached.** The earlier caching caveat was narrow —
do not store a second copy of whole licensed files, because they already exist as
`ImportedSource` records with extracted text. Caching an *excerpt plus a page reference* per
attachment is exactly what the differentiation design proposes and there is no obstacle to it.

**Correction 2: ignoring is unnecessary.** Nothing has to be discarded to keep the weekly planner
clean. The fix is routing, not exclusion.

**The core idea: these are three independent decisions, currently collapsed into one.**

Today a single classification (`ImportedSourceRole`) implicitly decides everything, which is why
a practice worksheet becomes a scheduled lesson. Separate them:

| Decision | Question | Consequence |
|---|---|---|
| Placement eligibility | Does this have the shape of a teachable lesson? | Gates the weekly-planner pathway only |
| Differentiation role | Which support category does it serve? | Feeds the differentiation guide + printables |
| Attachment key | Which lesson does it belong to? | Links material to lesson |

A document can be *not placeable* and *valuable differentiation material* at the same time. That
combination is the pathway split the owner is asking for, and it is unrepresentable today.

**Four routing outcomes, nothing thrown away:**

1. **Placeable lesson** — lesson shape present (objective and/or instructional sequence).
   Proceeds to the weekly planner. Only this pathway may occupy a schedule block.
2. **Supporting material** — reteach, challenge, practice, vocabulary, assessment. Routed to the
   differentiation guide for its attached lesson and cached for printables. **Never enters the
   planner pathway at all** — it is not a lesson candidate, so it cannot be mis-scheduled.
3. **Planning document** — pacing guide, calendar, map. Existing pathway, already works.
4. **Inert** — genuinely unusable for either purpose (cover page, index, blank, unreadable).
   Imported and visible so the teacher can see it was received, referenced by nothing. This is
   the honest version of "ignore": not deleted, not hidden, just not used.

**The attachment key, measured against the owner's real import.** For material to inform *the
right* lesson's differentiation guide, it needs a link. Curriculum artifacts commonly carry a
module/lesson identifier, so that is a far stronger key than the subject-keyword scoring that
failed in the planner. Measured coverage across the 316 documents:

- 48 have a module/lesson identifier inferable from the **filename**
- 142 from the **document text** (first 3,000 characters)
- **143 (45%) from either** — usable auto-attachment coverage

45% is a genuine, honest number, not a solved problem. It is also far better than the current
behavior, where such documents become phantom scheduled lessons. Plan for it explicitly:

- Auto-attach where an identifier resolves to a known lesson, marked `attachedAutomatically`.
- Where no identifier resolves, leave the material **unattached but available**, listed for the
  teacher to attach in one click. Do not guess by subject or filename similarity — guessing is
  what produced the original scatter.
- Never let a failed attachment promote a material into the planner pathway.

**Why routing beats ignoring.** Ignoring loses ~55% of the folder's real value: those reteach and
challenge sheets are exactly what makes a differentiation guide worth printing. Routing keeps
them, keeps the planner clean, and leaves the teacher in control of the ambiguous remainder.

**Where this lands in the build order.** Decision 1 (placement eligibility) is already the
revised step 1 in CONTINUITY_LOG.md. Decisions 2 and 3 belong with the
`LessonMaterialAttachment` work in the section above, and should reuse the same artifact-type
signals the gate computes rather than recomputing them.
