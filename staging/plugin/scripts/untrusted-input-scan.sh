#!/usr/bin/env bash
# untrusted-input-scan v1.0 (ADR-0059 / issue #113). Heuristic, shape-anchored detector for
# prompt-injection-shaped content in a GitHub issue title/body that is about to become an
# unattended agent's input (spec-from-issue, roadmap-from-issues.sh).
#
# A MITIGATION, NOT A BOUNDARY (ADR-0059 §D1). The mechanism reading this text — an LLM — is the
# same mechanism an attacker is trying to redirect, so nothing here "prevents" or "blocks"
# injection. It raises the cost of the naive attacks and routes anything shape-matched to the
# existing needs-human SKIP path (ADR-0059 §D3); it never invents a second enforcement mechanism.
# The real boundary is capability (ADR-0059 §D2: autopilot never merges, force-pushes, or
# writes main), not this script.
#
# Input: issue title+body text on stdin, in whatever order the caller concatenates them. This
# script does not parse issue structure; it scans lines.
#
# Output: "CLEAN" (no shape matched) or one or more, one per finding:
#   INJECTION<TAB><rule><TAB><line-number>
# ALWAYS exits 0 — this is a REPORTER, not a gate (mirrors weakening-scan.sh's contract,
# ADR-0047 §D3 / ADR-0051). The caller decides what a finding means and does the blocking.
#
# CALLER IDIOM (repeated here because getting it wrong reintroduces the exact bug earlier
# reporters' callers already hit — ADR-0046 §D2, ADR-0047 §D3):
#   out=$(bash untrusted-input-scan.sh <text); printf '%s\n' "$out" | grep -q '^INJECTION'
#   NEVER  [ -n "$out" ]         -- TRUE even on CLEAN output; would block every clean run.
#   NEVER  grep -c ... || echo 0 -- grep -c prints 0 AND exits 1 on no match, so the fallback
#                                    fires too and the result is the two-line string "0\n0".
#   || true is the fix, not || echo 0.
#
# Rules are anchored on SHAPE — an override phrase's grammar, a role-prefix line format, position
# inside a fenced code block, a URL adjacent to directive language — never on a bare keyword. A
# body that MENTIONS "prompt injection" in prose does not match any rule below; a body that
# PERFORMS one does. That is where the false-positive rate lives (ADR-0059, plan Task 2).
#
# Unconditional by design (ADR-0059 §D5): no public/private branch, no flag to disable this for a
# repo believed "trusted" — that belief is exactly what silently rots the day it stops being true.
#
# Bash 3.2 clean.
set -u

TMPD=$(mktemp -d) || { echo "CLEAN"; exit 0; }
trap 'rm -rf "$TMPD"' EXIT
IN="$TMPD/in.txt"
cat >"$IN"

FOUND="$TMPD/found"
: >"$FOUND"

# R1 — instruction-override phrasing. An override verb (ignore/disregard/forget/overrule/
# override/bypass) governing a reference to instructions/rules/prompt that came before this text
# — the grammatical shape of "ignore previous instructions", not the bare word "instructions".
grep -inE '(ignore|disregard|forget|overrule|override|bypass)([^.!?]{0,40})(previous|prior|above|earlier|all|your|these)([^.!?]{0,40})(instruction|rule|prompt|directive|guideline|constraint)' "$IN" \
  | awk -F: '{print "INJECTION\tinstruction-override\t" $1}' >>"$FOUND"

grep -inE '(new instructions|system prompt|you are now (a|an|the)?[[:space:]]*[a-z])[[:space:]]*:' "$IN" \
  | awk -F: '{print "INJECTION\tinstruction-override\t" $1}' >>"$FOUND"

# R2 — embedded role markers. A line whose shape is a chat-turn prefix (role name immediately
# followed by a colon at the start of the line, or a bracket/pipe role-delimiter token) — the
# same structural marker a real system prompt uses to separate turns.
grep -inE '^[[:space:]]*(system|assistant|user|human)[[:space:]]*:' "$IN" \
  | awk -F: '{print "INJECTION\trole-marker\t" $1}' >>"$FOUND"
grep -inE '(<\|(system|assistant|user)\|>|\[(SYSTEM|ASSISTANT|USER|INST)\])' "$IN" \
  | awk -F: '{print "INJECTION\trole-marker\t" $1}' >>"$FOUND"

# R3 — a fenced code block whose content takes the shape of a role marker or an identity-
# reassignment directive ("you are now the system", "act as", "pretend you are"). Fencing alone
# is not a signal — an ordinary code block is exactly that; a role-shaped line INSIDE a fence is.
awk '
  /^```/ { infence = !infence; next }
  infence {
    l = tolower($0)
    if (l ~ /^[[:space:]]*(system|assistant|user|human)[[:space:]]*:/ ||
        l ~ /(you are (now|the)|act as|pretend (to be|you are))/) {
      print "INJECTION\tfenced-system-block\t" NR
    }
  }
' "$IN" >>"$FOUND"

# R4 — a URL sitting next to directive language on the same line: not a bare link (bare links are
# ordinary issue content) but one paired with "follow the instructions", "fetch and run/execute",
# or "the instructions are here/at/there" phrasing.
grep -inE 'https?://[^ )>"'"'"']+' "$IN" \
  | grep -iE '(follow[^.!?]{0,25}instructions?|fetch[^.!?]{0,25}(run|execute)|instructions?[^.!?]{0,25}(here|at this|over there|below)|execute[^.!?]{0,25}(script|code|steps)|download[^.!?]{0,25}(and run|it and run))' \
  | awk -F: '{print "INJECTION\tinstruction-bearing-url\t" $1}' >>"$FOUND"

if [ -s "$FOUND" ]; then
  sort -u "$FOUND"
else
  echo "CLEAN"
fi
exit 0
