#!/usr/bin/env bash
set -euo pipefail
INPUT=$(cat)
FILE_PATH=$(printf '%s\n' "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FILE_PATH" ] && exit 0
PROTECTED=(".env" ".env." "secrets" ".pem" ".key" "credentials" "/.git/" "package-lock.json")
for p in "${PROTECTED[@]}"; do
  if [[ "$FILE_PATH" == *"$p"* ]]; then
    printf 'Blocked: %s matches protected pattern '\''%s'\''. Ask Stefano explicitly.\n' "$FILE_PATH" "$p" >&2
    exit 2
  fi
done
exit 0
