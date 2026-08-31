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
#   AM2' -- `memory:` combined with `isolation: worktree` is permitted ONLY for the frozen
#     one-line allowlist below (`coder`). Everything else combining both is still denied. This
#     replaces AM2's original absolute ban (rule 19: the ban stood because the Step 5 merge-back
#     path was never measured, not because the combination is inherently impossible -- see
#     VCS-057/ADR-0184, which measured it and found the write DOES persist onto the feature
#     branch and IS re-injected on the next dispatch, under a per-dispatch shard write discipline
#     enforced by `coder-memory-scope.sh`). The original AM2 stood correctly from 2026-07 (ADR-0038
#     Correction) through 2026-08-31 (VCS-056/ADR-0183 Phase 0) on a bare-dispatch measurement that
#     never ran the real chain's merge-back.
#   AM3 -- any `memory:` value present is one of the three documented scopes (`user`/`project`/
#     `local`), never a typo or an invented value.
#   AM4 -- reverse check (rule 8): no agent BODY instructs the use of a "Memory tool", in any file,
#     so the retired, never-real phrasing cannot creep back into a different agent.
#   AM5 -- reverse check (rule 8, VCS-056/ADR-0183): `researcher` and `lesson-extractor` never
#     carry a `memory:` field. Their only safety guarantee is having no Write/Edit tool at all;
#     `memory:` auto-grants both, silently erasing that guarantee. Machine-checked, not just prose.
#   AM6 -- producer/consumer meet (rule 17, VCS-057/ADR-0184): if `coder.md` instructs the
#     per-dispatch shard write discipline, then `coder-memory-scope.sh` must exist AND be wired in
#     `sync-to-claude.sh`'s PAIRS table AND in its settings-wiring block. A shard instruction with
#     no enforcing guard is exactly the unattended-instruction failure rule 16 warns about.
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
# AM2' -- `memory:` combined with `isolation: worktree` is permitted ONLY for the frozen
# one-line allowlist (`coder`). Deleted assertion note (rule 19): the original AM2 asserted an
# absolute ban here from 2026-07 (ADR-0038 Correction, `local` scope) through 2026-08-31
# (VCS-056/ADR-0183 Phase 0, `project` scope) -- both real findings on a BARE dispatch that never
# ran Step 5's merge-back. VCS-057/ADR-0184 measured the real chain's merge-back path and found
# the write persists and is re-injected. The allowlist below is the only agent for which this is
# both true and enforced (`coder-memory-scope.sh`, AM6 below); every other agent stays banned.
# =====================================================================================
# plant: AM2' | plugin/agents/tester.md | color: yellow memory: project | color: yellow\nmemory: project\nisolation: worktree
_am2_allowlist="coder"
_am2_bad=""
for _f in $_agent_files; do
  if grep -qE '^memory: ' "$_f" && grep -qE '^isolation: *worktree' "$_f"; then
    _am2_name=$(basename "$_f" .md)
    case " $_am2_allowlist " in
      *" $_am2_name "*) ;;
      *) _am2_bad="$_am2_bad $_f" ;;
    esac
  fi
done
if [ -z "$_am2_bad" ]; then
  ok "AM2': memory: + isolation: worktree only on the allowlist ($_am2_allowlist)"
else
  bad "AM2': memory: + isolation: worktree both present outside the allowlist in:$_am2_bad"
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

# =====================================================================================
# AM5 -- reverse check (rule 8, VCS-056/ADR-0183): `researcher` never carries `memory:`. Its
# only safety guarantee is having no Write/Edit tool; `memory:` would auto-grant both.
# `lesson-extractor` carries the same guarantee but is OUT OF SCOPE here: it is never vendored
# into staging/plugin/agents/ (deployed-only, owned by the auto-learning skill -- AM0's "exactly
# 8" denominator excludes it by design), so this repo's harness has no file to check it against.
# =====================================================================================
# plant: AM5 | plugin/agents/researcher.md | model: haiku | model: haiku\nmemory: project
_am5_bad=""
for _f in $_agent_files; do
  case "$_f" in
    */researcher.md)
      grep -qE '^memory: ' "$_f" && _am5_bad="$_am5_bad $_f"
      ;;
  esac
done
if [ -z "$_am5_bad" ]; then
  ok "AM5: researcher never carries memory: (Write/Edit-less safety guarantee intact)"
else
  bad "AM5: memory: field found on a Write/Edit-less agent:$_am5_bad"
fi

# =====================================================================================
# AM6 -- producer/consumer meet (rule 17, VCS-057/ADR-0184): coder's shard-write instruction, the
# enforcing guard, and its wiring must all exist together. Only checked once coder.md actually
# carries memory: -- an AM2'-allowlisted agent with no memory: yet has nothing to enforce.
# =====================================================================================
# plant: AM6 | sync-to-claude.sh | plugin/scripts/coder-memory-scope.sh|hooks/coder-memory-scope.sh | plugin/scripts/coder-memory-scope.sh|hooks/coder-memory-scope-renamed.sh
_coder_md="$AGENTS_DIR/coder.md"
if [ -f "$_coder_md" ] && grep -qE '^memory: ' "$_coder_md"; then
  _guard="$SCRIPTS/coder-memory-scope.sh"
  _am6_bad=""
  [ -f "$_guard" ] || _am6_bad="$_am6_bad guard-missing"
  grep -qE '^plugin/scripts/coder-memory-scope\.sh\|hooks/coder-memory-scope\.sh$' "$STAGING/sync-to-claude.sh" 2>/dev/null \
    || _am6_bad="$_am6_bad not-in-sync-pairs-table"
  grep -q 'bash ~/.claude/hooks/coder-memory-scope\.sh' "$STAGING/sync-to-claude.sh" 2>/dev/null \
    || _am6_bad="$_am6_bad not-in-sync-wiring-block"
  if [ -z "$_am6_bad" ]; then
    ok "AM6: coder's shard discipline is enforced (guard exists and is wired in sync-to-claude.sh)"
  else
    bad "AM6: coder carries memory: but enforcement is incomplete:$_am6_bad"
  fi
else
  ok "AM6: coder does not yet carry memory: -- nothing to enforce (not a false pass: AM2' already covers the allowlist boundary)"
fi

printf '\nPASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
