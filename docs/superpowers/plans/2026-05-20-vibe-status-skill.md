# Vibe-status skill — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Changelog:**
- v1.0 (2026-05-20): initial — TDD plan derivato da `ADR-0005-vibe-status-skill.md` e dallo spec `2026-05-20-vibe-status-skill-design.md`. 8 task: 1 red harness, 3 green (SKILL.md + aggregate.sh + harness-runner.sh + render), 1 dedicated harness, 1 documental sync (ADR/spec status), 2 deliverable doc + memory + MEMORY.md.

**Goal:** introdurre skill markdown `~/.claude/skills/vibe-status/` invocabile come `/skill vibe-status` che aggrega in singolo report Markdown su stdout lo stato del sistema vibe-coding: harness PASS/FAIL (parallel execution, timeout 8s per-harness), ADR del project cwd con status, manifest in flight, skill custom installati, hook configurati in settings.json, recente ciclo review-triage-fix, head memory. Overall health: HEALTHY | DEGRADED | CRITICAL. Read-only, <10s typical, fail-graceful per ogni section.

**Architecture:** new skill dir `~/.claude/skills/vibe-status/` con `SKILL.md` (~80 righe) + `scripts/aggregate.sh` (~200 righe) + `scripts/harness-runner.sh` (~30 righe) + `tests/run-tests.sh` (~100 righe, target PASS=9). 1 anchor structural in `~/.claude/skills/review-triage-fix/tests/run-tests.sh` (verifica esistenza vibe-status SKILL.md). Harness review-triage-fix PASS=47 → PASS=48 (additivo). Read-only by construction (no file write, solo stdout). Auto-discovery per harness via glob `~/.claude/skills/*/tests/run-tests.sh`. Cwd-aware: globale + locale (ADR/manifest/triage dipendono da cwd).

**Tech Stack:** bash 3.2.57 (script + harness; pattern timeout da `stop-gate.sh` linee 77-88, parallel parallelism via `&` subshell + `wait`), jq (parse settings.json + triage state JSON), grep/awk/sed/head/tail (3.2-portable), markdown (SKILL.md, plan/spec/ADR/memory).

**Spec:** `docs/superpowers/specs/2026-05-20-vibe-status-skill-design.md` (approvato 2026-05-20).
**ADR:** `docs/architecture/ADR-0005-vibe-status-skill.md` (Proposed 2026-05-20).

---

## Environment notes (read first)

- **No git in `~/.claude/` né in questo repo doc.** Checkpoint per task = harness verde + TodoWrite update. Nessun commit. Skill è additive, read-only, inert finché Stefano la invoca esplicitamente. Nessun HITL gate complesso.
- **Bash 3.2 cleanliness.** Tutti gli script usano subset 3.2-clean: `[ -f "$X" ]`, `for f in glob; do ... done`, `while read -r L; do ... done < file`, `&` background + `wait`, `mktemp -d`, jq, grep/awk/head/tail/sed. No assoc array, no `mapfile`, no `${v^^}`, no process substitution `<()`.
- **Read-only HARD.** Nessuno script modifica file di sistema. Output solo a stdout. Eventuale tmpdir (mktemp -d) viene cleanup-ato a fine esecuzione. Nessun `.cache/` o stato persistente in v1.0.
- **Anchor preservation.** I 47 anchor di review-triage-fix restano intatti. Nuovo anchor (Task 1) inserito post-Task-7 ADR-0004 (se entrambi deployati) o post-Task-6 ADR-0001 (se ADR-0004 non yet). Plan assume ADR-0004 NON ancora deployato → anchor inserito post-Task-6, baseline PASS=47. Se ADR-0004 viene mergiato prima, baseline diventa PASS=48 e nuovo target PASS=49 (rebase del numero, no semantic change).
- **Performance budget.** <10s typical case (3 harness in parallel × 2-3s + metadata <2s). Worst-case 10s (1 harness near 8s timeout).
- **Discovery convention.** `~/.claude/skills/*/tests/run-tests.sh` glob 3.2-portable. Order: alphabetical (default `*` expansion). Output table ordering preservato.
- **Lingua.** SKILL.md in inglese (system contract), script comment in inglese, output Markdown in inglese (header/table/legend), reason field eventuali in italiano. Spec/plan/ADR/memory in italiano (utente Stefano).

## File structure

Tutti i path live (`~/.claude/skills/vibe-status/`, `~/.claude/skills/review-triage-fix/tests/`); deliverable doc nel repo `vibe-coding-system`; memory in `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/`.

- Create `~/.claude/skills/vibe-status/SKILL.md` — orchestrator markdown ~80 righe (inglese).
- Create `~/.claude/skills/vibe-status/scripts/aggregate.sh` — main entry ~200 righe bash 3.2.
- Create `~/.claude/skills/vibe-status/scripts/harness-runner.sh` — single harness invoker con timeout ~30 righe.
- Create `~/.claude/skills/vibe-status/tests/run-tests.sh` — dedicated harness ~100 righe target PASS=9.
- Modify `~/.claude/skills/review-triage-fix/tests/run-tests.sh` — insert nuovo blocco `# --- Task 8: vibe-status skill ---` (1 anchor) pre-summary.
- Modify `docs/architecture/ADR-0005-vibe-status-skill.md` — status line da Proposed a Accepted.
- Modify `docs/superpowers/specs/2026-05-20-vibe-status-skill-design.md` — status line da "approvato" a "implementato".
- Create `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/project_vibe-status-skill.md` — nuovo project memory entry.
- Modify `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/MEMORY.md` — append riga nuova in sezione `## Project`.

Unchanged (vincoli HARD): tutti gli agent (`coder.md`, `reviewer.md`, etc.), altri hook, altre skill (`concept-to-code`, `refactor-snapshot`, `review-triage-fix/SKILL.md`), `vibe-coding-system.md`.

---

### Task 1: Harness anchor failing (red)

**Files:**
- Modify: `~/.claude/skills/review-triage-fix/tests/run-tests.sh` (insert blocco Task 8 pre-summary)

**Red phase:** baseline harness `PASS=47 FAIL=0` (verificato pre-implementation). Nuovo blocco cerca literal `Vibe-Coding System Status` in `~/.claude/skills/vibe-status/SKILL.md` — file non esiste yet. Aspettativa: 1 nuovo `FAIL`, cumulative `PASS=47 FAIL=1`, exit 1.

**Green phase (edit concreto):** localizza l'ultima riga del blocco esistente (anchor pre-existing) e la summary line. Inserisci tra le due (riga vuota di separazione) il blocco:

```bash

# --- Task 8: vibe-status skill ---
V="$HOME/.claude/skills/vibe-status/SKILL.md"
grep -q -- 'Vibe-Coding System Status' "$V" 2>/dev/null && ok "vibe-status: SKILL.md present" || bad "vibe-status: SKILL.md missing"

```

Notes:
- 1 anchor totale. Bash 3.2-clean: `grep -q --` + `&&`/`||` + helpers.
- Match string `Vibe-Coding System Status` è il literal del title del report Markdown (Task 2-3 lo introducono nel SKILL.md descrizione).
- Cumulative TARGET = `PASS=48 FAIL=0` post-Task-2 (SKILL.md creato).

- [ ] **Step 1: Write the failing test** — edit `~/.claude/skills/review-triage-fix/tests/run-tests.sh` per inserire il blocco Task 8.

- [ ] **Step 2: Run test to verify it fails**

Verify command:
```bash
bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh; echo "exit=$?"
```
Expected: 47 anchor esistenti `PASS`; nuovo anchor `vibe-status: SKILL.md missing` `FAIL`; summary `PASS=47 FAIL=1`, exit 1.

- [ ] **Step 3: Checkpoint** — failing test in place. TodoWrite update.

**Stima tempo:** 4 min.

---

### Task 2: SKILL.md (green primary — anchor)

**Files:**
- Create: `~/.claude/skills/vibe-status/SKILL.md` (~80 righe markdown)
- Create: `~/.claude/skills/vibe-status/scripts/` (directory, mkdir -p)
- Create: `~/.claude/skills/vibe-status/tests/` (directory, mkdir -p)

**Red phase:** harness `PASS=47 FAIL=1` post-Task-1. Anchor `vibe-status: SKILL.md missing` fail.

**Green phase (edit concreto):** create il SKILL.md con questo body (inglese, frontmatter + content):

```markdown
---
name: vibe-status
description: Aggregate health report of the vibe-coding system. Runs harness in parallel, lists ADRs, manifests, skills, hooks, memory. Read-only, <10s typical. Title in report: Vibe-Coding System Status.
---

# vibe-status

Single command to render the full health status of the vibe-coding system. Read-only,
<10s typical, fail-graceful per section.

## When to invoke

- Before a complex multi-agent dispatch — verify system is HEALTHY.
- After deploy of a new skill/hook/agent — confirm harness regression is clean.
- Periodic check — discover skills/hooks added recently.

## Process

1. Run `bash ~/.claude/skills/vibe-status/scripts/aggregate.sh [--json|--plain|--skip-harness]`.
2. Default output is Markdown to stdout. The orchestrator/LLM can render directly in chat.
3. Interpret overall status header: HEALTHY (all green) | DEGRADED (1+ issue) | CRITICAL (2+ harness fails or all harness errors).

## Flags

- `--json` — emit JSON for programmatic consumption (future skill chaining).
- `--plain` — plain text output (no Markdown tables).
- `--skip-harness` — metadata-only, <1s (no harness execution).

## Discovery

Globale (always):
- Harness: `~/.claude/skills/*/tests/run-tests.sh`
- Skills: `~/.claude/skills/*/`
- Agents: `~/.claude/agents/*.md`
- Hooks: parsed from `~/.claude/settings.json`

Locale (cwd-relative, conditional on existence):
- ADR: `$PWD/docs/architecture/ADR-*.md`
- Manifests: `$PWD/docs/manifests/*.yaml`
- Triage state: `$PWD/.triage-fix-last.json`
- Memory head: `~/.claude/projects/<encoded-cwd>/memory/MEMORY.md`

## Defaults

- Per-harness timeout: 8s (env `VIBE_STATUS_HARNESS_TIMEOUT`).
- Window: cwd-aware. Degrades gracefully on missing dirs/files.

## Title

The report header is: `# Vibe-Coding System Status — <ISO-timestamp>`.

## Output sample

See `~/.claude/skills/vibe-status/tests/run-tests.sh` for fixtures and expected output
shape.

## Reference

- ADR: `docs/architecture/ADR-0005-vibe-status-skill.md`
- Spec: `docs/superpowers/specs/2026-05-20-vibe-status-skill-design.md`
- Plan: `docs/superpowers/plans/2026-05-20-vibe-status-skill.md`
```

Create directory structure: `mkdir -p ~/.claude/skills/vibe-status/scripts ~/.claude/skills/vibe-status/tests`.

Notes:
- SKILL.md in inglese (system contract).
- Frontmatter `name:` and `description:` standard (matches `concept-to-code`, `refactor-snapshot`).
- Literal `Vibe-Coding System Status` presente sia in description (frontmatter) sia in body (sezione Title) → match anchor Task 1.

- [ ] **Step 1: Create directory structure**

Verify command:
```bash
mkdir -p ~/.claude/skills/vibe-status/scripts ~/.claude/skills/vibe-status/tests && ls -d ~/.claude/skills/vibe-status/{scripts,tests}
```

- [ ] **Step 2: Write the SKILL.md** — `Write` di `~/.claude/skills/vibe-status/SKILL.md` con il content sopra.

- [ ] **Step 3: Harness re-run — anchor green**

Verify command:
```bash
bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh; echo "exit=$?"
```
Expected: 47 esistenti + nuovo anchor `vibe-status: SKILL.md present` tutti PASS; summary `PASS=48 FAIL=0`, exit 0. **TARGET RAGGIUNTO review-triage-fix PASS=48.**

- [ ] **Step 4: Checkpoint** — SKILL.md present, harness verde. TodoWrite update.

**Stima tempo:** 10 min.

---

### Task 3: harness-runner.sh helper (green)

**Files:**
- Create: `~/.claude/skills/vibe-status/scripts/harness-runner.sh` (~30 righe, executable)

**Red phase:** file non esiste.

**Green phase (edit concreto):** create lo script con pattern timeout da `stop-gate.sh` linee 77-88:

```bash
#!/bin/bash
# harness-runner: invoca un single harness con timeout, emette "RC=<rc> DUR=<sec>s\n<output>".
# 3.2-clean, fail-graceful.
H="$1"; TMO="${2:-8}"
[ -z "$H" ] && { echo "RC=127 DUR=0s"; echo "ERROR: no harness arg"; exit 0; }
[ ! -f "$H" ] && { echo "RC=127 DUR=0s"; echo "ERROR: harness file not found: $H"; exit 0; }

START=$(date +%s)
OUT=$(mktemp)
if command -v timeout >/dev/null 2>&1; then
  timeout "$TMO" bash "$H" >"$OUT" 2>&1
  RC=$?
elif command -v gtimeout >/dev/null 2>&1; then
  gtimeout "$TMO" bash "$H" >"$OUT" 2>&1
  RC=$?
else
  bash "$H" >"$OUT" 2>&1 &
  P=$!
  ( sleep "$TMO"; kill -0 "$P" 2>/dev/null && kill -9 "$P" 2>/dev/null ) &
  W=$!
  wait "$P" 2>/dev/null; RC=$?
  kill -9 "$W" 2>/dev/null; wait "$W" 2>/dev/null
  [ "$RC" -eq 137 ] && RC=124
fi
END=$(date +%s)
DUR=$((END - START))
echo "RC=$RC DUR=${DUR}s"
cat "$OUT"
rm -f "$OUT"
exit 0
```

Make executable.

Notes:
- Pattern identico a `stop-gate.sh` per timeout robusto cross-platform (macOS no `timeout` di default; spesso `gtimeout` da coreutils; fallback subshell+kill).
- Output strutturato: prima riga `RC=N DUR=Xs`, resto è stdout/stderr del harness. Parsable da aggregate.sh.
- RC=124 = timeout (convenzione). RC=127 = file not found.
- 3.2-clean.

- [ ] **Step 1: Write the helper** — `Write` di `~/.claude/skills/vibe-status/scripts/harness-runner.sh`.

- [ ] **Step 2: Make executable**

Verify command:
```bash
chmod +x ~/.claude/skills/vibe-status/scripts/harness-runner.sh && ls -l ~/.claude/skills/vibe-status/scripts/harness-runner.sh
```

- [ ] **Step 3: Smoke test inline**

Verify command:
```bash
bash ~/.claude/skills/vibe-status/scripts/harness-runner.sh ~/.claude/skills/review-triage-fix/tests/run-tests.sh 8 | head -3
```
Expected: prima riga `RC=0 DUR=Xs` (X = duration sec), seconde+ righe output del harness.

- [ ] **Step 4: Checkpoint** — helper live e funzionante. TodoWrite update.

**Stima tempo:** 10 min.

---

### Task 4: aggregate.sh main (green primary)

**Files:**
- Create: `~/.claude/skills/vibe-status/scripts/aggregate.sh` (~200 righe, executable)

**Red phase:** file non esiste.

**Green phase (edit concreto):** create lo script con sezioni in ordine. Outline strutturale (non riga-per-riga; il coder deve implementare seguendo logica spec §3.3):

```bash
#!/bin/bash
# vibe-status aggregate v1.0 — read-only, parallel harness, fail-graceful per section.
# Output: Markdown to stdout (default), JSON (--json), plain (--plain).
# Performance budget: <10s typical, 8s per-harness timeout.

set -u  # NOTA: NO `set -e` — fail-graceful per section richiede continuazione.

# --- Args parsing ---
FORMAT="markdown"
SKIP_HARNESS=0
for arg in "$@"; do
  case "$arg" in
    --json) FORMAT="json" ;;
    --plain) FORMAT="plain" ;;
    --skip-harness) SKIP_HARNESS=1 ;;
  esac
done

TMO="${VIBE_STATUS_HARNESS_TIMEOUT:-8}"
TS=$(date "+%Y-%m-%d %H:%M")
START=$(date +%s)
TMP=$(mktemp -d)
RUNNER="$HOME/.claude/skills/vibe-status/scripts/harness-runner.sh"

# --- Section 1: Harness discovery + parallel exec ---
HARNESS_OK=0; HARNESS_FAIL=0; HARNESS_ERR=0; HARNESS_TOTAL=0
HARNESS_LINES=""
if [ "$SKIP_HARNESS" -eq 0 ]; then
  for h in "$HOME"/.claude/skills/*/tests/run-tests.sh; do
    [ -f "$h" ] || continue
    HARNESS_TOTAL=$((HARNESS_TOTAL + 1))
    name=$(basename "$(dirname "$(dirname "$h")")")
    ( bash "$RUNNER" "$h" "$TMO" >"$TMP/$name.out" 2>&1 ) &
  done
  wait

  for f in "$TMP"/*.out; do
    [ -f "$f" ] || continue
    name=$(basename "$f" .out)
    head1=$(head -n 1 "$f")
    rc=$(echo "$head1" | sed -E 's/^RC=([0-9]+) .*/\1/')
    dur=$(echo "$head1" | sed -E 's/.* DUR=([0-9]+)s/\1/')
    pass=$(grep -E '^PASS=[0-9]+' "$f" | head -n 1 | sed -E 's/.*PASS=([0-9]+).*/\1/')
    fail=$(grep -E 'FAIL=[0-9]+' "$f" | head -n 1 | sed -E 's/.*FAIL=([0-9]+).*/\1/')
    pass="${pass:-?}"; fail="${fail:-?}"; dur="${dur:-?}"; rc="${rc:-127}"
    if [ "$rc" = "124" ]; then
      status="TIMEOUT"; HARNESS_ERR=$((HARNESS_ERR + 1))
    elif [ "$rc" = "0" ]; then
      status="OK"; HARNESS_OK=$((HARNESS_OK + 1))
    elif [ "$rc" = "1" ]; then
      status="FAIL"; HARNESS_FAIL=$((HARNESS_FAIL + 1))
    else
      status="ERROR"; HARNESS_ERR=$((HARNESS_ERR + 1))
    fi
    HARNESS_LINES="$HARNESS_LINES| $name | $pass | $fail | ${dur}s | $status |
"
  done
fi

# --- Section 2: ADR scan (cwd-local) ---
ADR_LINES=""
ADR_COUNT=0
ADR_DIR="$PWD/docs/architecture"
if [ -d "$ADR_DIR" ]; then
  for adr in "$ADR_DIR"/ADR-*.md; do
    [ -f "$adr" ] || continue
    ADR_COUNT=$((ADR_COUNT + 1))
    title=$(head -n 1 "$adr" | sed -E 's/^# //')
    status=$(grep -m1 '^\*\*Status:\*\*' "$adr" | sed -E 's/^\*\*Status:\*\* *//')
    ADR_LINES="$ADR_LINES- $title — $status
"
  done
fi

# --- Section 3: Manifests (cwd-local) ---
MANIFEST_COUNT=0
MANIFEST_LINES=""
MANIFEST_DIR="$PWD/docs/manifests"
if [ -d "$MANIFEST_DIR" ]; then
  for m in "$MANIFEST_DIR"/*.yaml; do
    [ -f "$m" ] || continue
    MANIFEST_COUNT=$((MANIFEST_COUNT + 1))
    MANIFEST_LINES="$MANIFEST_LINES- $(basename "$m")
"
  done
fi

# --- Section 4: Triage state (cwd-local) ---
TRIAGE_LINE="(no recent triage cycle)"
TF="$PWD/.triage-fix-last.json"
if [ -f "$TF" ]; then
  if command -v jq >/dev/null 2>&1; then
    ts=$(jq -r '.timestamp // "?"' "$TF" 2>/dev/null)
    skill=$(jq -r '.skill // "?"' "$TF" 2>/dev/null)
    result=$(jq -r '.result // "?"' "$TF" 2>/dev/null)
    TRIAGE_LINE="$ts — $skill — $result"
  else
    TRIAGE_LINE="(jq missing — cannot parse)"
  fi
fi

# --- Section 5: Skills custom (globale) ---
SKILL_COUNT=0
SKILL_NAMES=""
for s in "$HOME"/.claude/skills/*/; do
  [ -d "$s" ] || continue
  SKILL_COUNT=$((SKILL_COUNT + 1))
  n=$(basename "$s")
  SKILL_NAMES="$SKILL_NAMES$n, "
done

# --- Section 6: Hooks (parse settings.json) ---
HOOK_LINES="(unable to parse settings.json)"
S_JSON="$HOME/.claude/settings.json"
if [ -f "$S_JSON" ] && command -v jq >/dev/null 2>&1; then
  HOOK_LINES=$(jq -r '.hooks // {} | to_entries[] | "- \(.key): \(.value | length) entries"' "$S_JSON" 2>/dev/null)
  [ -z "$HOOK_LINES" ] && HOOK_LINES="(no hooks configured)"
fi

# --- Section 7: Memory head ---
MEM_LINE="(no memory file)"
ENC=$(printf '%s' "$PWD" | tr '/' '-')
MEM_FILE="$HOME/.claude/projects/$ENC/memory/MEMORY.md"
if [ -f "$MEM_FILE" ]; then
  pcount=$(grep -c '^- \[' "$MEM_FILE" 2>/dev/null || echo 0)
  MEM_LINE="$pcount entries indexed in MEMORY.md"
fi

# --- Section 8: Overall status calc ---
META_ERROR=0
[ ! -d "$ADR_DIR" ] && [ "$PWD" != "$HOME" ] && META_ERROR=0  # non penalize: solo se project context atteso
[ ! -f "$S_JSON" ] && META_ERROR=1

if [ "$SKIP_HARNESS" -eq 0 ]; then
  if [ "$HARNESS_OK" -eq "$HARNESS_TOTAL" ] && [ "$META_ERROR" -eq 0 ]; then
    HEALTH="HEALTHY"
  elif [ "$HARNESS_FAIL" -ge 2 ] || { [ "$HARNESS_ERR" -eq "$HARNESS_TOTAL" ] && [ "$HARNESS_TOTAL" -gt 0 ]; }; then
    HEALTH="CRITICAL"
  else
    HEALTH="DEGRADED"
  fi
else
  HEALTH="UNKNOWN (skip-harness)"
fi

END=$(date +%s)
ELAPSED=$((END - START))

# --- Render ---
case "$FORMAT" in
  json)
    # Minimal JSON output
    printf '{"timestamp":"%s","health":"%s","harness":{"ok":%d,"fail":%d,"err":%d,"total":%d},"adr":%d,"manifests":%d,"skills":%d,"elapsed":%d}\n' \
      "$TS" "$HEALTH" "$HARNESS_OK" "$HARNESS_FAIL" "$HARNESS_ERR" "$HARNESS_TOTAL" \
      "$ADR_COUNT" "$MANIFEST_COUNT" "$SKILL_COUNT" "$ELAPSED"
    ;;
  *)
    cat <<EOF
# Vibe-Coding System Status — $TS

## Health: $HEALTH

## Harness ($HARNESS_OK/$HARNESS_TOTAL passing)
| Skill | PASS | FAIL | Duration | Status |
|---|---|---|---|---|
$HARNESS_LINES

## ADR ($ADR_COUNT total in docs/architecture/)
${ADR_LINES:-(no project ADR directory)}

## In-flight manifests
${MANIFEST_LINES:-(none)}

## Recent triage cycle
$TRIAGE_LINE

## Skill custom ($SKILL_COUNT installed)
${SKILL_NAMES%, }

## Hooks (settings.json)
$HOOK_LINES

## Memory
$MEM_LINE

---
Legend: HEALTHY = all harness pass + no metadata error.
        DEGRADED = >=1 harness FAIL/TIMEOUT/ERROR or metadata parse error.
        CRITICAL = >=2 harness FAIL or all harness ERROR.
Generated in ${ELAPSED}s.
EOF
    ;;
esac

rm -rf "$TMP"
exit 0
```

Make executable.

Notes:
- Bash 3.2-clean (no assoc array, no mapfile, no `${v^^}`, no `<()`).
- Parallel harness execution: `for h in glob; do ... & done; wait`. Subshell isolation, no race.
- Output Markdown well-formed: table header + body + sections + footer.
- Fail-graceful per section: empty `HARNESS_LINES` → table vuota (UX da rifinire in v1.1 con "(no harness)"); `(none)` fallback per liste vuote.
- JSON mode: minimal `{}` output, enough per parsing programmatico. Estendibile v1.1.
- Performance: 3 harness × 2s parallel + metadata <2s = ~4s typical, sotto budget.

- [ ] **Step 1: Write the aggregate.sh** — `Write` di `~/.claude/skills/vibe-status/scripts/aggregate.sh`.

- [ ] **Step 2: Make executable**

Verify command:
```bash
chmod +x ~/.claude/skills/vibe-status/scripts/aggregate.sh && ls -l ~/.claude/skills/vibe-status/scripts/aggregate.sh
```

- [ ] **Step 3: Smoke test live**

Verify command:
```bash
cd /Users/stefanoferri/Developer/vibe-coding-system && bash ~/.claude/skills/vibe-status/scripts/aggregate.sh | head -20
```
Expected: output Markdown well-formed; prima riga `# Vibe-Coding System Status — <timestamp>`; sezione `## Health: HEALTHY` o `DEGRADED` (dipende stato live harness); sezione `## Harness` con tabella.

- [ ] **Step 4: Smoke test --skip-harness**

Verify command:
```bash
time bash ~/.claude/skills/vibe-status/scripts/aggregate.sh --skip-harness | head -10
```
Expected: output sotto 1s, tabella harness vuota o con placeholder.

- [ ] **Step 5: Smoke test --json**

Verify command:
```bash
bash ~/.claude/skills/vibe-status/scripts/aggregate.sh --json | jq .
```
Expected: JSON parsabile; campi `timestamp`, `health`, `harness.ok`, `adr`, etc.

- [ ] **Step 6: Verify performance (<10s)**

Verify command:
```bash
time bash ~/.claude/skills/vibe-status/scripts/aggregate.sh >/dev/null
```
Expected: real time ≤10s. Tipico 3-5s con 3 harness paralleli.

- [ ] **Step 7: Checkpoint** — aggregate.sh live, smoke pass, performance ok. TodoWrite update.

**Stima tempo:** 40 min.

---

### Task 5: Dedicated harness (green)

**Files:**
- Create: `~/.claude/skills/vibe-status/tests/run-tests.sh` (~100 righe, executable)

**Red phase:** harness non esiste.

**Green phase (edit concreto):** create il harness con 9 test cases (vedi spec §3.7):

```bash
#!/bin/bash
# Harness dedicato per vibe-status — target PASS=9.
PASS=0; FAIL=0
ok() { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
TMP=$(mktemp -d)
SKILL="$HOME/.claude/skills/vibe-status"
AGG="$SKILL/scripts/aggregate.sh"
RUNNER="$SKILL/scripts/harness-runner.sh"

# Test 1: SKILL.md exists + has name field
[ -f "$SKILL/SKILL.md" ] && grep -q '^name: vibe-status' "$SKILL/SKILL.md" \
  && ok "1: SKILL.md exists + name field" \
  || bad "1: SKILL.md / name field"

# Test 2: aggregate.sh exists + executable
[ -x "$AGG" ] && ok "2: aggregate.sh executable" || bad "2: aggregate.sh not executable"

# Test 3: harness-runner.sh exists + executable
[ -x "$RUNNER" ] && ok "3: harness-runner.sh executable" || bad "3: harness-runner.sh not executable"

# Test 4: Smoke test — aggregate.sh produces well-formed Markdown
bash "$AGG" --skip-harness >"$TMP/o4" 2>&1
if head -n 1 "$TMP/o4" | grep -q '^# Vibe-Coding System Status' \
   && grep -q '^## Health:' "$TMP/o4"; then
  ok "4: smoke Markdown well-formed"
else
  bad "4: smoke Markdown (head=$(head -n 1 $TMP/o4))"
fi

# Test 5: --skip-harness mode
START5=$(date +%s)
bash "$AGG" --skip-harness >/dev/null 2>&1
END5=$(date +%s)
DUR5=$((END5 - START5))
if [ "$DUR5" -le 2 ]; then ok "5: --skip-harness <=2s (was ${DUR5}s)"
else bad "5: --skip-harness too slow (${DUR5}s)"; fi

# Test 6: --json flag produces valid JSON
bash "$AGG" --json --skip-harness >"$TMP/o6" 2>&1
if command -v jq >/dev/null 2>&1; then
  jq -e '.health' "$TMP/o6" >/dev/null 2>&1 && ok "6: --json parsable + has .health" \
    || bad "6: --json invalid (out=$(cat $TMP/o6))"
else
  ok "6: --json (skipped: no jq)"
fi

# Test 7: Harness timeout — simulate slow harness, expect TIMEOUT in output
mkdir -p "$TMP/fakeskill/tests"
cat >"$TMP/fakeskill/tests/run-tests.sh" <<'EOF'
#!/bin/bash
sleep 30
echo "PASS=1 FAIL=0"
EOF
chmod +x "$TMP/fakeskill/tests/run-tests.sh"
# Use harness-runner with 2s timeout
bash "$RUNNER" "$TMP/fakeskill/tests/run-tests.sh" 2 >"$TMP/o7" 2>&1
head1=$(head -n 1 "$TMP/o7")
echo "$head1" | grep -q 'RC=124' && ok "7: timeout RC=124 captured" \
  || bad "7: timeout (head=$head1)"

# Test 8: Missing ADR directory degrades gracefully
TMP_CWD="$TMP/nocwd"
mkdir -p "$TMP_CWD"
( cd "$TMP_CWD" && bash "$AGG" --skip-harness >"$TMP/o8" 2>&1 )
grep -q 'no project ADR directory\|## ADR (0 total' "$TMP/o8" && ok "8: missing ADR dir graceful" \
  || bad "8: missing ADR (out=$(grep -A1 '## ADR' $TMP/o8 | head -2))"

# Test 9: Malformed settings.json degrades gracefully — usa fake HOME
TMP_HOME="$TMP/fakehome"
mkdir -p "$TMP_HOME/.claude/skills"
echo "not-json" >"$TMP_HOME/.claude/settings.json"
HOME="$TMP_HOME" bash "$AGG" --skip-harness >"$TMP/o9" 2>&1
grep -q 'unable to parse settings.json\|no hooks configured' "$TMP/o9" && ok "9: malformed settings graceful" \
  || bad "9: malformed settings (out=$(grep -A1 '## Hooks' $TMP/o9 | head -2))"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
rm -rf "$TMP"
[ "$FAIL" -gt 0 ] && exit 1 || exit 0
```

Make executable.

Notes:
- 9 anchor test deterministici. Bash 3.2-clean.
- Test 7 (timeout) usa 2s timeout per fast harness execution; comportamento corretto = RC=124.
- Test 9 usa `HOME=$TMP_HOME` per isolare il malformed settings senza toccare quello vero.
- Cleanup tmpdir automatic.

- [ ] **Step 1: Write the harness** — `Write` di `~/.claude/skills/vibe-status/tests/run-tests.sh`.

- [ ] **Step 2: Make executable**

Verify command:
```bash
chmod +x ~/.claude/skills/vibe-status/tests/run-tests.sh
```

- [ ] **Step 3: Run harness full green**

Verify command:
```bash
bash ~/.claude/skills/vibe-status/tests/run-tests.sh; echo "exit=$?"
```
Expected: `PASS=9 FAIL=0`, exit 0. Se 1+ FAIL: debug case-by-case.

- [ ] **Step 4: Re-run review-triage-fix harness (no regression)**

Verify command:
```bash
bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh; echo "exit=$?"
```
Expected: `PASS=48 FAIL=0`, exit 0.

- [ ] **Step 5: Checkpoint** — dedicated harness verde end-to-end. TodoWrite update.

**Stima tempo:** 30 min.

---

### Task 6: ADR + spec status sync

**Files:**
- Modify: `docs/architecture/ADR-0005-vibe-status-skill.md` (status line)
- Modify: `docs/superpowers/specs/2026-05-20-vibe-status-skill-design.md` (status line)

**Red phase:** ADR `**Status:** Proposed — 2026-05-20`. Spec `**Stato:** approvato (post-ADR) — pronto per writing-plans`.

**Green phase:**

1. ADR riga 3:
   - Da: `**Status:** Proposed — 2026-05-20`
   - A: `**Status:** Accepted — 2026-05-20 (implemented via plan 2026-05-20-vibe-status-skill.md; harness review-triage-fix PASS=48; dedicated PASS=9)`

2. Spec riga 3:
   - Da: `**Stato:** approvato (post-ADR) — pronto per writing-plans`
   - A: `**Stato:** implementato — 2026-05-20 (harness PASS=48 + dedicated PASS=9; adozione organica da osservare)`

- [ ] **Step 1: Edit ADR status line.**
- [ ] **Step 2: Edit spec status line.**
- [ ] **Step 3: Verify both updated**

Verify command:
```bash
grep '^\*\*Status:\*\*' /Users/stefanoferri/Developer/vibe-coding-system/docs/architecture/ADR-0005-vibe-status-skill.md && grep '^\*\*Stato:\*\*' /Users/stefanoferri/Developer/vibe-coding-system/docs/superpowers/specs/2026-05-20-vibe-status-skill-design.md
```

- [ ] **Step 4: Checkpoint** — deliverable doc allineati. TodoWrite update.

**Stima tempo:** 3 min.

---

### Task 7: Memory entry — new project file

**Files:**
- Create: `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/project_vibe-status-skill.md`

**Red phase:** file non esiste.

**Green phase (edit concreto):** create memory file con body:

```markdown
# Vibe-status skill

**Stato:** DEPLOYED LIVE 2026-05-20 in `~/.claude/skills/vibe-status/` (SKILL.md + scripts/aggregate.sh + scripts/harness-runner.sh + tests/run-tests.sh PASS=9). +1 anchor in `review-triage-fix/tests/run-tests.sh` (PASS=48).

**Cosa:** skill markdown invocabile come `/skill vibe-status` che aggrega in singolo report Markdown (stdout) lo stato del sistema vibe-coding: harness PASS/FAIL parallel (timeout 8s per-harness via stop-gate pattern), ADR del project cwd con status, manifest in-flight, skill custom installati globalmente, hook configurati in settings.json, recente ciclo review-triage-fix, head memory. Overall health: HEALTHY | DEGRADED | CRITICAL.

**Flags:**
- default: Markdown
- `--json`: JSON minimal per programmatic chaining future
- `--plain`: plain text
- `--skip-harness`: metadata-only, <1s

**Read-only HARD.** Skill NON modifica nessun file di sistema. Output esclusivamente stdout. Tmpdir auto-cleanup.

**Discovery convention:**
- Globale (always): `~/.claude/skills/*/tests/run-tests.sh`, `~/.claude/skills/*/`, `~/.claude/agents/*.md`, `~/.claude/settings.json`.
- Locale (conditional): `$PWD/docs/architecture/ADR-*.md`, `$PWD/docs/manifests/*.yaml`, `$PWD/.triage-fix-last.json`, `~/.claude/projects/<enc-cwd>/memory/MEMORY.md`.

**Performance:** typical 3-5s con 3 harness paralleli. Worst-case ~10s (1 harness near 8s timeout). Misurato in Task 4 Step 6.

**Failure mode:**
- 1 harness timeout/crash → row TIMEOUT/ERROR, altri harness completi.
- settings.json malformato → section hook degrada a "(unable to parse)".
- Missing ADR dir → section ADR `(no project ADR directory)`.
- Overall status: HEALTHY (all green) | DEGRADED (>=1 issue) | CRITICAL (>=2 harness fail o tutti ERROR).

**Deliverable:**
- ADR: `docs/architecture/ADR-0005-vibe-status-skill.md` (Accepted 2026-05-20).
- Spec: `docs/superpowers/specs/2026-05-20-vibe-status-skill-design.md` (implementato 2026-05-20).
- Plan: `docs/superpowers/plans/2026-05-20-vibe-status-skill.md` (TDD 8 task, v1.0).

**Validazione pending:**
- Adozione real: Stefano userà `/skill vibe-status` regolarmente?
- Performance p95 con 5+ harness e session lunghi?
- Markdown rendering in chat human-readable o serve `--plain`?

**Subsume / supersede:** none. Skill puramente additive, read-only.

**Invariante HARD:**
- Anchor preservation: PASS≥48 in ogni futuro change. Mai scendere sotto 47.
- Read-only: skill MAI scrive file di sistema.
- Bash 3.2-clean (no assoc, no mapfile, no `${v^^}`, no `<()`).
- Performance: <10s typical case sempre rispettato.
```

- [ ] **Step 1: Create the memory file** — `Write` del file.

- [ ] **Step 2: Verify creation**

Verify command:
```bash
test -f ~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/project_vibe-status-skill.md && head -3 ~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/project_vibe-status-skill.md
```

- [ ] **Step 3: Checkpoint** — memory entry creato. TodoWrite update.

**Stima tempo:** 5 min.

---

### Task 8: MEMORY.md index update + final harness sync

**Files:**
- Modify: `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/MEMORY.md` (append nuova riga in `## Project`)

**Red phase:** `grep -c 'vibe-status-skill' MEMORY.md` returns `0`.

**Green phase:** append nuova riga:

```markdown
- [Vibe-status skill](project_vibe-status-skill.md) — **DEPLOYED 2026-05-20**: skill aggregator `/skill vibe-status` per health report sistema (harness paralleli, ADR/manifest/skill/hook/memory); read-only, <10s typical; harness review-triage-fix PASS=48 + dedicated PASS=9
```

- [ ] **Step 1: Append the new row.**

- [ ] **Step 2: Verify update**

Verify command:
```bash
grep -c 'vibe-status-skill' ~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/MEMORY.md
```
Expected: `1`.

- [ ] **Step 3: Final cross-harness end-to-end sanity**

Verify command:
```bash
bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh && bash ~/.claude/skills/vibe-status/tests/run-tests.sh; echo "exit=$?"
```
Expected: review-triage-fix `PASS=48 FAIL=0`, dedicated `PASS=9 FAIL=0`, exit 0.

- [ ] **Step 4: Final live smoke**

Verify command:
```bash
cd /Users/stefanoferri/Developer/vibe-coding-system && time bash ~/.claude/skills/vibe-status/scripts/aggregate.sh
```
Expected: Markdown report well-formed, real time <10s, overall Health HEALTHY (assumendo tutti gli harness verdi).

- [ ] **Step 5: Checkpoint** — index aggiornato, sistema verde end-to-end, skill operativa. TodoWrite update. **Implementazione completa.**

**Stima tempo:** 5 min.

---

## Harness expected delta

| Stato | review-triage-fix PASS | dedicated PASS | Note |
|---|---|---|---|
| Baseline (pre-implementazione, 2026-05-20) | 47 | n/a | 3 ADR + v1.2 anchor. |
| Post-Task-1 (red) | 47 FAIL=1 | n/a | +1 anchor vibe-status SKILL.md missing. Exit 1. |
| Post-Task-2 (SKILL.md) | 48 | n/a | Anchor verde. **TARGET review-triage-fix PASS=48.** |
| Post-Task-3 (harness-runner.sh) | 48 | n/a | No harness change (script support only). |
| Post-Task-4 (aggregate.sh) | 48 | n/a | No harness change (aggregate.sh non testato dal dedicated yet). |
| Post-Task-5 (dedicated harness) | 48 | 9 | Dedicated end-to-end. **TARGET dedicated PASS=9.** |
| Post-Task-6 (doc sync) | 48 | 9 | No harness change. |
| Post-Task-7 (memory entry) | 48 | 9 | No harness change. |
| Post-Task-8 (MEMORY.md) | 48 | 9 | **Stato finale.** |

**Delta totale dichiarato:**
- `review-triage-fix` harness PASS=47 → PASS=48 (+1 anchor SKILL.md vibe-status).
- Dedicated harness PASS=9 (new, target full coverage 9 test case).

**Anchor preservation invariante:** in nessun task viene rimosso o alterato uno dei 47 anchor v1.2+ADR-0001+ADR-0002+ADR-0003. Il blocco Task 8 è inserito pre-summary line. Se ADR-0004 viene mergiato prima di ADR-0005, baseline rebase a PASS=48 → target post-Task-2 PASS=49 (no semantic change).

---

## Risk summary

- **R1 — Performance fail su sistema con 5+ harness lenti.** Severity: low-medium. Parallel exec + 8s timeout per-harness mitigano. Misurabile via Task 4 Step 6 (`time aggregate.sh`). Se >10s p95: tuning timeout o aggiunta cache v1.1.
- **R2 — Parse fragility su settings.json malformato.** Severity: low. Fail-graceful: section hook degrada a "(unable to parse)", overall DEGRADED. Test 9 della harness dedicata copre questo path.
- **R3 — Parse fragility su harness output non-standard.** Severity: medium. aggregate.sh estrae `PASS=N`/`FAIL=N` con `grep -E`. Se un harness futuro cambia format del summary line, parse fail → row `? ?` nella tabella. Mitigazione: regex tollerante, fallback `?`. Convenzione: tutti i harness del sistema seguono format `PASS=N FAIL=N` (verificato per review-triage-fix, concept-to-code, refactor-snapshot 2026-05-20).
- **R4 — Cwd-sensitivity confusing su sessione globale (`$PWD = ~`).** Severity: low. Output mostra `(no project ADR directory)` etc. Documentato in SKILL.md. UX accettabile.
- **R5 — `transcript_path`-style assumption sull'invocazione `/skill vibe-status`.** Severity: low. La skill non dipende da transcript Claude Code; usa solo filesystem read. Robusta.
- **R6 — Bash 3.2 trap su syntax.** Severity: low. Hook + harness usano subset 3.2-clean (verificato in spec §3.10). Pre-Task-4 review: no assoc array, no mapfile, no `${v^^}`, no `<()`.
- **R7 — Coupling settings.json + review-triage-fix harness.** Severity: low. +1 anchor lega l'harness al SKILL.md vibe-status. Refactor futuro di review-triage-fix richiede update anchor. Costo: 1 path string.
- **R8 — Adozione bassa.** Severity: low (non blocking). Se Stefano non usa `/skill vibe-status` regolarmente, la skill resta inert ma non dannosa. Read-only, zero side-effect. Validabile in 2 settimane di uso.

## HITL gate

Nessun gate hard richiesto dal deploy. Edit additive su `~/.claude/skills/` + 1 anchor harness + doc. Nessun commit (no git). Nessun schema DB. Nessuna eliminazione permanente. Le decisioni HITL globali non si applicano.

Validazione operativa POST-deploy è osservativa, non bloccante:
- Adozione: contare invocazioni `/skill vibe-status` in 2 settimane.
- Performance: benchmark periodico `time aggregate.sh`.
- Markdown render quality in chat: feedback empirico da Stefano.
