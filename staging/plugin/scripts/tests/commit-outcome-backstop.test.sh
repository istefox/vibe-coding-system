#!/bin/bash
# commit-outcome-backstop.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash commit-outcome-backstop.test.sh
#
# ADR-0168 — docs/architecture/ADR-0168-commit-outcome-backstop-hook.md
# Plan — docs/superpowers/plans/2026-08-23-commit-outcome-backstop-hook.md, Task 1.
# SPEC.md R-01 (archived to docs/specs/ at completion). Assertion prefix CO, verified free across
# staging/ on 2026-08-23 (ADR-0168 §D10).
#
# TASK 1 ONLY (ADR-0101 rule 1 — an assertion must not sit in the same batch as the task it depends
# on). This file exercises `commit-outcome-check.sh`
# (staging/plugin/skills/concept-to-code/scripts/commit-outcome-check.sh), which Task 2 creates and
# does not exist yet. CO1-CO6 are RED here, by construction: `run_checker` below shells out to a
# script that is not on disk, `bash "$CHECKER" ...` fails with "No such file or directory" (bash
# exit 127), and that output matches none of the expected tokens/exit codes asserted below. A red
# assertion at this checkpoint is the deliverable, not a defect (plan's Batching table, Batch A/B —
# CO1-CO6 go green after Task 2).
#
# CO18 is a different kind of assertion — a denominator guard (rule 7) on THIS FILE'S OWN fixture
# derivation: did the search for a real manifest under docs/manifests/ that passes
# manifest-validate.sh find at least one candidate. It does not touch commit-outcome-check.sh at
# all, so unlike CO1-CO6 it is expected GREEN today; its purpose is to fail loudly if that search
# ever regresses to zero candidates, which would make CO1-CO5 vacuously RED for the wrong reason
# (zero matches and zero candidates look identical from outside).
#
# FIXTURES: a REAL manifest from docs/manifests/, patched via sed (project_root, current_step,
# status) — never a hand-written minimal one — so the quoting is the quoting manifest-init.sh
# actually writes. Real `git init` trees, real commits. Same technique
# commit-transition-order.test.sh already uses for its CTO12 fixtures (ADR-0078's lesson).
#
# --- plants (plant-check.sh, ADR-0149 grammar) ------------------------------------------------
# An assertion whose plant does not fire pins nothing (ADR-0108, rule 2). CO1-CO5 target
# commit-outcome-check.sh — a file that does not exist until Task 2, so these declarations name the
# exact line Task 2's verbatim move of the SKILL.md fence body will produce (source verified against
# the live c2c-step7-commit-outcome fence, 2026-08-23); plant-check.sh's Task 8 run is what actually
# fires them, once the file exists.
#
# plant: CO1 | plugin/skills/concept-to-code/scripts/commit-outcome-check.sh | if [ -z "$_gs" ]; then echo "COMMIT_OK"; exit 0; fi | if [ -n "$_gs" ]; then echo "COMMIT_OK"; exit 0; fi
# plant: CO2 | plugin/skills/concept-to-code/scripts/commit-outcome-check.sh | *)     echo "COMMIT_UNCOMMITTED modified";  exit 1 ;; | *)     echo "COMMIT_UNCOMMITTED untracked";  exit 1 ;;
# plant: CO3 | plugin/skills/concept-to-code/scripts/commit-outcome-check.sh | '??'*) echo "COMMIT_UNCOMMITTED untracked"; exit 1 ;; | '??'*) echo "COMMIT_UNCOMMITTED modified"; exit 1 ;;
# plant: CO4 | plugin/skills/concept-to-code/scripts/commit-outcome-check.sh | if [ "$_cs" != "completed" ]; then echo "COMMIT_NONTERMINAL current_step"; exit 1; fi | if [ "$_cs" = "completed" ]; then echo "COMMIT_NONTERMINAL current_step"; exit 1; fi
# plant: CO5 | plugin/skills/concept-to-code/scripts/commit-outcome-check.sh | [ -f "$_m" ] || { echo "COMMIT_OUTCOME_NORUN noManifest"; exit 3; } | [ -f "$_m" ] && { echo "COMMIT_OUTCOME_NORUN noManifest"; exit 3; }
#
# CO6 targets the PAIRS line itself (sync-to-claude.sh), once Task 2 adds it — a data line, not a
# comparison, so the plant corrupts the source-side path rather than inverting a condition.
#
# plant: CO6 | sync-to-claude.sh | plugin/skills/concept-to-code/scripts/commit-outcome-check.sh|skills/concept-to-code/scripts/commit-outcome-check.sh | plugin/skills/concept-to-code/scripts/commit-outcome-check-MISSING.sh|skills/concept-to-code/scripts/commit-outcome-check.sh
#
# CO18 self-targets: narrows this file's own base-manifest glob so nothing under docs/manifests/
# matches, so the search returns zero candidates instead of >=1 — proof the guard actually reads the
# search result and is not asserting a constant.
#
# plant: CO18 | plugin/scripts/tests/commit-outcome-backstop.test.sh | for _bm in "$REPO"/docs/manifests/*.manifest.yml; do | for _bm in "$REPO"/docs/manifests/NONEXISTENT-*.manifest.yml; do
#
# --- Task 5 plants (CO7-CO17; CO-CI has none, see the CO-CI section itself for why) ------------
#
# CO7/CO8 target the SKILL.md fence body, already rewritten by Task 4 and merged -- plantable and
# verifiable TODAY, unlike CO9-CO17 below. Both needles verified unique (grep -c == 1) against the
# live file, 2026-08-24.
#
# plant: CO7 | plugin/skills/concept-to-code/SKILL.md | bash "$_check" "<manifest-path>" | git -C "$(dirname "<manifest-path>")" status --porcelain -- "$(basename "<manifest-path>")"
# plant: CO8 | plugin/skills/concept-to-code/SKILL.md | _check="$CLAUDE_PLUGIN_ROOT/skills/concept-to-code/scripts/commit-outcome-check.sh" | _check="$CLAUDE_PLUGIN_ROOT/skills/concept-to-code/scripts/commit-outcome-check-WRONG.sh"
#
# CO9-CO17 target staging/plugin/scripts/commit-outcome-backstop.sh, which Task 6 creates. Unlike
# CO1-CO5 above (which extracted their needle from a LIVE fence), there is no file to verify these
# against yet -- each declaration names the exact line ADR-0168 predicts Task 6 will write: verbatim
# where §D7 gives literal text (CO9's grep pattern, CO12's -mtime -1), by the named
# precompact-guard.sh/SKILL.md-fence model otherwise (Task 6's own brief: "same header shape ...
# same log_audit helper ... same walk-up loop, same yval() field reader"). plant-check.sh's Task 8
# run is what actually confirms them; a NOFIRE there means the NEEDLE needs correcting to match what
# Task 6 actually wrote, never the plant's expected verdict (rule 2).
#
# plant: CO9 | plugin/scripts/commit-outcome-backstop.sh | grep -q '"skill"[[:space:]]*:[[:space:]]*"commit"' | grep -q '.'
# plant: CO10 | user/settings.json | "command": "\"$HOME\"/.claude/hooks/commit-outcome-backstop.sh" | "command": "\"$HOME\"/.claude/hooks/commit-outcome-backstop-DISABLED.sh"
# plant: CO11 | plugin/scripts/commit-outcome-backstop.sh | completed|step_7_commit|step_e4_commit|step_h5_commit) return 0 ;; | completed|step_e4_commit|step_h5_commit) return 0 ;;
# plant: CO12 | plugin/scripts/commit-outcome-backstop.sh | -name '*.manifest.yml' -mtime -1 | -name '*.manifest.yml' -mtime -36500
# plant: CO13 | plugin/scripts/commit-outcome-backstop.sh | completed|step_7_commit|step_e4_commit|step_h5_commit) return 0 ;; | *) return 0 ;;
# plant: CO14 | plugin/scripts/commit-outcome-backstop.sh | completed|step_7_commit|step_e4_commit|step_h5_commit) return 0 ;; | completed|step_7_commit) return 0 ;;
# plant: CO15 | plugin/scripts/commit-outcome-backstop.sh | command -v jq >/dev/null 2>&1 || | command -v jq >/dev/null 2>&1 &&
# plant: CO16 | plugin/scripts/commit-outcome-backstop.sh | "CLEAN" "no in-scope manifest | "CLEAN-BROKEN" "no in-scope manifest
# plant: CO17 | plugin/scripts/commit-outcome-backstop.sh | jq -r '.cwd // empty' | jq -r '.notcwd // empty'
#
# CO10 is a DATA plant against the staged REFERENCE copy of settings.json (Task 7 adds the entry),
# the same style CO6 above already uses against sync-to-claude.sh's PAIRS line.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
REPO=$(cd "$STAGING/.." && pwd)
CHECKER="$STAGING/plugin/skills/concept-to-code/scripts/commit-outcome-check.sh"
SYNC="$STAGING/sync-to-claude.sh"
MANIFEST_VALIDATE="$STAGING/plugin/skills/concept-to-code/scripts/manifest-validate.sh"

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# BASE_MANIFEST: a REAL manifest, patched — same loop, same reason, as
# commit-transition-order.test.sh's identical search (ADR-0078's lesson: a hand-written manifest
# would not carry the exact quoting a real reader of current_step/status has to parse).
# ---------------------------------------------------------------------------
BASE_MANIFEST=""; BASE_ROOT=""
for _bm in "$REPO"/docs/manifests/*.manifest.yml; do
  [ -f "$_bm" ] || continue
  if bash "$MANIFEST_VALIDATE" "$_bm" >/dev/null 2>&1; then
    BASE_MANIFEST="$_bm"
    BASE_ROOT=$(grep '^project_root:' "$_bm" | sed -e 's/^project_root:[[:space:]]*"//' -e 's/"[[:space:]]*$//')
    break
  fi
done
mkdir -p "$TMP/proj"

# mk_manifest <dest> <current_step> <status> — sed-level patch, quoting preserved.
mk_manifest() {
  [ -n "$BASE_MANIFEST" ] || return 1
  sed -e "s|$BASE_ROOT|$TMP/proj|g" \
      -e "s|^current_step:.*|current_step: \"$2\"|" \
      -e "s|^status:.*|status: \"$3\"|" "$BASE_MANIFEST" >"$1"
}

git_setup() {
  mkdir -p "$1"
  git -C "$1" init -q >/dev/null 2>&1
  git -C "$1" config user.email "test@example.com"
  git -C "$1" config user.name "Test"
  git -C "$1" config commit.gpgsign false
}

# run_checker <manifest-path> — the ONLY way CO1-CO5 talk to the file under test. Writes stdout to
# $TMP/co-out, exit code to $TMP/co-rc. stderr is captured for diagnostics only, never matched
# against.
run_checker() {
  bash "$CHECKER" "$1" >"$TMP/co-out" 2>"$TMP/co-err"
  echo "$?" >"$TMP/co-rc"
}

# ===========================================================================
# CO1 (R-01) — terminal, committed, clean -> stdout COMMIT_OK, exit 0.
# ===========================================================================
if [ -n "$BASE_MANIFEST" ]; then
  FXA="$TMP/fxA"; git_setup "$FXA"
  mk_manifest "$FXA/manifest.yml" completed completed
  git -C "$FXA" add manifest.yml >/dev/null 2>&1
  git -C "$FXA" commit -q -m init >/dev/null 2>&1
  run_checker "$FXA/manifest.yml"
  _rc=$(cat "$TMP/co-rc"); _out=$(cat "$TMP/co-out")
  if [ "$_out" = "COMMIT_OK" ] && [ "$_rc" -eq 0 ]; then
    ok "CO1 (R-01) terminal/committed/clean -> COMMIT_OK, exit 0"
  else
    bad "CO1 (R-01) terminal/committed/clean: expected 'COMMIT_OK' exit 0, got '$_out' exit $_rc"
  fi
else
  bad "CO1 (R-01) no base manifest available — see CO18"
fi

# ===========================================================================
# CO2 (R-01) — terminal, tracked and modified after the commit -> COMMIT_UNCOMMITTED modified, exit
# 1. Exact qualifier, not a prefix (the plan's own bullet).
# ===========================================================================
if [ -n "$BASE_MANIFEST" ]; then
  FXB="$TMP/fxB"; git_setup "$FXB"
  mk_manifest "$FXB/manifest.yml" completed completed
  git -C "$FXB" add manifest.yml >/dev/null 2>&1
  git -C "$FXB" commit -q -m init >/dev/null 2>&1
  printf '\n# touched after commit\n' >>"$FXB/manifest.yml"
  run_checker "$FXB/manifest.yml"
  _rc=$(cat "$TMP/co-rc"); _out=$(cat "$TMP/co-out")
  if [ "$_out" = "COMMIT_UNCOMMITTED modified" ] && [ "$_rc" -eq 1 ]; then
    ok "CO2 (R-01) terminal/tracked-modified -> COMMIT_UNCOMMITTED modified, exit 1"
  else
    bad "CO2 (R-01) terminal/tracked-modified: expected 'COMMIT_UNCOMMITTED modified' exit 1, got '$_out' exit $_rc"
  fi
else
  bad "CO2 (R-01) no base manifest available — see CO18"
fi

# ===========================================================================
# CO3 (R-01) — terminal, never added -> COMMIT_UNCOMMITTED untracked, exit 1. Exact qualifier.
# ===========================================================================
if [ -n "$BASE_MANIFEST" ]; then
  FXC="$TMP/fxC"; git_setup "$FXC"
  mk_manifest "$FXC/manifest.yml" completed completed
  run_checker "$FXC/manifest.yml"
  _rc=$(cat "$TMP/co-rc"); _out=$(cat "$TMP/co-out")
  if [ "$_out" = "COMMIT_UNCOMMITTED untracked" ] && [ "$_rc" -eq 1 ]; then
    ok "CO3 (R-01) terminal/untracked -> COMMIT_UNCOMMITTED untracked, exit 1"
  else
    bad "CO3 (R-01) terminal/untracked: expected 'COMMIT_UNCOMMITTED untracked' exit 1, got '$_out' exit $_rc"
  fi
else
  bad "CO3 (R-01) no base manifest available — see CO18"
fi

# ===========================================================================
# CO4 (R-01) — current_step: step_7_commit, status: in_progress, committed and clean ->
# COMMIT_NONTERMINAL current_step, exit 1. Both fields are non-terminal; the checker's own check
# order (current_step read before status, per the live fence) is what makes "current_step" the
# exact, not merely the possible, qualifier here.
# ===========================================================================
if [ -n "$BASE_MANIFEST" ]; then
  FXD="$TMP/fxD"; git_setup "$FXD"
  mk_manifest "$FXD/manifest.yml" step_7_commit in_progress
  git -C "$FXD" add manifest.yml >/dev/null 2>&1
  git -C "$FXD" commit -q -m init >/dev/null 2>&1
  run_checker "$FXD/manifest.yml"
  _rc=$(cat "$TMP/co-rc"); _out=$(cat "$TMP/co-out")
  if [ "$_out" = "COMMIT_NONTERMINAL current_step" ] && [ "$_rc" -eq 1 ]; then
    ok "CO4 (R-01) current_step=step_7_commit/status=in_progress, committed/clean -> COMMIT_NONTERMINAL current_step, exit 1"
  else
    bad "CO4 (R-01) expected 'COMMIT_NONTERMINAL current_step' exit 1, got '$_out' exit $_rc"
  fi
else
  bad "CO4 (R-01) no base manifest available — see CO18"
fi

# ===========================================================================
# CO5 (R-01) — manifest outside any git repository -> COMMIT_OUTCOME_NORUN, exit 3; AND a path that
# does not exist -> COMMIT_OUTCOME_NORUN noManifest, exit 3. Two sub-cases joined by the plan's own
# bullet into one assertion.
# ===========================================================================
CO5_FAIL=""
if [ -n "$BASE_MANIFEST" ]; then
  FXE="$TMP/fxE"; mkdir -p "$FXE"
  mk_manifest "$FXE/manifest.yml" completed completed
  if git -C "$FXE" rev-parse --show-toplevel >/dev/null 2>&1; then
    CO5_FAIL="$CO5_FAIL
  fixture invalid: $FXE is unexpectedly inside a git repository, cannot exercise the no-repo path"
  else
    run_checker "$FXE/manifest.yml"
    _rc=$(cat "$TMP/co-rc"); _out=$(cat "$TMP/co-out")
    case "$_out" in
      "COMMIT_OUTCOME_NORUN"*) [ "$_rc" -eq 3 ] || CO5_FAIL="$CO5_FAIL
  outside-repo case: exit=$_rc (expected 3), out=$_out" ;;
      *) CO5_FAIL="$CO5_FAIL
  outside-repo case: expected 'COMMIT_OUTCOME_NORUN', got: $_out (exit $_rc)" ;;
    esac
  fi

  run_checker "$TMP/does-not-exist/manifest.yml"
  _rc=$(cat "$TMP/co-rc"); _out=$(cat "$TMP/co-out")
  if [ "$_out" = "COMMIT_OUTCOME_NORUN noManifest" ] && [ "$_rc" -eq 3 ]; then
    :
  else
    CO5_FAIL="$CO5_FAIL
  nonexistent-path case: expected 'COMMIT_OUTCOME_NORUN noManifest' exit 3, got '$_out' exit $_rc"
  fi
else
  CO5_FAIL="
  no base manifest available — see CO18"
fi

if [ -z "$CO5_FAIL" ]; then
  ok "CO5 (R-01) outside-git -> COMMIT_OUTCOME_NORUN exit 3; nonexistent path -> COMMIT_OUTCOME_NORUN noManifest exit 3"
else
  bad "CO5 (R-01) failed:$CO5_FAIL"
fi

# ===========================================================================
# CO6 (R-01) — sync-to-claude.sh's PAIRS block carries the commit-outcome-check.sh entry. Without it
# the script never reaches ~/.claude and both callers (SKILL.md Step 7.1, the backstop hook) resolve
# nothing on a real machine — pairs-completeness.test.sh does not require it (skills are vendored
# selectively), so nothing else would catch this (ADR-0168 §D1).
# ===========================================================================
CO6_NEEDLE='plugin/skills/concept-to-code/scripts/commit-outcome-check.sh|skills/concept-to-code/scripts/commit-outcome-check.sh'
if grep -qxF "$CO6_NEEDLE" "$SYNC"; then
  ok "CO6 (R-01) sync-to-claude.sh PAIRS carries the commit-outcome-check.sh entry"
else
  bad "CO6 (R-01) sync-to-claude.sh PAIRS is missing the entry: $CO6_NEEDLE"
fi

# ===========================================================================
# CO18 (rule 7) — denominator guard: the base-manifest search above found at least one manifest
# passing manifest-validate.sh. Zero candidates and zero failures are indistinguishable from
# outside, and CO1-CO5 derive every fixture from that one file — a search that silently returns
# nothing would make CO1-CO5 vacuously RED for the wrong reason. Expected GREEN today: unlike
# CO1-CO6 this does not depend on commit-outcome-check.sh existing at all.
# ===========================================================================
if [ -n "$BASE_MANIFEST" ]; then
  ok "CO18 base-manifest search found a candidate passing manifest-validate.sh ($BASE_MANIFEST)"
else
  bad "CO18 base-manifest search found ZERO candidates under docs/manifests/ passing manifest-validate.sh — CO1-CO5 have nothing to build fixtures from"
fi

# ===========================================================================
# TASK 5 — sections CO7-CO17, CO-CI, COZ1 (ADR-0168, plan Task 5). All RED until Task 6/7 land,
# EXCEPT CO7/CO8 (the SKILL.md fence, already rewritten by Task 4 and merged), which are GREEN
# today. HOOK below does not exist until Task 6 -- run_hook() shells out to it exactly the way
# run_checker() above shells out to commit-outcome-check.sh, so CO9-CO17 fail with "No such file or
# directory" (bash exit 127) until then. That is the deliverable at this checkpoint (Batch C in the
# plan's own table), not a defect.
#
# STDIN-PIPING CONVENTION, same as every other hook harness here (precompact-occupancy.test.sh's
# run_guard(), COMMIT_OUTCOME_BACKSTOP_DIR/CLAUDE_PLUGIN_ROOT playing PRECOMPACT_GUARD_DIR's role): a
# synthetic PostToolUse JSON payload piped on stdin, state dir and plugin root overridden by env.
#
# THE ONE HOME OVERRIDE IN THIS FILE is CO8 case (b), declared again at its point of use below, per
# the plan's own instruction — it exists solely to defeat the fence's SECOND resolution tier
# ($HOME/.claude), which every other CO id in this file deliberately leaves untouched.
# ===========================================================================
HOOK="$SCRIPTS/commit-outcome-backstop.sh"
C2C="$STAGING/plugin/skills/concept-to-code/SKILL.md"
SETTINGS_STAGED="$STAGING/user/settings.json"
DOCSCI="$REPO/.github/workflows/docs-ci.yml"

git_setup_co() {
  mkdir -p "$1"
  git -C "$1" init -q >/dev/null 2>&1
  git -C "$1" config user.email "test@example.com"
  git -C "$1" config user.name "Test"
  git -C "$1" config commit.gpgsign false
}

# make_root_co <name> -> a fresh project root with docs/manifests/ present. No git unless the
# caller separately runs git_setup_co on it — several fixtures below (CO9, CO13, CO15a/b, CO16CLEAN)
# never reach commit-outcome-check.sh's own git-status read, so a repo is not needed for them.
make_root_co() {
  _r="$TMP/hroot-$1"; mkdir -p "$_r/docs/manifests"
  printf '%s' "$_r"
}

# mk_manifest_at <dest> <root> <current_step> <status> -- generalises CO1-CO6's mk_manifest() (which
# hardcodes $TMP/proj) to an arbitrary root, needed because CO11-CO17 build several independent
# project trees. Same BASE_MANIFEST/BASE_ROOT fixture as above: one real manifest, patched, never
# hand-written (ADR-0078's lesson).
mk_manifest_at() {
  [ -n "$BASE_MANIFEST" ] || return 1
  sed -e "s|$BASE_ROOT|$2|g" \
      -e "s|^current_step:.*|current_step: \"$3\"|" \
      -e "s|^status:.*|status: \"$4\"|" "$BASE_MANIFEST" >"$1"
}

# payload_co <tool_name> <skill> <cwd> <session_id> -- the jq-shaped PostToolUse payload every
# caller of this hook receives (ADR-0168's own measured live shape:
# {"name":"Skill","input":{"skill":"commit",...}}; the hook reads .tool_name/.tool_input.skill/
# .cwd/.session_id per §D7 step 4).
payload_co() {
  printf '{"tool_name":"%s","tool_input":{"skill":"%s"},"cwd":"%s","session_id":"%s"}' "$1" "$2" "$3" "$4"
}

# run_hook <payload-json> <backstop-dir> <plugin-root> [NAME=VALUE ...] -- stdout to $TMP/hook-out,
# exit code to $TMP/hook-rc, stderr captured for diagnostics only (never matched against, same
# convention as run_checker() above). Extra NAME=VALUE pairs are exported into the subshell first —
# CO15(b) uses this for a PATH override.
run_hook() {
  _rh_payload="$1"; _rh_dir="$2"; _rh_proot="$3"; shift 3
  ( export COMMIT_OUTCOME_BACKSTOP_DIR="$_rh_dir"
    export CLAUDE_PLUGIN_ROOT="$_rh_proot"
    for _rh_kv in "$@"; do export "$_rh_kv"; done
    printf '%s' "$_rh_payload" | bash "$HOOK"
  ) >"$TMP/hook-out" 2>"$TMP/hook-err"
  echo "$?" >"$TMP/hook-rc"
}

# run_hook_at <payload-json> <backstop-dir> <plugin-root> <chdir-target> -- CO17 only: a REAL `cd`
# (not merely a PWD= export) so a hook that wrongly fell back to $PWD instead of the payload's own
# .cwd field would resolve the OTHER tree, catching that exact bug class.
run_hook_at() {
  ( cd "$4" 2>/dev/null || true
    export COMMIT_OUTCOME_BACKSTOP_DIR="$2"
    export CLAUDE_PLUGIN_ROOT="$3"
    printf '%s' "$1" | bash "$HOOK"
  ) >"$TMP/hook-out" 2>"$TMP/hook-err"
  echo "$?" >"$TMP/hook-rc"
}

# audit_field4 <audit.log path> -- the classification field, tab-separated per §D6's own documented
# shape (ts, session_id, manifest_path, classification, reason). Used wherever a CO id needs the
# EXACT classification token, not merely a substring match.
audit_field4() { awk -F'\t' 'NR==1{print $4}' "$1" 2>/dev/null; }

# ===========================================================================
# Local fence extractor for c2c-step7-commit-outcome — a COPY of commit-transition-order.test.sh's
# enumerate_fences_ct/fence_body_ct, itself a copy of fence-contract-coverage.test.sh's originals,
# kept independent per ADR-0086 (rule 6): each hermetic harness in this corpus owns its own
# extraction rather than sharing one across files that answer different questions.
# ===========================================================================
enumerate_fences_co() {
  awk '
    {
      line = $0
      stripped = line; sub(/^[[:space:]]+/, "", stripped)
      if (stripped ~ /^<!--[[:space:]]*fence-(contract|illustration):/) { pending = stripped; next }
      if (stripped == "") { next }
      if (infence) {
        if (stripped == "```") { infence = 0 }
        next
      }
      if (stripped ~ /^```bash[[:space:]]*$/) {
        printf "%d\t%s\n", NR, (pending == "" ? "NONE" : pending)
        pending = ""; infence = 1; next
      }
      pending = ""
    }
  ' "$1"
}

fence_body_co() {
  awk -v want="$2" '
    NR == want {
      match($0, /^[[:space:]]*/); ind = RLENGTH; infence = 1; next
    }
    infence {
      s = $0; sub(/^[[:space:]]+/, "", s)
      if (s == "```") { exit }
      match($0, /^[[:space:]]*/); lw = RLENGTH
      strip = (lw < ind) ? lw : ind
      print substr($0, strip + 1)
    }
  ' "$1"
}

extract_outcome_fence_co() {
  _eo_ln=$(enumerate_fences_co "$C2C" | grep -F "fence-contract: c2c-step7-commit-outcome -->" | head -1 | cut -f1)
  [ -n "$_eo_ln" ] || return 1
  fence_body_co "$C2C" "$_eo_ln"
}

# run_outcome_fence_co <manifest-path> <plugin-root> [<home-override>] -- text-substitutes
# <manifest-path> (a quoted heredoc does not expand shell variables, same reasoning
# commit-transition-order.test.sh's run_outcome_fence() already states), then runs the RAW extracted
# body (still carrying its own `bash <<'FENCE_BASH' ... FENCE_BASH` wrapper) via one outer bash.
run_outcome_fence_co() {
  _rofc_body=$(extract_outcome_fence_co) || return 1
  [ -n "$_rofc_body" ] || return 1
  printf '%s\n' "$_rofc_body" | sed "s|<manifest-path>|$1|g" >"$TMP/co8-run.sh"
  if [ -n "${3:-}" ]; then
    ( export CLAUDE_PLUGIN_ROOT="$2"; export HOME="$3"
      bash "$TMP/co8-run.sh" ) >"$TMP/co8-out" 2>"$TMP/co8-err"
  else
    ( export CLAUDE_PLUGIN_ROOT="$2"
      bash "$TMP/co8-run.sh" ) >"$TMP/co8-out" 2>"$TMP/co8-err"
  fi
  echo "$?" >"$TMP/co8-rc"
  return 0
}

# ===========================================================================
# CO7 (R-02) — the fence body NAMES commit-outcome-check.sh AND no longer contains the literal
# `git status --porcelain` (rule 8, both directions; anchor on the mechanism's own filename, never
# on the word "classification", per rule 12).
# ===========================================================================
CO7_BODY=$(extract_outcome_fence_co)
CO7_FAIL=""
if [ -z "$CO7_BODY" ]; then
  CO7_FAIL="fence extraction failed -- c2c-step7-commit-outcome not found in SKILL.md"
else
  printf '%s' "$CO7_BODY" | grep -q 'commit-outcome-check\.sh' \
    || CO7_FAIL="$CO7_FAIL
  new mechanism absent: fence body does not name commit-outcome-check.sh"
  printf '%s' "$CO7_BODY" | grep -qF 'git status --porcelain' \
    && CO7_FAIL="$CO7_FAIL
  old mechanism still present: fence body still contains the literal 'git status --porcelain'"
fi
if [ -z "$CO7_FAIL" ]; then
  ok "CO7 (R-02) fence body names commit-outcome-check.sh and no longer inlines git status --porcelain"
else
  bad "CO7 (R-02) failed:$CO7_FAIL"
fi

# ===========================================================================
# CO8 (R-02) — EXECUTED proof, not a text match: extract the fence, substitute <manifest-path>, run
# it. (a) CLAUDE_PLUGIN_ROOT="$STAGING/plugin" against a terminal committed fixture -> COMMIT_OK
# exit 0. (b) CLAUDE_PLUGIN_ROOT at an empty tree AND HOME at a tree with no .claude -> neither tier
# resolves -> COMMIT_OUTCOME_NORUN noScript, exit 3. Case (b) is THE ONLY HOME OVERRIDE IN THIS FILE
# — it exists solely to defeat the fence's second resolution tier ($HOME/.claude).
# ===========================================================================
CO8_FAIL=""
if [ -n "$BASE_MANIFEST" ]; then
  FXG="$TMP/fxG"; git_setup_co "$FXG"
  mk_manifest_at "$FXG/manifest.yml" "$FXG" completed completed
  git -C "$FXG" add manifest.yml >/dev/null 2>&1
  git -C "$FXG" commit -q -m init >/dev/null 2>&1
  if run_outcome_fence_co "$FXG/manifest.yml" "$STAGING/plugin"; then
    _rc=$(cat "$TMP/co8-rc"); _out=$(cat "$TMP/co8-out")
    case "$_out" in
      "COMMIT_OK"*) [ "$_rc" -eq 0 ] || CO8_FAIL="$CO8_FAIL
  case (a): exit=$_rc (expected 0), out=$_out" ;;
      *) CO8_FAIL="$CO8_FAIL
  case (a): expected COMMIT_OK, got: $_out (exit $_rc)" ;;
    esac
  else
    CO8_FAIL="$CO8_FAIL
  case (a): fence extraction failed"
  fi

  EMPTY_PLUGIN_ROOT_CO8="$TMP/co8-empty-plugin"; mkdir -p "$EMPTY_PLUGIN_ROOT_CO8"
  NO_CLAUDE_HOME_CO8="$TMP/co8-home-no-claude"; mkdir -p "$NO_CLAUDE_HOME_CO8"
  if run_outcome_fence_co "$FXG/manifest.yml" "$EMPTY_PLUGIN_ROOT_CO8" "$NO_CLAUDE_HOME_CO8"; then
    _rc=$(cat "$TMP/co8-rc"); _out=$(cat "$TMP/co8-out")
    case "$_out" in
      "COMMIT_OUTCOME_NORUN noScript"*) [ "$_rc" -eq 3 ] || CO8_FAIL="$CO8_FAIL
  case (b): exit=$_rc (expected 3), out=$_out" ;;
      *) CO8_FAIL="$CO8_FAIL
  case (b): expected 'COMMIT_OUTCOME_NORUN noScript', got: $_out (exit $_rc)" ;;
    esac
  else
    CO8_FAIL="$CO8_FAIL
  case (b): fence extraction failed"
  fi
else
  CO8_FAIL="no base manifest available -- see CO18"
fi
if [ -z "$CO8_FAIL" ]; then
  ok "CO8 (R-02) executed fence: CLAUDE_PLUGIN_ROOT tier -> COMMIT_OK exit 0; both tiers unresolved (HOME override) -> COMMIT_OUTCOME_NORUN noScript exit 3"
else
  bad "CO8 (R-02) failed:$CO8_FAIL"
fi

# ===========================================================================
# CO9 (R-03) — payload with tool_input.skill = "interview-driver": exit 0, stdout EMPTY, and NO
# audit file created AT ALL (the pre-filter in ADR-0168 §D7 step 2 runs before any jq, any log, any
# scan — this is R-03's no-op path and it must leave nothing on disk, not even a CLEAN line).
# ===========================================================================
ROOT_CO9=$(make_root_co co9)
DIR_CO9="$TMP/state-co9"
PAYLOAD_CO9=$(payload_co "Skill" "interview-driver" "$ROOT_CO9" "sess-co9")
run_hook "$PAYLOAD_CO9" "$DIR_CO9" "$STAGING/plugin"
RC_CO9=$(cat "$TMP/hook-rc"); OUT_CO9=$(cat "$TMP/hook-out")
CO9_FAIL=""
[ "$RC_CO9" -eq 0 ] || CO9_FAIL="$CO9_FAIL
  exit=$RC_CO9 (expected 0)"
[ -z "$OUT_CO9" ] || CO9_FAIL="$CO9_FAIL
  stdout not empty: $OUT_CO9"
[ ! -e "$DIR_CO9/audit.log" ] || CO9_FAIL="$CO9_FAIL
  audit.log was created although skill != commit"
if [ -z "$CO9_FAIL" ]; then
  ok "CO9 (R-03) skill=interview-driver -> exit 0, empty stdout, no audit file at all"
else
  bad "CO9 (R-03) failed:$CO9_FAIL"
fi

# ===========================================================================
# CO10 (R-03) — staging/user/settings.json carries a PostToolUse entry with "matcher": "Skill" whose
# command names commit-outcome-backstop.sh. RED until Task 7 (this file documents the reference
# copy, ADR-0025 — sync-to-claude.sh never writes settings.json). The dynamic half (does
# sync-to-claude.sh's own MANUAL STEP notice actually gate on it) belongs in
# sync-manual-steps.test.sh, per the plan's own bullet.
# ===========================================================================
if command -v jq >/dev/null 2>&1 \
   && jq -e '(.hooks.PostToolUse // [])[] | select(.matcher == "Skill") | .hooks[]?.command // "" | test("commit-outcome-backstop\\.sh")' \
       "$SETTINGS_STAGED" >/dev/null 2>&1; then
  ok "CO10 (R-03) staging/user/settings.json carries a PostToolUse/Skill entry naming commit-outcome-backstop.sh"
else
  bad "CO10 (R-03) staging/user/settings.json has no PostToolUse entry with matcher=Skill naming commit-outcome-backstop.sh"
fi

# ===========================================================================
# CO11 (R-04) — the ADNOTA FIXTURE. current_step: step_7_commit, status: in_progress, mtime now,
# committed and clean; payload skill="commit", cwd inside the tree. Assert: stdout contains
# COMMIT_NONTERMINAL current_step AND names the manifest path; the audit log gains EXACTLY one line
# whose 4th tab-field is COMMIT_NONTERMINAL; exit 0.
# ===========================================================================
CO11_FAIL=""
if [ -n "$BASE_MANIFEST" ]; then
  ROOT_CO11=$(make_root_co co11); git_setup_co "$ROOT_CO11"
  MANIFEST_CO11="$ROOT_CO11/docs/manifests/2026-08-23-co11-adnota.manifest.yml"
  mk_manifest_at "$MANIFEST_CO11" "$ROOT_CO11" step_7_commit in_progress
  git -C "$ROOT_CO11" add docs/manifests/2026-08-23-co11-adnota.manifest.yml >/dev/null 2>&1
  git -C "$ROOT_CO11" commit -q -m init >/dev/null 2>&1
  DIR_CO11="$TMP/state-co11"
  PAYLOAD_CO11=$(payload_co "Skill" "commit" "$ROOT_CO11" "sess-co11")
  run_hook "$PAYLOAD_CO11" "$DIR_CO11" "$STAGING/plugin"
  RC_CO11=$(cat "$TMP/hook-rc"); OUT_CO11=$(cat "$TMP/hook-out")
  [ "$RC_CO11" -eq 0 ] || CO11_FAIL="$CO11_FAIL
  exit=$RC_CO11 (expected 0)"
  printf '%s' "$OUT_CO11" | grep -q 'COMMIT_NONTERMINAL current_step' || CO11_FAIL="$CO11_FAIL
  stdout does not contain 'COMMIT_NONTERMINAL current_step': $OUT_CO11"
  printf '%s' "$OUT_CO11" | grep -qF "$MANIFEST_CO11" || CO11_FAIL="$CO11_FAIL
  stdout does not name the manifest path $MANIFEST_CO11: $OUT_CO11"
  LOG_CO11="$DIR_CO11/audit.log"
  if [ -f "$LOG_CO11" ]; then
    _n=$(grep -c . "$LOG_CO11" 2>/dev/null || true)
    [ "$_n" -eq 1 ] || CO11_FAIL="$CO11_FAIL
  audit log has $_n lines (expected exactly 1)"
    [ "$(audit_field4 "$LOG_CO11")" = "COMMIT_NONTERMINAL" ] || CO11_FAIL="$CO11_FAIL
  audit log's 4th field is '$(audit_field4 "$LOG_CO11")' (expected 'COMMIT_NONTERMINAL')"
  else
    CO11_FAIL="$CO11_FAIL
  no audit.log written at all"
  fi
else
  CO11_FAIL="no base manifest available -- see CO18"
fi
if [ -z "$CO11_FAIL" ]; then
  ok "CO11 (R-04) Adnota fixture (step_7_commit/in_progress) -> COMMIT_NONTERMINAL current_step reported, one audit line, exit 0"
else
  bad "CO11 (R-04) failed:$CO11_FAIL"
fi

# ===========================================================================
# CO12 (R-05) — same shape of fixture, mtime pushed to 2020 -> NOT scanned: no COMMIT_NONTERMINAL on
# stdout, and the audit log's only line is CLEAN (rule 4: absence alone would be indistinguishable
# from "the hook never ran" — CLEAN is what proves it ran and found nothing in scope).
# ===========================================================================
CO12_FAIL=""
if [ -n "$BASE_MANIFEST" ]; then
  ROOT_CO12=$(make_root_co co12)
  MANIFEST_CO12="$ROOT_CO12/docs/manifests/2026-08-23-co12-stale.manifest.yml"
  mk_manifest_at "$MANIFEST_CO12" "$ROOT_CO12" step_7_commit in_progress
  touch -t 202001010000 "$MANIFEST_CO12"
  DIR_CO12="$TMP/state-co12"
  PAYLOAD_CO12=$(payload_co "Skill" "commit" "$ROOT_CO12" "sess-co12")
  run_hook "$PAYLOAD_CO12" "$DIR_CO12" "$STAGING/plugin"
  RC_CO12=$(cat "$TMP/hook-rc"); OUT_CO12=$(cat "$TMP/hook-out")
  [ "$RC_CO12" -eq 0 ] || CO12_FAIL="$CO12_FAIL
  exit=$RC_CO12 (expected 0)"
  printf '%s' "$OUT_CO12" | grep -q 'COMMIT_NONTERMINAL' && CO12_FAIL="$CO12_FAIL
  stdout wrongly reports COMMIT_NONTERMINAL for an out-of-window manifest: $OUT_CO12"
  LOG_CO12="$DIR_CO12/audit.log"
  if [ -f "$LOG_CO12" ]; then
    _n=$(grep -c . "$LOG_CO12" 2>/dev/null || true)
    [ "$_n" -eq 1 ] || CO12_FAIL="$CO12_FAIL
  audit log has $_n lines (expected exactly 1)"
    [ "$(audit_field4 "$LOG_CO12")" = "CLEAN" ] || CO12_FAIL="$CO12_FAIL
  audit log's 4th field is '$(audit_field4 "$LOG_CO12")' (expected 'CLEAN')"
  else
    CO12_FAIL="$CO12_FAIL
  no audit.log written -- an unscanned-by-mtime manifest still leaves the population empty, which must log CLEAN (§D6)"
  fi
else
  CO12_FAIL="no base manifest available -- see CO18"
fi
if [ -z "$CO12_FAIL" ]; then
  ok "CO12 (R-05) mtime > 24h -> not scanned, no COMMIT_NONTERMINAL on stdout, audit log's only line is CLEAN"
else
  bad "CO12 (R-05) failed:$CO12_FAIL"
fi

# ===========================================================================
# CO13 (R-05, rule 8 reverse direction) — a manifest IN the mtime window at
# current_step: step_3_project_memory, status: in_progress, UNCOMMITTED -> NOT reported. This is
# §D5's population rule asserted from the outside: an in-flight chain at an unrelated step must not
# generate a report on every unrelated commit. Population ends up empty -> CLEAN, same observable
# shape as CO12, asserted independently (a fresh fixture — tests stay order-independent).
# ===========================================================================
CO13_FAIL=""
if [ -n "$BASE_MANIFEST" ]; then
  ROOT_CO13=$(make_root_co co13)
  MANIFEST_CO13="$ROOT_CO13/docs/manifests/2026-08-23-co13-inflight.manifest.yml"
  mk_manifest_at "$MANIFEST_CO13" "$ROOT_CO13" step_3_project_memory in_progress
  DIR_CO13="$TMP/state-co13"
  PAYLOAD_CO13=$(payload_co "Skill" "commit" "$ROOT_CO13" "sess-co13")
  run_hook "$PAYLOAD_CO13" "$DIR_CO13" "$STAGING/plugin"
  RC_CO13=$(cat "$TMP/hook-rc"); OUT_CO13=$(cat "$TMP/hook-out")
  [ "$RC_CO13" -eq 0 ] || CO13_FAIL="$CO13_FAIL
  exit=$RC_CO13 (expected 0)"
  [ -z "$OUT_CO13" ] || CO13_FAIL="$CO13_FAIL
  stdout not empty for an out-of-population manifest: $OUT_CO13"
  LOG_CO13="$DIR_CO13/audit.log"
  if [ -f "$LOG_CO13" ]; then
    [ "$(audit_field4 "$LOG_CO13")" = "CLEAN" ] || CO13_FAIL="$CO13_FAIL
  audit log's 4th field is '$(audit_field4 "$LOG_CO13")' (expected 'CLEAN')"
  else
    CO13_FAIL="$CO13_FAIL
  no audit.log written"
  fi
else
  CO13_FAIL="no base manifest available -- see CO18"
fi
if [ -z "$CO13_FAIL" ]; then
  ok "CO13 (R-05, reverse) step_3_project_memory/in_progress, in-window, uncommitted -> not reported (CLEAN)"
else
  bad "CO13 (R-05, reverse) failed:$CO13_FAIL"
fi

# ===========================================================================
# CO14 (R-04, R-05) — the population INCLUDES step_e4_commit and step_h5_commit, not only
# step_7_commit and completed (§D5's three-path widening — CO11 alone would only prove the Standard
# path). One fixture per state, each committed/clean/in-window so a report is exactly the signal
# that the state was kept.
# ===========================================================================
CO14_FAIL=""
if [ -n "$BASE_MANIFEST" ]; then
  for _st in step_e4_commit step_h5_commit; do
    _root=$(make_root_co "co14-$_st"); git_setup_co "$_root"
    _mf="$_root/docs/manifests/2026-08-23-co14-$_st.manifest.yml"
    mk_manifest_at "$_mf" "$_root" "$_st" in_progress
    git -C "$_root" add "docs/manifests/2026-08-23-co14-$_st.manifest.yml" >/dev/null 2>&1
    git -C "$_root" commit -q -m init >/dev/null 2>&1
    _dir="$TMP/state-co14-$_st"
    _payload=$(payload_co "Skill" "commit" "$_root" "sess-co14-$_st")
    run_hook "$_payload" "$_dir" "$STAGING/plugin"
    _rc=$(cat "$TMP/hook-rc"); _out=$(cat "$TMP/hook-out")
    [ "$_rc" -eq 0 ] || CO14_FAIL="$CO14_FAIL
  $_st: exit=$_rc (expected 0)"
    printf '%s' "$_out" | grep -q 'COMMIT_NONTERMINAL current_step' || CO14_FAIL="$CO14_FAIL
  $_st: stdout does not contain 'COMMIT_NONTERMINAL current_step': $_out"
    _log="$_dir/audit.log"
    if [ -f "$_log" ]; then
      [ "$(audit_field4 "$_log")" = "COMMIT_NONTERMINAL" ] || CO14_FAIL="$CO14_FAIL
  $_st: audit log's 4th field is '$(audit_field4 "$_log")' (expected 'COMMIT_NONTERMINAL')"
    else
      CO14_FAIL="$CO14_FAIL
  $_st: no audit.log written"
    fi
  done
else
  CO14_FAIL="no base manifest available -- see CO18"
fi
if [ -z "$CO14_FAIL" ]; then
  ok "CO14 (R-04, R-05) step_e4_commit and step_h5_commit are both in the commit-stage population"
else
  bad "CO14 (R-04, R-05) failed:$CO14_FAIL"
fi

# ===========================================================================
# CO15 (R-06) — four error paths, each exit 0, each leaving the payload's tool call unharmed
# (report-only, never a decision/block field per §D4): (a) no docs/manifests/ anywhere up from cwd;
# (b) jq absent (PATH shadow, real interpreter paths captured first — the VAR=value cmd trap);
# (c) COMMIT_OUTCOME_BACKSTOP_DIR pointed at an unwritable path, WITH a reportable manifest present,
# per SPEC.md's own edge case ("audit-log directory uncreatable -> fail open; report to stdout only,
# skip the audit-log write") — an empty population would make (c) indistinguishable from (a), so
# this fixture deliberately has something to report; (d) commit-outcome-check.sh unresolved (its own
# fixture is reused by CO16 below, which contrasts its NORUN report against a genuine CLEAN one).
# ===========================================================================
CO15_FAIL=""

# (a) no docs/manifests/ anywhere up from cwd.
ROOT_CO15A="$TMP/hroot-co15a"; mkdir -p "$ROOT_CO15A"
DIR_CO15A="$TMP/state-co15a"
PAYLOAD_CO15A=$(payload_co "Skill" "commit" "$ROOT_CO15A" "sess-co15a")
run_hook "$PAYLOAD_CO15A" "$DIR_CO15A" "$STAGING/plugin"
RC_A=$(cat "$TMP/hook-rc"); OUT_A=$(cat "$TMP/hook-out")
[ "$RC_A" -eq 0 ] || CO15_FAIL="$CO15_FAIL
  (a) exit=$RC_A (expected 0)"
[ -z "$OUT_A" ] || CO15_FAIL="$CO15_FAIL
  (a) stdout not empty: $OUT_A"
[ ! -e "$DIR_CO15A/audit.log" ] || CO15_FAIL="$CO15_FAIL
  (a) audit.log was created although no docs/manifests/ exists anywhere up from cwd"

# (b) jq absent -- shadow PATH with every OTHER interpreter this hook needs, real paths captured via
# command -v (never blank PATH itself, per the VAR=value cmd trap).
STUBDIR_CO15B="$TMP/nobin-co15b"; mkdir -p "$STUBDIR_CO15B"
for _b in bash cat printf mkdir grep sed awk basename dirname date mv rm mktemp env find head cut; do
  _p=$(command -v "$_b" 2>/dev/null) && ln -sf "$_p" "$STUBDIR_CO15B/$(basename "$_p")" 2>/dev/null
done
ROOT_CO15B=$(make_root_co co15b)
DIR_CO15B="$TMP/state-co15b"
PAYLOAD_CO15B=$(payload_co "Skill" "commit" "$ROOT_CO15B" "sess-co15b")
run_hook "$PAYLOAD_CO15B" "$DIR_CO15B" "$STAGING/plugin" "PATH=$STUBDIR_CO15B"
RC_B=$(cat "$TMP/hook-rc"); OUT_B=$(cat "$TMP/hook-out")
[ "$RC_B" -eq 0 ] || CO15_FAIL="$CO15_FAIL
  (b) exit=$RC_B (expected 0)"
LOG_B="$DIR_CO15B/audit.log"
if [ -f "$LOG_B" ]; then
  grep -qi 'jq missing' "$LOG_B" || CO15_FAIL="$CO15_FAIL
  (b) audit log does not mention 'jq missing': $(cat "$LOG_B")"
else
  CO15_FAIL="$CO15_FAIL
  (b) no audit.log written for the jq-absent path"
fi

# (c) COMMIT_OUTCOME_BACKSTOP_DIR pointed at an unwritable path, WITH a reportable manifest.
: > "$TMP/co15c-blocked"
DIR_CO15C="$TMP/co15c-blocked/state"
if [ -n "$BASE_MANIFEST" ]; then
  ROOT_CO15C=$(make_root_co co15c); git_setup_co "$ROOT_CO15C"
  MANIFEST_CO15C="$ROOT_CO15C/docs/manifests/2026-08-23-co15c.manifest.yml"
  mk_manifest_at "$MANIFEST_CO15C" "$ROOT_CO15C" step_7_commit in_progress
  git -C "$ROOT_CO15C" add docs/manifests/2026-08-23-co15c.manifest.yml >/dev/null 2>&1
  git -C "$ROOT_CO15C" commit -q -m init >/dev/null 2>&1
  PAYLOAD_CO15C=$(payload_co "Skill" "commit" "$ROOT_CO15C" "sess-co15c")
  run_hook "$PAYLOAD_CO15C" "$DIR_CO15C" "$STAGING/plugin"
  RC_C=$(cat "$TMP/hook-rc"); OUT_C=$(cat "$TMP/hook-out")
  [ "$RC_C" -eq 0 ] || CO15_FAIL="$CO15_FAIL
  (c) exit=$RC_C (expected 0)"
  printf '%s' "$OUT_C" | grep -q 'COMMIT_NONTERMINAL' || CO15_FAIL="$CO15_FAIL
  (c) stdout does not report COMMIT_NONTERMINAL although only the audit dir is unwritable (SPEC.md: 'report to stdout only, skip the audit-log write'): $OUT_C"
  [ ! -e "$DIR_CO15C/audit.log" ] || CO15_FAIL="$CO15_FAIL
  (c) audit.log was written despite an uncreatable directory"
else
  CO15_FAIL="$CO15_FAIL
  (c) no base manifest available -- see CO18"
fi

# (d) commit-outcome-check.sh unresolved -- CLAUDE_PLUGIN_ROOT at an empty tree, HOME at a tree with
# no .claude, so neither tier resolves. Reused by CO16 below.
DIR_CO15D="$TMP/state-co15d"
EMPTY_PLUGIN_ROOT_CO15D="$TMP/co15d-empty-plugin"; mkdir -p "$EMPTY_PLUGIN_ROOT_CO15D"
NO_CLAUDE_HOME_CO15D="$TMP/co15d-home-no-claude"; mkdir -p "$NO_CLAUDE_HOME_CO15D"
if [ -n "$BASE_MANIFEST" ]; then
  ROOT_CO15D=$(make_root_co co15d); git_setup_co "$ROOT_CO15D"
  MANIFEST_CO15D="$ROOT_CO15D/docs/manifests/2026-08-23-co15d.manifest.yml"
  mk_manifest_at "$MANIFEST_CO15D" "$ROOT_CO15D" step_7_commit in_progress
  git -C "$ROOT_CO15D" add docs/manifests/2026-08-23-co15d.manifest.yml >/dev/null 2>&1
  git -C "$ROOT_CO15D" commit -q -m init >/dev/null 2>&1
  PAYLOAD_CO15D=$(payload_co "Skill" "commit" "$ROOT_CO15D" "sess-co15d")
  run_hook "$PAYLOAD_CO15D" "$DIR_CO15D" "$EMPTY_PLUGIN_ROOT_CO15D" "HOME=$NO_CLAUDE_HOME_CO15D"
  RC_D=$(cat "$TMP/hook-rc"); OUT_D=$(cat "$TMP/hook-out")
  [ "$RC_D" -eq 0 ] || CO15_FAIL="$CO15_FAIL
  (d) exit=$RC_D (expected 0)"
else
  CO15_FAIL="$CO15_FAIL
  (d) no base manifest available -- see CO18"
fi

if [ -z "$CO15_FAIL" ]; then
  ok "CO15 (R-06) four error paths (no docs/manifests; jq absent; unwritable audit dir; unresolved checker) all exit 0, tool call unharmed"
else
  bad "CO15 (R-06) failed:$CO15_FAIL"
fi

# ===========================================================================
# CO16 (R-06, rule 4) — path (d) reports its OWN condition (NORUN/noScript, both on stdout and in
# the audit line), distinct from a genuine CLEAN line. Contrasted against a DEDICATED clean fixture
# (population empty, dir writable) rather than CO15(a)/(c) above — (a) never writes a log at all and
# (c)'s dir is deliberately uncreatable, so neither has an on-disk CLEAN line to compare against;
# this is the one fixture in the whole file that genuinely produces one.
# ===========================================================================
CO16_FAIL=""
LOG_CO15D="$DIR_CO15D/audit.log"
if [ -f "$LOG_CO15D" ]; then
  grep -q 'NORUN' "$LOG_CO15D" || CO16_FAIL="$CO16_FAIL
  (d) audit log does not mention NORUN: $(cat "$LOG_CO15D")"
  grep -q 'noScript' "$LOG_CO15D" || CO16_FAIL="$CO16_FAIL
  (d) audit log does not mention noScript: $(cat "$LOG_CO15D")"
  grep -qi 'CLEAN' "$LOG_CO15D" && CO16_FAIL="$CO16_FAIL
  (d) audit log wrongly ALSO reads CLEAN — an unrun check must not read as a clean result"
else
  CO16_FAIL="$CO16_FAIL
  (d) no audit.log written for the unresolved-checker path"
fi
printf '%s' "$OUT_D" | grep -q 'NORUN' || CO16_FAIL="$CO16_FAIL
  (d) stdout does not mention NORUN: $OUT_D"
printf '%s' "$OUT_D" | grep -q 'noScript' || CO16_FAIL="$CO16_FAIL
  (d) stdout does not mention noScript: $OUT_D"

if [ -n "$BASE_MANIFEST" ]; then
  ROOT_CO16CLEAN=$(make_root_co co16clean)
  DIR_CO16CLEAN="$TMP/state-co16clean"
  PAYLOAD_CO16CLEAN=$(payload_co "Skill" "commit" "$ROOT_CO16CLEAN" "sess-co16clean")
  run_hook "$PAYLOAD_CO16CLEAN" "$DIR_CO16CLEAN" "$STAGING/plugin"
  LOG_CO16CLEAN="$DIR_CO16CLEAN/audit.log"
  if [ -f "$LOG_CO16CLEAN" ]; then
    [ "$(audit_field4 "$LOG_CO16CLEAN")" = "CLEAN" ] || CO16_FAIL="$CO16_FAIL
  clean fixture's audit line 4th field is '$(audit_field4 "$LOG_CO16CLEAN")' (expected 'CLEAN')"
  else
    CO16_FAIL="$CO16_FAIL
  clean fixture wrote no audit.log at all"
  fi
else
  CO16_FAIL="$CO16_FAIL
  no base manifest available -- see CO18"
fi

if [ -z "$CO16_FAIL" ]; then
  ok "CO16 (R-06, rule 4) unresolved checker reports NORUN noScript, textually distinct from a genuine CLEAN line"
else
  bad "CO16 (R-06, rule 4) failed:$CO16_FAIL"
fi

# ===========================================================================
# CO17 (R-07) — the project root comes from the payload's cwd, not from the process's own working
# directory. Two fixture trees, each with its own stale manifest; cwd points at one tree while the
# actual process cwd (via a REAL cd, not just a PWD= export) sits in the OTHER — a hook that fell
# back to $PWD instead of jq's .cwd read would report the wrong tree's manifest.
# ===========================================================================
CO17_FAIL=""
if [ -n "$BASE_MANIFEST" ]; then
  ROOT_CO17A=$(make_root_co co17a); git_setup_co "$ROOT_CO17A"
  MANIFEST_CO17A="$ROOT_CO17A/docs/manifests/2026-08-23-co17a.manifest.yml"
  mk_manifest_at "$MANIFEST_CO17A" "$ROOT_CO17A" step_7_commit in_progress
  git -C "$ROOT_CO17A" add docs/manifests/2026-08-23-co17a.manifest.yml >/dev/null 2>&1
  git -C "$ROOT_CO17A" commit -q -m init >/dev/null 2>&1

  ROOT_CO17B=$(make_root_co co17b); git_setup_co "$ROOT_CO17B"
  MANIFEST_CO17B="$ROOT_CO17B/docs/manifests/2026-08-23-co17b.manifest.yml"
  mk_manifest_at "$MANIFEST_CO17B" "$ROOT_CO17B" step_7_commit in_progress
  git -C "$ROOT_CO17B" add docs/manifests/2026-08-23-co17b.manifest.yml >/dev/null 2>&1
  git -C "$ROOT_CO17B" commit -q -m init >/dev/null 2>&1

  PAYLOAD_CO17A=$(payload_co "Skill" "commit" "$ROOT_CO17A" "sess-co17a")
  run_hook_at "$PAYLOAD_CO17A" "$TMP/state-co17a" "$STAGING/plugin" "$ROOT_CO17B"
  OUT_17A=$(cat "$TMP/hook-out")
  printf '%s' "$OUT_17A" | grep -qF "$MANIFEST_CO17A" || CO17_FAIL="$CO17_FAIL
  cwd=A/pwd=B: stdout does not name tree A's manifest: $OUT_17A"
  printf '%s' "$OUT_17A" | grep -qF "$MANIFEST_CO17B" && CO17_FAIL="$CO17_FAIL
  cwd=A/pwd=B: stdout wrongly names tree B's manifest (fell back to \$PWD instead of the payload's cwd): $OUT_17A"

  PAYLOAD_CO17B=$(payload_co "Skill" "commit" "$ROOT_CO17B" "sess-co17b")
  run_hook_at "$PAYLOAD_CO17B" "$TMP/state-co17b" "$STAGING/plugin" "$ROOT_CO17A"
  OUT_17B=$(cat "$TMP/hook-out")
  printf '%s' "$OUT_17B" | grep -qF "$MANIFEST_CO17B" || CO17_FAIL="$CO17_FAIL
  cwd=B/pwd=A: stdout does not name tree B's manifest: $OUT_17B"
  printf '%s' "$OUT_17B" | grep -qF "$MANIFEST_CO17A" && CO17_FAIL="$CO17_FAIL
  cwd=B/pwd=A: stdout wrongly names tree A's manifest: $OUT_17B"
else
  CO17_FAIL="no base manifest available -- see CO18"
fi
if [ -z "$CO17_FAIL" ]; then
  ok "CO17 (R-07) project root resolved from payload cwd, not from the process's own working directory"
else
  bad "CO17 (R-07) failed:$CO17_FAIL"
fi

# ===========================================================================
# CO-CI — this harness's own name is in .github/workflows/docs-ci.yml's shell-tests loop list (the
# self-registration convention every recent harness here follows; Task 6 adds the entry, so this
# assertion is RED until then). NO PLANT DECLARED, and that is the reason rather than an oversight:
# plant-check.sh mutates an isolated copy of staging/ and docs/ only (its own header) —
# .github/workflows/docs-ci.yml is in neither, so this assertion's mechanism cannot be reached by a
# plant, exactly the precedent pairs-completeness.test.sh's own CI1 already states for this same file.
# ===========================================================================
DOCSCI_LOOP=$(grep 'for t in ' "$DOCSCI" 2>/dev/null | head -1)
if printf '%s' "$DOCSCI_LOOP" | grep -qE '[[:space:]]commit-outcome-backstop[[:space:];]'; then
  ok "CO-CI docs-ci.yml's shell-tests loop runs commit-outcome-backstop"
else
  bad "CO-CI commit-outcome-backstop is not in docs-ci.yml's explicit harness list"
fi

# ===========================================================================
# COZ1 — assertion-count floor (ADR-0083 §D3), RE-MEASURED from the finished file (rule 10: a floor
# is a vacuity guard on the derivation, never the pin for any individual CO id's own behavior — the
# per-assertion evidence is each CO id going RED against its own declared plant at Task 8). NO PLANT
# (same "a vanished block is a structural deletion, not a one-line mutation" reasoning
# autopilot-run-scope.test.sh's own Z1 already states; that file's survey found no Z1 floor in this
# corpus carries one either).
# ===========================================================================
_co_total=$((PASS + FAIL))
if [ "$_co_total" -ge 19 ]; then
  ok "COZ1 assertion-count floor ($_co_total >= 19)"
else
  bad "COZ1 assertion count fell to $_co_total (floor 19) -- assertions vanished from this file"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
