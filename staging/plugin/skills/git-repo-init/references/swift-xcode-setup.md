# Swift / Xcode project setup (Tuist)

Read this file when the chosen stack is Swift. It defines how to create the project folder, generate the Xcode project with Tuist, and verify the build before the first commit.

## Fixed constants (Stefano's environment)

| Key | Value |
|-----|-------|
| Apple Developer Team ID | `T7H24G7BFW` |
| Bundle identifier prefix | `it.stefer.<ProjectName>` (PascalCase preserved, e.g. `it.stefer.CleanKey`) |
| Project location | `~/Developer/Apple/<ProjectName>` (PascalCase folder name) |
| Swift version | 6.0 |
| Default deployment targets | macOS 14.0, iOS 17.0 (Observable/Bindable baseline) — raise only if the user asks |
| Code signing | `CODE_SIGN_STYLE = Automatic` with the team ID above |

Do not ask the user for these values. If signing must differ (e.g. no App Store, ad-hoc distribution), the user will say so.

## Project kinds

Ask which kind during Fase 2 (see question catalog). Four supported:

1. **macOS app** — SwiftUI windowed app.
2. **iOS app** — SwiftUI app, iOS 17+.
3. **Menu bar / agent app** — macOS app with `LSUIElement = true`, UI via `MenuBarExtra`.
4. **Swift Package / CLI** — library or executable. No Tuist, no Xcode project: use `swift package init --type library|executable --name <Name>`. Skip the rest of this file except the .gitignore and verification sections.

## Tuist scaffolding (app kinds)

Tuist ≥ 4 is installed via Homebrew. Do NOT use the interactive `tuist init` — write the manifest files directly so every decision is explicit and reproducible.

Files to create in the project root:

### `Tuist.swift`

```swift
import ProjectDescription

let tuist = Tuist()
```

### `Tuist/Package.swift` (SPM dependencies — create even if empty)

```swift
// swift-tools-version: 6.0
import PackageDescription

#if TUIST
import ProjectDescription

let packageSettings = PackageSettings(productTypes: [:])
#endif

let package = Package(
    name: "<ProjectName>",
    dependencies: [
        // .package(url: "https://github.com/...", from: "1.0.0"),
    ]
)
```

### `Project.swift`

Template for a macOS app (adapt platform/destinations for iOS):

```swift
import ProjectDescription

let projectName = "<ProjectName>"
let bundlePrefix = "it.stefer"

let baseSettings: SettingsDictionary = [
    "DEVELOPMENT_TEAM": "T7H24G7BFW",
    "CODE_SIGN_STYLE": "Automatic",
    "SWIFT_VERSION": "6.0",
]

let project = Project(
    name: projectName,
    settings: .settings(base: baseSettings),
    targets: [
        .target(
            name: projectName,
            destinations: .macOS,                    // or [.iPhone, .iPad]
            product: .app,
            bundleId: "\(bundlePrefix).\(projectName)",
            deploymentTargets: .macOS("14.0"),       // or .iOS("17.0")
            infoPlist: .extendingDefault(with: [:]), // see per-kind keys below
            sources: ["Sources/**"],
            resources: ["Resources/**"],
            dependencies: []
        ),
        .target(
            name: "\(projectName)Tests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "\(bundlePrefix).\(projectName)Tests",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .default,
            sources: ["Tests/**"],
            dependencies: [.target(name: projectName)]
        ),
    ]
)
```

Per-kind `infoPlist` keys (`.extendingDefault(with:)`):

- **macOS app**: usually `[:]` is enough at bootstrap.
- **Menu bar app**: `["LSUIElement": true]` — hides the Dock icon; the UI entry point is `MenuBarExtra` in the App struct.
- **iOS app**: `["UILaunchScreen": ["UIColorName": "", "UIImageName": ""]]` — required or the app gets letterboxed.

### Source skeleton

```
Sources/
  <ProjectName>App.swift     # @main App struct (WindowGroup, or MenuBarExtra for menu bar kind)
  ContentView.swift          # minimal working view, not an empty file
Resources/
  Assets.xcassets/           # with empty Contents.json ({"info":{"author":"xcode","version":1}})
Tests/
  <ProjectName>Tests.swift   # one real Swift Testing test (import Testing, @Test func) that passes
```

Follow the `swift-vibe` skill patterns for the App/View code: Observable + Bindable, async/await, no ObservableObject. For macOS apps, if the project has real UX complexity, mention that the `macos-ux` skill exists for a HIG design pass — do not run it inside this wizard.

## .gitignore (Swift/Tuist additions)

Start from the GitHub Swift template, then append the Tuist section — generated artifacts never get committed:

```gitignore
# Tuist
Derived/
*.xcodeproj
*.xcworkspace
.tuist-version
Tuist/.build/
```

The `.xcodeproj` is a build artifact under Tuist: anyone (including CI) regenerates it with `tuist generate`.

## Generate and verify

Run in order, stop and report on any failure:

```bash
tuist install          # only if Tuist/Package.swift has dependencies
tuist generate --no-open
xcodebuild -scheme <ProjectName> -destination 'platform=macOS' build
xcodebuild -scheme <ProjectName> -destination 'platform=macOS' test
```

For iOS use `-destination 'platform=iOS Simulator,name=iPhone 16'` (check available simulators with `xcrun simctl list devices available` if it fails). For Swift Package/CLI: `swift build && swift test`.

A bootstrap that does not build is not done. Only proceed to the first commit after build + tests pass.

## CLAUDE.md commands block (Swift projects)

Fill the template's Commands section with:

```bash
tuist generate --no-open                                      # regenerate after editing Project.swift
xcodebuild -scheme <ProjectName> -destination 'platform=macOS' build
xcodebuild -scheme <ProjectName> -destination 'platform=macOS' test
```

And add to Working agreements: "Never edit the .xcodeproj — it is generated. Change Project.swift and run tuist generate."
