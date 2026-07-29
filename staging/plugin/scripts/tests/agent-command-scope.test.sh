#!/bin/bash
# agent-command-scope.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash agent-command-scope.test.sh
#
# Covers issue #58 gap 1: architect and reviewer keep Bash(bash *) / Bash(python3 *) (reviewer also
# Bash(awk *)), which subsume every command their narrowed git grants exclude. ADR-0042 closed the
# direct path for architect and said in as many words that `bash -c "git commit …"` still reached
# git. This hook closes the wrapper.
#
# THE OBJECTION THAT DEFERRED THIS THREE TIMES, AND WHY IT DOES NOT HOLD.
# A denylist on "git commit" blocks `rg "git commit" .`, a legitimate read-only search. True of a
# substring match; not true of a COMMAND-POSITION match. A verb inside quotes is data and never
# reaches a command position, so the case that looked like a blocker is not a false positive at all
# — it is section C, and every assertion there passes.
#
# THREAT MODEL — read this before trusting the hook for anything.
# It is a guardrail against an agent taking a shortcut, NOT a sandbox against an adversary. String
# inspection cannot be otherwise: subprocess.run(["git","push"]) splits the verb across list
# elements, and eval/base64/variable splicing defeat it outright. Section E pins one such bypass as
# EXPECTED-ALLOW so the limit lives in CI rather than only in prose. If someone closes it, E fails
# and forces the documentation to move with the code.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
HOOK="$SCRIPTS/agent-command-scope.sh"
ARCH_AGENT="$STAGING/plugin/agents/architect.md"
REV_AGENT="$STAGING/plugin/agents/reviewer.md"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# payload <agent_type> <command>
payload() {
  printf '%s' "$2" | jq -Rs --arg at "$1" \
    '{session_id:"s1",tool_name:"Bash",cwd:"/tmp/proj",agent_type:$at,agent_id:"a1",tool_input:{command:.}}'
}
run()    { printf '%s' "$1" | AGENT_COMMAND_SCOPE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null; }
denied() { printf '%s' "$1" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; }

# deny_case <label> <agent_type> <command>
deny_case() {
  _out=$(run "$(payload "$2" "$3")")
  denied "$_out" && ok "$1" || bad "$1 — allowed: $3"
}
# allow_case <label> <agent_type> <command>
allow_case() {
  _out=$(run "$(payload "$2" "$3")")
  [ -z "$_out" ] && ok "$1" || bad "$1 — denied: $3"
}

# =====================================================================================
# A. The bypass the issue is about: a mutating git call behind an interpreter wrapper.
deny_case "A1: bash -c git commit is denied"        architect 'bash -c "git commit -m x"'
deny_case "A2: bash -c git push is denied"          architect "bash -c 'git push origin main'"
deny_case "A3: chained behind && inside -c"         architect 'bash -c "cd docs && git commit -m x"'
deny_case "A4: sh -c git add is denied"             architect 'sh -c "git add ."'
deny_case "A5: reviewer is covered too"             reviewer  'bash -c "git commit -m x"'
deny_case "A6: python3 os.system shell-out"         reviewer  'python3 -c "import os; os.system(\"git commit -m x\")"'
deny_case "A7: awk system() shell-out"              reviewer  "awk 'BEGIN{system(\"git push\")}'"

# =====================================================================================
# B. Defence in depth: a direct call, denied by frontmatter today. Cheap to cover, and it keeps
# working if a grant is ever widened back — which is exactly how ADR-0036 §2.1 got its own
# contradiction (issue #91).
deny_case "B1: direct git commit is denied"         architect 'git commit -m x'
deny_case "B2: direct git push is denied"           reviewer  'git push'
deny_case "B3: git reset --hard is denied"          architect 'git reset --hard HEAD~1'

# =====================================================================================
# C. The read-only work both agents genuinely do. Every one of these contains the forbidden words
# or an interpreter, and every one must pass — this section IS the objection, answered.
allow_case "C1: rg for the literal string"          architect "rg 'git commit' ."
allow_case "C2: grep inside bash -c"                architect 'bash -c "grep \"git commit\" docs/x.md"'
allow_case "C3: running the test harness"           architect 'bash staging/plugin/scripts/tests/x.test.sh'
allow_case "C4: python3 YAML sanity one-liner"      architect 'python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))"'
allow_case "C5: read-only git log"                  architect 'git log --oneline -5'
allow_case "C6: read-only git diff piped"           reviewer  'git diff --stat | head -20'
allow_case "C7: git log inside bash -c"             architect 'bash -c "git log --oneline | head"'
allow_case "C8: os.system on a read-only git"       reviewer  'python3 -c "import os; os.system(\"git log\")"'
allow_case "C9: the verb only as printed data"      architect 'python3 -c "print(\"git commit\")"'
allow_case "C10: markdownlint"                      architect 'npx --yes markdownlint-cli2 docs/x.md'
allow_case "C11: git rev-parse in a substitution"   architect 'x=$(git rev-parse HEAD); echo "$x"'

# C12-C15 — the objection, answered a second time (issue #127's sibling audit). The header above
# says a verb inside quotes is data and never reaches a command position. That was true of the
# quoting forms section C already covered, and FALSE whenever the search tool is given its COUNT
# flag: `-c` was anchored on its own, for `bash -c` / `python3 -c`, and grep, rg and every other
# tool spell "count matches" the same way. `grep -c "git commit -m" f` was denied.
#
# It is the #127 class exactly — a guard arming on text ABOUT the thing it guards — reached
# through the command string instead of through the transcript. A reviewer auditing commit/SKILL.md
# is doing in-scope work with the one tool it is granted.
allow_case "C12: grep -c counting a mutating verb"  reviewer  'grep -c "git commit -m" staging/plugin/skills/commit/SKILL.md'
allow_case "C13: rg -c counting a mutating verb"    architect 'rg -c "git push origin" docs/'
allow_case "C14: rg -c with the verb and a flag"    reviewer  'rg -c "git add -u" .'
allow_case "C15: count then a chained command"      reviewer  'grep -c "git commit -m x" f && echo done'

# =====================================================================================
# D. Inert everywhere else. A hook that reached past its two agents would be found out the first
# time a coder committed, and switched off.
allow_case "D1: coder is untouched"                 coder     'git commit -m x'
allow_case "D2: tester is untouched"                tester    'bash -c "git push"'

OUT=$(printf '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' \
  | AGENT_COMMAND_SCOPE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && ok "D3: no agent_type (orchestrator) -> allow" \
              || bad "D3: hook fired with no agent_type — got: $OUT"

OUT=$(printf 'not json' | AGENT_COMMAND_SCOPE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && ok "D4: malformed JSON -> allow" || bad "D4: denied on malformed input — got: $OUT"

OUT=$(printf '{"session_id":"s1","tool_name":"Bash","agent_type":"architect","tool_input":{}}' \
  | AGENT_COMMAND_SCOPE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && ok "D5: no command -> allow (nothing to decide about)" \
              || bad "D5: denied with no command — got: $OUT"

# =====================================================================================
# E. DOCUMENTED LIMITS — these assert the hook does NOT catch something, on purpose.
# Not aspirations. If a future change closes one of these, this section fails, and whoever closed
# it has to update the threat-model paragraph in ADR-0045 in the same commit. That is the point:
# the limitation is versioned alongside the code instead of drifting out of a paragraph nobody
# re-reads.
_out=$(run "$(payload architect 'python3 -c "import subprocess; subprocess.run([\"git\",\"push\"])"')")
if [ -z "$_out" ]; then
  ok "E1: list-form subprocess bypass is NOT caught (documented limit, ADR-0045 threat model)"
else
  bad "E1: list-form subprocess is now caught — good, but ADR-0045's threat model must be updated"
fi

_out=$(run "$(payload architect 'bash -c "v=commit; git \$v -m x"')")
if [ -z "$_out" ]; then
  ok "E2: variable-spliced verb is NOT caught (documented limit, ADR-0045 threat model)"
else
  bad "E2: variable splicing is now caught — update ADR-0045's threat model with it"
fi

# =====================================================================================
# F. Coupling: the agents' own prose must say what the hook enforces. ADR-0041 Finding A and
# ADR-0042 both landed on the same lesson — a file whose prose and grant disagree tells the reader
# nothing about which one is authoritative.
for _f in "$ARCH_AGENT" "$REV_AGENT"; do
  _n=$(basename "$_f")
  if grep -q 'Command scope' "$_f" && grep -qE 'bash -c|route around' "$_f"; then
    ok "F: $_n documents the command scope and the no-routing-around rule"
  else
    bad "F: $_n should document the command scope, including the wrapper case"
  fi
done

# G: the deny reason has to be actionable, not just a refusal.
OUT=$(run "$(payload architect 'bash -c "git commit -m x"')")
if printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason' 2>/dev/null \
     | grep -q 'report'; then
  ok "G: deny reason tells the agent to report the change instead of routing around"
else
  bad "G: deny reason should tell the agent what to do instead"
fi

# =====================================================================================
# H. THE HEADLINE CASE, WHICH ESCAPED (issue #127's sibling audit).
# ADR-0042 and ADR-0045 both name `bash -c "git commit …"` as the bypass this hook closes. The
# shipped hook allowed `bash -c "git push"` — because R1's trailing boundary was ([[:space:]]|$)
# and the character after the verb is the CLOSING QUOTE. Every assertion in section A passes only
# because each of them happens to carry an argument after the verb: `-m x`, `origin main`, `.`.
#
# Found by running the regex over the forms the ADRs quote, not by reading it. Same lesson as
# ADR-0070's fourth defect: a check nobody has executed on its own documented example is
# unverified. Section A was green throughout.
deny_case "H1: bash -c with the verb as the LAST token" architect 'bash -c "git push"'
deny_case "H2: single-quoted, verb last"                architect "bash -c 'git commit'"
deny_case "H3: sh -c, verb last"                        reviewer  'sh -c "git clean"'
deny_case "H4: absolute interpreter path"               architect '/bin/bash -c "git push"'
# H5 — combined short flags. `-lc` is one argument, so an anchor written as a literal `-c` never
# saw it. Cheap to cover once the anchor is interpreter-qualified anyway.
deny_case "H5: bash -lc (combined flags)"               architect 'bash -lc "git push origin"'
deny_case "H6: an intervening interpreter flag"         reviewer  'python3 -u -c "git commit"'

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
