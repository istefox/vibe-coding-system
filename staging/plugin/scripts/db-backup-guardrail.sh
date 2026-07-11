#!/bin/bash
# db-backup-guardrail v1.1 — PreToolUse hook on matcher Bash.
# Intercepts destructive DB commands and escalates via hookSpecificOutput.permissionDecision.
# Gate: ask (orchestrator, agent_id absent) or deny (sub-agent, agent_id present).
# Allow = no output (empty stdout). Fail-OPEN on infra errors; fail-CLOSED after match.
# Bash 3.2 clean: no assoc array, no mapfile, no ${v^^}, no <<< here-string.
# ADR-0009. Contract: exit 0 always, never crash visibly.

DIR="${DB_GUARDRAIL_DIR:-$HOME/.claude/state/db-backup-guardrail}"
LOG="$DIR/audit.log"
MAX_AGE_H="${DB_BACKUP_MAX_AGE_HOURS:-24}"
case "$MAX_AGE_H" in ''|*[!0-9]*) MAX_AGE_H=24;; esac

mkdir -p "$DIR" 2>/dev/null || true

# Audit log: 7-field TAB-separated.
# Fields: timestamp, session_id, agent_type, agent_ctx, matched_category, action, reason
log_audit() {
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "${1:-?}" "${2:-?}" "${3:-?}" "${4:--}" "${5:-?}" "${6:-}" \
    >>"$LOG" 2>/dev/null || true
}

# Bypass 1: env var single-call override
if [ "$DB_GUARDRAIL" = "off" ]; then
  log_audit "?" "?" "?" "-" "bypass-env" "env DB_GUARDRAIL=off"
  exit 0
fi

# Read stdin once
INPUT=$(cat)

# Require jq; fail-open if missing
command -v jq >/dev/null 2>&1 || {
  log_audit "?" "?" "?" "-" "fail-open" "jq missing"
  exit 0
}

# Extract payload fields; fail-open on malformed JSON (session_id absent)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SID" ] && {
  log_audit "?" "?" "?" "-" "fail-open" "malformed or empty JSON (no session_id)"
  exit 0
}

AGENT_TYPE=$(printf '%s' "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null)
AGENT_ID=$(printf '%s' "$INPUT" | jq -r '.agent_id // empty' 2>/dev/null)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

# Fail-open on non-Bash tool or empty command
if [ "$TOOL" != "Bash" ] || [ -z "$CMD" ]; then
  log_audit "$SID" "$AGENT_TYPE" "?" "-" "not-db" "tool=$TOOL non-Bash or empty command"
  exit 0
fi

# Determine agent context (for ask/deny split)
if [ -z "$AGENT_ID" ]; then
  AGENT_CTX="orchestrator"
else
  AGENT_CTX="subagent"
fi

# Normalize command: collapse newlines and repeated spaces to single space
NORM=$(printf '%s' "$CMD" | tr '\n' ' ' | tr -s ' ')

# ---- Detection: Famiglia A (SQL destructive) and Famiglia B (migration tools) ----
CAT=""

# A1: DROP TABLE / DROP DATABASE / DROP SCHEMA
if [ -z "$CAT" ]; then
  printf '%s' "$NORM" | grep -iqE '\bdrop[[:space:]]+(table|database|schema)\b' 2>/dev/null \
    && CAT="A1-DROP-TABLE"
fi

# A2: TRUNCATE (TABLE optional)
if [ -z "$CAT" ]; then
  printf '%s' "$NORM" | grep -iqE '\btruncate[[:space:]]+(table[[:space:]]+)?[a-z0-9_".\`\[]' 2>/dev/null \
    && CAT="A2-TRUNCATE"
fi

# A3: DELETE FROM without WHERE (whole-command check, v1 approach)
if [ -z "$CAT" ]; then
  if printf '%s' "$NORM" | grep -iqE '\bdelete[[:space:]]+from\b' 2>/dev/null; then
    if ! printf '%s' "$NORM" | grep -iqE '\bwhere\b' 2>/dev/null; then
      CAT="A3-DELETE-NO-WHERE"
    fi
  fi
fi

# A4: ALTER TABLE ... DROP (column or constraint)
if [ -z "$CAT" ]; then
  printf '%s' "$NORM" | grep -iqE '\balter[[:space:]]+table\b.*\bdrop\b' 2>/dev/null \
    && CAT="A4-ALTER-DROP"
fi

# A5: UPDATE ... SET without WHERE (whole-command check)
if [ -z "$CAT" ]; then
  if printf '%s' "$NORM" | grep -iqE '\bupdate[[:space:]]+[a-z0-9_."]+[[:space:]]+set\b' 2>/dev/null; then
    if ! printf '%s' "$NORM" | grep -iqE '\bwhere\b' 2>/dev/null; then
      CAT="A5-UPDATE-NO-WHERE"
    fi
  fi
fi

# B1: alembic downgrade
if [ -z "$CAT" ]; then
  printf '%s' "$NORM" | grep -iqE '\balembic[[:space:]]+downgrade\b' 2>/dev/null \
    && CAT="B1-alembic-downgrade"
fi

# B2: prisma migrate reset / db push (force-reset implied by db push)
if [ -z "$CAT" ]; then
  printf '%s' "$NORM" | grep -iqE '\bprisma[[:space:]]+(migrate[[:space:]]+reset|db[[:space:]]+push)\b' 2>/dev/null \
    && CAT="B2-prisma-reset"
fi

# B3: django manage.py flush / sqlflush / migrate <app> zero
if [ -z "$CAT" ]; then
  if printf '%s' "$NORM" | grep -iqE '\b(manage\.py|django-admin)[[:space:]]+(flush|sqlflush)\b' 2>/dev/null; then
    CAT="B3-django-flush"
  elif printf '%s' "$NORM" | grep -iqE '\bmigrate[[:space:]]+[a-z_]+[[:space:]]+zero\b' 2>/dev/null; then
    CAT="B3-django-migrate-zero"
  fi
fi

# B4: knex migrate:rollback / migrate:down
if [ -z "$CAT" ]; then
  printf '%s' "$NORM" | grep -iqE '\bknex[[:space:]]+migrate:(rollback|down)\b' 2>/dev/null \
    && CAT="B4-knex-rollback"
fi

# B5: sequelize db:migrate:undo / db:drop
if [ -z "$CAT" ]; then
  printf '%s' "$NORM" | grep -iqE '\bsequelize[[:space:]]+db:(migrate:undo|drop)\b' 2>/dev/null \
    && CAT="B5-sequelize-drop"
fi

# B6: rails/rake db:drop / db:reset / db:rollback
if [ -z "$CAT" ]; then
  printf '%s' "$NORM" | grep -iqE '\b(rails|rake)[[:space:]]+db:(drop|reset|rollback)\b' 2>/dev/null \
    && CAT="B6-rails-db-drop"
fi

# Non-destructive: allow (fail-open)
if [ -z "$CAT" ]; then
  log_audit "$SID" "$AGENT_TYPE" "$AGENT_CTX" "-" "not-db" "no destructive pattern matched"
  exit 0
fi

# ---- Command is destructive. Now do backup-check. ----
# Fail-CLOSED from here: backup-check errors → gate ask/deny (never allow).

# Locate project root by climbing from CWD looking for .claude/ dir
ROOT=""
d="$CWD"
i=0
while [ -n "$d" ] && [ "$i" -lt 40 ]; do
  if [ -d "$d/.claude" ]; then
    ROOT="$d"
    break
  fi
  [ "$d" = "/" ] && break
  d=$(dirname "$d")
  i=$((i + 1))
done

# Bypass 2: project ephemeral marker
if [ -n "$ROOT" ] && [ -f "$ROOT/.claude/db-is-ephemeral" ]; then
  log_audit "$SID" "$AGENT_TYPE" "$AGENT_CTX" "$CAT" "bypass-ephemeral" "db-is-ephemeral marker present"
  exit 0
fi

# Helper: check if file mtime is within MAX_AGE_H hours (returns 0=fresh, 1=stale/error)
fresh_mtime() {
  local f="$1"
  local now
  now=$(date +%s)
  local mt
  mt=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null)
  case "$mt" in ''|*[!0-9]*) return 1;; esac
  local age_h
  age_h=$(( (now - mt) / 3600 ))
  [ "$age_h" -le "$MAX_AGE_H" ] && return 0 || return 1
}

# Bypass 3 / Backup-check A: db-backup-confirmed marker (fresh)
if [ -n "$ROOT" ] && [ -f "$ROOT/.claude/db-backup-confirmed" ]; then
  if fresh_mtime "$ROOT/.claude/db-backup-confirmed"; then
    log_audit "$SID" "$AGENT_TYPE" "$AGENT_CTX" "$CAT" "allow-marker" "db-backup-confirmed fresh"
    exit 0
  fi
fi

# Backup-check B: recent backup file in <root>/.backups/
if [ -n "$ROOT" ] && [ -d "$ROOT/.backups" ]; then
  RECENT_BACKUP=""
  # Check each extension via ls -t; pick the most recent across all extensions
  for ext in dump sql sql.gz dump.gz; do
    # ls -t sorts newest first; head -1 gets most recent
    f=$(ls -t "$ROOT/.backups/"*."$ext" 2>/dev/null | head -1)
    if [ -n "$f" ] && [ -f "$f" ]; then
      if fresh_mtime "$f"; then
        RECENT_BACKUP="$f"
        break
      fi
    fi
  done
  if [ -n "$RECENT_BACKUP" ]; then
    log_audit "$SID" "$AGENT_TYPE" "$AGENT_CTX" "$CAT" "allow-backup-file" "fresh backup: $RECENT_BACKUP"
    exit 0
  fi
fi

# ---- Gate ask/deny: no backup found, command is destructive ----
# Detect possible production host for enriching orchestrator reason (opportunistic only)
PROD_NOTE=""
if printf '%s' "$CMD" | grep -iqE '([a-z0-9-]+\.[a-z]{2,}|[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})' 2>/dev/null; then
  if ! printf '%s' "$CMD" | grep -iqE '(localhost|127\.0\.0\.1|0\.0\.0\.0)' 2>/dev/null; then
    PROD_NOTE=" WARNING: possible production target detected."
  fi
fi

ROOT_DISPLAY="${ROOT:-<project-root>}"

if [ "$AGENT_CTX" = "subagent" ]; then
  DECISION="deny"
  MSG="db-backup-guardrail: potentially destructive DB command ($CAT) with no evidence of a recent backup. STOP: do not execute. This operation requires a backup or explicit user confirmation. Report to the orchestrator and wait for instructions."
else
  DECISION="ask"
  MSG="db-backup-guardrail: potentially destructive DB command ($CAT) with no evidence of a recent backup. Proceed? To make it persistent: (1) run a backup (e.g. pg_dump/mysqldump into $ROOT_DISPLAY/.backups/), or (2) if you already have a recent backup: touch $ROOT_DISPLAY/.claude/db-backup-confirmed. If the target is a throwaway DB: touch $ROOT_DISPLAY/.claude/db-is-ephemeral.$PROD_NOTE"
fi

log_audit "$SID" "$AGENT_TYPE" "$AGENT_CTX" "$CAT" "$DECISION" "cmd=$CAT decision=$DECISION"

# Emit modern hookSpecificOutput format (never legacy {"decision":"block"})
jq -nc --arg d "$DECISION" --arg r "$MSG" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}' \
  2>/dev/null \
  || printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"}}\n' \
       "$DECISION" "db-backup-guardrail: destructive DB command blocked"

exit 0
