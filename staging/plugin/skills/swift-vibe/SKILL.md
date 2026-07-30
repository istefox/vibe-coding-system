---
name: swift-vibe
description: This skill should be used when working on SwiftUI/iOS code and ready-to-use modern patterns are helpful (Observable+Bindable iOS 17+, SwiftData @Query, URLSession async/await).
---
<!-- skill-coverage-exempt: snippet reference only — Swift code samples for a model to reuse; asserting their content would pin one API era, not a contract (ADR-0084). -->

SwiftUI best practices with ready-to-use snippets.

Main patterns:
- `@Observable` + `@Bindable` (iOS 17+) for state.
- SwiftData with `@Query` for declarative fetch.
- `URLSession` with async/await for networking.
- Small, composable views; side-effects in `.task`/`.onAppear`/`.onChange`.

Follow the `swift.md` rule. Extend this skill with additional patterns as you encounter them.
