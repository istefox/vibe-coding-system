#!/bin/bash
# clean-public-repo-history-safety test harness (ADR-0026) — Findings 1, 2, 3 from the
# clean-public-repo audit (SPEC.md / issue #30). Three lettered sections:
#   Section A (Finding 1, 5 tests) — fresh-history-publish.sh: the mandatory .git backup
#     tarball must land outside the work tree, resolved via the true git top-level (not the
#     raw ROOT argument), and `prepare` mode must hard-fail (exit 5, "SAFETY ABORT") if a
#     .git-backup-*.tar.gz path is ever found staged before the HITL instructions print.
#     Live subprocess execution against real fixture git repos.
#   Section B (Finding 3, 2 tests) — detect-tool-traces.sh: commit-trailer findings must
#     carry the correct SHA regardless of core.abbrev (7-40 hex chars, not a fixed 7).
#     Live subprocess execution.
#   Section C (Finding 2, 7 tests) — surgical-rewrite.sh: static grep anchors against the
#     script source and SKILL.md proving the backup relocation, origin-URL capture, and
#     truthful rollback instructions are present (git-filter-repo is confirmed absent on
#     this machine and uninstalled in CI, so no live subprocess test is possible or
#     meaningful for this finding — see ADR-0026 SS2.4/SS3.5).
# Zero $HOME dependency: runs identically in CI (ubuntu-latest, no ~/.claude) and locally.
# Bash 3.2 clean. Run: bash clean-public-repo-history-safety.test.sh
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)          # staging/plugin/scripts
STAGING=$(cd "$SCRIPTS/../.." && pwd)                # staging/
SKILL_DIR="$STAGING/plugin/skills/clean-public-repo"
FRESH_HISTORY="$SKILL_DIR/scripts/fresh-history-publish.sh"
SURGICAL_REWRITE="$SKILL_DIR/scripts/surgical-rewrite.sh"
DETECT_TRACES="$SKILL_DIR/scripts/detect-tool-traces.sh"
SKILL_MD="$SKILL_DIR/SKILL.md"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

# All live fixtures are built under their own mktemp -d TESTROOT, with the actual git repo
# one level inside it (FIXTURE="$TESTROOT/repo"), so "outside the work tree" can be asserted
# as "one level up from FIXTURE" with zero cross-test collision risk. One trap here cleans up
# every fixture used across every section of this file, regardless of where the script exits.
trap 'rm -rf "${TESTROOT_A1:-}" "${TESTROOT_A2:-}" "${TESTROOT_A3:-}" "${TESTROOT_B1:-}" "${TESTROOT_B2:-}"' EXIT

mk_fixture() {
  # mk_fixture <testroot-var-name> -- sets FIXTURE to <testroot>/repo, inits+commits file.txt
  _root=$(mktemp -d)
  eval "$1=\"\$_root\""
  FIXTURE="$_root/repo"
  mkdir -p "$FIXTURE"
  git -C "$FIXTURE" init -q
  git -C "$FIXTURE" config user.email t@example.com
  git -C "$FIXTURE" config user.name Test
  printf 'hello\n' > "$FIXTURE/file.txt"
  git -C "$FIXTURE" add file.txt
  git -C "$FIXTURE" commit -q -m 'initial commit'
}

# =====================================================================================
# Section A -- Finding 1: fresh-history-publish.sh backup placement + hard-fail guard
# =====================================================================================

# A1 + A4 share one fixture/run: a clean one-commit repo, `prepare` mode run once. A1 checks
# the backup lands outside the work tree; A4 (non-regression companion) checks the same run
# still reaches the ordinary HITL success message with no false guard trigger. A4 is expected
# to already pass today -- it guards against Task 2's fix later becoming an over-broad trap.
mk_fixture TESTROOT_A1
FIXTURE_A1="$FIXTURE"

A1_OUT=$(bash "$FRESH_HISTORY" "$FIXTURE_A1" prepare 2>&1)
A1_RC=$?
INSIDE_A1=$(find "$FIXTURE_A1" -maxdepth 1 -name '.git-backup-*.tar.gz')
OUTSIDE_A1=$(find "$TESTROOT_A1" -maxdepth 1 -name '.git-backup-*.tar.gz')

if [ "$A1_RC" -eq 0 ] && [ -z "$INSIDE_A1" ] && [ -n "$OUTSIDE_A1" ]; then
  ok "A1: prepare succeeds, backup lands outside the work tree (not inside)"
else
  bad "A1: prepare succeeds, backup lands outside the work tree (rc=$A1_RC inside='$INSIDE_A1' outside='$OUTSIDE_A1')"
fi

if [ "$A1_RC" -eq 0 ] && printf '%s' "$A1_OUT" | grep -q 'STOP FOR HITL'; then
  ok "A4: non-regression -- clean fixture still reaches STOP FOR HITL, no false guard trigger"
else
  bad "A4: non-regression -- clean fixture still reaches STOP FOR HITL, no false guard trigger (rc=$A1_RC)"
fi

# A2: a subdirectory of the repo passed as ROOT must still resolve to the true top-level, so
# the backup lands in the true repo's parent (TESTROOT), not in dirname(FIXTURE/sub) == FIXTURE
# (which is still inside the work tree).
mk_fixture TESTROOT_A2
FIXTURE_A2="$FIXTURE"
mkdir -p "$FIXTURE_A2/sub"

bash "$FRESH_HISTORY" "$FIXTURE_A2/sub" prepare >/dev/null 2>&1
A2_RC=$?
OUTSIDE_A2=$(find "$TESTROOT_A2" -maxdepth 1 -name '.git-backup-*.tar.gz')
INSIDE_A2=$(find "$FIXTURE_A2" -maxdepth 1 -name '.git-backup-*.tar.gz')

if [ "$A2_RC" -eq 0 ] && [ -n "$OUTSIDE_A2" ] && [ -z "$INSIDE_A2" ]; then
  ok "A2: subdirectory ROOT still resolves to the true top-level's parent"
else
  bad "A2: subdirectory ROOT still resolves to the true top-level's parent (rc=$A2_RC outside='$OUTSIDE_A2' inside='$INSIDE_A2')"
fi

# A3: a pre-staged .git-backup-*.tar.gz decoy inside the fixture must trigger the independent
# hard-fail guard (exit 5, "SAFETY ABORT"), not the ordinary success path.
mk_fixture TESTROOT_A3
FIXTURE_A3="$FIXTURE"
printf 'decoy' > "$FIXTURE_A3/.git-backup-20260101-000000.tar.gz"

A3_OUT=$(bash "$FRESH_HISTORY" "$FIXTURE_A3" prepare 2>&1)
A3_RC=$?

if [ "$A3_RC" -eq 5 ] && printf '%s' "$A3_OUT" | grep -q 'SAFETY ABORT'; then
  ok "A3: hard-fail guard fires on a tainted fixture (exit 5, SAFETY ABORT)"
else
  bad "A3: hard-fail guard fires on a tainted fixture (rc=$A3_RC)"
fi

# A5: SKILL.md's "Mandatory backup" step must mention the backup is written outside the work
# tree (case-insensitive match, narrow context grep to avoid matching unrelated prose).
if grep -A5 'Mandatory backup' "$SKILL_MD" | grep -qi 'outside'; then
  ok "A5: SKILL.md 'Mandatory backup' step mentions outside-work-tree placement"
else
  bad "A5: SKILL.md 'Mandatory backup' step mentions outside-work-tree placement"
fi

# =====================================================================================
# Section B -- Finding 3: detect-tool-traces.sh SHA matching (core.abbrev)
# =====================================================================================

# B1: the real bug. With core.abbrev=8, a commit-trailer finding's reported SHA must equal
# the commit's real 8-char %h -- the current regex requires an exact 7-char SHA + space, so
# it never matches once abbreviation exceeds 7, leaving the SHA field empty.
TESTROOT_B1=$(mktemp -d)
FIXTURE_B1="$TESTROOT_B1/repo"
mkdir -p "$FIXTURE_B1"
git -C "$FIXTURE_B1" init -q
git -C "$FIXTURE_B1" config user.email t@example.com
git -C "$FIXTURE_B1" config user.name Test
git -C "$FIXTURE_B1" config core.abbrev 8
printf 'a\n' > "$FIXTURE_B1/a.txt"
git -C "$FIXTURE_B1" add a.txt
git -C "$FIXTURE_B1" commit -q -m 'first commit'
printf 'b\n' >> "$FIXTURE_B1/a.txt"
git -C "$FIXTURE_B1" add a.txt
git -C "$FIXTURE_B1" commit -q -m 'second commit

Co-Authored-By: Claude <noreply@anthropic.com>'

EXPECTED_SHA_B1=$(git -C "$FIXTURE_B1" log -1 --format=%h HEAD)
B1_FINDINGS=$(bash "$DETECT_TRACES" "$FIXTURE_B1" 2>/dev/null)
REPORTED_SHA_B1=$(printf '%s\n' "$B1_FINDINGS" | grep 'Co-Authored-By' | head -1 | cut -d'|' -f3)

# Fixture sanity is folded into the same assertion (not a separate tally entry, to keep
# Section B at exactly 2 tests) but fails with a distinct, loud message if the >7-char
# scenario this bug needs was never actually forced -- a silently-wrong fixture would
# otherwise report a false GREEN.
if [ "${#EXPECTED_SHA_B1}" -ne 8 ]; then
  bad "B1: fixture sanity failed -- core.abbrev=8 did not force an 8-char %h (got '${EXPECTED_SHA_B1}', len=${#EXPECTED_SHA_B1}); git's abbreviation behavior may have changed"
elif [ -n "$REPORTED_SHA_B1" ] && [ "$REPORTED_SHA_B1" = "$EXPECTED_SHA_B1" ]; then
  ok "B1: commit-trailer finding carries the correct SHA with core.abbrev=8"
else
  bad "B1: commit-trailer finding carries the correct SHA with core.abbrev=8 (expected='$EXPECTED_SHA_B1' got='$REPORTED_SHA_B1')"
fi

# B2: non-regression companion at git's natural ~7-char default (no explicit core.abbrev).
# {7,40} is a strict superset of {7}, so this is expected to already pass today -- included
# as an explicit, cheap, visible check rather than left as an implicit assumption.
TESTROOT_B2=$(mktemp -d)
FIXTURE_B2="$TESTROOT_B2/repo"
mkdir -p "$FIXTURE_B2"
git -C "$FIXTURE_B2" init -q
git -C "$FIXTURE_B2" config user.email t@example.com
git -C "$FIXTURE_B2" config user.name Test
printf 'a\n' > "$FIXTURE_B2/a.txt"
git -C "$FIXTURE_B2" add a.txt
git -C "$FIXTURE_B2" commit -q -m 'only commit

Co-Authored-By: Claude <noreply@anthropic.com>'

EXPECTED_SHA_B2=$(git -C "$FIXTURE_B2" log -1 --format=%h HEAD)
B2_FINDINGS=$(bash "$DETECT_TRACES" "$FIXTURE_B2" 2>/dev/null)
REPORTED_SHA_B2=$(printf '%s\n' "$B2_FINDINGS" | grep 'Co-Authored-By' | head -1 | cut -d'|' -f3)

if [ -n "$REPORTED_SHA_B2" ] && [ "$REPORTED_SHA_B2" = "$EXPECTED_SHA_B2" ]; then
  ok "B2: non-regression -- natural default abbreviation still reports the correct SHA"
else
  bad "B2: non-regression -- natural default abbreviation still reports the correct SHA (expected='$EXPECTED_SHA_B2' got='$REPORTED_SHA_B2')"
fi

# =====================================================================================
# Section C -- Finding 2: surgical-rewrite.sh rollback-story truthfulness (static anchors)
# =====================================================================================
# git-filter-repo is confirmed absent on this machine and not installed by docs-ci.yml, so
# every mode of surgical-rewrite.sh is gated behind an unconditional `git filter-repo
# --version` check (exit 3) before any of this finding's fix is ever reached -- a live
# subprocess test would provide zero real coverage while looking like a real test. These
# are plain grep assertions against the script source / SKILL.md, no subprocess execution.

# C1: the old buggy inside-ROOT backup assignment must be gone.
if ! grep -qF 'BACKUP_PATH="${ROOT}/${BACKUP_NAME}"' "$SURGICAL_REWRITE"; then
  ok "C1: old inside-ROOT BACKUP_PATH assignment is gone"
else
  bad "C1: old inside-ROOT BACKUP_PATH assignment is gone"
fi

# C2: the new top-level-resolved backup assignment must be present.
if grep -qF 'dirname "$GIT_TOPLEVEL"' "$SURGICAL_REWRITE"; then
  ok "C2: new dirname(\$GIT_TOPLEVEL) backup assignment is present"
else
  bad "C2: new dirname(\$GIT_TOPLEVEL) backup assignment is present"
fi

# C3: origin's URL must be captured before Step 3 (filter-repo) removes the remote.
if grep -qE 'ORIGIN_URL=\$\(git -C "\$ROOT" remote get-url origin' "$SURGICAL_REWRITE"; then
  ok "C3: ORIGIN_URL is captured before filter-repo removes the remote"
else
  bad "C3: ORIGIN_URL is captured before filter-repo removes the remote"
fi

# C4: the HITL instructions must re-add the origin remote (filter-repo deletes it).
if grep -qF 'remote add origin' "$SURGICAL_REWRITE"; then
  ok "C4: HITL instructions re-add the origin remote"
else
  bad "C4: HITL instructions re-add the origin remote"
fi

# C5: verification guidance must point at filter-repo's own commit-map, not a dead diff.
if grep -qF 'filter-repo/commit-map' "$SURGICAL_REWRITE"; then
  ok "C5: commit-map is referenced as the real before/after record"
else
  bad "C5: commit-map is referenced as the real before/after record"
fi

# C6: the dead verification line (always prints nothing -- --all rewrites the backup
# branch identically to HEAD) must be removed, not merely caveated.
if ! grep -qF 'diff ${BACKUP_BRANCH} --stat' "$SURGICAL_REWRITE"; then
  ok "C6: dead 'diff \${BACKUP_BRANCH} --stat' verification line is removed"
else
  bad "C6: dead 'diff \${BACKUP_BRANCH} --stat' verification line is removed"
fi

# C7: SKILL.md's stale, dated "git-filter-repo PRESENT" claim must be replaced with
# non-perishable wording pointing at the script's own live version check.
if grep -Eqi 'live check|do not treat.*verified present|authoritative' "$SKILL_MD"; then
  ok "C7: SKILL.md stale environment claim reworded to point at the live version check"
else
  bad "C7: SKILL.md stale environment claim reworded to point at the live version check"
fi

printf '\nPASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
