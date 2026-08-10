#!/bin/bash
# fence-shell-divergence-scan.sh v1.0 — the zsh/bash divergence audit instrument (issue #394,
# ADR-0133 Task 1, R-01/R-12).
#
# THIS IS A REPORTER, NOT A CHECKER. It always exits 0 with findings on stdout (findings or none —
# it prints no `CLEAN` sentinel and must NEVER grow one), and exits 3 only when the awk in use
# cannot express its own rules (see THE INTERVAL PROBE below). It never decides policy and it never
# tells a caller to stop. ITS CONSUMER, section `WS` of `fence-contract-coverage.test.sh` (Task 3),
# IS A CHECKER: it branches on an exit code. `weakening-scan.sh`, `secret-scan.sh` and
# `mode-binding-check.sh` already demonstrate both idioms in this repository, and the two have
# already been confused once at a single call site (ADR-0048) and restated twice since
# (ADR-0117, ADR-0120, ADR-0131). Do not copy one block's branching into the other.
#
# WHAT IT READS. Exactly ONE fence body, on stdin, and it enumerates nothing itself:
#
#     some-fence-body-text | bash fence-shell-divergence-scan.sh
#
# The single enumerator of "what is a fence and what is its body" is
# `fence-contract-coverage.test.sh`'s `enumerate_fences`/`fence_body` pair. A second copy here
# would be a second answer to that question — ADR-0086 §D1's criterion answered in the affirmative
# ("extract only when two copies giving different answers would be a defect"; here they would).
# The Task 1 corpus drive (not this file) pipes each of the 162 fence bodies through this script in
# turn and reconciles the per-fence output into the ADR's Measured facts table.
#
# OUTPUT FORMAT (stdout): one record per finding —
#
#     <class>\t<body-line>\t<text>
#
# `<body-line>` is the 1-based line number WITHIN the fence body (not the file), and `<text>` is
# the offending line, trimmed of leading/trailing whitespace. A line can produce more than one
# record if more than one class applies.
#
# CLASSES
#   W-for       for X in $VAR — unquoted, so bash iterates each word and zsh iterates once (C1b)
#   W-set       set -- $VAR — the same word split, in the positional-parameter idiom (the
#               pre-ADR-0132 form; ADR-0133 R-11)
#   W-arg       any OTHER bare, unquoted parameter expansion used as a command word or argument —
#               `cmd $VAR`, `${v:+…}` — the shape #394 itself, and the shape the issue's own first
#               scanner could not see because it matched only `for X in $VAR` and `set -- $VAR`
#               (C1a/C1c)
#   G-glob      a path glob (a bare token containing `*` or `?`, not a case-arm pattern) used as a
#               command word — zsh's default `nomatch` makes an unmatched glob fail the command
#               instead of passing the literal pattern through, the way bash does (C2)
#   E-echo      `echo` (no `-e`/`-E`) whose argument contains a backslash escape sequence — bash's
#               builtin echo prints it literally, zsh's interprets it (C3; a class member, not
#               observed as a site in the corpus at design time)
#   B-builtin   `shopt`, `mapfile` or `readarray` as a bare command — bash builtins with no zsh
#               equivalent of the same name
#   B-var       a reference to a `BASH_*` special variable (`$BASH_SOURCE`, `${BASH_REMATCH[@]}`, …)
#               — bash-specific, generally unset under zsh
#   B-declare   `declare` or `typeset` as a bare command — attribute flags and scoping differ
#               across shells; deliberately excludes `local`, which both shells have (see blind
#               spots below)
#   A-array     bash array syntax: an array-literal assignment (`NAME=(…)`, parens directly after
#               `=`, never `NAME=$(…)`) or an array-subscript reference (`${NAME[…]}`)
#
# CLASSIFICATION MECHANICS
#
#   1. Comment lines (first non-blank character `#`) are skipped entirely — not classified.
#   2. Here-document BODIES are skipped as data: a `<<MARKER`/`<<'MARKER'`/`<<-MARKER` opener (any
#      of the three quoting forms, `<<-` noted) starts heredoc-skip mode; every following line is
#      skipped until one matches MARKER (leading tabs stripped, for the `<<-` form), and then
#      classification resumes on the NEXT line. The heredoc opener LINE ITSELF is still classified
#      normally — only the body between opener and terminator is skipped.
#   3. Every remaining line is MASKED before classification: single-quoted spans, double-quoted
#      spans (TRACKING `$( )` DEPTH while inside a double-quoted span, so `"$(cmd "x")"` counts as
#      fully quoted rather than the interior `"x"` prematurely closing the outer string),
#      arithmetic `$(( … ))` spans and `[[ … ]]` test spans are all replaced with blanks before the
#      W-for/W-set/W-arg/G-glob/B-builtin/B-declare/A-array rules run. `E-echo` and `B-var` read
#      the RAW (unmasked) line on purpose: an echoed escape sequence and a bash-only variable
#      reference are both relevant whether or not they sit inside quotes.
#   4. `G-glob` excludes any line that is SHAPED like a bare `case` arm (a pattern, alone on the
#      line, immediately followed by `)` and an optional `;;`) — a lexical heuristic, not a real
#      `case`/`esac` block tracker.
#
# DECLARED BLIND SPOTS — quoted, not paraphrased, from ADR-0133 §Consequences/Negative, because a
# sweep whose limits are unstated reads as complete:
#
#   "The scanner measures a floor and will always measure a floor. Its declared blind spots: a
#   multi-line quoted string is analysed as unquoted on its interior lines (the
#   `autopilot-build-check-3` false positive); here-document bodies are skipped as data, so shell
#   code fed to a shell through one is invisible; `case` arms are excluded from the glob class by a
#   lexical heuristic, so a genuine glob on a line shaped like a case arm is missed; only C1/C2/C3
#   plus four cheap bash-only probes are modelled, against a divergence surface that includes
#   `MULTIOS`, `KSH_ARRAYS`, `$0`, `[[ =~ ]]` captures, `printf %q` and `local`/`typeset` scoping;
#   and it reads staged `SKILL.md` only. A green scan means no modelled idiom was found, never
#   that no divergence exists."
#
# The first blind spot above is a DESIGN CHOICE, not an oversight: quote state is tracked WITHIN a
# line and reset at the start of every new line, deliberately, because carrying it across lines
# accurately needs a real shell tokenizer, which this reporter is not. `E-echo`/`B-var` reading the
# raw line rather than the masked one is the same trade in the other direction, made explicit here
# so the two are not mistaken for an inconsistency.
#
# THE INTERVAL PROBE (ADR-0046's receipt, secret-scan.sh's own idiom, reused rather than
# reinvented). Every rule above is written with `{n,}` interval syntax rather than `+`/`*`, ON
# PURPOSE: a pre-2019 awk without ERE interval support does not error on `{16}`, it treats the
# braces as LITERAL characters, and every rule then silently matches nothing — a scan that finds
# nothing would be indistinguishable from a scan that could not run at all, which is exactly the
# ambiguity ADR-0043's direction lesson and ADR-0046 §D4 both name. So capability is probed at
# start-up, with a synthetic string unrelated to any real rule, and the script exits 3 rather than
# return a clean-looking empty result.
#
# SCOPE. It reads whatever fence body it is handed on stdin; the corpus scope (staged `SKILL.md`
# files only) is a property of the Task 1 corpus drive that calls it, not of this file.
#
# Bash 3.2 / BSD-tools clean: no assoc arrays, no mapfile, no process substitution, no <<<.
# Run: <fence-body-text> | bash fence-shell-divergence-scan.sh
set -u

SELF="fence-shell-divergence-scan"

if [ "$#" -ne 0 ]; then
  echo "$SELF: usage: <fence-body-text> | bash fence-shell-divergence-scan.sh (reads stdin, takes no arguments)" >&2
  exit 2
fi

# --- the interval probe. A synthetic string, unrelated to any real rule above. ------------------
PROBE="QQQQ"; PROBE="${PROBE}WWWWWWWWWWWWWWWW"
PROBE_OUT=$(printf '%s\n' "$PROBE" \
  | awk '$0 ~ /QQQQ[A-Z]{16}/ { if (match($0, /[A-Z]{16}/)) print "y" }' 2>/dev/null)
if [ "$PROBE_OUT" != "y" ]; then
  printf '%s: FATAL — the awk in use does not support ERE interval syntax ({n}).\n' "$SELF" >&2
  printf '%s: every rule in this scanner uses {n} intervals and would silently match nothing.\n' "$SELF" >&2
  printf '%s: awk version: %s\n' "$SELF" "$(awk --version 2>&1 | head -1 || echo unknown)" >&2
  exit 3
fi

TMPD=$(mktemp -d) || { echo "$SELF: cannot create a temp directory" >&2; exit 2; }
trap 'rm -rf "$TMPD"' EXIT

cat >"$TMPD/scan.awk" <<'AWKEOF'
# ---- masking: blank single/double-quoted spans (tracking $( ) depth inside double quotes),
# arithmetic $(( )) spans and [[ ]] test spans. Per-line only — see the header's declared blind
# spot on multi-line quoted strings.
function mask_line(s,    n, i, c, out, state, depth) {
  n = length(s)
  out = ""
  state = "N"
  depth = 0
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (state == "N") {
      if (c == "'") { state = "S"; out = out " "; continue }
      if (c == "\"") { state = "D"; out = out " "; continue }
      if (c == "$" && substr(s, i + 1, 2) == "((") { state = "A"; depth = 2; out = out "  "; i += 2; continue }
      if (c == "[" && substr(s, i + 1, 1) == "[") { state = "T"; out = out "  "; i += 1; continue }
      out = out c
      continue
    }
    if (state == "S") {
      out = out " "
      if (c == "'") state = "N"
      continue
    }
    if (state == "D") {
      if (c == "\\") { out = out "  "; i += 1; continue }
      if (c == "\"") { state = "N"; out = out " "; continue }
      if (c == "$" && substr(s, i + 1, 1) == "(") { state = "C"; depth = 1; out = out "  "; i += 1; continue }
      out = out " "
      continue
    }
    if (state == "C") {
      out = out " "
      if (c == "(") depth++
      else if (c == ")") { depth--; if (depth == 0) state = "D" }
      continue
    }
    if (state == "A") {
      out = out " "
      if (c == "(") depth++
      else if (c == ")") { depth--; if (depth == 0) state = "N" }
      continue
    }
    if (state == "T") {
      if (c == "]" && substr(s, i + 1, 1) == "]") { state = "N"; out = out "  "; i += 1; continue }
      out = out " "
      continue
    }
  }
  return out
}

# ---- heredoc marker detection, on the RAW line (a copy of mode-binding-check.sh's own function —
# a deliberate copy per ADR-0086 §D1, not a shared helper: this file has no other dependency).
function detect_heredoc_marker(s,    p, rest, c, q) {
  p = index(s, "<<")
  if (p == 0) return ""
  rest = substr(s, p + 2)
  if (substr(rest, 1, 1) == "<") return ""              # <<< here-string, not a heredoc
  if (substr(rest, 1, 1) == "-") rest = substr(rest, 2)  # <<- variant
  sub(/^[ \t]+/, "", rest)
  c = substr(rest, 1, 1)
  if (c == "'" || c == "\"") {
    rest = substr(rest, 2)
    q = index(rest, c)
    if (q == 0) return ""
    return substr(rest, 1, q - 1)
  }
  if (match(rest, /^[A-Za-z_][A-Za-z0-9_]*/)) return substr(rest, RSTART, RLENGTH)
  return ""
}

# ---- a bare `case` pattern (possibly with a short one-line body, `pattern) cmd ;;`): excluded
# from G-glob. A NEGATIVE test, not an enumerated pattern-character class — a bracket-expression
# glob like `*[!0-9]*)` uses characters ([ ] !) a positive class would have to special-case, and
# getting a POSIX bracket-expression literal right for every one of them is its own hazard. `|` is
# deliberately NOT in the disqualifying set: it is ordinary case-pattern alternation
# (`foo|bar)`), so a pattern containing it is evidence FOR a case arm, not against one — a first
# draft excluded on it and misclassified `'ABSENT|'*)` as not-a-case-arm. The prefix up to the
# first `)` is a case arm unless it contains something no pattern legitimately does: whitespace,
# `=`, `$`, `(`, `)`, `;`, `&`, a backtick — a lexical heuristic, not a real case/esac tracker (see
# the header's declared blind spot: a genuine glob shaped like a case arm, e.g. a
# multi-line-continuation closer such as `arg2)`, is missed by design).
function is_case_arm(t,    p, prefix) {
  p = index(t, ")")
  if (p <= 1) return 0
  prefix = substr(t, 1, p - 1)
  if (prefix ~ /[ \t=$();&`]/) return 0
  return 1
}

# ---- W-for / W-set / W-arg: any BARE (post-mask) parameter expansion not on the right of a plain
# assignment (VAR=$VALUE never word-splits in either shell — that exclusion is correct shell
# semantics, not a heuristic).
function has_bare_var(masked,    pos, rest, mstart, before) {
  rest = masked
  pos = 0
  while (match(rest, /\$([A-Za-z_][A-Za-z0-9_]{0,}|\{[^}]{1,}\})/)) {
    mstart = pos + RSTART
    before = substr(masked, 1, mstart - 1)
    if (before !~ /[A-Za-z_][A-Za-z0-9_]{0,}=$/) return 1
    pos = mstart + RLENGTH - 1
    rest = substr(masked, pos + 1)
  }
  return 0
}

# ---- G-glob: a whitespace-delimited token containing `*` or `?` that does NOT start with `$` —
# the `$` exclusion is what keeps `$?` (exit status) and `$*`/`$@` from misreading as globs. A
# leading `NAME=` assignment prefix is stripped first, so `_rc=$?` is judged on `$?` (excluded),
# never on the glued token `_rc=$?` (which does not start with `$` and would otherwise misread).
function has_glob_word(s,    n, i, tok, arr) {
  n = split(s, arr, /[ \t]{1,}/)
  for (i = 1; i <= n; i++) {
    tok = arr[i]
    sub(/^[A-Za-z_][A-Za-z0-9_]{0,}=/, "", tok)
    if (tok == "") continue
    if (substr(tok, 1, 1) == "$") continue
    if (tok ~ /[*?]/) return 1
  }
  return 0
}

function emit(cls, ln, text) { printf "%s\t%d\t%s\n", cls, ln, text }

BEGIN { in_hd = 0; hd_marker = "" }

{
  raw = $0
  bl = NR

  if (in_hd) {
    t = raw
    sub(/^\t+/, "", t)
    if (t == hd_marker) in_hd = 0
    next
  }

  trimmed = raw
  sub(/^[ \t]+/, "", trimmed)
  if (substr(trimmed, 1, 1) == "#") next

  masked = mask_line(raw)

  hd = detect_heredoc_marker(raw)
  if (hd != "") { in_hd = 1; hd_marker = hd }

  disp = raw
  sub(/^[ \t]+/, "", disp); sub(/[ \t]+$/, "", disp)

  is_for = (masked ~ /(^|[ \t;])for[ \t]{1,}[A-Za-z_][A-Za-z0-9_]{0,}[ \t]{1,}in[ \t]{1,}\$/)
  is_set = (masked ~ /(^|[ \t;])set[ \t]{1,}--[ \t]{1,}\$/)

  if (is_for) { emit("W-for", bl, disp) }
  else if (is_set) { emit("W-set", bl, disp) }
  else if (has_bare_var(masked)) { emit("W-arg", bl, disp) }

  if (!is_case_arm(trimmed) && has_glob_word(masked)) { emit("G-glob", bl, disp) }

  if (match(raw, /(^|[ \t;&|(])echo([ \t]|$)/)) {
    erest = substr(raw, RSTART + RLENGTH)
    etrim = erest
    sub(/^[ \t]+/, "", etrim)
    if (etrim !~ /^-[a-zA-Z]{0,}e/) {
      if (erest ~ /\\[tnrabefv0]/) { emit("E-echo", bl, disp) }
    }
  }

  if (masked ~ /(^|[ \t;&|(])(shopt|mapfile|readarray)([ \t]|$)/) { emit("B-builtin", bl, disp) }

  if (raw ~ /\$\{?BASH_[A-Za-z_]{1,}/) { emit("B-var", bl, disp) }

  if (masked ~ /(^|[ \t;&|(])(declare|typeset)([ \t]|$)/) { emit("B-declare", bl, disp) }

  if (masked ~ /[A-Za-z_][A-Za-z0-9_]{0,}=\(/ || raw ~ /\$\{#?[A-Za-z_][A-Za-z0-9_]{0,}\[/) {
    emit("A-array", bl, disp)
  }
}
AWKEOF

awk -f "$TMPD/scan.awk"
exit 0
