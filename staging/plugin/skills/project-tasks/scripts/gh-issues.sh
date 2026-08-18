#!/usr/bin/env bash
# gh-issues.sh — read the open GitHub issues and report them as evidence.
#
# gh-issues.sh is a CHECKER. The caller branches on the exit code. It is NOT a
# reporter: it does not always exit 0 and it does not print CLEAN. scan.sh, the
# other evidence collector in this skill, is a reporter — do not copy one's call
# idiom into the other (ADR-0047, ADR-0048).
#
#   0  the read succeeded; ISSUE records on stdout, possibly zero, legitimately
#   2  bad invocation
#   3  could not evaluate — DIDNOTRUN record on stdout naming a cause and a remedy
#   4  broken derivation — zero issues where the ledger's section already held entries
#
# Usage: bash gh-issues.sh [--ledger FILE] [--issues-json FILE] [--repo OWNER/NAME]
#
# Records (TSV):
#   ISSUE     number  state  title  labels
#   DIDNOTRUN cause   remedy
#
# WRITES NOTHING, EVER. --ledger is READ, to supply the denominator the exit-4
# guard needs; it is never opened for writing. ledger-merge.sh is the only
# component of this skill that composes a new ledger, and even that one prints
# to stdout rather than editing in place.
#
# The live path and the --issues-json path share ONE parser. Two parsers would
# be two answers to one question, which is the defect ADR-0086's criterion names:
# a fixture that parses differently from the live payload makes every offline
# assertion in the harness evidence about nothing.
#
# Bash 3.2 clean: no [[ ]], no arrays, no mapfile, no ${var^^}.
set -u

LEDGER=""
ISSUES_JSON=""
REPO=""

die_usage() {
  echo "gh-issues.sh: $1" >&2
  echo "usage: bash gh-issues.sh [--ledger FILE] [--issues-json FILE] [--repo OWNER/NAME]" >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --ledger)       [ $# -ge 2 ] || die_usage "--ledger needs a value";       LEDGER="$2";      shift 2 ;;
    --issues-json)  [ $# -ge 2 ] || die_usage "--issues-json needs a value";  ISSUES_JSON="$2"; shift 2 ;;
    --repo)         [ $# -ge 2 ] || die_usage "--repo needs a value";         REPO="$2";        shift 2 ;;
    -h|--help)      sed -n '2,20p' "$0"; exit 0 ;;
    *)              die_usage "unknown argument: $1" ;;
  esac
done

didnotrun() {
  printf 'DIDNOTRUN\t%s\t%s\n' "$1" "$2"
  exit 3
}

# --- the payload -------------------------------------------------------------
# Either from a file (offline, and the only path the harness uses) or from gh.
# The gh path is probed in three steps because the three failures are three
# different situations for the operator, and a single "gh failed" would make
# them indistinguishable (rule 4 applied to causes, not just to states).
if [ -n "$ISSUES_JSON" ]; then
  [ -f "$ISSUES_JSON" ] || die_usage "--issues-json file does not exist: $ISSUES_JSON"
  PAYLOAD=$(cat "$ISSUES_JSON")
else
  command -v gh >/dev/null 2>&1 || didnotrun "gh-absent" \
    "install the GitHub CLI (brew install gh), or pass --issues-json FILE with a saved payload"
  gh auth status >/dev/null 2>&1 || didnotrun "gh-unauthenticated" \
    "run: gh auth login"
  if [ -n "$REPO" ]; then
    gh repo view "$REPO" --json nameWithOwner >/dev/null 2>&1 || didnotrun "no-remote" \
      "the repository $REPO is not reachable — check the name, or run from a checkout with a GitHub remote"
  else
    gh repo view --json nameWithOwner >/dev/null 2>&1 || didnotrun "no-remote" \
      "this directory has no GitHub remote — run: git remote add origin <url>, or pass --repo OWNER/NAME"
  fi
  if [ -n "$REPO" ]; then
    PAYLOAD=$(gh issue list --repo "$REPO" --state open --limit 300 --json number,title,state,labels 2>/dev/null) \
      || didnotrun "gh-issue-list-failed" "re-run: gh issue list --repo $REPO --state open --limit 300"
  else
    PAYLOAD=$(gh issue list --state open --limit 300 --json number,title,state,labels 2>/dev/null) \
      || didnotrun "gh-issue-list-failed" "re-run: gh issue list --state open --limit 300"
  fi
fi

# --- the parser --------------------------------------------------------------
# A character walk rather than a line regex: gh emits the whole array on one line
# when its output is piped, and a title may contain a brace, a comma or an
# escaped quote. Depth and string state are tracked so a top-level object is
# split correctly whatever its payload says.
RECORDS=$(printf '%s' "$PAYLOAD" | awk '
function jstr(s, i,   out, c) {
  out = ""
  i++                                    # step over the opening quote
  while (i <= length(s)) {
    c = substr(s, i, 1)
    if (c == "\\") { i++; c = substr(s, i, 1)
                     if (c == "n" || c == "t" || c == "r") c = " "
                     out = out c; i++; continue }
    if (c == "\"") break
    out = out c; i++
  }
  return out
}
function field(obj, key,   p) {
  p = index(obj, "\"" key "\":")
  if (p == 0) return ""
  p += length(key) + 3
  while (substr(obj, p, 1) == " ") p++
  if (substr(obj, p, 1) == "\"") return jstr(obj, p)
  return substr(obj, p, index(substr(obj, p) ",", ",") - 1)
}
function labels(obj,   p, q, seg, out, r) {
  p = index(obj, "\"labels\":")
  if (p == 0) return ""
  p = index(substr(obj, p), "[") + p - 1
  q = p; r = 0
  while (q <= length(obj)) {
    if (substr(obj, q, 1) == "[") r++
    else if (substr(obj, q, 1) == "]") { r--; if (r == 0) break }
    q++
  }
  seg = substr(obj, p, q - p + 1)
  out = ""
  while ((p = index(seg, "\"name\":")) > 0) {
    seg = substr(seg, p + 7)
    while (substr(seg, 1, 1) == " ") seg = substr(seg, 2)
    out = out (out == "" ? "" : ",") jstr(seg, 1)
  }
  return out
}
{ all = all $0 }
END {
  depth = 0; instr = 0; esc = 0; buf = ""
  for (i = 1; i <= length(all); i++) {
    c = substr(all, i, 1)
    if (instr) {
      if (esc)            { esc = 0 }
      else if (c == "\\") { esc = 1 }
      else if (c == "\"") { instr = 0 }
    } else if (c == "\"") { instr = 1 }
    else if (c == "{")    { depth++; if (depth == 1) { buf = ""; } }
    else if (c == "}")    { depth--
                            if (depth == 0) {
                              n = field(buf, "number"); gsub(/[^0-9]/, "", n)
                              t = field(buf, "title");  gsub(/[\t\n]/, " ", t)
                              s = field(buf, "state")
                              printf "ISSUE\t%s\t%s\t%s\t%s\n", n, s, t, labels(buf)
                              buf = ""
                              continue
                            } }
    if (depth >= 1) buf = buf c
  }
}')

# --- duplicate detection -----------------------------------------------------
# R-04 says each issue appears exactly once. A silent dedup would satisfy that
# sentence and hide that the input contradicted itself, so a repeat is a
# detectable failure and not a set operation.
DUPES=$(printf '%s\n' "$RECORDS" | awk -F'\t' '/^ISSUE/{print $2}' | sort | uniq -d)
if [ -n "$DUPES" ]; then
  echo "gh-issues.sh: issue number appears more than once in the payload: $(printf '%s' "$DUPES" | tr '\n' ' ')" >&2
  exit 3
fi

COUNT=$(printf '%s\n' "$RECORDS" | grep -c '^ISSUE')
[ -n "$COUNT" ] || COUNT=0

# --- the denominator guard ---------------------------------------------------
# Zero matches can be correct; zero candidates where there were candidates is a
# broken derivation, and from the rendered section the two look identical
# (rule 7). The previous section is the denominator: with entries in it, zero
# issues now is a contradiction, and with none, zero is simply zero.
if [ "$COUNT" -eq 0 ] && [ -n "$LEDGER" ] && [ -f "$LEDGER" ]; then
  PREV=$(awk '/^## GitHub Issues/{f=1; next} /^## /{f=0} f' "$LEDGER" \
         | grep -oE '#[0-9]+' | sort -u | wc -l | tr -d ' ')
  [ -n "$PREV" ] || PREV=0
  if [ "$PREV" -gt 0 ]; then
    printf 'DIDNOTRUN\t%s\t%s\n' "zero-issues-against-$PREV-existing" \
      "the read returned no open issues while the ledger's GitHub Issues section holds $PREV — verify with: gh issue list --state open --limit 300, and re-run once it agrees"
    exit 4
  fi
fi

printf '%s' "$RECORDS" | grep '^ISSUE' || true
exit 0
