# Design Spec — End-to-end smoke test concept-to-code

**Date:** 2026-05-20
**Status:** implementato — 2026-05-20
**ADR:** [ADR-0007](../../architecture/ADR-0007-concept-to-code-e2e-smoke.md)
**Plan:** [2026-05-20-concept-to-code-e2e-smoke.md](../plans/2026-05-20-concept-to-code-e2e-smoke.md)

---

## 1. Objective

Aggiungere uno smoke E2E (`tests/smoke-e2e.sh`) che esercita la composizione
completa init → 16 legal transitions → 3 illegal → 1 failure-force su
manifest tmp, integrato come 13ª assertion composita di
`tests/run-tests.sh`.

## 2. Scope

### In scope

- Nuovo script `~/.claude/skills/concept-to-code/tests/smoke-e2e.sh` (bash
  3.2-clean, executable).
- Modifica `~/.claude/skills/concept-to-code/tests/run-tests.sh` per invocare
  smoke-e2e.sh come 13ª assertion (add, NON modificare le 12 esistenti).
- Aggiornamento `SKILL.md` linea 92-equivalente: "Self-test PASS=13 FAIL=0"
  (era PASS=12 implicito).

### Out of scope

- Test di failure handling cross-step (es. "se manifest-validate.sh ritorna
  exit 2, transition rejects with right reason"). Pattern coperto solo
  superficialmente; out-of-scope per v1.
- Test di concurrency (2 transition simultanee su stesso manifest). YAGNI.
- Tracing/logging stack ML — fuori dominio.

## 3. Stack

- **Shell:** bash 3.2.57. NO assoc array, NO `mapfile`, NO `${v^^}`, NO `<()`.
- **Tools:** coreutils (`mktemp`, `grep`, `sed`, `awk`, `cat`, `date`, `cp`,
  `rm`), nessuna dipendenza esterna.
- **YAML parsing:** `grep`/`sed` line-based (manifest format è line-based,
  no nested structures rilevanti per smoke).

## 4. Contracts

### 4.1 `smoke-e2e.sh` invocation contract

```
bash ~/.claude/skills/concept-to-code/tests/smoke-e2e.sh
```

**No env input.** No args.

**Stdout (PASS):**
```
SMOKE=PASS
```

**Stdout (FAIL):**
```
SMOKE=FAIL:<phase>:<detail>
```

`<phase>` ∈ {`setup`, `init`, `happy`, `illegal`, `failure-force`,
`consistency`, `teardown`}.

**Stderr:** una linea per ogni step interno, prefisso `[smoke]`:

```
[smoke] setup OK tmp=/tmp/tmp.XXXX
[smoke] init OK M=/tmp/tmp.XXXX/proj/docs/manifests/2026-05-20-demo.manifest.yml
[smoke] happy 1/18 step_0_init→step_1_interview OK current_step=step_1_interview
[smoke] happy 2/18 step_1_interview→gate_1_spec_review OK ...
...
[smoke] illegal 1/3 step_0→step_5_implementation REJECTED OK
[smoke] failure-force OK status=failed
[smoke] consistency OK current_step=completed status=completed
[smoke] teardown OK
```

**Exit codes:**
- `0` — SMOKE=PASS, all phases green.
- `1` — SMOKE=FAIL al primo step che fallisce. Successive phases NON eseguite
  (fail-fast).

**Side effects:** zero persistenti. `mktemp -d` + `trap 'rm -rf "$TMP"' EXIT`
garantisce cleanup unconditional.

### 4.2 `run-tests.sh` integration

Aggiungi prima della linea finale `echo "----" / echo PASS/FAIL` (linea 101+):

```
# --- Assertion 13: end-to-end smoke ---
bash "$SKILL_DIR/tests/smoke-e2e.sh" >/dev/null 2>&1 \
  && ok "smoke-e2e: full state machine composition" \
  || bad "smoke-e2e: full state machine composition"
```

Non rimuove né modifica le 12 esistenti.

### 4.3 SKILL.md changes

Aggiungere/modificare la sezione test contracts (se esiste una linea che
cita "self-test: target PASS=10" o simili) → "target PASS=13 FAIL=0".

(N.B.: la SKILL.md di concept-to-code non ha sezione esplicita "Self-test"
come ce l'ha refactor-snapshot. Lo aggiungiamo nel plan task corrispondente
solo se serve documentare per `vibe-status`.)

## 5. Data model

### 5.1 Tmp layout durante smoke

```
$TMP/
  proj/
    docs/
      manifests/
        2026-05-20-demo.manifest.yml        # primary manifest
  proj2/
    docs/manifests/2026-05-20-demo2.manifest.yml   # second flow (shortcut)
  proj3/
    docs/manifests/2026-05-20-illegal.manifest.yml # for illegal attempts
  proj4/
    docs/manifests/2026-05-20-fail.manifest.yml    # for failure-force
```

Manifest paths derivati da `manifest-init.sh` output convention:
`<project-root>/docs/manifests/$(date +%Y-%m-%d)-<slug>.manifest.yml`.

### 5.2 Happy path transitions (18 sequence covering 16 unique pairs)

Su `proj/`:
```
 1. step_0_init                  → step_1_interview
 2. step_1_interview             → gate_1_spec_review
 3. gate_1_spec_review           → step_1_interview               (reject)
 4. step_1_interview             → gate_1_spec_review              (re)
 5. gate_1_spec_review           → step_2_architecture             (approve)
 6. step_2_architecture          → gate_2_architecture_review
 7. gate_2_architecture_review   → step_2_architecture             (reject)
 8. step_2_architecture          → gate_2_architecture_review      (re)
 9. gate_2_architecture_review   → step_3_project_memory           (approve)
10. step_3_project_memory        → gate_3_project_memory_review
11. gate_3_project_memory_review → step_3_project_memory           (reject)
12. step_3_project_memory        → gate_3_project_memory_review    (re)
13. gate_3_project_memory_review → step_4_session_boundary         (approve)
14. step_4_session_boundary      → ready_for_implementation
15. ready_for_implementation     → step_5_implementation
16. step_5_implementation        → step_6_review                   (long path)
17. step_6_review                → gate_5_review_decision
18. gate_5_review_decision       → completed
```

Pairs distinte coperte da questo flow: 15/16.

### 5.3 Second flow (shortcut path)

Su `proj2/`:
```
1'. step_0_init                  → step_1_interview
2'. step_1_interview             → gate_1_spec_review
3'. gate_1_spec_review           → step_2_architecture
4'. step_2_architecture          → gate_2_architecture_review
5'. gate_2_architecture_review   → step_3_project_memory
6'. step_3_project_memory        → gate_3_project_memory_review
7'. gate_3_project_memory_review → step_4_session_boundary
8'. step_4_session_boundary      → ready_for_implementation
9'. ready_for_implementation     → step_5_implementation
10'. step_5_implementation       → gate_5_review_decision   (SHORTCUT, 16ª pair)
11'. gate_5_review_decision      → completed
```

Total coverage: 16/16 unique legal pairs.

### 5.4 Illegal attempts (3)

Su `proj3/` (fresh manifest in step_0_init):
```
illegal 1: step_0_init → step_5_implementation     (skip ahead, exit 1)
illegal 2: step_0_init → completed                  (jump terminal, exit 1)
illegal 3: step_0_init → gate_2_architecture_review (skip gates, exit 1)
```

### 5.5 Failure-force

Su `proj4/` (fresh manifest in step_0_init):
```
manifest-transition $M failed → exit 0, manifest.status="failed"
```

## 6. Validation strategy

### 6.1 smoke-e2e.sh internal assertion (per phase)

Dopo ogni step, esegue check minimo:
- Happy: `grep "^current_step:" $M` → `current_step: "<expected>"`. Se
  mismatch → SMOKE=FAIL.
- Illegal: exit code di `manifest-transition` deve essere 1. Se 0 → SMOKE=FAIL.
- Failure-force: exit 0, e `grep '^status: "failed"' $M`.
- Consistency final: `current_step=completed`, `status=completed`,
  `last_updated_at` ≥ `created_at`.

### 6.2 Anchor invariants

- `~/.claude/skills/review-triage-fix/tests/run-tests.sh` → PASS ≥ 49 (anchor
  duro; target 50 post fix in flight).
- `~/.claude/skills/refactor-snapshot/tests/run-tests.sh` → PASS = 11 (anchor).
- `~/.claude/skills/concept-to-code/tests/run-tests.sh` → PASS = 13 (era 12).

Plan non tocca review-triage-fix né refactor-snapshot.

### 6.3 Performance budget

Misurazione: `time bash tests/smoke-e2e.sh` deve completare in <8s wall
(target <5s). Se >8s, warning su stderr nell'orchestrator del plan, NON
fail dell'assertion.

## 7. Risks

| Risk | Mitigation |
|---|---|
| `manifest-init.sh` exit 2 su double-init same day (linea 22 di run-tests.sh assertion 2) | smoke usa 4 PROJECT root distinti (proj/proj2/proj3/proj4) → ogni init è fresco. No collisione. |
| `date +%Y-%m-%d` differente tra l'INIT e VALIDATE se smoke gira a mezzanotte | Quasi impossibile (smoke <8s); risk acceptato. |
| Forced `failed` status non onorato perché manifest-validate richiede `failed.failed_step` non-null (assertion 10) | smoke per la failure-force imposta esplicitamente `failed_step: "step_0_init"` via sed dopo la transizione, prima della validate. |
| Cleanup leak se smoke aborts hard (kill -9) | `trap 'rm -rf "$TMP"' EXIT` non scatta su SIGKILL. Acceptable: /tmp si auto-pulisce; non running in CI long-lived. |
| Filesystem case-insensitive su macOS HFS+ → "Demo" ≠ "demo" mismatch | smoke usa solo lowercase slug ("demo", "demo2"). Allineato con `manifest-init.sh` slug convention. |
| Cambi futuri al numero di pairs (es. 18 invece di 16) | Smoke esercita le pairs *dichiarate*; un nuovo pair non testato passerebbe il smoke. Documento in ADR-0007 §4 come known gap; mitigation: aggiornare smoke ogni volta che si tocca `manifest-transition.sh`. |

## 8. Open questions

Nessuna — tutte le 4 domande dell'orchestrator hanno risposta in ADR-0007 §2.5.

## 9. Acceptance criteria

1. `smoke-e2e.sh` exists, executable, bash 3.2-clean (validato con `bash -n`
   + grep negative pattern).
2. `bash ~/.claude/skills/concept-to-code/tests/smoke-e2e.sh` → exit 0,
   stdout `SMOKE=PASS` in <8s.
3. `bash ~/.claude/skills/concept-to-code/tests/run-tests.sh` → PASS=13 FAIL=0.
4. Anchor: `~/.claude/skills/review-triage-fix/tests/run-tests.sh` PASS ≥ 49.
5. Anchor: `~/.claude/skills/refactor-snapshot/tests/run-tests.sh` PASS = 11.
6. Mutation test (manual): inserire typo in `manifest-transition.sh` PAIRS
   line (es. `step_1_interviuw`) → `smoke-e2e.sh` deve fallire con
   `SMOKE=FAIL:happy:...`. Annota nel report.
7. Tmpdir cleanup verificato: `ls /tmp/tmp.*` post-smoke ritorna nulla
   relativa al smoke run.
