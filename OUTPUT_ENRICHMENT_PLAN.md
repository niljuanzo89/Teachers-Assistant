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
4. Next: apply the same helper to `LessonPlanRenderer` and the differentiation guide.
