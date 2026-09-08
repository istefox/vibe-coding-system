#!/bin/bash
# enumerate-sources.test.sh (R-04, ADR-0197 §D9, migrate-deep-refactor-out-of-vendored-pa) —
# the LIVE-SIDE behavioural probe for the deployed
# $HOME/.claude/skills/deep-refactor/scripts/enumerate-sources.sh. Run it by hand when
# `sync-to-claude.sh`'s dry-run drift report says DRIFT for this file, to tell a cosmetic change
# in the deployed copy apart from an actual contract break: this asserts *whether the contract
# still holds*, where the drift report only says *that* the byte content changed.
# It stays pointed at the deployed copy on purpose (never the staging one — that is
# refactor-snapshot-deep-refactor.test.sh's Section B, the CI-runnable compatibility contract
# test). By design this file sits outside `docs-ci.yml`'s shell-tests list AND outside
# `plant-check.sh`'s `staging/plugin/scripts/tests/*.test.sh` glob — `.claude/test-ignore`
# already documents that perimeter boundary. Because it is outside `plant-check.sh`'s
# perimeter, no plant is declarable for any assertion below (rule 2 does not apply here; there
# is nothing for plant-check.sh to sweep).
# Bash 3.2-clean: no assoc arrays, no mapfile, no process substitution, no <<<, no ${v^^}
# Uses mktemp -d for isolation; trap cleans up on exit.
set -u

SCRIPT="$HOME/.claude/skills/deep-refactor/scripts/enumerate-sources.sh"

# Rule-4 guard: "did not run" is not "found nothing". Without this, an absent deployed copy
# (e.g. a machine that never ran sync-to-claude.sh, or CI, which never deploys to $HOME) would
# fall straight into the 13 tests below and print 13 FAILs that read as 13 contract breaks,
# instead of the one true state: this probe never ran.
if [ ! -f "$SCRIPT" ]; then
  printf 'DID-NOT-RUN: live script absent: %s\n' "$SCRIPT"
  exit 3
fi

TMP="$(mktemp -d)"
PASS=0; FAIL=0

ok()  { PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Set up a mini git repo with a representative file tree
# ---------------------------------------------------------------------------
REPO="$TMP/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email "test@test.local"
git -C "$REPO" config user.name "Test"

# Normal source file — must be included
mkdir -p "$REPO/Sources/App"
printf 'import Foundation\n' > "$REPO/Sources/App/normal.swift"
git -C "$REPO" add Sources/App/normal.swift

# DerivedData/ — must be excluded
mkdir -p "$REPO/DerivedData/Build"
printf 'generated\n' > "$REPO/DerivedData/Build/foo.swift"
git -C "$REPO" add DerivedData/Build/foo.swift

# Pods/ — must be excluded
mkdir -p "$REPO/Pods/Alamofire"
printf 'pod\n' > "$REPO/Pods/Alamofire/bar.swift"
git -C "$REPO" add Pods/Alamofire/bar.swift

# .build/ — must be excluded
mkdir -p "$REPO/.build/release"
printf 'build\n' > "$REPO/.build/release/baz.swift"
git -C "$REPO" add ".build/release/baz.swift"

# *.generated.swift — must be excluded
printf 'generated\n' > "$REPO/Sources/App/auto.generated.swift"
git -C "$REPO" add "Sources/App/auto.generated.swift"

# *.xcarchive (treated as directory with files) — must be excluded
mkdir -p "$REPO/MyApp.xcarchive/Products"
printf 'archive\n' > "$REPO/MyApp.xcarchive/Products/bar"
git -C "$REPO" add "MyApp.xcarchive/Products/bar"

# Additional source file in a subdirectory for path-override tests
mkdir -p "$REPO/Sources/Models"
printf 'struct Model {}\n' > "$REPO/Sources/Models/Model.swift"
git -C "$REPO" add "Sources/Models/Model.swift"

# A file outside Sources/ to confirm path-override restricts scope
printf '// top level\n' > "$REPO/AppDelegate.swift"
git -C "$REPO" add "AppDelegate.swift"

git -C "$REPO" commit -q -m "test fixture"

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

# 1. normal.swift is included
OUT="$(bash "$SCRIPT" "$REPO" 2>/dev/null)"
printf '%s\n' "$OUT" | grep -q "Sources/App/normal.swift" \
  && ok "normal.swift included" \
  || bad "normal.swift included"

# 2. DerivedData/ files are excluded
printf '%s\n' "$OUT" | grep -q "DerivedData/" \
  && bad "DerivedData/ excluded" \
  || ok "DerivedData/ excluded"

# 3. Pods/ files are excluded
printf '%s\n' "$OUT" | grep -q "Pods/" \
  && bad "Pods/ excluded" \
  || ok "Pods/ excluded"

# 4. .build/ files are excluded
printf '%s\n' "$OUT" | grep -q "\.build/" \
  && bad ".build/ excluded" \
  || ok ".build/ excluded"

# 5. *.generated.swift files are excluded
printf '%s\n' "$OUT" | grep -q "auto\.generated\.swift" \
  && bad "*.generated.swift excluded" \
  || ok "*.generated.swift excluded"

# 6. *.xcarchive files/dirs are excluded
printf '%s\n' "$OUT" | grep -q "\.xcarchive" \
  && bad "*.xcarchive excluded" \
  || ok "*.xcarchive excluded"

# 7. path-override restricts scope to Sources/ prefix only
OUT_SCOPED="$(bash "$SCRIPT" "$REPO" "Sources/" 2>/dev/null)"
printf '%s\n' "$OUT_SCOPED" | grep -q "AppDelegate.swift" \
  && bad "path-override: AppDelegate.swift excluded from Sources/ scope" \
  || ok "path-override: AppDelegate.swift excluded from Sources/ scope"

# 8. path-override includes files under the given prefix
printf '%s\n' "$OUT_SCOPED" | grep -q "Sources/App/normal.swift" \
  && ok "path-override: Sources/ includes Sources/App/normal.swift" \
  || bad "path-override: Sources/ includes Sources/App/normal.swift"

# 9. path-override still applies exclude globs (generated files inside Sources/ still excluded)
printf '%s\n' "$OUT_SCOPED" | grep -q "auto\.generated\.swift" \
  && bad "path-override: generated files still excluded within Sources/" \
  || ok "path-override: generated files still excluded within Sources/"

# 10. non-git directory exits non-zero
NOGIT="$TMP/nogit"
mkdir -p "$NOGIT"
bash "$SCRIPT" "$NOGIT" > /dev/null 2>&1
EXIT_CODE=$?
[ "$EXIT_CODE" -ne 0 ] \
  && ok "non-git dir: exit non-zero" \
  || bad "non-git dir: exit non-zero"

# 11. non-git directory prints error to stderr
STDERR_OUT="$(bash "$SCRIPT" "$NOGIT" 2>&1 >/dev/null)"
printf '%s\n' "$STDERR_OUT" | grep -q "not a git repository" \
  && ok "non-git dir: error printed to stderr" \
  || bad "non-git dir: error printed to stderr"

# 12. no output when no files match path-override
OUT_EMPTY="$(bash "$SCRIPT" "$REPO" "NonExistentDir/" 2>/dev/null)"
[ -z "$OUT_EMPTY" ] \
  && ok "empty output on no match (caller handles 0-files)" \
  || bad "empty output on no match (caller handles 0-files)"

# 13. same-prefix false positive: OtherSources/ must NOT match "Sources/" scope
mkdir -p "$REPO/OtherSources"
printf '// other\n' > "$REPO/OtherSources/Other.swift"
git -C "$REPO" add "OtherSources/Other.swift"
git -C "$REPO" commit -q -m "add OtherSources"
OUT_PREFIX="$(bash "$SCRIPT" "$REPO" "Sources/" 2>/dev/null)"
printf '%s\n' "$OUT_PREFIX" | grep -q "OtherSources/Other.swift" \
  && bad "path-override: OtherSources/ not matched by Sources/ prefix" \
  || ok "path-override: OtherSources/ not matched by Sources/ prefix"

# ---------------------------------------------------------------------------
printf -- '----\n'
printf 'PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
