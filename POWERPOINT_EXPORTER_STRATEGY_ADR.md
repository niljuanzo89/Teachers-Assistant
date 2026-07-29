# ADR: Supported PowerPoint Exporter Strategy

Date: 2026-07-28

## Decision

The sellable LessonPlanner build should use a native Swift Open XML PowerPoint exporter as the supported exporter path.

The exporter should write `.pptx` files directly as Office Open XML PresentationML packages from approved `LessonRecord` data. The current personal Codex-runtime bridge remains useful for prototyping, but it should become a personal-only adapter behind `SlideDeckGenerating`.

## Why This Strategy

PowerPoint `.pptx` files are Open XML packages: a presentation is made of separate XML parts for the presentation, slides, slide layouts, slide masters, themes, notes, relationships, and content types. This is a documented standard rather than an opaque binary format.

A native Swift writer is the best sellable default because it:

- Removes Codex, Claude, Node, and developer-runtime dependencies from customer installs.
- Keeps all export work local.
- Fits the macOS app distribution model.
- Lets the app validate exactly what it wrote.
- Keeps the privacy boundary clear: approved lesson fields go into output files; raw source text does not.
- Makes failures easier to explain in app-owned terms.

## Alternatives Considered

### Keep the current personal bridge

Rejected for sellable use. It depends on owner-local Codex runtime paths and is not installable or supportable for customers.

### Bundle Node plus the current JavaScript generator

Rejected as the primary sellable path. It could work technically, but it increases app size, signing/notarization surface, dependency auditing, and support burden. It also preserves a runtime boundary that the native app does not otherwise need.

### Use LibreOffice or Apple automation

Rejected for core export. It would depend on external applications, UI automation, or user machine state. That is too fragile for customer support.

### Use a server-side conversion/export service

Rejected for the default product. It conflicts with the local-first promise and would require customer data transmission, billing, retention, and privacy controls. It may be a future opt-in integration, not the default exporter.

## Initial Scope

The first native exporter should support:

- 16:9 slide decks.
- Editable text boxes.
- Rectangles and simple lines.
- Theme colors and fonts.
- Speaker notes with local provenance.
- Deterministic filenames and package structure.
- Structural validation of slide count, text presence, notes presence, and relationship integrity.

The first implementation does not need to support:

- Arbitrary imported PowerPoint templates.
- Animations, audio, video, SmartArt, charts, or embedded objects.
- Direct Google Slides API export.
- AI-generated imagery or externally sourced visual assets.

## Implementation Slices

1. Create a `NativePowerPointExporter` conforming to `SlideDeckGenerating`.
2. Add a small internal `PPTXPackageWriter` that writes ZIP package parts, content types, and relationships.
3. Recreate the current generic lesson-deck layouts in Swift.
4. Add package-level tests that inspect generated XML parts without opening PowerPoint.
5. Add render/round-trip QA using the existing generic deck fixtures.
6. Keep `SlideDeckBridge` as `PersonalPowerPointBridge` or equivalent, excluded from sellable targets.
7. Add a build/release check that fails if the sellable target references owner-local runtime paths.

## Release Gates

Before this exporter can be considered sellable:

- Generated decks must open in PowerPoint.
- Generated decks must import into Google Slides with editable text.
- Generic stress fixtures must pass overflow/layout checks.
- Output history must record manual QA review.
- The exporter must work on a clean customer-like Mac without Codex runtime caches.

## References

- ECMA-376 defines Office Open XML vocabularies, document representation, packaging, and requirements for producers and consumers.
- Microsoft’s PresentationML documentation describes `.pptx` presentations as packages containing separate presentation, slide, layout, master, theme, notes, relationship, and content-type parts.
