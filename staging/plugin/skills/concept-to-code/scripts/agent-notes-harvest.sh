#!/bin/bash
# agent-notes-harvest.sh — ADR-0012 orchestrator-mediated agent memory helper.
#
# The orchestrator (never a subagent) uses this to read prior notes into a dispatch
# brief and to harvest a subagent's terminal `DURABLE NOTES:` section back to the
# central store. Subagents NEVER call this and NEVER resolve the encoded path (D2).
#
# Modes:
#   inject  <agent>   -> prints a `PRIOR AGENT NOTES` block (or `PRIOR AGENT NOTES: none yet`)
#                        to stdout, for embedding in the dispatch brief.
#   harvest <agent>   -> reads a subagent report from stdin, extracts the terminal
#                        `DURABLE NOTES:` section, appends well-formed notes to the
#                        agent's central store file. Never writes MEMORY.md.
#
# Store root (orchestrator-side resolution):
#   $AGENT_NOTES_ROOT overrides (used by the harness with a fixture dir).
#   Else: $HOME/.claude/projects/<ENC>/memory/agent-notes  where ENC = $PWD with '/'->'-'.
#   The encoding is the same fragile pattern noted in feedback_pretooluse-payload-schema:
#   acceptable HERE because it is confined to the orchestrator and a wrong encoding only
#   degrades to a missed harvest, never corruption. Never replicate this in a subagent.
#
# Truncation tolerance (lesson: feedback_subagent-truncation-transport):
#   - if the report stream has no trailing newline, its last (partial) line is dropped;
#   - only well-formed bullets `- [<category>] <content>` are harvested — a bullet cut
#     before its closing bracket fails the pattern and is dropped;
#   - a `DURABLE NOTES:` header with zero well-formed bullets writes nothing.
#
# 3.2-clean: no assoc array, no mapfile, no ${v^^}, no <().
set -u

MODE="${1:-}"
AGENT="${2:-}"

case "$MODE" in
  inject|harvest) ;;
  *) echo "usage: agent-notes-harvest.sh {inject|harvest} <agent>" >&2; exit 2 ;;
esac
[ -n "$AGENT" ] || { echo "error: missing <agent> argument" >&2; exit 2; }

if [ -n "${AGENT_NOTES_ROOT:-}" ]; then
  ROOT="$AGENT_NOTES_ROOT"
else
  ENC=$(printf '%s' "$PWD" | tr '/' '-')
  ROOT="$HOME/.claude/projects/$ENC/memory/agent-notes"
fi
STORE="$ROOT/$AGENT.md"

# ---- inject ---------------------------------------------------------------
if [ "$MODE" = "inject" ]; then
  if [ -s "$STORE" ]; then
    echo "PRIOR AGENT NOTES (read-only context — past durable decisions/patterns for the $AGENT on this project; factor in, do not repeat settled work):"
    cat "$STORE"
  else
    echo "PRIOR AGENT NOTES: none yet"
  fi
  exit 0
fi

# ---- harvest --------------------------------------------------------------
REPORT=$(mktemp)
trap 'rm -f "$REPORT" "$REPORT.t"' EXIT
cat > "$REPORT"

# Drop a trailing partial line if the stream was truncated mid-line.
if [ -s "$REPORT" ] && [ -n "$(tail -c1 "$REPORT")" ]; then
  sed '$d' "$REPORT" > "$REPORT.t" && mv "$REPORT.t" "$REPORT"
fi

HDR_LINE=$(grep -n '^DURABLE NOTES:' "$REPORT" | tail -1 | cut -d: -f1)
if [ -z "$HDR_LINE" ]; then
  echo "harvest($AGENT): no DURABLE NOTES section — nothing written"
  exit 0
fi

HDR=$(sed -n "${HDR_LINE}p" "$REPORT" | sed 's/[[:space:]]*$//')
if [ "$HDR" = "DURABLE NOTES: none" ]; then
  echo "harvest($AGENT): DURABLE NOTES: none — nothing written"
  exit 0
fi

NOTES=$(sed -n "$((HDR_LINE+1)),\$p" "$REPORT" | grep -E '^- \[[^]]+\] .+' || true)
if [ -z "$NOTES" ]; then
  echo "harvest($AGENT): header present but no well-formed notes (possibly truncated) — nothing written"
  exit 0
fi

mkdir -p "$ROOT"
{
  echo ""
  echo "## $(date '+%Y-%m-%d') — harvested ($AGENT)"
  printf '%s\n' "$NOTES"
} >> "$STORE"
N=$(printf '%s\n' "$NOTES" | grep -c '^- ')
echo "harvest($AGENT): appended $N note(s) to $STORE"
exit 0
