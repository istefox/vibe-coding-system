#!/bin/bash
# vendor-checks.sh v1.0 — copies the deterministic CI check scripts into a target repo's
# .claude/scripts/ (issue #108; ADR-0054 §D3/§D4).
#
# WHY VENDORED, NOT FETCHED (ADR-0054 §D3). A CI run that reaches the network to fetch its own
# security gates has made those gates depend on an external service being up and honest. A
# vendored copy is pinned — a change needs a visible diff in the PR that introduced it — and
# reviewable in that same PR. The cost is drift, accepted deliberately: the same trade
# sync-to-claude.sh already makes for ~/.claude. Nothing here refreshes the copies automatically;
# re-run this script by hand whenever the source scripts change upstream.
#
# WHAT IT COPIES, BYTE-IDENTICAL, NEVER MODIFIED (ADR-0054 §D1 / this feature's headline
# constraint, pinned by project-ci-checks.test.sh section CE): secret-scan.sh, dependency-scan.sh
# and interface-check.sh from this same directory, plus weakening-scan.sh from
# review-triage-fix/scripts/ — the one script in this family that lives beside a skill rather than
# standalone (the same cross-skill script dependency ADR-0047 §A2 already accepted for the same
# reason: one source of truth, not a second copy that drifts on its own).
#
# HOUSE RULE: never overwrite an existing file without showing the diff first. Dry-run by default
# — every changed or new target is reported, nothing is written; --apply is what writes. The diff
# for a CHANGED file is printed unconditionally, --apply or not, mirroring sync-to-claude.sh's
# exact idiom (same repository, same convention, same reviewer expectation).
#
# SOURCE REVISION RECORDED (ADR-0054 §D3, "so a stale copy is identifiable"). A
# .claude/scripts/VENDORED manifest lists the copied files plus the source repository's HEAD SHA
# and that commit's own date — never wall-clock "now". Two vendoring runs against the same source
# commit therefore produce a byte-identical manifest (idempotent), not one that differs only by
# the moment the command happened to run.
#
# Bash 3.2 clean: no assoc arrays, no mapfile, no process substitution, no <<<.
set -u

SELF="vendor-checks"

usage() {
  [ "${1:-}" = "" ] || printf '%s: %s\n' "$SELF" "$1" >&2
  cat >&2 <<'EOF'
usage: vendor-checks.sh <target-repo-root> [--apply]

Copies secret-scan.sh, dependency-scan.sh, weakening-scan.sh and interface-check.sh into
<target-repo-root>/.claude/scripts/, plus a VENDORED manifest recording the source revision.
Dry-run by default (reports what would change, writes nothing); --apply writes.
EOF
}

TARGET=""; APPLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) usage "unknown flag: $1"; exit 2 ;;
    *)
      [ -n "$TARGET" ] && { usage "target-repo-root given twice"; exit 2; }
      TARGET="$1"; shift ;;
  esac
done

[ -n "$TARGET" ] || { usage "missing <target-repo-root>"; exit 2; }
[ -d "$TARGET" ] || { usage "not a directory: $TARGET"; exit 2; }

SCRIPTS=$(cd "$(dirname "$0")" && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
REPO=$(cd "$STAGING/.." && pwd)
DEST="$TARGET/.claude/scripts"
mkdir -p "$DEST" 2>/dev/null || { printf '%s: cannot create %s\n' "$SELF" "$DEST" >&2; exit 2; }

# src (relative to $STAGING) | dst basename under $DEST
PAIRS_LOCAL="
plugin/scripts/secret-scan.sh|secret-scan.sh
plugin/scripts/dependency-scan.sh|dependency-scan.sh
plugin/scripts/interface-check.sh|interface-check.sh
plugin/skills/review-triage-fix/scripts/weakening-scan.sh|weakening-scan.sh
"

printf '%s\n' "$PAIRS_LOCAL" | while IFS='|' read -r src dst; do
  [ -z "$src" ] && continue
  s="$STAGING/$src"; d="$DEST/$dst"
  [ -f "$s" ] || { printf '%s: source missing: %s\n' "$SELF" "$src" >&2; continue; }
  if [ ! -f "$d" ]; then
    printf '\n== NEW: %s\n' "$dst"
    [ "$APPLY" -eq 1 ] && { cp "$s" "$d"; chmod +x "$d"; printf '   written\n'; }
  elif ! diff -q "$s" "$d" >/dev/null 2>&1; then
    printf '\n== CHANGED: %s\n' "$dst"
    diff -u "$d" "$s" | sed 's/^/   /'
    [ "$APPLY" -eq 1 ] && { cp "$s" "$d"; chmod +x "$d"; printf '   overwritten\n'; }
  fi
done

# --- the VENDORED manifest: which files, from what source revision (§D3). Deterministic per
# commit (SHA + that commit's own date, never wall-clock "now"), so two runs against the same
# source commit are byte-identical — idempotency for the manifest, not just the scripts. ---------
REV=$(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo unknown)
REVDATE=$(git -C "$REPO" log -1 --format=%cI "$REV" 2>/dev/null || echo unknown)
MANIFEST="$DEST/VENDORED"
TMPMANIFEST=$(mktemp) || { printf '%s: cannot create a temp file\n' "$SELF" >&2; exit 2; }
trap 'rm -f "$TMPMANIFEST"' EXIT
{
  printf '# Vendored by vendor-checks.sh (issue #108, ADR-0054) — do not hand-edit, re-run to refresh.\n'
  printf '# Source revision: %s (%s)\n' "$REV" "$REVDATE"
  printf 'secret-scan.sh\n'
  printf 'dependency-scan.sh\n'
  printf 'weakening-scan.sh\n'
  printf 'interface-check.sh\n'
} >"$TMPMANIFEST"

if [ ! -f "$MANIFEST" ]; then
  printf '\n== NEW: VENDORED\n'
  [ "$APPLY" -eq 1 ] && { cp "$TMPMANIFEST" "$MANIFEST"; printf '   written\n'; }
elif ! diff -q "$TMPMANIFEST" "$MANIFEST" >/dev/null 2>&1; then
  printf '\n== CHANGED: VENDORED\n'
  diff -u "$MANIFEST" "$TMPMANIFEST" | sed 's/^/   /'
  [ "$APPLY" -eq 1 ] && { cp "$TMPMANIFEST" "$MANIFEST"; printf '   overwritten\n'; }
fi

[ "$APPLY" -eq 0 ] && printf '\n(dry-run — no files written. Re-run with --apply after reviewing.)\n'
exit 0
