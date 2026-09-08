#!/bin/bash
# session-state.test.sh — offline, hermetic, no network. Bash 3.2 clean. Run: bash session-state.test.sh
#
# Covers ADR-0197: session-state/SKILL.md is the single producer of .claude/context.md, invoked
# from commit/SKILL.md Step 5.5 (automatic) and standalone (manual). Satisfies
# skill-coverage-perimeter.test.sh's S1 by NAME, not by corpus glob (rule 1 — a needle whose
# reach is a directory glob does not prove the file was read for what it claims).
#
# WHAT THIS FILE DOES NOT DO. It does not execute the skill (SKILL.md is prose read by a model,
# not a script) and does not re-litigate that Step 5.5's old inline template moved here — that is
# ADR-0197's own record. What it pins is the CONTRACT: the fields ADR-0197 D2 requires exist, the
# omission rule for Notes is stated (not just the field name), the boundary against Open decisions
# is stated (not left implicit, which is exactly how the drift into Next happened before), and the
# two call sites (commit Step 5.5, project-init's seed) actually name this skill rather than
# re-declaring their own copy of the template (rule 6).

set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)                    # staging/plugin/scripts
STAGING=$(cd "$SCRIPTS/../.." && pwd)                         # staging/
SKILL="$STAGING/plugin/skills/session-state/SKILL.md"
COMMITMD="$STAGING/plugin/skills/commit/SKILL.md"
PROJINITMD="$STAGING/plugin/skills/project-init/SKILL.md"
SYNC="$STAGING/sync-to-claude.sh"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# ==================================================================================================
# SS0. The file exists and parses as a skill (frontmatter present, name matches directory).
# ==================================================================================================
if [ -f "$SKILL" ]; then
  ok "SS0: session-state/SKILL.md exists at the expected staged path"
else
  bad "SS0: session-state/SKILL.md not found at $SKILL"
fi

if grep -qE '^name: session-state$' "$SKILL" 2>/dev/null; then
  ok "SS0b: frontmatter name: matches the directory name"
else
  bad "SS0b: frontmatter name: does not read 'session-state'"
fi

# ==================================================================================================
# SS1. The field set ADR-0197 D2 requires is present in the template.
# ==================================================================================================
for _field in '\*\*Branch:\*\*' '\*\*Last commit:\*\*' '\*\*In progress:\*\*' '\*\*Next:\*\*' \
              '\*\*Open decisions:\*\*' '\*\*Notes:\*\*'; do
  if grep -qE "$_field" "$SKILL" 2>/dev/null; then
    ok "SS1: template carries the $_field field"
  else
    bad "SS1: template is missing the $_field field"
  fi
done

# ==================================================================================================
# SS2. The Notes omission rule is stated, not just the field name (ADR-0197 D2's actual point —
# a field that is always present and blank teaches readers to skip it).
# ==================================================================================================
if grep -qi 'omitted entirely' "$SKILL" 2>/dev/null; then
  ok "SS2: the Notes-omission rule is stated in prose, not just implied by the field existing"
else
  bad "SS2: no omission rule found — Notes could regress to an always-blank field"
fi

# ==================================================================================================
# SS3. The boundary against Open decisions is stated. Without this rule the two fields compete
# for the same content, which is what produced the pre-ADR-0197 "Known deferred risk" living
# inside Next instead of anywhere it belonged.
# ==================================================================================================
if tr '\n' ' ' <"$SKILL" 2>/dev/null | tr -s ' ' | grep -qi 'compete for the same content'; then
  ok "SS3: the Open-decisions/Notes boundary is stated explicitly"
else
  bad "SS3: no explicit boundary between Open decisions and Notes"
fi

# ==================================================================================================
# SS4. The rule-16 disclosure — this is an instruction, not an enforcement — is present. Every
# prose-only skill in this repo that asks a model to follow a rule says so (rule 16).
# ==================================================================================================
if grep -qi 'instruction, not an enforcement' "$SKILL" 2>/dev/null; then
  ok "SS4: the skill discloses its own rule-16 status (no code path checks Notes gets filled)"
else
  bad "SS4: missing rule-16 disclosure"
fi

# ==================================================================================================
# SS5. commit/SKILL.md Step 5.5 invokes this skill by name, rather than carrying its own inline
# copy of the template (ADR-0197 D1 — the reason a skill was extracted at all, rule 6).
# ==================================================================================================
if grep -A5 '^### Step 5.5' "$COMMITMD" 2>/dev/null | grep -qi 'session-state'; then
  ok "SS5: commit/SKILL.md Step 5.5 names session-state instead of re-declaring the template"
else
  bad "SS5: commit/SKILL.md Step 5.5 does not name session-state"
fi

# SS5b — the inline template is actually gone from Step 5.5, not just supplemented. Two live
# copies of the same template is the exact drift ADR-0197 exists to close (project-init's own
# pre-fix history is the example).
if grep -A20 '^### Step 5.5' "$COMMITMD" 2>/dev/null | grep -q '\*\*Open decisions:\*\*'; then
  bad "SS5b: commit/SKILL.md Step 5.5 still carries its own inline Open decisions field"
else
  ok "SS5b: commit/SKILL.md Step 5.5 carries no surviving inline copy of the template"
fi

# ==================================================================================================
# SS6. project-init's seed explicitly names session-state as the owner of the full template,
# rather than leaving the divergence between the two templates undocumented.
# ==================================================================================================
if grep -qi 'session-state' "$PROJINITMD" 2>/dev/null; then
  ok "SS6: project-init/SKILL.md names session-state as the full-template owner"
else
  bad "SS6: project-init/SKILL.md does not reference session-state"
fi

# ==================================================================================================
# SS7. The deploy pairing exists — a skill with no PAIRS entry never reaches ~/.claude, and every
# claim above about "this is what ships" would be describing a file nobody deploys.
# ==================================================================================================
if grep -qF 'plugin/skills/session-state/SKILL.md|skills/session-state/SKILL.md' "$SYNC" 2>/dev/null; then
  ok "SS7: sync-to-claude.sh PAIRS deploys session-state/SKILL.md"
else
  bad "SS7: no PAIRS entry deploys session-state/SKILL.md"
fi

# ==================================================================================================
# Z1. Assertion-count floor — a derivation that silently stopped matching would otherwise pass
# vacuously at zero.
# ==================================================================================================
TOTAL=$((PASS+FAIL))
if [ "$TOTAL" -ge 12 ]; then
  ok "Z1: assertion floor met ($TOTAL executed, floor 12)"
else
  bad "Z1: only $TOTAL assertions executed (floor 12) — this harness ran short"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
