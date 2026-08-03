#!/bin/bash
# transition-pair-count.sh v1.0 — the single derivation of manifest-transition.sh's legal
# transition-pair count (issue #289, ADR-0120). Three ad-hoc derivations existed across three
# harness files and disagreed on three of five mutation fixtures (ADR-0120 M3): one deduped
# without bounding to the pair-building block, one bounded without deduping, one did neither.
# The correct rule matches the script's own runtime semantics — `grep -Fxq "$current_step,$new_step"
# "$PAIRS"` — which is BLOCK-BOUNDED (a pair-shaped line outside the block never reaches $PAIRS)
# AND DISTINCT (a duplicate line is a no-op). This file is the only place that decides what a
# transition pair is, the same role `plan-task-predicate.awk` plays for a plan task (ADR-0069) and
# `manifest-field-state.sh` plays for an additive manifest field (ADR-0076).
#
# THIS IS A CHECKER, NOT A REPORTER. The caller branches on the exit code. It prints no `CLEAN`
# sentinel and must NEVER grow one — the reporter/checker confusion this repository has already
# made once at a single call site (ADR-0048) and restated at a second (ADR-0117). Do not copy a
# reporter's always-exit-0 idiom into this file.
#
# EXCLUDED FROM THE COUNT, by decision (ADR-0120 M2):
#   - producer exemptions (`# transition-producer-exempt:` declarations, ADR-0095) — comments,
#     not pairs, emit nothing into $PAIRS. There are currently zero of them.
#   - the unconditional `any -> failed|aborted` wildcard — a separate branch that short-circuits
#     before $PAIRS is built. Counting it would mean one pair per reachable state, counted twice.
#
# USAGE
#   transition-pair-count.sh <transition-script> <skill-md>
#
# Both files are ARGUMENTS, deliberately (ADR-0117 §3.9): a later issue can point this at a
# different pair-owning script or a different SKILL.md without editing this file.
#
# DERIVATION. manifest-transition.sh's own pair-building block is opened by the literal line
# `PAIRS="$(mktemp)"` and closed by the literal line `if ! grep -Fxq` (both used only as index()
# substrings, never as a built regex — no escaping surface). Every line between them shaped
# `echo "<from>,<to>" >> "$PAIRS"` (or `>` for the block's first pair) is a candidate pair; a
# candidate already seen is a no-op, matching `grep -Fxq`'s own semantics; the running phase
# (standard / express / hybrid) flips on the script's own `# Express path transitions` /
# `# Hybrid path transitions` section comments, so a sub-count is only as strong as that comment
# surviving (see DISCLOSURES below).
#
# LITERAL SITES (three, ADR-0120 M4), each read via its own distinctive anchor, never a bare
# number:
#   - SKILL.md  "Legal transition pairs (<n> total — <n> standard + <n> express + <n> hybrid"
#   - SKILL.md  "atomically (<n> pairs)"
#   - manifest-transition.sh  "(spec §3.3, <n> transitions)"
# Each is compared against the derived total; the header's own triple is additionally checked for
# internal consistency (does it sum to its own stated total) and per sub-count against the
# derived per-block counts — this is what catches a SKILL.md self-contradiction mechanically
# (ADR-0120 D-A) rather than by a human noticing nine lines apart.
#
# EXIT CONTRACT
#   0  clean. stdout EMPTY.
#   1  one or more findings, one per line on stdout.
#   2  bad invocation: wrong argument count, unreadable target file.
#   3  DID NOT RUN: the block-bounded pair derivation produced zero pairs. Distinct from 0 —
#      renaming the block's opening/closing marker, or rewriting the pair block in a different
#      shell idiom (heredoc, array, loop), makes the derivation silently return 0, which must
#      never read as a clean parse of an empty machine (ADR-0085: count-guard the denominator,
#      not the matches).
#
# Always printed to STDERR, on every run regardless of exit code:
#   transition-pair-count: pairs=<n> standard=<n> express=<n> hybrid=<n> literals=<n> findings=<n>
#
# DISCLOSURES (stated here because a green run does not mean what it looks like):
#   - the extractor is coupled to the script's CURRENT shell idiom (a run of
#     `echo "a,b" >> "$PAIRS"` lines); rewriting the pair block in another form makes this exit 3,
#     loudly — never a silent 0.
#   - the block boundary strings (`PAIRS="$(mktemp)"`, `if ! grep -Fxq`) are now anchors in a file
#     nobody previously had to treat as anchored.
#   - the sub-count derivation rests on section COMMENTS, a weaker anchor than code: deleting the
#     `# Express path transitions` / `# Hybrid path transitions` line merges its pairs into the
#     preceding phase and produces a wrong sub-count alongside a right total — a finding, but one
#     whose message points at the wrong block.
#   - producer exemptions and the `any -> failed|aborted` wildcard are outside the count, by
#     decision (ADR-0095; ADR-0120 M2) — a stated scope boundary, not a gap.
#
# Placed under staging/plugin/scripts/tests/ deliberately, following path-rule-check.sh's
# precedent (ADR-0117 §3.9/D3): this directory sits outside pairs-completeness.test.sh's
# non-recursive plugin/scripts/*.sh population, and the file does not end in .test.sh, so
# .claude/test-cmd does not execute it directly. No PAIRS entry, no sync dependency.
#
# Bash 3.2 / BSD-tools clean. Run: bash transition-pair-count.sh <transition-script> <skill-md>
set -u

STATS_TOTAL=0
STATS_STD=0
STATS_EXP=0
STATS_HYB=0
STATS_LITERALS=3
STATS_FINDINGS=0

print_stats() {
  echo "transition-pair-count: pairs=$STATS_TOTAL standard=$STATS_STD express=$STATS_EXP hybrid=$STATS_HYB literals=$STATS_LITERALS findings=$STATS_FINDINGS" >&2
}

if [ "$#" -ne 2 ]; then
  echo "transition-pair-count: usage: transition-pair-count.sh <transition-script> <skill-md>" >&2
  print_stats
  exit 2
fi

TR="$1"
SKILL="$2"

if [ ! -f "$TR" ] || [ ! -r "$TR" ]; then
  echo "transition-pair-count: transition script not readable: $TR" >&2
  print_stats
  exit 2
fi

if [ ! -f "$SKILL" ] || [ ! -r "$SKILL" ]; then
  echo "transition-pair-count: skill file not readable: $SKILL" >&2
  print_stats
  exit 2
fi

FIND_FILE="$(mktemp)"
trap 'rm -f "$FIND_FILE"' EXIT

# -------------------------------------------------------------------------------------------
# DERIVATION — block-bounded AND distinct. Literal substring search via index()/substr() only.
# -------------------------------------------------------------------------------------------
DERIVED="$(
  awk '
    BEGIN { in_block = 0; phase = "standard"; total = 0; std = 0; xp = 0; hy = 0 }
    {
      if (index($0, "PAIRS=\"$(mktemp)\"") > 0) { in_block = 1; next }
      if (in_block && index($0, "if ! grep -Fxq") > 0) { in_block = 0 }
      if (!in_block) next

      if (index($0, "# Express path transitions") > 0) { phase = "express" }
      if (index($0, "# Hybrid path transitions") > 0) { phase = "hybrid" }

      s = $0
      while (length(s) > 0 && (substr(s, 1, 1) == " " || substr(s, 1, 1) == "\t")) s = substr(s, 2)
      if (substr(s, 1, 6) != "echo \"") next
      rest = substr(s, 7)
      q = index(rest, "\"")
      if (q == 0) next
      pair = substr(rest, 1, q - 1)
      if (index(pair, ",") == 0) next
      tail = substr(rest, q + 1)
      while (length(tail) > 0 && substr(tail, 1, 1) == " ") tail = substr(tail, 2)
      if (substr(tail, 1, 1) != ">") next
      if (index(tail, "\"$PAIRS\"") == 0) next

      if (!(pair in seen)) {
        seen[pair] = 1
        total++
        if (phase == "standard") std++
        else if (phase == "express") xp++
        else hy++
      }
    }
    END { printf "%d %d %d %d\n", total, std, xp, hy }
  ' "$TR"
)"

TOTAL_D="0"
STD_D="0"
EXP_D="0"
HYB_D="0"
read -r TOTAL_D STD_D EXP_D HYB_D <<EOF_DERIVED
$DERIVED
EOF_DERIVED
TOTAL_D="${TOTAL_D:-0}"
STD_D="${STD_D:-0}"
EXP_D="${EXP_D:-0}"
HYB_D="${HYB_D:-0}"

STATS_TOTAL="$TOTAL_D"
STATS_STD="$STD_D"
STATS_EXP="$EXP_D"
STATS_HYB="$HYB_D"

if [ "$TOTAL_D" -eq 0 ]; then
  echo "transition-pair-count: DID NOT RUN -- the block-bounded pair derivation produced zero pairs from $TR (block open/close marker not found, or the pair-building shell idiom changed)" >&2
  print_stats
  exit 3
fi

# -------------------------------------------------------------------------------------------
# LITERAL EXTRACTION — one distinctive anchor per shipping site. "x" is the not-found sentinel,
# distinct from a legitimate 0.
# -------------------------------------------------------------------------------------------
NUMBEFORE_FN='
  function numbefore(s, marker,   p, i, c, d) {
    p = index(s, marker)
    if (p == 0) return "x"
    i = p - 1; d = ""
    while (i >= 1) {
      c = substr(s, i, 1)
      if (c >= "0" && c <= "9") { d = c d; i-- } else break
    }
    if (d == "") return "x"
    return d
  }
'

HDR_LINE="$(grep -F 'Legal transition pairs (' "$SKILL" | head -1)"
HDR_PARSED="$(printf '%s\n' "$HDR_LINE" | awk "$NUMBEFORE_FN"'
  {
    pos = index($0, "Legal transition pairs (")
    if (pos == 0) { print "x x x x"; next }
    rest = substr($0, pos + length("Legal transition pairs ("))
    pe = index(rest, ")")
    scope = (pe > 0) ? substr(rest, 1, pe - 1) : rest
    t = numbefore(scope, " total")
    s2 = numbefore(scope, " standard")
    e = numbefore(scope, " express")
    h = numbefore(scope, " hybrid")
    print t, s2, e, h
  }
')"
HDR_TOTAL="x"; HDR_STD="x"; HDR_EXP="x"; HDR_HYB="x"
read -r HDR_TOTAL HDR_STD HDR_EXP HDR_HYB <<EOF_HDR
$HDR_PARSED
EOF_HDR
HDR_TOTAL="${HDR_TOTAL:-x}"
HDR_STD="${HDR_STD:-x}"
HDR_EXP="${HDR_EXP:-x}"
HDR_HYB="${HDR_HYB:-x}"

HELPER_LINE="$(grep -F 'atomically (' "$SKILL" | head -1)"
HELPER_TOTAL="$(printf '%s\n' "$HELPER_LINE" | awk "$NUMBEFORE_FN"'
  {
    pos = index($0, "atomically (")
    if (pos == 0) { print "x"; next }
    rest = substr($0, pos + length("atomically ("))
    pe = index(rest, ")")
    scope = (pe > 0) ? substr(rest, 1, pe - 1) : rest
    print numbefore(scope, " pairs")
  }
')"
HELPER_TOTAL="${HELPER_TOTAL:-x}"

COMMENT_LINE="$(grep -F '§3.3,' "$TR" | head -1)"
COMMENT_TOTAL="$(printf '%s\n' "$COMMENT_LINE" | awk '
  function numfromstart(s,   i, c, d) {
    i = 1; d = ""
    while (i <= length(s)) {
      c = substr(s, i, 1)
      if (c >= "0" && c <= "9") { d = d c; i++ } else break
    }
    if (d == "") return "x"
    return d
  }
  {
    pos = index($0, "§3.3,")
    if (pos == 0) { print "x"; next }
    rest = substr($0, pos + length("§3.3,"))
    while (length(rest) > 0 && substr(rest, 1, 1) == " ") rest = substr(rest, 2)
    print numfromstart(rest)
  }
')"
COMMENT_TOTAL="${COMMENT_TOTAL:-x}"

# -------------------------------------------------------------------------------------------
# COMPARISONS -> findings, one per line.
# -------------------------------------------------------------------------------------------

# A — header stated total vs derived total (site: "Legal transition pairs (<n> total").
if [ "$HDR_TOTAL" != "x" ] && [ "$HDR_TOTAL" -ne "$TOTAL_D" ]; then
  printf 'transition-pair-count: SKILL.md "Legal transition pairs (%s total" states %s, derived total is %s\n' \
    "$HDR_TOTAL" "$HDR_TOTAL" "$TOTAL_D" >>"$FIND_FILE"
fi

# B — header triple internal consistency (does it sum to its own stated total).
if [ "$HDR_TOTAL" != "x" ] && [ "$HDR_STD" != "x" ] && [ "$HDR_EXP" != "x" ] && [ "$HDR_HYB" != "x" ]; then
  _sum=$((HDR_STD + HDR_EXP + HDR_HYB))
  if [ "$_sum" -ne "$HDR_TOTAL" ]; then
    printf 'transition-pair-count: SKILL.md header triple %s standard + %s express + %s hybrid = %s does not sum to its own stated total %s\n' \
      "$HDR_STD" "$HDR_EXP" "$HDR_HYB" "$_sum" "$HDR_TOTAL" >>"$FIND_FILE"
  fi
fi

# C — per sub-count vs the derived per-block count (catches D-A mechanically).
if [ "$HDR_STD" != "x" ] && [ "$HDR_STD" -ne "$STD_D" ]; then
  printf 'transition-pair-count: SKILL.md header standard sub-count states %s, derived standard is %s\n' \
    "$HDR_STD" "$STD_D" >>"$FIND_FILE"
fi
if [ "$HDR_EXP" != "x" ] && [ "$HDR_EXP" -ne "$EXP_D" ]; then
  printf 'transition-pair-count: SKILL.md header express sub-count states %s, derived express is %s\n' \
    "$HDR_EXP" "$EXP_D" >>"$FIND_FILE"
fi
if [ "$HDR_HYB" != "x" ] && [ "$HDR_HYB" -ne "$HYB_D" ]; then
  printf 'transition-pair-count: SKILL.md header hybrid sub-count states %s, derived hybrid is %s\n' \
    "$HDR_HYB" "$HYB_D" >>"$FIND_FILE"
fi

# D — helper-description line vs derived total (site: "atomically (<n> pairs)").
if [ "$HELPER_TOTAL" != "x" ] && [ "$HELPER_TOTAL" -ne "$TOTAL_D" ]; then
  printf 'transition-pair-count: SKILL.md "atomically (%s pairs)" states %s, derived total is %s\n' \
    "$HELPER_TOTAL" "$HELPER_TOTAL" "$TOTAL_D" >>"$FIND_FILE"
fi

# E — manifest-transition.sh's own comment vs derived total (site: "(spec §3.3, <n> transitions)").
if [ "$COMMENT_TOTAL" != "x" ] && [ "$COMMENT_TOTAL" -ne "$TOTAL_D" ]; then
  printf 'transition-pair-count: manifest-transition.sh comment "(§3.3, %s transitions)" states %s, derived total is %s\n' \
    "$COMMENT_TOTAL" "$COMMENT_TOTAL" "$TOTAL_D" >>"$FIND_FILE"
fi

STATS_FINDINGS="$(wc -l <"$FIND_FILE" | tr -d ' ')"
STATS_FINDINGS="${STATS_FINDINGS:-0}"

if [ -s "$FIND_FILE" ]; then
  cat "$FIND_FILE"
  print_stats
  exit 1
fi

print_stats
exit 0
