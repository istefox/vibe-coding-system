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
