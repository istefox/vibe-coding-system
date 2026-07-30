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
NA="$SKILLS/nightly-autopilot/SKILL.md"
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
# Indentation-tolerant: `nightly-autopilot` indents fences inside numbered list items, and a
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

# fence_body <file> <opener-line> — the fence body with its own indentation stripped.
fence_body() {
  awk -v want="$2" '
    NR == want {
      match($0, /^[[:space:]]*/); ind = RLENGTH; infence = 1; next
    }
    infence {
      s = $0; sub(/^[[:space:]]+/, "", s)
      if (s == "```") { exit }
      print substr($0, ind + 1)
    }
  ' "$1"
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
for f in "$SKILLS"/*/SKILL.md; do
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
CONTRACT_IDS=$(grep -oE 'fence-contract:[[:space:]]*[A-Za-z0-9_-]+' "$ABORT_LIST" \
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
RAW=$(grep -oE 'fence-contract:[[:space:]]*[A-Za-z0-9_-]+' "$ABORT_LIST" | grep -c . )
if [ "$DUP" -eq "$RAW" ]; then
  ok "F6: all $DUP contract ids are unique"
else
  bad "F6: $RAW contract markers but only $DUP distinct ids — an id is reused"
fi

# F7: a contract must at minimum parse as bash. This is the mechanical half of the
# contract-versus-illustration split, and it is what identified the one genuine illustration.
BADSYN=""
while IFS="$(printf '\t')" read -r f ln marker; do
  [ -n "$f" ] || continue
  case "$marker" in *fence-contract:*) ;; *) continue ;; esac
  fence_body "$f" "$ln" >"$TMPROOT/syn.sh"
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

# S3 is the count-guard lesson applied to indentation: `nightly-autopilot` indents fences inside
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

_ill_ln=$(enumerate_fences "$SKILLS/concept-to-code/SKILL.md" | grep -F 'fence-illustration:' | head -1 | cut -f1)
if [ -n "$_ill_ln" ]; then
  fence_body "$SKILLS/concept-to-code/SKILL.md" "$_ill_ln" >"$TMPROOT/syn2.sh"
  if bash -n "$TMPROOT/syn2.sh" 2>/dev/null; then
    bad "S9: the real merge-back fence now PARSES — if it became executable, promote it to a contract"
  else
    ok "S9: F7's classifier rejects the real merge-back fence's pseudo-code"
  fi
else
  bad "S9: no illustration-declared fence found in concept-to-code — the classifier has nothing to reject"
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
cat >"$TMPROOT/s6" <<EOF
HOME="$FAKE_HOME"; export HOME
manifest="$TC_OK"
project_root="\$PROJECT_ROOT_UNDER_TEST"
EOF
PROJECT_ROOT_UNDER_TEST="$PR6"; export PROJECT_ROOT_UNDER_TEST
_rc=$(run_fence "autopilot-build-check-6" "$AB" "$TMPROOT/s6")
if [ "$_rc" = "0" ]; then ok "E7: check 6 passes a real, TOFU-trusted test-cmd"
else bad "E7: check 6 rejected a trusted test-cmd (rc=$_rc): $(head -2 "$TMPROOT/out-autopilot-build-check-6" 2>/dev/null | tr '\n' ' ')"; fi
printf 'NONE\n' >"$PR6/.claude/test-cmd"
_rc=$(run_fence "autopilot-build-check-6" "$AB" "$TMPROOT/s6")
if [ "$_rc" = "1" ]; then ok "E8: check 6 aborts (exit 1) when test-cmd is NONE"
else bad "E8: check 6 did not abort on test-cmd=NONE (rc=$_rc)"; fi
printf 'pytest -q\n' >"$PR6/.claude/test-cmd"
: >"$FAKE_HOME/.claude/state/stop-gate/trust"
_rc=$(run_fence "autopilot-build-check-6" "$AB" "$TMPROOT/s6")
if [ "$_rc" = "1" ]; then ok "E9: check 6 aborts (exit 1) when the command is not TOFU-trusted"
else bad "E9: check 6 did not abort on an untrusted test-cmd (rc=$_rc)"; fi

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

# ---- E12/E13: nightly-autopilot pre-flight 3 — publish opt-in marker --------------------------
NP="$TMPROOT/nightly"; mkdir -p "$NP/.claude"
printf 'publish: true\n' >"$NP/.claude/nightly-autopilot.yml"
printf 'cd %s\n' "$NP" >"$TMPROOT/sn"
_rc=$(run_fence "nightly-autopilot-optin" "$NA" "$TMPROOT/sn")
if [ "$_rc" = "0" ]; then ok "E12: nightly opt-in passes with publish: true"
else bad "E12: nightly opt-in rejected publish: true (rc=$_rc): $(head -2 "$TMPROOT/out-nightly-autopilot-optin" 2>/dev/null | tr '\n' ' ')"; fi
printf 'publish: false\n' >"$NP/.claude/nightly-autopilot.yml"
_rc=$(run_fence "nightly-autopilot-optin" "$NA" "$TMPROOT/sn")
if [ "$_rc" = "1" ]; then ok "E13: nightly opt-in aborts (exit 1) on publish: false"
else bad "E13: nightly opt-in did not abort on publish: false (rc=$_rc)"; fi
rm -f "$NP/.claude/nightly-autopilot.yml"
_rc=$(run_fence "nightly-autopilot-optin" "$NA" "$TMPROOT/sn")
if [ "$_rc" = "1" ]; then ok "E14: nightly opt-in aborts (exit 1) when the marker is absent"
else bad "E14: nightly opt-in did not abort on an absent marker (rc=$_rc)"; fi

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
CCM="$SKILLS/concept-to-code/SKILL.md"
if enumerate_fences "$CCM" | grep -q 'fence-illustration:'; then
  ok "E20: the merge-back fence is declared an illustration, with its reason"
else
  bad "E20: concept-to-code carries no illustration declaration — the pseudo-code fence is unmarked"
fi

# Z1: assertion-count FLOOR, the same guard added to scope-guards.test.sh and
# plan-task-count.test.sh in this change. Every E-section assertion depends on an extraction, so a
# broken marker could take a dozen of them out of the run — and a suite reporting fewer assertions
# than yesterday does not read as broken. Measured on the two neighbours: rewording one heading
# turned "43 passed, 0 failed" into "35 passed, 2 failed". Lowering the floor needs a deliberate edit.
_TOTAL=$((PASS + FAIL))
if [ "$_TOTAL" -ge 37 ]; then
  ok "Z1: $_TOTAL assertions ran (floor 37) — none silently vanished"
else
  bad "Z1: only $_TOTAL assertions ran, floor 37 — assertions disappeared, they did not fail"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
