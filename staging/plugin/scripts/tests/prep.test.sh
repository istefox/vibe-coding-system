#!/usr/bin/env bash
# Phase 2 test harness (ADR-0023) — detect-test-cmd, roadmap-from-issues, spec-issue-gate.
# Offline, no gh/network. Bash 3.2 clean.
set -uo pipefail

S=$(cd "$(dirname "$0")/.." && pwd)
DETECT="$S/detect-test-cmd.sh"; ROADMAP="$S/roadmap-from-issues.sh"; GATE="$S/spec-issue-gate.sh"

PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); echo "ok   $1"; }
no() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }
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

# ==================================================================================================
# TU — issue #470 / ADR-0165 (2026-08-22-470-chain-never-regenerates-xcode.md): the
# generated-Xcode-project branch detect-test-cmd.sh gains for a Tuist- or XcodeGen-managed project.
# Fixed-width assertion ids TU01 ... TU99, one ok/no call per id, extending this harness the same
# way the unlabeled assertions above it already do. TU99 (near the end of this file) is the
# assertion-count floor for the whole file, which had none before this feature.
# ==================================================================================================

# ---- TU01-TU04 (R-03, R-06) — Task 1: forward guards, all GREEN today. These assertions pass
# against the script exactly as it stands; they are what makes "the existing branches are
# unmodified in behavior" (R-03) and "an existing trusted test-cmd is left untouched" (R-06) mean
# something once the generated-Xcode-project branch lands. This is also the batch that converts
# no() to the plantable `FAIL: <id>` form, above. ----

tu01d=$(mk tu01); mkdir -p "$tu01d/Foo.xcodeproj"
bash "$DETECT" --root "$tu01d" >/dev/null
grep -q 'xcodebuild test -project' "$tu01d/.claude/test-cmd" && grep -q 'Foo' "$tu01d/.claude/test-cmd" \
  && ! grep -q 'tuist generate' "$tu01d/.claude/test-cmd" && ! grep -q 'xcodegen generate' "$tu01d/.claude/test-cmd" \
  && ok "TU01 (R-03) xcodeproj-only fixture: -project form intact, no regeneration prefix" \
  || no "TU01 (R-03) xcodeproj-only fixture: -project form intact, no regeneration prefix"

tu02d=$(mk tu02); mkdir -p "$tu02d/Bar.xcworkspace"
bash "$DETECT" --root "$tu02d" >/dev/null
grep -q -- '-workspace' "$tu02d/.claude/test-cmd" && grep -q 'Bar' "$tu02d/.claude/test-cmd" \
  && ! grep -q 'tuist generate' "$tu02d/.claude/test-cmd" && ! grep -q 'xcodegen generate' "$tu02d/.claude/test-cmd" \
  && ok "TU02 (R-03) xcworkspace-only fixture: -workspace form intact, no regeneration prefix" \
  || no "TU02 (R-03) xcworkspace-only fixture: -workspace form intact, no regeneration prefix"

grep -q -- "-derivedDataPath \"$tu01d/.build/DerivedData\"" "$tu01d/.claude/test-cmd" \
  && grep -q -- "-derivedDataPath \"$tu02d/.build/DerivedData\"" "$tu02d/.claude/test-cmd" \
  && ok "TU03 (R-03) both frozen branches keep an absolute, per-fixture -derivedDataPath (ADR-0159 D1)" \
  || no "TU03 (R-03) both frozen branches keep an absolute, per-fixture -derivedDataPath (ADR-0159 D1)"

d=$(mk tu04); mkdir -p "$d/.claude"
printf 'distinctive custom cmd for TU04\n' > "$d/.claude/test-cmd"
: > "$d/Project.swift"
cp "$d/.claude/test-cmd" "$tmp/tu04-before"
tu04out=$(bash "$DETECT" --root "$d"); tu04rc=$?
if cmp -s "$tmp/tu04-before" "$d/.claude/test-cmd" && [ "$tu04rc" -eq 0 ] \
  && printf '%s\n' "$tu04out" | grep -q 'already present'; then
  ok "TU04 (R-06) existing test-cmd + Project.swift present: file untouched, exit 0, 'already present'"
else
  no "TU04 (R-06) existing test-cmd + Project.swift present: file untouched, exit 0, 'already present'"
fi

# ---- TU10-TU17 (R-01, R-04) — Task 2: detection, branch ordering and the SwiftPM manifest fix.
# Every assertion here is RED until the generated-Xcode-project branch lands in
# detect-test-cmd.sh (issue #470, ADR-0165 Task 4). ----

d=$(mk tu10); : > "$d/Project.swift"; mkdir -p "$d/Foo.xcodeproj" "$d/Bar.xcworkspace"
bash "$DETECT" --root "$d" >/dev/null
# plant: TU10 | plugin/scripts/detect-test-cmd.sh | if [ -f "Project.swift" ] || [ -f "Tuist.swift" ] || [ -f "project.yml" ] || [ -f "project.yaml" ]; then | if false; then
grep -q 'tuist generate' "$d/.claude/test-cmd" \
  && ok "TU10 (R-01) Project.swift + xcodeproj + xcworkspace: new branch wins, ordered first" \
  || no "TU10 (R-01) Project.swift + xcodeproj + xcworkspace: new branch wins, ordered first"

d=$(mk tu11); : > "$d/Tuist.swift"
bash "$DETECT" --root "$d" >/dev/null
grep -q 'tuist generate' "$d/.claude/test-cmd" \
  && ok "TU11 (R-01) Tuist.swift alone -> tuist generate" \
  || no "TU11 (R-01) Tuist.swift alone -> tuist generate"

d=$(mk tu12); : > "$d/project.yml"
bash "$DETECT" --root "$d" >/dev/null
# plant: TU12 | plugin/scripts/detect-test-cmd.sh | TOOL="xcodegen"; REGEN="xcodegen generate" | TOOL="tuist"; REGEN="tuist generate --no-open"
grep -q 'xcodegen generate' "$d/.claude/test-cmd" && ! grep -q 'tuist generate' "$d/.claude/test-cmd" \
  && ok "TU12 (R-01) project.yml alone -> xcodegen generate, never tuist generate" \
  || no "TU12 (R-01) project.yml alone -> xcodegen generate, never tuist generate"

d=$(mk tu13); : > "$d/project.yaml"
bash "$DETECT" --root "$d" >/dev/null
grep -q 'xcodegen generate' "$d/.claude/test-cmd" \
  && ok "TU13 (R-01) project.yaml alone -> xcodegen generate" \
  || no "TU13 (R-01) project.yaml alone -> xcodegen generate"

d=$(mk tu14); : > "$d/Project.swift"
tu14out=$(bash "$DETECT" --root "$d")
printf '%s\n' "$tu14out" | grep -q 'stack=xcode-project-generated' \
  && ok "TU14 (R-01) Project.swift fixture: stdout names stack=xcode-project-generated" \
  || no "TU14 (R-01) Project.swift fixture: stdout names stack=xcode-project-generated"

d=$(mk tu15); mkdir -p "$d/Tuist"; : > "$d/Tuist/Package.swift"
bash "$DETECT" --root "$d" >/dev/null
# plant: TU15 | plugin/scripts/detect-test-cmd.sh | || [ -f "Tuist/Package.swift" ]
grep -qx 'swift test' "$d/.claude/test-cmd" \
  && ok "TU15 (R-04) Tuist/Package.swift only, no root Package.swift -> swift test" \
  || no "TU15 (R-04) Tuist/Package.swift only, no root Package.swift -> swift test"

d=$(mk tu16); mkdir -p "$d/Tuist"; : > "$d/Tuist/Package.swift"; : > "$d/Project.swift"
bash "$DETECT" --root "$d" >/dev/null
tu16cmd=$(cat "$d/.claude/test-cmd")
if printf '%s' "$tu16cmd" | grep -q 'tuist generate' && [ "$tu16cmd" != "swift test" ]; then
  ok "TU16 (R-04) Tuist/Package.swift + Project.swift: generated branch wins over swift test"
else
  no "TU16 (R-04) Tuist/Package.swift + Project.swift: generated branch wins over swift test"
fi

d=$(mk tu17)
bash "$DETECT" --root "$d" >/dev/null
grep -qx 'NONE' "$d/.claude/test-cmd" \
  && ok "TU17 (R-01) no manifest, no Xcode artifact -> NONE (negative direction)" \
  || no "TU17 (R-01) no manifest, no Xcode artifact -> NONE (negative direction)"

# ---- TU20-TU34 (R-02, R-05) — Task 3: the generated candidate's content and its DID-NOT-RUN
# contract. All RED until the generated-Xcode-project branch lands in detect-test-cmd.sh
# (issue #470, ADR-0165 Task 4). ----

d=$(mk tu20); : > "$d/Project.swift"
bash "$DETECT" --root "$d" >/dev/null
tu20cmd=$(cat "$d/.claude/test-cmd")
case "$tu20cmd" in
  "cd \"$d\" &&"*) ok 'TU20 (R-02) candidate begins with cd "<abs-fixture-root>" &&' ;;
  *) no 'TU20 (R-02) candidate begins with cd "<abs-fixture-root>" &&' ;;
esac

d=$(mk tu21); : > "$d/Project.swift"
bash "$DETECT" --root "$d" >/dev/null
# plant: TU21 | plugin/scripts/detect-test-cmd.sh | --no-open
grep -q -- 'tuist generate --no-open' "$d/.claude/test-cmd" \
  && ok "TU21 (R-02) candidate contains tuist generate --no-open (flag present)" \
  || no "TU21 (R-02) candidate contains tuist generate --no-open (flag present)"

d=$(mk tu22)
cat > "$d/Project.swift" <<'EOF'
let projectName = "Ondum"
let project = Project(
    name: projectName,
    targets: []
)
EOF
bash "$DETECT" --root "$d" >/dev/null
grep -q -- '-scheme "Ondum"' "$d/.claude/test-cmd" \
  && ok 'TU22 (R-02) let projectName = "Ondum" + name: projectName -> -scheme "Ondum"' \
  || no 'TU22 (R-02) let projectName = "Ondum" + name: projectName -> -scheme "Ondum"'

d=$(mk tu23)
printf 'let project = Project(name: "Vibro", targets: [])\n' > "$d/Project.swift"
bash "$DETECT" --root "$d" >/dev/null
grep -q -- '-scheme "Vibro"' "$d/.claude/test-cmd" \
  && ok 'TU23 (R-02) single-line Project(name: "Vibro" -> -scheme "Vibro"' \
  || no 'TU23 (R-02) single-line Project(name: "Vibro" -> -scheme "Vibro"'

d=$(mk tu24)
cat > "$d/Project.swift" <<'EOF'
let project = Project(
    name: "Ondum",
    targets: [
        .target(name: "OndumApp", destinations: .macOS)
    ]
)
EOF
bash "$DETECT" --root "$d" >/dev/null
grep -q -- '-scheme "Ondum"' "$d/.claude/test-cmd" && ! grep -q -- '-scheme "OndumApp"' "$d/.claude/test-cmd" \
  && ok 'TU24 (R-02) multi-line name: "Ondum" before .target(name: "OndumApp" -> -scheme "Ondum" (first match)' \
  || no 'TU24 (R-02) multi-line name: "Ondum" before .target(name: "OndumApp" -> -scheme "Ondum" (first match)'

d=$(mk tu25)
printf 'name: MyProject\ntargets:\n  MyProject:\n    type: application\n' > "$d/project.yml"
bash "$DETECT" --root "$d" >/dev/null
grep -q -- '-scheme "MyProject"' "$d/.claude/test-cmd" \
  && ok 'TU25 (R-02) project.yml name: MyProject at column 1 -> -scheme "MyProject"' \
  || no 'TU25 (R-02) project.yml name: MyProject at column 1 -> -scheme "MyProject"'

d=$(mk Zed); : > "$d/Tuist.swift"
bash "$DETECT" --root "$d" >/dev/null
grep -q -- '-scheme "Zed"' "$d/.claude/test-cmd" \
  && ok 'TU26 (R-02) Tuist.swift-only in a dir named Zed -> -scheme "Zed" (basename fallback)' \
  || no 'TU26 (R-02) Tuist.swift-only in a dir named Zed -> -scheme "Zed" (basename fallback)'

d=$(mk tu27); : > "$d/Project.swift"
bash "$DETECT" --root "$d" >/dev/null
# plant: TU27 | plugin/scripts/detect-test-cmd.sh | '$dest' -derivedDataPath | '$dest'
grep -q -- "-derivedDataPath \"$d/.build/DerivedData\"" "$d/.claude/test-cmd" \
  && ok "TU27 (R-02) generated candidate carries -derivedDataPath at the absolute fixture root" \
  || no "TU27 (R-02) generated candidate carries -derivedDataPath at the absolute fixture root"

d=$(mk tu28)
cat > "$d/Project.swift" <<'EOF'
let projectName = "Comment"
let project = Project(
    name: projectName,
    targets: [
        .target(
            name: projectName,
            destinations: .macOS,                    // or [.iPhone, .iPad]
            product: .app
        )
    ]
)
EOF
bash "$DETECT" --root "$d" >/dev/null
# plant: TU28 | plugin/scripts/detect-test-cmd.sh | sed 's,//.*,,' "$MANIFEST" | cat "$MANIFEST"
grep -q -- "-destination 'platform=macOS'" "$d/.claude/test-cmd" && ! grep -q 'iOS Simulator' "$d/.claude/test-cmd" \
  && ok "TU28 (R-02) macOS destination with a trailing // or [.iPhone, .iPad] comment -> platform=macOS (comment-strip)" \
  || no "TU28 (R-02) macOS destination with a trailing // or [.iPhone, .iPad] comment -> platform=macOS (comment-strip)"

d=$(mk tu29)
cat > "$d/Project.swift" <<'EOF'
let projectName = "Handheld"
let project = Project(
    name: projectName,
    targets: [
        .target(
            name: projectName,
            destinations: [.iPhone, .iPad],
            product: .app
        )
    ]
)
EOF
bash "$DETECT" --root "$d" >/dev/null
grep -q 'iOS Simulator' "$d/.claude/test-cmd" \
  && ok "TU29 (R-02) destinations: [.iPhone, .iPad] outside a comment -> platform=iOS Simulator" \
  || no "TU29 (R-02) destinations: [.iPhone, .iPad] outside a comment -> platform=iOS Simulator"

d=$(mk tu30); : > "$d/Project.swift"
bash "$DETECT" --root "$d" >/dev/null
# plant: TU30 | plugin/scripts/detect-test-cmd.sh | exit 127; | exit 3;
grep -q -- 'command -v tuist' "$d/.claude/test-cmd" && grep -q -- 'exit 127' "$d/.claude/test-cmd" \
  && ok "TU30 (R-05) candidate carries the command -v tuist guard and exit 127" \
  || no "TU30 (R-05) candidate carries the command -v tuist guard and exit 127"

d=$(mk tu31); : > "$d/Project.swift"
bash "$DETECT" --root "$d" >/dev/null
grep -q -- 'DID-NOT-RUN:' "$d/.claude/test-cmd" \
  && ok "TU31 (R-05) candidate carries the legible DID-NOT-RUN: string" \
  || no "TU31 (R-05) candidate carries the legible DID-NOT-RUN: string"

d=$(mk tu32); : > "$d/Project.swift"
bash "$DETECT" --root "$d" >/dev/null
tu32lines=$(wc -l < "$d/.claude/test-cmd" | tr -d ' ')
tu32extracted=$(awk '{ l=$0; sub(/^[ \t]+/,"",l); sub(/[ \t]+$/,"",l); if(l=="" || substr(l,1,1)=="#") next; print l; exit }' "$d/.claude/test-cmd")
tu32full=$(cat "$d/.claude/test-cmd")
if [ "$tu32lines" = "1" ] && [ "$tu32extracted" = "$tu32full" ] \
  && printf '%s' "$tu32extracted" | grep -q 'tuist generate'; then
  ok "TU32 (R-02) generated candidate is one line, byte-identical to stop-gate.sh's own awk extraction"
else
  no "TU32 (R-02) generated candidate is one line, byte-identical to stop-gate.sh's own awk extraction"
fi

d=$(mk tu33); : > "$d/Project.swift"
bash "$DETECT" --root "$d" >/dev/null
tu33extracted=$(awk '{ l=$0; sub(/^[ \t]+/,"",l); sub(/[ \t]+$/,"",l); if(l=="" || substr(l,1,1)=="#") next; print l; exit }' "$d/.claude/test-cmd")
mkdir -p "$tmp/tu33-empty-path"
real_bash=$(command -v bash)
tu33err=$(PATH="$tmp/tu33-empty-path" "$real_bash" -c "$tu33extracted" 2>&1 >/dev/null); tu33rc=$?
if [ "$tu33rc" -eq 127 ] && printf '%s' "$tu33err" | grep -q 'DID-NOT-RUN' \
  && ! printf '%s' "$tu33err" | grep -qi 'xcodebuild'; then
  ok "TU33 (R-05) executed: empty PATH -> exit 127, stderr carries DID-NOT-RUN, no xcodebuild trace"
else
  no "TU33 (R-05) executed: empty PATH -> exit 127, stderr carries DID-NOT-RUN, no xcodebuild trace"
fi

d=$(mk tu34); : > "$d/Project.swift"
bash "$DETECT" --root "$d" >/dev/null
tu34extracted=$(awk '{ l=$0; sub(/^[ \t]+/,"",l); sub(/[ \t]+$/,"",l); if(l=="" || substr(l,1,1)=="#") next; print l; exit }' "$d/.claude/test-cmd")
tu34bin="$tmp/tu34-bin"; mkdir -p "$tu34bin"
printf '#!/bin/sh\nexit 0\n' > "$tu34bin/tuist"
printf '#!/bin/sh\nexit 65\n' > "$tu34bin/xcodebuild"
chmod +x "$tu34bin/tuist" "$tu34bin/xcodebuild"
PATH="$tu34bin:$PATH" bash -c "$tu34extracted" >/dev/null 2>&1
tu34rc=$?
[ "$tu34rc" -eq 65 ] \
  && ok "TU34 (R-05) executed: stub tuist(0)+xcodebuild(65) -> 65, distinguishable from DID-NOT-RUN" \
  || no "TU34 (R-05) executed: stub tuist(0)+xcodebuild(65) -> 65, distinguishable from DID-NOT-RUN"

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

# ---- TU99 — assertion-count floor for this whole file (issue #470, ADR-0165 §D6). Evaluated last,
# so PASS+FAIL already reflects every assertion above, TU and non-TU alike. Re-derived (never
# incremented by feel) at the end of every later task that adds TU assertions — CLAUDE.md rule 10:
# a floor absorbs its own plant, so this stays a floor (>=) rather than an exact count, since the
# roadmap-from-issues assertions above are themselves conditional on `jq` being on PATH. ----
tu99_total=$((PASS+FAIL))
tu99_floor=40
if [ "$tu99_total" -ge "$tu99_floor" ]; then
  ok "TU99 assertion-count floor ($tu99_total >= $tu99_floor)"
else
  no "TU99 assertion count fell to $tu99_total (floor $tu99_floor)"
fi

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
