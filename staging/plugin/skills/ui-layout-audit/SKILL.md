---
name: ui-layout-audit
description: Audit and fix SwiftUI or HTML/CSS views for layout bugs — text truncation, content overflow, spurious scrollbars, hard-coded sizes, dynamic-type blindness. Invoke after writing a view, before committing.
---

# UI Layout Audit

## When to invoke
- After writing or editing a SwiftUI view or HTML/CSS component.
- Before committing UI code — one pass catches hours of manual refinement.
- Trigger: "layout audit", "fix layout", "text truncated", "overflow", "scrollbar problem", "ui-layout-audit".

## Arguments

```
/skill ui-layout-audit [file-or-glob]
```

- `file-or-glob`: path to the file(s) to audit. If omitted, use all Swift files or HTML/CSS files modified in the current diff (`git diff --name-only HEAD`).

---

## Step 1 — Detect target files

If an explicit path was given, use it. Otherwise:

```bash
git diff --name-only HEAD | grep -E '\.(swift|html|css|tsx|jsx|vue)$'
```

If that returns nothing, fall back to:

```bash
find . -maxdepth 4 -name "*.swift" -o -name "*.html" -o -name "*.css" -o -name "*.tsx" -o -name "*.jsx" | grep -v "/.build/" | grep -v "/node_modules/"
```

Classify each file:
- `.swift` → SwiftUI path
- `.html`, `.css`, `.tsx`, `.jsx`, `.vue` → Web path

Audit each file independently using the checklist for its type.

---

## Step 2 — SwiftUI layout audit

For each `.swift` file, check every `View` struct for the following invariants. Flag each violation with severity **P1** (layout breaks), **P2** (degrades on some content), or **P3** (defensive — unlikely but possible).

### Text invariants

| ID | Rule | Severity | Fix |
|----|------|----------|-----|
| S1 | `Text(...)` inside a fixed-height `.frame(height: N)` container → text clips | P1 | Replace with `.frame(minHeight: N)` or remove height constraint; add `.fixedSize(horizontal: false, vertical: true)` |
| S2 | `Text(...)` without `.lineLimit(nil)` inside a horizontally-constrained container (e.g., `HStack`, `List`, `NavigationLink`) | P2 | Add `.lineLimit(nil)` or an explicit `.lineLimit(N)` with `.truncationMode` |
| S3 | Hard-coded `.frame(width: N)` on a `Text` that may contain variable-length strings | P2 | Replace with `.frame(maxWidth: N)` or let it size naturally |
| S4 | `.font(.system(size: N))` with a fixed size and no `.dynamicTypeSize` modifier | P2 | Use semantic fonts (`.font(.body)`, `.font(.caption)`) or add `.dynamicTypeSize(...)` |
| S5 | Long strings in `Text` with no word-wrap protection in a tight layout | P2 | Add `.multilineTextAlignment(.leading)` and verify parent is not width-constrained without `.fixedSize` |
| S6 | `Text` inside `Button` label without flexible layout — button clips on long text | P1 | Wrap in `HStack` with `Spacer()` or use `.frame(maxWidth: .infinity)` |

### Scroll and container invariants

| ID | Rule | Severity | Fix |
|----|------|----------|-----|
| S7 | `ScrollView` with a sibling `.frame(height: N)` that is a fixed value — content taller than N is clipped instead of scrolling | P1 | Change to `.frame(maxHeight: N)` or remove the fixed height |
| S8 | `VStack` / `LazyVStack` inside a `ScrollView` without `.frame(maxWidth: .infinity)` — content can shrink too narrow | P2 | Add `.frame(maxWidth: .infinity, alignment: .leading)` to the stack |
| S9 | `List` with `.listRowInsets(EdgeInsets())` and no padding on cell content — text touches edge | P3 | Add `.padding(.horizontal)` to cell content |
| S10 | Nested `ScrollView` (same axis) — inner scroll never activates, content clips | P1 | Remove inner `ScrollView` or change axis of one |

### Window and sheet invariants

| ID | Rule | Severity | Fix |
|----|------|----------|-----|
| S11 | `.sheet` / `.popover` content without a `ScrollView` wrapping dynamic content — overflow on small screens | P2 | Wrap the sheet body in `ScrollView` with a `.padding()` |
| S12 | `NavigationStack` title that is a long string without `.navigationBarTitleDisplayMode(.inline)` — title truncates silently | P3 | Add `.navigationBarTitleDisplayMode(.inline)` for titles > ~20 chars |
| S13 | `.popover` with a fixed `.frame` — overflows or clips on iPad vs iPhone | P1 | Use `.presentationDetents` or ensure frame uses `min/max` not fixed |

---

## Step 3 — HTML/CSS layout audit

For each web file, check for the following invariants.

### Text overflow invariants

| ID | Rule | Severity | Fix |
|----|------|----------|-----|
| W1 | `height: Npx` on a container that holds `<p>`, `<span>`, or dynamic text | P1 | Replace with `min-height: Npx` |
| W2 | `white-space: nowrap` without `text-overflow: ellipsis` and `overflow: hidden` | P1 | Add `overflow: hidden; text-overflow: ellipsis` or remove `nowrap` |
| W3 | `overflow-x: hidden` on `body` / root without checking that it hides a real overflow source | P2 | Trace the overflow source; fix it instead of hiding with `overflow-x: hidden` |
| W4 | Long words / URLs in `<p>` or `<div>` without `overflow-wrap: break-word` | P2 | Add `overflow-wrap: break-word; word-break: break-word` |
| W5 | `font-size: Npx` (fixed pixels) without a responsive fallback | P3 | Replace with `rem` units or add a media-query override |

### Container / flex / grid invariants

| ID | Rule | Severity | Fix |
|----|------|----------|-----|
| W6 | Flex child without `min-width: 0` — flex child overflows its parent when content is wide | P1 | Add `min-width: 0` to the flex child |
| W7 | Grid column defined as `repeat(N, Npx)` (fixed) without `minmax` or `auto-fit` | P2 | Change to `repeat(auto-fit, minmax(Npx, 1fr))` |
| W8 | `width: 100%` child inside a parent that has `padding` but `box-sizing: content-box` — child overflows by padding amount | P1 | Add `box-sizing: border-box` globally or on the child |
| W9 | Absolutely-positioned element without a `position: relative` ancestor — escapes container | P2 | Set `position: relative` on the intended containing parent |
| W10 | `z-index` on a non-positioned element (no `position` set) — has no effect but creates confusion | P3 | Add `position: relative` to the element, or remove the unused `z-index` |

### Scroll invariants

| ID | Rule | Severity | Fix |
|----|------|----------|-----|
| W11 | `overflow: auto` or `overflow: scroll` on a container with `display: flex` / `display: grid` — scroll fires even when content fits because the container doesn't shrink | P2 | Use `overflow: auto` only on a block container, or constrain the flex/grid with `max-height` |
| W12 | Horizontal scroll bar appearing on `<body>` — usually caused by a `100vw` element ignoring scrollbar width | P1 | Replace `width: 100vw` with `width: 100%` on full-bleed elements |

---

## Step 4 — Report findings

Emit a concise findings table grouped by file:

```
## Layout audit: <filename>

| ID  | Line | Severity | Description                             | Fix applied |
|-----|------|----------|-----------------------------------------|-------------|
| S1  | 42   | P1       | Fixed height 60 clips Text in HStack    | yes         |
| W6  | 15   | P1       | Flex child missing min-width:0          | yes         |
```

Totals: `P1: N  P2: N  P3: N`.

If 0 findings: emit `✓ <filename>: no layout issues found.`

---

## Step 5 — Apply fixes

**Apply all P1 and P2 fixes automatically** using the Edit tool. For each fix:
1. Show the PATTERN: line (Pre-flight Pattern Classifier — ADD/REMOVE/REPLACE/MODIFY).
2. Apply the edit.
3. Mark "Fix applied: yes" in the table.

**P3 fixes:** list as recommendations only (do NOT auto-apply). Emit them in a separate block:
```
### P3 recommendations (not auto-applied)
- <filename>:<line>: <recommendation>
```

After all fixes are applied, re-read each modified file and verify the fix is syntactically valid (no broken braces, no unclosed tags). If a fix introduced a syntax error, revert it and mark "Fix applied: reverted — manual fix needed".

---

## Step 6 — Summary

Emit a one-line summary per file:
```
ui-layout-audit: <filename> — N issues fixed (P1: N, P2: N) | N P3 recommendations | 0 regressions
```

If the project has a test command at `.claude/test-cmd`, run it after fixes:
```bash
cat .claude/test-cmd
# Run the command if not NONE
```

Report pass/fail. If red: list which files were edited and recommend reverting the failing changes one at a time.
