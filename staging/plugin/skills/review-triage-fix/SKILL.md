---
name: review-triage-fix
description: Use this skill when you want a FULL review+fix cycle — not just findings, but also automated routing to fixing agents (debugger/refactorer/coder), verification, and a decision-grade recap before committing. One invocation = one bounded cycle: review→triage→fix→re-review→recap→STOP. Manual invocation only, from the orchestrator session. Triggers include "review-triage-fix", "review and fix", "full review cycle", "triage findings and fix", "fix cycle with review", "run review fix cycle". Do NOT use for quick findings-only requests ("review", "code review", "show me the problems") — those go to the built-in code-review skill. Supersedes built-in code-review when fixing is needed.
---

# review-triage-fix

One invocation = **exactly one cycle**:
`pre-flight → reviewer → triage → route-fix (sequential) → re-review → recap → STOP`.
You recommend; the user decides whether to re-invoke or commit. **NO COMMIT,
no push, no automatic iteration beyond the cycle** inside this skill.

## Hard constraints (read first)

- **Skill isolation — no superpowers check during the cycle.** Do not invoke
  `writing-plans`, `brainstorming`, `EnterPlanMode`, or any other
  `superpowers/*` skill between steps. This skill is a self-contained workflow:
  the cycle `pre-flight → reviewer → triage → fix → re-review → recap` replaces
  every intermediate skill-check. Explicit override of the `using-superpowers` rule.
- **Sub-agents do not spawn sub-agents** (nesting supported since CC 2.1.172; kept flat by
  design — see blueprint §2.2). This skill orchestrates multiple dispatches: run it **only
  in the orchestrator session**. If invoked from inside a sub-agent, stop and say so —
  you would not be able to dispatch.
- **Dispatch always sequential.** Never fix in parallel: same codebase →
  edit conflicts.
- **STOP at end of cycle.** One invocation, one cycle, then recap and stop. No
  commit/PR (those remain separate HITL steps).
- The three helpers are in
  `$HOME/.claude/skills/review-triage-fix/scripts/` and are invoked via Bash.
  They are reporters: read the **first stdout token**, not the exit code.
- **Required external dependency:** `jq` must be in PATH. The `triage-state commit` subcommand exits 1 if `jq` is absent; `triage-state diff` degrades gracefully. Verify with `command -v jq`.

## Step 0 — Pre-flight

1. Confirm you are the orchestrator session (not a sub-agent). If unsure, stop.
2. Resolve the project root (the dir whose `.claude/` you'll use). Run the
   **baseline** once and record it:
   `bash $HOME/.claude/skills/review-triage-fix/scripts/verify.sh <root>`
   - `PASS` → baseline **GREEN**.
   - `FAIL …` → baseline **RED** (CIRCUIT BREAKER A disabled this cycle —
     regression detection unavailable; say so in the recap).
   - `UNVERIFIED …` → **CIRCUIT BREAKER D** active for the whole cycle.
3. **Resolve the per-branch state file path** (`RTF_SF`). The state is
   per-branch to prevent cross-branch contamination (false "resolved"/"oscillates"
   when a previous cycle was on a different branch). Compute once and reuse in
   all subsequent steps:
   ```sh
   _branch=$(git -C "<root>" rev-parse --abbrev-ref HEAD 2>/dev/null)
   # fallback for non-git repos or detached HEAD
   case "$_branch" in
     "") _branch="_no-git" ;;
     HEAD) _branch="_detached" ;;
   esac
   # sanitize: replace any char not in [a-zA-Z0-9._-] with _
   _branch=$(printf '%s' "$_branch" | sed 's/[^a-zA-Z0-9._-]/_/g')
   RTF_SF="<root>/.claude/.triage-fix-last-${_branch}.json"
   ```
   Use `$RTF_SF` (written as `<rtf-state-file>` in the templates below) in
   every `triage-state.sh` call for this cycle.
4. State the cycle number and previous finding count using only `jq` — no Python, no ad-hoc parsing:
   ```sh
   if [ -f "$RTF_SF" ]; then
     prev=$(jq 'length' "$RTF_SF" 2>/dev/null || echo "?")
     echo "State file EXISTS (cycle N+1, $prev previous findings)"
   else
     echo "State file absent (cycle 1)"
   fi
   ```
   `jq 'length'` works on the state array regardless of content. Do not call `.get()` or any dict-specific method on this file.
5. **Fix-dispatch model variant (cost pilot, see `~/.claude/plans/bubbly-imagining-teapot.md` — not yet a committed decision, ADR to follow only if a variant wins clearly).** Declare which variant this cycle uses, default `opus` (today's behavior, unchanged unless the user names a different variant for this invocation):
   - `opus` — default. Every fix dispatch (`coder`/`refactorer`/`debugger`) runs at `model: "opus"` for the whole call, as in Step 3's Model override.
   - `sonnet-xhigh` — zero-mechanism alternative. Every fix dispatch runs at `model: "sonnet"` instead of opus. No advisor call. **The name is now historical: there is no `effort` pin, because the Agent tool has no such parameter (ADR-0068 §D7, issue #180) and RTF dispatches fixes exclusively through it.** The variant reduces to a model swap with no reasoning-tier lever — see Step 3's Model override for the same disclosure. Kept under its original name so the pilot's existing `rtf-sonnet-xhigh-*` cost-log rows stay comparable; rename it only together with those.
   - `advisor` — two-call pattern per routable finding (see Step 3 for the mechanics).
   Non-blocking — never fail the cycle if the script is unavailable. Use the **same** label for both calls, built from data already resolved in this step (`RTF_LABEL="rtf-<variant>-${_branch}"`, reusing `$_branch` from item 3), since `usage-snapshot.py --diff <label>` both locates the snapshot AND becomes the logged chain name — a mismatched pair silently breaks the lookup, and there is no separate "log label" flag. Before the cycle: `python3 ~/.claude/scripts/usage-snapshot.py --save "$RTF_LABEL" >/dev/null 2>&1 || true`. After Step 5 (see the reminder there): `python3 ~/.claude/scripts/usage-snapshot.py --diff "$RTF_LABEL" --log-to ~/.claude/chain-eval.md >/dev/null 2>&1 || true`.

## Step 1 — Review

**Native memory (VCS-055 Phase 2.3 / VCS-056, ADR-0182 / ADR-0183):** reviewer and debugger both
carry `memory: project` and manage their own persistent notes — no inject/harvest step for either.
This retires the ADR-0012 mediated mechanism entirely; `coder` and `refactorer` were never subject
to it.

<!-- dispatch-site: rtf-step1-reviewer class=inline exempt: reviewer produces no completion fact — its Edit/Write (via memory: project) is confined to its own memory directory by reviewer-write-scope.sh, and an empty report yields an empty triage rather than a green -->
**If `manifest.use_codex_review = true` (Gate CDX):** run
`~/.claude/scripts/codex-reviewer.sh --mode review --diff-scope uncommitted --out <tmp-review-file>`.
- exit `0` → read `<tmp-review-file>` exactly as the reviewer agent's own report; continue below
  unchanged.
- exit `3` (DID-NOT-RUN) → **stop and ask, never silently fall back to Claude:**
  `AskUserQuestion`: "Codex review unavailable at RTF Step 1: `<reason from stderr>`. Fallback to
  Claude's reviewer agent for this dispatch, or halt the chain?" Options: "Fallback to Claude
  reviewer (Recommended)" → dispatch `reviewer` exactly as below, then continue / "Halt the chain"
  → abort per this skill's existing abort convention.

**Otherwise (default — `use_codex_review` absent or `false`):** Dispatch the `reviewer` agent over
the recent changes. Edge cases:
- Reviewer reports **no detectable changes** → stop, emit a "nothing to do"
  recap, do not invent work.
- **Huge diff sampled** → propagate that caveat verbatim into the recap.

## Step 2 — Triage (classify every finding per the table)

Read the reviewer's severity-grouped report. For each finding extract
`sev` (BLOCKER/MAJOR/MINOR/NIT), `loc` (`path:line`), a one-line `problem`,
and the suggested fix. Classify:

| Finding class | Route to | Note |
|---|---|---|
| Failure: runtime error, red test, reproducible wrong behavior | `debugger` | root-cause + minimal fix + regression + verify (its contract) |
| Structural: duplication, oversized unit, tangled responsibility | `refactorer` | requires a GREEN baseline (Step 0); if baseline red → REPORT-ONLY |
| Localized non-failure non-structural code change: missing validation, edge-case test, naming, small hardening | `coder` | synthesize a **micro-piano** = the finding + suggested-fix as a 1-item plan so the coder's plan-driven contract is satisfied |
| Architectural / design-level / ambiguous | **REPORT-ONLY** | flag for the user, no fix |
| Swift concurrency: async/actor isolation changes, DispatchQueue removal, Sendable conformance additions | **REPORT-ONLY** | static analysis cannot prove thread-safety; green tests do not either (ADR-0018). No rationalization overrides this. |
| Security finding of any class — injection, path traversal, auth bypass, hardcoded secrets, insecure deserialization, filesystem access with user-controlled input, and any other input-handling vulnerability | **REPORT-ONLY** | CIRCUIT BREAKER C. The class is non-exhaustive: when in doubt, treat as security. Never downgrade to `coder` based on locality or perceived severity. |
| Reviewer-declared low confidence | **REPORT-ONLY** | acting on uncertain findings is risky |

NITs are routed (coherent with auto-route-all) but treated as a single
low-risk batch and shown **separately** in the recap sub-table.

**Micro-piano discipline (for `coder` dispatches): strictly 2-3 lines** —
finding + suggested-fix + (optional) file:line. NOT a multi-paragraph spec.
The coder must do exactly that change and stop, not expand scope. Bound the
context aggressively: a bloated micro-piano = a bloated dispatch (40k+ tokens
for a small change is a smell, observed in the v1 pilot).

**Add+Remove rule (for SUBSTITUTION fixes):** when the fix replaces a pattern
rather than just adding (e.g. move local import to top-level, extract magic
number to a named constant, consolidate duplicate fixtures, rename a helper),
the micro-piano MUST list BOTH the new pattern (`Add: ...`) AND the old
instances to delete (`Remove: <path:line> ...`). Without an explicit Remove,
the coder typically acts conservatively and leaves the old pattern in place →
duplication that the re-review then flags as a new finding (observed cycle 2
2026-05-20, M-3 autouse fixture → M-1 re-review). For purely ADDITIVE fixes
(missing input validation, new edge-case test, docstring fix), `Add:` alone
suffices — no Remove section needed.

**Toolchain completeness rule (for fixes that add a dev tool):** if the fix adds a
linter, formatter, or type-checker to dev dependencies (e.g. `mypy`, `ruff`, `pylint`),
the dispatch brief MUST include: *"After adding the tool to dev deps, run it against the
full codebase and fix every error it surfaces before declaring done."* Without this, the
coder adds the dep but never runs the tool, leaving tool-specific findings (missing stubs,
missing `py.typed`, config errors) unresolved in the re-review baseline.

Then compute cross-cycle status. Write the current findings as TSV
(`sev<TAB>loc<TAB>problem`, one per line) and run:
`… | bash $HOME/.claude/skills/review-triage-fix/scripts/triage-state.sh diff <rtf-state-file>`
(`<rtf-state-file>` = `$RTF_SF` resolved in Step 0 — per-branch, never shared
across branches). Keep its `id/state` rows, `COUNTS`, and `CONVERGENCE` line
for the recap.

## Step 3 — Route-fix (sequential, severity order)

**Before the loop — snapshot pattern (universal, git AND non-git):** the
per-fix attribution that breakers A and B need requires a pre-fix baseline.
`git diff` alone shows cumulative uncommitted changes from ALL prior fixes,
which mis-attributes weakening to innocent later fixes. So: snapshot the test
tree before the loop AND refresh it after each fix.

```
cp -R <test dirs> "$TMPDIR/rtf-snap"     # before the loop, once
# … per-fix dispatch …
diff -ru "$TMPDIR/rtf-snap" <live test files> | weakening-scan.sh
rm -rf "$TMPDIR/rtf-snap" && cp -R <test dirs> "$TMPDIR/rtf-snap"   # refresh
```

**Coder dispatch cap: max 4 non-NIT items per cycle.** Count items routed to `coder` before entering the loop. If the count exceeds 4, fix the top 4 by severity (BLOCKER first, then MAJOR, then MINOR), mark the remainder `DEFERRED[cap: overflow N>4]` in the recap table, and stop — do not attempt them this cycle. The next RTF invocation picks them up from the re-review baseline. This cap does not apply to the NIT batch (which is always a single dispatch regardless of count).

**Stale-worktree pre-check (before EACH coder dispatch).** The coder agent runs with `isolation: worktree`, which forks from the last commit and does not see uncommitted changes already applied this cycle. Before each dispatch run:
```sh
git -C <root> diff HEAD --name-only 2>/dev/null
```
If this returns any files: **do not dispatch the coder agent**. Apply the fix directly as orchestrator (Read → Edit/Write). Record the substitution in the recap `Routing` column as `coder (inline — stale worktree)`. This is not a fallback — it is the correct path when uncommitted changes are present. Only dispatch the coder agent when the output is empty (working tree is clean).

For each **routable** finding (skip REPORT-ONLY and DEFERRED), in order
<!-- dispatch-site: rtf-fix-agents class=inline exempt: each fix dispatch is followed by a git-diff no-op detection that reads the filesystem, so an unfinished agent reads as no-op rather than as fixed -->
BLOCKER → MAJOR → MINOR → NIT, dispatch the chosen agent with a curated input:
the finding, `loc`, the reviewer's suggested fix, (for `coder`) the micro-piano,
and the project's test-cmd so the agent self-verifies.
**Model override — branches on the variant declared in Step 0, item 5:**

- **`opus` (default):** use `model: "opus"` for all fix dispatches (`coder`, `refactorer`, `debugger`). Fix agents make judgment calls without a structured plan — Opus reduces the risk of introducing new issues (e.g. using unavailable APIs, wrong deployment target assumptions).
- **`sonnet-xhigh`:** use `model: "sonnet"` for all fix dispatches instead of `opus`. Do NOT pin `effort` — RTF dispatches fixes exclusively through the Agent tool (no Workflow `agent()` call exists anywhere in this file), and the Agent tool has no `effort` parameter at all (ADR-0068 §D7, issue #180). This means the variant has no lever for a higher reasoning tier and reduces to a plain model swap — the "higher reasoning tier at lower cost than opus" intent the name `sonnet-xhigh` was chosen for does not survive on the Agent tool as currently spec'd. No mechanism currently exists to pin per-dispatch reasoning effort on this tool; that gap is disclosed here, not solved. No other change to this step.
- **`advisor`:** for each routable finding, two `Agent`-tool calls instead of one:
  <!-- dispatch-site: rtf-advisor-pair class=inline exempt: the advisor is a reviewer with no Write tool and its own failure clause already falls back to plain opus behaviour for that one finding -->
  1. **Advisor call.** **If `manifest.use_codex_review = true` (Gate CDX):** run
     `~/.claude/scripts/codex-reviewer.sh --mode diagnose --finding "<finding + loc + suggested fix>" --out <tmp-diag-file>`.
     - exit `0` → read `<tmp-diag-file>` as the diagnosis; proceed to the Executor call below.
     - exit `3` (DID-NOT-RUN) → **stop and ask, never silently fall back to Claude:**
       `AskUserQuestion`: "Codex advisor unavailable: `<reason from stderr>`. Fallback to Claude's
       reviewer agent for this advisor call, or halt the chain?" Options: "Fallback to Claude
       reviewer (Recommended)" → run the Claude advisor call below, then continue / "Halt the
       chain" → abort per this skill's existing abort convention. This gate covers Codex being
       *unavailable*; it does not replace the existing "advisor call errors/times out/returns
       empty" clause below, which stays as-is for the Claude call.

     **Otherwise (default):** dispatch `subagent_type: "reviewer"` (read-only by design — it reports, never edits code; its `memory: project` grant is confined to its own memory directory by `reviewer-write-scope.sh`, so it structurally cannot touch source even if asked to) at `model: "opus"`. Brief: the finding, `loc`, the reviewer's suggested fix, and the instruction *"Diagnose only, do not propose an edit as a diff — return root cause, fix approach, and exactly which files/functions to touch. Keep the answer under 150 words."* This call is the entire advisor cost — bounded by the word cap, not a full plan. No agent-memory contract applies here (reviewer uses native memory per ADR-0182; there is nothing to inject or harvest).
  2. **Executor call** — dispatch the normal fix agent (`coder`/`refactorer`/`debugger`) at `model: "sonnet"` (no effort override), with the advisor's diagnosis prepended to the existing dispatch brief under a `FIX GUIDANCE (already diagnosed — apply, do not re-diagnose):` header. Everything else about the dispatch (micro-piano, test-cmd, isolation, circuit breakers) is unchanged.
  If the advisor call errors, times out, or returns empty: skip it and fall back to `opus` behavior for that one finding only — never block the cycle on an advisor failure.
  NIT batching stays a single dispatch either way; run the advisor call once for the whole batch (one diagnosis covering the list), not once per NIT.

**NIT batching is mandatory.** All routable NITs go to `coder` as a **SINGLE
dispatch with a list** (one line per NIT: sev, loc, problem, suggested-fix) —
not N separate dispatches. The micro-piano for the batch IS the list, with
"apply all of these, each as the smallest possible change" as the instruction.
Verify + weakening-scan once after the batch, not after each NIT inside it.
This alone removed the dominant cost in the v1 pilot (multiple NIT/MINOR
dispatches at 1-2 min each).

After **each** fix dispatch (or after the NIT batch):

**No-op detection (before verify.sh).** Check whether the dispatch actually modified anything:
```sh
git -C <root> diff HEAD --name-only 2>/dev/null
```
If this returns empty: the agent made no changes. Record `coder [NO-OP]` (or `debugger [NO-OP]` etc.) in the recap `Routing` column, mark the finding `UNRESOLVED — agent no-op` in Status, **skip** `verify.sh` and `weakening-scan.sh` for this iteration (suite is unchanged), and continue to the next finding without breaking the loop. A no-op does NOT fire breaker A (no regression introduced), but the finding remains open and will resurface in Step 4's re-review.

Then re-run verification yourself (do not trust the agent's self-report for the breakers):

- `bash $HOME/.claude/skills/review-triage-fix/scripts/verify.sh <root>`
- `diff -ru "$TMPDIR/rtf-snap" <live test files>` piped into
  `bash $HOME/.claude/skills/review-triage-fix/scripts/weakening-scan.sh`
- then refresh the snapshot for the next iteration.

Apply the circuit breakers:

- **CIRCUIT BREAKER A — abort on regression.** Only if baseline was GREEN. If
  `verify.sh` flips PASS→FAIL and stays FAIL after the responsible agent ran:
  **stop fixing**, do not pile on, record the culprit finding, jump to Step 4
  with flag `ABORT: regression at <finding>`. If baseline was RED: detection
  off; recap notes "baseline RED — regression detection unavailable".
- **CIRCUIT BREAKER B — hard-fail anti-test-weakening.** If `weakening-scan.sh`
  prints any `WEAKENED` line for this fix: mark that finding
  `UNRESOLVED — test weakened`, raise a BLOCKER flag in the recap,
  regardless of suite colour. **NO auto-revert** — leave the change in
  place, flag it loud (destructive action stays with the human gate).
  **A silent breaker B is not evidence that no test was weakened (ADR-0073 §D4,
  ADR-0148, issue #311).** An assertion edited IN PLACE removes one
  assert-bearing line and adds one, so `assert-removed`'s count comparison
  cannot fire and nothing here sees it. No detector exists for it: measured over
  383 non-merge commits, a rule on `asrt_rm == asrt_add > 0` has a precision of
  0 of 6, and correcting a wrong test and relaxing a right one produce
  byte-identical diffs. This breaker is the enforcement point the `commit` skill
  defers to, which is why the limit is stated here: the only thing in the whole
  flow that puts a changed assertion in front of a human is the **Test diff**
  section of `commit`'s Step 4 gate, and nothing in this loop substitutes for it.
- **CIRCUIT BREAKER C — security finding report-only.** Never enters this loop
  (classified REPORT-ONLY in Step 2 regardless of class or locality); counted in the recap under "Security (deferred to human)". If a finding was mis-routed to `coder` despite being security class, reclassify it REPORT-ONLY here before dispatch.
- **CIRCUIT BREAKER D — unverified cycle.** If Step 0 returned UNVERIFIED:
  fixes still happen but every recap row carries `UNVERIFIED`, breaker A is
  inert, and the recap header is `⚠ UNVERIFIED CYCLE`.

## Step 4 — Re-review

**Wording-preservation for cross-cycle hash stability.** When dispatching the re-reviewer, include the previous cycle's findings table (problem column verbatim). Instruct the reviewer: *for any finding that is unchanged, reuse the exact one-line problem wording from the previous cycle's recap — paraphrasing changes the finding hash and generates false RESOLVED+NEW pairs in convergence tracking.* New or genuinely changed findings may use new wording.

<!-- dispatch-site: rtf-step4-rereview class=inline exempt: the reviewer grant carries no Write tool, and an early read produces fewer findings which the cross-cycle diff surfaces rather than hides -->
**If `manifest.use_codex_review = true` (Gate CDX):** write the previous cycle's findings as
`sev<TAB>loc<TAB>problem` TSV to a temp file, then run
`~/.claude/scripts/codex-reviewer.sh --mode review --diff-scope uncommitted --carry-forward <that-tsv-file> --out <tmp-review-file>`
(`--carry-forward` embeds the wording-preservation instruction above directly in the Codex prompt,
so it is never skipped when the dispatch is substituted).
- exit `0` → read `<tmp-review-file>` exactly as the reviewer agent's own report; continue below
  unchanged.
- exit `3` (DID-NOT-RUN) → **stop and ask, never silently fall back to Claude:**
  `AskUserQuestion`: "Codex review unavailable at RTF Step 4 re-review: `<reason from stderr>`.
  Fallback to Claude's reviewer agent for this dispatch, or halt the chain?" Options: "Fallback to
  Claude reviewer (Recommended)" → dispatch `reviewer` exactly as below, then continue / "Halt the
  chain" → abort per this skill's existing abort convention.

**Otherwise (default — `use_codex_review` absent or `false`):** Dispatch `reviewer` again over the new state. Recompute the cross-cycle diff:
write the post-fix findings as TSV (`sev<TAB>loc<TAB>problem`) and run — using
the **same** `<rtf-state-file>` path resolved in Step 0 (never a fresh file,
or convergence tracking breaks):
`… | bash $HOME/.claude/skills/review-triage-fix/scripts/triage-state.sh diff <rtf-state-file>`
to get resolved / still-open / new / regressed.

## Step 5 — Recap (decision-grade) then STOP

**Header:** project root; cycle N; verification mode
(`VERIFIED: test-cmd=<cmd>` or `⚠ UNVERIFIED CYCLE`); baseline colour →
post-cycle colour; a prominent flag banner if any
(`ABORT regression`, BLOCKER anti-weakening, deferred security-BLOCKER count).

**Per-finding table** — columns:
`ID (sev+loc+hash) | Sev | Problem (1 line) | Routing | Change (file:line or "—") |
Verification (PASS/FAIL/UNVERIFIED/N-A) | Status vs prev cycle
(NEW/RESOLVED/STILL-OPEN/REGRESSED/WEAKENED)`.

Routing cell values (use these exactly — no free-text in this column):
- `debugger` / `refactorer` / `coder` — dispatched normally
- `coder (inline — stale worktree)` — applied directly by orchestrator because uncommitted changes were present
- `REPORT-ONLY[architectural]` / `REPORT-ONLY[security]` / `REPORT-ONLY[async/actor ADR-0018]` / `REPORT-ONLY[low-confidence]` — routing table match; reason required
- `coder → DEFERRED[cap: overflow N>4]` — was coder-routable but bumped by the 4-dispatch cap

The `[reason]` suffix is mandatory for REPORT-ONLY and DEFERRED rows. Without it the recap reader cannot distinguish a cap overflow from a concurrency guard from a security block, and the next cycle's triage re-argues the same finding from scratch.

`triage-state.sh diff` emits only NEW/RESOLVED/STILL-OPEN/REGRESSED. `WEAKENED`
is not produced by any helper: if **CIRCUIT BREAKER B** fired for a finding, you
override that finding's "Status vs prev cycle" to `WEAKENED` yourself.

**NIT:** a separate compressed sub-table beneath the main one.

**Cycle diff:** explicit counts from `triage-state.sh`
(Resolved / Open / New / Regressed) + the `CONVERGENCE` reading.

**Verdict** (you recommend, the user decides):
- `SAFE: 0 open, suite green → consider commit`
- `RE-RUN recommended: N open, converging`
- `STOP & INSPECT: abort/weakening/not converging`
- `UNVERIFIED: manual verification required before commit`

The finding ID is a hash of `sev|loc|problem`: to keep cross-cycle tracking
stable, reuse the **exact** problem wording from the previous cycle's recap
table when a finding is unchanged — paraphrasing it makes the next cycle
mis-report it as RESOLVED+NEW (false "oscillates") instead of STILL-OPEN.

Then persist state for the next cycle: write the final findings as TSV
(`sev<TAB>loc<TAB>problem<TAB>status`, status `open`|`resolved`) into
`… | bash $HOME/.claude/skills/review-triage-fix/scripts/triage-state.sh commit <rtf-state-file>`
(`<rtf-state-file>` = `$RTF_SF` from Step 0; this also gitignores the
state file when the project is a git repo).

**Cost-pilot logging (Step 0 item 5):** every cycle, regardless of variant — run the post-cycle
snapshot log now, before stopping, matching Step 0 item 5's unconditional `--save`:
`python3 ~/.claude/scripts/usage-snapshot.py --diff "$RTF_LABEL" --log-to ~/.claude/chain-eval.md
>/dev/null 2>&1 || true` (non-blocking; `$RTF_LABEL` resolved in Step 0 item 5). Logging every
cycle, including `opus` (default), is what lets `chain-eval.md` accumulate a baseline to compare
the pilot variants against — gating this call the way the `--save` call isn't gated would leave
`opus` cycles' snapshots written but never diffed or cleaned up.

**STOP.** Do not commit, do not re-invoke yourself. Hand the verdict to the user.

## Future work — parallel batch mode (v2, NOT enabled in v1.1)

A parallel-dispatch optimization for independent fixes is plausible. The two
original blockers are now cleared:
- `~/.claude/agents/coder.md` frontmatter has `isolation: worktree` (was missing in v1).
- CC 2.1.161 fixed the bug where workflow agents with `isolation: worktree` were
  blocked from modifying their own files.

The remaining reason parallel mode is **not yet enabled** is the trade-off:
parallel attribution for circuit breaker A becomes batch-level (regression ↔ culprit
identification requires binary search back-out). The sequential default avoids this.
Parallel mode remains a deliberate architectural choice, not a technical blocker.

To add a parallel mode, gate it on:
all candidates routed to `coder`, non-BLOCKER, disjoint `loc` paths.
Trade-off: lose per-fix attribution for breaker A (regression becomes
batch-level; binary-search-back-out to find culprit). Keep sequential as the
default; parallel as opt-in for time-pressure batches.
