# ADR-0033 — vibe-status: recursion guard and active-chains wiring

**Status:** Accepted
**Date:** 2026-07-11
**Author:** istefox
**Supersedes:** none
**Amends:** ADR-0005 (`vibe-status-skill`) — the harness-runner.sh timeout mechanism it specifies
("per-harness timeout: 8s default... invoke single harness with timeout") is re-implemented here on
bash job control instead of external `timeout`/`gtimeout` binaries; ADR-0005's own decision record is
left unedited (historical), this ADR is the amendment of record for that one implementation detail.
**Superseded by:** none
**Related:**
- SPEC: `docs/specs/37-vibe-status-recursion-guard-and-active-c.spec.md` (= `SPEC.md` at repo root,
  GitHub issue #37, confirmed byte-identical by diff before writing this ADR)
- ADR-0021 (`chain-memory-posttooluse-native-store`) — defines the `chain-history/<slug>.md` STATE OF
  FACT schema `chain-memory-section.sh` reads; this ADR lands its read-only consumer, unchanged
- ADR-0012 (`native-subagent-memory-supersede-mediated`) — the agent-notes read-only watch pattern
  `chain-memory-section.sh`'s own header cites as precedent for "read-only, fail-graceful"
- ADR-0005 (`vibe-status-skill`) — founding ADR for `aggregate.sh`/`harness-runner.sh`, amended above
- ADR-0024/0025 (`vendor-deployed-only-skills-and-hooks`, `refresh-stale-staging-copies`) — confirms
  `staging/` is this roadmap's working source of truth; `~/.claude` stays untouched until a human sync
- ADR-0028 (`manifest-helpers-guards`, issue #32) — source of the `grep -c` count-guard idiom this ADR
  reuses verbatim for the same bug class
- ADR-0029 (`hook-verify-session-filter`, issue #33) — structural precedent for empirically-verified
  findings and the "unset ambient env vars the script reads" test convention
- `staging/plugin/skills/vibe-status/scripts/aggregate.sh`,
  `staging/plugin/skills/vibe-status/scripts/harness-runner.sh`,
  `staging/plugin/skills/vibe-status/tests/run-tests.sh`,
  `staging/plugin/skills/vibe-status/SKILL.md`, `staging/plugin/skills/vibe-status/INTEGRATION.md`,
  `staging/sync-to-claude.sh` — the files this ADR patches
- Implementation plan: `docs/superpowers/plans/2026-07-11-37-vibe-status-recursion-chains.md`

---

## 1. Context

`vibe-status` aggregates a health report by discovering every skill's `tests/run-tests.sh` under
`$HOME/.claude/skills/*/tests/` and every hook harness under `$HOME/.claude/hooks/tests/*.sh`, running
them in parallel via `harness-runner.sh` (a per-harness timeout wrapper), and rendering a Markdown
report. `vibe-status` is itself one of the discovered skills.

**Finding 1 (P2, recursion + orphaned processes, `aggregate.sh:36`, `tests/run-tests.sh:117`,
`harness-runner.sh:27-32`).** `aggregate.sh`'s own discovery loop finds
`vibe-status/tests/run-tests.sh` among the skills it discovers. That harness's own Test 10 (current
line 117) calls `aggregate.sh` again, unwrapped, against the real `$HOME`. That second `aggregate.sh`
invocation discovers the same 13 skill harnesses again — including `vibe-status/tests/run-tests.sh` a
second time — whose own Test 10 calls `aggregate.sh` a third time, and so on. This is not specific to
the test: any real, top-level invocation of `aggregate.sh` (a human running `vibe-status`, not just the
test suite) triggers the identical recursion, because the self-reference lives in the discovery loop
itself, not in the test.

**Empirically verified in this session**, on the real, unfixed code, real `$HOME`
(13 skills with an executable `tests/run-tests.sh`, one of which is `vibe-status` itself; 4 executable
harnesses under `hooks/tests/`): reproduced a one-level-nested `harness-runner.sh` invocation (outer
`TMO=2` wrapping a harness that itself calls the real, unfixed `harness-runner.sh` with `TMO=15` on a
harness that forks a long-lived grandchild). The outer wrapper's timeout fired and returned `RC=124` in
2s as expected, but `ps` immediately after showed the inner `timeout 15 bash leaf.sh` process tree
still alive with **PPID=1** (already reparented to `launchd`, i.e. genuinely orphaned) — the outer kill
never reached it. Root cause, traced precisely: this machine has both `timeout` and `gtimeout`
installed (Homebrew coreutils; stock macOS ships neither). GNU `timeout`, run without `--foreground`
(the default, and what `harness-runner.sh` uses), places its wrapped child into a **new** process group
and kills that whole group on its own timeout — this is correct in isolation. But every *nested*
`harness-runner.sh` invocation calls `timeout` again for its own harness, and each such call creates
**another** fresh process group, independent of the one the outer `timeout` is tracking. An outer kill
can only ever reach processes still inside the group it created; a nested timeout-wrapped subtree has
already moved to a different one by the time the outer kill fires. This matches the SPEC's own
description exactly ("nested timeout invocations move into fresh process groups and survive the parent
kill") and is the mechanism behind the live orphans observed on Stefano's machine, not merely a
hypothetical.

Separately, but also named by SPEC finding 1: `harness-runner.sh`'s third branch (used when neither
`timeout` nor `gtimeout` is on `PATH` — the case on a stock macOS without Homebrew coreutils) kills only
the single top PID (`kill -9 "$P"`), which by construction can never reach any child the harness itself
forks, group or no group. This branch is dead on Stefano's own machine today but is real, load-bearing
code for any machine without Homebrew coreutils installed.

The SPEC also flags that `tests/run-tests.sh`'s Test 10 builds a sandboxed `TMP_AGG_HOME` fixture
(current lines 109-115) it never actually uses — the real invocation two lines later (current line 117)
runs against the unmodified real `$HOME`, dead-code evidence of an earlier, abandoned attempt to make
this specific test hermetic. A second, adjacent dead write exists at current line 105
(`bash "$AGG" --skip-harness >"$TMP/o10"`), whose output is never read anywhere in the test.

**Finding 2 (P2, Memory section rendering, `aggregate.sh:180`).**
```bash
pcount=$(grep -c '^\- \[' "$MEM_FILE" 2>/dev/null || echo 0)
```
is the identical bug class ADR-0028 (issue #32) already fixed once in this codebase, in a sibling
script: `grep -c` already prints a numeric count on every outcome, including zero matches — on zero
matches it prints `0` **and** exits `1`. The `||` then fires on that exit code, appending a *second*
`echo 0` to the same command substitution, so `$pcount` becomes the two-line string `"0\n0"` whenever
`MEMORY.md` exists with no `- [` index entries. `MEM_LINE="$pcount entries indexed in MEMORY.md"` then
embeds that two-line value into what the Markdown renderer treats as a single report line, breaking the
`## Memory` section's rendering exactly as SPEC describes.

**Finding 3 (P2, ADR-0021 wiring never executed, reverse drift, `staging/plugin/skills/vibe-status/`).**
`INTEGRATION.md` (staged 2026-06-22) fully specifies a read-only `## Active chains` section —
`chain-memory-section.sh` already exists in `staging/plugin/skills/vibe-status/scripts/`, reads the
`chain-history/<slug>.md` STATE OF FACT headers ADR-0021 defines, and renders non-terminal chains. It
has never been wired into `aggregate.sh`'s render path, never added to `SKILL.md`'s Discovery section,
and — confirmed by grep across the whole repo before writing this ADR — has **zero** existing test
coverage anywhere. It also has no `sync-to-claude.sh` PAIRS entry, so even a full `--apply` sync today
would silently omit it while still deploying the `aggregate.sh` that would (once wired) try to call it.

**Confirmed before planning, not assumed:**
- `docs-ci.yml`'s `shell-tests` job has an explicit 11-file list; `vibe-status/tests/run-tests.sh` is
  not in it and never has been — this harness is, and remains, CI-dark by design (it inspects the real
  deployed `$HOME/.claude`, which does not exist in a CI checkout).
- `.claude/test-cmd` (`for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`)
  does not glob this file either — same reason.
- The `review-triage-fix` anchor referencing vibe-status (`tests/run-tests.sh:169-170`) only checks that
  `SKILL.md` contains the string `Vibe-Coding System Status` — untouched by this ADR's changes, safe.
- No file outside `staging/plugin/skills/vibe-status/` and `staging/sync-to-claude.sh` references
  `TMP_AGG_HOME`, the `target PASS=13` count, or `harness-runner.sh`'s internal timeout mechanism in a
  way this change would break (`grep` swept the whole repo; the only hits are this skill's own files,
  historical ADRs/plans recording past, already-executed states, and `SPEC.md`/its `docs/specs/` copy).

## 2. Decision

Fix all three findings inside `staging/plugin/skills/vibe-status/` only. Add four new test assertions
(14-17) to `tests/run-tests.sh`, bringing it from 13 to 17. Add one `sync-to-claude.sh` PAIRS entry. Do
not touch `~/.claude`, `docs-ci.yml`, or `.claude/test-cmd` — none of the three findings, nor SPEC's own
scope, call for any of that.

### 2.1 Finding 1a — recursion guard: a name-scoped environment sentinel

`aggregate.sh` gains, immediately after its existing `RUNNER=...` line (current line 25):
```bash
# Recursion guard (issue #37): vibe-status's own harness (tests/run-tests.sh) calls this same
# script as part of testing itself (SKILL.md Discovery). Without a guard, every real invocation
# discovers and re-invokes its own skill's harness, which reaches aggregate.sh again, unbounded —
# empirically reproduced in this session, not hypothetical. NESTED records whether this process
# was already inside an aggregate.sh sweep when it started (inherited via env export); a nested
# aggregate.sh skips re-discovering the vibe-status entry specifically, capping self-testing to
# exactly one level regardless of recursion depth elsewhere.
NESTED="${VIBE_STATUS_RECURSING:-0}"
export VIBE_STATUS_RECURSING=1
```
and the skills-discovery loop (current lines 36-42) gains one `case` guard before the existing
`HARNESS_TOTAL` increment:
```bash
for h in "$HOME"/.claude/skills/*/tests/run-tests.sh; do
  [ -f "$h" ] || continue
  [ -x "$h" ] || continue
  case "$h" in
    */skills/vibe-status/tests/run-tests.sh) [ "$NESTED" = "1" ] && continue ;;
  esac
  HARNESS_TOTAL=$((HARNESS_TOTAL + 1))
  ...
```
At the top level (`NESTED=0`), nothing changes — the human-facing report still tests vibe-status once,
same as today. Only a nested invocation (reached exclusively via vibe-status's own recursive self-test)
skips re-adding itself; it still discovers and runs the other ~12 skills and ~4 hooks normally, which is
exactly what Test 10 was already trying to verify. Recursion is now bounded to one extra level by
construction, not by luck or by a race against a timeout.

`hooks/tests/*.sh` discovery (current lines 44-50) is untouched — no hook harness calls `aggregate.sh`,
so there is nothing to guard there.

### 2.2 Finding 1b — `harness-runner.sh`: kill the whole process group, unconditionally

Replace the three-way `timeout`/`gtimeout`/manual branch (current lines 18-32) with one path built on
bash job control, which needs no external binary and is present in bash 3.2+ unconditionally:
```bash
set -m
bash "$H" >"$OUT" 2>&1 &
P=$!
(
  sleep "$TMO"
  kill -0 "$P" 2>/dev/null || exit 0
  kill -TERM -- "-$P" 2>/dev/null
  sleep 1
  kill -0 "$P" 2>/dev/null && kill -KILL -- "-$P" 2>/dev/null
) &
W=$!
wait "$P" 2>/dev/null; RC=$?
kill -9 "$W" 2>/dev/null; wait "$W" 2>/dev/null
set +m
[ "$RC" -gt 128 ] && RC=124
```
`set -m` makes the backgrounded `bash "$H"` the leader of its own new process group (its PGID equals its
own PID, `$P`) regardless of what `$H` itself forks; `kill -TERM -- "-$P"` / `kill -KILL -- "-$P"`
targets that whole group by negative PID, the POSIX process-group-kill convention. The `RC=127`
(no arg / file not found) branches (current lines 12-13) and the output contract (`RC=<n> DUR=<s>s` first
line, then harness stdout/stderr) are unchanged.

**Empirically verified in this session**, all four observable outcomes: (1) a harness that forks a
`sleep 20 &` grandchild, wrapped with `TMO=2` — the grandchild is gone (no marker file written) within
the bounded post-kill poll, `RC=124`; (2) the same run's captured stderr is empty — `set -m` in a
non-interactive script produces no stray job-control notification text that could corrupt the
`RC=`/`DUR=` header line; (3) a harness that exits `1` normally (no timeout in play) still reports
`RC=1`; (4) a harness that exits `0` normally still reports `RC=0`. All four ran under this machine's
actual `/bin/bash` on `PATH`, confirmed to be bash 3.2.57 — the actual constraint target, not a newer
Homebrew bash shadowing it.

**Fifth outcome (added during the issue #37 review cycle):** a harness that dies from its own signal
(e.g. self-`SIGTERM` = 143) with no timeout in play must NOT be clamped to `RC=124` — the pre-fix
`timeout`/`gtimeout` branches (the ones that actually ran on this machine) passed 143 through
unclamped and `aggregate.sh` bucketed it as `ERROR`, not `TIMEOUT`. The first draft's unconditional
`RC>128 → 124` clamp mislabeled such crashes; fixed with a watchdog-owned kill marker
(`$OUT.killed`, written by the watchdog just before it kills the group) so only watchdog-issued
kills clamp. Verified live post-fix: self-kill → `RC=143`, watchdog timeout → `RC=124` with zero
orphans, normal exits unchanged.

### 2.3 Finding 2 — Memory count guard, same idiom as ADR-0028

```bash
pcount=$(grep -c '^\- \[' "$MEM_FILE" 2>/dev/null)
if [ -z "$pcount" ]; then
  pcount=0
fi
```
One line becomes four, identical in shape to ADR-0028 §2.1's fix for the same bug class: `grep -c` keeps
its own correct zero-on-no-match behavior; only the erroneous `|| echo 0` second-line append is removed,
replaced by a defensive `-z` guard for the case `grep` cannot run at all. The pattern itself
(`^\- \[`) and the surrounding `if [ -f "$MEM_FILE" ]` / `MEM_LINE=...` lines are untouched.

### 2.4 Finding 3 — execute the ADR-0021 wiring, staging side only

`aggregate.sh`'s Section 7 (current lines 175-182) and Section 7b (current lines 184-200) both derive a
per-cwd memory directory path independently (`$HOME/.claude/projects/$ENC/memory/...`). Factor it once,
immediately before Section 7:
```bash
MEM_DIR="$HOME/.claude/projects/$ENC/memory"
```
Section 7 becomes `MEM_FILE="$MEM_DIR/MEMORY.md"`; Section 7b becomes `AN_DIR="$MEM_DIR/agent-notes"`.
Both sections' own logic beyond that one line is untouched.

In the Markdown/plain render branch, immediately after the existing `## Memory` block (current line
293) and before `## Agent notes` (current line 295), add the exact call INTEGRATION.md already
specifies:
```bash
bash "$HOME/.claude/skills/vibe-status/scripts/chain-memory-section.sh" "$MEM_DIR" || true
```
`chain-memory-section.sh` itself is untouched — it already prints nothing when there are no active
chains or no `chain-history/` directory, and a full `## Active chains (concept-to-code)` block
otherwise; its own header already documents the read-only, fail-graceful contract this ADR relies on.
The `--json` branch is not touched — see Alternatives §3.4 (D2) for why.

`SKILL.md`'s Discovery → Locale list gains one bullet (INTEGRATION.md's own suggested text):
`Chain history: ~/.claude/projects/<encoded-cwd>/memory/chain-history/*.md (active chains)`, and the
Output sample paragraph gains one sentence noting the new section appears when in-progress chains
exist — both exactly as INTEGRATION.md already specifies.

`INTEGRATION.md` itself gains a short status note at the top recording that the staging-side wiring is
executed by this ADR, and its "Deploy (live, separate HITL step)" section is rewritten to point at the
now-adequate `sync-to-claude.sh --apply` (once the new PAIRS entry below lands, that single standard
sync command covers this file exactly like the other four vibe-status files already synced) instead of
the manual `cp`/`chmod` commands it currently describes, which become redundant, not wrong.

`staging/sync-to-claude.sh`'s `PAIRS` block gains, grouped with the other four vibe-status entries:
```
plugin/skills/vibe-status/scripts/chain-memory-section.sh|skills/vibe-status/scripts/chain-memory-section.sh
```
This is the only new PAIRS entry this ADR adds — `aggregate.sh`, `harness-runner.sh`, `SKILL.md`, and
`tests/run-tests.sh` already have PAIRS mappings from prior work; only their *content* changes here, not
their sync status.

### 2.5 Test strategy

`tests/run-tests.sh` grows from 13 to 17 assertions, target-count comment updated accordingly. Four new:

- **Test 14** — `harness-runner.sh` kills the whole process group on timeout. PGID-scoped (the harness
  writes its own `$$` to a file before forking a long-lived grandchild — under the fix, `$$` is also the
  process group id), bounded polling wait (max ~8s, not a fixed sleep), asserts zero surviving members of
  that PGID and that the grandchild's own completion marker was never written. Self-cleans via a
  negative-PID `kill -9` in its own failure branch so a failing assertion cannot itself leak a
  long-running process into the machine running the suite.
- **Test 15** — the recursion guard caps vibe-status's self-invocation to exactly one nested level. Fully
  hermetic: an isolated fake `$HOME` containing only a minimal stub `vibe-status/tests/run-tests.sh` (plus
  a copied `harness-runner.sh`, required for the stub to even be invocable) that increments a marker file
  and recurses into the real `aggregate.sh` under test with the same fake `$HOME`. Asserts the marker was
  written exactly once (not `>1`, which is what the unfixed code produces) and the whole call completes
  within a generous bound. Does not touch the real `$HOME`.
- **Test 16** — `MEMORY.md` with zero `- [` index lines renders `0 entries indexed in MEMORY.md` on a
  single line (not the two-line `"0\n0..."` the unfixed code produces).
  Fixture-based, isolated `$HOME`/cwd, no dependency on the real environment's actual `MEMORY.md`.
- **Test 17** — the chain-memory wiring: given a fixture `chain-history/` file with `status: in_progress`
  (non-terminal), `aggregate.sh`'s Markdown output contains `## Active chains`; given no `chain-history/`
  directory at all, it does not. This is the only existing coverage `chain-memory-section.sh` gains
  anywhere in the repo — it tests the wiring (does `aggregate.sh` call it, with the right argument, at
  the right point), not the script's own internal STATE OF FACT parsing, which is out of this issue's
  scope (the script itself is untouched).

Test 10 is simplified, not replaced: the dead `$TMP/o10` write (current line 105) and the never-used
`TMP_AGG_HOME` fixture (current lines 109-115) are deleted; the real assertion (current lines 117-124,
`>= 5` harnesses found via a genuine, unwrapped `aggregate.sh` run against the real `$HOME`) is kept,
now safe to run because of §2.1's guard, and gains a wall-clock upper bound (a generous ceiling well
above the bounded one-extra-level cost) as an explicit regression pin against the recursion ever coming
back unbounded.

All 17 assertions stay bash 3.2 / BSD-safe: no `mapfile`, no `declare -A`, no `${v^^}`, no `<()`. Test
15's fixture, by construction, transiently spawns a handful of short-lived, self-terminating background
processes while exercising the guard in its own hermetic sandbox during development/verification of this
fix — the plan's Task 1 checkpoint includes an explicit cleanup step for that specific run. `run-tests.sh`
itself stays CI-dark and `$HOME`-coupled by design (Test 10's own nature, unchanged) — no `docs-ci.yml` or
`.claude/test-cmd` edit is made or needed.

## 3. Alternatives considered

### 3.1 Recursion guard mechanism (Finding 1a)

**Chosen:** environment-variable sentinel (`VIBE_STATUS_RECURSING`), exported once at the top of
`aggregate.sh`, checked by name against the one specific self-referential discovery-loop entry.

- **Alternative — point Test 10 at the already-built `TMP_AGG_HOME` fixture instead** (SPEC's own named
  alternative fix). Rejected as the *primary* fix, though the dead fixture is still deleted as cleanup
  regardless: this only makes the *test's* recursion go away. It does nothing for the live production
  bug — every unwrapped, real invocation of `aggregate.sh` (a human running `vibe-status`, not just
  `run-tests.sh`) discovers and re-invokes vibe-status's own harness today, confirmed by this session's
  own empirical reproduction against the real, deployed 13-skill inventory. A test-only fix would leave
  the actually-observed, live bug live and merely hide it from this one test.
- **Alternative — fully hermetic redesign of the entire vibe-status test suite** (make all 13-17
  assertions `$HOME`-independent, add the file to `docs-ci.yml`). Rejected as out of scope: none of
  SPEC's three objectives ask for a suite-wide hermeticity migration, and `run-tests.sh` is deliberately
  an integration-style check of the real, deployed `~/.claude` by original design (ADR-0005) — that is
  a legitimate, separate property worth revisiting some day, not something this issue's three findings
  require touching.
- **Alternative — generic recursion detection** (`aggregate.sh` inspects each discovered harness path
  via `$0`/`realpath` self-comparison, or maintains a call graph, instead of a hardcoded name match).
  Rejected as over-engineering for the actual failure mode: exactly one skill (vibe-status) has a test
  suite that calls back into `aggregate.sh`; no other skill's harness does. A generic mechanism would
  need to either execute/parse each candidate first (defeating the point of a cheap pre-filter) or track
  a call graph across processes — real complexity for a problem with exactly one instance today. The
  accepted trade-off (the guard silently stops matching if vibe-status is ever renamed or relocated) is
  disclosed in Consequences, not hidden.

### 3.2 `harness-runner.sh` group-kill mechanism (Finding 1b)

**Chosen:** bash job control (`set -m`) + negative-PID `kill -TERM`/`kill -KILL`, one unified path,
verified empirically as described in §2.2.

- **Alternative — keep the existing three-way branch, patch only the manual-fallback `else`** (the one
  branch objectively broken today: `kill -9 "$P"` targets a single PID and, by construction, can never
  reach any child the harness forks, group or no group). Rejected: this session's own empirical
  reproduction (§1, nested-timeout scratchpad test) proved that even *with* `timeout` present and firing
  correctly by its own documented default behavior, a **nested** `timeout` invocation still escapes the
  outer kill, because each `timeout` call creates its own fresh process group independent of the outer
  one. Patching only the third branch would leave the other two branches carrying that same fragility,
  resting on assumed (not independently re-verified per-branch) third-party defaults. Unifying around one
  self-owned mechanism this codebase controls directly removes that dependency entirely, for all three
  former branches at once.
- **Alternative — use `setsid` to force a new session/process group.** Rejected: `setsid` is a GNU
  coreutils/util-linux tool, confirmed absent from this machine's stock `PATH` layout (which has
  Homebrew's `timeout`/`gtimeout` but no bare `setsid`) — using it would reintroduce exactly the kind of
  external-binary dependency this fix exists to remove, on a tool that is *less* commonly pre-installed
  on macOS than even `timeout` was. Bash's own `set -m` is a shell builtin, present unconditionally in
  bash 3.2+.
- **Alternative — keep `timeout`/`gtimeout` as the primary timing mechanism for signal precision, layer
  bash job-control group-tracking only as an after-the-fact defense-in-depth cleanup pass.** Rejected as
  unnecessary complexity: this session's empirical tests show a plain `sleep "$TMO"` + `kill -0` polling
  loop is precise enough here (harness timeouts are whole-second values in the 2-12s range; nothing in
  `SKILL.md`'s contract needs sub-second precision), and running two independent timing mechanisms for
  one deadline is a source of races and dual-maintenance cost for no measured benefit.

### 3.3 Memory count fix (Finding 2)

**Chosen:** reuse ADR-0028's exact idiom — drop `|| echo 0`, add an explicit `-z` guard.

- **Alternative — replace `grep -c` with `grep PATTERN FILE | wc -l | tr -d ' '`.** Rejected, for the
  identical reason ADR-0028 §3.1 already gave at the identical bug class: `grep -c` already prints a
  correct `0` on the zero-match case entirely on its own; the bug is the redundant `|| echo 0` appending
  a second line, not any deficiency in `grep -c` itself. Switching tools here would also make this fix
  visually inconsistent with its own sibling fix from one issue earlier, for zero behavioral gain.

### 3.4 Chain-memory wiring execution scope (Finding 3)

**Chosen:** execute exactly the staging-side wiring INTEGRATION.md already specifies, add the missing
PAIRS entry, update INTEGRATION.md's own "Deploy" section to reflect that PAIRS now covers it.

- **Alternative — also deploy to `~/.claude` in this same pass** (run `sync-to-claude.sh --apply`).
  Rejected: explicitly out of SPEC's own stated scope ("Out: Deploying the wiring... is a separate human
  step"), and `~/.claude` is read-only for this task per the operating brief. The new PAIRS entry is
  sufficient for the *next* human-run sync to pick this file up automatically alongside the other four,
  already-paired vibe-status files — no further action is needed from this issue.
- **Alternative — extend `--json` output with an `active_chains` field, for symmetry with the Markdown
  section.** Rejected (labeled D2 in the plan): INTEGRATION.md's own text describes only the Markdown
  render path; a repo-wide grep before writing this ADR found zero existing consumers of
  `aggregate.sh --json` output at all, so there is no concrete need driving this, and adding an
  undocumented field would be unrequested scope growth beyond what INTEGRATION.md itself specifies. Left
  for a future issue if a real JSON consumer ever needs it.

## 4. Consequences

### Positive

- The recursion is eliminated at its root cause (the discovery loop itself), not merely worked around in
  one test — every real, top-level invocation of `aggregate.sh` benefits, not just `run-tests.sh`.
  Recursion is now bounded to exactly one extra level by construction, independent of timing or luck.
- `harness-runner.sh`'s group-kill is now correct and dependency-free: it no longer requires `timeout` or
  `gtimeout` to be installed, fixing the manual-fallback branch's objectively broken single-PID kill on
  any machine without Homebrew coreutils (stock macOS included) — a portability improvement beyond what
  SPEC's own finding required, obtained for free by unifying the three branches into one.
- The `## Memory` section renders correctly for a `MEMORY.md` with zero index entries, using the exact
  idiom already proven correct one issue earlier (ADR-0028), keeping the two fixes visually and
  behaviorally consistent for future readers of either script.
- ADR-0021's chain-memory wiring finally goes live in the vendored (staging) copy, closing the "reverse
  drift" finding from the audit (staged 2026-06-22, unexecuted until now) — the next human sync will
  surface in-progress `concept-to-code` chains directly in every `vibe-status` report.
- Test coverage grows from 13 to 17 assertions, closing four previously-untested surfaces at once:
  group-kill semantics, recursion-guard semantics, the Memory zero-count edge case, and the chain-memory
  wiring (which had zero coverage anywhere in the repo before this ADR).
- Two genuinely dead code blocks are removed from Test 10 (the unused `TMP_AGG_HOME` fixture and the
  unused `$TMP/o10` write), leaving a smaller, clearer, and now demonstrably safe test.
- No `~/.claude` file is touched; no `docs-ci.yml` or `.claude/test-cmd` edit; the fix is fully contained
  in `staging/`, consistent with every prior ADR in this roadmap (ADR-0024 through ADR-0032).

### Negative

- `harness-runner.sh`'s rewrite (dropping `timeout`/`gtimeout` for bash job control) is a non-trivial
  behavioral change to a script every skill's `run-tests.sh` execution passes through via `aggregate.sh`.
  This session's empirical verification ran on exactly one machine (bash 3.2.57, arm64 macOS) — residual
  risk that some other bash build or environment interacts differently with `set -m` in a non-interactive
  script is not fully eliminated by a single session's testing. Mitigation: Test 7 (pre-existing,
  `RC=124` on timeout) and the new Test 14 (PGID-scoped group-kill) both pin the observable contract, so
  a regression on a different environment would be caught by the suite, not silently shipped.
- The recursion guard is a hardcoded path-suffix match (`*/skills/vibe-status/tests/run-tests.sh`), not a
  generic self-detection mechanism. If vibe-status is ever renamed or relocated, the guard silently stops
  matching and the original unbounded recursion returns with no warning. Accepted and disclosed
  (§3.1) rather than solved generically, given the actual failure mode has exactly one instance today.
- Cleanup after an *external* kill (a human's Ctrl-C, or a CI job timing out the whole process) is
  bounded but not instantaneous: the deepest nested harness's process group can stay alive for up to one
  more `TMO` window after its parent dies, cleaned up by its own orphaned watcher subshell rather than
  immediately by the outer kill (empirically confirmed in this session, prior to the recursion-guard fix
  — with the guard capping recursion to one level, this residual window is now small and finite instead
  of unbounded). Not solved further here; see §3.2 for why a stronger, instant-cascading-kill design was
  rejected as unneeded complexity given the now-small bound.
- Test 15's own RED-phase verification (Task 1 of the implementation plan) deliberately exercises the
  *unfixed* recursive code path in its isolated fixture and will transiently spawn a handful of
  short-lived orphaned background processes under that fixture's own `mktemp` path before the Task 3 fix
  lands — the plan includes an explicit cleanup step scoped to that one checkpoint.

### Neutral

- The chain-memory wiring is scoped to the Markdown/plain render path only; `--json` output gains no
  equivalent field (§3.4, D2) — not a limitation being carried forward, simply matching what
  INTEGRATION.md itself specifies and what the repo actually consumes today.
- INTEGRATION.md's "Deploy" section changes from manual `cp`/`chmod` instructions to "run the standard
  `sync-to-claude.sh --apply`" — a simplification enabled by the new PAIRS entry, not a scope change; the
  actual deploy action (a separate, human-gated step) is unchanged.
- `run-tests.sh` remains CI-dark and `$HOME`-coupled by design (Test 10's own long-standing nature) —
  this ADR does not attempt, and was not asked, to make the suite hermetic or CI-lit; that remains a
  legitimate but separate, unscoped future improvement.

## 5. References

- SPEC: `docs/specs/37-vibe-status-recursion-guard-and-active-c.spec.md` (= `SPEC.md`, GitHub issue #37)
- ADR-0021 — `docs/architecture/ADR-0021-chain-memory-posttooluse-native-store.md`
- ADR-0012 — `docs/architecture/ADR-0012-implementation-plan.md` (agent-notes read-only watch precedent)
- ADR-0005 — `docs/architecture/ADR-0005-vibe-status-skill.md` (amended, §Amends above)
- ADR-0024 — `docs/architecture/ADR-0024-28-vendor-deployed-only-skills-and-hooks.md`
- ADR-0025 — `docs/architecture/ADR-0025-29-refresh-stale-staging-copies.md`
- ADR-0028 — `docs/architecture/ADR-0028-32-manifest-helpers-guards.md` (§2.1, the reused `grep -c` idiom)
- ADR-0029 — `docs/architecture/ADR-0029-33-hook-verify-session-filter.md` (structural/test precedent)
- `staging/plugin/skills/vibe-status/scripts/aggregate.sh`,
  `staging/plugin/skills/vibe-status/scripts/harness-runner.sh`,
  `staging/plugin/skills/vibe-status/scripts/chain-memory-section.sh` (untouched, newly wired),
  `staging/plugin/skills/vibe-status/tests/run-tests.sh`, `staging/plugin/skills/vibe-status/SKILL.md`,
  `staging/plugin/skills/vibe-status/INTEGRATION.md`, `staging/sync-to-claude.sh`
- Implementation plan: `docs/superpowers/plans/2026-07-11-37-vibe-status-recursion-chains.md`
