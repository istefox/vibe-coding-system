#!/bin/bash
# harness-helper-scope.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash harness-helper-scope.test.sh
#
# Issue #310 / ADR-0146. ADR-0081 found it on the way to something else: `pairs-completeness.test.sh`
# had no `ok()`/`bad()` helpers, a draft called them anyway, and **six assertions printed "command
# not found" while the suite reported `PASS=244 FAIL=0` and exited 0**. Nothing here runs under
# `set -e`, so a call to a helper the file does not define is indistinguishable from an assertion
# that passed. It is the false-green class inside the files where every other assertion lives.
#
# MEASURED BEFORE BUILDING THIS, 2026-08-16 across all 82 harnesses: **zero** such calls. ADR-0081's
# instance was repaired and no new one exists. So this guard ships against a population of zero,
# which is exactly the case where a guard is worth having and worth being honest about: it cannot
# claim to have found anything, and its whole value is the next draft.
#
# THE VOCABULARY IS DERIVED, NEVER LISTED. A helper is any function defined by **two or more**
# harnesses — that is what makes it a convention a draft would copy in rather than one file's
# private function. A hand-written list would be blind to precisely the file that invents a new
# helper name, which is rule 8: a check over a list cannot see what the list omits.
#
# WHAT COUNTS AS A CALL, and why the position work is the whole difficulty. The first version of
# this scan matched the English word "no" inside message strings — `no` IS a helper here, defined by
# phase1.test.sh — and reported 47 findings, none real. A name counts only in COMMAND POSITION:
# outside single and double quotes (which wrap across lines in this corpus), outside heredoc bodies,
# not a `name=` assignment, and not a `name)` case label. Both of those last two sit in command
# position and neither is a call.
#
# --- plants (plant-check.sh) ------------------------------------------------------------
# Each line below removes ONE mechanism and names the assertion that must go RED for it.
# An assertion whose plant does not fire pins nothing. Format and rationale: plant-check.sh.
# plant: HS1 | plugin/scripts/tests/spec-archive.test.sh | set -u | set -u; verdict "a call planted by the registry"
# plant: HS2 | plugin/scripts/tests/harness-helper-scope.test.sh | helpers = {n for n, c in vocab.items() if c >= 2} | helpers = set()
set -u

TESTS=$(cd "$(dirname "$0")" && pwd)

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# The scanner, as a file so the self-test below can run the SAME code against a planted fixture
# rather than a lookalike. It prints one `<file>:<line>:<helper>` per finding and a count on the
# last line, so a caller can tell "found nothing" from "did not run" (rule 4).
cat >"$TMP/scan.py" <<'SCANEOF'
import re, sys, glob, os, collections

TESTS = sys.argv[1]
files = sorted(glob.glob(os.path.join(TESTS, "*.test.sh")))
DEF = re.compile(r'^\s*(?:function\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*\(\)\s*\{')

defined = {}
for f in files:
    defined[f] = set()
    for line in open(f, errors="replace").read().split("\n"):
        m = DEF.match(line)
        if m:
            defined[f].add(m.group(1))

vocab = collections.Counter()
for names in defined.values():
    for n in names:
        vocab[n] += 1
helpers = {n for n, c in vocab.items() if c >= 2}

if not files or not helpers:
    print("FILES 0")
    print("HELPERS 0")
    print("COUNT -1")            # -1 is "did not run", never "found nothing"
    raise SystemExit


def mask_heredocs(src):
    spans = []
    for m in re.finditer(r"<<-?\s*'?\"?([A-Za-z_][A-Za-z0-9_]*)'?\"?\s*\n", src):
        end = src.find("\n" + m.group(1) + "\n", m.end() - 1)
        if end != -1:
            spans.append((m.end(), end + 1))
    chars = list(src)
    for a, b in spans:
        for k in range(a, min(b, len(chars))):
            if chars[k] != "\n":
                chars[k] = " "
    return "".join(chars)


def command_positions(src):
    i, n, line = 0, len(src), 1
    sq = dq = False
    cmd_next = True
    while i < n:
        c = src[i]
        if c == "\n":
            line += 1
            if not sq and not dq:
                cmd_next = True
            i += 1
            continue
        if sq:
            if c == "'":
                sq = False
            i += 1
            continue
        if dq:
            if c == "\\":
                i += 2
                continue
            if c == '"':
                dq = False
            i += 1
            continue
        if c == "'":
            sq = True; cmd_next = False; i += 1; continue
        if c == '"':
            dq = True; cmd_next = False; i += 1; continue
        if c == "#" and cmd_next:
            j = src.find("\n", i)
            i = n if j == -1 else j
            continue
        if c in ";&|(":
            cmd_next = True; i += 1; continue
        if c in " \t":
            i += 1; continue
        if cmd_next:
            yield i, line
            cmd_next = False
        i += 1


count = 0
for f in files:
    src = mask_heredocs(open(f, errors="replace").read())
    for off, line in command_positions(src):
        m = re.match(r'([A-Za-z_][A-Za-z0-9_]*)', src[off:off + 64])
        if not m:
            continue
        name = m.group(1)
        if src[off + len(name): off + len(name) + 1] in ("=", ")"):
            continue                      # an assignment or a case label, not a call
        if name in helpers and name not in defined[f]:
            print(f"{os.path.basename(f)}:{line}:{name}")
            count += 1
print(f"FILES {len(files)}")
print(f"HELPERS {len(helpers)}")
print(f"COUNT {count}")
SCANEOF

_out=$(python3 "$TMP/scan.py" "$TESTS" 2>/dev/null)
_files=$(printf '%s\n' "$_out" | sed -n 's/^FILES //p')
_helpers=$(printf '%s\n' "$_out" | sed -n 's/^HELPERS //p')
_count=$(printf '%s\n' "$_out" | sed -n 's/^COUNT //p')

# ==================================================================================================
# HS0 — the denominator (rule 7). A glob that stops resolving, or a vocabulary derivation that
# collapses, discovers nothing and reads exactly like a corpus with no undefined calls in it.
# ==================================================================================================
case "${_files:-x}${_helpers:-x}${_count:-x}" in
  *x*) bad "HS0: the scan did not run — files=[${_files:-}] helpers=[${_helpers:-}] count=[${_count:-}]" ;;
  *)
    if [ "$_files" -ge 40 ] && [ "$_helpers" -ge 5 ] && [ "$_count" -ge 0 ]; then
      ok "HS0: scanned $_files harnesses against a derived vocabulary of $_helpers helper(s)"
    else
      bad "HS0: derivation collapsed — $_files harness(es), $_helpers helper(s); a zero here reads exactly like a clean corpus"
    fi ;;
esac

# ==================================================================================================
# HS1 — no harness calls a helper it does not define.
# ==================================================================================================
if [ "${_count:-1}" -eq 0 ]; then
  ok "HS1: no harness calls an assertion helper it does not define"
else
  bad "HS1: $_count call(s) to an undefined helper — each one prints 'command not found' and is counted as a passing assertion:
$(printf '%s\n' "$_out" | grep -vE '^(FILES|HELPERS|COUNT) ' | sed 's/^/    /')"
fi

# ==================================================================================================
# HS2 — the scan can SEE one. HS1 ships against a measured population of zero, so on its own it is
# a green line with no demonstrated ability to go red: the self-test plants a call into a copy of
# the corpus and requires exactly that one finding. Without this, HS1 and a broken scanner are the
# same output.
# ==================================================================================================
mkdir -p "$TMP/fixture"
cp "$TESTS"/*.test.sh "$TMP/fixture/" 2>/dev/null
_victim="$TMP/fixture/spec-archive.test.sh"
if [ -f "$_victim" ] && ! grep -q '^verdict()' "$_victim"; then
  printf '\nverdict "a planted call to a helper this file does not define"\n' >>"$_victim"
  _selftest=$(python3 "$TMP/scan.py" "$TMP/fixture" 2>/dev/null | sed -n 's/^COUNT //p')
  _selftest=${_selftest:-0}
  if [ "$_selftest" -eq 1 ]; then
    ok "HS2 (self-test): the scan finds a planted call to an undefined helper"
  else
    bad "HS2 (self-test): the scan reported $_selftest finding(s) against a fixture carrying exactly one planted call — HS1's clean result says nothing"
  fi
else
  bad "HS2 (self-test): the fixture could not be built — HS1's clean result is unverified"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
