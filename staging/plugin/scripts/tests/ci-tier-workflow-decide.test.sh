#!/bin/bash
# ci-tier-workflow-decide.test.sh — offline, hermetic, no network. Bash 3.2 clean.
# Run: bash ci-tier-workflow-decide.test.sh
#
# VCS-053 / ADR-0180 Correction (2026-08-30). ci-tier.test.sh's SKF0-SKF3b already execute
# commit/SKILL.md's Step 3.7 fence (the trailer-WRITING half). Nothing anywhere executed the
# workflow's own "Decide CI tier" step body (the trailer-READING half) — a correct-looking bash
# block embedded in YAML, never run outside a real GitHub Actions job. That gap is exactly how
# VCS-053 shipped: HEAD^2 silently fails to resolve under the default shallow checkout on
# pull_request events, so REQUESTED was always empty and every PR ran at tier `full` regardless
# of its `CI: <tier>` trailer, undetected until read directly off live job logs.
#
# This harness extracts the actual `run:` body of the `Decide CI tier` step from the real call
# sites (docs-ci.yml's plant-shard and shell-tests jobs — never a copy typed into this file) and
# EXECUTES it in an isolated git sandbox that reproduces the real failure shape: a shallow clone
# checked out at a synthetic merge commit, with the real PR head commit reachable only by absolute
# SHA (rule 16 — an instruction is not an enforcement).
#
# ADR-0193 Correction (2026-09-06): a third call site, ci.yml's `ci` job, existed until this repo's
# own ci.yml was deleted as the duplicate harness runner (rule 14 — this note records the change
# forward rather than rewriting the paragraph above). CTW2's push-event case is now checking a path
# that Phase 1 of ADR-0193 also made dead in production: docs-ci.yml's plant-shard and shell-tests
# jobs both carry `if: ... && github.event_name != 'push'`, so their own "Decide CI tier" step no
# longer runs on a real push either. It stays asserted here because the step body is a portable
# bash script this harness extracts and can run standalone regardless of the job's `if:` — proving
# the trailer-read logic itself still behaves correctly on a push event costs nothing, and dropping
# it would leave a silent gap if a future job ever re-enables running this step on push.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
REPO=$(cd "$STAGING/.." && pwd)
CT="$SCRIPTS/ci-tier.sh"
DOCSCI="$REPO/.github/workflows/docs-ci.yml"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# ==================================================================================================
# Extraction: job body (plant-registry-parallel.test.sh's own _yaml_job_body pattern) -> step body
# (bounded by the next "- name:" at the same 6-space indent) -> the "run: |" block, dedented by
# whatever indent its first line actually uses (never a hardcoded column count).
# ==================================================================================================
_yaml_job_body() {   # <file> <job-key>
  awk -v job="  $2:" '
    $0 == job {f=1; next}
    f && /^  [A-Za-z0-9_-]+:$/ {f=0}
    f {print}
  ' "$1"
}
_yaml_step_body() {  # stdin=job body, $1=step name substring
  awk -v marker="- name: $1" '
    index($0, marker) {f=1; next}
    f && /^      - name:/ {exit}
    f {print}
  '
}
_yaml_run_block() {  # stdin=step body — a YAML block scalar ends at the first non-blank line
                      # indented LESS than its own first line (the next key/step/comment at the
                      # step's own indent level), never at a fixed "next - name:" marker.
  awk '
    match($0, /^[ ]*run: \|/) {f=1; next}
    f && NF==0 {print ""; next}
    f {
      match($0, /^ */)
      if (!indent_set) { indent=RLENGTH; indent_set=1 }
      if (RLENGTH < indent) exit
      print substr($0, indent+1)
    }
  '
}
extract_decide_body() {  # <file> <job-key> -> prints the dedented run: body on stdout
  _yaml_job_body "$1" "$2" | _yaml_step_body "Decide CI tier" | _yaml_run_block
}

# ==================================================================================================
# CTW0. Extraction sanity: every call site must yield a non-empty body that parses as bash, and
# must reference $PR_HEAD_SHA in the trailer-read branch — never HEAD^2 (VCS-053's bug).
# ==================================================================================================
SITES="$DOCSCI:plant-shard:docs-ci.yml/plant-shard $DOCSCI:shell-tests:docs-ci.yml/shell-tests"

# CTW-SITES: count guard on the site list itself (rule 7) — ci.yml's `ci` job was a third site
# until ADR-0193 deleted the file; a SITES derivation that silently collapsed further (e.g. a typo
# dropping shell-tests too) would make every loop below run zero times and read as a clean pass.
_nsites=$(printf '%s\n' $SITES | wc -l | tr -d ' ')
[ "$_nsites" -eq 2 ] && ok "CTW-SITES: exactly 2 Decide-CI-tier call sites (docs-ci.yml's plant-shard, shell-tests — ci.yml's removed by ADR-0193)" \
                     || bad "CTW-SITES: expected exactly 2 call sites, found $_nsites — every CTW assertion below would run on the wrong set"

_site_bodies_ok=1
for _site in $SITES; do
  _file=${_site%%:*}; _rest=${_site#*:}; _job=${_rest%%:*}; _label=${_rest#*:}
  _body=$(extract_decide_body "$_file" "$_job")
  _bfile="$TMP/body-$(printf '%s' "$_job" | tr -c 'A-Za-z0-9' '_').sh"
  printf '%s\n' "$_body" >"$_bfile"
  if [ -z "$_body" ]; then
    bad "CTW0: extracted an empty Decide-CI-tier body from $_label — every assertion below for this site is meaningless"
    _site_bodies_ok=0
    continue
  fi
  bash -n "$_bfile" 2>/dev/null || { bad "CTW0: extracted body from $_label does not parse as bash"; _site_bodies_ok=0; }
  printf '%s\n' "$_body" | grep -v '^[[:space:]]*#' | grep -q 'HEAD\^2' \
    && { bad "CTW0 (VCS-053 regression): $_label's executable code still reads the trailer via HEAD^2 — the exact bug (a comment mentioning it, e.g. VCS-053's own history note, does not count)"; _site_bodies_ok=0; }
  printf '%s' "$_body" | grep -q 'PR_HEAD_SHA' \
    || { bad "CTW0: $_label's trailer-read branch never references \$PR_HEAD_SHA"; _site_bodies_ok=0; }
done
[ "$_site_bodies_ok" -eq 1 ] && ok "CTW0: both Decide-CI-tier bodies extracted non-empty, parse as bash, and read the trailer via \$PR_HEAD_SHA (never HEAD^2)"

# ==================================================================================================
# Sandbox fixtures. A bare "origin", a base commit, a divergent head commit carrying a real
# `CI: docs` trailer, and — for the pull_request cases — a synthetic merge commit pushed under its
# own ref and checked out --depth 1, so `HEAD^2` is genuinely unresolvable in the fixture exactly as
# it is on a real GitHub Actions shallow checkout (a plain bare-repo clone silently ignores --depth
# for local filesystem paths; only an explicit file:// URL honours it).
# ==================================================================================================
_mkorigin() {  # -> prints "<bare-repo-path> <base-sha> <head-sha> <merge-sha>"
  _o="$TMP/origin-$1.git"; _w="$TMP/work-$1"
  git init -q "$_o" --bare
  git clone -q "$_o" "$_w" >/dev/null 2>&1
  ( cd "$_w"
    git config user.email t@t; git config user.name t
    echo base >file.txt; git add file.txt; git commit -q -m "base commit"
    git push -q origin HEAD:refs/heads/main >/dev/null 2>&1
    echo "$(git rev-parse HEAD)" >"$TMP/base-$1.sha"

    git checkout -q -b feature
    echo changed >file.txt; git add file.txt
    git commit -q -m "$(printf 'docs(todo): fixture entry\n\nCI: docs\n')"
    git push -q origin HEAD:refs/heads/feature >/dev/null 2>&1
    echo "$(git rev-parse HEAD)" >"$TMP/head-$1.sha"

    git checkout -q main
    git merge -q --no-ff -m "Merge feature into main" feature
    git push -q origin HEAD:refs/heads/pr-merge >/dev/null 2>&1
    echo "$(git rev-parse HEAD)" >"$TMP/merge-$1.sha"
  ) >/dev/null 2>&1
  printf '%s %s %s %s' "$_o" "$(cat "$TMP/base-$1.sha")" "$(cat "$TMP/head-$1.sha")" "$(cat "$TMP/merge-$1.sha")"
}

_mkshallow_pr_checkout() {  # <origin-bare> <ref> <label> -> prints the shallow clone dir
  _d="$TMP/shallow-$3"
  git clone -q --depth 1 --branch "$2" "file://$1" "$_d" >/dev/null 2>&1
  mkdir -p "$_d/staging/plugin/scripts"
  cp "$CT" "$_d/staging/plugin/scripts/ci-tier.sh"
  printf '%s' "$_d"
}

# run_body <sandbox-dir> <body-file> <env-assignment>... -> prints the body's stdout
run_body() {
  _d="$1"; _bf="$2"; shift 2
  ( cd "$_d"
    export GITHUB_OUTPUT="$TMP/gh-output-$$"
    : >"$GITHUB_OUTPUT"
    for _e in "$@"; do export "$_e"; done
    bash "$_bf" 2>&1
    echo "---GITHUB_OUTPUT---"
    cat "$GITHUB_OUTPUT"
  )
}

read -r ORIGIN1 BASE1 HEAD1 MERGE1 <<EOF
$(_mkorigin ctw1)
EOF

# ==================================================================================================
# CTW1 — pull_request event, real PR head commit fetchable only by absolute SHA (HEAD^2 must fail
# in this fixture exactly as it fails on a real shallow GitHub Actions checkout). Run against every
# site's extracted (fixed) body: each must read the CI: docs trailer correctly.
# ==================================================================================================
for _site in $SITES; do
  _file=${_site%%:*}; _rest=${_site#*:}; _job=${_rest%%:*}; _label=${_rest#*:}
  _bfile="$TMP/body-$(printf '%s' "$_job" | tr -c 'A-Za-z0-9' '_').sh"
  [ -s "$_bfile" ] || continue
  _sb=$(_mkshallow_pr_checkout "$ORIGIN1" "pr-merge" "ctw1-$_job")
  # Confirm the fixture actually reproduces the bug shape before trusting the assertion below.
  if git -C "$_sb" rev-parse HEAD^2 >/dev/null 2>&1; then
    bad "CTW1 fixture ($_label): HEAD^2 unexpectedly resolved — the shallow-clone simulation is not shallow, this case proves nothing"
    continue
  fi
  _out=$(run_body "$_sb" "$_bfile" \
    "EVENT_NAME=pull_request" "PR_BASE_SHA=$BASE1" "PR_HEAD_SHA=$HEAD1" "PUSH_BEFORE_SHA=")
  printf '%s\n' "$_out" | grep -q 'requested=docs' \
    && ok "CTW1 ($_label): a pull_request run reads the CI: docs trailer via \$PR_HEAD_SHA where HEAD^2 cannot resolve" \
    || bad "CTW1 ($_label): expected requested=docs, got: $_out"
done

# ==================================================================================================
# CTW1-RED — the plant. The OLD (pre-VCS-053-fix) trailer-read block, run against the identical
# fixture, must fail to see the trailer (falls back to the merge commit's own message) — proving
# this harness would have caught VCS-053 had it existed before the fix landed.
# ==================================================================================================
# No `# plant:` marker here (rule 1/2): plant-check.sh's own --require-legs design states
# `.github/` is copied into its sandbox to be READ but is not a legal plant TARGET — a changed
# workflow file cannot be registered into ci-tier.sh's full-tier registry (confirmed above: an
# `.github/...` entry fails to resolve under ci-tier.sh's staging/-or-../docs/ resolution and
# would DID-NOT-RUN the whole registry for every future classification). This assertion's subject
# lives only in `.github/`, so it cannot honestly point a plant needle at it either. The RED proof
# is therefore inline and immediate instead: the OLD body below is executed against the identical
# fixture CTW1 already proved GREEN on, and must independently fail — the same "seen failing
# against a known-bad input" evidence a plant supplies, without borrowing another mechanism's
# target.
cat >"$TMP/old-body.sh" <<'OLDBODY'
set -u
if [ "$EVENT_NAME" = "pull_request" ]; then
  TRAILER_SRC=$(git log -1 --format=%B HEAD^2 2>/dev/null || git log -1 --format=%B HEAD 2>/dev/null || true)
else
  TRAILER_SRC=$(git log -1 --format=%B HEAD 2>/dev/null || true)
fi
REQUESTED=$(printf '%s\n' "$TRAILER_SRC" | grep -oE '^CI: (docs|standard|full)$' | head -1 | cut -d' ' -f2)
[ -n "$REQUESTED" ] || REQUESTED=full
echo "::notice::CI tier — computed=n/a requested=$REQUESTED effective=n/a"
OLDBODY
_sb=$(_mkshallow_pr_checkout "$ORIGIN1" "pr-merge" "ctw1-red")
_out=$(run_body "$_sb" "$TMP/old-body.sh" \
  "EVENT_NAME=pull_request" "PR_BASE_SHA=$BASE1" "PR_HEAD_SHA=$HEAD1" "PUSH_BEFORE_SHA=")
printf '%s\n' "$_out" | grep -q 'requested=full' \
  && ok "CTW1-RED: the pre-fix HEAD^2 body silently drops the CI: docs trailer and defaults to full on this exact fixture — this harness would have caught VCS-053" \
  || bad "CTW1-RED: expected the OLD body to wrongly report requested=full (proving the plant fires), got: $_out"

# ==================================================================================================
# CTW2 — push event, unaffected. HEAD directly (no HEAD^2 involved) already worked before the fix
# and must keep working identically after it — no regression on the already-correct path.
# ==================================================================================================
read -r ORIGIN2 BASE2 HEAD2 MERGE2 <<EOF
$(_mkorigin ctw2)
EOF
for _site in $SITES; do
  _rest=${_site#*:}; _job=${_rest%%:*}; _label=${_rest#*:}
  _bfile="$TMP/body-$(printf '%s' "$_job" | tr -c 'A-Za-z0-9' '_').sh"
  [ -s "$_bfile" ] || continue
  _wd="$TMP/push-$_job"
  git clone -q "$ORIGIN2" "$_wd" >/dev/null 2>&1
  git -C "$_wd" checkout -q feature
  mkdir -p "$_wd/staging/plugin/scripts"
  cp "$CT" "$_wd/staging/plugin/scripts/ci-tier.sh"
  _out=$(run_body "$_wd" "$_bfile" \
    "EVENT_NAME=push" "PR_BASE_SHA=" "PR_HEAD_SHA=" "PUSH_BEFORE_SHA=$BASE2")
  printf '%s\n' "$_out" | grep -q 'requested=docs' \
    && ok "CTW2 ($_label): a push event still reads the CI: docs trailer straight off HEAD — unaffected by the fix" \
    || bad "CTW2 ($_label): expected requested=docs on a push event, got: $_out"
done

# ==================================================================================================
# CTW3 — pull_request event, PR_HEAD_SHA unfetchable (bogus SHA no remote ever advertised). Must
# fall back to reading HEAD (the merge commit's own message, no trailer) -> requested=full. Confirms
# the fail-toward-full safety direction the fix must not disturb.
# ==================================================================================================
_BOGUS_SHA=0123456789abcdef0123456789abcdef01234567
for _site in $SITES; do
  _rest=${_site#*:}; _job=${_rest%%:*}; _label=${_rest#*:}
  _bfile="$TMP/body-$(printf '%s' "$_job" | tr -c 'A-Za-z0-9' '_').sh"
  [ -s "$_bfile" ] || continue
  _sb=$(_mkshallow_pr_checkout "$ORIGIN1" "pr-merge" "ctw3-$_job")
  _out=$(run_body "$_sb" "$_bfile" \
    "EVENT_NAME=pull_request" "PR_BASE_SHA=$BASE1" "PR_HEAD_SHA=$_BOGUS_SHA" "PUSH_BEFORE_SHA=")
  printf '%s\n' "$_out" | grep -q 'requested=full' \
    && ok "CTW3 ($_label): an unfetchable PR_HEAD_SHA falls back to HEAD (no trailer) and defaults to full — fail-safe direction unchanged" \
    || bad "CTW3 ($_label): expected requested=full on an unfetchable PR_HEAD_SHA, got: $_out"
done

printf '\nPASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
