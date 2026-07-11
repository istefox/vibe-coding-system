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
#   Section C (Finding 3.11, ~6 tests) -- nightly-autopilot/SKILL.md pre-flight check 6 named a
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
NA_SKILL="$STAGING/plugin/skills/nightly-autopilot/SKILL.md"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# =====================================================================================
# Section A -- Finding 2.5 (P2): autopilot-build Check 1 scope guard
# =====================================================================================

extract_check1() {
  awk '
    /^\*\*Check 1 / { grab=1; next }
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
run_check1() {
  RAW="$(extract_check1)"
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

# run_conductor_lookup <root> <slug> -- runs the extracted lookup with `_root` preset to <root> and
# <topic-slug> substituted with <slug>, then prints the resulting $_manifest value on stdout (empty
# if nothing bound). Test fixture roots are always plain mktemp -d paths (no spaces/quote
# characters), so a simple double-quoted assignment is sufficient -- no shell-escaping helper
# needed for this harness's own controlled inputs.
run_conductor_lookup() {
  RAW="$(extract_conductor_lookup)"
  CMD="${RAW//<topic-slug>/$2}"
  {
    printf '_root="%s"\n' "$1"
    printf '%s\n' "$CMD"
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
# Section C -- Finding 3.11: nightly-autopilot check 6
# =====================================================================================

extract_check6() {
  awk '
    /^6\. \*\*hook_verified known/ { grab=1; next }
    grab && /^7\. / { exit }
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
  ( cd "$1" && bash -c "$(extract_check6)" )
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

# C6 (dynamic, genuine RED): one manifest, hook_verified field absent/corrupted => ABORT (exit 1).
mkdir -p "$TMP/c/null/docs/manifests"
printf 'topic: "x"\n' > "$TMP/c/null/docs/manifests/2026-07-01-x.manifest.yml"
run_check6 "$TMP/c/null" >/dev/null 2>&1
[ "$?" -eq 1 ] && ok "C6: hook_verified absent/corrupted => ABORT (exit 1)" || bad "C6: corrupted hook_verified should ABORT"

printf '\nPASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
