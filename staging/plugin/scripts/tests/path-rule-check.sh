#!/bin/bash
# path-rule-check.sh v1.0 — a derived guard for concept-to-code's own stated PATH RULE (issue
# #286, ADR-0117). ADR-0028 (issue #32) enforced the rule at five named call sites and disclosed
# a sixth, deferring it because the SPEC and orchestrator brief both presented the population as a
# closed, counted list. It never was: five more call sites were written by ADR-0099 three weeks
# later, with no reason to know the rule existed. This checker re-derives the population every
# time it runs instead of trusting a count written down once.
#
# THIS IS A CHECKER, NOT A REPORTER. The caller branches on the exit code. It prints no `CLEAN`
# sentinel and must NEVER grow one: weakening-scan.sh is a REPORTER (always exits 0, signals on
# stdout only), and the two idioms have already been confused once in this repository at a single
# call site (ADR-0048, "two adjacent gates, two opposite caller idioms"). Do not copy one block's
# branching into the other.
#
# USAGE
#   path-rule-check.sh <skill-md> <helper-scripts-dir>
#
# The file is an ARGUMENT, deliberately: a later issue can point this at autopilot-build/SKILL.md
# or project-conductor/SKILL.md without editing this script (ADR-0117 §3.9 — those skills are out
# of THIS SPEC's scope, but the mechanism is not tied to concept-to-code by name).
#
# DERIVATION. Helper basenames come from `<helper-scripts-dir>/manifest-*.sh` at run time, NEVER a
# hardcoded list — a helper added tomorrow (manifest-entry-state.sh was, by ADR-0109, after
# ADR-0028's own inventory) must be in scope without anyone remembering to add it.
#
# SCANNING IS BY LITERAL index(), NEVER A BUILT REGEX. Building an alternation from derived names
# is how ADR-0093 shipped a rule that silently matched nothing: BSD grep rejects an empty ERE
# alternative and the whole sweep then reads as clean. Literal substring matching has no escaping
# surface and no empty-alternative failure mode.
#
# PREDICATE, applied in this order per occurrence, after the line is truncated at the first
# `<!-- path-rule-exempt:` (ADR-0082's skip-your-own-declaration rule — without the truncation a
# waiver's own reason text could satisfy itself, rule 12):
#   1. COMPLIANT/absolute   — immediately preceded by one of the three absolute-path prefixes.
#   2. COMPLIANT/comment    — the line's first non-blank character is `#`.
#   3. FINDING/invocation   — any of: preceding text ends `scripts/`; char before is not a
#                             backtick; char after is not a backtick; the normalised word before
#                             an opening backtick is an invocation verb.
#   4. COMPLIANT/prose      — otherwise: a bare code span, nothing after it, no verb before it.
# An invocation-shaped occurrence on a line carrying the waiver marker is WAIVED, not a finding.
# A marked line with zero waived occurrences is a STALE-WAIVER finding (ADR-0081 §ZA4 — a stale
# waiver reads exactly like clean coverage). A reason under 40 characters is a SHORT-REASON
# finding.
#
# RESIDUAL BLIND SPOT (stated per ADR-0117 §4 Negative, on purpose): the verb set below is a list,
# and a call site written with an invocation verb outside it passes uncaught. A green run means "no
# *recognised* invocation shape is bare", not "no bare call site exists". The comment-line
# exemption is also broader than fenced code: any line whose first non-blank character is `#` is
# skipped, markdown headings included.
#
# EXIT CONTRACT
#   0  no findings. stdout is EMPTY.
#   1  one or more findings, one per line on stdout.
#   2  bad invocation: wrong argument count, unreadable skill file, missing/unreadable helper dir.
#   3  DID NOT RUN: the helper derivation produced zero basenames. Distinct from 0 — a derivation
#      that silently stops resolving must never read as a clean file (ADR-0085: count-guard the
#      denominator, not the matches).
#
# Always printed to STDERR, on every run regardless of exit code:
#   path-rule-check: helpers=<n> occurrences=<n> compliant=<n> waived=<n> findings=<n>
#
# Bash 3.2 / BSD-tools clean. Run: bash path-rule-check.sh <skill-md> <helper-dir>

if [ "$#" -ne 2 ]; then
  echo "path-rule-check: usage: path-rule-check.sh <skill-md> <helper-scripts-dir>" >&2
  echo "path-rule-check: helpers=0 occurrences=0 compliant=0 waived=0 findings=0" >&2
  exit 2
fi

SKILL_MD="$1"
HELPER_DIR="$2"

if [ ! -f "$SKILL_MD" ] || [ ! -r "$SKILL_MD" ]; then
  echo "path-rule-check: skill file not readable: $SKILL_MD" >&2
  echo "path-rule-check: helpers=0 occurrences=0 compliant=0 waived=0 findings=0" >&2
  exit 2
fi

if [ ! -d "$HELPER_DIR" ]; then
  echo "path-rule-check: helper scripts dir not found: $HELPER_DIR" >&2
  echo "path-rule-check: helpers=0 occurrences=0 compliant=0 waived=0 findings=0" >&2
  exit 2
fi

# Derive helper basenames from the directory at run time. Never hardcode.
HELPERS=""
HCOUNT=0
for f in "$HELPER_DIR"/manifest-*.sh; do
  [ -e "$f" ] || continue
  b="$(basename "$f")"
  if [ -z "$HELPERS" ]; then
    HELPERS="$b"
  else
    HELPERS="$HELPERS $b"
  fi
  HCOUNT=$((HCOUNT + 1))
done

if [ "$HCOUNT" -eq 0 ]; then
  echo "path-rule-check: DID NOT RUN -- zero helper basenames derived from $HELPER_DIR" >&2
  echo "path-rule-check: helpers=0 occurrences=0 compliant=0 waived=0 findings=0" >&2
  exit 3
fi

RESULT="$(
  awk -v helpers="$HELPERS" -v hcount="$HCOUNT" '
    BEGIN {
      nh = split(helpers, harr, " ")

      nverbs = split("via call calls calling invoke invokes invoking run runs running use uses using execute executes", varr, " ")
      for (i = 1; i <= nverbs; i++) verbset[varr[i]] = 1

      prefixes[1] = "~/.claude/skills/concept-to-code/scripts/"
      prefixes[2] = "$HOME/.claude/skills/concept-to-code/scripts/"
      prefixes[3] = "$_c2c/"

      occurrences = 0
      compliant = 0
      waived = 0
      findings = 0
    }

    function ends_with(s, suf,    ls, lu) {
      ls = length(s); lu = length(suf)
      if (lu == 0 || lu > ls) return 0
      return (substr(s, ls - lu + 1) == suf)
    }

    function is_absolute_prefixed(pre,    p) {
      for (p = 1; p <= 3; p++) {
        if (ends_with(pre, prefixes[p])) return 1
      }
      return 0
    }

    function normalise_word(w) {
      if (substr(w, length(w), 1) == "`") w = substr(w, 1, length(w) - 1)
      gsub(/^[(*]+/, "", w)
      gsub(/[.,:*]+$/, "", w)
      w = tolower(w)
      return w
    }

    function last_field(s,    n, arr2) {
      n = split(s, arr2, /[ \t]+/)
      if (n == 0) return ""
      return arr2[n]
    }

    {
      line = $0
      orig = $0
      nr = NR

      # ADR-0082: truncate at the first waiver-marker declaration before scanning. The reason
      # text a marker carries must never contribute occurrences to itself (rule 12).
      marker_pos = index(line, "<!-- path-rule-exempt:")
      is_marked = (marker_pos > 0)
      if (is_marked) {
        reason = substr(orig, marker_pos)
        sub(/^<!-- path-rule-exempt:[ \t]*/, "", reason)
        sub(/[ \t]*-->.*$/, "", reason)
        scan_text = substr(line, 1, marker_pos - 1)
      } else {
        scan_text = line
      }

      # COMPLIANT/comment applies to the whole line, first non-blank char.
      trimmed = orig
      sub(/^[ \t]+/, "", trimmed)
      is_comment_line = (substr(trimmed, 1, 1) == "#")

      line_waived_count = 0

      # scan every helper basename, every occurrence, left to right
      for (hi = 1; hi <= nh; hi++) {
        bn = harr[hi]
        blen = length(bn)
        search = scan_text
        base_offset = 0
        while (1) {
          p = index(search, bn)
          if (p == 0) break
          abs_pos = base_offset + p
          pre = substr(scan_text, 1, abs_pos - 1)
          after_char = substr(scan_text, abs_pos + blen, 1)
          before_char = (abs_pos > 1) ? substr(scan_text, abs_pos - 1, 1) : ""

          occurrences++

          if (is_absolute_prefixed(pre)) {
            compliant++
          } else if (is_comment_line) {
            compliant++
          } else {
            is_finding = 0
            if (ends_with(pre, "scripts/")) is_finding = 1
            if (before_char != "`") is_finding = 1
            if (after_char != "`") is_finding = 1
            if (before_char == "`") {
              word_text = substr(pre, 1, length(pre) - 1)
              sub(/[ \t]+$/, "", word_text)
              w = normalise_word(last_field(word_text))
              if (w in verbset) is_finding = 1
            }

            if (is_finding) {
              if (is_marked) {
                waived++
                line_waived_count++
              } else {
                findings++
                printf("%d: FINDING %s -- %s\n", nr, bn, trimmed)
              }
            } else {
              compliant++
            }
          }

          # advance search past this occurrence
          base_offset = abs_pos + blen - 1
          search = substr(scan_text, base_offset + 1)
        }
      }

      if (is_marked) {
        if (line_waived_count == 0) {
          findings++
          printf("%d: STALE-WAIVER %s\n", nr, trimmed)
        }
        rl = reason
        sub(/^[ \t]+/, "", rl)
        sub(/[ \t]+$/, "", rl)
        if (length(rl) < 40) {
          findings++
          printf("%d: SHORT-REASON %s\n", nr, trimmed)
        }
      }
    }

    END {
      printf("path-rule-check: helpers=%d occurrences=%d compliant=%d waived=%d findings=%d\n", hcount, occurrences, compliant, waived, findings) > "/dev/stderr"
    }
  ' "$SKILL_MD"
)"
AWK_STATUS=$?

if [ "$AWK_STATUS" -ne 0 ]; then
  echo "path-rule-check: internal error running awk over $SKILL_MD" >&2
  echo "path-rule-check: helpers=$HCOUNT occurrences=0 compliant=0 waived=0 findings=0" >&2
  exit 2
fi

if [ -n "$RESULT" ]; then
  printf '%s\n' "$RESULT"
  exit 1
fi

exit 0
