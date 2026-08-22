#!/usr/bin/env bash
# detect-test-cmd v1.0 (ADR-0023 D3). Detects the stack and writes a .claude/test-cmd CANDIDATE
# if none exists. Writes the file only; it NEVER registers TOFU trust (that stays human,
# ADR-0014/0020). The human runs approve-test-cmd.sh once after reviewing the candidate.
#
# Usage: detect-test-cmd.sh --root <dir> [--dry-run]
# Bash 3.2 clean.
set -euo pipefail

ROOT="."; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    *) echo "detect-test-cmd: unknown arg $1" >&2; exit 2 ;;
  esac
done
[ -d "$ROOT" ] || { echo "detect-test-cmd: not a dir: $ROOT" >&2; exit 2; }
cd "$ROOT"

has() { compgen -G "$1" >/dev/null 2>&1; }   # glob-exists test, quiet

# -derivedDataPath (issue #488, ADR-0159): without it the build root is whatever the machine's
# Xcode build-location preference says, which for a custom absolute location is shared by every
# checkout on the machine — worktrees included. Two concurrent `xcodebuild` runs (a tester's
# worktree and a coder's, or a worktree and the main checkout's controller-side verification) then
# overwrite each other's products; observed cost was an unsigned framework and a false red, but the
# dangerous direction is the opposite one, a stale product reporting green on a broken tree.
# `"$PWD"` here is `$ROOT` (already `cd`-ed into, above) at DETECTION time, so the value written
# to `.claude/test-cmd` is an absolute, per-checkout path from the start — it does not depend on the
# invoker's cwd matching `$ROOT` when the command runs later, only on `$ROOT` itself not moving.
CMD="NONE"; STACK="unknown"
if [ -f "Project.swift" ] || [ -f "Tuist.swift" ] || [ -f "project.yml" ] || [ -f "project.yaml" ]; then
  # issue #470, ADR-0165 D1: checked FIRST, ahead of the *.xcworkspace / *.xcodeproj globs below.
  # Those artifacts are gitignored on exactly the projects this branch is for (ADR-0068's
  # baseRef: head forks a worktree from the tracked tree only), so on a fresh worktree they match
  # nothing and on a stale checkout they match the wrong thing. The manifest is tracked and present
  # in every worktree. Plain [ -f ] tests, not globs — these are exact, known filenames.
  STACK="xcode-project-generated"
  if [ -f "Project.swift" ] || [ -f "Tuist.swift" ]; then
    TOOL="tuist"; REGEN="tuist generate --no-open"
    if [ -f "Project.swift" ]; then MANIFEST="Project.swift"; else MANIFEST="Tuist.swift"; fi
  else
    TOOL="xcodegen"; REGEN="xcodegen generate"
    if [ -f "project.yml" ]; then MANIFEST="project.yml"; else MANIFEST="project.yaml"; fi
  fi

  # Scheme name (ADR-0165 D4), first match wins, no tool executed, no command substitution left in
  # the written candidate:
  #   let projectName = "X"  ->  Project(name: "X"  ->  ^\s*name: "X"  ->  ^name: X  ->  basename
  scheme=""
  if [ -f "$MANIFEST" ]; then
    scheme=$(sed -n -E 's/.*let[[:space:]]+projectName[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/p' "$MANIFEST" | head -1)
    if [ -z "$scheme" ]; then
      scheme=$(sed -n -E 's/.*Project\([[:space:]]*name:[[:space:]]*"([^"]*)".*/\1/p' "$MANIFEST" | head -1)
    fi
    if [ -z "$scheme" ]; then
      scheme=$(sed -n -E 's/^[[:space:]]*name:[[:space:]]*"([^"]*)".*/\1/p' "$MANIFEST" | head -1)
    fi
    if [ -z "$scheme" ]; then
      scheme=$(sed -n -E 's/^name:[[:space:]]*([^[:space:]]*).*/\1/p' "$MANIFEST" | head -1)
    fi
  fi
  if [ -z "$scheme" ]; then
    scheme=$(basename "$PWD")
  fi

  # Platform (ADR-0165 D4), scanned from a COMMENT-STRIPPED copy: git-repo-init's own Project.swift
  # template carries the iOS spelling inside a trailing `// or [.iPhone, .iPad]` comment on the very
  # line that selects macOS, so the strip is not optional.
  stripped=""
  if [ -f "$MANIFEST" ]; then
    case "$MANIFEST" in
      project.yml|project.yaml) stripped=$(sed 's/#.*//' "$MANIFEST") ;;
      *) stripped=$(sed 's,//.*,,' "$MANIFEST") ;;
    esac
  fi
  if printf '%s\n' "$stripped" | grep -E 'destinations:|deploymentTargets:|platform:' | grep -qE '\.iOS|\.iPhone|\.iPad|iOS'; then
    dest="platform=iOS Simulator,name=iPhone 17"
  else
    dest="platform=macOS"
  fi

  # cd-anchored (stop-gate.sh runs this via `bash -c` with no cd of its own), the regeneration
  # tool guarded by `command -v` with a legible DID-NOT-RUN: string and exit 127 (ADR-0165 D5) if
  # absent from PATH at run time, then the regeneration command, then -scheme (never -project /
  # -workspace, ADR-0165 D3) with the same absolute per-checkout -derivedDataPath as the two
  # branches below (ADR-0159 D1).
  CMD="cd \"$PWD\" && command -v $TOOL >/dev/null 2>&1 || { echo 'DID-NOT-RUN: $TOOL absent from PATH - the generated Xcode project was NOT regenerated and its tests were NOT run (issue #470, ADR-0165)' >&2; exit 127; }; $REGEN && xcodebuild test -scheme \"$scheme\" -destination '$dest' -derivedDataPath \"$PWD/.build/DerivedData\""
elif has "*.xcworkspace"; then
  ws=$(compgen -G "*.xcworkspace" | head -1); scheme="${ws%.xcworkspace}"
  STACK="xcode-workspace"
  CMD="xcodebuild test -workspace \"$ws\" -scheme \"$scheme\" -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath \"$PWD/.build/DerivedData\""
elif has "*.xcodeproj"; then
  pj=$(compgen -G "*.xcodeproj" | head -1); scheme="${pj%.xcodeproj}"
  STACK="xcode-project"
  CMD="xcodebuild test -project \"$pj\" -scheme \"$scheme\" -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath \"$PWD/.build/DerivedData\""
elif [ -f "Package.swift" ] || [ -f "Tuist/Package.swift" ]; then
  # issue #470, ADR-0165: detection fix only. Tuist.swift/Project.swift already win the branch
  # above when present; this closes the worktree-visibility gap for a plain SwiftPM library under
  # Tuist, where the manifest lives at Tuist/Package.swift, not root. CMD stays "swift test".
  STACK="swift-package"; CMD="swift test"
elif [ -f "package.json" ]; then
  STACK="node"
  if grep -q '"test"[[:space:]]*:' package.json 2>/dev/null; then CMD="npm test"; else CMD="NONE"; fi
elif [ -f "pyproject.toml" ] || [ -f "setup.py" ] || [ -f "setup.cfg" ] || [ -f "requirements.txt" ]; then
  STACK="python"; CMD="python3 -m pytest"
elif [ -f "Cargo.toml" ]; then
  STACK="rust"; CMD="cargo test"
elif [ -f "go.mod" ]; then
  STACK="go"; CMD="go test ./..."
fi

TARGET=".claude/test-cmd"
if [ -f "$TARGET" ]; then
  echo "detect-test-cmd: $TARGET already present, leaving it untouched (stack: $STACK)"
  exit 0
fi

echo "detect-test-cmd: stack=$STACK candidate=[$CMD]"
if [ "$DRY" -eq 1 ]; then
  echo "[dry-run] would write $TARGET"
  exit 0
fi
mkdir -p .claude
printf '%s\n' "$CMD" > "$TARGET"
echo "detect-test-cmd: wrote $TARGET (NOT trusted — run: approve-test-cmd.sh \"$(pwd -P)\")"
