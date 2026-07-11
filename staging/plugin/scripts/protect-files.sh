#!/usr/bin/env bash
set -u
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
[ -z "$FILE_PATH" ] && exit 0
PROTECTED=(".env" ".env." "secrets" ".pem" ".key" "credentials" "/.git/" "package-lock.json")
for p in "${PROTECTED[@]}"; do
  if [[ "$FILE_PATH" == *"$p"* ]]; then
    echo "Blocked: $FILE_PATH matches protected pattern '$p'. Ask Stefano explicitly." >&2
    exit 2
  fi
done
exit 0
