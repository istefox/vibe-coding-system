---
paths:
  - "**/*.swift"
---

# Swift / SwiftUI

- Swift 6 + SwiftUI; UIKit solo se una feature lo richiede. iOS + macOS dalla stessa codebase quando possibile.
- `@Observable` (no `ObservableObject`) per nuovo codice. Mai force-unwrap `!` o `try!` in produzione.
- View < 150 righe: estrai in private struct. `body` puro: side-effect in `.task`/`.onAppear`/`.onChange`.
- `LazyVStack`/`LazyHStack` per liste lunghe. Testi utente in `Localizable.strings`.
- Package manager: SPM only (mai CocoaPods/Carthage).
- Test: Swift Testing (Swift 6) per nuovi test; XCTest solo per suite legacy esistenti.
- SwiftLint (+ `.swiftlint.yml`) e swift-format (Apple). 1 type principale per file, raggruppa per feature.
- Quirk: Claude edita i `.swift`, Xcode rileva e ricarica da solo.

## Swift 6 Concurrency — Correctness

- `deinit` MUST NOT access `self` members that are actor-isolated or captured in async closures. Cancel `Task` handles stored as `nonisolated(unsafe) var`; do not touch actor state in deinit.
- `@MainActor` class `deinit`: safe to access `@MainActor` state only if deallocation is guaranteed on the main actor. Use `nonisolated` for `deinit` when uncertain; schedule cleanup via a detached `Task`.
- Every actor that calls `startAccessingSecurityScopedResource()` must call `stopAccessingSecurityScopedResource()` in every exit path — use `defer` at the call site. A missed `stop` silently revokes sandbox access.
- `AsyncStream` continuations: always call `continuation.finish()` in the `onTermination` handler to prevent consumer tasks from hanging on actor deallocation.
- Two actors cooperating: pass `Sendable` value types across the boundary (snapshot in, outcome out). Never store a reference to another actor as a property.
- `nonisolated` functions on an actor cannot access actor-isolated state. If actor state is needed, make the function `async` and `await` the actor-isolated property.

## AppKit + SwiftUI Bridge — Correctness

- `NSHostingView` / `NSHostingController` inside an `NSPanel` must be created on `@MainActor`. Never create them in a background context.
- `NSApp.activate(ignoringOtherApps:)` ONLY on explicit user trigger (hotkey, menu click). Never call it on launch or programmatic panel show — breaks `.accessory` activation policy.
- `NSPanel` with `.nonactivatingPanel` does NOT fire `windowDidBecomeKey` on show. Use `makeKeyAndOrderFront` + `orderFrontRegardless` explicitly when key status is needed.
- `KeyboardShortcuts.Recorder` requires `Binding<KeyboardShortcuts.Name>` where the name is a `static` extension on `KeyboardShortcuts.Name`. Passing a local `@State` string binding does not compile.
- `resignFirstResponder()` on an `NSTextView` embedded via `NSViewRepresentable` must be called on the `NSTextView` instance directly — calling it on the hosting view is a no-op.
- `NSPopover` anchored to an `NSRect` inside `NSTextView` must be AppKit-owned. SwiftUI `.popover` cannot anchor to an arbitrary rect and falls back to window-level positioning.
