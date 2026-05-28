# ADR-0014 — Architect proposes `.claude/test-cmd` in the `concept-to-code` chain (Step 2), unchanged human TOFU approval

**Status:** Accepted — 2026-05-25 (Stefano: greenfield = **option A** "approve-the-intention-now + consumers fail-open until executable"; `TEST-CMD CANDIDATE:` / `TEST-CMD MODE:` block format confirmed. Implemented: edit to `concept-to-code` Step 2 + coexistence note; TOFU/`approve-test-cmd.sh` unchanged.)

**Deciders:** architect (dispatch orchestrator), Stefano Ferri (final approval)

**Related:** ADR-0002 (`docs/architecture/ADR-0002-refactor-snapshot-harness.md` — defines
`.claude/test-cmd` as the only stack-specific contact point for behavior-preservation,
instrumented via SHA256 of the command output; this ADR automates its *proposal*, not the
contract); ADR-0003 (`docs/architecture/ADR-0003-concept-to-code-chain.md` — the chain where
the proposal is inserted, at Step 2); ADR-0009 + swarm-testcmd (the asymmetric fail-mode and
TOFU SHA-pinned: "a wrong test-cmd gives false security -> better UNVERIFIED than auto-guess";
this ADR does NOT touch that gate); ADR-0012 (`docs/architecture/ADR-0012-agent-memory-orchestrator-mediated.md`
— precedent for how architect contracts are conveyed by the **chain template**, not by inflating
`architect.md`; pattern reused here for the `TEST-CMD CANDIDATE` block).

---

## Context

### The `.claude/test-cmd` file and its consumers (VERIFIED 2026-05-25)

`.claude/test-cmd` is a single-useful-line file (plus `#` comments and empty lines) that declares
the project's test command. It is the **only stack-specific contact point** of behavior-preservation
(ADR-0002). Format and parser are identical across all consumers (awk: first non-empty,
non-comment line; special value `NONE` = opt-out). Consumers ascend the tree from cwd looking for
`.claude/test-cmd` (max 40 levels):

- `~/.claude/hooks/stop-gate.sh` — at end of task, if the code is "dirty", **executes** the
  command if and only if the file is TOFU-trusted; otherwise blocks asking for approval. Fail-open
  on absent/`NONE`/empty/non-executable/timeout (never false confirmation).
- `~/.claude/skills/review-triage-fix/scripts/verify.sh` — reporter (not gate): PASS / FAIL /
  **UNVERIFIED** as first token; UNVERIFIED if file absent, `NONE`, empty, or non-executable.
- `~/.claude/skills/refactor-snapshot/` + `~/.claude/agents/refactorer.md` — the refactorer
  REQUIRES the file to pre-exist and be approved; if absent -> snapshot UNVERIFIED -> STOP.
- `~/.claude/hooks/approve-test-cmd.sh` — CLI TOFU (NOT a hook). Computes SHA256 of the file and
  records `<sha256>\t<normalized-root>` in the trust file. **Never executes the command.** Changing
  the file invalidates trust -> re-approval required.

### The problem: "create it manually" friction

Today `.claude/test-cmd` must be **written by hand** and then approved with the CLI. The
`concept-to-code` chain does not scaffold it: it only cites it in the coexistence invariants
(SKILL.md line 559). Consequence: every new project passed through the chain arrives at
implementation without a test-cmd, and the three consumers remain in unverified state
(block/UNVERIFIED/STOP) until Stefano manually creates the file. The friction is unnecessary: at
**Step 2** of the chain the architect has already read the SPEC, ARCH, and the stack/framework —
it is the **most informed point** of the workflow for deducing the correct test command. Moving
the deduction there eliminates the manual work without shifting the security gate.

### Greenfield vs brownfield: the tension to resolve

- **Brownfield** (existing project with tests): the command deduced by the architect is
  **immediately executable**. The proposal is also immediately verifiable.
- **Greenfield** (new project, tests not yet written): the command is the *intended* one
  (e.g. `pytest -q`, `npm test`) but **does not run** until the tests exist (typically until
  scaffold/impl). Approving a not-yet-executable command is safe for TOFU (SHA pinned on an
  intention), but it is not yet "verified in execution": on first run consumers fail-open on
  "not executable" (stop-gate fail-open, verify.sh UNVERIFIED) — therefore **no false
  confirmation**, but a decision is needed on WHEN the approval/use becomes sensible. This
  tension is explicitly resolved in Decision point 4 (with the final decision deferred to Stefano).

---

## Decision

1. **Proposal point = architect, Step 2.** In the architect's report a terminal structured block
   `TEST-CMD CANDIDATE:` is added with the test command deduced from the stack, and the
   greenfield/brownfield flag (format in Decision point 3). The contract is conveyed by the
   **chain template** (SKILL.md Step 2), NOT by `architect.md` — consistent with ADR-0012, to
   avoid inflating the agent definition with chain-specific logic.

2. **The orchestrator writes the candidate; the human approves.** After the architect returns,
   the orchestrator extracts the command from the block and writes `<project-root>/.claude/test-cmd`
   as a **candidate** (with a `#` comment marking it as proposed + greenfield flag if applicable).
   Then it presents a **HITL gate** that shows the command and asks Stefano to approve it by
   running `bash ~/.claude/hooks/approve-test-cmd.sh "<project-root>"`. The **existing TOFU
   mechanism is reused**: no new gate, no new trust store, no new CLI.

3. **Architect block format** (terminal, after `DURABLE NOTES:`):
   ```
   TEST-CMD CANDIDATE: <test command on a single line>
   TEST-CMD MODE: greenfield | brownfield
   ```
   If the architect cannot deduce a reliable command -> the literal line
   `TEST-CMD CANDIDATE: none` (the orchestrator does NOT write the file and signals it at the gate).

4. **Greenfield resolution (deferred to Stefano — open point).** Recommended approach:
   **approve-the-intention-now + verify-executability-at-first-real-use**. The greenfield
   `.claude/test-cmd` is written and approved immediately (SHA pinned on the intention); marked
   with the comment `# greenfield: provisional — not executable until tests exist`. Until then
   consumers fail-open correctly (stop-gate fail-open on rc 124/125/126/127, verify.sh ->
   UNVERIFIED): never false confirmation. When the first tests appear (scaffold/impl), the command
   becomes executable **without any re-approval** provided the file has not changed; if the
   architect guessed the wrong command and it needs correction, the file change invalidates TOFU
   and forces re-approval — desired behavior. **Alternative Stefano must evaluate:** move the
   greenfield approval gate *after* the first tests (approve only an already-executable command),
   at the cost of leaving the project unverified during the initial scaffold.

5. **Security unchanged.** The SHA-pinned approval remains **human and singular**. The system
   PROPOSES (writes a candidate), never auto-executes **a command that has not been approved**:
   writing the file does NOT make it trusted — trust arises only from the explicit execution of
   `approve-test-cmd.sh` by Stefano. This **does not weaken TOFU**: the pinned object (SHA of
   the file) and the gate (human CLI) are unchanged; only *who drafts the candidate* changes
   (architect instead of Stefano by hand), which is upstream of the pin.

6. **Coexistence unchanged.** The candidate is written in the same single-line format consumed by
   stop-gate / verify.sh / refactor-snapshot; no consumer script changes. The coexistence
   invariants of the chain (SKILL.md) remain valid; only the note is updated from "does not
   scaffold test-cmd" to "scaffolds a candidate test-cmd at Step 2, TOFU approval unchanged".

---

## Consequences

**Positive**
- Eliminates "create it manually" friction: the command is drafted by the most informed point of
  the chain.
- Zero new security surface: reuses TOFU + trust store + existing CLI.
- Consistent with ADR-0012: contract in chain template, `architect.md` does not inflate.
- Consumers (stop-gate/verify.sh/refactorer) do not change: minimal regression risk.

**Negative**
- The architect may deduce a wrong command; mitigated by the fact that the HITL gate shows the
  command to Stefano *before* approval, and that a wrong command gives UNVERIFIED (not false
  confirmation) until corrected + re-approved.
- Greenfield introduces a "provisional" state that requires discipline (the decision on when to
  approve remains open, point 4).

**Neutral**
- The chain acquires a micro-step (candidate writing + gate). On brownfield it is also immediately
  verifiable; on greenfield it is declarative.
- If the architect emits `TEST-CMD CANDIDATE: none`, behavior is identical to today (no file,
  consumers in unverified state): no regression from status quo.

---

## Alternatives considered

**(A) Status quo — manual test-cmd creation.** Rejected: it is exactly the friction Stefano wants
to remove. Leaves every new chain project without test-cmd until manual intervention, with the
three consumers blocked/UNVERIFIED. No gain beyond the absence of design work.

**(B) Heuristic auto-detect at runtime, without involving architecture.** A script that, on first
use, guesses the command from present files (presence of `pytest.ini`, `package.json`,
`Cargo.toml`...) and writes/executes it. Rejected: the heuristic is **less informed than the
architect** (does not know SPEC/ARCH or the project's testing choices), and — per the
ADR-0009/swarm-testcmd principle — a wrongly guessed test-cmd gives **false security**. Executing
without approval violates TOFU; no heuristic is reliable enough to bypass the human gate.

**(C) Proposal at Step 2 (architect) + single TOFU approval — CHOSEN.** The architect, already
the most informed point of the chain, declares the command in the report; the orchestrator writes
a candidate; Stefano approves once with the existing CLI. Combines the informational advantage of
an architecture-level analysis with the unchanged human security gate. Reason for choice: maximizes
proposal quality and zeroes the new security surface, maintaining PROPOSES-not-executes.

**(D) Approval gate moved to end of chain (after first tests, only executable commands).**
Rejected as default, retained as greenfield option in Decision point 4: guarantees approving only
an already-executable command, at the cost of leaving the initial scaffold unverified and moving
the gate far from the point where the command is deduced.

---

## References

- `~/.claude/hooks/approve-test-cmd.sh` — CLI TOFU (SHA256-pinning, never executes the command).
- `~/.claude/hooks/stop-gate.sh` — enforce TOFU + end-of-task execution, asymmetric fail-open.
- `~/.claude/skills/review-triage-fix/scripts/verify.sh` — PASS/FAIL/UNVERIFIED reporter.
- `~/.claude/agents/refactorer.md` — consumer that REQUIRES an approved test-cmd (snapshot
  UNVERIFIED if absent).
- `~/.claude/skills/concept-to-code/SKILL.md` — Step 2 (architect dispatch, ~lines 167-221)
  insertion point; coexistence invariants line ~559.
- ADR-0002, ADR-0003, ADR-0009, ADR-0012 (see Related).
