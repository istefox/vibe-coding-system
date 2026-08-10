#!/bin/bash
# mode-binding-check.sh v1.0 — does every invocation of a two-mode script declare the QUESTION it
# is asking, and does that declaration agree with the flag it actually used (issue #294, ADR-0131).
# `plan-tasks.sh` has two modes with OPPOSITE failure directions (--count over-counts, safe for a
# guard; --count-openers can legitimately return 0, safe for arithmetic) and, until this feature,
# the only thing stopping a caller mixing them up was a paragraph in the script's own header — read
# once by whoever writes a call site, never again by anything. This checker re-derives, every run,
# the mode vocabulary, the mode -> question table, and every call site under a population root, and
# compares all three, so a THIRD caller written by someone who never read the header is caught on
# the next run rather than never.
#
# THIS IS A CHECKER, NOT A REPORTER. The caller branches on the exit code. It prints no `CLEAN`
# sentinel and must NEVER grow one — `weakening-scan.sh` four Step 5 blocks away is a REPORTER
# (always exits 0, signals on stdout only), and the two idioms have already been confused once in
# this repository at a single call site (ADR-0048) and restated at two more (ADR-0117, ADR-0120).
# Do not copy one block's branching into the other.
#
# USAGE
#   mode-binding-check.sh <plan-tasks-script> <population-root>
#
# Both are ARGUMENTS, deliberately (ADR-0117 §3.9): a later issue can point this at another
# two-mode script, or another root, without editing this file.
#
# EXIT CONTRACT
#   0  ran; every invocation is bound and agrees. stdout EMPTY.
#   1  ran; one or more findings, one per line on stdout.
#   2  bad invocation of the checker itself: wrong argument count, unreadable script, missing root.
#   3  DID NOT RUN: zero modes derived from <plan-tasks-script>'s own parser, OR zero invocations
#      found under <population-root>. Distinct from 0 — a derivation that stops resolving discovers
#      nothing and reads exactly like a tree where every call site is correctly bound (ADR-0085:
#      count-guard the denominator, not the matches). stdout stays EMPTY on exit 3 too, so "found
#      nothing" can never be mistaken for "did not run".
#
# FINDING TAXONOMY (one line each on stdout: "<file>:<line>: <TOKEN> <subject> [-- detail]")
#   UNBOUND            an invocation with a recognised mode and no `# plan-tasks-question:` marker
#   UNKNOWN-MODE        the token after the script path is not a mode the parser accepts
#   MISMATCH            the declared question does not equal the mode's own `# mode-contract:`
#                        question (message names the expected question)
#   UNKNOWN-QUESTION     the mode HAS its own contract, the declared word disagrees, and the word
#                        matches no `# mode-contract:` question anywhere in the file
#   UNCOVERED-MODE      the parser accepts a mode with no `# mode-contract:` line
#   STALE-CONTRACT      a `# mode-contract:` line names a mode the parser does not accept
#   SHORT-REASON        a `# mode-contract:` line's third (failure-direction) field is < 40 chars
#   STALE-MODE-EXEMPT    the `--help` exemption below (D4) no longer has a subject in the parser —
#                        an EIGHTH token, beyond ADR-0131 §D3's table, because D4's stale-waiver
#                        check (ADR-0081 ZA4) has no assigned name there
#
# RESIDUAL LIMIT, STATED FLATLY (ADR-0131 Consequences/negative): the marker declares INTENT, and
# NOTHING here verifies the intent is honest. A call site that declares `guard`, invokes `--count`,
# and then feeds the number to arithmetic passes every check in this file. That is issue #242's
# exact shape, and this feature does not close it. A green run means "every invocation declares its
# question and the declaration agrees with its flag", never "no invocation is used for the wrong
# question".
#
# POPULATION BOUNDARIES, DECLARED (ADR-0131 §D4): `*.sh` under <population-root>, excluding any
# path containing `/tests/`, non-comment lines only; `*.md`, only lines inside a fenced ```bash
# block (opening fence matched INDENTATION-TOLERANTLY — ADR-0083 §S3), again non-comment lines. A
# caller inside `<root>/…/tests/` is outside the population BY DESIGN — a harness invoking the
# script is exercising it, not asking it a question, and every harness invocation in this repo
# holds the script path in a variable, so the literal-path population would never see them anyway
# while their `ok`/`bad` message strings would flood it. A caller written directly into a deployed
# tree (`~/.claude`) or into `docs/` is invisible: this file reads `<population-root>` only.
#
# FOUR FILTERS narrow "names <plan-tasks-script>'s basename" down to a genuine invocation, each
# closing a MEASURED false-positive class (grep the corpus before trusting a filter list):
#   1. comment lines (first non-blank char `#`) are skipped — clears the two fences' own
#      explanatory header comments AND this file's own header, which legitimately name the script
#      while describing it (rule 12).
#   2. the "mode-token requirement": the whitespace-delimited token immediately following the
#      script's basename must, after stripping one optional leading quote, start with `-`. This
#      clears the measured rule-12 trap inside `autopilot-build-check-5` —
#      `echo "... (plan-tasks.sh exit $rc)."` — which names the script and carries no flag: "exit"
#      does not start with `-`, so the line never becomes a candidate at all (ADR-0131 premise 3).
#      Once a token DOES start with `-`, it is never silently dropped for not matching a derived
#      mode — that is UNKNOWN-MODE, a finding, not a skip (ADR-0131 §D4).
#   3. the `*/tests/*` path exclusion clears the harness's own `ok`/`bad` message strings, which are
#      CODE, not commentary, and which filter 1 cannot reach.
#   4. heredoc BODIES (a marker `<<'EOF' … EOF` state machine) are skipped as data, in `*.sh` files
#      AND `.md` fences alike. Found by measurement, not named in the ADR: `plan-tasks.sh`'s own
#      `usage()` heredoc prints "usage: plan-tasks.sh --count <plan-file>" — a line with no leading
#      `#`, naming the script, immediately followed by a real flag. Without this filter the checker
#      would report its own target's help text as two permanently-UNBOUND invocations, and PTK2
#      (ADR-0131) could never go green.
#      ONE NAMED EXCEPTION, added by issue #394 / ADR-0133: the literal delimiter `FENCE_BASH` does
#      NOT open a skip. That marker is the D1 wrapper (`bash <<'FENCE_BASH' … FENCE_BASH`) every
#      population fence now carries — its body is not caller data fed to some other command, it IS
#      the fence's own executed bash source, byte-for-byte what a `plan-tasks.sh` call site writes.
#      Treating it as opaque heredoc data is what silently took all three real invocations (two in
#      concept-to-code, one in autopilot-build) to zero the day the wrapper landed: every one of them
#      sits inside a `FENCE_BASH`-wrapped fence, all three PTK2/PTK3/PTK7 red for that one reason.
#      Descending into it is SAFE and SPECIFIC to this one name: measured pre-#394 (ADR-0131 fact 8),
#      no `SKILL.md` used the literal `FENCE_BASH` for anything else, and #394's own D1 rule 1 reused
#      it precisely because nothing else did. Every OTHER delimiter is unaffected and still opens a
#      skip, including ones now NESTED inside a wrapped fence's own body — `DIRTY_EOF`
#      (concept-to-code, a dirty-tree classification loop) and `TESTFILES_EOF` (commit, a path list)
#      are both measured examples in the corpus today, and both must stay data: a `plan-tasks.sh`-
#      shaped string inside either is a file path or a diff line, never an invocation.
#
# Bash 3.2 / BSD-tools clean. Run: bash mode-binding-check.sh <plan-tasks-script> <population-root>
set -u

MODE_COUNT=0
CONTRACTS_COUNT=0
INVOCATIONS=0
BOUND=0
FINDINGS_TOTAL=0

print_stats() {
  printf 'mode-binding-check: modes=%s contracts=%s invocations=%s bound=%s findings=%s\n' \
    "$MODE_COUNT" "$CONTRACTS_COUNT" "$INVOCATIONS" "$BOUND" "$FINDINGS_TOTAL" >&2
}

if [ "$#" -ne 2 ]; then
  echo "mode-binding-check: usage: mode-binding-check.sh <plan-tasks-script> <population-root>" >&2
  print_stats
  exit 2
fi

SCRIPT="$1"
ROOT="$2"

if [ ! -f "$SCRIPT" ] || [ ! -r "$SCRIPT" ]; then
  echo "mode-binding-check: plan-tasks script not readable: $SCRIPT" >&2
  print_stats
  exit 2
fi

if [ ! -d "$ROOT" ]; then
  echo "mode-binding-check: population root not found: $ROOT" >&2
  print_stats
  exit 2
fi

TMPD=$(mktemp -d) || { echo "mode-binding-check: cannot create a temp directory" >&2; print_stats; exit 2; }
trap 'rm -rf "$TMPD"' EXIT

# -------------------------------------------------------------------------------------------------
# PHASE 1 — parse <plan-tasks-script>: the `--<word>)` arms of its own `case "$1" in … esac`
# (never a hardcoded list, ADR-0085 J0a's technique), and its `# mode-contract:` lines. Emits raw
# modes, contracts, and the UNCOVERED-MODE / STALE-CONTRACT / SHORT-REASON / STALE-MODE-EXEMPT
# cross-checks — all derivable from this one file, so all computed in this one awk pass.
#
# mode-exempt: --help — a usage-only flag: it exits 2 and produces no number any caller can
# consume, so it needs no # mode-contract: line of its own (ADR-0131 §D4). Hardcoded here rather
# than self-parsed, exactly as path-rule-check.sh hardcodes its verb list rather than deriving it
# from a separate declaration file; STALE-MODE-EXEMPT below is what keeps the exemption asserted
# live (ADR-0081 ZA4) rather than a silent, un-checked assumption.
# -------------------------------------------------------------------------------------------------
cat > "$TMPD/script.awk" <<'AWKEOF'
BEGIN { in_case = 0; nraw = 0; ncontract = 0 }
{
  line = $0

  if (!in_case && index(line, "case \"$1\" in") > 0) { in_case = 1; next }
  if (in_case && index(line, "esac") > 0) { in_case = 0 }

  if (in_case) {
    t = line
    sub(/^[ \t]+/, "", t)
    p = index(t, ")")
    if (p > 0) {
      patt = substr(t, 1, p - 1)
      if (patt ~ /^[A-Za-z0-9_*|-]+$/) {
        na = split(patt, arms, "|")
        for (a = 1; a <= na; a++) {
          tok = arms[a]
          if (substr(tok, 1, 2) == "--" && !(tok in seenraw)) {
            seenraw[tok] = 1
            nraw++
            rawtok[nraw] = tok
            rawline[nraw] = NR
          }
        }
      }
    }
  }

  tt = line
  sub(/^[ \t]+/, "", tt)
  if (index(tt, "# mode-contract:") == 1) {
    rest = substr(tt, length("# mode-contract:") + 1)
    sub(/^[ \t]+/, "", rest)
    p1 = index(rest, " | ")
    if (p1 > 0) {
      after1 = substr(rest, p1 + 3)
      p2 = index(after1, " | ")
      if (p2 > 0) {
        ncontract++
        cflag[ncontract] = substr(rest, 1, p1 - 1)
        cquestion[ncontract] = substr(after1, 1, p2 - 1)
        reason = substr(after1, p2 + 3)
        sub(/[ \t]+$/, "", reason)
        creasonlen[ncontract] = length(reason)
        cline[ncontract] = NR
      }
    }
  }
}
END {
  for (i = 1; i <= nraw; i++) printf "MODE\t%s\t%d\n", rawtok[i], rawline[i]
  for (i = 1; i <= ncontract; i++) printf "CONTRACT\t%s\t%s\t%d\t%d\n", cflag[i], cquestion[i], creasonlen[i], cline[i]

  for (i = 1; i <= nraw; i++) {
    if (rawtok[i] == "--help") continue
    covered = 0
    for (j = 1; j <= ncontract; j++) if (cflag[j] == rawtok[i]) { covered = 1; break }
    if (!covered) printf "FINDING\tUNCOVERED-MODE\t%s\t%d\n", rawtok[i], rawline[i]
  }
  for (j = 1; j <= ncontract; j++) {
    accepted = 0
    for (i = 1; i <= nraw; i++) if (rawtok[i] == cflag[j]) { accepted = 1; break }
    if (!accepted) printf "FINDING\tSTALE-CONTRACT\t%s\t%d\n", cflag[j], cline[j]
    if (creasonlen[j] < 40) printf "FINDING\tSHORT-REASON\t%s\t%d\n", cflag[j], cline[j]
  }
  helpfound = 0
  for (i = 1; i <= nraw; i++) if (rawtok[i] == "--help") { helpfound = 1; break }
  if (!helpfound) printf "FINDING\tSTALE-MODE-EXEMPT\t--help\t0\n"
}
AWKEOF

awk -f "$TMPD/script.awk" "$SCRIPT" > "$TMPD/script.out" 2>"$TMPD/script.err"
if [ "$?" -ne 0 ]; then
  echo "mode-binding-check: internal error deriving modes/contracts from $SCRIPT" >&2
  print_stats
  exit 2
fi

MODES_STR=""
CONTRACTS_STR=""
: > "$TMPD/findings.txt"

while IFS=$'\t' read -r rtype f2 f3 f4 f5; do
  [ -n "${rtype:-}" ] || continue
  case "$rtype" in
    MODE)
      if [ "$f2" != "--help" ]; then
        MODE_COUNT=$((MODE_COUNT + 1))
        MODES_STR="$MODES_STR $f2"
      fi
      ;;
    CONTRACT)
      CONTRACTS_COUNT=$((CONTRACTS_COUNT + 1))
      CONTRACTS_STR="$CONTRACTS_STR$f2:$f3,"
      ;;
    FINDING)
      FINDINGS_TOTAL=$((FINDINGS_TOTAL + 1))
      case "$f2" in
        UNCOVERED-MODE)
          printf "%s:%s: UNCOVERED-MODE %s -- the parser accepts this mode, no # mode-contract: line binds it\n" "$SCRIPT" "$f4" "$f3" >> "$TMPD/findings.txt" ;;
        STALE-CONTRACT)
          printf "%s:%s: STALE-CONTRACT %s -- a # mode-contract: line names a mode the parser does not accept\n" "$SCRIPT" "$f4" "$f3" >> "$TMPD/findings.txt" ;;
        SHORT-REASON)
          printf "%s:%s: SHORT-REASON %s -- the failure-direction field is under 40 characters\n" "$SCRIPT" "$f4" "$f3" >> "$TMPD/findings.txt" ;;
        STALE-MODE-EXEMPT)
          printf "%s: STALE-MODE-EXEMPT %s -- the declared exemption's subject is no longer in the parser\n" "$SCRIPT" "$f3" >> "$TMPD/findings.txt" ;;
      esac
      ;;
  esac
done < "$TMPD/script.out"

if [ "$MODE_COUNT" -eq 0 ]; then
  echo "mode-binding-check: DID NOT RUN -- zero modes derived from $SCRIPT's own case \"\$1\" in … esac parser (block markers not found, or no --<word>) arms)" >&2
  FINDINGS_TOTAL=0
  print_stats
  exit 3
fi

# -------------------------------------------------------------------------------------------------
# PHASE 2 — population scan. Two shared pieces (comment test, invocation emission) loaded into two
# small per-filetype drivers via `-f`, never pasted twice (ADR-0069 §D2's rule, applied here).
# -------------------------------------------------------------------------------------------------
cat > "$TMPD/shared.awk" <<'AWKEOF'
function is_comment_line(   tt) {
  tt = $0
  sub(/^[ \t]+/, "", tt)
  return (substr(tt, 1, 1) == "#")
}
function detect_heredoc_marker(   p, rest, c, q, m) {
  p = index($0, "<<")
  if (p == 0) return ""
  rest = substr($0, p + 2)
  if (substr(rest, 1, 1) == "<") return ""              # <<< here-string, not a heredoc
  if (substr(rest, 1, 1) == "-") rest = substr(rest, 2)  # <<- variant
  sub(/^[ \t]+/, "", rest)
  c = substr(rest, 1, 1)
  if (c == "'" || c == "\"") {
    rest = substr(rest, 2)
    q = index(rest, c)
    if (q == 0) return ""
    m = substr(rest, 1, q - 1)
  } else if (match(rest, /^[A-Za-z_][A-Za-z0-9_]*/)) {
    m = substr(rest, RSTART, RLENGTH)
  } else {
    return ""
  }
  # issue #394 / ADR-0133: FENCE_BASH is the D1 wrapper, not caller data — its body is the fence's
  # own bash source and must stay in scope for the population scan. See the header's filter-4 note
  # for why this one name is safe to descend into and every other delimiter is not.
  if (m == "FENCE_BASH") return ""
  return m
}
function emit_candidate(   pos, rest, tok, qtok, mtok, mpos, mrest) {
  pos = index($0, "plan-tasks.sh")
  if (pos == 0) return
  rest = substr($0, pos + length("plan-tasks.sh"))
  sub(/^[ \t]+/, "", rest)
  if (rest == "") return
  split(rest, arr, /[ \t]+/)
  tok = arr[1]
  qtok = tok
  if (substr(qtok, 1, 1) == "\"" || substr(qtok, 1, 1) == "'") qtok = substr(qtok, 2)
  if (substr(qtok, 1, 1) != "-") return                  # filter 2: mode-token requirement

  mtok = ""
  mpos = index($0, "# plan-tasks-question:")
  if (mpos > 0) {
    mrest = substr($0, mpos + length("# plan-tasks-question:"))
    sub(/^[ \t]+/, "", mrest)
    split(mrest, marr, /[ \t]+/)
    mtok = marr[1]
  }
  printf "%s\t%d\t%s\t%s\n", FILENAME, FNR, tok, mtok
}
AWKEOF

cat > "$TMPD/sh_driver.awk" <<'AWKEOF'
BEGIN { in_hd = 0; hd_marker = "" }
{
  if (in_hd) {
    if ($0 == hd_marker) in_hd = 0
    next
  }
  m = detect_heredoc_marker()
  if (m != "") { in_hd = 1; hd_marker = m }
  if (!is_comment_line()) emit_candidate()
}
AWKEOF

cat > "$TMPD/md_driver.awk" <<'AWKEOF'
BEGIN { infence = 0; in_hd = 0; hd_marker = "" }
{
  t = $0
  sub(/^[ \t]+/, "", t)
  if (!infence) {
    if (substr(t, 1, 7) == "```bash") infence = 1
    next
  }
  if (substr(t, 1, 3) == "```") { infence = 0; next }
  if (in_hd) {
    if ($0 == hd_marker) in_hd = 0
    next
  }
  m = detect_heredoc_marker()
  if (m != "") { in_hd = 1; hd_marker = m }
  if (!is_comment_line()) emit_candidate()
}
AWKEOF

: > "$TMPD/invocations.txt"
while IFS= read -r f; do
  [ -n "$f" ] || continue
  awk -f "$TMPD/shared.awk" -f "$TMPD/sh_driver.awk" "$f" >> "$TMPD/invocations.txt"
done <<EOF
$(find "$ROOT" -type f -name '*.sh' ! -path '*/tests/*')
EOF
while IFS= read -r f; do
  [ -n "$f" ] || continue
  awk -f "$TMPD/shared.awk" -f "$TMPD/md_driver.awk" "$f" >> "$TMPD/invocations.txt"
done <<EOF
$(find "$ROOT" -type f -name '*.md')
EOF

INVOCATIONS=$(grep -c . "$TMPD/invocations.txt" 2>/dev/null || true); INVOCATIONS=${INVOCATIONS:-0}

if [ "$INVOCATIONS" -eq 0 ]; then
  echo "mode-binding-check: DID NOT RUN -- zero invocations of $(basename "$SCRIPT") found under $ROOT (population: *.sh excluding */tests/*, and fenced \`\`\`bash blocks in *.md, non-comment executable context only)" >&2
  FINDINGS_TOTAL=0
  print_stats
  exit 3
fi

# -------------------------------------------------------------------------------------------------
# PHASE 3 — compare each invocation against the derived mode set (EXACT equality, never a prefix:
# `--count` is a strict prefix of `--count-openers`, ADR-0131 premise 4) and the contract table.
# -------------------------------------------------------------------------------------------------
cat > "$TMPD/compare.awk" <<'AWKEOF'
BEGIN {
  FS = "\t"
  nm = split(modes, marr, " ")
  for (i = 1; i <= nm; i++) modeset[marr[i]] = 1
  nc = split(contracts, carr, ",")
  for (i = 1; i <= nc; i++) {
    if (carr[i] == "") continue
    split(carr[i], kv, ":")
    qmap[kv[1]] = kv[2]
    knownq[kv[2]] = 1
  }
  bound = 0
  findings = 0
}
{
  file = $1; line = $2; tok = $3; mk = $4

  if (!(tok in modeset)) {
    findings++
    printf "%s:%d: UNKNOWN-MODE %s\n", file, line, tok
    next
  }
  if (mk == "") {
    findings++
    printf "%s:%d: UNBOUND %s\n", file, line, tok
    next
  }
  if ((tok in qmap) && qmap[tok] == mk) { bound++; next }

  findings++
  if (mk in knownq) {
    expected = (tok in qmap) ? qmap[tok] : "(no # mode-contract: line for " tok ")"
    printf "%s:%d: MISMATCH %s -- declares '%s', expected '%s'\n", file, line, tok, mk, expected
  } else if (!(tok in qmap)) {
    # tok itself has no contract of its own: cannot verify, so this is treated as a mismatch
    # rather than "unknown" -- there is no vocabulary yet to call the word unknown AGAINST.
    printf "%s:%d: MISMATCH %s -- declares '%s', %s has no # mode-contract: line to verify against\n", file, line, tok, mk, tok
  } else {
    printf "%s:%d: UNKNOWN-QUESTION %s -- declares '%s', no # mode-contract: line binds that word\n", file, line, tok, mk
  }
}
END {
  printf "%d\t%d\n", bound, findings > statsfile
}
AWKEOF

MODES_TRIMMED="${MODES_STR# }"
awk -v modes="$MODES_TRIMMED" -v contracts="$CONTRACTS_STR" -v statsfile="$TMPD/phase3.stats" \
  -f "$TMPD/compare.awk" "$TMPD/invocations.txt" >> "$TMPD/findings.txt"

P3_BOUND=0
P3_FINDINGS=0
if [ -f "$TMPD/phase3.stats" ]; then
  read -r P3_BOUND P3_FINDINGS < "$TMPD/phase3.stats"
fi
BOUND=${P3_BOUND:-0}
FINDINGS_TOTAL=$((FINDINGS_TOTAL + ${P3_FINDINGS:-0}))

if [ "$FINDINGS_TOTAL" -gt 0 ]; then
  cat "$TMPD/findings.txt"
  print_stats
  exit 1
fi

print_stats
exit 0
