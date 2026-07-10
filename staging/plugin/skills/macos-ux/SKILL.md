---
name: macos-ux
description: macOS HIG design + review skill. Design mode interviews the user about their app's UX structure and produces a HIG-compliant UX-BLUEPRINT.md (window types, navigation, Settings, menu bar, toolbar, keyboard shortcuts) before any code is written. Review mode audits existing SwiftUI files for structural HIG violations (wrong navigation pattern, settings in a sheet, missing menu/shortcut, bad dialog button roles, window-type misuse). Triggers: "macos-ux", "design my mac app", "macOS UX", "HIG review", "review mac app", "ux blueprint". Also invoked from the concept-to-code chain orchestrator at Gate 1c.
---

# macOS UX Skill

## 1. Modes and when to invoke

**Design mode** (default): before writing any SwiftUI. You have a SPEC or feature idea but haven't decided the window structure, navigation pattern, or menu layout. Produces `UX-BLUEPRINT.md` — the single source of truth for the app's UX skeleton. The architect agent reads this to generate consistent ADR + plan decisions.

**Review mode**: after writing SwiftUI views. Audits for HIG structural violations. This is a *structural* audit only — it does not duplicate `ui-layout-audit` (layout/overflow mechanics) or `swiftui-pro` (general SwiftUI code quality). Scope: navigation pattern, window types, settings placement, dialogs, menu bar coverage, keyboard shortcut completeness.

Do NOT invoke for:
- Layout bugs (truncation, overflow, scroll) → use `ui-layout-audit`.
- General SwiftUI code quality → use `swiftui-pro`.
- Architecture decisions → that is the `architect` agent's job.

---

## 2. Mode dispatch

Parse `$ARGUMENTS`:
- Starts with `review` (e.g. `review MyView.swift`, `review`) → enter **Review mode** (§5). Optional remainder is the file/glob target.
- Anything else (including empty) → enter **Design mode** (§3).

---

## 3. Design mode — interview flow

Load `~/.claude/skills/macos-ux/references/macos-hig.md` for reference during the interview.

**Conduct rules** (same as design-brainstorm):
- One `AskUserQuestion` at a time, max 4 options.
- Synthesize 1–2 lines after each answer before moving on.
- Present options with Pros/Cons and mark a recommended option (first in list, " (Recommended)" label) — the trade-off decision remains the user's.
- Time-box the full interview at 6–8 exchanges. If a topic is clearly not applicable, skip it.
- Tone: direct, technical, no filler.

Work through the following topics in order. Skip a topic if the user's answers so far already make it unambiguous.

### Topic 1 — App archetype and primary window

```
question: "What best describes your app's primary window pattern?"
header: "App archetype"
options:
  - label: "Single main window"
    description: "One persistent window — the whole app lives here (like Finder, Notes, Mail). WindowGroup with one entry point."
  - label: "Library → detail"
    description: "Sidebar lists items; right side shows detail. Suitable for document-manager or data-browsing apps. NavigationSplitView 2-3 columns."
  - label: "Utility / panel"
    description: "Small floating tool window — always on top or hidden when not focused. Window scene + utilityWindow style."
  - label: "Menu bar extra (no main window)"
    description: "Lives in the system menu bar; popover or minimal window on click. MenuBarExtra scene."
```

### Topic 2 — Primary navigation structure

Ask only if the archetype from Topic 1 is "Single main window" or "Library → detail".

```
question: "How does the user navigate between major sections of the app?"
header: "Navigation"
options:
  - label: "Sidebar + content (NavigationSplitView)"
    description: "Standard macOS pattern. Sidebar lists sections; content area on the right. Supports .sidebar style, disclosure groups, collapsible."
  - label: "Single content area, no navigation"
    description: "The app does one thing and shows it directly — no sidebar needed."
  - label: "Drill-down / detail stack"
    description: "Users tap into items hierarchically. NavigationStack appropriate."
  - label: "Tabs (secondary areas only)"
    description: "TabView is acceptable for secondary panels inside a window, but NOT as the primary Mac navigation pattern."
```

> NOTE: TabView as the primary macOS navigation pattern is a HIG violation (M2). If the user selects it, note this and recommend NavigationSplitView; record the user's final decision honestly in the blueprint.

### Topic 3 — Settings

```
question: "Does your app have user preferences or settings?"
header: "Settings"
options:
  - label: "Yes — standard Settings window (Cmd+,)"
    description: "Settings scene in SwiftUI App. Automatically wires Cmd+, and the menu item. Tabbed if multiple categories."
  - label: "Yes — but minimal, just 2-3 toggles"
    description: "Still use the Settings scene; a single-tab Settings window is fine."
  - label: "No settings"
    description: "No preferences. Skip this entirely."
```

> NOTE (M11): **Settings windows must never show a scrollbar.** If a tab's content is too long to fit at 1080p without scrolling, split it into additional tabs. Never wrap Settings tab content in `ScrollView`. Record how many tabs the user expects — if >1, ask what goes in each.

### Topic 4 — Menu bar commands

```
question: "Which categories of actions should live in the menu bar?"
header: "Menu bar"
options:
  - label: "Standard only (File/Edit/View/Window/Help auto-provided)"
    description: "No custom menus. SwiftUI provides the standard set. Suitable for simple apps."
  - label: "Custom actions in existing menus"
    description: "Add items to File, Edit, or View menus (CommandGroup .before/.after). List the key actions."
  - label: "One or more custom top-level menus"
    description: "New CommandMenu entries for app-specific verbs (e.g. Format, Data, Tools)."
  - label: "Full custom menu bar"
    description: "Replace standard menu items substantially. High complexity — confirm with the user."
```

After the user answers, ask a follow-up if they chose a custom option: "List the 3–5 most important actions that must be accessible from the menu bar."

### Topic 5 — Toolbar

```
question: "What primary actions should live in the toolbar (the bar below the title bar)?"
header: "Toolbar"
options:
  - label: "New item / primary create action"
    description: "Placement: .primaryAction. SF Symbol + label."
  - label: "Navigation controls (back/forward)"
    description: "Placement: .navigation. Standard chevron symbols."
  - label: "Mode or view switcher"
    description: "Segmented control or picker in .principal placement."
  - label: "No toolbar needed"
    description: "All actions are in menus or the main content area."
```

Note: toolbar items without a matching menu/shortcut are a partial HIG violation (M4). If the user lists toolbar-only actions, flag this and recommend adding corresponding menu items.

### Topic 6 — Inspector / secondary windows

```
question: "Does your app need an inspector panel or secondary windows?"
header: "Inspector / panels"
options:
  - label: "Inspector panel (trailing column in NavigationSplitView)"
    description: "Shows properties of the selected item. Third column in a 3-column split view. Best macOS-native pattern."
  - label: "Separate inspector window (Window scene)"
    description: "Floating panel separate from the main window. Use when the inspector content is large or the user wants to detach it."
  - label: "Sheet for occasional secondary UI"
    description: ".sheet for flows that block interaction with the main window until complete."
  - label: "No secondary windows"
    description: "Everything in the main window."
```

### Topic 7 — Keyboard shortcuts baseline

```
question: "Which standard keyboard shortcuts does your app need beyond Cmd+W / Cmd+Q?"
header: "Shortcuts"
options:
  - label: "Cmd+N (new document/item)"
    description: "Standard create action."
  - label: "Cmd+, (Settings) — already free if Settings scene used"
    description: "Auto-wired by Settings scene."
  - label: "Cmd+R or Cmd+Return (primary commit/action)"
    description: "For apps with a primary action like search, run, or send."
  - label: "None beyond standard"
    description: "The standard set (Cut/Copy/Paste/Undo/Redo/Select All) is sufficient."
```

This is multiSelect — the user may pick multiple. After the answer, note any toolbar actions that need a shortcut and weren't listed.

### Topic 8 — Accessibility baseline

```
question: "Which accessibility features are required for your first release?"
header: "Accessibility"
options:
  - label: "VoiceOver labels on all controls"
    description: ".accessibilityLabel on all interactive elements that lack a text label."
  - label: "Dynamic Type support"
    description: "Use semantic fonts (.body, .title2) not fixed sizes. Required for system font scaling."
  - label: "Full keyboard access"
    description: "Every action reachable without the mouse. .focusable() on custom controls."
  - label: "Minimum viable (labels only)"
    description: "Only obvious unlabeled controls get labels. Acceptable for internal tools."
```

---

## 4. Output contract — UX-BLUEPRINT.md

After all topics are covered, write `UX-BLUEPRINT.md` at `<project-root>/UX-BLUEPRINT.md`.

This file is the UX skeleton. No code. No ADR. No plan. The architect reads it to generate consistent Scene/container decisions and reflects it in the ADR.

### Mandatory structure

```markdown
# UX Blueprint — <topic/feature name>

## Window inventory

| Window | Type | SwiftUI Scene / Style | Notes |
|--------|------|-----------------------|-------|
| Main window | WindowGroup | NavigationSplitView | Primary content |
| Settings | Settings | TabView (2 tabs: General, Advanced) | Cmd+, auto-wired |
| … | … | … | … |

## Navigation structure

<prose description of the primary navigation pattern, with the specific SwiftUI
type to use (NavigationSplitView / NavigationStack / none), column layout, and
what each column/section contains>

## Settings layout

<list of settings tabs and the preferences in each; or "No settings" if none>

## Menu bar map

| Menu | Item | Shortcut | Action |
|------|------|----------|--------|
| File | New Item | Cmd+N | Creates a new … |
| … | … | … | … |

## Toolbar items

| Item | Symbol | Placement | Shortcut | Notes |
|------|--------|-----------|----------|-------|
| New | plus | .primaryAction | Cmd+N | Creates … |
| … | … | … | … | … |

## Keyboard shortcuts

| Action | Shortcut | Source |
|--------|----------|--------|
| New | Cmd+N | File menu + toolbar |
| Settings | Cmd+, | Settings scene auto |
| Close window | Cmd+W | Auto-provided |
| … | … | … |

## Accessibility checklist

- [ ] VoiceOver labels on all unlabeled interactive controls
- [ ] Semantic fonts used (no fixed sizes)
- [ ] All actions reachable without the mouse
- [ ] Increase Contrast mode tested

## Notes for the architect

<2–4 bullet points: key Scene types to use, critical SwiftUI structural decisions,
any HIG caveats or trade-off decisions made during the interview>
```

**Quality invariants:**
- The Window inventory covers every distinct window/panel/scene.
- Every toolbar item has a matching menu entry and shortcut (or is explicitly noted as toolbar-only by user decision).
- Settings placement uses the Settings scene (not a sheet or custom modal).
- No code snippets — just type names and notes.

---

## 5. Review mode

### 5.1 Determine target files

If `$ARGUMENTS` after `review` is non-empty, use that path/glob. Otherwise:
```bash
git diff --name-only HEAD | grep '\.swift$'
```
If empty, fall back to:
```bash
find . -maxdepth 5 -name "*.swift" | grep -v "/.build/" | grep -v "/DerivedData/"
```

### 5.2 Load reference

Load `~/.claude/skills/macos-ux/references/macos-hig.md` for the violation catalog.

### 5.3 Scope guard

This skill reviews **structural/HIG issues only**:
- Wrong navigation pattern (e.g. TabView as primary Mac nav)
- Settings presented via sheet/modal instead of Settings scene
- Actions accessible only from a button (not from menu bar)
- Dialog button roles/order wrong
- Wrong window type for the use case
- Missing standard keyboard shortcut on a primary action

Do NOT flag:
- Text truncation, overflow, fixed heights — that is `ui-layout-audit`
- General SwiftUI code quality, API choices — that is `swiftui-pro`
- Architecture or data-model decisions — that is outside scope

### 5.4 Checklist (reference macos-hig.md M1–M10)

Apply each relevant check from the HIG catalog:

| ID | Check |
|----|-------|
| M1 | Window types: Settings presented via Settings scene, not .sheet |
| M2 | Primary navigation: NavigationSplitView (not TabView) for primary Mac nav |
| M3 | Settings scene used; Cmd+, wired |
| M4 | Every toolbar/primary-action button also reachable from menu bar with shortcut |
| M5 | Toolbar items use .toolbar with placement + label |
| M6 | Dialogs use Alert/confirmationDialog; button roles correct; no custom modal for simple confirm |
| M7 | Standard shortcuts (Cmd+W, Cmd+N where applicable) present |
| M8 | Window sizing: .defaultSize or .frame(min/ideal/max), not fixed .frame on WindowGroup |
| M9 | Sidebar: .listStyle(.sidebar), section headers where relevant |
| M10 | VoiceOver labels on unlabeled interactive elements |
| M11 | Settings tabs contain no `ScrollView` or uncontrolled `List`; `Form` used as root container; tab height fits screen without scrolling |

**Severity:**
- **P1** (auto-fix): Settings in a sheet instead of Settings scene; TabView as primary mac nav; missing `.listStyle(.sidebar)` on a clearly intended sidebar; alert with wrong button role order.
- **P2** (auto-fix): Missing `.accessibilityLabel` on a control with no text label; `.frame(width:height:)` on WindowGroup content (fixed size, no resizability).
- **P3** (recommend only): Missing menu item for a toolbar action; no `.defaultSize` on a window; no keyboard shortcut on primary action.

### 5.5 Report and fix

Emit a findings table per file (same format as `ui-layout-audit`):

```
## HIG review: <filename>

| ID  | Line | Sev | Description                                  | Fix applied |
|-----|------|-----|----------------------------------------------|-------------|
| M1  | 12   | P1  | Settings presented via .sheet → Settings scene | yes |
```

Apply P1 and P2 fixes via Edit (emit PATTERN: line per ADR-0001 before each edit). Re-read after each fix to verify no syntax breakage; revert if broken.

Emit per-file summary:
```
macos-ux review: <filename> — N issues fixed (P1: N, P2: N) | N P3 recommendations
```

---

## 6. References

Load `~/.claude/skills/macos-ux/references/macos-hig.md` when:
- In design mode: to frame questions and validate user decisions against HIG.
- In review mode: for the violation catalog and fix patterns.

Do not load it unless actively needed (progressive disclosure, consistent with swiftui-pro pattern).

---

## 7. Chain invocation — return contract

This section activates when the invocation contains `Chain context: concept-to-code (gate 1c)`.

When invoked from Gate 1c:
1. Run design mode (§3–4).
2. Write `UX-BLUEPRINT.md` at `<project-root>/UX-BLUEPRINT.md`.
3. **Do NOT produce any closing response, summary, or handoff message** after writing the file.
4. **End execution silently**: the concept-to-code orchestrator continues immediately and handles the manifest update (`artifacts.ux_blueprint`), state transition, and architect dispatch.

Emitting a closing message breaks the chain (ends the turn; orchestrator never resumes). End silently.
