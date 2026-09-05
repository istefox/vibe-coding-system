#!/bin/bash
# coder-discipline.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash coder-discipline.test.sh
#
# Covers ADR-0192: the coder agent's working discipline, rewritten after measuring 69 real coder
# dispatches (turns x context is the cost lever; the two largest self-inflicted losses were a
# never-emitted PATTERN header and edits by absolute path into the shared checkout). Every
# assertion here pins an INSTRUCTION, not an enforcement (rule 16): a green run says the clause
# is present in the prompt the model receives, nothing more. The enforcement side of the same
# behaviours lives in pre-flight-pattern-enforce.sh and worktree-git-guardrail.sh, tested
# elsewhere.
#
# Prose assertions match a flattened, undecorated, case-insensitive copy of the section they
# belong to (rule 3), extracted by heading (litter-discipline LA idiom), so a clause wrapped,
# bolded or backticked is still the same clause. Structural markers (headings) stay line-wise.
#
# ASSERTION LABELS ARE CD-PREFIXED (CD0..CD10) — grepped across the tests/ directory at HEAD
# before this file was written; the prefix was unused.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
REPO=$(cd "$STAGING/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

CODER="$STAGING/plugin/agents/coder.md"
DOCSCI="$REPO/.github/workflows/docs-ci.yml"

# section <heading-text> <file> -> the body of that `## ` section, flattened, undecorated,
# lower-cased, on stdout. Empty when the heading is absent.
section() {
  awk -v h="## $1" '$0 == h {f=1; next} /^## /{f=0} f' "$2" \
    | tr '\n' ' ' | tr -s ' ' | sed 's/[`*_]//g' | tr 'A-Z' 'a-z'
}

if [ ! -f "$CODER" ]; then
  bad "CD0: $CODER missing — nothing below can run"
  echo "----"; echo "PASS=$PASS FAIL=$FAIL"; exit 1
fi

# ==============================================================================================
# CD0. A `## Hard rules` section exists and sits BEFORE `## When to invoke`: the rules a hook or
# the orchestrator enforces are the first thing after the role line, not the last (ADR-0192 §D1).
# Line-wise (rule 3: a heading is structure). Position is asserted because salience is the point:
# the measured never-emitted PATTERN header sat 750 tokens deep in the old layout.
# ==============================================================================================
# plant: CD0 | plugin/agents/coder.md | ## Hard rules | ## Hard rulez
HR_LINE=$(grep -n '^## Hard rules$' "$CODER" | head -1 | cut -d: -f1)
WI_LINE=$(grep -n '^## When to invoke$' "$CODER" | head -1 | cut -d: -f1)
if [ -n "$HR_LINE" ] && [ -n "$WI_LINE" ] && [ "$HR_LINE" -lt "$WI_LINE" ]; then
  ok "CD0: '## Hard rules' section present (line $HR_LINE) before '## When to invoke' (line $WI_LINE)"
else
  bad "CD0: '## Hard rules' missing or not before '## When to invoke' (hard=${HR_LINE:-none}, when=${WI_LINE:-none})"
fi
HARD=$(section "Hard rules" "$CODER")
PROC=$(section "Process" "$CODER")

# ==============================================================================================
# CD1. The PATTERN header must be in the SAME MESSAGE as the tool call, and that rule lives in
# Hard rules (ADR-0192 §D1). Measured: 54 of 83 blocked edits had no header at all in the window.
# ==============================================================================================
# plant: CD1 | plugin/agents/coder.md | in the same message as the tool call
if printf '%s' "$HARD" | grep -q 'same message'; then
  ok "CD1: Hard rules state the PATTERN header goes in the same message as the tool call"
else
  bad "CD1: Hard rules do not state 'same message' for the PATTERN header"
fi

# ==============================================================================================
# CD2. Relative-path discipline: Hard rules name `pwd` and 'relative path only'. The plant INVERTS
# the rule (relative -> absolute) rather than deleting it, because an inverted rule is the exact
# failure the 23 rejected absolute-path edits came from (ADR-0068 §D11, ADR-0192 §D1).
# ==============================================================================================
# plant: CD2 | plugin/agents/coder.md | by relative path only | by absolute path only
if printf '%s' "$HARD" | grep -q 'pwd' && printf '%s' "$HARD" | grep -q 'relative path only'; then
  ok "CD2: Hard rules require pwd once and edits by relative path only"
else
  bad "CD2: Hard rules lack the pwd + 'relative path only' discipline"
fi

# ==============================================================================================
# CD3. Memory is CONSUMED, not only produced (rule 17): Process reads the coder's own topics/
# shards before editing. Measured: shards written in 2 runs, read back by hand in 3 of 69, no
# index ever curated (ADR-0192 §D2).
# ==============================================================================================
# plant: CD3 | plugin/agents/coder.md | read every shard whose name matches this task's id, slug or files
if printf '%s' "$PROC" | grep -q 'agent-memory/coder/topics/' && printf '%s' "$PROC" | grep -q 'read every shard whose name matches'; then
  ok "CD3: Process lists .claude/agent-memory/coder/topics/ and reads the matching shards"
else
  bad "CD3: Process does not read the coder's own topics/ shards before editing"
fi

# ==============================================================================================
# CD4. Verification hygiene: a bound on full-suite runs and a tail pipe on every verification
# command (ADR-0192 §D4). Measured: 11.9 test executions per run on average, 135 tool results
# over 20k characters.
# ==============================================================================================
# plant: CD4 | plugin/agents/coder.md | at most twice | as often as needed
if printf '%s' "$PROC" | grep -q 'at most twice' && printf '%s' "$PROC" | grep -q 'tail -n 40'; then
  ok "CD4: Process bounds full-suite runs (at most twice) and pipes output through tail -n 40"
else
  bad "CD4: Process lacks the full-suite bound and/or the tail -n 40 pipe"
fi

# ==============================================================================================
# CD5. Definition of done: the diff is read hunk by hunk against the plan's sub-steps
# (ADR-0192 §D5).
# ==============================================================================================
# plant: CD5 | plugin/agents/coder.md | read it hunk by hunk against the plan's sub-steps
if printf '%s' "$PROC" | grep -q 'hunk by hunk' && printf '%s' "$PROC" | grep -q 'sub-step'; then
  ok "CD5: Process has a definition-of-done pass reading the diff hunk by hunk against sub-steps"
else
  bad "CD5: Process lacks the hunk-by-hunk definition-of-done pass"
fi

# ==============================================================================================
# CD6. Conditional tooling: the context7/LSP step says what to do when the tools are ABSENT
# (skip). Measured: 1 context7 call and 1 LSP call across 69 runs; LSP does not register in
# subagents on native builds (ADR-0038). An unconditional instruction to call an absent tool is
# a turn wasted on every dispatch (ADR-0192 §D6).
# ==============================================================================================
# plant: CD6 | plugin/agents/coder.md | skip this step without comment
if printf '%s' "$PROC" | grep -q 'skip this step'; then
  ok "CD6: the context7/LSP step has an explicit skip branch for absent tools"
else
  bad "CD6: the context7/LSP step has no skip branch for absent tools"
fi

# ==============================================================================================
# CD7. The eslint instruction is conditional on the tool being available. Measured: 0 eslint MCP
# calls, no eslint MCP server configured on this machine (ADR-0192 §D6). Scoped to the line(s)
# that name the tool, so prose elsewhere saying 'available' cannot satisfy it (rule 1).
# ==============================================================================================
# plant: CD7 | plugin/agents/coder.md | If `mcp__eslint__check_file` is available, run it | Run `mcp__eslint__check_file`
ESL=$(grep -F 'mcp__eslint__check_file' "$CODER" | tr 'A-Z' 'a-z')
if [ -n "$ESL" ] && printf '%s' "$ESL" | grep -q 'available'; then
  ok "CD7: the eslint instruction is conditional ('available') on the tool being present"
else
  bad "CD7: the eslint instruction is missing or unconditional"
fi

# ==============================================================================================
# CD8. Size ceiling. VACUITY GUARD (rule 10): this is a ceiling on the file, not a per-clause
# pin; it exists so the sections above cannot silently regrow into the 10,469-byte layout whose
# salience failure was measured. The ceiling is frozen at the rewrite's measured size (9,995
# bytes on 2026-09-04) plus ~400 bytes of headroom; a deliberate growth bumps it here, with the
# reason, in the same commit.
# ==============================================================================================
# plant: CD8 | plugin/agents/coder.md | ## Edge Cases | ## Edge Cases\nCD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler. CD8 vacuity plant filler.
CD8_CEILING=10400
SIZE=$(wc -c < "$CODER" | tr -d ' ')
if [ "$SIZE" -le "$CD8_CEILING" ]; then
  ok "CD8: coder.md is $SIZE bytes, within the $CD8_CEILING-byte ceiling (vacuity guard)"
else
  bad "CD8: coder.md is $SIZE bytes, over the $CD8_CEILING-byte ceiling — bump the ceiling deliberately or trim"
fi

# ==============================================================================================
# CD9. Forward guards on clauses the rewrite had to keep verbatim because sibling suites pin
# them: the Cleanup bullet inside Output Format (litter-discipline LA), the classifier heading
# (review-triage-fix run-tests.sh greps the deployed copy), and 'never commit' inside Hard rules
# (worktree-isolation-contract H6 pins presence anywhere; here it is section-scoped).
# ==============================================================================================
# plant: CD9a | plugin/agents/coder.md | - **Cleanup**: list every temporary file | - **Tidy**: list every temporary file
OF="$TMP/of.txt"
awk '/^## Output Format$/{f=1; next} /^## /{f=0} f' "$CODER" > "$OF"
if [ -s "$OF" ] && grep -qF '**Cleanup**' "$OF"; then
  ok "CD9a: Cleanup bullet still inside ## Output Format"
else
  bad "CD9a: Cleanup bullet missing from ## Output Format"
fi

# plant: CD9b | plugin/agents/coder.md | ## Pre-flight Pattern Classifier | ## Pre-flight Classifier
if grep -q '^## Pre-flight Pattern Classifier$' "$CODER"; then
  ok "CD9b: '## Pre-flight Pattern Classifier' heading present"
else
  bad "CD9b: '## Pre-flight Pattern Classifier' heading missing"
fi

# plant: CD9c | plugin/agents/coder.md | **Never commit, never `git add`.** | **Never `git add`.**
if printf '%s' "$HARD" | grep -q 'never commit'; then
  ok "CD9c: Hard rules state 'never commit'"
else
  bad "CD9c: Hard rules do not state 'never commit'"
fi

# ==============================================================================================
# CD10. Registration: docs-ci.yml's shell-tests loop runs this harness, appended right after
# codex-reviewer-schema (LG1 idiom). Not plantable: plant-check.sh reaches staging/ and ../docs/
# only, never .github/, so a plant against the workflow is inexpressible; stated here so the
# missing `# plant:` line reads as a known limit, not an oversight (rule 2).
# ==============================================================================================
DOCSCI_LOOP=$(grep 'for t in ' "$DOCSCI" 2>/dev/null | head -1)
if printf '%s' "$DOCSCI_LOOP" | grep -qE 'codex-reviewer-schema[[:space:]]+coder-discipline[[:space:];]'; then
  ok "CD10: docs-ci.yml's shell-tests loop runs coder-discipline, appended right after codex-reviewer-schema"
else
  bad "CD10: coder-discipline is not appended after codex-reviewer-schema in docs-ci.yml's shell-tests loop"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
