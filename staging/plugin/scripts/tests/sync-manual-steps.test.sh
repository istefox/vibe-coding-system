#!/bin/bash
# sync-manual-steps.test.sh — offline, hermetic, no network. Bash 3.2 clean.
# Run: bash sync-manual-steps.test.sh
#
# sync-to-claude.sh used to end with one unconditional heredoc printing two MANUAL STEP
# notices. Checked live on 2026-07-25, both steps were already done — the autopilot-guard hook
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
# seven notices above, which are gated by grep on a hook name, this one is gated on a JSON value
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
CMD_MARK="alongside the agent-write-scope entry"
TEST_MARK="alongside the agent-command-scope entry"
# VCS-046: agent-write-scope.sh was merged into test-write-scope.sh and deleted; the "please wire
# agent-write-scope" notice ARCH_MARK used to key off is gone with it. In its place,
# sync-to-claude.sh now warns the OPPOSITE thing — that a stale PreToolUse entry invoking the
# now-deleted script is still present. See section D3/E section below for the inverted fail-safe
# direction this implies and the new fixtures that exercise it.
STALE_ARCH_MARK="invoking hooks/agent-write-scope.sh"
PRECOMPACT_MARK="PreCompact is not currently in the hooks block"
USAGE_HINT_MARK="usage-daily-hint (issue #112, ADR-0058"
RETIRED_MARK="MANUAL STEP: retired hook cleanup"
CLEAR_MARK="no manual steps outstanding"
BASEREF_MARK="worktree forks from the default branch and the chain's Step 5 pre-flight will refuse to dispatch"
INSTRUCTIONS_LOADED_MARK="has nothing to read"

# Two wiring notices now share the "MANUAL STEP: hook wiring" heading (autopilot-guard and, since
# issue #87, write-scope-enforce), so the marks above discriminate on each notice's own body.
# Matching the shared heading would make the two indistinguishable.
#
# WIRED_HOOKS / UNWIRED_HOOKS below are the SINGLE definition of "what does a settings.json hooks
# block look like with nothing outstanding" / "with nothing wired at all". Every notice that is a
# CONTRACT CHANGE to this file (precompact-guard/ADR-0058, worktree.baseRef/ADR-0068,
# commit-outcome-backstop/ADR-0168, usage-daily-hint/ADR-0170, memory-store-guard/VCS-055 Phase 2,
# reviewer-write-scope/VCS-055 Phase 2.3/ADR-0182, coder-memory-scope/VCS-057/ADR-0184, and
# whichever is next) must be
# reflected here, in the one place, or A3's all-clear assertion breaks the moment the new notice
# exists. Before this was extracted, the same JSON blob was inlined three times (build_home,
# build_home_br, build_home_skills), and one of the three copies — build_home_skills — had
# already drifted two hooks behind the other two by the time this was noticed: its comment
# claimed to reuse "build_home's fully-wired settings.json" while actually carrying its own,
# stale copy. A single source makes that drift structurally impossible instead of forbidden by a
# comment (rule 6: two copies answering ONE question — "is this hooks block fully wired?" — is
# the defect, not a design choice).
# VCS-046: no agent-write-scope.sh entry here — that PreToolUse entry invoked a script that no
# longer exists (merged into test-write-scope.sh, which needs no change to gate the architect
# too), so its PRESENCE is now the outstanding condition (see STALE_ARCH_MARK), not its absence.
WIRED_HOOKS='{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash ~/.claude/hooks/autopilot-guard.sh"}]},{"matcher":"Edit|Write|MultiEdit","hooks":[{"type":"command","command":"bash ~/.claude/hooks/write-scope-enforce.sh"}]},{"matcher":"Edit|Write|MultiEdit","hooks":[{"type":"command","command":"bash ~/.claude/hooks/memory-store-guard.sh"}]},{"matcher":"Edit|Write|MultiEdit","hooks":[{"type":"command","command":"bash ~/.claude/hooks/reviewer-write-scope.sh"}]},{"matcher":"Edit|Write|MultiEdit","hooks":[{"type":"command","command":"bash ~/.claude/hooks/coder-memory-scope.sh"}]},{"matcher":"Bash","hooks":[{"type":"command","command":"bash ~/.claude/hooks/agent-command-scope.sh"}]},{"matcher":"Edit|Write|MultiEdit","hooks":[{"type":"command","command":"bash ~/.claude/hooks/test-write-scope.sh"}]},{"matcher":"Skill","hooks":[{"type":"command","command":"bash ~/.claude/hooks/commit-outcome-backstop.sh"}]}],"PreCompact":[{"hooks":[{"type":"command","command":"bash ~/.claude/hooks/precompact-guard.sh"}]}],"Stop":[{"hooks":[{"type":"command","command":"bash ~/.claude/hooks/usage-daily-hint.sh"}]}],"InstructionsLoaded":[{"matcher":"session_start|nested_traversal|path_glob_match|include|compact","hooks":[{"type":"command","command":"\"$HOME\"/.claude/hooks/instructions-loaded-log.sh"}]}]}'
UNWIRED_HOOKS='{"PreToolUse":[{"matcher":"Edit|Write","hooks":[{"type":"command","command":"protect-files.sh"}]}]}'

# build_home <name> <wired:yes|no|nofile> <retired:yes|no> — returns the fixture HOME path.
# "wired: yes" means every wired hook is present, i.e. genuinely nothing outstanding.
build_home() {
  _h="$TMP/$1"; mkdir -p "$_h/.claude/hooks"
  case "$2" in
    yes) printf '{"worktree":{"baseRef":"head"},"hooks":%s}\n' "$WIRED_HOOKS" > "$_h/.claude/settings.json" ;;
    no)  printf '{"hooks":%s}\n' "$UNWIRED_HOOKS" > "$_h/.claude/settings.json" ;;
    nofile) : ;;
  esac
  [ "$3" = "yes" ] && printf '#!/bin/bash\n# retired one-shot backup\n' > "$_h/.claude/hooks/backup-before-deploy.sh"
  printf '%s' "$_h"
}

run_sync() { HOME="$1" bash "$SYNC" 2>&1; }

# build_home_br <name> <hooks:yes|no|nofile> <baseref:absent|wrong|correct> — returns the fixture
# HOME path. Independent of build_home's fixture shape because the baseRef notice is gated on a
# JSON value, not a hook-name substring; "hooks" here reuses WIRED_HOOKS/UNWIRED_HOOKS, the same
# single source build_home draws from, so every existing notice behaves identically to sections
# A-E while $3 varies only the "worktree" key. "nofile" (no settings.json at all) ignores $3.
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
    yes) _hooks="$WIRED_HOOKS" ;;
    no)  _hooks="$UNWIRED_HOOKS" ;;
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
  *) ok "A1: wiring notice suppressed when autopilot-guard is already wired" ;;
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
  *"$WIRING_MARK"*) ok "B1: wiring notice printed when autopilot-guard is absent from settings.json" ;;
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
# D3 — VCS-046: agent-write-scope.sh was merged into test-write-scope.sh and deleted; the notice
# this used to test ("please wire agent-write-scope") is gone with it. In its place
# sync-to-claude.sh now warns the OPPOSITE thing (a stale PreToolUse entry naming the deleted
# script is still present), so the fail-safe direction inverts too: an unconfirmable settings.json
# must not be read as containing a stale entry any more than it should be read as containing a
# wanted one — but here that means the notice must NOT fire, not that it must (contrast D1/D2/D4).
case "$OUT" in
  *"$STALE_ARCH_MARK"*) bad "D3: stale agent-write-scope notice fired on a missing settings.json — an unconfirmable file cannot be read as containing a stale entry" ;;
  *) ok "D3: stale agent-write-scope notice correctly silent on a missing settings.json (inverted fail-safe direction vs D1/D2/D4, VCS-046)" ;;
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
printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash ~/.claude/hooks/autopilot-guard.sh"}]}]}}\n' > "$_h/.claude/settings.json"
OUT=$(run_sync "$_h")
case "$OUT" in
  *"$WIRING_MARK"*) bad "E1: autopilot-guard notice printed although it IS wired" ;;
  *) ok "E1: autopilot-guard notice suppressed when only write-scope is missing" ;;
esac
case "$OUT" in
  *"$SCOPE_MARK"*) ok "E2: write-scope notice fires independently of the autopilot-guard one" ;;
  *) bad "E2: write-scope notice suppressed although it is not wired" ;;
esac
# E3 — VCS-046: this fixture (only autopilot-guard wired) carries no agent-write-scope entry at
# all, so the stale-entry notice (see D3 above) has nothing to warn about and must stay silent —
# proving an unrelated hook being wired does not spuriously trigger it. The positive direction
# (the notice DOES fire when a stale entry genuinely is present, independent of other wiring) is
# E6/E6b below.
case "$OUT" in
  *"$STALE_ARCH_MARK"*) bad "E3: stale agent-write-scope notice fired although this fixture has no such entry to be stale" ;;
  *) ok "E3: stale agent-write-scope notice correctly silent when no agent-write-scope entry is present (VCS-046)" ;;
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
  *"$STALE_ARCH_MARK"*) bad "E6-neg: stale agent-write-scope notice fired although the e5 fixture carries no such entry" ;;
  *) ok "E6-neg: stale agent-write-scope notice correctly silent when e5's agent-command-scope-only fixture has no stale entry (VCS-046)" ;;
esac

# E6/E6b — VCS-046, positive direction: a fixture genuinely carrying a stale agent-write-scope
# PreToolUse entry ALONGSIDE agent-command-scope wired. Proves both halves of independence at
# once — the stale notice fires regardless of what else is wired (E6), and an unrelated hook's
# OWN notice is unaffected by the unrelated stale entry sitting next to it (E6b) — the same
# both-directions shape as E1/E2 and E4/E5 above, applied to the new notice.
_h="$TMP/e6stale"; mkdir -p "$_h/.claude/hooks"
printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash ~/.claude/hooks/agent-command-scope.sh"}]},{"matcher":"Write|Edit|MultiEdit","hooks":[{"type":"command","command":"bash ~/.claude/hooks/agent-write-scope.sh"}]}]}}\n' > "$_h/.claude/settings.json"
OUT6=$(run_sync "$_h")
case "$OUT6" in
  *"$STALE_ARCH_MARK"*) ok "E6: stale agent-write-scope notice fires when the entry is genuinely present, even with an unrelated hook (agent-command-scope) also wired (VCS-046)" ;;
  *) bad "E6: stale agent-write-scope notice suppressed although settings.json carries the stale entry — got: $OUT6" ;;
esac
case "$OUT6" in
  *"$CMD_MARK"*) bad "E6b: agent-command-scope's own notice printed although this fixture wires it" ;;
  *) ok "E6b: agent-command-scope's own notice stays suppressed once wired, unaffected by the unrelated stale entry alongside it" ;;
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
  *"$WIRING_MARK"*) ok "E11: wiring PreCompact does not suppress the autopilot-guard notice" ;;
  *) bad "E11: autopilot-guard notice muted by an unrelated event key being wired" ;;
esac

# E12: usage-daily-hint (issue #112, ADR-0058 D4) fires independently too — it is Stop, a
# different event key again, and shares the fixture's default settings.json (no Stop entry at
# all) with none of the notices above.
case "$OUT" in
  *"$USAGE_HINT_MARK"*) ok "E12: usage-daily-hint notice fires independently too (issue #112, ADR-0058 D4)" ;;
  *) bad "E12: usage-daily-hint notice suppressed although Stop/usage-daily-hint is not wired" ;;
esac

# E13: the reverse direction — wiring Stop/usage-daily-hint must suppress its own reminder while
# leaving the PreToolUse/PreCompact notices alone.
_h="$TMP/e12"; mkdir -p "$_h/.claude/hooks"
printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"bash ~/.claude/hooks/usage-daily-hint.sh"}]}]}}\n' > "$_h/.claude/settings.json"
OUT12=$(run_sync "$_h")
case "$OUT12" in
  *"$USAGE_HINT_MARK"*) bad "E13: usage-daily-hint notice printed although it IS wired" ;;
  *) ok "E13: usage-daily-hint notice suppressed once wired" ;;
esac
case "$OUT12" in
  *"$WIRING_MARK"*) ok "E14: wiring Stop/usage-daily-hint does not suppress the autopilot-guard notice" ;;
  *) bad "E14: autopilot-guard notice muted by an unrelated event key being wired" ;;
esac
case "$OUT12" in
  *"$PRECOMPACT_MARK"*) ok "E14b: wiring Stop/usage-daily-hint does not suppress the precompact-guard notice" ;;
  *) bad "E14b: precompact-guard notice muted by an unrelated event key being wired" ;;
esac


# =====================================================================================
# F. baseRef settings-key notice (issue #176, ADR-0068 Task 5, R-05/R-17). Gated on
# worktree.baseRef == "head" in $DEST/settings.json, not on a hook-name grep.

# F1: absent entirely — all seven hooks wired, so the other seven notices must stay silent while this
# one fires alone.
OUT=$(run_sync "$(build_home_br f1 yes absent)")
case "$OUT" in
  *"$BASEREF_MARK"*) ok "F1: baseRef notice printed when worktree.baseRef is absent from settings.json" ;;
  *) bad "F1: baseRef notice suppressed although worktree.baseRef is absent" ;;
esac
case "$OUT" in
  *"$WIRING_MARK"*) bad "F1b: an unrelated hook-wiring notice leaked into the absent-baseRef case" ;;
  *) ok "F1b: the seven hook-wiring notices stay suppressed when only baseRef is missing" ;;
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
  *) ok "F2b: the seven hook-wiring notices stay suppressed when only baseRef is wrong" ;;
esac

# F3: present and correct — suppressed, and the all-clear line fires since nothing is outstanding.
OUT=$(run_sync "$(build_home_br f3 yes correct)")
case "$OUT" in
  *"$BASEREF_MARK"*) bad "F3: baseRef notice printed although worktree.baseRef is already \"head\"" ;;
  *) ok "F3: baseRef notice suppressed once worktree.baseRef is \"head\"" ;;
esac
case "$OUT" in
  *"$CLEAR_MARK"*) ok "F3b: all-clear line prints once baseRef is correct and all seven hooks are wired" ;;
  *) bad "F3b: no all-clear line although baseRef is correct and all seven hooks are wired — the CLEAR_MARK condition doesn't yet account for baseRef" ;;
esac

# F4: independence, reverse direction — hooks NOT wired, baseRef correct. Proves fixing baseRef
# does not mute the seven hook-wiring notices, and an unwired hook does not force the baseRef notice.
OUT=$(run_sync "$(build_home_br f4 no correct)")
case "$OUT" in
  *"$BASEREF_MARK"*) bad "F4: baseRef notice printed although worktree.baseRef is \"head\" (should be independent of hook wiring)" ;;
  *) ok "F4: baseRef notice stays suppressed when correct, even though the seven hooks are all unwired" ;;
esac
case "$OUT" in
  *"$WIRING_MARK"*) ok "F4b: the autopilot-guard wiring notice still fires independently of a correct baseRef" ;;
  *) bad "F4b: autopilot-guard wiring notice was muted by a correct baseRef value" ;;
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

# build_home_skills <name> <skill-dir-names...> — returns the fixture HOME path. Reuses
# WIRED_HOOKS, the same single source build_home draws from, so the existing MANUAL STEP notices
# stay silent and cannot interfere with the new assertions; adds a $HOME/.claude/skills/ directory
# populated with one empty directory per name given.
build_home_skills() {
  _n="$1"; shift
  _h="$TMP/$_n"; mkdir -p "$_h/.claude/hooks" "$_h/.claude/skills"
  printf '{"worktree":{"baseRef":"head"},"hooks":%s}\n' "$WIRED_HOOKS" > "$_h/.claude/settings.json"
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

# =====================================================================================
# H. commit-outcome-backstop MANUAL STEP notice (2026-08-23-commit-outcome-backstop-hook,
# ADR-0168 Task 7, R-03). Gated on `grep -q 'commit-outcome-backstop' "$DEST/settings.json"` per
# the plan's own Task 7 bullet. RED until Task 7 adds the seventh MANUAL STEP block to
# sync-to-claude.sh — this section documents the CONTRACT the coder must satisfy; the assertions
# below are not weakened to pass early, per this file's own subject.
# NOT "deployed but never invoked" -- that exact phrase is already boilerplate shared by several
# EXISTING notices (sync-to-claude.sh lines 397/414/432/453/475, confirmed 2026-08-24), so it would
# match H1's "no" fixture vacuously today, before Task 7 lands, for a reason that has nothing to do
# with commit-outcome-backstop (rule 1/12: a needle must belong to the mechanism it asserts about
# and to nothing else).
# NOT the bare hook filename "commit-outcome-backstop" either — corrected 2026-08-24 after the
# coder flagged the same rule-1/12 collision from an angle this file had not measured: Task 7's own
# PAIRS entry (sync-to-claude.sh line 206) vendors plugin/scripts/commit-outcome-backstop.sh into
# hooks/commit-outcome-backstop.sh, and the PAIRS-vendoring dry-run loop unconditionally prints
# "== NEW: hooks/commit-outcome-backstop.sh" for any fixture $HOME lacking a pre-deployed copy —
# every H fixture below, since build_home never places that file on disk. A bare-filename needle
# therefore matches that unrelated listing line regardless of whether the seventh MANUAL STEP
# notice fires, so H2/H3 could pass or fail for the wrong reason. Match notice-specific text
# instead, the same idiom the six marks above use ("alongside the ... entry"): confirmed this exact
# phrase occurs exactly once in sync-to-claude.sh (grep -c), inside Task 7's own NOTE block and
# nowhere else — not in the PAIRS loop, not in any other notice. Cut before "heartbeat": the NOTE
# block wraps its parenthetical across a line break ("agentwake\nheartbeat entries)"), and a mark
# containing a literal space where the source has a newline never matches the captured stdout.
COMMIT_OUTCOME_MARK="alongside the chain-memory-capture / agentwake"

# H1: not wired (the plain "no" fixture, same on/off shape the seven existing marks use) -> fires.
OUT=$(run_sync "$(build_home h1 no no)")
case "$OUT" in
  *"$COMMIT_OUTCOME_MARK"*) ok "H1: commit-outcome-backstop notice printed when unwired" ;;
  *) bad "H1: commit-outcome-backstop notice did not print for an unwired settings.json" ;;
esac

# H2: wired (the "yes" fixture, now extended above to include the Skill/commit-outcome-backstop.sh
# entry) -> suppressed.
OUT=$(run_sync "$(build_home h2 yes no)")
case "$OUT" in
  *"$COMMIT_OUTCOME_MARK"*) bad "H2: commit-outcome-backstop notice printed although the yes fixture wires it" ;;
  *) ok "H2: commit-outcome-backstop notice suppressed once wired" ;;
esac

# H3: independence, both directions at once — a fixture wiring ONLY commit-outcome-backstop.
# Wiring it must suppress its OWN notice (mirrors H2, E5, E8, E10's "own notice suppressed once
# wired" shape) while leaving the unrelated autopilot-guard notice firing (mirrors E1, E6, E11's
# "an unrelated hook being wired does not mute this one" shape) — proving neither direction
# couples to the other.
_h="$TMP/h3"; mkdir -p "$_h/.claude/hooks"
printf '{"hooks":{"PostToolUse":[{"matcher":"Skill","hooks":[{"type":"command","command":"bash ~/.claude/hooks/commit-outcome-backstop.sh"}]}]}}\n' > "$_h/.claude/settings.json"
OUT=$(run_sync "$_h")
case "$OUT" in
  *"$COMMIT_OUTCOME_MARK"*) bad "H3: commit-outcome-backstop notice printed although this fixture wires it" ;;
  *) ok "H3: commit-outcome-backstop notice suppressed when wired alone" ;;
esac
case "$OUT" in
  *"$WIRING_MARK"*) ok "H3b: the unrelated autopilot-guard notice still fires — wiring commit-outcome-backstop alone does not mute it" ;;
  *) bad "H3b: autopilot-guard notice muted by an unrelated hook (commit-outcome-backstop) being wired" ;;
esac

# I. InstructionsLoaded MANUAL STEP notice (ADR-0171). Gated on
# `grep -q 'InstructionsLoaded' "$DEST/settings.json"`, same shape as the seven hook-name marks
# above. INSTRUCTIONS_LOADED_MARK is "has nothing to read" (the closing sentence of the notice's
# own body, confirmed to occur exactly once in sync-to-claude.sh) rather than the bare hook
# filename or the shared "top-level \"hooks\" object" phrase — that phrase already appears in the
# precompact-guard notice (sync-to-claude.sh:468), so it would match regardless of whether THIS
# notice fires (rule 1/12 again, the same collision H's own comment already found once).

# I1: not wired -> fires.
OUT=$(run_sync "$(build_home i1 no no)")
case "$OUT" in
  *"$INSTRUCTIONS_LOADED_MARK"*) ok "I1: InstructionsLoaded notice printed when unwired" ;;
  *) bad "I1: InstructionsLoaded notice did not print for an unwired settings.json" ;;
esac

# I2: wired (the "yes" fixture, now extended above to include the InstructionsLoaded entry) -> suppressed.
OUT=$(run_sync "$(build_home i2 yes no)")
case "$OUT" in
  *"$INSTRUCTIONS_LOADED_MARK"*) bad "I2: InstructionsLoaded notice printed although the yes fixture wires it" ;;
  *) ok "I2: InstructionsLoaded notice suppressed once wired" ;;
esac

# I3: independence, both directions — a fixture wiring ONLY InstructionsLoaded.
_i="$TMP/i3"; mkdir -p "$_i/.claude/hooks"
printf '{"hooks":{"InstructionsLoaded":[{"matcher":"session_start","hooks":[{"type":"command","command":"bash ~/.claude/hooks/instructions-loaded-log.sh"}]}]}}\n' > "$_i/.claude/settings.json"
OUT=$(run_sync "$_i")
case "$OUT" in
  *"$INSTRUCTIONS_LOADED_MARK"*) bad "I3: InstructionsLoaded notice printed although this fixture wires it" ;;
  *) ok "I3: InstructionsLoaded notice suppressed when wired alone" ;;
esac
case "$OUT" in
  *"$WIRING_MARK"*) ok "I3b: the unrelated autopilot-guard notice still fires — wiring InstructionsLoaded alone does not mute it" ;;
  *) bad "I3b: autopilot-guard notice muted by an unrelated hook (InstructionsLoaded) being wired" ;;
esac

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
