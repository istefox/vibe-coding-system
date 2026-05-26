#!/usr/bin/env bash
set -euo pipefail
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FILE_PATH" ] && exit 0
case "$FILE_PATH" in
  *.py)
    command -v ruff >/dev/null 2>&1 && { ruff format "$FILE_PATH" 2>/dev/null || true; ruff check --fix "$FILE_PATH" 2>/dev/null || true; }
    ;;
  *.ts|*.tsx|*.js|*.jsx)
    if [ -f package.json ] && command -v npx >/dev/null 2>&1; then npx --no-install prettier --write "$FILE_PATH" 2>/dev/null || true; fi
    ;;
  *.swift)
    command -v swift-format >/dev/null 2>&1 && { swift-format -i "$FILE_PATH" 2>/dev/null || true; }
    ;;
esac
exit 0
