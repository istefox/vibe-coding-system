#!/bin/bash
# skill-text-corrections test harness (ADR-0035) -- six instruction-layer defects from the audit
# (SPEC.md / issue #39, range "3.1, 3.17 to 3.21") across five staging skills. Five lettered
# sections, one per file (git-repo-init carries two findings, fixed in one Fase 5 rewrite):
#   Section A -- claude-md-generator/SKILL.md:13 hardcoded "root CLAUDE.md" as the only write
#     target, conflicting with concept-to-code Branch B's own dispatch prompt ("Generate
#     CLAUDE.md.proposed ... Do NOT overwrite CLAUDE.md"). Fixed with an explicit
#     caller-provided-output-path contract; also adds the file's first sync-to-claude.sh PAIRS
#     entry (none existed -- ADR-0025 SS2.3 flagged this gap for this issue by name).
#   Section B -- prompt-builder/SKILL.md:3 NEGATIVE clause named two ghost skills
#     (vibrofer-perplexity-prompt, which exists nowhere in this system; skill-creator, a
#     marketplace/catalog plugin -- docs/plugins-and-mcp-catalog.md:21 -- not a staging skill).
#     Fixed with plain-terms exclusions, no skill names.
#   Section C -- git-repo-init/SKILL.md's Fase 5: line 48 asserted "no further questions" while
#     line 58 instructed, then contradicted itself on, opening a browser. Fixed with one HITL
#     recap gate (path, visibility, files, remote; Approve/Abort, recommended-option convention)
#     inserted between scaffolding and the first commit, and a browser-free verify step.
#   Section D -- swiftui-pro/SKILL.md:29 asserted iOS 26/Swift 6.2 as unconditional defaults,
#     fighting a project's own declared target. Fixed with a scoping bullet placed before the
#     specific defaults it governs.
#   Section E -- find-skills/SKILL.md:3 triggered on any "how do I do X" question, overlapping
#     virtually every installed skill. Fixed with an explicit-intent-only trigger and a NEGATIVE
#     clause.
# Every assertion is a static grep/sed/positional check against real file content -- no mktemp -d
# fixtures, no dynamic extract-and-execute (unlike scope-guards.test.sh/*-autopilot-gates.test.sh):
# none of these five files has runtime bash logic to pin down (ADR-0035 SS2.6/SS3.8).
# Zero $HOME dependency: runs identically in CI (ubuntu-latest, no ~/.claude) and locally.
# Never point any variable at $HOME/.claude/... -- that is the deployed copy, out of scope.
# Bash 3.2 clean. Run: bash skill-text-corrections.test.sh
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)              # staging/plugin/scripts
STAGING=$(cd "$SCRIPTS/../.." && pwd)                    # staging/
CMG_SKILL="$STAGING/plugin/skills/claude-md-generator/SKILL.md"
PB_SKILL="$STAGING/plugin/skills/prompt-builder/SKILL.md"
GRI_SKILL="$STAGING/plugin/skills/git-repo-init/SKILL.md"
SUI_SKILL="$STAGING/plugin/skills/swiftui-pro/SKILL.md"
FS_SKILL="$STAGING/plugin/skills/find-skills/SKILL.md"
SYNC="$STAGING/sync-to-claude.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

# frontmatter_ok <file> -- structural sanity check, not a real YAML parser: file opens with a
# `---` line, a second `---` closing line exists, and `name:`/`description:` both appear between
# them. Bash-only, zero dependency (no python, no yq), matching this directory's own convention.
frontmatter_ok() {
  _f="$1"
  [ "$(sed -n '1p' "$_f")" = "---" ] || return 1
  _close=$(awk 'NR>1 && $0=="---"{print NR; exit}' "$_f")
  [ -n "$_close" ] || return 1
  _fm=$(sed -n "2,${_close}p" "$_f")
  printf '%s\n' "$_fm" | grep -q '^name:' || return 1
  printf '%s\n' "$_fm" | grep -q '^description:' || return 1
  return 0
}

# =====================================================================================
# Section A -- Finding A: claude-md-generator output-path contract
# =====================================================================================

# A1 (static, genuine RED now): the old unconditional "root CLAUDE.md" instruction is gone.
if grep -qF 'Generate a root `CLAUDE.md` that is **lean and Anthropic-compliant**' "$CMG_SKILL"; then
  bad "A1: old unconditional 'root CLAUDE.md' instruction is still present"
else
  ok "A1: old unconditional 'root CLAUDE.md' instruction is gone"
fi

# A2 (static, genuine RED now): the caller-provided-output-path contract is present.
grep -qF 'output path given by the caller' "$CMG_SKILL" \
  && ok "A2: caller-provided output-path contract is present" \
  || bad "A2: caller-provided output-path contract should be present"

# A3 (static, genuine RED now): the never-touch-CLAUDE.md-from-the-chain rule is present.
grep -qF 'Never touch `CLAUDE.md` directly when invoked from the chain' "$CMG_SKILL" \
  && ok "A3: never-touch-CLAUDE.md-from-the-chain rule is present" \
  || bad "A3: never-touch-CLAUDE.md-from-the-chain rule should be present"

# A4 (static, non-regression companion, already passing today): frontmatter still parses.
frontmatter_ok "$CMG_SKILL" && ok "A4: claude-md-generator frontmatter still parses" \
  || bad "A4: claude-md-generator frontmatter should still parse"

# A5 (static, genuine RED now): sync-to-claude.sh gains claude-md-generator's first PAIRS entry.
grep -qF 'plugin/skills/claude-md-generator/SKILL.md|skills/claude-md-generator/SKILL.md' "$SYNC" \
  && ok "A5: claude-md-generator has a PAIRS entry in sync-to-claude.sh" \
  || bad "A5: claude-md-generator should have a PAIRS entry in sync-to-claude.sh"

# =====================================================================================
# Section B -- Finding B: prompt-builder ghost skill names
# =====================================================================================

# B1 (static, genuine RED now): 'vibrofer-perplexity-prompt' is gone from the whole file.
_b1=$(grep -cF 'vibrofer-perplexity-prompt' "$PB_SKILL")
[ "$_b1" -eq 0 ] && ok "B1: 'vibrofer-perplexity-prompt' is gone from prompt-builder" \
  || bad "B1: 'vibrofer-perplexity-prompt' should be gone, found $_b1 occurrence(s)"

# B2 (static, genuine RED now): 'skill-creator' is gone from the whole file.
_b2=$(grep -cF 'skill-creator' "$PB_SKILL")
[ "$_b2" -eq 0 ] && ok "B2: 'skill-creator' is gone from prompt-builder" \
  || bad "B2: 'skill-creator' should be gone, found $_b2 occurrence(s)"

# B3 (static, non-regression companion, already passing today): the NEGATIVE clause's own subject
# survives in plain terms, isolated to the frontmatter description line (line 3) so this cannot
# pass by accident against unrelated prose.
sed -n '3p' "$PB_SKILL" | grep -qF 'NON usare per ricerche Perplexity Vibrofer' \
  && ok "B3: NEGATIVE clause still excludes Perplexity Vibrofer research, in plain terms" \
  || bad "B3: NEGATIVE clause should still exclude Perplexity Vibrofer research"

# B4 (static, non-regression companion, already passing today): frontmatter still parses.
frontmatter_ok "$PB_SKILL" && ok "B4: prompt-builder frontmatter still parses" \
  || bad "B4: prompt-builder frontmatter should still parse"

# =====================================================================================
# Section C -- Finding C: git-repo-init Fase 5 HITL gate + browser fix
# =====================================================================================

# C1 (static, genuine RED now): the old "no further questions" preamble is gone.
if grep -qF 'Ordine fisso, nessuna domanda aggiuntiva:' "$GRI_SKILL"; then
  bad "C1: old 'nessuna domanda aggiuntiva' preamble is still present"
else
  ok "C1: old 'nessuna domanda aggiuntiva' preamble is gone"
fi

# C2 (static, genuine RED now): the old, self-contradicting browser instruction is gone.
if grep -qF '`gh repo view --web` NO' "$GRI_SKILL"; then
  bad "C2: old self-contradicting browser instruction is still present"
else
  ok "C2: old self-contradicting browser instruction is gone"
fi

# C3 (static, genuine RED now): exactly one HITL gate marker (SPEC success criterion: "exactly one").
_c3=$(grep -cF 'Gate di conferma (HITL)' "$GRI_SKILL")
[ "$_c3" -eq 1 ] && ok "C3: exactly one HITL gate marker present" \
  || bad "C3: expected exactly one HITL gate marker, found $_c3"

# C4 (static, genuine RED now): the recommended-option convention is honored.
grep -qF '"Approva (Recommended)"' "$GRI_SKILL" \
  && ok "C4: recommended-option convention honored ('Approva (Recommended)')" \
  || bad "C4: 'Approva (Recommended)' should be present"

# C5 (static, genuine RED now): the browser is explicitly never opened. Today's text reads "non
# aprire il browser" (a different string -- different first word) inside the self-contradicting
# sentence C2 already targets; this checks for the NEW phrasing specifically.
grep -qF 'mai aprire il browser' "$GRI_SKILL" \
  && ok "C5: 'mai aprire il browser' present" \
  || bad "C5: 'mai aprire il browser' should be present"

# C6 (static, genuine RED now, positional): the gate sits between scaffolding (step 4) and the
# first commit, not before or after. Anchors are content-based (stable across the renumbering
# steps 6-9 -> 7-10 undergo), not step-number-based.
_scaffold_line=$(grep -nF '4. Genera `CLAUDE.md` e `PROJECT_BRIEF.md`' "$GRI_SKILL" | head -1 | cut -d: -f1)
_gate_line=$(grep -nF 'Gate di conferma (HITL)' "$GRI_SKILL" | head -1 | cut -d: -f1)
_commit_line=$(grep -nF 'Primo commit, sempre conventional' "$GRI_SKILL" | head -1 | cut -d: -f1)
if [ -n "$_scaffold_line" ] && [ -n "$_gate_line" ] && [ -n "$_commit_line" ] \
   && [ "$_gate_line" -gt "$_scaffold_line" ] && [ "$_gate_line" -lt "$_commit_line" ]; then
  ok "C6: HITL gate sits between scaffolding and the first commit"
else
  bad "C6: HITL gate should sit between scaffolding (line $_scaffold_line) and first commit (line $_commit_line), found at line $_gate_line"
fi

# C7 (static, non-regression companion, already passing today): frontmatter still parses.
frontmatter_ok "$GRI_SKILL" && ok "C7: git-repo-init frontmatter still parses" \
  || bad "C7: git-repo-init frontmatter should still parse"

# =====================================================================================
# Section D -- Finding D: swiftui-pro scoping line
# =====================================================================================

# D1 (static, genuine RED now): the scoping bullet is present. Double-quoted (apostrophe in
# "project's" -- see this file's Quoting rule).
grep -qF "the project's own declared deployment target and Swift version" "$SUI_SKILL" \
  && ok "D1: scoping bullet (declared deployment target and Swift version) is present" \
  || bad "D1: scoping bullet should be present"

# D2 (static, non-regression companion, already passing today): the original iOS 26 default
# bullet is untouched.
grep -qF 'iOS 26 exists, and is the default deployment target for new apps.' "$SUI_SKILL" \
  && ok "D2: original iOS 26 default bullet is unchanged" \
  || bad "D2: original iOS 26 default bullet should be unchanged"

# D3 (static, genuine RED now, positional): the scoping bullet precedes the specific default it
# governs. Double-quoted for the same reason as D1.
_scope_line=$(grep -n "the project's own declared deployment target and Swift version" "$SUI_SKILL" | head -1 | cut -d: -f1)
_ios26_line=$(grep -n 'iOS 26 exists, and is the default deployment target for new apps.' "$SUI_SKILL" | head -1 | cut -d: -f1)
if [ -n "$_scope_line" ] && [ -n "$_ios26_line" ] && [ "$_scope_line" -lt "$_ios26_line" ]; then
  ok "D3: scoping bullet precedes the iOS 26/Swift 6.2 defaults it governs"
else
  bad "D3: scoping bullet should precede the iOS 26/Swift 6.2 defaults (scope=$_scope_line, ios26=$_ios26_line)"
fi

# D4 (static, non-regression companion, already passing today): frontmatter still parses.
frontmatter_ok "$SUI_SKILL" && ok "D4: swiftui-pro frontmatter still parses" \
  || bad "D4: swiftui-pro frontmatter should still parse"

# =====================================================================================
# Section E -- Finding E: find-skills narrowed trigger + NEGATIVE clause
# =====================================================================================

# E1 (static, genuine RED now, isolated to the frontmatter description line): narrowed to explicit
# skill-discovery intent.
sed -n '3p' "$FS_SKILL" | grep -qF 'explicitly asks to find, search for, or install' \
  && ok "E1: description narrows to explicit skill-discovery intent" \
  || bad "E1: description should narrow to explicit skill-discovery intent"

# E2 (static, genuine RED now, isolated to line 3): a NEGATIVE clause is present.
sed -n '3p' "$FS_SKILL" | grep -qF 'Do NOT use' \
  && ok "E2: NEGATIVE clause ('Do NOT use') is present" \
  || bad "E2: NEGATIVE clause should be present"

# E3 (static, genuine RED now, isolated to line 3): the NEGATIVE clause excludes requests already
# covered by an installed skill (not just a generic exclusion).
sed -n '3p' "$FS_SKILL" | grep -qF 'already-installed skill already covers the request' \
  && ok "E3: NEGATIVE clause excludes requests covered by an installed skill" \
  || bad "E3: NEGATIVE clause should exclude requests covered by an installed skill"

# E4 (static, non-regression companion, already passing today): frontmatter still parses.
frontmatter_ok "$FS_SKILL" && ok "E4: find-skills frontmatter still parses" \
  || bad "E4: find-skills frontmatter should still parse"

# =====================================================================================
# Section F (issue #56) -- disable-model-invocation restored on the two skills that lost it
# =====================================================================================
# Both skills carried the flag until the #29 staging refresh mirrored deployment wholesale
# (ADR-0025 Consequences flagged it and left it, being out of that issue's scope). Without it the
# model may invoke them on its own: interview-driver seizes the turn with AskUserQuestion, and
# fastapi-react-vibe writes a multi-file scaffold. Blueprint sec. 8's own templates for both skills
# show the flag, so this restores a documented default rather than inventing one.
# The flag's other documented effect is a trade-off, not a bug (blueprint changelog 2026-07-09,
# CC v2.1.196): a scheduled /loop fire does NOT execute a flagged skill, it pastes it as plain text.
# Neither of these two is a /loop target, so the safety side wins here.

for _pair in "interview-driver" "fastapi-react-vibe"; do
  _f="$STAGING/plugin/skills/$_pair/SKILL.md"
  _close=$(awk 'NR>1 && $0=="---"{print NR; exit}' "$_f" 2>/dev/null)
  if [ -n "$_close" ] && sed -n "2,${_close}p" "$_f" | grep -qx 'disable-model-invocation: true'; then
    ok "F: $_pair carries disable-model-invocation: true in frontmatter"
  else
    bad "F: $_pair should carry disable-model-invocation: true (model can self-invoke it today)"
  fi
done

# F3: both files still parse as frontmatter after the insertion.
frontmatter_ok "$STAGING/plugin/skills/interview-driver/SKILL.md" \
  && ok "F3: interview-driver frontmatter still parses" \
  || bad "F3: interview-driver frontmatter should still parse"
frontmatter_ok "$STAGING/plugin/skills/fastapi-react-vibe/SKILL.md" \
  && ok "F4: fastapi-react-vibe frontmatter still parses" \
  || bad "F4: fastapi-react-vibe frontmatter should still parse"

# F5: the blueprint sentence that names which skills carry the flag must not still name
# project-bootstrap, retired from staging by ADR-0025. It named three skills, and was wrong about
# all three: two had lost the flag and one no longer existed.
if grep -q 'Three staged skills carry that flag' "$STAGING/../docs/vibe-coding-system.md"; then
  bad "F5: blueprint still claims 'Three staged skills carry that flag' (false on all three)"
else
  ok "F5: blueprint's stale flag-carrier claim is corrected"
fi

printf '\nPASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
