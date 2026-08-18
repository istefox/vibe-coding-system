#!/usr/bin/env bash
# ledger-merge.sh — compose the next TODO.md and print it. A pure filter.
#
# Reads the ledger, writes a CANDIDATE to stdout. IT NEVER WRITES THE LEDGER,
# on any path, including its failure paths. The one file it does write is the
# one the caller names with --proposals, which is a separate output stream by
# contract: proposals are not multiplexed onto stdout, because stdout carries a
# file the caller is expected to be able to diff.
#
# THE CONTRACT: the output is byte-identical to the input EXCEPT inside three
# regions —
#   1. the `GitHub Issues` section
#   2. each entry's provenance comment (runs:, promote:) — NEVER opened:, NEVER src:
#   3. the `Steps — <feature>` section header, and the one-line notice that stands
#      in for it when the section is omitted
# Everything else passes through unread: unknown sections, free prose,
# hand-written entries with no id, every HTML comment that is not one of this
# script's own notices. NT16 is that contract, and ADR-0153 §D2's whole safety
# argument rests on it. Do not relax it to accommodate a new section.
#
# Region 3 includes the omission notice, which is a reading and not a quotation:
# the SPEC says the section is omitted and the ledger says why in one line, and
# an HTML comment is what makes that line idempotent across runs. A visible line
# would be a FOURTH region, and re-running would accumulate copies of it.
#
#   0  clean
#   2  bad invocation
#   3  could not evaluate / self-check failed
#
# --p1-gate is a CHECKER with its own codes, because its caller in
# concept-to-code branches on them (rule 5):
#   0  no open P1 at all
#   1  at least one P1 opened on or after --since — the commit gate blocks
#   5  only pre-existing P1s — reported, does not block
# 5 rather than a second use of 2 or 3: a gate that cannot distinguish "you just
# introduced this" from "I could not evaluate" is a gate that blocks on its own
# malfunction.
#
# Usage: bash ledger-merge.sh --ledger FILE [--issues TSV] [--manifests DIR]
#                             [--roadmap FILE] [--today YYYY-MM-DD]
#                             [--mode full|quick|add|close|map] [--proposals FILE]
#                             [--promote ID=NNN] [--promote-declined ID]
#                             [--p1-gate --since YYYY-MM-DD]
#
# Bash 3.2 driving awk. No python3, no jq (ADR-0153 alternatives 3 and 4).
set -u

LEDGER=""; ISSUES=""; MANIFESTS=""; ROADMAP=""; TODAY=""; MODE="full"
PROPOSALS=""; PROMOTE=""; PROMOTE_DECLINED=""; P1GATE=0; SINCE=""

die_usage() {
  echo "ledger-merge.sh: $1" >&2
  echo "usage: bash ledger-merge.sh --ledger FILE [--issues TSV] [--manifests DIR] [--roadmap FILE]" >&2
  echo "       [--today YYYY-MM-DD] [--mode full|quick|add|close|map] [--proposals FILE]" >&2
  echo "       [--promote ID=NNN] [--promote-declined ID] [--p1-gate --since YYYY-MM-DD]" >&2
  exit 2
}
need() { [ "$1" -ge 2 ] || die_usage "$2 needs a value"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --ledger)            need $# --ledger;            LEDGER="$2";           shift 2 ;;
    --issues)            need $# --issues;            ISSUES="$2";           shift 2 ;;
    --manifests)         need $# --manifests;         MANIFESTS="$2";        shift 2 ;;
    --roadmap)           need $# --roadmap;           ROADMAP="$2";          shift 2 ;;
    --today)             need $# --today;             TODAY="$2";            shift 2 ;;
    --mode)              need $# --mode;              MODE="$2";             shift 2 ;;
    --proposals)         need $# --proposals;         PROPOSALS="$2";        shift 2 ;;
    --promote)           need $# --promote;           PROMOTE="$2";          shift 2 ;;
    --promote-declined)  need $# --promote-declined;  PROMOTE_DECLINED="$2"; shift 2 ;;
    --since)             need $# --since;             SINCE="$2";            shift 2 ;;
    --p1-gate)           P1GATE=1; shift ;;
    -h|--help)           sed -n '2,46p' "$0"; exit 0 ;;
    *)                   die_usage "unknown argument: $1" ;;
  esac
done

[ -n "$LEDGER" ] || die_usage "--ledger is required"
[ -f "$LEDGER" ] || { echo "ledger-merge.sh: ledger does not exist: $LEDGER" >&2; exit 3; }
case "$MODE" in full|quick|add|close|map) : ;; *) die_usage "unknown --mode: $MODE" ;; esac

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# The sections whose entries are OPEN work. Done, Project Map and GitHub Issues
# are deliberately absent: a closed entry does not survive a run, it survived it
# once and stopped, and incrementing runs: there would grow a number nobody reads.
OPEN_SECTION_RE='^## (Open Issues|In Progress|Backlog|Blocked)'

# --- --p1-gate ---------------------------------------------------------------
if [ "$P1GATE" -eq 1 ]; then
  [ -n "$SINCE" ] || die_usage "--p1-gate needs --since YYYY-MM-DD"
  awk -v since="$SINCE" -v secre="$OPEN_SECTION_RE" '
    $0 ~ secre { inopen = 1; next }
    /^## /     { inopen = 0 }
    !inopen    { next }
    /^- \[[ x]\] / && /\*\*P1\*\*/ {
      id = ""; if (match($0, /`[A-Za-z]+-[0-9]+`/)) id = substr($0, RSTART+1, RLENGTH-2)
      op = ""; if (match($0, /opened:[0-9-]+/))     op = substr($0, RSTART+7, RLENGTH-7)
      if (id == "") next
      # A date compares correctly as a string only in ISO form, which is the one
      # form opened: is ever written in.
      if (op != "" && op >= since) { new = new (new=="" ? "" : " ") id }
      else                         { old = old (old=="" ? "" : " ") id }
    }
    END {
      if (new != "") { print "P1-NEW\t" new; if (old != "") print "P1-PRE\t" old; exit 1 }
      if (old != "") { print "P1-PRE\t" old; exit 5 }
      print "P1-NONE"; exit 0
    }' "$LEDGER"
  exit $?
fi

# --- the issue payload -------------------------------------------------------
ISSUE_COUNT=0; DIDNOTRUN_COUNT=0
: > "$WORK/issues"; : > "$WORK/didnotrun"
if [ -n "$ISSUES" ]; then
  [ -f "$ISSUES" ] || { echo "ledger-merge.sh: --issues file does not exist: $ISSUES" >&2; exit 3; }
  grep '^ISSUE' "$ISSUES" > "$WORK/issues" 2>/dev/null || true
  grep '^DIDNOTRUN' "$ISSUES" > "$WORK/didnotrun" 2>/dev/null || true
  ISSUE_COUNT=$(grep -c . "$WORK/issues" || true)
  DIDNOTRUN_COUNT=$(grep -c . "$WORK/didnotrun" || true)
fi

# --- the roadmap phase map ---------------------------------------------------
# A row's phase is the heading above it. Absent file and present-with-no-match are
# THREE states away from each other in what they mean and one state apart in what
# they render, which is why the absent case gets its own notice (rule 7).
: > "$WORK/phases"
ROADMAP_STATE="none"
if [ -n "$ROADMAP" ]; then
  if [ -f "$ROADMAP" ]; then
    ROADMAP_STATE="present"
    awk '
      /^## / { ph = $0; sub(/^## /, "", ph); sub(/ [-—].*$/, "", ph); gsub(/[[:space:]]+$/, "", ph); next }
      /^- \[[ x~]\] / {
        s = $0
        while (match(s, /#[0-9]+/)) { print substr(s, RSTART+1, RLENGTH-1) "\t" ph; s = substr(s, RSTART+RLENGTH) }
      }' "$ROADMAP" > "$WORK/phases"
  else
    ROADMAP_STATE="missing"
  fi
fi

# --- the manifests case ------------------------------------------------------
# Terminality is TWO fields (ADR-0113): status: aborted is terminal even when
# current_step is not. A missing directory is a third state, distinct from a
# directory holding zero non-terminal manifests — NT29b is that distinction.
MAN_STATE="none"; MAN_NAMES=""; MAN_FILE=""; MAN_N=0
if [ -n "$MANIFESTS" ]; then
  if [ -d "$MANIFESTS" ]; then
    for _m in "$MANIFESTS"/*.manifest.yml; do
      [ -f "$_m" ] || continue
      _cs=$(awk -F'"' '/^current_step:/{print $2}' "$_m" | head -1)
      _st=$(awk -F'"' '/^status:/{print $2}' "$_m" | head -1)
      case "$_st" in completed|aborted|failed) continue ;; esac
      case "$_cs" in completed|aborted) continue ;; esac
      # `topic:`, measured, not `topic_slug:`, assumed. 61 of 61 manifests in this
      # repository's corpus carry `topic:` and 0 carry `topic_slug:` (2026-08-18), so the
      # first version of this line read a field that exists nowhere and every manifest
      # fell through to the basename. Rule 13: measure the premise before designing on it.
      _slug=$(awk -F'"' '/^topic:/{print $2}' "$_m" | head -1)
      [ -n "$_slug" ] || _slug=$(basename "$_m")
      MAN_NAMES="$MAN_NAMES${MAN_NAMES:+, }$_slug"
      MAN_FILE=$(basename "$_m")
      MAN_N=$((MAN_N+1))
    done
    case "$MAN_N" in 0) MAN_STATE="zero" ;; 1) MAN_STATE="one" ;; *) MAN_STATE="many" ;; esac
  else
    MAN_STATE="missing"
  fi
fi

# --- the promoted entry ------------------------------------------------------
PROMOTE_ID=""; PROMOTE_NUM=""
if [ -n "$PROMOTE" ]; then
  PROMOTE_ID="${PROMOTE%%=*}"; PROMOTE_NUM="${PROMOTE#*=}"
  { [ -n "$PROMOTE_ID" ] && [ -n "$PROMOTE_NUM" ] && [ "$PROMOTE_ID" != "$PROMOTE" ]; } \
    || die_usage "--promote takes ID=NNN"
fi
[ -n "$TODAY" ] || TODAY=""

# --- render the GitHub Issues section body -----------------------------------
: > "$WORK/section"
SECTION_MODE="untouched"
if [ -n "$ISSUES" ]; then
  if [ "$DIDNOTRUN_COUNT" -gt 0 ] && [ "$ISSUE_COUNT" -eq 0 ]; then
    # The read could not run. The entries already here are EVIDENCE and stay
    # exactly as they are; the section is never rendered empty and never
    # silently skipped (rule 4). The notice carries the cause and the remedy the
    # producer supplied, so a reworded remedy travels without an edit here.
    SECTION_MODE="did-not-run"
    awk '/^## GitHub Issues/{f=1; next} /^## /{f=0} f' "$LEDGER" > "$WORK/section"
    awk -F'\t' '{printf "<!-- github-read: DID-NOT-RUN cause:%s remedy:%s -->\n", $2, $3}' \
      "$WORK/didnotrun" >> "$WORK/section"
  else
    SECTION_MODE="rendered"
    awk -F'\t' -v phfile="$WORK/phases" '
      BEGIN { while ((getline l < phfile) > 0) { split(l, p, "\t"); phase[p[1]] = p[2] } }
      /^ISSUE/ {
        n = $2; st = $3; ti = $4; lb = $5
        ptr = (n in phase && phase[n] != "") ? " — " phase[n] : ""
        printf "- [ ] `#%s` %s%s <!-- src:github state:%s labels:%s -->\n", n, ti, ptr, st, lb
      }' "$WORK/issues" | sort -t'#' -k2 -n >> "$WORK/section"
  fi
fi

# --- the main pass -----------------------------------------------------------
awk -v secre="$OPEN_SECTION_RE" \
    -v mode="$MODE" -v today="$TODAY" \
    -v promote_id="$PROMOTE_ID" -v promote_num="$PROMOTE_NUM" \
    -v declined_id="$PROMOTE_DECLINED" \
    -v section_mode="$SECTION_MODE" -v secfile="$WORK/section" \
    -v man_state="$MAN_STATE" -v man_names="$MAN_NAMES" -v man_file="$MAN_FILE" -v man_dir="$MANIFESTS" \
    -v road_state="$ROADMAP_STATE" -v road_file="$ROADMAP" '
function entry_id(l,   r) { r = ""; if (match(l, /`[A-Za-z]+-[0-9]+`/)) r = substr(l, RSTART+1, RLENGTH-2); return r }
function has_comment(l) { return (l ~ /<!--/ && l ~ /-->/) }
function bump_runs(l,   n) {
  if (!has_comment(l)) return l
  if (match(l, /runs:[0-9]+/)) {
    n = substr(l, RSTART+5, RLENGTH-5) + 1
    return substr(l, 1, RSTART-1) "runs:" n substr(l, RSTART+RLENGTH)
  }
  sub(/[[:space:]]*-->/, " runs:1 -->", l)
  return l
}
function set_promote(l, v) {
  if (!has_comment(l)) return l
  if (match(l, /promote:[^ >]+/)) return substr(l, 1, RSTART-1) "promote:" v substr(l, RSTART+RLENGTH)
  sub(/[[:space:]]*-->/, " promote:" v " -->", l)
  return l
}
function disk_runs(l,   n) { n = 0; if (match(l, /runs:[0-9]+/)) n = substr(l, RSTART+5, RLENGTH-5) + 0; return n }
BEGIN { insec = 0; inopen = 0; made = 0 }
# This script owns exactly three notice comments. Dropping them on read is what
# makes a re-run idempotent instead of accumulating a copy per run.
/^<!-- (github-read|steps|roadmap): / { next }
/^## GitHub Issues/ {
  print
  insec = 1; inopen = 0; made = 1
  if (section_mode != "untouched") { while ((getline l < secfile) > 0) print l; close(secfile) }
  next
}
/^## / {
  # A ledger with NO GitHub Issues section is every ledger written before this feature
  # existed, and the section has to be CREATED rather than assumed. Without this the
  # rendered body had no header to follow and was dropped in silence; the self-check
  # caught it on the first real ledger, and no fixture had it because every fixture was
  # written after the section existed.
  if (!made && section_mode != "untouched") {
    print "## GitHub Issues"
    print ""
    while ((getline l < secfile) > 0) print l
    close(secfile)
    print ""
    made = 1
  }
  if (insec) insec = 0
  inopen = ($0 ~ secre) ? 1 : 0
  print
  next
}
insec && section_mode != "untouched" { next }
{
  line = $0
  if (inopen && line ~ /^- \[[ x]\] /) {
    id = entry_id(line)
    if (id != "") {
      if (promote_id != "" && id == promote_id) {
        line = bump_runs(line)
        line = set_promote(line, (today != "" ? today : "yes"))
        promoted_line = line
        promoted_id = id
        next
      }
      if (declined_id != "" && id == declined_id) line = set_promote(line, "declined")
      if (mode == "full") {
        if (line ~ /\*\*P1\*\*/ || line ~ /src:review/ || disk_runs(line) >= 2) {
          if (line !~ /promote:/) props = props id "\n"
        }
        line = bump_runs(line)
      }
    }
  }
  print line
}
END {
  if (promoted_line != "") print "PROMOTED\t" promoted_line > "/dev/stderr"
  if (props != "") printf "%s", props > "/dev/stderr"
}' "$LEDGER" > "$WORK/pass1" 2> "$WORK/side"

# The promoted line and the proposal ids travel on stderr out of the awk pass and
# are separated here. awk has one stdout and this pass owns it for the candidate.
PROMOTED_LINE=$(grep '^PROMOTED	' "$WORK/side" 2>/dev/null | sed 's/^PROMOTED	//')
grep -v '^PROMOTED	' "$WORK/side" 2>/dev/null | grep -E '^[A-Za-z]+-[0-9]+$' > "$WORK/props" || true

# --- the promoted entry joins the GitHub Issues section ----------------------
if [ -n "$PROMOTE_ID" ] && [ -n "$PROMOTED_LINE" ]; then
  # Strip, in order: the checkbox, the backticked local id, the priority marker and
  # the trailing provenance comment. Leaving the id in was the first defect this
  # script's own self-check caught, before any assertion did: the rendered line
  # carried `VCS-031` twice and the run refused itself with exit 3.
  _title=$(printf '%s' "$PROMOTED_LINE" \
    | sed -e 's/^- \[[ x]\] //' -e 's/^`[A-Za-z]*-[0-9]*` *//' -e 's/^\*\*P[0-9]\*\* *//' -e 's/ *<!--.*$//')
  # "regenerated from GitHub" when the payload knows the number, the local text when
  # it does not — a promotion can name an issue this run never read.
  _gh_title=$(awk -F'\t' -v n="$PROMOTE_NUM" '$1=="ISSUE" && $2==n {print $4; exit}' "$WORK/issues")
  [ -n "$_gh_title" ] && _title="$_gh_title"
  _prio=$(printf '%s' "$PROMOTED_LINE" | grep -oE '\*\*P[0-9]\*\*' | head -1)
  _prov=$(printf '%s' "$PROMOTED_LINE" | grep -oE '<!--.*-->' | head -1)
  _new="- [ ] \`$PROMOTE_ID\` → #$PROMOTE_NUM $_prio $_title $_prov"
  awk -v ins="$_new" '/^## GitHub Issues/{print; print ins; next} {print}' "$WORK/pass1" > "$WORK/pass2"
else
  cp "$WORK/pass1" "$WORK/pass2"
fi

# --- the notices -------------------------------------------------------------
# Appended at the end so nothing above them moves. Emitted only when the caller
# asked the question: with no --manifests and no --roadmap there is no question
# and therefore no answer, which is what keeps NT16's pass-through exact.
# The Steps block is region 3: either the header, when there is something to head,
# or the one-line notice that stands in for it. One non-terminal manifest names it
# and reads derived; two or more name the candidates and derive nothing, because
# guessing which feature is "the" one in flight is the ambiguity the rest of this
# system refuses.
: > "$WORK/steps"
case "$MAN_STATE" in
  one)     printf '## Steps — %s (derived from %s)\n\n' "$MAN_NAMES" "$MAN_FILE" > "$WORK/steps" ;;
  many)    printf '## Steps — ambiguous (candidates: %s) — nothing derived\n\n' "$MAN_NAMES" > "$WORK/steps" ;;
  missing) printf '<!-- steps: no manifests directory at %s — section omitted -->\n' "$MANIFESTS" > "$WORK/steps" ;;
  zero)    printf '<!-- steps: no non-terminal manifest under %s — section omitted -->\n' "$MANIFESTS" > "$WORK/steps" ;;
esac

# It goes where the declared section order puts it — before Project Map — and not at
# the end of the file. Appending was the first shape and it put the section after
# Done, which is the one place a reader has already stopped looking.
if [ -s "$WORK/steps" ] && grep -q '^## Project Map' "$WORK/pass2"; then
  awk -v f="$WORK/steps" '/^## Project Map/ && !done { while ((getline l < f) > 0) print l; close(f); done = 1 } {print}' \
    "$WORK/pass2" > "$WORK/pass3"
else
  cat "$WORK/pass2" > "$WORK/pass3"
  [ -s "$WORK/steps" ] && cat "$WORK/steps" >> "$WORK/pass3"
fi

case "$ROADMAP_STATE" in
  missing) echo "<!-- roadmap: no roadmap file at $ROADMAP — phase pointers omitted -->" >> "$WORK/pass3" ;;
esac

# --- the self-check ----------------------------------------------------------
# Before exit, not after, and it names what it found. A short section that exits
# 0 is the failure this guards: the caller would commit it.
SELF_ERR=""
if [ "$SECTION_MODE" = "rendered" ]; then
  while IFS=$'\t' read -r _tag _n _rest; do
    [ "$_tag" = "ISSUE" ] || continue
    # Count RENDERINGS, not mentions - the same defect as the duplicate check one level
    # down, and found the same way. An issue whose title cites another issue number puts
    # that number inside the section: on this repository #437's title names #426 and
    # #309, so both reported "renders 2 times" against a section that rendered each once.
    # A rendering is the line whose LEADING token is the issue, which is also why a
    # promoted local entry - whose leading token is its local id - is not counted here.
    _c=$(awk '/^## GitHub Issues/{f=1; next} /^## /{f=0} f' "$WORK/pass3" \
         | grep -cE "^- \[[ x]\] \`#$_n\`" || true)
    [ "$_c" = "1" ] || SELF_ERR="$SELF_ERR issue #$_n renders $_c time(s)"
  done < "$WORK/issues"
fi
# Count DEFINITIONS, not mentions. An id is defined by standing at the head of an entry
# line; anywhere else it is a cross-reference, and this ledger is full of them - an entry
# routinely explains that it is blocked by another entry and names it. Counting every
# backticked id reported four false duplicates on this repository's own ledger, all four
# of them prose citations (rule 18: a scan is satisfied by the whole population it
# searches, not by the part it meant). The prefix is read from the header rather than
# assumed, so a foreign `ADR-0153` in an entry's text is outside the population by
# construction and not merely by luck.
PREFIX=$(sed -n 's/.*project-tasks:[[:space:]]*prefix=\([A-Za-z][A-Za-z]*\).*/\1/p' "$LEDGER" | head -1)
[ -n "$PREFIX" ] || PREFIX='[A-Za-z][A-Za-z]*'
DUP_IDS=$(grep -oE "^- \[[ x]\] \`$PREFIX-[0-9]+\`" "$WORK/pass3" \
          | grep -oE "$PREFIX-[0-9]+" | sort | uniq -d | tr '\n' ' ')
[ -z "$DUP_IDS" ] || SELF_ERR="$SELF_ERR local id(s) appearing more than once: $DUP_IDS"
if [ -n "$SELF_ERR" ]; then
  echo "ledger-merge.sh: self-check failed —$SELF_ERR" >&2
  exit 3
fi

# --- the proposals stream ----------------------------------------------------
if [ -n "$PROPOSALS" ]; then
  if [ "$MODE" = "full" ]; then sort -u "$WORK/props" > "$PROPOSALS"; else : > "$PROPOSALS"; fi
fi

cat "$WORK/pass3"
exit 0
