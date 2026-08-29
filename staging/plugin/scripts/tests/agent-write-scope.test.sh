#!/bin/bash
# agent-write-scope.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash agent-write-scope.test.sh
#
# Covers issue #58 gap 2: `Write` carries no path restriction in Claude Code's frontmatter
# grammar, so architect's "you may only write under docs/..." is prose, not a control.
# ADR-0036 §3.3 disclosed exactly this and left it open.
#
# Simpler than write-scope-enforce.sh (#87): the scope here is STATIC per agent type, so the
# hook never reads a transcript. It keys off .agent_type and .tool_input.file_path alone.
#
# THE ALLOWED SET IS TWO ROOTS, NOT ONE. architect.md said "docs/architecture/** only", but
# concept-to-code Step 2 orders the architect to write its plan to
# docs/superpowers/plans/YYYY-MM-DD-<slug>.md (SKILL.md:357) and HARD ABORTs if that path is
# missing from the report (SKILL.md:409). A hook enforcing the file's literal claim would have
# broken every chain run at Step 2. B2 below is the regression guard for that.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
# VCS-046: agent-write-scope.sh was merged into test-write-scope.sh (universal per-call
# process-spawn overhead, not agent-type-gated) — the architect-scope logic this file tests now
# lives in the ARCHITECT BRANCH section of the merged file, unchanged.
HOOK="$SCRIPTS/test-write-scope.sh"
ARCH_AGENT="$STAGING/plugin/agents/architect.md"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

ROOT="$TMP/proj"
mkdir -p "$ROOT/docs/architecture" "$ROOT/docs/superpowers/plans" "$ROOT/src" "$ROOT/.claude"

# payload <agent_type> <file_path> [tool]
payload() {
  printf '{"session_id":"s1","tool_name":"%s","cwd":"%s","agent_type":"%s","agent_id":"a1","tool_input":{"file_path":"%s"}}' \
    "${3:-Write}" "$ROOT" "$1" "$2"
}
run() { printf '%s' "$1" | AGENT_WRITE_SCOPE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null; }
denied() { printf '%s' "$1" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; }

# =====================================================================================
# A. The deny that is the point of the issue.
OUT=$(run "$(payload architect "$ROOT/src/main.py")")
if denied "$OUT"; then
  ok "A1: architect writing outside both doc roots is denied"
else
  bad "A1: out-of-scope architect Write was allowed — got: $OUT"
fi

if printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason' 2>/dev/null | grep -q 'docs/architecture'; then
  ok "A2: deny reason names the allowed roots"
else
  bad "A2: deny reason does not tell the agent where it may write"
fi

OUT=$(run "$(payload architect "$ROOT/.claude/test-cmd")")
denied "$OUT" && ok "A3: architect writing config outside the doc roots is denied" \
               || bad "A3: config write was allowed — got: $OUT"

# =====================================================================================
# B. The two legitimate targets. B2 is the regression guard: enforcing architect.md's literal
# "docs/architecture/** only" would break concept-to-code Step 2 on every single run.
OUT=$(run "$(payload architect "$ROOT/docs/architecture/ADR-0099-x.md")")
[ -z "$OUT" ] && ok "B1: architect writing an ADR is allowed" \
              || bad "B1: legitimate ADR write was denied — got: $OUT"

OUT=$(run "$(payload architect "$ROOT/docs/superpowers/plans/2026-07-25-x.md")")
[ -z "$OUT" ] && ok "B2: architect writing a PLAN is allowed (c2c Step 2 requires this path)" \
              || bad "B2: plan write denied — this would HARD ABORT every chain at Step 2: $OUT"

# =====================================================================================
# C. Inert for everything else. A scope hook that reaches beyond its agent would be found out
# the first time a coder touched a source file, and disabled.
OUT=$(run "$(payload coder "$ROOT/src/main.py")")
[ -z "$OUT" ] && ok "C1: another agent type writing source is untouched" \
              || bad "C1: hook fired on a non-architect agent — got: $OUT"

OUT=$(printf '{"session_id":"s1","tool_name":"Write","tool_input":{"file_path":"%s"}}' "$ROOT/src/main.py" | AGENT_WRITE_SCOPE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && ok "C2: no agent_type (orchestrator) -> allow" \
              || bad "C2: hook fired with no agent_type — got: $OUT"

OUT=$(printf 'not json' | AGENT_WRITE_SCOPE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && ok "C3: malformed JSON -> allow" || bad "C3: denied on malformed input — got: $OUT"

OUT=$(printf '{"session_id":"s1","tool_name":"Write","agent_type":"architect","tool_input":{}}' | AGENT_WRITE_SCOPE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && ok "C4: no file_path -> allow (nothing to decide about)" \
              || bad "C4: denied with no file_path — got: $OUT"

# =====================================================================================
# D. Edit and MultiEdit must be covered too. Constraining Write while leaving Edit open would
# be enforcement in name only.
OUT=$(run "$(payload architect "$ROOT/src/main.py" Edit)")
denied "$OUT" && ok "D1: Edit is covered, not just Write" || bad "D1: Edit slipped through — got: $OUT"

OUT=$(run "$(payload architect "$ROOT/src/main.py" MultiEdit)")
denied "$OUT" && ok "D2: MultiEdit is covered" || bad "D2: MultiEdit slipped through — got: $OUT"

# =====================================================================================
# E. Coupling: the roots the hook enforces and the roots architect.md claims must agree.
# If they drift, the agent is told one thing and permitted another — which is how ADR-0036's
# §2.1 ended up asserting an exclusion its own grant did not express.
for r in 'docs/architecture' 'docs/superpowers/plans'; do
  if grep -q "$r" "$HOOK" && grep -q "$r" "$ARCH_AGENT"; then
    ok "E: '$r' is named in both the hook and architect.md"
  else
    bad "E: '$r' missing from the hook or from architect.md — they disagree"
  fi
done

# =====================================================================================
# F. SELF-ARMING AUDIT (issue #127). #127 asked whether this hook can be armed the way
# write-scope-enforce.sh was — by an agent reading a file that quotes the marker, which lands in
# its transcript as a `user` entry indistinguishable from the dispatch prompt.
#
# FINDING: it cannot, and the reason is structural rather than careful. This hook derives nothing
# from the transcript. Its scope is a constant in its own source, and the payload's agent_type and
# file_path are its whole input, so there is no text an agent can cause to be READ that changes
# what it enforces. Recorded as an assertion rather than as prose, because the property that makes
# it immune is exactly the property a future "make the roots configurable per dispatch" change
# would remove — and that change would look like an improvement.
# VCS-046: $HOOK is now the merged test-write-scope.sh, whose CODER branch legitimately reads a
# subagent transcript (that is the whole point of ADR-0049's marker check). Scoping the grep to
# only the ARCHITECT BRANCH anchors keeps this assertion meaningful — it still proves the
# architect logic specifically touches no transcript, rather than failing on the unrelated coder
# branch's transcript code that now shares the file.
ARCH_BLOCK=$(awk '/ARCHITECT BRANCH START/,/ARCHITECT BRANCH END/' "$HOOK")
if printf '%s' "$ARCH_BLOCK" | grep -qE 'transcript_path|TRANSCRIPT|\.jsonl'; then
  bad "F1: the architect branch now reads a transcript — re-audit it against issue #127's self-arming class"
else
  ok "F1: the architect branch derives its scope from no transcript — structurally cannot self-arm (#127)"
fi

# F2: the payload-borne twin of the same question. A file_path that quotes the OTHER hook's marker
# is still just a path, and it is out of scope, so it must be denied on its path alone.
OUT=$(run "$(payload architect "$ROOT/src/you may edit ONLY docs/architecture/x.md")")
denied "$OUT" && ok "F2: a marker-shaped file_path decides nothing — denied on the path itself" \
               || bad "F2: a marker-shaped path was allowed — got: $OUT"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
