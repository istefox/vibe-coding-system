#!/bin/bash
# agent-memory-contract test harness (VCS-055, ADR-0038 Correction 2026-08-30).
#
# Closes the gap that let the coder `memory: local` defect ship undetected: no test anywhere
# asserted anything about the `memory:` frontmatter field before this file. Four invariants,
# each a statement this repo got wrong once already:
#
#   AM0 -- denominator guard (rule 7): the agent-file glob must yield exactly 8 files.
#   AM1 -- no agent declares a tool literally named `Memory` in its `tools:` line. No build of
#     Claude Code registers a tool by that name; `memory:` auto-enables the real Read/Write/Edit
#     tools instead (code.claude.com/docs/en/sub-agents, verified live 2026-08-30).
#   AM2 -- no agent combines a `memory:` field with `isolation: worktree`. `local`/`project` scope
#     resolves INSIDE the worktree sandbox and is deleted with it -- confirmed live on coder before
#     this fix. This is the configuration that cannot persist, as a machine-checked invariant.
#   AM3 -- any `memory:` value present is one of the three documented scopes (`user`/`project`/
#     `local`), never a typo or an invented value.
#   AM4 -- reverse check (rule 8): no agent BODY instructs the use of a "Memory tool", in any file,
#     so the retired, never-real phrasing cannot creep back into a different agent.
#
# Zero $HOME dependency: runs identically in CI (ubuntu-latest, no ~/.claude) and locally. Never
# point any variable at $HOME/.claude/... -- that is the deployed copy, out of scope (same rule as
# agent-tool-scoping.test.sh).
# Bash 3.2 clean. Run: bash agent-memory-contract.test.sh
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)              # staging/plugin/scripts
STAGING=$(cd "$SCRIPTS/../.." && pwd)                    # staging/
AGENTS_DIR="$STAGING/plugin/agents"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

# Portable file list -- no unquoted glob (host shell is zsh, but this file runs under bash; still
# avoid relying on nullglob semantics either interpreter might apply differently).
_agent_files=""
for _f in "$AGENTS_DIR"/*.md; do
  [ -f "$_f" ] && _agent_files="$_agent_files $_f"
done

# =====================================================================================
# AM0 -- denominator guard (rule 7, no plant: a broken glob is not a mutation to seed, it is a
# missing-file state the guard exists to catch on its own).
# =====================================================================================
_n=0
for _f in $_agent_files; do _n=$((_n+1)); done
[ "$_n" -eq 8 ] && ok "AM0: found exactly 8 agent files" \
                || bad "AM0: expected 8 agent files, found $_n -- derivation broken, not clean"

# =====================================================================================
# AM1 -- no `Memory` tool entry on any agent's `tools:` line.
# =====================================================================================
# plant: AM1 | plugin/agents/coder.md | Bash, LSP, mcp__plugin_context7_context7__resolve-library-id | Bash, LSP, Memory, mcp__plugin_context7_context7__resolve-library-id
_am1_bad=""
for _f in $_agent_files; do
  _tl=$(grep -m1 '^tools:' "$_f" 2>/dev/null || true)
  [ -n "$_tl" ] || continue
  printf '%s\n' "$_tl" | grep -qE '(^tools: |, )Memory(,|$)' && _am1_bad="$_am1_bad $_f"
done
if [ -z "$_am1_bad" ]; then
  ok "AM1: no agent declares a 'Memory' tool (no such tool exists on any build)"
else
  bad "AM1: 'Memory' tool declared in:$_am1_bad"
fi

# =====================================================================================
# AM2 -- `memory:` never combined with `isolation: worktree` (the config that cannot persist).
# =====================================================================================
# plant: AM2 | plugin/agents/coder.md | isolation: worktree | isolation: worktree\nmemory: local
_am2_bad=""
for _f in $_agent_files; do
  if grep -qE '^memory: ' "$_f" && grep -qE '^isolation: *worktree' "$_f"; then
    _am2_bad="$_am2_bad $_f"
  fi
done
if [ -z "$_am2_bad" ]; then
  ok "AM2: no agent combines memory: with isolation: worktree"
else
  bad "AM2: memory: + isolation: worktree both present in:$_am2_bad (cannot persist, ADR-0038 Correction)"
fi

# =====================================================================================
# AM3 -- any `memory:` value is one of user / project / local.
# =====================================================================================
# plant: AM3 | plugin/agents/coder.md | isolation: worktree | isolation: worktree\nmemory: bogus
_am3_bad=""
for _f in $_agent_files; do
  _mv=$(grep -m1 -E '^memory: ' "$_f" 2>/dev/null | sed -E 's/^memory: *//' || true)
  [ -n "$_mv" ] || continue
  case "$_mv" in
    user|project|local) ;;
    *) _am3_bad="$_am3_bad $_f=$_mv" ;;
  esac
done
if [ -z "$_am3_bad" ]; then
  ok "AM3: every memory: value (if any) is user/project/local"
else
  bad "AM3: invalid memory: value in:$_am3_bad"
fi

# =====================================================================================
# AM4 -- reverse check (rule 8): no agent BODY instructs use of a "Memory tool".
# =====================================================================================
# plant: AM4 | plugin/agents/debugger.md | You never suppress errors or symptoms. | You never suppress errors or symptoms. Use the Memory tool for all memory operations.
_am4_bad=""
for _f in $_agent_files; do
  grep -qi 'memory tool' "$_f" && _am4_bad="$_am4_bad $_f"
done
if [ -z "$_am4_bad" ]; then
  ok "AM4: no agent body instructs use of a 'Memory tool'"
else
  bad "AM4: 'Memory tool' phrasing found in:$_am4_bad"
fi

printf '\nPASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
