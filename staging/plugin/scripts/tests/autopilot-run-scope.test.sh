#!/bin/bash
# autopilot-run-scope.test.sh — offline, hermetic, no network. Bash 3.2 clean.
# Targets staging/ directly, never the deployed $HOME/.claude/ copy.
# Run: bash autopilot-run-scope.test.sh
#
# Issue #365, ADR-0129. `/skill autopilot` takes no arguments today, so a launch attempts every
# unchecked PROJECT.md row and the only brakes are the /goal turn budget and a human hand.
#
# THIS FILE GROWS ACROSS TASKS 1-9 OF THE IMPLEMENTATION PLAN. Task 1 wrote Section KB (KB1-KB6)
# and the shared machinery; Task 2 (a separate batch, IMPL only) turned KB1/KB4/KB5/KB6 GREEN with
# no change to this file. This batch is Task 3's TEST sub-steps: Section RB (the rtf-blocker
# sentence in autopilot/SKILL.md §3.3), Section TU (the RUNBOOK's turn-budget restatement), and
# KB7/KB8 (the RUNBOOK's token-budget table row and its "five ways" count — ids stay in KB because
# the subject is the same removal KB1-KB6 already cover, not a new mechanism). Sections AR, RS, CG,
# RP and the Z1 floor still do not exist: they are later tasks' own RED/GREEN pairs and must not be
# written ahead of them (batch boundaries, ADR-0101 rule 1 — an assertion must not sit in the same
# batch as the task it depends on, and the mirror holds for a batch writing ahead of a task that has
# not run).
#
# WHY token-budget IS REMOVED RATHER THAN WIRED — three findings, and only the third settles it:
#   1. The proposed producer (ADR-0127 §D6) cannot produce what the consumer reads: it accumulates
#      `spent=` from step5-report.json's task_metrics, whose four ADR-0064 fields (test_count_delta,
#      deleted_lines, iteration_count, elapsed_wall_seconds) contain no token count at all.
#   2. That block does not exist anyway — the only real step5-report.json on disk carries no
#      task_metrics; agent-metrics.test.sh GA1/GA2 assert the field name in SKILL.md's schema block,
#      never in a produced report.
#   3. The halt is structurally unable to do its job: autopilot-guard.sh is a PreToolUse hook on
#      git push / gh pr create, so it gets a turn only at publish, once per feature, at the end. A
#      ceiling evaluated afterwards cannot stop the feature that exceeded it, only the one after —
#      cumulative drift, which --features N already bounds deterministically (Tasks 4-7, not here).
#
# ADR-0129 §D6 — THE VERDICT IS NOT TRANSFERRED TO rtf-blocker. rtf-blocker keeps its read in the
# guard and its clear in the disarm, BYTE-UNCHANGED. token-budget's halt was structurally unable to
# work (finding 3 above); rtf-blocker's halt would work correctly the moment something wrote it — no
# review cycle runs during an unattended roadmap run (concept-to-code Gate 5's autopilot default is
# "Skip review", and project-conductor invokes concept-to-code for every feature on both branches),
# which is a measured reason rtf-blocker is unproduced, not evidence its mechanism is unsound. KB2
# and KB3 below are the positive twins that pin this: a guard that halts on nothing is
# indistinguishable from one that works (ADR-0039's correction).
#
# DERIVED-GUARD PATTERN — NOT an instance. This file derives no population at run time; every
# section drives a fixed, named set of two scripts and (from Task 4 on) fence contracts. The
# count-guard idiom is deliberately absent for that reason (ADR-0086 §D1). Z1, added in Task 9, is
# an assertion FLOOR — a different thing: it catches an assertion that vanishes, not a derivation
# that stops resolving.
#
# ok()/bad() MUST print "FAIL: " with the colon — plant-check.sh attributes a fired plant on
# `^FAIL: <id>`, and a colon-less harness makes every plant here read as "did not fire" (ADR-0128 §D4).
#
# plant: KB1 | plugin/scripts/autopilot-guard.sh | reason="review-triage-fix raised a BLOCKER" print_halt "$reason" fi return 0 } | reason="review-triage-fix raised a BLOCKER"; print_halt "$reason"; fi; [ -f "$sdir/token-budget" ] && print_halt "token budget exceeded"; return 0; }
# plant: KB4 | plugin/scripts/autopilot-guard.sh | STATE_SUBDIR=".claude/autopilot-state" | STATE_SUBDIR=".claude/autopilot-state"; _plant_kb4="token-budget"
# plant: KB5 | plugin/scripts/autopilot-disarm.sh | "$SDIR/build-status" "$SDIR/rtf-blocker" | "$SDIR/build-status" "$SDIR/rtf-blocker" "$SDIR/scope"
# plant: KB6 | plugin/scripts/autopilot-disarm.sh | "$SDIR/build-status" "$SDIR/rtf-blocker" | "$SDIR/build-status" "$SDIR/rtf-blocker" "$SDIR/token-budget"
#
# KB1's needle targets the shape run_halt_checks has AFTER Task 2 deletes the token-budget block —
# it does not exist in today's tree, so plant-check.sh cannot validate it until Task 2 lands (Task 9
# does that validation; a mismatch there is a defect in the plant, per Task 9's own instruction, and
# is fixed there). KB4's needle targets a line untouched by this feature (STATE_SUBDIR), on purpose,
# so it is valid today and stays valid after Task 2 — the safer anchor of the two.
#
# KB5/KB6 RE-ANCHORED (issue #400, ADR-0167 §D1, Task 3). Their old needle,
# `"$SDIR/rtf-blocker" "$SDIR/scope"`, was the adjacency in the clear loop BEFORE ADR-0167 removed
# `scope` from it — that substring no longer exists (0 matches → BADPLANT). The new needle,
# `"$SDIR/build-status" "$SDIR/rtf-blocker"`, is the adjacent pair immediately before it that
# ADR-0167 left untouched (verified single-occurrence, on one line, no `\`-continuation between the
# two tokens). Each replacement re-inserts the ONE file its own assertion depends on: KB5's adds
# `"$SDIR/scope"` back to the loop (scope would be cleared again, falsifying "scope survives"); KB6's
# adds `"$SDIR/token-budget"` back to the loop (token-budget would be cleared, falsifying "token-budget
# survives" — unchanged from before this task).
#
# KB2/KB3 ARE REGRESSION GUARDS AND CARRY NO PLANT. Both assert mechanisms this feature does not
# touch — build-status and rtf-blocker are byte-unchanged by ADR-0129 §D6 — so mutating either would
# test a different feature's guardrail, not token-budget's removal. Their only job here is to prove
# that KB1's green (once Task 2 lands) is not a guard that has stopped halting on anything at all.
#
# Task 3 plants (RB/TU/KB7 sections, nine declarations). Each targets either an ANCHOR-PLUS-APPEND
# (a stable line unrelated to this feature, with the banned phrase appended — KB4's own technique,
# above) or a CONTENT MUTATION on the text the coder's IMPL sub-step is told to write, close to
# verbatim, from ADR-0129 §D6/§D11. Every content-mutation needle deliberately avoids a
# backtick-wrapped code span:
# plant-check.sh's needle match runs against the RAW file (backticks intact), unlike this file's own
# flattened, tick-stripped assertions below — a needle spanning a backtick boundary silently matches
# zero times and plant-check.sh reports it as a malformed declaration, not as "did not fire".
#
# plant: RB1 | plugin/skills/autopilot/SKILL.md | ## 4. Phase 2 — Morning report and disarm | ## 4. Phase 2 — Morning report and disarm (written by the review step and this skill's /goal overlay respectively)
# plant: RB2 | plugin/skills/autopilot/SKILL.md | deliberately unproduced | deliberately produced
# plant: RB3 | plugin/skills/autopilot/SKILL.md | for every feature on both branches | for every feature on one branch
# plant: RB4 | plugin/scripts/autopilot-guard.sh | if [ -f "$sdir/rtf-blocker" ]; then | if [ -f "$sdir/scope-removed" ]; then
# plant: TU1 | ../docs/RUNBOOK-autopilot.md | after N × 60 turns | after 200 turns
# plant: TU2 | ../docs/RUNBOOK-autopilot.md | n = 1 | n = 3
# plant: TU3 | ../docs/RUNBOOK-autopilot.md | not the bound | the primary bound
# plant: TU4 | ../docs/RUNBOOK-autopilot.md | Re-derive it from the morning report's | Estimate independently of the morning report's
# plant: KB7 | ../docs/RUNBOOK-autopilot.md | ## What the machine will never do | ## What the machine will never do (token-budget)
#
# RB1's and KB7's needles are anchor-plus-append: the text each assertion forbids will not exist
# ANYWHERE in the post-IMPL file to mutate directly (the whole point of RB1/KB7 is that it is gone),
# so the plant reintroduces it via a heading neither Task 3 sub-step touches ("## 4. Phase 2 —
# Morning report and disarm" in autopilot/SKILL.md; "## What the machine will never do" in the
# RUNBOOK, both verified single-occurrence today). RB2/RB3/TU1/TU3/TU4 target the CONTENT the coder
# is instructed to write and invert or remove the clause the assertion requires (RB2:
# unproduced→produced; RB3: both→one branch; TU1: N × 60→200, restoring the removed number; TU3:
# "not the bound"→"the primary bound", ADR-0127 §D8's superseded framing). RB4 (forward guard) and
# TU2 are POSITIVE assertions planted by deleting the literal string each requires — RB4 against
# autopilot-guard.sh's own `if [ -f "$sdir/rtf-blocker" ]; then` line (unique in the file; the
# header-comment mentions of rtf-blocker are NOT touched, so a plant that broke the comment instead
# of the code would prove nothing), TU2 against the literal `n = 1` sample-size figure ADR-0129 §D11
# measures. RB4 is the one plant of the nine that WAS validable at declaration time, because it
# targets autopilot-guard.sh, which Task 2 (a prior, separate batch) had already landed.
#
# TASK 9 SWEEP: RB1-RB3, RB4, KB7 and TU1-TU3 needed no repair — every needle still matches exactly
# one site against the real, landed autopilot/SKILL.md and RUNBOOK text. TU4's did not: it read
# "re-derive from the report's", and the coder's IMPL sub-step wrote a different sentence —
# "Re-derive it from the morning report's `scope.turns_per_feature`" — so the needle matched ZERO
# sites (rotted, not ambiguous). Re-anchored on the sentence as actually written,
# "Re-derive it from the morning report's" (confirmed unique), swapped for
# "Estimate independently of the morning report's". Confirmed against the real RUNBOOK: the
# assertion's own two-part check (`grep -qi "re-derive"` AND a `turns_per_feature` mention) passes on
# the unmutated file and fails on the mutated one, since "re-derive" is gone from the sentence.

set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
SKILLS="$STAGING/plugin/skills"
REPO=$(cd "$STAGING/.." && pwd)

GUARD="$SCRIPTS/autopilot-guard.sh"
DISARM="$SCRIPTS/autopilot-disarm.sh"
NA="$SKILLS/autopilot/SKILL.md"
PC="$SKILLS/project-conductor/SKILL.md"
RUNBOOK="$REPO/docs/RUNBOOK-autopilot.md"
SYNC="$STAGING/sync-to-claude.sh"

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

# =====================================================================================
# Shared machinery, copied from conductor-entry-failure-split.test.sh (not re-derived: later tasks
# in THIS file ask the same two questions — "extract a fence", "make a scratch root" — that file
# already answers; ADR-0086's criterion keeps it a copy because the two files are independently
# runnable and must fail independently).

# enumerate_fences <file> — "<opener-line>\t<marker-or-NONE>", indentation-tolerant.
enumerate_fences() {
  awk '
    {
      line = $0
      stripped = line; sub(/^[[:space:]]+/, "", stripped)
      if (stripped ~ /^<!--[[:space:]]*fence-(contract|illustration):/) { pending = stripped; next }
      if (stripped == "") { next }
      if (infence) { if (stripped == "```") { infence = 0 } ; next }
      if (stripped ~ /^```bash[[:space:]]*$/) {
        printf "%d\t%s\n", NR, (pending == "" ? "NONE" : pending)
        pending = ""; infence = 1; next
      }
      pending = ""
    }
  ' "$1"
}

# fence_body <file> <opener-line> — issue #394 / ADR-0133: strips AT MOST the opener's own
# indentation (`ind`), never more than a given line's OWN leading whitespace (`lw`) —
# `strip = (lw < ind) ? lw : ind`. The prior unconditional `substr($0, ind + 1)` corrupted a
# column-0 line inside an indented fence: `autopilot-scope-resolve` is indented 3, and its D1
# wrapper's column-0 `FENCE_BASH` terminator extracted as `CE_BASH`, which is no longer the
# heredoc's own terminator — the rest of the fence's body is swallowed into the heredoc and its exit
# code is destroyed. This fence's own execution stayed GREEN under the bug only because every branch
# it can take ends in an explicit `exit`, so the here-document-to-EOF form terminates before reaching
# the corrupted line — a green-by-accident the bug in `required-checks-audit.test.sh`'s
# `autopilot-check-8` (whose success arm falls through) exposed. `fence-contract-coverage.test.sh`
# carries the same fix under the same ADR (Task 2); this is a DELIBERATE COPY, not a shared import
# (ADR-0086: three private `fence_body`s already answer this file's own question independently, and
# each file must fail independently).
fence_body() {
  awk -v want="$2" '
    NR == want { match($0, /^[[:space:]]*/); ind = RLENGTH; infence = 1; next }
    infence {
      s = $0; sub(/^[[:space:]]+/, "", s)
      if (s == "```") { exit }
      match($0, /^[[:space:]]*/); lw = RLENGTH
      strip = (lw < ind) ? lw : ind
      print substr($0, strip + 1)
    }
  ' "$1"
}

# extract_fence <file> <id> — anchored on the MARKER, never a heading (ADR-0083 §D3).
extract_fence() {
  _ln=$(enumerate_fences "$1" | grep -F "fence-contract: ${2} -->" | head -1 | cut -f1)
  [ -n "$_ln" ] || return 1
  fence_body "$1" "$_ln"
}

# The substitution contract: a SKILL.md names the DEPLOYED path; this harness exercises staging/.
subst_paths() { sed -e "s|\$HOME/.claude/skills/|$SKILLS/|g" -e "s|~/.claude/skills/|$SKILLS/|g"; }

# run_fence <contract-id> <skill-md> <setup-script> — extract, substitute, prepend the setup that
# binds the fence's free variables, execute, print the exit code.
run_fence() {
  _id="$1"; _f="$2"; _setup="$3"
  _body=$(extract_fence "$_f" "$_id") || { echo "EXTRACT_FAILED"; return; }
  if [ -z "$_body" ]; then echo "EXTRACT_EMPTY"; return; fi
  _s="$TMPROOT/run-$_id.sh"
  { cat "$_setup"; printf '\n'; } >"$_s"
  printf '%s\n' "$_body" | subst_paths >>"$_s"
  ( bash "$_s" >"$TMPROOT/out-$_id" 2>&1 ); echo "$?"
}

out_of() { cat "$TMPROOT/out-$1" 2>/dev/null; }

FEATURE='Some feature  (issue #42)'

# mk_root <name> — a scratch project root. NOT a counter incremented inside $(...): that runs in a
# SUBSHELL, so every call returns the same directory and the fixtures accumulate into each other
# (ADR-0096's mk_root bug, met again in ADR-0110 and ADR-0124).
mk_root() {
  _r="$TMPROOT/$1"
  mkdir -p "$_r/docs/manifests" "$_r/docs/specs" "$_r/.claude/autopilot-state"
  printf -- '- [ ] %s\n- [ ] Another feature  (issue #77)\n' "$FEATURE" > "$_r/PROJECT.md"
  printf '%s' "$_r"
}

# arm <root> <session-id> — write a run marker in the current format (autopilot-guard-disarm.test.sh's
# shape). Needed by KB5/KB6, which exercise the disarm's RECOVERY path — a session that did NOT arm
# the marker — never the --completing path, which is out of scope for this feature.
arm() {
  printf 'session_id=%s\nstarted_at=%s\n' "$2" "2026-08-06T00:00:00Z" > "$1/.claude/autopilot-state/active"
}

# =====================================================================================
# KB. token-budget's removal (R-06, R-07). KB1/KB4/KB5/KB6 are RED until Task 2 lands; KB2/KB3 are
# regression guards and must stay green throughout.

# KB1: run_halt_checks no longer reads token-budget — a root carrying limit=1/spent=9 (a value that
# WOULD halt under today's code, spent >= limit) makes `autopilot-guard.sh --check` exit 0.
R=$(mk_root kb1)
printf 'limit=1\nspent=9\n' > "$R/.claude/autopilot-state/token-budget"
OUT=$(bash "$GUARD" --check "$R" 2>&1); RC=$?
if [ "$RC" = "0" ]; then
  ok "KB1: a spent>=limit token-budget file no longer halts --check"
else
  bad "KB1: rc=$RC — $(printf '%s' "$OUT" | head -1)"
fi

# KB2: a RED build-status still halts. REGRESSION GUARD, NO PLANT (see header) — build-status is
# byte-unchanged by this feature, so mutating it would test a different mechanism's guardrail.
R=$(mk_root kb2)
printf 'RED' > "$R/.claude/autopilot-state/build-status"
OUT=$(bash "$GUARD" --check "$R" 2>&1); RC=$?
if [ "$RC" = "2" ] && printf '%s' "$OUT" | grep -q 'AUTOPILOT-GUARD HALT'; then
  ok "KB2: a RED build-status still halts --check (regression guard, no plant — see header)"
else
  bad "KB2: rc=$RC — $(printf '%s' "$OUT" | head -1)"
fi

# KB3: rtf-blocker still halts. REGRESSION GUARD, NO PLANT for the same reason as KB2 — ADR §D6
# keeps rtf-blocker's read byte-unchanged; its verdict is deliberately NOT the one being removed.
R=$(mk_root kb3)
printf 'blocker\n' > "$R/.claude/autopilot-state/rtf-blocker"
OUT=$(bash "$GUARD" --check "$R" 2>&1); RC=$?
if [ "$RC" = "2" ] && printf '%s' "$OUT" | grep -q 'AUTOPILOT-GUARD HALT'; then
  ok "KB3: rtf-blocker still halts --check (regression guard, no plant — see header)"
else
  bad "KB3: rc=$RC — $(printf '%s' "$OUT" | head -1)"
fi

# KB4: the string token-budget is gone from autopilot-guard.sh entirely — not just the read, the
# word. R-07's "no remaining reference asserting it has a producer" half, asserted literally.
if ! grep -q 'token-budget' "$GUARD"; then
  ok "KB4: the string token-budget no longer appears anywhere in autopilot-guard.sh"
else
  bad "KB4: token-budget is still named in autopilot-guard.sh — $(grep -n 'token-budget' "$GUARD" | head -1)"
fi

# KB5/KB6: both from a FOREIGN-SESSION fixture, so the RECOVERY path (autopilot-guard-disarm.test.sh
# section O) is the one exercised — never the --completing path, which this feature does not touch.
R=$(mk_root kb56); arm "$R" "session-AAA"
printf 'source=arguments\nfeatures=2\n' > "$R/.claude/autopilot-state/scope"
printf 'limit=1\nspent=9\n' > "$R/.claude/autopilot-state/token-budget"
OUT=$(CLAUDE_CODE_SESSION_ID=session-BBB bash "$DISARM" "$R" 2>&1); RC=$?

# KB5 was "a scope file is cleared by autopilot-disarm.sh" (issue #365, ADR-0129 §D1); inverted by
# issue #400, ADR-0167 §D1. KB5: a scope file SURVIVES the disarm — on the same terms `published`
# already does (ADR-0167 §D1): both are the run's configuration/progress, not guard conditions.
if [ "$RC" = "0" ] && [ -f "$R/.claude/autopilot-state/scope" ]; then
  ok "KB5: a scope file SURVIVES autopilot-disarm.sh (ADR-0167 §D1 — configuration, not a guard condition)"
else
  bad "KB5: rc=$RC scope=$( [ -f "$R/.claude/autopilot-state/scope" ] && echo present || echo absent ) — $(printf '%s' "$OUT" | head -1)"
fi

# KB6: token-budget is no longer in the cleared set — the SAME fixture wrote a token-budget file,
# and it must survive the disarm untouched once the loop no longer names it.
if [ -f "$R/.claude/autopilot-state/token-budget" ]; then
  ok "KB6: token-budget is no longer named in autopilot-disarm.sh's cleared loop (the file survives)"
else
  bad "KB6: token-budget was cleared by the disarm — it is still named in the loop"
fi

# =====================================================================================
# RB. Task 3 (issue #365, ADR-0129 §D6): the rtf-blocker sentence in autopilot/SKILL.md §3.3.
# RB1-RB3 are RED until the coder's IMPL sub-step lands; RB4 is a FORWARD GUARD — green before this
# task's IMPL runs AND after, because it proves the mechanism itself (the guard's rtf-blocker read,
# the disarm's rtf-blocker clear) is untouched by ADR-0129, asserted against autopilot-guard.sh and
# autopilot-disarm.sh directly, never against the prose — the negative of "tidy it away for
# consistency with token-budget's removal". Prose checks (RB1-RB3) match a flattened, undecorated,
# case-insensitive copy of autopilot/SKILL.md: a clause is the same clause whether it wraps, is
# bolded, or is backticked.

NA_FLAT=$(tr '\n' ' ' < "$NA" | tr -s ' ' | tr -d '`*')

# RB1: the file no longer claims rtf-blocker/token-budget have a producer.
if printf '%s' "$NA_FLAT" | grep -qi "written by the review step and this skill's /goal overlay respectively"; then
  bad "RB1: autopilot/SKILL.md still claims rtf-blocker/token-budget are written by a producer"
else
  ok "RB1: autopilot/SKILL.md no longer claims a producer exists for rtf-blocker (or token-budget)"
fi

# RB2: it states rtf-blocker is deliberately unproduced.
if printf '%s' "$NA_FLAT" | grep -qi "deliberately unproduced"; then
  ok "RB2: autopilot/SKILL.md states rtf-blocker is deliberately unproduced"
else
  bad "RB2: autopilot/SKILL.md does not state rtf-blocker is deliberately unproduced"
fi

# RB3: it names the measured reason (concept-to-code Gate 5's autopilot default skips review;
# project-conductor invokes concept-to-code on both branches, never autopilot-build) — ADR §D6.
RB3_OK=1
printf '%s' "$NA_FLAT" | grep -qi "gate 5's autopilot default is" || RB3_OK=0
printf '%s' "$NA_FLAT" | grep -qi "skip review" || RB3_OK=0
printf '%s' "$NA_FLAT" | grep -qi "invokes concept-to-code" || RB3_OK=0
printf '%s' "$NA_FLAT" | grep -qi "both branches" || RB3_OK=0
printf '%s' "$NA_FLAT" | grep -qi "never autopilot-build" || RB3_OK=0
if [ "$RB3_OK" = "1" ]; then
  ok "RB3: autopilot/SKILL.md names the measured reason rtf-blocker is unproduced"
else
  bad "RB3: autopilot/SKILL.md does not name the measured reason (Gate 5 skip-review / both branches / never autopilot-build)"
fi

# RB4 (FORWARD GUARD, planted — see header): the guard's rtf-blocker read and the disarm's
# rtf-blocker clear are both still present. Green before Task 3's IMPL lands and must stay green
# after — this feature does not touch either mechanism (ADR §D6, byte-unchanged).
if grep -qF 'if [ -f "$sdir/rtf-blocker" ]; then' "$GUARD" && grep -qF '"$SDIR/rtf-blocker"' "$DISARM"; then
  ok "RB4: the guard's rtf-blocker read and the disarm's rtf-blocker clear are both still present (forward guard)"
else
  bad "RB4: rtf-blocker's read or clear disappeared from the guard/disarm — a working mechanism was tidied away, not corrected (ADR §D6)"
fi

# =====================================================================================
# TU. Task 3 (issue #365, ADR-0129 §D11): the RUNBOOK's turn-budget restatement. All four RED until
# the coder's IMPL sub-step lands. Prose checks match a flattened, undecorated, case-insensitive
# copy of docs/RUNBOOK-autopilot.md, reached at plant time via the ../docs/ hatch (issue #339) since
# this file lives outside staging/.

RUNBOOK_FLAT=$(tr '\n' ' ' < "$RUNBOOK" | tr -s ' ' | tr -d '`*')

# TU1: the /goal template carries N × 60, not 200.
if printf '%s' "$RUNBOOK_FLAT" | grep -qi "200 turns"; then
  bad "TU1: the RUNBOOK's /goal template still says 200 turns"
elif printf '%s' "$RUNBOOK_FLAT" | grep -qi "n × 60"; then
  ok "TU1: the RUNBOOK's /goal template carries N × 60 and not 200"
else
  bad "TU1: the RUNBOOK's /goal template names neither N × 60 nor 200"
fi

# TU2: it states the sample size (one measured chain, n = 1).
if printf '%s' "$RUNBOOK_FLAT" | grep -qi "n = 1"; then
  ok "TU2: the RUNBOOK states the sample size (n = 1)"
else
  bad "TU2: the RUNBOOK does not state the sample size"
fi

# TU3: it calls the budget a fail-safe for a run that hangs, rather than the bound.
if printf '%s' "$RUNBOOK_FLAT" | grep -qi "fail-safe for" && printf '%s' "$RUNBOOK_FLAT" | grep -qi "not the bound"; then
  ok "TU3: the RUNBOOK calls the turn budget a fail-safe, not the bound"
else
  bad "TU3: the RUNBOOK does not call the turn budget a fail-safe distinct from the bound"
fi

# TU4: it instructs re-derivation from the report's per-feature turns.
TU4_OK=0
if printf '%s' "$RUNBOOK_FLAT" | grep -qi "re-derive"; then
  if printf '%s' "$RUNBOOK_FLAT" | grep -qi "turns_per_feature" || printf '%s' "$RUNBOOK_FLAT" | grep -qi "turns per feature"; then
    TU4_OK=1
  fi
fi
if [ "$TU4_OK" = "1" ]; then
  ok "TU4: the RUNBOOK instructs re-deriving the budget from the report's per-feature turns"
else
  bad "TU4: the RUNBOOK does not instruct re-deriving the budget from the report"
fi

# =====================================================================================
# KB7/KB8. Task 3 (issue #365, ADR-0129 §D6): the RUNBOOK's stuck-table loses its token-budget row
# and its intro count drops from five to four. Ids stay in Section KB because the subject is the
# same removal KB1-KB6 already cover, not a new mechanism.

# KB7: the stuck-table no longer carries a token-budget row.
if ! grep -q 'token-budget' "$RUNBOOK"; then
  ok "KB7: the RUNBOOK's stuck-table no longer carries a token-budget row"
else
  bad "KB7: token-budget is still named in docs/RUNBOOK-autopilot.md — $(grep -n 'token-budget' "$RUNBOOK" | head -1)"
fi

# KB8 NOW HAS A PLANT, added in Task 9's sweep: the intro's own count sentence, "four ways to be
# stuck" (unique in the RUNBOOK — the "five" form no longer exists anywhere post-IMPL, so unlike
# RB1/KB7's anchor-plus-append this is a direct content mutation), inverted back to "five". Confirmed
# against the real RUNBOOK: the mutated file trips KB8's first branch ("still counts five") instead
# of its second, going red. Declared here rather than in the top header, for the same reason Section
# AR's plants are declared at their own site (plant-check.sh's extraction is position-independent).
#
# plant: KB8 | ../docs/RUNBOOK-autopilot.md | four ways to be stuck | five ways to be stuck
#
# KB8: the intro counts four ways to be stuck, not five. Its content is the same row KB7 already
# targets, from the other side (the row gone vs. the count that named it).
if printf '%s' "$RUNBOOK_FLAT" | grep -qi "five ways to be stuck"; then
  bad "KB8: the RUNBOOK's intro still counts five ways to be stuck"
elif printf '%s' "$RUNBOOK_FLAT" | grep -qi "four ways to be stuck"; then
  ok "KB8: the RUNBOOK's intro counts four ways to be stuck, not five"
else
  bad "KB8: the RUNBOOK's intro names neither four nor five ways to be stuck"
fi

# =====================================================================================
# AR. Task 4 (issue #365, ADR-0129 §D7): the autopilot-scope-args fence contract (R-01, R-02,
# R-11). TEST ONLY — the fence does not exist yet (Task 5, a later batch, adds it above §1.4 Phase
# M), so every AR case is RED via EXTRACT_FAILED right now: run_fence's own contract is "echo
# EXTRACT_FAILED and return" when enumerate_fences/extract_fence find no
# `fence-contract: autopilot-scope-args -->` marker in autopilot/SKILL.md, which is exactly what
# rule 1 of ADR-0101 protects — a RED for the right reason, not a broken harness.
#
# PLANTS — declared here rather than in the top header, because the dispatch that wrote this
# section was told to disturb nothing above it; plant-check.sh's own extraction is `grep '^# plant:'`
# over the WHOLE file (column-anchored only, position-independent — ADR-0115's PC4), so a plant
# declared here is exactly as valid as one declared at the top.
#
# TASK 9 SWEEP (issue #365 Task 9's own instruction: "any plant that does not fire is a defect in
# the plant or the assertion — fix the right one"), now that Task 5's IMPL exists:
#
#   AR1/AR2/AR3/AR4/AR7 needed no repair — each needle still matches exactly one site (measured, not
#   assumed), and AR4 was independently re-verified by extracting the real fence and running it: the
#   mutation (`_only="$_cli_only"` → `_only="$_cli_only $_marker_only"`) leaks a literal space into
#   `$_only` because `$_marker_only` is genuinely unset on the arguments branch (no `set -u` in the
#   extracted fence), so `[ -n "$_only" ]` goes true and the SCOPE-PARSE line grows an `only=` token
#   AR4's negative half forbids. Confirmed to fire against the mutated fence and to stay silent
#   against the real one — the residual risk this plant's needle named (a differently-shaped discard)
#   did not materialise.
#
#   AR5/AR6 collided: the bare phrase "positive integer" also appears in this file's own `--features`
#   prose two lines above the fence (`--features N ... N a positive integer`), so the needle matched
#   TWICE and both plants were rejected as ambiguous. Re-anchored on the compound
#   "must be a positive integer", which exists only in the fence's own echoed message — one site,
#   confirmed by re-running both fixtures against the mutated fence (`must be a whole number` in the
#   output, `positive integer` gone).
#
#   AR8 collided the same way: "dry_run=false" is a substring of the fence's own initialiser
#   (`_dry_run=false`) AND of an unrelated RUNBOOK-flavoured prose sentence in this file
#   ("On pass with `dry_run=false`, fall into Phase M."). Re-anchored on `_dry_run=false` (the
#   leading underscore is present only at the initialiser), confirmed to flip the flag's own default
#   from false to true when mutated.
#
#   RETARGETED (issue #385 dispatch, Batch 3 test-authoring pass). Task 5 moved the initialisers
#   and the parse loop out of autopilot/SKILL.md's fence and into scope-args-parse.sh (ADR-0132
#   §D2 — only that narrow excision, not the marker branch or the output line, which stay in the
#   fence). `_dry_run=false` now matches exactly once, in the new script, and zero times in
#   SKILL.md — measured, not assumed. AR1-AR7, AR9 are untouched: their needles sit in the
#   marker/validation/output section that did NOT move.
#
#   AR9 collided with Fence 2's own two DID-NOT-RUN sites (RS9's territory, added by Task 7). Bare
#   "DID-NOT-RUN" now matches three places across this one file. Re-anchored on
#   "exists but is not readable — DID-NOT-RUN" (Fence 1's exact message, em-dash and all — Fence 2's
#   sibling message uses a double-hyphen "--" and reads "the check DID-NOT-RUN", so the two do not
#   share a substring longer than the bare token). Confirmed against the mutated fence: exit code
#   stays 3 (untouched), the token becomes DID_NOT_RUN, and AR9's `grep -q 'DID-NOT-RUN'` goes red.
#
# plant: AR1 | plugin/skills/autopilot/SKILL.md | source=none | source=marker
# plant: AR2 | plugin/skills/autopilot/SKILL.md | source=arguments | source=none
# plant: AR3 | plugin/skills/autopilot/SKILL.md | source=marker | source=none
# plant: AR4 | plugin/skills/autopilot/SKILL.md | _only="$_cli_only" | _only="$_cli_only $_marker_only"
# plant: AR5 | plugin/skills/autopilot/SKILL.md | must be a positive integer | must be a whole number
# plant: AR6 | plugin/skills/autopilot/SKILL.md | must be a positive integer | must be a whole number
# plant: AR7 | plugin/skills/autopilot/SKILL.md | block is empty | block is unusual
# plant: AR8 | plugin/skills/autopilot/scripts/scope-args-parse.sh | _dry_run=false | _dry_run=true
# plant: AR9 | plugin/skills/autopilot/SKILL.md | exists but is not readable — DID-NOT-RUN | exists but is not readable — DID_NOT_RUN

# mk_ar_root <name> — a scratch root for Fence 1 (Phase S). No PROJECT.md, no docs/: ADR-0129 §D7
# states Phase S reads the arguments and the opt-in marker and NOTHING ELSE — in particular not
# PROJECT.md, which does not exist yet in auto-design mode.
mk_ar_root() {
  _r="$TMPROOT/$1"
  mkdir -p "$_r/.claude"
  printf '%s' "$_r"
}

# setup_ar <root> <args> — binds the two free variables Fence 1 declares: _root and _args (the raw
# argument string), per ADR-0129 §D7 / Task 5's bullet 2. CLAUDE_PLUGIN_ROOT is bound to the
# STAGING copy (issue #385, ADR-0132 §D2/§D4): once Task 5's coder sub-step lands, the fence
# resolves scope-args-parse.sh two-tier through this variable first, exactly the pattern
# conductor-entry-failure-split.test.sh's setup() and recovery-preflight.test.sh's rj_run() already
# bind. An unbound CLAUDE_PLUGIN_ROOT falls through to $HOME/.claude and can make an assertion pass
# from the deployed copy instead of staging/ — that exact defect was found in this session's own
# RJ14 and it was green while testing nothing. Inert today: no fence in this file references the
# variable yet, so no currently-passing assertion changes behaviour from this binding alone.
setup_ar() {
  cat >"$TMPROOT/setup-ar.sh" <<SETUP_EOF
_root='$1'
_args='$2'
CLAUDE_PLUGIN_ROOT='$STAGING/plugin'
SETUP_EOF
  printf '%s' "$TMPROOT/setup-ar.sh"
}

# AR1: no arguments and no scope: block -> exit 0, the exact literal
# "SCOPE-PARSE: OK source=none features=" and no only= anywhere in the output (Task 4's own wording).
R=$(mk_ar_root ar1)
RC=$(run_fence "autopilot-scope-args" "$NA" "$(setup_ar "$R" "")")
OUT=$(out_of autopilot-scope-args)
if [ "$RC" = "0" ] && printf '%s' "$OUT" | grep -qF 'SCOPE-PARSE: OK source=none features=' \
   && ! printf '%s' "$OUT" | grep -q 'only='; then
  ok "AR1: no args, no marker -> source=none, features= empty, no only= at all"
else
  bad "AR1: rc=$RC — $(printf '%s' "$OUT" | head -2)"
fi

# AR2: --features 2 --only 293,294 -> exit 0, source=arguments features=2 only=293,294.
R=$(mk_ar_root ar2)
RC=$(run_fence "autopilot-scope-args" "$NA" "$(setup_ar "$R" "--features 2 --only 293,294")")
OUT=$(out_of autopilot-scope-args)
if [ "$RC" = "0" ] && printf '%s' "$OUT" | grep -q 'source=arguments' \
   && printf '%s' "$OUT" | grep -q 'features=2' \
   && printf '%s' "$OUT" | grep -q 'only=293,294'; then
  ok "AR2: --features 2 --only 293,294 -> source=arguments features=2 only=293,294"
else
  bad "AR2: rc=$RC — $(printf '%s' "$OUT" | head -2)"
fi

# AR3: a .claude/autopilot.yml carrying scope: with features: 3, and no arguments -> source=marker
# features=3.
R=$(mk_ar_root ar3)
printf 'scope:\n  features: 3\n' > "$R/.claude/autopilot.yml"
RC=$(run_fence "autopilot-scope-args" "$NA" "$(setup_ar "$R" "")")
OUT=$(out_of autopilot-scope-args)
if [ "$RC" = "0" ] && printf '%s' "$OUT" | grep -q 'source=marker' \
   && printf '%s' "$OUT" | grep -q 'features=3'; then
  ok "AR3: a scope: marker with features: 3 and no args -> source=marker features=3"
else
  bad "AR3: rc=$RC — $(printf '%s' "$OUT" | head -2)"
fi

# AR4 (NEGATIVE — see header): the same marker PLUS --features 2 -> source=arguments features=2, and
# the marker's own only: values (9101/9102, chosen to collide with no other fixture in this file) are
# ABSENT from the output — the whole-block discard, R-02 / ADR-0129 A4.
R=$(mk_ar_root ar4)
printf 'scope:\n  features: 3\n  only: "9101,9102"\n' > "$R/.claude/autopilot.yml"
RC=$(run_fence "autopilot-scope-args" "$NA" "$(setup_ar "$R" "--features 2")")
OUT=$(out_of autopilot-scope-args)
if [ "$RC" = "0" ] && printf '%s' "$OUT" | grep -q 'source=arguments' \
   && printf '%s' "$OUT" | grep -q 'features=2' \
   && ! printf '%s' "$OUT" | grep -q '9101' \
   && ! printf '%s' "$OUT" | grep -q 'only='; then
  ok "AR4: a scoping argument discards the marker's only: block WHOLE, never merges it (R-02)"
else
  bad "AR4: rc=$RC — $(printf '%s' "$OUT" | head -2)"
fi

# AR5: --features 0 -> exit 2, message names the value (word-bounded "0") and the reason ("positive
# integer" — the exact phrase this assertion requires, part of the plant's needle; see header).
R=$(mk_ar_root ar5)
RC=$(run_fence "autopilot-scope-args" "$NA" "$(setup_ar "$R" "--features 0")")
OUT=$(out_of autopilot-scope-args)
if [ "$RC" = "2" ] && printf '%s' "$OUT" | grep -qi 'positive integer' \
   && printf '%s' "$OUT" | grep -qE '(^|[^0-9])0([^0-9]|$)'; then
  ok "AR5: --features 0 -> exit 2, message names the value and the reason"
else
  bad "AR5: rc=$RC — $(printf '%s' "$OUT" | head -2)"
fi

# AR6: --features x -> exit 2, message names the value (word-bounded "x") and the same reason.
R=$(mk_ar_root ar6)
RC=$(run_fence "autopilot-scope-args" "$NA" "$(setup_ar "$R" "--features x")")
OUT=$(out_of autopilot-scope-args)
if [ "$RC" = "2" ] && printf '%s' "$OUT" | grep -qi 'positive integer' \
   && printf '%s' "$OUT" | grep -qE '(^|[^A-Za-z0-9_])x([^A-Za-z0-9_]|$)'; then
  ok "AR6: --features x -> exit 2, message names the value and the reason"
else
  bad "AR6: rc=$RC — $(printf '%s' "$OUT" | head -2)"
fi

# AR7: a scope: block that is present but EMPTY -> exit 2, message names the block. A malformed
# bound must not read as an absent one (SPEC edge cases). "block is empty" is the exact phrase this
# assertion requires, so it is also the plant's needle; see header.
R=$(mk_ar_root ar7)
printf 'scope:\n' > "$R/.claude/autopilot.yml"
RC=$(run_fence "autopilot-scope-args" "$NA" "$(setup_ar "$R" "")")
OUT=$(out_of autopilot-scope-args)
if [ "$RC" = "2" ] && printf '%s' "$OUT" | grep -qi 'scope' && printf '%s' "$OUT" | grep -qi 'block is empty'; then
  ok "AR7: an empty scope: block -> exit 2, message names the block"
else
  bad "AR7: rc=$RC — $(printf '%s' "$OUT" | head -2)"
fi

# AR8: --dry-run -> exit 0, dry_run=true; without it, dry_run=false. Two invocations of the same
# fence, one assertion — both halves must hold for the flag's default and its override to be pinned
# together.
R=$(mk_ar_root ar8)
RC_T=$(run_fence "autopilot-scope-args" "$NA" "$(setup_ar "$R" "--dry-run")")
OUT_T=$(out_of autopilot-scope-args)
RC_F=$(run_fence "autopilot-scope-args" "$NA" "$(setup_ar "$R" "")")
OUT_F=$(out_of autopilot-scope-args)
if [ "$RC_T" = "0" ] && printf '%s' "$OUT_T" | grep -q 'dry_run=true' \
   && [ "$RC_F" = "0" ] && printf '%s' "$OUT_F" | grep -q 'dry_run=false'; then
  ok "AR8: --dry-run -> dry_run=true; without it -> dry_run=false"
else
  bad "AR8: rc_true=$RC_T rc_false=$RC_F — $(printf '%s' "$OUT_T" | head -1) / $(printf '%s' "$OUT_F" | head -1)"
fi

# AR9: an UNREADABLE opt-in marker -> exit 3, DID-NOT-RUN, distinct from AR7's exit 2. Skipped when
# the test user can read a chmod-000 file (CI often runs as root — ADR-0028's caveat), because there
# the fixture cannot express the state at all and a pass would be for the wrong reason.
R=$(mk_ar_root ar9)
printf 'scope:\n  features: 1\n' > "$R/.claude/autopilot.yml"
chmod 000 "$R/.claude/autopilot.yml" 2>/dev/null
if [ -r "$R/.claude/autopilot.yml" ]; then
  ok "AR9 (skipped, not asserted): this user can read a chmod-000 file, so the unreadable-marker state is not expressible here"
else
  RC=$(run_fence "autopilot-scope-args" "$NA" "$(setup_ar "$R" "")")
  OUT=$(out_of autopilot-scope-args)
  if [ "$RC" = "3" ] && printf '%s' "$OUT" | grep -q 'DID-NOT-RUN'; then
    ok "AR9: an unreadable opt-in marker -> exit 3, DID-NOT-RUN"
  else
    bad "AR9: rc=$RC — $(printf '%s' "$OUT" | head -2)"
  fi
fi

# =====================================================================================
# RS. Task 6 (issue #365, ADR-0129 §D7 fence 2, §D2/§D3/§D4/§D8): the autopilot-scope-resolve
# fence contract (R-05, R-06, R-11). TEST ONLY — the fence does not exist until Task 7 (a later
# batch) adds it as Phase 0 check 9, so every RS case is RED via EXTRACT_FAILED right now, for the
# same reason Section AR is: run_fence's own contract on a missing
# `fence-contract: autopilot-scope-resolve -->` marker.
#
# Fixture: mk_rs_root builds one shared PROJECT.md with four rows — an (issue #293) row, an
# (issue #29) row (the prefix-collision case D3 names by number), a hand-written row carrying NO
# issue marker (the topic-slug path), and a `- [x]` row — matching roadmap-from-issues.sh:103's
# measured `- [ ] %s  (issue #%s)` format (two spaces before the marker) exactly, not a convenient
# approximation of it. mk_rs_dup_root is a second, separate fixture for RS5 alone: two hand-written
# rows whose titles diverge only AFTER the 40-char slug-truncation boundary, so both derive the
# IDENTICAL topic-slug — a real truncation collision (ADR-0129 §D3), not a contrived duplicate
# issue number. RS9 reuses Section AR's own mk_ar_root (no PROJECT.md at all): the same "does not
# exist" state, a different fence.
#
# PLANTS — TASK 9 SWEEP. All seven of RS1/RS2/RS3/RS5/RS6/RS7/RS9's needles were the bare
# FILE-FORMAT KEY LITERALS the header used to name (`only=`/`source=`/`features=`/the scope-file
# PATH/`DID-NOT-RUN`), and the residual risk it predicted materialised exactly as described: once
# Fence 1 and Fence 2 both exist in this file, each bare token matches 2-9 static sites and every one
# of the seven was rejected as ambiguous (measured, not guessed — plant-check.sh's own match count).
# Re-anchored, one at a time, by extracting the real Fence 2 body and running the mutated fixture
# before declaring the plant (never by reading the source and assuming):
#
#   RS1 — was "not a slug" and stayed the closest to it: targets the `1)` match-count branch's own
#   title extraction, `_title=$(printf '%s' "$_matches"`, and swaps the source variable to `$_tok`
#   (the resolved TOKEN, "293") instead of `$_matches` (the roadmap line). Confirmed: the written
#   file then carries `only=293`, not `only=<the roadmap line's exact text>` — RS1's own claim,
#   broken directly rather than by proxy.
#
#   RS2 — now genuinely tests the "closing-paren rule" it was named for: targets the issue-number
#   match's own pattern, `(issue #$_tok)`, and drops the trailing paren. Confirmed: `--only 29`
#   then matches BOTH the `#29` and `#293` rows (the literal collision D3 exists to close), so the
#   fence reports `ambiguous` instead of resolving — RC flips from 0 to 1, exactly RS2's asserted
#   failure mode.
#
#   RS3 — targets the scope file's own path assignment, `_sf="$_root/.claude/autopilot-state/scope"`
#   (unique; the file's only other occurrence of that path is prose in the fence's own doc block, not
#   code), appending "3" to the written filename. Confirmed: the file lands at `…/scope3` and RS3's
#   check against the standard `…/scope` path finds nothing.
#
#   RS5 — now genuinely tests "ambiguous-match detection": targets the ambiguous branch's own row-dump
#   line, `sed -E 's/^- \[[ xX]\][[:space:]]*/    /'` (unique — this is the four-space-replacement
#   form; the `1)` branch's sibling sed strips to nothing, `//`, and is a different string), and
#   restricts it to `sed -n -E '1s/…/    /p'` — prints only the FIRST matched row. Confirmed: the
#   two-row collision fixture then names only 'AAAA' in the ambiguous message, and 'BBBB' — the
#   assertion's other required name — is gone.
#
#   RS6 — reuses RS1's sibling mechanism (the write, not the extraction): targets the write block's
#   own `only=` emitter, `sed 's/^/only=/'` (unique — Fence 1's SCOPE-PARSE line never runs this sed;
#   it interpolates `only=$_only` directly), uppercased to `sed 's/^/ONLY=/'`. Confirmed: the written
#   line reads `ONLY=<row>`, and RS6's lowercase `only=` check finds nothing.
#
#   RS7 — same technique on the sibling field: targets `echo "features=$_scope_features"` (unique —
#   Fence 1's own `features=` sits inside a different string, `"SCOPE-PARSE: OK source=$_source
#   features=$_features"`, not this one), uppercased. Confirmed: the written line reads
#   `FEATURES=2`, breaking RS7's `features=2` check.
#
#   RS9 — same disambiguation Section AR needed for AR9, on Fence 2's own sibling message: targets
#   "PROJECT.md not found -- the check DID-NOT-RUN" (Fence 2's no-PROJECT.md exit-3 message; distinct
#   from its own second DID-NOT-RUN site — the unreadable-file branch two lines below, which reads
#   "exists but is not readable" — and from AR9's Fence-1 message, which uses an em-dash and no "the
#   check"). Confirmed: RC stays 3 (untouched), the token becomes DID_NOT_RUN, RS9's grep goes red.
#
# RS8 was already planted and needed no change: `_dry_run` is a free variable this dispatch itself
# declares, and the `[ "$_dry_run" = "true" ]` guard inverted to `"false"` still matches exactly one
# site and still makes the write fire on RS8's own dry-run scenario.
#
# RS4's negative half NOW HAS A PLANT — the real early-abort shape exists (Task 7 landed) and it is
# an ADR-mandated value, not a guess: the branch that decides "no match" is
# `if [ -z "$_matches" ]; then _n=0; else …`, and inverting the assigned literal (`_n=0` → `_n=1`)
# reroutes an unresolvable token into the SINGLE-MATCH branch instead of aborting it. Confirmed
# against the real fence: `--only totally-unresolvable-token-xyz` then exits 0 (not 1), never names
# the token in output, and DOES write a scope file (with `source=`/`features=` and no `only=` line) —
# all three of RS4's ANDed conditions break at once. The needle is unique (Fence 2's only other
# `if [ -z "$_matches" ]; then` guards the SECOND, slug-fallback match attempt and reads `then` with
# no trailing assignment on the same line, so the two do not collide).
#
# plant: RS1 | plugin/skills/autopilot/SKILL.md | _title=$(printf '%s' "$_matches" | _title=$(printf '%s' "$_tok"
# plant: RS2 | plugin/skills/autopilot/SKILL.md | (issue #$_tok) | (issue #$_tok
# plant: RS3 | plugin/skills/autopilot/SKILL.md | _sf="$_root/.claude/autopilot-state/scope" | _sf="$_root/.claude/autopilot-state/scope3"
# plant: RS4 | plugin/skills/autopilot/SKILL.md | if [ -z "$_matches" ]; then _n=0; else | if [ -z "$_matches" ]; then _n=1; else
# The character class is `[ xX~]`, widened from `[ xX]` by RTF cycle 1's MINOR fix so a `- [~]`
# row is stripped like any other. This needle targets that exact line, so the widening orphaned it
# until it was updated here too — a production fix that changes text a plant points at silently
# demotes the plant to BADPLANT, and the harness stays green while it happens.
# plant: RS5 | plugin/skills/autopilot/SKILL.md | sed -E 's/^- \[[ xX~]\][[:space:]]*/    /' | sed -n -E '1s/^- \[[ xX~]\][[:space:]]*/    /p'
# plant: RS6 | plugin/skills/autopilot/SKILL.md | sed 's/^/only=/' | sed 's/^/ONLY=/'
# plant: RS7 | plugin/skills/autopilot/SKILL.md | echo "features=$_scope_features" | echo "FEATURES=$_scope_features"
# plant: RS9 | plugin/skills/autopilot/SKILL.md | PROJECT.md not found -- the check DID-NOT-RUN | PROJECT.md not found -- the check DID_NOT_RUN
# plant: RS8 | plugin/skills/autopilot/SKILL.md | "$_dry_run" = "true" | "$_dry_run" = "false"
# RS10's plant removes the roadmap-row filter itself, which is the whole mechanism #462 added. With
# it gone the fixture's table row derives the same slug as its roadmap row, the token matches two
# lines, and the fence takes its ambiguity branch — the exact failure observed on the live run.
# plant: RS10 | plugin/skills/autopilot/SKILL.md | '- ['*) : ;; | '- ['*) : ;; *) : ;;

RS_ROW1='Add a caching layer for query results  (issue #293)'
RS_ROW2='Improve structured logging output  (issue #29)'
RS_ROW3='A hand-written roadmap row with no issue marker'
RS_ROW4='Already delivered feature from last cycle  (issue #77)'
RS5_ROW_A='This is a very long duplicate roadmap feature title AAAA'
RS5_ROW_B='This is a very long duplicate roadmap feature title BBBB'
# Both computed with `tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; ...' | cut -c1-40`
# against the literals above, verified before writing this file (not guessed):
RS3_SLUG='a-hand-written-roadmap-row-with-no-issue'
RS5_SLUG='this-is-a-very-long-duplicate-roadmap-fe'

# mk_rs_root <name> — the shared four-row PROJECT.md fixture for RS1-RS4, RS6-RS8.
mk_rs_root() {
  _r="$TMPROOT/$1"
  mkdir -p "$_r/.claude"
  printf -- '- [ ] %s\n- [ ] %s\n- [ ] %s\n- [x] %s\n' \
    "$RS_ROW1" "$RS_ROW2" "$RS_ROW3" "$RS_ROW4" > "$_r/PROJECT.md"
  printf '%s' "$_r"
}

# mk_rs_dup_root <name> — RS5 only: two rows that slug-collide past the 40-char truncation.
mk_rs_dup_root() {
  _r="$TMPROOT/$1"
  mkdir -p "$_r/.claude"
  printf -- '- [ ] %s\n- [ ] %s\n' "$RS5_ROW_A" "$RS5_ROW_B" > "$_r/PROJECT.md"
  printf '%s' "$_r"
}

# setup_rs <root> <source> <features> <only> <dry_run> — binds the five free variables Fence 2
# declares, per this dispatch's own brief and ADR-0129 §D7/§D8.
setup_rs() {
  cat >"$TMPROOT/setup-rs.sh" <<SETUP_EOF
_root='$1'
_scope_source='$2'
_scope_features='$3'
_scope_only='$4'
_dry_run='$5'
SETUP_EOF
  printf '%s' "$TMPROOT/setup-rs.sh"
}

# RS1: an issue-number token resolves, and the scope file's only= line is the EXACT roadmap line
# text -- not a slug.
R=$(mk_rs_root rs1)
RC=$(run_fence "autopilot-scope-resolve" "$NA" "$(setup_rs "$R" "arguments" "1" "293" "false")")
OUT=$(out_of autopilot-scope-resolve)
SF="$R/.claude/autopilot-state/scope"
if [ "$RC" = "0" ] && [ -f "$SF" ] && grep -qF "only=$RS_ROW1" "$SF"; then
  ok "RS1: an issue-number token resolves to the exact roadmap line text, not a slug"
else
  bad "RS1: rc=$RC — $(printf '%s' "$OUT" | head -2)"
fi

# RS2: --only 29 does NOT resolve to the (issue #293) row -- the needle includes the closing
# parenthesis, closing the obvious prefix collision (ADR §D3).
R=$(mk_rs_root rs2)
RC=$(run_fence "autopilot-scope-resolve" "$NA" "$(setup_rs "$R" "arguments" "1" "29" "false")")
OUT=$(out_of autopilot-scope-resolve)
SF="$R/.claude/autopilot-state/scope"
if [ "$RC" = "0" ] && [ -f "$SF" ] && grep -qF "only=$RS_ROW2" "$SF" \
   && ! grep -qF '(issue #293)' "$SF"; then
  ok "RS2: --only 29 resolves to the #29 row and never the #293 row (closing-paren rule)"
else
  bad "RS2: rc=$RC — $(printf '%s' "$OUT" | head -2)"
fi

# RS3: a full topic-slug token resolves against the hand-written row (no issue marker).
R=$(mk_rs_root rs3)
RC=$(run_fence "autopilot-scope-resolve" "$NA" "$(setup_rs "$R" "arguments" "1" "$RS3_SLUG" "false")")
OUT=$(out_of autopilot-scope-resolve)
SF="$R/.claude/autopilot-state/scope"
if [ "$RC" = "0" ] && [ -f "$SF" ] && grep -qF "only=$RS_ROW3" "$SF"; then
  ok "RS3: a full topic-slug token resolves against the hand-written row"
else
  bad "RS3: rc=$RC — $(printf '%s' "$OUT" | head -2)"
fi

# RS4 (NEGATIVE half — see header): an unknown token -> exit 1, the message names the token, and
# no scope file is written.
R=$(mk_rs_root rs4)
RC=$(run_fence "autopilot-scope-resolve" "$NA" "$(setup_rs "$R" "arguments" "1" "totally-unresolvable-token-xyz" "false")")
OUT=$(out_of autopilot-scope-resolve)
SF="$R/.claude/autopilot-state/scope"
if [ "$RC" = "1" ] && printf '%s' "$OUT" | grep -qF 'totally-unresolvable-token-xyz' && [ ! -f "$SF" ]; then
  ok "RS4: an unknown token aborts (exit 1), names the token, and writes no scope file"
else
  bad "RS4: rc=$RC scope=$( [ -f "$SF" ] && echo present || echo absent ) — $(printf '%s' "$OUT" | head -2)"
fi

# RS5: a token matching two rows -> exit 1, naming the token and both rows. Fixture: two
# hand-written rows sharing an identical 40-char slug prefix (a real truncation collision).
R=$(mk_rs_dup_root rs5)
RC=$(run_fence "autopilot-scope-resolve" "$NA" "$(setup_rs "$R" "arguments" "1" "$RS5_SLUG" "false")")
OUT=$(out_of autopilot-scope-resolve)
SF="$R/.claude/autopilot-state/scope"
if [ "$RC" = "1" ] && printf '%s' "$OUT" | grep -qF "$RS5_SLUG" \
   && printf '%s' "$OUT" | grep -q 'AAAA' && printf '%s' "$OUT" | grep -q 'BBBB' \
   && [ ! -f "$SF" ]; then
  ok "RS5: a token matching two rows aborts (exit 1), naming the token and both rows"
else
  bad "RS5: rc=$RC — $(printf '%s' "$OUT" | head -3)"
fi

# RS6: a token naming a - [x] row resolves -- checkbox state is not part of resolution. Whether
# the run downstream delivers nothing for an already-checked row is not this fence's concern
# (the SPEC's own deliberate edge case); it resolves the token like any other.
R=$(mk_rs_root rs6)
RC=$(run_fence "autopilot-scope-resolve" "$NA" "$(setup_rs "$R" "arguments" "1" "77" "false")")
OUT=$(out_of autopilot-scope-resolve)
SF="$R/.claude/autopilot-state/scope"
if [ "$RC" = "0" ] && [ -f "$SF" ] && grep -qF "only=$RS_ROW4" "$SF"; then
  ok "RS6: a token naming a checked (- [x]) row resolves like any other row"
else
  bad "RS6: rc=$RC — $(printf '%s' "$OUT" | head -2)"
fi

# RS7: the written file carries source=, features= and one only= per resolved row, at
# <root>/.claude/autopilot-state/scope. ONLY_COUNT avoids the `grep -c ... || echo 0` two-line
# trap (issue #174) by reading grep -c's own "0" on no match instead of appending a second one.
R=$(mk_rs_root rs7)
RC=$(run_fence "autopilot-scope-resolve" "$NA" "$(setup_rs "$R" "arguments" "2" "293,29" "false")")
OUT=$(out_of autopilot-scope-resolve)
SF="$R/.claude/autopilot-state/scope"
ONLY_COUNT=$(grep -c '^only=' "$SF" 2>/dev/null)
if [ "$RC" = "0" ] && [ -f "$SF" ] && grep -qF 'source=arguments' "$SF" \
   && grep -qF 'features=2' "$SF" && [ "$ONLY_COUNT" = "2" ] \
   && grep -qF "only=$RS_ROW1" "$SF" && grep -qF "only=$RS_ROW2" "$SF"; then
  ok "RS7: the written file carries source=, features= and one only= per resolved row"
else
  bad "RS7: rc=$RC only_count=$ONLY_COUNT — $(printf '%s' "$OUT" | head -2)"
fi

# RS8 (NEGATIVE, planted — see header): _dry_run=true -> exit 0, the list and the source are
# printed, and no file exists afterward.
R=$(mk_rs_root rs8)
RC=$(run_fence "autopilot-scope-resolve" "$NA" "$(setup_rs "$R" "arguments" "1" "293" "true")")
OUT=$(out_of autopilot-scope-resolve)
SF="$R/.claude/autopilot-state/scope"
if [ "$RC" = "0" ] && printf '%s' "$OUT" | grep -qi 'arguments' \
   && printf '%s' "$OUT" | grep -qF "$RS_ROW1" && [ ! -f "$SF" ]; then
  ok "RS8: --dry-run prints the resolved list and source, and writes no scope file"
else
  bad "RS8: rc=$RC scope=$( [ -f "$SF" ] && echo present || echo absent ) — $(printf '%s' "$OUT" | head -2)"
fi

# RS9: no PROJECT.md -> exit 3 DID-NOT-RUN naming the file, distinct from RS4's exit 1. Reuses
# Section AR's own mk_ar_root (no PROJECT.md at all) rather than a third fixture builder.
R=$(mk_ar_root rs9)
RC=$(run_fence "autopilot-scope-resolve" "$NA" "$(setup_rs "$R" "arguments" "1" "293" "false")")
OUT=$(out_of autopilot-scope-resolve)
if [ "$RC" = "3" ] && printf '%s' "$OUT" | grep -q 'DID-NOT-RUN' && printf '%s' "$OUT" | grep -qF 'PROJECT.md'; then
  ok "RS9: no PROJECT.md -> exit 3 DID-NOT-RUN naming the file (distinct from RS4's exit 1)"
else
  bad "RS9: rc=$RC — $(printf '%s' "$OUT" | head -2)"
fi

# RS10 (issue #462): a NON-ROADMAP line cannot resolve a token. The slug loop read every line of
# PROJECT.md, and `cut -c1-40` then made a markdown table row collide with the roadmap row it
# documents — observed on a live autopilot run, 2026-08-17, where a documentation table made its
# own feature unschedulable by name. The fence's ambiguity refusal was correct; the population it
# searched was not (CLAUDE.md rule 18).
#
# The fixture is the real collision, not an approximation: the roadmap row's title is exactly 40
# characters once normalised, so the `(issue #7)` marker and the ` | 3.1 | ADR-003 |` columns both
# fall past the cut and the two lines derive the IDENTICAL slug. Verified against the fence's own
# derivation before writing this, the way RS3_SLUG/RS5_SLUG were.
#
# This asserts the ROADMAP-ROW FILTER and nothing else. The remaining #462 work — whether an
# indented row survives a `'- ['*` prefix match, and whether the issue-number path has the same
# exposure — is not covered here and is not claimed to be.
RS10_ROW='Kindle login with persistent web session  (issue #7)'
RS10_SLUG='kindle-login-with-persistent-web-session'
R="$TMPROOT/rs10"; mkdir -p "$R/.claude"
printf -- '- [ ] %s\n\n| Feature | Spec | ADR |\n| %s | 3.1 | ADR-003 |\n' \
  "$RS10_ROW" "Kindle login with persistent web session" > "$R/PROJECT.md"
RC=$(run_fence "autopilot-scope-resolve" "$NA" "$(setup_rs "$R" "arguments" "1" "$RS10_SLUG" "false")")
OUT=$(out_of autopilot-scope-resolve)
SF="$R/.claude/autopilot-state/scope"
if [ "$RC" = "0" ] && [ -f "$SF" ] && grep -qF "only=$RS10_ROW" "$SF"; then
  ok "RS10: a markdown table row documenting a feature cannot collide with its roadmap row (#462)"
else
  bad "RS10: rc=$RC — a non-roadmap line resolved a token, or the collision aborted the fence: $(printf '%s' "$OUT" | head -2)"
fi

# =====================================================================================
# CG. Task 8 (issue #365, ADR-0129 §D2/§D4/§D5, R-01/R-03/R-04): the conductor-scope-gate fence
# contract in project-conductor/SKILL.md Step 2, added IMMEDIATELY BEFORE the existing
# conductor-published-skip block (Task 8's own IMPL bullet: "an exhausted run ends regardless of
# which candidate is next, and both checks read the same ledger"). TEST ONLY -- the fence does not
# exist until the coder's IMPL sub-step (a separate, later batch) lands, so every CG case except CG9
# is RED via EXTRACT_FAILED right now, for the same reason Sections AR and RS are: run_fence's own
# contract on a missing `fence-contract: conductor-scope-gate -->` marker. CG9 is the one exception:
# it is a pure prose assertion on the Step 5 branch A `published`-append paragraph (Task 8's third
# IMPL bullet), not a fence extraction -- its RED reason is "the paragraph is not there yet", never
# EXTRACT_FAILED. Both RED reasons are verified in the run recorded in this feature's task note.
#
# Setup binds the fence's three free variables, exactly as this dispatch's own brief states: _root,
# _feature (the candidate roadmap line's exact text, no checkbox marker), _autopilot. CG1-CG7 reuse
# Section KB's mk_root (it already creates .claude/autopilot-state/ and a PROJECT.md carrying
# $FEATURE) rather than a fourth private root builder. CG8 needs two feature titles where one is a
# textual PREFIX of the other's line and does NOT need PROJECT.md to carry either -- ADR §D2 says
# the gate matches the scope file's only= list against $_feature with grep -qxF directly, never via
# PROJECT.md -- so mk_cg_prefix_root below builds a bare root instead.
#
# PLANTS, chosen against MEASURED occurrence counts in project-conductor/SKILL.md TODAY, not against
# a guess: bare `DID-NOT-RUN` already occurs 13 times across five existing fences (PUBLISHED-SKIP,
# FORK-POINT, SPEC-COPY x2, ENTRY-INIT, BRANCH-C), and bare `grep -qxF` already occurs twice (the
# PUBLISHED-SKIP code line plus its own explanatory prose). A needle must match EXACTLY ONE site
# (standing rule), so those bare tokens are unusable for CG7/CG8 even before the coder's IMPL adds a
# sixth fence using the same convention. The file's established idiom is `<PREFIX>: <TOKEN>`
# (`PUBLISHED-SKIP: ALREADY` occurs exactly once, its bare `ALREADY` twice — measured, not assumed)
# so CG1-CG5 and CG7 all plant the FULL prefixed compound (`SCOPE-GATE: <TOKEN>`), none of which has
# any occurrence in the file today (measured: zero `SCOPE-GATE` hits at all). NAMED RESIDUAL RISK,
# not hidden: `SPEC-COPY: DID-NOT-RUN` itself occurs TWICE, from two distinct exit points inside one
# fence -- so even a prefixed compound is not a guarantee if the coder's CG fence grows a second
# DID-NOT-RUN branch. If any of CG1-CG5/CG7's plants turns out to match more than one site once
# Task 8's IMPL lands, that is a defect in the plant (not the assertion) for Task 9's sweep to
# repair by narrowing further, per this task's own instruction ("any plant that does not fire is a
# defect in the plant or the assertion — fix the right one").
#
# TASK 9 SWEEP:
#
#   CG3/CG5 collided on exactly the class the residual-risk paragraph above named: the fence's own
#   IN-SCOPE branch fires in TWO places (the `only=` match, and the empty-only "every row is in
#   scope" fallback), so the prefixed compound `SCOPE-GATE: IN-SCOPE` still matched twice. Both
#   re-anchored on the FULL echoed sentence (`… — '$_feature' is in the only= list` for CG3, `… — no
#   only= list; every row is in scope` for CG5 — each unique). Confirmed against the real fence: CG3's
#   mutation (`IN-SCOPE` → `IN_SCOPE`) and CG5's (`IN-SCOPE` → `IN-RANGE`) each still exit 0 with the
#   matching scenario, but the printed token no longer contains the hyphenated `IN-SCOPE` substring
#   both assertions require.
#
#   CG8 matched its one intended site and STILL DID NOT FIRE — the more serious class this task's
#   own instruction distinguishes. Diagnosis, confirmed by extracting the real fence and running
#   CG8's exact fixture both ways: the operand mutation (`only=$_feature` → `ONLY=$_feature`) makes
#   `grep -qxF` search for a line that can never exist (the scope file always writes lowercase
#   `only=`), so it reports "no match" for EVERY feature, not only the genuine prefix collision CG8
#   exists to prove is excluded. CG8's own fixture is a case where the correct answer is ALSO "no
#   match" (the short title is a prefix of the long one, so an exact match correctly fails), so the
#   mutation and the real code produce the identical observable output — the assertion never
#   distinguished "matched correctly, excluded a genuine prefix" from "cannot match anything at all".
#   The fix is in the plant, not the assertion: re-anchored on the MATCH IDIOM itself,
#   `grep -qxF "only=$_feature"` (unique), dropping the `-x` flag. Confirmed: under the mutated
#   (non-exact) grep, the short title's line IS found as a substring of the long title's `only=` entry
#   — the fence now reports IN-SCOPE instead of OUT-OF-SCOPE, RC flips 1 → 0, and CG8 goes red for
#   the actual collision it is meant to catch.
#
#   CG6's two absences NOW HAVE A PLANT for one half (sufficient to redden the AND-chain): the
#   EXHAUSTED branch's own echo line, `echo "SCOPE-GATE: EXHAUSTED — $_delivered/$_features
#   delivered."` (unique), gains an appended `; touch "$_root/.claude/autopilot-state/skipped-features"`
#   on the same line — no newline, no ` | ` sequence. Confirmed against the real fence and fixture:
#   the file now exists afterward, breaking CG6's `[ ! -e … skipped-features ]` half directly (the
#   PROJECT.md-byte-unchanged half is left unexercised by this plant, which is why only one half is
#   claimed).
#
#   CG9 NOW HAS A PLANT: it is prose, but not without an anchor — the publish-site paragraph Task 8's
#   IMPL writes contains the literal phrase "second counter" (unique in the file), required by CG9's
#   own `grep -qi "second counter"` leg. Swapped for "another producer", which shares no substring
#   with any of CG9's three required phrases. Confirmed against the real file (built the flattened
#   copy exactly as CG9's own code does): "second counter" is gone, "delivered counter" and "optimis"
#   are untouched, and CG9's three-way AND goes false on the removed leg alone.
#
# plant: CG1 | plugin/skills/project-conductor/SKILL.md | SCOPE-GATE: INACTIVE | SCOPE-GATE: ACTIVE
# plant: CG2 | plugin/skills/project-conductor/SKILL.md | SCOPE-GATE: NONE | SCOPE-GATE: EMPTY
# plant: CG3 | plugin/skills/project-conductor/SKILL.md | SCOPE-GATE: IN-SCOPE — '$_feature' is in the only= list | SCOPE-GATE: IN_SCOPE — '$_feature' is in the only= list
# plant: CG4 | plugin/skills/project-conductor/SKILL.md | SCOPE-GATE: OUT-OF-SCOPE | SCOPE-GATE: OUT_OF_SCOPE
# plant: CG5 | plugin/skills/project-conductor/SKILL.md | SCOPE-GATE: IN-SCOPE — no only= list; every row is in scope | SCOPE-GATE: IN-RANGE — no only= list; every row is in scope
# plant: CG6 | plugin/skills/project-conductor/SKILL.md | echo "SCOPE-GATE: EXHAUSTED — $_delivered/$_features delivered." | echo "SCOPE-GATE: EXHAUSTED — $_delivered/$_features delivered."; touch "$_root/.claude/autopilot-state/skipped-features"
# plant: CG7 | plugin/skills/project-conductor/SKILL.md | SCOPE-GATE: DID-NOT-RUN | SCOPE-GATE: DID_NOT_RUN
# plant: CG8 | plugin/skills/project-conductor/SKILL.md | grep -qxF "only=$_feature" | grep -qF "only=$_feature"
# plant: CG9 | plugin/skills/project-conductor/SKILL.md | second counter | another producer

# setup_cg <root> <feature> <autopilot> -- binds the three free variables Task 8's own brief
# declares: _root, _feature, _autopilot.
setup_cg() {
  cat >"$TMPROOT/setup-cg.sh" <<SETUP_EOF
_root='$1'
_feature='$2'
_autopilot='$3'
SETUP_EOF
  printf '%s' "$TMPROOT/setup-cg.sh"
}

CG_OTHER_FEATURE='Another feature  (issue #77)'
CG_ROW_SHORT='Add caching'
CG_ROW_LONG='Add caching for query results'

# mk_cg_prefix_root <name> -- CG8 only: a bare root (no PROJECT.md row needed; ADR §D2's match is
# scope-file-vs-_feature only, never against PROJECT.md).
mk_cg_prefix_root() {
  _r="$TMPROOT/$1"
  mkdir -p "$_r/.claude/autopilot-state"
  printf '%s' "$_r"
}

# CG1: _autopilot=false -> exit 0, SCOPE-GATE: INACTIVE, byte-identical attended behaviour (the
# gate is a no-op outside autopilot, exactly as conductor-published-skip already is).
R=$(mk_root cg1)
RC=$(run_fence "conductor-scope-gate" "$PC" "$(setup_cg "$R" "$FEATURE" "false")")
OUT=$(out_of conductor-scope-gate)
if [ "$RC" = "0" ] && printf '%s' "$OUT" | grep -qF 'SCOPE-GATE: INACTIVE'; then
  ok "CG1: _autopilot=false -> exit 0, SCOPE-GATE: INACTIVE (byte-identical attended behaviour)"
else
  bad "CG1: rc=$RC — $(printf '%s' "$OUT" | head -2)"
fi

# CG2: no scope file -> exit 0, SCOPE-GATE: NONE. Distinct from CG7's unreadable-file exit 3.
R=$(mk_root cg2)
RC=$(run_fence "conductor-scope-gate" "$PC" "$(setup_cg "$R" "$FEATURE" "true")")
OUT=$(out_of conductor-scope-gate)
if [ "$RC" = "0" ] && printf '%s' "$OUT" | grep -qF 'SCOPE-GATE: NONE'; then
  ok "CG2: no scope file -> exit 0, SCOPE-GATE: NONE (distinct from an unreadable one)"
else
  bad "CG2: rc=$RC — $(printf '%s' "$OUT" | head -2)"
fi

# CG3: the candidate's exact line text is in the only= list -> exit 0, IN-SCOPE.
R=$(mk_root cg3)
printf 'source=arguments\nfeatures=2\nonly=%s\n' "$FEATURE" > "$R/.claude/autopilot-state/scope"
RC=$(run_fence "conductor-scope-gate" "$PC" "$(setup_cg "$R" "$FEATURE" "true")")
OUT=$(out_of conductor-scope-gate)
if [ "$RC" = "0" ] && printf '%s' "$OUT" | grep -qF 'IN-SCOPE'; then
  ok "CG3: the candidate's exact line text is in the only= list -> exit 0, IN-SCOPE"
else
  bad "CG3: rc=$RC — $(printf '%s' "$OUT" | head -2)"
fi

# CG4: it is not -> exit 1, OUT-OF-SCOPE; the caller advances to the next - [ ].
R=$(mk_root cg4)
printf 'source=arguments\nfeatures=2\nonly=%s\n' "$CG_OTHER_FEATURE" > "$R/.claude/autopilot-state/scope"
RC=$(run_fence "conductor-scope-gate" "$PC" "$(setup_cg "$R" "$FEATURE" "true")")
OUT=$(out_of conductor-scope-gate)
if [ "$RC" = "1" ] && printf '%s' "$OUT" | grep -qF 'OUT-OF-SCOPE'; then
  ok "CG4: not in the only= list -> exit 1, OUT-OF-SCOPE (caller advances to the next - [ ])"
else
  bad "CG4: rc=$RC — $(printf '%s' "$OUT" | head -2)"
fi

# CG5: an empty only= list with a features= cap -> IN-SCOPE (every row is in scope, never none).
R=$(mk_root cg5)
printf 'source=arguments\nfeatures=2\n' > "$R/.claude/autopilot-state/scope"
RC=$(run_fence "conductor-scope-gate" "$PC" "$(setup_cg "$R" "$FEATURE" "true")")
OUT=$(out_of conductor-scope-gate)
if [ "$RC" = "0" ] && printf '%s' "$OUT" | grep -qF 'IN-SCOPE'; then
  ok "CG5: an empty only= list with a features= cap -> IN-SCOPE (every row is in scope)"
else
  bad "CG5: rc=$RC — $(printf '%s' "$OUT" | head -2)"
fi

# CG6 (NEGATIVE, one half planted in Task 9 -- see header): published holds features= lines -> exit 2,
# EXHAUSTED, and PROJECT.md is byte-unchanged and no skipped-features file is created (R-04's whole
# content, asserted on the filesystem, not on a sentence).
R=$(mk_root cg6)
printf 'source=arguments\nfeatures=2\n' > "$R/.claude/autopilot-state/scope"
printf 'slot-one\nslot-two\n' > "$R/.claude/autopilot-state/published"
cp "$R/PROJECT.md" "$TMPROOT/cg6-project-before.md"
RC=$(run_fence "conductor-scope-gate" "$PC" "$(setup_cg "$R" "$FEATURE" "true")")
OUT=$(out_of conductor-scope-gate)
if [ "$RC" = "2" ] && printf '%s' "$OUT" | grep -qF 'EXHAUSTED' \
   && cmp -s "$TMPROOT/cg6-project-before.md" "$R/PROJECT.md" \
   && [ ! -e "$R/.claude/autopilot-state/skipped-features" ]; then
  ok "CG6: published holds features= lines -> exit 2, EXHAUSTED, PROJECT.md byte-unchanged, no skipped-features file (R-04)"
else
  bad "CG6: rc=$RC pmd_changed=$( cmp -s "$TMPROOT/cg6-project-before.md" "$R/PROJECT.md" && echo no || echo yes ) skipped=$( [ -e "$R/.claude/autopilot-state/skipped-features" ] && echo present || echo absent ) — $(printf '%s' "$OUT" | head -2)"
fi

# CG7: an unreadable scope file -> exit 3, DID-NOT-RUN. Skipped when the test user can read a
# chmod-000 file (CI often runs as root — ADR-0028's caveat), same posture as AR9/RS9.
R=$(mk_root cg7)
printf 'source=arguments\nfeatures=1\n' > "$R/.claude/autopilot-state/scope"
chmod 000 "$R/.claude/autopilot-state/scope" 2>/dev/null
if [ -r "$R/.claude/autopilot-state/scope" ]; then
  ok "CG7 (skipped, not asserted): this user can read a chmod-000 file, so the unreadable-scope-file state is not expressible here"
else
  RC=$(run_fence "conductor-scope-gate" "$PC" "$(setup_cg "$R" "$FEATURE" "true")")
  OUT=$(out_of conductor-scope-gate)
  if [ "$RC" = "3" ] && printf '%s' "$OUT" | grep -qF 'DID-NOT-RUN'; then
    ok "CG7: an unreadable scope file -> exit 3, DID-NOT-RUN"
  else
    bad "CG7: rc=$RC — $(printf '%s' "$OUT" | head -2)"
  fi
fi

# CG8: a feature title that is a prefix of another does not collide (grep -qxF, ADR §D2). only=
# holds the LONGER title's exact line; _feature is the SHORTER title (a textual prefix of it) --
# under a naive (non -x) grep this would falsely match, which is the collision D2 exists to close.
R=$(mk_cg_prefix_root cg8)
printf 'source=arguments\nfeatures=1\nonly=%s\n' "$CG_ROW_LONG" > "$R/.claude/autopilot-state/scope"
RC=$(run_fence "conductor-scope-gate" "$PC" "$(setup_cg "$R" "$CG_ROW_SHORT" "true")")
OUT=$(out_of conductor-scope-gate)
if [ "$RC" = "1" ] && printf '%s' "$OUT" | grep -qF 'OUT-OF-SCOPE'; then
  ok "CG8: a feature title that is a prefix of another does not collide (grep -qxF)"
else
  bad "CG8: rc=$RC — $(printf '%s' "$OUT" | head -2)"
fi

# CG9: the publish site (Step 5 branch A, at the published append) names its published append as
# the delivered counter Step 2's scope gate reads -- a behavioural-adjacent PROSE assertion, no
# fence, planted in Task 9 (see header). Not EXTRACT_FAILED -- checked against
# project-conductor/SKILL.md's flattened text directly.
PC_FLAT=$(tr '\n' ' ' < "$PC" | tr -s ' ' | tr -d '`*')
CG9_OK=1
printf '%s' "$PC_FLAT" | grep -qi "delivered counter" || CG9_OK=0
printf '%s' "$PC_FLAT" | grep -qi "second counter" || CG9_OK=0
printf '%s' "$PC_FLAT" | grep -qi "optimis" || CG9_OK=0
if [ "$CG9_OK" = "1" ]; then
  ok "CG9: the publish site names its published append as the delivered counter Step 2's scope gate reads"
else
  bad "CG9: the publish site does not yet name its published append as the delivered counter"
fi

# =====================================================================================
# RP. Task 9 (issue #365, ADR-0129 §D10): the report's additive `scope` block in autopilot/SKILL.md
# §4. TEST ONLY -- §4 does not carry the block yet. Measured against this tree before writing these
# checks (not assumed): neither `remaining_in_roadmap` nor `turns_per_feature` nor `published` nor
# `version bump` nor `at report time` nor `before the disarm` appears anywhere in the file, so all
# five assertions below are RED for the right reason -- the coder's IMPL sub-step (a later, separate
# batch within Task 9) has not run yet, exactly the state Section AR's header documents for AR1-AR9.
#
# Reuses NA_FLAT, the flattened/undecorated/case-insensitive copy of autopilot/SKILL.md the RB
# section above already built (one read per file, not re-derived -- ADR-0086's criterion). Nothing
# between here and there re-assigns it, and $NA is not touched by anything this file runs, so the
# snapshot is still valid.
#
# PLANTS -- declared here rather than in the top header, for the same reason Section AR's header
# states: this dispatch was told to disturb nothing above Section CG, and plant-check.sh's own
# extraction is `grep '^# plant:'` over the WHOLE file, column-anchored only and position-independent
# (ADR-0115's PC4) -- a plant declared here is exactly as valid as one declared at the top.
#
# Every RP plant targets text the coder's IMPL sub-step writes, so none of them were validable at
# declaration time -- the same deferred-validation state Section KB's header documents for
# KB1/KB4/KB5/KB6 and Section AR's for AR1-AR9. Task 9's own instruction governs the later sweep:
# "any plant that does not fire is a defect in the plant or the assertion -- fix the right one." All
# five needles target phrases ADR-0129 §D10 states close to verbatim -- the JSON field name
# `"remaining_in_roadmap"`, and the exact clauses "before the disarm"/"deletes both", "at report
# time", "never read by a gate", "version bump" -- the same confidence level RB2/RB3/TU1/TU3/TU4
# claim above for the identical reason: the coder cannot satisfy RP1-RP5 without also writing the
# needle. RP1's needle is the JSON key form (double-quoted, no backticks -- it targets the fenced
# code example, not an inline prose mention of the same field, which this file's convention would
# backtick-wrap instead and which the needle therefore will not collide with).
#
# TASK 9 SWEEP: all five needed no repair -- each still matches exactly one site against the real,
# landed §4 text, confirmed by static match-count against autopilot/SKILL.md before accepting it.
#
# plant: RP1 | plugin/skills/autopilot/SKILL.md | "remaining_in_roadmap" | "remaining_features"
# plant: RP2 | plugin/skills/autopilot/SKILL.md | before the disarm | after the disarm
# plant: RP3 | plugin/skills/autopilot/SKILL.md | at report time | at run start
# plant: RP4 | plugin/skills/autopilot/SKILL.md | never read by a gate | always read by a gate
# plant: RP5 | plugin/skills/autopilot/SKILL.md | version bump | version increment

# RP1: §4 documents an additive scope block with source, requested (features, only), delivered,
# remaining_in_roadmap and turns_per_feature (ADR-0129 §D10's JSON example).
RP1_OK=1
printf '%s' "$NA_FLAT" | grep -qi "scope"                || RP1_OK=0
printf '%s' "$NA_FLAT" | grep -qi "source"                || RP1_OK=0
printf '%s' "$NA_FLAT" | grep -qi "requested"              || RP1_OK=0
printf '%s' "$NA_FLAT" | grep -qi "delivered"               || RP1_OK=0
printf '%s' "$NA_FLAT" | grep -qi "remaining_in_roadmap"    || RP1_OK=0
printf '%s' "$NA_FLAT" | grep -qi "turns_per_feature"       || RP1_OK=0
if [ "$RP1_OK" = "1" ]; then
  ok "RP1: autopilot/SKILL.md §4 documents an additive scope block (source, requested, delivered, remaining_in_roadmap, turns_per_feature)"
else
  bad "RP1: autopilot/SKILL.md §4 does not yet document the scope block's fields"
fi

# RP2: it states that published and scope are read before the disarm, which deletes both.
RP2_OK=1
printf '%s' "$NA_FLAT" | grep -qi "published"               || RP2_OK=0
printf '%s' "$NA_FLAT" | grep -Eqi "before (the )?disarm"    || RP2_OK=0
printf '%s' "$NA_FLAT" | grep -qi "deletes both"              || RP2_OK=0
if [ "$RP2_OK" = "1" ]; then
  ok "RP2: autopilot/SKILL.md §4 states published and scope are read before the disarm, which deletes both"
else
  bad "RP2: autopilot/SKILL.md §4 does not yet state the read-before-disarm ordering"
fi

# RP3: remaining_in_roadmap is defined as the count of - [ ] rows at report time.
RP3_OK=1
printf '%s' "$NA_FLAT" | grep -qi "count of"        || RP3_OK=0
printf '%s' "$NA_FLAT" | grep -qi "at report time"   || RP3_OK=0
if [ "$RP3_OK" = "1" ]; then
  ok "RP3: autopilot/SKILL.md §4 defines remaining_in_roadmap as the count of - [ ] rows at report time"
else
  bad "RP3: autopilot/SKILL.md §4 does not yet define remaining_in_roadmap"
fi

# RP4: turns_per_feature is labelled an orchestrator self-report, derived by counting turns between
# AUTOPILOT-PUBLISH lines, and is stated never to be read by a gate.
RP4_OK=1
printf '%s' "$NA_FLAT" | grep -qi "self-report"          || RP4_OK=0
printf '%s' "$NA_FLAT" | grep -qi "AUTOPILOT-PUBLISH"     || RP4_OK=0
printf '%s' "$NA_FLAT" | grep -qi "never read by a gate"   || RP4_OK=0
if [ "$RP4_OK" = "1" ]; then
  ok "RP4: autopilot/SKILL.md §4 labels turns_per_feature an orchestrator self-report, never read by a gate"
else
  bad "RP4: autopilot/SKILL.md §4 does not yet label turns_per_feature a self-report (or does not state it is never read by a gate)"
fi

# RP5: no schema version bump is claimed -- the block is additive on v2.2.
RP5_OK=1
printf '%s' "$NA_FLAT" | grep -Eqi "no[^.]*version bump" || RP5_OK=0
printf '%s' "$NA_FLAT" | grep -qi "v2.2"                   || RP5_OK=0
if [ "$RP5_OK" = "1" ]; then
  ok "RP5: autopilot/SKILL.md §4 claims no schema version bump -- the block is additive on v2.2"
else
  bad "RP5: autopilot/SKILL.md §4 does not yet claim no version bump"
fi

# =====================================================================================
# ---------------------------------------------------------------------------------------------
# Section AV -- a scoping flag passed with NO VALUE (RTF cycle 1, MAJOR).
#
# Found by review, not by this file: `--features` with nothing after it set _has_scoping_arg=1
# (so the marker's scope: block was discarded) while leaving _cli_features empty, and the
# positive-integer guard is gated on `[ -n "$_features" ]`, so it never ran. The fence exited 0
# with `features=` empty, fence 2 wrote an empty features= line, and conductor-scope-gate's
# EXHAUSTED branch -- itself gated on `[ -n "$_features" ]` -- could never fire. A one-token
# operator typo silently produced an UNBOUNDED run, which is the exact thing this feature exists
# to prevent. Section AR tested `0` and `x` and never tested "absent".
#
# The ids are AV, not AR10: `plant-check.sh` attributes with `grep -q "^FAIL: $aid"`, a PREFIX
# match, so AR10 would be satisfied by AR1 failing (#355, open). No existing id starts with AV.
#
# All three plants target the MECHANISM (the guard condition, the flag-shaped-value arm), never
# the message text -- rule 12.
#
# AV1/AV2 target the `_seen_*=1` assignment, NOT the guard condition, and the reason is measured:
# inverting the guard (`-z` -> `-n`) makes it fire on a well-formed `--features 2`, so it takes out
# AR2/AR4/AR5/AR6 as well and attributes nothing. `_seen_features` is read by the empty-value guard
# and by nothing else, so zeroing it isolates the case. Verified by running each mutation.
#
# RETARGETED, all three (issue #385 dispatch, Batch 3 test-authoring pass). Task 5 moved the
# initialisers and the parse loop — where all three needles live — out of autopilot/SKILL.md's
# fence into scope-args-parse.sh (ADR-0132 §D2). Each needle now matches exactly once in the new
# script and zero times in SKILL.md, measured with grep before retargeting, not assumed.
# plant: AV1 | plugin/skills/autopilot/scripts/scope-args-parse.sh | _seen_features=1 | _seen_features=0
# plant: AV2 | plugin/skills/autopilot/scripts/scope-args-parse.sh | _seen_only=1 | _seen_only=0
# The needle below carries a BARE `|` with no surrounding spaces. That is correct and must not be
# "escaped": plant-check.sh splits fields on the regex ` \| ` (space-pipe-space), so only a pipe
# with spaces around it would collide. A `\|` here matches nothing in the source and silently
# demotes the plant to BADPLANT — which is exactly what the first draft of this line did.
# plant: AV3 | plugin/skills/autopilot/scripts/scope-args-parse.sh | ''|-*) _cli_features=""; shift ;; | '') _cli_features=""; shift ;;

# AV1: a bare `--features` (last token on the line) -> exit 2, message names the flag. Without
# this the run is unbounded and nothing says so.
R=$(mk_ar_root av1)
RC=$(run_fence "autopilot-scope-args" "$NA" "$(setup_ar "$R" "--features")")
OUT=$(out_of autopilot-scope-args)
if [ "$RC" = "2" ] && printf '%s' "$OUT" | grep -qi 'no value' \
   && printf '%s' "$OUT" | grep -q -- '--features'; then
  ok "AV1: a bare --features -> exit 2, message names the flag (not an unbounded run)"
else
  bad "AV1: rc=$RC — $(printf '%s' "$OUT" | head -2)"
fi

# AV2: the same for `--only`. It discards the marker's scope: block just as `--features` does, so
# a bare `--only` silently drops a bound the marker did carry.
R=$(mk_ar_root av2)
RC=$(run_fence "autopilot-scope-args" "$NA" "$(setup_ar "$R" "--only")")
OUT=$(out_of autopilot-scope-args)
if [ "$RC" = "2" ] && printf '%s' "$OUT" | grep -qi 'no value' \
   && printf '%s' "$OUT" | grep -q -- '--only'; then
  ok "AV2: a bare --only -> exit 2, message names the flag"
else
  bad "AV2: rc=$RC — $(printf '%s' "$OUT" | head -2)"
fi

# AV3: a flag where the VALUE should be (`--features --dry-run`) is a missing value, not a value
# of "--dry-run". Asserts the missing-value message specifically, NOT merely exit 2 -- without
# the `-*` arm the token is swallowed as a value and rejected by the positive-integer guard
# instead, which is also exit 2 and would let this assertion pass for the wrong reason.
R=$(mk_ar_root av3)
RC=$(run_fence "autopilot-scope-args" "$NA" "$(setup_ar "$R" "--features --dry-run")")
OUT=$(out_of autopilot-scope-args)
if [ "$RC" = "2" ] && printf '%s' "$OUT" | grep -qi 'no value'; then
  ok "AV3: --features followed by a flag is a missing value, not a value of '--dry-run'"
else
  bad "AV3: rc=$RC — $(printf '%s' "$OUT" | head -2)"
fi

# =====================================================================================
# SAP. Task 5 (issue #385, ADR-0132 §D2/§D4): scope-args-parse.sh, the initialisers and parse
# loop excised from Phase S's autopilot-scope-args fence (SKILL.md 112-151) — `_cli_features` …
# `_seen_only`, `set -- $_args`, the `while`/`case`. Everything below that (the marker branch, the
# positive-integer guard, the `SCOPE-PARSE:` line) STAYS in the fence — the narrow excision moves
# 4 plants instead of 12 (ADR-0132 §A3, measured). Six `key=value` lines:
# has_scoping_arg, seen_features, seen_only, cli_features, cli_only, dry_run — everything the
# marker branch, the positive-integer guard and the SCOPE-PARSE line need to finish the job.
#
# EXPECTED RED (tester dispatch, issue #385 Task 5). scope-args-parse.sh does not exist yet, so
# SAP1-SAP6 fail on a missing file (bash: …: No such file or directory, rc=127); SAP8/SAP9 fail
# because the fence still inlines the parser and never references the script at all — never
# because of a defect in this test file. NO PLANTS ARE DECLARED HERE — a separate tester pass
# declares them once the coder's implementation turns these green (ADR-0108/ADR-0115 PC4's own
# reasoning, applied to the caller side, and this dispatch's own instruction).
#
# PLANTS (issue #385 dispatch, Batch 3 test-authoring pass — coder's implementation is green now).
# Each targets the MECHANISM the assertion's own output check depends on, not the message text.
# SAP1/SAP3/SAP4/SAP5 target the six `printf 'key=%s\n' "$var"` output lines, one apiece — each
# appears exactly once, so hardcoding a wrong literal into one output line cannot be confused with
# any other. SAP2 targets the `--only` value-capture arm specifically, the one thing SAP2 checks
# that no sibling assertion also checks (both flags' VALUES captured together). SAP6 targets the
# default `*)` arm as a single \s+-joined needle spanning its three physical lines — verified to
# match exactly once before declaring, per this dispatch's own instruction.
# plant: SAP1 | plugin/skills/autopilot/scripts/scope-args-parse.sh | printf 'has_scoping_arg=%s\n' "$_has_scoping_arg" | printf 'has_scoping_arg=%s\n' "1"
# plant: SAP2 | plugin/skills/autopilot/scripts/scope-args-parse.sh | _cli_only="$2"; shift 2 | _cli_only=""; shift 2
# plant: SAP3 | plugin/skills/autopilot/scripts/scope-args-parse.sh | printf 'cli_features=%s\n' "$_cli_features" | printf 'cli_features=%s\n' "${_cli_features}X"
# plant: SAP4 | plugin/skills/autopilot/scripts/scope-args-parse.sh | printf 'dry_run=%s\n' "$_dry_run" | printf 'dry_run=%s\n' "false"
# plant: SAP5 | plugin/skills/autopilot/scripts/scope-args-parse.sh | printf 'seen_only=%s\n' "$_seen_only" | printf 'seen_only=%s\n' "1"
# plant: SAP6 | plugin/skills/autopilot/scripts/scope-args-parse.sh | *) shift ;; | *) _has_scoping_arg=1; shift ;;
#
# SAP7 mirrors MR9/CDA6's own PAIRS-entry technique (same dispatch, sibling file): both sides of
# the pipe-delimited entry renamed identically, so the exact literal SAP7 greps for no longer
# exists. SAP8 removes the DID-NOT-RUN token from the fence's own not-deployed message, the one
# thing SAP8's grep depends on that RC=3 alone does not prove. SAP9 quotes the argument string the
# fence hands to scope-args-parse.sh — exactly the regression SAP9's own negative assertion exists
# to catch, since a quoted "$_args" collapses every multi-token launch into one opaque word.
# plant: SAP7 | sync-to-claude.sh | plugin/skills/autopilot/scripts/scope-args-parse.sh|skills/autopilot/scripts/scope-args-parse.sh | plugin/skills/autopilot/scripts/scope-args-parse-RENAMED.sh|skills/autopilot/scripts/scope-args-parse-RENAMED.sh
# plant: SAP8 | plugin/skills/autopilot/SKILL.md | not deployed — DID-NOT-RUN, the arguments were not parsed | not deployed — the arguments were not parsed
# plant: SAP9 | plugin/skills/autopilot/SKILL.md | _sap_out=$(bash "$_sap" $_args) || { | _sap_out=$(bash "$_sap" "$_args") || {

SAP_SCRIPT="$SKILLS/autopilot/scripts/scope-args-parse.sh"

# SAP1: no arguments -> all six fields at their zero value, exit 0.
OUT=$(bash "$SAP_SCRIPT" 2>&1); RC=$?
if [ "$RC" = "0" ] && printf '%s\n' "$OUT" | grep -qxF 'has_scoping_arg=0' \
   && printf '%s\n' "$OUT" | grep -qxF 'seen_features=0' \
   && printf '%s\n' "$OUT" | grep -qxF 'seen_only=0' \
   && printf '%s\n' "$OUT" | grep -qxF 'cli_features=' \
   && printf '%s\n' "$OUT" | grep -qxF 'cli_only=' \
   && printf '%s\n' "$OUT" | grep -qxF 'dry_run=false'; then
  ok "SAP1: no arguments -> all six fields at their zero value, exit 0"
else
  bad "SAP1: rc=$RC — $(printf '%s' "$OUT" | head -2)"
fi

# SAP2: --features 2 --only 293,294 -> both flags seen and both values captured, exit 0.
OUT=$(bash "$SAP_SCRIPT" --features 2 --only 293,294 2>&1); RC=$?
if [ "$RC" = "0" ] && printf '%s\n' "$OUT" | grep -qxF 'has_scoping_arg=1' \
   && printf '%s\n' "$OUT" | grep -qxF 'seen_features=1' \
   && printf '%s\n' "$OUT" | grep -qxF 'seen_only=1' \
   && printf '%s\n' "$OUT" | grep -qxF 'cli_features=2' \
   && printf '%s\n' "$OUT" | grep -qxF 'cli_only=293,294' \
   && printf '%s\n' "$OUT" | grep -qxF 'dry_run=false'; then
  ok "SAP2: --features 2 --only 293,294 -> both flags seen, both values captured, exit 0"
else
  bad "SAP2: rc=$RC — $(printf '%s' "$OUT" | head -2)"
fi

# SAP3: a bare --features (last token on the line, nothing after it) -> seen but empty, never
# swallowed as a value (ADR-0129 A4, the AV1 case one layer down).
OUT=$(bash "$SAP_SCRIPT" --features 2>&1); RC=$?
if [ "$RC" = "0" ] && printf '%s\n' "$OUT" | grep -qxF 'has_scoping_arg=1' \
   && printf '%s\n' "$OUT" | grep -qxF 'seen_features=1' \
   && printf '%s\n' "$OUT" | grep -qxF 'cli_features=' \
   && printf '%s\n' "$OUT" | grep -qxF 'dry_run=false'; then
  ok "SAP3: a bare --features (last token) -> seen_features=1, cli_features= empty (not swallowed)"
else
  bad "SAP3: rc=$RC — $(printf '%s' "$OUT" | head -2)"
fi

# SAP4: --features followed by a flag (--dry-run) -> the flag is NOT swallowed as the value; it is
# processed on its own next iteration. Distinguishes "missing value" from "value consumed the next
# flag" — without the `-*` arm dry_run would stay false here, which is the AV3 shape one layer
# down (header there: "without the -* arm the token is swallowed as a value").
OUT=$(bash "$SAP_SCRIPT" --features --dry-run 2>&1); RC=$?
if [ "$RC" = "0" ] && printf '%s\n' "$OUT" | grep -qxF 'seen_features=1' \
   && printf '%s\n' "$OUT" | grep -qxF 'cli_features=' \
   && printf '%s\n' "$OUT" | grep -qxF 'dry_run=true'; then
  ok "SAP4: --features followed by a flag -> cli_features= empty AND the flag is still processed (dry_run=true)"
else
  bad "SAP4: rc=$RC — $(printf '%s' "$OUT" | head -2)"
fi

# SAP5: --dry-run alone -> only dry_run flips; the scoping fields stay at their zero value.
OUT=$(bash "$SAP_SCRIPT" --dry-run 2>&1); RC=$?
if [ "$RC" = "0" ] && printf '%s\n' "$OUT" | grep -qxF 'has_scoping_arg=0' \
   && printf '%s\n' "$OUT" | grep -qxF 'seen_features=0' \
   && printf '%s\n' "$OUT" | grep -qxF 'seen_only=0' \
   && printf '%s\n' "$OUT" | grep -qxF 'cli_features=' \
   && printf '%s\n' "$OUT" | grep -qxF 'cli_only=' \
   && printf '%s\n' "$OUT" | grep -qxF 'dry_run=true'; then
  ok "SAP5: --dry-run alone -> only dry_run flips, the scoping fields stay at zero"
else
  bad "SAP5: rc=$RC — $(printf '%s' "$OUT" | head -2)"
fi

# SAP6: an unrecognised flag is skipped -> exit 0, every field at its zero value (the `*) shift ;;`
# arm, never an error on an unknown token).
OUT=$(bash "$SAP_SCRIPT" --bogus 2>&1); RC=$?
if [ "$RC" = "0" ] && printf '%s\n' "$OUT" | grep -qxF 'has_scoping_arg=0' \
   && printf '%s\n' "$OUT" | grep -qxF 'seen_features=0' \
   && printf '%s\n' "$OUT" | grep -qxF 'seen_only=0' \
   && printf '%s\n' "$OUT" | grep -qxF 'dry_run=false'; then
  ok "SAP6: an unrecognised flag is silently skipped -> exit 0, every field at zero"
else
  bad "SAP6: rc=$RC — $(printf '%s' "$OUT" | head -2)"
fi

# SAP7 -- the PAIRS entry. pairs-completeness.test.sh cannot see a skill scripts/ file (its
# check_complete covers plugin/skills with */SKILL.md only -- ADR-0043), so this is the only guard
# (ADR-0109 MES0b / ADR-0069 PTB7 / MR9 precedent, same sibling file).
if grep -qF 'plugin/skills/autopilot/scripts/scope-args-parse.sh|skills/autopilot/scripts/scope-args-parse.sh' "$SYNC"; then
  ok "SAP7: the PAIRS entry for scope-args-parse.sh exists in sync-to-claude.sh"
else
  bad "SAP7: no PAIRS entry for scope-args-parse.sh in sync-to-claude.sh"
fi

# SAP8: the fence takes its documented exit-3 DID-NOT-RUN branch when scope-args-parse.sh is
# unresolvable, with the sync remedy printed (ADR-0132 §D4: "the code that fence already documents
# as 'the check DID NOT RUN'" — Phase S's own AR9 case, exit 3). Same renamed-path-substring
# technique as MR7/MR8/G5 in the sibling file: today the fence has no reference to the script at
# all, so the substitution matches nothing, the fence runs its CURRENT inline body unchanged, and
# this goes red for that reason — never a defect in this test.
R=$(mk_ar_root sap8)
_sap_body=$(extract_fence "$NA" "autopilot-scope-args")
_sap_broken=$(printf '%s\n' "$_sap_body" | sed 's|autopilot/scripts/scope-args-parse\.sh|autopilot/scripts/DOES-NOT-EXIST-scope-args-parse.sh|g')
{ cat "$(setup_ar "$R" "")"; printf '\n'; printf '%s\n' "$_sap_broken" | subst_paths; } > "$TMPROOT/sap8.sh"
bash "$TMPROOT/sap8.sh" >"$TMPROOT/out-sap8" 2>&1
RC=$?
if [ "$RC" = "3" ] && grep -q 'DID-NOT-RUN' "$TMPROOT/out-sap8" && grep -q 'sync-to-claude.sh --apply' "$TMPROOT/out-sap8"; then
  ok "SAP8: an unresolvable scope-args-parse.sh takes the exit-3 DID-NOT-RUN branch and prints the sync remedy"
else
  bad "SAP8: rc=$RC — $(head -2 "$TMPROOT/out-sap8" 2>/dev/null | tr '\n' ' ') — still inlines the parser, or does not yet resolve the helper two-tier"
fi

# SAP9: the fence invokes the resolved script with the argument string UNQUOTED, preserving
# today's `set -- $_args` word-split (ADR-0132 §D2, Task 5's own bullet 3) — both conditions
# together: the fence must NAME the script (never true today, since it still inlines the parser)
# and must never carry a QUOTED "$_args" anywhere (a quoted single argument would defeat the
# case/while match on --features/--only entirely, collapsing every multi-token invocation to one
# opaque word). Static, on the extracted fence body — not a re-run of AR2, which only exercises
# the property incidentally through the fence's end-to-end output.
_sap_body2=$(extract_fence "$NA" "autopilot-scope-args")
if printf '%s\n' "$_sap_body2" | grep -qF 'scope-args-parse.sh' \
   && printf '%s\n' "$_sap_body2" | grep -qF '$_args' \
   && ! printf '%s\n' "$_sap_body2" | grep -qF '"$_args"'; then
  ok "SAP9: the fence names scope-args-parse.sh and invokes it with the argument string unquoted, never quoted"
else
  bad "SAP9: the fence does not yet name scope-args-parse.sh, or quotes the argument string at the call site (the word-split would be lost)"
fi

# Z1 -- assertion-count floor (ADR-0083 §D3). NO PLANT: the floor's inversion is "an assertion block
# silently stops running", a multi-line structural deletion (a whole `if`/`ok`/`bad` triple gone),
# not a one-line needle->replacement content mutation -- said here rather than omitted silently, per
# this task's own instruction. The one precedent in this corpus that plants a Z1
# (worktree-isolation-contract.test.sh) does it by appending `PASS=$((PASS-N))` to an unrelated
# assertion's setup line -- forcing the counter down directly rather than genuinely removing an
# assertion, which tests the arithmetic rather than the vanishing-assertion class Z1 exists to catch.
# Every other Z1 floor already in this codebase (permission-mode-state, transition-pair-count,
# spec-pointer-archive, gate5-state-removal, and the rest of the corpus swept while writing this)
# carries no plant either; this one follows that norm.
#
# MARGIN, not equality (ADR-0083 §D3: "a floor, not an exact count"). Measured, not assumed: the
# total right before this check runs is 61 -- 43 pre-existing (Sections KB/RB/TU/AR/RS/CG) plus the
# five RP assertions, plus AV1-AV3, plus the nine SAP assertions just above (issue #385 Task 5),
# ALL of them counted toward PASS+FAIL regardless of their RED/GREEN colour, because `_z1_total`
# sums executed assertions, not passing ones -- a failing assertion still ran (the nine SAP cases
# are exactly that: expected-red today, still counted). Raised from the prior floor (50, itself one
# below a since-stale measured 48 -- corrected here rather than left, per the rule "grep the message
# strings whenever a literal in an assertion changes") to 60, one below the new measured total, per
# ADR-0124's own correction to a Z1-shaped floor (spec-pointer-archive's, raised 13->16 the same
# day): "left at 13 this floor would carry three units of slack and three assertions could vanish
# while it stayed green." A one-unit margin leaves no slack for a second assertion to vanish
# silently alongside a legitimate one-line edit, while staying a floor rather than an equality --
# Task 5's own coder sub-step edits SKILL.md prose and sync-to-claude.sh, not this test file, so it
# adds nothing to this count regardless.
_z1_total=$((PASS + FAIL))
if [ "$_z1_total" -ge 60 ]; then
  ok "Z1: assertion-count floor ($_z1_total >= 60)"
else
  bad "Z1: only $_z1_total assertions ran -- floor is 60; a section stopped running, not merely failing"
fi

echo "----"
echo "autopilot-run-scope.test.sh — PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
