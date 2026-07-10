# Convenzioni Git - riferimento operativo

## Conventional Commits (v1.0.0)

Formato: `tipo(scope opzionale): descrizione` + body opzionale + footer opzionale.

Tipi: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert.
Breaking change: `!` dopo il tipo (`feat!:`) o footer `BREAKING CHANGE:`.

Esempi:
- `feat(parser): add CSV import`
- `fix: handle empty config file`
- `chore: initial project scaffolding` (primo commit di questa skill)

Perche: storia leggibile, changelog e semantic versioning automatizzabili, e Claude Code mantiene lo stile se documentato in CLAUDE.md.

## Conventional Branch

Prefissi: `feature/`, `fix/`, `chore/`, `docs/`, `release/`, `hotfix/`.
Formato: `prefisso/descrizione-kebab-case`, es. `feature/csv-import`.
Branch trunk (main) senza prefisso.

## Workflow a confronto

| Workflow | Branch | Quando |
|----------|--------|--------|
| GitHub Flow | main + feature branch corti, merge via PR | default: dev singolo o team piccolo, deploy continuo |
| Trunk-based | commit diretti o branch di ore su main, CI forte | team maturi con CI/CD solido e feature flag |
| Git Flow | main + develop + release/hotfix branch | release versionate formali, software con versioni mantenute in parallelo. Overhead alto: sconsigliato per progetti singoli |

## Branch protection via gh api

Solo dopo il primo push. Esempio "require PR":

```bash
gh api -X PUT repos/{owner}/{repo}/branches/main/protection \
  -F required_pull_request_reviews[required_approving_review_count]=0 \
  -F enforce_admins=false \
  -F required_status_checks=null \
  -F restrictions=null
```

Con status check richiesti, valorizza `required_status_checks[contexts][]` con il nome del job CI. Se l'API fallisce (piano GitHub free + repo private non supporta protection), avvisa e prosegui: non e bloccante.

## File community standard (livello completo)

- CONTRIBUTING.md: come proporre modifiche, convenzioni commit/branch adottate.
- SECURITY.md: come segnalare vulnerabilita (email del maintainer).
- .github/CODEOWNERS: `* @<owner>` come default.
- Posizione consigliata per CODEOWNERS e template: directory `.github/`.
