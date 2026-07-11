#!/bin/bash
# Trust file migration CLI (NOT a hook). Usage: migrate-trust-paths.sh [--dry-run]
# Reads $STOP_GATE_TRUST_FILE (default ~/.claude/state/stop-gate/trust),
# normalizes each entry's path with the same norm_path semantics used by
# stop-gate.sh / approve-test-cmd.sh, deduplicates, atomic-writes back.
# With --dry-run, prints the projected output to stdout WITHOUT writing.
# Idempotent: re-running on already-normalized trust produces byte-identical file.
# Fail-safe: if trust file absent or empty, exits 0 with no-op.
set -u
DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1
TRUST="${STOP_GATE_TRUST_FILE:-$HOME/.claude/state/stop-gate/trust}"
[ -f "$TRUST" ] || { echo "migrate-trust-paths: trust file absent — nothing to do" >&2; exit 0; }
[ -s "$TRUST" ] || { echo "migrate-trust-paths: trust file empty — nothing to do" >&2; exit 0; }

# Identical to stop-gate.sh / approve-test-cmd.sh norm_path.
# Fail-open: if cd fails (dir gone), echo $1 unchanged (still apply lowercase below).
norm_path() {
  local p; p=$(cd "$1" 2>/dev/null && pwd -P) || { printf '%s' "$1"; return 0; }
  local sys="${STOP_GATE_UNAME:-$(uname)}"
  [ "$sys" = "Darwin" ] && p=$(printf '%s' "$p" | tr '[:upper:]' '[:lower:]')
  printf '%s' "$p"
}
# String-only fallback for entries whose path no longer exists on FS.
norm_str() {
  local p="$1"
  local sys="${STOP_GATE_UNAME:-$(uname)}"
  [ "$sys" = "Darwin" ] && p=$(printf '%s' "$p" | tr '[:upper:]' '[:lower:]')
  printf '%s' "$p"
}

tmp=$(mktemp) || { echo "migrate-trust-paths: mktemp failed" >&2; exit 1; }
# Read each line; split on tab; normalize path; emit <sha>\t<norm>.
# IFS=$'\t' splits on tab; -r prevents backslash interpretation.
while IFS=$'\t' read -r sha path; do
  [ -z "$sha" ] && continue
  [ -z "$path" ] && continue
  if [ -d "$path" ]; then
    norm=$(norm_path "$path")
  else
    norm=$(norm_str "$path")
  fi
  printf '%s\t%s\n' "$sha" "$norm" >> "$tmp"
done < "$TRUST"

# Dedup (sort -u is deterministic on identical input → idempotent).
sort -u "$tmp" > "$tmp.dedup" && mv "$tmp.dedup" "$tmp"

if [ "$DRY_RUN" -eq 1 ]; then
  cat "$tmp"; rm -f "$tmp"
  exit 0
fi

# Atomic replace.
mv "$tmp" "$TRUST"
n_after=$(wc -l < "$TRUST")
echo "migrate-trust-paths: trust normalized ($n_after entries)" >&2
exit 0
