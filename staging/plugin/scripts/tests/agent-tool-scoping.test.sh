#!/bin/bash
# agent-tool-scoping test harness (ADR-0036) -- four frontmatter defects from the audit (SPEC.md /
# issue #40) across architect.md, reviewer.md, researcher.md, and docs/vibe-coding-system.md sec. 3:
#   Section A -- architect.md: unrestricted Bash scoped to Bash(rg *) (blueprint, restored) plus
#     four verification-tool entries (deliberate widening, ADR-0036 SS2.1); effort:
#     max corrected to effort: xhigh (ADR-0036 SS2.4); permissionMode: plan deliberately NOT restored
#     (ADR-0036 SS2.2 -- verified against a live Claude Code docs constraint, not this plan's call).
#     SUPERSEDED IN PART (ADR-0042, issue #91): blueprint's other architect entry, Bash(git *),
#     matched EVERY git subcommand -- commit and push included -- while ADR-0036 SS2.1's own prose
#     asserted they were excluded, and no deny rule covered plain commit/push. A1 now asserts its
#     ABSENCE and A12 the five read-only replacements. Do not "restore" Bash(git *) to match
#     blueprint sec. 3.1's code block: that divergence is deliberate and recorded in the sec. 3.1
#     deployment note.
#   Section B -- reviewer.md: unrestricted Bash scoped to Bash(git diff*)/Bash(git log*) (blueprint,
#     restored, still no git add/commit) plus three verification-tool entries (ADR-0036 SS2.5).
#   Section C -- researcher.md: NOT edited (ADR-0036 SS2.6/SS3.6). Non-regression invariant only --
#     confirms the file, and specifically its mcpServers-less tools: line, stays exactly as it is
#     today, both before and after every other task in this plan.
#   Section D -- docs/vibe-coding-system.md: a new dated changelog entry plus two deployment-note
#     blockquotes (sec. 3.1 architect, sec. 3.3 reviewer) recording why staging/deployed diverges from
#     the blueprint's literal example text (ADR-0036 SS2.7).
#   Section E -- docs/vibe-coding-system.md sec. 3.8/3.9: the mcpServers YAML syntax shown is
#     map-keyed with no `type:` field; current code.claude.com/docs/en/sub-agents (fetched
#     2026-07-11) documents a YAML list with an explicit `type: stdio` field. Corrected in both
#     places, plus the sec. 3.9 field-reference table cell (ADR-0036 SS2.6/SS2.7).
# Every assertion is a static grep/sed/positional check against real file content -- no mktemp -d
# fixtures, no dynamic extract-and-execute (ADR-0036 SS2.8/SS3.8). Sections D/E resolve every anchor
# dynamically with `grep -n` at run time -- never a hardcoded line number -- because Tasks 4 and 5
# insert content earlier in docs/vibe-coding-system.md than sec. 3.8/3.9 live, shifting every later
# line number.
# Zero $HOME dependency: runs identically in CI (ubuntu-latest, no ~/.claude) and locally.
# Never point any variable at $HOME/.claude/... -- that is the deployed copy, out of scope.
# Bash 3.2 clean. Run: bash agent-tool-scoping.test.sh
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)              # staging/plugin/scripts
STAGING=$(cd "$SCRIPTS/../.." && pwd)                    # staging/
REPO_ROOT=$(cd "$STAGING/.." && pwd)                     # repo root
ARCH_AGENT="$STAGING/plugin/agents/architect.md"
REV_AGENT="$STAGING/plugin/agents/reviewer.md"
RES_AGENT="$STAGING/plugin/agents/researcher.md"
BLUEPRINT="$REPO_ROOT/docs/vibe-coding-system.md"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

# frontmatter_ok <file> -- structural sanity check, not a real YAML parser: file opens with a
# `---` line, a second `---` closing line exists, and `name:`/`description:` both appear between
# them. Bash-only, zero dependency, matching this directory's own convention.
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
# Section A -- architect.md: Bash scope, effort pin, permissionMode invariant
# =====================================================================================

# A1 (ADR-0042, issue #91 -- inverted from ADR-0036's "present"): Bash(git *) grants every git
# subcommand, so it is the one entry that must NOT be here. See A12 for what replaced it.
if sed -n '4p' "$ARCH_AGENT" | grep -qF 'Bash(git *)'; then
  bad "A1: Bash(git *) grants git commit/push and must be gone (ADR-0042)"
else
  ok "A1: Bash(git *) is absent (ADR-0042 supersedes ADR-0036 SS2.1)"
fi

# A2-A6 (static): the remaining five Bash entries are present in the tools: line.
sed -n '4p' "$ARCH_AGENT" | grep -qF 'Bash(rg *)' \
  && ok "A2: Bash(rg *) present" || bad "A2: Bash(rg *) should be present"
sed -n '4p' "$ARCH_AGENT" | grep -qF 'Bash(bash *)' \
  && ok "A3: Bash(bash *) present" || bad "A3: Bash(bash *) should be present"
sed -n '4p' "$ARCH_AGENT" | grep -qF 'Bash(npx markdownlint-cli2*)' \
  && ok "A4: Bash(npx markdownlint-cli2*) present (tightened from npx *)" || bad "A4: tightened npx markdownlint entry should be present"
sed -n '4p' "$ARCH_AGENT" | grep -qF 'Bash(python3 *)' \
  && ok "A5: Bash(python3 *) present" || bad "A5: Bash(python3 *) should be present"
sed -n '4p' "$ARCH_AGENT" | grep -qF 'Bash(shasum *)' \
  && ok "A6: Bash(shasum *) present" || bad "A6: Bash(shasum *) should be present"

# A7 (static, genuine RED now): no bare, unscoped Bash token remains on the tools: line.
if sed -n '4p' "$ARCH_AGENT" | grep -qF 'Bash,'; then
  bad "A7: bare unscoped 'Bash,' is still present on the tools: line"
else
  ok "A7: bare unscoped 'Bash,' is gone from the tools: line"
fi

# A8 (static, genuine RED now): the effort line reads exactly 'effort: xhigh'.
[ "$(sed -n '6p' "$ARCH_AGENT")" = "effort: xhigh" ] \
  && ok "A8: effort line reads exactly 'effort: xhigh'" \
  || bad "A8: effort line should read exactly 'effort: xhigh'"

# A9 (static, invariant -- true both before and after, this plan never adds the field): no
# permissionMode: line anywhere in the file (ADR-0036 SS2.2 -- deliberately not restored).
if grep -q '^permissionMode:' "$ARCH_AGENT"; then
  bad "A9: permissionMode: should not be present (ADR-0036 SS2.2)"
else
  ok "A9: permissionMode: is absent, as decided (ADR-0036 SS2.2)"
fi

# A10 (static, non-regression companion, already passing today): frontmatter still parses.
frontmatter_ok "$ARCH_AGENT" && ok "A10: architect frontmatter still parses" \
  || bad "A10: architect frontmatter should still parse"

# A11 (static, non-regression companion, already passing today): non-Bash tool grants survive the
# tools: line rewrite (Write and both context7 tool names).
if sed -n '4p' "$ARCH_AGENT" | grep -qF 'Write' \
   && sed -n '4p' "$ARCH_AGENT" | grep -qF 'mcp__plugin_context7_context7__resolve-library-id' \
   && sed -n '4p' "$ARCH_AGENT" | grep -qF 'mcp__plugin_context7_context7__query-docs'; then
  ok "A11: Write and both context7 tools still present on the tools: line"
else
  bad "A11: Write and both context7 tools should still be present on the tools: line"
fi

# A12 (ADR-0042, issue #91 -- genuine RED before the fix): the five read-only git entries that
# replace Bash(git *). No-space form, matching reviewer's blueprint-native Bash(git diff*) --
# deliberately normalising the space/no-space split the ADR-0036 plan's Risk B warned against
# doing by accident. No mutating git subcommand begins with any of these five words, so the
# looser prefix match costs nothing here.
A12_MISSING=""
for _e in 'Bash(git log*)' 'Bash(git diff*)' 'Bash(git show*)' 'Bash(git status*)' 'Bash(git rev-parse*)'; do
  sed -n '4p' "$ARCH_AGENT" | grep -qF "$_e" || A12_MISSING="$A12_MISSING $_e"
done
if [ -z "$A12_MISSING" ]; then
  ok "A12: all five read-only git entries present"
else
  bad "A12: missing read-only git entries:$A12_MISSING"
fi

# A13 (ADR-0042): no mutating git entry may be granted. NOTE -- this one passes before the fix as
# well as after: the defect was never a spelled-out Bash(git commit*) entry, it was Bash(git *)
# silently covering it, which is A1's job. A13 is a forward guard against someone adding one by
# hand, not evidence that anything was fixed.
A13_BAD=""
for _e in 'Bash(git commit' 'Bash(git push' 'Bash(git add' 'Bash(git reset' 'Bash(git checkout' \
          'Bash(git merge' 'Bash(git rebase' 'Bash(git clean' 'Bash(git stash'; do
  sed -n '4p' "$ARCH_AGENT" | grep -qF "$_e" && A13_BAD="$A13_BAD $_e"
done
if [ -z "$A13_BAD" ]; then
  ok "A13: no mutating git subcommand is granted"
else
  bad "A13: mutating git entries granted:$A13_BAD"
fi

# A14 (ADR-0042): coupling, tools: line -> body. Every git subcommand actually granted must be
# named in the body's Command-scope bullet. ADR-0041 Finding A is the reason this exists: when an
# agent's prose and its grant disagree, one of them is lying to whoever reads it next, and the
# file itself gives no sign which. The reverse direction is covered by A13.
A14_SCOPE=$(grep -F '**Command scope:**' "$ARCH_AGENT")
A14_UNDOC=""
if [ -z "$A14_SCOPE" ]; then
  bad "A14: no '**Command scope:**' bullet in the body to check the grant against"
else
  for _sub in $(sed -n '4p' "$ARCH_AGENT" | grep -o 'Bash(git [a-z-]*' | sed 's/Bash(git //'); do
    printf '%s' "$A14_SCOPE" | grep -qF "git $_sub" || A14_UNDOC="$A14_UNDOC git-$_sub"
  done
  if [ -z "$A14_UNDOC" ]; then
    ok "A14: every granted git subcommand is named in the Command-scope bullet"
  else
    bad "A14: granted but undocumented in the Command-scope bullet:$A14_UNDOC"
  fi
fi

# A15 (ADR-0042): the body says out loud what the grant no longer permits, and why routing around
# it is not the move -- the same phrasing discipline the write-scope hooks (#87/#58) rely on.
if [ -n "$A14_SCOPE" ] \
   && printf '%s' "$A14_SCOPE" | grep -qF 'git commit' \
   && printf '%s' "$A14_SCOPE" | grep -qF 'git push'; then
  ok "A15: Command-scope bullet names git commit and git push as excluded"
else
  bad "A15: Command-scope bullet should name git commit and git push as excluded"
fi

# =====================================================================================
# Section B -- reviewer.md: Bash scope
# =====================================================================================

# B1-B5 (static, genuine RED now): the five Bash entries are present in the tools: line.
sed -n '4p' "$REV_AGENT" | grep -qF 'Bash(git diff*)' \
  && ok "B1: Bash(git diff*) present" || bad "B1: Bash(git diff*) should be present"
sed -n '4p' "$REV_AGENT" | grep -qF 'Bash(git log*)' \
  && ok "B2: Bash(git log*) present" || bad "B2: Bash(git log*) should be present"
sed -n '4p' "$REV_AGENT" | grep -qF 'Bash(bash *)' \
  && ok "B3: Bash(bash *) present" || bad "B3: Bash(bash *) should be present"
sed -n '4p' "$REV_AGENT" | grep -qF 'Bash(awk *)' \
  && ok "B4: Bash(awk *) present" || bad "B4: Bash(awk *) should be present"
sed -n '4p' "$REV_AGENT" | grep -qF 'Bash(python3 *)' \
  && ok "B5: Bash(python3 *) present" || bad "B5: Bash(python3 *) should be present"

# B6 (static, genuine RED now): no bare, unscoped Bash token remains, and no git add/commit/push
# entry was introduced (reviewer must stay read-only-git -- ADR-0036 SS2.5).
if sed -n '4p' "$REV_AGENT" | grep -qF 'Bash,'; then
  bad "B6: bare unscoped 'Bash,' is still present on the tools: line"
elif sed -n '4p' "$REV_AGENT" | grep -qE 'Bash\(git (add|commit|push)'; then
  bad "B6: a mutating git entry (add/commit/push) must not be present"
else
  ok "B6: bare unscoped 'Bash,' is gone and no mutating git entry was introduced"
fi

# B7 (static, non-regression companion, already passing today): LSP tool grant survives.
sed -n '4p' "$REV_AGENT" | grep -qF 'LSP' \
  && ok "B7: LSP tool still present on the tools: line" \
  || bad "B7: LSP tool should still be present on the tools: line"

# B8 (static, non-regression companion, already passing today): frontmatter still parses.
frontmatter_ok "$REV_AGENT" && ok "B8: reviewer frontmatter still parses" \
  || bad "B8: reviewer frontmatter should still parse"

# B9 (static, non-regression companion, already passing today): effort: high is untouched (this
# finding is Bash-scope only -- ADR-0036 names no reviewer effort change).
[ "$(sed -n '6p' "$REV_AGENT")" = "effort: high" ] \
  && ok "B9: effort line still reads 'effort: high' (untouched)" \
  || bad "B9: effort line should still read 'effort: high' (untouched)"

# =====================================================================================
# Section C -- researcher.md: non-regression invariant only (file is never edited)
# =====================================================================================

# C1 (static, invariant -- true both before and after): no mcpServers: block in the live file
# (ADR-0036 SS2.6 -- deliberately not deployed pending a live smoke test).
if grep -q '^mcpServers:' "$RES_AGENT"; then
  bad "C1: mcpServers: should not be present in researcher.md (ADR-0036 SS2.6)"
else
  ok "C1: mcpServers: is absent, as decided (ADR-0036 SS2.6)"
fi

# C2 (static, invariant -- true both before and after): the tools: line is byte-identical to today.
[ "$(sed -n '4p' "$RES_AGENT")" = "tools: Read, Grep, Glob, WebSearch, WebFetch, mcp__plugin_context7_context7__resolve-library-id, mcp__plugin_context7_context7__query-docs" ] \
  && ok "C2: researcher tools: line is unchanged" \
  || bad "C2: researcher tools: line should be unchanged"

# C3 (static, non-regression companion, already passing today): frontmatter still parses.
frontmatter_ok "$RES_AGENT" && ok "C3: researcher frontmatter still parses" \
  || bad "C3: researcher frontmatter should still parse"

# =====================================================================================
# Section D -- blueprint: changelog entry + sec. 3.1/3.3 deployment notes
# =====================================================================================

# D1 (static, genuine RED now): the new changelog heading is present.
grep -qF '### Correction 2026-07-11 (issue #40, agent tool scoping reconciliation)' "$BLUEPRINT" \
  && ok "D1: issue #40 changelog heading is present" \
  || bad "D1: issue #40 changelog heading should be present"

# D2 (static, genuine RED now): the architect deployment-note phrase is present.
grep -qF 'the deployed/staging `architect.md` widens' "$BLUEPRINT" \
  && ok "D2: architect deployment note is present" \
  || bad "D2: architect deployment note should be present"

# D3 (static, genuine RED now): the reviewer deployment-note phrase is present.
grep -qF 'the deployed/staging `reviewer.md` keeps' "$BLUEPRINT" \
  && ok "D3: reviewer deployment note is present" \
  || bad "D3: reviewer deployment note should be present"

# D4 (static, genuine RED now, positional): the architect note sits inside sec. 3.1, between the
# "### 3.1 architect" and "### 3.2 coder" headings.
_l31=$(grep -nF '### 3.1 architect' "$BLUEPRINT" | head -1 | cut -d: -f1)
_l32=$(grep -nF '### 3.2 coder' "$BLUEPRINT" | head -1 | cut -d: -f1)
_lnote_a=$(grep -nF 'the deployed/staging `architect.md` widens' "$BLUEPRINT" | head -1 | cut -d: -f1)
if [ -n "$_l31" ] && [ -n "$_l32" ] && [ -n "$_lnote_a" ] \
   && [ "$_lnote_a" -gt "$_l31" ] && [ "$_lnote_a" -lt "$_l32" ]; then
  ok "D4: architect deployment note sits within sec. 3.1"
else
  bad "D4: architect deployment note should sit within sec. 3.1 (3.1=$_l31, note=$_lnote_a, 3.2=$_l32)"
fi

# D5 (static, genuine RED now, positional): the reviewer note sits inside sec. 3.3, between the
# "### 3.3 reviewer" and "### 3.4 tester" headings.
_l33=$(grep -nF '### 3.3 reviewer' "$BLUEPRINT" | head -1 | cut -d: -f1)
_l34=$(grep -nF '### 3.4 tester' "$BLUEPRINT" | head -1 | cut -d: -f1)
_lnote_r=$(grep -nF 'the deployed/staging `reviewer.md` keeps' "$BLUEPRINT" | head -1 | cut -d: -f1)
if [ -n "$_l33" ] && [ -n "$_l34" ] && [ -n "$_lnote_r" ] \
   && [ "$_lnote_r" -gt "$_l33" ] && [ "$_lnote_r" -lt "$_l34" ]; then
  ok "D5: reviewer deployment note sits within sec. 3.3"
else
  bad "D5: reviewer deployment note should sit within sec. 3.3 (3.3=$_l33, note=$_lnote_r, 3.4=$_l34)"
fi

# D6 (static, non-regression companion, already passing today): sec. 3.10's heading, the last of the
# ten 3.N subsections, still exists -- cheap canary that section numbering survives every edit.
grep -qF '### 3.10 Cost model' "$BLUEPRINT" \
  && ok "D6: sec. 3.10 Cost model heading still present (numbering canary)" \
  || bad "D6: sec. 3.10 Cost model heading should still be present"

# =====================================================================================
# Section E -- blueprint sec. 3.8/3.9: mcpServers YAML syntax correction
# =====================================================================================

# E1 (static, genuine RED now, scoped to sec. 3.8's own range): the corrected 'type: stdio' field is
# present inside sec. 3.8's researcher.md template.
_l38=$(grep -nF '### 3.8 researcher' "$BLUEPRINT" | head -1 | cut -d: -f1)
_l39=$(grep -nF '### 3.9 Agent frontmatter' "$BLUEPRINT" | head -1 | cut -d: -f1)
if [ -n "$_l38" ] && [ -n "$_l39" ] \
   && sed -n "${_l38},${_l39}p" "$BLUEPRINT" | grep -qF 'type: stdio'; then
  ok "E1: sec. 3.8 mcpServers example includes 'type: stdio'"
else
  bad "E1: sec. 3.8 mcpServers example should include 'type: stdio'"
fi

# E2 (static, genuine RED now, scoped to sec. 3.8's own range): the stacked correction note is
# present, without disturbing the original 2026-05-29 note (ADR-0036 SS2.6/SS2.7 -- stacked, not
# replaced).
if [ -n "$_l38" ] && [ -n "$_l39" ] \
   && sed -n "${_l38},${_l39}p" "$BLUEPRINT" | grep -qF 'does not match deployed or staging reality'; then
  ok "E2: sec. 3.8 correction note is present"
else
  bad "E2: sec. 3.8 correction note should be present"
fi

# E3 (static, genuine RED now, scoped to sec. 3.9's own range): the corrected 'type: stdio' field is
# present inside sec. 3.9's illustrative duplicate example.
_l310=$(grep -nF '### 3.10 Cost model' "$BLUEPRINT" | head -1 | cut -d: -f1)
if [ -n "$_l39" ] && [ -n "$_l310" ] \
   && sed -n "${_l39},${_l310}p" "$BLUEPRINT" | grep -qF 'type: stdio'; then
  ok "E3: sec. 3.9 duplicate example includes 'type: stdio'"
else
  bad "E3: sec. 3.9 duplicate example should include 'type: stdio'"
fi

# E4 (static, genuine RED now, scoped to sec. 3.9's own range): the field-reference table row for
# mcpServers now says 'YAML list', matching the corrected example beneath it.
if [ -n "$_l39" ] && [ -n "$_l310" ] \
   && sed -n "${_l39},${_l310}p" "$BLUEPRINT" | grep -qF 'YAML list'; then
  ok "E4: sec. 3.9 table row says 'YAML list'"
else
  bad "E4: sec. 3.9 table row should say 'YAML list'"
fi

# E5 (static, genuine RED now, scoped to sec. 3.8's own range): exactly two deployment-note/
# correction blockquote paragraphs exist in sec. 3.8 (the original 2026-05-29 note, preserved, plus
# the new 2026-07-11 correction stacked after it) -- confirms "stacked, not replaced".
if [ -n "$_l38" ] && [ -n "$_l39" ]; then
  _cnt=$(sed -n "${_l38},${_l39}p" "$BLUEPRINT" | grep -cE '^> \*\*(Deployment note|Correction)')
  [ "$_cnt" -eq 2 ] && ok "E5: sec. 3.8 has exactly 2 stacked note paragraphs" \
    || bad "E5: sec. 3.8 should have exactly 2 stacked note paragraphs, found $_cnt"
else
  bad "E5: could not resolve sec. 3.8/3.9 anchors"
fi

# D7 (added in the issue #40 RTF cycle): both blueprint deployment notes must carry the
# wrapped-command qualification -- a partial-symmetry regression here reintroduces the exact
# overclaim the BLOCKER fix walked back (sec 3.1 architect note, sec 3.3 reviewer note).
BP_D7="$STAGING/../docs/vibe-coding-system.md"
if grep -q 'disclosed wrapped-command residual' "$BP_D7" && grep -q 'qualified, not absolute' "$BP_D7"; then
  ok "D7: both deployment notes carry the wrapped-command qualification"
else
  bad "D7: a deployment note lost its wrapped-command qualification"
fi

printf '\nPASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
