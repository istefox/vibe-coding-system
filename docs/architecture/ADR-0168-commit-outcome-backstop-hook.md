# ADR-0168 — one classification, two callers: Step 7.1 keeps the verdict, a PostToolUse hook keeps a copy of the question

- **Topic slug:** `commit-outcome-backstop-hook`
- **Issue:** none — raised from a live incident (Adnota PR #36, 2026-08-23), drafted as
  `docs/proposal-c4-commit-outcome-hook.md`, formalised as `SPEC.md`.
- **SPEC:** `SPEC.md` (R-01 … R-08), archived at completion to `docs/specs/`
- **Plan:** `docs/superpowers/plans/2026-08-23-commit-outcome-backstop-hook.md`
- **Extends:** ADR-0135 §D3 (the Step 7.1 classification and its four-token contract), ADR-0058
  (`precompact-guard.sh` — the walk-up project-root resolution, the audit-log shape, the fail-open
  hook contract), ADR-0132 (logic out of a fence and into a script), ADR-0133 (the fence's
  `bash <<'FENCE_BASH'` wrapper), ADR-0025 (`settings.json` is never written by the sync script),
  ADR-0086 (a new harness, not an extension), ADR-0047 §A3 (a verdict is read off disk, never off a
  self-report).
- **Supersedes:** `docs/proposal-c4-commit-outcome-hook.md` (draft C4). Its three open questions are
  answered below, two as resolved and one as a residual risk with a named verification step.

## Status

Accepted — 2026-08-23.

**Numbering.** The highest ADR reachable from any branch is `ADR-0167`
(`git log --all --diff-filter=A` over `docs/architecture/ADR-016*`, run 2026-08-23). This ADR is
**0168**. It adds no twenty-first `CLAUDE.md` rule: everything here is an instance of rules 4, 5,
6, 12, 16 and 17.

## Context

`concept-to-code`'s Step 7.1 exists to answer one question after the `commit` skill returns: did the
manifest actually reach a committed, terminal state? It answers it by reading the manifest on disk,
never by asking `commit` what it did (ADR-0047 §A3), and it emits one of four tokens with a fixed
exit code:

```text
COMMIT_OK                                   exit 0
COMMIT_UNCOMMITTED untracked|modified       exit 1
COMMIT_NONTERMINAL current_step|status      exit 1
COMMIT_OUTCOME_NORUN <reason>               exit 3
```

That classification lives in exactly one place: an inline `bash <<'FENCE_BASH'` body inside the
`c2c-step7-commit-outcome` fence in `staging/plugin/skills/concept-to-code/SKILL.md`. The
orchestrator is *instructed* to run it. Nothing makes it.

This is rule 16 stated as a defect rather than as a caveat. Step 7.1 is an instruction, not an
enforcement, and the instruction is issued at the point in a chain run where the most instructions
have already been processed — after Step 7.0, 7.0b, 7.0c, a snapshot collapse, a baseline bump and a
`commit` invocation that opens its own HITL gate.

### The incident

Adnota repo, PR #36 (`344b7772`, 2026-08-23), correcting the merge of PR #35. The Step 7 snapshot
collapse staged the manifest *before* the SPEC-archive repoint and the `completed` transition ran,
and neither follow-up write was re-staged before the commit. The merged manifest read
`current_step: step_7_commit`, `status: in_progress`. The feature shipped correct; only the
bookkeeping was stale.

`COMMIT_NONTERMINAL current_step` is precisely the token Step 7.1 emits for that state. It was never
emitted, because Step 7.1 never ran.

### Why a stale manifest is not only a hygiene problem

When Step 7.1 does not report, the chain proceeds to the post-commit push, the `PROJECT.md` update
that marks the feature `[x]`, and the cost snapshot. `project-conductor` and `autopilot` read those
checkboxes to decide what to work on next. A false-positive `[x]` on work whose manifest never
reached a terminal committed state is how an unattended run skips real work believing it is done.

### Measurements, re-derived for this ADR rather than carried from the SPEC or the proposal (rule 13)

Measured 2026-08-23 on `feat/400-autopilot-disarm-scope-unbounded` at `9d08df1`.

```text
Step 7.1 classification, copies in the tree:        1   (the SKILL.md fence body)
callers of that classification today:               1   (the orchestrator, by instruction)
harnesses that EXECUTE the fence body:              1   (commit-transition-order.test.sh, CTO12,
                                                         five real git fixtures A-E)
harnesses that assert on the fence's PROSE:         1   (same file, CTO13)
skills that invoke the `commit` skill:              3   (concept-to-code, autopilot-build,
                                                         deep-refactor — all orchestrator-level)
agent definitions that invoke the `commit` skill:   0   (grep over staging/plugin/agents/*.md)
`Skill` tool_use payload shape, from live transcripts:
        {"name":"Skill","input":{"skill":"commit","args":"…"}}
manifest commit-stage states, from manifest-transition.sh's own graph:
        step_7_commit (Standard) · step_e4_commit (Express) · step_h5_commit (Hybrid) · completed
two-tier script resolution in SKILL.md:            10 sites, all
        CLAUDE_PLUGIN_ROOT → $HOME/.claude → a distinct did-not-run third branch
        (exit 3 in this fence's own sibling; exit 2 or an empty sentinel elsewhere)
`settings.json` PostToolUse entries today:          5   (3× Edit|Write, 1× Bash, 1× `.*`)
`sync-to-claude.sh` writes to settings.json:        0   (ADR-0025; six gated MANUAL STEP notices)
```

### Two things the SPEC gets wrong, found by measuring

Both are recorded here rather than fixed silently, because a SPEC criterion outranks a SPEC design
sketch and the operator has to see which one was chosen.

**1. The SPEC's manifest filter excludes the SPEC's own fixture.** `SPEC.md`'s Scope says the hook
"filters to `status: completed` or `current_step: completed`". R-04 requires the hook to catch a
manifest at `current_step: step_7_commit`, `status: in_progress`. That manifest satisfies neither
disjunct. As written, the filter drops R-04's fixture before the classification ever sees it, and
the feature would ship green against a population that cannot contain the defect it was built for.
Resolved in D5.

**2. "Nothing logged" makes the hook indistinguishable from an unwired hook.** `SPEC.md`'s Edge
cases say that when no manifest falls in the window the hook produces "no output, nothing logged".
The stated reason — zero transcript noise — is right. The conclusion is rule 4 pointed at itself: a
hook that leaves no trace on its common path cannot be told apart from a hook the matcher never
matched, and this repository has already shipped that exact failure once (ADR-0127's stale
`nightly-guard.sh`, wired, running, and inert, with no error anywhere). Resolved in D6.

## Decision

### D1 — the classification becomes `commit-outcome-check.sh`, beside its siblings, resolved two-tier (R-01)

`staging/plugin/skills/concept-to-code/scripts/commit-outcome-check.sh <manifest-path>`, deployed by
`sync-to-claude.sh` to `~/.claude/skills/concept-to-code/scripts/`, alongside the other twenty-three
`concept-to-code` helpers. Not under `plugin/scripts/` (that zone is hooks), and not duplicated into
the hook's own directory.

The body is the current fence body, moved verbatim: same `grep`/`sed` field reads, same
`git status --porcelain -- <basename>` check, same four tokens, same exit codes 0/1/3. The extraction
is behaviour-preserving by construction, and CTO12's five existing fixtures (A–E) are what prove it.

Both callers resolve it the same way every other `concept-to-code` helper is resolved in this
codebase — `CLAUDE_PLUGIN_ROOT` first, `$HOME/.claude` second, a distinct did-not-run branch third
(ten existing sites, measured above; this fence's own third branch is `NORUN` exit 3).

### D2 — Step 7.1 keeps its marker, its placeholder and its branch table; only the body changes (R-02)

The `<!-- fence-contract: c2c-step7-commit-outcome -->` marker stays, the `bash <<'FENCE_BASH'`
wrapper with its column-0 terminator stays (ADR-0133), the single `<manifest-path>` placeholder stays,
and the four-branch prose table below the fence stays word for word — including the sentence naming
`COMMIT_UNCOMMITTED`, "no rollback", "no transition" and "absorbing", which CTO13 asserts as a
compound needle.

Everything that is preserved here is preserved because something already pins it. That is the point:
the extraction is invisible to every existing assertion except one, and that one is named in D10.

### D3 — no fallback copy: an unresolved script is `COMMIT_OUTCOME_NORUN noScript`, exit 3 (R-01, R-02)

If neither tier resolves the script, the fence prints `COMMIT_OUTCOME_NORUN noScript` and exits 3.
It does not fall back to an inline copy of the classification.

A fallback would recreate the exact thing this ADR exists to remove — two definitions of "what does
this manifest's outcome classify as", diverging silently, with the fallback path exercised by nobody
because it only runs on the machine where the deploy failed. Rule 4 says an unrun check must report a
state distinct from a clean result; exit 3 is that state, and Step 7.1's existing third branch
already routes it to "report did not run", so no new prose is needed.

### D4 — the script is a CHECKER, the hook is a REPORTER, and the call sites say so (R-03, R-06, rule 5)

`commit-outcome-check.sh` is branched on by exit code: 0 / 1 / 3. `commit-outcome-backstop.sh`
always exits 0 and signals on its output stream. The two idioms are opposite and this ADR names
which is which, because the hook consumes the checker and a caller that treats a reporter's exit
code as a verdict (or a checker's stdout as advisory) is the defect rule 5 was written for.

The hook never blocks. A `PostToolUse` hook can inject text but cannot replay Step 7.1's stop
semantics — the ADR-0078 absorbing-state reasoning, the explicit "no rollback is attempted", the
named remediation. That messaging stays exclusively in `SKILL.md`, and the hook's output says so by
pointing at Step 7.1 rather than restating it.

### D5 — the population is the mtime window AND a commit-stage-or-terminal `current_step` (R-04, R-05)

```text
in scope  ⇔  mtime within 24h
             AND ( current_step ∈ {completed, step_7_commit, step_e4_commit, step_h5_commit}
                   OR status == completed )
```

The SPEC's two disjuncts are both kept. Three states are added: the commit-stage state of each chain
path, taken from `manifest-transition.sh`'s own graph rather than from a list written by hand.

This is the minimum widening that makes R-04 satisfiable (see Context). It is also the *correct*
population on its own terms: the question the backstop asks is "did the manifest that a commit was
just supposed to terminalise actually get there", and a manifest sitting at its path's commit step is
exactly a manifest for which the answer can be no. A manifest at `step_3_project_memory` is not in
the population and never triggers — which is what keeps an in-flight chain in another window from
generating a report on every unrelated commit.

The 24-hour window is `find <dir> -name '*.manifest.yml' -mtime -1`. BSD and GNU `find` agree on
`-mtime -1`; `-newermt` is GNU-only and `stat` has incompatible flags on the two platforms, so this
is the one portable spelling. The glob excludes the `.manifest.yml.bak` files that already exist in
`docs/manifests/`.

### D6 — one audit line per matched invocation, `CLEAN` included; stdout stays silent (R-04, R-06)

Every invocation that gets past the `commit` filter appends exactly one line per examined manifest to
`~/.claude/state/commit-outcome-backstop/audit.log`, and appends one `CLEAN` line when the window
holds no in-scope manifest at all:

```text
<ISO-8601-Z>\t<session_id>\t<manifest-path>\t<classification>\t<reason>
2026-08-23T19:41:07Z	abc123	-	CLEAN	no in-scope manifest in the 24h window under /Users/…
```

**Stdout remains empty on the clean path.** The SPEC's "zero transcript noise" requirement is
honoured exactly; what changes is the Edge-case clause "nothing logged", which is overridden for the
reason in Context: an audit log is not the transcript, and a hook whose only evidence of life is a
report it almost never produces cannot be distinguished from a hook that never fires. This is rule 5's
`CLEAN` convention applied to a reporter whose channel is a file.

R-04 is unaffected — it asks for "one matching entry", and a `COMMIT_NONTERMINAL` line is still
exactly one line.

### D7 — matcher `Skill` as specified; the hook re-checks `tool_name` and pre-filters before `jq` (R-03, R-06)

Registered exactly as the SPEC requires:

```json
{ "matcher": "Skill",
  "hooks": [ { "type": "command", "command": "\"$HOME\"/.claude/hooks/commit-outcome-backstop.sh" } ] }
```

The hook nonetheless verifies `tool_name == "Skill"` itself, so that widening the matcher to `.*`
later (see A5) is a one-line settings change and not a correctness change.

Order of operations inside the hook, and the reason for it:

1. Read stdin. Empty → exit 0, silent.
2. `grep -q '"skill"[[:space:]]*:[[:space:]]*"commit"'` on the raw payload → no match, exit 0,
   silent, **no `jq`, no log, no scan**. This is R-03's no-op path and it costs one `grep` on every
   skill call in the session.
3. Only past that point: require `jq`, read `tool_name`, `tool_input.skill`, `cwd`, `session_id`, and
   re-decide precisely. `jq` absent here → log `jq missing`, exit 0.

The grep in step 2 is a pre-filter, never the authority — it can over-match (a `commit` invocation
whose `args` string quotes the same literal), and over-matching costs a scan that reports nothing.
It cannot under-match a real invocation, which is the direction that would matter. Putting the
`jq`-absent log *after* the pre-filter is what stops a machine without `jq` from writing an audit
line on every skill call in every session.

### D8 — `~/.claude/settings.json` is machine-local and is not vendored; the sync script prints a gated notice (R-03)

`sync-to-claude.sh` has never written `settings.json` and does not start now (ADR-0025: machine-local
keys need a `jq del()` pass, not a straight copy; `staging/user/settings.json` is deliberately absent
from `PAIRS`). Registration reaches a machine through three artefacts and one human:

1. a new gated MANUAL STEP block in `sync-to-claude.sh`, keyed on
   `grep -q 'commit-outcome-backstop' "$DEST/settings.json"`, in the same shape as the six that
   already exist;
2. the staged reference copy `staging/user/settings.json`, updated so the block it documents is real;
3. `sync-manual-steps.test.sh`'s `build_home` "yes" fixture extended to represent the new hook as
   wired — that file's own header states that omitting this rots its all-clear assertion, and it has
   rotted twice before for exactly this reason;
4. the operator, editing `~/.claude/settings.json` by hand at a HITL gate.

### D9 — state dir at `~/.claude/state/commit-outcome-backstop/`, overridable by env (R-04, R-06)

`${COMMIT_OUTCOME_BACKSTOP_DIR:-$HOME/.claude/state/commit-outcome-backstop}`, mirroring
`precompact-guard.sh`'s `PRECOMPACT_GUARD_DIR`. The override is what makes the harness hermetic; the
default is what makes the nine sibling hooks' state layout uniform.

Fail-open covers every path: unwritable directory, unwritable log, unreadable manifest, absent
`docs/manifests/`, absent `jq`, unresolved `commit-outcome-check.sh`. The hook exits 0 in all of
them. Where it can still say something it does — an unresolved checker is reported once per
invocation as its own condition (`NORUN noScript`), never as "found nothing" (rule 4).

### D10 — a new harness, plus a mandated repair of the one call-site the extraction breaks

New file `staging/plugin/scripts/tests/commit-outcome-backstop.test.sh`, assertion prefix `CO`
(verified free across `staging/` on 2026-08-23). Its question — "does the backstop find, classify,
report and log" — is not `commit-transition-order.test.sh`'s question ("is the terminal transition
ordered before the commit"). ADR-0086's criterion says two copies answering different questions stay
separate.

The repair is not optional and is not a matter of taste. `commit-transition-order.test.sh`'s `CTO12`
extracts the Step 7.1 fence body and *executes* it against five real git fixtures. After D2 that body
resolves a script through `CLAUDE_PLUGIN_ROOT` → `$HOME/.claude`, and `CTO12` exports neither. On a
machine where the script is not yet deployed, all five fixtures return `COMMIT_OUTCOME_NORUN noScript`
and `CTO12` goes red for a reason that has nothing to do with the contract it guards; on a machine
where it *is* deployed, `CTO12` silently starts testing the deployed copy instead of `staging/`,
breaking the "no `$HOME` dependency" claim in its own header. `run_outcome_fence()` must export
`CLAUDE_PLUGIN_ROOT="$STAGING/plugin"`, exactly as `spec-coverage-baseline-bump.test.sh`'s `NB16`
already does for the sibling Step 7.0b fence. No assertion is deleted, so rule 19's tombstone
requirement does not apply.

### D11 — the proposal is marked superseded, not deleted (R-08)

`docs/proposal-c4-commit-outcome-hook.md` gets a header line pointing at this ADR. It is not removed
here: deleting a file is a HITL decision, and the file is untracked, so the deletion cannot even be
recorded as a diff. The operator may delete it at Gate 7 once the ADR is committed.

## Alternatives considered

**A1 — a blocking `PreToolUse` gate instead of a report-only `PostToolUse` backstop.**
Rejected on two independent grounds. Ordering: the condition this feature detects can only exist
*after* `commit` has run, so a pre-hook would be classifying the previous invocation's outcome, one
tool call late, which is worse than a post-hook, not better. Semantics: a block would duplicate a
halt that Step 7.1 already owns, and duplicate it *badly* — a hook denial cannot carry the ADR-0078
absorbing-state reasoning or the "no rollback is attempted" instruction, so the operator would get a
refusal without the one paragraph that tells them what to do about it. Two halting mechanisms with
different messages for the same condition is the divergence this ADR is otherwise built to prevent.

**A2 — a project-local hook, registered in each consuming project's `.claude/settings.json`.**
Rejected. The defect is in `concept-to-code`, which is global; a project-local hook would have to be
installed into every project that ever runs the chain, and the projects most exposed are the ones
nobody remembers to configure. Every other hook in this repository is vendored to `~/.claude/hooks/`
and this one has no property that argues for an exception. The hook is inert outside a project with
`docs/manifests/`, so global registration costs nothing where it does not apply.

**A3 — keep the classification inline and have the hook carry its own copy.**
Rejected, and it is the alternative worth naming most explicitly because it is the smallest diff.
Two copies of the same decision, in two files, called by two different callers, is the shape rule 6
forbids: copies answering *one* question must be extracted. The failure mode is not hypothetical —
the divergence would appear the first time someone tightens the classification in `SKILL.md` (where
it is visible) and not in the hook (where it is not), and the hook would then keep reporting `OK` on
a state the chain has started treating as a defect.

**A4 — no extraction at all: have the hook shell out to the `SKILL.md` fence.**
Rejected. It makes a markdown file an executable dependency of a hook, requires the hook to
reimplement `fence-contract` extraction (an `awk` program that already exists in three harnesses and
would become a fourth copy), and couples the hook's correctness to the *formatting* of a document.
The extraction in D1 costs one file and removes all three problems.

**A5 — register with `"matcher": ".*"` and filter on `tool_name` inside the hook.**
Rejected as the shipped default, but kept as the named fallback for R2 below. Live hook documentation
lists the matcher's vocabulary as built-in tool names plus `mcp__<server>__<tool>`, and does not
document a `Skill` tool at all; a `.*` matcher demonstrably fires (the `agentwake` heartbeat entry
already uses one on every tool call) and would remove the uncertainty entirely. It was not chosen
because R-03 specifies `"matcher": "Skill"` in as many words, and because `.*` runs the hook on
*every* tool call rather than every skill call — a much larger multiplier for a pre-filter that has
to be cheap. If the verification step in the plan shows the `Skill` matcher does not fire, the
remedy is this alternative, one line in `settings.json`, with the hook already written to accept it
(D7).

**A6 — scope the scan by session rather than by mtime: only manifests written during this session.**
Rejected. It needs per-session state written by something other than this hook (the hook sees a
`session_id`, not a list of what that session touched), which means a second state file whose
staleness becomes its own problem. The 24-hour mtime window needs no state at all, and D5's
commit-stage filter — not the window — is what actually excludes the abandoned-manifest false
positives the proposal worried about. The window is a cheap outer bound, not the discriminator.

**A7 — extend `commit-transition-order.test.sh` rather than add a harness.**
Rejected under ADR-0086. That file's population is the ordering relation between manifest writes and
`commit` invocations *inside `SKILL.md`*; this feature's population is a hook's behaviour against
fixture trees. Merging them would put two questions behind one `Z`-floor and make either one's
vacuity invisible to the other. The one thing that *does* belong in that file — `CTO12`'s repair —
stays in it, because it is that file's own assertion.

## Consequences

### Positive

- The Step 7.1 classification acquires a second caller that cannot forget to call it. The instruction
  remains an instruction (rule 16 is not repealed here), but the *shape* of its failure changes: a
  skipped Step 7.1 now leaves an audit-log line and, on a real defect, a transcript report.
- There is exactly one definition of the four-token contract, in a file with a shebang, that can be
  run by hand against any manifest — which is also the first time this classification is invocable
  outside a chain run.
- The Adnota incident becomes a fixture. `CO`-prefixed assertions reconstruct `current_step:
  step_7_commit` / `status: in_progress` inside a real `git init` tree and require
  `COMMIT_NONTERMINAL current_step` plus a matching audit line, so the specific state that shipped
  is now the specific state that is pinned.
- `commit-outcome-check.sh` is reusable by `autopilot-build` and `deep-refactor`, the two other
  orchestrator-level skills that invoke `commit`. Neither is changed here, and neither has to be for
  the backstop to cover them: the hook fires on the tool call, not on the caller.
- The audit log gives a human (or a later automated check) a per-invocation record of a step that
  previously left no trace at all, in the same tab-separated shape as `precompact-guard.sh`'s.

### Negative

- **The `Skill` matcher is not documented, so the hook may be registered and inert.** This is the one
  genuinely open risk and it is the same failure ADR-0127 recorded for `nightly-guard.sh`: wired,
  running, finding nothing, erroring never. Mitigated by D6 (a `CLEAN` line per invocation makes
  "fired and found nothing" distinguishable from "never fired") and by an explicit post-deploy
  verification step in the plan. Not eliminated.
- The hook runs on every `Skill` tool call in every session on the machine. The common path is one
  `grep` against a small JSON payload and an exit — but it is a cost paid globally for a check that
  matters on one skill.
- One more file must be edited by hand on every machine (`~/.claude/settings.json`), and the gap
  between "vendored" and "wired" is where six previous hooks have sat unwired for days. The gated
  MANUAL STEP notice is the mitigation and it is the same mitigation that has already failed to be
  noticed twice.
- The hook's project root comes from the session's `cwd`. Measured from live transcripts: an
  orchestrator sometimes invokes `commit` against a *different* worktree than its own `cwd` (observed
  2026-08-23, a commit into `/Users/stefer/Developer/vcs-gate-audit-check` from a session rooted in
  this repo). In that case the backstop scans the session root's manifests, not the tree that was
  committed. The failure direction is a **missed report**, never a false alarm, and Step 7.1 —
  which is handed the manifest path explicitly — is unaffected.
- `commit-transition-order.test.sh` acquires a dependency on `CLAUDE_PLUGIN_ROOT` that it did not
  have. Its "no `$HOME` dependency" claim survives only because the export makes the first tier hit;
  if a future edit drops that export, the file silently starts testing a deployed copy.

### Neutral

- The four-token contract does not change. This is stated as a decision (`SPEC.md` Out of scope) and
  is worth restating as a consequence: nothing downstream of Step 7.1 sees a different string or a
  different exit code than it saw before.
- `commit`'s own Step 4 HITL gate is untouched. The backstop runs strictly after `commit` returns.
- Flags passed to `commit` (`--include`, `--branch`, `--autopilot`, `--no-pr`) are irrelevant to the
  hook; it classifies whatever manifests the population rule selects.
- No new runtime dependency. `jq` is already required by `precompact-guard.sh` and several other
  hooks, and the hook's no-op path does not use it at all.
- Two of the proposal's three open questions close as non-issues rather than as work:
  **R1 (cwd inside a subagent)** — measured, zero agent definitions invoke the `commit` skill; the
  three invokers are all orchestrator-level skills, so a subagent-invoked `commit` does not occur and
  is not a case to handle. The distinct worktree case above is real and is recorded as a negative
  consequence, not as an open question.
  **R3 (matcher-level skill filtering)** — confirmed against live hook documentation: the matcher
  filters on tool name only, and the per-handler `if` field takes permission-rule syntax over tool
  arguments, with no documented spelling for a skill name. The internal `tool_input.skill` check is
  the mechanism, not a gap to close later.

## References

- `SPEC.md` (R-01 … R-08) — archived at completion to `docs/specs/`.
- `docs/superpowers/plans/2026-08-23-commit-outcome-backstop-hook.md` — the implementation plan.
- `docs/proposal-c4-commit-outcome-hook.md` — the superseded draft.
- ADR-0135 §D3 — the Step 7.1 classification, its four tokens and the `c2c-step7-commit-outcome`
  fence contract.
- ADR-0058 — `precompact-guard.sh`: the walk-up project-root resolution, the audit-log shape, the
  one-shot/fail-open split this hook borrows the fail-open half of.
- ADR-0078 — `completed` is absorbing; why Step 7.1 stops without rolling back.
- ADR-0047 §A3 — a verdict is read off disk, never off an agent's self-report; §rule 5, the
  checker/reporter split.
- ADR-0086 — extract only when two copies giving different answers would be a defect; why a new
  harness.
- ADR-0025 — `sync-to-claude.sh` never writes `settings.json`.
- ADR-0127 §D2.1 — the wired-but-inert hook, the precedent behind D6's `CLEAN` line.
- ADR-0132, ADR-0133 — logic out of a fence into a script; the `bash <<'FENCE_BASH'` wrapper and its
  column-0 terminator.
- ADR-0154 — the plan/harness back-reference required for this feature's ids to be in scope.
- Adnota repo PR #36 (`344b7772`, 2026-08-23) — the incident.
