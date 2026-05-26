# ADR-0005 — Vibe-status skill

**Status:** Accepted — 2026-05-20 (implemented via plan 2026-05-20-vibe-status-skill.md; harness review-triage-fix PASS=49; dedicated PASS=9)
**Authors:** Adriano (architect agent) per Stefano Ferri
**Supersedes:** none
**Superseded by:** none
**Related:**
- `docs/superpowers/specs/2026-05-20-vibe-status-skill-design.md`
- `docs/superpowers/plans/2026-05-20-vibe-status-skill.md`
- `~/.claude/skills/concept-to-code/` (pattern skill markdown + scripts come reference)
- `~/.claude/skills/refactor-snapshot/` (pattern skill recente)
- Memory `feedback_bash32-constraint.md`

---

## 1. Context

Il sistema vibe-coding (`docs/vibe-coding-system.md`) è ora composto da 8 sub-agent + ~12
skill + 4 hook + 3 ADR (0001-0003) + un livello memory persistente. **Lo stato corrente
del sistema non è ispezionabile in modo aggregato**: per sapere "è tutto sano?" oggi
serve manualmente:

1. `bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh` → PASS=47
2. `bash ~/.claude/skills/concept-to-code/tests/run-tests.sh` → PASS=10
3. `bash ~/.claude/skills/refactor-snapshot/tests/run-tests.sh` → PASS=11
4. `ls docs/architecture/` (per ADR e status)
5. `ls docs/manifests/` (per manifest concept-to-code in flight, se presente)
6. `cat ~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/MEMORY.md`
7. `cat .triage-fix-last.json` (se presente — output ultimo review-triage-fix)
8. Verificare `~/.claude/settings.json` per hook configurati

**8 punti di lookup separati.** Audit del sistema 2026-05-20: l'unica "skill aggregator"
non esiste. Friction operativa misurabile (3-5 min per audit completo manuale).

**Direzione:** introdurre **skill markdown `vibe-status`** invocabile dall'orchestrator
come `/skill vibe-status`, che produce un singolo report Markdown con:

- Stato dei N harness (PASS/FAIL count, durata)
- Manifest in flight (`docs/manifests/` se presente in cwd)
- ADR esistenti e loro status (parsing prima riga `**Status:**`)
- Skill custom installate (ls `~/.claude/skills/`)
- Hook configurati in `~/.claude/settings.json`
- Recente ciclo review-triage-fix (`.triage-fix-last.json` se presente)
- Memory entries attive (head di MEMORY.md)

Report stampato a stdout, Markdown ben formato per chat rendering, <10s typical.

### Vincoli ereditati

- **Anchor preservation `review-triage-fix`:** PASS=47 deve restare ≥ 47.
- **Bash 3.2.57 compat** per script aggregator.
- **Read-only:** skill NON modifica nessun file di sistema. Solo legge.
- **Performance target:** <10s typical case.
- **No HITL nel design phase.**
- **Repo NON-git:** no commit step.

### Assunzioni esplicite (non verificate empiricamente)

- **L'invocazione `/skill vibe-status` da orchestrator carica `SKILL.md` ed esegue gli
  step descritti** (allineato al pattern di `concept-to-code` e `refactor-snapshot`).
  Verificato per i 2 skill esistenti.
- **Lo skill può eseguire script bash (`scripts/aggregate.sh`) come parte degli step**
  (pattern di `concept-to-code/scripts/`).
- **Il typical caso ha ≤5 harness attivi** (oggi 3, crescita a 5-6 prevista in 2026 Q3).
  Performance budget 10s = 2s per harness × 5 harness + overhead 0-fluff.
- **Lo skill è cwd-sensitive:** lo invocatore è in `$PWD = current project`. Discovery
  globale di `~/.claude/skills/*/tests/` + discovery locale di `./docs/manifests/`,
  `./docs/architecture/`, `./.triage-fix-last.json` se presenti.

---

## 2. Decision

Introdurre la skill **`vibe-status`** in `~/.claude/skills/vibe-status/` con la
struttura standard (SKILL.md + scripts + tests), invocabile come `/skill vibe-status`.
Produce report Markdown su stdout in <10s typical.

### 2.1 Risposta alle 6 domande architetturali

#### Q1 — Forma: skill markdown vs bash standalone

**Skill markdown in `~/.claude/skills/vibe-status/SKILL.md` con `scripts/aggregate.sh`
helper.**

Razionale:
- Coerente con `concept-to-code`, `refactor-snapshot`, `review-triage-fix` (pattern
  stabilito).
- L'invocazione `/skill vibe-status` è discoverable nel CLI tab-completion.
- Lo SKILL.md può fornire context interpretativo all'LLM (es. "se 1 harness fail,
  flagga MAJOR; se tutti pass, dichiara HEALTHY") oltre al raw output dello script.
- `~/.claude/bin/vibe-status` standalone bash sarebbe alternative ma rompe la convenzione
  (mai usato pattern nel sistema attuale, non discoverable dall'orchestrator senza
  documentazione separata).

**Pattern hybrid:** SKILL.md orchestra; `scripts/aggregate.sh` fa il lavoro pesante
(harness invoke + manifest scan + ADR parse) producendo Markdown raw. SKILL.md può
aggiungere semantic layer top (HEALTHY/DEGRADED/CRITICAL header) post-hoc se l'LLM
sceglie di interpretare.

#### Q2 — Discovery dei file da aggregare

**Hybrid: auto-discovery con convention + override via manifest opzionale.**

Default behavior (no manifest):
- **Harness:** glob `~/.claude/skills/*/tests/run-tests.sh` (3.2-portable via `for f in
  ~/.claude/skills/*/tests/run-tests.sh; do ... done`).
- **ADR:** glob `<cwd>/docs/architecture/ADR-*.md` (cwd-local).
- **Manifests:** glob `<cwd>/docs/manifests/*.yaml` se directory esiste.
- **Triage state:** `<cwd>/.triage-fix-last.json` se file esiste.
- **Hook:** parse `~/.claude/settings.json` con jq.
- **Memory:** head di `~/.claude/projects/<encoded-cwd>/memory/MEMORY.md` se esiste.

Override opzionale via `<cwd>/.claude/vibe-status.yaml` (se presente):
```yaml
harness:
  - path: ~/.claude/skills/custom/tests/run-tests.sh
    timeout: 30
  - skip: ~/.claude/skills/swift-vibe/tests/run-tests.sh
adr_dir: docs/architecture
manifests_dir: docs/manifests
```

Trade-off: hardcoded list nel SKILL.md sarebbe più semplice (3 harness today) ma non
scala (un nuovo harness richiede edit a SKILL.md). Auto-discovery è write-once,
self-updating.

#### Q3 — Cwd sensitivity: globale vs locale

**Hybrid: globale (sempre) + locale (se path esistono in cwd).**

Comportamento:
- **Sempre legge (globale):**
  - `~/.claude/skills/*/tests/run-tests.sh` (harness)
  - `~/.claude/skills/*/SKILL.md` (skill list)
  - `~/.claude/settings.json` (hook config)
  - `~/.claude/agents/*.md` (agent list)
- **Conditionally legge (locale):**
  - `<cwd>/docs/architecture/ADR-*.md` se directory esiste — altrimenti sezione ADR del
    report mostra `(no project ADR directory)`.
  - `<cwd>/docs/manifests/*.yaml` se directory esiste — altrimenti sezione manifest mostra
    `(no in-flight manifests)`.
  - `<cwd>/.triage-fix-last.json` se file esiste — altrimenti `(no recent triage cycle)`.
  - `~/.claude/projects/<encoded-cwd>/memory/MEMORY.md` se file esiste.

Se `$PWD = ~` (home, no project context), la sezione locale degrada a "(no project
context)" senza erroring.

#### Q4 — Performance + parallel/cache

**Parallelizzazione harness con timeout per-harness + cache opzionale.**

Default v1.0:
- Harness eseguiti **in parallelo** via background subshell + wait (3.2-portable):
  ```bash
  for h in "$@"; do
    ( bash "$h" >"$TMP/$(basename $(dirname $(dirname $h)))" 2>&1; echo $? > "$TMP/rc.$$" ) &
  done
  wait
  ```
- **Timeout per-harness:** 8s default, configurable via env `VIBE_STATUS_HARNESS_TIMEOUT`.
- Se >timeout: skip + flag `TIMEOUT` nel report (non blocca altre sections).
- **No cache v1.0.** Premature: 3 harness paralleli in 8s = walltime ≤8s, sotto budget.
  Cache richiede invalidation (file mtime? sha?), defer to v1.1 se metriche pilota
  mostrano slowness ricorrente.

Skip-flag opt-in: `--skip-harness` produce report senza eseguire harness (solo metadata
scan, <1s).

#### Q5 — Output format

**Default: Markdown su stdout. Flag `--json` per JSON. Flag `--plain` per plain text.**

Default (Markdown):

```markdown
# Vibe-Coding System Status — 2026-05-20 14:32

## Health: HEALTHY

## Harness (3/3 passing)
| Skill | PASS | FAIL | Duration | Status |
|---|---|---|---|---|
| review-triage-fix | 47 | 0 | 2.1s | OK |
| concept-to-code | 10 | 0 | 1.4s | OK |
| refactor-snapshot | 11 | 0 | 1.9s | OK |

## ADR (3 total)
- ADR-0001 — Coder pre-flight pattern classifier — Accepted 2026-05-20
- ADR-0002 — Refactor snapshot harness — Accepted 2026-05-20
- ADR-0003 — Concept-to-code chain — Accepted 2026-05-20

## In-flight manifests
(none)

## Recent triage cycle
2026-05-20 11:05 — review-triage-fix v1.2 — PASS

## Hooks (4 configured)
- stop-gate.sh (Stop)
- approve-test-cmd.sh (utility)
- migrate-trust-paths.sh (utility)
- backup-before-deploy.sh (PreToolUse)

## Memory entries
- 4 project entries (1 RESOLVED, 1 SUPERSEDED)
- 3 feedback entries (all active)
```

`--json` flag emette il medesimo content come strutturato per programmatic consumption
(future skill chaining).

Output esclusivamente a stdout — nessun file scritto (vincolo read-only).

#### Q6 — Failure mode

**Skip-and-flag, mai block-entire-report.**

Casi:
- **1 harness timeout:** sezione harness mostra `TIMEOUT` row; altri harness completi;
  overall status `DEGRADED` (non `CRITICAL`).
- **1 harness FAIL:** mostra PASS/FAIL count; overall status `DEGRADED`.
- **1 harness crash (exit 127, file not found, etc.):** sezione harness mostra `ERROR`
  row con tail di stderr (last 80 char); overall status `DEGRADED`.
- **`~/.claude/settings.json` malformato (jq parse error):** sezione hook mostra
  `(unable to parse settings.json)`; overall status `DEGRADED`.
- **`<cwd>/docs/architecture/` non esiste:** sezione ADR `(no project ADR directory)`;
  overall status invariato (locale, non penalizza).

Overall status legend:
- **HEALTHY:** tutti harness PASS, no error nei metadata.
- **DEGRADED:** ≥1 harness FAIL/TIMEOUT/ERROR oppure metadata parse error.
- **CRITICAL:** ≥2 harness FAIL contemporanei oppure tutti i harness ERROR.

Status legend stampato in footer del report per chiarezza.

### 2.2 Architettura della skill

```
~/.claude/skills/vibe-status/
├── SKILL.md                          # orchestrator markdown, ~80 righe
├── scripts/
│   ├── aggregate.sh                  # main entry, 3.2-clean, ~200 righe
│   ├── harness-runner.sh             # invoke single harness con timeout
│   └── render-markdown.sh            # format output
└── tests/
    └── run-tests.sh                  # harness anchor + smoke test, ~50 anchor target

# Anchor structural in review-triage-fix harness:
~/.claude/skills/review-triage-fix/tests/run-tests.sh  # +1 anchor: presenza skill vibe-status
```

### 2.3 Coesistenza con harness `review-triage-fix`

Il harness `review-triage-fix` (PASS=47) acquisisce **+1 anchor** che verifica la
presenza del file `~/.claude/skills/vibe-status/SKILL.md` e del literal `Vibe-Coding System Status`
nel SKILL.md. Trade-off: lega review-triage-fix a un quarto file (oltre `SKILL.md` proprio,
`coder.md` da ADR-0001, `settings.json` da ADR-0004), ma il principio "review-triage-fix
ha autorità sulla qualità dello stack" si estende coerentemente.

**Harness PASS=47 → PASS=48** (con ADR-0004 = PASS=49 cumulativo se entrambi deployati;
ognuno indipendente porta +1).

### 2.4 La skill ha proprio harness?

**Sì, dedicato in `~/.claude/skills/vibe-status/tests/run-tests.sh`.** Pattern di
`concept-to-code/tests` e `refactor-snapshot/tests`. Anchor:
- presenza SKILL.md
- presenza scripts/aggregate.sh executable
- smoke test: invoke aggregate.sh su mock tmp env produce Markdown well-formed
  (head ha `# Vibe-Coding System Status`)
- harness discovery: glob `~/.claude/skills/*/tests/run-tests.sh` returns ≥3 files
- ADR parsing: parse di un ADR fixture estrae title e status
- timeout: harness fixture che sleep 30s viene killed in 8s

Target PASS=8-10 anchor nel proprio harness. Quel harness diventa il 4° in
auto-discovery di `vibe-status` stessa (self-referential, idempotente).

### 2.5 Lingua

SKILL.md in inglese (system contract). Script bash con comment in inglese. Reason field
e log in italiano (utente-facing). Spec, plan, memory, ADR in italiano. Allineato a
global rule.

---

## 3. Alternatives considered

### 3.1 Forma: skill vs bash standalone (Q1)

**a) Skill markdown + scripts (CHOSEN).** Coerente con `concept-to-code`, `refactor-snapshot`.
Discoverable, contestualizzabile dall'LLM, segue convention.

**b) Bash standalone `~/.claude/bin/vibe-status`** — *Rejected*. Mai usato pattern,
duplicherebbe la directory structure. Non discoverable senza alias o doc esterna. Non
permette l'LLM di interpretare l'output (es. "il sistema è DEGRADED perché..."), solo
raw dump.

**c) Sub-agent dedicato `vibe-monitor`** — *Rejected*. 8 sub-agent già coprono lo
spettro; aggiungere un 9° per status reporting è overkill (sub-agent = role con system
prompt complex, qui basta uno skill aggregator).

### 3.2 Discovery (Q2)

**a) Auto-discovery + manifest override opzionale (CHOSEN).** Scala self-updating; override
copre edge case (skill di test interni, harness sperimentali da skip).

**b) Hardcoded list nel SKILL.md** — *Rejected*. Non scala. Un nuovo harness richiede
edit a SKILL.md. Stale-by-design.

**c) Manifest hardcoded obbligatorio** — *Rejected*. Force every project a maintain
config file. Friction sproporzionata al benefit (default funziona per 95% dei casi).

### 3.3 Cwd sensitivity (Q3)

**a) Hybrid globale + locale (CHOSEN).** Globale per stack `~/.claude/`, locale per
project context. Degrada gracefully se project context manca.

**b) Solo globale** — *Rejected*. Perde ADR/manifest/triage del project corrente, riduce
utility a 50%.

**c) Solo locale** — *Rejected*. Perde harness/hook/skill globali, riduce utility a 30%.

### 3.4 Performance / parallel (Q4)

**a) Parallel + timeout per-harness, no cache v1.0 (CHOSEN).** 8s timeout × 3-5 harness
in parallelo = walltime ≤8s. Sotto budget. Cache defer.

**b) Sequential** — *Rejected*. 3-5 harness × 2-5s = 10-25s walltime. Sopra budget.

**c) Cache TTL 60s** — *Rejected v1.0*. Richiede storage in `~/.claude/state/vibe-status/`,
invalidation logic (file mtime check). Premature: parallel solo è sufficiente.
Considerable v1.1 se metriche mostrano slowness.

### 3.5 Output format (Q5)

**a) Markdown default + flag `--json`/`--plain` (CHOSEN).** Markdown è il rendering
nativo di chat Claude Code, JSON è hatch per future programmatic chaining (es. skill
`vibe-status-watch` futuro che parsi JSON).

**b) Plain text default** — *Rejected*. Lose table formatting, harder to scan.

**c) JSON default** — *Rejected*. Non human-readable senza tool. L'utilizzatore primario
è Stefano in chat, non un altro tool.

### 3.6 Failure mode (Q6)

**a) Skip-and-flag, never block entire (CHOSEN).** Resilience: 1 harness rotto non
oscura le altre info.

**b) Block entire report on first failure** — *Rejected*. Anti-pattern: lo skill di
status che fallisce per render lo stato è cattiva UX. Se la skill non riesce a riportare,
l'utilità è zero.

**c) Retry su timeout** — *Rejected v1.0*. Aggiunge complessità senza chiaro benefit.
Un harness che timeoutta 1x probabilmente timeoutta 2x. Defer.

---

## 4. Consequences

### 4.1 Positive

- **Single command per audit completo del sistema.** Da 8 lookup manuali a 1 invocazione.
  Tempo: 3-5 min → <10s.
- **Self-updating via auto-discovery.** Un nuovo harness/skill è automaticamente incluso
  senza editare config.
- **Read-only.** Zero rischio di side effect su file di sistema.
- **Coerente con convention.** Skill markdown + scripts pattern già consolidato.
- **Programmatic-friendly via `--json`.** Future skill di automazione (es. weekly health
  check) possono parsare l'output.
- **Anchor preservato** (PASS=47 → PASS=48 per skill esistenza).
- **Bash 3.2-clean** by construction (script segue stile `stop-gate.sh`).

### 4.2 Negative

- **Walltime fino a 8s + overhead** sotto carico nominale. Non istantaneo. Mitigato da
  `--skip-harness` per quick metadata-only view (<1s).
- **Dipendenza dal harness PASS count** (parse del summary `PASS=N FAIL=N`). Cambio
  format del harness rompe il parser. Mitigazione: regex tollerante (`grep -E
  'PASS=[0-9]+'`), fail-graceful con `?` se non match.
- **Cwd-sensitive non sempre intuitivo.** Stefano in `~` vede meno info che in
  `~/Developer/vibe-coding-system`. Documentato in SKILL.md header.
- **Settings.json parsing fragile su edits manuali.** Se JSON malformato (trailing comma,
  etc.), sezione hook è degradata. Mitigato da fail-graceful (vedi §2.1 Q6).
- **Coupling settings.json + review-triage-fix harness.** Nuova entry anchor lega
  l'harness a un 4° file (oltre SKILL.md, coder.md, future settings.json di ADR-0004).
  Refactor futuro di review-triage-fix richiede update anchor.

### 4.3 Neutral

- Il sistema attuale resta funzionante senza skill. È puramente additive.
- Memory `feedback_micropiano-refactor-cleanup` resta RESOLVED. No interazione.
- L'orchestrator non cambia: chiama `/skill vibe-status` quando vuole status, ignora
  altrimenti.

### 4.4 Open questions (validation pending)

- **Adozione real:** Stefano userà `/skill vibe-status` regolarmente o resterà unused?
  Validabile in 2 settimane di uso organico. Se unused, signal che la friction
  pre-existing non era effettivamente alta.
- **Performance under load.** 5+ harness con jsonl session lunghi: rispetta <10s
  budget? Misurabile via benchmark Task del piano.
- **Parsing robustness su `~/.claude/settings.json` edits manuali.** Stefano edita
  occasionalmente settings.json a mano; resilience del parser verificabile solo a uso.

---

## 5. References

- `~/.claude/skills/concept-to-code/` (pattern skill + scripts)
- `~/.claude/skills/refactor-snapshot/` (pattern recente con harness)
- `~/.claude/skills/review-triage-fix/` (skill autoritativa sulla qualità stack)
- `~/.claude/hooks/stop-gate.sh` (pattern bash 3.2-clean robusto)
- `docs/vibe-coding-system.md` sez. 8 (skill stack), sez. 3 (sub-agent list)
- `docs/architecture/ADR-0003-concept-to-code-chain.md` (pattern recente skill markdown)
- Memory `feedback_bash32-constraint.md`
