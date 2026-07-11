---
name: git-repo-init
description: Wizard interattivo che inizializza una nuova repository Git completa - crea la repo locale (in ~/Developer, o ~/Developer/Apple per Swift) e su GitHub (gh CLI), imposta licenza, .gitignore, convenzioni commit/branch, scaffolding e genera CLAUDE.md + PROJECT_BRIEF.md per l'handoff a Claude Code, chiudendo con il primo commit e push. Per stack Swift inizializza anche il progetto Xcode completo via Tuist (Team ID, bundle id, target test, build verificata) per app macOS, iOS, menu bar o Swift Package. Usa questa skill OGNI VOLTA che l'utente vuole creare, inizializzare o impostare una nuova repo o un nuovo progetto software, anche se non dice "skill" o "wizard". Trigger - "nuova repo", "crea repository", "setup repo", "inizializza progetto", "git init", "nuovo progetto su github", "imposta la repo per...", "parti con il progetto X", "scaffolding nuovo progetto", "nuova app macOS/iOS", "nuovo progetto Swift/Xcode". NON usare per operazioni su repo esistenti (commit, branch, merge, fix).
---

# git-repo-init

Wizard a 4 fasi per creare una repository Git nuova, pronta per lo sviluppo con Claude Code. Raccoglie le decisioni di progetto con domande progressive, poi esegue tutto in automatico: repo locale, repo GitHub, scaffolding, file di contesto per Claude Code, primo commit e push.

Lingua di interazione: italiano. Contenuto dei file generati (README, CLAUDE.md, PROJECT_BRIEF.md, commit): inglese, salvo richiesta contraria.

## Principio guida

L'output piu importante NON e la repo in se: e il pacchetto di decisioni documentate (CLAUDE.md + PROJECT_BRIEF.md) che permette a Claude Code di iniziare a fare coding senza ri-chiedere nulla. Ogni domanda del wizard esiste per alimentare quei due file. Se una risposta e gia deducibile dal contesto della conversazione, non ri-chiederla: proponila come default e vai avanti.

## Posizione del progetto (convenzione fissa)

- Progetti generici: `~/Developer/<nome-repo>` (kebab-case).
- Progetti Swift/Apple: `~/Developer/Apple/<NomeProgetto>` (PascalCase).

Non creare mai il progetto nella cwd corrente salvo richiesta esplicita. Se la directory target esiste gia, fermati e chiedi (mai sovrascrivere).

## Fase 0 - Prerequisiti (silenziosa)

Prima di fare domande, verifica l'ambiente:

```bash
git --version && gh --version && gh auth status
```

- `gh` autenticato: percorso completo (locale + GitHub).
- `gh` mancante o non autenticato: avvisa in 1 riga e procedi in modalita solo-locale; a fine setup stampa il comando `gh repo create` pronto da incollare.
- In Cowork senza cartella utente montata: chiedi di selezionare la cartella dove creare il progetto (request_cowork_directory) prima di proseguire. La repo deve nascere sul filesystem reale dell'utente, non nella sandbox.

## Fasi 1-4 - Wizard progressivo

Usa AskUserQuestion, un batch per fase. NON fare tutte le domande in un blocco unico. Tra una fase e l'altra, 1 riga di conferma di cio che e stato deciso. Il catalogo completo delle domande, con opzioni e razionale, e in `references/question-catalog.md`: leggilo prima di iniziare la Fase 1.

Sintesi delle fasi:

1. **Identita repo** - nome (suggerisci kebab-case; PascalCase se Swift), descrizione breve, visibilita (private default), licenza (MIT default per open source, "nessuna/proprietaria" per codice interno). Se visibilita = public: chiedi se eseguire la skill `clean-public-repo` (audit dati personali/segreti) prima del primo push — default si.
2. **Stack e architettura** - linguaggio/stack (incluso Swift), tipo di progetto (CLI, web app, API, libreria, automazione, docs; per Swift: macOS app, iOS app, menu bar app, package/CLI), descrizione del progetto da costruire, profondita di progetto (prototipo usa-e-getta / tool personale / prodotto mantenuto — calibra rigore di architettura, test e CI). Per decisioni architetturali non banali: se sono installate le skill `engineering:system-design` o `engineering:architecture` (ADR), invocale e salva l'esito in `docs/adr/0001-initial-architecture.md`. Se non installate, discuti l'architettura inline e documentala comunque nel PROJECT_BRIEF. **Se stack = Swift: leggi `references/swift-xcode-setup.md` prima della Fase 4.**
3. **Convenzioni Git** - workflow (GitHub Flow default per sviluppatore singolo; trunk-based o Git Flow su richiesta), Conventional Commits (default si), naming branch (Conventional Branch: feature/, fix/, chore/...), branch protection su main (solo se repo pubblica o team). Dettagli e razionale in `references/git-conventions.md`.
4. **Scaffolding** - livello: `minimal` (README, LICENSE, .gitignore), `standard` (+ struttura src/tests/docs + tooling lint/format dello stack), `completo` (+ CI GitHub Actions, CONTRIBUTING.md, SECURITY.md, CODEOWNERS in .github/). CLAUDE.md e PROJECT_BRIEF.md vengono generati SEMPRE, a ogni livello.

## Fase 5 - Esecuzione

Ordine fisso, nessuna domanda aggiuntiva:

1. `mkdir` nella posizione canonica (vedi "Posizione del progetto") e `git init -b main`
2. Genera i file dello scaffolding scelto. Per .gitignore usa i template ufficiali GitHub (`gh repo gitignore view <Template>` o https://github.com/github/gitignore). Per la licenza usa il testo ufficiale (gh o choosealicense.com) con anno corrente e nome utente.
3. **Se stack = Swift**: esegui il setup Tuist/Xcode da `references/swift-xcode-setup.md` (manifesti, sorgenti skeleton, `tuist generate`, build + test verde). Per gli altri stack genera la struttura sorgenti standard.
4. Genera `CLAUDE.md` e `PROJECT_BRIEF.md` dai template in `assets/`, compilati con TUTTE le risposte del wizard. Non lasciare placeholder vuoti. Per Swift usa il blocco Commands e il working agreement indicati in `references/swift-xcode-setup.md`.
5. **Se visibilita = public e l'utente ha accettato l'audit**: invoca la skill `clean-public-repo` ORA, prima del primo commit/push.
6. Primo commit, sempre conventional: `chore: initial project scaffolding`
7. Se gh disponibile: `gh repo create <nome> --<visibilita> --source . --push --description "<descrizione>"`
8. Se richiesta branch protection: applicala via `gh api` dopo il push.
9. Verifica: `git log --oneline` e (se remoto) `gh repo view --web` NO - non aprire il browser; stampa solo l'URL della repo.

## Fase 6 - Report finale

Chiudi con max 8 righe: percorso locale, URL GitHub (se creato), licenza, workflow scelto, file generati, e il suggerimento operativo: "Apri la cartella con Claude Code: leggera CLAUDE.md e PROJECT_BRIEF.md e potra iniziare a sviluppare subito."

## Gestione errori

- Nome repo gia esistente su GitHub: proponi 2 alternative, non fallire.
- Push fallito: la repo locale resta valida; stampa i comandi di recovery.
- Mai eseguire `git push --force`, mai cancellare directory esistenti. Se la directory target esiste gia e non e vuota, fermati e chiedi.

## Risorse

- `references/question-catalog.md` - catalogo completo domande wizard (leggere prima della Fase 1)
- `references/git-conventions.md` - Conventional Commits, Conventional Branch, confronto workflow, branch protection
- `references/swift-xcode-setup.md` - setup Tuist/Xcode per stack Swift: Team ID, bundle id, manifesti, skeleton, verifica build (leggere se stack = Swift)
- `assets/CLAUDE.template.md` - template CLAUDE.md
- `assets/PROJECT_BRIEF.template.md` - template PROJECT_BRIEF.md
