#!/usr/bin/env bash
# Phase 2 test harness (ADR-0023) — detect-test-cmd, roadmap-from-issues, spec-issue-gate.
# Offline, no gh/network. Bash 3.2 clean.
set -uo pipefail

S=$(cd "$(dirname "$0")/.." && pwd)
DETECT="$S/detect-test-cmd.sh"; ROADMAP="$S/roadmap-from-issues.sh"; GATE="$S/spec-issue-gate.sh"

PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); echo "ok   $1"; }
no() { FAIL=$((FAIL+1)); echo "FAIL $1"; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# ---- detect-test-cmd ----
mk() { d="$tmp/$1"; mkdir -p "$d"; printf '%s' "$d"; }

d=$(mk swift); : > "$d/Package.swift"
bash "$DETECT" --root "$d" >/dev/null
grep -qx 'swift test' "$d/.claude/test-cmd" && ok "detect: swift package -> swift test" || no "detect: swift package"

d=$(mk xc); mkdir -p "$d/Ondum.xcodeproj"
bash "$DETECT" --root "$d" >/dev/null
grep -q 'xcodebuild test -project' "$d/.claude/test-cmd" && grep -q 'Ondum' "$d/.claude/test-cmd" \
  && ok "detect: xcodeproj -> xcodebuild + scheme" || no "detect: xcodeproj"

# issue #488 / ADR-0159: without -derivedDataPath the build root is whatever the machine's Xcode
# preference says, shared by every checkout on it — worktrees included. The value written is
# absolute at DETECTION time ($PWD after detect-test-cmd.sh's own `cd "$ROOT"`), so it names THIS
# project's root regardless of the cwd a later invocation runs from.
#
# NOT PLANTED (rule 2's obligation, disclosed rather than silently skipped). This file's `no()`
# prints `FAIL <label>`, with no colon and no id — the counter-example named verbatim in
# prep-row-select.test.sh's own header ("makes every plant declared [t]here unattributable"), which
# predates this change. A declaration here would be indistinguishable from every other assertion in
# this file: `plant-check.sh`'s `red_re()` requires `^FAIL: <id>`, never produced. Verified by hand
# instead (CLAUDE.md rule 2's letter, not the registry's mechanism): reverting `detect-test-cmd.sh`'s
# `-derivedDataPath` addition on the `-project` branch flips exactly the xcodeproj assertion below
# to FAIL and nothing else; the same check on the `-workspace` branch flips exactly the xcworkspace
# assertion. Fixing `prep.test.sh`'s reporting convention itself is out of scope here — it is a
# pre-existing, separately documented limitation, not a new defect this change introduces.
grep -q -- '-derivedDataPath' "$d/.claude/test-cmd" && grep -q -- "-derivedDataPath \"$d/.build/DerivedData\"" "$d/.claude/test-cmd" \
  && ok "detect: xcodeproj -> -derivedDataPath is absolute and per-checkout (issue #488)" \
  || no "detect: xcodeproj -> -derivedDataPath (issue #488)"

d=$(mk xcws); mkdir -p "$d/Ondum.xcworkspace"
bash "$DETECT" --root "$d" >/dev/null
grep -q -- '-derivedDataPath' "$d/.claude/test-cmd" && grep -q -- "-derivedDataPath \"$d/.build/DerivedData\"" "$d/.claude/test-cmd" \
  && ok "detect: xcworkspace -> -derivedDataPath is absolute and per-checkout (issue #488)" \
  || no "detect: xcworkspace -> -derivedDataPath (issue #488)"

d=$(mk py); : > "$d/pyproject.toml"
bash "$DETECT" --root "$d" >/dev/null
grep -qx 'python3 -m pytest' "$d/.claude/test-cmd" && ok "detect: python -> pytest" || no "detect: python"

d=$(mk node); printf '{"scripts":{"test":"jest"}}' > "$d/package.json"
bash "$DETECT" --root "$d" >/dev/null
grep -qx 'npm test' "$d/.claude/test-cmd" && ok "detect: node w/test -> npm test" || no "detect: node w/test"

d=$(mk nodetestless); printf '{"name":"x"}' > "$d/package.json"
bash "$DETECT" --root "$d" >/dev/null
grep -qx 'NONE' "$d/.claude/test-cmd" && ok "detect: node no-test -> NONE" || no "detect: node no-test"

d=$(mk empty)
bash "$DETECT" --root "$d" >/dev/null
grep -qx 'NONE' "$d/.claude/test-cmd" && ok "detect: unknown -> NONE" || no "detect: unknown"

d=$(mk keep); mkdir -p "$d/.claude"; printf 'my custom cmd\n' > "$d/.claude/test-cmd"; : > "$d/Package.swift"
bash "$DETECT" --root "$d" >/dev/null
grep -qx 'my custom cmd' "$d/.claude/test-cmd" && ok "detect: existing test-cmd untouched" || no "detect: existing untouched"

# ---- roadmap-from-issues ----
if command -v jq >/dev/null 2>&1; then
  d=$(mk rm); cd "$d"; git init -q 2>/dev/null || true
  cat > issues.json <<'JSON'
[ {"number":137,"title":"Add greeting module"},
  {"number":144,"title":"Fix crash on launch"} ]
JSON
  bash "$ROADMAP" --root "$d" --label release-blocker --issues-json "$d/issues.json" >/dev/null
  _c=$(grep -c '(issue #' PROJECT.md 2>/dev/null); c=${_c:-0}   # issue #174 count idiom
  { [ "$c" = "2" ] && grep -q '(issue #137)' PROJECT.md && grep -q '(issue #144)' PROJECT.md; } \
    && ok "roadmap: 2 issues -> 2 features" || no "roadmap: 2 issues -> 2 features (c=$c)"
  m=$(wc -l < docs/specs/_issue-map.tsv | tr -d ' ')
  [ "$m" = "2" ] && ok "roadmap: issue-map has 2 rows" || no "roadmap: issue-map rows ($m)"
  # slug must be prefixed with the issue number (unique + resolvable by number)
  grep -qE '^137-add-greeting-module	137	' docs/specs/_issue-map.tsv \
    && ok "roadmap: slug is number-prefixed" || no "roadmap: slug number-prefixed"
  # idempotency
  bash "$ROADMAP" --root "$d" --label release-blocker --issues-json "$d/issues.json" >/dev/null
  c2=$(grep -c '(issue #' PROJECT.md)
  [ "$c2" = "2" ] && ok "roadmap: re-run no duplicates" || no "roadmap: re-run duplicated (c=$c2)"
  cd - >/dev/null
else
  echo "skip roadmap tests (no jq)"
fi

# ---- spec-issue-gate ----
printf 'fix it' | bash "$GATE" >/dev/null 2>&1
[ $? -eq 3 ] && ok "gate: short body -> THIN" || no "gate: short body -> THIN"

body='## Acceptance criteria
- [ ] the greet() function returns a localized string
- [ ] it must handle an empty name without crashing
- [ ] expected behavior covered by a unit test'
printf '%s' "$body" | bash "$GATE" >/dev/null 2>&1
[ $? -eq 0 ] && ok "gate: rich body w/criteria -> OK" || no "gate: rich body -> OK"

# a few padded lines, no acceptance-criteria signal, under the substantial bar -> THIN
body2='vague talk about a thing here
another line continuing vaguely
a third line with no real content
a fourth padded line of filler'
printf '%s' "$body2" | bash "$GATE" >/dev/null 2>&1
[ $? -eq 3 ] && ok "gate: padded no-signal short -> THIN" || no "gate: padded no-signal short -> THIN"

# a genuinely substantial body (>=400 non-space chars) with no keyword -> OK
body3=$(printf 'The module keeps a rolling window of samples and averages them per channel. %.0s' 1 2 3 4 5 6 7 8 9)
printf '%s' "$body3" | bash "$GATE" >/dev/null 2>&1
[ $? -eq 0 ] && ok "gate: substantial no-signal -> OK" || no "gate: substantial no-signal -> OK"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
