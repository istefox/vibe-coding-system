#!/usr/bin/env bash
# chain-memory-capture.sh — PostToolUse(Bash) hook.
# Records concept-to-code chain task completion + state of fact into the native
# Claude memory store, so progress persists across sessions and is browsable via
# /memory. Fires in the ORCHESTRATOR session only (manifest helpers are
# orchestrator-run), so it never depends on subagent hook propagation (ADR-0016).
# Deterministic, zero-LLM. Observational: ALWAYS exits 0, never blocks the tool.
# See ADR-0021. Mirrors the namespace pattern of ADR-0012 (agent-notes/).
#
# NOTE: deliberately NOT `set -e`. Every step is best-effort; a parse/IO failure
# degrades to a no-op, never an error that would disturb the Bash tool flow.
set -uo pipefail

# --- 0. Read payload (tolerant; jq absent or bad JSON → no-op) -----------------
command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat 2>/dev/null) || exit 0
[ -z "$INPUT" ] && exit 0

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# --- 1. Gate on helper identity ------------------------------------------------
# Only manifest mutation helpers are of interest; everything else is a no-op.
HELPER=$(printf '%s' "$COMMAND" | grep -oE 'manifest-(transition|set-gate|set-flag|set-artifact)\.sh' | head -1)
[ -z "$HELPER" ] && exit 0

# --- 2. Gate on success --------------------------------------------------------
# If an exit code is present and non-zero, the mutation failed → record nothing.
# (Bash tool_response does not always carry exit_code; absent → assume success.)
EXIT_CODE=$(printf '%s' "$INPUT" | jq -r '.tool_response.exit_code // .tool_response.exitCode // empty' 2>/dev/null)
if [ -n "$EXIT_CODE" ] && [ "$EXIT_CODE" != "0" ]; then exit 0; fi

# --- 3. Locate the manifest argument and derive the topic slug -----------------
MANIFEST=$(printf '%s' "$COMMAND" | grep -oE '[^[:space:]"'\'']+\.manifest\.yml' | head -1)
[ -z "$MANIFEST" ] && exit 0
MANIFEST_BASE=$(basename "$MANIFEST")
# YYYY-MM-DD-<slug>.manifest.yml → <slug>
SLUG=$(printf '%s' "$MANIFEST_BASE" | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}-//; s/\.manifest\.yml$//')
[ -z "$SLUG" ] && exit 0

# --- 4. Resolve the native memory dir for THIS project (scope-safe) ------------
# Robust: derive from dirname(transcript_path) — never re-encode $PWD (ADR-0012
# D2 / encoding fragility). The transcript lives under
# ~/.claude/projects/<encoded>/<session>.jsonl, so its dirname IS the project dir.
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
if [ -n "$TRANSCRIPT" ]; then
  PROJ_DIR=$(dirname "$TRANSCRIPT")
else
  # Fallback only (older CC without transcript_path): single residual encoding risk.
  ENCODED=$(printf '%s' "$PWD" | tr '/' '-')
  PROJ_DIR="$HOME/.claude/projects/$ENCODED"
fi
MEM_DIR="$PROJ_DIR/memory"
HIST_DIR="$MEM_DIR/chain-history"
HIST_FILE="$HIST_DIR/$SLUG.md"
MEM_FILE="$MEM_DIR/MEMORY.md"
mkdir -p "$HIST_DIR" 2>/dev/null || exit 0

# --- 5. Parse the event semantics from the command ----------------------------
# Strip everything up to and including the first ".sh", drop quotes, tokenize.
ARGS_PART="${COMMAND#*.sh}"
ARGS_PART=$(printf '%s' "$ARGS_PART" | tr -d '"'\''')
# shellcheck disable=SC2206
read -r -a A <<< "$ARGS_PART"   # A[0]=manifest, A[1]=arg1, A[2]=arg2 ...

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown")
EVENT=""
case "$HELPER" in
  manifest-transition.sh) EVENT="transition  → step=${A[1]:-?}" ;;
  manifest-set-gate.sh)   EVENT="gate        gate=${A[1]:-?} ${A[2]:-?}" ;;
  manifest-set-flag.sh)   EVENT="flag        ${A[1]:-?}=${A[2]:-?}" ;;
  manifest-set-artifact.sh) EVENT="artifact    ${A[1]:-?}=${A[2]:-?}" ;;
esac
[ -z "$EVENT" ] && exit 0

# --- 6. Read the current state of fact from the manifest (best-effort) ---------
yval() { grep -E "^$1:" "$2" 2>/dev/null | head -1 | sed -E "s/^$1:[[:space:]]*//; s/^\"//; s/\"$//"; }
CUR_STEP="?"; CUR_STATUS="?"; CUR_PATH="?"; NEXT_ACTION=""; LAST_GATE="n/a"
if [ -r "$MANIFEST" ]; then
  CUR_STEP=$(yval current_step "$MANIFEST"); [ -z "$CUR_STEP" ] && CUR_STEP="?"
  CUR_STATUS=$(yval status "$MANIFEST"); [ -z "$CUR_STATUS" ] && CUR_STATUS="?"
  CUR_PATH=$(yval chain_path "$MANIFEST"); [ -z "$CUR_PATH" ] && CUR_PATH="?"
  NEXT_ACTION=$(yval next_action "$MANIFEST")
  # Highest gate number that reached status approved.
  LG=$(awk '
    /^hitl_gates:/{inb=1}
    inb && /- gate:/{g=$3}
    inb && /status:[[:space:]]*"?approved/{lg=g}
    END{ if (lg!="") print lg }' "$MANIFEST" 2>/dev/null)
  [ -n "$LG" ] && LAST_GATE="$LG (approved)"
fi

# Short next-action for the one-line MEMORY.md pointer.
NEXT_SHORT=$(printf '%s' "$NEXT_ACTION" | cut -c1-70)
[ -z "$NEXT_SHORT" ] && NEXT_SHORT="(none)"

# --- 7. Rewrite chain-history/<slug>.md: STATE OF FACT header + event log ------
# Header is regenerated in place each event; the event log is append-only,
# capped at 200 lines (oldest pruned). Atomic write via temp + mv.
PREV_EVENTS=""
if [ -f "$HIST_FILE" ]; then
  PREV_EVENTS=$(awk 'f && /^- /{print} /^## Event log/{f=1}' "$HIST_FILE" 2>/dev/null)
fi
TMP_HIST=$(mktemp "$HIST_DIR/.${SLUG}.XXXXXX" 2>/dev/null) || exit 0
{
  printf -- '---\n'
  printf 'node_type: chain-history\n'
  printf 'topic: %s\n' "$SLUG"
  printf 'manifest: %s\n' "$MANIFEST"
  printf -- '---\n\n'
  printf '# Chain history — %s\n\n' "$SLUG"
  printf '## STATE OF FACT\n'
  printf -- '- current_step: %s\n' "$CUR_STEP"
  printf -- '- status: %s\n' "$CUR_STATUS"
  printf -- '- chain_path: %s\n' "$CUR_PATH"
  printf -- '- last_gate: %s\n' "$LAST_GATE"
  printf -- '- next_action: %s\n' "${NEXT_ACTION:-(none)}"
  printf -- '- updated_at: %s\n\n' "$NOW"
  printf '## Event log\n'
  if [ -n "$PREV_EVENTS" ]; then printf '%s\n' "$PREV_EVENTS"; fi
  printf -- '- %s  %s\n' "$NOW" "$EVENT"
} > "$TMP_HIST" 2>/dev/null || { rm -f "$TMP_HIST" 2>/dev/null; exit 0; }

# Cap event log at last 200 entries (preserve header).
# `grep -c` prints 0 AND exits 1 on no match: `|| echo 0` would make this the two-line "0\n0" and
# the -gt below would error instead of comparing (issue #174).
_ec=$(grep -c '^- ' "$TMP_HIST" 2>/dev/null); EVT_COUNT=${_ec:-0}
if [ "${EVT_COUNT:-0}" -gt 200 ]; then
  HEADER_PART=$(awk '/^## Event log/{print; exit} {print}' "$TMP_HIST")
  KEPT=$(grep '^- ' "$TMP_HIST" | tail -200)
  { printf '%s\n' "$HEADER_PART"; printf '%s\n' "$KEPT"; } > "$TMP_HIST.2" 2>/dev/null && mv -f "$TMP_HIST.2" "$TMP_HIST"
fi
mv -f "$TMP_HIST" "$HIST_FILE" 2>/dev/null || rm -f "$TMP_HIST" 2>/dev/null

# --- 8. Upsert the one-line pointer into MEMORY.md (lock-serialized) -----------
# The hook owns a delimited managed block; human-curated content above is never
# touched. Active chains shown at SessionStart; terminal chains demoted to a
# capped Archived list. CLAUDE.md is NEVER touched.
BEGIN_MARK='<!-- chain-memory:begin (auto-maintained — do not edit by hand) -->'
END_MARK='<!-- chain-memory:end -->'
case "$CUR_STATUS" in
  completed|aborted|failed) TERMINAL=1 ;;
  *) TERMINAL=0 ;;
esac
POINTER="- $SLUG — step=$CUR_STEP, status=$CUR_STATUS, next: $NEXT_SHORT → chain-history/$SLUG.md"

LOCK="$MEM_DIR/.chain-memory.lock"
i=0
while ! mkdir "$LOCK" 2>/dev/null; do
  i=$((i+1))
  if [ "$i" -ge 40 ]; then
    # Timeout: a foreign lock is still held by another invocation. Do NOT proceed
    # unlocked (would race the concurrent writer) and do NOT fall through to the
    # trap below (would rmdir a lock this process never acquired — issue #38
    # finding 2). Skip this MEMORY.md upsert event; the per-slug chain-history
    # file above (section 7) is unaffected — it is not lock-protected because it
    # is not shared across invocations the way MEMORY.md is.
    exit 0
  fi
  sleep 0.05 2>/dev/null || exit 0
done
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT

PRE=$(mktemp 2>/dev/null); ACT=$(mktemp 2>/dev/null); ARC=$(mktemp 2>/dev/null)
: > "$PRE"; : > "$ACT"; : > "$ARC"
if [ -f "$MEM_FILE" ]; then
  awk -v bm="$BEGIN_MARK" -v em="$END_MARK" -v pre="$PRE" -v act="$ACT" -v arc="$ARC" '
    $0==bm { mode="mgd"; next }
    $0==em { mode="post"; next }
    mode=="mgd" && /^### Active chains/   { sec="act"; next }
    mode=="mgd" && /^### Archived chains/ { sec="arc"; next }
    mode=="mgd" && /^- / && sec=="act" { print >> act; next }
    mode=="mgd" && /^- / && sec=="arc" { print >> arc; next }
    mode=="mgd" { next }
    { print >> pre }
  ' "$MEM_FILE" 2>/dev/null
fi

# Drop placeholder lines and any existing pointer for this slug from both sections.
# NB: use `;` not `&&` — grep -v exits 1 when it filters out every line, which
# would otherwise skip the mv and leave the stale pointer in place.
grep -v -e "^- $SLUG — " -e '^- (none' "$ACT" > "$ACT.f" 2>/dev/null; mv -f "$ACT.f" "$ACT" 2>/dev/null
grep -v -e "^- $SLUG — " -e '^- (none' "$ARC" > "$ARC.f" 2>/dev/null; mv -f "$ARC.f" "$ARC" 2>/dev/null

# Insert the fresh pointer into the right section.
if [ "$TERMINAL" -eq 1 ]; then
  { printf '%s\n' "$POINTER"; cat "$ARC"; } > "$ARC.n" 2>/dev/null && mv -f "$ARC.n" "$ARC"
  head -10 "$ARC" > "$ARC.c" 2>/dev/null && mv -f "$ARC.c" "$ARC"   # cap last 10
else
  printf '%s\n' "$POINTER" >> "$ACT"
fi

# Re-render MEMORY.md: human preamble + managed block. Section headers MUST be
# `### Active chains` / `### Archived chains` to match the awk parser above so the
# block round-trips on the next event.
TMP_MEM=$(mktemp 2>/dev/null)
{
  cat "$PRE"
  printf '%s\n' "$BEGIN_MARK"
  printf '## Chain memory (concept-to-code — auto-maintained, see chain-history/)\n\n'
  printf '### Active chains\n'
  if [ -s "$ACT" ]; then cat "$ACT"; else printf -- '- (none active)\n'; fi
  printf '\n### Archived chains (last 10)\n'
  if [ -s "$ARC" ]; then cat "$ARC"; else printf -- '- (none)\n'; fi
  printf '%s\n' "$END_MARK"
} > "$TMP_MEM" 2>/dev/null
mv -f "$TMP_MEM" "$MEM_FILE" 2>/dev/null

rm -f "$PRE" "$ACT" "$ARC" 2>/dev/null
exit 0
