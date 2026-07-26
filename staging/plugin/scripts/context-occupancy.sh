#!/usr/bin/env bash
# context-occupancy.sh v1.0 — reports approximate context-window occupancy from the runtime's OWN
# recorded token usage in a session transcript (issue #112; ADR-0058 §D5: NO independent token
# counter). The figure comes exclusively from the `usage` object Claude Code itself writes into
# the last assistant message carrying usage data in the transcript — input_tokens +
# cache_creation_input_tokens + cache_read_input_tokens, the exact token count the runtime sent as
# context on the most recent turn. This script never tokenizes text, never counts characters or
# words, and never sums usage across turns (that would be its own accumulator, not a read of what
# the runtime currently reports — only the LAST usage-bearing record is used).
#
# CONTRACT: a measurement utility, not a gate (§D4). No threshold comparison exists anywhere in
# this file — do not add one; the occupancy figure is reported by callers (context-occupancy.sh's
# only consumer today is usage-daily-hint.sh, the Stop hint), never used to block anything.
# Prints a bare integer percentage on stdout on success. Prints nothing and exits 0 on any error
# (no path argument, unreadable/missing file, no usage data found, python3 missing, bad window) —
# a measurement that cannot be made says nothing, it does not fail loud.
#
# WINDOW is a documented platform constant (the model's context window size in tokens), not a
# measurement of anything — override with CONTEXT_OCCUPANCY_WINDOW for testing or a different
# model tier. It is unrelated to CLAUDE_AUTOCOMPACT_PCT_OVERRIDE, which is a compaction threshold
# PERCENTAGE, not a token-count denominator; this script never reads that variable.
set -u

TRANSCRIPT="${1:-}"
WINDOW="${CONTEXT_OCCUPANCY_WINDOW:-200000}"
case "$WINDOW" in ''|*[!0-9]*) exit 0 ;; esac
[ -z "$TRANSCRIPT" ] && exit 0
[ -r "$TRANSCRIPT" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

TRANSCRIPT="$TRANSCRIPT" WINDOW="$WINDOW" python3 -c "
import json, os, sys

path = os.environ['TRANSCRIPT']
window = int(os.environ['WINDOW'])
last_total = None

try:
    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except Exception:
                continue
            message = rec.get('message')
            if not isinstance(message, dict):
                continue
            usage = message.get('usage')
            if not isinstance(usage, dict):
                continue
            # Read exactly what the runtime recorded for this turn. No estimation, no tokenizer,
            # no running total across turns (§D5) — this overwrites, it never accumulates.
            total = (
                usage.get('input_tokens', 0)
                + usage.get('cache_creation_input_tokens', 0)
                + usage.get('cache_read_input_tokens', 0)
            )
            last_total = total
except Exception:
    sys.exit(0)

if last_total is None or window <= 0:
    sys.exit(0)

pct = round(last_total * 100 / window)
print(pct)
" 2>/dev/null

exit 0
