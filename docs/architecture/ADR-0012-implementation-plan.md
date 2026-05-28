# Implementation Plan — ADR-0012 (orchestrator-mediated agent memory)

**Reference ADR:** `docs/architecture/ADR-0012-agent-memory-orchestrator-mediated.md` — **Accepted** 2026-05-24.
**Plan status:** DONE — implemented and verified 2026-05-25 (T1-T10 completed; harness FAIL=0: concept-to-code 25, review-triage-fix 62, vibe-status 12, round-trip standalone 7/7). The only remaining open question to validate in pilot: harvest forgotten in direct dispatches outside the chain (re-evaluation clause, choice 5).
The 5 open choices of the ADR are confirmed by Stefano:
1. report label = `DURABLE NOTES:`
2. path = `~/.claude/projects/<encoded-project-dir>/memory/agent-notes/<agent>.md`, separate from `MEMORY.md`
3. harvest outside chain = manual orchestrator discipline (no enforcement hook now)
4. read-only watch in `vibe-status` on freshness of `agent-notes/` = **included**
5. re-evaluation clause towards A (git-ignore) / C (removal) = accepted

**Nature of the deliverable.** The repo `vibe-coding-system` is blueprint-only (no git, no code).
The artifacts these tasks modify live in `~/.claude/` (agent definitions, skill, memory store).
**No commit step** in the plan: the deploy is direct application of files under `~/.claude/`
+ data migration, after Stefano's approval. The 2 data files to migrate live **inside** this repo
(`docs/agent-notes/`); their removal is the only step that touches the blueprint tree.

---

## Verified state (verified by reading files, 2026-05-24)

- **3 live agent definitions** with the read+append pattern to `docs/agent-notes/`:
  - `~/.claude/agents/architect.md` — Process p.5 (line 33) read+append; Write scope (line 64) includes `docs/agent-notes/architect.md`.
  - `~/.claude/agents/debugger.md` — Process p.2 (line 28) read; Process p.6 (line 32) append.
  - `~/.claude/agents/reviewer.md` — Process p.3 (line 29) read+append.
- **`.bak`:** only `~/.claude/agents/refactorer.md.bak-2026-05-20` contains the pattern; `refactorer.md.bak-2026-05-20-rfs-runs` does **not**; live `refactorer.md` **already clean**.
- **Reviewer/debugger dispatch is NOT in the chain directly.** The chain's Step 6 dispatches the `review-triage-fix` skill, which internally dispatches `reviewer` (Step 1, line ~64, always) and `debugger` (Step 3 route-fix, lines ~77/127, conditional). **Consequence for the plan:** the injection/collection contract for reviewer/debugger must be inserted in `review-triage-fix` dispatch points, NOT in the chain's Step 6. Only `architect` is dispatched directly by the chain (Step 2).
- **`claude-md-generator`** (`~/.claude/skills/claude-md-generator/SKILL.md`, 17 lines): grep of `agent-notes`/`scaffold`/`tracked tree` = **empty**. Does not generate or make exceptions for the rule. D5 reduces to a **non-regression guard** (a note line), not a removal.
- **vibe-status** (`~/.claude/skills/vibe-status/scripts/aggregate.sh`): Section 7 "Memory head" already resolves the encoded path with `ENC=$(printf '%s' "$PWD" | tr '/' '-')` and reads `MEMORY.md`. It is the natural and consistent point to hook a read-only Section 7b on `agent-notes/`. Dedicated harness in `tests/run-tests.sh` with helpers `ok`/`bad`, header `PASS=`/`FAIL=`.
- **Memory store:** `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/` exists (`MEMORY.md` + per-topic files with frontmatter). The `agent-notes/` subfolder **does not yet exist**.
- **Data to migrate (inside this repo):** `docs/agent-notes/architect.md` (~25KB, multi-ADR append-only log) and `docs/agent-notes/debugger.md` (~7KB, bug log). NO `reviewer.md` or `refactorer.md` in the tree.
- **Bash 3.2.57 constraint** (system bash of `~/.claude`): no assoc array, `mapfile`, `${v^^}`, `<()`. Consolidated harness pattern: `set -u`, helpers `ok`/`bad`, `grep -q -- "literal"`, parsing via `sed -n`.

---

## Safe order (rationale)

The order constraint is **no data loss** and **no broken system mid-way**:

1. **First structure + data migration** (Tasks 1-2): create the namespace and copy the contents of the 2 files into the central store, while agents still write to the old path. No loss: data exists in both places.
2. **Then change the agents** (Tasks 3-4): from that point, new runs emit `DURABLE NOTES:` instead of writing files. The old path is no longer recreated.
3. **Then remove the 2 files from the tree** (Task 5, **blocking HITL gate**): only after (a) data is migrated and verified and (b) no agent recreates them anymore. Removing before Task 3 would cause the files to reappear on the first dispatch.
4. **Then the contract in dispatchers** (Tasks 6-7): chain + review-triage-fix, so injection/collection becomes automatic.
5. **Then watches and tests** (Tasks 8-10): claude-md-generator non-regression, vibe-status read-only, round-trip harness.

Tasks 3, 4, 6, 7, 8, 9, 10 are mutually independent downstream of Task 5; they can be batched. Tasks 1->2->5 form a tight chain (data).

---

## Tasks (10, ordered, bounded — dispatch in batches of 2-3, chain rule >=6 tasks)

> Change category legend: **ADD** (addition only) · **REMOVE** (deletion only) · **REPLACE** (substitution: new + old to remove) · **MODIFY** (in-place edit without net add/remove).

### Task 1 — Create the `agent-notes/` namespace in the central store

- **Files touched:** create dir `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/agent-notes/` (empty) + a minimal `~/.claude/projects/.../memory/agent-notes/README.md` that documents: append-only, not linked from `MEMORY.md`, one file per agent (`<agent>.md`), written only by the orchestrator (never by sub-agents).
- **What changes (ADD):** structure creation only. No modification to existing files.
- **Verification:** `test -d ~/.claude/projects/.../memory/agent-notes && test -f ~/.claude/projects/.../memory/agent-notes/README.md`. Confirm that `MEMORY.md` does **not** link `agent-notes/` (negative grep: `grep -c "agent-notes" MEMORY.md` = 0).
- **Dependencies:** none. Prerequisite of Task 2.
- **HITL:** none (creation only, no deletion/overwrite).

### Task 2 — Migrate the content of the 2 existing files to the central store

- **Files touched:**
  - **reads** (source, does NOT modify, does NOT delete): `docs/agent-notes/architect.md` (~25KB), `docs/agent-notes/debugger.md` (~7KB) — inside this repo.
  - **writes** (destination): `~/.claude/projects/.../memory/agent-notes/architect.md`, `~/.claude/projects/.../memory/agent-notes/debugger.md`.
- **What changes (ADD):** 1:1 copy of content. Add a provenance line at the top of each destination file: `<!-- migrated from docs/agent-notes/<agent>.md on 2026-05-24 (ADR-0012) -->`. Maintain the existing append-only format (already per-date logs). Do NOT create `reviewer.md`/`refactorer.md` (no source files exist).
- **Verification:** `diff <(sed '1d' dest/architect.md) docs/agent-notes/architect.md` must differ only by the provenance line (or use a byte-count + spot-check of first/last 20 lines comparison). Same for debugger. **Success criterion:** every byte of source content is present in the destination.
- **Dependencies:** Task 1 (dir must exist).
- **HITL:** none **on the sources** (not touched). The copy to `~/.claude/` is additive. Source removal is Task 5 (separate, with gate).

### Task 3 — Migrate `~/.claude/agents/architect.md` to the injection/collection contract

- **Files touched:** `~/.claude/agents/architect.md`.
- **What changes (REPLACE):**
  - **Line 33 (Process p.5)** — `Remove:` "Check `docs/agent-notes/architect.md` … After designing, append new durable decisions/patterns to it (create the file/dir if absent)." `Add:` "Factor in the `PRIOR AGENT NOTES` block if present in your brief (past durable decisions/patterns for this project); do not re-litigate settled choices. Do NOT read or write any memory file yourself."
  - **Line 64 (Edge Cases -> Write scope)** — `Remove:` `docs/agent-notes/architect.md` from write-scope. `Add:` leave write-scope = only `docs/architecture/**`.
  - **New "Output Format" section (ADD):** add as the last block of the report the terminal section `DURABLE NOTES:` with the exact format from ADR D1.2 (header `DURABLE NOTES:` on its own line; one bullet per note `- [<category>] <1-2 lines> (<optional context>)`; literal line `DURABLE NOTES: none` if no new notes). Specify: it is the LAST section of the report (terminal, machine-greppable, sister of `PATTERN:` from ADR-0001).
- **Verification:** `grep -c "agent-notes" ~/.claude/agents/architect.md` = **0**; `grep -q "DURABLE NOTES:" ~/.claude/agents/architect.md` = true; `grep -q "PRIOR AGENT NOTES" ~/.claude/agents/architect.md` = true; write-scope remains only `docs/architecture/**`.
- **Dependencies:** Task 2 (migrate before removing the write channel from agents — so nothing written in the meantime is lost). Independent of Task 4.
- **HITL:** none (agent config modification under `~/.claude/`, no deletions).

### Task 4 — Migrate `~/.claude/agents/debugger.md` and `~/.claude/agents/reviewer.md` to the same contract

- **Files touched:** `~/.claude/agents/debugger.md`, `~/.claude/agents/reviewer.md`.
- **What changes (REPLACE), debugger.md:**
  - **Line 28 (Process p.2)** — `Remove:` "Check `docs/agent-notes/debugger.md` … for similar past issues; factor in." `Add:` "Factor in the `PRIOR AGENT NOTES` block if present in your brief (past bug patterns on this project)."
  - **Line 32 (Process p.6)** — `Remove:` "Append the bug pattern + resolution to `docs/agent-notes/debugger.md` (create file/dir if absent)." `Add:` emit the terminal `DURABLE NOTES:` section in Output Format (same format as Task 3); write no memory file.
- **What changes (REPLACE), reviewer.md:**
  - **Line 29 (Process p.3)** — `Remove:` "Check `docs/agent-notes/reviewer.md` … Append newly observed recurring patterns after the review (create file/dir if absent)." `Add:` "Factor in the `PRIOR AGENT NOTES` block if present in your brief; emit recurring patterns observed in this review in a terminal `DURABLE NOTES:` section of your report (format above). Write no memory file."
  - Add the `DURABLE NOTES:` format block to Output Format here too (ADD).
- **Verification:** for both: `grep -c "agent-notes"` = **0**; `grep -q "DURABLE NOTES:"` = true; `grep -q "PRIOR AGENT NOTES"` = true. Format consistency of `DURABLE NOTES:` identical among architect/debugger/reviewer (same header, same `none` convention).
- **Dependencies:** Task 2. Independent of Task 3 (batchable with Task 3).
- **HITL:** none.

### Task 5 — Remove the 2 `docs/agent-notes/` files from the repo tree (BLOCKING HITL GATE)

- **Files touched:** `docs/agent-notes/architect.md`, `docs/agent-notes/debugger.md` (deletion); evaluate removal of `docs/agent-notes/` dir if left empty.
- **What changes (REMOVE):** deletion of the 2 files from the tree (and dir if empty).
- **Blocking preconditions (all green before the gate):**
  1. Task 2 completed and **verified** (content present in central store — byte-count + spot-check).
  2. Tasks 3 and 4 completed (no agent recreates the path -> removal is permanent, not recurring).
  3. Show Stefano a **dry-run**: exact paths to delete, their size, and confirmation that copies exist in `~/.claude/.../memory/agent-notes/`. Do not delete anything before explicit `ok`.
- **Post-removal verification:** `test ! -e docs/agent-notes/architect.md && test ! -e docs/agent-notes/debugger.md`. Copies in the store remain intact (`test -f ~/.claude/.../memory/agent-notes/architect.md`).
- **Dependencies:** Tasks 2, 3, 4 (tight chain — NOT anticipatable).
- **HITL:** **BLOCKING GATE** — permanent file deletion. Stefano global rule: "never delete files without explicit confirmation" + "show diff/dry-run". Orchestrator removes only after `ok`.
- **Rollback:** if something goes wrong, contents are still in `~/.claude/.../memory/agent-notes/` (copy from Task 2) -> can be restored to the tree. Recommended pre-deletion tar backup of the 2 files (`docs/agent-notes/.bak-2026-05-24.tar`) kept out of the commit, until the pilot confirms.

### Task 6 — Insert the injection/collection contract into the `concept-to-code` chain (architect dispatch)

- **Files touched:** `~/.claude/skills/concept-to-code/SKILL.md`.
- **What changes (ADD):**
  - **Step 2 — architect dispatch (template lines ~186-208).** Add, at the top of the brief, the injection block:
    ```
    PRIOR AGENT NOTES (read-only context — past durable decisions/patterns for the
    architect on this project; factor in, do not repeat settled work):
    <orchestrator inserts here the content of memory/agent-notes/architect.md, or "none yet">
    ```
    Add to the "Return a report with: …" line the explicit request for the terminal `DURABLE NOTES:` section.
  - **After architect returns (lines ~210-211, "After architect returns…").** Add the **collection** step: the orchestrator extracts the `DURABLE NOTES:` block from the report and, if != `none`, appends it to `memory/agent-notes/architect.md` (never to `MEMORY.md`). Specify that encoded path resolution is the orchestrator's responsibility (never the subagent's — D2).
  - **§6 Coexistence invariants (line ~544).** Update the note on `architect.md`: currently says "not patched; this skill passes a literal prompt template at dispatch time" -> remains true, but add that the template now **injects `PRIOR AGENT NOTES` and collects `DURABLE NOTES:`** (ADR-0012 contract).
- **Verification:** `grep -q "PRIOR AGENT NOTES" SKILL.md` and `grep -q "DURABLE NOTES:" SKILL.md` = true; the harvest step is described in the text after Step 2. **Observable contract changed** (brief form + required report form) -> see Task 10 for the round-trip watch; no external call-site asserts the old brief (grep `PRIOR AGENT NOTES`/`DURABLE NOTES` in the rest of `~/.claude/skills` and `~/.claude/agents` = only the files this plan touches).
- **Dependencies:** Task 3 (architect must already emit `DURABLE NOTES:`). Logically independent of Task 7.
- **HITL:** none.

### Task 7 — Insert the injection/collection contract into `review-triage-fix` (reviewer + debugger dispatch)

- **Files touched:** `~/.claude/skills/review-triage-fix/SKILL.md`.
- **Rationale:** reviewer and debugger are NOT dispatched directly by the chain, but by this skill (chain Step 6 -> review-triage-fix). Therefore their contract lives here.
- **What changes (ADD):**
  - **Step 1 — Review (line ~64), reviewer dispatch.** Add to the brief the `PRIOR AGENT NOTES` block for `reviewer` (content of `memory/agent-notes/reviewer.md` or `none yet`) and request the terminal `DURABLE NOTES:` in the report. After the reviewer report, harvest towards `memory/agent-notes/reviewer.md`.
  - **Step 3 — Route-fix (lines ~126-129), debugger dispatch.** When the route leads to `debugger`, add the `PRIOR AGENT NOTES` block for `debugger` and the post-report harvest of `DURABLE NOTES:` towards `memory/agent-notes/debugger.md`. (The `coder` and `refactorer` are not subjects of the contract — the ADR concerns only the 3 agents with memory; do not add the block to their dispatches.)
  - Add a note at the top of the skill: encoded path resolution and harvest are the responsibility of the orchestrator executing the skill (D2).
- **Verification:** `grep -c "PRIOR AGENT NOTES" SKILL.md` >= 2 (reviewer + debugger); `grep -q "DURABLE NOTES:" SKILL.md` = true; the `coder`/`refactorer` dispatches do NOT contain the block (context grep). **Observable contract changed** (reviewer/debugger brief) -> round-trip harness (Task 10) covers the form; no other file asserts the old brief.
- **Dependencies:** Task 4 (reviewer and debugger must already emit `DURABLE NOTES:`). Independent of Task 6.
- **HITL:** none.

### Task 8 — Non-regression guard on `claude-md-generator` (D5)

- **Files touched:** `~/.claude/skills/claude-md-generator/SKILL.md`.
- **What changes (ADD, minimal):** the current grep confirms the skill does **not** mention `agent-notes` or an anti-scaffolding rule -> there is nothing to remove. The D5 action is **ensuring no re-introduction**: add a guard line in SKILL.md, e.g. in the generation section: "Do not generate doc-discipline rules that prohibit `docs/agent-notes/` in the tracked tree: after ADR-0012 that path is no longer created by any agent (agent memory lives in `~/.claude/projects/<encoded>/memory/agent-notes/`, managed by the orchestrator)."
- **Verification:** `grep -q "agent-notes" SKILL.md` = true (the sole guard note); the additive directive of the chain's Step 3 (`claude-md-generator` invoked as-is) remains unchanged — confirm the modification is an additive line, does not touch the generative flow.
- **Dependencies:** none functional (can go in batch with Tasks 6/7). Logically follows the decision, not the data.
- **HITL:** none.
- **Note / alternative:** if Stefano prefers **zero** mention of `agent-notes` in a skill (to avoid accidentally re-introducing the association), the alternative is to not add the guard line and rely solely on the non-regression grep in the harness (Task 10) as the only watch. Recommended: the guard line is explicit and at zero cost. **Stefano's decision** (see Risks).

### Task 9 — Read-only signal on `agent-notes/` freshness in `vibe-status`

- **Files touched:** `~/.claude/skills/vibe-status/scripts/aggregate.sh`; `~/.claude/skills/vibe-status/tests/run-tests.sh` (one new test); optionally 1 line in `~/.claude/skills/vibe-status/SKILL.md` (Discovery section).
- **What changes (ADD):**
  - In `aggregate.sh`, after Section 7 (Memory head, lines ~170-177), add a **Section 7b — Agent notes**: reuse the same `ENC=$(printf '%s' "$PWD" | tr '/' '-')` already computed; point to `$HOME/.claude/projects/$ENC/memory/agent-notes/`; if the dir exists, count `*.md` files and report the most recent mtime (freshness). Read-only output, fail-graceful (dir absent -> "(no agent-notes)"). NOT blocking: does not alter the `HEALTH` calculation.
  - Add Section 7b rendering in the Markdown block (near `## Memory`) and an optional field in the `--json` branch.
  - In `run-tests.sh`, add **one** test: given a fake store with `agent-notes/<agent>.md`, the output contains the agent-notes section with count >= 1; with dir absent, degrades to "(no agent-notes)" and `exit 0`.
- **Bash 3.2.57 constraint:** follow existing style (`set -u`, no assoc array/mapfile/`${v^^}`/`<()`, `stat -f`/`stat -c` with fallback as line ~134, `grep -q --`).
- **Verification:** `bash run-tests.sh` -> `PASS=` incremented by 1, `FAIL=0`. Smoke: `bash aggregate.sh --skip-harness` shows agent-notes section and exits 0 even with dir absent.
- **Dependencies:** Task 1 (target dir must exist for the "present" case; the "absent" case is testable regardless with a fake store). Independent of others.
- **HITL:** none (read-only).
- **Known coupling to declare:** Section 7b reuses `tr '/' '-'` for encoding, like the existing Section 7. This is the fragile pattern warned by `feedback_pretooluse-payload-schema.md` (`_`->`-`, `cwd` vs `dirname(transcript_path)`). Here **acceptable** because: (a) confined to an orchestrator script (never a sub-agent — D2), (b) consistent with the already-live Section 7 (does not introduce a second convention), (c) it is only a read-only signal (an incorrect encoding produces a false "(no agent-notes)", not corruption). Do not replicate this resolution on the sub-agent side.

### Task 10 — Round-trip contract harness (D6)

- **Files touched:** new `~/.claude/skills/concept-to-code/tests/agent-notes-roundtrip.sh` (or additions to `tests/run-tests.sh` if a single entry point is preferred; see note). Executable (`chmod +x`).
- **What changes (ADD):** deterministic bash 3.2-clean harness (style `vibe-status/tests/run-tests.sh`: `set -u`, `ok`/`bad`, `PASS=`/`FAIL=`, `mktemp -d`, never touch the real store) that verifies the 3 phases of the contract on fixtures:
  1. **Injection** — given a fixture store with `agent-notes/architect.md` of known content, the injection routine (extracted in a helper script or simulated via grep of the template) produces a `PRIOR AGENT NOTES` block containing that text; given absent store, produces `none yet`.
  2. **Collection/parse** — given a fixture report with a well-formed `DURABLE NOTES:` section (>=1 bullet), the parser extracts the correct bullets; given `DURABLE NOTES: none`, extracts zero notes; given a report **truncated** mid-section, the parser does NOT write partial notes (tolerates truncation — lesson `feedback_subagent-truncation-transport.md`).
  3. **Persistence** — the append ends up in `agent-notes/<agent>.md` of the fixture store, **never** in `MEMORY.md` (assert that the fixture `MEMORY.md` remains byte-identical).
- **Implementation note.** Injection and harvest, in B-mediated design, are **orchestrator actions described in prose in the templates** (no single binary). To make them testable headless, Task 10 must extract the deterministic logic (parse of `DURABLE NOTES:` block, `none`/truncated distinction, target path) into a **small bash helper** (e.g. `~/.claude/skills/concept-to-code/scripts/agent-notes-harvest.sh`) that the harness invokes and that Tasks 6/7 reference. This is additive and consistent with the "standalone skill reused by the gate" pattern. **Stefano's decision** whether to have the extracted helper or a harness that only asserts structural anchors in the SKILL.md (weaker but zero new executable code) — see Risks.
- **Bash 3.2.57 constraint:** as above.
- **Verification:** `bash agent-notes-roundtrip.sh` -> `FAIL=0`. Align the PASS target to the style (announce `PASS=N` in the report). If the harness lives in `concept-to-code/tests/`, `vibe-status` discovers it automatically (global Discovery `~/.claude/skills/*/tests/run-tests.sh`) **only** if called `run-tests.sh`; if it is a separate file, add it to the entry point or accept that it runs standalone.
- **Dependencies:** Tasks 6 and 7 (the contract must be inserted to be end-of-template tested). The helper (if extracted) must be created here and retroactively referenced by 6/7 — in that case execute Task 10-helper before 6/7, or coordinate in the same batch.
- **HITL:** none.

---

## Final verification (all green before declaring done)

1. **No agent references `agent-notes/` anymore:** `grep -rl "agent-notes" ~/.claude/agents/` returns **only** `refactorer.md.bak-2026-05-20` (inactive historical `.bak`). architect/debugger/reviewer clean.
2. **Contract present in 3 agents:** each of architect/debugger/reviewer contains `PRIOR AGENT NOTES` (factor-in) and `DURABLE NOTES:` (terminal format).
3. **Architect write-scope:** only `docs/architecture/**` (no `docs/agent-notes/`).
4. **Data migrated:** `~/.claude/.../memory/agent-notes/{architect,debugger}.md` contain the entire content of sources (byte-count + spot-check), `MEMORY.md` does not link them.
5. **Tree clean:** `docs/agent-notes/` removed from the repo (after gate); copies in the store intact.
6. **Chain + review-triage-fix** inject/collect (grep `PRIOR AGENT NOTES`/`DURABLE NOTES:` in the two SKILL.md).
7. **claude-md-generator** does not re-introduce the rule (Task 8 guard).
8. **vibe-status** shows Section 7b agent-notes and exits 0 in all cases; `bash ~/.claude/skills/vibe-status/tests/run-tests.sh` -> `FAIL=0`.
9. **Round-trip harness** green: `FAIL=0`.
10. **System regression:** run `/skill vibe-status` (or `aggregate.sh`) -> health not worsened; in particular the existing harnesses `review-triage-fix` and `concept-to-code` remain green (Tasks 6/7 modified their SKILL.md -> run the respective full `tests/run-tests.sh`, not just the new test — a contract change can break existing anchors in those harnesses).

---

## Risks, dependencies, and decisions that require Stefano before starting

- **[GATE] Deletion of the 2 files (Task 5).** Permanent deletion in the repo tree. Requires explicit `ok` from Stefano after dry-run; precondition = data migrated and verified (Task 2) + agents already migrated (Tasks 3/4). Recommended tar backup until pilot confirms. **Do not proceed without confirmation.**
- **[DECISION] Form of claude-md-generator guard (Task 8).** Add a guard line mentioning `agent-notes` (explicit, recommended) **or** leave the skill intact and rely solely on the non-regression grep in the harness. Trade-off: the line is explicit but re-introduces the term in a skill; absence is cleaner but the guard becomes implicit. Recommended: the guard line.
- **[DECISION] Extraction of the harvest helper (Task 10).** To make the round-trip testable headless, the `DURABLE NOTES:` parse logic must be extracted into a small bash script reused by chain + review-triage-fix. Lighter alternative: harness that only asserts structural anchors in the SKILL.md (no new executable, but does not truly test the parse/truncation). Recommended: extracted helper — D6 explicitly asks to test the parse and truncation tolerance, not just anchor presence.
- **[Non-headless-testable operational risk] Harvest forgotten outside the chain.** Direct dispatch to a sub-agent (outside chain/outside review-triage-fix) remains manual orchestrator discipline (confirmed choice 3, no enforcement hook now). The harness verifies the parse, NOT that the orchestrator *remembers* to collect in a live session. Remains an open question to validate in pilot -> re-evaluation clause towards A (git-ignore) or C (removal) accepted (choice 5).
- **[Encoding risk] Encoded path `tr '/' '-'`.** Confined to the orchestrator and to `vibe-status/aggregate.sh` (never to sub-agents — D2). Consistent with existing Section 7. An incorrect encoding degrades to false "(no agent-notes)" / missing harvest, not corruption. Do not replicate on sub-agent side.
- **[Order dependency] Tight chain Tasks 1->2->5.** Data must not be lost: create structure -> migrate -> (only after agents migrated) remove. Tasks 3/4 must precede Task 5, otherwise files reappear on first dispatch (the conflict is by-design, not one-shot).
- **[NOTE] Inactive `.bak` files.** `refactorer.md.bak-2026-05-20` retains the pattern but is inactive: do NOT touch it (pointless noise, confirmed ADR). The second `.bak` (`-rfs-runs`) does not have the pattern.
- **[NOTE] No commit.** Blueprint repo non-git; artifacts live in `~/.claude/`. The deploy is direct file application + migration, without commit step. The only touch to the repo tree is Task 5 (removal, under gate).

---

## Batch dispatch summary (rule: plan >=6 tasks -> batches of 2-3)

- **Batch 1 (data, tight chain):** Task 1 -> Task 2. Verify migration.
- **Batch 2 (agents):** Task 3 + Task 4 (mutually independent).
- **Batch 3 (removal, GATE):** Task 5 — only after HITL `ok`.
- **Batch 4 (dispatcher contract + helper):** Task 10-helper (if extracted) -> Task 6 + Task 7.
- **Batch 5 (watches + tests):** Task 8 + Task 9 + Task 10-harness.
- **Closure:** Final verification (10 points) + full harness regression.
