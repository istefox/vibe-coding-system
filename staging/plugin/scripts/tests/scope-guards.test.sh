#!/bin/bash
# scope-guards test harness (ADR-0030) -- three findings from the concept-to-code audit
# (SPEC.md / issue #34). Three lettered sections:
#   Section A (Finding 2.5, P2, ~6 tests) -- autopilot-build/SKILL.md Check 1's scope guard was
#     inverted (compared containment in the wrong direction) and not slash-anchored: a session
#     opened at a PARENT of project_root (allowed by ADR-0020) aborted; a session opened INSIDE
#     project_root, or at an unrelated sibling directory sharing a name prefix, both wrongly
#     passed. Fixed to a `case`-based, quoted, slash-anchored containment test.
#   Section B (Finding 3.10, ~6 tests) -- project-conductor/SKILL.md's three manifest-lookup call
#     sites globbed by bare substring (*<topic-slug>*.manifest.yml), so a feature slug that is a
#     hyphen-prefix of another feature's slug (e.g. "export" / "export-csv") could bind to the
#     wrong manifest and silently mark a feature complete, or auto-resume the wrong chain, without
#     it ever having run. Fixed with a naming-convention-anchored glob plus an exact-match check
#     against the candidate manifest's own topic: field.
#   Section C (Finding 3.11, ~6 tests) -- autopilot/SKILL.md pre-flight check 6 named a
#     "global smoke-test record written by hook-verify-workflow.sh" that does not exist (verified:
#     that script is deliberately read-only and stateless -- ADR-0029 Section 1 "Gap flagged for
#     issue #34"; hook-verify-workflow.sh internals are out of scope for issue #34 -- SPEC.md
#     "Out"). Fixed with a concrete, roadmap-wide hook_verified validity check over whatever
#     manifests currently exist, and an explicit, non-blocking zero-manifest branch for Phase P's
#     pre-any-feature pre-flight moment (ADR-0030 Section 2.3/3.3).
# Zero $HOME dependency: runs identically in CI (ubuntu-latest, no ~/.claude) and locally.
# Never point any variable at $HOME/.claude/... -- that is the deployed copy, out of scope.
# Bash 3.2 clean. Run: bash scope-guards.test.sh
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)              # staging/plugin/scripts
STAGING=$(cd "$SCRIPTS/../.." && pwd)                    # staging/
AB_SKILL="$STAGING/plugin/skills/autopilot-build/SKILL.md"
PC_SKILL="$STAGING/plugin/skills/project-conductor/SKILL.md"
NA_SKILL="$STAGING/plugin/skills/autopilot/SKILL.md"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# =====================================================================================
# Section A -- Finding 2.5 (P2): autopilot-build Check 1 scope guard
# =====================================================================================

# Anchored on the fence's own `<!-- fence-contract: … -->` marker, not on the heading above it
# (issue #206). A heading rewrite used to empty this extraction, and an empty script exits 0 — so
# A3/A4 went GREEN and only A5/A6 failed, with messages that blamed the guard. Measured: rewording
# the heading took this file from PASS=29 FAIL=0 to PASS=27 FAIL=2, reading as two broken checks
# rather than as an extraction that found nothing. The marker travels with the fence.
extract_check1() {
  awk '
    index($0, "fence-contract: autopilot-build-check-1 -->") { grab=1; next }
    grab && /^```bash/ { infence=1; next }
    grab && infence && /^```/ { exit }
    grab && infence { print }
  ' "$AB_SKILL"
}

# run_check1 <manifest-path> -- substitutes <manifest-path>, writes the result to a temp script,
# and appends a trailing `exit 0` OUTSIDE the extracted text (harness-only normalization: the
# extracted snippet's own last-executed statement is ambiguous on the pass path -- an `if` guard
# whose condition is false has exit status 1 even though no SCOPE ERROR fires and no `exit 1`
# runs; the production contract does not need its own trailing exit 0, since the real caller reads
# printed output, not a raw $?, exactly as the ORIGINAL, buggy code already required -- see
# ADR-0030 Consequences/Negative and this plan's Risk register). The abort path's own internal
# `exit 1` still fires first and this appended line is never reached in that case.
# Caller must `cd` to the desired CWD before calling.
#
# An empty extraction is a HARD FAILURE here, not an empty script (issue #206). Without this, the
# appended `exit 0` below makes every positive assertion in this section pass and only the abort
# ones fail -- the reader is told the guard is broken when the guard was never read. Exit 97 is
# outside the fence's own contract (0 pass, 1 abort) so no assertion can mistake it for either.
run_check1() {
  RAW="$(extract_check1)"
  if [ -z "$RAW" ]; then
    echo "EXTRACTION FAILED: no fence-contract: autopilot-build-check-1 marker in $AB_SKILL" >&2
    return 97
  fi
  CMD="${RAW//<manifest-path>/$1}"
  printf '%s\nexit 0\n' "$CMD" > "$TMP/check1-cmd.sh"
  bash "$TMP/check1-cmd.sh"
}

# A1 (static, genuine RED now): the old inverted, unquoted, unanchored containment test is gone.
if grep -qF '${cwd_n##$project_root_n}' "$AB_SKILL"; then
  bad "A1: old inverted, unquoted containment test is still present in Check 1"
else
  ok "A1: old inverted, unquoted containment test is gone from Check 1"
fi

# A2 (static, genuine RED now): the new, quoted, slash-anchored case pattern is present.
if grep -qF '"$cwd_n"/*)' "$AB_SKILL"; then
  ok "A2: new quoted, slash-anchored containment test is present in Check 1"
else
  bad "A2: new quoted, slash-anchored containment test should be present in Check 1"
fi

# Fixture: $TMP/a/proj (the project), $TMP/a/proj/sub (a child), $TMP/a/proj-backup (a sibling
# sharing a hyphenated name prefix). Resolved through `cd && pwd -P` so the fixture manifest and
# the script's own `pwd -P` agree (macOS mktemp -d gives /var/folders/... which pwd -P resolves to
# /private/var/folders/... -- same gotcha stop-gate.sh/triage-state.sh already document).
mkdir -p "$TMP/a/proj/sub" "$TMP/a/proj-backup"
PROJ_REAL=$(cd "$TMP/a/proj" && pwd -P)
A_MANIFEST="$TMP/a/fixture.manifest.yml"
printf 'project_root: "%s"\n' "$PROJ_REAL" > "$A_MANIFEST"

# A3 (dynamic, non-regression companion, already passing today): exact match, CWD == project_root
# => PASS (exit 0). Already true today too (the old code's first `!=` check already short-circuits
# this one case to "no abort") -- pinned here so the rewrite cannot silently break it.
( cd "$PROJ_REAL" && run_check1 "$A_MANIFEST" ) >/dev/null 2>&1
[ "$?" -eq 0 ] && ok "A3: CWD == project_root => PASS (exit 0)" || bad "A3: CWD == project_root should PASS"

# A4 (dynamic, genuine RED): parent CWD, project_root beneath it => PASS (exit 0). ADR-0020 D3 #1
# explicitly allows this; today's bug aborts it.
( cd "$TMP/a" && run_check1 "$A_MANIFEST" ) >/dev/null 2>&1
[ "$?" -eq 0 ] && ok "A4: parent CWD, project_root beneath it => PASS (exit 0)" || bad "A4: parent CWD should PASS"

# A5 (dynamic, genuine RED): child CWD, project_root above it => ABORT (exit 1). Today's bug passes
# this silently.
( cd "$PROJ_REAL/sub" && run_check1 "$A_MANIFEST" ) >/dev/null 2>&1
[ "$?" -eq 1 ] && ok "A5: child CWD, project_root above it => ABORT (exit 1)" || bad "A5: child CWD should ABORT"

# A6 (dynamic, genuine RED): sibling directory sharing a hyphenated name prefix => ABORT (exit 1).
# Today's bug passes this silently (unanchored prefix strip).
( cd "$TMP/a/proj-backup" && run_check1 "$A_MANIFEST" ) >/dev/null 2>&1
[ "$?" -eq 1 ] && ok "A6: sibling 'proj-backup' => ABORT (exit 1)" || bad "A6: sibling directory should ABORT"

# =====================================================================================
# Section B -- Finding 3.10: project-conductor manifest binding
# =====================================================================================

extract_conductor_lookup() {
  awk '
    /^### Step 5 — Evaluate chain outcome/ { grab=1 }
    grab && /^```bash/ { infence=1; next }
    grab && infence && /^```/ { exit }
    grab && infence { print }
  ' "$PC_SKILL"
}

# ADR-0133 (issue #394) wrapper-aware bypass. Once this lookup (one of the three unmarked
# project-conductor `_manifest` glob sites the ADR's outbound-direction table names by line) is
# wrapped, its body runs inside a `bash <<'FENCE_BASH' … FENCE_BASH` here-document — a
# SUBPROCESS — so `_manifest`, bound INSIDE the fence and read only by run_conductor_lookup's own
# appended `printf` below, would die at the closing terminator and read back empty, exactly
# human-gate-coverage.test.sh's HIB1-HIB4 before their own fix. Same mechanism as that file's and
# fence-contract-coverage.test.sh's `unwrap_body`: returns the here-document's INNER body when the
# wrapper is present, and the input UNCHANGED otherwise, so this file keeps working whether or not
# the fence has been wrapped yet.
UNWRAP_AWK="$TMP/unwrap.awk"
cat >"$UNWRAP_AWK" <<'UNWRAPEOF'
BEGIN { mode = "before"; nb = 0 }
{
  if (mode == "before") {
    if ($0 == "bash <<'FENCE_BASH'") { mode = "wrap"; next }
    nb++; before[nb] = $0
    next
  }
  if (mode == "wrap") {
    if ($0 == "FENCE_BASH") { mode = "after"; next }
    print
    next
  }
}
END {
  if (mode == "before") { for (i = 1; i <= nb; i++) print before[i] }
}
UNWRAPEOF
unwrap_body() { awk -f "$UNWRAP_AWK" "$1"; }

# run_conductor_lookup <root> <slug> -- runs the extracted lookup with `_root` preset to <root> and
# <topic-slug> substituted with <slug>, then prints the resulting $_manifest value on stdout (empty
# if nothing bound). Test fixture roots are always plain mktemp -d paths (no spaces/quote
# characters), so a simple double-quoted assignment is sufficient -- no shell-escaping helper
# needed for this harness's own controlled inputs.
run_conductor_lookup() {
  RAW="$(extract_conductor_lookup)"
  CMD="${RAW//<topic-slug>/$2}"
  printf '%s\n' "$CMD" > "$TMP/conductor-cmd-outer.sh"
  {
    printf '_root="%s"\n' "$1"
    unwrap_body "$TMP/conductor-cmd-outer.sh"
    printf 'printf "%%s" "$_manifest"\n'
  } > "$TMP/conductor-cmd.sh"
  bash "$TMP/conductor-cmd.sh"
}

# B1 (static, genuine RED now): the old bare-substring glob is gone from all 3 call sites.
_old_count=$(grep -cF 'ls -t "$_root"/docs/manifests/*<topic-slug>*.manifest.yml' "$PC_SKILL")
[ "$_old_count" -eq 0 ] && ok "B1: old bare-substring glob is gone from all call sites" \
  || bad "B1: old bare-substring glob still present at $_old_count site(s)"

# B2 (static, genuine RED now): the new anchored glob is present at all 3 call sites.
_new_count=$(grep -cF '"$_root"/docs/manifests/????-??-??-"$_slug".manifest.yml' "$PC_SKILL")
[ "$_new_count" -eq 3 ] && ok "B2: anchored glob is present at all 3 call sites" \
  || bad "B2: anchored glob expected at 3 call sites, found $_new_count"

# B3 (static, genuine RED now): the topic-field verification is present at all 3 call sites.
_verify_count=$(grep -cF "grep '^topic:' \"\$_cand\"" "$PC_SKILL")
[ "$_verify_count" -eq 3 ] && ok "B3: topic-field verification is present at all 3 call sites" \
  || bad "B3: topic-field verification expected at 3 call sites, found $_verify_count"

# Fixture: two manifests in the same docs/manifests/ dir -- "export" and "export-csv" -- the exact
# collision SPEC.md finding 3.10 names.
mkdir -p "$TMP/b/root/docs/manifests"
B_ROOT="$TMP/b/root"
printf 'topic: "export"\nproject_root: "%s"\n' "$B_ROOT" > "$B_ROOT/docs/manifests/2026-07-01-export.manifest.yml"
printf 'topic: "export-csv"\nproject_root: "%s"\n' "$B_ROOT" > "$B_ROOT/docs/manifests/2026-07-02-export-csv.manifest.yml"

# B4 (dynamic, genuine RED): slug "export" must bind to its own manifest, never export-csv's.
B4_OUT=$(run_conductor_lookup "$B_ROOT" "export")
case "$B4_OUT" in
  *export-csv.manifest.yml) bad "B4: slug 'export' wrongly bound to the export-csv manifest" ;;
  *export.manifest.yml) ok "B4: slug 'export' binds to its own manifest, not export-csv" ;;
  *) bad "B4: slug 'export' resolved to unexpected value: $B4_OUT" ;;
esac

# B5 (dynamic, non-regression companion): slug "export-csv" must still bind to its own manifest
# (proves the fix does not just make everything fail closed).
B5_OUT=$(run_conductor_lookup "$B_ROOT" "export-csv")
case "$B5_OUT" in
  *export-csv.manifest.yml) ok "B5: slug 'export-csv' still binds to its own manifest" ;;
  *) bad "B5: slug 'export-csv' should bind to its own manifest (got: $B5_OUT)" ;;
esac

# B6 (dynamic, genuine RED): a manifest whose filename matches the anchored glob but whose internal
# topic: field disagrees (simulated corruption / hand-edit) must NOT bind.
mkdir -p "$TMP/b/root2/docs/manifests"
B_ROOT2="$TMP/b/root2"
printf 'topic: "something-else"\nproject_root: "%s"\n' "$B_ROOT2" > "$B_ROOT2/docs/manifests/2026-07-01-drift.manifest.yml"
B6_OUT=$(run_conductor_lookup "$B_ROOT2" "drift")
[ -z "$B6_OUT" ] && ok "B6: filename-glob match with disagreeing internal topic: field does not bind" \
  || bad "B6: should not bind when internal topic: field disagrees (got: $B6_OUT)"

# =====================================================================================
# Section C -- Finding 3.11: autopilot check 6
# =====================================================================================

extract_check6() {
  awk '
    index($0, "fence-contract: autopilot-check-6 -->") { grab=1; next }
    grab && /^[[:space:]]*```bash/ { infence=1; next }
    grab && infence && /^[[:space:]]*```/ { exit }
    grab && infence { print }
  ' "$NA_SKILL"
}

# run_check6 <root> -- check 6's own contract reads $PWD directly (no <placeholder> to substitute),
# so the harness only needs to `cd` there before executing the extracted body. Unlike run_check1,
# check 6's own guard is phrased as "assert the good condition directly"
# ([ "$_bad" -eq 0 ] || exit 1), which already exits 0 cleanly on its own on the pass path -- no
# trailing-exit-0 normalization needed here (see this plan's Risk register for why Section A does
# need it and Section C does not).
run_check6() {
  # The fence resolves manifest-field-state.sh through CLAUDE_PLUGIN_ROOT first (issue #195).
  # staging/plugin IS that layout, so this is the documented resolution path, not a test seam:
  # in CI there is no $HOME/.claude and the second tier would leave the gate failing closed.
  _x6="$(extract_check6)"
  if [ -z "$_x6" ]; then
    echo "EXTRACTION FAILED: no fence-contract: autopilot-check-6 marker in $NA_SKILL" >&2
    return 97
  fi
  ( cd "$1" && CLAUDE_PLUGIN_ROOT="$STAGING/plugin" bash -c "$_x6" )
}

# C1 (static, genuine RED now): check 6 gains a runnable bash fence (today it is prose-only).
_c6_fence=$(awk '/^6\. \*\*hook_verified known/{grab=1;next} grab && /^[[:space:]]*```bash/{print "yes"; exit} grab && /^7\. /{exit}' "$NA_SKILL")
[ "$_c6_fence" = "yes" ] && ok "C1: check 6 has a runnable bash fence" || bad "C1: check 6 should have a runnable bash fence"

# C2 (static, genuine RED now): the explicit zero-manifest, non-blocking rule text is present.
grep -q 'no manifests exist yet' "$NA_SKILL" \
  && ok "C2: check 6 documents the explicit zero-manifest, non-blocking rule" \
  || bad "C2: check 6 should document the explicit zero-manifest, non-blocking rule"

# C3 (dynamic, genuine RED): zero manifests => PASS (exit 0), non-blocking.
mkdir -p "$TMP/c/zero/docs/manifests"
run_check6 "$TMP/c/zero" >/dev/null 2>&1
[ "$?" -eq 0 ] && ok "C3: zero manifests => PASS (exit 0), non-blocking" || bad "C3: zero manifests should PASS"

# C4 (dynamic, non-regression companion once Section C's fix lands): one manifest,
# hook_verified: false => PASS.
mkdir -p "$TMP/c/false/docs/manifests"
printf 'topic: "x"\nhook_verified: false\n' > "$TMP/c/false/docs/manifests/2026-07-01-x.manifest.yml"
run_check6 "$TMP/c/false" >/dev/null 2>&1
[ "$?" -eq 0 ] && ok "C4: hook_verified: false => PASS (exit 0)" || bad "C4: hook_verified: false should PASS"

# C5 (dynamic, non-regression companion once Section C's fix lands): one manifest,
# hook_verified: true => PASS.
mkdir -p "$TMP/c/true/docs/manifests"
printf 'topic: "x"\nhook_verified: true\n' > "$TMP/c/true/docs/manifests/2026-07-01-x.manifest.yml"
run_check6 "$TMP/c/true" >/dev/null 2>&1
[ "$?" -eq 0 ] && ok "C5: hook_verified: true => PASS (exit 0)" || bad "C5: hook_verified: true should PASS"

# C6 (dynamic): a manifest with no hook_verified and no current_step => ABORT (exit 1).
# The fixture and the expectation are unchanged from the original C6; only the LABEL is corrected.
# It read "absent/corrupted", and issue #123 is precisely that those are two different things: this
# fixture is a manifest still in flight, where an absent field means nobody knows the dispatch
# mode. C7 below covers the case the old label wrongly swept in with it.
mkdir -p "$TMP/c/null/docs/manifests"
printf 'topic: "x"\n' > "$TMP/c/null/docs/manifests/2026-07-01-x.manifest.yml"
run_check6 "$TMP/c/null" >/dev/null 2>&1
[ "$?" -eq 1 ] && ok "C6: hook_verified absent on an IN-FLIGHT manifest => ABORT (exit 1)" \
               || bad "C6: absent hook_verified on an in-flight manifest should ABORT"

# =====================================================================================
# C7-C13 -- issue #123. Check 6 iterated EVERY manifest in docs/manifests/ and aborted the whole
# roadmap on any hook_verified that was not true/false. Two long-completed chains
# (2026-05-23-clean-public-repo-anonymize, 2026-05-29-dynamic-workflows-step5) hit it. Neither was
# corrupted: both PREDATE the field, which ADR-0016 added to manifest-init.sh afterwards. The
# diagnostic said "corrupted or hand-edited", which is actively misleading, and the abort was
# roadmap-wide for two chains unrelated to the roadmap being launched.
#
# A completed chain's dispatch mode cannot affect a future run, so absence there is the documented
# default (false) rather than an error. Absence on a chain still in flight is still an abort (C6).

# C7: THE ISSUE. Absent field on a COMPLETED manifest => PASS.
mkdir -p "$TMP/c/oldschema/docs/manifests"
printf 'topic: "x"\nschema_version: "1.1"\ncurrent_step: "completed"\n' \
  > "$TMP/c/oldschema/docs/manifests/2026-05-23-x.manifest.yml"
run_check6 "$TMP/c/oldschema" >/dev/null 2>&1
[ "$?" -eq 0 ] && ok "C7: absent hook_verified on a COMPLETED manifest => PASS (predates the field)" \
               || bad "C7: a pre-schema completed manifest still aborts the roadmap (#123)"

# C8: the corruption the check was written for is NOT weakened by C7. A present-but-invalid value
# aborts even on a completed manifest — that is a value someone wrote, not a value nobody wrote.
mkdir -p "$TMP/c/maybe/docs/manifests"
printf 'topic: "x"\ncurrent_step: "completed"\nhook_verified: maybe\n' \
  > "$TMP/c/maybe/docs/manifests/2026-07-01-x.manifest.yml"
run_check6 "$TMP/c/maybe" >/dev/null 2>&1
[ "$?" -eq 1 ] && ok "C8: present-but-invalid value => ABORT even when completed" \
               || bad "C8: an invalid hook_verified value stopped aborting — C7 weakened the check"

# C9: the message must name the actual value. "has hook_verified=None" was the original defect's
# whole visible surface: it told the operator nothing about which of the two causes it was.
_c9=$(run_check6 "$TMP/c/maybe" 2>&1)
printf '%s' "$_c9" | grep -q 'maybe' \
  && ok "C9: the abort names the actual invalid value" \
  || bad "C9: the abort should quote the value it rejected — got: $_c9"

# C10: the two causes must read differently. An operator who sees "corrupted or hand-edited" for a
# manifest that is merely old goes looking for damage that is not there.
_c10=$(run_check6 "$TMP/c/null" 2>&1)
if printf '%s' "$_c10" | grep -qi 'in flight\|not completed\|still running'; then
  ok "C10: absent-on-in-flight is diagnosed as its own case, not as corruption"
else
  bad "C10: absent and invalid still share one message — got: $_c10"
fi

# C11: a manifest the check cannot READ is a third state. An unparseable file produced an empty
# value and was reported as an invalid one — the check did not run, which is not the same as
# finding something wrong (the distinction secret-scan.sh, spec-coverage.sh and plan-tasks.sh all
# make with a dedicated exit code).
mkdir -p "$TMP/c/broken/docs/manifests"
printf 'topic: "x\n  bad: [unclosed\n' > "$TMP/c/broken/docs/manifests/2026-07-01-x.manifest.yml"
run_check6 "$TMP/c/broken" >/dev/null 2>&1
_rc=$?
_c11=$(run_check6 "$TMP/c/broken" 2>&1)
if [ "$_rc" -eq 1 ] && printf '%s' "$_c11" | grep -qi 'could not be read\|unreadable\|did not run'; then
  ok "C11: an unparseable manifest aborts as did-not-run, distinct from an invalid value"
else
  bad "C11: unparseable manifest not distinguished (rc=$_rc) — got: $_c11"
fi

# C12: leniency must not mask a bad neighbour. One pre-schema completed manifest beside one
# invalid manifest still aborts — the loop must keep scanning past the tolerated one.
mkdir -p "$TMP/c/mixed/docs/manifests"
printf 'topic: "a"\ncurrent_step: "completed"\n' > "$TMP/c/mixed/docs/manifests/2026-05-23-a.manifest.yml"
printf 'topic: "b"\ncurrent_step: "completed"\nhook_verified: maybe\n' > "$TMP/c/mixed/docs/manifests/2026-07-01-b.manifest.yml"
run_check6 "$TMP/c/mixed" >/dev/null 2>&1
[ "$?" -eq 1 ] && ok "C12: a tolerated pre-schema manifest does not mask an invalid one" \
               || bad "C12: the loop stopped short — an invalid manifest was missed"

# C13: the real corpus. Every manifest this repository actually carries must pass, or the check
# would abort a roadmap here. This is the population the issue was found in — asserted against the
# files rather than against a fixture, with a count guard so an empty glob cannot pass vacuously
# (the pairs-completeness self-test lesson).
_repo_root=$(cd "$STAGING/.." && pwd)
_n=$(ls "$_repo_root"/docs/manifests/*.manifest.yml 2>/dev/null | wc -l | tr -d ' ')
if [ "$_n" -ge 30 ]; then
  # Through run_check6, not a second inline invocation: this had its own copy of the runner and
  # so missed the CLAUDE_PLUGIN_ROOT binding when the fence gained a helper dependency, failing
  # for a reason that had nothing to do with the manifests it exists to check.
  run_check6 "$_repo_root" >/dev/null 2>&1
  [ "$?" -eq 0 ] && ok "C13: all $_n manifests in this repository pass check 6" \
                 || bad "C13: check 6 aborts on this repository's own manifests"
else
  bad "C13: expected >= 30 manifests in docs/manifests/, found $_n — C13 would pass vacuously"
fi

# =====================================================================================
# Section D -- issue #123, sibling call site: autopilot-build check 7
# =====================================================================================
# The same field read the same brittle way, one skill over, with the MIRROR defect. Check 7 reads
# a single manifest — the one about to be built, which is by definition not completed — so absence
# should abort and does. But its test is `[ "$hv" = "None" ] || [ -z "$hv" ]`, so any value that is
# neither of those PASSES: `hook_verified: maybe` sails through and the run then branches on it.
# Autopilot check 6 aborted on too much; this aborts on too little. Same field, same one-liner,
# opposite failure — which is why #123's audit had to look at both.

extract_check7() {
  awk '
    index($0, "fence-contract: autopilot-build-check-7 -->") { grab=1; next }
    grab && /^```bash/ { infence=1; next }
    grab && infence && /^```/ { exit }
    grab && infence { print }
  ' "$AB_SKILL"
}
# run_check7 <manifest-file> — check 7 reads $manifest, so bind it and append a trailing exit 0
# outside the extracted text, for the same reason run_check1 does.
run_check7() {
  _x7="$(extract_check7)"
  if [ -z "$_x7" ]; then
    echo "EXTRACTION FAILED: no fence-contract: autopilot-build-check-7 marker in $AB_SKILL" >&2
    return 97
  fi
  printf 'manifest=%s\n%s\nexit 0\n' "$1" "$_x7" > "$TMP/check7-cmd.sh"
  CLAUDE_PLUGIN_ROOT="$STAGING/plugin" bash "$TMP/check7-cmd.sh"
}

mkdir -p "$TMP/d"
printf 'topic: "x"\nhook_verified: false\n' > "$TMP/d/ok.manifest.yml"
printf 'topic: "x"\n'                        > "$TMP/d/absent.manifest.yml"
printf 'topic: "x"\nhook_verified: maybe\n'  > "$TMP/d/maybe.manifest.yml"

run_check7 "$TMP/d/ok.manifest.yml" >/dev/null 2>&1
[ "$?" -eq 0 ] && ok "D1: check 7 passes a valid hook_verified" \
               || bad "D1: check 7 rejected a valid manifest"

run_check7 "$TMP/d/absent.manifest.yml" >/dev/null 2>&1
[ "$?" -eq 1 ] && ok "D2: check 7 still aborts on an absent field (the manifest is in flight)" \
               || bad "D2: check 7 stopped aborting on an absent field"

run_check7 "$TMP/d/maybe.manifest.yml" >/dev/null 2>&1
[ "$?" -eq 1 ] && ok "D3: check 7 aborts on a present-but-invalid value" \
               || bad "D3: check 7 ACCEPTS an invalid hook_verified value — the run branches on garbage"

_d4=$(run_check7 "$TMP/d/maybe.manifest.yml" 2>&1)
printf '%s' "$_d4" | grep -q 'maybe' \
  && ok "D4: check 7's abort names the value it rejected" \
  || bad "D4: check 7's abort should quote the rejected value — got: $_d4"

# Z1: assertion-count FLOOR. The hazard issue #206 measured is not a quiet pass, it is a shrunken
# suite: an extraction that finds nothing removes its dependent assertions from the run, and
# "PASS=27 FAIL=2" reads as two broken checks rather than as checks that no longer exist. A floor
# catches that without needing a bump on every added assertion.
_TOTAL=$((PASS + FAIL))
[ "$_TOTAL" -ge 29 ] \
  && ok "Z1: $_TOTAL assertions ran (floor 29) — none silently vanished" \
  || bad "Z1: only $_TOTAL assertions ran, floor 29 — assertions disappeared, they did not fail"

printf '\nPASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
