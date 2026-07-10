# Catalogo domande wizard

Ogni fase = un batch AskUserQuestion (max 4 domande per batch). Se una risposta e gia chiara dal contesto, proponila come prima opzione "(dedotto dal contesto)" invece di chiederla da zero. L'utente puo sempre rispondere "Other" con testo libero.

## Fase 1 - Identita repo

| # | Domanda | Opzioni | Default / note |
|---|---------|---------|----------------|
| 1.1 | Nome della repo | suggerisci 2-3 nomi derivati dalla descrizione del progetto | kebab-case minuscolo, no spazi; PascalCase se stack Swift. Verifica che non esista gia: `gh repo view <owner>/<nome>` |
| 1.2 | Visibilita | private / public / internal (solo org) | private |
| 1.2b | (solo se public) Audit `clean-public-repo` prima del push? | si (Recommended) / no | si. La skill cerca dati personali, segreti, riferimenti interni prima della pubblicazione |
| 1.3 | Licenza | MIT / Apache-2.0 / GPL-3.0 / nessuna (proprietario) | MIT se public; "nessuna" se private aziendale. Per progetti con dipendenze GPL segnala il vincolo copyleft |
| 1.4 | Descrizione breve (1 riga, inglese) | testo libero | usata per `gh repo create --description` e README |

Licenze, razionale rapido da dare se l'utente chiede:
- MIT: massima permissivita, standard de facto per tool e librerie.
- Apache-2.0: come MIT + grant esplicito di brevetti. Preferibile per progetti con potenziale uso enterprise.
- GPL-3.0: copyleft, i derivati devono restare open. Da scegliere solo se e una decisione consapevole.
- Nessuna licenza = tutti i diritti riservati. Corretto per codice interno Vibrofer.

## Fase 2 - Stack e architettura

| # | Domanda | Opzioni | Note |
|---|---------|---------|------|
| 2.1 | Tipo di progetto | CLI tool / web app / API-backend / libreria-package / automazione-script / documentazione | guida .gitignore, scaffolding e CI |
| 2.2 | Stack principale | Python / TypeScript-Node / Swift / entrambi / altro | determina template .gitignore e tooling. Se Swift: leggi `references/swift-xcode-setup.md` e fai anche la 2.2b |
| 2.2b | (solo se Swift) Tipo di progetto Apple | macOS app / iOS app / menu bar-agent app / Swift Package-CLI | determina manifesti Tuist, Info.plist e destinazione (vedi swift-xcode-setup.md). Sostituisce la 2.1 |
| 2.3 | Descrizione del progetto da costruire | testo libero, 3-5 righe | va INTEGRALE nel PROJECT_BRIEF: cosa fa, per chi, input/output principali |
| 2.4 | Profondita di progetto | prototipo usa-e-getta / tool personale / prodotto mantenuto | calibra il resto: prototipo = scaffolding minimal e niente CI; tool personale = standard; prodotto = standard o completo + architettura documentata |
| 2.5 | Serve una sessione di architettura? | si, invoca skill architettura / no, architettura semplice, decidiamo inline | se si e sono installate `engineering:system-design` o `engineering:architecture`, invocale ora e salva l'output come ADR |

Tooling di default per stack (livello standard e completo):
- Python: `pyproject.toml`, ruff (lint+format), pytest, struttura `src/<package>/` + `tests/`
- TypeScript/Node: `package.json`, eslint + prettier, vitest, struttura `src/` + `tests/`
- Swift: Tuist (`Project.swift` + `Tuist.swift`), Swift Testing, struttura `Sources/` + `Tests/` + `Resources/` — dettagli completi in `swift-xcode-setup.md`
- Altro stack: chiedi all'utente o usa le convenzioni idiomatiche del linguaggio

## Fase 3 - Convenzioni Git

| # | Domanda | Opzioni | Default |
|---|---------|---------|---------|
| 3.1 | Workflow | GitHub Flow / trunk-based / Git Flow | GitHub Flow per dev singolo o team piccolo |
| 3.2 | Conventional Commits | si / no | si (abilita changelog e versioning automatici) |
| 3.3 | Branch protection su main | nessuna / require PR / require PR + status check | nessuna se private + dev singolo; require PR se public o team |

Naming branch: se Conventional Commits = si, applica anche Conventional Branch (feature/, fix/, chore/, docs/, release/) senza chiederlo. Documenta tutto in CLAUDE.md cosi Claude Code lo rispetta nei commit futuri.

## Fase 4 - Scaffolding

| # | Domanda | Opzioni | Contenuto |
|---|---------|---------|-----------|
| 4.1 | Livello scaffolding | minimal / standard / completo | vedi sotto |
| 4.2 | CI al primo commit (solo se completo) | lint+test su push / solo lint / nessuna | GitHub Actions workflow in `.github/workflows/ci.yml` |

Livelli:
- **minimal**: README.md, LICENSE, .gitignore, CLAUDE.md, PROJECT_BRIEF.md
- **standard**: minimal + struttura sorgenti dello stack + tooling lint/format/test configurato + `docs/`
- **completo**: standard + `.github/workflows/ci.yml`, CONTRIBUTING.md, SECURITY.md, `.github/CODEOWNERS`, template issue/PR in `.github/`

README minimo al primo commit: titolo, descrizione 1 riga, sezione Status ("bootstrap - under active development"), come installare/avviare se gia noto. Niente sezioni vuote segnaposto.
