#!/bin/bash
# pairs-completeness test harness (ADR-0024, extended by ADR-0043) — two structural checks, in
# opposite directions:
#   1. every PAIRS src exists under staging/  (ADR-0024, the original check)
#   2. every file in the covered staging subtrees appears as a PAIRS src  (ADR-0043, issue #93)
# Direction 2 exists because direction 1 cannot see the failure that motivated it: PR #90's fix to
# architect.md never deployed, because no agent file was in PAIRS at all. A file missing FROM the
# list is invisible to a check that only validates the list's own entries. Nothing failed, nothing
# looked wrong, and the deployed agent kept a stale line for half a day.
# This is a "self-test the checker" harness (see the plan's rationale): there is no live PAIRS defect to
# drive a real RED against, so it first proves the check function itself detects a missing file against a
# synthetic broken fixture, then runs the same check against the real PAIRS block in sync-to-claude.sh.
# It does NOT compare against ~/.claude (deliberately — see ADR-0024 §3.4): staging is expected to move
# ahead of deployed as the audit-fix roadmap lands fixes.
# Bash 3.2 clean. Run: bash pairs-completeness.test.sh
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
SYNC="$STAGING/sync-to-claude.sh"

PASS=0; FAIL=0

# ok()/bad() did not exist in this file until issue #212 needed per-assertion reporting, and their
# absence was INVISIBLE: six calls to an undefined `ok` printed "command not found" to stderr and
# the suite still reported PASS=244 FAIL=0 and exited 0. Nothing here runs under `set -e`, and the
# counters are only touched by the check_* helpers, so an assertion that never executes is
# indistinguishable from one that passed. Anything added below must go through these.
ok()  { PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

# check_pairs <base-dir> <pairs-file>
# Reads src|dst lines from <pairs-file>, asserts <base-dir>/<src> exists as a file.
# Updates the global PASS/FAIL counters and prints PASS: <src> / FAIL: <src> per line.
check_pairs() {
  _base="$1"; _file="$2"
  while IFS='|' read -r src dst; do
    [ -z "$src" ] && continue
    if [ -f "$_base/$src" ]; then
      PASS=$((PASS+1)); printf 'PASS: %s\n' "$src"
    else
      FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$src"
    fi
  done < "$_file"
}

# check_complete <pairs-file> <staging-relative-dir> <name-pattern>
# The reverse direction (ADR-0043): asserts every file matching <name-pattern> under
# <staging-relative-dir> appears as a src on some PAIRS line. Compares the staging-relative path
# exactly as PAIRS spells it, so a typo'd entry counts as missing rather than as coverage.
# <name-pattern> may span a directory level (e.g. '*/SKILL.md'), which is why the relative path is
# derived by stripping the staging prefix rather than by basename — the first version flattened
# skills/<name>/SKILL.md to skills/SKILL.md and would have reported every skill as uncovered.
# A fourth argument, when given, names a file of staging-relative paths that are EXEMPT — files
# that legitimately have no deployed counterpart. Every exemption is DECLARED, never a silent skip,
# and check_exemptions_live() below asserts each one still exists: an exemption that outlives its
# subject protects nothing while still hiding whatever takes its place.
check_complete() {
  _file="$1"; _dir="$2"; _pat="$3"; _exempt="${4:-}"
  for _f in "$STAGING/$_dir"/$_pat; do
    [ -f "$_f" ] || continue                       # unexpanded glob when a dir is empty
    _rel="${_f#$STAGING/}"
    if [ -n "$_exempt" ] && grep -qxF "$_rel" "$_exempt" 2>/dev/null; then
      PASS=$((PASS+1)); printf 'PASS: exempt from PAIRS by declaration (not deployed): %s\n' "$_rel"
    elif cut -d'|' -f1 < "$_file" | grep -qxF "$_rel"; then
      PASS=$((PASS+1)); printf 'PASS: covered by PAIRS: %s\n' "$_rel"
    else
      FAIL=$((FAIL+1)); printf 'FAIL: in staging but not in PAIRS (edits will never deploy): %s\n' "$_rel"
    fi
  done
}

# An exemption list is only meaningful while its subjects exist. Without this, deleting or renaming
# a probe script leaves a line that silently exempts nothing — and the next file to take that path
# would inherit the exemption.
check_exemptions_live() {
  while IFS= read -r _e; do
    [ -n "$_e" ] || continue
    if [ -f "$STAGING/$_e" ]; then
      PASS=$((PASS+1)); printf 'PASS: exemption has a live subject: %s\n' "$_e"
    else
      FAIL=$((FAIL+1)); printf 'FAIL: exemption names a file that no longer exists — delete the line: %s\n' "$_e"
    fi
  done < "$1"
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- self-test: prove the checker detects a missing PAIRS src (real RED) --------------------------
printf 'does/not/exist.sh|hooks/does-not-exist.sh\n' > "$tmp/broken-pairs"
check_pairs "$tmp" "$tmp/broken-pairs" > "$tmp/self-test.out"

if [ "$PASS" -eq 0 ] && [ "$FAIL" -eq 1 ] && grep -q '^FAIL: does/not/exist.sh$' "$tmp/self-test.out"; then
  printf 'ok   self-test: checker detects a missing PAIRS src (FAIL=1)\n'
else
  printf 'FAIL self-test: checker did not detect the broken fixture (PASS=%s FAIL=%s)\n' "$PASS" "$FAIL"
  exit 1
fi

# --- self-test 2 (ADR-0043): prove the reverse checker detects an UNLISTED staging file ------------
# Without this the new check could pass vacuously — a glob that matches nothing reports nothing, and
# a silent zero-file check reads exactly like full coverage. Point it at a real, non-empty subtree
# with an empty PAIRS list: every file there must be reported missing.
PASS=0; FAIL=0
: > "$tmp/empty-pairs"
check_complete "$tmp/empty-pairs" "plugin/agents" '*.md' > "$tmp/self-test-2.out"
_agent_count=$(ls -1 "$STAGING/plugin/agents"/*.md 2>/dev/null | wc -l | tr -d ' ')

if [ "$_agent_count" -gt 0 ] && [ "$PASS" -eq 0 ] && [ "$FAIL" -eq "$_agent_count" ]; then
  printf 'ok   self-test 2: reverse checker flags every unlisted staging file (FAIL=%s)\n' "$FAIL"
else
  printf 'FAIL self-test 2: reverse checker did not flag the unlisted fixture (files=%s PASS=%s FAIL=%s)\n' \
    "$_agent_count" "$PASS" "$FAIL"
  exit 1
fi

# reset counters before the real check
PASS=0; FAIL=0

# --- real check: every PAIRS src in sync-to-claude.sh must exist under staging/ --------------------
awk '/^PAIRS="$/{f=1; next} /^"$/{f=0} f' "$SYNC" > "$tmp/real-pairs"
check_pairs "$STAGING" "$tmp/real-pairs"

# --- real check, reverse direction (ADR-0043, issue #93) ------------------------------------------
# Covered subtrees: the two whose files reach ~/.claude ONLY through docs/RUNBOOK.md Step 6's bulk
# `cp`, which is a full-install procedure nobody runs to ship a one-line frontmatter fix.
# staging/plugin/hooks/hooks.json is deliberately NOT covered: it has no deployed counterpart at all,
# so a PAIRS entry would create a file that has never existed there. That is a deployment decision,
# not a completeness fix — ADR-0043 Consequences.
check_complete "$tmp/real-pairs" "plugin/agents" '*.md'
check_complete "$tmp/real-pairs" "user/rules" '*.md'
# Skills: SKILL.md only, not the scripts/ and tests/ files under each skill. Those are vendored
# selectively by design (ADR-0024 scope), so demanding an entry for each would report intended
# absences as defects. A skill's SKILL.md is the file that always has to reach the machine.
check_complete "$tmp/real-pairs" "plugin/skills" '*/SKILL.md'
# A skill that splits step-local content out of SKILL.md (VCS-042) puts it under references/*.md —
# unlike scripts/tests/ above, this IS content the orchestrator reads at runtime, so a missing PAIRS
# entry here is the same silent deployment gap as a missing SKILL.md entry, not an intended absence.
check_complete "$tmp/real-pairs" "plugin/skills" '*/references/*.md'

# Hook scripts. Found missing on 2026-07-29 while syncing the issue #174 fix: three REGISTERED,
# DEPLOYED hooks (auto-format.sh, chain-memory-capture.sh, protect-files.sh) had no PAIRS entry, so
# a repo-side edit could never reach ~/.claude. Two of the three happened to be byte-identical with
# their deployed copies at that moment, which is precisely the condition ADR-0043 names as what
# keeps this class of gap invisible — the one that differed was carrying an unshipped bug fix.
#
# The four exemptions are probe-only tooling with no deployed counterpart and no settings.json
# registration. worktree-capture.sh is not merely undeployed but MUST NOT be wired: registering it
# aborts every worktree creation on the machine (ADR-0068 §D2), so an accidental PAIRS entry for it
# is worse than a missing one.
cat > "$tmp/scripts-exempt" <<'EOF'
plugin/scripts/hook-probe.sh
plugin/scripts/hook-probe-sandbox.sh
plugin/scripts/hook-probe-verify.sh
plugin/scripts/worktree-capture.sh
EOF
check_complete "$tmp/real-pairs" "plugin/scripts" '*.sh' "$tmp/scripts-exempt"
check_exemptions_live "$tmp/scripts-exempt"

# =====================================================================================
# ZONE ANOMALIES (issue #212). Every PAIRS entry maps its zone predictably — plugin/scripts/X ->
# hooks/X, plugin/skills/X -> skills/X, plugin/agents/X -> agents/X, user/X -> X. Two entries do
# not, both for good reasons, and until now neither was checked and only one was written down.
#
# This is the direction that matters (rule 5): the anomaly set is DERIVED from PAIRS and each member
# must appear in sync-to-claude.sh's own `pairs-zone-anomaly:` declaration. A third anomaly fails
# HERE, at the moment it is introduced, instead of being rediscovered by an audit that then has to
# adjudicate whether it is deliberate. It cost exactly that once already: the audit of 2026-07-29
# reported hook-verify-workflow.sh as a missing file and the conclusion had to be reconstructed
# from ADR-0024.
#
# The needle is built at run time so this file does not match its own search (rule 12).
ZMARK="pairs-zone-""anomaly"
ZDECL=$(grep "^# *${ZMARK}:" "$SYNC" 2>/dev/null | head -1 | sed "s/^# *${ZMARK}://")

_zn=$(printf '%s\n' $ZDECL | sed '/^$/d' | wc -l | tr -d ' ')
[ "$_zn" -ge 1 ] && ok "ZA1: sync-to-claude.sh declares $_zn zone anomal(ies)" \
                 || bad "ZA1: no '${ZMARK}:' declaration line found in $SYNC"

# Derive. Expected dest per zone; anything else is an anomaly.
ZFOUND=$(awk -F'|' '
  /^plugin\/scripts\// { t=$1; sub(/^plugin\/scripts\//,"",t); if ($2 != "hooks/" t) print $1; next }
  /^plugin\/skills\//  { t=$1; sub(/^plugin\//,"",t);          if ($2 != t)          print $1; next }
  /^plugin\/agents\//  { t=$1; sub(/^plugin\//,"",t);          if ($2 != t)          print $1; next }
  /^plugin\/rules\//   { t=$1; sub(/^plugin\//,"",t);          if ($2 != t)          print $1; next }
  /^user\//            { t=$1; sub(/^user\//,"",t);            if ($2 != t)          print $1; next }
' "$SYNC")

# Count guard on the DERIVATION, not on the anomalies: if the PAIRS parse returns almost nothing,
# an empty anomaly set looks like full compliance. Same failure shape as self-test 2 above.
_zt=$(grep -cE '^(plugin|user)/[^|]+\|' "$SYNC")
[ "$_zt" -ge 100 ] && ok "ZA2: parsed $_zt PAIRS entries for the zone check (count guard: >= 100)" \
                   || bad "ZA2: only $_zt PAIRS entries parsed — ZA3 would pass vacuously"

_zbad=""
for _z in $ZFOUND; do
  case " $ZDECL " in *" $_z "*) ;; *) _zbad="$_zbad $_z" ;; esac
done
[ -z "$_zbad" ] && ok "ZA3: every derived zone anomaly is declared in sync-to-claude.sh" \
                || bad "ZA3: undeclared zone anomal(ies) —$_zbad"

# ZA4: the reverse. A declaration for an anomaly that no longer exists is a stale waiver, and it
# would keep ZA3 green while describing an arrangement that has been normalised away.
_zstale=""
for _d in $ZDECL; do
  printf '%s\n' "$ZFOUND" | grep -qxF "$_d" || _zstale="$_zstale $_d"
done
[ -z "$_zstale" ] && ok "ZA4: every declared anomaly still exists in PAIRS" \
                  || bad "ZA4: declared but no longer anomalous (stale waiver) —$_zstale"

# ZA5: the flat source of the hook-verify-workflow remap must still be there. This is the half that
# breaks if someone "fixes" the SKILL.md reference to point at a staging path — the deployed
# invocation would then read a file that sync never wrote.
[ -f "$STAGING/plugin/scripts/hook-verify-workflow.sh" ] \
  && ok "ZA5: hook-verify-workflow.sh is still flat in staging/plugin/scripts (ADR-0016/0024)" \
  || bad "ZA5: the flat source is gone — the skills/ remap now deploys nothing"

# =====================================================================================
# DEPLOYED-ONLY REGISTRY (issue #222, ADR-0087). sync-to-claude.sh declares the skills that exist
# in ~/.claude/skills/ and deliberately do NOT belong in staging/ (personal routines, a foreign
# repo symlink, another project's intake front end, book-derived proprietary content). ADR-0077's
# rule — a waiver travels with the file it excuses — cannot apply here: the excused file is absent
# from staging/ by construction, so there is nothing for the waiver to travel with (ADR-0087 §D-
# registry). This section is the CI-runnable half of the two-direction contract: every declared
# name must be genuinely absent from staging/, every reason must clear the 40-char floor, and the
# derivation itself must not collapse to zero.
#
# The needle is built at run time so this file does not match its own explanatory prose (rule 12).
DMARK="deployed""-only"

# Extracted via REDIRECTION into a tmp file, never a pipe into `while read` — a piped while runs in
# a subshell in bash and would silently drop any counter built inside it, exactly the pitfall
# check_pairs/check_complete above already avoid by reading `< "$_file"`.
grep "^# *${DMARK}: " "$SYNC" > "$tmp/deployed-only-decl" 2>/dev/null

# DO1: count guard on the derivation. This is RED right now — sync-to-claude.sh carries no
# `# deployed-only:` lines yet (Task 4 of this feature adds the five). Must stay RED after this
# section is written; Task 4's coder is what turns it GREEN.
_don=$(grep -c "^# *${DMARK}: " "$SYNC" 2>/dev/null || true)
[ -z "$_don" ] && _don=0
[ "$_don" -ge 5 ] && ok "DO1: sync-to-claude.sh declares $_don deployed-only skill(s) (>= 5)" \
                   || bad "DO1: only $_don '${DMARK}:' declaration(s) found in $SYNC — expected >= 5"

# DO2: forward check on the REAL file — no declared name has a matching staging/plugin/skills/
# <name>/SKILL.md (the stale-waiver direction R-05 names). Expected to pass trivially against the
# real registry today (none of the five is vendored, by construction); its value is regression
# protection, not a first RED. DO4 below is what proves this logic actually detects a stale entry —
# without it, DO2 alone is vacuously satisfiable by an empty registry (self-test-2's own lesson,
# applied here).
_do2_bad=""
while IFS= read -r _dline; do
  [ -n "$_dline" ] || continue
  _dname=$(printf '%s\n' "$_dline" | sed "s/^# *${DMARK}: *//" | cut -d' ' -f1)
  [ -n "$_dname" ] || continue
  if [ -f "$STAGING/plugin/skills/$_dname/SKILL.md" ]; then
    _do2_bad="$_do2_bad $_dname"
  fi
done < "$tmp/deployed-only-decl"
[ -z "$_do2_bad" ] && ok "DO2: no declared deployed-only name is vendored in staging/plugin/skills" \
                   || bad "DO2: declared deployed-only but ALSO vendored (stale waiver) —$_do2_bad"

# DO3: every declared reason is >= 40 characters (same floor S3/ADR-0077 T4 use elsewhere).
#
# The original extraction here stripped everything up to the FIRST hyphen-class character via
# `sed 's/^[^—-]*[—-] *//'`, and every one of these skill names (agent-design, daily-close, ...)
# CONTAINS a hyphen. So the sed cut the string at the name's own internal hyphen, not at the
# " — " separator before the reason, and what got measured for length was
# "<tail of the name> — <reason>", not the reason. It could not produce a false FAIL on the five
# real declarations (their genuine reasons are long), so it looked correct — but it does not
# measure a reason, and a long name with a short reason would pass on the name's length alone.
#
# Fixed by extracting via plain bash parameter expansion instead of a hyphen-class sed: strip the
# marker, take the first whitespace-delimited token as the name, remove exactly that name prefix,
# then strip the "—" (em dash) or "-" (hyphen) SEPARATOR specifically — never a character class
# that also matches inside the name. No sed regex-escaping surface, bash 3.2 clean.
do3_reason() {
  # $1 = the full "<name> — <reason>" tail (marker already stripped by the caller).
  _do3r_full="$1"
  _do3r_name=$(printf '%s\n' "$_do3r_full" | cut -d' ' -f1)
  _do3r_rest="${_do3r_full#"$_do3r_name"}"
  while [ "${_do3r_rest#" "}" != "$_do3r_rest" ]; do _do3r_rest="${_do3r_rest#" "}"; done
  case "$_do3r_rest" in
    "—"*) _do3r_rest="${_do3r_rest#"—"}" ;;
    "-"*) _do3r_rest="${_do3r_rest#"-"}" ;;
  esac
  while [ "${_do3r_rest#" "}" != "$_do3r_rest" ]; do _do3r_rest="${_do3r_rest#" "}"; done
  printf '%s' "$_do3r_rest"
}

_do3_bad=""
while IFS= read -r _dline; do
  [ -n "$_dline" ] || continue
  _dfull=$(printf '%s\n' "$_dline" | sed "s/^# *${DMARK}: *//")
  _dname=$(printf '%s\n' "$_dfull" | cut -d' ' -f1)
  _dreason=$(do3_reason "$_dfull")
  _rlen=${#_dreason}
  [ "$_rlen" -lt 40 ] && _do3_bad="$_do3_bad $_dname($_rlen)"
done < "$tmp/deployed-only-decl"
[ -z "$_do3_bad" ] && ok "DO3: every declared reason is >= 40 characters" \
                   || bad "DO3: reason(s) shorter than 40 characters —$_do3_bad"

# DO5 (backward self-test for DO3, same shape as DO4 for DO2): DO3 alone can never be seen
# failing against the real registry — all five reasons are genuinely long, so a still-broken
# extraction and a correct one both report clean. Build a synthetic fixture line whose NAME is
# long (to catch a regression back to "measure the name's tail") and whose REASON is clearly
# under 40 characters, run DO3's exact extraction + length logic against it, and assert it is
# flagged. Text kept free of key-shaped literals and "secret"/"credential"/".env"/".pem" path
# fragments, same constraint DO4's fixture already observes (protect-files.sh / secret-scan.sh).
_do5_fixture="some-extremely-long-descriptive-name — too short"
_do5_reason=$(do3_reason "$_do5_fixture")
_do5_len=${#_do5_reason}
[ "$_do5_reason" = "too short" ] && [ "$_do5_len" -lt 40 ] \
  && ok "DO5: self-test — a long-name/short-reason fixture is flagged (reason='$_do5_reason', len=$_do5_len)" \
  || bad "DO5: self-test — extraction did not isolate the reason as expected (got '$_do5_reason', len=$_do5_len)"

# DO4 (backward self-test, the R-09 evidence for R-05): build a synthetic one-line fixture
# declaring an EXISTING staged skill ("commit") as deployed-only, and run DO2's exact stale-waiver
# logic against the fixture instead of the real file. Without this, DO2 alone never exercises its
# own failure branch — the real registry, by construction, never contains a stale name.
printf '# %s: commit — a synthetic stale waiver planted for this self-test only, not a real entry\n' \
  "$DMARK" > "$tmp/deployed-only-fixture"

_do4_bad=""
while IFS= read -r _dline; do
  [ -n "$_dline" ] || continue
  _dname=$(printf '%s\n' "$_dline" | sed "s/^# *${DMARK}: *//" | cut -d' ' -f1)
  [ -n "$_dname" ] || continue
  if [ -f "$STAGING/plugin/skills/$_dname/SKILL.md" ]; then
    _do4_bad="$_do4_bad $_dname"
  fi
done < "$tmp/deployed-only-fixture"
[ -n "$_do4_bad" ] && ok "DO4: self-test — stale waiver on a real staged skill (commit) is flagged" \
                   || bad "DO4: self-test — a declared name that IS vendored was NOT flagged (the check would pass vacuously)"

# =================================================================================================
# CI — the harness list in .github/workflows/docs-ci.yml, both directions (issue #331, ADR-0113).
#
# THIS FILE'S SUBJECT, ONE LIST OVER. ADR-0043's lesson was that a check asserting "every entry in
# the list resolves to a file" is blind by construction to a file the list omits. `docs-ci.yml`'s
# `shell-tests` job enumerates the harnesses by name, and that enumeration had drifted: FOUR test
# files from the last four merged PRs were absent from it, so four features' assertions ran on the
# author's machine and nowhere else. Nothing reported it, because the omitted direction is exactly
# the one nobody was checking — the omission looked like a full run.
#
# The reverse direction is loud on its own (the job runs under `set -e`, so a name with no file
# exits 127) and is asserted anyway: cheap, and "loud today" is not a property to rely on silently.
#
# A file that genuinely must not run in CI declares it in its own header, one line, and the waiver
# travels with the file rather than sitting in a list here (ADR-0077):
#   # ci-dark-exempt: <reason, >= 40 chars>
#
# NO PLANT DECLARED, AND THIS IS THE REASON RATHER THAN AN OVERSIGHT. `plant-check.sh` mutates an
# isolated copy of `staging/` and `docs/`; `.github/workflows/docs-ci.yml` is in neither, so CI1's
# mechanism cannot be reached by a plant and a sandbox run reads the real workflow file. What CI1
# has instead is LIVE red evidence: on its first run it failed naming conductor-entry-failure-split,
# manifest-entry-state, autopilot-guard-disarm and permission-mode-state — four real harnesses that
# had never run in CI. Live evidence beats a synthetic case built to pass (ADR-0108 §PC1).
CIWF="$STAGING/../.github/workflows/docs-ci.yml"
CI_LIST="$tmp/ci-list"; : >"$CI_LIST"
if [ -f "$CIWF" ]; then
  grep -o 'for t in [^;]*' "$CIWF" | head -1 | sed 's/^for t in //' | tr ' ' '\n' \
    | sed '/^$/d' | sort -u >"$CI_LIST"
fi
_nci=$(grep -c . "$CI_LIST" 2>/dev/null || true); _nci=${_nci:-0}

CI_FILES="$tmp/ci-files"
ls "$STAGING"/plugin/scripts/tests/*.test.sh 2>/dev/null \
  | sed 's|.*/||; s|\.test\.sh$||' | sort -u >"$CI_FILES"
_nf=$(grep -c . "$CI_FILES" 2>/dev/null || true); _nf=${_nf:-0}

# CI0/CI0b — count guards on BOTH denominators. A `for t in` line that stops matching yields an
# empty list, every file then reads as uncovered (loud); an empty FILE glob yields nothing to
# check and reads as full coverage (silent). The second is the dangerous one and is why both are
# guarded rather than just the list.
[ "$_nci" -ge 40 ] && ok "CI0: parsed $_nci harness names out of docs-ci.yml (guard: >= 40)" \
                   || bad "CI0: parsed only $_nci names from $CIWF — the derivation is broken, not clean"
[ "$_nf" -ge 40 ]  && ok "CI0b: found $_nf *.test.sh files under staging (guard: >= 40)" \
                   || bad "CI0b: found only $_nf test files — CI1 would pass vacuously"

# CI1 — every harness runs in CI, or says in its own header why it does not.
_ci_missing=""
while IFS= read -r _t; do
  [ -n "$_t" ] || continue
  grep -qxF "$_t" "$CI_LIST" && continue
  _r=$(grep -m1 '^# ci-dark-exempt:' "$STAGING/plugin/scripts/tests/$_t.test.sh" 2>/dev/null \
       | sed 's/^# ci-dark-exempt:[[:space:]]*//')
  [ "${#_r}" -ge 40 ] && continue
  _ci_missing="$_ci_missing $_t"
done < "$CI_FILES"
[ -z "$_ci_missing" ] && ok "CI1: every staged harness is in the docs-ci.yml shell-tests list" \
                      || bad "CI1: harness(es) that never run in CI and declare no reason —$_ci_missing"

# CI2 — the reverse: a listed name with no file. `set -e` makes this exit 127 in CI, so this
# assertion buys an earlier and clearer message, not a new guarantee.
_ci_stale=""
while IFS= read -r _t; do
  [ -n "$_t" ] || continue
  [ -f "$STAGING/plugin/scripts/tests/$_t.test.sh" ] || _ci_stale="$_ci_stale $_t"
done < "$CI_LIST"
[ -z "$_ci_stale" ] && ok "CI2: every name in the docs-ci.yml list resolves to a harness file" \
                    || bad "CI2: listed but absent from staging —$_ci_stale"

printf '\nPASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
