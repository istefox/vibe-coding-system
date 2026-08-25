#!/bin/bash
# worktree-git-guardrail.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash worktree-git-guardrail.test.sh
#
# Covers VCS-039: coder (isolation: worktree, unrestricted Bash grant, ADR-0068) has no
# compensating control of its own against a git invocation escaping its assigned worktree back
# onto the main checkout — protection was entirely platform-side until this hook.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
HOOK="$SCRIPTS/worktree-git-guardrail.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

WT="$TMP/.claude/worktrees/agent-1"
OTHER_WT="$TMP/.claude/worktrees/agent-2"
mkdir -p "$WT" "$OTHER_WT" "$TMP/notaworktree"

# payload <cwd> <command> [tool]
payload() {
  jq -n --arg cwd "$1" --arg cmd "$2" --arg tool "${3:-Bash}" \
    '{session_id:"s1",tool_name:$tool,cwd:$cwd,tool_input:{command:$cmd}}'
}
run() { printf '%s' "$1" | WORKTREE_GIT_GUARDRAIL_DIR="$TMP/state" bash "$HOOK" 2>/dev/null; }
denied() { printf '%s' "$1" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; }

# =====================================================================================
# A. Inert unless .cwd is a worktree this system created (the whole hook's arming signal).
OUT=$(run "$(payload "$TMP/notaworktree" "git -C /etc status")")
[ -z "$OUT" ] && ok "A1: cwd not under .claude/worktrees -> allow, even with an obvious escape shape" \
              || bad "A1: hook fired outside a worktree cwd — got: $OUT"

# =====================================================================================
# B. Ordinary git inside the worktree, no target flag, is untouched — this is the daily case
# a coder dispatch actually runs, and a false-positive here breaks every dispatch.
for cmd in "git status" "git diff HEAD~1" "git log --oneline -5" "git add ." "git commit -m 'x'"; do
  OUT=$(run "$(payload "$WT" "$cmd")")
  [ -z "$OUT" ] && ok "B: '$cmd' inside the worktree is allowed" \
                || bad "B: '$cmd' was denied — got: $OUT"
done

# =====================================================================================
# C. The four escape vectors, each independently sufficient to deny.
# C1 uses a RELATIVE -C target rather than an absolute one deliberately: an absolute target is
# also caught by C6's absolute-path-argument vector, which would mask this vector's own plant
# (its needle deletion leaves the absolute-path vector to independently deny the same command, so
# the assertion would never go RED). A relative ".." target isolates the -C/--git-dir/--work-tree
# vector, since the absolute-path vector never inspects a relative argument.
OUT=$(run "$(payload "$WT" "git -C ../outside status")")
denied "$OUT" && ok "C1: git -C <relative ../outside path> is denied" || bad "C1: -C escape allowed — got: $OUT"

OUT=$(run "$(payload "$WT" "git --git-dir=/etc/.git status")")
denied "$OUT" && ok "C2: git --git-dir=<outside path> is denied" || bad "C2: --git-dir escape allowed — got: $OUT"

OUT=$(run "$(payload "$WT" "git --work-tree /etc status")")
denied "$OUT" && ok "C3: git --work-tree <outside path> is denied" || bad "C3: --work-tree escape allowed — got: $OUT"

OUT=$(run "$(payload "$WT" "cd / && git status")")
denied "$OUT" && ok "C4: cd <outside path> && git ... is denied" || bad "C4: cd-chain escape allowed — got: $OUT"

OUT=$(run "$(payload "$WT" "cd /etc; git log")")
denied "$OUT" && ok "C5: cd <outside path>; git ... (semicolon chain) is denied" || bad "C5: cd; escape allowed — got: $OUT"

OUT=$(run "$(payload "$WT" "git checkout /etc/passwd")")
denied "$OUT" && ok "C6: an absolute-path argument outside the worktree is denied" || bad "C6: absolute-path escape allowed — got: $OUT"

# =====================================================================================
# D. git worktree remove: own worktree is allowed, a DIFFERENT worktree is denied.
OUT=$(run "$(payload "$WT" "git worktree remove $WT")")
[ -z "$OUT" ] && ok "D1: worktree remove targeting its own worktree is allowed" \
              || bad "D1: self-removal was denied — got: $OUT"

OUT=$(run "$(payload "$WT" "git worktree remove $OTHER_WT")")
denied "$OUT" && ok "D2: worktree remove targeting a DIFFERENT worktree is denied" \
              || bad "D2: cross-worktree removal was allowed — got: $OUT"

# =====================================================================================
# E. A relative path with no .. segment is never flagged — it resolves under cwd by construction,
# and treating every relative arg as suspect would false-positive on ordinary usage.
OUT=$(run "$(payload "$WT" "git -C subdir status")")
[ -z "$OUT" ] && ok "E1: a plain relative -C target is allowed" \
              || bad "E1: plain relative target was denied — got: $OUT"

OUT=$(run "$(payload "$WT" "git -C ../.. status")")
denied "$OUT" && ok "E2: a relative target containing .. is denied conservatively" \
              || bad "E2: an upward-climbing relative target was allowed — got: $OUT"

# =====================================================================================
# F. Compound commands: only the git clause is inspected, not unrelated clauses.
OUT=$(run "$(payload "$WT" "ls /etc && git status")")
[ -z "$OUT" ] && ok "F1: an absolute path in an unrelated clause does not trip the guardrail" \
              || bad "F1: unrelated-clause absolute path was denied — got: $OUT"

OUT=$(run "$(payload "$WT" "git status && cd /etc")")
[ -z "$OUT" ] && ok "F2: a cd AFTER the git clause does not retroactively deny it" \
              || bad "F2: trailing cd denied a preceding, in-scope git clause — got: $OUT"

# =====================================================================================
# G. Fail-open scaffolding: every infra failure allows, never crashes, never exits non-zero.
OUT=$(printf 'not json' | WORKTREE_GIT_GUARDRAIL_DIR="$TMP/state" bash "$HOOK" 2>/dev/null); RC=$?
[ -z "$OUT" ] && [ "$RC" -eq 0 ] && ok "G1: malformed JSON -> allow, exit 0" \
              || bad "G1: malformed JSON did not fail open — got: '$OUT' rc=$RC"

OUT=$(run "$(payload "$WT" "git -C /etc status" "Write")")
[ -z "$OUT" ] && ok "G2: non-Bash tool -> allow" || bad "G2: hook fired on a non-Bash tool — got: $OUT"

OUT=$(jq -n --arg cwd "$WT" '{session_id:"s1",tool_name:"Bash",cwd:$cwd,tool_input:{}}' | WORKTREE_GIT_GUARDRAIL_DIR="$TMP/state" bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && ok "G3: empty command -> allow" || bad "G3: denied with no command — got: $OUT"

mkdir -p "$TMP/emptybin"
BASH_BIN=$(command -v bash)
PAYLOAD_G4=$(payload "$WT" "git -C /etc status")
OUT=$(printf '%s' "$PAYLOAD_G4" | PATH="$TMP/emptybin" WORKTREE_GIT_GUARDRAIL_DIR="$TMP/state" "$BASH_BIN" "$HOOK" 2>/dev/null); RC=$?
[ -z "$OUT" ] && [ "$RC" -eq 0 ] && ok "G4: jq missing -> allow, exit 0" \
              || bad "G4: missing-jq path did not fail open — got: '$OUT' rc=$RC"

# =====================================================================================
# H. Env bypass, same idiom as db-backup-guardrail.sh's DB_GUARDRAIL=off.
OUT=$(printf '%s' "$(payload "$WT" "git -C /etc status")" | WORKTREE_GIT_GUARDRAIL=off WORKTREE_GIT_GUARDRAIL_DIR="$TMP/state" bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && ok "H1: WORKTREE_GIT_GUARDRAIL=off bypasses an otherwise-denied escape" \
              || bad "H1: env bypass did not allow — got: $OUT"

# =====================================================================================
# I. PLANTED ASSERTION (repo rule 2 / ADR-0108), collected and mutated by plant-check.sh itself —
# deleting this needle removes the -C alternative from the TARGET extraction, so C1 above (git -C
# <relative ../outside path> denied) must go RED. The declared id is "C1", matching the ok/bad
# message prefix verbatim (plant-check.sh's red_re anchors on "FAIL: <id>", issue #355).
# plant: C1 | plugin/scripts/worktree-git-guardrail.sh | -C[[:space:]]+[^[:space:]]+|

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
