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

# --- E5-E8 (issue #59): the BODY must not be broader than the frontmatter it sits under -----------
# #39 narrowed line 3 and stopped there, by its own SPEC's scope. The body kept telling the model to
# use the skill for "how do I do X" and "can you do X" — the exact cases line 3's NEGATIVE clause
# excludes. A model reasoning from body content rather than frontmatter alone would have walked
# straight back into the overlap the frontmatter fix was written to close. Same defect class as
# ADR-0041 Finding A and ADR-0042: prose and machine-read field disagreeing, with nothing in the
# file to say which one wins.
FS_BODY=$(sed -n '5,$p' "$FS_SKILL")

E5_BROAD=""
# Checked as whole phrases: "how do I do X" as a TRIGGER is what must go. The narrowed body may
# still mention such a question as an example of what NOT to fire on, which is why E6 exists.
for _p in 'Asks "how do I do X"' 'Asks "can you do X"' 'Expresses interest in extending agent capabilities' \
          'Mentions they wish they had help with a specific domain'; do
  printf '%s' "$FS_BODY" | grep -qF "$_p" && E5_BROAD="$E5_BROAD | $_p"
done
if [ -z "$E5_BROAD" ]; then
  ok "E5: body no longer lists general-question triggers"
else
  bad "E5: body still lists triggers the frontmatter excludes:$E5_BROAD"
fi

# E6: the body carries the frontmatter's NEGATIVE routing, not just the positive scope. Stating
# where the skill applies without stating where it does not is what left the old body broad.
if printf '%s' "$FS_BODY" | grep -qF 'Do NOT use this skill' \
   && printf '%s' "$FS_BODY" | grep -qiF 'already installed'; then
  ok "E6: body carries the NEGATIVE routing, including the installed-skill exclusion"
else
  bad "E6: body should carry the NEGATIVE routing, including the installed-skill exclusion"
fi

# E7: the worked examples must be skill-discovery requests, not ordinary task requests. Examples are
# what a model pattern-matches on, so a narrowed prose section with broad examples under it teaches
# the broad behaviour anyway.
# Scoped to the example lines themselves (those mapping a user utterance to a `npx skills find`
# command), NOT to the whole body: the corrected body legitimately quotes "How do I make my React
# app faster?" as a case to answer directly rather than search on. A bare absence check would pass
# on capitalisation alone here, which is not evidence of anything.
if printf '%s' "$FS_BODY" | grep -F '`npx skills find' | grep -qiE '"?how do i|can you help me'; then
  bad "E7: a search example is still phrased as an ordinary task request"
else
  ok "E7: search examples are phrased as skill-discovery requests"
fi

# E8 (non-regression): the body still documents the CLI it exists to drive — the narrowing must not
# hollow the skill out.
if printf '%s' "$FS_BODY" | grep -qF 'npx skills find' \
   && printf '%s' "$FS_BODY" | grep -qF 'npx skills add'; then
  ok "E8: body still documents the find/add commands"
else
  bad "E8: body should still document the find/add commands"
fi

# =====================================================================================
# Section F (issue #56, amended by ADR-0067) -- who carries disable-model-invocation
# =====================================================================================
# Both skills carried the flag until the #29 staging refresh mirrored deployment wholesale
# (ADR-0025 Consequences flagged it and left it, being out of that issue's scope). #56 restored it
# on both. ADR-0067 then removed it from interview-driver ALONE, because the flag makes a skill
# user-invocable only and concept-to-code Step 1 / Step H1 dispatch interview-driver through the
# Skill tool -- so the restore made the chain's first step permanently unreachable
# ("cannot be used with Skill tool due to disable-model-invocation"). It had worked before #56 only
# because the flag was missing. There is no settings-level escape hatch: the frontmatter key locks
# the skill state to on/name-only, and skillOverrides can only disable further, never re-enable.
#
# F1 is therefore an INVERTED assertion, and deliberately so. Do not "restore" the flag on
# interview-driver: that reintroduces the regression. fastapi-react-vibe keeps it (F2) -- no chain
# invokes it and it writes a multi-file scaffold unprompted.
# The flag's other documented effect (blueprint changelog 2026-07-09, CC v2.1.196): a scheduled
# /loop fire does NOT execute a flagged skill, it pastes it as plain text. Removing it from
# interview-driver also closes that trap for `/loop … /interview-driver`.

# F1 (inverted): interview-driver must NOT carry the flag -- the chain has to invoke it.
_f="$STAGING/plugin/skills/interview-driver/SKILL.md"
_close=$(awk 'NR>1 && $0=="---"{print NR; exit}' "$_f" 2>/dev/null)
if [ -n "$_close" ] && sed -n "2,${_close}p" "$_f" | grep -qx 'disable-model-invocation: true'; then
  bad "F1: interview-driver must NOT carry disable-model-invocation (c2c Step 1 cannot invoke it)"
else
  ok "F1: interview-driver carries no disable-model-invocation, so the chain can invoke it"
fi

# F2: fastapi-react-vibe still carries it -- untouched by ADR-0067.
_f="$STAGING/plugin/skills/fastapi-react-vibe/SKILL.md"
_close=$(awk 'NR>1 && $0=="---"{print NR; exit}' "$_f" 2>/dev/null)
if [ -n "$_close" ] && sed -n "2,${_close}p" "$_f" | grep -qx 'disable-model-invocation: true'; then
  ok "F2: fastapi-react-vibe carries disable-model-invocation: true in frontmatter"
else
  bad "F2: fastapi-react-vibe should carry disable-model-invocation: true (model can self-invoke it today)"
fi

# F3: both files still parse as frontmatter after the edit.
frontmatter_ok "$STAGING/plugin/skills/interview-driver/SKILL.md" \
  && ok "F3: interview-driver frontmatter still parses" \
  || bad "F3: interview-driver frontmatter should still parse"
frontmatter_ok "$STAGING/plugin/skills/fastapi-react-vibe/SKILL.md" \
  && ok "F4: fastapi-react-vibe frontmatter still parses" \
  || bad "F4: fastapi-react-vibe frontmatter should still parse"

# F5: the blueprint sentence naming the flag carriers must match the files. It has been wrong twice
# already -- it named project-bootstrap after ADR-0025 retired it, and it named two skills that had
# lost the flag. Asserted POSITIVELY (the three real carriers present, interview-driver absent)
# rather than by banning the stale wording: the count in that sentence legitimately returns to
# "three" under ADR-0067, so a string ban would now fire on the CORRECT sentence.
_BP="$STAGING/../docs/vibe-coding-system.md"
_LOOPLINE=$(grep -n 'staged skills carry that flag' "$_BP" | head -1 | cut -d: -f1)
if [ -n "$_LOOPLINE" ]; then
  _S=$(sed -n "${_LOOPLINE}p" "$_BP")
  if printf '%s' "$_S" | grep -qF '`fastapi-react-vibe`' \
     && printf '%s' "$_S" | grep -qF '`goal-loop`' \
     && printf '%s' "$_S" | grep -qF '`research-prompt`' \
     && ! printf '%s' "$_S" | grep -qF '`interview-driver`, `fastapi-react-vibe`'; then
    ok "F5: blueprint's flag-carrier list matches the files (three carriers, interview-driver out)"
  else
    bad "F5: blueprint's flag-carrier list disagrees with the files"
  fi
else
  bad "F5: blueprint no longer carries the /loop flag-carrier sentence at all"
fi

# F6 (ADR-0067, generalising guard): NO skill that concept-to-code declares chain-invokable may
# carry disable-model-invocation. The rule is not new — docs/guida-workflow-orchestrazione.md §10
# has carried it as a named troubleshooting entry since the design-brainstorm work, and
# design-brainstorm/ and clean-public-repo/ both enforce it with their own negative anchors. #56
# broke it on interview-driver anyway, because nothing checked the class, only the instances.
# The skill list is DERIVED from c2c §25 rather than hardcoded here, so adding a chain-invoked skill
# extends the guard automatically.
_C2C="$STAGING/plugin/skills/concept-to-code/SKILL.md"
_INVOKABLE_LINE=$(grep -n 'skills invokable inside this chain' "$_C2C" | head -1 | cut -d: -f1)
_F6_CHECKED=0
_F6_BAD=""
if [ -n "$_INVOKABLE_LINE" ]; then
  # Backticked tokens on that line that are also real staged skill directories. The line also
  # backticks agent names and gate labels; the directory test filters them out.
  for _s in $(sed -n "${_INVOKABLE_LINE}p" "$_C2C" | tr '`' '\n' | sed -n 'n;p' | sort -u); do
    _sf="$STAGING/plugin/skills/$_s/SKILL.md"
    [ -f "$_sf" ] || continue
    _F6_CHECKED=$((_F6_CHECKED + 1))
    _c=$(awk 'NR>1 && $0=="---"{print NR; exit}' "$_sf" 2>/dev/null)
    if [ -n "$_c" ] && sed -n "2,${_c}p" "$_sf" | grep -qx 'disable-model-invocation: true'; then
      _F6_BAD="$_F6_BAD $_s"
    fi
  done
fi
# Count guard: a derived list that silently resolves to nothing reads exactly like full coverage.
if [ "$_F6_CHECKED" -lt 5 ]; then
  bad "F6: only $_F6_CHECKED chain-invokable skills resolved from c2c §25 (expected >= 5) — the derivation broke, the guard is vacuous"
elif [ -n "$_F6_BAD" ]; then
  bad "F6: chain-invokable skill(s) carry disable-model-invocation, which makes c2c unable to invoke them:$_F6_BAD"
else
  ok "F6: none of the $_F6_CHECKED chain-invokable skills carries disable-model-invocation"
fi

# F7/F8 (issue #211, ADR-0084): the OTHER two flag carriers, asserted on the FILES.
# F5 asserts the blueprint sentence names all three; F2 asserts the flag on disk for exactly one of
# them. So goal-loop and research-prompt were pinned only by a sentence in a document — if either
# lost the flag, F5 would still pass (the sentence would still name it) and F6 would still pass
# (neither is chain-invokable, so neither is in its derivation). Same shape as ADR-0042's finding:
# prose and file disagreeing with nothing to say which is authoritative.
#
# Written as two named assertions rather than a loop ON PURPOSE. #211's perimeter check counts a
# skill as covered when a test names its path literally, because a loop or a glob is how a corpus
# SWEEP reaches a file and a sweep says nothing about that skill in particular. A two-element loop
# here would be indistinguishable from one, and these two files would still be reported uncovered —
# which is what happened on the first draft.
carries_flag() {
  _close=$(awk 'NR>1 && $0=="---"{print NR; exit}' "$1" 2>/dev/null)
  [ -n "$_close" ] && sed -n "2,${_close}p" "$1" | grep -qx 'disable-model-invocation: true'
}

if carries_flag "$STAGING/plugin/skills/goal-loop/SKILL.md"; then
  ok "F7: goal-loop carries disable-model-invocation: true in frontmatter (no chain invokes it)"
else
  bad "F7: goal-loop should carry disable-model-invocation: true — the model can self-invoke it today, and F5 would not notice"
fi

if carries_flag "$STAGING/plugin/skills/research-prompt/SKILL.md"; then
  ok "F8: research-prompt carries disable-model-invocation: true in frontmatter (no chain invokes it)"
else
  bad "F8: research-prompt should carry disable-model-invocation: true — the model can self-invoke it today, and F5 would not notice"
fi

printf '\nPASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
