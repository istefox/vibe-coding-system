#!/bin/bash
# sync-manual-steps.test.sh — offline, hermetic, no network. Bash 3.2 clean.
# Run: bash sync-manual-steps.test.sh
#
# sync-to-claude.sh used to end with one unconditional heredoc printing two MANUAL STEP
# notices. Checked live on 2026-07-25, both steps were already done — the nightly-guard hook
# was wired and the retired backup-before-deploy.sh did not exist — yet the script printed
# them on every run. Fixed noise is what buries the notice that one day matters, so each
# notice is now gated on the state it describes.
#
# HERMETIC $HOME OVERRIDE. The script derives DEST from $HOME (line 14) and nothing else, so
# pointing HOME at a fixture directory gives a full run that cannot touch the real ~/.claude.
# Runs are dry-run (no --apply), so the script only reads. ADR-0024 recorded $HOME coupling as
# the reason several legacy harnesses are CI-dark; this is the pattern that closes that gap
# without editing the script under test — reusable for the others.
#
# Section F (issue #176, ADR-0068 Task 5, R-05/R-17): the baseRef settings-key notice. Unlike the
# six notices above, which are gated by grep on a hook name, this one is gated on a JSON value
# (worktree.baseRef == "head" in $DEST/settings.json), so it needs its own fixture shape rather
# than build_home's hooks-only JSON. EXPECTED at RED time: every F assertion FAILS — no such
# notice exists in sync-to-claude.sh yet (confirmed absent before this section was written); Task
# 5 adds it under a NEW heading ("MANUAL STEP: settings key"), distinct from the shared
# "MANUAL STEP: hook wiring" heading the marks above key off.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
SYNC="$STAGING/sync-to-claude.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

WIRING_MARK="alongside the Edit|Write protect-files entry"
SCOPE_MARK="alongside the pre-flight-pattern-enforce entry"
ARCH_MARK="alongside the write-scope-enforce entry"
CMD_MARK="alongside the agent-write-scope entry"
TEST_MARK="alongside the agent-command-scope entry"
PRECOMPACT_MARK="PreCompact is not currently in the hooks block"
RETIRED_MARK="MANUAL STEP: retired hook cleanup"
CLEAR_MARK="no manual steps outstanding"
BASEREF_MARK="worktree forks from the default branch and the chain's Step 5 pre-flight will refuse to dispatch"

# Two wiring notices now share the "MANUAL STEP: hook wiring" heading (nightly-guard and, since
# issue #87, write-scope-enforce), so the marks above discriminate on each notice's own body.
# Matching the shared heading would make the two indistinguishable.
#
# precompact-guard (issue #112, ADR-0058) is a CONTRACT CHANGE to this file, not just an addition:
# the "yes" fixture below enumerates every wired hook and must include PreCompact too, or A3's
# all-clear assertion breaks the moment sync-to-claude.sh's new notice exists (this caught
# ADR-0049 too — see the comment on issue #87 above). worktree.baseRef (issue #176, ADR-0068
# Task 5) is the same kind of contract change: the "yes" fixture's settings.json must also carry
# "worktree":{"baseRef":"head"}, or A3 breaks the moment the baseRef notice exists. Whoever adds
# the next notice: extend build_home's "yes" fixture to represent it as wired too, or A3 rots
# again.

# build_home <name> <wired:yes|no|nofile> <retired:yes|no> — returns the fixture HOME path.
# "wired: yes" means every wired hook is present, i.e. genuinely nothing outstanding.
build_home() {
  _h="$TMP/$1"; mkdir -p "$_h/.claude/hooks"
  case "$2" in
    yes) printf '{"worktree":{"baseRef":"head"},"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash ~/.claude/hooks/nightly-guard.sh"}]},{"matcher":"Edit|Write|MultiEdit","hooks":[{"type":"command","command":"bash ~/.claude/hooks/write-scope-enforce.sh"}]},{"matcher":"Write|Edit|MultiEdit","hooks":[{"type":"command","command":"bash ~/.claude/hooks/agent-write-scope.sh"}]},{"matcher":"Bash","hooks":[{"type":"command","command":"bash ~/.claude/hooks/agent-command-scope.sh"}]},{"matcher":"Edit|Write|MultiEdit","hooks":[{"type":"command","command":"bash ~/.claude/hooks/test-write-scope.sh"}]}],"PreCompact":[{"hooks":[{"type":"command","command":"bash ~/.claude/hooks/precompact-guard.sh"}]}]}}\n' > "$_h/.claude/settings.json" ;;
    no)  printf '{"hooks":{"PreToolUse":[{"matcher":"Edit|Write","hooks":[{"type":"command","command":"protect-files.sh"}]}]}}\n' > "$_h/.claude/settings.json" ;;
    nofile) : ;;
  esac
  [ "$3" = "yes" ] && printf '#!/bin/bash\n# retired one-shot backup\n' > "$_h/.claude/hooks/backup-before-deploy.sh"
  printf '%s' "$_h"
}

run_sync() { HOME="$1" bash "$SYNC" 2>&1; }

# build_home_br <name> <hooks:yes|no|nofile> <baseref:absent|wrong|correct> — returns the fixture
# HOME path. Independent of build_home's fixture shape because the baseRef notice is gated on a
# JSON value, not a hook-name substring; "hooks" here reuses "yes"/"no"'s exact JSON blobs from
# build_home so the six existing notices behave identically to sections A-E while $3 varies only
# the "worktree" key. "nofile" (no settings.json at all) ignores $3.
build_home_br() {
  _h="$TMP/$1"; mkdir -p "$_h/.claude/hooks"
  if [ "$2" = "nofile" ]; then
    printf '%s' "$_h"
    return
  fi
  case "$3" in
    absent)  _wt='' ;;
    wrong)   _wt='"worktree":{"baseRef":"fresh"},' ;;
    correct) _wt='"worktree":{"baseRef":"head"},' ;;
  esac
  case "$2" in
    yes) _hooks='{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash ~/.claude/hooks/nightly-guard.sh"}]},{"matcher":"Edit|Write|MultiEdit","hooks":[{"type":"command","command":"bash ~/.claude/hooks/write-scope-enforce.sh"}]},{"matcher":"Write|Edit|MultiEdit","hooks":[{"type":"command","command":"bash ~/.claude/hooks/agent-write-scope.sh"}]},{"matcher":"Bash","hooks":[{"type":"command","command":"bash ~/.claude/hooks/agent-command-scope.sh"}]},{"matcher":"Edit|Write|MultiEdit","hooks":[{"type":"command","command":"bash ~/.claude/hooks/test-write-scope.sh"}]}],"PreCompact":[{"hooks":[{"type":"command","command":"bash ~/.claude/hooks/precompact-guard.sh"}]}]}' ;;
    no)  _hooks='{"PreToolUse":[{"matcher":"Edit|Write","hooks":[{"type":"command","command":"protect-files.sh"}]}]}' ;;
  esac
  printf '{%s"hooks":%s}\n' "$_wt" "$_hooks" > "$_h/.claude/settings.json"
  printf '%s' "$_h"
}

# =====================================================================================
# A. Wired, no retired file — the real state of this machine on 2026-07-25. Neither notice
# may print, and the all-clear line must, so silence is never ambiguous with "forgot to check".
OUT=$(run_sync "$(build_home a yes no)")
case "$OUT" in
  *"$WIRING_MARK"*) bad "A1: wiring notice printed although the hook is wired" ;;
  *) ok "A1: wiring notice suppressed when nightly-guard is already wired" ;;
esac
case "$OUT" in
  *"$RETIRED_MARK"*) bad "A2: retired-hook notice printed although the file is absent" ;;
  *) ok "A2: retired-hook notice suppressed when the file does not exist" ;;
esac
case "$OUT" in
  *"$CLEAR_MARK"*) ok "A3: all-clear line printed when nothing is outstanding" ;;
  *) bad "A3: no all-clear line — silence is ambiguous with a skipped check" ;;
esac

# =====================================================================================
# B. Not wired — the notice must fire, and only that one.
OUT=$(run_sync "$(build_home b no no)")
case "$OUT" in
  *"$WIRING_MARK"*) ok "B1: wiring notice printed when nightly-guard is absent from settings.json" ;;
  *) bad "B1: wiring notice suppressed although the hook is NOT wired" ;;
esac
case "$OUT" in
  *"$RETIRED_MARK"*) bad "B2: retired-hook notice leaked into the not-wired case" ;;
  *) ok "B2: retired-hook notice still suppressed" ;;
esac

# =====================================================================================
# C. Retired file present, hook wired — mirror image of B.
OUT=$(run_sync "$(build_home c yes yes)")
case "$OUT" in
  *"$RETIRED_MARK"*) ok "C1: retired-hook notice printed when the file exists" ;;
  *) bad "C1: retired-hook notice suppressed although the file exists" ;;
esac
case "$OUT" in
  *"$WIRING_MARK"*) bad "C2: wiring notice leaked into the retired-file case" ;;
  *) ok "C2: wiring notice still suppressed" ;;
esac

# =====================================================================================
# D. No settings.json at all. Fail-safe direction is to PRINT: an unconfirmable state must not
# read as "already wired". This is the one case where a false positive is the correct output.
OUT=$(run_sync "$(build_home d nofile no)")
case "$OUT" in
  *"$WIRING_MARK"*) ok "D1: wiring notice printed when settings.json is missing (fail-safe)" ;;
  *) bad "D1: missing settings.json silently treated as wired" ;;
esac
case "$OUT" in
  *"$SCOPE_MARK"*) ok "D2: write-scope wiring notice also fail-safes on a missing settings.json" ;;
  *) bad "D2: missing settings.json silently treated as write-scope-wired" ;;
esac
case "$OUT" in
  *"$ARCH_MARK"*) ok "D3: agent-write-scope notice also fail-safes on a missing settings.json" ;;
  *) bad "D3: missing settings.json silently treated as agent-write-scope-wired" ;;
esac
case "$OUT" in
  *"$PRECOMPACT_MARK"*) ok "D4: precompact-guard notice also fail-safes on a missing settings.json (issue #112)" ;;
  *) bad "D4: missing settings.json silently treated as precompact-guard-wired" ;;
esac

# =====================================================================================
# E. The two wiring notices must be independent — issue #87 added the second one. If wiring
# either hook suppressed the other's notice, installing one would silently mute the reminder for
# the one still missing, which is the exact failure #85 set out to remove.
_h="$TMP/e2"; mkdir -p "$_h/.claude/hooks"
printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash ~/.claude/hooks/nightly-guard.sh"}]}]}}\n' > "$_h/.claude/settings.json"
OUT=$(run_sync "$_h")
case "$OUT" in
  *"$WIRING_MARK"*) bad "E1: nightly-guard notice printed although it IS wired" ;;
  *) ok "E1: nightly-guard notice suppressed when only write-scope is missing" ;;
esac
case "$OUT" in
  *"$SCOPE_MARK"*) ok "E2: write-scope notice fires independently of the nightly-guard one" ;;
  *) bad "E2: write-scope notice suppressed although it is not wired" ;;
esac
# E3: five wiring notices now share the "hook wiring" heading. Each must key off its own hook,
# so wiring any one of them cannot mute the reminders for the others.
case "$OUT" in
  *"$ARCH_MARK"*) ok "E3: agent-write-scope notice fires independently too" ;;
  *) bad "E3: agent-write-scope notice suppressed although it is not wired" ;;
esac
case "$OUT" in
  *"$CMD_MARK"*) ok "E4: agent-command-scope notice fires independently too (issue #58 gap 1)" ;;
  *) bad "E4: agent-command-scope notice suppressed although it is not wired" ;;
esac

# E5: the reverse direction for the newest notice — wiring it must suppress its own reminder while
# leaving the others alone. Without this, E4 alone would pass on a notice that prints
# unconditionally, which is the fixed-noise problem #85 existed to remove.
_h="$TMP/e5"; mkdir -p "$_h/.claude/hooks"
printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash ~/.claude/hooks/agent-command-scope.sh"}]}]}}\n' > "$_h/.claude/settings.json"
OUT5=$(run_sync "$_h")
case "$OUT5" in
  *"$CMD_MARK"*) bad "E5: agent-command-scope notice printed although it IS wired" ;;
  *) ok "E5: agent-command-scope notice suppressed once wired" ;;
esac
case "$OUT5" in
  *"$ARCH_MARK"*) ok "E6: wiring agent-command-scope does not mute the agent-write-scope notice" ;;
  *) bad "E6: agent-write-scope notice muted by an unrelated hook being wired" ;;
esac

case "$OUT" in
  *"$TEST_MARK"*) ok "E7: test-write-scope notice fires independently too (issue #103, ADR-0049)" ;;
  *) bad "E7: test-write-scope notice suppressed although it is not wired" ;;
esac

# E8: the reverse direction for the newest notice — wiring it must suppress its own reminder while
# leaving the others alone. Without this, E7 alone would pass on a notice that prints
# unconditionally, which is the fixed-noise problem #85 existed to remove.
_h="$TMP/e7"; mkdir -p "$_h/.claude/hooks"
printf '{"hooks":{"PreToolUse":[{"matcher":"Edit|Write|MultiEdit","hooks":[{"type":"command","command":"bash ~/.claude/hooks/test-write-scope.sh"}]}]}}\n' > "$_h/.claude/settings.json"
OUT7=$(run_sync "$_h")
case "$OUT7" in
  *"$TEST_MARK"*) bad "E8: test-write-scope notice printed although it IS wired" ;;
  *) ok "E8: test-write-scope notice suppressed once wired" ;;
esac

# E9: precompact-guard (issue #112) fires independently of the five PreToolUse wiring notices —
# it is a different event key entirely (PreCompact), so nothing about the PreToolUse fixtures
# above should affect it either way.
case "$OUT" in
  *"$PRECOMPACT_MARK"*) ok "E9: precompact-guard notice fires independently too (issue #112, ADR-0058)" ;;
  *) bad "E9: precompact-guard notice suppressed although PreCompact is not wired" ;;
esac

# E10: the reverse direction — wiring PreCompact must suppress its own reminder while leaving the
# PreToolUse notices alone. Without this, E9 alone would pass on a notice that prints
# unconditionally, the same fixed-noise problem #85 existed to remove.
_h="$TMP/e9"; mkdir -p "$_h/.claude/hooks"
printf '{"hooks":{"PreCompact":[{"hooks":[{"type":"command","command":"bash ~/.claude/hooks/precompact-guard.sh"}]}]}}\n' > "$_h/.claude/settings.json"
OUT9=$(run_sync "$_h")
case "$OUT9" in
  *"$PRECOMPACT_MARK"*) bad "E10: precompact-guard notice printed although it IS wired" ;;
  *) ok "E10: precompact-guard notice suppressed once wired" ;;
esac
case "$OUT9" in
  *"$WIRING_MARK"*) ok "E11: wiring PreCompact does not suppress the nightly-guard notice" ;;
  *) bad "E11: nightly-guard notice muted by an unrelated event key being wired" ;;
esac


# =====================================================================================
# F. baseRef settings-key notice (issue #176, ADR-0068 Task 5, R-05/R-17). Gated on
# worktree.baseRef == "head" in $DEST/settings.json, not on a hook-name grep.

# F1: absent entirely — all six hooks wired, so the other six notices must stay silent while this
# one fires alone.
OUT=$(run_sync "$(build_home_br f1 yes absent)")
case "$OUT" in
  *"$BASEREF_MARK"*) ok "F1: baseRef notice printed when worktree.baseRef is absent from settings.json" ;;
  *) bad "F1: baseRef notice suppressed although worktree.baseRef is absent" ;;
esac
case "$OUT" in
  *"$WIRING_MARK"*) bad "F1b: an unrelated hook-wiring notice leaked into the absent-baseRef case" ;;
  *) ok "F1b: the six hook-wiring notices stay suppressed when only baseRef is missing" ;;
esac

# F2: present but WRONG value ("fresh", not "head") — the case that matters most, since it is easy
# to conflate "key present" with "key correct". Must fire exactly like the absent case.
OUT=$(run_sync "$(build_home_br f2 yes wrong)")
case "$OUT" in
  *"$BASEREF_MARK"*) ok "F2: baseRef notice printed when worktree.baseRef is present but NOT \"head\" (e.g. \"fresh\")" ;;
  *) bad "F2: baseRef notice suppressed although worktree.baseRef is present with the wrong value — a wrong value is being silently treated as correct" ;;
esac
case "$OUT" in
  *"$WIRING_MARK"*) bad "F2b: an unrelated hook-wiring notice leaked into the wrong-baseRef case" ;;
  *) ok "F2b: the six hook-wiring notices stay suppressed when only baseRef is wrong" ;;
esac

# F3: present and correct — suppressed, and the all-clear line fires since nothing is outstanding.
OUT=$(run_sync "$(build_home_br f3 yes correct)")
case "$OUT" in
  *"$BASEREF_MARK"*) bad "F3: baseRef notice printed although worktree.baseRef is already \"head\"" ;;
  *) ok "F3: baseRef notice suppressed once worktree.baseRef is \"head\"" ;;
esac
case "$OUT" in
  *"$CLEAR_MARK"*) ok "F3b: all-clear line prints once baseRef is correct and all six hooks are wired" ;;
  *) bad "F3b: no all-clear line although baseRef is correct and all six hooks are wired — the CLEAR_MARK condition doesn't yet account for baseRef" ;;
esac

# F4: independence, reverse direction — hooks NOT wired, baseRef correct. Proves fixing baseRef
# does not mute the six hook-wiring notices, and an unwired hook does not force the baseRef notice.
OUT=$(run_sync "$(build_home_br f4 no correct)")
case "$OUT" in
  *"$BASEREF_MARK"*) bad "F4: baseRef notice printed although worktree.baseRef is \"head\" (should be independent of hook wiring)" ;;
  *) ok "F4: baseRef notice stays suppressed when correct, even though the six hooks are all unwired" ;;
esac
case "$OUT" in
  *"$WIRING_MARK"*) ok "F4b: the nightly-guard wiring notice still fires independently of a correct baseRef" ;;
  *) bad "F4b: nightly-guard wiring notice was muted by a correct baseRef value" ;;
esac

# F5: fail-safe — no settings.json at all. An unconfirmable state must not read as "already
# correct" (same fail-safe direction as D1-D4 above).
OUT=$(run_sync "$(build_home_br f5 nofile absent)")
case "$OUT" in
  *"$BASEREF_MARK"*) ok "F5: baseRef notice printed when settings.json is missing entirely (fail-safe)" ;;
  *) bad "F5: missing settings.json silently treated as baseRef-correct" ;;
esac

# =====================================================================================
# G. Undeclared deployed skill report (issue #222, ADR-0087, R-06). sync-to-claude.sh reports,
# once per run, every directory under $HOME/.claude/skills/ that is neither vendored in
# staging/plugin/skills/ nor declared in the Task-4 `# deployed-only:` registry. It is a REPORT,
# distinct from the MANUAL STEP blocks above: it never sets MANUAL=1 and never affects the exit
# code. Pinned by the orchestrator so the tester and coder agree on the exact heading:
REPORT_MARK="-- REPORT: deployed skill(s) neither vendored nor declared --"

# build_home_skills <name> <skill-dir-names...> — returns the fixture HOME path. Reuses build_home's
# fully-wired "yes" settings.json (every hook wired, baseRef correct) so the six existing MANUAL
# STEP notices stay silent and cannot interfere with the new assertions; adds a $HOME/.claude/
# skills/ directory populated with one empty directory per name given.
build_home_skills() {
  _n="$1"; shift
  _h="$TMP/$_n"; mkdir -p "$_h/.claude/hooks" "$_h/.claude/skills"
  printf '{"worktree":{"baseRef":"head"},"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash ~/.claude/hooks/nightly-guard.sh"}]},{"matcher":"Edit|Write|MultiEdit","hooks":[{"type":"command","command":"bash ~/.claude/hooks/write-scope-enforce.sh"}]},{"matcher":"Write|Edit|MultiEdit","hooks":[{"type":"command","command":"bash ~/.claude/hooks/agent-write-scope.sh"}]},{"matcher":"Bash","hooks":[{"type":"command","command":"bash ~/.claude/hooks/agent-command-scope.sh"}]},{"matcher":"Edit|Write|MultiEdit","hooks":[{"type":"command","command":"bash ~/.claude/hooks/test-write-scope.sh"}]}],"PreCompact":[{"hooks":[{"type":"command","command":"bash ~/.claude/hooks/precompact-guard.sh"}]}]}}\n' > "$_h/.claude/settings.json"
  for _s in "$@"; do
    mkdir -p "$_h/.claude/skills/$_s"
  done
  printf '%s' "$_h"
}

# G1: one directory whose name is neither a vendored-skill name (from PAIRS) nor one of the five
# Task-4 registry names ("agent-design", "daily-close", "daily-open", "vibiso-intake",
# "website-auditor") — the report block must appear, naming it. This is RED right now (Task 6 has
# not yet added the report block to sync-to-claude.sh) and must stay RED until Task 6 lands.
OUT=$(run_sync "$(build_home_skills g1 commit some-unknown-skill)")
case "$OUT" in
  *"$REPORT_MARK"*) ok "G1: report block appears for a deployed skill neither vendored nor declared" ;;
  *) bad "G1: report block did not appear for an undeclared, unvendored deployed skill (some-unknown-skill)" ;;
esac
case "$OUT" in
  *"some-unknown-skill"*) ok "G1b: report block names the undeclared skill" ;;
  *) bad "G1b: report block did not name the undeclared skill (some-unknown-skill)" ;;
esac

# G2: only vendored (commit) and/or declared (agent-design) names present — the report block must
# not appear at all.
OUT=$(run_sync "$(build_home_skills g2 commit agent-design)")
case "$OUT" in
  *"$REPORT_MARK"*) bad "G2: report block appeared although every deployed skill is vendored or declared" ;;
  *) ok "G2: report block absent when every deployed skill is vendored or declared" ;;
esac

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
