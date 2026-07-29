#!/bin/bash
# secret-scan v1.0 — content-based secret reporter (issue #100; ADR-0046).
#
# CONTRACT (ADR-0046 §D1/§D2). This is a REPORTER: it never decides policy.
#   stdout  SECRET<TAB><file>:<line><TAB><rule>   (empty means no findings)
#   stderr  one summary line per run, always
#   exit 0  the scan ran; findings may or may not be on stdout
#   exit 2  invalid invocation (unknown flag, missing argument, unreadable list)
#   exit 3  the environment cannot support the rules (see the awk probe below)
# Exit 0 WITH findings is the contract, and it is pinned by a test. Codes 2 and 3 never mean
# "found something", they mean "believe nothing about this run" — which is what lets issue #108
# run this identical script fail-closed in CI while the commit path stays advisory.
#
# WHY THE RULES ARE ANCHORED AND NOT ENTROPY-SCORED.
# Measured against this repository, not assumed: the cheap approximation of entropy
# ([A-Za-z0-9+/]{32,}) matches ordinary prose, because `/` is in the base64 alphabet and every
# absolute path in every ADR qualifies. A real scorer would still need a hex-digest exclusion to
# clear seven 40-hex GitHub Actions SHA pins and a 60-hex fixture — at which point the exclusion is
# doing the work and the score is decoration. Ten rules anchor on a vendor prefix or a structural
# marker; `assigned-secret` is the single keyword-anchored heuristic and carries four exclusions.
# The known cost: a bare high-entropy password with no keyword and no prefix is missed. That is
# deliberate, and it is why the commit HITL gate remains the real gate.
#
# WHY THERE IS A START-UP PROBE (ADR-0046 §D4).
# Every rule uses ERE interval syntax ({16}). An awk without interval support does NOT error on
# {16} — it treats the braces as literal characters and every rule silently matches nothing. A
# check that reports nothing is indistinguishable from a check that found nothing, and that
# ambiguity is exactly what kept issue #93 invisible. So the interval capability is probed at
# start-up and the script exits 3 rather than return a clean-looking empty result.
# SECRET_SCAN_AWK overrides the interpreter so that failure path is testable.
#
# No git, no jq, no hook payload, no external tool beyond POSIX: issue #108 needs this runnable
# from a plain shell in a target project's CI, with no agent present.
# Bash 3.2 clean: no assoc arrays, no mapfile, no process substitution, no <<<.
set -u

AWK="${SECRET_SCAN_AWK:-awk}"
SELF="secret-scan"

usage() {
  [ "${1:-}" = "" ] || printf '%s: %s\n' "$SELF" "$1" >&2
  cat >&2 <<'EOF'
usage: secret-scan.sh --files <list-file>    newline-separated paths ("-" reads the list from stdin)
       secret-scan.sh --diff                 unified diff on stdin; added lines only

Output (stdout): SECRET<TAB><file>:<line><TAB><rule>, one line per (file, rule).
Exit: 0 scan completed (with or without findings) | 2 bad invocation | 3 awk lacks ERE intervals.
EOF
}

MODE=""; LIST=""
while [ $# -gt 0 ]; do
  case "$1" in
    --files)
      [ -n "$MODE" ] && { usage "--files and --diff are mutually exclusive"; exit 2; }
      [ $# -ge 2 ] || { usage "--files needs a list-file argument"; exit 2; }
      MODE="files"; LIST="$2"; shift 2 ;;
    --diff)
      [ -n "$MODE" ] && { usage "--files and --diff are mutually exclusive"; exit 2; }
      MODE="diff"; shift ;;
    *) usage "unknown argument: $1"; exit 2 ;;
  esac
done
[ -n "$MODE" ] || { usage "one of --files or --diff is required"; exit 2; }

# --- the interval probe. Built by concatenation so this file is not itself a corpus violation. ---
PROBE="AKIA"; PROBE="${PROBE}ABCDEFGHIJKLMNOP"
PROBE_OUT=$(printf '%s\n' "$PROBE" \
  | "$AWK" '$0 ~ /AKIA[0-9A-Z]{16}/ { if (match($0, /[0-9A-Z]{16}/)) print "y" }' 2>/dev/null)
if [ "$PROBE_OUT" != "y" ]; then
  printf '%s: FATAL — the awk in use does not support ERE interval syntax ({16}).\n' "$SELF" >&2
  printf '%s: every rule would silently match nothing, so no scan was performed.\n' "$SELF" >&2
  printf '%s: awk = %s ; version = %s\n' "$SELF" "$AWK" \
    "$("$AWK" --version 2>&1 | head -1 || echo unknown)" >&2
  printf '%s: install a POSIX awk with interval support, or set SECRET_SCAN_AWK to one.\n' "$SELF" >&2
  exit 3
fi

TMPD=$(mktemp -d) || { printf '%s: cannot create a temp directory\n' "$SELF" >&2; exit 2; }
trap 'rm -rf "$TMPD"' EXIT

RECORDS="$TMPD/records"; : >"$RECORDS"
FN_OUT="$TMPD/fn_out";   : >"$FN_OUT"
FN_PATHS="$TMPD/fn_paths"; : >"$FN_PATHS"

# --- the filename rule (ADR-0046 §D7). The four patterns are commit/SKILL.md's Step 1 secrets
# check — the `.env`, `*secret*`, `*credential*`, `*.pem` list — verbatim and NOT narrowed:
# narrowing them would weaken an existing invariant guardrail. Case-insensitive.
fname_match() {
  _lp=$(printf '%s' "$1" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')
  _bn="${_lp##*/}"
  case "$_lp" in *secret*|*credential*|*.pem) return 0 ;; esac
  case "$_bn" in .env|.env.*) return 0 ;; esac
  return 1
}
record_fname() {
  printf 'SECRET\t%s:0\tfilename-pattern\n' "$1" >>"$FN_OUT"
  printf '%s\n' "$1" >>"$FN_PATHS"
}

# Always one integer on stdout. NOT `$(grep -c … || echo 0)`: grep -c PRINTS 0 and EXITS 1 when
# nothing matches, so the fallback fires as well and the substitution yields "0\n0" — which breaks
# printf and arithmetic on every clean run. Pinned by C13.
count_re() { _c=$(grep -c "$1" "$2" 2>/dev/null); printf '%s' "${_c:-0}"; }

# --- the rule engine, shared by both modes (ADR-0046 §D6). One table, two front ends: a rule table
# per mode is how two detectors drift apart.
cat >"$TMPD/rules.awk" <<'AWKEOF'
# Input records: path<TAB>lineno<TAB>content. Output: SECRET<TAB>path:line<TAB>rule.
# One line per (file, rule), at the first occurrence.

# assigned-secret: the only keyword-anchored rule, and the only one with exclusions.
# The keyword half is matched on a lowercased copy (positions are preserved by tolower, so the
# value can still be verified against the original, case-sensitive character class).
function assigned(s,   lc, tail, val, lv, n) {
  lc = tolower(s)
  if (!match(lc, /(api[_-]?key|apikey|secret|token|passwd|password|credential|auth)[a-z0-9_.-]*["']?[ \t]*[:=][ \t]*["']?/)) return 0
  tail = substr(s, RSTART + RLENGTH)
  if (!match(tail, /^[A-Za-z0-9+\/_=.~-]{16,}/)) return 0
  val = substr(tail, 1, RLENGTH)
  lv = tolower(val)
  # 1. placeholder value
  if (lv ~ /^(x{8,}|changeme|your[-_]|example|sample|dummy|fake|placeholder|redacted|todo|none|null)/) return 0
  # 2. an MD5 / SHA-1 / SHA-256 / SHA-512 digest. This is the corpus rule that keeps the Actions
  #    SHA pins and the fake trust hash quiet.
  n = length(val)
  if (val ~ /^[0-9a-fA-F]+$/ && (n == 32 || n == 40 || n == 64 || n == 128)) return 0
  # 3. the line reads an environment variable rather than defining a value. A value beginning with
  #    "$" is free: $, { and } are outside the value character class, so it cannot reach 16 chars.
  if (s ~ /process\.env|os\.environ|getenv|ENV\[/) return 0
  return 1
}

function classify(s,   tail) {
  if (s ~ /(^|[^A-Za-z0-9])(AKIA|ASIA)[0-9A-Z]{16}([^A-Za-z0-9]|$)/) return "aws-access-key-id"
  if (match(tolower(s), /aws[_-]?secret[_-]?access[_-]?key["']?[ \t]*[:=][ \t]*["']?/)) {
    tail = substr(s, RSTART + RLENGTH)
    if (tail ~ /^[A-Za-z0-9\/+=]{40}([^A-Za-z0-9\/+=]|$)/) return "aws-secret-access-key"
  }
  if (s ~ /-----BEGIN [A-Z ]*PRIVATE KEY-----/) return "private-key-block"
  if (s ~ /(^|[^A-Za-z0-9_])gh[pousr]_[A-Za-z0-9]{36}([^A-Za-z0-9]|$)/) return "github-token"
  if (s ~ /(^|[^A-Za-z0-9_])github_pat_[A-Za-z0-9_]{30,}/) return "github-token"
  if (s ~ /(^|[^A-Za-z0-9_-])AIza[0-9A-Za-z_-]{35}/) return "google-api-key"
  if (s ~ /(^|[^A-Za-z0-9_-])xox[abprse]-[0-9A-Za-z-]{10,}/) return "slack-token"
  if (s ~ /(^|[^A-Za-z0-9_])(sk|rk)_live_[0-9A-Za-z]{16,}/) return "stripe-secret-key"
  # A real JWT payload is a JSON object, so its base64 begins with the same three characters as
  # the header. Requiring BOTH segments turns a rule that would fire on any dotted base64-ish
  # string into one that fires on a JWT.
  if (s ~ /eyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/) return "jwt"
  if (s ~ /(^|[^A-Za-z0-9_])sk-(proj-)?[A-Za-z0-9_-]{32,}/) return "openai-api-key"
  if (assigned(s)) return "assigned-secret"
  return ""
}

BEGIN {
  if (fnfile != "") {
    while ((getline l < fnfile) > 0) if (l != "") supp[l] = 1
    close(fnfile)
  }
}
{
  i = index($0, "\t"); if (i == 0) next
  path = substr($0, 1, i - 1); rest = substr($0, i + 1)
  j = index(rest, "\t"); if (j == 0) next
  ln = substr(rest, 1, j - 1); line = substr(rest, j + 1)
  # A file already reported by filename-pattern is reported ONCE, not twice.
  if (path in supp) next
  r = classify(line); if (r == "") next
  k = path SUBSEP r; if (k in seen) next
  seen[k] = 1
  printf "SECRET\t%s:%s\t%s\n", path, ln, r
}
AWKEOF

LISTED=0; SCANNED=0; SKIPPED=0

if [ "$MODE" = "files" ]; then
  if [ "$LIST" = "-" ]; then
    cat >"$TMPD/list"; LIST="$TMPD/list"
  fi
  [ -r "$LIST" ] || { usage "cannot read list file: $LIST"; exit 2; }

  SCANLIST="$TMPD/scanlist"; : >"$SCANLIST"
  while IFS= read -r p || [ -n "$p" ]; do
    [ -n "$p" ] || continue
    LISTED=$((LISTED + 1))
    if [ ! -f "$p" ]; then SKIPPED=$((SKIPPED + 1)); continue; fi
    # Refused loudly rather than mis-parsed: the output format is <file>:<line> and a colon in the
    # path makes it ambiguous to re-split.
    case "$p" in
      *:*) printf '%s: skipping path containing a colon (output format is <file>:<line>): %s\n' \
             "$SELF" "$p" >&2
           SKIPPED=$((SKIPPED + 1)); continue ;;
    esac
    if fname_match "$p"; then
      record_fname "$p"; SCANNED=$((SCANNED + 1)); continue
    fi
    # An empty file is scanned with nothing to find; counting it as skipped would misreport.
    if [ ! -s "$p" ]; then SCANNED=$((SCANNED + 1)); continue; fi
    printf '%s\n' "$p" >>"$SCANLIST"
  done <"$LIST"

  # Binary detection in one batch pass. /dev/null is a fixed first argument on every xargs
  # invocation so grep can never be left with no file operand and start reading stdin.
  TEXTLIST="$TMPD/textlist"; : >"$TEXTLIST"
  if [ -s "$SCANLIST" ]; then
    tr '\n' '\0' <"$SCANLIST" | xargs -0 grep -Il '' /dev/null 2>/dev/null >"$TEXTLIST"
  fi
  N_SCAN=$(count_re . "$SCANLIST")
  N_TEXT=$(count_re . "$TEXTLIST")
  SCANNED=$((SCANNED + N_TEXT))
  SKIPPED=$((SKIPPED + N_SCAN - N_TEXT))

  if [ -s "$TEXTLIST" ]; then
    tr '\n' '\0' <"$TEXTLIST" \
      | xargs -0 "$AWK" '{ printf "%s\t%d\t%s\n", FILENAME, FNR, $0 }' 2>/dev/null >"$RECORDS"
  fi
else
  cat >"$TMPD/diff"
  # Pass 1: the filename rule over the new paths in the diff.
  grep '^+++ ' "$TMPD/diff" 2>/dev/null | sed -e 's|^+++ ||' -e 's|[	 ].*$||' -e 's|^b/||' \
    | while IFS= read -r p; do
        [ -n "$p" ] && [ "$p" != "/dev/null" ] || continue
        if fname_match "$p"; then record_fname "$p"; fi
      done
  # Pass 2: added lines only, with the new-file line number derived from the @@ hunk headers.
  "$AWK" '
    /^diff --git /   { path = ""; ln = 0; next }
    /^--- /          { next }
    /^\+\+\+ /       { p = $2; sub(/^b\//, "", p)
                       path = (p == "/dev/null") ? "" : p; ln = 0; next }
    /^@@ /           { if (match($0, /\+[0-9]+/)) ln = substr($0, RSTART + 1, RLENGTH - 1) + 0
                       next }
    {
      if (path == "" || ln == 0) next
      c = substr($0, 1, 1)
      if (c == "+")       { printf "%s\t%d\t%s\n", path, ln, substr($0, 2); ln++ }
      else if (c == "-")  { }
      else if (c == "\\") { }
      else                { ln++ }
    }
  ' <"$TMPD/diff" >"$RECORDS" 2>/dev/null
  LISTED=$(count_re '^+++ ' "$TMPD/diff")
  SCANNED="$LISTED"
fi

# Deduplicate the filename findings (a path can appear twice in a list or a diff), then the
# content findings, suppressing any path the filename rule already claimed.
FINDINGS="$TMPD/findings"; : >"$FINDINGS"
[ -s "$FN_OUT" ] && sort -u "$FN_OUT" >>"$FINDINGS"
if [ -s "$RECORDS" ]; then
  "$AWK" -v fnfile="$FN_PATHS" -f "$TMPD/rules.awk" <"$RECORDS" >>"$FINDINGS" 2>/dev/null
fi

N_FIND=$(count_re . "$FINDINGS")
[ -s "$FINDINGS" ] && cat "$FINDINGS"

# The summary always goes to stderr, on every run, findings or not (ADR-0046 §D5). stdout stays a
# clean machine-readable channel for #108's `wc -l`, and "0 files scanned" becomes visible instead
# of reading like a clean result.
printf '%s: %d file(s) listed, %d scanned, %d skipped, %d finding(s)\n' \
  "$SELF" "$LISTED" "$SCANNED" "$SKIPPED" "$N_FIND" >&2
exit 0
