#!/bin/bash
# required-checks-audit.test.sh — offline, hermetic, no network, no $HOME dependency.
# Issue #322 / ADR-0114. Bash 3.2 clean. Run: bash required-checks-audit.test.sh
#
# WHAT IS UNDER TEST. `autopilot` pre-flight check 8 said *"verify the `ci` check is
# required on main"* and was PROSE with no mechanism, while this repository's `main` requires three
# contexts. `required-checks-audit.sh` derives the live required set and asks, of each context,
# whether anything in this repo PRODUCES it.
#
# `gh` IS STUBBED ON `PATH`, so every branch is reachable with no network. The stub stands in for
# `gh`'s own `--jq`: it emits already-extracted check-run names. That is a deliberate boundary —
# nothing here exercises `gh`'s jq, only the script's use of what it returns.
#
# THE `gh`-MISSING FIXTURE USES AN ABSOLUTE `bash` AND AN EMPTY `PATH` ON PURPOSE. `PATH="" bash x`
# resolves `bash` through the *new* PATH in a prefix assignment, so the fixture would fail at 127
# and report nothing about the script (ADR-0076 §X6, met again). Emptying PATH also has to happen
# where nothing external runs before the check under test — here the `command -v gh` guard is the
# first external command in the file, which is what makes the fixture possible at all.
set -u

TESTS=$(cd "$(dirname "$0")" && pwd)
SCRIPTS=$(cd "$TESTS/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
REPO=$(cd "$STAGING/.." && pwd)
RCA="$SCRIPTS/required-checks-audit.sh"
NA="$STAGING/plugin/skills/autopilot/SKILL.md"
BASHBIN=$(command -v bash)

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# ================================================================================================
# The gh stub. Driven entirely by environment, so one stub serves every fixture.
#   RCA_AUTH=ok|fail        gh auth status
#   RCA_BRANCH=ok|fail      does repos/<r>/branches/<b> exist
#   RCA_PROT=<file>         protection JSON; unset/absent => the API call fails (unprotected)
#   RCA_RUNS=<file>         newline-separated check-run names; unset/absent => the call fails
STUB="$TMP/bin"; mkdir -p "$STUB"
cat > "$STUB/gh" <<'GHSTUB'
#!/bin/bash
if [ "${1:-}" = "auth" ] && [ "${2:-}" = "status" ]; then
  [ "${RCA_AUTH:-ok}" = "ok" ] && exit 0 || exit 1
fi
if [ "${1:-}" = "repo" ]; then printf '%s\n' "${RCA_REPO:-acme/widget}"; exit 0; fi
if [ "${1:-}" = "api" ]; then
  case "${2:-}" in
    */protection)
      if [ -n "${RCA_PROT:-}" ] && [ -f "${RCA_PROT}" ]; then cat "${RCA_PROT}"; exit 0; fi
      exit 1 ;;
    */check-runs)
      if [ -n "${RCA_RUNS:-}" ] && [ -f "${RCA_RUNS}" ]; then cat "${RCA_RUNS}"; exit 0; fi
      exit 1 ;;
    *)
      [ "${RCA_BRANCH:-ok}" = "ok" ] && exit 0 || exit 1 ;;
  esac
fi
exit 1
GHSTUB
chmod +x "$STUB/gh"

# run <root> -> prints exit code; output lands in $TMP/out
run() {
  ( PATH="$STUB:$PATH" bash "$RCA" --root "$1" >"$TMP/out" 2>&1 ); echo "$?"
}
out() { cat "$TMP/out" 2>/dev/null; }

mk_prot() {  # mk_prot <name> <json>
  printf '%s\n' "$2" > "$TMP/$1.json"; printf '%s' "$TMP/$1.json"
}
mk_runs() {  # mk_runs <name> <newline-separated names>
  printf '%s\n' "$2" > "$TMP/$1.txt"; printf '%s' "$TMP/$1.txt"
}
mk_wf() {    # mk_wf <dirname> ; creates <dir>/.github/workflows and echoes <dir>
  mkdir -p "$TMP/$1/.github/workflows"; printf '%s' "$TMP/$1"
}

THREE='{"required_status_checks":{"strict":false,"contexts":["markdownlint","links","ci"],"checks":[{"context":"markdownlint"},{"context":"links"},{"context":"ci"}]}}'
PROT3=$(mk_prot three "$THREE")
RUNS4=$(mk_runs four "ci
links
markdownlint
shell-tests")

# A workflow tree that declares two jobs by id and one by display name, plus a STEP name that must
# NOT count (see A5).
ROOTA=$(mk_wf roota)
cat > "$ROOTA/.github/workflows/docs.yml" <<'WF'
name: Docs CI
on: [push]
jobs:
  markdownlint:
    name: markdownlint
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v5
  links:
    name: links
    runs-on: ubuntu-latest
    steps:
      - name: Internal links
        run: true
WF
cat > "$ROOTA/.github/workflows/ci.yml" <<'WF'
name: ci
on: [push]
jobs:
  ci:
    name: ci
    runs-on: ubuntu-latest
    steps:
      - name: Run tests
        run: true
WF

# ================================================================================================
# A. The verdicts, one fixture per exit code. Both directions per contract.

RCA_AUTH=ok RCA_BRANCH=ok RCA_PROT="$PROT3" RCA_RUNS="$RUNS4" ; export RCA_AUTH RCA_BRANCH RCA_PROT RCA_RUNS
RC=$(run "$ROOTA")
if [ "$RC" = 0 ] && out | grep -q '^AUDIT: PASS'; then
  ok "A1: every required context has a producer -> PASS, exit 0"
else
  bad "A1: expected PASS/0, got rc=$RC — $(out | head -2)"
fi
# plant: A1 | plugin/scripts/required-checks-audit.sh | printf 'AUDIT: PASS — all %s required context(s) on %s@%s have a producer\n' | printf 'AUDIT: OK — all %s required context(s) on %s@%s have a producer\n'

# A2 — THE ADVISORY, which is the M7 finding this feature surfaced: `shell-tests` runs on every
# commit and is not required, so the merge gate does not include the harness. Reported, never a
# gate: the pre-flight's job is that PRs are mergeable, not that the gate is as strict as someone
# would like.
if out | grep -q 'not-required: shell-tests'; then
  ok "A2: a producer that is NOT required is reported as advisory"
else
  bad "A2: the produced-but-not-required line is missing — $(out)"
fi
# plant: A2 | plugin/scripts/required-checks-audit.sh | sed 's/^/    not-required: /' | sed 's/^/    x: /'
#
# The FIRST draft of this plant aimed at the `note:` HEADER line one line above, and did not fire —
# correctly. A2 greps for `not-required: shell-tests`, which the header does not produce; removing
# it left the lines A2 actually reads untouched. The assertion was fine and the plant was aimed one
# line off, which is only visible by looking at what the mutation produced rather than at what the
# runner reported (ADR-0090). A plant must remove the thing the assertion READS, not the thing next
# to it.

# A3 — a required context nothing produces. THE assertion the issue was filed for.
PROT4=$(mk_prot four_ctx '{"required_status_checks":{"contexts":["markdownlint","links","ci","codeql"],"checks":[]}}')
RCA_PROT="$PROT4"; export RCA_PROT
RC=$(run "$ROOTA")
if [ "$RC" = 1 ] && out | grep -q 'missing-producer: codeql'; then
  ok "A3: a required context with no producer -> UNSATISFIABLE naming it, exit 1"
else
  bad "A3: expected 1 + 'missing-producer: codeql', got rc=$RC — $(out | head -3)"
fi
# plant: A3 | plugin/scripts/required-checks-audit.sh | || MISSING="$MISSING | || true; : "

# A4 — matching is whole-line, not substring, and the fixture has to run the RIGHT WAY ROUND. The
# danger is a required context that is a SUBSTRING OF A PRODUCER: required `ci`, produced only
# `cid`. A first draft inverted it (required `cid`, produced `ci`) and its plant did not fire —
# correctly, because dropping the `-x` there changes nothing: no producer line contains `cid`. The
# assertion looked right and pinned nothing (ADR-0090: look at what the mutation produced).
ROOTC=$(mk_wf rootc)
cat > "$ROOTC/.github/workflows/q.yml" <<'WF'
name: quality
on: [push]
jobs:
  cid:
    name: cid
    runs-on: ubuntu-latest
    steps:
      - name: Run
        run: true
WF
PROT5=$(mk_prot substr '{"required_status_checks":{"contexts":["ci"],"checks":[]}}')
RCA_PROT="$PROT5"; RCA_RUNS=""; export RCA_PROT RCA_RUNS
RC=$(run "$ROOTC")
if [ "$RC" = 1 ] && out | grep -q 'missing-producer: ci'; then
  ok "A4: a context that is a SUBSTRING of a producer ('ci' in 'cid') is unsatisfiable"
else
  bad "A4: substring matching satisfied 'ci' from the job 'cid' — rc=$RC, $(out | head -2)"
fi
# plant: A4 | plugin/scripts/required-checks-audit.sh | grep -qxF "$_ctx" | grep -qF "$_ctx"

# A5 — STEP names must not count as producers. A required context called `Checkout` would otherwise
# be satisfied by every checkout step in the repo, which is the over-match the narrowing rejects.
PROT6=$(mk_prot stepname '{"required_status_checks":{"contexts":["Checkout"],"checks":[]}}')
RCA_PROT="$PROT6"; RCA_RUNS=""; export RCA_PROT RCA_RUNS
RC=$(run "$ROOTA")
if [ "$RC" = 1 ] && out | grep -q 'missing-producer: Checkout'; then
  ok "A5: a step-level 'name:' is not a producer"
else
  bad "A5: a step name satisfied a required context — rc=$RC, $(out | head -2)"
fi

# ================================================================================================
# B. The three ways to say "nothing was found to be broken", which are NOT the same sentence.

# B1 — no protection at all: today's behaviour exactly (R-04). Nothing blocks a merge, so there is
# nothing for this audit to guarantee and it must not invent a finding.
RCA_PROT=""; RCA_BRANCH=ok; RCA_RUNS="$RUNS4"; export RCA_PROT RCA_BRANCH RCA_RUNS
RC=$(run "$ROOTA")
if [ "$RC" = 0 ] && out | grep -q '^AUDIT: NO-PROTECTION'; then
  ok "B1: an unprotected branch -> NO-PROTECTION, exit 0 (R-04)"
else
  bad "B1: expected NO-PROTECTION/0, got rc=$RC — $(out | head -2)"
fi

# B2 — protected, empty contexts list (R-03). A DISTINCT token, and the message says in words that
# this is not "all satisfied": there is no context to satisfy. Reporting it as PASS is the same
# class of defect as reporting an unrun check as clean.
PROTE=$(mk_prot empty '{"required_status_checks":{"strict":false,"contexts":[],"checks":[]}}')
RCA_PROT="$PROTE"; export RCA_PROT
RC=$(run "$ROOTA")
if [ "$RC" = 0 ] && out | grep -q '^AUDIT: NO-REQUIRED-CHECKS'; then
  ok "B2: an empty contexts list -> its own token, exit 0 (R-03)"
else
  bad "B2: expected NO-REQUIRED-CHECKS/0, got rc=$RC — $(out | head -2)"
fi
if out | grep -q 'NOT "all satisfied"'; then
  ok "B3: the empty-list message states it is not 'all satisfied'"
else
  bad "B3: an empty required set reports as if everything passed — $(out)"
fi
# plant: B3 | plugin/scripts/required-checks-audit.sh | Nothing was verified. This is NOT "all satisfied": no context exists to satisfy. | Nothing to do here.

# ================================================================================================
# C. DID-NOT-RUN — every way the check cannot look, and none of them may read as a clean result.

# C1 — no gh at all. Absolute bash + empty PATH; see the header for why both halves are required.
RC=$( ( PATH="$TMP/nothing" "$BASHBIN" "$RCA" --root "$ROOTA" >"$TMP/out" 2>&1 ); echo "$?" )
if [ "$RC" = 3 ] && out | grep -q 'DID-NOT-RUN'; then
  ok "C1: gh absent -> exit 3, DID-NOT-RUN"
else
  bad "C1: expected 3/DID-NOT-RUN, got rc=$RC — $(out | head -2)"
fi

# C2 — gh present but unauthenticated.
RCA_AUTH=fail; RCA_PROT="$PROT3"; export RCA_AUTH RCA_PROT
RC=$(run "$ROOTA")
if [ "$RC" = 3 ] && out | grep -q 'not authenticated'; then
  ok "C2: gh unauthenticated -> exit 3, naming the cause"
else
  bad "C2: expected 3 + 'not authenticated', got rc=$RC — $(out | head -2)"
fi
RCA_AUTH=ok; export RCA_AUTH

# C3 — the protection response is not parseable. This must NOT take the empty-list branch: an
# unreadable answer is a fact about the environment, an empty list is a fact about the input.
PROTX=$(mk_prot garbage 'not json at all {{{')
RCA_PROT="$PROTX"; export RCA_PROT
RC=$(run "$ROOTA")
if [ "$RC" = 3 ] && out | grep -q 'not parseable JSON'; then
  ok "C3: an unparseable protection response -> exit 3, never NO-REQUIRED-CHECKS"
else
  bad "C3: expected 3 + 'not parseable JSON', got rc=$RC — $(out | head -2)"
fi
# plant: C3 | plugin/scripts/required-checks-audit.sh | jq -e . >/dev/null 2>&1; then | cat >/dev/null; then

# C4 — the branch itself does not exist: not "unprotected", which would be a definite answer from
# a check that never located its subject.
RCA_PROT=""; RCA_BRANCH=fail; export RCA_PROT RCA_BRANCH
RC=$(run "$ROOTA")
if [ "$RC" = 3 ]; then
  ok "C4: a branch that does not exist -> exit 3, not NO-PROTECTION"
else
  bad "C4: expected 3, got rc=$RC — $(out | head -2)"
fi
RCA_BRANCH=ok; export RCA_BRANCH

# C5 — ZERO producer evidence from BOTH sources. This is the one that decides the whole design: an
# empty producer set makes every required context look broken, and the failure that costs a night
# is the false ABORT, not the false pass.
ROOTB=$(mk_wf rootb); rm -rf "$ROOTB/.github"
RCA_PROT="$PROT3"; RCA_RUNS=""; export RCA_PROT RCA_RUNS
RC=$(run "$ROOTB")
if [ "$RC" = 3 ] && out | grep -q 'no producer evidence at all'; then
  ok "C5: no check-runs AND no workflows -> exit 3, NOT UNSATISFIABLE"
else
  bad "C5: an empty producer set produced a verdict — rc=$RC, $(out | head -3)"
fi
# plant: C5 | plugin/scripts/required-checks-audit.sh | if [ "$OBS_N" -eq 0 ] && [ "$DEC_N" -eq 0 ]; then | if false; then

# ================================================================================================
# D. The producer union, each half alone. A false abort needs BOTH sources to miss, and that is
# only true if either alone is sufficient.

# D1 — declared only: a workflow that has never run on this branch (the `pull_request`-only shape).
RCA_PROT="$PROT3"; RCA_RUNS=""; export RCA_PROT RCA_RUNS
RC=$(run "$ROOTA")
if [ "$RC" = 0 ] && out | grep -q '^AUDIT: PASS'; then
  ok "D1: producers from the workflow files alone are sufficient"
else
  bad "D1: a declared-but-never-run job was called unsatisfiable — rc=$RC, $(out | head -3)"
fi

# D2 — observed only: a check produced by an app or an external service, with no workflow file.
RCA_RUNS="$RUNS4"; export RCA_RUNS
RC=$(run "$ROOTB")
if [ "$RC" = 0 ] && out | grep -q '^AUDIT: PASS'; then
  ok "D2: producers from observed check-runs alone are sufficient"
else
  bad "D2: an observed check-run was not accepted as a producer — rc=$RC, $(out | head -3)"
fi

# ================================================================================================
# E. Bad invocation is its own exit code — never folded into "did not run".
RC=$( ( PATH="$STUB:$PATH" bash "$RCA" --root "$TMP/no-such-dir" >"$TMP/out" 2>&1 ); echo "$?" )
[ "$RC" = 2 ] && ok "E1: a --root that is not a directory -> exit 2" \
              || bad "E1: expected 2, got rc=$RC — $(out | head -1)"
RC=$( ( PATH="$STUB:$PATH" bash "$RCA" --nonsense >"$TMP/out" 2>&1 ); echo "$?" )
[ "$RC" = 2 ] && ok "E2: an unknown argument -> exit 2" \
              || bad "E2: expected 2, got rc=$RC — $(out | head -1)"

# ================================================================================================
# R. The REAL data (rule 10). Recorded from this repository on 2026-08-01, run against this
# repository's ACTUAL .github/workflows. A synthetic fixture proves the script's logic; only the
# real inputs prove it answers the question the issue asked.
PROTR=$(mk_prot real '{"required_status_checks":{"strict":false,"contexts":["markdownlint","links","ci"],"checks":[{"app_id":15368,"context":"markdownlint"},{"app_id":15368,"context":"links"},{"app_id":15368,"context":"ci"}]}}')
RUNSR=$(mk_runs real "markdownlint
shell-tests
links
ci")
RCA_PROT="$PROTR"; RCA_RUNS="$RUNSR"; export RCA_PROT RCA_RUNS
RC=$(run "$REPO")
_nreq=$(out | grep -c '^  required: ' || true)
if [ "$_nreq" -ge 3 ]; then
  ok "R1: the recorded live required set resolves $_nreq contexts (guard: >= 3)"
else
  bad "R1: only $_nreq required context(s) parsed from the recorded response — R2/R3 would be vacuous"
fi
[ "$RC" = 0 ] && ok "R2: this repository's real required set is fully satisfiable" \
              || bad "R2: expected PASS on the real data, got rc=$RC — $(out | head -3)"
out | grep -q 'not-required: shell-tests' \
  && ok "R3: shell-tests is reported as produced-but-not-required on the real data" \
  || bad "R3: the real advisory did not fire — the harness job's exclusion from the gate is invisible"

# ================================================================================================
# RB. The REAL data, re-recorded (rule 14 — the 2026-08-01 snapshot above stays as the historical
# record, never edited in place). ADR-0193's D2/Task 8 deleted `.github/workflows/ci.yml` and
# removed `ci` from main's required status checks (executed 2026-09-06, immediately after the D2/D3
# PR merged — the ordering the ADR names as load-bearing). `ci` no longer exists as a required
# context OR as a producer; `shell-tests` moves from advisory (R3 above) to REQUIRED. R3's assertion
# was correct for 2026-08-01 and is not the live truth any more — this block is what proves that
# forward instead of silently leaving R3 to be misread as still-current.
RUNSR2=$(mk_runs real2 "markdownlint
shell-tests
plant-shard
links")
PROTR2=$(mk_prot real2 '{"required_status_checks":{"strict":false,"contexts":["markdownlint","links","shell-tests"],"checks":[{"app_id":15368,"context":"markdownlint"},{"app_id":15368,"context":"links"},{"app_id":15368,"context":"shell-tests"}]}}')
RCA_PROT="$PROTR2"; RCA_RUNS="$RUNSR2"; export RCA_PROT RCA_RUNS
RC=$(run "$REPO")
_nreq2=$(out | grep -c '^  required: ' || true)
if [ "$_nreq2" -ge 3 ]; then
  ok "RB1: the recorded live required set (2026-09-06) resolves $_nreq2 contexts (guard: >= 3)"
else
  bad "RB1: only $_nreq2 required context(s) parsed from the recorded response — RB2/RB3 would be vacuous"
fi
[ "$RC" = 0 ] && ok "RB2: this repository's real required set (2026-09-06, post-ADR-0193) is fully satisfiable" \
              || bad "RB2: expected PASS on the 2026-09-06 real data, got rc=$RC — $(out | head -3)"
out | grep -q '  required: shell-tests' \
  && ok "RB3: shell-tests is now a REQUIRED context (was advisory-only on 2026-08-01 per R3) — confirms Task 8 landed" \
  || bad "RB3: shell-tests is not reported as required on the 2026-09-06 data — did Task 8's branch-protection change actually land?"
out | grep -q 'not-required: shell-tests' \
  && bad "RB4: shell-tests still reported as advisory-only — the required-set derivation did not pick up the 2026-09-06 change" \
  || ok "RB4: shell-tests is no longer reported as produced-but-not-required (it moved into the required set)"

# ================================================================================================
# F. Check 8's fence — declared, and EXECUTED. The whole defect was a step that had never run
# (ADR-0083 §D3): a marker anchor, never a heading, and an empty extraction is a FAILURE here.
enumerate_fences() {
  awk '
    {
      line = $0
      stripped = line; sub(/^[[:space:]]+/, "", stripped)
      if (stripped ~ /^<!--[[:space:]]*fence-(contract|illustration):/) { pending = stripped; next }
      if (stripped == "") { next }
      if (infence) { if (stripped == "```") { infence = 0 } ; next }
      if (stripped ~ /^```bash[[:space:]]*$/) {
        printf "%d\t%s\n", NR, (pending == "" ? "NONE" : pending)
        pending = ""; infence = 1; next
      }
      pending = ""
    }
  ' "$1"
}
# fence_body <file> <opener-line> — issue #394 / ADR-0133: strips AT MOST the opener's own
# indentation (`ind`), never more than a given line's OWN leading whitespace (`lw`) —
# `strip = (lw < ind) ? lw : ind`. The prior unconditional `substr($0, ind + 1)` corrupted a
# column-0 line inside an indented fence: `autopilot-check-8` is indented 3, and its D1 wrapper's
# column-0 `FENCE_BASH` terminator extracted as `CE_BASH`, which is no longer the heredoc's own
# terminator — the rest of the fence's body is swallowed into the heredoc and its exit code is
# destroyed. `fence-contract-coverage.test.sh` carries the same fix under the same ADR (Task 2); this
# is a DELIBERATE COPY, not a shared import (ADR-0086: three private `fence_body`s already answer
# this file's own question independently, and each file must fail independently).
fence_body() {
  awk -v want="$2" '
    NR == want { match($0, /^[[:space:]]*/); ind = RLENGTH; infence = 1; next }
    infence {
      s = $0; sub(/^[[:space:]]+/, "", s)
      if (s == "```") { exit }
      match($0, /^[[:space:]]*/); lw = RLENGTH
      strip = (lw < ind) ? lw : ind
      print substr($0, strip + 1)
    }
  ' "$1"
}
extract_fence() {
  _ln=$(enumerate_fences "$1" | grep -F "fence-contract: ${2} -->" | head -1 | cut -f1)
  [ -n "$_ln" ] || return 1
  fence_body "$1" "$_ln"
}
# run_fence <id> <fake-HOME-hooks-dir> — the SKILL.md names the DEPLOYED path because that is what
# the model runs; the harness must exercise the STAGING copy, which is what a PR changes.
run_fence() {
  _b=$(extract_fence "$NA" "$1") || { echo "EXTRACT_FAILED"; return; }
  [ -n "$_b" ] || { echo "EXTRACT_EMPTY"; return; }
  _s="$TMP/fence-$1.sh"
  printf '%s\n' "$_b" > "$_s"
  ( HOME="$2" PATH="$STUB:$PATH" bash "$_s" >"$TMP/fout" 2>&1 ); echo "$?"
}
fout() { cat "$TMP/fout" 2>/dev/null; }

FH="$TMP/fakehome"; mkdir -p "$FH/.claude/hooks"
cp "$RCA" "$FH/.claude/hooks/required-checks-audit.sh"

RCA_PROT="$PROTR"; RCA_RUNS="$RUNSR"; export RCA_PROT RCA_RUNS
cd "$REPO" || exit 1
RC=$(run_fence "autopilot-check-8" "$FH")
if [ "$RC" = 0 ] && fout | grep -q '✓ check 8'; then
  ok "F1: check 8's fence runs and passes on a satisfiable gate"
else
  bad "F1: expected 0 + the ✓ line, got rc=$RC — $(fout | head -3)"
fi

RCA_PROT="$PROT4"; export RCA_PROT   # the four-context set with an unproduced `codeql`
RC=$(run_fence "autopilot-check-8" "$FH")
if [ "$RC" = 1 ] && fout | grep -q 'has no producer'; then
  ok "F2: an unsatisfiable gate aborts check 8, naming the consequence"
else
  bad "F2: expected 1 + the abort line, got rc=$RC — $(fout | head -3)"
fi

# F3 — the audit missing from ~/.claude aborts the pre-flight, and says the check DID NOT RUN plus
# the remedy. A gate that degrades to a pass when its own tool is absent is the defect one level up.
RC=$(run_fence "autopilot-check-8" "$TMP/emptyhome")
if [ "$RC" = 1 ] && fout | grep -q 'DID NOT RUN'; then
  ok "F3: a missing audit script aborts check 8 as DID-NOT-RUN"
else
  bad "F3: expected 1 + 'DID NOT RUN', got rc=$RC — $(fout | head -3)"
fi
# plant: F3 | plugin/skills/autopilot/SKILL.md | echo "✗ check 8: required-checks-audit.sh not found at $_rca — the check DID NOT RUN." | echo "check 8: skipped"

# F4 — rc=3 aborts. The whole reason the audit distinguishes "could not look" from "found nothing"
# is so this branch can exist; a pre-flight that proceeds on an unknown merge gate has verified
# nothing while reporting PASSED.
RCA_AUTH=fail; export RCA_AUTH
RC=$(run_fence "autopilot-check-8" "$FH")
if [ "$RC" = 1 ] && fout | grep -q 'DID NOT RUN (rc=3)'; then
  ok "F4: rc=3 from the audit aborts check 8 rather than passing it"
else
  bad "F4: a DID-NOT-RUN audit did not abort the pre-flight — rc=$RC, $(fout | head -3)"
fi
RCA_AUTH=ok; export RCA_AUTH
# plant: F4 | plugin/skills/autopilot/SKILL.md | *) echo "✗ check 8: the audit DID NOT RUN (rc=$_rc). A roadmap does not start on an unknown" | *) echo "check 8: the audit returned rc=$_rc, continuing"

# ================================================================================================
# G. The prose that carries the decisions, matched against a flattened, undecorated copy — a clause
# is the same clause whether it wraps, whether a word inside it is backticked, and whether it opens
# a sentence (ADR-0073 / ADR-0076 / ADR-0080 / ADR-0101, one family, met five times).
flat() { tr '\n' ' ' < "$1" | tr -s ' ' | tr -d '`*' | tr '[:upper:]' '[:lower:]'; }
FNA=$(flat "$NA")
FRCA=$(flat "$RCA")

printf '%s' "$FNA" | grep -q 'the authority is the live required set, derived, never a list declared in the opt-in marker' \
  && ok "G1: check 8 states which authority was chosen" \
  || bad "G1: the derive-vs-declare decision is not stated where the reader stands"

printf '%s' "$FRCA" | grep -q 'satisfiable never means "will be green"' \
  && ok "G2: the script states what PASS does NOT mean" \
  || bad "G2: nothing warns that a producer check is not a green check"

printf '%s' "$FRCA" | grep -q 'the failure direction that matters here is the false abort' \
  && ok "G3: the union-of-two-sources design records its failure direction" \
  || bad "G3: the reason for the union is unstated — a later reader will simplify it away"

# G4 — the aggregate decision, in the skill and in the schema, because a reader of one does not
# read the other.
printf '%s' "$FNA" | grep -q 'is the aggregate over the required set, not one check.s colour' \
  && ok "G4: phase 2 states that ci_status is an aggregate" \
  || bad "G4: the ci_status semantics change is not stated in the skill"
SCH="$REPO/docs/architecture/ADR-0022-morning-report-schema.md"
printf '%s' "$(flat "$SCH")" | grep -q 'it is the aggregate over the branch.s required context set' \
  && ok "G5: the report schema records the ci_status aggregate" \
  || bad "G5: the schema still describes ci_status as one check's colour"

# G6 — the required set must not be re-derived from `gh pr checks`, which lists every check that
# ran whether required or not. Stated at the call site, since that is where someone would do it.
printf '%s' "$FNA" | grep -q 'do not re-derive it from gh pr checks output' \
  && ok "G6: phase 2 forbids deriving the required set from gh pr checks" \
  || bad "G6: nothing stops the aggregate being taken over non-required checks"

# ================================================================================================
# H. Deployment. The fence executes a ~/.claude path, so without the PAIRS entry it aborts every
# pre-flight — inert AND worse than inert. `pairs-completeness.test.sh` covers plugin/scripts, so
# this is belt-and-braces on the one entry this feature adds.
SYNC="$STAGING/sync-to-claude.sh"
grep -qF 'plugin/scripts/required-checks-audit.sh|hooks/required-checks-audit.sh' "$SYNC" \
  && ok "H1: sync-to-claude.sh carries the PAIRS entry" \
  || bad "H1: no PAIRS entry — the fence would exit 1 on every machine"
# Membership in the chmod statement, never position in it: an assertion matching the name plus
# whatever follows it holds only while this file is LAST, and goes red on a correct deploy the day
# something is appended. That is exactly what this feature did to `autopilot-guard-disarm.test.sh` P2.
_chmod_block=$(sed -n '/chmod +x /,/|| true/p' "$SYNC")
printf '%s\n' "$_chmod_block" | grep -q 'hooks/required-checks-audit.sh' \
  && ok "H2: the deployed copy is made executable" \
  || bad "H2: the audit deploys without its executable bit"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
# Z1: assertion-count floor (ADR-0083 §D3) — a file that silently stops running six assertions
# reports fewer of them and nothing reads the total. A floor, not an exact count.
_total=$((PASS + FAIL))
if [ "$_total" -ge 36 ]; then
  echo "PASS: Z1: $_total assertions ran (floor: 36)"
  PASS=$((PASS+1))
else
  echo "FAIL: Z1: only $_total assertions ran — expected >= 36; assertions vanished"
  FAIL=$((FAIL+1))
fi
echo "required-checks-audit.test.sh — PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
