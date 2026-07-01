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

CMD="NONE"; STACK="unknown"
if has "*.xcworkspace"; then
  ws=$(compgen -G "*.xcworkspace" | head -1); scheme="${ws%.xcworkspace}"
  STACK="xcode-workspace"
  CMD="xcodebuild test -workspace \"$ws\" -scheme \"$scheme\" -destination 'platform=iOS Simulator,name=iPhone 17'"
elif has "*.xcodeproj"; then
  pj=$(compgen -G "*.xcodeproj" | head -1); scheme="${pj%.xcodeproj}"
  STACK="xcode-project"
  CMD="xcodebuild test -project \"$pj\" -scheme \"$scheme\" -destination 'platform=iOS Simulator,name=iPhone 17'"
elif [ -f "Package.swift" ]; then
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
