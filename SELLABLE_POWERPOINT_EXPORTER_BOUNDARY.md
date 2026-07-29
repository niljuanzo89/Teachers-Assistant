# Sellable PowerPoint Exporter Boundary

## Purpose

This note separates the current personal PowerPoint prototype from the exporter that would be acceptable in a sellable LessonPlanner build.

The current bridge is useful for local testing because it proves the app can turn one approved lesson record into an editable deck. It is not customer-facing architecture.

## Current Personal Bridge

The personal build uses:

- `SlideDeckBridge.swift` in the macOS app.
- `Resources/SlideDeckGenerator.mjs` as the deck generator.
- The owner's locally installed Codex presentation runtime under the local Codex runtime cache.

The bridge sends only approved lesson fields to the local generator. It does not send raw source text to a hosted AI service.

## Sellable-Version Requirements

A sellable exporter must:

- Be bundled, installed, and supported with the app.
- Require no Codex, Claude, developer runtime, or owner-specific local cache.
- Generate editable PowerPoint files from the approved `LessonRecord`.
- Preserve teacher review boundaries: only approved lesson data should generate classroom-facing outputs.
- Include predictable error messages for missing dependencies, file-write failures, unsupported content, and export timeouts.
- Provide automated structural checks for slide count, editable text, source notes, and obvious overflow.
- Provide manual QA review metadata after the teacher or owner inspects the generated output.
- Keep template ownership clear: customer-owned templates and school-specific visual styles must not be embedded in the generic product.

## Migration Path

1. Define a provider-neutral export interface behind `SlideDeckGenerating`.
2. Move the current personal bridge behind a clearly named personal-only adapter.
3. Add a supported exporter implementation that ships with the app.
4. Add installer/build checks that fail if the sellable target depends on owner-local runtime paths.
5. Expand fixture coverage with generic, non-proprietary lesson records only.
6. Keep PowerPoint-to-Google-Slides round-trip testing as a release gate for template changes.

## Explicit Non-Goals

- Do not embed school curriculum, student data, HMH content, or school-specific templates in generic code or fixtures.
- Do not require a customer to install Codex or authenticate a developer AI account to export slides.
- Do not let AI approve, publish, or generate final classroom outputs without teacher approval of the lesson record.
- Do not upload generated decks to Google Slides or another external service without explicit user authorization for the specific file and destination.

## Current Status

As of 2026-07-28, the personal exporter has:

- A seven-slide generic QA deck that imports cleanly into Google Slides.
- Long-text resilience for titles, objectives, and instructional-step overflow.
- App-level diagnostics for personal runtime availability.
- AppStore tests for approved-lesson generation and refusal of unapproved lessons.
- Manual QA review metadata for generated outputs.

The supported exporter strategy is recorded in `POWERPOINT_EXPORTER_STRATEGY_ADR.md`: use a native Swift Open XML PowerPoint exporter for the sellable build.

The next sellable-product step is not more personal bridge polish. It is implementing the native exporter path that can ship without owner-local runtime dependencies.
