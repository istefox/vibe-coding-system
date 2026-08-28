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
# Section H (Task 6, R-06/R-07/R-08/R-09/R-14): explicit isolation on the tester stage and on
# Step 6's fix-agent dispatch, the merge-back block (positioned between the tester and coder stage
# headings), the base-fork audit (capture-before-commit ordering, halt on mismatch), and a
# no-effort-on-Agent(...) sweep. Most of section H is RED at the time it was written — see the
# per-assertion EXPECTED comment immediately above the section for the full RED/GREEN split,
# including which parts were already satisfied by prior tasks and one pre-existing defect (an
# `effort` key on a real `Agent(...)` call, ADR-0068 §D7) this section's general sweep found
# rather than introduced. Task 6's GREEN step turns H1b, H2, H2b, H3, H3b, H4a, H5, H5b and H7
# green; H1, H1c, H4b, H6, H6b, H6c, H7a and H7b are already green (forward guards or prior work).
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
STEP5_REF="$STAGING/plugin/skills/concept-to-code/references/step5-implementation.md"
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
# The Step 5 range moved to references/step5-implementation.md (VCS-047, ADR-0174); the
# reference file's body IS the block, so no awk range is needed any more.
cp "$STEP5_REF" "$CC_STEP5" 2>/dev/null

if [ -s "$CC_STEP5" ]; then
  ok "G0: concept-to-code Step 5 (references/step5-implementation.md) is extractable (G1-G4 below read)"
else
  bad "G0: could not read references/step5-implementation.md — G1-G4 below would pass vacuously (empty extract, negative-shaped risk)"
fi

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

# ==============================================================================================
# Section H (Task 6, R-06, R-07, R-08, R-09, R-14) — the stage protocol: explicit isolation on
# both dispatch paths, tester in a worktree, orchestrator merge-back, and the base-fork audit
# (ADR-0068 §D5, §D6, §D7, §D9).
#
# EXPECTED at RED time (Task 6 GREEN not yet run):
#   H1   GREEN — Step 5 Stage 2 (Workflow path) already pins isolation: "worktree" (prior task's
#                work, confirmed present at the time this section was written).
#   H1b  RED   — Step 6 Phase 3's fix-agent dispatch (agentType is chosen at runtime from
#                fix_type, which includes "coder") carries no isolation key at all yet.
#   H1c  GREEN — the Agent-tool fallback's coder dispatch (item 2) already pins isolation:
#                "worktree" explicitly (same prior work as H1).
#   H2   RED   — Step 5 Stage 1 (Workflow path) tester dispatch names no isolation value.
#   H2b  RED   — the Agent-tool fallback's tester dispatch (item 1) names no isolation value.
#   H3   RED   — no merge-back block exists anywhere naming worktreePath/worktreeBranch.
#   H3b  RED   — positional: no merge-back heading exists to sit between the tester stage heading
#                and the coder stage heading (the recovery-preflight.test.sh RE5 idiom: compare
#                line numbers of two located headings).
#   H4a  RED   — no "nothing to merge" wording exists for the auto-removed/empty-diff case.
#   H4b  GREEN (trivially, absence-of-flag) — no --allow-empty flag exists either, since nothing
#                exists yet. Kept as its own assertion (not folded into H4a) because R-14 is a
#                positive claim ("nothing to merge") AND a negative one ("no empty commit") —
#                folding them would let a future implementation satisfy one silently at the
#                other's expense.
#   H5   RED   — no base-fork capture-before-commit ordering exists (neither literal is present).
#   H5b  RED   — no base-fork mismatch halt language exists.
#   H6   GREEN (forward guard) — agents/coder.md already states "never commit(s)"; unchanged by
#                this feature, and ADR-0068 §D5 explicitly keeps it that way (R-08).
#   H6b  GREEN (forward guard) — neither SKILL.md contains an affirmative "instruct the coder to
#                commit" phrasing today (verified by direct grep before this section was written).
#   H6c  GREEN (forward guard, mandatory positive twin) — the H6b detector, run against a
#                synthetic fixture that DOES instruct a coder to commit, correctly flags it.
#   H7a  GREEN (forward guard) — at least one Agent(...) (Agent-tool, capital A) call block exists
#                in concept-to-code/SKILL.md; the paragraph-split extractor is not vacuous.
#   H7   RED   — one existing Agent(...) call (the Step 4.5 tracer-bullet probe dispatch,
#                concept-to-code/SKILL.md ~line 609) already carries an "effort" key, which the
#                Agent tool does not accept (ADR-0068 §D7: opts.effort is Workflow-only). This is
#                a pre-existing defect this dispatch found while writing the general assertion the
#                plan asked for, not something Task 6 introduces — flagged here, not fixed (tests
#                only; a tester never edits production code).
#   H7b  GREEN (forward guard, mandatory positive twin, synthetic fixture) — the same detector,
#                applied to a fixture pairing a violating Agent(...) block with a correctly-formed
#                Workflow-style agent(...) block that ALSO carries effort, flags only the former —
#                proving the check discriminates on call syntax (capital A, literal parenthesis),
#                not merely on the word "effort" (which would false-positive on every correctly
#                written Workflow dispatch — the exact trap this section exists to avoid).
#
# Task 6's GREEN phase is expected to introduce ONE new heading, chosen here as the acceptance
# anchor for H3/H3b/H4a/H5/H5b: `#### Merge-back and base-fork audit`. This mirrors the file's
# existing single-resolution-site convention (`#### Pattern seed handoff`, `#### Proportional
# audit depth`) — stated once, referenced by both dispatch paths — and it MUST sit, in document
# order, after `**Stage 1 — tester.**` and before `**Stage 2 — coder.**`, so a reader (and this
# test) sees the same ordering the runtime enforces (ADR-0068 §D6: the tester's worktree merges
# before the coder's worktree is created).
# ==============================================================================================

# ------------------------------------------------------------------------------------------------
# Shared helpers for section H.
# ------------------------------------------------------------------------------------------------
block_between() {
  # $1=file $2=start ere (awk) $3=end ere (awk); start inclusive, end exclusive.
  awk -v s="$2" -v e="$3" '$0 ~ s{f=1} $0 ~ e{f=0} f' "$1" 2>/dev/null
}

block_from_heading() {
  # $1=file $2=start ere (awk). Prints from the first line matching $2 (inclusive) up to, but not
  # including, the next line that begins with a markdown ### or #### heading. Empty output if $2
  # matches nothing (the heading does not exist yet).
  awk -v s="$2" '
    $0 ~ s { f=1 }
    f && /^#{3,4} / && $0 !~ s { exit }
    f { print }
  ' "$1" 2>/dev/null
}

split_paragraphs() {
  # $1 = source file, $2 = destination dir (must already exist; cleared of prior para-*.txt).
  # Splits on blank lines (awk paragraph mode, RS="").
  rm -f "$2"/para-*.txt 2>/dev/null
  awk -v outdir="$2" 'BEGIN{RS=""} { n++; print > (outdir "/para-" n ".txt") }' "$1" 2>/dev/null
}

agent_tool_effort_hits() {
  # $1 = dir already populated by split_paragraphs. Prints the path of every paragraph containing
  # a capital-A "Agent(" call (the Agent-tool literal call syntax) that also mentions "effort" —
  # a key the Agent tool does not accept (ADR-0068 §D7). Case-sensitive by construction: lowercase
  # "agent(" (Workflow) calls are a different mechanism and must never be flagged here.
  for pf in "$1"/para-*.txt; do
    [ -f "$pf" ] || continue
    if grep -qE '(^|[^A-Za-z])Agent\(' "$pf" 2>/dev/null && grep -q 'effort' "$pf" 2>/dev/null; then
      echo "$pf"
    fi
  done
}

agent_tool_call_count() {
  # $1 = dir already populated by split_paragraphs. Counts paragraphs containing a capital-A
  # "Agent(" call, regardless of whether they also carry "effort" — the H7a non-vacuity guard.
  grep -lE '(^|[^A-Za-z])Agent\(' "$1"/para-*.txt 2>/dev/null | wc -l | tr -d ' '
}

# ==============================================================================================
# H1 / H1b / H1c (R-06) — every `coder` dispatch (Workflow Stage 2, Workflow Step 6 Phase 3
# fix-agent, Agent-tool fallback) pins isolation: "worktree" explicitly.
# ==============================================================================================
STAGE2_BLOCK=$(block_between "$STEP5_REF" '^\*\*Stage 2 — coder\.\*\*' '^\*\*Pin the model explicitly')
if printf '%s\n' "$STAGE2_BLOCK" | grep -qF 'isolation: "worktree"'; then
  ok "H1: concept-to-code Step 5 Stage 2 (Workflow path) pins isolation: \"worktree\" on the coder dispatch (R-06)"
else
  bad "H1: concept-to-code Step 5 Stage 2 (Workflow path) does not pin isolation: \"worktree\" on the coder dispatch (R-06)"
fi

PHASE3_BLOCK=$(block_between "$CC" '^Phase 3 — Fix in parallel per file group:' '^Phase 4 — Re-review:')
if printf '%s\n' "$PHASE3_BLOCK" | grep -q 'isolation'; then
  ok "H1b: concept-to-code Step 6 Phase 3's fix-agent dispatch pins an isolation value (R-06)"
else
  bad "H1b: concept-to-code Step 6 Phase 3's fix-agent dispatch names no isolation value — agentType can resolve to \"coder\" (via fix_type) and R-06 requires isolation: 'worktree' there too"
fi

FALLBACK_CODER_BLOCK=$(block_between "$STEP5_REF" '^2\. Dispatch coder with batch 1' '^3\. Checkpoint between batches')
if printf '%s\n' "$FALLBACK_CODER_BLOCK" | grep -qF 'isolation: "worktree"'; then
  ok "H1c: the Agent-tool fallback's coder dispatch pins isolation: \"worktree\" explicitly (R-06)"
else
  bad "H1c: the Agent-tool fallback's coder dispatch does not pin isolation: \"worktree\" explicitly (R-06)"
fi

# ==============================================================================================
# H2 / H2b (R-09) — Step 5 Stage 1's tester dispatch carries an isolation value on both paths.
# ==============================================================================================
STAGE1_BLOCK=$(block_between "$STEP5_REF" '^\*\*Stage 1 — tester\.\*\*' '^\*\*Stage 2 — coder\.\*\*')
if printf '%s\n' "$STAGE1_BLOCK" | grep -q 'isolation'; then
  ok "H2: concept-to-code Step 5 Stage 1 (Workflow path) tester dispatch names an isolation value (R-09)"
else
  bad "H2: concept-to-code Step 5 Stage 1 (Workflow path) tester dispatch names no isolation value — R-09 requires isolation: \"worktree\" explicitly"
fi

FALLBACK_TESTER_BLOCK=$(block_between "$STEP5_REF" '^1\. Dispatch `tester` for batch 1' '^2\. Dispatch coder with batch 1')
if printf '%s\n' "$FALLBACK_TESTER_BLOCK" | grep -q 'isolation'; then
  ok "H2b: the Agent-tool fallback's tester dispatch (batch 1) names an isolation value (R-09)"
else
  bad "H2b: the Agent-tool fallback's tester dispatch (batch 1) names no isolation value — R-09 requires isolation: \"worktree\" explicitly, same as the coder dispatch immediately below it"
fi

# ==============================================================================================
# H3 / H3b (R-07, R-09) — the merge-back block exists, names worktreePath and worktreeBranch, and
# sits, in document order, between the tester stage heading and the coder stage heading (the
# recovery-preflight.test.sh RE5 idiom: compare line numbers of two located headings).
# ==============================================================================================
MB_HEADING_ERE='^#### Merge-back and base-fork audit'
# VCS-047/ADR-0174: this section now lives in references/step5-implementation.md.
MB_SECTION=$(block_from_heading "$STEP5_REF" "$MB_HEADING_ERE")

if printf '%s\n' "$MB_SECTION" | grep -qF 'worktreePath' && printf '%s\n' "$MB_SECTION" | grep -qF 'worktreeBranch'; then
  ok "H3: a merge-back block exists naming worktreePath and worktreeBranch (R-07)"
else
  bad "H3: no merge-back block naming worktreePath and worktreeBranch was found (R-07) — Task 6 adds a '#### Merge-back and base-fork audit' section"
fi

# VCS-047/ADR-0174: all three anchors now live in references/step5-implementation.md.
STAGE1_HEAD_LINE=$(grep -n '^\*\*Stage 1 — tester\.\*\*' "$STEP5_REF" 2>/dev/null | head -1 | cut -d: -f1)
MB_HEAD_LINE=$(grep -n "$MB_HEADING_ERE" "$STEP5_REF" 2>/dev/null | head -1 | cut -d: -f1)
STAGE2_HEAD_LINE=$(grep -n '^\*\*Stage 2 — coder\.\*\*' "$STEP5_REF" 2>/dev/null | head -1 | cut -d: -f1)
if [ -n "$STAGE1_HEAD_LINE" ] && [ -n "$MB_HEAD_LINE" ] && [ -n "$STAGE2_HEAD_LINE" ] \
   && [ "$STAGE1_HEAD_LINE" -lt "$MB_HEAD_LINE" ] && [ "$MB_HEAD_LINE" -lt "$STAGE2_HEAD_LINE" ]; then
  ok "H3b: the merge-back block sits between the tester stage heading and the coder stage heading (R-07, R-09, RE5 idiom)"
else
  bad "H3b: the merge-back block is not positioned between the tester stage heading and the coder stage heading (R-07, R-09) — expected a '#### Merge-back and base-fork audit' heading after '**Stage 1 — tester.**' and before '**Stage 2 — coder.**'"
fi

# ==============================================================================================
# H4a / H4b (R-14) — the empty/auto-removed worktree case is "nothing to merge": neither an error
# nor an empty commit. Two assertions on purpose: a positive claim (the wording exists) and a
# negative one (no empty-commit escape hatch), so a future implementation cannot satisfy one
# silently at the other's expense.
# ==============================================================================================
if printf '%s\n' "$MB_SECTION" | grep -qF 'nothing to merge'; then
  ok "H4a: the merge-back block states the empty/auto-removed case as 'nothing to merge' (R-14)"
else
  bad "H4a: the merge-back block does not state the empty/auto-removed case as 'nothing to merge' (R-14)"
fi

if printf '%s\n' "$MB_SECTION" | grep -qF -- '--allow-empty'; then
  bad "H4b: the merge-back block uses --allow-empty — R-14 requires NO empty commit, not an empty commit with a marker"
else
  ok "H4b: the merge-back block does not use --allow-empty (no empty commit is produced, R-14)"
fi

# ==============================================================================================
# H5 / H5b (R-07) — the base-fork audit: the fork point is captured with `rev-parse HEAD` BEFORE
# the snapshot commit lands (ordering), and a mismatch halts (behaviour). Two assertions, because
# the ordering half is the one that silently rots (ADR-0068 §D5 step 2, "records the fork point
# before touching anything").
# ==============================================================================================
# VCS-047/ADR-0174: both anchors now live in references/step5-implementation.md.
BASE_SHA_LINE=$(grep -nF 'BASE_SHA=$(git -C "$WT" rev-parse HEAD)' "$STEP5_REF" 2>/dev/null | head -1 | cut -d: -f1)
SNAPSHOT_COMMIT_LINE=$(grep -nF 'git -C "$WT" commit -m "chore(step5): snapshot' "$STEP5_REF" 2>/dev/null | head -1 | cut -d: -f1)
if [ -n "$BASE_SHA_LINE" ] && [ -n "$SNAPSHOT_COMMIT_LINE" ] && [ "$BASE_SHA_LINE" -lt "$SNAPSHOT_COMMIT_LINE" ]; then
  ok "H5: the fork point (BASE_SHA = rev-parse HEAD) is captured before the snapshot commit lands (R-07, ordering)"
else
  bad "H5: no evidence the fork point is captured before the snapshot commit (R-07, ordering) — expected literal 'BASE_SHA=\$(git -C \"\$WT\" rev-parse HEAD)' to precede literal 'git -C \"\$WT\" commit -m \"chore(step5): snapshot'"
fi

if printf '%s\n' "$MB_SECTION" | grep -qF 'forked from somewhere other than the feature branch' \
   && printf '%s\n' "$MB_SECTION" | grep -qi 'halt'; then
  ok "H5b: a base-fork mismatch halts the chain, with the reason stated (R-07)"
else
  bad "H5b: no base-fork mismatch halt was found (R-07) — expected the merge-back block to state that a mismatch means the worktree forked from somewhere other than the feature branch, and to halt"
fi

# ==============================================================================================
# H6 / H6b / H6c (R-08) — coder.md's "never commits" instruction is unchanged (forward guard,
# green from the start — ADR-0068 §D5 keeps it untouched on purpose), and no dispatch prompt in
# either SKILL.md instructs a coder to commit. Mandatory positive twin (H6c): the same detector
# fires on a synthetic fixture that DOES instruct a coder to commit.
# ==============================================================================================
if grep -qi 'never commit' "$CODER_MD" 2>/dev/null; then
  ok "H6 (forward guard): agents/coder.md still states its coder 'never commit(s)' (R-08)"
else
  bad "H6 (forward guard): agents/coder.md no longer states 'never commit(s)' — R-08 requires this instruction untouched"
fi

coder_commit_instruction_hits() {
  # $1 = file. Exit 0 (match) iff an affirmative "instruct the coder to commit" phrasing is
  # present. Deliberately NOT matching "do not commit" / "never commit" — those are the correct
  # instruction, and this detector must not flag its own compliance.
  grep -qiE 'please commit|commit your changes|commit the changes|coder (should|must) commit|have the coder commit|commit this' "$1" 2>/dev/null
}

if coder_commit_instruction_hits "$CC" || coder_commit_instruction_hits "$AB"; then
  bad "H6b (forward guard): a dispatch prompt instructs a coder to commit — R-08 forbids this"
else
  ok "H6b (forward guard): neither concept-to-code/SKILL.md nor autopilot-build/SKILL.md instructs a coder to commit (R-08)"
fi

FIXTURE_H6C="$TMP/fixture-h6c.md"
printf 'Coder brief: implement the change, then please commit your changes and report back.\n' > "$FIXTURE_H6C"
if coder_commit_instruction_hits "$FIXTURE_H6C"; then
  ok "H6c (forward guard, mandatory positive twin): the R-08 detector fires on a fixture that DOES instruct a coder to commit"
else
  bad "H6c (forward guard, mandatory positive twin): the R-08 detector did NOT fire on a fixture instructing a coder to commit — H6b cannot be trusted to catch a real regression"
fi

# ==============================================================================================
# H7a / H7 / H7b — no `Agent(...)` (Agent-tool, capital A) call carries an `effort` key; the Agent
# tool has no such parameter (ADR-0068 §D7). `agent(...)` (lowercase, Workflow) calls legitimately
# carry `effort` and MUST NOT be flagged — H7b is the mandatory synthetic positive twin proving the
# check distinguishes the two, not merely the word "effort".
# ==============================================================================================
CC_PARA_DIR="$TMP/paras-cc"
mkdir -p "$CC_PARA_DIR"
split_paragraphs "$CC" "$CC_PARA_DIR"

AGENT_TOOL_CALLS=$(agent_tool_call_count "$CC_PARA_DIR")
case "$AGENT_TOOL_CALLS" in ''|*[!0-9]*) AGENT_TOOL_CALLS=0 ;; esac
if [ "$AGENT_TOOL_CALLS" -ge 1 ]; then
  ok "H7a (forward guard): at least one Agent(...) (Agent-tool) call block was found in concept-to-code/SKILL.md (count=$AGENT_TOOL_CALLS) — the extractor is not vacuous"
else
  bad "H7a (forward guard): zero Agent(...) call blocks found — the extractor is broken and H7 is meaningless"
fi

CC_EFFORT_HITS=$(agent_tool_effort_hits "$CC_PARA_DIR")

AB_PARA_DIR="$TMP/paras-ab"
mkdir -p "$AB_PARA_DIR"
split_paragraphs "$AB" "$AB_PARA_DIR"
AB_EFFORT_HITS=$(agent_tool_effort_hits "$AB_PARA_DIR")

if [ -z "$CC_EFFORT_HITS" ] && [ -z "$AB_EFFORT_HITS" ]; then
  ok "H7: no Agent(...) (Agent-tool) call carries an effort key — the Agent tool has none (ADR-0068 §D7)"
else
  bad "H7: at least one Agent(...) (Agent-tool) call carries an effort key, which the Agent tool does not accept (ADR-0068 §D7) — found in: $(printf '%s %s' "$CC_EFFORT_HITS" "$AB_EFFORT_HITS" | tr '\n' ' ')"
fi

FIXTURE_H7="$TMP/fixture-h7.md"
cat > "$FIXTURE_H7" <<'EOF'
Agent({ agentType: "coder", model: "sonnet", effort: "high",
        prompt: "do the thing" })

agent(`
  do the thing
`, { agentType: "coder", model: "sonnet", effort: "high" })
EOF
FIXTURE_H7_DIR="$TMP/paras-h7fixture"
mkdir -p "$FIXTURE_H7_DIR"
split_paragraphs "$FIXTURE_H7" "$FIXTURE_H7_DIR"
FIXTURE_H7_HITS=$(agent_tool_effort_hits "$FIXTURE_H7_DIR")
FIXTURE_H7_HIT_COUNT=$(printf '%s\n' "$FIXTURE_H7_HITS" | grep -c . 2>/dev/null || true)
case "$FIXTURE_H7_HIT_COUNT" in ''|*[!0-9]*) FIXTURE_H7_HIT_COUNT=0 ;; esac
if [ "$FIXTURE_H7_HIT_COUNT" -eq 1 ]; then
  ok "H7b (forward guard, mandatory positive twin): the detector flags exactly the Agent(...) block and not the agent(...) Workflow block, both carrying effort — proving it discriminates on call syntax, not on the word 'effort'"
else
  bad "H7b (forward guard, mandatory positive twin): expected exactly one flagged paragraph in the fixture (the Agent(...) block), got $FIXTURE_H7_HIT_COUNT — the detector cannot be trusted to distinguish Agent-tool calls from Workflow calls"
fi

# ==============================================================================================
# Section I (Task 7, R-10, R-12) — binding conflict scan and the conflict halt (ADR-0068 §D8).
#
# EXPECTED at RED time (Task 7 GREEN not yet run):
#   I-guard0 GREEN (forward guard) — the conflict-scan block itself is non-empty, so the absence
#            checks below (I2) cannot pass merely because the extractor found nothing.
#   I1      RED   — the scan block states no binding/sequencing language yet ("binding",
#            "sequenced", "batch" are all absent from the block at the time this section was
#            written; "parallel" alone IS already present — "Groups with no path overlap keep the
#            default parallel dispatch" — which is why all four keywords are required together,
#            not "parallel" alone).
#   I2      RED   — the scan block still states "This stays advisory: every group runs with
#            `isolation: worktree`" (confirmed present, ADR-0068 §D8's superseded clause) — R-10
#            requires this replaced by a binding scan with no such advisory escape.
#   I2b     GREEN (forward guard, mandatory positive twin) — the same absence detector, applied to
#            a fixture carrying the literal advisory sentence, correctly flags it. Proves I2 is not
#            passing because the detector is broken.
#   I3      RED   — no conflict-halt block naming `git merge --abort` and `--diff-filter=U` exists
#            anywhere in concept-to-code/SKILL.md yet (confirmed absent by direct grep before this
#            section was written); Task 6 left the placeholder `<conflict halt, Task 7>` at the
#            `git merge --no-edit "$WB" ||` line inside `#### Merge-back and base-fork audit`.
#   I4      RED   — no "no automatic resolution" wording, and no "rebase"/"resolver" mentions,
#            exist anywhere in the file yet (confirmed absent).
#   I5      RED   — neither literal (`CONFLICTS=$(git diff --name-only --diff-filter=U)` nor
#            `git merge --abort`) exists yet, so the capture-before-abort ordering cannot be
#            asserted true; this is the ordering trap named in the dispatch brief, mirrored on the
#            H5 idiom (compare line numbers of two located literals).
#   I6      RED   — autopilot-build/SKILL.md's restated conflict-scan paragraph (the block between
#            "Parallel-conflict scan" and "Dispatch:") says nothing about a halt yet.
#   I7      RED   — autopilot-build/SKILL.md does not mention "autopilot" anywhere yet
#            (confirmed absent by direct grep), so it cannot yet note that autopilot
#            inherits the halt.
#
# Task 7's GREEN steps are expected to: (a) rewrite the conflict-scan paragraph from advisory to
# binding inside `#### Workflow dispatch path — Step 5 implementation`; (b) replace the
# `<conflict halt, Task 7>` placeholder inside `#### Merge-back and base-fork audit` with the real
# halt, capturing `$CONFLICTS` BEFORE `git merge --abort` (the abort clears the unmerged paths);
# (c) add a halt-by-reference plus an autopilot note to autopilot-build/SKILL.md.
# ==============================================================================================

# ------------------------------------------------------------------------------------------------
# I-guard0 / I1 / I2 / I2b — the file-conflict scan block (R-10).
# ------------------------------------------------------------------------------------------------
SCAN_BLOCK=$(block_between "$STEP5_REF" 'conflict scan' 'Step 5 dispatch prompt')

if [ -n "$SCAN_BLOCK" ]; then
  ok "I-guard0 (forward guard): the parallel task conflict scan block was extracted (non-empty) — I1/I2 are not vacuous"
else
  bad "I-guard0 (forward guard): the parallel task conflict scan block could not be extracted — I1/I2 would pass vacuously"
fi

if printf '%s\n' "$SCAN_BLOCK" | grep -qi 'binding' \
   && printf '%s\n' "$SCAN_BLOCK" | grep -qi 'sequenced' \
   && printf '%s\n' "$SCAN_BLOCK" | grep -qi 'parallel' \
   && printf '%s\n' "$SCAN_BLOCK" | grep -qi 'batch'; then
  ok "I1: the file-conflict scan states groups naming the same file are sequenced, never dispatched in the same parallel() batch, and the scan is binding (R-10)"
else
  bad "I1: the file-conflict scan block does not yet state binding/sequenced/parallel/batch language (R-10) — Task 7 GREEN rewrites GAP E from advisory to binding"
fi

if printf '%s\n' "$SCAN_BLOCK" | grep -qF 'This stays advisory'; then
  bad "I2: the scan block still states 'This stays advisory: every group runs with isolation: worktree' — R-10 requires this superseded clause removed"
else
  ok "I2: the scan block no longer states the superseded 'This stays advisory' clause (R-10)"
fi

FIXTURE_I2="$TMP/fixture-i2.md"
printf 'This stays advisory: every group runs with `isolation: worktree` — no gate here.\n' > "$FIXTURE_I2"
if grep -qF 'This stays advisory' "$FIXTURE_I2"; then
  ok "I2b (forward guard, mandatory positive twin): the I2 detector fires on a fixture carrying the superseded advisory sentence"
else
  bad "I2b (forward guard, mandatory positive twin): the I2 detector did NOT fire on a fixture carrying the superseded advisory sentence — I2 cannot be trusted to catch a real regression"
fi

# ------------------------------------------------------------------------------------------------
# I3 / I4 — the conflict-halt block (R-12). Reuses MB_SECTION (section H), the
# `#### Merge-back and base-fork audit` block, since ADR-0068 §D8 places the halt on the same
# `git merge --no-edit "$WB" ||` line Task 6 already wrote there.
# ------------------------------------------------------------------------------------------------
if printf '%s\n' "$MB_SECTION" | grep -qF 'git merge --abort' \
   && printf '%s\n' "$MB_SECTION" | grep -qF -- '--diff-filter=U' \
   && printf '%s\n' "$MB_SECTION" | grep -qi 'preserve' \
   && printf '%s\n' "$MB_SECTION" | grep -qi 'branch'; then
  ok "I3: a conflict-halt block exists naming git merge --abort, --diff-filter=U, and branch preservation (R-12)"
else
  bad "I3: no conflict-halt block naming git merge --abort, --diff-filter=U, and branch preservation was found (R-12) — Task 7 GREEN replaces the '<conflict halt, Task 7>' placeholder"
fi

if printf '%s\n' "$MB_SECTION" | grep -qi 'no automatic resolution' \
   && printf '%s\n' "$MB_SECTION" | grep -qi 'rebase' \
   && printf '%s\n' "$MB_SECTION" | grep -qi 'resolver'; then
  ok "I4: the conflict-halt block states that no automatic resolution is attempted — no rebase, no resolver dispatch (R-12)"
else
  bad "I4: the conflict-halt block does not yet state that no automatic resolution is attempted (R-12) — expected mentions of 'no automatic resolution', 'rebase' and 'resolver' all absent (or ADR-0068 §D8's '-X ours' example) from the merge-back block"
fi

# ------------------------------------------------------------------------------------------------
# I5 (R-12, ordering trap) — $CONFLICTS is captured BEFORE `git merge --abort`, since the abort
# clears the unmerged paths `--diff-filter=U` would otherwise report. Positional check on the
# H5 idiom: compare line numbers of two located literals in the whole file, not the pre-extracted
# MB_SECTION text (which carries no original line numbers).
# ------------------------------------------------------------------------------------------------
# VCS-047/ADR-0174: both anchors now live in references/step5-implementation.md.
CONFLICTS_CAPTURE_LINE=$(grep -nF 'CONFLICTS=$(git diff --name-only --diff-filter=U)' "$STEP5_REF" 2>/dev/null | head -1 | cut -d: -f1)
MERGE_ABORT_LINE=$(grep -nF 'git merge --abort' "$STEP5_REF" 2>/dev/null | head -1 | cut -d: -f1)
if [ -n "$CONFLICTS_CAPTURE_LINE" ] && [ -n "$MERGE_ABORT_LINE" ] \
   && [ "$CONFLICTS_CAPTURE_LINE" -lt "$MERGE_ABORT_LINE" ]; then
  ok "I5: \$CONFLICTS is captured (git diff --name-only --diff-filter=U) before git merge --abort clears the unmerged paths (R-12, ordering)"
else
  bad "I5: no evidence \$CONFLICTS is captured before git merge --abort (R-12, ordering) — expected literal 'CONFLICTS=\$(git diff --name-only --diff-filter=U)' to precede literal 'git merge --abort'"
fi

# ------------------------------------------------------------------------------------------------
# I6 / I7 — the halt is restated by reference in autopilot-build/SKILL.md, which also notes that
# autopilot inherits it (it reuses c2c Steps 5-7 verbatim).
# ------------------------------------------------------------------------------------------------
AB_SCAN_BLOCK=$(block_between "$AB" 'Parallel-conflict scan' 'Dispatch:')

if printf '%s\n' "$AB_SCAN_BLOCK" | grep -qi 'halt'; then
  ok "I6: autopilot-build/SKILL.md's parallel-conflict scan restates the conflict halt by reference (R-12)"
else
  bad "I6: autopilot-build/SKILL.md's parallel-conflict scan paragraph does not mention a halt (R-12) — Task 7 restates the c2c conflict halt by reference here"
fi

if grep -qi 'autopilot' "$AB" 2>/dev/null && grep -qi 'inherit' "$AB" 2>/dev/null; then
  ok "I7: autopilot-build/SKILL.md notes that autopilot inherits the conflict halt (it reuses c2c Steps 5-7 verbatim)"
else
  bad "I7: autopilot-build/SKILL.md does not mention that autopilot inherits the conflict halt — Task 7 adds this note"
fi

# ==============================================================================================
# Section J (Task 8, R-15, R-16 — R-18 has no assertion here; see note below) — documentation
# surfaces, forward-recorded corrections, and the CLAUDE.md revision (ADR-0068 §D12).
#
# EXPECTED at RED time (Task 8 GREEN not yet run):
#   J1   RED   — staging/user/rules/parallelization.md:21 is still the single pre-existing line
#        ("Parallel `coder` sub-agents must use `isolation: worktree`."); it names no
#        forked-from-HEAD / merge-back / non-git-refusal wording yet.
#   J1a/J1b GREEN (forward guards, mandatory positive/negative twins) — the predicate itself
#        passes a fixture stating the contract correctly and rejects one that still names a
#        fallback.
#   J2   RED   — docs/GUIDA-USO-IT.md:632-633 still states "la chain usa `isolation: none`
#        automaticamente" (confirmed the only "none"-bearing isolation line in the file; lines
#        117, 136, 167 and 275 mention worktree isolation without this claim already).
#   J2a  GREEN (forward guard, mandatory positive twin).
#   J3   RED   — docs/SKILLS-AND-AGENTS-GUIDE.md:355-356 still states "isolation falls back to
#        `none`" verbatim.
#   J3a  GREEN (forward guard, mandatory positive twin).
#   J4a/J4b/J4c RED — none of ADR-0016, ADR-0049, ADR-0050 mentions ADR-0068 anywhere yet
#        (confirmed: ADR-0068 postdates all three), so no dated correction block naming it exists.
#   J4d/J4e GREEN (forward guards, mandatory positive + negative twins) — the detector fires on a
#        fixture paragraph combining a date, "ADR-0068" and a correction-ish word, and does NOT
#        fire on a fixture that merely co-mentions a date and "ADR-0068" without one.
#   J5-guard0 GREEN (forward guard) — the documentation sweep is non-vacuous (scans a real
#        double-digit file count).
#   J5   GREEN already — no real documentation surface under docs/ or staging/user/rules/
#        currently promises a WorktreeCreate hook (confirmed: the only real mentions under docs/
#        live in this feature's own excluded ADR-0068 and plan files). This is a forward guard,
#        not fix evidence — it protects against a FUTURE regression, not a defect Task 8 removes.
#   J5a/J5b GREEN (forward guards, mandatory positive + negative twins) — the detector fires on a
#        fixture that promises a hook and stays silent on a fixture that discloses its absence.
#   J6   RED   — CLAUDE.md's ADR-0068 section (line 921 to EOF) still names `worktree-create.sh`
#        (line 937: "`worktree-create.sh` ships alongside it...") alongside `worktree.baseRef` —
#        it describes the refuted two-layer design (ADR-0068 §D12: written at the first pass's
#        Gate 3, before the probe).
#   J6a/J6b GREEN (forward guards, mandatory positive + negative twins).
#
# R-18 (issue #175 closure reason) has NO assertion in this section: Task 8's own RED checklist
# item does not name it (only parallelization.md, GUIDA-USO-IT.md, the three ADRs, the
# WorktreeCreate sweep, and CLAUDE.md are listed), and closing #175 on GitHub is a HITL action the
# GREEN checklist assigns to the operator, not to a file this harness can inspect. Recorded here so
# the gap is a disclosed scope boundary, not a silently skipped requirement.
#
# EXCLUSION LIST for the J5 "no surface promises a WorktreeCreate hook" sweep, stated once here so
# it is visible rather than incidental: this feature's own artefacts discuss `WorktreeCreate` at
# length to explain why no hook exists (a disclosure, not a promise), and would otherwise trip a
# naive substring sweep on their own explanatory prose —
#   - docs/architecture/ADR-0068-176-worktree-isolation-contract.md
#   - docs/superpowers/plans/2026-07-28-176-worktree-isolation-contract.md
# SPEC.md is out of scope by construction (repo root, not under docs/ or staging/user/rules/), and
# so is this test file itself (staging/plugin/scripts/tests/, not staging/user/rules/). The sweep
# is scoped to flag a PROMISE of a hook (an unnegated mention), never any mention of the event
# name — see hook_promise_hits()'s doc comment for the negation-based distinction.
# ==============================================================================================

# ------------------------------------------------------------------------------------------------
# J1 (R-15) — staging/user/rules/parallelization.md states the contract as measured and names no
# fallback.
# ------------------------------------------------------------------------------------------------
PARALLEL_RULES="$STAGING/user/rules/parallelization.md"

contract_stated_no_fallback() {
  # $1 = file. Exit 0 iff it states the measured worktree contract (forked from HEAD, merge-back,
  # non-git CWD refused) AND names no fallback ("isolation: none", "falls back", "fallback").
  grep -qi 'forked from' "$1" 2>/dev/null \
    && grep -qi 'HEAD' "$1" 2>/dev/null \
    && grep -qi 'merge' "$1" 2>/dev/null \
    && grep -qi 'refused' "$1" 2>/dev/null \
    && ! grep -qiE 'isolation:? *`?"?none|falls back|fallback' "$1" 2>/dev/null
}

if contract_stated_no_fallback "$PARALLEL_RULES"; then
  ok "J1: staging/user/rules/parallelization.md states the worktree contract as measured (forked from HEAD, merge-back, non-git refusal) and names no fallback (R-15)"
else
  bad "J1: staging/user/rules/parallelization.md does not yet state the measured contract (forked-from-HEAD / merge-back / non-git-refusal wording), or still names a fallback (R-15) — Task 8 GREEN replaces line 21"
fi

FIXTURE_J1_GOOD="$TMP/fixture-j1-good.md"
printf 'Parallel modification sub-agents run in a worktree forked from `HEAD`; the orchestrator merges each stage back before the next worktree is created; a non-git CWD is refused, not downgraded.\n' > "$FIXTURE_J1_GOOD"
if contract_stated_no_fallback "$FIXTURE_J1_GOOD"; then
  ok "J1a (forward guard): the J1 predicate passes a fixture that correctly states the contract with no fallback"
else
  bad "J1a (forward guard): the J1 predicate wrongly failed a fixture that correctly states the contract with no fallback — it can never go green"
fi

FIXTURE_J1_BAD="$TMP/fixture-j1-bad.md"
printf 'Parallel modification sub-agents run in a worktree forked from `HEAD`; the orchestrator merges each stage back before the next worktree is created; a non-git CWD is refused, not downgraded. However, isolation falls back to `none` in the legacy subdirectory case.\n' > "$FIXTURE_J1_BAD"
if contract_stated_no_fallback "$FIXTURE_J1_BAD"; then
  bad "J1b (forward guard, mandatory positive twin): the J1 predicate wrongly passed a fixture that still names a fallback"
else
  ok "J1b (forward guard, mandatory positive twin): the J1 predicate correctly rejects a fixture naming a fallback, even though every other conjunct is satisfied"
fi

# ------------------------------------------------------------------------------------------------
# J2 (R-15) — docs/GUIDA-USO-IT.md no longer promises isolation falls back to "none"
# automatically. Checked as one whole-file predicate, which also covers lines 117, 136, 167 and
# 275 (they mention worktree isolation without this claim already, and would trip the same
# predicate if the claim ever migrated there).
# ------------------------------------------------------------------------------------------------
GUIDA="$REPO/docs/GUIDA-USO-IT.md"

guida_promises_auto_none() {
  # $1 = file. Exit 0 iff it still claims isolation automatically falls back to "none". Matches
  # both the English and Italian wording: "automaticamente" contains "automatic" as a substring.
  grep -qiE 'isolation:? *`?"?none' "$1" 2>/dev/null && grep -qi 'automatic' "$1" 2>/dev/null
}

if guida_promises_auto_none "$GUIDA"; then
  bad "J2: docs/GUIDA-USO-IT.md still promises isolation falls back to 'none' automatically (R-15) — Task 8 GREEN removes the sentence at lines 632-633"
else
  ok "J2: docs/GUIDA-USO-IT.md no longer promises isolation falls back to 'none' automatically (R-15)"
fi

FIXTURE_J2="$TMP/fixture-j2.md"
printf 'Se il progetto non e una repo git completa, la chain usa `isolation: none` automaticamente.\n' > "$FIXTURE_J2"
if guida_promises_auto_none "$FIXTURE_J2"; then
  ok "J2a (forward guard, mandatory positive twin): the J2 detector fires on a fixture repeating the false automatic-fallback claim"
else
  bad "J2a (forward guard, mandatory positive twin): the J2 detector did NOT fire on a fixture repeating the false claim — J2 cannot be trusted to catch a regression"
fi

# ------------------------------------------------------------------------------------------------
# J3 (R-15, same false-fallback class, not named in the SPEC's Scope but fixed anyway per the
# plan) — docs/SKILLS-AND-AGENTS-GUIDE.md no longer states "isolation falls back to `none`".
# ------------------------------------------------------------------------------------------------
SKILLS_GUIDE="$REPO/docs/SKILLS-AND-AGENTS-GUIDE.md"

if grep -qF 'isolation falls back to `none`' "$SKILLS_GUIDE" 2>/dev/null; then
  bad "J3: docs/SKILLS-AND-AGENTS-GUIDE.md still states 'isolation falls back to \`none\`' — Task 8 GREEN fixes lines 355-356"
else
  ok "J3: docs/SKILLS-AND-AGENTS-GUIDE.md no longer states the false 'isolation falls back to none' claim"
fi

FIXTURE_J3="$TMP/fixture-j3.md"
printf 'Runs in `isolation: worktree`. If the project root is not a direct git repo, isolation falls back to `none`.\n' > "$FIXTURE_J3"
if grep -qF 'isolation falls back to `none`' "$FIXTURE_J3" 2>/dev/null; then
  ok "J3a (forward guard, mandatory positive twin): the J3 detector fires on a fixture repeating the false claim"
else
  bad "J3a (forward guard, mandatory positive twin): the J3 detector did NOT fire on a fixture repeating the false claim — J3 cannot be trusted to catch a regression"
fi

# ------------------------------------------------------------------------------------------------
# J4 (R-16) — ADR-0016, ADR-0049 and ADR-0050 each carry a dated correction block naming ADR-0068
# (ADR-0034 forward-recorded-correction precedent, never an in-place edit of a shipped ADR).
# ------------------------------------------------------------------------------------------------
ADR0016="$REPO/docs/architecture/ADR-0016-dynamic-workflows-step5.md"
ADR0049="$REPO/docs/architecture/ADR-0049-103-generator-verifier-separation.md"
ADR0050="$REPO/docs/architecture/ADR-0050-104-recovery-readiness-preflight.md"

dated_correction_hits() {
  # $1 = file. Prints one line per paragraph naming BOTH a YYYY-MM-DD date and "ADR-0068" together
  # with a correction-ish word (correct|supersed|retir) — an actual forward-recorded correction
  # block, not an incidental co-mention of a date and ADR-0068 somewhere in the same paragraph.
  pdir="$TMP/dc-scan"
  rm -rf "$pdir"; mkdir -p "$pdir"
  split_paragraphs "$1" "$pdir"
  for pf in "$pdir"/para-*.txt; do
    [ -f "$pf" ] || continue
    if grep -qE '20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]' "$pf" 2>/dev/null \
       && grep -qF 'ADR-0068' "$pf" 2>/dev/null \
       && grep -qiE 'correct|supersed|retir' "$pf" 2>/dev/null; then
      echo "$pf"
    fi
  done
}

if [ -n "$(dated_correction_hits "$ADR0016")" ]; then
  ok "J4a: ADR-0016 carries a dated correction block naming ADR-0068 (R-16)"
else
  bad "J4a: ADR-0016 has no dated correction block naming ADR-0068 yet (R-16) — Task 8 GREEN appends one near § Cross-repo isolation constraint"
fi

if [ -n "$(dated_correction_hits "$ADR0049")" ]; then
  ok "J4b: ADR-0049 carries a dated correction block naming ADR-0068 (R-16)"
else
  bad "J4b: ADR-0049 has no dated correction block naming ADR-0068 yet (R-16) — Task 8 GREEN appends one near §D2"
fi

if [ -n "$(dated_correction_hits "$ADR0050")" ]; then
  ok "J4c: ADR-0050 carries a dated correction block naming ADR-0068 (R-16)"
else
  bad "J4c: ADR-0050 has no dated correction block naming ADR-0068 yet (R-16) — Task 8 GREEN appends one near §D4"
fi

FIXTURE_J4_HIT="$TMP/fixture-j4-hit.md"
printf '### Correction 2026-07-28 (ADR-0068 supersedes this section)\n\nThis section'"'"'s dirty-tree tolerance is retired by ADR-0068; see its §D2.\n' > "$FIXTURE_J4_HIT"
if [ -n "$(dated_correction_hits "$FIXTURE_J4_HIT")" ]; then
  ok "J4d (forward guard, mandatory positive twin): the J4 detector fires on a fixture paragraph that is an actual dated correction block naming ADR-0068"
else
  bad "J4d (forward guard, mandatory positive twin): the J4 detector did NOT fire on a fixture dated correction block naming ADR-0068 — J4a/b/c cannot be trusted to go green"
fi

FIXTURE_J4_MISS="$TMP/fixture-j4-miss.md"
printf 'On 2026-07-28 the team also discussed ADR-0068 informally in a design review, unrelated to this section.\n' > "$FIXTURE_J4_MISS"
if [ -z "$(dated_correction_hits "$FIXTURE_J4_MISS")" ]; then
  ok "J4e (forward guard, negative twin): the J4 detector does NOT fire on a fixture that merely co-mentions a date and ADR-0068 without a correction word"
else
  bad "J4e (forward guard, negative twin): the J4 detector wrongly fired on a casual co-mention of a date and ADR-0068 — it cannot distinguish an actual correction block from an incidental reference"
fi

# ------------------------------------------------------------------------------------------------
# J5 (R-04, documentation extension) — no documentation surface under docs/ or
# staging/user/rules/ promises that a WorktreeCreate hook exists or will be wired. See the module
# docstring above this section for the exclusion list and its reasoning.
# ------------------------------------------------------------------------------------------------
hook_promise_hits() {
  # $1 = file. Prints one line per paragraph mentioning WorktreeCreate WITHOUT a nearby negation
  # (no/not/never/nothing/does not/n't) — i.e. a paragraph reading as a PROMISE the hook exists or
  # will be wired, rather than a disclosure that it does not and will not.
  pdir="$TMP/hp-scan"
  rm -rf "$pdir"; mkdir -p "$pdir"
  split_paragraphs "$1" "$pdir"
  for pf in "$pdir"/para-*.txt; do
    [ -f "$pf" ] || continue
    if grep -qi 'worktreecreate' "$pf" 2>/dev/null; then
      if grep -qiE '(^|[^a-z])(no|not|never|nothing)([^a-z]|$)|does not|n.t([^a-z]|$)' "$pf" 2>/dev/null; then
        : # negation present nearby — a disclosure, not a promise
      else
        echo "$pf"
      fi
    fi
  done
}

J5_SCANNED=0
J5_HITS=""
for f in $(find "$REPO/docs" -name '*.md' \
             ! -path "*/architecture/ADR-0068-176-worktree-isolation-contract.md" \
             ! -path "*/superpowers/plans/2026-07-28-176-worktree-isolation-contract.md") \
          "$STAGING"/user/rules/*.md; do
  [ -f "$f" ] || continue
  J5_SCANNED=$((J5_SCANNED + 1))
  HIT=$(hook_promise_hits "$f")
  if [ -n "$HIT" ]; then
    J5_HITS="$J5_HITS $f"
  fi
done

if [ "$J5_SCANNED" -ge 20 ]; then
  ok "J5-guard0 (forward guard): the documentation sweep scanned $J5_SCANNED files under docs/ + staging/user/rules/ — not vacuous"
else
  bad "J5-guard0 (forward guard): the documentation sweep scanned only $J5_SCANNED files — too few to trust J5"
fi

if [ -z "$J5_HITS" ]; then
  ok "J5: no documentation surface under docs/ or staging/user/rules/ promises a WorktreeCreate hook (R-04), excluding this feature's own ADR-0068 and plan — GREEN already, a forward guard against a future regression, not fix evidence"
else
  bad "J5: a documentation surface promises a WorktreeCreate hook with no negation nearby:$J5_HITS"
fi

FIXTURE_J5_PROMISE="$TMP/fixture-j5-promise.md"
printf 'Register `worktree-create.sh` as a WorktreeCreate hook in settings.json to scope the base branch per dispatch.\n' > "$FIXTURE_J5_PROMISE"
if [ -n "$(hook_promise_hits "$FIXTURE_J5_PROMISE")" ]; then
  ok "J5a (forward guard, mandatory positive twin): the J5 detector fires on a fixture that promises a WorktreeCreate hook"
else
  bad "J5a (forward guard, mandatory positive twin): the J5 detector did NOT fire on a fixture promising a WorktreeCreate hook — J5 cannot be trusted to catch a regression"
fi

FIXTURE_J5_DISCLOSE="$TMP/fixture-j5-disclose.md"
printf 'No `WorktreeCreate` hook is registered by this system; nothing intercepts worktree creation for any session.\n' > "$FIXTURE_J5_DISCLOSE"
if [ -z "$(hook_promise_hits "$FIXTURE_J5_DISCLOSE")" ]; then
  ok "J5b (forward guard, negative twin): the J5 detector does NOT fire on a fixture that discloses the ABSENCE of a WorktreeCreate hook (negation nearby)"
else
  bad "J5b (forward guard, negative twin): the J5 detector wrongly fired on a legitimate disclosure fixture — it cannot distinguish a promise from a disclosure"
fi

# ------------------------------------------------------------------------------------------------
# J6 (ADR-0068 §D12) — CLAUDE.md's ADR-0068 section (the one place a stale summary would be read
# by every future session in this project) names worktree.baseRef rather than worktree-create.sh.
# ------------------------------------------------------------------------------------------------
CLAUDEMD="$REPO/CLAUDE.md"

block_from_h2_heading() {
  # $1=file $2=start ere (awk). Prints from the first line matching $2 (inclusive) up to, but not
  # including, the next line beginning with "## " (a different level-2 heading). Empty output if
  # $2 matches nothing.
  awk -v s="$2" '
    $0 ~ s { f=1; print; next }
    f && /^## / { exit }
    f { print }
  ' "$1" 2>/dev/null
}

# THE TARGET MOVED (issue #380, ADR-0136). All 95 narrative blocks were moved verbatim from
# CLAUDE.md to docs/chain-decisions.md, because CLAUDE.md is loaded in full into every orchestrator
# turn and the blocks were 98% of it. J6's intent — the one place a stale summary would be read is
# not stale — is unchanged; only its address is. Both files are searched, and the first that has
# the section wins, because a project that has not adopted the split still appends to CLAUDE.md
# (ADR-0136 §D6). The needles are byte-identical to before: a repoint, not a relaxation.
CLAUDE_ADR0068_SECTION=$(block_from_h2_heading "$REPO/docs/chain-decisions.md" '^## Decisions from the worktree isolation contract chain')
[ -n "$CLAUDE_ADR0068_SECTION" ] || \
  CLAUDE_ADR0068_SECTION=$(block_from_h2_heading "$CLAUDEMD" '^## Decisions from the worktree isolation contract chain')

if printf '%s\n' "$CLAUDE_ADR0068_SECTION" | grep -qF 'worktree.baseRef' \
   && ! printf '%s\n' "$CLAUDE_ADR0068_SECTION" | grep -qF 'worktree-create.sh'; then
  ok "J6: CLAUDE.md's ADR-0068 section names worktree.baseRef and no longer names worktree-create.sh (ADR-0068 §D12)"
else
  bad "J6: CLAUDE.md's ADR-0068 section still names worktree-create.sh (or lost its worktree.baseRef mention) — ADR-0068 §D12 requires this section REVISED, not appended to, describing the one-layer contract"
fi

FIXTURE_J6_GOOD="$TMP/fixture-j6-good.md"
printf '## Decisions from the worktree isolation contract chain (ADR-0068)\n\nOne layer: `worktree.baseRef: "head"`, no hook registered.\n\n## Next section\n\nUnrelated.\n' > "$FIXTURE_J6_GOOD"
FIXTURE_J6_GOOD_SECTION=$(block_from_h2_heading "$FIXTURE_J6_GOOD" '^## Decisions from the worktree isolation contract chain')
if printf '%s\n' "$FIXTURE_J6_GOOD_SECTION" | grep -qF 'worktree.baseRef' \
   && ! printf '%s\n' "$FIXTURE_J6_GOOD_SECTION" | grep -qF 'worktree-create.sh'; then
  ok "J6a (forward guard, mandatory positive twin): the J6 predicate correctly passes a fixture section naming only worktree.baseRef"
else
  bad "J6a (forward guard, mandatory positive twin): the J6 predicate wrongly failed a fixture section naming only worktree.baseRef"
fi

FIXTURE_J6_BAD="$TMP/fixture-j6-bad.md"
printf '## Decisions from the worktree isolation contract chain (ADR-0068)\n\nTwo layers: `worktree.baseRef: "head"` plus `worktree-create.sh`.\n\n## Next section\n\nUnrelated.\n' > "$FIXTURE_J6_BAD"
FIXTURE_J6_BAD_SECTION=$(block_from_h2_heading "$FIXTURE_J6_BAD" '^## Decisions from the worktree isolation contract chain')
if printf '%s\n' "$FIXTURE_J6_BAD_SECTION" | grep -qF 'worktree.baseRef' \
   && ! printf '%s\n' "$FIXTURE_J6_BAD_SECTION" | grep -qF 'worktree-create.sh'; then
  bad "J6b (forward guard, negative twin): the J6 predicate wrongly passed a fixture section that still names worktree-create.sh"
else
  ok "J6b (forward guard, negative twin): the J6 predicate correctly rejects a fixture section that still names worktree-create.sh"
fi

# ==============================================================================================
# Section K (Task 9 evidence gap, R-07/R-09) — the `#### Merge-back and base-fork audit` section
# states `$WT`/`$WB` as coming "from the dispatch result (F10)" — true on the Agent-tool path
# only. On the Workflow path the orchestrator receives NO worktree identity at all (F19); the run
# journal records only agentId, key, result, type, and the task notification carries no worktree
# block. Task 9's own evidence run confirmed `git worktree list` enumeration reliably locates the
# Workflow worktree, and that this is preferable to the `.claude/worktrees/<runId>-<n>` naming
# convention (F20), which the ADR records as an observed convention, not a reported contract.
#
# EXPECTED at RED time (this gap is not yet fixed):
#   K1   RED — the merge-back section does not state BOTH retrieval methods (F10's
#        worktreePath/worktreeBranch for the Agent-tool path AND `git worktree list` enumeration
#        for the Workflow path).
#   K1a  GREEN (forward guard, mandatory positive twin) — a fixture stating both methods passes.
#   K1b  GREEN (forward guard, mandatory negative twin) — a fixture stating only the F10 method
#        (today's real content) fails the same predicate.
#   K2   RED — no mention of `git worktree list` as the Workflow-path mechanism.
#   K2a  GREEN (forward guard, mandatory positive twin).
#   K3   RED — no statement that the Workflow path does not report worktree identity, citing F19.
#   K3a  GREEN (forward guard, mandatory positive twin).
#   K4-guard0 GREEN (forward guard) — the precedence predicate is exercised on fixtures where the
#        naming convention IS mentioned, so K4 is not vacuously green merely because today's real
#        section mentions neither method.
#   K4   GREEN (today, vacuously true — see K4-guard0 for the non-vacuous form) — the real
#        section does not present the `<runId>-<n>` naming convention as the primary retrieval
#        mechanism, because it does not mention it at all yet.
#   K4a  GREEN (forward guard, mandatory positive twin) — a fixture where `git worktree list` is
#        stated before, and preferred over, the naming convention passes.
#   K4b  GREEN (forward guard, mandatory negative twin) — a fixture where the naming convention
#        is stated as the primary mechanism (before / without `git worktree list`) fails.
# ==============================================================================================

MB_SECTION_FILE="$TMP/mb-section-k.txt"
printf '%s\n' "$MB_SECTION" > "$MB_SECTION_FILE"

# ------------------------------------------------------------------------------------------------
# K1 / K1a / K1b (R-07, R-09) — both retrieval methods are stated: F10's worktreePath/
# worktreeBranch for the Agent-tool path, AND `git worktree list` enumeration for the Workflow
# path. Neither alone satisfies the gap Task 9 found.
# ------------------------------------------------------------------------------------------------
both_retrieval_methods_stated() {
  # $1 = file. Exit 0 iff it names the Agent-tool F10 fields AND the Workflow enumeration
  # mechanism (`git worktree list`).
  grep -qF 'worktreePath' "$1" 2>/dev/null \
    && grep -qF 'worktreeBranch' "$1" 2>/dev/null \
    && grep -qF 'git worktree list' "$1" 2>/dev/null
}

if both_retrieval_methods_stated "$MB_SECTION_FILE"; then
  ok "K1: the merge-back section states both retrieval methods — F10's worktreePath/worktreeBranch (Agent-tool) AND git worktree list (Workflow) (R-07, R-09)"
else
  bad "K1: the merge-back section does not state both retrieval methods — it names F10's worktreePath/worktreeBranch but not git worktree list enumeration for the Workflow path (R-07, R-09) — the gap Task 9's evidence step found"
fi

FIXTURE_K1_GOOD="$TMP/fixture-k1-good.md"
printf 'On the Agent-tool path, $WT/$WB come from worktreePath/worktreeBranch (F10). On the Workflow path, locate the worktree with git worktree list instead.\n' > "$FIXTURE_K1_GOOD"
if both_retrieval_methods_stated "$FIXTURE_K1_GOOD"; then
  ok "K1a (forward guard, mandatory positive twin): the K1 predicate passes a fixture stating both retrieval methods"
else
  bad "K1a (forward guard, mandatory positive twin): the K1 predicate wrongly failed a fixture stating both retrieval methods — it can never go green"
fi

FIXTURE_K1_BAD="$TMP/fixture-k1-bad.md"
printf '$WT = worktreePath, $WB = worktreeBranch, both from the dispatch result (F10).\n' > "$FIXTURE_K1_BAD"
if both_retrieval_methods_stated "$FIXTURE_K1_BAD"; then
  bad "K1b (forward guard, mandatory negative twin): the K1 predicate wrongly passed a fixture stating only the F10 method (today's real content) — it cannot distinguish the fixed state from the gap"
else
  ok "K1b (forward guard, mandatory negative twin): the K1 predicate correctly rejects a fixture stating only the F10 method, same as today's real section"
fi

# ------------------------------------------------------------------------------------------------
# K2 / K2a (R-07, R-09) — `git worktree list` is named as the Workflow-path mechanism, not merely
# present as an unrelated string.
# ------------------------------------------------------------------------------------------------
enumeration_named_for_workflow() {
  # $1 = file. Exit 0 iff `git worktree list` appears AND the word "Workflow" appears in the same
  # file (a co-occurrence check; the paragraph-level binding is asserted qualitatively in K1/K3).
  grep -qF 'git worktree list' "$1" 2>/dev/null && grep -qi 'workflow' "$1" 2>/dev/null
}

if enumeration_named_for_workflow "$MB_SECTION_FILE"; then
  ok "K2: the merge-back section names git worktree list as the Workflow-path mechanism"
else
  bad "K2: the merge-back section does not name git worktree list as the Workflow-path mechanism — Task 9's evidence step confirmed enumeration reliably locates the Workflow worktree and the section must say so"
fi

FIXTURE_K2_GOOD="$TMP/fixture-k2-good.md"
printf 'On the Workflow dispatch path, use git worktree list to locate the worktree.\n' > "$FIXTURE_K2_GOOD"
if enumeration_named_for_workflow "$FIXTURE_K2_GOOD"; then
  ok "K2a (forward guard, mandatory positive twin): the K2 predicate passes a fixture naming git worktree list for the Workflow path"
else
  bad "K2a (forward guard, mandatory positive twin): the K2 predicate wrongly failed a fixture naming git worktree list for the Workflow path"
fi

# ------------------------------------------------------------------------------------------------
# K3 / K3a (R-07, R-09) — the section states that the Workflow path does NOT report worktree
# identity, citing F19, so a reader does not "simplify" the two retrieval methods back into one.
# ------------------------------------------------------------------------------------------------
workflow_identity_gap_cited() {
  # $1 = file. Exit 0 iff it states the Workflow path reports no worktree identity AND cites F19.
  grep -qF 'F19' "$1" 2>/dev/null \
    && grep -qiE 'does not report|no worktree identity|carries no worktree' "$1" 2>/dev/null
}

if workflow_identity_gap_cited "$MB_SECTION_FILE"; then
  ok "K3: the merge-back section states the Workflow path reports no worktree identity, citing F19 (R-07, R-09)"
else
  bad "K3: the merge-back section does not state that the Workflow path reports no worktree identity, citing F19 (R-07, R-09) — without this a reader can wrongly assume F10's method covers both dispatch paths"
fi

FIXTURE_K3_GOOD="$TMP/fixture-k3-good.md"
printf 'On the Workflow path the run journal does not report worktree identity at all (F19); use git worktree list instead.\n' > "$FIXTURE_K3_GOOD"
if workflow_identity_gap_cited "$FIXTURE_K3_GOOD"; then
  ok "K3a (forward guard, mandatory positive twin): the K3 predicate passes a fixture citing F19 and stating the identity gap"
else
  bad "K3a (forward guard, mandatory positive twin): the K3 predicate wrongly failed a fixture citing F19 and stating the identity gap"
fi

# ------------------------------------------------------------------------------------------------
# K4 / K4-guard0 / K4a / K4b (R-07, R-09) — the `<runId>-<n>` naming convention (F20) is not
# presented as the primary retrieval mechanism. Stated as a PRECEDENCE check, not a ban on
# mentioning the convention at all: F20 legitimately documents it. The predicate compares line
# position within a file — whichever of "git worktree list" / the runId convention pattern
# appears FIRST is treated as the one presented as primary.
# ------------------------------------------------------------------------------------------------
convention_not_presented_as_primary() {
  # $1 = file. Exit 0 (pass) iff:
  #   - the runId naming-convention pattern is absent (nothing to be primary over — vacuous only
  #     for the real section today, exercised non-vacuously by K4-guard0/K4a/K4b below), OR
  #   - `git worktree list` is absent when the convention IS present (nothing to prefer it over,
  #     which would itself be a K2 failure, not a K4 one), OR
  #   - `git worktree list`'s first line number is STRICTLY LESS than the convention pattern's
  #     first line number (enumeration is presented first / primary).
  # Exit 1 (fail) iff the convention pattern appears at or before git worktree list's first line
  # (or git worktree list is entirely absent while the convention is present).
  local f="$1"
  local conv_line enum_line
  conv_line=$(grep -nF '<runId>-<n>' "$f" 2>/dev/null | head -1 | cut -d: -f1)
  [ -z "$conv_line" ] && return 0
  enum_line=$(grep -nF 'git worktree list' "$f" 2>/dev/null | head -1 | cut -d: -f1)
  [ -z "$enum_line" ] && return 1
  [ "$enum_line" -lt "$conv_line" ]
}

if convention_not_presented_as_primary "$MB_SECTION_FILE"; then
  ok "K4: the merge-back section does not present the <runId>-<n> naming convention as the primary retrieval mechanism (F20) — today vacuously true, since neither method is mentioned yet; see K4-guard0/K4a/K4b for the non-vacuous form"
else
  bad "K4: the merge-back section presents the <runId>-<n> naming convention (F20) as the primary retrieval mechanism, ahead of (or instead of) git worktree list enumeration"
fi

FIXTURE_K4_GOOD="$TMP/fixture-k4-good.md"
printf 'Prefer git worktree list to locate the Workflow worktree.\nOnly as a documented fallback, the path follows the .claude/worktrees/<runId>-<n> naming convention (F20).\n' > "$FIXTURE_K4_GOOD"
if convention_not_presented_as_primary "$FIXTURE_K4_GOOD"; then
  ok "K4-guard0 (forward guard): the precedence predicate is exercised non-vacuously — a fixture naming BOTH methods, with git worktree list first, passes"
else
  bad "K4-guard0 (forward guard): the precedence predicate wrongly failed a fixture where git worktree list is stated before the naming convention — K4 cannot be trusted"
fi

if convention_not_presented_as_primary "$FIXTURE_K4_GOOD"; then
  ok "K4a (forward guard, mandatory positive twin): same fixture as K4-guard0 — git worktree list stated first is correctly treated as primary"
else
  bad "K4a (forward guard, mandatory positive twin): the K4 predicate wrongly failed a fixture where git worktree list precedes the naming convention"
fi

FIXTURE_K4_BAD="$TMP/fixture-k4-bad.md"
printf 'The Workflow worktree follows the .claude/worktrees/<runId>-<n> naming convention (F20). git worktree list also works.\n' > "$FIXTURE_K4_BAD"
if convention_not_presented_as_primary "$FIXTURE_K4_BAD"; then
  bad "K4b (forward guard, mandatory negative twin): the K4 predicate wrongly passed a fixture presenting the naming convention (F20) before git worktree list, i.e. as primary"
else
  ok "K4b (forward guard, mandatory negative twin): the K4 predicate correctly rejects a fixture presenting the naming convention (F20) as primary, ahead of git worktree list"
fi

# ==================================================================================================
# W. §D11 — isolation: worktree is a CWD convention, not a sandbox (issue #245).
#
# The escape was real and was disclosed by the agent that made it: a coder wrote into the shared
# checkout through an absolute path from inside a correctly-created worktree. Two live probes then
# established that a PreToolUse hook keyed on `cwd` is feasible AND would not have caught it — the
# escape came through mkdir/cp, i.e. Bash, whose tool_input carries no file_path at all.
#
# Prose clauses are matched against a whitespace-FLATTENED copy: a prose assertion must not depend
# on where markdown wraps the text (ADR-0073's lesson, and its relatives in ADR-0076/0080/0082;
# ADR-0088's own first run reproduced it again).
# ==================================================================================================
ADR68="$REPO/docs/architecture/ADR-0068-176-worktree-isolation-contract.md"

w_count_flat() {
  _n=$(tr '\n' ' ' <"$2" 2>/dev/null | tr -s ' ' | grep -oF -- "$1" 2>/dev/null | wc -l | tr -d ' ')
  [ -n "${_n:-}" ] || _n=0
  printf '%s' "$_n"
}

W_CLAUSE='Writes go under the dispatched worktree, never to an absolute path into the shared checkout'
# VCS-047/ADR-0174: all 4 occurrences of this clause live in references/step5-implementation.md.
n=$(w_count_flat "$W_CLAUSE" "$STEP5_REF")
if [ "$n" -eq 4 ]; then
  ok "W1: the working-root clause appears at exactly 4 dispatch sites (both tester templates, both coder templates)"
else
  bad "W1: expected the working-root clause at exactly 4 dispatch sites, found $n — a template without it dispatches an agent that was never told (#245)"
fi

# W2 — the check must read UNTRACKED, not the whole porcelain. The manifest is legitimately
# modified-tracked throughout Step 5 (#239), so a --porcelain check would halt every stage.
if grep -qF 'git ls-files --others --exclude-standard' "$STEP5_REF" 2>/dev/null; then
  ok "W2: the merge-back escape check reads untracked files, which is what leaves the #239 manifest case alone"
else
  bad "W2: the merge-back escape check does not use 'git ls-files --others --exclude-standard' (#245)"
fi

# W3 — ORDER is the property, not presence: after the merge the damage has already happened, and a
# path collision would have been reported as a conflict whose named cause is wrong.
# VCS-047/ADR-0174: both anchors now live in references/step5-implementation.md.
_esc=$(grep -n 'git ls-files --others --exclude-standard' "$STEP5_REF" 2>/dev/null | head -1 | cut -d: -f1)
_mrg=$(grep -n 'git merge --no-edit "\$WB"' "$STEP5_REF" 2>/dev/null | head -1 | cut -d: -f1)
if [ -n "$_esc" ] && [ -n "$_mrg" ] && [ "$_esc" -lt "$_mrg" ]; then
  ok "W3: the escape check runs BEFORE the merge (line $_esc < $_mrg)"
else
  bad "W3: the escape check does not precede the merge (escape=${_esc:-absent} merge=${_mrg:-absent}) — after it, the merge has already mis-reported the cause (#245)"
fi

if [ "$(w_count_flat 'is a CWD convention, not a sandbox' "$ADR68")" -ge 1 ]; then
  ok "W4: ADR-0068 states the threat model in the terms its sibling guards use"
else
  bad "W4: ADR-0068 does not state that isolation: worktree is a CWD convention, not a sandbox (§D11)"
fi

# W5 — the measurement that CLOSED an option has to survive in the record, or the next reader
# rebuilds the hook this ADR rejected and expects it to close the case.
if [ "$(w_count_flat 'would not have caught the incident' "$ADR68")" -ge 1 ]; then
  ok "W5: ADR-0068 records that a PreToolUse hook would not have caught the observed escape"
else
  bad "W5: ADR-0068 does not record why a hook is not the mechanism — the next reader will build it (#245)"
fi

# W6 — EXECUTED PREMISE, not fix evidence: passes before and after. The whole untracked-not-
# porcelain choice rests on a claim about git's behaviour, and rule 11 says a claim nobody ran is
# unverified. Real fixture repo, both directions.
W_FIX="$TMP/w6-repo"
mkdir -p "$W_FIX" && cd "$W_FIX" 2>/dev/null
git init -q . 2>/dev/null
git config user.email w6@example.invalid 2>/dev/null
git config user.name w6 2>/dev/null
printf 'tracked\n' > tracked.txt
git add tracked.txt 2>/dev/null && git commit -q -m init 2>/dev/null
printf 'modified\n' > tracked.txt                      # the #239 manifest shape
_only_modified=$(git ls-files --others --exclude-standard 2>/dev/null)
printf 'stray\n' > escaped.txt                         # the #245 escape shape
_with_stray=$(git ls-files --others --exclude-standard 2>/dev/null)
cd "$REPO" 2>/dev/null || cd /
if [ -z "$_only_modified" ] && [ "$_with_stray" = "escaped.txt" ]; then
  ok "W6 (premise, passes before and after): git ls-files --others is silent on a modified-tracked file and names an untracked one — the #239/#245 discrimination the check depends on"
else
  bad "W6: the untracked predicate does not discriminate as designed (modified-only='$_only_modified' with-stray='$_with_stray')"
fi

# ==============================================================================================
# Section L (issue #288, ADR-0119 §D3-§D6) — the cross-file isolation-claim assertion.
#
# ADR-0119 §D8 says "a new section K". Section K already exists in this file; L is the first free
# letter (A B C D G H I J K W are taken). §D8 also computes a floor of 96 from eight assertions;
# ten were needed, so Z1 sits at 98. Both recounted here rather than inherited — ADR-0083's rule.
#
# WHAT IS COMPARED. The guide's diagram parenthetical is a CLAIM about behaviour. What decides
# that behaviour is whether the step's SKILL.md block dispatches an agent with an isolation value
# pinned on it — a MECHANISM. Prose-to-prose was rejected (§D3): comparing the guide against
# SKILL.md's own "No worktree isolation" note would verify that two sentences agree, not that
# either is true, and it would go green the moment either side is reworded.
#
# FIVE states, not the four §D3 lists. UNMAPPED is the fifth and it is load-bearing: a first draft
# let a token with no matching block fall through to NEITHER, because an awk that never entered a
# block reaches END with an empty buffer and an empty buffer contains no mechanism. The two are
# then indistinguishable, and renaming `#### Step E2 — Execute` would silently remove E2 from the
# population — the check stays green while it stops looking. L5 pins the distinction.
#
# The claim predicate runs over the GUIDE ONLY. It does not distinguish an assertion from a denial
# (§D5, and ADR-0093 measured negation-in-prose and rejected it), so `nessuna worktree isolation`
# would fire it. The editing constraint that follows is stated at the guide's three corrected
# sites: state the absence positively, never by negating the claim phrase.
# ==============================================================================================

L_GUIDA="$REPO/docs/GUIDA-USO-IT.md"

# l_classify <skill.md> <step-id> -> DISPATCH|DIRECT|AMBIGUOUS|NEITHER|UNMAPPED
# Block boundary set is `^### ` or `^(##|###|####) (Step|Gate) `, both with the trailing space —
# measured fence-safe on this file (9 and 22 matches, 24 distinct lines, none inside a fence).
# Written as an explicit alternation rather than `#{2,4}`: interval expressions are the awk
# feature secret-scan.sh already has to exit 3 over, and nothing here needs them.
l_classify() {
  awk -v want="$2" '
    function isb(l) { return (l ~ /^### / || l ~ /^(##|###|####) (Step|Gate) /) }
    BEGIN { found=0; inb=0; buf="" }
    {
      if (isb($0)) {
        inb=0
        h=tolower($0); sub(/^#+ +/,"",h)
        if (h ~ ("^step " want " ")) { found=1; inb=1; buf="" }
        next
      }
      if (inb) buf = buf tolower($0) "\n"
    }
    END {
      if (!found) { print "UNMAPPED"; exit }
      d = (buf ~ /isolation:[^\n]*worktree/); r = (buf ~ /no sub-agents/)
      print (d && r) ? "AMBIGUOUS" : (d ? "DISPATCH" : (r ? "DIRECT" : "NEITHER"))
    }' "$1"
}

# l_claims <guide> <step-id> -> the guide lines that make a claim ABOUT that step, or nothing.
# A line references the step by its `step_<id>_…` state name, or — for the Express/Hybrid ids
# only — by the bare `[EH][0-9]+` token. The bare form is load-bearing rather than belt-and-
# braces: the third false site this issue fixed was `# E2: dispatch coder` in the usage example,
# which carries no state name at all and would sit outside the population without it.
l_claims() {
  awk -v want="$2" '
    BEGIN { bare = (want ~ /^[eh][0-9]+$/) }
    {
      l = tolower($0)
      if (l !~ /dispatch coder/ && l !~ /worktree isolation/) next
      if (l ~ ("step_" want "_")) { print NR ": " $0; next }
      if (bare && l ~ ("(^|[^a-z0-9_])" want "([^a-z0-9_]|$)")) { print NR ": " $0 }
    }' "$1"
}

# VCS-047/ADR-0174: Step 5's own body (isolation:/no-sub-agents mechanism included) moved into
# references/step5-implementation.md; SKILL.md keeps only the "### Step 5 —" heading plus a
# pointer paragraph. l_classify's block-buffer scan reads a single file, so a Step 5 block read
# from $CC alone would see an empty mechanism and misclassify as NEITHER — a false L2 hit. Splice
# the reference content back in, right after the heading, so the block boundaries l_classify walks
# match what actually ships (STEP5_REF carries no '### Step 5 —'/'### Step 6 —' heading of its own,
# so this cannot mis-nest into a neighbouring step).
L_CC_MERGED="$TMP/cc_merged_for_l.md"
awk -v step5file="$STEP5_REF" '
  /^### Step 5 —/ {
    print
    while ((getline line < step5file) > 0) print line
    close(step5file)
    skip=1
    next
  }
  skip && /^### Step 6 —/ { skip=0 }
  skip { next }
  { print }
' "$CC" > "$L_CC_MERGED"

# The population is every step token the guide actually names — derived, never listed here.
L_TOKENS=$(grep -oE 'step_[a-z0-9]+[a-z0-9_]*' "$L_GUIDA" 2>/dev/null \
  | sed -E 's/^step_([a-z0-9]+)_.*/\1/' | sort -u)
L_MAPPED=0; L_DIRECT_HIT=""; L_NEITHER_HIT=""; L_DISPATCH_CLAIMED=0; L_AMBIG=""
for _id in $L_TOKENS; do
  _cls=$(l_classify "$L_CC_MERGED" "$_id")
  [ "$_cls" = "UNMAPPED" ] || L_MAPPED=$((L_MAPPED+1))
  _cl=$(l_claims "$L_GUIDA" "$_id")
  case "$_cls" in
    AMBIGUOUS) L_AMBIG="$L_AMBIG $_id" ;;
    DIRECT)    [ -n "$_cl" ] && L_DIRECT_HIT="$L_DIRECT_HIT
  step_$_id -> $_cl" ;;
    DISPATCH)  [ -n "$_cl" ] && L_DISPATCH_CLAIMED=$((L_DISPATCH_CLAIMED+1)) ;;
    NEITHER)   printf '%s\n' "$_cl" | grep -qi 'worktree isolation' \
                 && L_NEITHER_HIT="$L_NEITHER_HIT
  step_$_id -> $_cl" ;;
  esac
done

# L0 — the DENOMINATOR, not the matches. Zero violations is the correct and common result, and it
# is exactly what a derivation that stopped resolving also produces. Guard the population, or
# every assertion below is vacuously true and reads as coverage (ADR-0085's rule).
# plant: L0 | plugin/scripts/tests/worktree-isolation-contract.test.sh | sed -E 's/^step_([a-z0-9]+)_.*/\1/' | sed -E 's/^NOPE_([a-z0-9]+)_.*/\1/'
if [ "$L_MAPPED" -ge 12 ]; then
  ok "L0 (denominator guard): $L_MAPPED of the guide's step tokens resolve to a SKILL.md block (floor: 12)"
else
  bad "L0: only $L_MAPPED token(s) resolved to a block — the extractor stopped matching, so L1-L4 are vacuous, not clean"
fi

# L1 — §D4 condition 1. Names THE GUIDE: the block pins no isolation value and says "No
# sub-agents", so the claim contradicts the mechanism, and SKILL.md is authoritative because it is
# what the orchestrator executes. If the step genuinely gained a dispatch, ADR-0119's premise has
# changed and the ADR is what must move, not this assertion.
# plant: L1 | ../docs/GUIDA-USO-IT.md | -> step_e2_execute   (esecuzione diretta, nessun sub-agent: edit nel working tree) | -> step_e2_execute   (dispatch coder, worktree isolation)
if [ -z "$L_DIRECT_HIT" ]; then
  ok "L1 (forward guard): no direct-execution step is claimed by the guide to dispatch or to isolate"
else
  bad "L1: THE GUIDE is wrong — it claims a dispatch or worktree isolation for a step whose SKILL.md block pins no isolation value and says 'No sub-agents':$L_DIRECT_HIT"
fi

# L2 — §D4 condition 2. Names SKILL.md: the guide may be describing yesterday's behaviour
# correctly and the block lost its pin, or a heading rewrite moved its boundary.
# plant: L2 | ../docs/GUIDA-USO-IT.md | -> step_7_commit           (skill commit) | -> step_7_commit           (worktree isolation)
if [ -z "$L_NEITHER_HIT" ]; then
  ok "L2 (forward guard): no step the guide credits with worktree isolation has a block that pins none"
else
  bad "L2: SKILL.md is wrong — its block pins no isolation value for a step the guide credits with worktree isolation (lost pin, or a heading rewrite moved the block boundary):$L_NEITHER_HIT"
fi

# L3 — §D4 condition 3, the POSITIVE TWIN. Without it L1 and L2 pass trivially on a guide with no
# parentheticals at all. "At least one", never "every": Step 6 is also DISPATCH and the guide's
# line for it carries no claim, which is correct and must not fail.
# plant: L3 | ../docs/GUIDA-USO-IT.md | (dispatch coder, worktree isolation, ultracode se hook_verified=true) | (esecuzione diretta)
if [ "$L_DISPATCH_CLAIMED" -ge 1 ]; then
  ok "L3 (positive twin): $L_DISPATCH_CLAIMED dispatching step(s) are claimed as such by the guide — L1/L2 are not passing on an empty guide"
else
  bad "L3: no guide line claims a dispatch or worktree isolation for any DISPATCH step — either the Standard diagram line lost its claim or Step 5 lost its pin"
fi

# L4 — AMBIGUOUS has never occurred. A block that both pins an isolation value and says "No
# sub-agents" describes two incompatible mechanisms and no verdict about it can be trusted.
# The plant targets a line INSIDE the E2 block, and both halves of that are earned. A replacement
# cannot contain a newline (ADR-0112), so a plant aimed at the `#### Step E2 — Execute` heading
# lands ON the heading, which the classifier skips via `next` — it does not fire, and the first
# draft of this plant did exactly that. E2 and H3 are near-identical prose, so almost every line
# in the block matches twice and is rejected by PC2; the transition call is the one line unique
# to E2.
# plant: L4 | plugin/skills/concept-to-code/SKILL.md | bash ~/.claude/skills/concept-to-code/scripts/manifest-transition.sh <manifest-path> gate_e3_verify | bash x.sh <manifest-path> gate_e3_verify   # isolation: "worktree"
if [ -z "$L_AMBIG" ]; then
  ok "L4 (forward guard): no step block is AMBIGUOUS (pinning an isolation value AND declaring no sub-agents)"
else
  bad "L4: block(s) both pin an isolation value and declare no sub-agents, so neither reading is trustworthy:$L_AMBIG"
fi

# L5 — the UNMAPPED/NEITHER distinction, executed rather than asserted in prose. `step_0_init` and
# `step_4_session_boundary` are real manifest states with no `Step 0`/`Step 4` heading in
# SKILL.md; they must report UNMAPPED. If they read NEITHER, the classifier has collapsed "no
# block found" into "block with no mechanism" and a renamed heading silently leaves the
# population. Note `Step 4.5` exists and must NOT satisfy id `4` — the trailing space in the
# heading match is what stops it.
# plant: L5 | plugin/scripts/tests/worktree-isolation-contract.test.sh | if (!found) { print "UNMAPPED"; exit } | if (!found) { print "NEITHER"; exit }
_l5_0=$(l_classify "$CC" 0); _l5_4=$(l_classify "$CC" 4)
if [ "$_l5_0" = "UNMAPPED" ] && [ "$_l5_4" = "UNMAPPED" ]; then
  ok "L5: a token with no matching block reports UNMAPPED, distinct from NEITHER (step_0_init, step_4_session_boundary)"
else
  bad "L5: an unmapped token does not report UNMAPPED (step_0='$_l5_0' step_4='$_l5_4') — 'no block found' is collapsing into 'block with no mechanism'"
fi

# L6 — the negative twin of L1, on a FIXTURE rather than on the live tree, so the detector is
# proven to fire without anyone having to break the repository to see it. This is the exact line
# this issue removed.
# plant: L6 | plugin/scripts/tests/worktree-isolation-contract.test.sh | if (l !~ /dispatch coder/ && l !~ /worktree isolation/) next | if (1) next
_l6_g="$TMP/l6-guida.md"
sed 's#-> step_e2_execute   (esecuzione diretta.*#-> step_e2_execute   (dispatch coder, worktree isolation)#' \
  "$L_GUIDA" > "$_l6_g" 2>/dev/null
_l6_hit=$(l_claims "$_l6_g" e2)
if [ -n "$_l6_hit" ] && [ "$(l_classify "$CC" e2)" = "DIRECT" ]; then
  ok "L6 (negative twin): the pre-#288 guide line is detected as a claim about a DIRECT step"
else
  bad "L6: the detector does not catch the very line #288 removed (hit='$_l6_hit' class='$(l_classify "$CC" e2)') — L1 is pinning nothing"
fi

# L7 — the negative twin of L4. A DIRECT block that acquires a pin must read AMBIGUOUS, not
# DISPATCH: silently promoting it would hide the contradiction rather than report it.
# The plant collapses AMBIGUOUS into DISPATCH — the silent-promotion failure L7 exists to catch,
# and the one that leaves L4 green while the contradiction goes unreported.
# plant: L7 | plugin/scripts/tests/worktree-isolation-contract.test.sh | print (d && r) ? "AMBIGUOUS" : (d ? "DISPATCH" : (r ? "DIRECT" : "NEITHER")) | print (d) ? "DISPATCH" : (r ? "DIRECT" : "NEITHER")
_l7_s="$TMP/l7-skill.md"
awk '{ print } /^#### Step E2 — Execute$/ { print ""; print "isolation: \"worktree\"" }' \
  "$CC" > "$_l7_s" 2>/dev/null
_l7_cls=$(l_classify "$_l7_s" e2)
if [ "$_l7_cls" = "AMBIGUOUS" ]; then
  ok "L7 (negative twin): a direct-execution block that acquires an isolation pin reads AMBIGUOUS"
else
  bad "L7: a block with both mechanisms reads '$_l7_cls', not AMBIGUOUS — the contradiction would be resolved silently instead of reported"
fi

# L8 — R-03. The Express note must state the absence as a DELIBERATE decision WITH its reason, not
# as a bare fact ("Known limitation" was the bare fact). Matched against a flattened, undecorated,
# lowercased copy: a clause is the same clause whether it wraps, whether a word in it is
# backticked, and whether it opens a sentence.
# plant: L8 | plugin/skills/concept-to-code/SKILL.md | **No worktree isolation, by design** — Step E2 dispatches no sub-agent | **No worktree isolation** — known limitation
_l8_flat=$(tr '\n' ' ' < "$CC" | tr -d '`*_' | tr '[:upper:]' '[:lower:]' | tr -s ' ')
_l8_missing=""
for _n in "no worktree isolation, by design" "dispatches no sub-agent" "no worktree to isolate" "the price of the single-session design"; do
  printf '%s' "$_l8_flat" | grep -qF "$_n" || _l8_missing="$_l8_missing [$_n]"
done
if [ -z "$_l8_missing" ]; then
  ok "L8 (R-03): the Express note states the absence of isolation as a deliberate decision and gives its reason"
else
  bad "L8 (R-03): the Express note no longer states the decision and its reason — missing:$_l8_missing"
fi

# L9 — rule 12, applied to the note this feature writes. §D6's prescribed wording quoted the
# DISPATCH mechanism string verbatim. It is harmless only while the note lives in the unmappable
# section-opener block; moved a few lines down into Step E2 it would classify that block
# AMBIGUOUS, and the guard would fire on the text written to satisfy it. The note must describe
# the pin, never spell it.
# plant: L9 | plugin/skills/concept-to-code/SKILL.md | requires every *dispatch* to pin that value explicitly | requires every *dispatch* to pin isolation: "worktree" explicitly
_l9_note=$(grep -F 'No worktree isolation, by design' "$CC" | head -1)
if [ -n "$_l9_note" ] && ! printf '%s' "$_l9_note" | grep -qiE 'isolation:[^ ]* *"?worktree'; then
  ok "L9: the Express note describes the isolation pin without spelling the literal that classifies a block as DISPATCH"
else
  bad "L9: the Express note spells the DISPATCH mechanism literal — moved into a mapped block it would classify that block AMBIGUOUS (rule 12)"
fi

# Section M (issue #488, ADR-0159) — no two concurrent builds share a build root.
#
# `isolation: worktree` gives each dispatch its own working directory. It does not, by itself, give
# a compiled-language build its own build OUTPUT directory, and a shared one is invisible until two
# worktrees race on it — reported live: a tester's worktree still building while the controller ran
# verification in the main checkout, an unsigned framework, a false red. The dangerous direction is
# the opposite one, a stale product reporting green on a broken tree.
#
# M1/M2 pin the pre-flight gate (Step 5.0.4b): a trusted xcodebuild test-cmd without
# `-derivedDataPath` refuses to dispatch, the same posture as 5.0.4 beside it. M3 pins the
# generator half (issue #488's other fix, in `detect-test-cmd.sh` — checked here too, since a
# chain-side prose gate with no corresponding generator update would tell every EXISTING project's
# operator to fix a file that every NEW project's detector still writes broken).
# Anchored on the CODE line inside the fence, not a bare substring match against the whole file:
# the remediation prose a few lines below ALSO mentions "-derivedDataPath" in English, so a bare
# `grep -F` would still find a hit after the check itself is neutralised (measured — a registry
# NOFIRE on the first draft).
# VCS-047/ADR-0174: M1's needle moved to references/step5-implementation.md.
_m1=$(grep -F -- "grep -q -- '-derivedDataPath' .claude/test-cmd" "$STEP5_REF" | head -1)
# plant: M1 | plugin/skills/concept-to-code/references/step5-implementation.md | grep -q -- '-derivedDataPath' .claude/test-cmd | true
if [ -n "$_m1" ]; then
  ok "M1: Step 5.0.4b's assertion body checks for -derivedDataPath in .claude/test-cmd, not just for its presence somewhere in the guide"
else
  bad "M1: no -derivedDataPath check found in $STEP5_REF — issue #488's pre-flight gate is missing"
fi

# VCS-047/ADR-0174: M2's needle moved to references/step5-implementation.md.
_m2=$(grep -F '5.0.4b' "$STEP5_REF" | grep -iF 'xcodebuild')
# The needle is the HEADING line alone — "build root (issue #488, ADR-0159)." also appears in a
# second, unrelated sentence at this file's Pre-dispatch worktree-isolation-contract section
# (measured: the first draft's needle matched both and would have been a registry BADPLANT, "must
# match exactly 1"). Anchored on "Step 5.0.4b —" to keep it unique to the heading.
# plant: M2 | plugin/skills/concept-to-code/references/step5-implementation.md | Step 5.0.4b — a trusted `xcodebuild` test-cmd names its own build root | Step 5.0.4b — a trusted test-cmd names its own build root
if [ -n "$_m2" ]; then
  ok "M2: Step 5.0.4b names xcodebuild — the gate is scoped to the stack it guards, not every test-cmd"
else
  bad "M2: Step 5.0.4b does not name xcodebuild — the gate's own scope is unstated or misworded"
fi

# Anchored on the -project CANDIDATE specifically: the bare flag text appears twice in this file
# (the -workspace candidate carries the identical suffix), and a needle matching two sites is a
# registry BADPLANT ("must match exactly 1") rather than a plant proving anything — measured on
# the first draft. -project is chosen arbitrarily between the two; either would do, and only one
# needs a plant to prove the count check below actually reads both.
# plant: M3 | plugin/scripts/detect-test-cmd.sh | CMD="xcodebuild test -project \"$pj\" -scheme \"$scheme\" -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath \"$PWD/.build/DerivedData\"" | CMD="xcodebuild test -project \"$pj\" -scheme \"$scheme\" -destination 'platform=iOS Simulator,name=iPhone 17'"
# Counted on CMD= lines only — the comment above this script's own two candidates also names the
# flag in prose, and a bare occurrence count would see three matches for two real candidates.
_m3_n=$(grep -F 'CMD="xcodebuild' "$STAGING/plugin/scripts/detect-test-cmd.sh" | grep -cF -- '-derivedDataPath')
if [ "$_m3_n" -eq 2 ]; then
  ok "M3: detect-test-cmd.sh writes -derivedDataPath on BOTH xcodebuild candidates (xcworkspace and xcodeproj)"
else
  bad "M3: detect-test-cmd.sh names -derivedDataPath $_m3_n time(s), expected 2 — a new project's generated candidate would still be broken"
fi

# M4/M5 (issue #494, ADR-0159) — the batch completion fact is read from the coder's worktree
# BEFORE that worktree's own merge-back runs, never after. Measured in a scratch repo (git
# 2.50.1): `git worktree remove` on a worktree whose only dirty content is gitignored succeeds
# (rc=0) and deletes the whole worktree tree, `.claude/dispatch/*.done` included — so reading the
# completion fact after an already-run merge-back means reading a path `git worktree remove` just
# deleted, and `dispatch-state.sh` reports NONE for a directory that does not exist. On a HEALTHY
# batch that is a spurious HALT, not a stale read: the two were left undistinguished until measured
# here (rule 13). M4 pins the ordering instruction at the coder-dispatch call site; M5 pins it
# again at the post-fence branch, where a `complete` verdict authorizes the merge-back rather than
# the other way round.
# plant: M4 | plugin/skills/concept-to-code/references/step5-implementation.md | BEFORE running its own merge-back | AFTER running its own merge-back
# VCS-047/ADR-0174: M4/M5's needles moved to references/step5-implementation.md.
if grep -qF "BEFORE running its own merge-back" "$STEP5_REF"; then
  ok "M4: the coder-dispatch step reads the completion fact BEFORE running that coder's own merge-back"
else
  bad "M4: no 'BEFORE running its own merge-back' instruction found in $STEP5_REF — the completion-fact read could run after the worktree that holds it is removed (#494)"
fi

# plant: M5 | plugin/skills/concept-to-code/references/step5-implementation.md | do NOT run the merge-back | do run the merge-back
if grep -qF "do NOT run the merge-back" "$STEP5_REF"; then
  ok "M5: a HALT from the completion-fact gate explicitly forbids running the merge-back — the worktree stays exactly as it is"
else
  bad "M5: no HALT-forbids-merge-back instruction found in $STEP5_REF — a HALT could still be followed by a merge-back that removes the very worktree it named"
fi

# Z1 — assertion-count floor. §D8: this file had none, so the vanishing-assertion class ADR-0083
# exists to catch was open here. A FLOOR, not an exact count, so adding an assertion does not
# require bumping it — EXCEPT when the addition closes the exact margin Z1's own -3 plant needs
# (rule 10, a floor absorbs its own plant). Measured, issue #488: Section M's first 3 assertions
# landed BEFORE this check runs, raising the pre-mutation total from 98 to 101 — exactly enough
# that 101-3=98 still clears a floor of 98, and the registry reported Z1 a NOFIRE. Bumped to 101 so
# that mutation cleared the then-current baseline's own margin. Bumped again to 103, issue #494:
# M4/M5 landed BEFORE this check too, and the same -3 plant against an un-bumped 101 would clear
# 98 < 101 without the new pair ever having run. Recounted here rather than inherited, the same
# discipline L9's comment already names for this file.
# plant: Z1 | plugin/scripts/tests/worktree-isolation-contract.test.sh | _l5_0=$(l_classify "$CC" 0); _l5_4=$(l_classify "$CC" 4) | _l5_0=UNMAPPED; _l5_4=UNMAPPED; PASS=$((PASS-3))
_z1_total=$((PASS + FAIL + 1))   # +1 counts Z1 itself, so the number matches the final PASS= line
if [ "$_z1_total" -ge 103 ]; then
  ok "Z1 (assertion floor): $_z1_total assertions ran (floor: 103)"
else
  bad "Z1: only $_z1_total assertions ran, floor is 103 — a section stopped running rather than failing"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
