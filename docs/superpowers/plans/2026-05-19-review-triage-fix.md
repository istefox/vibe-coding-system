# review-triage-fix Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `review-triage-fix` workflow skill that, in one manual invocation, runs `reviewer → triage → route-fix (sequential) → re-review → recap → STOP`, reusing the deployed `reviewer`/`debugger`/`refactorer`/`coder` agents and the `.claude/test-cmd` gate, with 4 circuit breakers and a decision-grade per-cycle recap.

**Architecture:** A markdown workflow (`SKILL.md`) carries the LLM orchestration (dispatch, triage judgement, routing, recap assembly, STOP-without-commit). Three small bash+jq helper scripts carry the genuinely deterministic, fixture-testable scaffolding from design §10: `verify.sh` (re-uses the project's `.claude/test-cmd`, exactly as `stop-gate.sh` resolves it), `weakening-scan.sh` (heuristic anti-test-weakening detector over a unified diff), `triage-state.sh` (cross-cycle `.triage-fix-last.json` diff + commit + gitignore). Helpers are unit-tested via a self-contained harness; the end-to-end LLM pipeline is validated once, manually, on the pilot.

**Tech Stack:** bash, `jq`, `shasum`/`sha256sum`, `awk`, `git` (optional, for gitignore + diff source); Claude Code skill (`~/.claude/skills/<name>/SKILL.md`) invoked manually from the orchestrator session.

**Spec:** `docs/superpowers/specs/2026-05-19-review-triage-fix-design.md` (approved at brainstorming).

**v1.1 (2026-05-19, post-pilot):** SKILL.md updated based on the partial pilot
on `pricing-markup-cli` (interrupted at fix 5/9, ~40 min wall-clock projected):
- **Snapshot pattern made universal** (Step 3): pre-fix snapshot+refresh is
  required for per-fix attribution; `git diff` alone is insufficient because
  it accumulates prior fixes' changes. The v1 wording "non-git only" misled the
  orchestrator (which correctly chose snapshot anyway for safety).
- **NIT batching made mandatory** (Step 2 → Step 3): all NITs go to a single
  `coder` dispatch as a list, not N dispatches. Dominant cost-reducer.
- **Micro-piano discipline tightened** (Step 2): 2-3 lines max, no multi-paragraph
  specs. The v1 pilot saw a `coder` dispatch use 40k tokens for a small task.
- **Parallel batch mode** flagged as future-work (v2): requires upstream
  `isolation: worktree` on `coder.md`; without it, parallel dispatches share
  the live filesystem → conflicts. NOT enabled in v1.1.

Helper scripts and harness unchanged through v1.1 (40/40 PASS preserved); v1.2 patch adds 1 anchor → 41/41 PASS (see "v1.2" section below).

**v1.2 (2026-05-20, Add+Remove rule):** SKILL.md patched in Step 2 to add an
explicit "Add+Remove rule (for SUBSTITUTION fixes)" paragraph after the
"Micro-piano discipline" bullet. Root cause of the M-1 MAJOR observed in
`pricing-markup-cli` cycle 2 (2026-05-19): the M-3 fix asked the coder to
"add an autouse fixture" without explicitly listing the existing duplicate
fixture to remove → coder acted only-additively → re-review flagged the
duplication. The new rule mandates `Add:` AND `Remove: <path:line>` lists
for substitution fixes (replace pattern A with pattern B); purely additive
fixes still need only `Add:`. Harness +1 anchor (`Add+Remove rule`),
cumulative PASS=41. No helper script touched. Spec:
`docs/superpowers/specs/2026-05-20-review-triage-fix-v1.2-addremove-design.md`.
Memory: `feedback_micropiano-refactor-cleanup.md` (now RESOLVED).

---

## Environment notes (read first)

- **No git in this repo and in `~/.claude/`.** Writing-plans "commit" = **checkpoint**: harness green + TodoWrite update + short report. There is no live-global HITL migration here (unlike swarm-testcmd): the skill is purely additive — it changes no existing agent, hook, or `settings.json`. Adding the skill dir is inert until the user invokes `review-triage-fix`.
- **Helpers reuse, never re-implement, the gate's contract.** `verify.sh` duplicates the ~10-line upward project-root search + the exact `awk` test-cmd parser from `~/.claude/hooks/stop-gate.sh:35-46` and its `run_with_timeout` from `:64-75`. This duplication is the **established convention** here (`stop-gate.sh` and `approve-test-cmd.sh` already duplicate the same resolver); coupling a skill helper to a hook's internals would be worse. Spec §11 "riuso, coerenza" is satisfied by reusing the same `.claude/test-cmd` *file and semantics*, not by sourcing the hook.
- **Helpers are reporters, not gates.** They always `exit 0` (except usage errors) and put the verdict on stdout as a leading token. The skill (LLM) reads stdout and enforces circuit breakers. No helper ever reverts, commits, or blocks (design §7-B "nessun auto-revert", §11 "nessun commit dentro la skill").
- **Determinism boundary.** Deterministic + fixture-tested: test-cmd run/classify, unified-diff weakening heuristic, cross-cycle state diff + stable finding ID. Non-deterministic (LLM, validated manually on pilot only): dispatching agents, reading the reviewer's markdown into the normalized finding TSV, triage classification per §5, recap narrative. Design §10 explicitly accepts this split.
- **Skill-local test env vars:** the harness sets `RTF_TEST_TIMEOUT` (verify.sh timeout, default 120) and uses a `mktemp -d` workspace; it never touches real project state or the global trust registry.
- **bash 3.2 constraint (discovered during execution, Task 3).** The system `/bin/bash` is 3.2.57 (macOS default; confirmed `bash --version`). Helpers run under it via `#!/bin/bash`. **No `declare -A` / associative arrays** (bash 4.0+ only) — `triage-state.sh` therefore uses temp-file maps (`id<TAB>status` lines + `grep -m1`/`grep -qx`) instead. BSD `grep -m1` is available and used. Any re-implementation MUST stay bash-3.2-clean: no assoc arrays, no `mapfile`/`readarray`, no `${var^^}`. (Tasks 1/2 were already 3.2-clean.)
- **Portability (spec §11):** the whole `~/.claude/skills/review-triage-fix/` dir is copy-portable. `SKILL.md` references helpers by `$HOME/.claude/skills/review-triage-fix/scripts/<name>.sh` (a fixed, documented location; the dir moves as a unit).

## File structure

All paths are live (`~/.claude/`), since a skill is only effective when deployed there; there is no staging mirror because the skill is additive and inert until invoked (contrast swarm-testcmd, which mutated a live hook).

- Create `~/.claude/skills/review-triage-fix/SKILL.md` — the workflow the orchestrator follows: pre-flight, dispatch reviewer, triage per §5, sequential route-fix to debugger/refactorer/coder, post-fix `verify.sh` + `weakening-scan.sh`, 4 circuit breakers, re-review, recap per §8, STOP. One responsibility: orchestration prose.
- Create `~/.claude/skills/review-triage-fix/scripts/verify.sh` — resolve `<root>/.claude/test-cmd` (stop-gate semantics) and run it with timeout → first stdout token `PASS` | `FAIL\texit=N\t<tail>` | `UNVERIFIED\t<reason>`. One responsibility: verification reporting.
- Create `~/.claude/skills/review-triage-fix/scripts/weakening-scan.sh` — read a unified diff on stdin, apply the §7-B heuristic → `CLEAN` or `WEAKENED\t<file>\t<reason>` lines. One responsibility: anti-weakening detection (report-only).
- Create `~/.claude/skills/review-triage-fix/scripts/triage-state.sh` — `diff`/`commit` subcommands over `<root>/.claude/.triage-fix-last.json`: stable finding ID, cross-cycle NEW/STILL-OPEN/REGRESSED/RESOLVED, counts, convergence line, gitignore handling. One responsibility: cross-cycle state.
- Create `~/.claude/skills/review-triage-fix/tests/run-tests.sh` — self-contained harness (`ok`/`bad` convention mirroring `~/.claude/hooks/tests/run-hook-tests.sh`), isolated `mktemp -d` workspace.

`docs/superpowers/specs/2026-05-19-review-triage-fix-design.md` line 4 (`Stato:`) is updated to `approvato → piano` in Task 6 only.

---

### Task 1: harness skeleton + `verify.sh`

**Files:**
- Create: `~/.claude/skills/review-triage-fix/tests/run-tests.sh`
- Create: `~/.claude/skills/review-triage-fix/scripts/verify.sh`

- [ ] **Step 1: Write the failing test** — create `~/.claude/skills/review-triage-fix/tests/run-tests.sh` with exactly:

```bash
#!/bin/bash
# review-triage-fix helper unit harness. Isolated; never touches real state.
set -u
SK="$HOME/.claude/skills/review-triage-fix"
S="$SK/scripts"
TMP="$(mktemp -d)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

# --- Task 1: verify.sh ---
# 1a: no .claude/test-cmd → UNVERIFIED
PA="$TMP/v_absent"; mkdir -p "$PA"
O=$(bash "$S/verify.sh" "$PA" 2>/dev/null); r=$?
[ $r -eq 0 ] && [ "${O%%$'\t'*}" = "UNVERIFIED" ] && ok "verify: absent test-cmd → UNVERIFIED" || bad "verify absent"
# 1b: NONE → UNVERIFIED (opt-out)
PN="$TMP/v_none/.claude"; mkdir -p "$PN"; printf 'NONE\n' > "$PN/test-cmd"
O=$(bash "$S/verify.sh" "$TMP/v_none" 2>/dev/null)
[ "${O%%$'\t'*}" = "UNVERIFIED" ] && ok "verify: NONE → UNVERIFIED" || bad "verify NONE"
# 1c: empty (comments only) → UNVERIFIED
PE="$TMP/v_empty/.claude"; mkdir -p "$PE"; printf '# only a comment\n\n' > "$PE/test-cmd"
O=$(bash "$S/verify.sh" "$TMP/v_empty" 2>/dev/null)
[ "${O%%$'\t'*}" = "UNVERIFIED" ] && ok "verify: empty → UNVERIFIED" || bad "verify empty"
# 1d: green → PASS
PG="$TMP/v_grn/.claude"; mkdir -p "$PG"; printf 'true\n' > "$PG/test-cmd"
O=$(bash "$S/verify.sh" "$TMP/v_grn" 2>/dev/null)
[ "$O" = "PASS" ] && ok "verify: green → PASS" || bad "verify green"
# 1e: red → FAIL + tail captured
PR="$TMP/v_red/.claude"; mkdir -p "$PR"; printf 'echo BOOMTAIL >&2; exit 3\n' > "$PR/test-cmd"
O=$(bash "$S/verify.sh" "$TMP/v_red" 2>/dev/null)
[ "${O%%$'\t'*}" = "FAIL" ] && echo "$O" | grep -q 'BOOMTAIL' && ok "verify: red → FAIL+tail" || bad "verify red"
# 1f: comment then real cmd → parsed (PASS)
PC="$TMP/v_cmt/.claude"; mkdir -p "$PC"; printf '# header\n\ntrue\n' > "$PC/test-cmd"
O=$(bash "$S/verify.sh" "$TMP/v_cmt" 2>/dev/null)
[ "$O" = "PASS" ] && ok "verify: comment+cmd → parsed" || bad "verify comment-parse"
# 1g: timeout → UNVERIFIED (never blocks the cycle)
PT="$TMP/v_to/.claude"; mkdir -p "$PT"; printf 'sleep 5\n' > "$PT/test-cmd"
O=$(RTF_TEST_TIMEOUT=1 bash "$S/verify.sh" "$TMP/v_to" 2>/dev/null); r=$?
[ $r -eq 0 ] && [ "${O%%$'\t'*}" = "UNVERIFIED" ] && ok "verify: timeout → UNVERIFIED" || bad "verify timeout"

echo "----"; echo "PASS=$PASS FAIL=$FAIL"; rm -rf "$TMP"
[ $FAIL -eq 0 ]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh`
Expected: every `verify:` check `FAIL` (script absent), final `PASS=0 FAIL=7`, non-zero exit.

- [ ] **Step 3: Write minimal implementation** — create `~/.claude/skills/review-triage-fix/scripts/verify.sh`:

```bash
#!/bin/bash
# review-triage-fix: verification reporter (NOT a gate). Reuses the project's
# .claude/test-cmd with stop-gate's exact resolution + parser. Always exits 0;
# the cycle status is the FIRST stdout token: PASS | FAIL | UNVERIFIED.
# Usage: verify.sh [start-dir]   (default: $PWD)
TMO="${RTF_TEST_TIMEOUT:-120}"; case "$TMO" in ''|*[!0-9]*) TMO=120;; esac
start="${1:-$PWD}"
[ -d "$start" ] || { printf 'UNVERIFIED\tstart-dir inesistente\n'; exit 0; }
start=$(cd "$start" 2>/dev/null && pwd) || { printf 'UNVERIFIED\tcd fallita\n'; exit 0; }
ROOT=""; d="$start"; i=0
while [ -n "$d" ] && [ "$i" -lt 40 ]; do
  [ -f "$d/.claude/test-cmd" ] && { ROOT="$d"; break; }
  [ "$d" = "/" ] && break
  d=$(dirname "$d"); i=$((i + 1))
done
[ -z "$ROOT" ] && { printf 'UNVERIFIED\tnessun .claude/test-cmd\n'; exit 0; }
TCF="$ROOT/.claude/test-cmd"
CMD=$(awk '{ l=$0; sub(/^[ \t]+/,"",l); sub(/[ \t]+$/,"",l); if(l=="" || substr(l,1,1)=="#") next; print l; exit }' "$TCF" 2>/dev/null)
[ "$CMD" = "NONE" ] && { printf 'UNVERIFIED\ttest-cmd=NONE (opt-out)\n'; exit 0; }
[ -z "$CMD" ] && { printf 'UNVERIFIED\ttest-cmd vuoto\n'; exit 0; }
run_with_timeout() {  # $1=secs $2=cmdstring → rc; 124=timeout 125=cannot-run
  if command -v timeout >/dev/null 2>&1; then timeout "$1" bash -c "$2"; return $?
  elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$1" bash -c "$2"; return $?
  else
    bash -c "$2" & local p=$!
    ( sleep "$1"; kill -0 "$p" 2>/dev/null && kill -9 "$p" 2>/dev/null ) & local w=$!
    wait "$p" 2>/dev/null; local rc=$?
    kill -9 "$w" 2>/dev/null; wait "$w" 2>/dev/null
    [ "$rc" -eq 137 ] && return 124
    return "$rc"
  fi
}
OUT=$(mktemp)
run_with_timeout "$TMO" "cd $(printf %q "$ROOT") && ( $CMD )" >"$OUT" 2>&1
RC=$?
if [ "$RC" -eq 124 ] || [ "$RC" -eq 125 ] || [ "$RC" -eq 126 ] || [ "$RC" -eq 127 ]; then
  rm -f "$OUT"; printf 'UNVERIFIED\ttest non eseguibile/timeout (rc=%s)\n' "$RC"; exit 0
fi
if [ "$RC" -eq 0 ]; then rm -f "$OUT"; printf 'PASS\n'; exit 0; fi
TAIL=$(tail -c 600 "$OUT" 2>/dev/null | tr '\n' ' '); rm -f "$OUT"
printf 'FAIL\texit=%s\t%s\n' "$RC" "$TAIL"
exit 0
```

Then: `chmod +x ~/.claude/skills/review-triage-fix/scripts/verify.sh`

- [ ] **Step 4: Run test to verify it passes**

Run: `bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh`
Expected: 7 `PASS:` lines (`verify: absent…`, `NONE`, `empty`, `green`, `red+tail`, `comment+cmd`, `timeout`), final `PASS=7 FAIL=0`, exit 0.

- [ ] **Step 5: Checkpoint** — harness green; TodoWrite update. (No git: checkpoint = harness + report, no commit.)

---

### Task 2: `weakening-scan.sh`

**Files:**
- Create: `~/.claude/skills/review-triage-fix/scripts/weakening-scan.sh`
- Modify: `~/.claude/skills/review-triage-fix/tests/run-tests.sh` (append before the `echo "----"` summary line)

- [ ] **Step 1: Write the failing test** — insert before the `echo "----"; echo "PASS=$PASS FAIL=$FAIL"` line:

```bash
# --- Task 2: weakening-scan.sh ---
W="$S/weakening-scan.sh"
# 2a: clean non-test change → CLEAN
D=$(printf 'diff --git a/src/app.py b/src/app.py\n--- a/src/app.py\n+++ b/src/app.py\n@@ -1 +1 @@\n-x=1\n+x=2\n')
O=$(printf '%s\n' "$D" | bash "$W" 2>/dev/null)
[ "$O" = "CLEAN" ] && ok "weakening: clean src → CLEAN" || bad "weakening clean"
# 2b: assert removed in a test file → WEAKENED assert-removed
D=$(printf 'diff --git a/tests/test_x.py b/tests/test_x.py\n--- a/tests/test_x.py\n+++ b/tests/test_x.py\n@@ -1,3 +1,2 @@\n def test_a():\n-    assert foo() == 1\n+    foo()\n')
O=$(printf '%s\n' "$D" | bash "$W" 2>/dev/null)
echo "$O" | grep -q 'WEAKENED.*tests/test_x.py.*assert-removed' && ok "weakening: assert-removed" || bad "weakening assert"
# 2c: deleted test file → WEAKENED deleted-test-file
D=$(printf 'diff --git a/tests/test_y.py b/tests/test_y.py\ndeleted file mode 100644\n--- a/tests/test_y.py\n+++ /dev/null\n@@ -1,2 +0,0 @@\n-def test_y():\n-    assert True\n')
O=$(printf '%s\n' "$D" | bash "$W" 2>/dev/null)
echo "$O" | grep -q 'WEAKENED.*tests/test_y.py.*deleted-test-file' && ok "weakening: deleted-file" || bad "weakening deleted"
# 2d: skip added → WEAKENED skip/xfail-added
D=$(printf 'diff --git a/spec/foo.spec.js b/spec/foo.spec.js\n--- a/spec/foo.spec.js\n+++ b/spec/foo.spec.js\n@@ -1,2 +1,2 @@\n-it("works", () => { expect(x).toBe(1) })\n+it.skip("works", () => { expect(x).toBe(1) })\n')
O=$(printf '%s\n' "$D" | bash "$W" 2>/dev/null)
echo "$O" | grep -q 'WEAKENED.*foo.spec.js.*skip' && ok "weakening: skip-added" || bad "weakening skip"
# 2e: test fn removed, none added → WEAKENED test-removed-or-commented
D=$(printf 'diff --git a/tests/test_z.py b/tests/test_z.py\n--- a/tests/test_z.py\n+++ b/tests/test_z.py\n@@ -1,4 +1,1 @@\n-def test_z():\n-    assert g()\n+pass\n')
O=$(printf '%s\n' "$D" | bash "$W" 2>/dev/null)
echo "$O" | grep -q 'WEAKENED.*tests/test_z.py' && ok "weakening: test-removed" || bad "weakening test-removed"
# 2f: assert removed in NON-test file → ignored (CLEAN)
D=$(printf 'diff --git a/src/util.py b/src/util.py\n--- a/src/util.py\n+++ b/src/util.py\n@@ -1,2 +1,1 @@\n-    assert ok\n+    return\n')
O=$(printf '%s\n' "$D" | bash "$W" 2>/dev/null)
[ "$O" = "CLEAN" ] && ok "weakening: non-test assert ignored" || bad "weakening non-test"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh`
Expected: Task 1 still `PASS`; the 6 `weakening:` checks `FAIL` (script absent); non-zero exit.

- [ ] **Step 3: Write minimal implementation** — create `~/.claude/skills/review-triage-fix/scripts/weakening-scan.sh`:

```bash
#!/bin/bash
# review-triage-fix: anti-test-weakening detector (heuristic, report-only).
# Input: a unified diff on stdin. Output: "CLEAN" or one or more
#   WEAKENED<TAB><file><TAB><reason>
# Heuristic on purpose (design §7-B). No auto-revert. Always exits 0.
awk '
function is_test(p){ return (p ~ /(^|\/)tests?\//) || (p ~ /(^|\/)spec\//) \
  || (p ~ /test_[^\/]*\.[a-zA-Z]+$/) || (p ~ /_test\.[a-zA-Z]+$/) \
  || (p ~ /\.test\.[a-zA-Z]+$/) || (p ~ /\.spec\.[a-zA-Z]+$/) \
  || (p ~ /Tests?\.[a-zA-Z]+$/) }
function flush(){
  if(file!="" && testf){
    if(deleted) print "WEAKENED\t" file "\tdeleted-test-file"
    else {
      if(skipadd>0)            print "WEAKENED\t" file "\tskip/xfail-added"
      if(asrt_rm>asrt_add)     print "WEAKENED\t" file "\tassert-removed (" asrt_rm ">" asrt_add ")"
      if(defrm>0 && defadd==0) print "WEAKENED\t" file "\ttest-removed-or-commented"
    }
  }
}
/^diff --git / { flush(); file=""; testf=0; deleted=0; skipadd=0; asrt_rm=0; asrt_add=0; defrm=0; defadd=0; next }
/^deleted file mode/ { deleted=1; next }
/^\+\+\+ / { p=$2; sub(/^b\//,"",p); if(p!="/dev/null") file=p; testf=is_test(file); next }
/^--- /    { if(file==""){ p=$2; sub(/^a\//,"",p); file=p; testf=is_test(file) } next }
{
  if(!testf) next
  line=$0
  if(substr(line,1,1)=="-" && substr(line,1,3)!="---"){
    b=substr(line,2)
    if(b ~ /assert|expect\(|XCTAssert|EXPECT_|ASSERT_|require\.|should|t\.Error|t\.Fatal/) asrt_rm++
    if(b ~ /(def|func|fn)[ \t]+[Tt]est|[ \t]it\(|[ \t]test\(|@Test/) defrm++
  } else if(substr(line,1,1)=="+" && substr(line,1,3)!="+++"){
    a=substr(line,2)
    if(a ~ /assert|expect\(|XCTAssert|EXPECT_|ASSERT_|require\.|should|t\.Error|t\.Fatal/) asrt_add++
    if(a ~ /(def|func|fn)[ \t]+[Tt]est|[ \t]it\(|[ \t]test\(|@Test/) defadd++
    if(a ~ /@pytest\.mark\.(skip|xfail)|\.skip\(|\.only\(|xit\(|xdescribe\(|t\.Skip\(|@Disabled|@Ignore|@unittest\.skip/) skipadd++
  }
}
END{ flush() }
' | { out=$(cat); [ -z "$out" ] && echo "CLEAN" || printf '%s\n' "$out"; }
exit 0
```

Then: `chmod +x ~/.claude/skills/review-triage-fix/scripts/weakening-scan.sh`

- [ ] **Step 4: Run test to verify it passes**

Run: `bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh`
Expected: Task 1 (7) + Task 2 (6) all `PASS`; `PASS=13 FAIL=0`, exit 0.

- [ ] **Step 5: Checkpoint** — harness green; TodoWrite update.

---

### Task 3: `triage-state.sh diff`

**Files:**
- Create: `~/.claude/skills/review-triage-fix/scripts/triage-state.sh`
- Modify: `~/.claude/skills/review-triage-fix/tests/run-tests.sh` (append before the summary line)

- [ ] **Step 1: Write the failing test** — insert before the `echo "----"` summary line:

```bash
# --- Task 3: triage-state.sh diff ---
T="$S/triage-state.sh"
SF="$TMP/.triage-fix-last.json"
# 3a: no prev state → all NEW, convergence stabile
rm -f "$SF"
O=$(printf 'MAJOR\tsrc/a.py:10\tmissing validation\nMINOR\tsrc/b.py:4\tnaming\n' | bash "$T" diff "$SF" 2>/dev/null); r=$?
[ $r -eq 0 ] && [ "$(echo "$O" | grep -c $'\tNEW$')" = "2" ] \
  && echo "$O" | grep -q $'^COUNTS\tresolved=0\topen=2\tnew=2\tregressed=0' \
  && ok "state diff: first run → 2 NEW" || bad "state diff first"
# seed a prev state via commit (tested fully in Task 4; used here as fixture)
printf 'MAJOR\tsrc/a.py:10\tmissing validation\topen\nMINOR\tsrc/b.py:4\tnaming\topen\n' | bash "$T" commit "$SF" 2>/dev/null
# 3b: one resolved (b gone), one still-open (a) → RESOLVED + STILL-OPEN, converge
O=$(printf 'MAJOR\tsrc/a.py:10\tmissing validation\n' | bash "$T" diff "$SF" 2>/dev/null)
echo "$O" | grep -q $'src/a.py:10\tSTILL-OPEN' \
  && echo "$O" | grep -q $'\tRESOLVED' \
  && echo "$O" | grep -q $'^COUNTS\tresolved=1\topen=1\tnew=0\tregressed=0' \
  && echo "$O" | grep -q $'^CONVERGENCE\tconverge: 2→1 aperti' \
  && ok "state diff: resolved+still-open+converge" || bad "state diff resolved"
# 3c: previously-resolved finding reappears → REGRESSED
printf 'MAJOR\tsrc/a.py:10\tmissing validation\tresolved\n' | bash "$T" commit "$SF" 2>/dev/null
O=$(printf 'MAJOR\tsrc/a.py:10\tmissing validation\n' | bash "$T" diff "$SF" 2>/dev/null)
echo "$O" | grep -q $'src/a.py:10\tREGRESSED' \
  && echo "$O" | grep -q $'^COUNTS\tresolved=0\topen=1\tnew=0\tregressed=1' \
  && ok "state diff: regressed" || bad "state diff regressed"
# 3d: stable ID — same finding hashes identically across calls (whitespace-normalized)
ID1=$(printf 'MAJOR\tsrc/a.py:10\tmissing validation\n'   | bash "$T" diff "$TMP/none1.json" 2>/dev/null | awk -F'\t' '/NEW$/{print $1}')
ID2=$(printf 'MAJOR\tsrc/a.py:10\t  missing   validation \n' | bash "$T" diff "$TMP/none2.json" 2>/dev/null | awk -F'\t' '/NEW$/{print $1}')
[ -n "$ID1" ] && [ "$ID1" = "$ID2" ] && ok "state diff: stable normalized ID" || bad "state diff id"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh`
Expected: Tasks 1–2 `PASS`; the 4 `state diff:` checks `FAIL` (script absent); non-zero exit.

- [ ] **Step 3: Write minimal implementation** — create `~/.claude/skills/review-triage-fix/scripts/triage-state.sh`:

```bash
#!/bin/bash
# review-triage-fix: cross-cycle finding state (deterministic).
#   diff   <state-file>  : stdin TSV "sev<TAB>loc<TAB>problem"
#       → per-finding "id<TAB>sev<TAB>loc<TAB>{NEW|STILL-OPEN|REGRESSED}",
#         then RESOLVED rows, then COUNTS line, then CONVERGENCE line. No write.
#   commit <state-file>  : stdin TSV "sev<TAB>loc<TAB>problem<TAB>status"
#         (status open|resolved) → write JSON state; gitignore it if in a git tree.
set -u
sub="${1:-}"; SF="${2:-}"
if [ -z "$sub" ] || [ -z "$SF" ]; then
  echo "usage: triage-state.sh diff|commit <state-file>" >&2; exit 2
fi
fid(){ # "sev|loc|problem" → first 8 hex of sha256 (whitespace-normalized)
  # sed (not `tr -s ' \t'`): on BSD/macOS tr's \t handling is unreliable.
  # Collapse runs of whitespace, strip spaces around the | joins, trim ends —
  # so the same finding hashes identically regardless of incidental spacing.
  local s; s=$(printf '%s' "$1" | sed 's/[[:space:]][[:space:]]*/ /g; s/ *| */|/g; s/^ //; s/ $//')
  if command -v shasum >/dev/null 2>&1; then printf '%s' "$s" | shasum -a 256 | awk '{print substr($1,1,8)}'
  else printf '%s' "$s" | sha256sum | awk '{print substr($1,1,8)}'; fi
}
case "$sub" in
diff)
  # bash 3.2 has no associative arrays → temp-file maps.
  # Load previous state into a temp file: "id<TAB>status" per line
  PSTATE=$(mktemp); : > "$PSTATE"
  if [ -f "$SF" ] && command -v jq >/dev/null 2>&1; then
    jq -r '.[] | "\(.id)\t\(.status)"' "$SF" 2>/dev/null > "$PSTATE"
  fi
  FINDINGS=$(cat)
  OUT=$(mktemp); : > "$OUT"
  newc=0; openc=0; regc=0
  SEEN=$(mktemp); : > "$SEEN"
  while IFS=$'\t' read -r sev loc prob; do
    [ -z "${sev}${loc}${prob}" ] && continue
    id=$(fid "$sev|$loc|$prob")
    printf '%s\n' "$id" >> "$SEEN"
    p=$(grep -m1 "^${id}	" "$PSTATE" | awk -F'\t' '{print $2}')
    if   [ -z "$p" ];           then st=NEW;        newc=$((newc+1))
    elif [ "$p" = "resolved" ]; then st=REGRESSED;  regc=$((regc+1))
    else                             st=STILL-OPEN; openc=$((openc+1)); fi
    printf '%s\t%s\t%s\t%s\n' "$id" "$sev" "$loc" "$st" >> "$OUT"
  done <<EOF
$FINDINGS
EOF
  resc=0; prevopen=0
  while IFS=$'\t' read -r pid pst; do
    [ -z "$pid" ] && continue
    [ "$pst" = "open" ] && prevopen=$((prevopen+1))
    if [ "$pst" = "open" ] && ! grep -q -x "$pid" "$SEEN" 2>/dev/null; then
      printf '%s\t-\t-\tRESOLVED\n' "$pid" >> "$OUT"; resc=$((resc+1))
    fi
  done < "$PSTATE"
  cat "$OUT"
  curopen=$((openc+regc+newc))
  printf 'COUNTS\tresolved=%s\topen=%s\tnew=%s\tregressed=%s\n' "$resc" "$curopen" "$newc" "$regc"
  if   [ "$curopen" -eq 0 ]; then
    printf 'CONVERGENCE\tpulito: 0 aperti\n'
  elif [ "$prevopen" -gt 0 ] && [ "$curopen" -lt "$prevopen" ] && [ "$regc" -eq 0 ]; then
    printf 'CONVERGENCE\tconverge: %s→%s aperti\n' "$prevopen" "$curopen"
  elif [ "$resc" -gt 0 ] && [ "$newc" -gt 0 ]; then
    printf 'CONVERGENCE\toscilla: %s risolti, %s nuovi\n' "$resc" "$newc"
  else
    printf 'CONVERGENCE\tstabile: %s aperti\n' "$curopen"
  fi
  rm -f "$PSTATE" "$OUT" "$SEEN"
  ;;
commit)
  command -v jq >/dev/null 2>&1 || { echo "triage-state: jq mancante" >&2; exit 1; }
  tmp=$(mktemp); echo '[]' > "$tmp"
  while IFS=$'\t' read -r sev loc prob status; do
    [ -z "${sev}${loc}${prob}" ] && continue
    case "$status" in open|resolved) ;; *) status=open;; esac
    id=$(fid "$sev|$loc|$prob")
    jq --arg id "$id" --arg s "$sev" --arg l "$loc" --arg st "$status" \
       '. += [{id:$id,sev:$s,loc:$l,status:$st}]' "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp"
  done
  mkdir -p "$(dirname "$SF")" 2>/dev/null || true
  mv "$tmp" "$SF"
  d=$(cd "$(dirname "$SF")" 2>/dev/null && pwd) || exit 0
  if command -v git >/dev/null 2>&1 && git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # Use --show-prefix (repo-relative, no path canonicalization) instead of
    # string-subtracting --show-toplevel: on macOS $TMPDIR is /var → /private/var
    # symlinked, so a literal prefix-strip would mismatch and corrupt the entry.
    top=$(git -C "$d" rev-parse --show-toplevel 2>/dev/null)
    pref=$(git -C "$d" rev-parse --show-prefix 2>/dev/null)
    if [ -n "$top" ]; then
      rel="${pref}$(basename "$SF")"
      gi="$top/.gitignore"
      if ! { [ -f "$gi" ] && grep -F -x -q -- "$rel" "$gi" 2>/dev/null; }; then
        printf '%s\n' "$rel" >> "$gi"
      fi
    fi
  fi
  ;;
*) echo "usage: triage-state.sh diff|commit <state-file>" >&2; exit 2;;
esac
exit 0
```

Then: `chmod +x ~/.claude/skills/review-triage-fix/scripts/triage-state.sh`

- [ ] **Step 4: Run test to verify it passes**

Run: `bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh`
Expected: Tasks 1–2 + the 4 `state diff:` checks all `PASS`; `PASS=17 FAIL=0`, exit 0.

- [ ] **Step 5: Checkpoint** — harness green; TodoWrite update.

---

### Task 4: `triage-state.sh commit` (state file + gitignore)

**Files:**
- Modify: `~/.claude/skills/review-triage-fix/tests/run-tests.sh` (append before the summary line)

**Decomposition note (conscious, see self-review):** `triage-state.sh` is one
cohesive module; `commit` was necessarily implemented in Task 3 (Task 3's diff
tests need a seeded state file, which only `commit` can produce). This task is
therefore a **contract-locking test layer** for the distinct `commit` behaviors
(JSON shape, ID round-trip vs `diff`, git vs non-git gitignore) that deserve
their own scenarios — not a fresh red-first implementation. An unexpected `FAIL`
here is a real Task-3 bug to fix in the script.

- [ ] **Step 1: Write the failing test** — insert before the `echo "----"` summary line:

```bash
# --- Task 4: triage-state.sh commit ---
T="$S/triage-state.sh"
# 4a: commit writes a JSON array with id/sev/loc/status
CF="$TMP/c_plain/.claude/.triage-fix-last.json"
printf 'BLOCKER\tsrc/x.py:9\tinjection\tresolved\nNIT\tsrc/y.py:1\tstyle\topen\n' | bash "$T" commit "$CF" 2>/dev/null
[ -f "$CF" ] && [ "$(jq 'length' "$CF" 2>/dev/null)" = "2" ] \
  && [ "$(jq -r '.[0]|.sev+"|"+.status' "$CF")" = "BLOCKER|resolved" ] \
  && ok "state commit: writes JSON array" || bad "state commit json"
# 4b: ID matches what diff computes for the same finding (round-trip stable)
ID_C=$(jq -r '.[1].id' "$CF")
ID_D=$(printf 'NIT\tsrc/y.py:1\tstyle\n' | bash "$T" diff "$TMP/none3.json" 2>/dev/null | awk -F'\t' '/NEW$/{print $1}')
[ -n "$ID_C" ] && [ "$ID_C" = "$ID_D" ] && ok "state commit: id == diff id" || bad "state commit id"
# 4c: NON-git target → no .gitignore created, no error
NG="$TMP/c_nogit/.claude/.triage-fix-last.json"
printf 'MINOR\ta:1\tp\topen\n' | bash "$T" commit "$NG" 2>/dev/null; r=$?
[ $r -eq 0 ] && [ -f "$NG" ] && [ ! -e "$TMP/c_nogit/.gitignore" ] && ok "state commit: non-git → no gitignore" || bad "state commit nogit"
# 4d: git target → state-file path appended to repo .gitignore (idempotent)
GR="$TMP/c_git"; mkdir -p "$GR"; ( cd "$GR" && git init -q && git config user.email t@t && git config user.name t )
GF="$GR/.claude/.triage-fix-last.json"
printf 'MAJOR\tz:2\tq\topen\n' | bash "$T" commit "$GF" 2>/dev/null
printf 'MAJOR\tz:2\tq\topen\n' | bash "$T" commit "$GF" 2>/dev/null   # second call
[ "$(grep -c -F '.claude/.triage-fix-last.json' "$GR/.gitignore" 2>/dev/null)" = "1" ] \
  && ok "state commit: git → gitignored once" || bad "state commit gitignore"
```

- [ ] **Step 2: Run test to verify the commit contract holds**

Run: `bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh`
Expected: Tasks 1–3 `PASS`; the 4 `state commit:` checks `PASS` (the `commit`
subcommand exists from Task 3 and its contract should already be satisfied).
An unexpected `FAIL` is a genuine Task-3 bug — proceed to Step 3.

- [ ] **Step 3: Fix the script only if Step 2 showed a FAIL**

If all `state commit:` PASS, no change — skip to Step 4. If a `FAIL` appeared,
diagnose the named assertion against the Task 3 `triage-state.sh` `commit`
block (most likely the `rel`/`--show-prefix` computation or the jq array shape)
and apply the minimal fix to the script, then re-run.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh`
Expected: `state commit: writes JSON array`, `id == diff id`, `non-git → no gitignore`, `git → gitignored once` all `PASS`; `PASS=21 FAIL=0`, exit 0.

- [ ] **Step 5: Checkpoint** — harness green; TodoWrite update. All three helpers feature-complete and unit-covered.

---

### Task 5: author `SKILL.md` (the workflow) + structural self-test

**Files:**
- Create: `~/.claude/skills/review-triage-fix/SKILL.md`
- Modify: `~/.claude/skills/review-triage-fix/tests/run-tests.sh` (append before the summary line)

- [ ] **Step 1: Write the failing test** — insert before the `echo "----"` summary line. This asserts the workflow doc actually encodes every load-bearing element from the design (a missing anchor = an incomplete skill, caught deterministically):

```bash
# --- Task 5: SKILL.md structural completeness ---
M="$SK/SKILL.md"
g(){ grep -q -- "$1" "$M" 2>/dev/null && ok "SKILL.md: $2" || bad "SKILL.md missing: $2"; }
[ -f "$M" ] || bad "SKILL.md: file exists"
head -1 "$M" | grep -q '^---$' && grep -q '^name: review-triage-fix$' "$M" && ok "SKILL.md: frontmatter name" || bad "SKILL.md: frontmatter name"
grep -q '^description:.*invoc' "$M" && ok "SKILL.md: description" || bad "SKILL.md: description"
g 'scripts/verify.sh'        'invokes verify.sh'
g 'scripts/weakening-scan.sh' 'invokes weakening-scan.sh'
g 'scripts/triage-state.sh'  'invokes triage-state.sh'
g 'debugger'                 'routes to debugger'
g 'refactorer'               'routes to refactorer'
g 'coder'                    'routes to coder'
g 'micro-piano'              'coder micro-plan'
g 'REPORT-ONLY'              'report-only class'
g 'CIRCUIT BREAKER A'        'breaker A regressione'
g 'CIRCUIT BREAKER B'        'breaker B anti-weakening'
g 'CIRCUIT BREAKER C'        'breaker C security'
g 'CIRCUIT BREAKER D'        'breaker D unverified'
g 'NESSUN COMMIT'            'no-commit invariant'
g 'STOP'                     'single-cycle STOP'
g 'sub-agent'                'sub-agent-no-spawn constraint'
g 'sequenzial'               'sequential dispatch'
g '.triage-fix-last.json'    'cross-cycle state file'
g 'Add+Remove rule'          'add+remove substitution rule'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh`
Expected: Tasks 1–4 `PASS`; all `SKILL.md:` checks `FAIL` (file absent); non-zero exit.

- [ ] **Step 3: Write minimal implementation** — create `~/.claude/skills/review-triage-fix/SKILL.md` with exactly:

````markdown
---
name: review-triage-fix
description: This skill should be used when, after a coding pass, you want one bounded review→triage→fix→re-review→recap cycle over recent changes. Manual invocation only, from the orchestrator session (not from inside a sub-agent). Triggers include "review-triage-fix", "cicla review e fix", "triage dei finding e correggi".
---

# review-triage-fix

One invocation = **exactly one cycle**:
`pre-flight → reviewer → triage → route-fix (sequential) → re-review → recap → STOP`.
You recommend; the user decides whether to re-invoke or commit. **NESSUN COMMIT,
nessun push, nessuna iterazione automatica oltre il ciclo** dentro questa skill.

## Hard constraints (read first)

- **Sub-agent non spawnano sub-agent.** Questa skill orchestra dispatch multipli:
  gira **solo nella sessione orchestratore**. Se vieni invocato da dentro un
  sub-agent, fermati e dillo — non potresti dispatchare.
- **Dispatch sempre sequenziale.** Mai fix in parallelo: stesso codebase →
  conflitti di edit.
- **STOP a fine ciclo.** Un'invocazione, un ciclo, poi recap e stop. Nessun
  commit/PR (restano HITL separati).
- I tre helper sono in
  `$HOME/.claude/skills/review-triage-fix/scripts/` e si invocano via Bash.
  Sono reporter: leggi il **primo token di stdout**, non l'exit code.

## Step 0 — Pre-flight

1. Confirm you are the orchestrator session (not a sub-agent). If unsure, stop.
2. Resolve the project root (the dir whose `.claude/` you'll use). Run the
   **baseline** once and record it:
   `bash $HOME/.claude/skills/review-triage-fix/scripts/verify.sh <root>`
   - `PASS` → baseline **VERDE**.
   - `FAIL …` → baseline **ROSSO** (CIRCUIT BREAKER A disabled this cycle —
     regression detection unavailable; say so in the recap).
   - `UNVERIFIED …` → **CIRCUIT BREAKER D** active for the whole cycle.
3. State the cycle number = (previous `.triage-fix-last.json` present ? N+1 : 1).

## Step 1 — Review

Dispatch the `reviewer` agent over the recent changes. Edge cases:
- Reviewer reports **no detectable changes** → stop, emit a "niente da fare"
  recap, do not invent work.
- **Huge diff sampled** → propagate that caveat verbatim into the recap.

## Step 2 — Triage (classify every finding per the table)

Read the reviewer's severity-grouped report. For each finding extract
`sev` (BLOCKER/MAJOR/MINOR/NIT), `loc` (`path:line`), a one-line `problem`,
and the suggested fix. Classify:

| Finding class | Route to | Note |
|---|---|---|
| Failure: runtime error, red test, reproducible wrong behavior | `debugger` | root-cause + minimal fix + regression + verify (its contract) |
| Structural: duplication, oversized unit, tangled responsibility | `refactorer` | requires a GREEN baseline (Step 0); if baseline red → REPORT-ONLY |
| Localized non-failure non-structural code change: missing validation, edge-case test, naming, small hardening | `coder` | synthesize a **micro-piano** = the finding + suggested-fix as a 1-item plan so the coder's plan-driven contract is satisfied |
| Architectural / design-level / ambiguous | **REPORT-ONLY** | flag for the user, no fix |
| Security BLOCKER (auth/secret/injection) | **REPORT-ONLY** | CIRCUIT BREAKER C |
| Reviewer-declared low confidence | **REPORT-ONLY** | acting on uncertain findings is risky |

NITs are routed (coherent with auto-route-all) but treated as a single
low-risk batch and shown **separately** in the recap sub-table.

**Micro-piano discipline (for `coder` dispatches): strictly 2-3 lines** —
finding + suggested-fix + (optional) file:line. NOT a multi-paragraph spec.
The coder must do exactly that change and stop, not expand scope. Bound the
context aggressively: a bloated micro-piano = a bloated dispatch (40k+ tokens
for a small change is a smell, observed in the v1 pilot).

**Add+Remove rule (for SUBSTITUTION fixes):** when the fix replaces a pattern
rather than just adding (e.g. move local import to top-level, extract magic
number to a named constant, consolidate duplicate fixtures, rename a helper),
the micro-piano MUST list BOTH the new pattern (`Add: ...`) AND the old
instances to delete (`Remove: <path:line> ...`). Without an explicit Remove,
the coder typically acts conservatively and leaves the old pattern in place →
duplication that the re-review then flags as a new finding (observed cycle 2
2026-05-20, M-3 autouse fixture → M-1 re-review). For purely ADDITIVE fixes
(missing input validation, new edge-case test, docstring fix), `Add:` alone
suffices — no Remove section needed.

Then compute cross-cycle status. Write the current findings as TSV
(`sev<TAB>loc<TAB>problem`, one per line) and run:
`… | bash $HOME/.claude/skills/review-triage-fix/scripts/triage-state.sh diff <root>/.claude/.triage-fix-last.json`
Keep its `id/state` rows, `COUNTS`, and `CONVERGENCE` line for the recap.

## Step 3 — Route-fix (sequential, severity order)

**Before the loop — snapshot pattern (universal, git AND non-git):** the
per-fix attribution that breakers A and B need requires a pre-fix baseline.
`git diff` alone shows cumulative uncommitted changes from ALL prior fixes,
which mis-attributes weakening to innocent later fixes. So: snapshot the test
tree before the loop AND refresh it after each fix.

```
cp -R <test dirs> "$TMPDIR/rtf-snap"     # before the loop, once
# … per-fix dispatch …
diff -ru "$TMPDIR/rtf-snap" <live test files> | weakening-scan.sh
rm -rf "$TMPDIR/rtf-snap" && cp -R <test dirs> "$TMPDIR/rtf-snap"   # refresh
```

For each **routable** finding (skip REPORT-ONLY), in order
BLOCKER → MAJOR → MINOR → NIT, dispatch the chosen agent with a curated input:
the finding, `loc`, the reviewer's suggested fix, (for `coder`) the micro-piano,
and the project's test-cmd so the agent self-verifies.

**NIT batching is mandatory.** All routable NITs go to `coder` as a **SINGLE
dispatch with a list** (one line per NIT: sev, loc, problem, suggested-fix) —
not N separate dispatches. The micro-piano for the batch IS the list, with
"apply all of these, each as the smallest possible change" as the instruction.
Verify + weakening-scan once after the batch, not after each NIT inside it.
This alone removed the dominant cost in the v1 pilot (multiple NIT/MINOR
dispatches at 1-2 min each).

After **each** fix dispatch (or after the NIT batch), you re-run verification
yourself (do not trust the agent's self-report for the breakers):

- `bash $HOME/.claude/skills/review-triage-fix/scripts/verify.sh <root>`
- `diff -ru "$TMPDIR/rtf-snap" <live test files>` piped into
  `bash $HOME/.claude/skills/review-triage-fix/scripts/weakening-scan.sh`
- then refresh the snapshot for the next iteration.

Apply the circuit breakers:

- **CIRCUIT BREAKER A — abort on regression.** Only if baseline was VERDE. If
  `verify.sh` flips PASS→FAIL and stays FAIL after the responsible agent ran:
  **stop fixing**, do not pile on, record the culprit finding, jump to Step 4
  with flag `ABORT: regressione a <finding>`. If baseline was ROSSO: detection
  off; recap notes "baseline rosso — rilevazione regressioni non disponibile".
- **CIRCUIT BREAKER B — hard-fail anti-test-weakening.** If `weakening-scan.sh`
  prints any `WEAKENED` line for this fix: mark that finding
  `NON RISOLTO — test indebolito`, raise a BLOCKER flag in the recap,
  regardless of suite colour. **NESSUN auto-revert** — leave the change in
  place, flag it loud (destructive action stays with the human gate).
- **CIRCUIT BREAKER C — security BLOCKER report-only.** Never enters this loop
  (classified REPORT-ONLY in Step 2); counted/deferred in the recap.
- **CIRCUIT BREAKER D — unverified cycle.** If Step 0 returned UNVERIFIED:
  fixes still happen but every recap row carries `UNVERIFIED`, breaker A is
  inert, and the recap header is `⚠ UNVERIFIED CYCLE`.

## Step 4 — Re-review

Dispatch `reviewer` again over the new state. Recompute the cross-cycle diff:
write the post-fix findings as TSV (`sev<TAB>loc<TAB>problem`) and run — using
the **same** `<root>/.claude/.triage-fix-last.json` path as Step 2 (never a
fresh file, or convergence tracking breaks):
`… | bash $HOME/.claude/skills/review-triage-fix/scripts/triage-state.sh diff <root>/.claude/.triage-fix-last.json`
to get resolved / still-open / new / regressed.

## Step 5 — Recap (decision-grade) then STOP

**Header:** project root; cycle N; verification mode
(`VERIFIED: test-cmd=<cmd>` or `⚠ UNVERIFIED CYCLE`); baseline colour →
post-cycle colour; a prominent flag banner if any
(`ABORT regressione`, BLOCKER anti-weakening, deferred security-BLOCKER count).

**Per-finding table** — columns:
`ID (sev+loc+hash) | Sev | Problema (1 riga) | Routing
(debugger/refactorer/coder/REPORT-ONLY[reason]) | Change (file:line or "—") |
Verifica (PASS/FAIL/UNVERIFIED/N-A) | Stato vs ciclo prec.
(NEW/RESOLVED/STILL-OPEN/REGRESSED/WEAKENED)`.

`triage-state.sh diff` emits only NEW/RESOLVED/STILL-OPEN/REGRESSED. `WEAKENED`
is not produced by any helper: if **CIRCUIT BREAKER B** fired for a finding, you
override that finding's "Stato vs ciclo prec." to `WEAKENED` yourself.

**NIT:** a separate compressed sub-table beneath the main one.

**Diff di ciclo:** explicit counts from `triage-state.sh`
(Risolti / Aperti / Nuovi / Regrediti) + the `CONVERGENCE` reading.

**Verdetto** (you recommend, the user decides):
- `SAFE: 0 aperti, suite verde → valuta commit`
- `RE-RUN consigliato: N aperti, converge`
- `STOP & ISPEZIONA: abort/weakening/non converge`
- `UNVERIFIED: verifica manuale prima del commit`

The finding ID is a hash of `sev|loc|problem`: to keep cross-cycle tracking
stable, reuse the **exact** problem wording from the previous cycle's recap
table when a finding is unchanged — paraphrasing it makes the next cycle
mis-report it as RESOLVED+NEW (false "oscilla") instead of STILL-OPEN.

Then persist state for the next cycle: write the final findings as TSV
(`sev<TAB>loc<TAB>problem<TAB>status`, status `open`|`resolved`) into
`… | bash $HOME/.claude/skills/review-triage-fix/scripts/triage-state.sh commit <root>/.claude/.triage-fix-last.json`
(this also gitignores the state file when the project is a git repo).

**STOP.** Do not commit, do not re-invoke yourself. Hand the verdict to the user.

## Future work — parallel batch mode (v2, NOT enabled in v1.1)

A parallel-dispatch optimization for independent fixes is plausible but BLOCKED
by an upstream prerequisite: `~/.claude/agents/coder.md` has no
`isolation: worktree` field (the blueprint envisioned it but the deployed
agent does not have it). Without per-agent worktrees, parallel `coder`
dispatches edit the same live filesystem → conflicts.

When `coder.md` gains `isolation: worktree`, add a parallel mode here gated on:
all candidates routed to `coder`, non-BLOCKER, disjoint `loc` paths.
Trade-off: lose per-fix attribution for breaker A (regression becomes
batch-level; binary-search-back-out to find culprit). Keep sequential as the
default; parallel as opt-in for time-pressure batches.
````

- [ ] **Step 4: Run test to verify it passes**

Run: `bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh`
Expected: every `SKILL.md:` anchor check `PASS` — 19 checks (frontmatter name, description, 3 helper paths, debugger/refactorer/coder, micro-piano, REPORT-ONLY, breakers A–D, NESSUN COMMIT, STOP, sub-agent, sequenzial, state file); cumulative `PASS=40 FAIL=0` (verify 7 + weakening 6 + state-diff 4 + state-commit 4 + SKILL.md 19), exit 0. (v1.2 patch: PASS=41 with 1 added anchor "Add+Remove rule" — SKILL.md ×20.)

- [ ] **Step 5: Checkpoint** — harness green; TodoWrite update. Skill is structurally complete.

---

### Task 6: full harness + spec-coverage self-review gate

**Files:**
- Modify: `docs/superpowers/specs/2026-05-19-review-triage-fix-design.md:4` (status line only)

- [ ] **Step 1: Full harness run**

Run: `bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh`
Expected: final `PASS=40 FAIL=0` (v1.1) or `PASS=41 FAIL=0` (v1.2), exit 0 (Task 1 verify ×7, Task 2 weakening ×6, Task 3 state-diff ×4, Task 4 state-commit ×4, Task 5 SKILL.md ×19 [v1.1] / ×20 [v1.2]).

- [ ] **Step 2: Spec coverage check (self, inline — no subagent)**

Verify each design section maps to delivered behavior:
- §4 one-cycle contract → SKILL.md Step 0–5 + `STOP`. ✔
- §5 routing table incl. architectural & low-confidence → REPORT-ONLY → SKILL.md Step 2 table + structural test. ✔
- §6 data flow (pre-flight/baseline, review edges, triage, sequential fix + self re-run, re-review, recap) → SKILL.md Steps 0–5. ✔
- §7 breakers A/B/C/D → SKILL.md Step 3 + structural test anchors; A trigger = skill's own `verify.sh` re-run. ✔
- §8 recap format (header, per-finding columns, NIT sub-table, cycle diff, verdetto) → SKILL.md Step 5. ✔
- §9 `.triage-fix-last.json` per-project + gitignored if git → `triage-state.sh commit` + Task 4d. ✔
- §10 testable scaffolding (parser is LLM by design; verify/weakening/state are unit-tested) → Tasks 1–4. ✔
- §11/§12 invariants & deps (no commit, sequential, reuse test-cmd, reuse deployed agents) → SKILL.md hard-constraints + reuse of `.claude/test-cmd`. ✔
List any gap; if a §-requirement has no task/anchor, add a structural assertion in Task 5's block and re-run before continuing.

- [ ] **Step 3: Update the spec status line**

Edit `docs/superpowers/specs/2026-05-19-review-triage-fix-design.md` line 4 from
`**Stato:** approvato (brainstorming) — pronto per writing-plans` to
`**Stato:** approvato → piano `docs/superpowers/plans/2026-05-19-review-triage-fix.md` (helper unit-tests verdi; pilota pending)`.

- [ ] **Step 4: Checkpoint** — harness `FAIL=0`, spec coverage closed, spec status synced. Report readiness for the pilot.

---

### Task 7: pilot end-to-end validation (Stefano-run)

**Files:** none in this repo. Manual validation in `~/developer/pricing-markup-cli` (has git).

This is the non-deterministic LLM pipeline check the design defers to a single
manual pilot run (design §10, §13). Prepare; Stefano runs/approves.

- [ ] **Step 1: Pilot prerequisites (Stefano)**

In `~/developer/pricing-markup-cli`:
```bash
mkdir -p .claude && printf 'pytest -q\n' > .claude/test-cmd
bash ~/.claude/hooks/approve-test-cmd.sh "$PWD"   # TOFU approve (reused gate)
```

- [ ] **Step 2: One full cycle (Stefano, fresh orchestrator session in the pilot)**

Make a small intentional set of issues (e.g. a missing input validation + a
trivially red unit test), then invoke `review-triage-fix`. Expected:
- baseline reported; reviewer dispatched; findings triaged per §5;
- the red test routed to `debugger`, the missing validation to `coder` with a
  micro-piano, an architectural/ambiguous note kept REPORT-ONLY;
- after each fix the skill re-runs `verify.sh` + `weakening-scan.sh` itself;
- recap matches §8 (header, table, NIT sub-table, cycle diff, verdetto);
- the cycle **STOPS** — no commit, no auto re-invoke.

- [ ] **Step 3: Circuit-breaker spot checks (Stefano)**

- Seed a "fix" that deletes/loosens an assert → expect breaker **B**:
  `NON RISOLTO — test indebolito`, BLOCKER flag, **no auto-revert**.
- Seed a fix that turns the green suite red and stays red → expect breaker
  **A**: `ABORT: regressione a <finding>`, skill stops piling on.
- Remove `.claude/test-cmd` then invoke → expect breaker **D**:
  `⚠ UNVERIFIED CYCLE`, every row `UNVERIFIED`.

- [ ] **Step 4: Second consecutive invocation (Stefano)**

Re-invoke without committing → expect the cross-cycle diff to show correct
RESOLVED/STILL-OPEN/NEW/REGRESSED vs cycle 1 and a sensible `CONVERGENCE` line.

- [ ] **Step 5: Final report**

Summarize observed behavior against design §13 success criteria; note any
divergence between the LLM orchestration and the recap contract for follow-up.

---

## Known limitations (surfaced by the final integration review)

- **Non-git multi-file weakening undercount (M1).** `weakening-scan.sh` resets
  per-file state and `flush()`es on `^diff --git ` headers. `git diff` (git
  projects, incl. the pilot) emits those — correct. The non-git fallback
  `diff -ru "$TMPDIR/rtf-snap" <live>` does NOT emit `diff --git` headers, so a
  **multi-file** non-git diff flushes only once (at END): only the last test
  file is evaluated and its counters are cross-file-contaminated, and the
  `assert-removed (N>)` count shows an empty added-side. Single-file non-git
  fixes (the common per-finding case) still work. Not blocking (pilot is git);
  hardening the non-git path = future work (would reopen the Task-2 artifact +
  add a `diff -ru` harness case).
- **Content-hash ID drift (M2).** Finding ID = `sha256(sev|loc|problem)`. If the
  reviewer paraphrases an unchanged finding's problem text between cycles, the
  next cycle reports it RESOLVED+NEW (false "oscilla"). Mitigated by an explicit
  SKILL.md Step 5 instruction to reuse the prior recap's exact wording; residual
  risk is inherent to content-hash keys and accepted by design §10.

## Out of scope

- New "fixer" agent — capability already covered by debugger/refactorer/coder.
- Automatic trigger / hook — invocation and decision stay human.
- Auto-revert of any fix (including the anti-weakening case) — human gate only.
- Parallel fix execution — sequential is mandatory (edit conflicts).
- Commit / PR — separate existing HITL workflows.
- Sandboxing the test-cmd — delegated to the deployed Stop-gate testcmd + protect-files.
```
