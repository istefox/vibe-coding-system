#!/bin/bash
# fence-contract-coverage.test.sh — offline, hermetic, no network. Bash 3.2 clean.
# Targets staging/ directly, never the deployed $HOME/.claude/ copy.
# Run: bash fence-contract-coverage.test.sh
#
# THE RULE — a bash fence in a SKILL.md that can ABORT a run must declare itself, and a fence
# that declares itself a CONTRACT must be executed by a test. Issue #206.
#
# Rule 11: a prose code block nobody has executed is unverified code. The receipt is issue #174 —
# `autopilot-build` check 5 read a leading dash as a getopt OPTION, exited 2 without running, and
# aborted on EVERY plan. That block had sat in the file through several audits, read by humans,
# looking correct. Nine more fences were in exactly that position: code, on a path that stops work
# when it misfires, executed by nothing.
#
# THE DECLARATION. Immediately above the fence opener (nearest non-blank line):
#
#     <!-- fence-contract: <id> -->            executed by a test; the id names the execution
#     <!-- fence-illustration: <reason> -->    deliberately not executable; reason >= 40 chars
#
# The marker is ALSO the extraction anchor, and that is the second reason it exists. Every
# existing extractor in this harness anchors on a HEADING (`scope-guards.test.sh`'s four,
# `plan-task-count.test.sh`'s two), so rewording a heading turns extraction into an empty result
# that reads as a passing skip. A marker beside the fence moves with it. `extract_fence` below
# treats an empty extraction as a FAILURE, never a skip — and `plan-task-count.test.sh` PTC/PTF
# were corrected the same way in this change rather than left as the unsafe precedent next door.
#
# THE NUMBERS, RECOUNTED (the issue's arithmetic was right and both its inputs were wrong).
# #206 reported 15 abort-capable fences of which ~6 covered, leaving 9. Measured here: 138 bash
# fences, **13** abort-capable, **4** covered, leaving 9. The 15 came from matching `ABORT` as a
# SUBSTRING, which also hits the word "aborted" in two fences that cannot abort anything; the 6
# counted `extract_conductor_lookup`, whose fence is not abort-capable at all. Both off by two in
# the same direction, so 15-6 and 13-4 agree. Two wrong numbers subtracting to the right one is
# not a check — recount before building on a count.
#
# WHAT `bash -n` SETTLED. Of the 13, exactly one is not syntactically valid bash:
# `concept-to-code`'s merge-back block, which carries `<base-fork halt: …>` pseudo-code. That is a
# mechanical classifier for the contract-versus-illustration question the issue calls the deeper
# finding, and it found the single genuine illustration among the thirteen rather than leaving the
# split to taste. `F7` keeps it: a fence declared a contract must at minimum parse.
#
# DERIVED-GUARD PATTERN — instance 2 of 6 (ADR-0086). Derives: fenced blocks inside a file. Waiver: `<!-- fence-contract: <id> -->` / `<!-- fence-illustration: … -->`, which is ALSO the extraction anchor.
# The pattern is deliberately COPIED across the six, not shared. Before writing a seventh by
# copying this file, read ADR-0086 §D1: extract only when two copies giving different answers
# would be a DEFECT. Here they would not — the six ask six questions about six populations.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
SKILLS="$STAGING/plugin/skills"
TESTS="$SCRIPTS/tests"
REPO=$(cd "$STAGING/.." && pwd)

AB="$SKILLS/autopilot-build/SKILL.md"
NA="$SKILLS/autopilot/SKILL.md"
CMS="$SKILLS/claude-md-slim/SKILL.md"
CMT="$SKILLS/commit/SKILL.md"

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

# =====================================================================================
# Shared machinery.

# enumerate_fences <file> — one record per bash fence: "<opener-line>\t<marker-or-NONE>".
# Indentation-tolerant: `autopilot` indents fences inside numbered list items, and a
# column-0 anchor undercounts (the issue's own first sweep reported 101 instead of 138).
enumerate_fences() {
  awk '
    function flush_marker() { last_marker = "NONE" }
    {
      line = $0
      stripped = line; sub(/^[[:space:]]+/, "", stripped)
      if (stripped ~ /^<!--[[:space:]]*fence-(contract|illustration):/) { pending = stripped; next }
      if (stripped == "") { next }                     # blank lines do not clear a pending marker
      if (infence) {
        if (stripped == "```") { infence = 0 }
        next
      }
      if (stripped ~ /^```bash[[:space:]]*$/) {
        printf "%d\t%s\n", NR, (pending == "" ? "NONE" : pending)
        pending = ""; infence = 1; next
      }
      pending = ""                                     # any other content clears it
    }
  ' "$1"
}

# fence_body <file> <opener-line> — the fence body with its own indentation stripped. Strips AT
# MOST the opener's own indentation (`ind`), and never more than a given line's OWN leading
# whitespace (`lw`) — `strip = (lw < ind) ? lw : ind`. Issue #394 / ADR-0133: the prior
# unconditional `substr($0, ind + 1)` corrupted a column-0 line inside an indented fence (a
# 3-space-indented fence turned the line `FENCE_BASH` into `CE_BASH`, eating three characters of
# real content instead of three characters of absent whitespace). `WS8` pins the fixed behaviour;
# for every line whose own indentation is >= ind (the overwhelmingly common case) this produces the
# byte-identical result the old unconditional strip did.
fence_body() {
  awk -v want="$2" '
    NR == want {
      match($0, /^[[:space:]]*/); ind = RLENGTH; infence = 1; next
    }
    infence {
      s = $0; sub(/^[[:space:]]+/, "", s)
      if (s == "```") { exit }
      match($0, /^[[:space:]]*/); lw = RLENGTH
      strip = (lw < ind) ? lw : ind
      print substr($0, strip + 1)
    }
  ' "$1"
}

# unwrap_body <body-file> — the here-document BODY when the ADR-0133 §D1 wrapper
# (`bash <<'"'"'FENCE_BASH'"'"'`, a column-0 `FENCE_BASH` terminator) is present anywhere in the
# input; the input UNCHANGED otherwise. `bash -n` cannot see past a quoted heredoc opener — the
# body between the delimiters is DATA to the outer parse, not code — so `F7` extended to call
# `bash -n` on the wrapped fence directly would keep passing a wrapped fence unconditionally,
# looking unchanged while checking nothing (`WS9`). Buffers pre-wrapper lines so the "unwrapped"
# fallback can print the ORIGINAL input verbatim when no wrapper is ever found.
UNWRAP_AWK="$TMPROOT/unwrap.awk"
cat >"$UNWRAP_AWK" <<'UNWRAPEOF'
BEGIN { mode = "before"; nb = 0 }
{
  if (mode == "before") {
    if ($0 == "bash <<'FENCE_BASH'") { mode = "wrap"; next }
    nb++; before[nb] = $0
    next
  }
  if (mode == "wrap") {
    if ($0 == "FENCE_BASH") { mode = "after"; next }
    print
    next
  }
  # mode == "after": nothing expected past the terminator; ignored rather than mis-parsed.
}
END {
  if (mode == "before") { for (i = 1; i <= nb; i++) print before[i] }
}
UNWRAPEOF
unwrap_body() {
  awk -f "$UNWRAP_AWK" "$1"
}

# fence_is_abort_capable <body-file> — word-boundary `exit 1|2` or the standalone word `abort`.
# NOT a substring match on ABORT: that hits "aborted", which is how #206 reached 15.
fence_is_abort_capable() {
  grep -qE '(^|[^[:alnum:]_])exit[[:space:]]+[12]([^0-9]|$)' "$1" && return 0
  grep -qiE '(^|[^[:alnum:]_])abort([^[:alnum:]_]|$)' "$1" && return 0
  return 1
}

# extract_fence <skill-md> <contract-id> — body of the fence whose marker names <id>.
# Anchored on the MARKER, not a heading. An empty result is a failure at the call site, never a
# quietly passing skip.
extract_fence() {
  _f="$1"; _id="$2"
  _ln=$(enumerate_fences "$_f" | grep -F "fence-contract: ${_id} -->" | head -1 | cut -f1)
  [ -n "$_ln" ] || return 1
  fence_body "$_f" "$_ln"
}

# The substitution contract, applied to EVERY extracted body: a SKILL.md names the DEPLOYED path
# because that is what the model runs; the harness must exercise the STAGING copy, which is what a
# PR changes. Two-line sed, stated once, applied in one place.
subst_paths() {
  sed -e "s|~/.claude/skills/|$SKILLS/|g" -e "s|~/.claude/hooks/|$SCRIPTS/|g"
}

# run_fence <contract-id> <skill-md> <setup-script> [extra-sed] — extract, apply the substitution
# contract (plus any per-fence placeholder sed), prepend the setup that binds the fence's free
# variables, execute, print the exit code. The id is a real argument of a real execution, which is
# what F4 greps for: a contract is covered when something RUNS it, never when something says so.
# `run_check1` and `run_check6` in scope-guards.test.sh already showed two divergent shapes for
# this; the [extra-sed] parameter is what lets one helper cover both instead of a third shape.
run_fence() {
  _id="$1"; _f="$2"; _setup="$3"; _sed="${4:-}"
  _body=$(extract_fence "$_f" "$_id") || { echo "EXTRACT_FAILED"; return; }
  if [ -z "$_body" ]; then echo "EXTRACT_EMPTY"; return; fi
  _s="$TMPROOT/run-$_id.sh"
  { cat "$_setup"; printf '\n'; } >"$_s"
  if [ -n "$_sed" ]; then
    printf '%s\n' "$_body" | subst_paths | sed "$_sed" >>"$_s"
  else
    printf '%s\n' "$_body" | subst_paths >>"$_s"
  fi
  ( bash "$_s" >"$TMPROOT/out-$_id" 2>&1 ); echo "$?"
}

# run_fence_logic <contract-id> <skill-md> <setup-script> <trailing-script> [extra-sed] — issue
# #394 / ADR-0133. The D1 wrapper runs a fence's body in a SUBSHELL (`bash <<'FENCE_BASH' …`), so a
# variable the body computes dies at the closing terminator and is invisible to a caller capturing
# only stdout+exit-code via run_fence — exactly the property Task 2's unwrap_body already exists to
# see past, for a different consumer (F7's syntax check, WS3, WS9). Reused here for the same
# reason: to assert what a fence's OWN LOGIC computes (include_paths, _missing, test_files…) by
# running the UNWRAPPED body directly with a caller-supplied trailing script appended in the SAME
# process, so the trailing script's own prints land in the captured output regardless of whether
# the wrapper has landed yet. This is a test-harness-only bypass of the process boundary — it does
# not weaken R-04's "communicate through stdout and exit code only" contract for the ORCHESTRATOR,
# which never sees past the wrapper either way. Extraction failure propagates
# EXTRACT_FAILED/EXTRACT_EMPTY exactly like run_fence, which is what lets WSC-WSH below read RED
# before a `fence-contract` marker exists on these three fences at all.
run_fence_logic() {
  _id="$1"; _f="$2"; _setup="$3"; _trail="$4"; _sed="${5:-}"
  _obody=$(extract_fence "$_f" "$_id") || { echo "EXTRACT_FAILED"; return; }
  if [ -z "$_obody" ]; then echo "EXTRACT_EMPTY"; return; fi
  if [ -n "$_sed" ]; then
    printf '%s\n' "$_obody" | subst_paths | sed "$_sed" >"$TMPROOT/rfl-outer-$_id"
  else
    printf '%s\n' "$_obody" | subst_paths >"$TMPROOT/rfl-outer-$_id"
  fi
  unwrap_body "$TMPROOT/rfl-outer-$_id" >"$TMPROOT/rfl-inner-$_id"
  _s="$TMPROOT/run-logic-$_id.sh"
  { cat "$_setup"; printf '\n'; cat "$TMPROOT/rfl-inner-$_id"; printf '\n'; cat "$_trail"; printf '\n'; } >"$_s"
  ( bash "$_s" >"$TMPROOT/outlogic-$_id" 2>&1 ); echo "$?"
}

# A real manifest, patched. A hand-written minimal one trips unrelated invariants and reports a
# failure about everything except the thing under test (the ADR-0078 lesson).
#
# The base is chosen by RUNNING `manifest-validate.sh` over the corpus, not by picking one that
# looks complete: this repository's own manifests carry a `project_root` from a different machine
# (ADR-0078), and invariant 4 skips the existence check only for terminal states — so flipping
# `current_step` to a live value makes an otherwise-valid manifest fail for a reason that has
# nothing to do with any fence. That is why the fixture rewrites the root as well as the step.
BASE_MANIFEST=""
for _m in "$REPO"/docs/manifests/*.manifest.yml; do
  [ -f "$_m" ] || continue
  if bash "$SKILLS/concept-to-code/scripts/manifest-validate.sh" "$_m" >/dev/null 2>&1; then
    BASE_MANIFEST="$_m"; BASE_ROOT=$(grep '^project_root:' "$_m" | sed -e 's/^project_root:[[:space:]]*"//' -e 's/"[[:space:]]*$//')
    break
  fi
done

# mk_manifest_text <dest> <current_step> <status> — sed-level patching, quoting preserved.
# Required for anything that reaches manifest-validate.sh, which greps the raw text for a QUOTED
# absolute path: a yaml round-trip emits `spec: /abs/path` unquoted and the validator rejects it.
mk_manifest_text() {
  [ -n "$BASE_MANIFEST" ] || return 1
  sed -e "s|$BASE_ROOT|$TMPROOT/proj|g" \
      -e "s|^current_step:.*|current_step: \"$2\"|" \
      -e "s|^status:.*|status: \"$3\"|" "$BASE_MANIFEST" >"$1"
}
mkdir -p "$TMPROOT/proj"

# =====================================================================================
# F. The derived class check.

ALL_FENCES="$TMPROOT/all"; : >"$ALL_FENCES"
# Population is SKILL.md itself PLUS any references/*.md a skill splits content into (VCS-042):
# a fence-contract fence moved out of SKILL.md without widening this glob silently leaves the
# controlled population while the >=100 floor below likely still passes — rule 10.
for f in "$SKILLS"/*/SKILL.md "$SKILLS"/*/references/*.md; do
  [ -f "$f" ] || continue
  enumerate_fences "$f" | while IFS="$(printf '\t')" read -r ln marker; do
    printf '%s\t%s\t%s\n' "$f" "$ln" "$marker"
  done >>"$ALL_FENCES"
done
FENCE_N=$(grep -c . "$ALL_FENCES")

# F1: count guard. Measured at 138; a glob or a fence parser that has stopped matching reports
# clean, and that is indistinguishable from a corpus with nothing to check.
if [ "$FENCE_N" -ge 100 ]; then
  ok "F1: fence enumeration non-vacuous ($FENCE_N bash fences)"
else
  bad "F1: only $FENCE_N bash fences enumerated — expected >= 100; the parser is broken, not clean"
fi

# Classify.
ABORT_LIST="$TMPROOT/abort"; : >"$ABORT_LIST"
while IFS="$(printf '\t')" read -r f ln marker; do
  [ -n "$f" ] || continue
  fence_body "$f" "$ln" >"$TMPROOT/body"
  if fence_is_abort_capable "$TMPROOT/body"; then
    printf '%s\t%s\t%s\n' "$f" "$ln" "$marker" >>"$ABORT_LIST"
  fi
done <"$ALL_FENCES"
ABORT_N=$(grep -c . "$ABORT_LIST")

# F2: second count guard, per-population rather than global. The abort predicate is the narrow
# part of this harness and a typo in it would silently empty F3.
if [ "$ABORT_N" -ge 10 ]; then
  ok "F2: abort-capable subset non-vacuous ($ABORT_N of $FENCE_N)"
else
  bad "F2: only $ABORT_N abort-capable fences found — expected >= 10; the predicate has stopped matching"
fi

# F3: THE DIRECTION ASSERTION. Every abort-capable fence must carry a marker. This is what fails
# when a new one is added — the check runs against what the corpus contains, never against a list
# of what someone remembered to write down (rule 5).
UNMARKED=""
while IFS="$(printf '\t')" read -r f ln marker; do
  [ -n "$f" ] || continue
  case "$marker" in
    NONE) UNMARKED="$UNMARKED
${f#$REPO/}:$ln" ;;
  esac
done <"$ABORT_LIST"
UNMARKED=$(printf '%s\n' "$UNMARKED" | grep -v '^$')
if [ -z "$UNMARKED" ]; then
  ok "F3: every abort-capable fence declares itself a contract or an illustration"
else
  bad "F3: abort-capable fence(s) with no declaration:"
  printf '%s\n' "$UNMARKED" | sed 's/^/        /'
fi

# F4: a contract id must be RUN by a test, not merely mentioned. Two accepted forms, both of which
# name the id in a position that only an actual execution occupies:
#
#   run_fence "<id>"              this file's helper
#   fence-contract: <id> -->      a bespoke extractor anchoring on the marker string itself
#
# The second exists because four of these fences were already covered by `scope-guards.test.sh`
# and `plan-task-count.test.sh` before this change, each with its own extractor. Those were
# re-anchored on the marker in this same change rather than reimplemented here — a test cannot
# extract the fence without naming its id, so the claim is verified rather than declared. A
# `# covered elsewhere` comment would have been a claim, and the difference matters.
#
# Neither needle can be satisfied by this file's own marker-parsing code, which builds the string
# by interpolation and contains no literal id (rule 12).
# Derived from ALL_FENCES — every DECLARATION — not from ABORT_LIST (issue #281, ADR-0107).
#
# It read the abort-capable subset, so a fence that declared itself and then ended `exit 3` or
# `exit "$_rc"` sat outside `fence_is_abort_capable` and therefore outside its own guard. Measured:
# **18 declarations, 13 in the population, 5 invisible** — four added in one day (ADR-0096,
# ADR-0102, ADR-0103, ADR-0104, each of which disclosed it by hand) and one,
# `concept-to-code-step5-plan-structure`, that predates all of them and nobody had noticed.
#
# All five were in fact executed and did parse. The defect was never coverage; it was that nothing
# CHECKED the coverage, which is the same shape as the producer/consumer class #248 records —
# an assertion that is true and unverified reads exactly like one that is verified.
CONTRACT_IDS=$(grep -oE 'fence-contract:[[:space:]]*[A-Za-z0-9_-]+' "$ALL_FENCES" \
  | sed 's/.*fence-contract:[[:space:]]*//' | sort -u)
CONTRACT_N=$(printf '%s\n' "$CONTRACT_IDS" | grep -c . )
UNRUN=""
for id in $CONTRACT_IDS; do
  grep -qF "run_fence \"$id\"" "$TESTS"/*.test.sh 2>/dev/null && continue
  grep -qF "fence-contract: $id -->" "$TESTS"/*.test.sh 2>/dev/null && continue
  UNRUN="$UNRUN $id"
done
if [ -z "$UNRUN" ]; then
  ok "F4: all $CONTRACT_N declared contracts are executed by a test"
else
  bad "F4: contract(s) declared but never run:$UNRUN"
fi

# F5: an illustration's reason is a sentence a human wrote, on ONE line. One line is not cosmetic:
# a reason that wraps is a prose assertion depending on where the text breaks, the family this
# repository has now been bitten by four times (ADR-0073, ADR-0076, ADR-0080, ADR-0082).
SHORT=""
ILL_N=0
while IFS="$(printf '\t')" read -r f ln marker; do
  [ -n "$f" ] || continue
  case "$marker" in
    *fence-illustration:*)
      ILL_N=$((ILL_N + 1))
      _r=$(printf '%s' "$marker" | sed -e 's/.*fence-illustration:[[:space:]]*//' -e 's/[[:space:]]*-->[[:space:]]*$//')
      [ "${#_r}" -lt 40 ] && SHORT="$SHORT
${f#$REPO/}:$ln (${#_r} chars)" ;;
  esac
done <"$ABORT_LIST"
SHORT=$(printf '%s\n' "$SHORT" | grep -v '^$')
if [ -z "$SHORT" ]; then
  ok "F5: every illustration declaration carries a one-line reason of at least 40 characters"
else
  bad "F5: illustration reason too short (a bare waiver excuses nothing):"
  printf '%s\n' "$SHORT" | sed 's/^/        /'
fi

# F6: ids must be unique, or two fences share one execution and one of them is uncovered while
# looking covered.
DUP=$(printf '%s\n' "$CONTRACT_IDS" | grep -c . )
RAW=$(grep -oE 'fence-contract:[[:space:]]*[A-Za-z0-9_-]+' "$ALL_FENCES" | grep -c . )
if [ "$DUP" -eq "$RAW" ]; then
  ok "F6: all $DUP contract ids are unique"
else
  bad "F6: $RAW contract markers but only $DUP distinct ids — an id is reused"
fi

# F7: a contract must at minimum parse as bash. This is the mechanical half of the
# contract-versus-illustration split, and it is what identified the one genuine illustration.
#
# Parses the INNER body, through unwrap_body (issue #394, ADR-0133 §D6): `bash -n` is blind to a
# quoted heredoc's contents — a wrapped fence would otherwise parse unconditionally the day the
# wrapper lands, looking unchanged while checking nothing (WS9). unwrap_body returns its input
# unchanged when no wrapper is present, so this is a no-op for every fence today.
BADSYN=""
while IFS="$(printf '\t')" read -r f ln marker; do
  [ -n "$f" ] || continue
  case "$marker" in *fence-contract:*) ;; *) continue ;; esac
  fence_body "$f" "$ln" >"$TMPROOT/syn-outer.sh"
  unwrap_body "$TMPROOT/syn-outer.sh" >"$TMPROOT/syn.sh"
  bash -n "$TMPROOT/syn.sh" 2>/dev/null || BADSYN="$BADSYN
${f#$REPO/}:$ln"
done <"$ABORT_LIST"
BADSYN=$(printf '%s\n' "$BADSYN" | grep -v '^$')
if [ -z "$BADSYN" ]; then
  ok "F7: every declared contract parses as bash"
else
  bad "F7: contract fence(s) that do not parse — declare them illustrations or fix them:"
  printf '%s\n' "$BADSYN" | sed 's/^/        /'
fi

# F8: the illustration escape hatch must stay small and must actually be used, or F5 is vacuous
# and nobody would notice the mechanism rotting. Measured: exactly one at the time of writing.
if [ "$ILL_N" -ge 1 ] && [ "$ILL_N" -le 3 ]; then
  ok "F8: $ILL_N illustration declaration(s) — the escape hatch is exercised and still narrow"
else
  bad "F8: $ILL_N illustration declarations — expected 1..3; either F5 is vacuous or the hatch is widening"
fi

# F9: the population is EVERY declaration, not the abort-capable subset (ADR-0107).
#
# This is the regression guard for the widening above, stated as a property rather than as a count
# so it cannot rot: every `fence-contract:` marker that exists must be in the set F4/F6/F7 check.
# Reverting the derivation to ABORT_LIST makes this fail naming the five it drops.
#
# F5 and F8 deliberately keep reading ABORT_LIST. F8 measures the escape hatch from F3, which only
# applies to abort-capable fences, so widening it would change what it means; F5 rides on F8's
# population and there is exactly one illustration in the corpus, inside that subset. Measured, not
# assumed — a second illustration outside it would need F5 widened, and F8 would still not move.
MISSING=""
for _m in $(grep -oE 'fence-contract:[[:space:]]*[A-Za-z0-9_-]+' "$ALL_FENCES" \
              | sed 's/.*fence-contract:[[:space:]]*//' | sort -u); do
  printf '%s\n' "$CONTRACT_IDS" | grep -qxF "$_m" || MISSING="$MISSING $_m"
done
if [ -z "$MISSING" ]; then
  ok "F9: the contract population is every declaration ($CONTRACT_N), not the abort-capable subset"
else
  bad "F9: declared contract(s) missing from the checked population — the derivation narrowed:$MISSING"
fi

# F10: count guard on that population (ADR-0085 — guard the denominator). An enumeration that
# quietly stops matching empties F4, F6, F7 and F9 at once, and four silent passes read as coverage.
if [ "$CONTRACT_N" -ge 15 ]; then
  ok "F10: contract population non-vacuous ($CONTRACT_N declarations)"
else
  bad "F10: only $CONTRACT_N declared contracts found — expected >= 15; the marker parse is broken, not clean"
fi

# =====================================================================================
# S. Self-tests. The F section passes on a clean tree; these prove the machinery can fail.

SF="$TMPROOT/fixtures"; mkdir -p "$SF"
printf '# t\n\n```bash\nexit 1\n```\n' >"$SF/unmarked.md"
printf '# t\n\n<!-- fence-contract: sf-one -->\n```bash\ntrue\nexit 1\n```\n' >"$SF/marked.md"
printf '# t\n\n1. step\n   <!-- fence-contract: sf-indent -->\n   ```bash\n   exit 1\n   ```\n' >"$SF/indented.md"
printf '# t\n\n<!-- fence-contract: sf-one -->\n\n```bash\nexit 1\n```\n' >"$SF/blankline.md"
# No synthetic pseudo-code fixture. Two drafts of one were written and BOTH parsed as valid bash:
# `foo <bar baz>` is a redirect plus a command, and `… || <base-fork halt: … stop>` followed by
# another line consumes that line's first token as the `>` target. The construct only fails when
# the pseudo-code closes the block. S9 therefore runs the classifier over the REAL fence, which is
# the only input whose behaviour the claim is about (rule 10 — an issue's repro is not the defect;
# run the actual line from the actual file).

_n=$(enumerate_fences "$SF/unmarked.md" | cut -f2)
if [ "$_n" = "NONE" ]; then
  ok "S1: an undeclared fence enumerates as NONE"
else
  bad "S1: expected NONE for the unmarked fixture, got '$_n'"
fi

_n=$(enumerate_fences "$SF/marked.md" | cut -f2)
case "$_n" in *"fence-contract: sf-one -->"*) ok "S2: a marker is attached to the fence below it" ;;
  *) bad "S2: marker not attached (got '$_n')" ;; esac

# S3 is the count-guard lesson applied to indentation: `autopilot` indents fences inside
# numbered lists, and a column-0 anchor silently drops them.
_n=$(enumerate_fences "$SF/indented.md" | cut -f2)
case "$_n" in *"fence-contract: sf-indent -->"*) ok "S3: an INDENTED fence and its marker are seen" ;;
  *) bad "S3: indented fence missed (got '$_n') — the parser is column-0 anchored" ;; esac

# S4: a blank line between marker and fence must not detach them, or every marker inside a list
# item would need to hug the fence and the mechanism would be fragile for cosmetic reasons.
_n=$(enumerate_fences "$SF/blankline.md" | cut -f2)
case "$_n" in *"fence-contract: sf-one -->"*) ok "S4: a blank line does not detach a marker" ;;
  *) bad "S4: blank line detached the marker (got '$_n')" ;; esac

# S5: the abort predicate must not fire on the word "aborted" — that substring match is exactly
# how #206 counted 15 where there are 13.
printf 'bash x.sh <m> aborted aborted\n' >"$TMPROOT/p1"
printf 'echo hi\nexit 1\n'               >"$TMPROOT/p2"
printf 'echo hi\nexit 0\n'               >"$TMPROOT/p3"
if ! fence_is_abort_capable "$TMPROOT/p1"; then
  ok "S5: 'aborted' does not count as abort-capable"
else
  bad "S5: the predicate matched 'aborted' — this is the substring bug that produced 15"
fi
if fence_is_abort_capable "$TMPROOT/p2"; then ok "S6: 'exit 1' counts as abort-capable"
else bad "S6: 'exit 1' not detected — the predicate is broken"; fi
if ! fence_is_abort_capable "$TMPROOT/p3"; then ok "S7: 'exit 0' does not count as abort-capable"
else bad "S7: 'exit 0' counted as abort-capable"; fi

# S8: an extraction that finds nothing must be distinguishable from one that found an empty
# fence, and neither may look like a pass. This is the hazard the issue names.
if extract_fence "$SF/unmarked.md" "sf-absent" >/dev/null 2>&1; then
  bad "S8: extract_fence succeeded for an id that does not exist"
else
  ok "S8: extract_fence fails (non-zero) for an absent id rather than returning empty"
fi

# VCS-047/ADR-0174: the merge-back fence moved into references/step5-implementation.md.
CC_STEP5_REF="$SKILLS/concept-to-code/references/step5-implementation.md"
_ill_ln=$(enumerate_fences "$CC_STEP5_REF" | grep -F 'fence-illustration:' | head -1 | cut -f1)
if [ -n "$_ill_ln" ]; then
  fence_body "$CC_STEP5_REF" "$_ill_ln" >"$TMPROOT/syn2.sh"
  if bash -n "$TMPROOT/syn2.sh" 2>/dev/null; then
    bad "S9: the real merge-back fence now PARSES — if it became executable, promote it to a contract"
  else
    ok "S9: F7's classifier rejects the real merge-back fence's pseudo-code"
  fi
else
  bad "S9: no illustration-declared fence found in concept-to-code — the classifier has nothing to reject"
fi

# =====================================================================================
# WS. Wrapper machinery (issue #394, ADR-0133). WS0-WS7 — the population-and-wrapper-presence
# guard — land in Task 3 of the same feature. This section carries only the two TDD pairs Task 2
# owns: `fence_body`'s indentation-dedent guard and `unwrap_body`, the helper `F7` needs so a
# wrapped fence's INNER body is what gets syntax-checked. Both must exist before Task 3's
# WS1/WS3 can mean anything — an indented fence's body would otherwise be corrupted before it is
# even checked, and a wrapped fence's inner body would not parse at all.
#
# WS8's needle spans the fixed line AND the `print` line after it, not the bare expression alone:
# `strip = (lw < ind) ? lw : ind` also appears, backtick-quoted, in this section's own header
# comment two paragraphs up, and the plant tool's needle is whitespace-collapsed before matching
# (`\s+`-joined words, ADR-0099) — so an unqualified needle ignores leading indentation entirely
# and would match BOTH sites, tripping the exactly-one-match guard (ADR-0108). The two-line span
# is unique; verified by simulating the tool's own match-and-substitute logic against this file
# before writing the declaration, not by inspection. The replacement collapses both lines back to
# the pre-fix single unconditional `substr($0, ind + 1)` — the exact bug WS8 exists to catch.
# No WS9 plant: `unwrap_body`'s real body is a multi-line `awk -f` call, and registry v1 has no
# expressible single-line mutation that both reproduces its no-op-passthrough failure mode and
# stays inside the tool's own syntax limits (no newline in a field, no ` | ` inside a field) —
# recorded as a limit rather than forced into a plant that misrepresents what it mutates.
# plant: WS8 | plugin/scripts/tests/fence-contract-coverage.test.sh | strip = (lw < ind) ? lw : ind print substr($0, strip + 1) | print substr($0, ind + 1)

# WS8: fence_body must strip AT MOST the opener's own indentation, never `substr` past the start
# of a shorter line. Measured (ADR-0133 §Measured facts): the pre-fix unconditional
# `substr($0, ind + 1)` corrupted a column-0 line inside a 3-space-indented fence — the line
# `FENCE_BASH` extracted as `CE_BASH`.
printf '%s\n' '# t' '' '1. step' '   <!-- fence-contract: sf-ws8 -->' '   ```bash' '   echo one' \
  'FENCE_BASH' '   ```' >"$SF/ws8.md"
_ws8_ln=$(enumerate_fences "$SF/ws8.md" | grep -F 'fence-contract: sf-ws8 -->' | head -1 | cut -f1)
_ws8_body=$(fence_body "$SF/ws8.md" "$_ws8_ln")
if printf '%s\n' "$_ws8_body" | grep -qxF 'FENCE_BASH'; then
  ok "WS8: fence_body preserves a column-0 line inside an indented fence intact"
else
  bad "WS8: fence_body corrupted a column-0 line — body was: $(printf '%s' "$_ws8_body" | tr '\n' '|')"
fi

# WS9: RED evidence for the vacuity `bash -n` on a WRAPPED body would otherwise settle into —
# `bash <<'FENCE_BASH' … FENCE_BASH` is syntactically valid no matter what junk sits between the
# delimiters, because a quoted heredoc body is DATA to the outer parse, never code. Measured
# (ADR-0133 §Measured facts): a wrapper whose inner body reads `if [ ; then` passes `bash -n`
# today. `unwrap_body` is what lets the real check see the inner body instead.
#
# The inner body deliberately OMITS the closing `fi`. `[` is an ordinary command name (not shell
# grammar), so a zero-argument `[` invocation is a RUNTIME error, not a syntax one — `if [ ; then
# echo bad; fi` parses cleanly under `bash -n` even unwrapped. Confirmed by direct measurement
# before writing this fixture: with `fi` present, both the wrapped body AND the unwrapped inner
# content pass `bash -n` (rc=0), so the assertion below would never have gone RED. Without `fi`,
# the wrapped body still passes `bash -n` (rc=0 — the blind-spot premise this test exists to pin),
# while the unwrapped inner content correctly fails (rc=2, "unexpected end of file").
printf '%s\n' 'export foo' "bash <<'FENCE_BASH'" 'if [ ; then' '  echo bad' 'FENCE_BASH' \
  >"$TMPROOT/ws9-body"
if bash -n "$TMPROOT/ws9-body" 2>/dev/null; then
  ok "WS9 precondition: bash -n is blind to the WRAPPED form (confirms the measured blind spot)"
else
  bad "WS9 precondition: bash -n rejected the wrapped body outright — the blind-spot premise this assertion is built on no longer holds"
fi
unwrap_body "$TMPROOT/ws9-body" >"$TMPROOT/ws9-inner"
if bash -n "$TMPROOT/ws9-inner" 2>/dev/null; then
  bad "WS9: unwrap_body's inner body still parses — the malformed 'if [ ; then' was not exposed"
else
  ok "WS9: unwrap_body exposes the malformed inner body to bash -n — the wrapper no longer hides it"
fi

# =====================================================================================
# WS0-WS7. THE POPULATION-AND-WRAPPER-PRESENCE GUARD (issue #394, ADR-0133 Task 3, R-05/R-06/
# R-10/R-13). Written BEFORE any fence is wrapped (Tasks 4-7, batches 3-4 of this Step 5):
# WS1/WS3/WS4 are THEREFORE EXPECTED RED here, naming the unwrapped fences — ADR-0101's case (a),
# a red a LATER task in the SAME Step 5 restores, never a red this task must clear itself.
# WS0/WS2/WS5/WS6/WS7 are forward guards: they hold today for reasons independent of wrap status
# (a non-vacuous population, no terminator to mis-indent yet, a working scanner, no stray
# positional token, a pinned decision) and must STAY green once wrapping lands.
#
# THE POPULATION (R-05, derived at run time, NEVER from a list): every DECLARED fence-contract
# (from ALL_FENCES above) union every UNMARKED fence the scanner (fence-shell-divergence-scan.sh,
# Task 1) flags as divergent on its CURRENT (as-stored) body. A fence-illustration-marked fence is
# excluded from the population even when the scanner flags it (ADR-0133 §D3 — the merge-back
# pseudo-code fence carries four false-positive W-arg records and is a documented, PERMANENT
# exclusion, not a repair owed to it).
#
# --- WS7-PROSE-START ---------------------------------------------------------------------------
# D2 — the wrapper carries no declaration marker of its own. Its presence in the body IS its own
# evidence: a `<!-- fence-wrapped -->` marker would be a second source of truth that can disagree
# with the mechanism it describes, with nothing to say which is authoritative (the ADR-0042 shape,
# and the shape ADR-0043's direction lesson is about). A marker is a claim; an executable line is
# not. Stated here because the next reader meeting an unmarked convention in a repository full of
# markers will otherwise "fix" the omission. WS7 pins this paragraph is present, bounded by the
# sentinels above/below it so the check does not also match its own grep pattern two screens down
# (rule 12 — a scan whose needle is a literal counts itself; unbounded, the phrase "carries no
# declaration marker" would satisfy itself from WS7's own code line alone, with no header at all).
# --- WS7-PROSE-END -----------------------------------------------------------------------------
SCANNER="$TESTS/fence-shell-divergence-scan.sh"

# ws_has_wrapper <body-file> — true (0) if the ADR-0133 D1 wrapper's quoted opener
# (`bash <<'FENCE_BASH'`) AND a FENCE_BASH terminator line (any indentation) are both present.
ws_has_wrapper() {
  grep -qxF "bash <<'FENCE_BASH'" "$1" && grep -qE '^[[:space:]]*FENCE_BASH[[:space:]]*$' "$1"
}

# ws_terminator_indented <body-file> — true (0) if a FENCE_BASH terminator-shaped line exists but
# NONE of them sits at column 0 (D1 rule 2: an indented terminator swallows the rest of the script
# into the here-document and silently destroys the exit code).
ws_terminator_indented() {
  grep -qE '^[[:space:]]*FENCE_BASH[[:space:]]*$' "$1" && ! grep -qxF 'FENCE_BASH' "$1"
}

# Population + scanner-flagged derivation, over ALL_FENCES (built by the F section above — every
# bash fence in every staged SKILL.md). Re-run fresh here rather than trusted from the ADR: a count
# in a prior document is a snapshot of its moment (ADR-0107's own lesson).
WS_POP="$TMPROOT/ws-pop"; : >"$WS_POP"              # file \t line \t marker \t kind(declared|divergent)
WS_FLAGGED="$TMPROOT/ws-flagged"; : >"$WS_FLAGGED"  # file \t line \t marker — ANY scanner record
while IFS="$(printf '\t')" read -r f ln marker; do
  [ -n "$f" ] || continue
  fence_body "$f" "$ln" >"$TMPROOT/ws-body"
  _wsout=$(bash "$SCANNER" <"$TMPROOT/ws-body" 2>/dev/null)
  case "$marker" in
    *fence-contract:*)
      printf '%s\t%s\t%s\tdeclared\n' "$f" "$ln" "$marker" >>"$WS_POP"
      [ -n "$_wsout" ] && printf '%s\t%s\t%s\n' "$f" "$ln" "$marker" >>"$WS_FLAGGED"
      ;;
    *fence-illustration:*)
      # ADR-0133 §D3 — excluded from the POPULATION even though the scanner flags it; it stays
      # unwrapped forever, so it must never be counted as "needs wrapping".
      [ -n "$_wsout" ] && printf '%s\t%s\t%s\n' "$f" "$ln" "$marker" >>"$WS_FLAGGED"
      ;;
    *)
      if [ -n "$_wsout" ]; then
        printf '%s\t%s\t%s\tdivergent\n' "$f" "$ln" "$marker" >>"$WS_POP"
        printf '%s\t%s\t%s\n' "$f" "$ln" "$marker" >>"$WS_FLAGGED"
      fi
      ;;
  esac
done <"$ALL_FENCES"
cut -f1,2 "$WS_POP" >"$TMPROOT/ws-pop-keys"

WS_POP_N=$(grep -c . "$WS_POP" 2>/dev/null || true); WS_POP_N=${WS_POP_N:-0}
WS_DECLARED_N=$(awk -F'\t' '$4=="declared"{c++} END{print c+0}' "$WS_POP")
WS_DIVERGENT_N=$(awk -F'\t' '$4=="divergent"{c++} END{print c+0}' "$WS_POP")
WS_FLAGGED_N=$(grep -c . "$WS_FLAGGED" 2>/dev/null || true); WS_FLAGGED_N=${WS_FLAGGED_N:-0}

# plant: WS0 | plugin/scripts/tests/fence-contract-coverage.test.sh | WS_POP_N=$(grep -c . "$WS_POP" 2>/dev/null || true); WS_POP_N=${WS_POP_N:-0} | WS_POP_N=$(grep -c . /dev/null 2>/dev/null || true); WS_POP_N=${WS_POP_N:-0}

# WS0: denominator guard (ADR-0085). A marker parse or a scanner that has stopped matching empties
# every other WS assertion at once, and four silent passes would read as coverage.
if [ "$WS_POP_N" -ge 32 ]; then
  ok "WS0: the population is non-vacuous ($WS_POP_N: $WS_DECLARED_N declared, $WS_DIVERGENT_N unmarked-divergent)"
else
  bad "WS0: only $WS_POP_N population fence(s) — expected >= 32; the derivation is broken, not clean"
fi

# Batch 5 repair (issue #394 Task 8, ADR-0090): the above `&&`->`||` mutation fired while at least
# one population fence had neither the opener nor the terminator (batches 1-3), because `A || B`
# was still false for that fence. Task 7 wrapped the last one — every population fence now
# satisfies BOTH conjuncts, so `A || B` is true for all of them exactly as `A && B` is, and the
# mutation stopped changing ws_has_wrapper's verdict for any real input. Corpus-dependent by
# construction, and the corpus moved.
#
# Retargeted at the OPENER NEEDLE ITSELF rather than the boolean connective: renaming the
# delimiter the first grep looks for to a string no fence body will ever contain makes that grep
# fail for EVERY population fence regardless of wrap status, so ws_has_wrapper is unconditionally
# false and WS1 reports every population fence as unwrapped — true whether 0 or all 41 are wrapped,
# because the needle is simply unmatchable. Corpus-independent, which the boolean-flip mutation
# never was. Verified by inspecting what it produced, not by the word "fired" (ADR-0090): run
# against the fully-wrapped corpus it reddens WS1 naming all 35 population fences, while WS0 (the
# denominator) stays green — the failure is WS1's own, not an emptied population.
# plant: WS1 | plugin/scripts/tests/fence-contract-coverage.test.sh | grep -qxF "bash <<'FENCE_BASH'" "$1" && grep -qE '^[[:space:]]*FENCE_BASH[[:space:]]*$' "$1" | grep -qxF "bash <<'ZZZ_NEVER_MATCHES_ANY_FENCE_ZZZ'" "$1" && grep -qE '^[[:space:]]*FENCE_BASH[[:space:]]*$' "$1"

# WS1 (R-05/R-10): every population fence carries the ADR-0133 wrapper. EXPECTED RED before Task 4
# — no fence is wrapped yet. The failure list is the work order for Tasks 4-7.
WS_UNWRAPPED=""
while IFS="$(printf '\t')" read -r f ln marker kind; do
  [ -n "$f" ] || continue
  fence_body "$f" "$ln" >"$TMPROOT/ws-body"
  ws_has_wrapper "$TMPROOT/ws-body" || WS_UNWRAPPED="$WS_UNWRAPPED
${f#$REPO/}:$ln"
done <"$WS_POP"
WS_UNWRAPPED=$(printf '%s\n' "$WS_UNWRAPPED" | grep -v '^$')
if [ -z "$WS_UNWRAPPED" ]; then
  ok "WS1: every population fence ($WS_POP_N) carries the ADR-0133 wrapper"
else
  _wsn=$(printf '%s\n' "$WS_UNWRAPPED" | grep -c .)
  bad "WS1: $_wsn of $WS_POP_N population fence(s) do not yet carry the wrapper (the Task 4-7 work order):"
  printf '%s\n' "$WS_UNWRAPPED" | sed 's/^/        /'
fi

# plant: WS2 | plugin/scripts/tests/fence-contract-coverage.test.sh | grep -qE '^[[:space:]]*FENCE_BASH[[:space:]]*$' "$1" && ! grep -qxF 'FENCE_BASH' "$1" | grep -qE '^[[:space:]]*FENCE_BASH[[:space:]]*$' "$1" && grep -qxF 'FENCE_BASH' "$1"

# WS2 (R-05): a FENCE_BASH terminator, wherever one exists, sits at column 0. Measured hazard
# (ADR-0133 §Measured facts): an indented terminator swallows the rest of the script into the
# here-document and destroys the exit code silently, while looking like correct formatting.
#
# Batch 3 carried this forward as a non-firing plant, on the stated reason "no fence yet carries
# the wrapper". Re-checked in batch 4 (issue #394, 5 fences now wrapped): the plant NOW FIRES —
# verified by inverting the condition (accept an indented terminator, reject a column-0 one)
# against the 5 real wrapped fences, all of which have a correct column-0 terminator, so the
# inverted check reports every one of them as bad. This assertion has discriminating power today;
# it is no longer a forward guard, and the "finds nothing to flag" reading above is stale.
WS_BADCOL=""
while IFS="$(printf '\t')" read -r f ln marker kind; do
  [ -n "$f" ] || continue
  fence_body "$f" "$ln" >"$TMPROOT/ws-body"
  ws_terminator_indented "$TMPROOT/ws-body" && WS_BADCOL="$WS_BADCOL
${f#$REPO/}:$ln"
done <"$WS_POP"
WS_BADCOL=$(printf '%s\n' "$WS_BADCOL" | grep -v '^$')
if [ -z "$WS_BADCOL" ]; then
  ok "WS2: no population fence's FENCE_BASH terminator is indented ($WS_POP_N checked)"
else
  bad "WS2: population fence(s) with an INDENTED terminator (silently destroys the exit code):"
  printf '%s\n' "$WS_BADCOL" | sed 's/^/        /'
fi

# ws_inner_syntax_bad <body-file> — true (0) if the wrapper is absent, OR its inner body (through
# Task 2's unwrap_body) does not parse as bash. `bash -n` is blind to a WRAPPED body (WS9) — this
# is what keeps the widening below from going vacuous once the wrapper lands (ADR-0133 §D6).
ws_inner_syntax_bad() {
  ws_has_wrapper "$1" || return 0
  unwrap_body "$1" >"$TMPROOT/ws3-inner"
  ! bash -n "$TMPROOT/ws3-inner" 2>/dev/null
}

# plant: WS3 | plugin/scripts/tests/fence-contract-coverage.test.sh | ! bash -n "$TMPROOT/ws3-inner" 2>/dev/null | bash -n "$TMPROOT/ws3-inner" 2>/dev/null

# WS3 (R-02/R-05): every population fence's INNER body parses as bash. EXPECTED RED before Task 4
# — with no wrapper present, ws_has_wrapper's own gate reports every population fence as failing
# this check, for the same underlying reason WS1 does, verified through an independent mechanism
# (Task 2's unwrap_body + bash -n, not a literal string match).
WS_BADSYN3=""
while IFS="$(printf '\t')" read -r f ln marker kind; do
  [ -n "$f" ] || continue
  fence_body "$f" "$ln" >"$TMPROOT/ws-body"
  ws_inner_syntax_bad "$TMPROOT/ws-body" && WS_BADSYN3="$WS_BADSYN3
${f#$REPO/}:$ln"
done <"$WS_POP"
WS_BADSYN3=$(printf '%s\n' "$WS_BADSYN3" | grep -v '^$')
if [ -z "$WS_BADSYN3" ]; then
  ok "WS3: every population fence's inner (unwrapped) body parses as bash"
else
  _wsn=$(printf '%s\n' "$WS_BADSYN3" | grep -c .)
  bad "WS3: $_wsn of $WS_POP_N population fence(s) fail the inner-body parse (not yet wrapped, or bad syntax once unwrapped):"
  printf '%s\n' "$WS_BADSYN3" | sed 's/^/        /'
fi

# Batch 5 repair (issue #394 Task 8, ADR-0090): the population-membership `if` above was mutated
# by inverting its negation. That line is only reached for a `WS_FLAGGED` entry that survives the
# `case … *fence-illustration:*) continue ;; esac` guard just above the loop body — and once
# batches 4-5 wrapped every divergent fence, the scanner's only surviving flagged entry IS the
# illustration, so the loop `continue`s on it before the mutated line ever runs. The mutation
# stopped firing not because the property broke, but because its target became unreachable.
#
# Retargeted at the ILLUSTRATION-EXEMPTION `continue` ITSELF, which is the property WS4 actually
# protects: without it, the illustration — permanently flagged by the scanner (ADR-0133 §D3, four
# false-positive W-arg records) and permanently excluded from the population by design — falls
# through to the membership check, is correctly reported as absent from `ws-pop-keys` (illustrations
# never enter WS_POP), and WS4 wrongly flags it "(outside the population)". Corpus-independent: as
# long as the scanner keeps flagging the one declared illustration — a structural, not a wrap-status,
# fact — this fires regardless of how many other fences are wrapped. Verified by inspecting what it
# produced (ADR-0090): reddens WS4 alone, naming the merge-back illustration as spuriously outside
# the population, with every other WS assertion (including WS0/WS1/WS3) unaffected.
# plant: WS4 | plugin/scripts/tests/fence-contract-coverage.test.sh | case "$marker" in *fence-illustration:*) continue ;; esac | case "$marker" in *ZZZ_NEVER_MATCHES_ANYTHING_ZZZ*) continue ;; esac

# WS4 (R-05): the scanner's CURRENT flagged set, minus the documented illustration exemption
# (ADR-0133 §D3 — the sole false-positive-only exclusion; every OTHER false positive sits on an
# already-declared or already-divergent fence and needs no separate handling, since it is wrapped
# regardless of whether its scanner record was genuine), is a subset of the population AND every
# member already carries the wrapper. A flagged fence outside the population would be a genuinely
# new, unaccounted-for divergence; a flagged POPULATION fence not yet wrapped is exactly WS1's
# condition, reached here by an INDEPENDENT, scanner-based mechanism rather than a literal string
# match. EXPECTED RED before Task 4: nothing is wrapped, so every non-exempt flagged fence still
# shows a record.
WS4_BAD=""
while IFS="$(printf '\t')" read -r f ln marker; do
  [ -n "$f" ] || continue
  case "$marker" in
    *fence-illustration:*) continue ;;
  esac
  _key=$(printf '%s\t%s' "$f" "$ln")
  if ! grep -qxF "$_key" "$TMPROOT/ws-pop-keys" 2>/dev/null; then
    WS4_BAD="$WS4_BAD
${f#$REPO/}:$ln (outside the population)"
    continue
  fi
  fence_body "$f" "$ln" >"$TMPROOT/ws-body"
  ws_has_wrapper "$TMPROOT/ws-body" || WS4_BAD="$WS4_BAD
${f#$REPO/}:$ln (not yet wrapped)"
done <"$WS_FLAGGED"
WS4_BAD=$(printf '%s\n' "$WS4_BAD" | grep -v '^$')
WS4_OUTSIDE_N=$(printf '%s\n' "$WS4_BAD" | grep -c '(outside the population)' 2>/dev/null || true)
WS4_OUTSIDE_N=${WS4_OUTSIDE_N:-0}
if [ -z "$WS4_BAD" ]; then
  ok "WS4: the scanner's flagged set ($WS_FLAGGED_N, illustration exempted) is fully accounted for by the population and already wrapped"
else
  bad "WS4: scanner-flagged fence(s) not accounted for or not yet wrapped ($WS4_OUTSIDE_N outside the population; the rest merely await wrapping):"
  printf '%s\n' "$WS4_BAD" | sed 's/^/        /'
fi

# plant: WS5 | plugin/scripts/tests/fence-shell-divergence-scan.sh | if [ "$PROBE_OUT" != "y" ]; then | if [ "$PROBE_OUT" = "y" ]; then

# WS5 (R-06): scanner denominator guard (ADR-0085, applied to the Task 1 reporter rather than to
# this file's own population). A scanner reporting nothing must be distinguishable from a corpus
# with nothing to report: it must classify NON-VACUOUSLY on a known-divergent fixture, and it must
# exit 3 — never a clean-looking empty result — when the awk in use cannot express its {n}
# interval rules (ADR-0046's receipt; secret-dep-gate.test.sh's C12 fake-awk idiom, reused here).
_ws5nonvac=0
_ws5out=$(printf 'for _t in $VAR\n' | bash "$SCANNER" 2>/dev/null)
[ -n "$_ws5out" ] && _ws5nonvac=1

_ws5fakedir="$TMPROOT/ws5-fakeawk"; mkdir -p "$_ws5fakedir"
printf '#!/bin/bash\nexit 0\n' >"$_ws5fakedir/awk"; chmod +x "$_ws5fakedir/awk"
printf '' | PATH="$_ws5fakedir:$PATH" bash "$SCANNER" >/dev/null 2>"$TMPROOT/ws5-err"
_ws5rc=$?

if [ "$_ws5nonvac" = "1" ] && [ "$_ws5rc" = "3" ]; then
  ok "WS5: the scanner classifies non-vacuously on a divergent fixture and exits 3 on an incapable awk"
else
  bad "WS5: scanner denominator guard failed (non-vacuous=$_ws5nonvac, incapable-awk rc=$_ws5rc, expected 1/3)"
fi

# No WS6 plant, and this corrects batch 3's stated reason rather than merely restating it. Batch 3
# declared one and reported it non-firing because "no fence yet carries a real positional token to
# catch", implying wrapping more fences would eventually produce one. Re-checked in batch 4 (issue
# #394, 5 fences now wrapped, verified with a scratch declaration before removing it): STILL DOES
# NOT FIRE, and the reason is NOT population size — this is a `must-not-happen` assertion
# (ADR-0112's negative-assertion class) over a corpus ADR-0132 already made TRUE by construction.
# A plant here can only redirect the detector from `\$[0-9]` to some other digit-suffixed pattern
# equally absent from every fence body, so both the real and the mutated detector report "nothing
# found" and no mutation can make them disagree. No amount of wrapping changes this: a real
# positional token appearing in the corpus would be a REGRESSION of ADR-0132, not progress toward
# a firing plant. A declared-but-permanently-non-firing plant would leave `plant-check.sh`'s own
# PC1 red forever, which is a worse signal than an honest absence — the same class WS9's own
# multi-line limit already carries above.
#
# WS6 (R-10): independent ADR-0132 cross-check — no population fence body contains a
# positional-parameter token. Cheap here because every population body is already extracted; the
# canonical guard is skill-fence-positional-tokens.test.sh, unaffected by this file either way.
WS6_BAD=""
while IFS="$(printf '\t')" read -r f ln marker kind; do
  [ -n "$f" ] || continue
  fence_body "$f" "$ln" >"$TMPROOT/ws-body"
  if grep -qE '\$[0-9]' "$TMPROOT/ws-body"; then
    WS6_BAD="$WS6_BAD
${f#$REPO/}:$ln"
  fi
done <"$WS_POP"
WS6_BAD=$(printf '%s\n' "$WS6_BAD" | grep -v '^$')
if [ -z "$WS6_BAD" ]; then
  ok "WS6: no population fence body contains a positional-parameter token ($WS_POP_N checked)"
else
  bad "WS6: population fence(s) containing a positional-parameter token (ADR-0132):"
  printf '%s\n' "$WS6_BAD" | sed 's/^/        /'
fi

# WS7 (R-05, ADR-0133 §D2): the no-marker decision is pinned as PROSE, bounded by the
# WS7-PROSE-START/END sentinels above. NO PLANT: the phrases checked below must appear in BOTH the
# prose (to state the decision) and this grep pattern (to check for it) if the search were
# unbounded, so a needle wide enough to hit the prose would also hit the code that reads it,
# failing the registry's exactly-one-match requirement (ADR-0108) — the same self-reference this
# file's own WS8/WS9 header already names for a different assertion. Bounding the search to the
# sentinel-delimited block (rather than the whole file) is what makes the CHECK itself sound, but
# it does not create a plantable target: mutating a phrase inside the bounded block still leaves an
# identical phrase in WS7's own code, two matches, a malformed declaration. Recorded as a limit,
# not worked around, per the plan's own instruction for a denominator/prose guard.
SELF_FILE="$TESTS/fence-contract-coverage.test.sh"
_ws7block=$(sed -n '/WS7-PROSE-START/,/WS7-PROSE-END/p' "$SELF_FILE")
_ws7missing=""
printf '%s\n' "$_ws7block" | grep -qi "carries no declaration marker" || _ws7missing="$_ws7missing declaration"
printf '%s\n' "$_ws7block" | grep -qi "second source of truth" || _ws7missing="$_ws7missing source-of-truth"
printf '%s\n' "$_ws7block" | grep -qi "presence in the body" || _ws7missing="$_ws7missing presence-is-evidence"
if [ -z "$_ws7missing" ]; then
  ok "WS7: the guard's own comments pin the D2 no-marker decision (statement + reason)"
else
  bad "WS7: the D2 no-marker decision is not fully pinned in prose — missing:$_ws7missing"
fi

# =====================================================================================
# E. The executions. Each contract gets BOTH directions: it must pass on a good fixture and abort
# on the bad one it exists to catch. A negative-case assertion pins nothing without its positive
# twin (the ADR-0039 lesson) — a check that aborts on everything satisfies the negative alone.

git_init() { git -C "$1" init -q 2>/dev/null; git -C "$1" config user.email t@t; git -C "$1" config user.name t; }

# mk_manifest <dest> <python patch expr>… — yaml round-trip, for the fences that read the manifest
# through `python3 -c "import yaml"`. Those never see the raw text, so re-emitted quoting is
# irrelevant to them; anything reaching manifest-validate.sh must use mk_manifest_text instead.
mk_manifest() {
  _dest="$1"; shift
  [ -n "$BASE_MANIFEST" ] || return 1
  python3 - "$BASE_MANIFEST" "$_dest" "$@" <<'PY'
import sys, yaml
src, dest = sys.argv[1], sys.argv[2]
m = yaml.safe_load(open(src))
for expr in sys.argv[3:]:
    exec(expr, {'m': m})
open(dest, 'w').write(yaml.safe_dump(m, sort_keys=False, allow_unicode=True))
PY
}

# ---- E1/E2: autopilot-build check 2 — manifest state -------------------------------------------
# Substitution: the `<manifest-path>` placeholder, and the deployed script prefix.
MAN_OK="$TMPROOT/ok.manifest.yml"
MAN_BAD="$TMPROOT/bad.manifest.yml"
mk_manifest_text "$MAN_OK"  "ready_for_implementation" "in_progress"
mk_manifest_text "$MAN_BAD" "step_2_architecture"      "in_progress"

: >"$TMPROOT/empty-setup"
if [ -n "$BASE_MANIFEST" ] && [ -s "$MAN_OK" ]; then
  _rc=$(run_fence "autopilot-build-check-2" "$AB" "$TMPROOT/empty-setup" "s|<manifest-path>|$MAN_OK|g")
  if [ "$_rc" = "0" ]; then ok "E1: check 2 passes a ready_for_implementation manifest"
  else bad "E1: check 2 rejected a valid manifest (rc=$_rc): $(head -2 "$TMPROOT/out-autopilot-build-check-2" 2>/dev/null | tr '\n' ' ')"; fi
  _rc=$(run_fence "autopilot-build-check-2" "$AB" "$TMPROOT/empty-setup" "s|<manifest-path>|$MAN_BAD|g")
  if [ "$_rc" = "1" ]; then ok "E2: check 2 aborts (exit 1) on the wrong current_step"
  else bad "E2: check 2 did not abort on current_step=step_2_architecture (rc=$_rc)"; fi
else
  bad "E1/E2: no manifest in the corpus validates cleanly — cannot build a fixture"
fi

# ---- E3/E4: autopilot-build check 3 — gates 1-3 approved ---------------------------------------
GATES_OK="$TMPROOT/g-ok.yml";  GATES_BAD="$TMPROOT/g-bad.yml"
mk_manifest "$GATES_OK" "m['hitl_gates']=[{'gate':n,'status':'approved'} for n in (1,2,3)]" 2>/dev/null
mk_manifest "$GATES_BAD" "m['hitl_gates']=[{'gate':1,'status':'approved'},{'gate':2,'status':'pending'},{'gate':3,'status':'approved'}]" 2>/dev/null
cat >"$TMPROOT/s3" <<EOF
manifest="\$MANIFEST_UNDER_TEST"
EOF
MANIFEST_UNDER_TEST="$GATES_OK"; export MANIFEST_UNDER_TEST
_rc=$(run_fence "autopilot-build-check-3" "$AB" "$TMPROOT/s3")
if [ "$_rc" = "0" ]; then ok "E3: check 3 passes when gates 1-3 are all approved"
else bad "E3: check 3 rejected three approved gates (rc=$_rc): $(head -2 "$TMPROOT/out-autopilot-build-check-3" 2>/dev/null | tr '\n' ' ')"; fi
MANIFEST_UNDER_TEST="$GATES_BAD"
_rc=$(run_fence "autopilot-build-check-3" "$AB" "$TMPROOT/s3")
if [ "$_rc" = "1" ]; then ok "E4: check 3 aborts (exit 1) when gate 2 is pending"
else bad "E4: check 3 did not abort on a pending gate 2 (rc=$_rc)"; fi

# ---- E5/E6: autopilot-build check 4 — artifacts on disk ----------------------------------------
mkdir -p "$TMPROOT/art"
: >"$TMPROOT/art/SPEC.md"; : >"$TMPROOT/art/ADR.md"; : >"$TMPROOT/art/PLAN.md"
ART_OK="$TMPROOT/a-ok.yml"; ART_BAD="$TMPROOT/a-bad.yml"
mk_manifest "$ART_OK" "m['artifacts']={'spec':'$TMPROOT/art/SPEC.md','adr':'$TMPROOT/art/ADR.md','plan':'$TMPROOT/art/PLAN.md'}" 2>/dev/null
mk_manifest "$ART_BAD" "m['artifacts']={'spec':'$TMPROOT/art/SPEC.md','adr':'$TMPROOT/art/nope.md','plan':'$TMPROOT/art/PLAN.md'}" 2>/dev/null
MANIFEST_UNDER_TEST="$ART_OK"
_rc=$(run_fence "autopilot-build-check-4" "$AB" "$TMPROOT/s3")
if [ "$_rc" = "0" ]; then ok "E5: check 4 passes when all three artifacts exist"
else bad "E5: check 4 rejected three existing artifacts (rc=$_rc): $(head -2 "$TMPROOT/out-autopilot-build-check-4" 2>/dev/null | tr '\n' ' ')"; fi
MANIFEST_UNDER_TEST="$ART_BAD"
_rc=$(run_fence "autopilot-build-check-4" "$AB" "$TMPROOT/s3")
if [ "$_rc" = "1" ]; then ok "E6: check 4 aborts (exit 1) on a manifest artifact path not on disk"
else bad "E6: check 4 did not abort on a missing artifact (rc=$_rc)"; fi

# ---- E7/E8/E9: autopilot-build check 6 — test-cmd real and TOFU-trusted ------------------------
# HOME is redirected so the trust registry is a fixture, not this machine's.
PR6="$TMPROOT/proj6"; mkdir -p "$PR6/.claude"
printf 'pytest -q\n' >"$PR6/.claude/test-cmd"
FAKE_HOME="$TMPROOT/home6"; mkdir -p "$FAKE_HOME/.claude/state/stop-gate"
H6=$(shasum -a 256 "$PR6/.claude/test-cmd" | awk '{print $1}')
R6=$(cd "$PR6" && pwd -P | tr '[:upper:]' '[:lower:]')
printf '%s\t%s\n' "$H6" "$R6" >"$FAKE_HOME/.claude/state/stop-gate/trust"
TC_OK="$TMPROOT/t-ok.yml"
mk_manifest "$TC_OK" "m['test_cmd_placeholder']=False" 2>/dev/null
# `CLAUDE_PLUGIN_ROOT` is bound because check 6 now reads test_cmd_placeholder through
# `manifest-field-state.sh` (issue #258), and `HOME` is redirected to a fixture — so the second
# resolution tier cannot find the helper and the first must. Same binding `scope-guards.test.sh`
# uses for check 7, which has had this dependency since ADR-0075.
#
# PYTHONPATH IS PINNED BECAUSE REDIRECTING HOME HIDES PyYAML. Python derives the per-user
# site-packages directory from $HOME, so a fixture HOME — set here so the TOFU trust registry is
# not this machine's — makes `import yaml` fail wherever PyYAML was installed with `pip --user`.
# The helper then correctly reports exit 3 ("the check DID NOT RUN") and check 6 correctly aborts,
# so the fixture, not the fence, is what is wrong. Discovered by E7/E9/E7d going red on a fence
# that was behaving exactly as designed. `scope-guards.test.sh` never hit this because its check-7
# runner does not redirect HOME. Resolve from the module itself rather than guessing a layout, so
# a system-installed PyYAML (the CI runner) is covered by the same line.
_YAMLPATH=$(python3 -c "import yaml,os; print(os.path.dirname(os.path.dirname(yaml.__file__)))" 2>/dev/null || true)
cat >"$TMPROOT/s6" <<EOF
HOME="$FAKE_HOME"; export HOME
PYTHONPATH="$_YAMLPATH\${PYTHONPATH:+:\$PYTHONPATH}"; export PYTHONPATH
CLAUDE_PLUGIN_ROOT="$STAGING/plugin"; export CLAUDE_PLUGIN_ROOT
manifest="\$MANIFEST_UNDER_TEST_6"
project_root="\$PROJECT_ROOT_UNDER_TEST"
EOF
PROJECT_ROOT_UNDER_TEST="$PR6"; export PROJECT_ROOT_UNDER_TEST
MANIFEST_UNDER_TEST_6="$TC_OK"; export MANIFEST_UNDER_TEST_6
_rc=$(run_fence "autopilot-build-check-6" "$AB" "$TMPROOT/s6")
if [ "$_rc" = "0" ]; then ok "E7: check 6 passes a real, TOFU-trusted test-cmd"
else bad "E7: check 6 rejected a trusted test-cmd (rc=$_rc): $(head -2 "$TMPROOT/out-autopilot-build-check-6" 2>/dev/null | tr '\n' ' ')"; fi
printf 'NONE\n' >"$PR6/.claude/test-cmd"
_rc=$(run_fence "autopilot-build-check-6" "$AB" "$TMPROOT/s6")
if [ "$_rc" = "1" ]; then ok "E8: check 6 aborts (exit 1) when test-cmd is NONE"
else bad "E8: check 6 did not abort on test-cmd=NONE (rc=$_rc)"; fi
printf 'pytest -q\n' >"$PR6/.claude/test-cmd"
: >"$FAKE_HOME/.claude/state/stop-gate/trust"
# The message is asserted, not just the exit code. Adding the helper dependency turned this green
# for the WRONG reason for one run — the fence aborted on an unresolvable helper, which is also
# rc=1 (rule 8: a negative assertion pins nothing when every failure looks alike).
_rc=$(run_fence "autopilot-build-check-6" "$AB" "$TMPROOT/s6")
if [ "$_rc" = "1" ] && grep -q 'TOFU-trusted' "$TMPROOT/out-autopilot-build-check-6" 2>/dev/null; then
  ok "E9: check 6 aborts (exit 1) when the command is not TOFU-trusted, naming TOFU"
else bad "E9: check 6 did not abort ON THE TOFU CAUSE (rc=$_rc): $(head -2 "$TMPROOT/out-autopilot-build-check-6" 2>/dev/null | tr '\n' ' ')"; fi
printf '%s\t%s\n' "$H6" "$R6" >"$FAKE_HOME/.claude/state/stop-gate/trust"

# ---- E7b..E7f: issue #258 — the placeholder read must fail CLOSED ------------------------------
# The line replaced here was `placeholder=$(python3 -c "… m.get('test_cmd_placeholder', False)"
# 2>/dev/null)` compared against "True". An unparseable manifest, or a missing PyYAML, produced an
# empty string that is not "True", so this UNATTENDED pre-flight PASSED.
#
# SEEN RED against the restored pre-#258 line: E7c (rc=0 — the unreadable manifest passed),
# E7e (rc=0 — 'maybe' accepted) and E7f (only one resolution block exists). E7/E7b/E7d/E8/E9
# are green before and after and are labelled as forward guards, not as evidence of the fix.
TC_TRUE="$TMPROOT/t-true.yml"; mk_manifest "$TC_TRUE" "m['test_cmd_placeholder']=True" 2>/dev/null
TC_BROKEN="$TMPROOT/t-broken.yml"; printf 'this: [is: not: valid: yaml\n' >"$TC_BROKEN"
TC_ABSENT="$TMPROOT/t-absent.yml"
grep -v '^test_cmd_placeholder:' "$TC_OK" >"$TC_ABSENT" 2>/dev/null
TC_JUNK="$TMPROOT/t-junk.yml"; mk_manifest "$TC_JUNK" "m['test_cmd_placeholder']='maybe'" 2>/dev/null

MANIFEST_UNDER_TEST_6="$TC_TRUE"
_rc=$(run_fence "autopilot-build-check-6" "$AB" "$TMPROOT/s6")
if [ "$_rc" = "1" ]; then ok "E7b (forward guard, green before and after): check 6 aborts when test_cmd_placeholder is true"
else bad "E7b: check 6 did not abort on test_cmd_placeholder=true (rc=$_rc)"; fi

MANIFEST_UNDER_TEST_6="$TC_BROKEN"
_rc=$(run_fence "autopilot-build-check-6" "$AB" "$TMPROOT/s6")
if [ "$_rc" = "1" ]; then ok "E7c (red evidence, #258): check 6 aborts on an UNREADABLE manifest instead of passing"
else bad "E7c: an unreadable manifest did NOT abort check 6 (rc=$_rc) — the unattended pre-flight still fails open (#258)"; fi

MANIFEST_UNDER_TEST_6="$TC_ABSENT"
_rc=$(run_fence "autopilot-build-check-6" "$AB" "$TMPROOT/s6")
if [ "$_rc" = "0" ]; then ok "E7d (forward guard, green before and after): an ABSENT field proceeds — the opposite of check 7, because the NONE and TOFU checks cover it"
else bad "E7d: check 6 aborted on an absent test_cmd_placeholder (rc=$_rc); 40 of 41 corpus manifests carry it and the one that does not predates the field"; fi

MANIFEST_UNDER_TEST_6="$TC_JUNK"
_rc=$(run_fence "autopilot-build-check-6" "$AB" "$TMPROOT/s6")
if [ "$_rc" = "1" ]; then ok "E7e: check 6 aborts on a value that is neither true nor false"
else bad "E7e: check 6 accepted test_cmd_placeholder='maybe' (rc=$_rc) — asserting the valid values is the ADR-0075 §D4 rule"; fi

# E7f — the two resolution blocks must agree. ADR-0086's criterion calls this extractable and it is
# deliberately NOT extracted: a fence borrowing a variable bound in an earlier fence stops being
# independently executable, which is what F4/F7 rest on. So the agreement is asserted instead.
_res6=$(extract_fence "$AB" "autopilot-build-check-6" | grep -F 'manifest-field-state.sh"' | sed 's/^[[:space:]]*//' | sort)
_res7=$(extract_fence "$AB" "autopilot-build-check-7" | grep -F 'manifest-field-state.sh"' | sed 's/^[[:space:]]*//' | sort)
if [ -n "$_res6" ] && [ "$_res6" = "$_res7" ]; then
  ok "E7f: checks 6 and 7 resolve manifest-field-state.sh by identical paths (two copies, pinned to agree)"
else
  bad "E7f: the two manifest-field-state.sh resolution blocks have diverged — check 6 and check 7 must find the same helper"
fi
MANIFEST_UNDER_TEST_6="$TC_OK"

# ---- E10/E11: autopilot-build check 8 — git repo at CWD ----------------------------------------
GITD="$TMPROOT/g"; mkdir -p "$GITD"; git_init "$GITD"
NOGIT="$TMPROOT/nog"; mkdir -p "$NOGIT"
printf 'cd %s\n' "$GITD" >"$TMPROOT/s8ok"
printf 'cd %s\nGIT_CEILING_DIRECTORIES=%s; export GIT_CEILING_DIRECTORIES\n' "$NOGIT" "$TMPROOT" >"$TMPROOT/s8bad"
_rc=$(run_fence "autopilot-build-check-8" "$AB" "$TMPROOT/s8ok")
if [ "$_rc" = "0" ]; then ok "E10: check 8 passes inside a git repository"
else bad "E10: check 8 failed inside a git repository (rc=$_rc)"; fi
_rc=$(run_fence "autopilot-build-check-8" "$AB" "$TMPROOT/s8bad")
if [ "$_rc" = "1" ]; then ok "E11: check 8 aborts (exit 1) outside a git repository"
else bad "E11: check 8 did not abort outside a git repository (rc=$_rc)"; fi

# ---- E12/E13: autopilot pre-flight 3 — publish opt-in marker --------------------------
NP="$TMPROOT/autopilot"; mkdir -p "$NP/.claude"
printf 'publish: true\n' >"$NP/.claude/autopilot.yml"
printf 'cd %s\n' "$NP" >"$TMPROOT/sn"
_rc=$(run_fence "autopilot-optin" "$NA" "$TMPROOT/sn")
if [ "$_rc" = "0" ]; then ok "E12: autopilot opt-in passes with publish: true"
else bad "E12: autopilot opt-in rejected publish: true (rc=$_rc): $(head -2 "$TMPROOT/out-autopilot-optin" 2>/dev/null | tr '\n' ' ')"; fi
printf 'publish: false\n' >"$NP/.claude/autopilot.yml"
_rc=$(run_fence "autopilot-optin" "$NA" "$TMPROOT/sn")
if [ "$_rc" = "1" ]; then ok "E13: autopilot opt-in aborts (exit 1) on publish: false"
else bad "E13: autopilot opt-in did not abort on publish: false (rc=$_rc)"; fi
rm -f "$NP/.claude/autopilot.yml"
_rc=$(run_fence "autopilot-optin" "$NA" "$TMPROOT/sn")
if [ "$_rc" = "1" ]; then ok "E14: autopilot opt-in aborts (exit 1) when the marker is absent"
else bad "E14: autopilot opt-in did not abort on an absent marker (rc=$_rc)"; fi

# ---- E15/E16: claude-md-slim — backup must refuse to overwrite --------------------------------
CMSD="$TMPROOT/cms"; mkdir -p "$CMSD"
printf '# CLAUDE.md\n' >"$CMSD/CLAUDE.md"
printf 'CLAUDE_MD=%s\n' "$CMSD/CLAUDE.md" >"$TMPROOT/scms"
_rc=$(run_fence "claude-md-slim-backup" "$CMS" "$TMPROOT/scms")
if [ "$_rc" = "0" ] && [ -f "$CMSD/CLAUDE.md.bak-$(date +%Y-%m-%d)" ]; then
  ok "E15: claude-md-slim backup creates today's .bak and exits 0"
else
  bad "E15: backup did not produce today's .bak (rc=$_rc)"
fi
_rc=$(run_fence "claude-md-slim-backup" "$CMS" "$TMPROOT/scms")
if [ "$_rc" = "1" ]; then ok "E16: backup aborts (exit 1) rather than overwriting an existing same-day backup"
else bad "E16: backup overwrote an existing same-day backup (rc=$_rc) — data loss path"; fi

# ---- E17/E18/E19: commit Step 3.6 — never commit to the default branch -------------------------
CR="$TMPROOT/cr"; mkdir -p "$CR"; git_init "$CR"
( cd "$CR" && printf 'x\n' >f && git add f && git commit -qm init )
DEF=$(git -C "$CR" branch --show-current)
cat >"$TMPROOT/scmt" <<EOF
cd $CR
default_branch="$DEF"
type="feat"
subject="\$SUBJECT_UNDER_TEST"
EOF
SUBJECT_UNDER_TEST="Add rate limiter"; export SUBJECT_UNDER_TEST
_rc=$(run_fence "commit-ensure-feature-branch" "$CMT" "$TMPROOT/scmt")
_now=$(git -C "$CR" branch --show-current)
if [ "$_rc" = "0" ] && [ "$_now" = "feat/add-rate-limiter" ]; then
  ok "E17: commit Step 3.6 moves off the default branch onto feat/add-rate-limiter"
else
  bad "E17: expected branch feat/add-rate-limiter (rc=$_rc), on '$_now': $(head -2 "$TMPROOT/out-commit-ensure-feature-branch" 2>/dev/null | tr '\n' ' ')"
fi
# On a feature branch it must be a no-op — the other half of the same contract.
_rc=$(run_fence "commit-ensure-feature-branch" "$CMT" "$TMPROOT/scmt")
_now2=$(git -C "$CR" branch --show-current)
if [ "$_rc" = "0" ] && [ "$_now2" = "feat/add-rate-limiter" ]; then
  ok "E18: on a feature branch Step 3.6 is a no-op, no second branch created"
else
  bad "E18: Step 3.6 was not a no-op on a feature branch (rc=$_rc, now '$_now2')"
fi
# The slug guard: a subject that would produce the default branch's own name must not.
git -C "$CR" checkout -q "$DEF"
SUBJECT_UNDER_TEST="main"
_rc=$(run_fence "commit-ensure-feature-branch" "$CMT" "$TMPROOT/scmt")
_now3=$(git -C "$CR" branch --show-current)
case "$_now3" in
  feat/main-changes) ok "E19: a subject of 'main' is rewritten to feat/main-changes, never feat/main" ;;
  *) bad "E19: expected feat/main-changes, got '$_now3' (rc=$_rc)" ;;
esac

# ---- E20: concept-to-code merge-back is declared an ILLUSTRATION -------------------------------
# Not covered by an execution, and that is the decision rather than a gap: the fence carries
# `<base-fork halt: …>` pseudo-code and does not parse. F7 would fail if it were declared a
# contract; this asserts the declaration is the illustration one, so a later edit that makes it
# executable has to change the marker and pick up an execution with it.
# VCS-047/ADR-0174: the merge-back fence moved into references/step5-implementation.md.
CCM="$SKILLS/concept-to-code/references/step5-implementation.md"
if enumerate_fences "$CCM" | grep -q 'fence-illustration:'; then
  ok "E20: the merge-back fence is declared an illustration, with its reason"
else
  bad "E20: concept-to-code carries no illustration declaration — the pseudo-code fence is unmarked"
fi

# =====================================================================================
# WSC-WSH. issue #394 / ADR-0133 Task 5 — the three `commit` fences that acquire a
# `fence-contract` marker for the first time. Every one is a bare computation block with no
# existing stdout/exit-code contract (unmarked before Task 5), so `run_fence` alone can only prove
# the wrapped form does not crash — folded in below as a smoke check — and `run_fence_logic`'s
# unwrap bypass (above) is what makes the fence's OWN variables observable for the real assertion.
# EXTRACT_FAILED before Task 5 lands the markers is the expected RED here (batch 3): these three
# ids do not exist as `fence-contract` declarations in commit/SKILL.md until the coder acts.
#
# NO `# plant:` FOR WSC-WSH (see WS9's precedent two sections above for the same kind of limit,
# stated rather than worked around). A plant's target must exist, TODAY, under staging/ — but the
# `fence-contract` marker and the ADR-0133 wrapper these executions extract by do not exist in
# commit/SKILL.md until Task 5 lands them, so a declaration naming the WRAPPED body's text would
# fail plant-check.sh's "target not found" guard outright. Targeting the fence's PRE-MARKER raw
# logic instead would not test anything either: extract_fence fails on the missing marker before
# it ever reads that logic, so WSC/WSE/WSG are ALREADY `FAIL: <id>` today for a reason that has
# nothing to do with any mutation — exactly the false "fired" plant-check.sh's own NOFIRE check
# exists to catch, not produce (ADR-0090's "inspect what a plant actually produced", applied here
# before writing one rather than after). Verified in the scratchpad instead, against a hand-built
# fixture simulating the post-Task-5 wrapped/marked form: each of WSC/WSD/WSE/WSF/WSG/WSH's
# assertions passes on its GOOD/BAD input as designed, AND flips to a wrong result under a
# hand-mutation of the corresponding fence logic (the comma split, the classification regex, the
# staging loop) — the assertions have real discriminating power even though nothing here can
# declare that mutation as a registry plant yet. A later batch, once the markers exist, should add
# `# plant:` lines for WSC-WSH mutating the actual fence logic in commit/SKILL.md.

# ---- WSC/WSD: commit-step1-include-resolve -------------------------------------------------
INCD="$TMPROOT/incl"; mkdir -p "$INCD"
: >"$INCD/a.txt"; : >"$INCD/b.txt"
cat >"$TMPROOT/s_incl_good" <<EOF
include_flag="$INCD/a.txt,$INCD/b.txt"
EOF
cat >"$TMPROOT/s_incl_bad" <<EOF
include_flag="$INCD/a.txt,$INCD/does-not-exist.txt"
EOF
cat >"$TMPROOT/t_incl" <<'EOF'
printf 'PATHS=%s\n' "$(printf '%s' "$include_paths" | tr '\n' ',')"
printf 'MISSING=[%s]\n' "$_missing"
EOF

_rc_wrapped=$(run_fence "commit-step1-include-resolve" "$CMT" "$TMPROOT/s_incl_good")
_rc_logic=$(run_fence_logic "commit-step1-include-resolve" "$CMT" "$TMPROOT/s_incl_good" "$TMPROOT/t_incl")
_out_logic=$(cat "$TMPROOT/outlogic-commit-step1-include-resolve" 2>/dev/null)
if [ "$_rc_wrapped" = "0" ] && [ "$_rc_logic" = "0" ] \
   && printf '%s' "$_out_logic" | grep -qF "PATHS=$INCD/a.txt,$INCD/b.txt" \
   && printf '%s' "$_out_logic" | grep -qF 'MISSING=[]'; then
  ok "WSC: commit-step1-include-resolve splits a multi-path --include value into each path individually, none missing"
else
  bad "WSC: commit-step1-include-resolve (wrapped rc=$_rc_wrapped, logic rc=$_rc_logic): $(printf '%s' "$_out_logic" | tr '\n' ' ')"
fi

_rc_logic=$(run_fence_logic "commit-step1-include-resolve" "$CMT" "$TMPROOT/s_incl_bad" "$TMPROOT/t_incl")
_out_logic=$(cat "$TMPROOT/outlogic-commit-step1-include-resolve" 2>/dev/null)
if [ "$_rc_logic" = "0" ] \
   && printf '%s' "$_out_logic" | grep -qF "PATHS=$INCD/a.txt,$INCD/does-not-exist.txt" \
   && printf '%s' "$_out_logic" | grep -qF "MISSING=[ $INCD/does-not-exist.txt]"; then
  ok "WSD: commit-step1-include-resolve flags a nonexistent path in \$_missing while the existing path is still resolved individually"
else
  bad "WSD: commit-step1-include-resolve did not flag the missing path individually: $(printf '%s' "$_out_logic" | tr '\n' ' ')"
fi

# ---- WSE/WSF: commit-h4-test-diff-classify --------------------------------------------------
# The regression this whole feature exists to fix: under the host shell's word-split bug the loop
# below classified EVERY changed file as a test file (observed live on 2026-08-08). WSE is the
# required mixed-set case (one test file, one non-test file, classified as one of each); WSF is
# the negative control the bug's own symptom names directly — a purely non-test change must not
# appear in test_files at all.
H4D="$TMPROOT/h4repo"; mkdir -p "$H4D/src" "$H4D/tests"
git_init "$H4D"
printf 'x = 1\n' >"$H4D/src/foo.py"
printf 'def test_foo():\n    pass\n' >"$H4D/tests/test_foo.py"
( cd "$H4D" && git add -A && git commit -qm init >/dev/null )
printf 'x = 2\n' >>"$H4D/src/foo.py"
printf '    pass\n' >>"$H4D/tests/test_foo.py"

cat >"$TMPROOT/s_h4_mixed" <<EOF
cd "$H4D"
staged=""
tracked_modified="src/foo.py
tests/test_foo.py"
untracked=""
EOF
cat >"$TMPROOT/s_h4_nontest" <<EOF
cd "$H4D"
staged=""
tracked_modified="src/foo.py"
untracked=""
EOF
cat >"$TMPROOT/t_h4" <<'EOF'
printf 'TEST_FILES=[%s]\n' "$(printf '%s' "$test_files" | tr '\n' '|')"
EOF

_rc_wrapped=$(run_fence "commit-h4-test-diff-classify" "$CMT" "$TMPROOT/s_h4_mixed")
_rc_logic=$(run_fence_logic "commit-h4-test-diff-classify" "$CMT" "$TMPROOT/s_h4_mixed" "$TMPROOT/t_h4")
_out_logic=$(cat "$TMPROOT/outlogic-commit-h4-test-diff-classify" 2>/dev/null)
if [ "$_rc_wrapped" = "0" ] && [ "$_rc_logic" = "0" ] \
   && printf '%s' "$_out_logic" | grep -qF 'TEST_FILES=[tests/test_foo.py]'; then
  ok "WSE: commit-h4-test-diff-classify classifies a mixed changed set as one test file and one non-test file (src/foo.py is excluded)"
else
  bad "WSE: commit-h4-test-diff-classify (wrapped rc=$_rc_wrapped, logic rc=$_rc_logic): $(printf '%s' "$_out_logic" | tr '\n' ' ')"
fi

_rc_logic=$(run_fence_logic "commit-h4-test-diff-classify" "$CMT" "$TMPROOT/s_h4_nontest" "$TMPROOT/t_h4")
_out_logic=$(cat "$TMPROOT/outlogic-commit-h4-test-diff-classify" 2>/dev/null)
if [ "$_rc_logic" = "0" ] && printf '%s' "$_out_logic" | grep -qF 'TEST_FILES=[]'; then
  ok "WSF: commit-h4-test-diff-classify leaves test_files EMPTY for a purely non-test change — the exact symptom (every changed file read as a test file) this feature fixes"
else
  bad "WSF: commit-h4-test-diff-classify misclassified a non-test-only change: $(printf '%s' "$_out_logic" | tr '\n' ' ')"
fi

# ---- WSG/WSH: commit-step5-include-stage ----------------------------------------------------
# Unlike the two fences above, this one's effect (a real git commit) persists on disk regardless
# of which shell ran it, so plain `run_fence` — the wrapped form, exactly as the orchestrator
# would run it — is enough on its own; no unwrap_body bypass is needed here.
CR5="$TMPROOT/cr5"; mkdir -p "$CR5"; git_init "$CR5"
( cd "$CR5" && printf 'x\n' >tracked.txt && git add tracked.txt && git commit -qm init >/dev/null )
: >"$CR5/inc1.txt"; : >"$CR5/inc2.txt"
cat >"$TMPROOT/s_stage_good" <<EOF
cd "$CR5"
staged=""
tracked_modified=""
include_paths="inc1.txt
inc2.txt"
EOF
_rc=$(run_fence "commit-step5-include-stage" "$CMT" "$TMPROOT/s_stage_good" "s|<commit-message>|WSG test commit|")
_tracked=$(git -C "$CR5" ls-tree -r --name-only HEAD 2>/dev/null | sort | tr '\n' ',')
_subj=$(git -C "$CR5" log -1 --pretty=%s 2>/dev/null)
if [ "$_rc" = "0" ] && [ "$_tracked" = "inc1.txt,inc2.txt,tracked.txt," ] && [ "$_subj" = "WSG test commit" ]; then
  ok "WSG: commit-step5-include-stage stages every --include path individually and commits them, alongside git add -u's default scope"
else
  bad "WSG: commit-step5-include-stage (rc=$_rc, tracked=[$_tracked], subject='$_subj')"
fi

CR6="$TMPROOT/cr6"; mkdir -p "$CR6"; git_init "$CR6"
( cd "$CR6" && printf 'x\n' >tracked.txt && git add tracked.txt && git commit -qm init >/dev/null )
printf 'y\n' >>"$CR6/tracked.txt"
: >"$CR6/inc1.txt"
cat >"$TMPROOT/s_stage_empty" <<EOF
cd "$CR6"
staged=""
tracked_modified="tracked.txt"
include_paths=""
EOF
_rc=$(run_fence "commit-step5-include-stage" "$CMT" "$TMPROOT/s_stage_empty" "s|<commit-message>|WSH test commit|")
_tracked=$(git -C "$CR6" ls-tree -r --name-only HEAD 2>/dev/null | sort | tr '\n' ',')
_subj=$(git -C "$CR6" log -1 --pretty=%s 2>/dev/null)
if [ "$_rc" = "0" ] && [ "$_tracked" = "tracked.txt," ] && [ "$_subj" = "WSH test commit" ]; then
  ok "WSH: commit-step5-include-stage's loop is a no-op on an empty --include value, staging only git add -u's default scope (today's behaviour for every caller that does not pass --include)"
else
  bad "WSH: commit-step5-include-stage (rc=$_rc, tracked=[$_tracked], subject='$_subj') — an empty include set must not stage inc1.txt"
fi

# ---- WSL: commit-step5-include-stage, VCS-011 regression pin --------------------------------
# The actual bug (2026-08-05): a concurrent session modifies a tracked file AFTER Step 1 computed
# its approved scope but BEFORE Step 5 stages and commits — `git add -u` sweeps it in regardless,
# with nothing that ever compares what actually got staged against what the human approved. Here
# `tracked_modified` (Step 1's snapshot) names only `known.txt`; `surprise.txt` is modified in the
# working tree afterward, simulating the other session's edit, then the fence itself runs. It must
# abort BEFORE `git commit` — no new commit, `surprise.txt` named in the error — never silently
# include it the way the live incident did.
CR7="$TMPROOT/cr7"; mkdir -p "$CR7"; git_init "$CR7"
( cd "$CR7" && printf 'x\n' >known.txt && printf 'x\n' >surprise.txt \
    && git add known.txt surprise.txt && git commit -qm init >/dev/null )
_head_before=$(git -C "$CR7" rev-parse HEAD)
printf 'known-change\n' >>"$CR7/known.txt"
printf 'unapproved-change\n' >>"$CR7/surprise.txt"
cat >"$TMPROOT/s_stage_abort" <<EOF
cd "$CR7"
staged=""
tracked_modified="known.txt"
include_paths=""
EOF
_rc=$(run_fence "commit-step5-include-stage" "$CMT" "$TMPROOT/s_stage_abort" "s|<commit-message>|WSL test commit|")
_out=$(cat "$TMPROOT/out-commit-step5-include-stage" 2>/dev/null)
_head_after=$(git -C "$CR7" rev-parse HEAD)
if [ "$_rc" != "0" ] && [ "$_head_after" = "$_head_before" ] \
   && printf '%s' "$_out" | grep -qF "surprise.txt"; then
  ok "WSL: commit-step5-include-stage aborts (rc=$_rc, no new commit) and names surprise.txt when git add -u sweeps in a tracked file outside Step 1's approved scope (VCS-011)"
else
  bad "WSL: commit-step5-include-stage (rc=$_rc, head_before=$_head_before, head_after=$_head_after): $_out — must abort without committing and name the unexpected file"
fi

# =====================================================================================
# WSI-WSK (issue #394 batch 4, ADR-0133): pinning the CLASS that broke
# human-gate-coverage.test.sh's run_h4() when batch 3 wrapped 5 fences. A test file that
# extracts a fence body, embeds it into a script, executes it, and then reads a raw shell
# variable the fence body BOUND (as opposed to only its stdout/exit code) breaks silently
# the moment that fence gets the ADR-0133 wrapper: the variable dies at the wrapper's
# closing `FENCE_BASH` terminator, invisible to a trailing script appended in the same
# process. This file's own `run_fence_logic` (Task 2) already answers it for THIS file;
# WSI-WSK answer it for every OTHER *.test.sh, so the next fence Task 6/7 wraps cannot
# silently reintroduce the same break in a fourth file the way it did in a first.
#
# WSI: population — every *.test.sh performing the dynamic fence-extraction-and-execution
# idiom is derived at run time from the "infence" awk state-variable name every such file's
# extraction shares (`fence_body`, `extract_fence`, `extract_conductor_lookup`, and this
# file's own `enumerate_fences` all use it), never a hardcoded file list. A denominator
# guard, the ADR-0085 T0b/J0a shape: zero matches would be indistinguishable from "the
# idiom moved to a different marker" without a floor on the CANDIDATE count, as opposed to
# the leak count WSJ/WSK check below.
WSI_POP="$TMPROOT/wsi-pop"; : >"$WSI_POP"
for _wf in "$TESTS"/*.test.sh; do
  grep -q 'infence' "$_wf" 2>/dev/null && printf '%s\n' "$_wf" >>"$WSI_POP"
done
WSI_POP_N=$(grep -c . "$WSI_POP" 2>/dev/null || true); WSI_POP_N=${WSI_POP_N:-0}
if [ "$WSI_POP_N" -ge 8 ]; then
  ok "WSI: $WSI_POP_N test file(s) perform dynamic fence extraction+execution (the 'infence' idiom) — the population WSJ/WSK check below"
else
  bad "WSI: only $WSI_POP_N test file(s) found via the 'infence' idiom — expected >= 8; the derivation is broken, not clean"
fi

# plant: WSK | plugin/scripts/tests/fence-contract-coverage.test.sh | test_files|test_diff|test_diff_truncated|test_diff_total_lines|include_paths|_missing|_manifest|tasks|openers|_troot|_autopilot|_fork_from|_scripts | ZZZNOTAREALVARZZZ
#
# The leak signature: the closed list of fence-INTERNAL variable names named in ADR-0133
# §Measured facts' outbound-direction table (test_files, test_diff, test_diff_truncated,
# test_diff_total_lines, include_paths, _missing, _manifest — plus this batch's own two
# additions, tasks/openers from concept-to-code-step5-plan-structure and _troot/_autopilot/
# _fork_from/_scripts named in the same table but read by no test today) interpolated as
# "$name" on a NON-comment line. Comment lines are excluded deliberately: `_autopilot` and
# `_fork_from` both appear this way inside `# plant:` declaration lines in
# conductor-entry-failure-split.test.sh (CDA1/CDA3/FK12) that legitimately name the
# fence-internal variables they mutate without reading them across a process boundary —
# rule 12 applied to this guard's own derivation before it shipped a false positive, not
# found after.
WSJ_LEAK="test_files|test_diff|test_diff_truncated|test_diff_total_lines|include_paths|_missing|_manifest|tasks|openers|_troot|_autopilot|_fork_from|_scripts"
WSJ_PATTERN='"\$('"$WSJ_LEAK"')"'
WSJ_ATRISK="$TMPROOT/wsj-atrisk"; : >"$WSJ_ATRISK"
while IFS= read -r _wf; do
  [ -n "$_wf" ] || continue
  if grep -v '^[[:space:]]*#' "$_wf" | grep -qE "$WSJ_PATTERN"; then
    printf '%s\n' "$_wf" >>"$WSJ_ATRISK"
  fi
done <"$WSI_POP"
WSJ_ATRISK_N=$(grep -c . "$WSJ_ATRISK" 2>/dev/null || true); WSJ_ATRISK_N=${WSJ_ATRISK_N:-0}
if [ "$WSJ_ATRISK_N" -ge 3 ]; then
  ok "WSK: $WSJ_ATRISK_N test file(s) exhibit the leak signature — the WSJ invariant below is non-vacuous"
else
  bad "WSK: only $WSJ_ATRISK_N test file(s) exhibit the leak signature, expected >= 3 — the leak-pattern list is broken (silently makes WSJ pass on nothing), not clean"
fi

# plant: WSJ | plugin/scripts/tests/human-gate-coverage.test.sh | unwrap_body "$H4_BLOCK" > "$H4_INNER" | cat "$H4_BLOCK" > "$H4_INNER"
#
# WSJ's plant targets a DIFFERENT file than the one this assertion lives in — legal because
# plant-check.sh sandboxes the whole `staging/` tree, not just the declaring file, and this
# assertion re-derives its population from `$TESTS/*.test.sh` at RUN TIME, so the mutated
# copy of human-gate-coverage.test.sh inside the sandbox is exactly what WSI/WSJ see when
# fence-contract-coverage.test.sh (the file the runner actually executes and greps for
# `FAIL: WSJ`) runs there. The needle is this batch's own Job 1 fix at its one call site —
# reverting it reproduces the ORIGINAL break verbatim (HIB1a/HIB1b/HIB3a/HIB3b/HIB4a, all RED
# before that fix), which is what WSJ exists to catch a fourth instance of.
#
# WSJ: the invariant itself — every at-risk file also INVOKES unwrap_body (`unwrap_body "`,
# a space then a quote, so a bare `unwrap_body() {` definition line does not self-satisfy
# and a prose mention like "Task 2's unwrap_body" does not either — verified against every
# existing occurrence in this file and in conductor-entry-failure-split.test.sh before
# shipping). Known, disclosed limit: this is FILE-LEVEL presence, not per-leak-site
# verification — a file with two leak sites where only one calls unwrap_body still passes.
# Tightening to per-site verification needs a shape-independent way to locate "the trailing
# script for THIS extraction" across four differently-written call sites, which risks
# fragility beyond a batch dispatch; the same class of scoped predicate limitation
# ADR-0085 accepted for `compliant()` rather than perfected.
WSJ_BAD=""
while IFS= read -r _wf; do
  [ -n "$_wf" ] || continue
  grep -q 'unwrap_body "' "$_wf" 2>/dev/null || WSJ_BAD="$WSJ_BAD
${_wf#$REPO/}"
done <"$WSJ_ATRISK"
WSJ_BAD=$(printf '%s\n' "$WSJ_BAD" | grep -v '^$')
if [ -z "$WSJ_BAD" ]; then
  ok "WSJ: every test file reading a fence-internal variable across a process boundary also invokes unwrap_body ($WSJ_ATRISK_N checked)"
else
  bad "WSJ: test file(s) reading a fence-internal variable with NO unwrap_body bypass — will silently break the moment their target fence is wrapped:"
  printf '%s\n' "$WSJ_BAD" | sed 's/^/        /'
fi

# =====================================================================================
# WSA/WSB (issue #394 Task 8, ADR-0133 R-06/R-07). THE EXECUTED PROOF.
#
# Every other assertion in this harness — indeed in every harness this repository has — runs an
# extracted fence body through `bash` (`run_fence`, `F7`, WS3's `unwrap_body` + `bash -n`, and so
# on). That is correct for what those assertions check, and it means the WHOLE SUITE is blind by
# construction to the defect this feature exists to fix: the shell that actually executes a fence
# when the model runs it is whatever the Bash tool's session shell is — zsh 5.9 on this machine —
# never bash. WS1 proves the wrapper TEXT is present, a structural check that proves a SHAPE. It
# cannot prove that shape produces the same BEHAVIOUR under the shell that actually runs it. This
# is the one assertion in the entire feature that can observe the failing quantity at all.
#
# Fence chosen: autopilot-check-6 (the plan's other candidate, autopilot-scope-args, needs a
# multi-token CLI argument list; this one's C1b divergence — `for _m in $_manifests` — is
# exercisable with a two-manifest-file fixture already the same shape as this file's own E7-E9
# fixtures). Never an arbitrary fence: a shell-agnostic body would pass under either shell and pin
# nothing about the wrapper actually doing its job.
#
# WSA extracts the WRAPPED fence — export prologue + `bash <<'FENCE_BASH' … FENCE_BASH`, byte-for-
# byte the text `run_fence` would execute — and runs that SAME outer script under `zsh` and under
# `bash`, comparing stdout and exit code. They must be byte-identical: a quoted heredoc opener is
# parsed identically by both outer shells (neither expands anything inside a quoted heredoc body),
# so the body is handed to a literal `bash` subprocess regardless of which shell reads the wrapper
# — the entire point of D1.
#
# WSB is the required NEGATIVE TWIN (a negative-case assertion pins nothing without its positive
# twin — ADR-0039's lesson, applied here in the OPPOSITE direction for the first time: the twin
# that must diverge, not the twin that must agree). It takes the SAME fence body, but UNWRAPPED
# (Task 2's `unwrap_body` — the here-document content alone, with no `bash <<'FENCE_BASH'` wrapper
# around it), and runs THAT under zsh and under bash directly. Those two MUST differ, or WSA could
# be passing merely because this fixture happens to be shell-agnostic, and WSA would then be unable
# to distinguish a working wrapper from a fence that never diverged in the first place.
#
# Both were measured live before either assertion was written (rc, stdout, both directions), on
# zsh 5.9 / bash 3.2.57 — see the ADR's Verification section for the recorded transcript.
#
# ZSH-ABSENT (the SPEC's own edge case, the ADR-0032 CI-dark class): if `zsh` is not on PATH, WSA
# and WSB CANNOT run — and a check that did not run must never read as a check that found nothing.
# Both assertions FAIL explicitly with a ZSH-ABSENT message; there is no skip path, and neither
# assertion is omitted from PASS+FAIL. Verified by hiding zsh from PATH (a PATH stripped to just
# the directories holding bash/grep/sed/awk/mktemp, with no zsh on it) and confirming the fall-
# through calls `bad`, not that the assertion count silently drops by two.
WSAB_PROJ="$TMPROOT/wsab-proj"
mkdir -p "$WSAB_PROJ/docs/manifests"
printf 'current_step: "completed"\nstatus: "completed"\nhook_verified: true\n' >"$WSAB_PROJ/docs/manifests/a.manifest.yml"
printf 'current_step: "completed"\nstatus: "completed"\n' >"$WSAB_PROJ/docs/manifests/b.manifest.yml"

ZSH_BIN=""
command -v zsh >/dev/null 2>&1 && ZSH_BIN=$(command -v zsh)

if [ -z "$ZSH_BIN" ]; then
  bad "WSA: ZSH-ABSENT — zsh is not on PATH, the executed proof could not run (never a silent skip)"
  bad "WSB: ZSH-ABSENT — zsh is not on PATH, the negative twin could not run (never a silent skip)"
else
  _wsab_outer=$(extract_fence "$NA" "autopilot-check-6") || _wsab_outer=""
  if [ -z "$_wsab_outer" ]; then
    bad "WSA: could not extract autopilot-check-6's fence body"
    bad "WSB: could not extract autopilot-check-6's fence body"
  else
    printf '%s\n' "$_wsab_outer" | subst_paths >"$TMPROOT/wsab-outer"

    {
      printf 'cd "%s"\n' "$WSAB_PROJ"
      printf 'CLAUDE_PLUGIN_ROOT="%s/plugin"; export CLAUDE_PLUGIN_ROOT\n' "$STAGING"
      cat "$TMPROOT/wsab-outer"
    } >"$TMPROOT/wsa-script"

    _wsa_out_zsh=$("$ZSH_BIN" "$TMPROOT/wsa-script" 2>&1); _wsa_rc_zsh=$?
    _wsa_out_bash=$(bash "$TMPROOT/wsa-script" 2>&1); _wsa_rc_bash=$?

    if [ "$_wsa_rc_zsh" = "$_wsa_rc_bash" ] && [ "$_wsa_out_zsh" = "$_wsa_out_bash" ]; then
      ok "WSA: autopilot-check-6's WRAPPED body is byte-identical under zsh and bash (rc=$_wsa_rc_bash, stdout: $(printf '%s' "$_wsa_out_bash" | head -1 | cut -c1-60)…)"
    else
      bad "WSA: autopilot-check-6's wrapped body diverges between shells — zsh(rc=$_wsa_rc_zsh): $(printf '%s' "$_wsa_out_zsh" | tr '\n' ' ') || bash(rc=$_wsa_rc_bash): $(printf '%s' "$_wsa_out_bash" | tr '\n' ' ')"
    fi

    unwrap_body "$TMPROOT/wsab-outer" >"$TMPROOT/wsab-inner"
    {
      printf 'cd "%s"\n' "$WSAB_PROJ"
      printf 'CLAUDE_PLUGIN_ROOT="%s/plugin"; export CLAUDE_PLUGIN_ROOT\n' "$STAGING"
      cat "$TMPROOT/wsab-inner"
    } >"$TMPROOT/wsb-script"

    _wsb_out_zsh=$("$ZSH_BIN" "$TMPROOT/wsb-script" 2>&1); _wsb_rc_zsh=$?
    _wsb_out_bash=$(bash "$TMPROOT/wsb-script" 2>&1); _wsb_rc_bash=$?

    if [ "$_wsb_rc_zsh" != "$_wsb_rc_bash" ] || [ "$_wsb_out_zsh" != "$_wsb_out_bash" ]; then
      ok "WSB: the SAME body UNWRAPPED diverges between shells — zsh(rc=$_wsb_rc_zsh) vs bash(rc=$_wsb_rc_bash) — confirms WSA is not shell-agnostic by accident"
    else
      bad "WSB: the unwrapped body did NOT diverge between zsh and bash (both rc=$_wsb_rc_bash, identical stdout) — WSA cannot be trusted to distinguish a working wrapper from a fence that never diverged"
    fi
  fi
fi

# Z1: assertion-count FLOOR, the same guard added to scope-guards.test.sh and
# plan-task-count.test.sh in this change. Every E-section assertion depends on an extraction, so a
# broken marker could take a dozen of them out of the run — and a suite reporting fewer assertions
# than yesterday does not read as broken. Measured on the two neighbours: rewording one heading
# turned "43 passed, 0 failed" into "35 passed, 2 failed". Lowering the floor needs a deliberate edit.
#
# Raised 37 -> 55 for issue #394 Task 3 (ADR-0133): WS0-WS7 add 8 assertions to the 47 this file
# already counted AT THIS CHECKPOINT (Z1 measures $_TOTAL before its own verdict is added, so the
# pre-existing 48-assertion whole-file total is 47 here plus Z1 itself). Left at 37 it would have
# carried 18 units of slack — enough to absorb every one of the eight vanishing and still read
# PASS, the exact defect ADR-0124 removed from SP5's `SLOT` count, reintroduced here by the very
# change that adds assertions if the floor were left unmoved.
#
# Raised 55 -> 61 for issue #394 Task 5 (ADR-0133): WSC-WSH add 6 assertions for the three
# `commit` fences (R-03). Left at 55 it would have carried 6 units of slack — enough to absorb
# every one of the six vanishing and still read PASS, the same defect this comment already names
# above, reintroduced by the same class of change a second time in one feature.
#
# Raised 61 -> 64 for issue #394 batch 4 (ADR-0133, cross-harness process-boundary sweep): WSI-WSK
# add 3 assertions pinning the class that broke human-gate-coverage.test.sh's run_h4() when this
# feature's own Task 3/5 wrapped fences it reads. Left at 61 it would have carried 3 units of slack
# — enough to absorb all three vanishing and still read PASS, the same defect this comment already
# names twice above, reintroduced a third time by the same class of change.
#
# Raised 64 -> 66 for issue #394 Task 8 (ADR-0133): WSA/WSB add 2 assertions — the executed proof
# and its negative twin, the only pair in this file able to observe the failing quantity at all.
# Left at 64 it would have carried 2 units of slack — enough to absorb both vanishing and still
# read PASS, the same defect this comment already names three times above, reintroduced a fourth
# time by the same class of change. Both live inside a `command -v zsh` branch (the ZSH-ABSENT
# path calls `bad` for each, never a silent omission), so the total moves by exactly 2 either way.
_TOTAL=$((PASS + FAIL))
if [ "$_TOTAL" -ge 66 ]; then
  ok "Z1: $_TOTAL assertions ran (floor 66) — none silently vanished"
else
  bad "Z1: only $_TOTAL assertions ran, floor 66 — assertions disappeared, they did not fail"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
