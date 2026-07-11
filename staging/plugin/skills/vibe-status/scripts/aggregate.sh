#!/bin/bash
# vibe-status aggregate v1.0 — read-only, parallel harness, fail-graceful per section.
# Output: Markdown to stdout (default), JSON (--json), plain (--plain).
# Performance budget: <10s typical, 12s per-harness timeout.
# Bash 3.2-clean: no assoc array, no mapfile, no ${v^^}, no <().

set -u
# NO set -e: fail-graceful per section requires continuation on error.

# --- Args parsing ---
FORMAT="markdown"
SKIP_HARNESS=0
for arg in "$@"; do
  case "$arg" in
    --json)         FORMAT="json" ;;
    --plain)        FORMAT="plain" ;;
    --skip-harness) SKIP_HARNESS=1 ;;
  esac
done

TMO="${VIBE_STATUS_HARNESS_TIMEOUT:-12}"
TS=$(date "+%Y-%m-%d %H:%M")
START=$(date +%s)
TMP=$(mktemp -d)
RUNNER="$HOME/.claude/skills/vibe-status/scripts/harness-runner.sh"

# --- Section 1: Harness discovery + parallel exec ---
HARNESS_OK=0
HARNESS_FAIL=0
HARNESS_ERR=0
HARNESS_TOTAL=0
HARNESS_LINES=""

if [ "$SKIP_HARNESS" -eq 0 ]; then
  # Discover all harness files — skills
  for h in "$HOME"/.claude/skills/*/tests/run-tests.sh; do
    [ -f "$h" ] || continue
    [ -x "$h" ] || continue
    HARNESS_TOTAL=$((HARNESS_TOTAL + 1))
    name=$(basename "$(dirname "$(dirname "$h")")")
    ( bash "$RUNNER" "$h" "$TMO" >"$TMP/$name.out" 2>&1 ) &
  done
  # Discover standalone harness files in hooks/tests/
  for h in "$HOME"/.claude/hooks/tests/*.sh; do
    [ -f "$h" ] || continue
    [ -x "$h" ] || continue
    HARNESS_TOTAL=$((HARNESS_TOTAL + 1))
    name=$(basename "$h" .sh)
    ( bash "$RUNNER" "$h" "$TMO" >"$TMP/$name.out" 2>&1 ) &
  done
  wait

  # Parse results
  for f in "$TMP"/*.out; do
    [ -f "$f" ] || continue
    name=$(basename "$f" .out)
    head1=$(head -n 1 "$f")
    rc=$(echo "$head1" | sed -n 's/^RC=\([0-9]*\) .*/\1/p')
    dur=$(echo "$head1" | sed -n 's/.* DUR=\([0-9]*\)s/\1/p')
    pass=$(grep -E 'PASS=[0-9]+' "$f" | tail -n 1 | sed -n 's/.*PASS=\([0-9]*\).*/\1/p')
    fail=$(grep -E 'FAIL=[0-9]+' "$f" | tail -n 1 | sed -n 's/.*FAIL=\([0-9]*\).*/\1/p')
    pass="${pass:-?}"
    fail="${fail:-?}"
    dur="${dur:-?}"
    rc="${rc:-127}"
    if [ "$rc" = "124" ]; then
      status="TIMEOUT"
      HARNESS_ERR=$((HARNESS_ERR + 1))
    elif [ "$rc" = "0" ]; then
      status="OK"
      HARNESS_OK=$((HARNESS_OK + 1))
    elif [ "$rc" = "1" ]; then
      status="FAIL"
      HARNESS_FAIL=$((HARNESS_FAIL + 1))
    else
      status="ERROR"
      HARNESS_ERR=$((HARNESS_ERR + 1))
    fi
    HARNESS_LINES="${HARNESS_LINES}| $name | $pass | $fail | ${dur}s | $status |
"
  done
fi

# --- Section 2: ADR scan (cwd-local) ---
ADR_LINES=""
ADR_COUNT=0
ADR_DIR="$PWD/docs/architecture"
if [ -d "$ADR_DIR" ]; then
  for adr in "$ADR_DIR"/ADR-*.md; do
    [ -f "$adr" ] || continue
    # Skip companion files that match the ADR-*.md glob but are not ADRs
    # (e.g. ADR-NNNN-implementation-plan.md). Real ADRs carry a **Status:** line.
    case "$(basename "$adr")" in
      *-implementation-plan.md) continue ;;
    esac
    ADR_COUNT=$((ADR_COUNT + 1))
    title=$(head -n 1 "$adr" | sed 's/^# //')
    adr_status=$(grep -m1 '^\*\*Status:\*\*' "$adr" | sed 's/^\*\*Status:\*\* *//')
    ADR_LINES="${ADR_LINES}- $title — $adr_status
"
  done
fi

# --- Section 3: Manifests (cwd-local) ---
MANIFEST_COUNT=0
MANIFEST_LINES=""
MANIFEST_DIR="$PWD/docs/manifests"
if [ -d "$MANIFEST_DIR" ]; then
  for m in "$MANIFEST_DIR"/*.yaml; do
    [ -f "$m" ] || continue
    MANIFEST_COUNT=$((MANIFEST_COUNT + 1))
    MANIFEST_LINES="${MANIFEST_LINES}- $(basename "$m")
"
  done
fi

# --- Section 4: Triage state (cwd-local) ---
TRIAGE_LINE="(no recent triage cycle)"
TF=""
# Discover newest per-branch file: .claude/.triage-fix-last-<branch>.json
for f in "$PWD"/.claude/.triage-fix-last-*.json; do
  [ -f "$f" ] || continue
  if [ -z "$TF" ] || [ "$f" -nt "$TF" ]; then
    TF="$f"
  fi
done
# Legacy fallback: flat path
if [ -z "$TF" ] && [ -f "$PWD/.triage-fix-last.json" ]; then
  TF="$PWD/.triage-fix-last.json"
fi
if [ -n "$TF" ] && [ -f "$TF" ]; then
  if command -v jq >/dev/null 2>&1; then
    total=$(jq 'length' "$TF" 2>/dev/null); total="${total:-0}"
    openc=$(jq '[.[]|select(.status=="open")]|length' "$TF" 2>/dev/null); openc="${openc:-0}"
    resc=$(jq '[.[]|select(.status=="resolved")]|length' "$TF" 2>/dev/null); resc="${resc:-0}"
    base=$(basename "$TF")
    br=$(echo "$base" | sed -n 's/^\.triage-fix-last-\(.*\)\.json$/\1/p')
    [ -z "$br" ] && br="(legacy)"
    mt=$(stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$TF" 2>/dev/null || stat -c '%y' "$TF" 2>/dev/null | cut -c1-16)
    TRIAGE_LINE="$br — $total finding (open=$openc, resolved=$resc) — $mt"
  else
    TRIAGE_LINE="(jq missing — cannot parse)"
  fi
fi

# --- Section 5: Skills custom (globale) ---
SKILL_COUNT=0
SKILL_NAMES=""
for s in "$HOME"/.claude/skills/*/; do
  [ -d "$s" ] || continue
  SKILL_COUNT=$((SKILL_COUNT + 1))
  n=$(basename "$s")
  SKILL_NAMES="${SKILL_NAMES}$n, "
done
# Trim trailing ", "
SKILL_NAMES="${SKILL_NAMES%, }"

# --- Section 6: Hooks (parse settings.json) ---
HOOK_LINES="(unable to parse settings.json)"
S_JSON="$HOME/.claude/settings.json"
if [ -f "$S_JSON" ]; then
  if command -v jq >/dev/null 2>&1; then
    parsed=$(jq -r '.hooks // {} | to_entries[] | "- \(.key): \(.value | length) entries"' "$S_JSON" 2>/dev/null)
    if [ $? -eq 0 ]; then
      if [ -z "$parsed" ]; then
        HOOK_LINES="(no hooks configured)"
      else
        HOOK_LINES="$parsed"
      fi
    fi
    # If jq failed (non-zero), HOOK_LINES stays as "(unable to parse settings.json)"
  fi
fi

# --- Section 7: Memory head ---
MEM_LINE="(no memory file)"
ENC=$(printf '%s' "$PWD" | tr '/' '-')
MEM_FILE="$HOME/.claude/projects/$ENC/memory/MEMORY.md"
if [ -f "$MEM_FILE" ]; then
  pcount=$(grep -c '^\- \[' "$MEM_FILE" 2>/dev/null || echo 0)
  MEM_LINE="$pcount entries indexed in MEMORY.md"
fi

# --- Section 7b: Agent notes (ADR-0012, read-only, non-blocking) ---
AN_COUNT=0
AN_LINE="(no agent-notes)"
AN_DIR="$HOME/.claude/projects/$ENC/memory/agent-notes"
if [ -d "$AN_DIR" ]; then
  AN_COUNT=$(ls -1 "$AN_DIR"/*.md 2>/dev/null | grep -v 'README.md' | wc -l | tr -d ' ')
  if [ "$AN_COUNT" -gt 0 ]; then
    newest=$(ls -t "$AN_DIR"/*.md 2>/dev/null | grep -v 'README.md' | head -1)
    mt=""
    [ -n "$newest" ] && mt=$(stat -f '%Sm' -t '%Y-%m-%d' "$newest" 2>/dev/null || stat -c '%y' "$newest" 2>/dev/null | cut -d' ' -f1)
    if [ -n "$mt" ]; then
      AN_LINE="$AN_COUNT agent(s) with notes, newest $mt"
    else
      AN_LINE="$AN_COUNT agent(s) with notes"
    fi
  fi
fi

# --- Section 8: Background agents (requires CC 2.1.169+, --json --all) ---
AGENT_LINE="(not available)"
_ag_total=0; _ag_active=0; _ag_blocked=0; _ag_completed=0
if command -v claude >/dev/null 2>&1; then
  _agents_raw=$(claude agents --json --all 2>/dev/null) || true
  if command -v jq >/dev/null 2>&1; then
    if [ -n "$_agents_raw" ]; then
      _ag_total=$(echo "$_agents_raw"   | jq 'length' 2>/dev/null || echo 0)
      _ag_active=$(echo "$_agents_raw"  | jq '[.[]|select(.state=="active")]|length'    2>/dev/null || echo 0)
      _ag_blocked=$(echo "$_agents_raw" | jq '[.[]|select(.state=="blocked")]|length'   2>/dev/null || echo 0)
      _ag_completed=$(echo "$_agents_raw" | jq '[.[]|select(.state=="completed")]|length' 2>/dev/null || echo 0)
      if [ "${_ag_total:-0}" -eq 0 ]; then
        AGENT_LINE="(none)"
      else
        AGENT_LINE="${_ag_total} session(s) — active=${_ag_active}, blocked=${_ag_blocked}, completed=${_ag_completed}"
      fi
    else
      AGENT_LINE="(none)"
    fi
  else
    AGENT_LINE="(jq missing — cannot parse)"
  fi
fi

# --- Section 9: Overall status calc ---
META_ERROR=0
# settings.json not found is a metadata error (global, always expected)
[ ! -f "$S_JSON" ] && META_ERROR=1

if [ "$SKIP_HARNESS" -eq 0 ]; then
  if [ "$HARNESS_OK" -eq "$HARNESS_TOTAL" ] && [ "$META_ERROR" -eq 0 ]; then
    HEALTH="HEALTHY"
  elif [ "$HARNESS_FAIL" -ge 2 ] || { [ "$HARNESS_ERR" -eq "$HARNESS_TOTAL" ] && [ "$HARNESS_TOTAL" -gt 0 ]; }; then
    HEALTH="CRITICAL"
  else
    HEALTH="DEGRADED"
  fi
else
  HEALTH="UNKNOWN (skip-harness)"
fi

END=$(date +%s)
ELAPSED=$((END - START))

# --- Render ---
if [ "$FORMAT" = "json" ]; then
  printf '{"timestamp":"%s","health":"%s","harness":{"ok":%d,"fail":%d,"err":%d,"total":%d},"adr":%d,"manifests":%d,"skills":%d,"agent_notes":%d,"agents":{"total":%d,"active":%d,"blocked":%d,"completed":%d},"elapsed":%d}\n' \
    "$TS" "$HEALTH" "$HARNESS_OK" "$HARNESS_FAIL" "$HARNESS_ERR" "$HARNESS_TOTAL" \
    "$ADR_COUNT" "$MANIFEST_COUNT" "$SKILL_COUNT" "$AN_COUNT" \
    "$_ag_total" "$_ag_active" "$_ag_blocked" "$_ag_completed" "$ELAPSED"
else
  # Markdown (default) or plain — both use same structure for now
  printf '# Vibe-Coding System Status — %s\n\n' "$TS"
  printf '## Health: %s\n\n' "$HEALTH"

  if [ "$SKIP_HARNESS" -eq 1 ]; then
    printf '## Harness\n(skipped via --skip-harness)\n\n'
  else
    printf '## Harness (%d/%d passing)\n' "$HARNESS_OK" "$HARNESS_TOTAL"
    printf '| Skill | PASS | FAIL | Duration | Status |\n'
    printf '|---|---|---|---|---|\n'
    if [ -n "$HARNESS_LINES" ]; then
      printf '%s' "$HARNESS_LINES"
    else
      printf '(no harness found)\n'
    fi
    printf '\n'
  fi

  printf '## ADR (%d total in docs/architecture/)\n' "$ADR_COUNT"
  if [ -n "$ADR_LINES" ]; then
    printf '%s' "$ADR_LINES"
  else
    printf '(no project ADR directory)\n'
  fi
  printf '\n'

  printf '## In-flight manifests\n'
  if [ -n "$MANIFEST_LINES" ]; then
    printf '%s' "$MANIFEST_LINES"
  else
    printf '(none)\n'
  fi
  printf '\n'

  printf '## Recent triage cycle\n%s\n\n' "$TRIAGE_LINE"

  printf '## Skill custom (%d installed)\n%s\n\n' "$SKILL_COUNT" "$SKILL_NAMES"

  printf '## Hooks (settings.json)\n%s\n\n' "$HOOK_LINES"

  printf '## Memory\n%s\n\n' "$MEM_LINE"

  printf '## Agent notes (ADR-0012)\n%s\n\n' "$AN_LINE"

  printf '## Background sessions\n%s\n\n' "$AGENT_LINE"

  echo "---"
  echo "Legend: HEALTHY = all harness pass + no metadata error."
  echo "        DEGRADED = >=1 harness FAIL/TIMEOUT/ERROR or metadata parse error."
  echo "        CRITICAL = >=2 harness FAIL or all harness ERROR."
  printf 'Generated in %ds.\n' "$ELAPSED"
fi

rm -rf "$TMP"
exit 0
