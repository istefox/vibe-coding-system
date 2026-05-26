# CLAUDE.md — [NOME_PROGETTO] (iOS/macOS)

Eredita `~/.claude/CLAUDE.md` e la rule `swift.md`. Qui solo specifico del progetto.

## Progetto
- App SwiftUI, target iOS 17+ (e macOS se multipiattaforma). Swift 6, SwiftData.

## Comandi (via XcodeBuildMCP)
- Build: `build` (Debug default)
- Test: `test` (Swift Testing)
- Clean: `clean` · Simulator: `simulator boot/install`
- Archive: solo su HITL gate esplicito.

## Struttura
`App/`, `Features/<Feature>/`, `Core/`, `DesignSystem/`, `Resources/`, `Tests/`.

## Accessibilità (obbligatoria)
- `.accessibilityLabel` su ogni View interattiva. VoiceOver sui flussi principali. Dynamic Type.
