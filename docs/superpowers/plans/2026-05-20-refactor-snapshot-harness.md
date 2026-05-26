# Refactor snapshot harness — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Changelog:**
- v1.0 (2026-05-20): initial — TDD plan derivato da `ADR-0002-refactor-snapshot-harness.md`
  e dallo spec `2026-05-20-refactor-snapshot-harness-design.md`. 8 task: 1 red harness
  anchor + 4 green (skill scripts + skill self-test + refactorer.md edit) + 1 sync
  ADR/spec status + 2 memory deliverable (project memory + MEMORY.md index).

**Goal:** deployare lo skill `~/.claude/skills/refactor-snapshot/` (3 file bash 3.2 +
SKILL.md + self-test harness) e patch al `refactorer` agent (`~/.claude/agents/refactorer.md`)
per integrare lo snapshot harness nel suo Process 8-step. Aggiungere 2 anchor structural
al harness `review-triage-fix/tests/run-tests.sh` (PASS=43 → PASS=45). Triple-angle
coverage del rischio "code change non corrisponde a intent": ADR-0001 (coder pre-flight,
Accepted 2026-05-20) + v1.2 (reviewer Add+Remove triage) + ADR-0002 (refactorer
post-edit snapshot, questo plan).

**Architecture:** skill nuova additiva (no overwrite di skill esistenti) + sostituzione
pulita di sezione `## Process` in `refactorer.md` (no shim) + 2 nuovi anchor in
harness review-triage-fix (no rimozione di anchor esistenti). Tutti gli script bash
3.2-clean by construction (memory `feedback_bash32-constraint.md`). Coexistenza
ortogonale con ADR-0001 + v1.2: nessun edit a `coder.md`, `reviewer.md`,
`review-triage-fix/SKILL.md`, hook, settings.json, MCP.

**Tech Stack:** markdown (SKILL.md, system prompt, plan, spec, memory), bash 3.2.57
(scripts skill + harness anchor — 3.2-clean by construction, identico stile dei 45
anchor target del review-triage-fix harness).

**Spec:** `docs/superpowers/specs/2026-05-20-refactor-snapshot-harness-design.md`
(approvato 2026-05-20).
**ADR:** `docs/architecture/ADR-0002-refactor-snapshot-harness.md` (Proposed 2026-05-20).

---

## Environment notes (read first)

- **No git in `~/.claude/` né in questo repo doc `vibe-coding-system`.** Checkpoint per
  task = harness verde + TodoWrite update + report. Nessun commit. Nessun HITL gate
  complesso: il deploy è additivo (nuova skill + edit additive su system prompt agent
  + harness), non tocca hook live, settings.json, MCP, helper script. Tutto inert
  finché il prossimo dispatch organico del `refactorer` legge il system prompt
  aggiornato.
- **Bash 3.2 cleanliness.** Tutti gli script in `~/.claude/skills/refactor-snapshot/`
  + il nuovo blocco anchor in `review-triage-fix/tests/run-tests.sh` usano solo
  `grep -q -- "..."`, `[ -f "$x" ]`, `[ "$a" = "$b" ]`, `command -v`, `mktemp -d`, `ok`/`bad`
  helpers (style identico a `verify.sh`/`weakening-scan.sh`/`triage-state.sh`). Nessun
  assoc array, nessun `mapfile`, nessun `${v^^}`, nessun `<()` process substitution.
  Per ragioni memory `feedback_bash32-constraint.md`.
- **Anchor preservation.** Nessuno dei 43 anchor post ADR-0001 viene rimosso o
  alterato. Il nuovo blocco Task 7 è appended TRA il blocco Task 6 (coder.md, ultimo
  anchor riga 149) e la summary line (`echo "----"`, riga 151). I 43 anchor restano
  nelle stesse righe.
- **Harness count baseline (verificato 2026-05-20 con
  `bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh`):** `PASS=43 FAIL=0`.
  Suddivisione: verify ×7 + weakening ×6 + state-diff ×4 + state-commit ×4 + SKILL.md
  ×20 + coder.md ×2. Adding 2 new anchor (Task 7 refactorer.md) porta cumulative a
  `PASS=45 FAIL=0`.
- **Skill self-test target:** lo skill `refactor-snapshot` ha proprio self-test harness
  in `tests/run-tests.sh`. Target PASS=10 FAIL=0 (10 assertion: contract di capture.sh,
  diff.sh, override integration — vedi spec §3.3).
- **Backup raccomandato pre-edit:** `cp ~/.claude/agents/refactorer.md
  ~/.claude/agents/refactorer.md.bak-2026-05-20` + `cp
  ~/.claude/skills/review-triage-fix/tests/run-tests.sh
  ~/.claude/skills/review-triage-fix/tests/run-tests.sh.bak-2026-05-20`. Patch
  refactorer.md è SOSTITUTIVA su Process section (non puramente additiva), quindi
  backup è raccomandato non opzionale. Patch harness è additiva.
- **Portability.** Edit operativi su `~/.claude/skills/refactor-snapshot/` (nuova),
  `~/.claude/agents/refactorer.md`, `~/.claude/skills/review-triage-fix/tests/run-tests.sh`.
  Deliverable doc (questo plan, ADR, spec, memory update) nel repo `vibe-coding-system`
  + `~/.claude/projects/.../memory/`. Nessun MCP, hook, settings.json toccato.
- **Coexistenza HARD (ortogonalità):** ADR-0001 sezione `## Pre-flight Pattern
  Classifier` in `coder.md` NON modificata. Item 5 `Pattern-drift check` in
  `reviewer.md` NON modificato. Regola `Add+Remove rule (for SUBSTITUTION fixes)` in
  `review-triage-fix/SKILL.md` Step 2 NON modificata. Hook `approve-test-cmd.sh` +
  `stop-gate.sh` NON modificati.
- **Auto mode (no HITL intermedio):** dal brief — l'architect non chiede conferme
  durante il design. Il deploy stesso del plan è anch'esso auto: backup → edit → harness
  verify → next task. HITL gate solo per creazione `.claude/refactor-snapshot-override`
  (user-only, runtime per progetto target, non parte di questo plan).

## File structure

Tutti i path live (`~/.claude/skills/refactor-snapshot/` nuova + `~/.claude/agents/refactorer.md`
+ `~/.claude/skills/review-triage-fix/tests/run-tests.sh`); deliverable doc nel repo
`vibe-coding-system`; memory in
`~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/`.

- Create `~/.claude/skills/refactor-snapshot/SKILL.md` — frontmatter (name +
  description) + body 6 sezioni (When to invoke, Invocation contract, Outputs,
  Stack-agnostic, Override, Failure modes). ~60 righe.
- Create `~/.claude/skills/refactor-snapshot/scripts/capture.sh` — bash 3.2, ~80
  righe. Legge `$PWD/.claude/test-cmd`, esegue con $RFS_FILTER/$RFS_FULL/$RFS_TIMEOUT,
  scrive `.claude/.refactor-snapshot.txt` (arg PRE) o `.refactor-snapshot.txt.post`
  (arg POST) con formato EXIT/SHA256/separator/payload.
- Create `~/.claude/skills/refactor-snapshot/scripts/diff.sh` — bash 3.2, ~90 righe.
  Legge PRE + POST snapshot + opzionale override file. Compara SHA256 + EXIT. Output
  STATUS=<PASS|FAIL|UNVERIFIED> + per-channel match. Exit 0/1/2.
- Create `~/.claude/skills/refactor-snapshot/tests/run-tests.sh` — bash 3.2, self-test
  harness della skill, ~110 righe. 10 assertion.
- Modify `~/.claude/agents/refactorer.md` — sostituire sezione `## Process`
  (righe 25-31 attuali) con la sequenza 8-step (spec §3.2). Append sezione
  `## Snapshot Harness Integration` (~10 righe) e 2 bullet a `## Edge Cases`.
- Modify `~/.claude/skills/review-triage-fix/tests/run-tests.sh` — append blocco
  `# --- Task 7: refactorer.md snapshot harness section ---` con 2 anchor su
  `refactorer.md`, tra blocco Task 6 (riga 149) e summary line (riga 151).
- Modify `docs/architecture/ADR-0002-refactor-snapshot-harness.md` — status line da
  `Proposed — 2026-05-20` a `Accepted — 2026-05-20`.
- Modify `docs/superpowers/specs/2026-05-20-refactor-snapshot-harness-design.md` —
  status line da `approvato (post-ADR) — pronto per writing-plans` a `implementato —
  2026-05-20`.
- Create `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/project_refactor-snapshot-harness.md` —
  nuovo project memory entry con link a ADR/spec/plan, stato deploy, invariante
  "snapshot harness + green→green check + ADR-0001 + v1.2 coesistono".
- Modify `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/MEMORY.md` —
  append riga nuova in sezione `## Project` con prefix `**DEPLOYED 2026-05-20**:`.

Unchanged (vincoli HARD): `~/.claude/skills/review-triage-fix/SKILL.md` (v1.2 Add+Remove
rule resta), `~/.claude/skills/review-triage-fix/scripts/*.sh` (verify, weakening-scan,
triage-state — invariati), `~/.claude/agents/coder.md` (ADR-0001 invariata),
`~/.claude/agents/reviewer.md` (item 5 invariato), `~/.claude/agents/debugger.md`,
`tester.md`, `architect.md`, `doc-writer.md`, `researcher.md`,
`~/.claude/hooks/approve-test-cmd.sh`, `stop-gate.sh`, `~/.claude/settings.json`,
`.mcp.json`, `.claude/rules/`, `docs/vibe-coding-system.md`.

---

### Task 1: Harness anchor failing (red)

**Files:**
- Modify: `~/.claude/skills/review-triage-fix/tests/run-tests.sh` (insert nuovo blocco
  Task 7 tra blocco Task 6 fine e summary line)

**Red phase:** baseline harness `PASS=43 FAIL=0` (post ADR-0001 deploy 2026-05-20). Il
nuovo blocco Task 7 cerca `Snapshot Harness Integration` e `refactor-snapshot` in
`~/.claude/agents/refactorer.md` — entrambi assenti pre-Task-6. Aspettativa: 2 nuovi
`FAIL`, cumulative `PASS=43 FAIL=2`, exit 1.

**Green phase (edit concreto):** localizza nel file la fine del blocco Task 6
(`grep -q -- 'PATTERN: <CATEGORY>' "$C" 2>/dev/null && ok "coder.md: PATTERN format
spec present" || bad "coder.md: PATTERN format spec missing"`, attualmente riga 149) e
la summary line (`echo "----"; echo "PASS=$PASS FAIL=$FAIL"; rm -rf "$TMP"`,
attualmente riga 151). Inserisci tra le due (in posizione riga 150 attuale blank line)
il blocco:

```bash

# --- Task 7: refactorer.md snapshot harness section ---
R="$HOME/.claude/agents/refactorer.md"
grep -q -- 'Snapshot Harness Integration' "$R" 2>/dev/null && ok "refactorer.md: snapshot integration section present" || bad "refactorer.md: snapshot integration section missing"
grep -q -- 'refactor-snapshot' "$R" 2>/dev/null && ok "refactorer.md: refactor-snapshot skill reference present" || bad "refactorer.md: refactor-snapshot skill reference missing"

```

Notes:
- 2 assertion totali (presence section + presence skill reference). No file-exists
  guard (allineato a stile Task 6, che lo ha rimosso post-refinement per stick al
  contract "+2 anchor").
- Match string `Snapshot Harness Integration` = literal H2 heading in refactorer.md
  (Task 6 lo introduce). `refactor-snapshot` = literal della reference path nella
  sezione (Task 6 lo introduce nello stesso edit).
- 3.2-clean by construction: `grep -q -- "..."` literal + `&&`/`||` + `ok`/`bad`
  (definiti righe 8-9). Identico stile blocco Task 6 (righe 146-149) e blocco Task 5
  (righe 122-144).
- Conta finale attesa post-Task-6: `PASS=45 FAIL=0`. Conta finale post-Task-1 (red):
  `PASS=43 FAIL=2`.

- [ ] **Step 1: Write the failing test** — edit
  `~/.claude/skills/review-triage-fix/tests/run-tests.sh` per inserire il blocco
  Task 7 (3 righe content + 1 blank leading + 1 blank trailing) tra riga 149 (ultimo
  anchor Task 6) e riga 151 (summary).

- [ ] **Step 2: Run test to verify it fails**

Verify command:
```bash
bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh; echo "exit=$?"
```
Expected: i 43 anchor (v1.2 + ADR-0001) ancora `PASS`; le 2 nuove check `refactorer.md:
snapshot integration section present` + `refactorer.md: refactor-snapshot skill
reference present` entrambe `FAIL`; summary `PASS=43 FAIL=2`, exit 1.

- [ ] **Step 3: Checkpoint** — failing test in place, baseline rossa confermata
  (`PASS=43 FAIL=2`). TodoWrite update.

**Stima tempo:** 5 min.

---

### Task 2: Create skill `refactor-snapshot/` (SKILL.md + scripts)

**Files:**
- Create: `~/.claude/skills/refactor-snapshot/SKILL.md`
- Create: `~/.claude/skills/refactor-snapshot/scripts/capture.sh`
- Create: `~/.claude/skills/refactor-snapshot/scripts/diff.sh`

**Red phase:** la directory `~/.claude/skills/refactor-snapshot/` non esiste. Inspectional
pre-edit:
```bash
ls -d ~/.claude/skills/refactor-snapshot/ 2>&1
```
Expected: `No such file or directory`.

**Green phase (edit concreto):**

#### 2.1 `~/.claude/skills/refactor-snapshot/SKILL.md`

```markdown
---
name: refactor-snapshot
description: Behavior-preservation snapshot harness for the refactorer agent. Captures stdout/stderr/exit-code of project test command pre-refactor, re-runs post-refactor, diffs SHA256. Fails loud on non-zero diff. Stack-agnostic via .claude/test-cmd contract.
---

# Refactor snapshot harness

Captures observable behavior of the project test suite (stdout + stderr + exit-code)
before a refactor, re-runs after the refactor, and diffs SHA256. Non-zero diff means
the refactor changed observable behavior and must be reconsidered.

## When to invoke

Exclusively from the `refactorer` sub-agent during its Process. Not auto-invoked, not
chained from other agents or skills. The `refactorer.md` system prompt step-2 / step-5
/ step-6 are the only callers.

## Invocation contract

The refactorer invokes three commands in sequence per refactor cycle:

    bash ~/.claude/skills/refactor-snapshot/scripts/capture.sh PRE    # before edit
    bash ~/.claude/skills/refactor-snapshot/scripts/capture.sh PRE    # determinism check
    bash ~/.claude/skills/refactor-snapshot/scripts/capture.sh PRE    # determinism check
    # ... refactor edits ...
    bash ~/.claude/skills/refactor-snapshot/scripts/capture.sh POST   # after edit
    bash ~/.claude/skills/refactor-snapshot/scripts/diff.sh           # gate

The 3 PRE runs verify determinism (SHA256 identical across runs). If not identical →
UNVERIFIED, abort.

## Outputs

- `$PWD/.claude/.refactor-snapshot.txt` — PRE snapshot (kept across cycles as
  baseline).
- `$PWD/.claude/.refactor-snapshot.txt.post` — POST snapshot (cleaned on PASS, kept on
  FAIL for inspection).

File format (both):

    EXIT=<integer>
    STDOUT-SHA256=<64 hex>
    STDERR-SHA256=<64 hex>
    ---STDOUT---
    <full stdout, byte-faithful>
    ---STDERR---
    <full stderr, byte-faithful>

Exit codes (`diff.sh`): 0 = PASS, 1 = FAIL, 2 = UNVERIFIED.

## Stack-agnostic

Reads `$PWD/.claude/test-cmd` (TOFU + 3-tier contract, deploy 2026-05-19 swarm-testcmd).
No language parsing. Project target declares its own test command (`pytest`, `npm
test`, `swift test`, etc).

If `.claude/test-cmd` is missing, `capture.sh` returns exit 1 → refactorer reports
UNVERIFIED and aborts the cycle.

## Override

Optional file `$PWD/.claude/refactor-snapshot-override`, user-created (HITL gate; the
refactorer NEVER creates this):

    REASON: <one-line justification>
    SCOPE: <stdout|stderr|exit|all>
    EXPIRES: <YYYY-MM-DD>

If present and valid, `diff.sh` ignores divergence in the declared SCOPE channels and
outputs `OVERRIDE=yes:<REASON>`. Audit trail: refactorer cites the file path + reason
in its final report.

## Failure modes

| State | Meaning | Refactorer action |
|---|---|---|
| `PASS` | All SHA256 + EXIT identical, or all diverging channels covered by override | Report success |
| `FAIL` | At least one diverging channel not covered by override | STOP, report drift (HITL) |
| `UNVERIFIED` | PRE non-deterministic (3 runs differ), or PRE/POST malformed, or test-cmd missing | STOP, report flakiness or precondition failure |

## Env vars

- `RFS_TIMEOUT` (default 120) — per-run test-cmd timeout in seconds.
- `RFS_FILTER` (default empty) — pattern passed to test-cmd (e.g. `pytest -k <pat>`).
- `RFS_FULL` (default 0) — when 1, ignore RFS_FILTER and use full test scope.
- `RFS_DETERMINISM_RUNS` (default 3) — number of PRE runs in the determinism check.

## Constraints

- Bash 3.2.57 portable (no assoc array, no `mapfile`, no `${v^^}`, no `<()`).
- SHA256 via `shasum -a 256` (BSD/macOS) with `sha256sum` fallback (Linux).
- Self-test: `bash tests/run-tests.sh` — target PASS=10 FAIL=0.
```

#### 2.2 `~/.claude/skills/refactor-snapshot/scripts/capture.sh`

Body (bash 3.2-clean, ~80 righe). Outline implementativo (il coder lo dettaglia
nell'implementazione; il plan fornisce contract):

- Validate arg in `{PRE, POST}`, else exit 3.
- Verify `$PWD/.claude/test-cmd` exists, else exit 1.
- Detect SHA256 tool: `command -v shasum >/dev/null && SHA="shasum -a 256" || SHA="sha256sum"`.
- Read test-cmd content (strip comments, leading/trailing whitespace).
- Compute target file: `PRE → .claude/.refactor-snapshot.txt`, `POST →
  .claude/.refactor-snapshot.txt.post`.
- Create tmp dir via `mktemp -d`.
- Build command line: if `$RFS_FULL` = 1, use raw test-cmd. Elif `$RFS_FILTER` non-empty,
  append `$RFS_FILTER` to test-cmd. Else raw test-cmd.
- Execute with timeout `$RFS_TIMEOUT` (default 120). Capture stdout to
  `$TMP/stdout`, stderr to `$TMP/stderr`, exit code to var.
- Compute SHA256 of stdout / stderr (hex only, no filename via `awk '{print $1}'`).
- Write target file with header (EXIT, STDOUT-SHA256, STDERR-SHA256) + separator
  `---STDOUT---` + stdout content + separator `---STDERR---` + stderr content.
- Cleanup tmp dir.
- Exit 0.

Edge handling:
- Timeout: `timeout $RFS_TIMEOUT bash -c "$CMD"` — se non disponibile (macOS senza
  coreutils), fallback a no-timeout + warning. Plan-level decision: assume `timeout` o
  `gtimeout` disponibile (homebrew coreutils standard); se non disponibile, capture.sh
  funziona ma senza limite temporale e logga warning su stderr.
- Test-cmd è multi-line script: leggi tutte le righe, esegui via `bash -c "$(cat .claude/test-cmd)"`.

#### 2.3 `~/.claude/skills/refactor-snapshot/scripts/diff.sh`

Body (bash 3.2-clean, ~90 righe). Outline:

- Parse args: `--baseline <path>` (default `$PWD/.claude/.refactor-snapshot.txt`),
  `--candidate <path>` (default `$PWD/.claude/.refactor-snapshot.txt.post`).
- Verify both files exist, else `STATUS=UNVERIFIED`, exit 2.
- Extract EXIT, STDOUT-SHA256, STDERR-SHA256 from each via `grep '^EXIT=' file | cut
  -d= -f2-` etc.
- Validate format (SHA256 is 64 hex chars), else `STATUS=UNVERIFIED`, exit 2.
- Compute per-channel match: `EXIT-MATCH`, `STDOUT-MATCH`, `STDERR-MATCH` (yes/no).
- Check override file `$PWD/.claude/refactor-snapshot-override`:
  - If present, parse REASON, SCOPE, EXPIRES.
  - Validate SCOPE in `{stdout, stderr, exit, all}`.
  - Validate EXPIRES is future date (`[ "$(date +%Y-%m-%d)" \< "$EXPIRES" ] || [ "$(date +%Y-%m-%d)" = "$EXPIRES" ]`).
  - If valid, set OVERRIDE_SCOPE and OVERRIDE_REASON.
- Compute STATUS:
  - If all three match: `STATUS=PASS`.
  - Elif override covers ALL diverging channels: `STATUS=PASS`, output `OVERRIDE=yes:<REASON>`.
  - Else: `STATUS=FAIL`.
- Output (always, stdout):
  ```
  STATUS=<status>
  EXIT-MATCH=<yes|no>
  STDOUT-MATCH=<yes|no>
  STDERR-MATCH=<yes|no>
  OVERRIDE=<yes:reason|no>
  ```
- Exit 0/1/2 per STATUS.

#### Verify

```bash
ls ~/.claude/skills/refactor-snapshot/SKILL.md ~/.claude/skills/refactor-snapshot/scripts/capture.sh ~/.claude/skills/refactor-snapshot/scripts/diff.sh
```
Expected: 3 file presenti, no error.

```bash
bash -n ~/.claude/skills/refactor-snapshot/scripts/capture.sh && bash -n ~/.claude/skills/refactor-snapshot/scripts/diff.sh && echo "syntax OK"
```
Expected: `syntax OK` (bash -n syntax check, no exec).

- [ ] **Step 1: Create SKILL.md** — `Write` di `~/.claude/skills/refactor-snapshot/SKILL.md`
  con il body §2.1.

- [ ] **Step 2: Create capture.sh** — `Write` di
  `~/.claude/skills/refactor-snapshot/scripts/capture.sh` con il body §2.2.
  Make executable via `chmod +x` post-write.

- [ ] **Step 3: Create diff.sh** — `Write` di
  `~/.claude/skills/refactor-snapshot/scripts/diff.sh` con il body §2.3. Make executable
  via `chmod +x` post-write.

- [ ] **Step 4: Bash syntax check** — `bash -n` su entrambi gli script, expected
  `syntax OK`.

- [ ] **Step 5: Checkpoint** — skill creata, script bash 3.2-clean validate via syntax
  check. Harness review-triage-fix non ancora rilevante (refactorer.md non ancora
  patchato). TodoWrite update.

**Stima tempo:** 25 min.

---

### Task 3: Self-test harness della skill `refactor-snapshot`

**Files:**
- Create: `~/.claude/skills/refactor-snapshot/tests/run-tests.sh`

**Red phase:** il file `tests/run-tests.sh` non esiste. Inspectional pre-edit:
```bash
ls ~/.claude/skills/refactor-snapshot/tests/run-tests.sh 2>&1
```
Expected: `No such file or directory`.

**Green phase (edit concreto):** crea `~/.claude/skills/refactor-snapshot/tests/run-tests.sh`
(bash 3.2-clean, ~110 righe). 10 assertion:

```bash
#!/bin/bash
# refactor-snapshot self-test harness. Isolated; never touches real state.
set -u
SK="$HOME/.claude/skills/refactor-snapshot"
S="$SK/scripts"
TMP="$(mktemp -d)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

# 1: SKILL.md frontmatter name
M="$SK/SKILL.md"
[ -f "$M" ] && head -1 "$M" | grep -q '^---$' && grep -q '^name: refactor-snapshot$' "$M" \
  && ok "SKILL.md: frontmatter name" || bad "SKILL.md: frontmatter name"

# 2: SKILL.md description includes "snapshot harness"
grep -q '^description:.*snapshot' "$M" && ok "SKILL.md: description" || bad "SKILL.md: description"

# 3: scripts present + executable
[ -x "$S/capture.sh" ] && ok "capture.sh: present + executable" || bad "capture.sh: present + executable"
[ -x "$S/diff.sh" ] && ok "diff.sh: present + executable" || bad "diff.sh: present + executable"

# 4: capture.sh missing test-cmd → exit 1
P1="$TMP/proj1"; mkdir -p "$P1/.claude"
( cd "$P1" && bash "$S/capture.sh" PRE >/dev/null 2>&1 ); r=$?
[ $r -eq 1 ] && ok "capture: missing test-cmd → exit 1" || bad "capture: missing test-cmd → exit 1"

# 5: capture.sh bad arg → exit 3
P2="$TMP/proj2"; mkdir -p "$P2/.claude"; printf 'true\n' > "$P2/.claude/test-cmd"
( cd "$P2" && bash "$S/capture.sh" XYZ >/dev/null 2>&1 ); r=$?
[ $r -eq 3 ] && ok "capture: bad arg → exit 3" || bad "capture: bad arg → exit 3"

# 6: capture.sh green test-cmd → snapshot file con EXIT=0 + SHA256 64-hex
P3="$TMP/proj3"; mkdir -p "$P3/.claude"; printf 'echo hello\n' > "$P3/.claude/test-cmd"
( cd "$P3" && bash "$S/capture.sh" PRE >/dev/null 2>&1 )
SF="$P3/.claude/.refactor-snapshot.txt"
[ -f "$SF" ] \
  && grep -q '^EXIT=0$' "$SF" \
  && grep -q '^STDOUT-SHA256=[0-9a-f]\{64\}$' "$SF" \
  && grep -q '^STDERR-SHA256=[0-9a-f]\{64\}$' "$SF" \
  && ok "capture: green test-cmd → valid snapshot" || bad "capture: green test-cmd → valid snapshot"

# 7: capture.sh red test-cmd → snapshot file con EXIT non-zero
P4="$TMP/proj4"; mkdir -p "$P4/.claude"; printf 'exit 7\n' > "$P4/.claude/test-cmd"
( cd "$P4" && bash "$S/capture.sh" PRE >/dev/null 2>&1 )
SFR="$P4/.claude/.refactor-snapshot.txt"
[ -f "$SFR" ] && grep -q '^EXIT=7$' "$SFR" \
  && ok "capture: red test-cmd → EXIT captured" || bad "capture: red test-cmd → EXIT captured"

# 8: diff.sh identical PRE/POST → exit 0 STATUS=PASS
P5="$TMP/proj5"; mkdir -p "$P5/.claude"; printf 'echo same\n' > "$P5/.claude/test-cmd"
( cd "$P5" && bash "$S/capture.sh" PRE >/dev/null 2>&1 )
( cd "$P5" && bash "$S/capture.sh" POST >/dev/null 2>&1 )
O=$( cd "$P5" && bash "$S/diff.sh" 2>/dev/null ); r=$?
[ $r -eq 0 ] && echo "$O" | grep -q '^STATUS=PASS$' \
  && ok "diff: identical → PASS exit 0" || bad "diff: identical → PASS exit 0"

# 9: diff.sh different stdout → exit 1 STATUS=FAIL
P6="$TMP/proj6"; mkdir -p "$P6/.claude"; printf 'echo "$RFS_VAR"\n' > "$P6/.claude/test-cmd"
RFS_VAR=A ( cd "$P6" && bash "$S/capture.sh" PRE >/dev/null 2>&1 ) || true
RFS_VAR=B ( cd "$P6" && bash "$S/capture.sh" POST >/dev/null 2>&1 ) || true
# Note: the above approach via env var may not work depending on test-cmd quoting;
# alternative implementation: modify test-cmd between PRE and POST. Plan-level
# decision: modify test-cmd between calls to ensure deterministic stdout difference.
printf 'echo aaa\n' > "$P6/.claude/test-cmd"; ( cd "$P6" && bash "$S/capture.sh" PRE >/dev/null 2>&1 )
printf 'echo bbb\n' > "$P6/.claude/test-cmd"; ( cd "$P6" && bash "$S/capture.sh" POST >/dev/null 2>&1 )
O=$( cd "$P6" && bash "$S/diff.sh" 2>/dev/null ); r=$?
[ $r -eq 1 ] && echo "$O" | grep -q '^STATUS=FAIL$' && echo "$O" | grep -q '^STDOUT-MATCH=no$' \
  && ok "diff: divergent stdout → FAIL exit 1" || bad "diff: divergent stdout → FAIL exit 1"

# 10: diff.sh with override SCOPE=stdout on divergent stdout → exit 0 STATUS=PASS OVERRIDE=yes
P7="$TMP/proj7"; mkdir -p "$P7/.claude"
printf 'echo aaa\n' > "$P7/.claude/test-cmd"; ( cd "$P7" && bash "$S/capture.sh" PRE >/dev/null 2>&1 )
printf 'echo bbb\n' > "$P7/.claude/test-cmd"; ( cd "$P7" && bash "$S/capture.sh" POST >/dev/null 2>&1 )
printf 'REASON: test timestamp drift expected\nSCOPE: stdout\nEXPIRES: 2099-12-31\n' > "$P7/.claude/refactor-snapshot-override"
O=$( cd "$P7" && bash "$S/diff.sh" 2>/dev/null ); r=$?
[ $r -eq 0 ] && echo "$O" | grep -q '^STATUS=PASS$' && echo "$O" | grep -q '^OVERRIDE=yes' \
  && ok "diff: override SCOPE=stdout → PASS exit 0" || bad "diff: override SCOPE=stdout → PASS exit 0"

echo "----"; echo "PASS=$PASS FAIL=$FAIL"; rm -rf "$TMP"
[ $FAIL -eq 0 ]
```

Notes:
- 10 assertion: 3 SKILL.md/script presence, 2 capture.sh contract, 2 capture.sh exec
  scenarios, 3 diff.sh scenarios (identical/divergent/override).
- Pattern style identico a `review-triage-fix/tests/run-tests.sh` (ok/bad helpers,
  isolated tmp dir, grep -q literal). 3.2-clean by construction.
- Edge handling assertion 9: ho rivisto l'approccio "env var" perché test-cmd quoting
  può essere fragile. Approach finale: modificare il contenuto del file `test-cmd`
  tra PRE e POST. Deterministic, no dipende da env var propagation.
- Lo skill harness conta NUMERATI 1-10; il numero esatto è 10 assertion + 1 summary.

#### Verify

```bash
chmod +x ~/.claude/skills/refactor-snapshot/tests/run-tests.sh
bash ~/.claude/skills/refactor-snapshot/tests/run-tests.sh; echo "exit=$?"
```
Expected: `PASS=10 FAIL=0`, exit 0. **TARGET SELF-TEST RAGGIUNTO.**

- [ ] **Step 1: Write the self-test harness** — `Write` del file
  `~/.claude/skills/refactor-snapshot/tests/run-tests.sh` con il body sopra.

- [ ] **Step 2: Make executable** — `chmod +x
  ~/.claude/skills/refactor-snapshot/tests/run-tests.sh`.

- [ ] **Step 3: Run self-test** — `bash
  ~/.claude/skills/refactor-snapshot/tests/run-tests.sh; echo "exit=$?"`. Expected
  `PASS=10 FAIL=0`, exit 0.

- [ ] **Step 4: Checkpoint** — skill self-test verde a `PASS=10`. Lo skill è
  funzionalmente completo (capture + diff + self-test). Harness review-triage-fix
  resta a `PASS=43 FAIL=2` (refactorer.md non ancora patchato). TodoWrite update.

**Stima tempo:** 20 min.

---

### Task 4: refactorer.md Process section + Snapshot Harness Integration (green primary)

**Files:**
- Modify: `~/.claude/agents/refactorer.md` (sostituisci sezione `## Process`, append
  sezione `## Snapshot Harness Integration`, append 2 bullet a `## Edge Cases`)

**Red phase:** harness review-triage-fix `PASS=43 FAIL=2` post-Task-1. Le 2 check
Task-7 ancora fallano (refactorer.md non contiene `Snapshot Harness Integration` né
`refactor-snapshot`).

**Green phase (edit concreto):**

#### 4.1 Sostituisci `## Process` (righe 25-31 attuali) con sequenza 8-step

Localizza in `~/.claude/agents/refactorer.md` la sezione `## Process` esistente (righe
25-31, 6 numbered points). Rimuovi le 6 righe esistenti e inserisci il nuovo body
sotto la heading `## Process`:

```markdown
## Process

1. **Baseline check.** Run the project test command (`.claude/test-cmd`). If non-zero → STOP, report "tests red at baseline, refactor unsafe" (defer to debugger).
2. **Pre-snapshot capture.** Invoke `bash ~/.claude/skills/refactor-snapshot/scripts/capture.sh PRE`. Writes `.claude/.refactor-snapshot.txt` with EXIT/STDOUT-SHA256/STDERR-SHA256 + payload.
3. **Determinism check.** Re-run pre-snapshot 2 more times (3 total). If SHA256 differs across runs → STOP, output `UNVERIFIED non-deterministic test output`, report flakiness with suggestion to create `.claude/refactor-snapshot-override` if intentional.
4. **Apply refactor.** Focused, behavior-preserving edit (≤200 lines per pass — existing invariant preserved).
5. **Post-snapshot capture.** Invoke `bash ~/.claude/skills/refactor-snapshot/scripts/capture.sh POST`. Writes `.claude/.refactor-snapshot.txt.post`.
6. **Diff.** Invoke `bash ~/.claude/skills/refactor-snapshot/scripts/diff.sh`. Compares EXIT + STDOUT-SHA256 + STDERR-SHA256 of PRE vs POST. Exit 0=PASS, 1=FAIL, 2=UNVERIFIED.
7. **On FAIL.** STOP. Report drift with `loc=path:line` for the diverging channel(s) (exit/stdout/stderr) + `diff -u` excerpt of the payloads. Refactor remains on disk; recommend revert. HITL gate: user decides whether to accept as intentional behavior change (not a refactor) or revert.
8. **On PASS.** Report success: `lines changed`, `tests passed`, `snapshot PASS`. Cleanup `.refactor-snapshot.txt.post` (PRE kept as baseline for next cycle).
```

#### 4.2 Append nuova sezione `## Snapshot Harness Integration` dopo `## Process` e prima di `## Quality Standards`

Inserisci tra la fine del Process section (step 8 sopra) e la heading `## Quality Standards` (riga ~33 attuale pre-edit, da rilocalizzare post-Step-4.1):

```markdown
## Snapshot Harness Integration

The behavior-preservation guarantee is provided by `~/.claude/skills/refactor-snapshot/`, invoked at steps 2/3 (PRE), 5 (POST), 6 (diff) of Process above.

- `.claude/test-cmd` MUST pre-exist and be approved (TOFU). If absent, snapshot is UNVERIFIED → STOP, ask user to deploy test-cmd first.
- For projects with non-deterministic test output (timestamps, random IDs), the user may create `.claude/refactor-snapshot-override` with `REASON:`/`SCOPE:`/`EXPIRES:` fields. The refactorer NEVER creates this file itself — HITL gate.
- For reflection / dynamic dispatch in the modified files, escalate blast radius via `RFS_FULL=1` env var (full project test scope). Declare the escalation in the report.
- For slow test suites, narrow scope via `RFS_FILTER=<pattern>` env var passed to the test command. Decide at runtime based on PRE-snapshot baseline duration.
```

#### 4.3 Append 2 bullet a `## Edge Cases`

Localizza la sezione `## Edge Cases` esistente (righe 48-51 pre-edit, 3 bullet
attuali: tests red at baseline, no tests exist, refactor balloons past 200 lines).
Append 2 bullet finali:

```markdown
- **Snapshot UNVERIFIED:** non-deterministic test output (3 PRE runs differ). Do not proceed with refactor. Report flakiness; suggest investigating test cleanup or creating override file.
- **Test-cmd missing:** `.claude/test-cmd` absent. STOP, defer to user to deploy test-cmd before refactor.
```

Notes:
- NON modificare frontmatter (name, description, tools, model, color).
- NON modificare `## When to invoke` (3 bullet).
- NON modificare `## Core Responsibilities` (5 numbered points, ma il bullet "Run the
  existing test suite before and after" è ora implicato dal nuovo Process step 1/6.
  Decisione plan: lascia il bullet così com'è — è una descrizione di responsabilità,
  non un duplicato del Process step).
- NON modificare `## Quality Standards`.
- NON modificare `## Output Format`.
- Anchor literals (per harness Task 7):
  - `Snapshot Harness Integration` → H2 heading nel blocco §4.2.
  - `refactor-snapshot` → literal della reference path `~/.claude/skills/refactor-snapshot/`
    nel blocco §4.2 (prima riga del body section).
- Lingua: sezione in inglese (system prompt agent = code/contract, ereditato dal
  refactorer.md esistente che è all-English). Allineato a regola globale.
- Backup raccomandato pre-edit: `cp ~/.claude/agents/refactorer.md
  ~/.claude/agents/refactorer.md.bak-2026-05-20` (la patch è sostitutiva su Process
  section).

#### Verify

```bash
bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh; echo "exit=$?"
```
Expected: tutti i 43 anchor ancora `PASS`; le 2 nuove check Task-7 ora entrambe `PASS`
(`refactorer.md: snapshot integration section present` + `refactorer.md:
refactor-snapshot skill reference present`); summary `PASS=45 FAIL=0`, exit 0.
**TARGET FINALE RAGGIUNTO (harness PASS=45).**

```bash
grep -c '^## Snapshot Harness Integration$' ~/.claude/agents/refactorer.md && grep -c '## Process$' ~/.claude/agents/refactorer.md && grep -c 'refactor-snapshot' ~/.claude/agents/refactorer.md
```
Expected: `1`, `1`, `≥3` (1 section heading, 1 Process heading, 3+ reference (heading
content + Process step 2 + Process step 5 + Process step 6 + edge case = 5+
matches). Conferma che l'inserzione è singola e nel posto giusto.

- [ ] **Step 1: Backup refactorer.md** — `cp ~/.claude/agents/refactorer.md
  ~/.claude/agents/refactorer.md.bak-2026-05-20`.

- [ ] **Step 2: Replace `## Process` section** — edit refactorer.md per sostituire le
  6 righe esistenti (25-31) con le 8 numbered points §4.1.

- [ ] **Step 3: Append `## Snapshot Harness Integration` section** — insert tra fine
  Process e `## Quality Standards`.

- [ ] **Step 4: Append 2 bullet a `## Edge Cases`** — append in coda alla sezione
  esistente.

- [ ] **Step 5: Spot-check direct grep** — vedi verify command sopra.

- [ ] **Step 6: Harness re-run (target finale)**

Verify command:
```bash
bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh; echo "exit=$?"
```
Expected: `PASS=45 FAIL=0`, exit 0.

- [ ] **Step 7: Checkpoint** — refactorer.md patchato, snapshot harness integrato nel
  Process, harness verde a `PASS=45`. **Feature è live-effective al prossimo dispatch
  organico del `refactorer` agent.** TodoWrite update.

**Stima tempo:** 15 min.

---

### Task 5: ADR + spec status sync

**Files:**
- Modify: `docs/architecture/ADR-0002-refactor-snapshot-harness.md` (status line)
- Modify: `docs/superpowers/specs/2026-05-20-refactor-snapshot-harness-design.md`
  (status line)

**Red phase:** ADR riga 3 dice `**Status:** Proposed — 2026-05-20`. Spec riga 3 dice
`**Stato:** approvato (post-ADR) — pronto per writing-plans`. Inspectional grep:
```bash
grep '^\*\*Status:\*\*' docs/architecture/ADR-0002-refactor-snapshot-harness.md
grep '^\*\*Stato:\*\*' docs/superpowers/specs/2026-05-20-refactor-snapshot-harness-design.md
```
Mostrano stato pre-implementazione.

**Green phase (edit concreto):**

1. In `docs/architecture/ADR-0002-refactor-snapshot-harness.md` sostituisci riga 3:
   - Da: `**Status:** Proposed — 2026-05-20`
   - A: `**Status:** Accepted — 2026-05-20 (implemented via plan 2026-05-20-refactor-snapshot-harness.md; harness PASS=45; skill self-test PASS=10)`

2. In `docs/superpowers/specs/2026-05-20-refactor-snapshot-harness-design.md`
   sostituisci riga 3:
   - Da: `**Stato:** approvato (post-ADR) — pronto per writing-plans`
   - A: `**Stato:** implementato — 2026-05-20 (harness review-triage-fix PASS=45; skill self-test PASS=10; dispatch organico del refactorer validerà fedeltà LLM al contract 8-step, vedi Open questions ADR §4.4)`

Notes:
- Solo modifica a status line, no altro contenuto modificato. Mantiene il resto dei due
  deliverable integro.
- "Accepted" in ADR convenzionale (ADR-MADR template: Proposed → Accepted | Deprecated
  | Superseded).

- [ ] **Step 1: Edit ADR-0002 status line** — applica la sostituzione 1.

- [ ] **Step 2: Edit spec status line** — applica la sostituzione 2.

- [ ] **Step 3: Verify both statuses updated**

Verify command:
```bash
grep '^\*\*Status:\*\*' /Users/stefanoferri/Developer/vibe-coding-system/docs/architecture/ADR-0002-refactor-snapshot-harness.md && grep '^\*\*Stato:\*\*' /Users/stefanoferri/Developer/vibe-coding-system/docs/superpowers/specs/2026-05-20-refactor-snapshot-harness-design.md
```
Expected: entrambe le righe mostrano il nuovo stato `Accepted` / `implementato`.
Nessun residuo di `Proposed` / `approvato (post-ADR)`.

- [ ] **Step 4: Checkpoint** — deliverable doc allineati a "implemented". TodoWrite
  update.

**Stima tempo:** 3 min.

---

### Task 6: Memory entry — new project file

**Files:**
- Create: `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/project_refactor-snapshot-harness.md`

**Red phase:** il file non esiste. Verify pre-edit:
```bash
ls ~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/project_refactor-snapshot-harness.md 2>&1
```
Expected: `No such file or directory`.

**Green phase (edit concreto):** crea il nuovo memory file con questo body:

```markdown
# Refactor snapshot harness

**Stato:** DEPLOYED LIVE 2026-05-20 in `~/.claude/skills/refactor-snapshot/` (skill nuova: SKILL.md + capture.sh + diff.sh + self-test) + `~/.claude/agents/refactorer.md` (Process 8-step + Snapshot Harness Integration section) + 2 anchor in `~/.claude/skills/review-triage-fix/tests/run-tests.sh`.

**Cosa:** skill bash 3.2-clean che cattura output testuale (stdout/stderr/exit-code) del test command `.claude/test-cmd` pre/post refactor, SHA256-hash entrambe, confronta. Diff non-zero → FAIL, refactorer abort. Determinism check via 3 PRE run consecutivi (UNVERIFIED se SHA256 differ). Override esplicito user-only via `.claude/refactor-snapshot-override` (REASON+SCOPE+EXPIRES).

**Razionale:** il refactorer era il sub-agent meno usato perché non c'era garanzia empirica di behavior-preservation (green→green è proxy debole). Snapshot harness *è* la garanzia, deterministica e ispezionabile. Triple-angle coverage del rischio "code change non corrisponde a intent": ADR-0001 (coder pre-flight classifier) + v1.2 (reviewer Add+Remove triage) + ADR-0002 (refactorer post-edit snapshot).

**Layer-stack:**
1. Primary: skill `~/.claude/skills/refactor-snapshot/` (capture.sh + diff.sh).
2. Secondary: green→green test check esistente nel refactorer.md `## Core Responsibilities` step 1 (invariato).
3. Tertiary safety net: review-triage-fix v1.2 Add+Remove rule + ADR-0001 pattern-drift check del reviewer (NON modificati, ortogonali — il refactor che cambia comportamento può comunque essere riassorbito a triage se il coder lo riapplica in cycle successivo).

**Harness:**
- `~/.claude/skills/review-triage-fix/tests/run-tests.sh` PASS=43 (post ADR-0001) → PASS=45 (+2 anchor `refactorer.md: snapshot integration section present` + `refactorer.md: refactor-snapshot skill reference present`).
- `~/.claude/skills/refactor-snapshot/tests/run-tests.sh` self-test PASS=10 FAIL=0 (10 assertion: SKILL.md frontmatter, scripts present+exec, capture missing test-cmd, capture bad arg, capture green, capture red, diff identical, diff divergent stdout, diff override).

**Cross-file structural anchor:** è la 2ª volta che il harness review-triage-fix legge un file agent (la 1ª è `coder.md` da ADR-0001). Pattern stabilito: il harness review-triage-fix ha autorità sulla qualità degli agent che dispatcha.

**Deliverable:**
- ADR: `docs/architecture/ADR-0002-refactor-snapshot-harness.md` (Accepted 2026-05-20).
- Spec: `docs/superpowers/specs/2026-05-20-refactor-snapshot-harness-design.md` (implementato 2026-05-20).
- Plan: `docs/superpowers/plans/2026-05-20-refactor-snapshot-harness.md` (TDD 8 task, v1.0).

**Validazione pending:**
- Hit-rate compliance (>95% target) — il refactorer invoca effettivamente capture/diff.
- FAIL rate (atteso 5-15%) — quanti refactor genuinamente cambiano behavior.
- UNVERIFIED rate (sweet spot <20%) — quanti progetti pilota hanno test flaky.
- Override usage rate (sweet spot 5-15%).
- Delega rate Stefano → refactorer post-deploy (outcome cognitivo, non metrica deterministica).
Vedi ADR §4.4 (Open questions).

**Subsume / supersede:**
- NON subsume `feedback_micropiano-refactor-cleanup` (RESOLVED 2026-05-20 da v1.2 + ADR-0001). Il snapshot harness è additivo al layer-stack triple-angle.
- Si lega architetturalmente a:
  - `project_swarm-testcmd` (riusa contract `.claude/test-cmd` + TOFU + 3-tier).
  - `feedback_bash32-constraint` (skill 3.2-clean by construction).
  - ADR-0001 coder pre-flight classifier (ortogonale, stesso meta-problema).

**Invariante HARD:**
- Anchor preservation review-triage-fix harness: PASS≥45 in ogni futuro change. Mai scendere sotto 43 (ADR-0001 baseline) o 41 (v1.2 baseline).
- Anchor preservation refactor-snapshot self-test: PASS=10 FAIL=0 in ogni futuro change.
- Coexistenza ortogonale: ADR-0001 sezione `## Pre-flight Pattern Classifier` in coder.md NON va rimossa/modificata. Item 5 `Pattern-drift check` in reviewer.md NON va modificato. Regola `Add+Remove rule` in review-triage-fix SKILL.md NON va modificata.
- Bash 3.2: tutti gli script live in `~/.claude/skills/refactor-snapshot/` 3.2-clean (literal `grep -q --` + ok/bad helpers, no assoc array, no mapfile).
- HITL gate: override file `.claude/refactor-snapshot-override` solo user-created. Il refactorer NON lo crea mai.
```

Notes:
- Stile coerente con `project_swarm-testcmd.md`, `project_approve-testcmd-path-case.md`,
  `project_coder-preflight-classifier.md` (memory esistenti): titolo h1 + stato leading
  + sezioni chiare + invariant esplicite + cross-link a memory correlate.
- Lingua italiano (memory layer interno, allineato a `MEMORY.md` esistente).
- No path absolute fragile: i riferimenti file usano `~/.claude/` (portable) e path
  relativi al repo per i deliverable.

- [ ] **Step 1: Create the memory file** — `Write` del file
  `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/project_refactor-snapshot-harness.md`
  con il content sopra.

- [ ] **Step 2: Verify creation**

Verify command:
```bash
test -f ~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/project_refactor-snapshot-harness.md && head -3 ~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/project_refactor-snapshot-harness.md
```
Expected: exit 0; output mostra titolo `# Refactor snapshot harness`, riga blank,
riga stato `DEPLOYED LIVE 2026-05-20`.

- [ ] **Step 3: Checkpoint** — memory entry creato, deploy state catturato. TodoWrite
  update.

**Stima tempo:** 5 min.

---

### Task 7: MEMORY.md index update

**Files:**
- Modify: `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/MEMORY.md`
  (append nuova riga in sezione `## Project`)

**Red phase:** baseline `MEMORY.md` ha N voci in `## Project` (4 originali + 1
aggiunto da ADR-0001 deploy 2026-05-20 = 5 voci attese). Nessuna voce per "refactor
snapshot harness". Verify pre-edit:
```bash
grep -c 'refactor-snapshot' ~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/MEMORY.md
```
Expected: `0`.

**Green phase (edit concreto):** append una nuova riga alla sezione `## Project` come
ultima voce (dopo l'eventuale entry coder-preflight-classifier aggiunta da ADR-0001),
immediatamente prima della blank line + `## Feedback`. Nuova riga:

```markdown
- [Refactor snapshot harness](project_refactor-snapshot-harness.md) — **DEPLOYED 2026-05-20**: skill `refactor-snapshot` (capture/diff bash 3.2) gate behavior-preservation per `refactorer` agent; triple-angle ortogonale con ADR-0001 + v1.2; harness review-triage-fix PASS=45, skill self-test PASS=10
```

Notes:
- Stile identico alle voci esistenti: dash-prefix bullet + `[Title](file.md)` +
  em-dash + description + clauses semicolon-separated + closing senza punto finale.
- Posizionamento alla fine della sezione `## Project` per ordine cronologico-deploy
  (2026-05-20 ADR-0001 coder-preflight-classifier → 2026-05-20 ADR-0002
  refactor-snapshot-harness; il snapshot è l'evento più recente).
- Non toccare le voci esistenti. Edit additive-only.

- [ ] **Step 1: Append the new row** — edit `MEMORY.md` per inserire la nuova riga in
  `## Project`.

- [ ] **Step 2: Verify update**

Verify command:
```bash
grep -c 'refactor-snapshot' ~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/MEMORY.md
```
Expected: `1` (la nuova riga; sale da 0 a 1).

- [ ] **Step 3: Final harness re-run (regressione end-to-end)**

Verify command:
```bash
bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh; echo "exit=$?"
bash ~/.claude/skills/refactor-snapshot/tests/run-tests.sh; echo "exit=$?"
```
Expected:
- review-triage-fix harness: `PASS=45 FAIL=0`, exit 0.
- refactor-snapshot self-test: `PASS=10 FAIL=0`, exit 0.

Conferma che i task 1-6 lasciano entrambi i harness verdi, e che il task 7 (solo doc)
non ha effetto.

- [ ] **Step 4: Checkpoint** — index aggiornato, ricerca memoria futura troverà il
  snapshot harness. TodoWrite update.

**Stima tempo:** 4 min.

---

### Task 8: Append architect note (cross-cycle pattern log)

**Files:**
- Modify: `docs/agent-notes/architect.md` (append nuova sezione per ADR-0002)

**Red phase:** `docs/agent-notes/architect.md` esiste con 1 sezione (ADR-0001) +
"Pattern riusabili per ADR futuri" footer. Nessuna sezione per ADR-0002. Verify
pre-edit:
```bash
grep -c 'ADR-0002' /Users/stefanoferri/Developer/vibe-coding-system/docs/agent-notes/architect.md
```
Expected: `0`.

**Green phase (edit concreto):** append nuova sezione TRA "2026-05-20 — ADR-0001
coder pre-flight pattern classifier" (sezione esistente) e "## Pattern riusabili per
ADR futuri" (footer esistente). Insert:

```markdown
## 2026-05-20 — ADR-0002 refactor snapshot harness

- **Pattern adottato:** behavior-preservation di un refactor è strumentabile in modo *stack-agnostic* tramite SHA256 di output testuale (stdout/stderr/exit-code) del test command già contrattualizzato in `.claude/test-cmd`. AST signature / call graph / pure function snapshot sono proxy fragili o stack-locked; output testuale è il proxy diretto del comportamento osservabile esterno.
- **Three-state outcome harness (PASS/FAIL/UNVERIFIED):** distinguere bug del refactor da test non-deterministico è il discriminator chiave. Determinism check via N=3 run consecutivi del pre-snapshot; SHA256 stabile → drift legit FAIL; SHA256 instabile → UNVERIFIED + override esplicito user-only.
- **Buy vs build su tooling snapshot:** in un sistema multi-stack (Python + Swift + JS) la scelta build (bespoke bash 3.2-clean) batte buy (pytest-snapshot, syrupy, jest snapshot, swift-snapshot-testing) per assenza di stack-lock + zero dipendenze. Pattern golden file è generic; bash 3.2 ne è l'implementazione minimale, allineata stilisticamente alla skill review-triage-fix.
- **Riuso del contract `.claude/test-cmd`:** la TOFU + 3-tier deploy 2026-05-19 (swarm-testcmd) è ora un asset architettonico riusabile. Qualunque feature multi-agente che richiede "esecuzione cross-stack di un comando user-defined" può consumare questo contract senza scaffolding. Pattern: prima di proporre un nuovo contract, verifica se uno esistente copre il caso.
- **Coexistenza ortogonale con ADR-0001 + v1.2:** quando una nuova feature attacca un meta-problema dello stesso famiglia ("code change non corrisponde a intent") da un terzo angolo (coder pre-flight / reviewer triage / refactorer post-edit), il design corretto è esplicitare ortogonalità → 3 agent diversi, 3 contract diversi, 3 layer di defense indipendenti. Anti-pattern sarebbe consolidare in un singolo super-mechanism (perderebbe granularità ed enforcement specifico).
- **Cross-file anchor harness pattern (2ª istanza):** il harness review-triage-fix legge ora 3 file (`SKILL.md` + `coder.md` + `refactorer.md`). Il pattern "skill harness ha autorità sulla qualità degli agent che la skill dispatcha" è confermato come pattern stabile, non one-off. Estendibile a `debugger.md` / `tester.md` se feature future richiederanno structural anchor.
- **HITL gate per override esplicito:** quando un harness deterministico ha un escape hatch (override), il file di override è user-only (allineato CLAUDE.md global "HITL gate sempre prima di ... eliminazioni permanenti"). L'agent NON crea mai il file da sé; può solo *suggerire* la creazione nel report di FAIL. Pattern riusabile per future feature con escape hatch.
- **Bash 3.2 vincolo invariante:** la skill `refactor-snapshot` (capture.sh, diff.sh, run-tests.sh) è 3.2-clean by construction (literal `grep -q --` + `ok`/`bad` helpers + `command -v` detection + `mktemp -d` isolation). Nessun assoc array, nessun mapfile, nessun `${v^^}`, nessun `<()`. Pattern già consolidato dai 45 anchor del harness review-triage-fix.
- **Plan TDD agnostico al harness runtime:** l'architect NON pre-dichiara PASS/FAIL/UNVERIFIED per step nei plan futuri del refactorer. Il harness è runtime, dal refactorer, per-cycle. Pre-dichiarazione cold dell'architect maschera drift legittimi. Analogo a pattern ADR-0001 (architect agnostico al classifier).
- **No backwards-compat shim per system prompt edits:** modifiche a `refactorer.md` (Process section sostituita pulita) seguono il pattern ADR-0001. Nessun "vecchio contract Process" da deprecare.
```

Notes:
- Stile coerente con la sezione ADR-0001 esistente (bullet list di pattern durevoli +
  invariant + razionali).
- Aggiunte 10 osservazioni cross-cycle (pattern riusabili per ADR futuri).

- [ ] **Step 1: Append architect note section** — edit
  `docs/agent-notes/architect.md` per inserire la nuova sezione tra ADR-0001 sezione
  e "Pattern riusabili" footer.

- [ ] **Step 2: Verify**

Verify command:
```bash
grep -c '^## 2026-05-20 — ADR-0002' /Users/stefanoferri/Developer/vibe-coding-system/docs/agent-notes/architect.md
```
Expected: `1`.

- [ ] **Step 3: Checkpoint** — architect note log aggiornato. **Implementazione
  completa.** TodoWrite update.

**Stima tempo:** 5 min.

---

## Harness expected delta

| Stato | review-triage-fix PASS | refactor-snapshot self-test PASS | FAIL | Note |
|---|---|---|---|---|
| Baseline (post ADR-0001, verificato 2026-05-20) | 43 | n/a (skill non esiste) | 0 | 17 g-anchor v1.0 + 1 frontmatter-name + 1 description + 1 v1.2 Add+Remove + 2 ADR-0001 coder.md = 43 |
| Post-Task-1 (red phase) | 43 | n/a | 2 | Nuovo blocco Task 7 emette 2 FAIL (`refactorer.md: snapshot integration section missing`, `refactorer.md: refactor-snapshot skill reference missing`). Exit 1. |
| Post-Task-2 (skill scripts created) | 43 | n/a (self-test non ancora scritto) | 2 | Nessun change al review-triage-fix harness (refactorer.md non ancora patchato). |
| Post-Task-3 (skill self-test) | 43 | 10 | 2 (review-triage-fix) + 0 (self-test) | Self-test verde. Review-triage-fix ancora red (refactorer.md non patchato). |
| Post-Task-4 (refactorer.md patch, target) | 45 | 10 | 0 | I 2 nuovi anchor passano (literal presenti in refactorer.md). Exit 0. **TARGET FINALE.** |
| Post-Task-5 (status doc sync) | 45 | 10 | 0 | No change ai harness (solo doc edit). |
| Post-Task-6 (memory entry) | 45 | 10 | 0 | No change ai harness (solo memory file). |
| Post-Task-7 (MEMORY.md index) | 45 | 10 | 0 | No change ai harness (solo memory file). |
| Post-Task-8 (architect note) | 45 | 10 | 0 | No change ai harness (solo agent-notes file). **Stato finale invariato.** |

**Delta totale dichiarato:** 
- review-triage-fix harness: PASS=43 → PASS=45 (+2 anchor in nuovo blocco Task 7, entrambi su `refactorer.md`).
- refactor-snapshot self-test (new): PASS=10 FAIL=0.

**Anchor preservation invariante:** in nessun task viene rimosso o alterato uno dei 43 anchor post-ADR-0001. Il blocco Task 7 è inserito tra l'ultimo anchor di Task 6 (riga 149) e la summary line (riga 151). I 43 anchor restano nelle stesse righe; la summary line si sposta di +5 righe (3 righe content + 2 blank di separazione).

**Cumulative test post-deploy (sanity, opzionale):**
```bash
bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh 2>&1 | grep -c '^PASS:'
# Expected: 45
bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh 2>&1 | grep -c '^FAIL:'
# Expected: 0
bash ~/.claude/skills/refactor-snapshot/tests/run-tests.sh 2>&1 | grep -c '^PASS:'
# Expected: 10
bash ~/.claude/skills/refactor-snapshot/tests/run-tests.sh 2>&1 | grep -c '^FAIL:'
# Expected: 0
```

---

## Risk summary

- **R1 — LLM drift sul contract Process 8-step.** Il `refactorer` agent potrebbe omettere la chiamata a capture.sh/diff.sh in stress conditions (context pieno, prompt lungo, refactor "ovvio"). Mitigato da: (a) anchor harness `PASS=45` che protegge la presenza della sezione `## Snapshot Harness Integration` nel system prompt (rimozione accidentale futura → red harness); (b) coexistenza con green→green check esistente (preserved invariant); (c) il fail mode cycle-2 pricing-markup-cli viene comunque catturato a triage dal review-triage-fix v1.2 Add+Remove rule. Severity: **medium**. Validabile solo nell'uso organico (ADR §4.4 open question).
- **R2 — Test non-deterministici producono UNVERIFIED spam.** Progetti pilota con test che includono timestamp/random ID/path assoluti producono `UNVERIFIED` ad ogni refactor cycle. Il refactorer abortisce; user deve creare override o pulire test. Friction. Mitigazione: override file documentato + suggerito nel report di UNVERIFIED. Severity: **medium**. Validabile in pilota su 3-5 progetti.
- **R3 — Reflection / dispatch dinamico false negative.** Refactor che cambia comportamento di caller indiretti via reflection passa snapshot perché blast radius via grep non lo cattura. Mitigazione: override `RFS_FULL=1` esiste ma richiede giudizio del refactorer (rilevazione reflection nei file modificati). Possibile falso negativo se refactorer non rileva reflection. Severity: **medium**. Validabile post-pilota con review dei MAJOR.
- **R4 — Anchor breakage.** Inserimento accidentale del blocco Task 7 in posizione errata potrebbe rompere il count finale. Mitigazione: il plan specifica posizione esatta (tra riga 149 e riga 151, post-coder.md anchor, pre-summary). Verify Task 1 Step 2 confronta `PASS=43 FAIL=2` esatto (non `PASS=41 FAIL=4` che indicherebbe breakage di Task 6). Severity: **low**.
- **R5 — Bash 3.2 trap nei nuovi script.** Tre nuovi script bash (capture.sh, diff.sh, self-test/run-tests.sh) + estensione del harness review-triage-fix. Rischio di slip 3.2 (assoc array accidentale, mapfile da reflex). Mitigazione: bash 3.2-clean by construction documentato in plan; Step 2.4 e Step 3.3 includono `bash -n` syntax check; self-test stesso esegue gli script in macOS bash 3.2.57 (memory `feedback_bash32-constraint.md`). Severity: **low**.
- **R6 — Timeout vs progetti slow.** Default `RFS_TIMEOUT=120` può essere insufficiente per progetti con test suite >2 min. Mitigazione: env var configurabile; refactorer può raise timeout via dispatch instruction. Severity: **low** (configurable runtime).
- **R7 — Coexistenza confusion / regressione ortogonale.** Possibile drift cognitivo futuro: "il snapshot harness sostituisce ADR-0001 o v1.2?". HARD invariante (ADR §1, spec §3.3, memory entry Task 6, agent-note Task 8): NO. I tre meccanismi sono ortogonali e coesistono. Mitigazione: invariante esplicitata in 4 luoghi (ADR, spec, memory, agent-note). Severity: **low** (governance issue, non runtime).
- **R8 — Doc fragility.** Status line sync (Task 5) e memory entries (Task 6-7) sono doc-only; se un futuro coder riassorbe il snapshot harness nel core senza aggiornare MEMORY.md, il search-by-keyword nel memory layer perde la voce. Mitigazione: convenzione "ogni feature merge aggiorna MEMORY.md" (vedi memory esistenti). Severity: **low**.

## HITL gate

Nessun gate hard richiesto dal deploy stesso (additivo, no destructive, no hook live, no settings.json, no schema DB). Le decisioni HITL del `~/.claude/CLAUDE.md` global (`commit, push, deploy, modifica schema DB, eliminazioni permanenti`) non si applicano: questo è un edit di system prompt agent + skill nuova + harness anchor + doc, senza commit (repo doc senza git, `~/.claude/` senza git).

Validazione operativa POST-deploy è osservativa, non bloccante: il primo dispatch organico del `refactorer` agent post-deploy fornirà evidenza empirica della hit-rate del contract 8-step. Se hit-rate <90% sui primi 10 cycle refactor, considera amendment v1.1 al system prompt (es. rinforzo del wording "MUST" sui step 2/5/6, esempi extra, etc).

HITL gate runtime (non parte di questo plan, ma documentato per chiarezza):
- **Creazione `.claude/refactor-snapshot-override`** in un progetto target: solo user-action. Il refactorer NON crea mai questo file.
- **Decision on FAIL outcome:** quando `diff.sh` exit 1 (refactor cambia comportamento), il refactorer abortisce e chiede al user di decidere (revert vs accept come intentional). HITL gate operativo.
