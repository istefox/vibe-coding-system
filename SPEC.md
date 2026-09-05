# SPEC — Extend the Codex-vs-Claude review gate to deep-refactor's audit dispatch

Source: chain interview, 2026-09-05. Extends ADR-0187 (`docs/architecture/ADR-0187-codex-review-gate.md`).

**Topic slug:** codex-review-gate-deep-refactor

## Objectives

1. Let `deep-refactor`'s Phase 1 audit dispatch (the 4 dimension `reviewer` agents — dead-code,
   perf, structure, security) run against Codex CLI instead of Claude's `reviewer` agent, on the
   same substitute-not-second-opinion contract ADR-0187 established, extended to deep-refactor's
   own `risk_level`/`fix_type` finding taxonomy.
2. Keep the gate scoped to `deep-refactor` only: a flag independent of `manifest.use_codex_review`,
   because `deep-refactor` is invocable standalone, outside any `concept-to-code` manifest.
3. Never touch Phase 2/3 (the fix loop: `coder`/`refactorer`/`debugger` dispatch) — identical to
   ADR-0187's own scope boundary, which never substitutes a fix agent, only a review-role one.
4. Preserve, byte-for-byte, `deep-refactor/SKILL.md`'s Claude-only behaviour for every invocation
   that does not opt in — same non-negotiable ADR-0187 already applied to the five original sites.

## Scope

In:
- A new `deep-refactor`-local gate (its own `AskUserQuestion`, not Gate CDX) asked once per
  standalone/attended invocation, before Phase 1 dispatch.
- Autopilot / unattended invocation via the `concept-to-code` chain's Gate 5.1: no question asked;
  the decision is inherited from `manifest.use_codex_review` when a manifest is present, else
  defaults to Claude-only (no manifest → no flag to inherit → today's behaviour).
- A new `--mode audit --dimension dead-code|perf|structure|security` mode in
  `staging/plugin/scripts/codex-reviewer.sh`, output shaped to `deep-refactor`'s finding schema
  (`dimension`/`severity`/`risk_level`/`fix_type`/`file`/`line`/`description`), not the
  BLOCKER/MAJOR/MINOR/NIT shape the existing `review`/`diagnose` modes use.
- The two mandatory guard instructions (dead-code's ObjC/reflection carve-out, perf's
  concurrency carve-out — `SKILL.md` "Mandatory guard 1/2") embedded verbatim inside the new
  Codex audit prompt for their respective dimensions, so the structural anchor `SKILL.md` declares
  stays true regardless of which engine actually ran.
- Per-dimension fallback: if Codex returns DID-NOT-RUN (exit 3, same convention as ADR-0187) for
  one or more of the 4 dimensions during Branch A's parallel fan-out, only the failing
  dimension(s) fall back to Claude's `reviewer` for that run; the others stay on Codex. The Phase 1
  findings summary (HITL Gate 1) reports which engine served each dimension.
- Both dispatch branches in `deep-refactor/SKILL.md` (`### Dispatch model` — Branch A Workflow
  fan-out, Branch B sequential `Agent`-tool fallback) get the IF/ELSE wrap, byte-preserving the
  existing Claude-only branch exactly, same idiom ADR-0187 used at its five sites.
- An ADR documenting the extension: either an addendum to ADR-0187 (its own text explicitly
  deferred this) or a new ADR cross-referencing it — architect's call at Step 2, consistent with
  rule 14 (a completed ADR's original scope note is a correct snapshot of its day and is not
  edited in place; the deferral is superseded going forward, not rewritten).
- Harness/test updates: a plant test asserting the new `--mode audit` exists and rejects a bad
  `--dimension`; a plant test asserting both mandatory guard instructions' literal text is present
  inside `codex-reviewer.sh`'s audit-mode prompt construction (mirroring the existing structural
  anchor check on `SKILL.md` itself); an Invariant-1-style manifest field check is NOT needed,
  since the new flag does not live in the c2c manifest schema (Objective 2).

Out:
- Any change to Phase 2 (fix loop), Phase 3 (security report-only section), or Phase 4
  (report/commit gate) dispatch — those stay exactly as `deep-refactor/SKILL.md` already commits
  to (coder/refactorer/debugger, model opus, Claude only).
- Any change to the five sites ADR-0187 already covers (RTF, Step 5 checkpoint) — untouched.
- A shared/unified taxonomy between `reviewer`'s BLOCKER/MAJOR/MINOR/NIT and deep-refactor's
  risk_level/fix_type — ADR-0187 already rejected merging these (rule 6: they answer different
  questions), and this feature does not revisit that.
- `security-audit` and Gate 5.06 (`silent-failure-hunter`/`type-design-analyzer`) — still
  explicitly deferred by ADR-0187, unaffected by this feature.

## Stack

Same as the rest of `staging/plugin/`: Bash 3.2-clean shell scripts (`codex-reviewer.sh`
extension), Markdown skill prose (`deep-refactor/SKILL.md` edits), an ADR in
`docs/architecture/`, plant-check-covered test scripts under `staging/plugin/scripts/tests/`.

## Architecture

### New flag

`deep-refactor`-local, not part of the c2c manifest schema. Two carriers:

1. **Attended/standalone invocation:** a new `AskUserQuestion` at deep-refactor's own HITL Gate 0
   (or immediately before it), asked every run — no persistent file, no new state mechanism.
   Options: "No — Claude only (current behaviour)" (default/recommended) / "Yes — use Codex for
   audit dispatch, with per-dimension fallback if unavailable".
2. **Unattended invocation via c2c Gate 5.1 with `manifest.autopilot = true`:** no question asked.
   If a c2c manifest is present, read `manifest.use_codex_review` and use its value directly as
   deep-refactor's own decision for this run. If no manifest is present (standalone autopilot has
   no manifest to read), the decision defaults to Claude-only — there is nothing to inherit.

### `codex-reviewer.sh` — new `--mode audit`

```
--mode audit --dimension dead-code|perf|structure|security --diff-scope uncommitted|base:<ref>|commit:<sha> --out <file>
```

Same exit-code contract as the existing two modes (0 success, 2 bad invocation, 3 DID-NOT-RUN).
Output written to `--out` as JSON matching deep-refactor's `FINDINGS_SCHEMA` (already declared in
`deep-refactor/SKILL.md` — `dimension`, `severity`, `file`, `line`, `description`, `risk_level`,
`fix_type`), not the existing modes' markdown report shape.

For `--dimension dead-code` and `--dimension perf`, the prompt construction embeds the exact
verbatim guard-instruction text from `SKILL.md`'s "Mandatory guard 1"/"Mandatory guard 2" sections.
For `--dimension security`, the prompt enforces `fix_type: report-only` on every returned finding
regardless of what Codex proposes (mirroring `SKILL.md`'s own "All security findings are always
`fix_type: report-only`" invariant) — the wrapper script, not Codex, is the enforcement point,
consistent with rule 16 (an instruction to an LLM is not an enforcement; a mechanical postprocess
step is).

### `deep-refactor/SKILL.md` — dispatch site changes

Both branches under `### Dispatch model` get an IF/ELSE on the new flag:

- **Branch A (Workflow fan-out, default):** when the flag is on, each of the 4 `agent()` calls is
  replaced by a call to `codex-reviewer.sh --mode audit --dimension <d>` for that dimension,
  fanned out the same way (still one call per dimension, still parallel). A per-dimension check on
  the exit code: `3` → that one dimension's call is replaced with the existing Claude `reviewer`
  agent() call for that dimension only (per-dimension fallback, Objective/Scope above); `0` →
  parse the JSON into the same in-memory findings shape the Claude path already produces, so
  everything downstream of Phase 1 (merge/dedup/sort/Gate 1) is unchanged.
- **Branch B (sequential `Agent`-tool fallback):** same substitution, sequential instead of
  parallel — call `codex-reviewer.sh` per dimension in the same fixed order
  (dead-code → perf → structure → security) the branch already documents, with the same
  per-dimension exit-3 fallback.
- The Claude-only branch (today's text) is preserved byte-for-byte inside the `ELSE`, per
  ADR-0187's own "byte-preserving the ELSE" convention — the harness greps for
  `Dispatch the \`reviewer\``-shaped text literally at the five original sites; this feature adds
  the same literal-text preservation requirement at deep-refactor's two branches.

### HITL Gate 1 (findings summary) — engine visibility

When the Codex flag was on for this run, Gate 1's summary gains one line per dimension naming
which engine actually served it (`Codex` or `Claude (fallback)`), so a per-dimension fallback is
visible to the operator before they approve the fix loop.

## Data model

`FINDINGS_SCHEMA` (already declared in `deep-refactor/SKILL.md`) is unchanged. No new field is
added to it — engine attribution is Gate-1-summary-only, not persisted into the finding object
itself, since Phase 2's fix loop and Phase 4's report never need to know which engine produced a
given finding.

## API / CLI surface

`codex-reviewer.sh --mode audit --dimension <d> --diff-scope <scope> --out <file>` — new mode,
additive to the existing `--mode review|diagnose`. No change to either existing mode's contract.

## UI flows

1. `deep-refactor` invoked (standalone, or via c2c Gate 5.1 attended) → its own Codex gate
   question fires once, before Phase 1 dispatch, mirroring Gate CDX's wording and default.
2. `deep-refactor` invoked via c2c Gate 5.1 with `manifest.autopilot = true` → no question; the
   manifest's `use_codex_review` value is read and applied silently.
3. Phase 1 dispatch fans out 4 dimension calls, each to Codex or Claude per the resolved flag;
   any per-dimension DID-NOT-RUN falls back to Claude for that dimension only, silently within the
   run (no mid-run question — consistent with ADR-0187's own "gate once, not per site" decision,
   here read as "resolve the engine choice once per invocation, not once per dispatch").
4. HITL Gate 1 shows the existing findings summary plus the new per-dimension engine line.
5. Phase 2 onward: unchanged, Claude only, exactly as today.

## Edge cases

- Codex unavailable for all 4 dimensions → all 4 fall back individually to Claude; Gate 1 shows
  four `Claude (fallback)` lines; behaviourally identical to the flag having been off, except for
  the visible fallback notice.
- No c2c manifest present AND autopilot true (fully standalone unattended deep-refactor) →
  nothing to inherit; defaults to Claude-only, no question asked (there is no operator to ask).
- `manifest.use_codex_review` absent on an older-schema manifest (pre-1.4) → treated as `false`
  (retrocompat, same as ADR-0187's own Invariant 24 default).
- Security dimension routed to Codex → `fix_type: report-only` is enforced by the wrapper script
  regardless of what Codex's own output claims, never trusted from the LLM response directly.
- Dead-code/perf dimensions routed to Codex → the mandatory guard instructions must appear in the
  actual prompt Codex receives, not merely be present in `SKILL.md`'s prose; the harness check for
  this feature greps `codex-reviewer.sh`'s own prompt-construction code, not just the skill file.

## Success criteria

- [ ] R-01 — `codex-reviewer.sh` gains a `--mode audit --dimension dead-code|perf|structure|security`
      mode with the exit-code contract 0/2/3 unchanged from the existing modes, and rejects an
      unknown `--dimension` value with exit 2.
- [ ] R-02 — the audit-mode output for a successful run is valid JSON matching deep-refactor's
      `FINDINGS_SCHEMA` field set (`dimension`, `severity`, `file`, `line`, `description`,
      `risk_level`, `fix_type`).
- [ ] R-03 — the dead-code and perf audit-mode prompts contain the exact verbatim guard-instruction
      text from `SKILL.md`'s Mandatory guard 1/2 sections.
- [ ] R-04 — the security audit-mode path forces `fix_type: report-only` on every finding it
      returns, regardless of the raw Codex response.
- [ ] R-05 — `deep-refactor/SKILL.md`'s Branch A (Workflow fan-out) dispatches each of the 4
      dimensions to Codex when the flag is on, with per-dimension exit-3 fallback to the existing
      Claude `reviewer` agent() call for that dimension only.
- [ ] R-06 — `deep-refactor/SKILL.md`'s Branch B (sequential Agent-tool fallback) gets the same
      per-dimension Codex/fallback behaviour, in the existing fixed dimension order.
- [ ] R-07 — the Claude-only branch text at both dispatch sites is preserved byte-for-byte inside
      the `ELSE` of the new IF/ELSE wrap (no rewording of the existing Claude path).
- [ ] R-08 — an attended/standalone `deep-refactor` invocation asks its own Codex gate question
      once, before Phase 1, defaulting to "No — Claude only".
- [ ] R-09 — a `deep-refactor` invocation via c2c Gate 5.1 with `manifest.autopilot = true` asks no
      question and inherits `manifest.use_codex_review` when a manifest is present, else defaults
      to Claude-only.
- [ ] R-10 — HITL Gate 1's findings summary names which engine (Codex or Claude fallback) served
      each of the 4 dimensions, only when the Codex flag was on for that run.
- [ ] R-11 — every invocation with the new flag left at its default (off) produces byte-identical
      dispatch behaviour to today's `deep-refactor/SKILL.md` (no regression on the unopted-in path).
- [ ] R-12 — a plant test exists asserting the new `--mode audit` and its `--dimension` validation
      (no-test: this is itself the harness coverage requirement — see repo Rule 2, a needle must be
      planted and observed RED against a real absence before it counts as coverage).
- [ ] R-13 — a plant test exists asserting both mandatory guard instructions' literal text is
      present inside `codex-reviewer.sh`'s prompt-construction code (no-test: same rule-2 reasoning
      as R-12 — this is the test-planting requirement itself, verified structurally, not by a unit
      assertion of behaviour).
- [ ] R-14 — an ADR (addendum to ADR-0187 or a new cross-referencing ADR, architect's call) records
      this extension and explicitly updates ADR-0187's "explicitly deferred" scope note going
      forward, without editing ADR-0187's original text in place (no-test: this is a documentation
      obligation, verified by reading the ADR file, not by an automated assertion).
