#!/bin/bash
# design-url-check v1.0 — Claude Design shared-URL SHAPE CHECKER (VCS-052; ADR-0181).
#
# CONTRACT. This is a CHECKER (rule 5): the exit code is the policy channel — the
# gate branches on it, it does not scan stdout for a sentinel.
#   exit 0  URL shape valid (matches ^https://claude\.ai/)
#   exit 1  URL non-empty and does NOT match the shape          stdout: nothing
#   exit 2  bad invocation                                       stdout: nothing
#   exit 3  DID-NOT-RUN — no --url given, or an empty --url value (rule 4, "did not
#           run" is not "found nothing"). The caller (Gate 1d) must still record the
#           pasted URL and write "URL shape check: did-not-run" into DESIGN.md —
#           never silently "valid".
#
# It must NOT fetch the URL (plan §5). The resource is org-scoped and login-walled:
# a fetch returns 401/404 for a perfectly valid link, and a 200 would prove nothing
# about the design's content either way. Shape only. The real validation is the
# human who pasted it.
#
# Ship the broad prefix `^https://claude\.ai/` and narrow only once a real
# claude.ai/design share-URL shape is confirmed — a guessed narrow regex fails
# closed on every valid link (could-not-verify item, plan §"Could not verify").
#
# Bash 3.2 clean: no assoc arrays, no mapfile, no process substitution, no <<<.
set -u

SELF="design-url-check"

usage() {
  [ "${1:-}" = "" ] || printf '%s: %s\n' "$SELF" "$1" >&2
  cat >&2 <<'EOF'
usage: design-url-check.sh --url <url>

stdout: nothing on any path — this checker signals through the exit code alone.
Exit: 0 valid shape | 1 non-empty and non-matching | 2 bad invocation |
      3 DID-NOT-RUN (no --url given, or --url was empty).
EOF
}

URL=""
HAVE_URL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --url)
      [ $# -ge 2 ] || { usage "--url needs a value"; exit 2; }
      URL="$2"; HAVE_URL=1; shift 2 ;;
    -h|--help)
      usage; exit 2 ;;
    *)
      usage "unrecognized argument: $1"; exit 2 ;;
  esac
done

if [ "$HAVE_URL" -eq 0 ] || [ -z "$URL" ]; then
  exit 3
fi

if printf '%s' "$URL" | grep -Eq '^https://claude\.ai/'; then
  exit 0
fi

exit 1
