# clean-public-repo + modalità anonima — Implementation Plan (TDD)

> **For agentic workers:** REQUIRED SUB-SKILL: usa superpowers:subagent-driven-development
> (consigliato) o superpowers:executing-plans per implementare task-by-task. Gli step usano
> checkbox (`- [ ]`).

**Changelog:**
- v1.0 (2026-05-23): initial — TDD plan derivato da `ADR-0011-clean-public-repo-anonymize.md`
  e da `BRAINSTORM.md`. 11 task: T1 anchor red (chain + review-triage-fix), T2
  `detect-public-remote.sh`, T3 `detect-tool-traces.sh` (grep custom), T4 `fresh-history-publish.sh`,
  T5 `surgical-rewrite.sh`, T6 SKILL.md clean-public-repo, T7 self-test harness, T8 Gate 0b +
  modalità anonima nel chain SKILL.md, T9 manifest schema 1.2 (`anonymize`), T10 anchor green +
  anchor-preserving gate, T11 doc status sync + memory.

**Goal:** introdurre la skill standalone `~/.claude/skills/clean-public-repo/` (audit + cleanup
di repo nuovi/esistenti, azione ibrida segnala→rimuovi-su-conferma, **orchestrator-only**) e la
**modalità anonima** nel chain `concept-to-code` (flag `anonymize` nel manifest schema 1.2,
attivato da un **Gate 0b** condizionale auto-detect remote pubblico, veicolato nei
prompt-template di dispatch). Strategie history: **fresh-history publish (default per
già-pubblici)** + **rewrite chirurgico (opzione 2, mai default)**. Detection grep custom
(zero-dep); gitleaks/gh opzionali con degrade graceful (gitleaks ASSENTE sull'ambiente, git-filter-repo
PRESENTE). Report `docs/clean-report/<date>-<slug>.md` con sezione COPERTURA & LIMITI obbligatoria.
Priorità #1: **nessun rewrite distruttivo non protetto** (backup tar + dry-run + HITL su force-push).

**Architecture:** nuova skill dir `~/.claude/skills/clean-public-repo/` con `SKILL.md`,
`scripts/detect-public-remote.sh` (D1, puro/testabile), `scripts/detect-tool-traces.sh` (D3,
grep custom, puro/testabile), `scripts/fresh-history-publish.sh` (D5, guida+dry-run),
`scripts/surgical-rewrite.sh` (D6, orchestratore di safety), `tests/run-tests.sh` (structural
anchor + smoke dei 2 detector puri, target PASS=18). Patch al chain:
`concept-to-code/SKILL.md` (Gate 0b + modalità anonima nei dispatch template + transizioni),
`scripts/manifest-validate.sh` (schema 1.2 + campo `anonymize`),
`scripts/manifest-init.sh` (scrive `anonymize: false` di default). Anchor in
`review-triage-fix/tests/run-tests.sh` (skill presente, orchestrator-only) e in
`concept-to-code/tests/run-tests.sh` (Gate 0b + anonymize + schema 1.2).

**Tech Stack:** bash 3.2.57 (script + harness: `grep -E`, `git`, `ls`, `case`, loop `while`,
`[ -f ]`; **vietati** assoc array / `mapfile` / `${v^^}` / `<()` / here-string `<<<`),
markdown. Le operazioni git distruttive (rewrite/force-push/orphan-publish) sono **prosa
procedurale nello SKILL.md** + helper di safety (dry-run/backup) — l'esecuzione mutante è
guidata dall'orchestrator a runtime con HITL, NON automatizzata negli script.

**ADR:** `docs/architecture/ADR-0011-clean-public-repo-anonymize.md` (Proposed 2026-05-23).
**SPEC:** `/Users/stefanoferri/Developer/vibe-coding-system/SPEC.md`.
**BRAINSTORM:** `/Users/stefanoferri/Developer/vibe-coding-system/BRAINSTORM.md`.

---

## Environment notes (read first)

- **No git in `~/.claude/` né nel repo `vibe-coding-system`.** Checkpoint per task = harness
  verde + TodoWrite + report. **Nessun commit step.** Il deploy aggiunge 1 skill + patch al
  chain; inerte finché la skill non è invocata su un repo target.
- **Orchestrator-only (ADR D2/D8, vincolo HARD).** Le operazioni git distruttive richiedono
  HITL interattivo; lo SKILL.md DEVE dichiarare che la skill gira sull'orchestrator e NON
  dispatchare un sub-agent per rewrite/force-push (coerente ADR-0010 D1 / ADR-0009).
- **Nessun rewrite distruttivo non protetto (priorità #1, vincolo HARD).** Ogni operazione
  history distruttiva → backup tar `.git/` + dry-run + **HITL esplicito** prima del force-push.
  Mai automatica, mai da sub-agent. Gli helper bash NON eseguono force-push; mostrano il dry-run
  e istruiscono la conferma.
- **Degrade graceful sulle dipendenze (ADR D2, vincolo HARD).** **Verificato:** `git-filter-repo`
  PRESENTE (`/opt/homebrew/bin`), `gitleaks` ASSENTE, `git` presente. Ogni script verifica
  `command -v` e degrada con messaggio install se assente. Percorso minimo (grep custom +
  fresh-history via git core) deve funzionare con solo `git`.
- **Auto-detect fail-safe verso silenzioso (ADR D1, vincolo HARD).** `detect-public-remote.sh`
  deve dare `silent` su: non-git, nessun remote, host non-github, visibilità non determinabile
  (gh assente/non auth). Propone il gate SOLO su remote github con visibilità `PUBLIC` accertata.
  T7 ha le regressioni anti falso-avvio. NON allentarle.
- **No falsificazione autori (vincolo etico HARD).** Lo SKILL.md DEVE dichiararlo
  esplicitamente; il harness lo ancora (anchor su literal). La feature rimuove marcatori, non
  attribuisce a terzi inventati.
- **Bash 3.2 cleanliness (`feedback_bash32-constraint`).** Vietati: assoc array, `mapfile`,
  `${v^^}`, `<()`, here-string `<<<`. Usa `grep -Eq`, `[ -f ]`, `case`, `git`, `ok`/`bad` helpers.
- **La feature NON è testabile headless end-to-end (ADR D8).** Il harness copre SOLO structural
  anchor sullo SKILL.md + smoke dei 2 detector puri. Rewrite reale, fresh-history publish reale,
  force-push, integrazione gitleaks/gh su remote vero → **open question, validabili solo in
  pilota** con un repo reale. Dichiararlo nel report finale e nella memory (T11). Non fingere
  copertura che non c'è (onestà design-brainstorm/ADR-0009/0010).
- **Anchor preservation HARD.** Baseline verificati pre-implementazione (NON regredirli):
  **review-triage-fix PASS=60**, **concept-to-code PASS=20**, design-brainstorm 9,
  refactor-snapshot 18, vibe-status 10, pre-flight-pattern-enforce 13, run-hook-tests 24,
  db-backup-guardrail 16. Harness modificati: review-triage-fix (+2 anchor → 62) e
  concept-to-code (+3 anchor → 23). Nuovo harness clean-public-repo parte da 0 → 18.
- **Backup pre-edit dei file critici del chain (regola globale "backup prima di file
  critici"):** `cp` con suffix `.bak-2026-05-23` per `concept-to-code/SKILL.md`,
  `manifest-validate.sh`, `manifest-init.sh` prima di modificarli (T8/T9).
- **Coexistence.** La skill è orthogonale a tutti gli agent e alle altre skill; NON patcha
  `coder.md`/`architect.md` (la modalità anonima è veicolata nei prompt-template di dispatch del
  chain, additiva, opt-in). Quando `anonymize=false` (default) i template sono identici a oggi
  → zero regressioni.
- **Manifest schema 1.2 retrocompat (ADR D1/Neutral).** `manifest-validate.sh` deve accettare
  `1.0|1.1|1.2`. **Nota di coesistenza con ADR-0010:** se ADR-0010 (web-e2e-test) è già
  deployato, lo schema live è già 1.2 → questo plan aggiunge SOLO il campo `anonymize` (non
  ri-bumpa). **Verifica lo stato live della regex riga 29 PRIMA di editare** (vedi T9). Gate 0b
  NON è uno stato → nessuna estensione di `VALID_STEPS`/transition pairs.

## File structure

- Create `~/.claude/skills/clean-public-repo/SKILL.md` — guida procedurale orchestrator (~230 righe).
- Create `~/.claude/skills/clean-public-repo/scripts/detect-public-remote.sh` — D1, puro, bash 3.2, executable.
- Create `~/.claude/skills/clean-public-repo/scripts/detect-tool-traces.sh` — D3 grep custom, puro, bash 3.2, executable.
- Create `~/.claude/skills/clean-public-repo/scripts/fresh-history-publish.sh` — D5, guida+dry-run+backup, executable.
- Create `~/.claude/skills/clean-public-repo/scripts/surgical-rewrite.sh` — D6, orchestratore safety (dry-run, no force-push), executable.
- Create `~/.claude/skills/clean-public-repo/tests/run-tests.sh` — self-test (target PASS=18), executable.
- Modify `~/.claude/skills/concept-to-code/SKILL.md` — Gate 0b + modalità anonima nei dispatch template + transizioni (backup prima).
- Modify `~/.claude/skills/concept-to-code/scripts/manifest-validate.sh` — schema 1.2 + campo `anonymize` (backup prima).
- Modify `~/.claude/skills/concept-to-code/scripts/manifest-init.sh` — scrive `anonymize: false` di default (backup prima).
- Modify `~/.claude/skills/review-triage-fix/tests/run-tests.sh` — +2 anchor (PASS=60→62).
- Modify `~/.claude/skills/concept-to-code/tests/run-tests.sh` — +3 anchor (PASS=20→23).
- Modify `docs/architecture/ADR-0011-clean-public-repo-anonymize.md` — Proposed → Accepted (T11).
- Create `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/project_clean-public-repo-anonymize.md` (T11).
- Modify `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/MEMORY.md` — append riga `## Project` (T11).

Unchanged (HARD): tutti gli agent `*.md` (in particolare `coder.md`/`architect.md`), tutti gli
hook, `settings.json`, `.mcp.json`, tutte le altre skill (design-brainstorm/interview-driver/
claude-md-generator/refactor-snapshot/vibe-status/web-e2e-test), `manifest-transition.sh`,
`gate0-detect.sh`.

**Harness PASS delta atteso:** review-triage-fix 60 → **62** (+2). concept-to-code 20 → **23**
(+3). Nuovo clean-public-repo: **PASS=18** (parte da 0). Tutti gli altri **invariati**.

---

### Task 1 — Anchor red nel chain + review-triage-fix harness (red)

**Files:**
- Modify: `~/.claude/skills/review-triage-fix/tests/run-tests.sh`
- Modify: `~/.claude/skills/concept-to-code/tests/run-tests.sh`

**Red phase:** baseline `review-triage-fix PASS=60`, `concept-to-code PASS=20` (verificati). I
nuovi anchor cercano literal assenti pre-implementazione → entrambi i harness rossi.

**Green phase (edit concreto):**

*review-triage-fix/tests/run-tests.sh* — inserisci PRIMA della riga finale di summary
(`echo "----"; echo "PASS=$PASS FAIL=$FAIL"; rm -rf "$TMP"`), dopo l'ultimo blocco esistente:
```bash

# --- clean-public-repo skill (ADR-0011) ---
CPR="$HOME/.claude/skills/clean-public-repo/SKILL.md"
[ -f "$CPR" ] && ok "clean-public-repo: SKILL.md present" || bad "clean-public-repo: SKILL.md missing"
grep -q -- 'orchestrator' "$CPR" 2>/dev/null && ok "clean-public-repo: orchestrator-only documented" || bad "clean-public-repo: orchestrator-only missing"
```

*concept-to-code/tests/run-tests.sh* — inserisci PRIMA della riga finale di summary:
```bash

# --- Gate 0b — anonymize (ADR-0011) ---
CC="$SKILL_DIR/SKILL.md"
grep -q -- 'Gate 0b' "$CC" 2>/dev/null && ok "concept-to-code: Gate 0b anonymize present" || bad "concept-to-code: Gate 0b missing"
grep -q -- 'anonymize' "$CC" 2>/dev/null && ok "concept-to-code: anonymize mode documented" || bad "concept-to-code: anonymize mode missing"
grep -Eq '1\.2' "$VAL" 2>/dev/null && ok "manifest-validate: schema 1.2 accepted" || bad "manifest-validate: schema 1.2 missing"
```
(`$SKILL_DIR` e `$VAL` sono già definiti in cima al harness — righe 9/11.)

- [ ] Step 1: edita i due harness inserendo i blocchi prima delle rispettive summary.
- [ ] Step 2: verifica fallimento di entrambi.
- [ ] Step 3: checkpoint — baseline rossa confermata. TodoWrite.

**Verify command:**
```bash
bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh | tail -1; echo "exit=$?"
bash ~/.claude/skills/concept-to-code/tests/run-tests.sh | tail -1; echo "exit=$?"
```
Atteso: review-triage-fix `PASS=60 FAIL=2` exit 1; concept-to-code `PASS=20 FAIL=3` exit 1.
(Se ADR-0010 è già deployato e lo schema è già 1.2, l'anchor `schema 1.2` può essere già verde:
in quel caso atteso `PASS=20 FAIL=2` — annotalo nel checkpoint e prosegui.)

**Stima:** 10 min.

---

### Task 2 — `detect-public-remote.sh` (green: auto-detect remote pubblico, fail-safe)

**Files:**
- Create: `~/.claude/skills/clean-public-repo/scripts/detect-public-remote.sh` (executable, bash 3.2, ~60 righe)

**Red phase:** lo script non esiste; il suo smoke (T7) non può passare.

**Green phase — logica (ADR D1, cascata fail-safe verso `silent`):**
1. Arg `ROOT="${1:-$PWD}"`. `set -u`. Stdout: una riga `public` | `silent`, e se `public` una
   seconda riga `repo=<owner/repo>`.
2. Cascata (primo che decide vince):
   - `git -C "$ROOT" rev-parse --is-inside-work-tree` fallisce → `silent` (non-git).
   - `git -C "$ROOT" remote get-url origin` (fallback: primo `git remote`) vuoto → `silent`.
   - URL non matcha host github (`grep -Eq 'github\.com'`) → `silent` (scope GitHub).
   - `command -v gh` assente **o** `gh auth status` fallisce → `silent` (visibilità non
     determinabile — fail-safe).
   - `gh repo view <owner/repo> --json visibility -q .visibility` == `PUBLIC` → `public` +
     `repo=<owner/repo>`. Altrimenti (`PRIVATE`/`INTERNAL`/errore) → `silent`.
3. Exit 0 sempre (classificazione nello stdout). Bash 3.2-clean.

- [ ] Step 1: scrivi `detect-public-remote.sh` (PATTERN: ADD); `chmod +x`.
- [ ] Step 2: smoke manuale (vedi verify).
- [ ] Step 3: checkpoint TodoWrite.

**Verify command:**
```bash
TMP=$(mktemp -d)
bash ~/.claude/skills/clean-public-repo/scripts/detect-public-remote.sh "$TMP" | head -1   # atteso: silent (non-git)
( cd "$TMP" && git init -q && git remote add origin git@gitlab.com:x/y.git )
bash ~/.claude/skills/clean-public-repo/scripts/detect-public-remote.sh "$TMP" | head -1   # atteso: silent (host non-github)
rm -rf "$TMP"
```
Atteso: prima `silent`, seconda `silent`.

**Stima:** 25 min.

---

### Task 3 — `detect-tool-traces.sh` (green: detection grep custom, zero-dep)

**Files:**
- Create: `~/.claude/skills/clean-public-repo/scripts/detect-tool-traces.sh` (executable, bash 3.2, ~90 righe)

**Red phase:** lo script non esiste; il suo smoke (T7) non può passare.

**Green phase — logica (ADR D3, grep custom su working tree + commit messages):**
1. Arg `ROOT="${1:-$PWD}"`. `set -u`. Stdout: righe `category|severity|location|match`
   (`severity` ∈ `auto-removable|review-needed|manual`), pipe-separated, per parsing del report.
2. **Working tree:** `git -C "$ROOT" ls-files` (se non-git → `find . -type f`); per ogni file
   (skip binari via `grep -Iq . "$f"`), grep -nE dei pattern:
   - `Co-Authored-By: *Claude` / `Generated with *Claude Code` → `trailer|auto-removable`.
   - `(added|generated) by Claude` / `# *generated by` → `comment-trace|auto-removable`.
   - emoji decorative + parola `claude`/`AI` → `string-emoji|auto-removable`.
   - **review-needed guard:** se il match è dentro un nome di dipendenza (`claude-`seguito da
     `[a-z0-9-]` in package.json/requirements/import) → `string|review-needed` (NON
     auto-removable: falso positivo SPEC edge).
   - file slop per nome (`scratch`, `*-COPY`, `notes.md` ridondante) → `slop|manual`.
3. **Commit messages:** `git -C "$ROOT" log --format='%h %B'` → stessi pattern trailer →
   `commit-trailer|auto-removable|<sha>`.
4. Exit 0 se nessun finding `auto-removable`, exit 1 se ce ne sono (utile al report `ready` vs
   `da-pulire`). Bash 3.2-clean.

- [ ] Step 1: scrivi `detect-tool-traces.sh` (PATTERN: ADD); `chmod +x`.
- [ ] Step 2: smoke manuale (vedi verify).
- [ ] Step 3: checkpoint TodoWrite.

**Verify command:**
```bash
TMP=$(mktemp -d)
printf 'def f():\n    return 1  # added by Claude\n' > "$TMP/a.py"
printf '{"dependencies":{"claude-sdk":"^1"}}' > "$TMP/package.json"
bash ~/.claude/skills/clean-public-repo/scripts/detect-tool-traces.sh "$TMP"
# atteso: una riga comment-trace|auto-removable su a.py; e claude-sdk marcato review-needed (NON auto-removable)
rm -rf "$TMP"
```
Atteso: trova il commento-traccia come `auto-removable`; marca `claude-sdk` come `review-needed`.

**Stima:** 35 min.

---

### Task 4 — `fresh-history-publish.sh` (green: D5 guida + dry-run + backup, no push automatico)

**Files:**
- Create: `~/.claude/skills/clean-public-repo/scripts/fresh-history-publish.sh` (executable, bash 3.2, ~70 righe)

**Red phase:** lo script non esiste; lo smoke T7 sul suo dry-run non passa.

**Green phase — logica (ADR D5, default per già-pubblici):**
1. Arg `ROOT="${1:-$PWD}"`, modo `MODE="${2:-dry-run}"` (`dry-run` | `prepare`). `set -u`.
2. Precondizioni: `git -C "$ROOT" rev-parse` (non-git → errore graceful + exit 2);
   working tree pulito atteso (warn se dirty).
3. **dry-run (default):** stampa il piano SENZA mutare: (a) backup tar che verrebbe creato
   (`.git-backup-<ts>.tar.gz`), (b) orphan branch `public-clean` che verrebbe creato, (c)
   commit singolo curato, (d) istruzione "push del solo public-clean su un NUOVO repo pubblico;
   NESSUN force-push sul repo originale". Exit 0.
4. **prepare:** esegue SOLO i passi non-distruttivi e reversibili (backup tar effettivo,
   creazione orphan branch locale, staging) → poi STOP e istruisce l'orchestrator a presentare
   l'HITL per il commit/push (mai automatico). NON crea repo remoto né pusha.
5. `command -v gh` → se presente, suggerisce `gh repo create` (su conferma); se assente,
   istruzioni manuali. Bash 3.2-clean.

- [ ] Step 1: scrivi lo script (PATTERN: ADD); `chmod +x`.
- [ ] Step 2: smoke dry-run su fixture git (vedi verify).
- [ ] Step 3: checkpoint TodoWrite.

**Verify command:**
```bash
TMP=$(mktemp -d); ( cd "$TMP" && git init -q && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init )
bash ~/.claude/skills/clean-public-repo/scripts/fresh-history-publish.sh "$TMP" dry-run | grep -Eqi 'orphan|public-clean|backup' && echo "dry-run plan ok"
git -C "$TMP" branch | grep -q public-clean && echo "FAIL: dry-run mutated repo" || echo "dry-run non-mutating ok"
rm -rf "$TMP"
```
Atteso: `dry-run plan ok`; `dry-run non-mutating ok` (il dry-run NON crea il branch).

**Stima:** 30 min.

---

### Task 5 — `surgical-rewrite.sh` (green: D6 orchestratore di safety, git-filter-repo dry-run, no force-push)

**Files:**
- Create: `~/.claude/skills/clean-public-repo/scripts/surgical-rewrite.sh` (executable, bash 3.2, ~80 righe)

**Red phase:** lo script non esiste; lo smoke T7 sul suo degrade/dry-run non passa.

**Green phase — logica (ADR D6, opzione 2 mai default):**
1. Arg `ROOT`, `PATTERNS_FILE` (file di regex per `--replace-text`), `MODE="${3:-dry-run}"`.
   `set -u`.
2. **Degrade graceful:** `command -v git-filter-repo` assente → stampa messaggio install
   (`brew install git-filter-repo` / `pip3 install git-filter-repo`) + "rewrite chirurgico
   disabilitato; usa fresh-history-publish" ed exit 3. (Verificato: sull'ambiente è presente,
   ma lo script NON deve assumerlo.)
3. **Pre-condizione fresh-clone:** avvisa che git-filter-repo opera su un clone fresco; NON
   passa `--force` per aggirare la protezione. Se il repo non è fresh-clone → istruisce a
   clonare, exit 4.
4. **Backup tar obbligatorio** della `.git/` (`tar -czf .git-backup-<ts>.tar.gz .git`) prima di
   qualunque operazione.
5. **dry-run (default):** `git filter-repo --replace-text "$PATTERNS_FILE" --dry-run` (+
   nota su `--message-callback` per i trailer) → mostra cosa cambierebbe. Exit 0.
6. **apply:** esegue il rewrite sul clone, crea backup branch/tag, poi STOP e istruisce
   l'HITL: "force-push SOLO dopo conferma esplicita dell'utente; mai automatico, mai da
   sub-agent". Lo script NON esegue il force-push. Bash 3.2-clean.

- [ ] Step 1: scrivi lo script (PATTERN: ADD); `chmod +x`.
- [ ] Step 2: smoke degrade (simula assenza) + dry-run su fixture (vedi verify).
- [ ] Step 3: checkpoint TodoWrite.

**Verify command:**
```bash
TMP=$(mktemp -d); ( cd "$TMP" && git init -q && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "Generated with Claude Code" )
printf 'Generated with Claude Code==>\n' > "$TMP/patterns.txt"
# degrade: forziamo PATH senza git-filter-repo
PATH="/usr/bin:/bin" bash ~/.claude/skills/clean-public-repo/scripts/surgical-rewrite.sh "$TMP" "$TMP/patterns.txt" dry-run; echo "exit=$?"
# atteso: messaggio install + exit 3 (degrade graceful), NESSUN force-push
rm -rf "$TMP"
```
Atteso: messaggio install di git-filter-repo + `exit=3`; nessuna mutazione remota.

**Stima:** 30 min.

---

### Task 6 — SKILL.md clean-public-repo (green: guida procedurale orchestrator)

**Files:**
- Create: `~/.claude/skills/clean-public-repo/SKILL.md` (~230 righe)

**Red phase:** il file non esiste; gli anchor T1 (review-triage-fix) e T7#1-11 falliscono.

**Green phase — contenuto (da ADR D2-D8):**
- **Frontmatter** `name: clean-public-repo` + `description` (audit + cleanup repo pubblico,
  azione ibrida, retroattivo). **NIENTE** `disable-model-invocation: true` (invocabile a
  richiesta e raccomandabile dal chain).
- `## Lingua` (italiano verso utente; inglese per description/intestazioni report/path).
- `## When to invoke` + `## Orchestrator-only` (gira sull'orchestrator; le operazioni git
  distruttive richiedono HITL; mai dispatchare un sub-agent per rewrite/force-push).
- `## Inquadramento etico` — **dichiarazione esplicita**: rimuove marcatori dello strumento +
  cura qualità; **MAI falsifica autori** (commit resta attribuito all'autore git reale); MAI
  inganna review umane / mente attivamente. (Vincolo etico HARD — ancorato in T7.)
- `## Auto-detect remote pubblico` (D1; riferisce `scripts/detect-public-remote.sh`; fail-safe
  silent).
- `## Detection` (D3; `scripts/detect-tool-traces.sh` grep custom primario; gitleaks opzionale
  con degrade graceful — nota "gitleaks non installato → grep-only"; falsi positivi review-needed).
- `## Azione ibrida` (D4; segnala→rimuove-su-conferma; **mai rimozione cieca**; per categoria/elemento).
- `## Report contract` (D4; `docs/clean-report/<date>-<slug>.md`; categorie R3; severity;
  **sezione COPERTURA & LIMITI obbligatoria** — cosa NON copre: binari, generati, metadati,
  tracce semantiche, file non tracciati).
- `## Strategia history — fresh-history publish (default per già-pubblici)` (D5; orphan branch;
  repo derivato; history originale privata; `scripts/fresh-history-publish.sh`; backup tar).
- `## Strategia history — rewrite chirurgico (opzione 2, mai default)` (D6;
  `scripts/surgical-rewrite.sh`; clone fresco + backup tar + dry-run + **HITL prima del
  force-push**; degrade graceful se git-filter-repo assente).
- `## Dipendenze e degrade graceful` (D2 tabella: git core sempre; git-filter-repo / gitleaks /
  gh opzionali con messaggio install; percorso minimo grep+fresh-history funziona con solo git).
- `## Safety / fail-mode` (D8; HITL su ogni operazione distruttiva; backup before; dry-run
  before; mai force-push automatico/da sub-agent).
- `## Coexistence` (D7; NON patcha agent/altre skill/hook; la modalità anonima nel chain è
  separata e veicolata nei prompt-template).

- [ ] Step 1: scrivi `SKILL.md` (PATTERN: ADD).
- [ ] Step 2: verifica che gli anchor T1 review-triage-fix passino e che il file contenga i
      literal richiesti dal self-test (vedi T7).
- [ ] Step 3: checkpoint TodoWrite.

**Verify command:**
```bash
S=~/.claude/skills/clean-public-repo/SKILL.md
grep -q 'name: clean-public-repo' "$S" && echo "name ok"
grep -q 'orchestrator' "$S" && echo "orchestrator ok"
! grep -q 'disable-model-invocation: true' "$S" && echo "no disable ok"
grep -Eqi 'mai falsifica|no falsificazione|never falsif' "$S" && echo "ethics anchor ok"
grep -Eqi 'LIMITI|COPERTURA' "$S" && echo "limits anchor ok"
grep -Eqi 'fresh-history' "$S" && echo "fresh-history ok"
bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh | tail -1
```
Atteso: tutti `ok`; review-triage-fix `PASS=62 FAIL=0` (i 2 anchor T1 ora verdi).

**Stima:** 45 min.

---

### Task 7 — Self-test harness (green: structural anchor + smoke dei 2 detector puri)

**Files:**
- Create: `~/.claude/skills/clean-public-repo/tests/run-tests.sh` (bash 3.2, target PASS=18)

**Red phase:** il harness non esiste.

**Green phase — struttura (scaffolding `ok`/`bad`/`PASS`/`FAIL`, `TMP=$(mktemp -d)`,
`S="$HOME/.claude/skills/clean-public-repo/SKILL.md"`,
`DR="$HOME/.claude/skills/clean-public-repo/scripts/detect-public-remote.sh"`,
`DT="$HOME/.claude/skills/clean-public-repo/scripts/detect-tool-traces.sh"`):**

**A. Structural anchor sullo SKILL.md (ADR D8):**
1. `[ -f "$S" ]`.
2. `grep -q 'name: clean-public-repo'`.
3. `! grep -q 'disable-model-invocation: true'` (anchor negativo).
4. `grep -q 'orchestrator'`.
5. `grep -Eqi 'mai falsifica|no falsificazione|never falsif'` (vincolo etico — critico).
6. `grep -Eqi 'LIMITI|COPERTURA'` (sezione limiti report — critico).
7. `grep -Eqi 'fresh-history'` (strategia default già-pubblici).
8. `grep -Eqi 'rewrite chirurgico|surgical'` (opzione 2).
9. `grep -Eqi 'dry-run'` (safety).
10. `grep -Eqi 'force-push'` + presenza di `HITL`/conferma vicino (safety distruttiva).
11. `grep -q '## Lingua'`.

**B. Smoke `detect-public-remote.sh` (ADR D1 — protegge "fail-safe silent"):** fixture `mktemp -d`:
12. dir non-git → `head -1` == `silent`. *(regressione anti falso-avvio su locale.)*
13. git init senza remote → `silent`. *(regressione anti falso-avvio.)*
14. git init + remote `gitlab.com` → `silent`. *(host non-github.)*

**C. Smoke `detect-tool-traces.sh` (ADR D3):** fixture `mktemp -d`:
15. file con `# added by Claude` → output contiene `auto-removable`.
16. `package.json` con `claude-sdk` dep → output marca `review-needed` (NON auto-removable su
    quel match). *(regressione anti falso-positivo SPEC edge — NON allentare.)*
17. file pulito (nessun marcatore) → exit 0 / nessun `auto-removable`.
18. emoji decorativa + `claude` in un .md → `auto-removable` `string-emoji`.

Helper `pr(dir)`: `bash "$DR" "$dir" | head -1`. Bash 3.2-clean.

- [ ] Step 1: scrivi harness con i 18 test (PATTERN: ADD); `chmod +x`.
- [ ] Step 2: esegui.
- [ ] Step 3: checkpoint.

**Verify command:**
```bash
bash ~/.claude/skills/clean-public-repo/tests/run-tests.sh; echo "exit=$?"
```
Atteso: `PASS=18 FAIL=0`, exit 0.

**Stima:** 35 min.

---

### Task 8 — Gate 0b + modalità anonima nel chain SKILL.md (green)

**Files:**
- Modify: `~/.claude/skills/concept-to-code/SKILL.md` (backup prima: `.bak-2026-05-23`)

**Red phase:** anchor T1 concept-to-code (`Gate 0b`, `anonymize`) falliscono.

**Green phase (edit concreto, da ADR D1/D7):**
1. **§1/§5 Gate 0b:** aggiungi un nuovo gate condizionale **dopo Gate 0** (`[c] chain`) e prima
   della transizione a `step_1_interview`. Esegui
   `scripts/detect-public-remote.sh <project-root>`:
   - output `silent` → Gate 0b **no-op silenzioso** (UX invariata; `anonymize` resta `false`).
   - output `public` → mostra il box Gate 0b (italiano) con `[y]` attiva modalità anonima /
     `[n]` no / `[a]` abort. `[y]` → setta `manifest.anonymize = true`. `[n]` → resta `false`.
   - **Decisione utente, mai auto-applicata** (SPEC R1).
2. **§4 Step 2 (dispatch architect):** se `anonymize=true`, aggiungi al template un blocco
   "Anonymize mode: ADR/plan concisi, no meta-commenti sullo strumento".
3. **§4 Step 5 (dispatch coder):** se `anonymize=true`, aggiungi al template "Anonymize mode
   active": commit Conventional corti/essenziali (no trailer strumento), nessun commento-traccia,
   nessun file slop, nessuna emoji decorativa, doc concisi. **NON modificare `coder.md`.**
   Quando `anonymize=false` il template resta identico a oggi.
4. **§5 recap dei gate:** mostra `Anonymize: ON/OFF` nei box per trasparenza.
5. **§6 Coexistence:** aggiungi `clean-public-repo` alla lista delle skill **raccomandate** (per
   il cleanup retroattivo, non invocata automaticamente dal chain); ribadisci che la modalità
   anonima è veicolata nei prompt-template, NON in `coder.md`/`architect.md`.

Vincoli: NON alterare i gate esistenti (0/1/1b/2/3/4/5) né le transizioni della state machine
(Gate 0b è un check, non uno stato). Backup obbligatorio prima dell'edit.

- [ ] Step 1: backup SKILL.md del chain.
- [ ] Step 2: edita §1/§4/§5/§6 (PATTERN: ADD per Gate 0b + blocchi anonimi; MODIFY per i recap).
- [ ] Step 3: checkpoint.

**Verify command:**
```bash
grep -c 'Gate 0b' ~/.claude/skills/concept-to-code/SKILL.md
grep -c 'anonymize' ~/.claude/skills/concept-to-code/SKILL.md
grep -c 'detect-public-remote' ~/.claude/skills/concept-to-code/SKILL.md
```
Atteso: ciascuno >= 1.

**Stima:** 30 min.

---

### Task 9 — Manifest schema 1.2 + campo `anonymize` (green: validate + init)

**Files:**
- Modify: `~/.claude/skills/concept-to-code/scripts/manifest-validate.sh` (backup prima)
- Modify: `~/.claude/skills/concept-to-code/scripts/manifest-init.sh` (backup prima)

**Red phase:** anchor T1 concept-to-code (`manifest-validate: schema 1.2`) fallisce (se ADR-0010
non ancora deployato); un manifest 1.2 con `anonymize` verrebbe rifiutato.

**Green phase (edit concreto, da ADR D1/Neutral):**
1. **manifest-validate.sh — Invariant 1 (riga 29):** verifica lo stato LIVE della regex:
   - se è `^manifest_schema_version: "(1\.0|1\.1)"$` → estendi a `(1\.0|1\.1|1\.2)`.
   - se è già `(1\.0|1\.1|1\.2)` (ADR-0010 deployato) → **nessuna modifica** (l'anchor è già
     verde). Annotalo nel checkpoint.
2. **manifest-validate.sh — campo `anonymize` (additivo):** aggiungi un invariante leggero: se
   il campo `anonymize:` è presente, deve essere `true|false` (regex
   `^anonymize: (true|false)$`); se assente, valido (retrocompat 1.0/1.1). Non renderlo
   obbligatorio.
3. **manifest-init.sh:** scrivi `anonymize: false` nel template del manifest (sezione di stato,
   accanto a `mode`/`gate0`). Default sicuro.

Vincoli: NON toccare gli altri invarianti né `VALID_STEPS` (Gate 0b non è uno stato); i manifest
1.0/1.1 esistenti devono restare validi (campo additivo). Backup obbligatorio prima dell'edit.

- [ ] Step 1: backup dei due script.
- [ ] Step 2: edita Invariant 1 (se necessario) + invariante `anonymize` + init (PATTERN: MODIFY
      per la regex / ADD per il nuovo invariante e la riga init).
- [ ] Step 3: smoke (vedi verify) + checkpoint.

**Verify command:**
```bash
V=~/.claude/skills/concept-to-code/scripts/manifest-validate.sh
TMP=$(mktemp -d)
bash ~/.claude/skills/concept-to-code/scripts/manifest-init.sh smoke-anon "Smoke anon" "$TMP" >/dev/null 2>&1
M="$TMP/docs/manifests/$(date +%Y-%m-%d)-smoke-anon.manifest.yml"
grep -q '^anonymize: false' "$M" && echo "init writes anonymize:false"
sed 's/^manifest_schema_version: "1.1"/manifest_schema_version: "1.2"/; s/^anonymize: false/anonymize: true/' "$M" > "$TMP/m12.yml"
bash "$V" "$TMP/m12.yml" && echo "1.2 + anonymize:true accepted"
bash "$V" "$M" && echo "init manifest still valid"
rm -rf "$TMP"
```
Atteso: `init writes anonymize:false`; `1.2 + anonymize:true accepted`; `init manifest still valid`.

**Stima:** 20 min.

---

### Task 10 — Anchor green + gate anchor-preserving (verify integrazione)

**Files:** nessuna modifica nuova — gate di verifica che T1+T6+T8+T9 hanno portato i 5 anchor
verdi e che tutti gli altri harness sono intatti.

**Red→Green:** già coperto da T1 (red) + T6/T8/T9 (green). Questo task è il **gate
anchor-preserving** sull'intero parco harness vivo.

- [ ] Step 1: esegui tutti gli harness vivi.
- [ ] Step 2: confronta con baseline dichiarato.
- [ ] Step 3: checkpoint.

**Verify command:**
```bash
bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh | tail -1
bash ~/.claude/skills/concept-to-code/tests/run-tests.sh | tail -1
bash ~/.claude/skills/concept-to-code/tests/smoke-e2e.sh | tail -1
bash ~/.claude/skills/clean-public-repo/tests/run-tests.sh | tail -1
bash ~/.claude/skills/design-brainstorm/tests/run-tests.sh | tail -1
bash ~/.claude/skills/refactor-snapshot/tests/run-tests.sh | tail -1
bash ~/.claude/skills/vibe-status/tests/run-tests.sh | tail -1
bash ~/.claude/hooks/tests/pre-flight-pattern-enforce.sh | tail -1
bash ~/.claude/hooks/tests/run-hook-tests.sh | tail -1
bash ~/.claude/hooks/tests/db-backup-guardrail.sh | tail -1
```
Atteso: review-triage-fix **PASS=62**; concept-to-code **PASS=23**; smoke-e2e verde (intatto);
clean-public-repo **PASS=18**; design-brainstorm 9; refactor-snapshot 18; vibe-status 10;
pre-flight-pattern-enforce 13; run-hook-tests 24; db-backup-guardrail 16. Tutti `FAIL=0`.
(Se ADR-0010/web-e2e-test è deployato: aggiungi `web-e2e-test` PASS=14 alla verifica e
concept-to-code potrebbe partire da una baseline più alta — adegua i numeri al live e
documenta lo scostamento nel checkpoint.)

**Stima:** 8 min.

---

### Task 11 — Doc status sync + memory

**Files:**
- Modify: `docs/architecture/ADR-0011-clean-public-repo-anonymize.md` (Status: Proposed → Accepted)
- Create: `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/project_clean-public-repo-anonymize.md`
- Modify: `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/MEMORY.md` (append `## Project`)

**Green phase:** aggiorna lo status dell'ADR; crea la project memory con: skill deployata (path)
+ Gate 0b nel chain + modalità anonima via prompt-template (NON patcha coder.md/architect.md) +
schema 1.2 campo `anonymize`; **architettura ibrida C+D** (prevenzione nuovi + rimedio
esistenti; fresh-history default per già-pubblici, rewrite chirurgico opzione 2); **rischio TOP
= rewrite distruttivo → mitigato by design** (default fresh-history, no force-push sul repo
originale; rewrite opt-in con backup tar+dry-run+HITL); **degrade graceful** (gitleaks ASSENTE →
grep-only; git-filter-repo presente ma verificato a runtime; gh assente → Gate 0b silent);
detection grep custom + falsi positivi review-needed; report con sezione COPERTURA & LIMITI
obbligatoria; **vincolo etico** (rimuove marcatori, mai falsifica autori); **open question:
rewrite/fresh-history/force-push reali validabili solo in pilota** (harness copre solo detector
puri + structural anchor); harness clean-public-repo PASS=18, review-triage-fix 62,
concept-to-code 23. Cross-link `[[project_concept-to-code-chain]]`, `[[project_web-e2e-test]]`,
`[[feedback_bash32-constraint]]`, `[[feedback_hitl-and-security-discipline]]`. Frontmatter
coerente con le altre memory.

- [ ] Step 1: edita ADR status (PATTERN: MODIFY).
- [ ] Step 2: crea project memory (PATTERN: ADD).
- [ ] Step 3: append riga index in MEMORY.md (PATTERN: MODIFY). Checkpoint finale.

**Verify command:**
```bash
grep -n 'Status:' docs/architecture/ADR-0011-clean-public-repo-anonymize.md | head -1
ls -la ~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/project_clean-public-repo-anonymize.md
grep -c 'clean-public-repo' ~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/MEMORY.md
```
Atteso: ADR `Accepted`; file memory presente; almeno 1 occorrenza in MEMORY.md.

**Stima:** 10 min.

---

## Harness PASS delta atteso (riepilogo)

| Harness | Baseline | Atteso post-plan |
|---|---|---|
| review-triage-fix | 60 | **62** (+2 anchor: SKILL.md present, orchestrator-only) |
| concept-to-code | 20 | **23** (+3 anchor: Gate 0b, anonymize mode, schema 1.2) |
| clean-public-repo (nuovo) | — | **18** (11 structural anchor + 3 smoke detect-public-remote + 4 smoke detect-tool-traces) |
| design-brainstorm | 9 | 9 (intatto) |
| refactor-snapshot | 18 | 18 (intatto) |
| vibe-status | 10 | 10 (intatto) |
| pre-flight-pattern-enforce | 13 | 13 (intatto) |
| run-hook-tests | 24 | 24 (intatto) |
| db-backup-guardrail | 16 | 16 (intatto) |

**Stima totale:** ~278 min (~4h40).

## Note di testabilità (onestà — ADR D8)

Il harness verifica SOLO ciò che è deterministico e headless: structural anchor sullo SKILL.md
(il contratto è scritto, incluso il vincolo etico e la sezione LIMITI) + smoke dei 2 detector
*puri* (`detect-public-remote.sh` fail-safe verso `silent`; `detect-tool-traces.sh` trova i
marcatori e marca i falsi positivi `review-needed`). Restano **open question, validabili solo in
pilota** con un repo reale + remote: il fresh-history publish effettivo (orphan+push su repo
derivato), il rewrite chirurgico reale (git-filter-repo apply + force-push), l'integrazione
gitleaks/gh su un remote vero, la detection della visibilità reale via `gh`. Non fingere
copertura che non c'è.

## Nota di coesistenza con ADR-0010 (web-e2e-test)

ADR-0010 ha pianificato un bump 1.1→1.2 (`artifacts.e2e` + stato `gate_6_e2e_web`). Ordine di
deploy non garantito. **T9 verifica lo stato LIVE della regex riga 29 prima di editare:** se lo
schema è già 1.2, NON ri-bumpa, aggiunge solo il campo `anonymize` (additivo); se è ancora
1.1, introduce 1.2 con `anonymize`. In entrambi i casi 1.2 resta retrocompat 1.0/1.1. Gate 0b
NON è uno stato → nessuna collisione con `gate_6_e2e_web` in `VALID_STEPS`.

## Rollback (HITL, no auto-delete)

Backout = ripristina `concept-to-code/SKILL.md.bak-2026-05-23`,
`manifest-validate.sh.bak-2026-05-23`, `manifest-init.sh.bak-2026-05-23`, rimuovi i 2+3 anchor
dai due harness, rimuovi la dir `~/.claude/skills/clean-public-repo/`. Tutte eliminazioni → HITL
utente (regola globale: mai eliminare file senza conferma). L'agent può solo *proporre* il
backout.

## Riferimenti

- ADR: `docs/architecture/ADR-0011-clean-public-repo-anonymize.md`
- SPEC: `/Users/stefanoferri/Developer/vibe-coding-system/SPEC.md`
- BRAINSTORM: `/Users/stefanoferri/Developer/vibe-coding-system/BRAINSTORM.md`
- Chain: `~/.claude/skills/concept-to-code/SKILL.md`, `scripts/manifest-validate.sh`,
  `scripts/manifest-init.sh`
- Pattern skill invocata/raccomandata dal chain: `~/.claude/skills/web-e2e-test/SKILL.md`
  (ADR-0010), `~/.claude/skills/design-brainstorm/SKILL.md` (ADR-0008)
- Prior-art tooling (researcher): `git-filter-repo` (rewrite chirurgico,
  `--replace-text`/`--dry-run`/`--message-callback`, rifiuta non-fresh-clone),
  `git checkout --orphan` (fresh-history), `gitleaks` (detection opzionale), `tar -czf` backup
- Memory: `feedback_bash32-constraint`, `feedback_hitl-and-security-discipline`,
  `project_concept-to-code-chain`
