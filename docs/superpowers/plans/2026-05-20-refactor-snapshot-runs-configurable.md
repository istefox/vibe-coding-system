# Plan — `RFS_RUNS=N` configurable determinism per refactor-snapshot

**Date:** 2026-05-20
**ADR:** [ADR-0006](../../architecture/ADR-0006-refactor-snapshot-runs-configurable.md)
**Spec:** [2026-05-20-refactor-snapshot-runs-configurable-design.md](../specs/2026-05-20-refactor-snapshot-runs-configurable-design.md)
**Style:** TDD (red → green → checkpoint). Auto mode active, no HITL inside the chain.

---

## Anchor invariants (HARD)

- `~/.claude/skills/review-triage-fix/tests/run-tests.sh` → PASS ≥ 49 (target 50 post fix in flight).
- `~/.claude/skills/concept-to-code/tests/run-tests.sh` → PASS = 12.
- `~/.claude/skills/refactor-snapshot/tests/run-tests.sh` → 10 esistenti preservati intatti, +6 nuove.

## Pre-flight constraints

- Bash 3.2.57 ONLY. NO assoc array, NO `mapfile`, NO `${v^^}`, NO `<()`.
- Repo `vibe-coding-system` NON-git: no commit step.
- No backwards-compat shim (RFS_DETERMINISM_RUNS può sparire dal SKILL.md — non era onorata).

---

## Task 1 — RED: aggiungere 6 assertion al self-test refactor-snapshot

**Files modified:**
- `~/.claude/skills/refactor-snapshot/tests/run-tests.sh` — append 6+ assertion dopo
  l'ultima esistente (linea ~74).

**Add (NON rimuovere niente):**
- Assertion 11: `pre-runs.sh` present + executable.
- Assertion 12: default `RFS_RUNS` (unset) con test-cmd deterministico → exit 0,
  STATUS=PASS, RUNS=3.
- Assertion 13: `RFS_RUNS=1` con test-cmd deterministico → exit 0, STATUS=PASS,
  NOTE=determinism-check-skipped present.
- Assertion 14: `RFS_RUNS=4` con test-cmd non-deterministico (`echo $RANDOM`) →
  exit 2, STATUS=UNVERIFIED.
- Assertion 15: `RFS_RUNS=0` → exit 1, stderr contains "invalid".
- Assertion 16: `RFS_RUNS=11` → exit 1.
- Assertion 17: `RFS_RUNS=abc` → exit 1.

**Expected:** run-tests.sh → PASS=10 FAIL=7 (le 7 nuove falliscono perché
`pre-runs.sh` non esiste ancora). Le 10 esistenti restano green.

**Checkpoint:** `bash ~/.claude/skills/refactor-snapshot/tests/run-tests.sh` mostra
FAIL=7 esattamente.

---

## Task 2 — GREEN: implementare `pre-runs.sh`

**Files created:**
- `~/.claude/skills/refactor-snapshot/scripts/pre-runs.sh` (chmod +x).

**Contract (da spec §4.1):**
- Legge `RFS_RUNS` (default 3); valida range [1,10] e tipo numerico (regex
  `^[1-9]$|^10$` — bash 3.2 portable).
- Detecta SHA256 tool (`shasum -a 256` || `sha256sum`).
- `mktemp -d` per work dir; `trap 'rm -rf "$TMP"' EXIT`.
- Loop `i=1..N`:
  - Invoca `bash "$SCRIPT_DIR/capture.sh" PRE`. Se exit ≠0 → emit
    `FAILED_RUN=$i CAPTURE_EXIT=...` su stderr; exit 3.
  - `cp $PWD/.claude/.refactor-snapshot.txt $TMP/run-$i.snapshot`.
  - `$SHA_CMD "$TMP/run-$i.snapshot" | awk '{print $1}' > $TMP/run-$i.sha`.
- Se N=1: stampa `RUNS=1`, `STATUS=PASS`, `NOTE=determinism-check-skipped`;
  exit 0.
- Se N≥2: leggi `run-1.sha` come baseline; loop `i=2..N`:
  - leggi `run-i.sha`; se diverso da baseline → emit `RUNS=N STATUS=UNVERIFIED
    DIVERGENT_RUN=$i EXPECTED_SHA=... ACTUAL_SHA=...`; exit 2.
- Se tutti uguali: emit `RUNS=N STATUS=PASS FIRST_RUN_SHA=...`; exit 0.
- L'ultimo `run-N.snapshot` viene già scritto come `.claude/.refactor-snapshot.txt`
  dall'ultima `capture.sh` (no extra copy necessario; capture overrida sempre).

**Validazione bash 3.2:**
```
bash -n ~/.claude/skills/refactor-snapshot/scripts/pre-runs.sh
grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' ~/.claude/skills/refactor-snapshot/scripts/pre-runs.sh
# secondo grep deve essere vuoto
```

**Expected:** run-tests.sh → PASS=17 FAIL=0.

**Checkpoint:** `bash ~/.claude/skills/refactor-snapshot/tests/run-tests.sh` →
`PASS=17 FAIL=0`.

---

## Task 3 — GREEN: aggiornare SKILL.md (`Invocation contract` + `Env vars`)

**Files modified:**
- `~/.claude/skills/refactor-snapshot/SKILL.md`

**Add:**
- Sezione "Invocation contract" riscritta (spec §4.2): nuovo flow
  `pre-runs.sh → capture.sh POST → diff.sh`.
- Sezione "Env vars": `RFS_RUNS` (default 3, range [1,10]) come prima voce
  dell'elenco.

**Remove:**
- Voce `RFS_DETERMINISM_RUNS` (rinominata).
- Le 3 chiamate esplicite `capture.sh PRE` nella sezione "Invocation contract"
  (sostituite con singola `pre-runs.sh`).

**Expected:** SKILL.md frontmatter intatto; lunghezza ~85-95 righe (era 92).
Self-test assertion 1+2 (frontmatter + description) restano green.

**Checkpoint:** `bash ~/.claude/skills/refactor-snapshot/tests/run-tests.sh` →
PASS=17 FAIL=0. Grep manuale: `grep RFS_DETERMINISM_RUNS SKILL.md` ritorna
vuoto; `grep 'RFS_RUNS' SKILL.md` ritorna ≥1 match.

---

## Task 4 — GREEN: aggiornare `refactorer.md` Step 3

**Files modified:**
- `~/.claude/agents/refactorer.md`

**Add (Step 3 riscritto, fonde con Step 2):**
```
2-3. PRE capture + determinism check. Invoke
     `bash ~/.claude/skills/refactor-snapshot/scripts/pre-runs.sh`.
     Default 3 runs; override via `RFS_RUNS=<1..10>` env. Exit 0 = PASS,
     exit 2 = UNVERIFIED. On UNVERIFIED → STOP, report flakiness with
     DIVERGENT_RUN/EXPECTED_SHA/ACTUAL_SHA from stdout. Cite `RUNS=N` value
     in the final report.
```

Renumerare Step 4-8 → 3-7 (decrementare di 1).

**Remove:**
- Step 2 esistente ("Pre-snapshot capture. Invoke capture.sh PRE...").
- Step 3 esistente ("Determinism check. Re-run 2 more times (3 total)...").

**Sezione "Snapshot Harness Integration":** aggiornare il riferimento
"invoked at steps 2/3 (PRE), 5 (POST), 6 (diff)" → "invoked at step 2-3
(PRE + determinism), step 4 (POST), step 5 (diff)".

**Backup:** prima di modificare, `cp refactorer.md refactorer.md.bak-2026-05-20-rfs-runs`
(già esiste backup `.bak-2026-05-20`, usa suffisso diverso).

**Expected:** refactorer.md ≤ 65 righe (era 64; minimo cambio di forma).

**Checkpoint:** `bash ~/.claude/skills/refactor-snapshot/tests/run-tests.sh` → 17/0.
`bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh` → ≥49. `bash
~/.claude/skills/concept-to-code/tests/run-tests.sh` → 12.

---

## Task 5 — GREEN: smoke test end-to-end manuale (toy project)

**Files created/modified:** none (manual exercise, output annotato nel report).

**Add:**
1. Crea toy project `/tmp/rfs-toy-deterministic/.claude/test-cmd` con `echo hello`.
   - Esegui `cd /tmp/rfs-toy-deterministic && bash ~/.claude/skills/refactor-snapshot/scripts/pre-runs.sh`.
   - Attesa: `RUNS=3 STATUS=PASS FIRST_RUN_SHA=...`, exit 0.
2. Crea toy project `/tmp/rfs-toy-flaky/.claude/test-cmd` con `echo $RANDOM`.
   - Esegui `RFS_RUNS=5 bash pre-runs.sh`.
   - Attesa: `RUNS=5 STATUS=UNVERIFIED DIVERGENT_RUN=2 ...`, exit 2.
3. Same toy, esegui `RFS_RUNS=1 bash pre-runs.sh`.
   - Attesa: `RUNS=1 STATUS=PASS NOTE=determinism-check-skipped`, exit 0.
4. Same toy, esegui `RFS_RUNS=0 bash pre-runs.sh; echo $?`.
   - Attesa: `1`, stderr contains "invalid".

**Expected:** 4/4 smoke pass.

**Checkpoint:** annotare exit codes + RUNS lines nel report finale al dispatcher.

---

## Task 6 — Anchor verification + final report

**Files modified:** none.

**Verify (anchor invariants):**
- `bash ~/.claude/skills/refactor-snapshot/tests/run-tests.sh` → PASS=17 FAIL=0.
- `bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh` → PASS ≥49 FAIL=0.
- `bash ~/.claude/skills/concept-to-code/tests/run-tests.sh` → PASS=12 FAIL=0.

**Report al dispatcher:**
- ADR path, spec path, plan path.
- PASS counts per ognuno dei 3 harness (before/after).
- File modificati (4 totali: `pre-runs.sh` create, `SKILL.md`, `refactorer.md`,
  `tests/run-tests.sh`).
- Smoke test output (4 invocazioni).
- Confidence dichiarata.

---

## Risk register (per coder esecutore)

- **Risk A:** rinumerazione Step 4→3 in `refactorer.md` può perdere
  cross-reference. **Mitigation:** grep `Step [4-7]` prima/dopo, verifica
  che la sezione "Snapshot Harness Integration" sia aggiornata coerentemente.
- **Risk B:** test che genera `$RANDOM` può colpire bash 3.2 quirks su
  macOS old (versione di `$RANDOM` deterministica per seed). **Mitigation:**
  usare `date +%N` o `head -c 4 /dev/urandom | od -An -tu4` per non-determinism
  garantito.
- **Risk C:** `capture.sh` interno emette stderr che inquina output di
  `pre-runs.sh`. **Mitigation:** invocare `capture.sh PRE 2>>"$TMP/capture.err"`
  e citare `$TMP/capture.err` solo su exit≠0.

## HITL gates (none in this plan)

Repo NON-git, no commit. Auto mode. Stefano valida ex-post leggendo il
report del dispatcher.
