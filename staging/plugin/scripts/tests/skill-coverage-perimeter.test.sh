#!/bin/bash
# skill-coverage-perimeter.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash skill-coverage-perimeter.test.sh
#
# Covers issue #211 (ADR-0084): the CLASS-level guard for skill test coverage.
#
# THE RULE
#   Every staged skill is either read by a test that NAMES it, or declares in its own SKILL.md why
#   it is deliberately uncovered:
#       <!-- skill-coverage-exempt: <reason, >= 40 chars> -->
#   One line, within three lines of the frontmatter close. The marker is also the extraction anchor.
#
# WHY. Ten of twenty-nine skills had no test naming them, and nothing distinguished "audited and
# deliberately uncovered" from "never looked at". Several of the ten are prompt templates whose whole
# content is instructions to a model; inventing an assertion to raise a number would be worse than
# the gap. What was missing is not coverage, it is the DECISION being recorded where the next reader
# meets it — ADR-0077 §D3's pattern, where the waiver travels with the file rather than sitting in a
# list inside a test.
#
# WHY THE PREDICATE IS A LITERAL NAME, AND NOT "A TEST OPENS THIS FILE".
# #211 said the ten were "read by no test at all". That is FALSE, and the correction is what shapes
# this file. THREE derived sweeps already read every (or nearly every) SKILL.md:
#   - worktree-isolation-contract.test.sh   — skills/*/SKILL.md + agents/*.md, `isolation:` values
#   - agent-tool-parameter-names.test.sh    — same corpus, Agent/Skill/EnterPlanMode call notation
#   - skill-text-corrections.test.sh F6     — names derived from concept-to-code §25, the flag
# Under a predicate of "some test opens this file", all twenty-nine would pass, the count guard would
# stay green, and the perimeter would be exactly as unmeasured as before — the ADR-0043 direction
# lesson one level up. A corpus sweep reaches a file through a glob or a variable and CANNOT produce
# the literal string `<name>/SKILL.md`; a test written for one skill must. S6 pins that distinction
# in the failing direction, because it is the whole reason this check is not vacuous.
#
# DIRECTION (rule 5). The population is every staged skill, and narrowing happens only through a
# DECLARED exemption in the skill itself. A new skill is in the population by default and must say
# something. S7 runs it backwards: a declaration on a skill that IS covered is a stale waiver, and a
# stale waiver reading as a clean bill of health is the failure ADR-0081 ZA4 exists to catch.
#
# DERIVED-GUARD PATTERN — instance 4 of 6 (ADR-0086). Derives: directories, verified against another tree. Waiver: `<!-- skill-coverage-exempt: <reason> -->`, position-constrained.
# The pattern is deliberately COPIED across the six, not shared. Before writing a seventh by
# copying this file, read ADR-0086 §D1: extract only when two copies giving different answers
# would be a DEFECT. Here they would not — the six ask six questions about six populations.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)                    # staging/plugin/scripts
STAGING=$(cd "$SCRIPTS/../.." && pwd)                        # staging/
TESTS="$SCRIPTS/tests"
SKILLS="$STAGING/plugin/skills"
C2C="$SKILLS/concept-to-code/SKILL.md"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# The exemption marker, built at run time so this file does not match its own search (rule 12 —
# a scan whose needle is a literal counts itself).
MARK="skill-coverage""-exempt"

# --- the two predicates, in one place, used by the sweep and by both self-tests ----------------

# covered_by <tests-dir> <skill-name> -> some file in <tests-dir> names <skill-name>/SKILL.md
covered_by() {
  grep -rlF -- "$2/SKILL.md" "$1" >/dev/null 2>&1
}

# marker_line <skill.md> -> the 1-based line number of the exemption marker, empty if absent
marker_line() {
  grep -n -- "$MARK:" "$1" 2>/dev/null | head -1 | cut -d: -f1
}

# marker_reason <skill.md> -> the reason text, trimmed, empty if the marker is absent or unclosed
marker_reason() {
  grep -- "$MARK:" "$1" 2>/dev/null | head -1 \
    | sed -e "s/^.*$MARK:[[:space:]]*//" -e 's/[[:space:]]*-->.*$//' \
          -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

# frontmatter_close <skill.md> -> line number of the closing --- , empty if it does not parse
frontmatter_close() {
  awk 'NR>1 && $0=="---"{print NR; exit}' "$1" 2>/dev/null
}

# ==============================================================================================
# S. The sweep. Every staged skill is covered by name or declares why not.
# ==============================================================================================
POP=""
for _d in "$SKILLS"/*/; do
  [ -f "$_d/SKILL.md" ] || continue
  POP="$POP $(basename "$_d")"
done
N=0
for _s in $POP; do N=$((N+1)); done

# S0: the count guard. A derivation that matches nothing reports nothing, and a silent zero reads
# exactly like full coverage.
if [ "$N" -ge 25 ]; then
  ok "S0: the derivation found $N staged skills (count guard: >= 25)"
else
  bad "S0: derivation found only $N skills — every assertion below would pass vacuously"
fi

UNCOVERED=""
DECLARED=""
for _s in $POP; do
  if covered_by "$TESTS" "$_s"; then continue; fi
  if [ -n "$(marker_line "$SKILLS/$_s/SKILL.md")" ]; then
    DECLARED="$DECLARED $_s"
    continue
  fi
  UNCOVERED="$UNCOVERED $_s"
done

if [ -z "$UNCOVERED" ]; then
  ok "S1: every staged skill is either named by a test or declares why it is uncovered"
else
  bad "S1: skill(s) neither covered nor declared:$UNCOVERED"
fi

# S2: the waiver population's own count guard. With zero declarations S3/S4/S5/S7 all pass
# vacuously, and a green suite would say nothing about the mechanism.
_dn=0
for _s in $DECLARED; do _dn=$((_dn+1)); done
if [ "$_dn" -ge 1 ]; then
  ok "S2: $_dn skill(s) carry a declared exemption — S3/S4/S5/S7 are not vacuous"
else
  bad "S2: no skill declares an exemption — the marker assertions below assert nothing"
fi

# S3: a reason has to be a reason. 40 chars is the same floor ADR-0077 T4 uses.
_short=""
for _s in $DECLARED; do
  _r=$(marker_reason "$SKILLS/$_s/SKILL.md")
  [ "${#_r}" -ge 40 ] || _short="$_short $_s(${#_r})"
done
if [ -z "$_short" ]; then
  ok "S3: every declared exemption carries a reason of at least 40 characters"
else
  bad "S3: exemption reason too short (chars in parens):$_short"
fi

# S4: one line, and one only. A reason wrapped across lines is a prose assertion that depends on
# where the text breaks — the fourth recurrence of that lesson (ADR-0073/0076/0080/0082), so it is
# forbidden at the moment it is written rather than tolerated and grepped around.
_badform=""
for _s in $DECLARED; do
  _f="$SKILLS/$_s/SKILL.md"
  _n=$(grep -c -- "$MARK:" "$_f" 2>/dev/null)
  case "$_n" in ''|*[!0-9]*) _n=0 ;; esac
  _l=$(marker_line "$_f")
  _txt=$(sed -n "${_l}p" "$_f")
  if [ "$_n" -ne 1 ]; then
    _badform="$_badform $_s(x$_n)"
  else
    case "$_txt" in *'-->') : ;; *) _badform="$_badform $_s(unclosed)" ;; esac
  fi
done
if [ -z "$_badform" ]; then
  ok "S4: every exemption marker appears exactly once and closes on its own line"
else
  bad "S4: malformed exemption marker(s):$_badform"
fi

# S5: deterministic position — within three lines of the frontmatter close, so the marker can never
# drift inside a fenced block where a parser would have to guess.
_pos=""
for _s in $DECLARED; do
  _f="$SKILLS/$_s/SKILL.md"
  _c=$(frontmatter_close "$_f")
  _l=$(marker_line "$_f")
  if [ -z "$_c" ]; then _pos="$_pos $_s(no-frontmatter)"; continue; fi
  if [ "$_l" -le "$_c" ] || [ "$_l" -gt $((_c + 3)) ]; then
    _pos="$_pos $_s(line $_l, frontmatter closes $_c)"
  fi
done
if [ -z "$_pos" ]; then
  ok "S5: every exemption marker sits within three lines of the frontmatter close"
else
  bad "S5: exemption marker out of position:$_pos"
fi

# S6: FORWARD self-test. A corpus sweep must not count as coverage. This is the assertion that
# stops the whole check from being satisfied by the three existing glob/derived sweeps — replace
# covered_by() with "some test opens this file" and this is what goes red.
mkdir -p "$TMP/faketests"
cat > "$TMP/faketests/sweep.test.sh" <<'FAKE'
# A corpus sweep of the shape that already exists three times in the real harness.
for f in "$STAGING"/plugin/skills/*/SKILL.md "$STAGING"/plugin/agents/*.md; do
  [ -f "$f" ] && grep -q 'something' "$f"
done
FAKE
_leak=""
for _s in $POP; do
  covered_by "$TMP/faketests" "$_s" && _leak="$_leak $_s"
done
if [ -z "$_leak" ]; then
  ok "S6: a glob-style corpus sweep counts as coverage for zero skills — the predicate discriminates"
else
  bad "S6: a corpus sweep was counted as skill-specific coverage for:$_leak"
fi

# S7: BACKWARD self-test. A declaration on a skill that IS covered is a stale waiver, and a stale
# waiver is invisible precisely because everything around it stays green (ADR-0081 ZA4).
_stale=""
for _s in $POP; do
  if covered_by "$TESTS" "$_s" && [ -n "$(marker_line "$SKILLS/$_s/SKILL.md")" ]; then
    _stale="$_stale $_s"
  fi
done
if [ -z "$_stale" ]; then
  ok "S7: no skill carries an exemption while also being covered by name"
else
  bad "S7: stale exemption(s) on covered skill(s):$_stale"
fi

# ==============================================================================================
# C. The skills this file covers. Each was in #211's list of ten and was judged an oversight
# rather than a deliberate gap — the assertion is what makes that judgement checkable.
# ==============================================================================================

# C1/C2 — humanize-en. ADR-0040 moved the perimeter INTO the description frontmatter, on the
# argument that "that field is what the model reads when deciding to invoke, so it matters as much
# as the global rule". Nothing asserted the field's content, which made the load-bearing half of
# that ADR the unverified half.
HUMANIZE="$SKILLS/humanize-en/SKILL.md"
_hc=$(frontmatter_close "$HUMANIZE")
_hf=$(sed -n "2,${_hc}p" "$HUMANIZE" 2>/dev/null)
if printf '%s' "$_hf" | grep -q 'NEGATIVE:'; then
  ok "C1: humanize-en's description carries the NEGATIVE: block (ADR-0040 perimeter)"
else
  bad "C1: humanize-en's description lost the NEGATIVE: block — the ADR-0040 perimeter is gone"
fi
_missing=""
for _t in Reddit forum blog newsletter announcement marketing; do
  printf '%s' "$_hf" | grep -qi -- "$_t" || _missing="$_missing $_t"
done
for _t in "source code" "commit messages" ADRs README changelogs; do
  printf '%s' "$_hf" | grep -qi -- "$_t" || _missing="$_missing ${_t// /-}"
done
if [ -z "$_missing" ]; then
  ok "C2: humanize-en's description names both sides of the perimeter (outside audience / internal)"
else
  bad "C2: humanize-en's description no longer names:$_missing"
fi

# C3/C4 — refactor-snapshot and vibe-status. Both have a sibling test that reads their scripts/ and
# not their SKILL.md: partial coverage that reads as full from the test filename. Every scripts/
# path the skill text tells an operator to run must exist. `tests/run-tests.sh` is deliberately
# outside the pattern — it is the skill's own self-test, not a scripts/ entry point.
check_named_scripts() {
  _skill="$1"
  _f="$SKILLS/$_skill/SKILL.md"
  _miss=""
  for _p in $(grep -oE 'scripts/[A-Za-z0-9_-]+\.sh' "$_f" 2>/dev/null | sort -u); do
    [ -f "$SKILLS/$_skill/${_p#scripts/}" ] || [ -f "$SKILLS/$_skill/$_p" ] || _miss="$_miss $_p"
  done
  _cnt=$(grep -oE 'scripts/[A-Za-z0-9_-]+\.sh' "$_f" 2>/dev/null | sort -u | wc -l | tr -d ' ')
  printf '%s\t%s\n' "$_cnt" "$_miss"
}

_r=$(check_named_scripts refactor-snapshot); _rc=$(printf '%s' "$_r" | cut -f1); _rm=$(printf '%s' "$_r" | cut -f2)
if [ "$_rc" -ge 3 ] && [ -z "$_rm" ]; then
  ok "C3: every scripts/ path refactor-snapshot/SKILL.md tells the operator to run exists ($_rc paths)"
else
  bad "C3: refactor-snapshot/SKILL.md names $_rc scripts/ paths, missing on disk:${_rm:- (none, but the count guard failed)}"
fi

_v=$(check_named_scripts vibe-status); _vc=$(printf '%s' "$_v" | cut -f1); _vm=$(printf '%s' "$_v" | cut -f2)
if [ "$_vc" -ge 2 ] && [ -z "$_vm" ]; then
  ok "C4: every scripts/ path vibe-status/SKILL.md tells the operator to run exists ($_vc paths)"
else
  bad "C4: vibe-status/SKILL.md names $_vc scripts/ paths, missing on disk:${_vm:- (none, but the count guard failed)}"
fi

# C5/C6 — design-brainstorm and macos-ux. concept-to-code §25 declares each chain-invokable under a
# GATE CONDITION, and nothing checked that the skill's own text agrees. That is the ADR-0042 shape:
# a file whose prose and its caller's contract disagree, with no way to tell which is authoritative.
INVOKABLE_LINE=$(grep -n 'skills invokable inside this chain' "$C2C" | head -1 | cut -d: -f1)
if [ -n "$INVOKABLE_LINE" ]; then
  _inv=$(sed -n "${INVOKABLE_LINE}p" "$C2C")
else
  _inv=""
  bad "C5/C6 precondition: concept-to-code no longer carries the chain-invokable line at all"
fi

check_gate_contract() {
  _skill="$1"; _gate="$2"
  _f="$SKILLS/$_skill/SKILL.md"
  printf '%s' "$_inv" | grep -qF -- "\`$_skill\` ($_gate only" || { echo "c2c-side"; return; }
  grep -qiF -- "$_gate" "$_f" 2>/dev/null || { echo "skill-side"; return; }
  echo ""
}

if [ -n "$_inv" ]; then
  _g=$(check_gate_contract design-brainstorm "gate 1b")
  case "$_g" in
    "")          ok "C5: c2c §25 restricts design-brainstorm to gate 1b and the skill's own text says so" ;;
    c2c-side)    bad "C5: c2c §25 no longer restricts design-brainstorm to gate 1b — the contract moved" ;;
    skill-side)  bad "C5: design-brainstorm/SKILL.md no longer names gate 1b, which c2c §25 restricts it to" ;;
  esac
  _g=$(check_gate_contract macos-ux "gate 1c")
  case "$_g" in
    "")          ok "C6: c2c §25 restricts macos-ux to gate 1c and the skill's own text says so" ;;
    c2c-side)    bad "C6: c2c §25 no longer restricts macos-ux to gate 1c — the contract moved" ;;
    skill-side)  bad "C6: macos-ux/SKILL.md no longer names gate 1c, which c2c §25 restricts it to" ;;
  esac
fi

# ==============================================================================================
# Z. Assertion floor (ADR-0083). A suite reporting FEWER assertions does not read as broken, and
# nobody watches the count. A floor catches a vanished assertion without a bump on every addition.
# ==============================================================================================
TOTAL=$((PASS + FAIL))
if [ "$TOTAL" -ge 14 ]; then
  ok "Z1: assertion floor met ($TOTAL executed, floor 14)"
else
  bad "Z1: only $TOTAL assertions executed — the floor is 14, so something stopped running"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
