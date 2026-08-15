#!/bin/bash
# dispatch-completion.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash dispatch-completion.test.sh
#
# Issue #435 / ADR-0139. CC 2.1.232 made non-teammate agent spawns run in the background by default
# in interactive sessions. Measured 2026-08-14: an `Agent()` call returns dispatch metadata and
# nothing else, and the report arrives later as a notification. Every Agent-tool dispatch site in
# this system signalled completion through the transcript.
#
# THE POPULATION RESISTED THREE MECHANICAL DERIVATIONS, and that is why this harness works the way
# it does. `Agent({` finds 5 sites. `subagent_type` finds 8. Reading the files finds 15, because
# most sites are prose — "**Dispatch architect:**", "Dispatch `reviewer` again over the new state".
# A needle keyed on notation would have reported coverage over a third of the population and looked
# green doing it (rule 12, and rule 7 on the denominator). So the population is DECLARED, at the
# site, and the declaration is checked in BOTH directions: DC20-DC22 forward over the declarations,
# DC23 backward over the prose forms a declaration must not miss.
#
# WHAT IS ENFORCEMENT AND WHAT IS NOT (rule 16). DC1-DC8 execute `dispatch-state.sh` and are
# mechanical. DC10-DC12 assert that the two converted call sites CONSULT it — they cannot assert
# that an orchestrator obeys a HALT line, and no assertion in this file claims to.
#
# --- plants (plant-check.sh) ------------------------------------------------------------
# Each line below removes ONE mechanism and names the assertion that must go RED for it.
# An assertion whose plant does not fire pins nothing. Format and rationale: plant-check.sh.
# plant: DC7 | plugin/scripts/dispatch-state.sh | if [ ! -x "$DIR" ] || [ ! -r "$DIR" ]; then | if false; then
# plant: DC10 | plugin/skills/concept-to-code/SKILL.md | Measure nothing until the coder has finished | Measure whenever
# plant: DC11 | plugin/skills/concept-to-code/SKILL.md | Do not look for `PATTERN: DONE` in the agent's report | Look for it
# plant: DC21 | plugin/skills/security-audit/SKILL.md | dispatch-site: security-audit-reviewer | dispatch-note: removed
# plant: DC22 | plugin/skills/security-audit/SKILL.md | class=inline exempt: the reviewer grant | class=maybe exempt: the reviewer grant
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
DS="$SCRIPTS/dispatch-state.sh"
SKILLS="$STAGING/plugin/skills"
CC="$SKILLS/concept-to-code/SKILL.md"

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

for _f in "$DS" "$CC"; do
  [ -f "$_f" ] || { echo "FATAL: missing $_f"; exit 1; }
done

TMP=$(mktemp -d) || { echo "FATAL: mktemp failed"; exit 1; }
cleanup() { chmod -R u+rwx "$TMP" 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT

# run_ds <root> <id> -> sets DS_OUT and DS_RC
run_ds() { DS_OUT=$(bash "$DS" "$1" "$2" 2>&1); DS_RC=$?; }

# ===========================================================================
# DC0 — vacuity guard. Without a parseable helper every assertion below is vacuous.
# ===========================================================================
if bash -n "$DS" 2>/dev/null; then ok "DC0: dispatch-state.sh parses"
else bad "DC0: dispatch-state.sh does not parse under bash -n"; fi

# ===========================================================================
# DC1-DC5 — the five tokens, executed rather than asserted about.
# ===========================================================================
R1="$TMP/r1"; mkdir -p "$R1"
run_ds "$R1" batchA
[ "$DS_RC" = 0 ] && [ "$DS_OUT" = "NONE|" ] \
  && ok "DC1: no state directory yields NONE" \
  || bad "DC1: expected 'NONE|' rc=0, got rc=$DS_RC '$DS_OUT'"

mkdir -p "$R1/.claude/dispatch"
: > "$R1/.claude/dispatch/batchA.started"
run_ds "$R1" batchA
[ "$DS_RC" = 0 ] && [ "$DS_OUT" = "PENDING|" ] \
  && ok "DC2: started without done yields PENDING" \
  || bad "DC2: expected 'PENDING|' rc=0, got rc=$DS_RC '$DS_OUT'"

printf 'tasks=3 files=7\n' > "$R1/.claude/dispatch/batchA.done"
run_ds "$R1" batchA
[ "$DS_RC" = 0 ] && [ "$DS_OUT" = "DONE|tasks=3 files=7" ] \
  && ok "DC3: well-formed payload yields DONE with its detail" \
  || bad "DC3: expected 'DONE|tasks=3 files=7' rc=0, got rc=$DS_RC '$DS_OUT'"

# The shape guard, not the glob. `tasks=1x files=2` MATCHES the case pattern `tasks=[0-9]* files=[0-9]*`
# because `*` spans any characters — a payload a killed agent can plausibly leave. Without the
# digit re-check this reads as DONE.
printf 'tasks=1x files=2\n' > "$R1/.claude/dispatch/batchB.done"
run_ds "$R1" batchB
case "$DS_OUT" in
  PARTIAL\|*) ok "DC4: a glob-matching but non-numeric payload yields PARTIAL, not DONE" ;;
  *)          bad "DC4: expected PARTIAL for 'tasks=1x files=2', got '$DS_OUT'" ;;
esac

mkdir -p "$R1/.claude/dispatch/batchC.done"
run_ds "$R1" batchC
[ "$DS_OUT" = "UNREADABLE|" ] \
  && ok "DC5: a done marker that is not a regular readable file yields UNREADABLE" \
  || bad "DC5: expected 'UNREADABLE|', got '$DS_OUT'"

# ===========================================================================
# DC6 — bad invocation is exit 2 in every form, including an id that would escape the state dir.
# ===========================================================================
_dc6=0
bash "$DS" "$R1" >/dev/null 2>&1;            [ $? = 2 ] || _dc6=1
bash "$DS" "$R1" "../escape" >/dev/null 2>&1; [ $? = 2 ] || _dc6=1
bash "$DS" "$R1" "a/b" >/dev/null 2>&1;       [ $? = 2 ] || _dc6=1
bash "$DS" "$TMP/nope" x >/dev/null 2>&1;     [ $? = 2 ] || _dc6=1
[ "$_dc6" = 0 ] \
  && ok "DC6: wrong arity, path-bearing id and missing root all exit 2" \
  || bad "DC6: at least one bad invocation did not exit 2"

# ===========================================================================
# DC7 — THE REGRESSION. An unsearchable state directory must be exit 3, never NONE.
#
# The first draft of dispatch-state.sh resolved NONE before anything that could exit 3, copying
# `manifest-entry-state.sh:110-115`. Measured, that produced a FALSE NONE: with the directory at
# chmod 000, `[ -e "$STARTED" ]` is false because the test cannot stat through it, so a batch that
# HAD been dispatched reported "nothing was ever dispatched". A check that could not run reported a
# clean result — the exact defect exit 3 exists to prevent, inside the script written to honour it.
# ===========================================================================
R2="$TMP/r2"; mkdir -p "$R2/.claude/dispatch"
: > "$R2/.claude/dispatch/batchE.started"
chmod 000 "$R2/.claude/dispatch"
run_ds "$R2" batchE
_dc7_rc=$DS_RC; _dc7_out=$DS_OUT
run_ds "$R2" neverdispatched
_dc7_rc2=$DS_RC
chmod 755 "$R2/.claude/dispatch"
if [ "$_dc7_rc" = 3 ] && [ "$_dc7_rc2" = 3 ]; then
  ok "DC7: an unsearchable state directory exits 3 for every id, never NONE"
else
  bad "DC7: expected rc=3 for both ids, got $_dc7_rc and $_dc7_rc2 (out: $_dc7_out)"
fi

# ===========================================================================
# DC8 — it never writes. A checker that creates the thing it checks answers its own question.
# ===========================================================================
R3="$TMP/r3"; mkdir -p "$R3"
_before=$(find "$R3" | sort)
bash "$DS" "$R3" someid >/dev/null 2>&1
_after=$(find "$R3" | sort)
[ "$_before" = "$_after" ] \
  && ok "DC8: a NONE query creates nothing under the root" \
  || bad "DC8: the helper wrote something: $(printf '%s\n' "$_after" | tail -3)"

# ===========================================================================
# DC10-DC12 — the two converted call sites consult the helper.
# Prose is matched flat and undecorated (ADR-0073/0076/0080/0098/0101).
# ===========================================================================
FLAT=$(tr '\n' ' ' <"$CC" | tr -d '`*' | tr -s ' ')

case "$FLAT" in
  *"Measure nothing until the coder has finished"*)
    ok "DC10: Step 4.5 states the ordering requirement before its filesystem measurement" ;;
  *) bad "DC10: Step 4.5 does not state that measurement waits for completion" ;;
esac

case "$FLAT" in
  *"Do not look for PATTERN: DONE in the agent's report"*)
    ok "DC11: Step 5 forbids the transcript check the 2.1.232 change invalidated" ;;
  *) bad "DC11: Step 5 does not forbid reading PATTERN: DONE from the report" ;;
esac

_gates=$(grep -c "dispatch-state.sh" "$CC" 2>/dev/null || true)
[ "${_gates:-0}" -ge 2 ] \
  && ok "DC12: concept-to-code consults dispatch-state.sh at both converted sites ($_gates references)" \
  || bad "DC12: expected >= 2 dispatch-state.sh references in concept-to-code, found ${_gates:-0}"

# ===========================================================================
# DC20-DC22 — the declared population, forward.
#
# ADR-0124: a floor with slack absorbs its own plant, so the identity of every declaration is
# frozen rather than counted. The count guard below is a VACUITY guard only, and says so.
# ===========================================================================
DECLS=$(grep -rhoE 'dispatch-site: [a-z0-9-]+' "$SKILLS"/*/SKILL.md 2>/dev/null | sed 's/dispatch-site: //' | sort)
DECL_N=$(printf '%s\n' "$DECLS" | grep -c . || true)

[ "${DECL_N:-0}" -ge 10 ] \
  && ok "DC20: the declared dispatch-site population is non-vacuous ($DECL_N declarations)" \
  || bad "DC20: only ${DECL_N:-0} dispatch-site declarations found — the derivation collapsed"

EXPECTED="deep-refactor-fix-agents
deep-refactor-reviewers
gate506-reviewers
rtf-advisor-pair
rtf-fix-agents
rtf-step1-reviewer
rtf-step4-rereview
security-audit-reviewer
step2-architect
step5-batch-coder
step5-batch-tester
step5-checkpoint-reviewer
tracer-bullet-coder"
if [ "$DECLS" = "$EXPECTED" ]; then
  ok "DC21: the declared set matches the frozen baseline exactly"
else
  bad "DC21: declared set drifted from the baseline — diff: $(printf '%s\n' "$DECLS" | comm -3 - <(printf '%s\n' "$EXPECTED") | tr '\n' ' ')"
fi

# Every declaration carries a class, and the class domain is closed. A type is not a value set
# (ADR-0125): an unrecognised class must fail rather than be carried as free text.
_badclass=0
while IFS= read -r _line; do
  [ -n "$_line" ] || continue
  case "$_line" in
    *"class=isolated"*|*"class=inline"*) ;;
    *) _badclass=$((_badclass+1)) ;;
  esac
done <<EOF
$(grep -rh "dispatch-site:" "$SKILLS"/*/SKILL.md 2>/dev/null)
EOF
[ "$_badclass" = 0 ] \
  && ok "DC22: every declaration carries class=isolated or class=inline" \
  || bad "DC22: $_badclass declaration(s) carry no recognised class"

# An exemption must state a reason long enough to be a reason. Same floor as every other waiver
# in this repo (>= 40 characters after the marker).
_shortreason=0
while IFS= read -r _line; do
  case "$_line" in
    *"exempt:"*)
      _r=${_line#*exempt:}
      _r=${_r%-->}
      _n=$(printf '%s' "$_r" | tr -d ' ' | wc -c | tr -d ' ')
      [ "$_n" -ge 40 ] || _shortreason=$((_shortreason+1))
      ;;
  esac
done <<EOF
$(grep -rh "dispatch-site:" "$SKILLS"/*/SKILL.md 2>/dev/null)
EOF
[ "$_shortreason" = 0 ] \
  && ok "DC23: every exemption states a reason of at least 40 characters" \
  || bad "DC23: $_shortreason exemption(s) carry a reason shorter than 40 characters"

# ===========================================================================
# DC24 — BACKWARD. The direction a declared population cannot check by itself (rule 8, ADR-0107).
#
# Every file that dispatches a subagent at all must carry at least one declaration. This does not
# prove each individual site is declared — no needle can, which is the finding above — but it does
# catch the failure that matters: a skill that grows a dispatch and declares nothing.
# ===========================================================================
_undeclared=""
for _s in "$SKILLS"/*/SKILL.md; do
  grep -qE 'subagent_type|Dispatch the `(reviewer|coder|tester|architect|refactorer|debugger)`|Dispatch `(reviewer|coder|tester|architect)`' "$_s" 2>/dev/null || continue
  grep -q "dispatch-site:" "$_s" 2>/dev/null && continue
  # A skill may forbid dispatch outright; that is a declaration of a different kind.
  grep -qiE "never dispatch|NEVER dispatch a sub-agent|NOT the .Agent. tool" "$_s" 2>/dev/null && continue
  _undeclared="$_undeclared $(basename "$(dirname "$_s")")"
done
[ -z "$_undeclared" ] \
  && ok "DC24: every skill that dispatches a subagent carries at least one declaration" \
  || bad "DC24: skill(s) dispatch a subagent and declare no site:$_undeclared"

# ===========================================================================
# DC25 — STALE WAIVER (rule 9). An exemption on a site that DOES gate on the helper is a waiver
# that outlived its reason. The two converted sites must not carry one.
# ===========================================================================
_stale=0
for _id in step5-batch-coder tracer-bullet-coder; do
  grep -rh "dispatch-site: $_id" "$SKILLS"/*/SKILL.md 2>/dev/null | grep -q "exempt:" && _stale=$((_stale+1))
done
[ "$_stale" = 0 ] \
  && ok "DC25: neither converted site carries a stale exemption" \
  || bad "DC25: $_stale converted site(s) still carry an exemption they no longer need"

# ===========================================================================
# DC13-DC14 — the two fence contracts are EXECUTED, not merely declared (ADR-0083 F4).
#
# Hermetic by construction: CLAUDE_PLUGIN_ROOT points at this repository's staging tree, so the
# fences resolve the helper from the checkout and never from a deployed $HOME copy. A harness that
# silently exercised ~/.claude would pass on this machine and fail in CI.
# ===========================================================================
extract_fence() {
  awk -v id="$1" '
    $0 ~ ("fence-contract: " id " -->") { f=1; next }
    f && /^```bash$/ { g=1; next }
    g && /^```$/ { exit }
    g { print }
  ' "$2"
}

# run_fence "<contract-id>" <skill-md> <setup-script-path> -> echoes the exit code
run_fence() {
  _body=$(extract_fence "$1" "$2")
  [ -n "$_body" ] || { echo "EXTRACT_EMPTY"; return; }
  _s="$TMP/fence-$1.sh"
  { cat "$3"; printf '\n%s\n' "$_body"; } > "$_s"
  ( bash "$_s" >"$TMP/out-$1" 2>&1 ); echo "$?"
}

PLUGIN_ROOT="$STAGING/plugin"

SETUP5="$TMP/setup5.sh"
WT_OK="$TMP/wt-ok"; mkdir -p "$WT_OK/.claude/dispatch"
printf 'tasks=2 files=5\n' > "$WT_OK/.claude/dispatch/step5-batch-1.done"
WT_PEND="$TMP/wt-pend"; mkdir -p "$WT_PEND/.claude/dispatch"
: > "$WT_PEND/.claude/dispatch/step5-batch-1.started"

printf 'export CLAUDE_PLUGIN_ROOT=%s\nexport WT=%s\nexport B=1\n' "$PLUGIN_ROOT" "$WT_OK" > "$SETUP5"
RC=$(run_fence "step5-batch-completion-gate" "$CC" "$SETUP5")
[ "$RC" = 0 ] \
  && ok "DC13: the Step 5 gate exits 0 on a DONE completion fact" \
  || bad "DC13: expected rc=0 on DONE, got '$RC' — $(head -2 "$TMP/out-step5-batch-completion-gate" 2>/dev/null)"

printf 'export CLAUDE_PLUGIN_ROOT=%s\nexport WT=%s\nexport B=1\n' "$PLUGIN_ROOT" "$WT_PEND" > "$SETUP5"
RC=$(run_fence "step5-batch-completion-gate" "$CC" "$SETUP5")
[ "$RC" = 2 ] \
  && ok "DC13b: the Step 5 gate refuses to advance on PENDING" \
  || bad "DC13b: expected rc=2 on PENDING, got '$RC' — $(head -2 "$TMP/out-step5-batch-completion-gate" 2>/dev/null)"

SETUPT="$TMP/setupt.sh"
PR_OK="$TMP/pr-ok"; mkdir -p "$PR_OK/.claude/worktrees/agent-a/.claude/dispatch"
printf 'tasks=1 files=3\n' > "$PR_OK/.claude/worktrees/agent-a/.claude/dispatch/tracer-bullet.done"
PR_NONE="$TMP/pr-none"; mkdir -p "$PR_NONE/.claude/worktrees/agent-a"

printf 'export CLAUDE_PLUGIN_ROOT=%s\nexport project_root=%s\n' "$PLUGIN_ROOT" "$PR_OK" > "$SETUPT"
RC=$(run_fence "tracer-bullet-completion-gate" "$CC" "$SETUPT")
[ "$RC" = 0 ] \
  && ok "DC14: the tracer gate exits 0 when the marker is found inside a worktree" \
  || bad "DC14: expected rc=0, got '$RC' — $(head -2 "$TMP/out-tracer-bullet-completion-gate" 2>/dev/null)"

printf 'export CLAUDE_PLUGIN_ROOT=%s\nexport project_root=%s\n' "$PLUGIN_ROOT" "$PR_NONE" > "$SETUPT"
RC=$(run_fence "tracer-bullet-completion-gate" "$CC" "$SETUPT")
[ "$RC" = 2 ] \
  && ok "DC14b: the tracer gate computes no verdict when nothing was written" \
  || bad "DC14b: expected rc=2, got '$RC' — $(head -2 "$TMP/out-tracer-bullet-completion-gate" 2>/dev/null)"

# ===========================================================================
echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
