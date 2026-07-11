# macOS HIG Catalog

Each entry is dual-framed: **Design** (what to use and when) + **Review** (violation → fix pattern).
IDs M1–M11 map to the checklist in macos-ux SKILL.md §5.4.

---

## M1 — Window types

### Design
Choose the right Scene type for each window:

| Window role | SwiftUI Scene | Notes |
|-------------|---------------|-------|
| Main app window | `WindowGroup` | The primary entry point. Supports multiple instances on macOS. |
| Settings/Preferences | `Settings { TabView { … } }` | Auto-wires Cmd+, and the "Settings…" menu item. Always tabbed when ≥2 categories. |
| Utility / floating panel | `Window("Title", id: "util") { … }.windowStyle(.titleBar)` | Non-document, non-restorable. For tools that float alongside the main window. |
| About box | `Window("About", id: "about") { … }` | Small, fixed size. |
| Inspector (attached) | Trailing column of `NavigationSplitView` | Prefer this over a separate window for item properties. |
| Document window | `DocumentGroup` | Only when the app is document-based (file open/save). |

### Review — violations and fixes

**V1a: Settings in a `.sheet`**
Pattern: `.sheet(isPresented: $showSettings) { SettingsView() }`
Fix: Move `SettingsView` content into the `Settings` scene in the `@main App` struct:
```
// Replace sheet with:
Settings {
    TabView {
        GeneralSettingsView().tabItem { Label("General", systemImage: "gear") }
    }
}
```
Severity: P1 — breaks the system Cmd+, convention; users can't find settings.

**V1b: Using `WindowGroup` for a utility tool that should be a panel**
Pattern: `WindowGroup { UtilityView() }` where the view is clearly a secondary tool.
Fix (P2): Change to `Window("Tool Name", id: "tool") { UtilityView() }.windowResizability(.contentSize)`.

---

## M2 — Primary navigation pattern

### Design
Choose the navigation container based on the app's information architecture:

| Pattern | SwiftUI type | Use when |
|---------|-------------|----------|
| Library / master-detail | `NavigationSplitView(sidebar:content:detail:)` | The app manages a collection (notes, emails, tasks, contacts). Sidebar lists categories; content lists items; detail shows the selected item. |
| Single drilldown | `NavigationStack` | The user navigates into progressively nested content from one starting point. |
| Single view, no nav | Plain `VStack`/`ZStack` | The app has one main view and no navigation is needed. |
| Document tabs | `.tabItem` inside `TabView` | Acceptable for secondary panels *within* a main window (e.g., tabs in a code editor). |

**TabView as the PRIMARY macOS navigation is a HIG violation.**
Users expect sidebar-based navigation on macOS. A TabView along the bottom is an iOS pattern.

### Review — violations and fixes

**V2a: `TabView` as primary Mac navigation**
Pattern:
```swift
TabView {
    HomeView().tabItem { Label("Home", systemImage: "house") }
    SettingsView().tabItem { Label("Settings", systemImage: "gear") }
}
```
Fix (P1): Replace with `NavigationSplitView`. Move sections to a sidebar `List`:
```swift
NavigationSplitView {
    List(selection: $selection) {
        Label("Home", systemImage: "house").tag(Section.home)
        Label("Settings", systemImage: "gear").tag(Section.settings)
    }
    .listStyle(.sidebar)
} detail: {
    switch selection { case .home: HomeView() … }
}
```
Note: this is a structural change — flag and explain rather than silently rewriting large view trees. Apply only if the view is small (<50 lines). Otherwise P3 recommendation.

---

## M3 — Settings placement

### Design
Always use the `Settings` scene. Benefits:
- Automatic "Settings…" menu item in the app menu (macOS 13+) or "Preferences…" (macOS 12).
- Automatic Cmd+, keyboard shortcut.
- Window management handled by the system.
- Tabbed automatically when wrapped in `TabView`.

Minimal settings (1–2 toggles): a single-tab Settings window is fine — no forced TabView.
`@AppStorage` for persisted values; `@Environment(\.dismiss)` is NOT needed (Settings window is closed by the system).

### Review — violations and fixes

**V3a: Settings via `.sheet`** — same as V1a, P1 fix.

**V3b: Settings as a separate `WindowGroup` triggered by a button**
Pattern: `openWindow(id: "settings")` where that window is actually a preferences UI.
Fix (P2): Replace the `WindowGroup` for settings with `Settings { … }`. Remove the `openWindow` call; Cmd+, handles it.

**V3c: Settings toolbar button without Cmd+, shortcut**
Pattern: `Button("Settings") { showSettings = true }` with no `.keyboardShortcut(",", modifiers: .command)`.
Fix (P3, recommend): Either move to `Settings` scene (best), or add `.keyboardShortcut(",", modifiers: .command)` if the sheet approach is intentional.

---

## M4 — Menu bar coverage

### Design
Every primary action must be reachable from the menu bar. This is a core macOS convention.

Guidelines:
- Use `CommandGroup(replacing:)` to replace default items; `CommandGroup(after:)` / `CommandGroup(before:)` to insert near existing items.
- Use `CommandMenu("CustomName")` for new top-level menus.
- Toolbar actions should mirror a menu item (same shortcut, same label).
- Standard actions (Cut/Copy/Paste/Undo/Redo/Select All) are auto-provided — don't duplicate.
- Help menu: add a `CommandGroup(replacing: .help)` entry pointing to your help content.

### Review — violations and fixes

**V4a: Primary action only on a toolbar button, no menu item**
Pattern: `ToolbarItem(placement: .primaryAction) { Button("Sync") { sync() } }` with no matching `CommandMenu` or `CommandGroup` item.
Fix (P3, recommend): Add a menu command in the App's `.commands { }` block.

**V4b: `Button` in the main content area for a primary verb (not in toolbar or menu)**
Fix (P3): Move to toolbar and add menu item; leave content area button as secondary action.

---

## M5 — Toolbar items

### Design
Toolbar items use `.toolbar { }` modifier on `NavigationSplitView`, `NavigationStack`, or the window's root view.

Key placements:
- `.primaryAction` — main create/action button, right side.
- `.navigation` — back/forward navigation, left side.
- `.principal` — center, e.g. a title or mode picker.
- `.automatic` — system decides (appropriate for most secondary actions).
- `.confirmationAction` / `.cancellationAction` — in sheets/dialogs.

Every toolbar item should have:
- A `Label("Name", systemImage: "sf.symbol")` — both label and icon.
- A matching menu command with the same shortcut (see M4).

### Review — violations and fixes

**V5a: ToolbarItem with only an icon, no label**
Pattern: `Button { Image(systemName: "plus") }`
Fix (P2): Replace with `Label("New", systemImage: "plus")`.

**V5b: `.toolbar { Button { … } }` without `ToolbarItem(placement:)`**
Fix (P3): Wrap in `ToolbarItem(placement: .primaryAction)` (or appropriate placement) for deterministic placement.

---

## M6 — Dialogs and alerts

### Design
- **Destructive confirmation**: use `.confirmationDialog` (sheet-style) or `Alert`.
- **Error**: use `Alert` with `.alert(isPresented:) { Alert(title:, message:, dismissButton:) }`.
- **Button ordering (macOS convention)**: Cancel on the left (or .cancel role), primary/destructive action on the right. SwiftUI handles this automatically via button roles.
- Use `.destructive` role on destructive buttons.
- **Never** use a custom modal view for a simple yes/no confirm — always use `Alert` or `confirmationDialog`.

### Review — violations and fixes

**V6a: Custom `VStack` with "Cancel" / "Delete" buttons for a destructive confirm**
Fix (P1): Replace with `.confirmationDialog("Are you sure?", isPresented: $showConfirm) { Button("Delete", role: .destructive) { … } }`.

**V6b: `Alert` with destructive button but missing `.destructive` role**
Pattern: `Alert(title:, primaryButton: .default(Text("Delete")) { … })`
Fix (P1): Change to `.destructive(Text("Delete")) { … }`.

---

## M7 — Keyboard shortcuts

### Design
Required baseline for most macOS apps:

| Action | Shortcut | Notes |
|--------|----------|-------|
| Close window | Cmd+W | Auto-provided by `WindowGroup`; do NOT override unless intentional |
| Quit | Cmd+Q | Auto-provided |
| Settings | Cmd+, | Auto-provided by `Settings` scene |
| New item/document | Cmd+N | Add via `CommandGroup(replacing: .newItem)` or toolbar |
| Undo/Redo | Cmd+Z / Cmd+Shift+Z | Auto-provided for UndoManager |
| Cut/Copy/Paste | Cmd+X/C/V | Auto-provided for text fields |

For every primary toolbar action, add `.keyboardShortcut` on the corresponding `CommandGroup`/`CommandMenu` item.

### Review — violations and fixes

**V7a: Primary create/action button in toolbar with no keyboard shortcut**
Fix (P3): Add to the commands block with `.keyboardShortcut("n", modifiers: .command)` (or appropriate shortcut).

**V7b: Cmd+W overridden to do something other than close the window**
Fix (P1): Remove the override unless there is a documented intentional reason (e.g. "close document" in a document-based app is intentional).

---

## M8 — Window sizing and restoration

### Design
- Use `.defaultSize(width:height:)` on `WindowGroup` or `Window` to set the initial size.
- Use `.windowResizability(.contentSize)` for utility windows that should auto-size to their content.
- Use `.frame(minWidth:idealWidth:maxWidth:minHeight:idealHeight:maxHeight:)` on the root view to constrain the window.
- Do NOT use `.frame(width:height:)` (fixed size) on a `WindowGroup` root — the user cannot resize.
- State restoration: `@SceneStorage` for per-window transient state; `@AppStorage` for persistent preferences.

### Review — violations and fixes

**V8a: Fixed `.frame(width:height:)` on `WindowGroup` root content**
Pattern: `ContentView().frame(width: 800, height: 600)` inside a `WindowGroup`.
Fix (P2): Change to `.frame(minWidth: 600, idealWidth: 800, maxWidth: .infinity, minHeight: 400, idealHeight: 600, maxHeight: .infinity)`.

**V8b: No `.defaultSize` on a new app's `WindowGroup`**
Fix (P3): Add `.defaultSize(width: 900, height: 600)` (or appropriate values) to the `WindowGroup`.

---

## M9 — Sidebar

### Design
Use `.listStyle(.sidebar)` on any `List` in the sidebar column of a `NavigationSplitView`.

Sidebar best practices:
- Group items with `Section` headers.
- Support `selection` binding for programmatic navigation.
- Use `DisclosureGroup` for expandable sub-sections.
- Avoid putting non-list content (e.g. forms, text editors) in the sidebar column.
- Minimum sidebar width: typically 180–220 pt.

### Review — violations and fixes

**V9a: Sidebar `List` without `.listStyle(.sidebar)`**
Pattern: `List { … }` in the first column of `NavigationSplitView` without `.listStyle(.sidebar)`.
Fix (P1): Add `.listStyle(.sidebar)`.

**V9b: Using `VStack` with custom tap-to-select for sidebar navigation instead of `List`**
Fix (P2): Replace with a `List(selection:)` and `.listStyle(.sidebar)` for proper highlight + keyboard navigation.

---

## M10 — Accessibility baseline

### Design
Minimum requirements for a first macOS release:

1. **VoiceOver labels**: every `Button`, `Toggle`, `Slider`, or custom control without a visible text label needs `.accessibilityLabel("Description")`.
2. **Dynamic Type**: use semantic fonts (`.font(.body)`, `.font(.title2)`) not fixed sizes. `Text` automatically scales; custom views need `.dynamicTypeSize(…)` constraints if they have minimum sizes.
3. **Full keyboard access**: every interactive control must be reachable without the mouse. Custom controls need `.focusable()`. `FocusState` for multi-step forms.
4. **Reduce Motion**: for animated transitions, check `@Environment(\.accessibilityReduceMotion)` and skip or minimize animations.

### Review — violations and fixes

**V10a: Icon-only `Button` without `.accessibilityLabel`**
Pattern: `Button { Image(systemName: "plus") } action: { … }` — no text label, no accessibility label.
Fix (P2): Add `.accessibilityLabel("Add item")` (or the appropriate description).

**V10b: Fixed `.font(.system(size: 14))` on user-visible text**
Fix (P3): Replace with `.font(.body)` or the appropriate semantic style.

**V10c: Custom tappable view without `.focusable()`**
Pattern: `Color.blue.onTapGesture { … }` used as an interactive element.
Fix (P2): Wrap in `Button` (preferred) or add `.focusable()` + `.onKeyPress(.return) { … }`.

---

## M11 — No scrollbars in Settings

### Design
The Settings window must never show a scrollbar. macOS Settings (Preferences) is a fixed-height panel where the user expects instant access to all options — scrolling signals a content organisation problem, not a layout constraint.

Rules:
- **Split dense tabs into more tabs** rather than letting a single tab grow too long. Each tab should be visible in full at 1080p with no scrolling.
- **Remove `ScrollView`** from all Settings tab content. If content does not fit, restructure: add a tab, remove low-priority options, or move advanced options to a sub-panel opened by a button.
- **Never rely on dynamic sizing** that causes the Settings window to grow beyond the screen — use `.fixedSize()` or explicit `Form` / `VStack` with no scroll wrapper.
- **Use `Form`** as the root container for each Settings tab. `Form` on macOS renders as a system-standard grouped layout and does not scroll by default when the window is sized to fit its content.

Typical max height before a tab needs splitting: ~400–500 pt (roughly 10–12 rows of Form content).

### Review — violations and fixes

**V11a: `ScrollView` inside a Settings tab**
Pattern:
```swift
Settings {
    TabView {
        ScrollView {
            VStack { /* lots of settings rows */ }
        }
        .tabItem { Label("General", systemImage: "gear") }
    }
}
```
Fix (P1): Remove `ScrollView`. Replace with a plain `Form` or `VStack`. If content still overflows, split into additional tabs:
```swift
Settings {
    TabView {
        Form { /* general options */ }
            .tabItem { Label("General", systemImage: "gear") }
        Form { /* advanced options */ }
            .tabItem { Label("Advanced", systemImage: "gearshape.2") }
    }
}
```

**V11b: Settings tab content taller than ~500 pt with no scroll, but visually dense**
Fix (P3 recommendation): Audit which rows can be removed or moved to an "Advanced" tab. A Settings tab that requires the user to read for >5 seconds to find an option is too long.

**V11c: `List` used as Settings tab content without `.scrollDisabled(true)`**
Pattern: `List { /* settings rows */ }` inside a Settings tab — `List` has built-in scroll.
Fix (P1): Replace with `Form` (preferred for Settings). If `List` is intentional, add `.scrollDisabled(true)` and ensure content fits the window height.
