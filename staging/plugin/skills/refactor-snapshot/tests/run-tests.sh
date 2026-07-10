#!/bin/bash
# refactor-snapshot self-test harness. Isolated; never touches real state.
set -u
SK="$HOME/.claude/skills/refactor-snapshot"
S="$SK/scripts"
TMP="$(mktemp -d)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

# 1: SKILL.md frontmatter name
M="$SK/SKILL.md"
[ -f "$M" ] && head -1 "$M" | grep -q '^---$' && grep -q '^name: refactor-snapshot$' "$M" \
  && ok "SKILL.md: frontmatter name" || bad "SKILL.md: frontmatter name"

# 2: SKILL.md description includes "snapshot harness"
grep -q '^description:.*snapshot' "$M" && ok "SKILL.md: description" || bad "SKILL.md: description"

# 3: scripts present + executable
[ -x "$S/capture.sh" ] && ok "capture.sh: present + executable" || bad "capture.sh: present + executable"
[ -x "$S/diff.sh" ] && ok "diff.sh: present + executable" || bad "diff.sh: present + executable"

# 4: capture.sh missing test-cmd → exit 1
P1="$TMP/proj1"; mkdir -p "$P1/.claude"
( cd "$P1" && bash "$S/capture.sh" PRE >/dev/null 2>&1 ); r=$?
[ $r -eq 1 ] && ok "capture: missing test-cmd → exit 1" || bad "capture: missing test-cmd → exit 1"

# 5: capture.sh bad arg → exit 3
P2="$TMP/proj2"; mkdir -p "$P2/.claude"; printf 'true\n' > "$P2/.claude/test-cmd"
( cd "$P2" && bash "$S/capture.sh" XYZ >/dev/null 2>&1 ); r=$?
[ $r -eq 3 ] && ok "capture: bad arg → exit 3" || bad "capture: bad arg → exit 3"

# 6: capture.sh green test-cmd → snapshot file con EXIT=0 + SHA256 64-hex
P3="$TMP/proj3"; mkdir -p "$P3/.claude"; printf 'echo hello\n' > "$P3/.claude/test-cmd"
( cd "$P3" && bash "$S/capture.sh" PRE >/dev/null 2>&1 )
SF="$P3/.claude/.refactor-snapshot.txt"
[ -f "$SF" ] \
  && grep -q '^EXIT=0$' "$SF" \
  && grep -q '^STDOUT-SHA256=[0-9a-f]\{64\}$' "$SF" \
  && grep -q '^STDERR-SHA256=[0-9a-f]\{64\}$' "$SF" \
  && ok "capture: green test-cmd → valid snapshot" || bad "capture: green test-cmd → valid snapshot"

# 7: capture.sh red test-cmd → snapshot file con EXIT non-zero
P4="$TMP/proj4"; mkdir -p "$P4/.claude"; printf 'exit 7\n' > "$P4/.claude/test-cmd"
( cd "$P4" && bash "$S/capture.sh" PRE >/dev/null 2>&1 )
SFR="$P4/.claude/.refactor-snapshot.txt"
[ -f "$SFR" ] && grep -q '^EXIT=7$' "$SFR" \
  && ok "capture: red test-cmd → EXIT captured" || bad "capture: red test-cmd → EXIT captured"

# 8: diff.sh identical PRE/POST → exit 0 STATUS=PASS
P5="$TMP/proj5"; mkdir -p "$P5/.claude"; printf 'echo same\n' > "$P5/.claude/test-cmd"
( cd "$P5" && bash "$S/capture.sh" PRE >/dev/null 2>&1 )
( cd "$P5" && bash "$S/capture.sh" POST >/dev/null 2>&1 )
O=$( cd "$P5" && bash "$S/diff.sh" 2>/dev/null ); r=$?
[ $r -eq 0 ] && echo "$O" | grep -q '^STATUS=PASS$' \
  && ok "diff: identical → PASS exit 0" || bad "diff: identical → PASS exit 0"

# 9: diff.sh different stdout → exit 1 STATUS=FAIL
P6="$TMP/proj6"; mkdir -p "$P6/.claude"
printf 'echo aaa\n' > "$P6/.claude/test-cmd"; ( cd "$P6" && bash "$S/capture.sh" PRE >/dev/null 2>&1 )
printf 'echo bbb\n' > "$P6/.claude/test-cmd"; ( cd "$P6" && bash "$S/capture.sh" POST >/dev/null 2>&1 )
O=$( cd "$P6" && bash "$S/diff.sh" 2>/dev/null ); r=$?
[ $r -eq 1 ] && echo "$O" | grep -q '^STATUS=FAIL$' && echo "$O" | grep -q '^STDOUT-MATCH=no$' \
  && ok "diff: divergent stdout → FAIL exit 1" || bad "diff: divergent stdout → FAIL exit 1"

# 10: diff.sh with override SCOPE=stdout on divergent stdout → exit 0 STATUS=PASS OVERRIDE=yes
P7="$TMP/proj7"; mkdir -p "$P7/.claude"
printf 'echo aaa\n' > "$P7/.claude/test-cmd"; ( cd "$P7" && bash "$S/capture.sh" PRE >/dev/null 2>&1 )
printf 'echo bbb\n' > "$P7/.claude/test-cmd"; ( cd "$P7" && bash "$S/capture.sh" POST >/dev/null 2>&1 )
printf 'REASON: test timestamp drift expected\nSCOPE: stdout\nEXPIRES: 2099-12-31\n' > "$P7/.claude/refactor-snapshot-override"
O=$( cd "$P7" && bash "$S/diff.sh" 2>/dev/null ); r=$?
[ $r -eq 0 ] && echo "$O" | grep -q '^STATUS=PASS$' && echo "$O" | grep -q '^OVERRIDE=yes' \
  && ok "diff: override SCOPE=stdout → PASS exit 0" || bad "diff: override SCOPE=stdout → PASS exit 0"

# 11: pre-runs.sh present + executable
[ -x "$S/pre-runs.sh" ] && ok "pre-runs.sh: present + executable" || bad "pre-runs.sh: present + executable"

# 12: default RFS_RUNS (unset) with deterministic test-cmd → exit 0, STATUS=PASS, RUNS=3
P8="$TMP/proj8"; mkdir -p "$P8/.claude"; printf 'echo hello\n' > "$P8/.claude/test-cmd"
O=$( cd "$P8" && bash "$S/pre-runs.sh" 2>/dev/null ); r=$?
[ $r -eq 0 ] && echo "$O" | grep -q '^STATUS=PASS$' && echo "$O" | grep -q '^RUNS=3$' \
  && ok "pre-runs: default N=3 deterministic → exit 0 STATUS=PASS RUNS=3" \
  || bad "pre-runs: default N=3 deterministic → exit 0 STATUS=PASS RUNS=3"

# 13: RFS_RUNS=1 with deterministic test-cmd → exit 0, STATUS=PASS, NOTE=determinism-check-skipped
P9="$TMP/proj9"; mkdir -p "$P9/.claude"; printf 'echo hello\n' > "$P9/.claude/test-cmd"
O=$( cd "$P9" && RFS_RUNS=1 bash "$S/pre-runs.sh" 2>/dev/null ); r=$?
[ $r -eq 0 ] && echo "$O" | grep -q '^STATUS=PASS$' && echo "$O" | grep -q '^NOTE=determinism-check-skipped$' \
  && ok "pre-runs: RFS_RUNS=1 → exit 0 STATUS=PASS NOTE=determinism-check-skipped" \
  || bad "pre-runs: RFS_RUNS=1 → exit 0 STATUS=PASS NOTE=determinism-check-skipped"

# 14: RFS_RUNS=4 with non-deterministic test-cmd → exit 2, STATUS=UNVERIFIED
P10="$TMP/proj10"; mkdir -p "$P10/.claude"
printf 'head -c 4 /dev/urandom | od -An -tu4\n' > "$P10/.claude/test-cmd"
O=$( cd "$P10" && RFS_RUNS=4 bash "$S/pre-runs.sh" 2>/dev/null ); r=$?
[ $r -eq 2 ] && echo "$O" | grep -q '^STATUS=UNVERIFIED$' \
  && ok "pre-runs: RFS_RUNS=4 non-deterministic → exit 2 STATUS=UNVERIFIED" \
  || bad "pre-runs: RFS_RUNS=4 non-deterministic → exit 2 STATUS=UNVERIFIED"

# 15: RFS_RUNS=0 → exit 1, stderr contains "invalid"
P11="$TMP/proj11"; mkdir -p "$P11/.claude"; printf 'echo hello\n' > "$P11/.claude/test-cmd"
E=$( cd "$P11" && RFS_RUNS=0 bash "$S/pre-runs.sh" 2>&1 1>/dev/null ); r=$?
[ $r -eq 1 ] && echo "$E" | grep -qi 'invalid' \
  && ok "pre-runs: RFS_RUNS=0 → exit 1 stderr invalid" \
  || bad "pre-runs: RFS_RUNS=0 → exit 1 stderr invalid"

# 16: RFS_RUNS=11 → exit 1
P12="$TMP/proj12"; mkdir -p "$P12/.claude"; printf 'echo hello\n' > "$P12/.claude/test-cmd"
( cd "$P12" && RFS_RUNS=11 bash "$S/pre-runs.sh" >/dev/null 2>&1 ); r=$?
[ $r -eq 1 ] && ok "pre-runs: RFS_RUNS=11 → exit 1" || bad "pre-runs: RFS_RUNS=11 → exit 1"

# 17: RFS_RUNS=abc → exit 1
P13="$TMP/proj13"; mkdir -p "$P13/.claude"; printf 'echo hello\n' > "$P13/.claude/test-cmd"
( cd "$P13" && RFS_RUNS=abc bash "$S/pre-runs.sh" >/dev/null 2>&1 ); r=$?
[ $r -eq 1 ] && ok "pre-runs: RFS_RUNS=abc → exit 1" || bad "pre-runs: RFS_RUNS=abc → exit 1"

echo "----"; echo "PASS=$PASS FAIL=$FAIL"; rm -rf "$TMP"
[ $FAIL -eq 0 ]
