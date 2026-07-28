#!/bin/bash
# worktree-isolation-contract.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Targets staging/ directly, never the deployed $HOME/.claude/ copy.
# Run: bash worktree-isolation-contract.test.sh
#
# Covers issue #176 / ADR-0068, Task 2 only (R-01, R-11, R-19). This file grows further with
# Tasks 4, 5, 6, 7 and 8 of the same plan; sections C onward do not exist yet.
#
# Section G (Task 5, R-05/R-17): the fourth Step 5 pre-flight assertion (Step 5.0.4,
# worktree.baseRef == "head"). EXPECTED at RED time: G1-G4 all FAIL. Neither
# concept-to-code/SKILL.md nor autopilot-build/SKILL.md mentions "baseRef" anywhere yet (confirmed
# absent before this section was written); Task 5's GREEN step adds Step 5.0.4 to the former and
# restates it in the latter's existing Recovery-readiness pre-flight restatement paragraph.
#
# Task 2's EXPECTED result, seen once and recorded here so a future reader does not mistake a
# checkpoint for fix evidence: sections A and B are RED (the two bad `isolation: "none"` /
# `isolation: none` prescriptions and the dirty-tree condition blocks still exist in this
# codebase — Task 3 removes them). Sections A2, A3 and B2 are GREEN from the start: they are
# forward guards proving the detectors themselves work, not proof that the defect is fixed.
#
# Section A is an ALLOWLIST over discovered `isolation` values (worktree|remote), never a
# denylist of `none` — a denylist cannot see the next invented value (the ADR-0043 direction
# lesson, applied at the schema level). Section B anchors on the compound phrase surrounding
# each dirty-tree isolation-selection block, never on the bare `git diff HEAD --name-only`,
# which legitimately survives in review-triage-fix/SKILL.md (ADR-0068 §D9) for an unrelated
# reason (stale-worktree pre-check, not isolation selection) — section B2 is the positive twin
# proving that survival is intentional, not an oversight this file failed to notice.
#
# Sections C onward (Task 4, R-02/R-04): no `worktree-create.sh` hook exists, and section D
# forbids registering one. The reason is not a preference — it was measured, and this is the
# evidence a future proposer must read before reopening the question (ADR-0068 Measured facts
# annex):
#
#   F13 — the `WorktreeCreate` stdin payload carries exactly six fields: `session_id`,
#   `transcript_path`, `cwd`, `prompt_id`, `hook_event_name`, `name`. There is no `agent_type`
#   and no `agent_id`, so a registered hook has no field to scope itself on — it cannot tell
#   which dispatch it is being asked about. (F17: the `session_id`/`transcript_path` in that
#   payload belong to the *dispatching* session, not the subagent about to run, because the
#   event fires before the subagent exists — there is no subagent identity to read even in
#   principle.)
#
#   F14 — exit 0 with empty stdout does NOT decline and fall through to default git behaviour.
#   It aborts the dispatch outright (`WorktreeCreate hook failed: hook succeeded but returned no
#   worktree path`). A registered hook must return a usable worktree path on every single
#   invocation or every dispatch on the machine fails.
#
#   Together, and combined with the fact that `WorktreeCreate` has no matcher: a hook that
#   cannot discriminate (F13) and cannot decline (F14) means registering ANY such hook makes it
#   the owner of every worktree creation on this machine, in every project, chain-related or not.
#   That is the entire reason sections C and D exist in this file — C declares the one-layer
#   replacement (`worktree.baseRef: "head"`, a settings key, not a hook); D asserts nothing
#   registers the event.
#
#   These facts are true of CC 2.1.220 and are build-specific, not permanent (the ADR-0016
#   v2.1.154 lesson: the substrate moves underneath a running system). A future build that adds
#   an agent discriminator and an abstain state to `WorktreeCreate` reopens this question on its
#   merits. The answer then is to re-run the probe (ADR-0068 Task 1), not to re-read this
#   comment as settled.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
REPO=$(cd "$STAGING/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

CC="$STAGING/plugin/skills/concept-to-code/SKILL.md"
AB="$STAGING/plugin/skills/autopilot-build/SKILL.md"
RTF="$STAGING/plugin/skills/review-triage-fix/SKILL.md"

# ==============================================================================================
# Shared extractor for section A. Matches `isolation:` followed (after optional space and an
# optional `"` or `<`) by an alpha token — this single pattern reaches every prescription form
# seen in this codebase: `isolation: worktree`, `isolation: "none"`, `isolation:none` (a heading),
# and the templated `isolation: <none if ISOLATION_MODE=none, else worktree>`. It is deliberately
# NOT anchored on `none` anywhere — see the module docstring above.
# ==============================================================================================
extract_isolation_values() {
  grep -ohE 'isolation:[[:space:]]*["<]?[A-Za-z_]+' "$1" 2>/dev/null \
    | sed -E 's/^isolation:[[:space:]]*["<]?//'
}

# ==============================================================================================
# Section A — schema conformance (R-01). Allowlist over discovered values, count-guarded.
# ==============================================================================================
ALL_VALUES="$TMP/all-isolation-values.txt"
: > "$ALL_VALUES"
for f in "$STAGING"/plugin/skills/*/SKILL.md "$STAGING"/plugin/agents/*.md; do
  [ -f "$f" ] || continue
  extract_isolation_values "$f" >> "$ALL_VALUES"
done

VALUE_COUNT=$(grep -c . "$ALL_VALUES" 2>/dev/null || true)
case "$VALUE_COUNT" in ''|*[!0-9]*) VALUE_COUNT=0 ;; esac
if [ "$VALUE_COUNT" -ge 1 ]; then
  ok "A0: at least one isolation value was discovered across staging/ (count=$VALUE_COUNT) — the extractor is not vacuous"
else
  bad "A0: zero isolation values discovered — the extractor is broken and every assertion below is meaningless"
fi

BAD_VALUES=$(grep -vE '^(worktree|remote)$' "$ALL_VALUES" 2>/dev/null | sort -u)
if [ -z "$BAD_VALUES" ]; then
  ok "A1: every discovered isolation value is one of worktree|remote"
else
  bad "A1: non-conforming isolation value(s) found (Agent tool rejects these): $(printf '%s' "$BAD_VALUES" | tr '\n' ' ')"
fi

# ==============================================================================================
# Section A2 — positive twin (forward guard, green from the start). Without this, a regex that
# matches nothing would pass section A for the wrong reason (the cfile=/dev/null lesson).
# ==============================================================================================
CODER_MD="$STAGING/plugin/agents/coder.md"
CODER_VALUES=$(extract_isolation_values "$CODER_MD")
if printf '%s\n' "$CODER_VALUES" | grep -qx 'worktree'; then
  ok "A2 (forward guard): the extractor actually finds 'worktree' on agents/coder.md:8"
else
  bad "A2 (forward guard): the extractor found no 'worktree' value on agents/coder.md — it is not extracting real prescriptions"
fi

# ==============================================================================================
# Section A3 — synthetic invented value (forward guard, green from the start). Proves section A
# is a forward guard against the NEXT invented value, not merely a record of today's two bad
# ones (`none`, and its `<none if ...>` templated form).
# ==============================================================================================
FIXTURE_A3="$TMP/fixture-a3.md"
printf 'fixture frontmatter\nisolation: sandbox\nend fixture\n\nSome prose that never says the word.\n' > "$FIXTURE_A3"
A3_VALUES=$(extract_isolation_values "$FIXTURE_A3")
A3_BAD=$(printf '%s\n' "$A3_VALUES" | grep -vE '^(worktree|remote)$' 2>/dev/null)
if [ -n "$A3_BAD" ]; then
  ok "A3 (forward guard): a fixture naming 'isolation: sandbox' is correctly flagged as non-conforming"
else
  bad "A3 (forward guard): the invented value 'sandbox' was NOT flagged — section A cannot see a future invented value"
fi

# ==============================================================================================
# Section B — dirty-tree retirement (R-11). Anchored on the compound phrase surrounding each
# isolation-selection block, never on the bare `git diff HEAD --name-only` (ADR-0068 §D9).
# Three call sites: concept-to-code's Workflow-path block, concept-to-code's Agent-tool-fallback
# block, and autopilot-build's restatement.
# ==============================================================================================
if grep -qF 'Non-empty output → dispatch that task group'"'"'s coder **with** `isolation: "none"`' "$CC" 2>/dev/null; then
  bad "B1: concept-to-code Workflow-path dirty-tree isolation-selection block still present"
else
  ok "B1: concept-to-code Workflow-path dirty-tree isolation-selection block is gone"
fi

if grep -qF 'Non-empty output → dispatch this batch'"'"'s coder **with** `isolation: "none"`' "$CC" 2>/dev/null; then
  bad "B1b: concept-to-code Agent-tool-fallback dirty-tree isolation-selection block still present"
else
  ok "B1b: concept-to-code Agent-tool-fallback dirty-tree isolation-selection block is gone"
fi

if grep -qF 'dispatch that group'"'"'s coder with `isolation: "none"`' "$AB" 2>/dev/null; then
  bad "B1c: autopilot-build dirty-tree isolation-selection block still present"
else
  ok "B1c: autopilot-build dirty-tree isolation-selection block is gone"
fi

# ==============================================================================================
# Section B2 — D9 guard (forward guard, green from the start). review-triage-fix's stale-worktree
# pre-check greps the identical `git diff HEAD --name-only` command but selects dispatch-versus-
# inline, not one isolation value versus another (ADR-0068 §D9), and must SURVIVE. A test that
# removes too much is the failure mode this section exists to catch.
# ==============================================================================================
if grep -qF 'Stale-worktree pre-check' "$RTF" 2>/dev/null && grep -qF 'git -C <root> diff HEAD --name-only' "$RTF" 2>/dev/null; then
  ok "B2 (forward guard / D9): review-triage-fix's stale-worktree pre-check still contains its git diff HEAD --name-only check"
else
  bad "B2 (forward guard / D9): review-triage-fix's stale-worktree pre-check is missing or its git diff HEAD --name-only check is gone — ADR-0068 §D9 requires this block to survive"
fi

# ==============================================================================================
# CI registration (R-19): both registries.
# ==============================================================================================
DOCSCI="$REPO/.github/workflows/docs-ci.yml"
CIYML="$REPO/.github/workflows/ci.yml"

DOCSCI_LOOP=$(grep 'for t in ' "$DOCSCI" 2>/dev/null | head -1)
if printf '%s' "$DOCSCI_LOOP" | grep -qE '[[:space:]]worktree-isolation-contract[[:space:];]'; then
  ok "CI1: docs-ci.yml's shell-tests loop list runs worktree-isolation-contract"
else
  bad "CI1: worktree-isolation-contract is not in docs-ci.yml's explicit harness list"
fi

if grep -qF 'staging/plugin/scripts/tests/*.test.sh' "$CIYML" 2>/dev/null; then
  ok "CI2: ci.yml still runs the automatic glob over staging/plugin/scripts/tests/*.test.sh (forward guard — no manual edit needed there)"
else
  bad "CI2: ci.yml no longer uses the automatic *.test.sh glob"
fi

# ==============================================================================================
# Section C (R-02) — the mechanism is declared. Parsed with python3 -c, NEVER grep: a grep for
# "head" would match a comment, a sibling key, or a value under the wrong parent. Task 1b retired
# `worktree-create.sh` as a premise F13/F14 refuted; this is the one-layer replacement — a
# settings key, not a hook.
#
# EXPECTED at RED time (Task 4 not yet implemented): C1 fails, because
# staging/user/settings.json:300 still declares "baseRef": "fresh". C1a and C1b are forward
# guards and are green from the start — they prove the predicate itself is sound, not that the
# defect is fixed (the cfile=/dev/null lesson, again).
# ==============================================================================================
SETTINGS_JSON="$STAGING/user/settings.json"

baseref_predicate() {
  # $1 = path to a settings.json-shaped file. Exit 0 iff worktree.baseRef == "head".
  python3 -c "
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
sys.exit(0 if d.get('worktree', {}).get('baseRef') == 'head' else 1)
" "$1"
}

if baseref_predicate "$SETTINGS_JSON"; then
  ok "C1: staging/user/settings.json declares worktree.baseRef == \"head\" (R-02)"
else
  bad "C1: staging/user/settings.json does not declare worktree.baseRef == \"head\" (R-02) — still \"fresh\""
fi

# Positive twin 1: the parse actually finds a 'worktree' object at all. Without this, a predicate
# that silently defaults a missing key to {} and then compares None != "head" would pass C1 for
# the wrong reason if the key were ever renamed instead of corrected.
WORKTREE_OBJ_PRESENT=$(python3 -c "
import json
d = json.load(open('$SETTINGS_JSON'))
print('yes' if isinstance(d.get('worktree'), dict) else 'no')
" 2>/dev/null)
if [ "$WORKTREE_OBJ_PRESENT" = "yes" ]; then
  ok "C1a (forward guard): a 'worktree' object is actually present in settings.json, not a vacuous default"
else
  bad "C1a (forward guard): no 'worktree' object found in settings.json — C1 would pass on a None default"
fi

# Positive twin 2: the same predicate returns non-zero against a fixture declaring "baseRef":
# "fresh" — proving the predicate can actually fail, not just pass by construction.
FIXTURE_C="$TMP/fixture-baseref-fresh.json"
printf '{"worktree": {"baseRef": "fresh"}}\n' > "$FIXTURE_C"
if baseref_predicate "$FIXTURE_C"; then
  bad "C1b (forward guard): predicate wrongly passed a fixture declaring baseRef=\"fresh\""
else
  ok "C1b (forward guard): predicate correctly rejects a fixture declaring baseRef=\"fresh\""
fi

# ==============================================================================================
# Section C2 (R-02) — the deployment path is declared. Static prose anchor: sync-to-claude.sh
# never edits settings.json (ADR-0025), so the baseRef key reaches the live file only through a
# MANUAL STEP notice. The notice text itself and its behavioural gating (fires when absent/wrong,
# suppressed when correct) are Task 5's sync-manual-steps.test.sh assertions, not this file's —
# this section only pins that the block exists and names the key and its value.
#
# EXPECTED at RED time: FAILS. No such block exists yet anywhere in sync-to-claude.sh (Task 5
# adds it, not Task 4) — disclosed, not fixed, by this dispatch.
# ==============================================================================================
SYNCSH="$STAGING/sync-to-claude.sh"

if grep -qF 'MANUAL STEP: settings key' "$SYNCSH" 2>/dev/null \
   && grep -qF 'baseRef' "$SYNCSH" 2>/dev/null \
   && grep -qF '"head"' "$SYNCSH" 2>/dev/null; then
  ok "C2: sync-to-claude.sh has a MANUAL STEP block naming the baseRef settings key and the literal value \"head\""
else
  bad "C2: sync-to-claude.sh has no MANUAL STEP block naming the baseRef key and its literal value \"head\" (R-02, R-17 — Task 5 adds this, not Task 4)"
fi

# ==============================================================================================
# Section D (R-04) — nothing registers the event. Layer 2 of the original two-layer contract
# (a WorktreeCreate hook) is deleted (F13/F14): no such hook ships. Detector checks the effective
# settings.json's hooks object AND sync-to-claude.sh's PAIRS list, since either one could
# reintroduce the registration.
#
# Positive twin is MANDATORY (ADR-0043 direction lesson / ADR-0039 cfile=/dev/null correction): a
# detector reporting nothing must be distinguishable from a subject that contains nothing. D1c
# runs the same detector against a fixture that DOES register the hook and must fire there.
# ==============================================================================================
worktree_create_registered() {
  # $1 = path to a settings.json-shaped file. Exit 0 iff a "WorktreeCreate" hook is registered.
  python3 -c "
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
hooks = d.get('hooks', {})
sys.exit(0 if 'WorktreeCreate' in hooks else 1)
" "$1"
}

if worktree_create_registered "$SETTINGS_JSON"; then
  bad "D1: staging/user/settings.json's hooks object registers WorktreeCreate — R-04 violated"
else
  ok "D1: staging/user/settings.json's hooks object registers no WorktreeCreate hook"
fi

if grep -qE '\|[^|]*worktree-create' "$SYNCSH" 2>/dev/null; then
  bad "D1b: sync-to-claude.sh's PAIRS list has an entry whose destination lands a worktree-create hook"
else
  ok "D1b: sync-to-claude.sh's PAIRS list has no entry landing a worktree-create hook"
fi

# Positive twin, mandatory: same detector, run over a fixture that DOES register WorktreeCreate.
FIXTURE_D="$TMP/fixture-worktreecreate.json"
cat > "$FIXTURE_D" <<'EOF'
{"hooks": {"WorktreeCreate": [{"hooks": [{"type": "command", "command": "echo hi"}]}]}}
EOF
if worktree_create_registered "$FIXTURE_D"; then
  ok "D1c (positive twin, mandatory): the detector fires on a fixture that registers WorktreeCreate"
else
  bad "D1c (positive twin, mandatory): the detector did NOT fire on a fixture that registers WorktreeCreate — D1/D1b cannot be trusted to catch a real regression"
fi

# ==============================================================================================
# Section D2 (R-04) — the retained instrument is labelled. worktree-capture.sh stays in the tree
# (it is F13's and F17's evidence) but must never be wired: registering it aborts every worktree
# creation on the machine (F14), and there is no matcher to scope it. Its header must say so, and
# it must never be deployed.
#
# EXPECTED at RED time: D2b FAILS. The current header (as of Task 1) still states the three-
# exit-state DECLINE contract F14 refuted — it does not yet name it a "measuring instrument" nor
# state F14's consequence in those words. Task 4's GREEN step rewrites it.
# ==============================================================================================
WTCAP="$STAGING/plugin/scripts/worktree-capture.sh"

if [ -f "$WTCAP" ]; then
  ok "D2a: worktree-capture.sh exists"
else
  bad "D2a: worktree-capture.sh is missing — it is F13's and F17's evidence and must be retained"
fi

if grep -qF 'measuring instrument' "$WTCAP" 2>/dev/null \
   && grep -qF 'every worktree creation on the machine' "$WTCAP" 2>/dev/null; then
  ok "D2b: worktree-capture.sh's header names it a measuring instrument and states F14's consequence (every worktree creation on the machine aborts)"
else
  bad "D2b: worktree-capture.sh's header does not yet call it a measuring instrument / state F14's abort-everything consequence — it still teaches the refuted decline belief"
fi

if grep -qE '(^|[[:space:]])plugin/scripts/worktree-capture\.sh\|' "$SYNCSH" 2>/dev/null; then
  bad "D2c: worktree-capture.sh has a PAIRS entry — it must never deploy to ~/.claude/hooks/ (a file next to a wiring note reads like something to wire)"
else
  ok "D2c: worktree-capture.sh has no PAIRS entry (staging-only, like hook-probe-sandbox.sh / hook-probe.sh / hook-probe-verify.sh)"
fi

# ==============================================================================================
# Section D3 — the reason is in THIS test file's own header. Self-referential on purpose: the
# next person to propose re-registering the hook reads the test that forbids it, and the test
# must carry the evidence (F13, F14), not just the prohibition.
#
# EXPECTED at RED time: FAILS. This file's pre-existing Task 2 header (lines 1-21) predates F13/
# F14 and names neither. Task 4 adds them to the header as part of turning this section green.
# ==============================================================================================
THIS_FILE="$0"
HEADER=$(sed -n '1,60p' "$THIS_FILE" 2>/dev/null)
if printf '%s' "$HEADER" | grep -q 'F13' && printf '%s' "$HEADER" | grep -q 'F14'; then
  ok "D3: this test file's own header names F13 and F14 as the reason no WorktreeCreate hook exists"
else
  bad "D3: this test file's own header does not name F13 and F14 — the prohibition has no evidence attached to it"
fi

# ==============================================================================================
# Section G (R-05, R-17) — Step 5's fourth pre-flight assertion, the settings key that governs
# it (ADR-0068 §D1), and its restatement on the autopilot path (ADR-0050 §D6, no leniency).
#
# EXPECTED at RED time: G1-G4 all FAIL. "baseRef" appears in neither SKILL.md today (verified
# above by direct grep before this section existed), so every conjunct below is unmet.
# ==============================================================================================
CC_STEP5="$TMP/cc-step5.txt"
awk '/^### Step 5 —/{f=1} /^### Step 6 —/{f=0} f' "$CC" >"$CC_STEP5" 2>/dev/null

# G1: the fourth assertion exists, named Step 5.0.4, and names both the key (worktree.baseRef)
# and the literal required value ("head"). Three conjuncts so a partial mention (heading added
# but key/value prose forgotten, or vice versa) still fails.
if grep -qF 'Step 5.0.4' "$CC_STEP5" 2>/dev/null \
   && grep -qF 'worktree.baseRef' "$CC_STEP5" 2>/dev/null \
   && grep -qF '"head"' "$CC_STEP5" 2>/dev/null; then
  ok "G1: concept-to-code Step 5 has a Step 5.0.4 assertion naming worktree.baseRef and the literal value \"head\""
else
  bad "G1: concept-to-code Step 5 is missing Step 5.0.4 / worktree.baseRef / the literal \"head\" value (R-05) — Task 5 adds this"
fi

# G2: the literal remediation command is present, not just a description of what it should say.
# Anchored on three distinctive fragments of the plan's own literal sentence — none of these
# three strings exists anywhere in concept-to-code/SKILL.md today (verified: zero hits pre-Task 5).
if grep -qF 'Recovery-readiness pre-flight: set' "$CC_STEP5" 2>/dev/null \
   && grep -qF 're-invoke Step 5' "$CC_STEP5" 2>/dev/null \
   && grep -qF 'ADR-0068 F15' "$CC_STEP5" 2>/dev/null; then
  ok "G2: Step 5.0.4 names the literal remediation command citing ADR-0068 F15"
else
  bad "G2: Step 5.0.4 is missing the literal remediation command (R-05) — Task 5 adds this"
fi

# G3: the assertion states explicitly that it fails CLOSED — a missing, unreadable or unparseable
# settings.json counts as NOT verified. This is the one component in the whole repository that
# fails closed (ADR-0068 §D3), the opposite of every hook's convention, so it must say so in
# words a reader who pattern-matches on the hook convention would otherwise miss.
if grep -qF 'missing or unparseable' "$CC_STEP5" 2>/dev/null \
   && grep -qF 'fails closed' "$CC_STEP5" 2>/dev/null; then
  ok "G3: Step 5.0.4 states that a missing/unreadable/unparseable settings.json is NOT verified (fails closed, ADR-0068 §D3)"
else
  bad "G3: Step 5.0.4 does not state the fail-closed behaviour for a missing/unparseable settings.json (R-05) — Task 5 adds this"
fi

# G4: autopilot-build restates the assertion (no leniency branch, ADR-0050 §D6) and records the
# failure in the report rather than prompting — the same "recorded in the report" phrase already
# used for the other three assertions (recovery-preflight.test.sh RF3), now co-occurring with a
# mention of baseRef so this conjunct cannot pass on the pre-existing text alone.
AB_STEP5="$TMP/ab-step5.txt"
awk '/^#### Step 5 —/{f=1} /^#### Step 6 —/{f=0} f' "$AB" >"$AB_STEP5" 2>/dev/null
if grep -qF 'baseRef' "$AB_STEP5" 2>/dev/null \
   && grep -qF 'recorded in the report' "$AB_STEP5" 2>/dev/null; then
  ok "G4: autopilot-build restates the baseRef assertion and records the failure in the report rather than prompting (ADR-0050 §D6, no leniency)"
else
  bad "G4: autopilot-build's Recovery-readiness pre-flight restatement does not yet mention baseRef (R-05, R-17) — Task 5 adds this"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
