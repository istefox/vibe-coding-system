#!/bin/bash
# stop-gate-path-predicate.test.sh — offline, hermetic, no $HOME dependency (see the fixture
# rig below: STOP_GATE_STATE_DIR and STOP_GATE_TRUST_FILE always redirect state; HOME is only
# ever overridden per-call, for SGP08, and never read otherwise). Bash 3.2 clean, `set -u`.
# Issue #404 / ADR-0137 / SPEC.md (topic slug 404-stop-gate-trigger-granularity).
#
# THE RULE THIS FILE ENFORCES: stop-gate.sh's `Stop`-event trigger is bound to a project-owned
# path-exclusion list (`.claude/test-ignore`, R-01/R-02/R-03/R-07/R-08) instead of firing on
# "anything was written this session" regardless of what. mark-dirty.sh records every written
# path instead of discarding it (R-06). Assertions here answer, for stop-gate.sh: given a
# recorded set of paths and an optional exclusion list, does the project's test command run?
#
# WRITTEN AGAINST THE PRE-FIX FILES, ON PURPOSE (Task 1 of the plan). At this checkpoint
# staging/plugin/scripts/stop-gate.sh has NO path predicate at all — it runs the test command
# unconditionally whenever the session marker exists, regardless of the marker's content — and
# staging/plugin/scripts/mark-dirty.sh truncates the marker on every write. Tasks 2 and 3 (a
# later, coder-owned batch per ADR-0101) make the assertions below pass; this file must not be
# edited to force them green early, and the RED output at this checkpoint is the deliverable,
# not a defect in the harness.
#
# WHAT IS ACTUALLY RED HERE, AND WHAT IS NOT (report this precisely, do not paper over it):
# every assertion whose expected outcome is the EXCLUDED direction (sentinel absent) is
# genuinely RED pre-fix, because the predicate that would produce that outcome does not exist
# yet: SGP01, SGP06, SGP07, SGP08, SGP09. Every assertion whose expected outcome is the ARMED
# direction (sentinel present) is a regression pin for behaviour R-02/R-03/R-06 require to stay
# exactly as it is TODAY, and today's unconditional "run whenever the marker exists" already
# produces that outcome by coincidence of having no predicate at all — so SGP02, SGP03, SGP04
# and SGP05 are already green pre-fix, and Task 3 must not regress them. SGP18 (injection) and
# SGPZ1 (the vacuity floor) are green at every checkpoint, including this one, for reasons
# stated at their own sites below.
#
# TASK 4 CHECKPOINT (R-09, R-10) — SGP10-SGP14 ADDED, WRITTEN AGAINST THE SAME PRE-FIX
# stop-gate.sh AS ABOVE. Expected RED, and the reason differs per assertion, not a blanket "the
# feature doesn't exist yet": SGP10 (absent ceiling file => 120 exactly) is pinned through a
# stub `timeout` binary that reports the value stop-gate.sh actually passed it — which is 120
# pre-fix TOO, because TMO already defaults to 120 today, so this one is a coincidence-green
# candidate exactly like SGP02-05 were in Task 1, reported as such rather than assumed RED.
# SGP11 (file overrides default; env overrides file) IS genuinely RED on its file-override
# half: pre-fix never reads .claude/test-timeout at all, so a file value of 5 is silently
# ignored and TMO stays 120. SGP12 (malformed/over-max values fall back to 120 AND say so on
# stderr) is RED on its stderr half: pre-fix emits no ceiling-related stderr line at all on the
# success path, even though the "TMO used is 120" half already holds by the same coincidence as
# SGP10 (the file is never read, so any file content is a no-op). SGP13 and SGP14 (R-10, the
# timeout counter) are genuinely RED: pre-fix increments <sid>.count only inside emit_block,
# which the 124/125/126/127 branch never reaches, so a timeout never increments anything and
# never disarms the marker at any cap — this is the exact defect ADR-0137 D5 names. SGP13 folds
# a negative direction (exit 127 must NOT increment) into the SAME id rather than claiming a new
# SGPnn: the plan's Task 4 lists that check as an unlabeled bullet directly under the
# SGP13/SGP14 pair, and the id population the plan declares ("SGP01…SGP18 plus SGPZ1") leaves no
# unclaimed number for it. That 127 half is already green pre-fix on its own (today's fail-open
# branch never increments anything for ANY of 124-127 either) — which is exactly why it must be
# ANDed into SGP13 rather than left unchecked: a Task 5 fix that increments on the WHOLE
# 124-127 branch, not just 124, would make SGP13's positive half true while still breaking the
# R-10 boundary this sub-check exists to catch.
#
# TASK 6 CHECKPOINT (R-11, R-12) - SGP15-SGP17 ADDED, 6a (tester-owned). 6b (coder, dispatched
# right after this checkpoint) creates .claude/test-ignore at the repository root; AT THIS
# CHECKPOINT IT DOES NOT EXIST YET. SGP16 (count guard on the DENOMINATOR: the tracked corpus is
# >= 300 entries AND the list holds >= 1 non-comment pattern) is expected RED for that reason -
# zero patterns, not a broken tracked-corpus derivation - whenever $REPO/.git is a real directory
# (a plain clone, or CI's actions/checkout; see the gate paragraph below for the checkpoint's own
# environment). SGP17 (three outcomes per pattern) is vacuously green with zero patterns to
# iterate: the empty-list case is SGP16's job to catch, not SGP17's (CLAUDE.md rule 7 - guard the
# denominator, not only the matches; a check that only validates the patterns present is blind by
# construction to the list being empty, rule 8's direction lesson).
#
# THE MECHANISM (ADR-0137 D7) - propose with a cheap `case`-based PREFILTER over a corpus, CONFIRM
# through the real hook. sgp_prefilter below only PROPOSES a candidate path; sgp_confirm asks the
# real staging/plugin/scripts/stop-gate.sh, through the Task 1 fixture rig, whether that candidate
# is actually excluded. Both SGP15 (a fully fixture-driven pair, plantable, hermetic) and
# SGP16/SGP17 (live, against this repository's real .claude/test-ignore) share these two
# functions - the same reason D7 gives for not extracting a second matcher into stop-gate.sh
# applies equally to not hand-rolling a second, independent harness copy of the "does this pattern
# match" question: the hook is the one authority, and the harness only proposes candidates for it
# to confirm or reject.
#
# THE CORPUS IS DERIVED, AND THE DERIVATION IS COUNT-GUARDED (CLAUDE.md rule 7): tracked paths
# from `git ls-files`, UNIONED with individually-listed ignored paths from
# `git status --porcelain --ignored=matching`. `--ignored=matching` IS REQUIRED and is not
# interchangeable with plain `--ignored`: the plain form collapses a WHOLLY-ignored directory
# (e.g. `.remember/`) into a single `!! .remember/` entry, and every file inside it - the one
# subject a pattern like `.remember/logs/` needs to have any chance of matching - is silently lost
# from the corpus. `=matching` lists every ignored file individually instead. The union matters
# because the day-one patterns (`.remember/logs/`, `*.bak`, `*.bak-*`) are themselves gitignored:
# their real subjects, when they exist, can only ever appear in the ignored half, never in
# `git ls-files` - a corpus built from tracked paths alone could never confirm any of them.
#
# SGP16 AND SGP17 ARE UNPLANTABLE BY CONSTRUCTION (recorded here per the plan, so Task 7 does not
# go looking for a plant that cannot exist): both read THIS repository's real .claude/test-ignore
# and its real git index, neither of which exists inside a plant-check.sh sandbox (a `cp -R` of
# staging/ and docs/ only - no .git, no repository-root .claude/). Their mechanism is pinned
# indirectly instead, through SGP15, which exercises the same sgp_prefilter/sgp_confirm functions
# against a fully fixture-driven corpus and pattern list - the precedent
# triage-state-gitignore.test.sh already set for live repository-root content (its T12/T15/T16 are
# likewise unplanted; only its differently-shaped T17 carries a `# plant:` line).
#
# THE GATE IS `[ -d "$REPO/.git" ]` - the SAME literal test claude-md-condensation.test.sh already
# uses (its CMD_PRESENT fallback, `elif [ -d "$REPO/.git" ]`) to tell a plant-check.sh sandbox
# apart from a real checkout. DISCLOSED HERE FOR A FUTURE READER, found while writing this file:
# in a git WORKTREE - this repository's own coder/tester dispatch mechanism, ADR-0068 - `.git` at
# the worktree root is a FILE holding a `gitdir:` pointer, not a directory, so this same gate reads
# a worktree as "not a real checkout" and SKIPs SGP16/SGP17 there too, even though git itself is
# fully functional in a worktree and both `git ls-files` and
# `git status --porcelain --ignored=matching` return correct, real data there (confirmed
# empirically against this exact worktree while writing this file - see the task note). So
# SGP16/SGP17 evaluate their live logic only in a plain clone or in CI; they SKIP, never FAIL or
# PASS, in both a plant-check.sh sandbox and every worktree-isolated dispatch - which, per
# ADR-0068, is the NORMAL execution environment for this very task, not a rare corner. This is a
# discovered gap in the literal `-d` gate, reported here rather than silently widened: a fix (e.g.
# `git rev-parse --git-dir`, which resolves the `gitdir:` indirection) is a mechanism change the
# plan did not specify, and deciding it is outside Task 6a's scope.
#
# TWO-DIGIT IDS FROM THE START, DELIBERATELY: plant-check.sh (ADR-0108) decides a plant fired
# with `grep -q "^FAIL: $aid"`, a PREFIX match — `SGP1` would be satisfied by `SGP10` failing.
# No `SGP1b`-style suffixes either, for the same reason: a suffixed id is still a prefix of
# nothing else's FAIL line only by luck, and luck is not the mechanism. Every assertion below
# emits `PASS: <id>` / `FAIL: <id>` WITH the colon, via ok()/bad(), so every id stays
# attributable to plant-check.sh once Task 7 declares plants against this file.
#
# DERIVED-GUARD INSTANCE NUMBER — RE-DERIVED FROM THE FILES, NOT COPIED FROM THE ADR. This file
# will be instance 16 of the derived-guard pattern (ADR-0086) once Task 6 adds the corpus
# derivation (SGP15-SGP17: tracked paths from `git ls-files` unioned with individually-listed
# ignored paths from `git status --porcelain --ignored=matching`, count-guarded). Task 1 itself
# derives no population at run time — it is plain hermetic fixtures — but the number is claimed
# here, now, so a concurrent plan re-deriving a free instance number by the same grep does not
# collide with this one before Task 6 lands. Evidence: grepped every literal `instance N` claim
# across `staging/plugin/scripts/tests/*.sh` headers on 2026-08-13. Found: 1
# (transcript-scan-rule.test.sh), 2 (fence-contract-coverage.test.sh), 3
# (cross-reference-form.test.sh), 4 (skill-coverage-perimeter.test.sh), 5
# (skill-text-corrections.test.sh), 6 (agent-command-scope.test.sh), 8 and 12 twice
# (manifest-field-state.test.sh, its own two sections), 9 (transition-producer.test.sh), 10
# twice — a COLLISION (concept-to-code-bsd-autopilot-gates.test.sh AND
# conductor-entry-failure-split.test.sh), 11 (concept-to-code-manifest-helpers-guards.test.sh),
# 14 (skill-fence-positional-tokens.test.sh), 15 (commit-transition-order.test.sh, whose own
# header already performed and recorded this exact grep as of its last edit, concluding 1-15
# are all accounted for — by marker or, for 7 and 13, by disclosed-but-unmarked consumption —
# and nothing above 15 exists). Re-running that same grep now, after the two commits that
# landed since (a CLAUDE.md condensation and a fix to claude-md-condensation.test.sh), finds no
# `instance 16` or higher anywhere in the tree, and neither touched a DERIVED-GUARD section.
# 16 is free. ADR-0137 independently also says 16; this is confirmed, not trusted on that
# say-so — the ADR's own text warns it has "collided twice and been silently unmarked twice
# more" before, which is exactly why this header re-derives rather than copies.
#
# --- plants (plant-check.sh, Task 7 / R-13) ---------------------------------------------------
# Each line below removes ONE mechanism and names the assertion that must go RED for it. Both
# directions R-13 requires: SGP01 is the EXCLUDED direction (an all-excluded session must not
# run), SGP02 is the NON-EXCLUDED direction (one unknown path must still arm) — neither alone is
# evidence, per the plan. SGP09 pins the R-08 absolute-pattern branch specifically, a narrower
# claim SGP01/SGP02 walk straight past. SGP12 pins the ceiling's maximum bound in isolation from
# its malformed-value half (SGP12's other four sub-cases are untouched by this mutation, since
# they are already caught by the digit/length checks one line above). SGP14 pins the timeout
# counter increment. SGP19 (R-06 gap closure, dispatched 2026-08-14) now carries the plant the
# plan's Task 7 originally assigned to SGP04 — see the dated CORRECTED note below this block for
# why it moved. SGP20 (also R-06 gap closure) pins the dedup guard separately: a different
# mechanism from SGP19's append, so per rule 2/ADR-0086 reasoning a plant on one is not evidence
# for the other. SGP15 is self-targeting: its own
# fixture corpus, neutralised to yield zero lines, must make its own assertion fail non-vacuously
# — the "count guard" is SGP15's own requirement that GOOD_CONFIRMED15 equal 1, not pass on an
# empty corpus.
#
# A REPLACEMENT CANNOT CONTAIN A NEWLINE (autopilot-guard-disarm.test.sh's O5 lesson, reproduced
# here for SGP01): a naive `>&2 exit 0` collapses onto one line and `exit 0` becomes two
# ARGUMENTS to echo, not a second statement — no exit happens and the assertion goes on passing
# while reading as fired. SGP01 and SGP02 both carry an explicit `;` before the no-op that
# replaces the neutralised statement, for exactly this reason.
# plant: SGP01 | plugin/scripts/stop-gate.sh | excluded by $IGN (matched:$WHY)" >&2 exit 0 | excluded by $IGN (matched:$WHY)" >&2; :
# plant: SGP02 | plugin/scripts/stop-gate.sh | else UNEXCLUDED=1; break fi | else :; fi
# plant: SGP09 | plugin/scripts/stop-gate.sh | case "$p" in $pat) hit="$pat"; break;; esac;; | case "$rel" in $pat) hit="$pat"; break;; esac;;
# plant: SGP12 | plugin/scripts/stop-gate.sh | { [ "$TMOV" -eq 0 ] || [ "$TMOV" -gt "$TMO_MAX" ]; } && TMO_BAD=1 | { [ "$TMOV" -eq 0 ]; } && TMO_BAD=1
# plant: SGP14 | plugin/scripts/stop-gate.sh | tcount=$((tcount + 1)) | tcount=$tcount
# plant: SGP19 | plugin/scripts/mark-dirty.sh | printf '%s\n' "$P" >> "$F" 2>/dev/null || true | printf '%s\n' "$P" >> /dev/null 2>/dev/null || true
# plant: SGP20 | plugin/scripts/mark-dirty.sh | grep -F -x -q -- "$P" "$F" 2>/dev/null || printf '%s\n' "$P" >> "$F" 2>/dev/null || true | printf '%s\n' "$P" >> "$F" 2>/dev/null || true
# plant: SGP15 | plugin/scripts/tests/stop-gate-path-predicate.test.sh | printf '%s\n' \ "docs/session-log.md" \ "src/app.py" \ "notes/readme.txt" \ > "$SGP15_CORPUS" | printf '' > "$SGP15_CORPUS"
#
# SGP04 DID NOT FIRE — recorded 2026-08-13, verified with plant-check.sh's own substitution
# mechanics before this line was written, not assumed. The plan's Task 7 assigns SGP04 to
# mark-dirty.sh's append (`printf '%s\n' "$P" >> "$F"`), but SGP04's assertion (above, R-02/R-06)
# never invokes mark-dirty.sh: it writes the marker's content directly through gate_run's own
# `printf '%s\n' "$RIG_PATHS" > "$RIG_DIRTY"`, bypassing the hook entirely, by design — the whole
# fixture rig only ever exercises stop-gate.sh's READ side of the marker contract. Neutralising
# mark-dirty.sh's append therefore changes nothing SGP04 can observe, and the plant is USABLE
# (target exists, needle matches exactly once, this harness emits `FAIL: <id>`) but does not, and
# structurally cannot, fire. **R-06's append mechanism — "mark-dirty.sh records every written
# path... discards none" — has no assertion anywhere in this file that invokes mark-dirty.sh at
# all.** The declaration above is kept rather than withdrawn: a plant that cannot fire is itself
# the finding CLAUDE.md rule 2 asks for, and withdrawing it to keep plant-check.sh green would be
# exactly the "fiddle with the needle until it goes green" move that same rule forbids. See the
# task report for the full statement of this gap and what closing it would require.
#
# CORRECTED 2026-08-14, RECORDED FORWARD RATHER THAN REWRITTEN IN PLACE (CLAUDE.md rule 14): the
# declaration two blocks above is now attributed to SGP19, not SGP04. This is NOT "tune the
# needle until it goes green" — rule 2 forbids exactly that, and it is not what happened. The
# mutation is byte-for-byte the one described in the paragraph above it and still neutralises
# mark-dirty.sh's append exactly as before; what changed is that a real subject for it now
# exists. SGP19-SGP24 (the R-06 GAP CLOSURE block below) drive the real mark-dirty.sh directly,
# closing the gap this paragraph documents, where SGP04 structurally could not and still cannot.
# Verified by hand, not assumed: in a scratch copy of mark-dirty.sh kept OUTSIDE this repository
# (never edited in place here — see the task report for the exact mutation and its location),
# applying this exact needle/replacement sends SGP19 to FAIL, and collaterally SGP20/SGP22/SGP23
# as well (all three also read content that this same neutralised append would have written),
# while SGP21 and SGP24 — which do not depend on any path actually reaching the file — stay
# green. SGP19 is the correct id to name here regardless of that collateral spread: it is the
# assertion whose own text is this exact bullet ("APPENDS and does not truncate... the exact
# defect Task 2 fixed"). SGP04 itself carries no plant declaration going forward; see the R-06
# GAP CLOSURE section below for which of SGP19-SGP24 are planted and which are not, and why.
# -------------------------------------------------------------------------------------------
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0; SKIP=0
ok()   { echo "PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
# skip() is a THIRD state (CLAUDE.md rule 4: "did not run" is not "found nothing"), used only by
# SGP16/SGP17 (Task 6) when $REPO/.git is not a real directory. Same precedent as
# claude-md-condensation.test.sh's identical skip()/SKIP pairing.
skip() { echo "SKIP: $1"; SKIP=$((SKIP+1)); }

# =====================================================================================
# THE FIXTURE RIG (built once here, reused unchanged by Tasks 4 and 6 per the plan's "The
# fixture rig" section). Two cooperating functions rather than one, because the caller needs
# to know the generated project root BEFORE it can write recorded paths that reference it.
#
# gate_new_proj: creates a throwaway `mktemp -d` project root with `.claude/test-cmd` set to a
# trivial, TOFU-approved command that touches a SENTINEL file, and resets every RIG_* input to
# its default ("no file", "no override"). Approval goes through approve-test-cmd.sh itself
# (the technique hook-hardening.test.sh already uses via STOP_GATE_TRUST_FILE) so the trust
# line is produced by the same hash + norm_path logic stop-gate.sh verifies against, not a
# hand-rolled duplicate that could quietly drift from it.
#
# gate_run: writes whatever the caller set (RIG_PATHS into the session marker, RIG_IGNORE into
# .claude/test-ignore if RIG_IGNORE_SET=1, RIG_TIMEOUT into .claude/test-timeout if non-empty),
# then pipes a synthetic Stop payload into the real staging/plugin/scripts/stop-gate.sh and
# records whether the sentinel now exists.
#
# SENTINEL PRESENT MEANS THE SUITE RAN. SENTINEL ABSENT MEANS IT DID NOT. That is a positive
# observation in each direction, not an inference from silence: the gate exits 0 on the
# excluded path AND on several unrelated fail-open paths (no jq, no sha256 tool, timeout,
# non-executable command), so the exit code alone cannot distinguish "excluded" from "declined
# for some other reason" — only the sentinel can.
#
# Inputs, via globals the caller sets AFTER gate_new_proj and BEFORE gate_run (bash 3.2 has no
# reliable pass-by-name for structured arguments, so plain globals are this codebase's existing
# idiom for fixture wiring — see hook-hardening.test.sh):
#   RIG_PATHS       newline-separated recorded paths for the session marker. "" means the
#                   marker exists but is truncated to zero bytes (holds no paths).
#   RIG_IGNORE_SET  set to 1 to write .claude/test-ignore at all (0 = no file, the default).
#   RIG_IGNORE      body of .claude/test-ignore when RIG_IGNORE_SET=1. "" writes an empty file.
#   RIG_TIMEOUT     body of .claude/test-timeout, or "" for "no file" (Task 4 uses this; Task 1
#                   never sets it, so the 120s default always applies here).
#   RIG_ENV         extra "NAME=value" tokens, space-separated, exported into the stop-gate.sh
#                   invocation only (Task 4's STOP_GATE_TEST_TIMEOUT / STOP_GATE_MAX_REENTRY).
#   RIG_HOME        if non-empty, HOME is overridden to this directory for the invocation only
#                   (SGP08's ~-pattern test). Left unset by every other assertion in this file —
#                   the rig never needs and never touches the real $HOME, because
#                   STOP_GATE_STATE_DIR and STOP_GATE_TRUST_FILE already redirect all state.
# Outputs, as globals: RIG_RC (stop-gate.sh's exit code), RIG_OUT (combined stdout+stderr),
# RIG_RAN (1 if the sentinel exists after the run, 0 otherwise), RIG_PROJ, RIG_SENTINEL,
# RIG_STATE, RIG_DIRTY, RIG_TRUST, RIG_SID.
# =====================================================================================
CASE_N=0

gate_new_proj() {
  CASE_N=$((CASE_N + 1))
  RIG_PROJ="$TMP/proj$CASE_N"
  mkdir -p "$RIG_PROJ/.claude"
  RIG_SENTINEL="$TMP/sentinel$CASE_N"
  rm -f "$RIG_SENTINEL"
  printf 'touch %s\n' "$(printf '%q' "$RIG_SENTINEL")" > "$RIG_PROJ/.claude/test-cmd"

  RIG_TRUST="$TMP/trust$CASE_N"
  STOP_GATE_TRUST_FILE="$RIG_TRUST" bash "$SCRIPTS/approve-test-cmd.sh" "$RIG_PROJ" >/dev/null 2>&1

  RIG_STATE="$TMP/state$CASE_N"
  mkdir -p "$RIG_STATE"
  RIG_SID="sgp$CASE_N"
  RIG_DIRTY="$RIG_STATE/$RIG_SID.dirty"

  RIG_PATHS=""
  RIG_IGNORE_SET=0
  RIG_IGNORE=""
  RIG_TIMEOUT=""
  RIG_ENV=""
  RIG_HOME=""
}

gate_run() {
  if [ "$RIG_IGNORE_SET" = "1" ]; then
    printf '%s' "$RIG_IGNORE" > "$RIG_PROJ/.claude/test-ignore"
  fi
  if [ -n "$RIG_TIMEOUT" ]; then
    printf '%s' "$RIG_TIMEOUT" > "$RIG_PROJ/.claude/test-timeout"
  fi
  if [ -n "$RIG_PATHS" ]; then
    printf '%s\n' "$RIG_PATHS" > "$RIG_DIRTY"
  else
    : > "$RIG_DIRTY"
  fi

  PAYLOAD=$(printf '{"session_id":"%s","cwd":"%s"}' "$RIG_SID" "$RIG_PROJ")

  if [ -n "$RIG_HOME" ]; then
    RIG_OUT=$(printf '%s' "$PAYLOAD" \
      | HOME="$RIG_HOME" STOP_GATE_STATE_DIR="$RIG_STATE" STOP_GATE_TRUST_FILE="$RIG_TRUST" \
        env $RIG_ENV bash "$SCRIPTS/stop-gate.sh" 2>&1)
  else
    RIG_OUT=$(printf '%s' "$PAYLOAD" \
      | STOP_GATE_STATE_DIR="$RIG_STATE" STOP_GATE_TRUST_FILE="$RIG_TRUST" \
        env $RIG_ENV bash "$SCRIPTS/stop-gate.sh" 2>&1)
  fi
  RIG_RC=$?

  RIG_RAN=0
  [ -f "$RIG_SENTINEL" ] && RIG_RAN=1
}

# =====================================================================================
# SGP01 (R-01) — every recorded path matches the exclusion list => sentinel ABSENT. The
# excluded direction: this is the one genuinely new capability the feature adds, and it is the
# clearest RED at this checkpoint, since pre-fix stop-gate.sh never declines on path grounds.
gate_new_proj
P="$RIG_PROJ"
RIG_PATHS="$P/docs/readme.md
$P/src/notes.md"
RIG_IGNORE_SET=1
RIG_IGNORE="*.md"
gate_run
if [ "$RIG_RAN" -eq 0 ]; then
  ok "SGP01"
else
  bad "SGP01 (every path matched *.md, expected sentinel absent, got RAN=$RIG_RAN rc=$RIG_RC out='$RIG_OUT')"
fi

# =====================================================================================
# SGP02 (R-03) — two recorded paths, one matching the list and one not => sentinel PRESENT.
# The list excludes, never includes; one unknown path is enough to arm. This direction already
# holds pre-fix (today's unconditional run), and must still hold post-fix.
gate_new_proj
P="$RIG_PROJ"
RIG_PATHS="$P/docs/readme.md
$P/src/app.py"
RIG_IGNORE_SET=1
RIG_IGNORE="*.md"
gate_run
if [ "$RIG_RAN" -eq 1 ]; then
  ok "SGP02"
else
  bad "SGP02 (app.py does not match *.md, expected sentinel present, got RAN=$RIG_RAN rc=$RIG_RC out='$RIG_OUT')"
fi

# =====================================================================================
# SGP03 (R-02) — no .claude/test-ignore at the root, one recorded path => sentinel PRESENT.
# The inert state is today's: with no list, the predicate branch must be a no-op.
gate_new_proj
RIG_PATHS="$RIG_PROJ/README.md"
gate_run
if [ "$RIG_RAN" -eq 1 ]; then
  ok "SGP03"
else
  bad "SGP03 (no test-ignore present, expected sentinel present, got RAN=$RIG_RAN rc=$RIG_RC out='$RIG_OUT')"
fi

# =====================================================================================
# SGP04 (R-02, R-06) — a marker that exists and holds NO paths => sentinel PRESENT, even with
# an exclusion list present that would (if it applied) exclude everything. Covers a session
# started under the old mark-dirty.sh (which truncates every write) and a payload with no
# file_path (which the new mark-dirty.sh also records as nothing). Both end states are the
# same empty marker, and stop-gate.sh's future logic must skip its whole predicate block when
# the marker holds no paths ([ -s ]) rather than trying to interpret "no paths" as "no writes".
gate_new_proj
RIG_PATHS=""
RIG_IGNORE_SET=1
RIG_IGNORE="*"
gate_run
if [ "$RIG_RAN" -eq 1 ]; then
  ok "SGP04"
else
  bad "SGP04 (empty marker with a list present, expected sentinel present, got RAN=$RIG_RAN rc=$RIG_RC out='$RIG_OUT')"
fi

# =====================================================================================
# SGP05 (R-07) — list grammar: blank lines and #-comment lines are skipped, including a
# comment whose TEXT would itself match if it were live. A list holding only such lines behaves
# exactly as no list => sentinel PRESENT.
gate_new_proj
RIG_PATHS="$RIG_PROJ/foo.md"
RIG_IGNORE_SET=1
RIG_IGNORE="# *.md

# another comment
"
gate_run
if [ "$RIG_RAN" -eq 1 ]; then
  ok "SGP05"
else
  bad "SGP05 (list holds only comments/blank lines including a would-match comment, expected sentinel present, got RAN=$RIG_RAN rc=$RIG_RC out='$RIG_OUT')"
fi

# =====================================================================================
# SGP06 (R-07) — a trailing-slash pattern matches a directory prefix and ONLY that prefix: a
# path under it is excluded (absent), a sibling directory whose name merely shares a string
# prefix is not (present). One assertion pair, both directions required.
gate_new_proj
RIG_IGNORE_SET=1
RIG_IGNORE="docs/books/"
RIG_PATHS="$RIG_PROJ/docs/books/one.md"
gate_run
UNDER_RAN=$RIG_RAN
UNDER_OUT=$RIG_OUT

gate_new_proj
RIG_IGNORE_SET=1
RIG_IGNORE="docs/books/"
RIG_PATHS="$RIG_PROJ/docs/booksxyz/one.md"
gate_run
SIBLING_RAN=$RIG_RAN
SIBLING_OUT=$RIG_OUT

if [ "$UNDER_RAN" -eq 0 ] && [ "$SIBLING_RAN" -eq 1 ]; then
  ok "SGP06"
else
  bad "SGP06 (under docs/books/ => want absent got RAN=$UNDER_RAN out='$UNDER_OUT'; sibling docs/booksxyz/ => want present got RAN=$SIBLING_RAN out='$SIBLING_OUT')"
fi

# =====================================================================================
# SGP07 (R-07) — patterns are matched against the path relative to the DISCOVERED ROOT: the
# same relative pattern excludes under root A (declared there) and does not accidentally
# exclude an identically-named path under a different root (where it was never declared). Each
# side is an independent project (independent .claude/test-cmd, independent state dir,
# independent trust file), so this also pins that the exclusion decision is read from the
# invocation's own root and not from some shared or cached state.
gate_new_proj
RIG_IGNORE_SET=1
RIG_IGNORE="notes.md"
RIG_PATHS="$RIG_PROJ/notes.md"
gate_run
ROOTA_RAN=$RIG_RAN
ROOTA_OUT=$RIG_OUT

gate_new_proj
RIG_PATHS="$RIG_PROJ/notes.md"
gate_run
ROOTB_RAN=$RIG_RAN
ROOTB_OUT=$RIG_OUT

if [ "$ROOTA_RAN" -eq 0 ] && [ "$ROOTB_RAN" -eq 1 ]; then
  ok "SGP07"
else
  bad "SGP07 (root A declares notes.md, want absent got RAN=$ROOTA_RAN out='$ROOTA_OUT'; root B declares nothing, want present got RAN=$ROOTB_RAN out='$ROOTB_OUT')"
fi

# =====================================================================================
# SGP08 (R-08) — a pattern beginning with / matches the ABSOLUTE recorded path (tested here
# against a path outside the discovered root, so no relative form could accidentally satisfy
# it), and a ~-rooted pattern is expanded against $HOME before that same absolute match. HOME
# is overridden to a fixture directory for this assertion only, and nowhere else in this file —
# the real $HOME is never read or written by any case here.
gate_new_proj
OUTSIDE="$TMP/outside-sgp08/data.txt"
RIG_PATHS="$OUTSIDE"
RIG_IGNORE_SET=1
RIG_IGNORE="$OUTSIDE"
gate_run
ABS_RAN=$RIG_RAN
ABS_OUT=$RIG_OUT

gate_new_proj
FIXHOME="$TMP/home-sgp08"
mkdir -p "$FIXHOME/dotfile"
RIG_HOME="$FIXHOME"
TARGET="$FIXHOME/dotfile/secret.txt"
RIG_PATHS="$TARGET"
RIG_IGNORE_SET=1
RIG_IGNORE="~/dotfile/secret.txt"
gate_run
TILDE_RAN=$RIG_RAN
TILDE_OUT=$RIG_OUT

if [ "$ABS_RAN" -eq 0 ] && [ "$TILDE_RAN" -eq 0 ]; then
  ok "SGP08"
else
  bad "SGP08 (absolute pattern on an outside-root path => want absent got RAN=$ABS_RAN out='$ABS_OUT'; ~-rooted pattern against fixture HOME => want absent got RAN=$TILDE_RAN out='$TILDE_OUT')"
fi

# =====================================================================================
# SGP09 (R-08) — a recorded path OUTSIDE the discovered root arms the gate (present) when only
# root-relative patterns are present — a root-relative pattern has nothing to match against,
# because the path has no relative form — and is excluded (absent) when an absolute pattern
# covers it. Both directions in one assertion pair; the arming half is the R-08 default this
# feature must not weaken (ADR-0055 §D2: the strict state wins when the gate does not know).
gate_new_proj
OUTSIDE1="$TMP/elsewhere1/file.md"
RIG_PATHS="$OUTSIDE1"
RIG_IGNORE_SET=1
RIG_IGNORE="*.md"
gate_run
RELONLY_RAN=$RIG_RAN
RELONLY_OUT=$RIG_OUT

gate_new_proj
OUTSIDE2="$TMP/elsewhere2/file.md"
RIG_PATHS="$OUTSIDE2"
RIG_IGNORE_SET=1
RIG_IGNORE="$OUTSIDE2"
gate_run
ABSCOVER_RAN=$RIG_RAN
ABSCOVER_OUT=$RIG_OUT

if [ "$RELONLY_RAN" -eq 1 ] && [ "$ABSCOVER_RAN" -eq 0 ]; then
  ok "SGP09"
else
  bad "SGP09 (outside root, only *.md declared => want present got RAN=$RELONLY_RAN out='$RELONLY_OUT'; outside root, absolute pattern covers it => want absent got RAN=$ABSCOVER_RAN out='$ABSCOVER_OUT')"
fi

# =====================================================================================
# TASK 4 HELPERS (R-09, R-10) — built ON TOP of gate_new_proj/gate_run, which stay exactly as
# Task 1 left them; neither function below is modified. Call order is always: gate_new_proj;
# [gate_set_cmd ...]; [gate_stub_timeout]; [more RIG_* customisation]; gate_run.
#
# gate_stub_timeout: stop-gate.sh's run_with_timeout() looks up `timeout` on $PATH. This
# installs a stub `timeout` ahead of whatever is really on $PATH (real timeout/gtimeout, or
# neither — the stub makes the choice irrelevant) that records its own first argument, the
# exact seconds value stop-gate.sh computed, into $STUB_TMO_LOG, then execs the real remainder
# of the command line unchanged so the wrapped test-cmd still runs normally. This is what lets
# SGP10-SGP12 pin the CEILING VALUE THE HOOK USES without ever waiting for a 120s (or 900s)
# ceiling to elapse.
gate_stub_timeout() {
  STUB_BIN="$TMP/stubbin$CASE_N"
  mkdir -p "$STUB_BIN"
  STUB_TMO_LOG="$TMP/stub-tmo-log$CASE_N"
  rm -f "$STUB_TMO_LOG"
  {
    printf '#!/bin/bash\n'
    printf 'printf %%s "$1" > %s\n' "$(printf '%q' "$STUB_TMO_LOG")"
    printf 'shift\n'
    printf 'exec "$@"\n'
  } > "$STUB_BIN/timeout"
  chmod +x "$STUB_BIN/timeout"
  RIG_ENV="PATH=$STUB_BIN:$PATH"
}

# gate_set_cmd: overwrites .claude/test-cmd with $1 and re-approves it through the SAME
# approve-test-cmd.sh + STOP_GATE_TRUST_FILE gate_new_proj already used — never a hand-rolled
# trust line — so a scenario needing a slow or nonexistent command still exercises the real TOFU
# check against content that matches its own trust entry.
gate_set_cmd() {
  printf '%s\n' "$1" > "$RIG_PROJ/.claude/test-cmd"
  STOP_GATE_TRUST_FILE="$RIG_TRUST" bash "$SCRIPTS/approve-test-cmd.sh" "$RIG_PROJ" >/dev/null 2>&1
}

# =====================================================================================
# SGP10 (R-09) — absent ceiling file => the timeout value stop-gate.sh actually uses is 120
# EXACTLY. Pinned through gate_stub_timeout's observable, never by timing a 120s sleep.
gate_new_proj
gate_stub_timeout
gate_run
GOT10=$(cat "$STUB_TMO_LOG" 2>/dev/null)
if [ "$GOT10" = "120" ]; then
  ok "SGP10"
else
  bad "SGP10 (no ceiling file, no env override — want timeout arg '120', got '$GOT10' rc=$RIG_RC out='$RIG_OUT')"
fi

# =====================================================================================
# SGP11 (R-09) — precedence, both directions in one pair: a valid .claude/test-timeout file
# overrides the 120s default, and STOP_GATE_TEST_TIMEOUT overrides the file when both are
# present. Same stub-timeout observable as SGP10.
gate_new_proj
gate_stub_timeout
RIG_TIMEOUT="5"
gate_run
FILE_GOT11=$(cat "$STUB_TMO_LOG" 2>/dev/null)

gate_new_proj
gate_stub_timeout
RIG_TIMEOUT="5"
RIG_ENV="$RIG_ENV STOP_GATE_TEST_TIMEOUT=42"
gate_run
ENV_GOT11=$(cat "$STUB_TMO_LOG" 2>/dev/null)

if [ "$FILE_GOT11" = "5" ] && [ "$ENV_GOT11" = "42" ]; then
  ok "SGP11"
else
  bad "SGP11 (file only => want '5' got '$FILE_GOT11'; file+env => want env '42' to win got '$ENV_GOT11')"
fi

# =====================================================================================
# SGP12 (R-09) — a malformed ceiling file value (empty, non-numeric, negative, zero) AND a
# value above the stated 900s maximum all fall back to 120 AND say so on stderr. Two halves per
# case, both required: the fallback (stub-timeout observable, as SGP10) and the report (a
# stderr line naming the value rejected and the value used — the empty case has no literal
# rejected-value text to search for, so only the "120" half is checked there).
sgp12_case() {  # $1 = case label; $2 = file value, "" meaning a file that EXISTS and is empty
  gate_new_proj
  if [ -z "$2" ]; then
    : > "$RIG_PROJ/.claude/test-timeout"
  else
    RIG_TIMEOUT="$2"
  fi
  gate_stub_timeout
  gate_run
  CASE_OK=1
  [ "$(cat "$STUB_TMO_LOG" 2>/dev/null)" = "120" ] || CASE_OK=0
  case "$RIG_OUT" in *120*) ;; *) CASE_OK=0;; esac
  if [ -n "$2" ]; then
    case "$RIG_OUT" in *"$2"*) ;; *) CASE_OK=0;; esac
  fi
  [ "$CASE_OK" -eq 1 ] || SGP12_FAILED="$SGP12_FAILED $1"
}
SGP12_FAILED=""
sgp12_case "empty" ""
sgp12_case "nonnumeric" "abc"
sgp12_case "negative" "-5"
sgp12_case "zero" "0"
sgp12_case "overmax" "5000"
if [ -z "$SGP12_FAILED" ]; then
  ok "SGP12"
else
  bad "SGP12 (failed sub-cases:$SGP12_FAILED)"
fi

# =====================================================================================
# SGP13 (R-10) — positive: a real timeout (exit 124, ceiling kept at 1s) increments
# <sid>.count by one, and below the cap the marker survives, as today. Negative, folded into
# this SAME id per the plan's own unlabeled bullet ("assert in the negative direction too") and
# the plan's closed id population (SGP01-SGP18 + SGPZ1 leaves no spare number for it): exit 127
# (command not found) keeps today's fail-open message and must NOT increment the counter.
# STOP_GATE_MAX_REENTRY is set well above 1 so the positive case cannot also trip SGP14's cap.
gate_new_proj
gate_set_cmd "sleep 3"
RIG_ENV="STOP_GATE_TEST_TIMEOUT=1 STOP_GATE_MAX_REENTRY=5"
gate_run
CNT124=$(cat "$RIG_STATE/$RIG_SID.count" 2>/dev/null || echo "")
MARKER124=0; [ -f "$RIG_DIRTY" ] && MARKER124=1

gate_new_proj
gate_set_cmd "this-command-does-not-exist-sgp13"
gate_run
CNTFILE127="$RIG_STATE/$RIG_SID.count"
CNT127_EXISTS=0; [ -f "$CNTFILE127" ] && CNT127_EXISTS=1
MSG127_OK=0
case "$RIG_OUT" in *"fail-open"*) MSG127_OK=1;; esac

if [ "$CNT124" = "1" ] && [ "$MARKER124" -eq 1 ] && [ "$CNT127_EXISTS" -eq 0 ] && [ "$MSG127_OK" -eq 1 ]; then
  ok "SGP13"
else
  bad "SGP13 (124: count='$CNT124' want '1', marker-survives=$MARKER124 want 1; 127: count-file-created=$CNT127_EXISTS want 0, fail-open-message=$MSG127_OK want 1, out='$RIG_OUT')"
fi

# =====================================================================================
# SGP14 (R-10) — at STOP_GATE_MAX_REENTRY consecutive timeouts the marker is REMOVED and a
# stderr line names the reason. Cap kept at 2, ceiling at 1s: two consecutive Stop invocations
# against the SAME session/state dir (gate_run called twice with no gate_new_proj between), the
# second one landing exactly on the cap. Costs about two seconds, not minutes. The reason text
# is checked for "disarm" (case-insensitive): the SPEC and ADR-0137 D5 both use exactly that
# word for this event ("the marker is disarmed", "naming the disarm and its reason"), so this
# is read from the design vocabulary, not guessed from an implementation that does not exist
# yet at this checkpoint.
gate_new_proj
gate_set_cmd "sleep 3"
RIG_ENV="STOP_GATE_TEST_TIMEOUT=1 STOP_GATE_MAX_REENTRY=2"
gate_run
FIRST_MARKER14=0; [ -f "$RIG_DIRTY" ] && FIRST_MARKER14=1
gate_run
SECOND_MARKER14=0; [ -f "$RIG_DIRTY" ] && SECOND_MARKER14=1
REASON_OK14=0
case "$RIG_OUT" in *[Dd]isarm*) REASON_OK14=1;; esac

if [ "$FIRST_MARKER14" -eq 1 ] && [ "$SECOND_MARKER14" -eq 0 ] && [ "$REASON_OK14" -eq 1 ]; then
  ok "SGP14"
else
  bad "SGP14 (after 1st timeout marker-present=$FIRST_MARKER14 want 1; after 2nd (at cap) marker-present=$SECOND_MARKER14 want 0; stderr names disarm=$REASON_OK14 want 1, out='$RIG_OUT')"
fi

# =====================================================================================
# TASK 6 (R-11, R-12) — the subject check that keeps this repository's exclusion list honest, and
# the count guard on its own derivation. See the header's TASK 6 CHECKPOINT paragraph for the full
# rationale, the gate discovery and the unplantable-by-construction disclosure.
STAGING=$(cd "$SCRIPTS/../.." && pwd)
REPO=$(cd "$STAGING/.." && pwd)
IGNFILE="$REPO/.claude/test-ignore"

# sgp_expand_pattern <raw-pattern> — the SAME expansion stop-gate.sh applies before matching
# (D2/D7): a trailing / gains a *, a leading ~ expands against $HOME. Cheap PREFILTER half only; a
# mismatch here in either direction is corrected by sgp_confirm below, never trusted alone.
sgp_expand_pattern() {
  _p="$1"
  case "$_p" in '~'*) _p="$HOME${_p#\~}";; esac
  case "$_p" in */) _p="${_p}*";; esac
  printf '%s' "$_p"
}

# sgp_prefilter <raw-pattern> <corpus-file> — proposes the FIRST corpus entry the (expanded)
# pattern matches, via bash's own `case`, into $SGP_CANDIDATE ("" and return 1 if none). A leading
# / matches the corpus entry's ABSOLUTE form ($REPO/<entry>); everything else matches the entry
# as-is (corpus entries are already root-relative — git ls-files/status emit them that way).
sgp_prefilter() {
  _pat=$(sgp_expand_pattern "$1")
  _corpus="$2"
  SGP_CANDIDATE=""
  case "$_pat" in
    /*)
      while IFS= read -r _c; do
        _abs="$REPO/$_c"
        case "$_abs" in $_pat) SGP_CANDIDATE="$_c"; return 0;; esac
      done < "$_corpus"
      ;;
    *)
      while IFS= read -r _c; do
        case "$_c" in $_pat) SGP_CANDIDATE="$_c"; return 0;; esac
      done < "$_corpus"
      ;;
  esac
  return 1
}

# sgp_confirm <raw-pattern> <candidate-relpath> — CONFIRMS a prefilter proposal through the REAL
# stop-gate.sh via the Task 1 fixture rig (gate_new_proj/gate_run): a fixture project whose marker
# holds only the candidate and whose .claude/test-ignore holds only this one pattern, exactly as
# written (not the expanded form) — the hook applies its own expansion. Sets SGP_CONFIRMED to 1
# (excluded — sentinel absent) or 0 (not excluded — the prefilter over-proposed and confirmation
# correctly rejects it, per D7: "a prefilter that over-proposes is rejected by the confirmation").
sgp_confirm() {
  gate_new_proj
  RIG_PATHS="$RIG_PROJ/$2"
  RIG_IGNORE_SET=1
  RIG_IGNORE="$1"
  gate_run
  if [ "$RIG_RAN" -eq 0 ]; then SGP_CONFIRMED=1; else SGP_CONFIRMED=0; fi
}

# =====================================================================================
# SGP15 (R-12) — FIXTURE PAIR, fully self-contained and hermetic: manufactures its OWN corpus, so
# it runs identically in a plant-check.sh sandbox (no real .git needed). One pattern WITH a
# subject in the fixture corpus; one deliberate typo with none. The good pattern must PROPOSE and
# CONFIRM; the typo must propose no candidate at all — the same "no subject" shape SGP17's FAIL
# branch reports live. THE PLANTED HALF OF THE MECHANISM (Task 7): a plant neutralising
# sgp_prefilter or sgp_confirm flips this assertion, because both are the exact functions
# SGP16/SGP17 depend on and cannot be planted directly (see the header).
SGP15_CORPUS="$TMP/sgp15-corpus"
printf '%s\n' \
  "docs/session-log.md" \
  "src/app.py" \
  "notes/readme.txt" \
  > "$SGP15_CORPUS"
GOOD_PAT15="docs/session-log.md"
TYPO_PAT15="docs/session-typo-nonexistent-xyz.md"

sgp_prefilter "$GOOD_PAT15" "$SGP15_CORPUS"
GOOD_CAND15="$SGP_CANDIDATE"
GOOD_CONFIRMED15=0
if [ -n "$GOOD_CAND15" ]; then
  sgp_confirm "$GOOD_PAT15" "$GOOD_CAND15"
  GOOD_CONFIRMED15=$SGP_CONFIRMED
fi

sgp_prefilter "$TYPO_PAT15" "$SGP15_CORPUS"
TYPO_CAND15="$SGP_CANDIDATE"

if [ "$GOOD_CONFIRMED15" -eq 1 ] && [ -z "$TYPO_CAND15" ]; then
  ok "SGP15"
else
  bad "SGP15 (good pattern '$GOOD_PAT15' confirmed=$GOOD_CONFIRMED15 candidate='$GOOD_CAND15' want confirmed=1; typo pattern '$TYPO_PAT15' candidate='$TYPO_CAND15' want empty — a typo must propose no subject)"
fi

# =====================================================================================
# SGP16/SGP17 (R-12) — LIVE, against this repository's real corpus and its real
# .claude/test-ignore. Gated on $REPO/.git being a real directory (see the header's TASK 6
# CHECKPOINT paragraph for exactly what that does and does not cover).
if [ -d "$REPO/.git" ]; then
  # THE DERIVATION, count-guarded on the denominator (CLAUDE.md rule 7). --ignored=matching is
  # REQUIRED: plain --ignored would collapse a wholly-ignored directory into one entry and lose
  # every file inside it — see the header.
  TRACKED_FILE="$TMP/sgp-live-tracked"
  ( cd "$REPO" && git ls-files 2>/dev/null ) > "$TRACKED_FILE"
  TRACKED_N=$(grep -c . "$TRACKED_FILE" 2>/dev/null || true); TRACKED_N=${TRACKED_N:-0}

  IGNORED_FILE="$TMP/sgp-live-ignored"
  ( cd "$REPO" && git status --porcelain --ignored=matching 2>/dev/null ) \
    | sed -n 's/^!! //p' > "$IGNORED_FILE"
  IGNORED_N=$(grep -c . "$IGNORED_FILE" 2>/dev/null || true); IGNORED_N=${IGNORED_N:-0}

  CORPUS="$TMP/sgp-live-corpus"
  cat "$TRACKED_FILE" "$IGNORED_FILE" > "$CORPUS"

  PAT_N=0
  if [ -f "$IGNFILE" ]; then
    PAT_N=$(grep -v '^[[:space:]]*#' "$IGNFILE" 2>/dev/null | grep -c '[^[:space:]]' || true)
    PAT_N=${PAT_N:-0}
  fi

  # SGP16 — count guard on the DENOMINATOR: a tracked corpus this small means the derivation
  # itself broke; zero non-comment patterns means an empty list would pass vacuously, which SGP17
  # alone (vacuously true over zero patterns) could never catch on its own.
  if [ "$TRACKED_N" -ge 300 ] && [ "$PAT_N" -ge 1 ]; then
    ok "SGP16 (tracked corpus $TRACKED_N entries, $IGNORED_N individually-listed ignored, $PAT_N non-comment pattern(s) in $IGNFILE)"
  else
    bad "SGP16 (tracked corpus $TRACKED_N entries, want >= 300; $PAT_N non-comment pattern(s) in $IGNFILE, want >= 1 — zero candidates on either side is a broken derivation, not coverage)"
  fi

  # SGP17 — THREE outcomes per pattern (CLAUDE.md rule 4): matches a corpus member => PASS;
  # matches nothing and a synthesised representative is NOT ignored by this repository's own
  # .gitignore => FAIL, loud in CI (the typo case); matches nothing and the representative IS
  # ignored => SKIP with a reason, because a fresh checkout cannot exhibit a runtime artefact.
  # Synthesis is MECHANICAL: a trailing / gains a literal component, every * becomes a literal
  # token — a WRONG synthesis produces the FAIL branch, never the PASS branch, because it never
  # gets near a prefilter match in the first place (the strict direction D6 requires).
  SGP17_FAIL=""; SGP17_SKIP=""; SGP17_PASS=""
  if [ "$PAT_N" -ge 1 ]; then
    while IFS= read -r PAT_RAW || [ -n "$PAT_RAW" ]; do
      PAT_LEAD=${PAT_RAW%%[! 	]*}; PAT=${PAT_RAW#"$PAT_LEAD"}
      case "$PAT" in ''|'#'*) continue;; esac

      sgp_prefilter "$PAT" "$CORPUS"
      if [ -n "$SGP_CANDIDATE" ]; then
        sgp_confirm "$PAT" "$SGP_CANDIDATE"
        if [ "$SGP_CONFIRMED" -eq 1 ]; then
          SGP17_PASS="$SGP17_PASS $PAT"
        else
          SGP17_FAIL="$SGP17_FAIL $PAT(prefilter proposed '$SGP_CANDIDATE' but stop-gate.sh did not exclude it)"
        fi
        continue
      fi

      REP="$PAT"
      case "$REP" in */) REP="${REP}sgp-representative-probe";; esac
      REP=$(printf '%s' "$REP" | sed 's/\*/sgp-representative-probe/g')
      if ( cd "$REPO" && git check-ignore -q -- "$REP" ) 2>/dev/null; then
        SGP17_SKIP="$SGP17_SKIP $PAT(no subject in this checkout; representative '$REP' is gitignored)"
      else
        SGP17_FAIL="$SGP17_FAIL $PAT(no subject, and representative '$REP' is NOT gitignored — looks like a typo)"
      fi
    done < "$IGNFILE"
  fi
  if [ -n "$SGP17_SKIP" ]; then
    echo "SGP17 detail — SKIP:$SGP17_SKIP"
  fi
  if [ -z "$SGP17_FAIL" ]; then
    ok "SGP17 (matched:${SGP17_PASS:- none}; skipped:${SGP17_SKIP:- none}; ${PAT_N} pattern(s) checked)"
  else
    bad "SGP17 (failing pattern(s):$SGP17_FAIL)"
  fi
else
  skip "SGP16 ($REPO/.git is not a directory — no real git checkout to query here; a plant-check.sh sandbox, or a git worktree where .git is a gitdir-pointer file, both read as 'cannot see the subject' rather than reporting a defect about it — see the header)"
  skip "SGP17 (same reason as SGP16 — see header)"
fi

# =====================================================================================
# SGP18 — INJECTION: a list containing a pattern whose text is a command substitution touching
# a canary must leave the canary absent. Verified at design time on bash 3.2.57 that a pattern
# held in a variable and matched via `case "$target" in $pat)` is NOT re-expanded; pinned here
# because a reviewer will ask and because the guarantee is load-bearing for reading a pattern
# out of a project file. GREEN at every checkpoint including this one: pre-fix stop-gate.sh
# does not read .claude/test-ignore at all, so the canary cannot fire either way yet, and
# post-fix it still cannot fire because of the guarantee above.
gate_new_proj
CANARY="$TMP/canary-sgp18"
rm -f "$CANARY"
RIG_PATHS="$RIG_PROJ/whatever.md"
RIG_IGNORE_SET=1
RIG_IGNORE='$(touch '"$CANARY"')'
gate_run
if [ ! -e "$CANARY" ]; then
  ok "SGP18"
else
  bad "SGP18 (canary fired — pattern text was executed: $CANARY exists)"
fi

# =====================================================================================
# R-06 GAP CLOSURE (SGP19-SGP24) — dispatched 2026-08-14, out of the plan's own Task
# numbering, closing a coverage hole found in review: SGP04's assertion (R-02/R-06, above)
# writes the marker's content directly through the fixture rig's own
# `printf '%s\n' "$RIG_PATHS" > "$RIG_DIRTY"` and never invokes mark-dirty.sh at all — the
# whole rig only ever exercises stop-gate.sh's READ side of the marker contract. Confirmed
# independently: run-hook-tests.sh is the only other file that invokes mark-dirty.sh, and it
# asserts only that the marker FILE EXISTS ([ -f ... ]), never its content. So R-06 — "records
# every written path, deduplicated, and discards none; a marker with no paths arms the gate" —
# had no assertion anywhere exercising the mechanism Task 2 rewrote. SGP19-SGP24 drive the REAL
# staging/plugin/scripts/mark-dirty.sh by piping a synthetic PostToolUse payload into it (the
# shape run-hook-tests.sh line 19 and mark-dirty.sh's own jq expressions use) against a fixture
# STOP_GATE_STATE_DIR, then inspect the resulting marker file's CONTENT. Each pins one distinct
# bullet of Task 2's spec — six separate ways the hook can be wrong, not one assertion covering
# all of them, because a single blended check could go green while any one bullet regresses
# alone.
#
# PLANT COVERAGE FOR THIS BLOCK, disclosed rather than implied: SGP19 (append/no-truncate) and
# SGP20 (dedup) each carry a `# plant:` declaration above (Task 7's block) — two DIFFERENT
# mechanisms in mark-dirty.sh, so one plant is not treated as evidence for the other, per
# rule 2/ADR-0086. SGP21 (empty/absent file_path still creates the marker), SGP22 (newline
# handling), SGP23 (the `grep -F -x -q --` leading-dash guard) and SGP24 (fail-open on no
# session_id / malformed JSON) carry NO `# plant:` declaration in this pass — this dispatch's
# scope was the mis-declared SGP04 plant and, at the dispatcher's discretion, a second plant for
# the dedup half; it did not extend to a full plant per new assertion. That is a real, disclosed
# gap, not "covered transitively" (they exercise code SGP19/SGP20's plants do not touch) — each
# was independently verified RED by hand in a scratch copy of mark-dirty.sh kept OUTSIDE this
# repository (never edited in place here; see the task report for all four mutations and their
# results), which is real evidence but is not the same guarantee an automated plant-check.sh
# declaration gives a future editor. A `# plant:` line for each is future work, not assumed done
# here.
#
# mdcall <state-dir> <payload-json> — the shared invocation: pipes $2 into the real
# mark-dirty.sh with STOP_GATE_STATE_DIR redirected to $1, discarding stdout/stderr (the hook
# is silent by contract) and returning its exit code. Never touches the real $HOME state.
mdcall() {
  printf '%s' "$2" | STOP_GATE_STATE_DIR="$1" bash "$SCRIPTS/mark-dirty.sh" >/dev/null 2>&1
  return $?
}

# SGP19 (R-06) — APPENDS and does not truncate: two writes of two DIFFERENT paths in the same
# session leave BOTH recorded. This is the exact defect Task 2 fixed (the old `: > "$F"`
# destroyed the whole record on every write) and it is the mechanism the mis-declared SGP04
# plant tried, and failed, to reintroduce — see the corrected declaration above.
MDSTATE19="$TMP/mdstate19"; mkdir -p "$MDSTATE19"
SID19="mdsgp19"
mdcall "$MDSTATE19" '{"session_id":"mdsgp19","tool_name":"Write","tool_input":{"file_path":"/a/one.txt"}}'
mdcall "$MDSTATE19" '{"session_id":"mdsgp19","tool_name":"Write","tool_input":{"file_path":"/b/two.txt"}}'
MARKER19="$MDSTATE19/$SID19.dirty"
HAS1_19=0; grep -F -x -q -- "/a/one.txt" "$MARKER19" 2>/dev/null && HAS1_19=1
HAS2_19=0; grep -F -x -q -- "/b/two.txt" "$MARKER19" 2>/dev/null && HAS2_19=1
if [ "$HAS1_19" -eq 1 ] && [ "$HAS2_19" -eq 1 ]; then
  ok "SGP19"
else
  bad "SGP19 (two different writes, want both recorded — got /a/one.txt=$HAS1_19 /b/two.txt=$HAS2_19, marker='$(cat "$MARKER19" 2>/dev/null)')"
fi

# SGP20 (R-06) — DEDUPLICATES: the same path written twice is recorded once, so a long session
# cannot grow the marker without bound. A different mechanism from SGP19's append (the grep -F
# -x -q guard, not the printf append), pinned with its own plant above per ADR-0086/rule-2
# reasoning: a plant on one is not evidence for the other.
MDSTATE20="$TMP/mdstate20"; mkdir -p "$MDSTATE20"
SID20="mdsgp20"
mdcall "$MDSTATE20" '{"session_id":"mdsgp20","tool_name":"Write","tool_input":{"file_path":"/dup/path.txt"}}'
mdcall "$MDSTATE20" '{"session_id":"mdsgp20","tool_name":"Write","tool_input":{"file_path":"/dup/path.txt"}}'
MARKER20="$MDSTATE20/$SID20.dirty"
LINES20=$(wc -l < "$MARKER20" 2>/dev/null | tr -d ' '); LINES20=${LINES20:-0}
CONTENT20=$(cat "$MARKER20" 2>/dev/null)
if [ "$LINES20" = "1" ] && [ "$CONTENT20" = "/dup/path.txt" ]; then
  ok "SGP20"
else
  bad "SGP20 (same path written twice, want exactly one line '/dup/path.txt' — got $LINES20 line(s), content='$CONTENT20')"
fi

# SGP21 (R-06) — an empty file_path, and an ABSENT file_path (no tool_input.file_path key at
# all), both record nothing but STILL CREATE the marker: existence keeps its old meaning, and a
# marker with no paths arms the gate (SGP04, above, pins the arming half through stop-gate.sh;
# this pins that mark-dirty.sh actually produces that empty-but-present marker in both source
# shapes).
MDSTATE21="$TMP/mdstate21"; mkdir -p "$MDSTATE21"
mdcall "$MDSTATE21" '{"session_id":"mdsgp21a","tool_name":"Write","tool_input":{"file_path":""}}'
MARKER21A="$MDSTATE21/mdsgp21a.dirty"
EXISTS21A=0; [ -f "$MARKER21A" ] && EXISTS21A=1
EMPTY21A=0; [ -f "$MARKER21A" ] && [ ! -s "$MARKER21A" ] && EMPTY21A=1

mdcall "$MDSTATE21" '{"session_id":"mdsgp21b","tool_name":"Write"}'
MARKER21B="$MDSTATE21/mdsgp21b.dirty"
EXISTS21B=0; [ -f "$MARKER21B" ] && EXISTS21B=1
EMPTY21B=0; [ -f "$MARKER21B" ] && [ ! -s "$MARKER21B" ] && EMPTY21B=1

if [ "$EXISTS21A" -eq 1 ] && [ "$EMPTY21A" -eq 1 ] && [ "$EXISTS21B" -eq 1 ] && [ "$EMPTY21B" -eq 1 ]; then
  ok "SGP21"
else
  bad "SGP21 (empty file_path: exists=$EXISTS21A want 1, empty=$EMPTY21A want 1; absent tool_input: exists=$EXISTS21B want 1, empty=$EMPTY21B want 1)"
fi

# SGP22 (R-06) — a path containing a NEWLINE is recorded on ONE line, with the newline replaced
# by a space and the whole record PREFIXED with a single space so it cannot begin with '/'
# (stop-gate.sh treats any line not beginning with '/' as unmatchable — the write still arms).
# Nothing is discarded. Built through jq -cn rather than hand-quoted JSON: a literal control
# character is not valid inside a JSON string, and jq is already a hard dependency of the hook
# under test, so using it here to produce a correctly \n-escaped payload is not a new external
# dependency, only a safer construction of the fixture.
MDSTATE22="$TMP/mdstate22"; mkdir -p "$MDSTATE22"
SID22="mdsgp22"
NLPATH22="/nl/one
two"
PAYLOAD22=$(jq -cn --arg sid "$SID22" --arg fp "$NLPATH22" '{session_id:$sid, tool_name:"Write", tool_input:{file_path:$fp}}')
mdcall "$MDSTATE22" "$PAYLOAD22"
MARKER22="$MDSTATE22/$SID22.dirty"
LINES22=$(wc -l < "$MARKER22" 2>/dev/null | tr -d ' '); LINES22=${LINES22:-0}
LINE22=$(sed -n '1p' "$MARKER22" 2>/dev/null)
STARTS_SLASH22=1
case "$LINE22" in /*) ;; *) STARTS_SLASH22=0;; esac
EXPECTED22=" /nl/one two"
if [ "$LINES22" = "1" ] && [ "$LINE22" = "$EXPECTED22" ] && [ "$STARTS_SLASH22" -eq 0 ]; then
  ok "SGP22"
else
  bad "SGP22 (newline path, want 1 line equal to '$EXPECTED22' not starting with / — got $LINES22 line(s), line='$LINE22')"
fi

# SGP23 (R-06) — a path BEGINNING WITH '-' is not read as a grep option (the `grep -F -x -q
# --` guard): it is recorded verbatim on its first write, and a second write of the SAME
# dash-leading path still dedups to one line rather than erroring or silently duplicating.
# Without `--`, "-oops.txt" fed to a bare `grep -F -x -q "$P" "$F"` would be parsed as options,
# not a pattern.
MDSTATE23="$TMP/mdstate23"; mkdir -p "$MDSTATE23"
SID23="mdsgp23"
DASHPATH23="-oops.txt"
PAYLOAD23=$(printf '{"session_id":"%s","tool_name":"Write","tool_input":{"file_path":"%s"}}' "$SID23" "$DASHPATH23")
mdcall "$MDSTATE23" "$PAYLOAD23"
mdcall "$MDSTATE23" "$PAYLOAD23"
MARKER23="$MDSTATE23/$SID23.dirty"
LINES23=$(wc -l < "$MARKER23" 2>/dev/null | tr -d ' '); LINES23=${LINES23:-0}
CONTENT23=$(cat "$MARKER23" 2>/dev/null)
if [ "$LINES23" = "1" ] && [ "$CONTENT23" = "$DASHPATH23" ]; then
  ok "SGP23"
else
  bad "SGP23 (dash-leading path written twice, want exactly one line '$DASHPATH23' — got $LINES23 line(s), content='$CONTENT23')"
fi

# SGP24 (R-06) — fail-open: a payload with no session_id, and a MALFORMED JSON payload, both
# exit 0 and record nothing (no marker file is created, since no session id was ever resolved
# to name one).
MDSTATE24="$TMP/mdstate24"; mkdir -p "$MDSTATE24"
mdcall "$MDSTATE24" '{"tool_name":"Write","tool_input":{"file_path":"/no/sid.txt"}}'
RC24A=$?
NOFILE24A=1
for f in "$MDSTATE24"/*.dirty; do [ -e "$f" ] && NOFILE24A=0; done

mdcall "$MDSTATE24" '{not valid json at all'
RC24B=$?

if [ "$RC24A" -eq 0 ] && [ "$NOFILE24A" -eq 1 ] && [ "$RC24B" -eq 0 ]; then
  ok "SGP24"
else
  bad "SGP24 (no session_id: rc=$RC24A want 0, marker-created=$((1-NOFILE24A)) want 0; malformed JSON: rc=$RC24B want 0)"
fi

# =====================================================================================
# SGPZ1 — VACUITY GUARD ONLY (ADR-0124: a floor absorbs its own plant, so this line pins
# nothing about any individual assertion — per-assertion pinning is Task 7's plants, not this
# line's job). This only guards against the whole file silently losing assertions, e.g. a
# syntax error that turns half the file into dead code while the script still exits 0. Raise
# FLOOR in the same edit whenever an assertion is added — Tasks 4 and 6 already do.
#
# SKIP IS COUNTED INTO THE TOTAL, same precedent as claude-md-condensation.test.sh's CMCZ1: SGP16
# and SGP17 land in the SKIP bucket rather than PASS/FAIL whenever $REPO/.git is not a real
# directory (a plant-check.sh sandbox, or a git worktree — see the header's TASK 6 CHECKPOINT
# paragraph), and without counting SKIP the floor would need slack that absorbs exactly the plant
# Task 7 cannot write for either of them. 25 assertions are declared in this file (SGP01-14,
# SGP15-17, SGP18, the R-06 GAP CLOSURE block's SGP19-24, SGPZ1); every one always lands in PASS,
# FAIL or SKIP, so FLOOR=24 keeps one point of slack, matching this file's own original ratio
# (18 of 19, raised 2026-08-14 from 18/19 when SGP19-SGP24 were added).
FLOOR=24
TOTAL=$((PASS + FAIL + SKIP))
if [ "$TOTAL" -ge "$FLOOR" ]; then
  ok "SGPZ1"
else
  bad "SGPZ1 (only $TOTAL assertions recorded, floor is $FLOOR)"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
[ "$FAIL" -gt 0 ] && exit 1 || exit 0
