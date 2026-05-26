# Design Spec — `RFS_RUNS=N` configurable determinism per refactor-snapshot

**Date:** 2026-05-20
**Status:** implementato — 2026-05-20
**ADR:** [ADR-0006](../../architecture/ADR-0006-refactor-snapshot-runs-configurable.md)
**Plan:** [2026-05-20-refactor-snapshot-runs-configurable.md](../plans/2026-05-20-refactor-snapshot-runs-configurable.md)

---

## 1. Objective

Trasformare il numero di esecuzioni del PRE-snapshot del refactor-snapshot harness da
costante hardcoded (3) a parametro configurabile via env var `RFS_RUNS` (default 3,
range [1,10]), con validazione fail-loud e audit trail nel report del refactorer.

## 2. Scope

### In scope

- Nuovo script eseguibile `~/.claude/skills/refactor-snapshot/scripts/pre-runs.sh`
  (bash 3.2-clean).
- Update `~/.claude/skills/refactor-snapshot/SKILL.md`:
  - sezione "Invocation contract" (3 chiamate `capture.sh PRE` → 1 chiamata
    `pre-runs.sh`).
  - sezione "Env vars" (`RFS_DETERMINISM_RUNS` → `RFS_RUNS`, default 3 range [1,10]).
- Update `~/.claude/agents/refactorer.md` Step 3 wording (2 righe).
- Update `~/.claude/skills/refactor-snapshot/tests/run-tests.sh`: aggiungere +6
  assertion per `pre-runs.sh` (no rimozioni dei 10 esistenti).

### Out of scope

- Modifiche a `capture.sh` o `diff.sh` (orthogonali; preservati intatti).
- File di config per-progetto (Alt-C rifiutata in ADR-0006).
- Override per-step granularity (es. "questo refactor pass usa N=5, il prossimo
  N=3"). Sessione-only env var via dispatch prompt.

## 3. Stack

- **Shell:** bash 3.2.57 (macOS system bash). NO assoc array, NO `mapfile`, NO
  `${v^^}`, NO `<()`.
- **Tooling:** `shasum -a 256` (BSD/macOS) con fallback `sha256sum` (Linux).
  Riusa la stessa detection logic di `capture.sh`.
- **No external deps.** Solo coreutils POSIX.

## 4. Contracts

### 4.1 `pre-runs.sh` invocation contract

```
bash ~/.claude/skills/refactor-snapshot/scripts/pre-runs.sh
```

**Env input:**
- `RFS_RUNS` — int, default 3, range [1,10]. Validato; out-of-range / non-numerico
  = exit 1.
- `RFS_TIMEOUT`, `RFS_FILTER`, `RFS_FULL` — passati through a ogni invocazione di
  `capture.sh PRE`. Non riletti dentro `pre-runs.sh`; vivono come env eredita.

**Cwd:** `$PWD` deve essere il project root (stesso contract di `capture.sh`).

**Stdout (PASS):**
```
RUNS=3
STATUS=PASS
FIRST_RUN_SHA=<sha256-hex>
```

**Stdout (UNVERIFIED):**
```
RUNS=3
STATUS=UNVERIFIED
DIVERGENT_RUN=2
EXPECTED_SHA=<sha-of-run-1>
ACTUAL_SHA=<sha-of-run-2>
```

**Stdout (N=1, no determinism check):**
```
RUNS=1
STATUS=PASS
NOTE=determinism-check-skipped
```

**Stderr:** ERROR lines per failure modes.

**Exit codes:**
- `0` — PASS (tutti i run identici, oppure N=1).
- `1` — Invalid `RFS_RUNS` (non-numerico, <1, >10).
- `2` — UNVERIFIED (N≥2 e SHA differiscono tra run).
- `3` — `capture.sh` interna ha fallito (test-cmd missing, timeout, etc.).
  Stderr include `FAILED_RUN=<i> CAPTURE_EXIT=<code>`.

**Side effects:**
- Scrive `$PWD/.claude/.refactor-snapshot.txt` (l'ultimo run; byte-faithful
  con format ADR-0002).
- Crea/rimuove tmpdir per snapshot intermedi (cleanup garantito via trap EXIT).
- NON crea `.post`, NON tocca `diff.sh` outputs.

### 4.2 SKILL.md changes

Sezione "Invocation contract" (lines 18-30 attuali) sostituita:

```
The refactorer invokes:

    bash ~/.claude/skills/refactor-snapshot/scripts/pre-runs.sh   # PRE + determinism
    # ... refactor edits ...
    bash ~/.claude/skills/refactor-snapshot/scripts/capture.sh POST
    bash ~/.claude/skills/refactor-snapshot/scripts/diff.sh

`pre-runs.sh` runs `capture.sh PRE` N times (RFS_RUNS, default 3) and verifies
SHA256 identity across runs. STATUS=UNVERIFIED if not deterministic.
```

Sezione "Env vars":
```
- RFS_RUNS (default 3, range [1,10]) — # of PRE runs for determinism check.
  Set RFS_RUNS=1 to skip determinism check (single capture).
- RFS_TIMEOUT (default 120) — per-run test-cmd timeout in seconds.
- RFS_FILTER (default empty) — pattern passed to test-cmd.
- RFS_FULL (default 0) — when 1, ignore RFS_FILTER and use full test scope.
```

Rimossa: `RFS_DETERMINISM_RUNS` (rinominata in `RFS_RUNS`).

### 4.3 `refactorer.md` Step 3 changes

**Prima (1 riga prosa, 3 invocazioni implicite):**
```
3. Determinism check. Re-run pre-snapshot 2 more times (3 total). If SHA256
   differs across runs → STOP, output `UNVERIFIED non-deterministic test output`...
```

**Dopo:**
```
3. PRE capture + determinism check. Invoke
   `bash ~/.claude/skills/refactor-snapshot/scripts/pre-runs.sh`. Default 3 runs;
   override via `RFS_RUNS=<1..10>` env. Exit 0 = PASS, exit 2 = UNVERIFIED.
   On UNVERIFIED → STOP, report flakiness + DIVERGENT_RUN/SHA from stdout.
   Cite `RUNS=N` in the final report.
```

Step 2 attuale ("Pre-snapshot capture") va FUSO in Step 3 (perché `pre-runs.sh`
fa entrambe le cose). Numerazione successiva preservata.

## 5. Data model

### 5.1 Tmp layout durante `pre-runs.sh`

```
$TMP/
  run-1.snapshot       # output di capture.sh PRE per run 1
  run-1.sha            # SHA256 di run-1.snapshot (calcolato da pre-runs.sh)
  run-2.snapshot
  run-2.sha
  ...
  run-N.snapshot
  run-N.sha
```

`$TMP` da `mktemp -d`, cleanup via `trap 'rm -rf "$TMP"' EXIT`.

`run-i.sha` = SHA256 del FULL snapshot file (non solo del payload). Razionale:
include `EXIT=`, `STDOUT-SHA256=`, `STDERR-SHA256=` lines + payload — un singolo
hash cattura ogni differenza tra run.

### 5.2 Comparison logic

```
sha_1 = read run-1.sha
for i in 2..N:
    sha_i = read run-i.sha
    if sha_i != sha_1:
        emit STATUS=UNVERIFIED with DIVERGENT_RUN=i
        cp run-N.snapshot .claude/.refactor-snapshot.txt   # most recent
        exit 2
emit STATUS=PASS with FIRST_RUN_SHA=sha_1
cp run-N.snapshot .claude/.refactor-snapshot.txt
exit 0
```

L'ultimo `run-N.snapshot` viene copiato come PRE baseline finale: anche su
UNVERIFIED preserva il latest stato osservato (utile per debug post-mortem).

## 6. Validation strategy

### 6.1 Self-test additions (target 11 → 17, +6)

1. **`pre-runs.sh` exists + executable** → exit prerequisite.
2. **Default N=3 with deterministic test-cmd** → STATUS=PASS, exit 0, snapshot
   file exists.
3. **N=1 (`RFS_RUNS=1`) with deterministic test-cmd** → STATUS=PASS, NOTE=
   determinism-check-skipped.
4. **N=5 with non-deterministic test-cmd** (e.g. `date +%N`) → STATUS=
   UNVERIFIED, exit 2, DIVERGENT_RUN line present.
5. **Invalid RFS_RUNS=0** → exit 1, stderr contains "invalid".
6. **Invalid RFS_RUNS=11** → exit 1.
7. **Invalid RFS_RUNS=abc** → exit 1.
8. **Missing test-cmd** → exit 3 (capture.sh internal failure propagated),
   stderr `FAILED_RUN=1`.

(Range [1,10] valuta 8 assertion concrete; aggregato 8 nuove ≥ 6 target.)

### 6.2 Anchor harnesses preserved

- `~/.claude/skills/review-triage-fix/tests/run-tests.sh` — DEVE rimanere ≥49
  (idealmente 50 post fix in flight). Questo plan non tocca nessun file della
  review-triage-fix.
- `~/.claude/skills/concept-to-code/tests/run-tests.sh` — DEVE rimanere 12.
  Questo plan non tocca concept-to-code.
- Self-test `refactor-snapshot/tests/run-tests.sh` — target post-deploy 17,
  no rimozioni dei 10 esistenti.

## 7. Risks

| Risk | Mitigation |
|---|---|
| Refactorer dispatch in flight quando rilascio (sessione attiva con vecchio prompt) | Cambio è additivo: il vecchio Step 3 (3x capture.sh) funziona ancora se il prompt è il vecchio. SKILL.md sezione "Invocation contract" annota entrambe le forme nel changelog (vedi plan task 5). |
| Env var leak tra session (RFS_RUNS=8 persistente) | Documented: `RFS_RUNS` è sessione-only, viene da `export` o prefix shell call. Niente persistenza inattesa. |
| Wallclock N×TIMEOUT esplode (es. N=10 × TIMEOUT=120 = 20 min) | Documentato in SKILL.md. L'utente lo decide. |
| Test flaky con failure rate 5% e N=3 → ancora 14% miss | Out-of-scope: la feature consente di aumentare N; la decisione è dell'utente. ADR documenta la math. |
| `pre-runs.sh` invocato senza `.claude/` esistente | `capture.sh` interno fallisce con exit 1 → propagato come exit 3 con FAILED_RUN=1. Stesso behavior di oggi. |

## 8. Open questions

Nessuna — tutte le 4 domande dell'orchestrator hanno risposta in ADR-0006 §2.2.

## 9. Acceptance criteria

1. `pre-runs.sh` esiste, è eseguibile, bash 3.2-clean (verifica: `bash -n
   pre-runs.sh` + `grep -E '<\(|mapfile|declare -A|\$\{[a-z]+\^\^\}' pre-runs.sh`
   ritorna vuoto).
2. Self-test `refactor-snapshot/tests/run-tests.sh` → PASS=17 FAIL=0.
3. Self-test `review-triage-fix/tests/run-tests.sh` → PASS ≥49 (anchor).
4. Self-test `concept-to-code/tests/run-tests.sh` → PASS=12 (anchor).
5. `SKILL.md` e `refactorer.md` aggiornati come §4.2/§4.3.
6. Dry-run manuale: `RFS_RUNS=5 bash pre-runs.sh` in un toy project deterministico
   → exit 0, RUNS=5, STATUS=PASS.
7. Dry-run manuale: `RFS_RUNS=2 bash pre-runs.sh` con test-cmd flaky (`echo
   $RANDOM`) → exit 2, STATUS=UNVERIFIED.
