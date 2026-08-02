#!/bin/bash
# permission-mode-state.test.sh — offline, hermetic, no network. Bash 3.2 clean.
# Run: bash permission-mode-state.test.sh
#
# Issue #320 / ADR-0110. `nightly-autopilot` states its first launch precondition three times in
# prose — set a non-blocking permission mode — and verified it NOWHERE. On 2026-07-31 pre-flight
# printed PASSED, the guard armed, the roadmap started, and the chain died at its first Gate 0
# write with nobody present. Every other precondition fails loudly and early; this one failed
# silently and late, and it is the only one whose failure is GUARANTEED fatal.
#
# THE MEASUREMENT THAT DECIDED THE DESIGN. The issue asked whether the effective mode is observable
# at all. It is, but not where anyone would look first:
#   - NOT the environment: the nine CLAUDE* vars carry no permission field.
#   - NOT `settings.json`: it holds the STORED DEFAULT. A session started with --permission-mode or
#     switched with Shift+Tab never writes there, so a stored `acceptEdits` would PASS while the
#     session runs `auto` and dies — wrong in exactly the direction that matters. Proven live:
#     settings.json said `auto` while the session was in `plan`.
#   - THE TRANSCRIPT: `permissionMode` is a TOP-LEVEL key on `user` entries and on a dedicated
#     `type: "permission-mode"` entry. The LAST one is the effective mode. `PM4` is that assertion
#     and it is the centre of this file.
#
# BUILD-STAMPED. 39 of 42 local transcripts carry the field; the two real exceptions are CC 2.1.219.
# The field is new, so UNOBSERVABLE is a first-class token rather than an error (ADR-0016's "the
# substrate moves", applied before it bites rather than after).
#
# --- plants (plant-check.sh) ------------------------------------------------------------
# Each line removes ONE mechanism and names the assertion that must go RED for it.
# plant: PM2 | plugin/skills/concept-to-code/scripts/permission-mode-state.sh | printf 'BLOCKING|%s | printf 'NONBLOCKING|%s
# plant: PM3 | plugin/skills/concept-to-code/scripts/permission-mode-state.sh | printf 'UNCLASSIFIED|%s | printf 'NONBLOCKING|%s
# plant: PM4 | plugin/skills/concept-to-code/scripts/permission-mode-state.sh | last = v | last = last or v
# PM9b's plant must DISABLE the guard, not retune it. The first draft used `-ne 999`, which with a
# stub python3 exiting 7 is TRUE — so the guard fired MORE, the assertion passed, and the registry
# correctly reported a plant that pins nothing. The plant was wrong, not the assertion (ADR-0090).
# plant: PM9b | plugin/skills/concept-to-code/scripts/permission-mode-state.sh | if [ "$PYRC" -ne 0 ]; then | if [ "$PYRC" -eq 999 ]; then
# plant: PMF3 | plugin/skills/nightly-autopilot/SKILL.md | Nobody is here to answer it, so the run would stall | All good
# plant: PMF7 | plugin/skills/autopilot-build/SKILL.md | autopilot-build runs with nobody to answer | it is fine
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
SKILLS="$STAGING/plugin/skills"

PMS="$SKILLS/concept-to-code/scripts/permission-mode-state.sh"
NA="$SKILLS/nightly-autopilot/SKILL.md"
AB="$SKILLS/autopilot-build/SKILL.md"
SYNC="$STAGING/sync-to-claude.sh"

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

for f in "$PMS" "$NA" "$AB" "$SYNC"; do
  [ -f "$f" ] || { echo "FATAL: missing $f"; exit 1; }
done

SID="fixture-session-0000"
PROJ="$TMP/projects"; mkdir -p "$PROJ/somewhere"
TR="$PROJ/somewhere/$SID.jsonl"

# put <line>... — writes a fixture transcript
put() { : >"$TR"; for _l in "$@"; do printf '%s\n' "$_l" >>"$TR"; done; }
# run -> echoes "<rc> <stdout>"
run() {
  _o=$(CLAUDE_PROJECTS_DIR="$PROJ" CLAUDE_CODE_SESSION_ID="$SID" bash "$PMS" 2>/dev/null); _r=$?
  printf '%s %s\n' "$_r" "$_o"
}

# ===========================================================================
# Section PM — the checker. One assertion per token, plus the negative twins.
# ===========================================================================
bash -n "$PMS" 2>/dev/null && ok "PM0 the checker parses" || bad "PM0 the checker does not parse"

if grep -qF 'plugin/skills/concept-to-code/scripts/permission-mode-state.sh|skills/concept-to-code/scripts/permission-mode-state.sh' "$SYNC"; then
  ok "PM0b the PAIRS entry exists"
else
  bad "PM0b no PAIRS entry — both call sites resolve ~/.claude/…, so without it every unattended run aborts on 'the check DID NOT RUN'. pairs-completeness.test.sh cannot see a skill scripts/ file (ADR-0043), so this is the only guard"
fi

put '{"type":"user","permissionMode":"acceptEdits"}'
R=$(run); [ "$R" = "0 NONBLOCKING|acceptEdits" ] && ok "PM1 acceptEdits is NONBLOCKING" \
  || bad "PM1 acceptEdits gave '$R'"

put '{"type":"user","permissionMode":"bypassPermissions"}'
R=$(run); [ "$R" = "0 NONBLOCKING|bypassPermissions" ] && ok "PM1b bypassPermissions is NONBLOCKING" \
  || bad "PM1b bypassPermissions gave '$R'"

put '{"type":"user","permissionMode":"auto"}'
R=$(run); [ "$R" = "0 BLOCKING|auto" ] && ok "PM2 auto is BLOCKING (Claude Code's own shipping default)" \
  || bad "PM2 auto gave '$R', expected '0 BLOCKING|auto'"

# The negative twin worth having explicitly: plan mode is a permission mode, and it blocks.
put '{"type":"permission-mode","permissionMode":"plan"}'
R=$(run); [ "$R" = "0 BLOCKING|plan" ] && ok "PM2b plan is BLOCKING, and is read from a permission-mode entry too" \
  || bad "PM2b plan gave '$R', expected '0 BLOCKING|plan'"

put '{"type":"user","permissionMode":"dontAsk"}'
R=$(run); [ "$R" = "0 UNCLASSIFIED|dontAsk" ] \
  && ok "PM3 dontAsk is UNCLASSIFIED — refused as unmeasured, never silently accepted" \
  || bad "PM3 dontAsk gave '$R', expected '0 UNCLASSIFIED|dontAsk' — an unmeasured mode must not fall into either safe or unsafe by accident"

# ===========================================================================
# PM4 — THE CENTRAL ASSERTION. The LAST value wins.
# Reading a first or stored value is precisely the settings.json defect: a session that STARTED
# non-blocking and was switched to `auto` would pass, and then die exactly as the 2026-07-31 run did.
# ===========================================================================
put '{"type":"user","permissionMode":"acceptEdits"}' \
    '{"type":"permission-mode","permissionMode":"auto"}'
R=$(run); [ "$R" = "0 BLOCKING|auto" ] \
  && ok "PM4 the LAST recorded mode wins (acceptEdits then auto -> BLOCKING)" \
  || bad "PM4 acceptEdits-then-auto gave '$R', expected '0 BLOCKING|auto' — reading anything but the last value reintroduces the stored-default defect"

# ===========================================================================
# PM5-PM7 — UNOBSERVABLE in its three shapes, each distinct from a mode verdict AND from exit 3.
# ===========================================================================
put '{"type":"user","permissionMode":"auto"}'
O=$(CLAUDE_PROJECTS_DIR="$PROJ" CLAUDE_CODE_SESSION_ID= bash "$PMS" 2>/dev/null); RC=$?
case "$RC $O" in
  "0 UNOBSERVABLE|no CLAUDE_CODE_SESSION_ID"*) ok "PM5 no session id -> UNOBSERVABLE, exit 0" ;;
  *) bad "PM5 no session id gave rc=$RC '$O'" ;;
esac

O=$(CLAUDE_PROJECTS_DIR="$PROJ" CLAUDE_CODE_SESSION_ID="no-such-session" bash "$PMS" 2>/dev/null); RC=$?
case "$RC $O" in
  "0 UNOBSERVABLE|no transcript"*) ok "PM6 no transcript for this session -> UNOBSERVABLE, exit 0" ;;
  *) bad "PM6 missing transcript gave rc=$RC '$O'" ;;
esac

put '{"type":"user"}' '{"type":"assistant"}'
R=$(run)
case "$R" in
  "0 UNOBSERVABLE|no permissionMode recorded"*) ok "PM7 a transcript without the field -> UNOBSERVABLE (a pre-2.1.220 build)" ;;
  *) bad "PM7 fieldless transcript gave '$R'" ;;
esac

# ===========================================================================
# PM8 — the value is read as a TOP-LEVEL key, so a nested occurrence cannot be mistaken for it.
# Measured on a real transcript: grep 114, parser 114 — the naive grep survives ONLY because JSON
# escapes the quotes of nested strings, an accidental property of the format. This pins the
# designed behaviour rather than the accident.
# ===========================================================================
put '{"type":"user","permissionMode":"auto"}' \
    '{"type":"user","message":{"content":[{"type":"tool_result","content":"permissionMode\":\"acceptEdits\""}]}}'
R=$(run); [ "$R" = "0 BLOCKING|auto" ] \
  && ok "PM8 a nested tool_result quoting the field is ignored; only the top-level key counts" \
  || bad "PM8 nested decoy gave '$R', expected '0 BLOCKING|auto' — the session's own state must not be readable out of its own output"

# ===========================================================================
# PM9-PM11 — did-not-run, bad invocation, and read-only.
# ===========================================================================
O=$(CLAUDE_PROJECTS_DIR="$TMP/absent-dir" CLAUDE_CODE_SESSION_ID="$SID" bash "$PMS" 2>&1); RC=$?
if [ "$RC" -eq 3 ] && ! printf '%s' "$O" | grep -qE '^(NONBLOCKING|BLOCKING|UNCLASSIFIED|UNOBSERVABLE)\|'; then
  ok "PM9 no projects directory -> exit 3 and NO token (environment, not input)"
else
  bad "PM9 missing projects dir gave rc=$RC '$O'; expected exit 3 with no token"
fi

CLAUDE_PROJECTS_DIR="$PROJ" CLAUDE_CODE_SESSION_ID="$SID" bash "$PMS" extra >/dev/null 2>&1
[ "$?" -eq 2 ] && ok "PM10 an argument -> exit 2 (bad invocation, distinct from 3)" \
  || bad "PM10 an argument did not exit 2"

# PM9b — an interpreter that FAILS is an environment fact (exit 3), never UNOBSERVABLE.
# Without this guard an empty result falls into the "no permissionMode recorded" branch and the
# operator is told "a pre-2.1.220 build does not write it" — a cause that is not the cause.
# Found by weakening-scan.sh's advisory `swallowed-error` heuristic, on this very file.
put '{"type":"user","permissionMode":"auto"}'
FAKEPY="$TMP/fakepy"; mkdir -p "$FAKEPY"
printf '#!/bin/bash\nexit 7\n' >"$FAKEPY/python3"; chmod +x "$FAKEPY/python3"
O=$(PATH="$FAKEPY:$PATH" CLAUDE_PROJECTS_DIR="$PROJ" CLAUDE_CODE_SESSION_ID="$SID" bash "$PMS" 2>&1); RC=$?
if [ "$RC" -eq 3 ] && ! printf '%s' "$O" | grep -qE '^(NONBLOCKING|BLOCKING|UNCLASSIFIED|UNOBSERVABLE)\|'; then
  ok "PM9b a failing python3 -> exit 3 and NO token, never a wrong-cause UNOBSERVABLE"
else
  bad "PM9b failing python3 gave rc=$RC '$O'; expected exit 3 with no token — an interpreter crash must not be reported as an old build"
fi

put '{"type":"user","permissionMode":"acceptEdits"}'
B=$(cksum "$TR" | awk '{print $1 $2}'); NB=$(ls -1 "$PROJ/somewhere" | wc -l | tr -d ' ')
run >/dev/null
A=$(cksum "$TR" | awk '{print $1 $2}'); NA_=$(ls -1 "$PROJ/somewhere" | wc -l | tr -d ' ')
[ "$B" = "$A" ] && [ "$NB" = "$NA_" ] && ok "PM11 the checker leaves the transcript and its directory byte-identical" \
  || bad "PM11 the checker modified something — it must only read"

# PM12 — behavioural proof that settings.json is NOT the source. A fixture HOME whose settings.json
# says `auto` must not change a transcript that says `acceptEdits`.
FH="$TMP/fakehome"; mkdir -p "$FH/.claude"
printf '{"permissions":{"defaultMode":"auto"}}\n' >"$FH/.claude/settings.json"
O=$(HOME="$FH" CLAUDE_PROJECTS_DIR="$PROJ" CLAUDE_CODE_SESSION_ID="$SID" bash "$PMS" 2>/dev/null)
[ "$O" = "NONBLOCKING|acceptEdits" ] \
  && ok "PM12 a settings.json saying 'auto' does not override a transcript saying 'acceptEdits'" \
  || bad "PM12 got '$O' — the stored default is being consulted, which is wrong in the direction that matters"

# ===========================================================================
# Section PMF — both fences, EXTRACTED AND EXECUTED.
# The marker literal is written out per fence: fence-contract-coverage.test.sh F4 counts a contract
# as covered only when a test NAMES it, and a name built at run time is a claim, not an execution.
# ===========================================================================
fence_body() {  # fence_body <file> <marker-literal>
  awk -v m="$2" '
    index($0, m) { seek=1; next }
    seek && $0 ~ /^[[:space:]]*```bash[[:space:]]*$/ { inb=1; seek=0; next }
    inb && $0 ~ /^[[:space:]]*```[[:space:]]*$/ { exit }
    inb { print }
  ' "$1"
}
NA_MARK='fence-contract: nightly-permission-posture -->'
AB_MARK='fence-contract: autopilot-build-check-1b -->'

NA_BODY=$(fence_body "$NA" "$NA_MARK")
AB_BODY=$(fence_body "$AB" "$AB_MARK")
[ "$(printf '%s\n' "$NA_BODY" | grep -c .)" -ge 20 ] && ok "PMF0 the nightly fence is declared and extracts" \
  || bad "PMF0 the nightly fence extracted nothing — an empty extraction is a FAILURE, never a skip"
[ "$(printf '%s\n' "$AB_BODY" | grep -c .)" -ge 20 ] && ok "PMF0b the autopilot-build fence is declared and extracts" \
  || bad "PMF0b the autopilot-build fence extracted nothing"

# run_body <body> <stub-dir> -> "<rc>::<all stdout, newlines squashed>"
run_body() {
  _s="$TMP/fence.sh"
  printf 'HOME=%s\n' "$2" >"$_s"
  printf '%s\n' "$1" | sed -e "s|\$HOME/.claude/skills/|$2/.claude/skills/|g" >>"$_s"
  _o=$(bash "$_s" 2>&1); _r=$?
  printf '%s::%s\n' "$_r" "$(printf '%s' "$_o" | tr '\n' ' ')"
}

# A stub home whose permission-mode-state.sh prints whatever we want.
# The directory is named FROM the token, not from a counter: a counter incremented inside `$(...)`
# lives in a subshell and every call would return the same directory — the ADR-0096 `mk_root`
# fixture bug, which reported as a defect in correct code.
stub_home() {  # stub_home <line-to-print> <exit-code> -> echoes the home dir
  _h="$TMP/stub-$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '-')"
  mkdir -p "$_h/.claude/skills/concept-to-code/scripts"
  {
    echo '#!/bin/bash'
    printf 'printf "%%s\\n" "%s"\n' "$1"
    printf 'exit %s\n' "$2"
  } >"$_h/.claude/skills/concept-to-code/scripts/permission-mode-state.sh"
  printf '%s\n' "$_h"
}

bash -n "$TMP/parse-na.sh" 2>/dev/null
printf '%s\n' "$NA_BODY" >"$TMP/parse-na.sh"; printf '%s\n' "$AB_BODY" >"$TMP/parse-ab.sh"
bash -n "$TMP/parse-na.sh" 2>/dev/null && ok "PMF1 the nightly fence parses as bash" \
  || bad "PMF1 the nightly fence does not parse (ADR-0083 F7)"
bash -n "$TMP/parse-ab.sh" 2>/dev/null && ok "PMF1b the autopilot-build fence parses as bash" \
  || bad "PMF1b the autopilot-build fence does not parse"

H=$(stub_home "NONBLOCKING|acceptEdits" 0)
R=$(run_body "$NA_BODY" "$H"); case "$R" in 0::*"permission posture: acceptEdits"*) ok "PMF2 nightly fence PASSES on NONBLOCKING" ;;
  *) bad "PMF2 nightly on NONBLOCKING gave '$R'" ;; esac
R=$(run_body "$AB_BODY" "$H"); case "$R" in 0::*"permission posture: acceptEdits"*) ok "PMF6 autopilot-build fence PASSES on NONBLOCKING" ;;
  *) bad "PMF6 autopilot-build on NONBLOCKING gave '$R'" ;; esac

H=$(stub_home "BLOCKING|auto" 0)
R=$(run_body "$NA_BODY" "$H")
case "$R" in 1::*"Nobody is here to answer it, so the run would stall"*) ok "PMF3 nightly fence ABORTS on BLOCKING, saying why" ;;
  *) bad "PMF3 nightly on BLOCKING gave '$R', expected exit 1 naming the stall" ;; esac
case "$R" in *"Shift+Tab"*) ok "PMF3b the abort names the remedy that actually works" ;;
  *) bad "PMF3b the BLOCKING abort does not name Shift+Tab — R-03 asks for the exact remedy, and /permissions is not it" ;; esac
R=$(run_body "$AB_BODY" "$H")
case "$R" in 1::*"autopilot-build runs with nobody to answer"*) ok "PMF7 autopilot-build fence ABORTS on BLOCKING" ;;
  *) bad "PMF7 autopilot-build on BLOCKING gave '$R', expected exit 1" ;; esac

H=$(stub_home "UNCLASSIFIED|dontAsk" 0)
R=$(run_body "$NA_BODY" "$H")
case "$R" in 1::*"not known-bad"*) ok "PMF4 nightly ABORTS on UNCLASSIFIED and says it is unmeasured, not unsafe" ;;
  *) bad "PMF4 nightly on UNCLASSIFIED gave '$R'; the operator must not be told their mode is bad when nobody measured it" ;; esac

H=$(stub_home "UNOBSERVABLE|no permissionMode recorded" 0)
R=$(run_body "$NA_BODY" "$H")
case "$R" in 1::*"fact about this build"*) ok "PMF5 nightly FAILS CLOSED on UNOBSERVABLE, naming the build as the cause" ;;
  *) bad "PMF5 nightly on UNOBSERVABLE gave '$R', expected exit 1 distinguishing build from mode" ;; esac

H="$TMP/emptyhome"; mkdir -p "$H"
R=$(run_body "$NA_BODY" "$H")
case "$R" in 1::*"DID NOT RUN"*) ok "PMF8 a missing checker aborts the nightly fence as DID NOT RUN, not as a pass" ;;
  *) bad "PMF8 missing checker gave '$R'" ;; esac
R=$(run_body "$AB_BODY" "$H")
case "$R" in 1::*"DID NOT RUN"*) ok "PMF8b a missing checker aborts the autopilot-build fence too" ;;
  *) bad "PMF8b missing checker gave '$R'" ;; esac

# One answer, not two: both fences must resolve the same script.
NAP=$(printf '%s\n' "$NA_BODY" | grep -c 'concept-to-code/scripts/permission-mode-state.sh')
ABP=$(printf '%s\n' "$AB_BODY" | grep -c 'concept-to-code/scripts/permission-mode-state.sh')
[ "$NAP" -ge 2 ] && [ "$ABP" -ge 2 ] \
  && ok "PMF9 both fences resolve the same checker (two-tier, plugin then ~/.claude)" \
  || bad "PMF9 the two fences do not both resolve concept-to-code/scripts/permission-mode-state.sh (nightly=$NAP autopilot-build=$ABP) — two unattended entry points must not get two answers"

# ===========================================================================
# Section PMP — the prose that was wrong, and the structural note that keeps it from regrowing.
# ===========================================================================
NAFLAT=$(tr '\n' ' ' <"$NA" | tr -d '`*' | tr -s ' ')
ABFLAT=$(tr '\n' ' ' <"$AB" | tr -d '`*' | tr -s ' ')

printf '%s' "$NAFLAT" | grep -qi 'permissions is not one of them' \
  && ok "PMP1 the launch order says /permissions does not set the mode" \
  || bad "PMP1 the launch order still implies /permissions sets the mode; it manages allow/ask/deny rules"

printf '%s' "$NAFLAT" | grep -qi 'must not be added as a ninth' \
  && ok "PMP2 Phase 0 says the posture check is not a ninth check there" \
  || bad "PMP2 nothing stops a future reader adding a second posture check inside Phase 0"

printf '%s' "$ABFLAT" | grep -qi 'nine checks, all read-only Bash' \
  && ok "PMP3 autopilot-build's Phase 0 header counts the new check" \
  || bad "PMP3 autopilot-build still says eight checks while running nine"

printf '%s' "$ABFLAT" | grep -qi 'Placed here and not first because Check 1 genuinely must be' \
  && ok "PMP4 check 1b records why it is neither first nor last" \
  || bad "PMP4 check 1b's placement rationale is missing — the next reader will move it"

# ===========================================================================
# Section PMQ — issue #339 / ADR-0116: the posture message must not overpromise
# ===========================================================================
#
# The pre-flight told the operator "no per-tool prompt will fire" for BOTH non-blocking modes.
# That is true of `bypassPermissions` and false of `acceptEdits`, which auto-accepts EDITS while a
# Bash command outside `permissions.allow` still prompts — observed live on 2026-08-02, and this
# machine's allowlist holds 16 Bash entries, none of which is the chain's own surface. The
# operator-facing line is what decides whether someone walks away from the machine.
#
# DERIVED, not a list of the six known sites: a seventh site added later must fail. The rule is
# one line — a claim that nothing can prompt has to name the mode that actually delivers it.
#
# `docs/architecture/` is OUT of the population on purpose. ADR-0022 line 179 still carries the old
# wording and stays byte-unchanged (ADR-0034 precedent: a historical ADR records its moment; the
# correction is written forward as a dated `## Correction`). This guard is about LIVING
# instructions — what an operator reads at launch time.
PMQ_REPO=$(cd "$STAGING/.." && pwd)
PMQ_POP=""
for _f in "$STAGING"/plugin/skills/*/SKILL.md "$STAGING"/plugin/skills/*/scripts/*.sh \
          "$PMQ_REPO"/docs/RUNBOOK-*.md; do
  [ -f "$_f" ] && PMQ_POP="$PMQ_POP $_f"
done
PMQ_N=$(printf '%s\n' $PMQ_POP | sed '/^$/d' | wc -l | tr -d ' ')

# PMQ0 (denominator guard): a glob that stops resolving empties the population, and an empty
# population makes PMQ1 pass vacuously — which reads exactly like full coverage.
if [ "$PMQ_N" -ge 25 ]; then
  ok "PMQ0 living-instruction population resolved ($PMQ_N files, >= 25 expected)"
else
  bad "PMQ0 population is only $PMQ_N file(s) — a glob stopped resolving, PMQ1 would be vacuous"
fi

# PMQ1: every line claiming no per-tool prompt must name bypassPermissions on that same line.
# plant: PMQ1 | plugin/skills/nightly-autopilot/SKILL.md | echo "✓ permission posture: bypassPermissions — no per-tool prompt can fire." | echo "✓ permission posture: $_pmval — no per-tool prompt can fire."
PMQ_BAD=$(grep -n 'no per-tool prompt' $PMQ_POP 2>/dev/null | grep -v 'bypassPermissions' || true)
if [ -z "$PMQ_BAD" ]; then
  ok "PMQ1 every 'no per-tool prompt' claim names bypassPermissions"
else
  bad "PMQ1 unqualified claim(s) — true only of bypassPermissions:"
  printf '%s\n' "$PMQ_BAD" | sed 's/^/      /'
fi

# PMQ2: both unattended entry points must brand acceptEdits with what it does NOT cover. A message
# that merely stops overpromising still leaves an operator with no way to know the difference.
# plant: PMQ2 | plugin/skills/autopilot-build/SKILL.md | permissions.allow STILL PROMPTS and nobody is here to answer it | permissions.allow is fine and nobody is here to answer it
PMQ2_MISS=""
for _f in "$STAGING/plugin/skills/nightly-autopilot/SKILL.md" \
          "$STAGING/plugin/skills/autopilot-build/SKILL.md"; do
  grep -qF 'STILL PROMPTS' "$_f" || PMQ2_MISS="$PMQ2_MISS $(basename "$(dirname "$_f")")"
done
if [ -z "$PMQ2_MISS" ]; then
  ok "PMQ2 both unattended pre-flights say acceptEdits still prompts on Bash"
else
  bad "PMQ2 pre-flight(s) not naming the acceptEdits limitation:$PMQ2_MISS"
fi

# PMQ3 (R-03): the RUNBOOK must stop presenting /permissions as the way to set the mode. ADR-0110
# established against the CC 2.1.220 binary that it does not, and nightly-autopilot/SKILL.md has
# said so in terms since — the RUNBOOK is the one an operator actually reads at launch.
# The `../docs/` prefix is the one non-staging target plant-check accepts, added with this issue:
# the sandbox already copied docs/ so tests could read it, and no plant could reach it, so a claim
# living in a RUNBOOK was unplantable by construction.
# plant: PMQ3 | ../docs/RUNBOOK-nightly-autopilot.md | claude --permission-mode bypassPermissions | /permissions is the way
PMQ3_RB="$PMQ_REPO/docs/RUNBOOK-nightly-autopilot.md"
if grep -qE '^[[:space:]]*/permissions' "$PMQ3_RB"; then
  bad "PMQ3 the RUNBOOK still offers /permissions as a way to set the permission mode"
elif grep -qF 'claude --permission-mode bypassPermissions' "$PMQ3_RB"; then
  ok "PMQ3 the RUNBOOK names --permission-mode bypassPermissions and not /permissions"
else
  bad "PMQ3 the RUNBOOK names no working way to set the mode"
fi

TOTAL=$((PASS+FAIL))
[ "$TOTAL" -ge 26 ] && ok "Z1 assertion floor met ($TOTAL)" \
  || bad "Z1 only $TOTAL assertions ran (floor 26) — assertions vanished rather than failed"

echo
echo "permission-mode-state.test.sh — PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
