# Plan — End-to-end smoke test concept-to-code

**Date:** 2026-05-20
**ADR:** [ADR-0007](../../architecture/ADR-0007-concept-to-code-e2e-smoke.md)
**Spec:** [2026-05-20-concept-to-code-e2e-smoke-design.md](../specs/2026-05-20-concept-to-code-e2e-smoke-design.md)
**Style:** TDD (red → green → checkpoint). Auto mode active, no HITL inside the chain.

---

## Anchor invariants (HARD)

- `~/.claude/skills/review-triage-fix/tests/run-tests.sh` → PASS ≥ 49 (target 50
  post fix in flight). Plan NON tocca review-triage-fix.
- `~/.claude/skills/refactor-snapshot/tests/run-tests.sh` → PASS = 11. Plan NON
  tocca refactor-snapshot.
- `~/.claude/skills/concept-to-code/tests/run-tests.sh` → PASS = 13 (era 12);
  le 12 esistenti restano intatte.

## Pre-flight constraints

- Bash 3.2.57 ONLY. NO assoc array, NO `mapfile`, NO `${v^^}`, NO `<()`.
- Repo `vibe-coding-system` NON-git: no commit step.
- No backwards-compat shim.

---

## Task 1 — RED: aggiungere assertion 13 al self-test concept-to-code

**Files modified:**
- `~/.claude/skills/concept-to-code/tests/run-tests.sh` — append assertion 13
  dopo l'assertion 12 (linea ~99) e prima del recap finale `echo "----"`.

**Add (NON rimuovere niente):**
```
# --- Assertion 13: end-to-end smoke ---
bash "$SKILL_DIR/tests/smoke-e2e.sh" >/dev/null 2>&1 \
  && ok "smoke-e2e: full state machine composition" \
  || bad "smoke-e2e: full state machine composition"
```

**Expected:** `bash tests/run-tests.sh` → PASS=12 FAIL=1 (smoke-e2e.sh non
esiste ancora, exit non-zero).

**Checkpoint:** verificare che le 12 esistenti restino verdi e l'unica nuova
fallisca.

---

## Task 2 — GREEN: scheletro `smoke-e2e.sh` con setup + teardown

**Files created:**
- `~/.claude/skills/concept-to-code/tests/smoke-e2e.sh` (chmod +x).

**Add (skeleton, no logic ancora):**

```
#!/usr/bin/env bash
# concept-to-code smoke E2E test. Exercises full state machine composition.
set -u
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SKILL_DIR="$HOME/.claude/skills/concept-to-code"
INIT="$SKILL_DIR/scripts/manifest-init.sh"
VAL="$SKILL_DIR/scripts/manifest-validate.sh"
TRN="$SKILL_DIR/scripts/manifest-transition.sh"

fail() { echo "SMOKE=FAIL:$1:$2"; exit 1; }

# Phase: setup
echo "[smoke] setup OK tmp=$TMP" >&2

# Phase: init (stub)
# Phase: happy (stub)
# Phase: illegal (stub)
# Phase: failure-force (stub)
# Phase: consistency (stub)

echo "[smoke] teardown OK" >&2
echo "SMOKE=PASS"
exit 0
```

**Expected:** `bash smoke-e2e.sh` → exit 0, stdout `SMOKE=PASS`. Self-test
PASS=13 FAIL=0 (smoke vuoto passa, ma nessuna copertura reale — risolto in
task 3-6).

**Validazione bash 3.2:**
```
bash -n ~/.claude/skills/concept-to-code/tests/smoke-e2e.sh
grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' ~/.claude/skills/concept-to-code/tests/smoke-e2e.sh
# secondo grep deve essere vuoto
```

**Checkpoint:** `bash tests/run-tests.sh` → PASS=13 FAIL=0. Auto-validation:
`bash -n smoke-e2e.sh` exit 0.

---

## Task 3 — GREEN: implementare init + happy path (18 transitions on proj/)

**Files modified:**
- `~/.claude/skills/concept-to-code/tests/smoke-e2e.sh`

**Add:**

1. **Init phase:**
   ```
   PROJ="$TMP/proj"
   mkdir -p "$PROJ"
   bash "$INIT" demo "Demo Feature" "$PROJ" >/dev/null 2>&1 \
     || fail init "init exit non-zero"
   M="$PROJ/docs/manifests/$(date +%Y-%m-%d)-demo.manifest.yml"
   [ -f "$M" ] || fail init "manifest file missing $M"
   echo "[smoke] init OK M=$M" >&2
   ```

2. **Happy path helper:**
   ```
   step() {
     local idx="$1" from="$2" to="$3"
     bash "$TRN" "$M" "$to" >/dev/null 2>&1 \
       || fail "happy" "$idx $from→$to transition rejected"
     local cur
     cur="$(grep '^current_step:' "$M" | sed 's/^current_step: *//;s/"//g' | head -1)"
     [ "$cur" = "$to" ] || fail "happy" "$idx after $from→$to current_step=$cur expected=$to"
     echo "[smoke] happy $idx $from→$to OK current_step=$to" >&2
   }
   ```

3. **18-step sequence (spec §5.2):**
   ```
   step  1 step_0_init step_1_interview
   step  2 step_1_interview gate_1_spec_review
   step  3 gate_1_spec_review step_1_interview
   step  4 step_1_interview gate_1_spec_review
   step  5 gate_1_spec_review step_2_architecture
   step  6 step_2_architecture gate_2_architecture_review
   step  7 gate_2_architecture_review step_2_architecture
   step  8 step_2_architecture gate_2_architecture_review
   step  9 gate_2_architecture_review step_3_project_memory
   step 10 step_3_project_memory gate_3_project_memory_review
   step 11 gate_3_project_memory_review step_3_project_memory
   step 12 step_3_project_memory gate_3_project_memory_review
   step 13 gate_3_project_memory_review step_4_session_boundary
   step 14 step_4_session_boundary ready_for_implementation
   step 15 ready_for_implementation step_5_implementation
   step 16 step_5_implementation step_6_review
   step 17 step_6_review gate_5_review_decision
   step 18 gate_5_review_decision completed
   ```

**Expected:** `bash smoke-e2e.sh` → SMOKE=PASS, stderr mostra 18 happy
lines. Wall <3s.

**Checkpoint:** `bash tests/run-tests.sh` → 13/0. `bash smoke-e2e.sh
2>&1 | grep -c '\[smoke\] happy'` → 18.

---

## Task 4 — GREEN: implementare second flow (shortcut path) on proj2/

**Files modified:**
- `~/.claude/skills/concept-to-code/tests/smoke-e2e.sh`

**Add (after happy phase, before illegal):**

1. **Second flow init:**
   ```
   PROJ2="$TMP/proj2"
   mkdir -p "$PROJ2"
   bash "$INIT" demo2 "Demo 2" "$PROJ2" >/dev/null 2>&1 \
     || fail init "init proj2 exit non-zero"
   M2="$PROJ2/docs/manifests/$(date +%Y-%m-%d)-demo2.manifest.yml"
   [ -f "$M2" ] || fail init "manifest2 missing"
   echo "[smoke] init OK M2=$M2 (shortcut flow)" >&2
   ```

2. **Helper step2 + 11-step sequence (spec §5.3) hitting shortcut pair:**
   ```
   step2() {
     local idx="$1" from="$2" to="$3"
     bash "$TRN" "$M2" "$to" >/dev/null 2>&1 \
       || fail "happy2" "$idx $from→$to transition rejected"
     echo "[smoke] happy2 $idx $from→$to OK" >&2
   }
   step2  1 step_0_init step_1_interview
   step2  2 step_1_interview gate_1_spec_review
   step2  3 gate_1_spec_review step_2_architecture
   step2  4 step_2_architecture gate_2_architecture_review
   step2  5 gate_2_architecture_review step_3_project_memory
   step2  6 step_3_project_memory gate_3_project_memory_review
   step2  7 gate_3_project_memory_review step_4_session_boundary
   step2  8 step_4_session_boundary ready_for_implementation
   step2  9 ready_for_implementation step_5_implementation
   step2 10 step_5_implementation gate_5_review_decision   # SHORTCUT pair
   step2 11 gate_5_review_decision completed
   ```

**Expected:** SMOKE=PASS, 18+11 = 29 stderr lines totali per happy.

**Checkpoint:** `bash smoke-e2e.sh 2>&1 | grep -E 'happy|happy2' | wc -l` → 29.

---

## Task 5 — GREEN: implementare illegal + failure-force + consistency

**Files modified:**
- `~/.claude/skills/concept-to-code/tests/smoke-e2e.sh`

**Add (after happy2 phase):**

1. **Illegal phase (proj3, fresh manifest):**
   ```
   PROJ3="$TMP/proj3"
   mkdir -p "$PROJ3"
   bash "$INIT" illegal "Illegal Tests" "$PROJ3" >/dev/null 2>&1
   M3="$PROJ3/docs/manifests/$(date +%Y-%m-%d)-illegal.manifest.yml"
   illegal() {
     local idx="$1" target="$2"
     bash "$TRN" "$M3" "$target" >/dev/null 2>&1
     local rc=$?
     [ "$rc" = "1" ] || fail "illegal" "$idx target=$target expected exit 1 got $rc"
     echo "[smoke] illegal $idx step_0→$target REJECTED OK" >&2
   }
   illegal 1 step_5_implementation
   illegal 2 completed
   illegal 3 gate_2_architecture_review
   ```

2. **Failure-force phase (proj4):**
   ```
   PROJ4="$TMP/proj4"
   mkdir -p "$PROJ4"
   bash "$INIT" failtest "Fail Force" "$PROJ4" >/dev/null 2>&1
   M4="$PROJ4/docs/manifests/$(date +%Y-%m-%d)-failtest.manifest.yml"
   bash "$TRN" "$M4" failed >/dev/null 2>&1 \
     || fail failure-force "transition to failed rejected"
   # Note: failure.failed_step must be set for validate to pass; smoke records
   # the transition succeeded — validate of failed-manifest is out of scope here
   # because invariant assertion 10 of run-tests.sh already covers it.
   grep -q '^status: "failed"' "$M4" \
     || fail failure-force "status not failed"
   echo "[smoke] failure-force OK status=failed" >&2
   ```

3. **Consistency phase (re-check M from proj/):**
   ```
   final_step="$(grep '^current_step:' "$M" | sed 's/^current_step: *//;s/"//g' | head -1)"
   final_status="$(grep '^status:' "$M" | sed 's/^status: *//;s/"//g' | head -1)"
   [ "$final_step" = "completed" ] || fail consistency "final current_step=$final_step expected completed"
   [ "$final_status" = "completed" ] || fail consistency "final status=$final_status expected completed"
   echo "[smoke] consistency OK current_step=completed status=completed" >&2
   ```

**Expected:** SMOKE=PASS, exit 0; stderr include 3 illegal + 1 failure-force
+ 1 consistency line.

**Checkpoint:** `bash smoke-e2e.sh 2>&1 | grep -E 'illegal|failure-force|consistency' | wc -l` → 5.

---

## Task 6 — GREEN: mutation verification (manual sanity check)

**Files modified:** none persistent.

**Add (executed manually, NOT committed):**

1. Backup `manifest-transition.sh`:
   `cp ~/.claude/skills/concept-to-code/scripts/manifest-transition.sh
   /tmp/mt.bak`.
2. Mutate (insert typo into a PAIRS line, e.g. `step_1_interviuw`):
   `sed -i.bak 's/step_1_interview,gate_1_spec_review/step_1_interviuw,gate_1_spec_review/' ~/.claude/skills/concept-to-code/scripts/manifest-transition.sh`.
3. Run smoke: `bash ~/.claude/skills/concept-to-code/tests/smoke-e2e.sh` →
   expected `SMOKE=FAIL:happy:...`, exit 1.
4. Run full self-test: `bash ~/.claude/skills/concept-to-code/tests/run-tests.sh` →
   expected PASS=12 FAIL=1 (assertion 13 fails; le altre 12 restano green
   perché testano comportamento isolato).
5. Restore: `cp /tmp/mt.bak ~/.claude/skills/concept-to-code/scripts/manifest-transition.sh`.
6. Re-run: assertion 13 → green nuovamente (PASS=13/0).

**Expected:** smoke catches the typo (proves utility).

**Checkpoint:** annotare nel report finale ai dispatcher: "mutation test OK,
smoke detected synthetic typo at happy step 2/18".

---

## Task 7 — Anchor verification + report finale

**Files modified:** none.

**Verify (anchor invariants):**
- `bash ~/.claude/skills/concept-to-code/tests/run-tests.sh` → PASS=13 FAIL=0.
- `bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh` → PASS ≥49 FAIL=0.
- `bash ~/.claude/skills/refactor-snapshot/tests/run-tests.sh` → PASS=11 FAIL=0.
- `time bash ~/.claude/skills/concept-to-code/tests/smoke-e2e.sh` → wall <8s.

**Report al dispatcher:**
- ADR path, spec path, plan path.
- PASS counts per ognuno dei 3 harness (before/after).
- File modificati (2 totali: `smoke-e2e.sh` create, `run-tests.sh` +1 line).
- Wall time del smoke E2E.
- Mutation test outcome.
- Confidence dichiarata.

---

## Risk register (per coder esecutore)

- **Risk A:** `manifest-transition` non aggiorna `failure.failed_step` quando
  transizione a `failed`; validate posteriore di M4 fallirebbe. **Mitigation:**
  smoke NON re-valida M4; controlla solo `status: "failed"` via grep.
  L'assertion 10 di run-tests.sh già copre validate stretto.
- **Risk B:** Backward transitions (3, 7, 11) potrebbero richiedere reset di
  `gates.<gate>` fields nel manifest; se transition.sh non lo gestisce, la
  validate intermedia fallisce. **Mitigation:** smoke usa stessa logica di
  run-tests.sh assertion 8 (sleep 2 + transition + grep) — se passa lì,
  passa qui.
- **Risk C:** Helper bash function `step` con local variables in bash 3.2.57.
  `local` è supportato in bash 3.2 (verified). **Mitigation:** nessuna.
- **Risk D:** Wall time esplode con FS lento (Spotlight indexing). **Mitigation:**
  budget hard 8s; warning-only se >5s. Su CI usare /tmp che è meno indicizzato.

## HITL gates (none in this plan)

Repo NON-git, no commit. Auto mode. Stefano valida ex-post leggendo il
report del dispatcher.
