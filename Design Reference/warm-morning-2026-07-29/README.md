# Handoff: Sunrise Lesson Planner (Warm Morning Redesign)

## Overview
A restyled UI for a teacher-facing lesson-planning app. Five screens — Today, This Week, Planning Preview, Document Intake, Workspace — covering daily/weekly scheduling, an AI-assisted lesson editor, a document-import flow, and a document library. This pass reskins the app's existing functional shape (seen in the reference screenshots) with a warm, morning-toned, rounded, depth-forward visual language, and reorganizes the Today screen (checklist now a full-height notepad-style side panel).

## About the Design Files
The bundled file (`Lesson Planner.dc.html`) is a **design reference built in HTML** — a working prototype of look, layout, and interaction, not production code to copy directly. It is a "Design Component": one HTML file with inline styles and a small React-like state class simulating real interactivity (add/remove tasks, toggle accordions, switch screens, edit a lesson, etc). The task is to **recreate this design in the target codebase's existing environment** (React, Vue, native, etc.), using its own component patterns, state management, and build tooling — or, if no environment exists yet, pick the most appropriate framework and implement there. Do not attempt to run or embed the .dc.html file itself in production.

## Fidelity
**High-fidelity.** Colors, type, spacing, radii and shadow values are final and intentional — implement pixel-close. Copy/microcopy shown is representative sample content; wire real data behind the same layout.

## Design system it's built on
Built on the "Broadsheet" design system (bundled under `_ds/`): Source Serif 4 for all type, a light warm paper ground, two accent ramps (100–900 each), and a shared component layer (`.btn`, `.tag`, `.input`, `.card`, etc. in `_ds/.../styles.css`). This redesign **overrides the system's default CSS custom properties** (see the `<style>` block at the top of the file's `<helmet>`) to shift the palette from the system's default cool cyan/magenta newsprint look to a warm morning palette, and to increase corner radius and shadow depth — while keeping the same component classes, type scale, and spacing scale. If the target codebase already has Broadsheet (or another system) implemented, apply the same token overrides there rather than hand-rolling new components.

### Design tokens (as overridden for this design)
- `--color-bg`: `#faf1e2` (warm cream page ground)
- `--color-surface`: `#fffaf1` (card/panel fill)
- `--color-text`: `#2f2415` (warm near-black)
- `--color-accent` (primary, amber/marigold): `#dd7e2c`, ramp 100→900: `#fdecd2, #fbd9a8, #f6c078, #eda552, #e08a3c, #c96f28, #a85720, #7c3f19, #4a2510`
- `--color-accent-2` (secondary, terracotta): `#d1573f`, ramp 100→900: `#fbe2da, #f6c4b4, #eea08a, #e07c60, #d1573f, #b23f2b, #8f2f20, #642015, #3a130c`
- `--color-neutral` ramp 100→900: `#fbf6ee, #f2e9d9, #e3d6c0, #cdbc9e, #ab9878, #8a765a, #6b5a42, #493d2c, #2c2417`
- Radius: `--radius-sm: 10px`, `--radius-md: 14px`, `--radius-lg: 22px` (all corners rounded — no square panels)
- Shadow: `--shadow-sm: 0 1px 2px rgba(120,72,20,.10)`; `--shadow-md: 0 10px 24px -8px rgba(120,72,20,.26), 0 2px 6px rgba(120,72,20,.12)`; `--shadow-lg: 0 26px 50px -16px rgba(120,72,20,.32), 0 8px 20px -6px rgba(120,72,20,.16)`
- Depth pattern: interactive elements (cards, buttons) rest at `shadow-sm` and lift to `shadow-md` plus a 1–2px upward translate on hover — depth is mostly expressed **on interaction**, not as constant heavy elevation.
- Font: Source Serif 4 for both headings and body (loaded via Google Fonts import in the DS stylesheet). No sans-serif is introduced anywhere.
- Subject/status color-coding uses the DS's four tag variants only: `.tag-accent` (amber), `.tag-accent-2` (terracotta), `.tag-neutral` (warm gray), `.tag-outline`.

## Screens / Views

Navigation is a single persistent top bar (see below); the five screens below are shown one at a time in the content area beneath it.

### Top navigation (persistent on every screen)
- Layout: horizontal flex bar, `padding: 16px 28px`, background `--color-surface`, bottom border `--color-divider`, soft ambient shadow.
- Left: 34×34px rounded-square (11px radius) icon mark with a warm amber→terracotta gradient and a small sun glyph, plus brand wordmark "Sunrise Planner" (Source Serif 4, 600 weight, 19px).
- Center/right: 5 nav buttons, each an icon (19px, inline duotone SVG, stroke=currentColor) + label (14px, Source Serif 4, 600 weight), `padding: 9px 16px`, `border-radius: var(--radius-sm)`. Active button: solid `--color-accent` fill, `--color-bg` text, `shadow-sm`. Inactive: transparent background, `--color-neutral-700` text.
- Below the nav, a persistent profile bar: 38px circular avatar (warm gradient, initial "N"), name "Nikolai" (600 weight, 15px) + subtitle "Teacher · 2nd grade · Local testing profile" (12px, `--color-accent-800` at 85% opacity), on a `--color-accent-100` background band; right-aligned "Switch profile" secondary button.

### 1. Today
- Purpose: at-a-glance view of today's schedule + a running task list.
- Layout: `padding: 28px`, main row is `display:flex; gap:24px`. Left column `flex:1` (periods grid + schedule-builder panel, stacked with 20px gap). Right column is a **fixed 300px-wide, full-height panel** — the checklist.
- Left column top: header row (`justify-content:space-between`) — "Today's periods" (26px heading) left, date label (13px, muted) right. No greeting banner — removed to keep periods high on the page.
- Periods grid: `grid-template-columns: repeat(auto-fill, minmax(220px,1fr))`, 16px gap. Each period card: `--color-surface` fill, 1px `--color-divider` border, `--radius-lg`, 16px padding, `shadow-sm` → `shadow-md` + `translateY(-2px)` on hover. Contents: time range (12px, `--color-accent-700`, 600 weight), title (16px Source Serif 600), instruction text (13px, `--color-neutral-700`), footer row with a subject `.tag` (left) and a trash icon-button (right, appears muted, tints terracotta on hover).
- "Add a schedule block" panel below the grid: `--color-surface` card, `--radius-lg`, `shadow-sm`, 20px padding. Fields: Block title (text input), Instruction (text input), then a row with Start/End labeled inputs (110px wide each) and a right-aligned primary "Add" button.
- **Checklist panel** (right column): full-height card, `--radius-lg`, `shadow-md` (slightly more resting elevation than other cards, since it's the page's featured element), with an 8px-wide vertical color spine on the far left edge (gradient amber→terracotta) evoking a notepad binding. Header row: pencil icon + "Checklist" (h4). Below: task-entry row (text input + primary "Add" button). Below that: the scrollable task list, rendered over a **faint ruled-paper background** (`repeating-linear-gradient` every 44px, using `--color-divider` for the rule lines) — each task row is exactly 44px tall to align with the rules. Each row: 20×20px rounded checkbox (7px radius; filled `--color-accent` + white check icon when done, plain surface otherwise), task text (14px; strikethrough + 50% opacity when done), and a small "x" remove icon-button at the far right.

### 2. This Week
- Purpose: scan/edit the week's lessons per day.
- Layout: `padding:28px`, `h1` "This week" (28px), then a 5-column grid (`repeat(5, minmax(230px,1fr))`, 16px gap) filling remaining height.
- Each day column: `--color-surface` card, `--radius-lg`, `shadow-sm`, `overflow:hidden`. Header band: `--color-accent-100` fill, day name (16px, 600) + date (12px, `--color-accent-800`). Body: `flex:1; overflow-y:auto`, split into a 56px-wide **mini time rail** (time labels, 11px, right-bordered in `--color-accent-200`) and a scrollable list of lesson cards.
- Each lesson card: `--color-neutral-100` fill, `--radius-md`, `shadow-sm` → `shadow-md` on hover. Contents: title (13.5px, 600), source label (11px, muted), then a row of a subject `.tag` plus three small toggleable pill buttons — **Plan / Deck / Guide**. Each pill toggles independently on click between an "off" state (outlined, `--color-accent-700` text on surface) and an "on" state (solid `--color-accent` fill) — this represents "this artifact has been generated for this lesson."

### 3. Planning Preview (lesson editor)
- Purpose: review/edit an AI-drafted lesson record before export.
- Layout: `padding:28px`, two-column grid: 280px lesson list sidebar + flexible editor pane.
- Sidebar: "Lessons" header + secondary "New" button; scrollable list of lesson rows, each showing title (13.5px, 600) and a status `.tag` (Approved → amber tag, Draft → neutral tag, Needs review → terracotta tag). Selected row gets a `--color-accent-100` background.
- Editor pane: header row with "Lesson editor" (h2) and a Status `<select>` (Draft/Approved/Needs review) at the right. An amber "AI review warnings" banner below (rounded, `--color-accent-100` fill, warning-triangle icon, `--color-accent-800` text).
- Below the banner: **5 accordion sections** — Core lesson, Instructional sequence, Materials and assessment, Differentiation, Source provenance. Each section is its own rounded card (`--radius-lg`, `shadow-sm`) with a full-width clickable header (title + chevron that rotates 180° when open) and a body that shows/hides. Core lesson is open by default. Fields inside are standard `.input`s (and one `textarea.input` for Materials), all bound to the currently selected lesson.
- Below all sections: a terracotta "Export readiness" confirmation banner.

### 4. Document Intake
- Purpose: import source documents (pacing guides, calendars, lesson materials) and see what was parsed.
- Layout: `padding:28px`, two-column grid: ~340px left list panel + flexible right preview panel.
- Left panel: "Document intake" (h1) + primary "Add documents…" button. Intro copy below. Then an **imported-state summary card** (amber, rounded) showing a count and per-type breakdown, with a "Clear and start over" text link that resets to the empty state. Below: a scrollable list of imported document rows (name + type + "Text extracted locally").
- Right panel has **two mutually-exclusive states**, switched by the same import/clear toggle:
  - Empty: centered dashed-border (`--color-accent-300`) drop-zone card with an upload icon, "Choose setup documents" (h2), and helper copy.
  - Imported: centered solid card with a checkmark icon, "All set for this week" (h2), and confirming copy.

### 5. Workspace
- Purpose: browse/manage the full document library.
- Layout: `padding:28px`, vertical scrollable list, header row ("Workspace" + a "N documents"/"N selected" counter that updates live).
- Each row: rounded card (`--radius-lg`, `shadow-sm`), left checkbox (toggles a selected outline state), name (14.5px, 600) + metadata line (modules/lessons/days/dates, 12px muted), right-aligned secondary "Edit" button that expands an assessments detail line below the row (`border-top` divider, 12.5px muted text).

## Interactions & Behavior
- **Nav**: click any of the 5 top-nav buttons to switch the visible screen; active state is solid-fill + shadow.
- **Today**: add a schedule block (title/instruction/start/end → appended to the periods grid); remove any period card via its trash icon; add a checklist task (text input + Add, or press the Add button); click a checkbox to toggle done (strikethrough + tint); remove a task via its x button.
- **This Week**: click Plan/Deck/Guide pills per lesson to toggle their "generated" state independently (visual only in this reference — wire to real generation calls in production).
- **Planning Preview**: click a lesson in the sidebar to select it (loads its fields into the editor); click any accordion header to expand/collapse that section (only one open at a time is *not* enforced — multiple can be open); edit any field to update the selected lesson's data; change the Status select to update its tag elsewhere in the list.
- **Document Intake**: "Add documents…" switches to the imported state (in production, opens a real file/folder picker); "Clear and start over" switches back to the empty state — these two states are mutually exclusive and drive both the left summary and the right illustration panel together.
- **Workspace**: click a row's checkbox to select/deselect (updates the header counter); click "Edit" to expand/collapse that row's assessment detail.
- **Hover/depth**: cards and buttons rest at `shadow-sm` and animate to `shadow-md` (+ a 1-2px lift on period/lesson cards) on hover — implement as a CSS transition on `box-shadow`/`transform`, ~150ms.
- No loading or error states are represented in this reference — this is a working-app style prototype with local mock data, not wired to a backend.

## State Management
Minimal local state, all colocated per screen in this reference (a real implementation should likely use a shared store):
- `view`: which of the 5 screens is active.
- `blocks[]`: today's schedule blocks (id, start, end, title, instruction, subject) + a small "new block" form state.
- `checklist[]`: task items (id, text, done) + "new task" text field.
- `week[]`: 5 days, each with `lessons[]` (id, time, title, subject, source, planAdded/deckAdded/guideAdded booleans).
- `lessons[]`: ~14 lesson records (id, title, subject, status, coreTitle, grade, objective, stepTitle, stepNotes, materials, assessment, differentiation, prompt, source) + `selectedLessonId`.
- `openCore/openSequence/openMaterials/openDifferentiation/openSource`: accordion open/closed booleans.
- `intakeImported`: boolean driving both intake panels.
- `workspace[]`: document rows (id, name, modules, lessons, days, dates, assessments, expanded, selected).

## Design Tokens
See the "Design tokens" subsection above under Design System — all values are also literally present as CSS custom properties at the top of `Lesson Planner.dc.html`'s `<style>` block, and in `_ds/broadsheet-.../styles.css` for the base (un-overridden) system values for reference.

## Assets
No external image assets. All icons are hand-inlined SVGs (duotone style: a filled 15–25%-opacity background shape + a full-opacity stroke/fill foreground, matching the Broadsheet system's "Phosphor duotone" icon guidance) directly in the markup — no icon font or sprite sheet dependency. Avatar and nav mark are CSS gradients, not images.

## Screenshots
`screenshots/01-today.png`, `02-this-week.png`, `03-planning-preview.png`, `04-document-intake.png`, `05-workspace.png` — one reference capture per screen, for quick visual lookup alongside the written spec above.

## Files
- `Lesson Planner.dc.html` — the full design reference (all 5 screens, inline styles + a small state-management class simulating interactivity). This is the file to read for exact markup, structure, and copy.
- `_ds/broadsheet-a6f96984-e199-4c49-9e81-c97d9c75cda4/styles.css` — the base design-system stylesheet the design is built on (component classes, base token values before this design's warm-palette override).
- `_ds/broadsheet-a6f96984-e199-4c49-9e81-c97d9c75cda4/_ds_bundle.js` — the compiled design-system bundle referenced by the HTML file (defines print/separation filter defs used elsewhere in the system; not load-bearing for this particular design beyond being referenced in `<helmet>`).
- `_ds/broadsheet-a6f96984-e199-4c49-9e81-c97d9c75cda4/readme.md` — the design system's own documentation (palette philosophy, type, components, dos/don'ts) — useful background for how the base tokens were derived before this design's warm override.
