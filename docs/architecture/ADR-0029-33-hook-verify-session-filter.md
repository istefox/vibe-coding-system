# ADR-0029 — hook-verify-workflow: filter the audit window by session

**Status:** Accepted
**Date:** 2026-07-11
**Author:** istefox
**Supersedes:** none
**Amends:** ADR-0016 (`dynamic-workflows-step5`), section "Smoke test replaced by `hook-verify-workflow`" —
the exit-3 (INCONCLUSIVE) contract documented there gains a second cause. ADR-0016 itself is left
unedited (historical record); this ADR is the amendment of record.
**Superseded by:** none
**Related:**
- SPEC: `docs/specs/33-hook-verify-workflow-filter-the-audit-wi.spec.md` (= `SPEC.md` at repo root,
  GitHub issue #33, confirmed byte-identical by diff before writing this ADR)
- ADR-0016 (`dynamic-workflows-step5`) — introduced `hook-verify-workflow.sh` and its exit-code
  contract; amended by this ADR
- ADR-0004 (`pre-flight-pattern-enforce-hook`) — the guard that writes the audit log this script
  reads; source of the `session_id` field this ADR's fix filters on
- ADR-0024/0025 (`vendor-deployed-only-skills-and-hooks`, `refresh-stale-staging-copies`) — confirms
  `staging/` is this roadmap's working source of truth; the deployed `~/.claude` copy stays untouched
  until a human sync, same convention this ADR follows
- ADR-0028 (`manifest-helpers-guards`) — immediately preceding issue (#32) in this roadmap and the
  same test-directory; structural precedent for empirically-verified findings, exhaustive
  backward-compatibility tracing, and the "disclose an environment/version-dependent gap rather than
  assert unverified confidence" idiom this ADR reuses
- `docs/specs/34-scope-guards-autopilot-cwd-check-conduct.spec.md` — issue #34's spec, which assumes
  "the global smoke-test record written by hook-verify-workflow.sh" exists; this ADR records that it
  does not (Context, "Gap flagged for issue #34")
- `staging/plugin/scripts/hook-verify-workflow.sh`, `staging/plugin/scripts/tests/hook-verify-workflow.test.sh`,
  `staging/plugin/skills/concept-to-code/SKILL.md` — the files this ADR patches
- Implementation plan: `docs/superpowers/plans/2026-07-11-33-hook-verify-session-filter.md`

---

## 1. Context

`hook-verify-workflow.sh` decides the `hook_verified` manifest flag consumed by `concept-to-code`
SKILL.md's Step 5 dispatch-mode gate (ADR-0016): it brackets a one-agent smoke workflow with a
timestamp marker, then reads `pre-flight-pattern-enforce.sh`'s own audit log
(`${PATTERN_ENFORCE_DIR:-~/.claude/state/pattern-enforce}/audit.log`) for rows recorded after the
marker. Rows reaching `allow`/`block` prove the guard ruled on a coder subagent; that is read as proof
hooks propagate into workflow subagents, and `hook_verified` is set accordingly.

**The defect (SPEC.md, issue #33):** the AFTER-window computation, `hook-verify-workflow.sh:96`,
`awk -F'\t' -v m="$MARK" '$1 > m' "$LOG"`, filters only on timestamp (field 1). It does not filter on
`session_id` (field 2). The audit log is a single, machine-global file shared by every concurrent
Claude Code session on the machine (SPEC.md cites 4,916 rows across 88 session IDs at audit time). Any
coder dispatched by **any** concurrent session, in any project, after the marker, makes `--check`
report `VERIFIED` — this is exactly the false-positive risk ADR-0016 itself named as a hard blocker for
the Workflow dispatch path.

**Baseline, re-verified before planning (2026-07-11), not assumed from the roadmap note:**
```
for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done
```
is green: 8 files match this glob (`clean-public-repo-history-safety`,
`concept-to-code-bsd-autopilot-gates`, `concept-to-code-manifest-helpers-guards`, `hook-probe`,
`hook-verify-workflow`, `pairs-completeness`, `phase1`, `prep`), identical in membership to
`.github/workflows/docs-ci.yml`'s explicit `shell-tests` list. `hook-verify-workflow.test.sh` itself:
`26 passed, 0 failed`. Two more files exist in the same directory without the `.test.sh` suffix
(`pre-flight-pattern-enforce.sh`, `db-backup-guardrail.sh`) — pre-existing, deliberately non-CI legacy
files (the roadmap note's "9 files" counts these as a bucket); neither is touched by, or relevant to,
this issue.

**Empirically reproduced in this session, against the real, unfixed script** (fixture: one AFTER-window
row, session_id `other-session-999`, decision `allow`):
```
$ PATTERN_ENFORCE_DIR=<fixture> bash hook-verify-workflow.sh --check "$MARK"
HOOK_VERIFY decisions_after_mark=1 enforced_on_coder=1 bypassed_workflow_subagent=0
HOOK_VERIFY status=VERIFIED
reason=pre-flight-pattern-enforce reached its allow/block branch, ...
RECOMMEND hook_verified=true
exit=0
```
Setting `CLAUDE_CODE_SESSION_ID=my-real-session-123` (a **different** session than the one that wrote
the row) in the environment makes no difference — the unfixed script never reads it. This is the exact
defect: a row from a completely unrelated session verified a session that produced no evidence at all.

### External-dependency verification: the SPEC's literal env var name is wrong

SPEC.md's scope section says: "When `CLAUDE_SESSION_ID` is available, filter the AFTER window on field
2 equal to it." This is the GitHub issue's own literal wording. **Verified against
`code.claude.com/docs/en/env-vars` (context7 `/websites/code_claude`, high source reputation,
corroborated across two independent doc chunks plus one changelog entry) that this exact name is
wrong:**

> "CLAUDE_CODE_SESSION_ID is automatically set to the current session ID in various subprocesses,
> including tool subprocesses, hook command subprocesses, and MCP server subprocesses. It can be used
> to correlate scripts and external tools with the Claude Code session that launched them."
> — `code.claude.com/docs/en/env-vars`

> "The CLAUDE_CODE_SESSION_ID is now available in the Bash tool subprocess environment, aligning with
> the `session_id` passed to hooks." — `code.claude.com/docs/en/whats-new/2026-w19`

The real variable is **`CLAUDE_CODE_SESSION_ID`**, not `CLAUDE_SESSION_ID`. A web search independently
corroborates this (community reports cite `CLAUDE_CODE_SESSION_ID`, available in Bash tool subprocesses
from CC v2.1.132+, "matches the session_id field in hook input JSON") and surfaces multiple still-open
`anthropics/claude-code` GitHub issues requesting Anthropic expose a variable literally named
`CLAUDE_SESSION_ID` — further evidence that exact spelling was never shipped. Had this ADR implemented
the SPEC's literal text, the primary session-filter code path would never engage on any real invocation
(the env var would never be found under that name): the fix would silently degrade to the
multi-session-ambiguity fallback only, defeating its own purpose in the single most common real-world
case (env var present, one or more concurrent sessions). **Decision 2.1 below uses the corrected name,
disclosed here as a correction to the issue's literal wording, not a silent deviation.**

Also verified: subagents dispatched within one Claude Code session (Task/Agent tool, or a Workflow
`agent()` call) **share the same `session_id`** as their parent/orchestrator session — confirmed by
`pre-flight-pattern-enforce.sh`'s own subagent-transcript-path derivation
(`$SID/subagents/agent-$AGENT_ID.jsonl`, nesting under the **parent's** `$SID`, ADR-0004 §2.1 "Q1")
and independently corroborated by a web search of `anthropics/claude-code` issue reports describing the
shared-session-id behavior for Task-tool subagents. This confirms filtering the audit log by
`CLAUDE_CODE_SESSION_ID` correctly scopes to "this session and every subagent it dispatches" (including
a workflow-dispatched coder), while excluding rows from any other, unrelated concurrent session — the
exact scoping SPEC.md's fix requires.

### Gap flagged for issue #34 (per roadmap instruction: disclose, do not implement here)

`docs/specs/34-scope-guards-autopilot-cwd-check-conduct.spec.md:14` assumes nightly-autopilot's Phase P
pre-flight check 6 can "consult the global smoke-test record written by hook-verify-workflow.sh (ADR-0016
result is global per CC version)". **No such record exists.** `hook-verify-workflow.sh`'s own header
states its contract plainly: "Read-only: never writes a manifest, never touches the audit log." It only
prints a recommendation to stdout; the only thing that persists a verdict is
`manifest-set-flag.sh <manifest> hook_verified <bool>`, called by the **caller** (SKILL.md's Step 5
gate), and that writes to one manifest's own YAML — scoped to that single manifest, not global. This fix
does not change that (the script stays read-only and stateless — see Decision 2.4/Alternatives §3.4),
so it neither closes nor worsens the gap. Issue #34's design will need either a new, separate persistent
store, or a different pre-flight-check-6 design that does not assume one already exists.

## 2. Decision

Filter the AFTER window by `CLAUDE_CODE_SESSION_ID` when it is available; when it is not, detect and
refuse to guess across an ambiguous multi-session window; otherwise preserve every existing behavior
exactly. Extend the existing test file (`hook-verify-workflow.test.sh`) rather than create a sibling —
SPEC.md's own instruction, and consistent with the file's already-focused, script-scoped remit. Update
the script's own header (exit-code contract) and `SKILL.md`'s Step 5 gate prose (the consumer of that
contract) so neither goes stale.

### 2.1 Session filtering: `CLAUDE_CODE_SESSION_ID`, with an ambiguity-aware fallback

```bash
AFTER_RAW=$(awk -F'\t' -v m="$MARK" '$1 > m' "$LOG" 2>/dev/null)

SID_SELF="${CLAUDE_CODE_SESSION_ID:-}"
SESSION_SCOPE="none"

if [ -n "$SID_SELF" ]; then
  AFTER=$(printf '%s\n' "$AFTER_RAW" | awk -F'\t' -v sid="$SID_SELF" '$2 == sid')
  SESSION_SCOPE="$SID_SELF"
else
  DISTINCT_SIDS=$(printf '%s\n' "$AFTER_RAW" | awk -F'\t' 'NF>0{print $2}' | sort -u | wc -l | tr -d ' ')
  if [ "$DISTINCT_SIDS" -gt 1 ]; then
    printf 'HOOK_VERIFY status=INCONCLUSIVE\n'
    printf 'reason=%s\n' "CLAUDE_CODE_SESSION_ID is not set and $DISTINCT_SIDS different Claude Code sessions recorded pattern-enforce decisions after $MARK. Cannot tell which one ran this workflow's smoke test, so this is not evidence either way. Re-run when no other Claude Code session is active on this machine, or use a Claude Code CLI version that sets CLAUDE_CODE_SESSION_ID (code.claude.com/docs/en/env-vars)."
    printf 'RECOMMEND hook_verified=unchanged\n'
    exit 3
  fi
  AFTER="$AFTER_RAW"
fi
```

When `AFTER` is empty after filtering (session set, but nothing of ours in the window, while foreign
rows exist), a **new**, distinct REFUTED reason fires instead of the pre-existing "no decision at all"
message, so a human is not told hooks might be disabled when they are provably not:

```bash
if [ -z "$AFTER" ]; then
  if [ -n "$SID_SELF" ] && [ -n "$AFTER_RAW" ]; then
    printf 'HOOK_VERIFY status=REFUTED\n'
    printf 'reason=%s\n' "no pattern-enforce decision recorded for this session (CLAUDE_CODE_SESSION_ID=$SID_SELF) after $MARK. Decisions were recorded after $MARK, but they belong to other, concurrent Claude Code session(s) and are not evidence for this session's workflow smoke test. Confirm the workflow in THIS session actually dispatched with agentType: 'coder', then re-run."
    printf 'RECOMMEND hook_verified=false\n'
    exit 1
  fi
  # ... existing "no decision at all" message and exit 1, byte-identical, unchanged ...
fi
```

Everything downstream (`ENFORCED`, `BYPASSED_WF`, `TOTAL`, the VERIFIED branch, the workflow-subagent
bypass branch, the final "ran in the main loop" branch) already operates on `$AFTER` — since `$AFTER`
now holds the **filtered** set whenever `SID_SELF` is set, these branches need **zero** further changes
to correctly count and decide only within scope. The summary line gains one purely additive field:

```bash
printf 'HOOK_VERIFY decisions_after_mark=%s enforced_on_coder=%s bypassed_workflow_subagent=%s session_scope=%s\n' \
  "$TOTAL" "$ENFORCED" "$BYPASSED_WF" "$SESSION_SCOPE"
```

**Threshold choice for the no-env-var case: `>1` distinct session ids, not `>=1`.** Exactly one session
id in the window (regardless of its value) has nothing to compare against and falls through to the
original, session-blind logic unchanged. This is deliberate (Alternatives §3.2) and is also what makes
every one of the 26 pre-existing assertions unaffected: none of them set the env var, and every fixture
in the file uses a single, uniform session id string ("sess") for every row, so `DISTINCT_SIDS` never
exceeds 1 for any of them — traced through all 9 existing fixtures individually during planning, not
assumed.

### 2.2 Header comment: keep the exit-code contract in sync

Current `hook-verify-workflow.sh:40-48` documents exit 3 as "the audit log is missing or unreadable"
only. Updated to name both causes:

```
#   3  INCONCLUSIVE — either the audit log is missing/unreadable, or CLAUDE_CODE_SESSION_ID is unset
#      and the post-marker window mixes rows from more than one Claude Code session with no way to
#      tell which one is ours (issue #33). Record NOTHING either way.
```

Exit 1's line gains "or only a different, concurrent Claude Code session did" (unchanged: still record
`false`, still take the fallback). A new "Known limit (issue #33)" paragraph is added after the existing
one (current lines 30-33), disclosing the residual gap Decision 2.4 does not close (Consequences,
Negative).

### 2.3 `SKILL.md`'s Step 5 smoke-test gate: the same sync, for the consumer

`SKILL.md:554-556` (the exit-3 bullet) currently reads, in full: "The audit log is missing, so
`pre-flight-pattern-enforce.sh` is not installed. Fix the install, then re-run." This is now
**actively misleading** for the new INCONCLUSIVE cause (an operator told to "fix the install" when the
real issue is a concurrent session would get nowhere). Updated to name both causes and point at the
script's own `reason=` line for the specific one. `SKILL.md:549-553` (the exit-1 bullet)'s two-cause
enumeration ("no decision recorded... or every workflow agent reported `workflow-subagent`") gains a
third clause naming the new REFUTED cause from §2.1, in the same paragraph, since leaving it
un-enumerated immediately beside a freshly-corrected sibling bullet would itself be a fresh
inconsistency (same reasoning ADR-0028 §2.5/§3.5 used for reconciling a whole paragraph, not just the
literally-named part of it). The **instruction** in both bullets (record `false`/nothing, which branch
to take) is unchanged; only the descriptive enumeration is extended.

### 2.4 The script stays read-only and stateless

No new state file, no new manifest field beyond the existing `hook_verified`, no change to what
`--mark` does. This preserves the script's own "Read-only... never touches the audit log" contract
(header, unchanged) and, as a side effect, leaves issue #34's own design space fully open (Context,
"Gap flagged for issue #34") — this ADR does not foreclose a future global record, it simply does not
build one, matching the roadmap instruction precisely.

### 2.5 Test strategy

Extend `staging/plugin/scripts/tests/hook-verify-workflow.test.sh` (not a sibling file) with 8 new
assertions across two sections, inserted before the existing "summary" block (current lines 118-120),
using a new `rowsid()` fixture helper (explicit session id, alongside the existing `row()` helper's
hardcoded `"sess"` placeholder, which stays untouched so none of the 26 pre-existing call sites change):

- **Session scoping (5 tests, S1-S5).** S1 (non-regression companion, already passing today): matching
  session id, allow row → VERIFIED. S2 (genuine RED): foreign session id, `CLAUDE_CODE_SESSION_ID` set
  → REFUTED, not VERIFIED — this is the exact false positive reproduced in Context. S3 (genuine RED):
  mixed rows, `CLAUDE_CODE_SESSION_ID` set → verdict AND the `decisions_after_mark` count are scoped to
  the matching session only (a foreign session's allow row does not rescue this session's own bypass).
  S4 (genuine RED): two distinct foreign session ids, no env var → INCONCLUSIVE, exit 3,
  `hook_verified=unchanged`. S5 (non-regression companion, already passing both before and after this
  fix): exactly one session id, no env var → legacy behavior, VERIFIED — this is the disclosed residual
  gap (§2.1, Consequences/Negative), pinned deliberately so a future change cannot silently alter it
  without this assertion failing first.
- **Exit-code contract sync (3 tests, S6-S8).** S6 (static, genuine RED): the script's own header
  documents the session-ambiguity INCONCLUSIVE cause. S7 (static, genuine RED): `SKILL.md`'s exit-3
  bullet no longer implies a missing log is the only cause. S8 (static, genuine RED): `SKILL.md`'s
  exit-1 bullet names the new concurrent-session REFUTED cause.

Final file: 26 (existing, unchanged) + 13 (new, across 8 named test cases S1-S8) = **39 assertions**. No CI wiring change —
`hook-verify-workflow` is already in `docs-ci.yml`'s explicit `shell-tests` list and in `.claude/test-cmd`'s
glob (both confirmed by direct reading before this ADR); extending an existing file needs neither.

Hermeticity guard (added during the review cycle): the test file now runs `unset CLAUDE_CODE_SESSION_ID`
before any fixture. The script under test reads exactly that variable, and the trusted test-cmd runs
inside live Claude Code sessions (stop-gate hook, RTF verify.sh), not only in clean CI shells — without
the guard, the ambient session id defeats the fixtures' hardcoded ids and 15 assertions fail in-session.
Cases exercising the variable-set path (S1-S3) set it explicitly per invocation, so the guard removes
non-determinism without weakening coverage. Validated in-session with an ambient id present: 39/39.

## 3. Alternatives considered

### 3.1 Which environment variable name to trust

**Chosen:** `CLAUDE_CODE_SESSION_ID` only (§2.1), verified against `code.claude.com/docs/en/env-vars`.

- **Alternative — use `CLAUDE_SESSION_ID` exactly as SPEC.md/the GitHub issue literally wrote it.**
  Rejected. Verified this name is not what Claude Code sets (Context, "External-dependency
  verification"); multiple open `anthropics/claude-code` feature requests asking for a variable with
  exactly this name further corroborate it was never shipped under that spelling. Implementing the
  literal text would leave the primary code path permanently unreachable in real usage — the whole
  point of this issue would silently not work, while every test using an env var of the same literal
  name the test author chose would still pass, masking the defect exactly the way ADR-0016's own
  `agent_type=coder` mismatch masked itself until checked against the real log (Context, ADR-0016 §
  cross-reference). Not repeating that mistake is the entire reason this ADR verifies external
  dependencies before writing the plan.
- **Alternative — check both `CLAUDE_CODE_SESSION_ID` and `CLAUDE_SESSION_ID` (fallback chain), to
  hedge against the docs being wrong or the shorter name shipping later.** Rejected. No evidence the
  shorter name is used, planned, or aliased anywhere in official documentation; adding a second,
  unverified variable name is exactly "promoting an assumption to a fact without a citation," which
  this project's own CLAUDE.md forbids. If Anthropic ships an alias later, adding it is a trivial
  one-line follow-up; speculatively coding for it now adds surface area for zero present benefit.

### 3.2 Ambiguity threshold when the env var is unavailable

**Chosen:** more than one distinct session id in the AFTER window triggers INCONCLUSIVE; zero or one
falls through to the original, session-blind logic (§2.1).

- **Alternative — treat the env var's absence itself as automatically INCONCLUSIVE, regardless of how
  many session ids appear.** Rejected outright by SPEC's own edge case ("Same-session rows only:
  VERIFIED" states no env-var precondition) and by the explicit success criterion "Existing test cases
  still pass" — none of the 26 pre-existing fixtures set the env var, so this alternative would break
  every one of them and make the gate never resolve on any CC version predating
  `CLAUDE_CODE_SESSION_ID`'s availability, a strict regression from today's behavior for the
  overwhelmingly common single-concurrent-session case.
- **Alternative — compare each row's session id against some other locally-derivable "self" identifier
  (e.g. shell `$$`, a PID) instead of session count.** Rejected as not actually addressing the same
  question: the audit log's field 2 is a Claude Code `session_id`, not a process id, and no PID-based
  value in this script's own process tree corresponds to it. There is no coherent "foreign" without a
  reference id to compare against; the only well-defined signal available without the env var is
  whether the window's own rows already disagree with each other, which is exactly the chosen design.

### 3.3 Where to add the doc-sync tests

**Chosen:** two additional static assertions (S7, S8) inside the same, extended
`hook-verify-workflow.test.sh` (§2.5).

- **Alternative — verify `SKILL.md`/header text only via a manual plan-checkpoint grep, no permanent
  test (mirroring how ADR-0026/27 treated some non-testable "process" properties, e.g. "no file under
  `~/.claude` modified").** Rejected. Those precedents are properties of a **session's actions** (what
  a human/agent did), which genuinely cannot be pinned by a static assertion on file content. `SKILL.md`
  prose describing the exit-code contract is a **static, checkable file-content property** with real
  operational stakes (an operator misreading a stale INCONCLUSIVE-cause description could misdiagnose a
  real problem) — a permanent drift-detecting assertion is two `grep` lines and strictly stronger
  protection than a one-time manual check that a later, unrelated `SKILL.md` edit could silently
  re-break.
- **Alternative — create a second, `SKILL.md`-focused test file (mirroring
  `concept-to-code-manifest-helpers-guards.test.sh`'s broader remit across multiple scripts and the
  whole skill).** Rejected. Two grep assertions do not justify a new file and its own CI-wiring task;
  SPEC.md's own instruction is to extend the existing file, and that file's own header already names
  "the exit-code contract" as its subject — `SKILL.md`'s Step 5 gate is a direct consumer of exactly
  that contract, squarely in scope for this file, not broad enough to warrant a sibling.

### 3.4 Whether to close the residual "single foreign session, no env var" gap

**Chosen:** disclose it; implement exactly the algorithm SPEC.md's scope section describes, nothing
more (§2.1, S5).

- **Alternative — require `CLAUDE_CODE_SESSION_ID` unconditionally; treat its absence as INCONCLUSIVE
  outright.** Rejected for the same reason as Alternatives §3.2's first alternative: regresses every
  environment where the variable is genuinely unavailable from "usable, session-blind" to "always
  inconclusive," breaking the 26 existing tests and SPEC's own "Same-session rows only: VERIFIED" edge
  case, which states no env-var precondition.
- **Alternative — add a session-scoped lock or marker file (e.g. a sentinel `--mark` writes and
  `--check` reads back) so the script can positively identify "its own" marker independent of the audit
  log's session field.** Rejected. This converts a deliberately read-only, stateless script (header
  contract: "Read-only: never writes a manifest, never touches the audit log") into a stateful one — a
  materially larger design change than this issue's scope, with new failure modes of its own (stale
  locks, concurrent `--mark` calls within one session, cleanup on crash) — and SPEC.md does not ask for
  it. A candidate for a future issue if the residual gap proves to matter in practice; not a silent
  scope expansion here, and not one that would even fully close the gap on its own (a lock file still
  says nothing about which session's *coder subagent* produced a given row without also correlating
  timestamps and session ids the same way the chosen design already does).

## 4. Consequences

### Positive

- Closes the exact false positive **empirically reproduced against the real, unfixed script in this
  session** (Context) whenever `CLAUDE_CODE_SESSION_ID` is available — verified to be the common case
  on any CC version at or after the one that introduced it (`code.claude.com/docs/en/whats-new/2026-w19`),
  which predates this repository's current working date.
- Corrects a latent defect in the GitHub issue's own literal environment-variable name **before it ever
  reached code**, caught by the mandatory external-dependency verification step rather than discovered
  later at test time (where a self-consistent but wrong fixture/script pair could have masked it, as
  ADR-0016 itself records happening once already with `agent_type=coder`) or in production.
- Exit 3 (INCONCLUSIVE) now also fires — instead of silently guessing — when evidence exists but cannot
  be attributed to a specific session, extending the exact "do not guess" discipline
  `hook-verify-workflow.sh`'s original author already applied to the missing-log case, to a second,
  newly-recognized instance of the same shape.
- All 26 pre-existing assertions proven, by individual trace through all 9 fixtures during planning (not
  merely expected), to take an unchanged code path under this fix — `DISTINCT_SIDS` never exceeds 1 and
  `SID_SELF` is never set in any of them.
- Zero new files, zero CI wiring changes, zero manifest schema changes, zero `~/.claude` writes — the
  smallest-blast-radius outcome available for a genuine correctness fix touching a security/trust-gate
  script.
- Gives issue #34 a concrete, verified answer to an assumption its own spec currently states as fact:
  no global smoke-test record exists yet (Context, "Gap flagged for issue #34"); #34's design must
  account for that rather than build on a record that was never written.

### Negative

- **Residual, disclosed blind spot (pinned by test S5):** with `CLAUDE_CODE_SESSION_ID` unset and
  exactly one *other* Claude Code session producing the only post-marker row, this script still reports
  a false VERIFIED — identical to today's behavior for that specific case. Not closed by this fix
  (Alternatives §3.4); no stronger guarantee is possible from a stateless, read-only script reading a
  global log without a materially larger design change this issue does not call for.
- The corrected environment variable is version-gated. On a CC version predating its introduction,
  every check silently falls back to the original, session-blind legacy behavior; nothing proactively
  warns an operator that this happened (the new `session_scope=none` diagnostic field records it, but
  only for someone who reads the output).
- The two new `SKILL.md`/header grep assertions (S6-S8) provide **presence-only** assurance (the
  corrected text exists) not semantic-correctness assurance (the text reads well and is accurate) — a
  human reviewer should still read the actual diff at commit time, not rely on green tests alone.
- `SKILL.md`'s exit-1 (REFUTED) bullet also gains a third example clause in the same edit (§2.3) — a
  small, disclosed scope nudge beyond SPEC.md's literal "keep the exit-code contract... in sync"
  instruction (which names exit 3 explicitly), made because the exit-1 and exit-3 bullets sit in the
  same short paragraph and leaving one freshly stale beside the other, just-corrected sibling would be a
  worse outcome for a reviewer than not having touched the paragraph at all — the same reasoning
  ADR-0028 §2.5/§3.5 used when it reconciled a whole paragraph rather than only the literally-named part
  of it.
- The currently-**deployed** copies (`~/.claude/skills/concept-to-code/scripts/hook-verify-workflow.sh`
  and `~/.claude/hooks/tests/hook-verify-workflow.test.sh`, per `staging/sync-to-claude.sh`'s own path
  mapping) keep today's false-positive-prone behavior until a human runs `sync-to-claude.sh --apply` —
  the same disclosed, established "deployed stays defective until sync, by design" convention this
  roadmap has used since ADR-0025/26/27/28, repeated here rather than assumed to already be understood.

### Neutral

- No hook wiring, no `settings.json`/`hooks.json`, no permission-mode change, no manifest schema change
  — this fix is entirely inside one script, its test file, and two `SKILL.md` prose bullets.
- The diagnostic summary line gains one new, purely additive field (`session_scope=<id>|none`) for
  operator/test visibility; the three pre-existing fields on that line keep their exact prior meaning.
- Reuses, rather than invents, the "disclose an environment/version-dependent coverage gap rather than
  assert unverified confidence" idiom already established by ADR-0026 §2.4/§3.5, ADR-0027 §2.6/Negative,
  and ADR-0028 §4/Negative — a fourth instance of the same pattern, now for a CLI-version/session-
  availability gap rather than a tooling- or CI-runner-environment gap (see `DURABLE NOTES` in the
  report for why this is worth reusing again).
- The script's existing "Known limit" header convention (workflow-vs-Agent-tool coder indistinguishable
  within one session) is extended with a second, analogous, explicitly disclosed limitation, keeping the
  file self-documenting in the same voice it already used before this ADR.
- Confirms (Context, "Gap flagged for issue #34") that `hook-verify-workflow.sh` remains exactly as
  stateless after this ADR as before it — a property some future issue could still choose to change, but
  this one deliberately does not.

## 5. References

- `SPEC.md` (repo root) / `docs/specs/33-hook-verify-workflow-filter-the-audit-wi.spec.md` — this
  issue's spec (confirmed byte-identical)
- `docs/architecture/ADR-0016-dynamic-workflows-step5.md` — original `hook-verify-workflow.sh` design
  and exit-code contract; amended by this ADR
- `docs/architecture/ADR-0004-pre-flight-pattern-enforce-hook.md` — the guard writing the audit log this
  script reads, and the `session_id` hook-payload field this ADR's fix is keyed on
- `docs/architecture/ADR-0024-28-vendor-deployed-only-skills-and-hooks.md`,
  `docs/architecture/ADR-0025-29-refresh-stale-staging-copies.md` — confirms `staging/` as this
  roadmap's working source of truth; deployed `~/.claude` stays out of scope by the same convention
- `docs/architecture/ADR-0028-32-manifest-helpers-guards.md` — immediately preceding issue (#32) in this
  roadmap and directory; structural and rigor precedent this ADR follows
- `docs/specs/34-scope-guards-autopilot-cwd-check-conduct.spec.md` — issue #34's spec; its assumption of
  a "global smoke-test record" is addressed (not implemented) in this ADR's Context
- `code.claude.com/docs/en/env-vars` — verified source for the `CLAUDE_CODE_SESSION_ID` environment
  variable (via context7 `/websites/code_claude`), corrected from SPEC.md's literal `CLAUDE_SESSION_ID`
- `code.claude.com/docs/en/whats-new/2026-w19` — changelog entry confirming `CLAUDE_CODE_SESSION_ID`'s
  introduction into the Bash tool subprocess environment
- `staging/plugin/scripts/hook-verify-workflow.sh`,
  `staging/plugin/scripts/tests/hook-verify-workflow.test.sh`,
  `staging/plugin/skills/concept-to-code/SKILL.md` — the files this ADR patches
- `staging/plugin/scripts/pre-flight-pattern-enforce.sh` — the guard whose audit-log writes and
  subagent-transcript-path derivation this ADR's session-sharing claim is verified against
- `staging/sync-to-claude.sh` — confirms the deployed path mapping for both patched files
- `.github/workflows/docs-ci.yml`, `.claude/test-cmd` — confirmed unchanged; both already cover
  `hook-verify-workflow.test.sh` by name/glob
- Implementation plan: `docs/superpowers/plans/2026-07-11-33-hook-verify-session-filter.md`
