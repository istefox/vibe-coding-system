# Plan — Refresh stale staging copies from the deployed tree

**Date:** 2026-07-11
**ADR:** [ADR-0025](../../architecture/ADR-0025-29-refresh-stale-staging-copies.md)
**Spec:** [SPEC.md](../../../SPEC.md) (= `docs/specs/29-refresh-stale-staging-copies-from-the-de.spec.md`, issue #29)
**Style:** TDD (red -> green -> checkpoint). Auto mode active, no intermediate HITL inside this plan; commit/push
stay HITL per repo `CLAUDE.md` invariant (see HITL gates at the end).

---

## Why "RED" means "confirmed stale," not "a failing unit test"

This is a content-refresh task: there is no application logic to drive with a failing assertion, because the
"bug" is staleness itself — a staged file not matching its deployed counterpart. "RED" here means the pre-refresh
`diff -q`/`diff -u` against `~/.claude` genuinely reports a difference (already confirmed during planning, exact
diff-line counts quoted per task below so the coder does not have to rediscover them), and "GREEN" means the same
diff reports none after the copy. For `staging/user/settings.json` (Task 5), which is deliberately **not**
byte-identical to deployment by design (ADR-0025 SS2.2), "GREEN" instead means a set of structural `jq` assertions
pass — specified in full in that task.

## Refresh mechanics (read once, applies to Tasks 1-4)

- **Direction:** `cp -p "$HOME/.claude/<deployed-relpath>" "staging/<staging-relpath>"` only. Never write under
  `~/.claude`. `-p` preserves permission bits, so the executable bit on `protect-files.sh`/`auto-format.sh`
  carries over automatically — no separate `chmod +x` needed. `.md` files stay non-executable, matching deployed.
- **Verify with `diff -q "staging/<path>" "$HOME/.claude/<path>"`** after every copy — expect exit 0, no output.
  Any output means the copy did not take or the deployed file changed mid-session (see Risk A).
- **No PAIRS changes in Tasks 1-4.** None of the files those tasks touch has an existing PAIRS entry (confirmed
  during planning by grepping the full PAIRS block in `staging/sync-to-claude.sh`), and this plan does not add
  any — see ADR-0025 SS2.3 for why (they are reachable via `docs/RUNBOOK.md`'s bulk `cp`/`cp -R` disaster-recovery
  steps, a separate mechanism from PAIRS). Do not "helpfully" add PAIRS entries for files not named in Task 6.
- **`pairs-completeness.test.sh` must report `PASS=105 FAIL=0` through Task 5**, then `PASS=107 FAIL=0` from
  Task 6 onward. Any other count means a PAIRS line was accidentally added, removed, or malformed.

## Pre-flight constraints

- Reading `~/.claude` is authorized (copy source only, per SPEC and ADR-0025). All writes stay inside the
  repository: `staging/`, `staging/sync-to-claude.sh`, `docs/vibe-coding-system.md` (exactly lines 2282, 2297,
  plus one new changelog block — see Task 7), `SPEC.md` (checkbox updates, Task 8 only).
- Do not touch: any `staging/plugin/skills/<name>/` directory not named below (in particular
  `project-conductor`, `spec-from-issue`, `concept-to-code`, `autopilot-build`, `deep-refactor`,
  `review-triage-fix`, `claude-md-slim`, `clean-public-repo`, `humanize-en`, `design-brainstorm`,
  `refactor-snapshot`, `macos-ux`, `project-init`, `git-repo-init`, `prompt-builder`, `vibe-status`,
  `swiftui-pro`, `find-skills` — all out of this issue's scope, several already PAIRS-covered by ADR-0024);
  `docs/RUNBOOK.md`; `docs/GUIDA-CREARE-PROGETTO.md`; `docs/guida-workflow-orchestrazione.md`; any file under
  `docs/superpowers/plans/` or `docs/superpowers/specs/` other than this new plan file; any
  `docs/vibe-coding-system.md` line other than 2282, 2297, and the one new changelog block (see Task 7 — in
  particular, leave section 8.3's ~line 1650 `project-bootstrap` catalog entry and section 4's ~line 970 template
  untouched).
- Do not add PAIRS entries beyond the two named in Task 6.
- `staging/user/settings.json`: use the exact `jq del()` command in Task 5. Do not hand-edit key by key, and do
  not strip any key beyond the six SPEC names (`model`, `theme`, `tui`, `editorMode`, `statusLine`,
  `cleanupPeriodDays`) — see ADR-0025 SS3.3 Alternative C for why not.

## Anchor invariants (HARD — must stay true after every task)

- `bash staging/plugin/scripts/tests/phase1.test.sh` -> PASS, exit 0 (30 passed).
- `bash staging/plugin/scripts/tests/prep.test.sh` -> PASS, exit 0 (15 passed).
- `bash staging/plugin/scripts/tests/hook-probe.test.sh` -> PASS, exit 0 (29 passed).
- `bash staging/plugin/scripts/tests/hook-verify-workflow.test.sh` -> PASS, exit 0 (26 passed).
- `bash staging/plugin/scripts/tests/pairs-completeness.test.sh` -> `PASS=105 FAIL=0` through Task 5,
  `PASS=107 FAIL=0` from Task 6 onward.
- `git status` shows changes only under the allow-listed paths in Pre-flight constraints. Nothing under
  `~/.claude` is ever a write target, at any point, in any task.

---

## Task 1 — RED then GREEN: refresh the 8 agent files

**Files modified (all `staging/plugin/agents/<name>.md`, source `$HOME/.claude/agents/<name>.md`):**
`architect.md`, `coder.md`, `debugger.md`, `doc-writer.md`, `refactorer.md`, `researcher.md`, `reviewer.md`,
`tester.md`.

**Confirmed RED (pre-refresh diff-line counts, `diff staging/... $HOME/.claude/...`):** `architect.md` 44,
`coder.md` 67, `debugger.md` 26, `doc-writer.md` 8, `refactorer.md` 28, `researcher.md` 12, `reviewer.md` 36,
`tester.md` 2. Two specific, named deltas to be aware of while reviewing (both fixed automatically by the full
mirror, no separate action needed):
- `staging/plugin/agents/coder.md` currently has zero `PATTERN` occurrences (deployed has 8 — the ADR-0001/0004
  classifier convention is entirely absent from the staged copy, not just outdated).
- `architect.md`, `debugger.md`, `refactorer.md`, `reviewer.md` currently reference `docs/agent-notes/<agent>.md`
  (the file-based memory convention ADR-0012 retired); `architect.md` currently has zero `DURABLE NOTES`
  occurrences (deployed has 1 — the ADR-0014 output-block convention).

**Contract:** `cp -p "$HOME/.claude/agents/<name>.md" "staging/plugin/agents/<name>.md"` for all 8. Full mirror,
no selective patching (ADR-0025 SS2.1) — this also carries over undocumented drift on `architect.md`
(`effort: max` vs. blueprint's documented `xhigh`, extra inline `mcp__plugin_context7_context7__*` tool grants)
and `reviewer.md` (extra `LSP` tool grant). **Do not** revert or "fix" any of this toward the blueprint's
documented intent — that is issue #40's job, not this task's. Leave it exactly as deployed.

**Expected (RED then GREEN):** pre-copy `diff -q` on all 8 exits 1 (matches the counts above); post-copy `diff -q`
on all 8 exits 0 with no output.

**Checkpoint:**
```bash
for f in architect coder debugger doc-writer refactorer researcher reviewer tester; do
  diff -q "staging/plugin/agents/$f.md" "$HOME/.claude/agents/$f.md" || echo "FAIL: $f"
done   # expect zero "FAIL" lines
grep -c PATTERN staging/plugin/agents/coder.md            # expect nonzero (8)
grep -rn "docs/agent-notes" staging/plugin/agents/*.md    # expect no output
for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done   # all 5 unchanged, still green
```

---

## Task 2 — GREEN: refresh the 7 repo-native `SKILL.md` files

**Files modified (all `staging/plugin/skills/<name>/SKILL.md`, source `$HOME/.claude/skills/<name>/SKILL.md`):**
`commit`, `interview-driver`, `adr-writer`, `claude-md-generator`, `code-review-checklist`, `swift-vibe`,
`fastapi-react-vibe`.

**Confirmed RED (pre-refresh diff-line counts):** `commit` 288 (staged copy is missing the entire `--autopilot`
flag from ADR-0020), `interview-driver` 21, `adr-writer` 24, `claude-md-generator` 28, `code-review-checklist` 28,
`swift-vibe` 24, `fastapi-react-vibe` 31. Note: both `interview-driver` and `fastapi-react-vibe` staged copies
currently have `disable-model-invocation: true` at line 4; **neither deployed copy does** — the refresh removes
it from both, per SPEC's explicit success criterion. This is a real, live gap against the blueprint's documented
`/loop` safety design (see ADR-0025 SS1 fact 2, SS3.5) — mirror it as directed, do not "fix" it by keeping the
flag, and do not silently drop this note from the coder's report.

**Contract:** `cp -p "$HOME/.claude/skills/<name>/SKILL.md" "staging/plugin/skills/<name>/SKILL.md"` for all 7.
Full mirror, no selective patching.

**Expected (RED then GREEN):** pre-copy `diff -q` on all 7 exits 1; post-copy exits 0, no output.

**Checkpoint:**
```bash
for f in commit interview-driver adr-writer claude-md-generator code-review-checklist swift-vibe fastapi-react-vibe; do
  diff -q "staging/plugin/skills/$f/SKILL.md" "$HOME/.claude/skills/$f/SKILL.md" || echo "FAIL: $f"
done   # expect zero "FAIL" lines
grep -q -- "--autopilot" staging/plugin/skills/commit/SKILL.md && echo "OK: --autopilot present"
grep -q "disable-model-invocation" staging/plugin/skills/interview-driver/SKILL.md && echo "FAIL: flag still present" || echo "OK: flag absent"
for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done   # 5 green, unchanged
```

---

## Task 3 — GREEN: refresh `protect-files.sh` and `auto-format.sh`

**Files modified:**
- `staging/plugin/scripts/protect-files.sh` (source `$HOME/.claude/hooks/protect-files.sh`)
- `staging/plugin/scripts/auto-format.sh` (source `$HOME/.claude/hooks/auto-format.sh`)

**Confirmed RED:** `protect-files.sh` 12 diff lines, `auto-format.sh` 8 diff lines. Both deployed scripts share
the same fail-open `jq` pattern on line 4 — `jq -r '.tool_input.file_path // empty' 2>/dev/null || true` —
absent from the current staged copies. ADR-0024 already flagged this exact pattern on these exact two files as
deliberate; keep it, do not simplify or "clean it up."

**Contract:** `cp -p "$HOME/.claude/hooks/<name>.sh" "staging/plugin/scripts/<name>.sh"` for both. `-p` preserves
the executable bit — confirm with `ls -l`, do not run a separate `chmod`.

**Expected (RED then GREEN):** pre-copy `diff -q` on both exits 1; post-copy exits 0, no output.

**Checkpoint:**
```bash
for f in protect-files.sh auto-format.sh; do
  diff -q "staging/plugin/scripts/$f" "$HOME/.claude/hooks/$f" || echo "FAIL: $f"
  bash -n "staging/plugin/scripts/$f" || echo "SYNTAX FAIL: $f"
  [ -x "staging/plugin/scripts/$f" ] || echo "FAIL: $f not executable"
done   # expect zero FAIL lines
grep -c "jq -r '.tool_input.file_path // empty' 2>/dev/null || true" staging/plugin/scripts/protect-files.sh staging/plugin/scripts/auto-format.sh
for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done   # 5 green, unchanged
```

---

## Task 4 — GREEN: refresh `staging/user/CLAUDE.md` + `rules/swift.md`; add `rules/parallelization.md`

**Files modified:**
- `staging/user/CLAUDE.md` (source `$HOME/.claude/CLAUDE.md`, 112 diff lines confirmed RED)
- `staging/user/rules/swift.md` (source `$HOME/.claude/rules/swift.md`, 19 diff lines confirmed RED)

**Files created:**
- `staging/user/rules/parallelization.md` (source `$HOME/.claude/rules/parallelization.md` — deployed-only
  today, 31 lines, `paths: ["**/*.py", "**/*.ts", "**/*.tsx", "**/*.js", "**/*.swift"]` frontmatter, ordinary
  content, no special handling needed). `docs/RUNBOOK.md` Step 4's `cp staging/user/rules/*.md ~/.claude/rules/`
  glob already picks this file up with no RUNBOOK edit required — confirm this by inspection, do not edit
  RUNBOOK.md.

**Contract:** `cp -p` for all three, same direction and verification as Tasks 1-3.

**Expected (RED then GREEN):** pre-copy `diff -q` on the two modified files exits 1; `parallelization.md` does
not exist pre-copy (`[ ! -f staging/user/rules/parallelization.md ]`). Post-copy: all three `diff -q` exit 0.

**Checkpoint:**
```bash
diff -q staging/user/CLAUDE.md "$HOME/.claude/CLAUDE.md" || echo "FAIL: CLAUDE.md"
diff -q staging/user/rules/swift.md "$HOME/.claude/rules/swift.md" || echo "FAIL: swift.md"
diff -q staging/user/rules/parallelization.md "$HOME/.claude/rules/parallelization.md" || echo "FAIL: parallelization.md"
ls staging/user/rules/   # expect: parallelization.md python.md shell.md sql-migrations.md swift.md typescript-react.md web-vanilla.md
npx --yes markdownlint-cli2 "staging/user/CLAUDE.md" "staging/user/rules/*.md"   # not covered by the
                                                                                    # staging/plugin/skills ignore;
                                                                                    # expect exit 0
for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done   # 5 green, unchanged
```
If the markdownlint run reports failures: stop and report in the checkpoint output rather than editing content
to force a pass (this is a byte-identical mirror of live, working content — a lint failure here is more likely a
config gap than a content defect; do not alter the copied content to satisfy the linter).

---

## Task 5 — GREEN: rewrite `staging/user/settings.json` via the `jq del()` transform

**Files modified:**
- `staging/user/settings.json`

**Contract (exact command, ADR-0025 SS2.2):**
```bash
jq 'del(.model, .theme, .tui, .editorMode, .statusLine, .cleanupPeriodDays)' \
  "$HOME/.claude/settings.json" > staging/user/settings.json
```
This is **not** a `diff -q`-to-zero task — the output is deliberately not byte-identical to deployment (six keys
excluded by design). "GREEN" here means the structural assertions below all pass. Do not hand-edit the file
instead of running the command; do not strip any key beyond the six named.

**Expected (structural GREEN, no RED phase — there is no prior staged version of this exact transform to diff
against, the current staged file predates the deployed structure entirely, see ADR-0025 SS1):**

**Checkpoint:**
```bash
jq empty staging/user/settings.json && echo "OK: valid JSON"

for k in model theme tui editorMode statusLine cleanupPeriodDays; do
  jq -e "has(\"$k\")" staging/user/settings.json >/dev/null \
    && echo "FAIL: $k still present" || echo "OK: $k absent"
done   # expect 6x "OK: ... absent"

jq -e '.permissions.allow | index("mcp__*")' staging/user/settings.json >/dev/null \
  && echo "FAIL: bare mcp__* wildcard still present" || echo "OK: no bare mcp__* wildcard"
jq -e '.permissions.allow | index("mcp__plugin_context7_context7__*")' staging/user/settings.json >/dev/null \
  && echo "OK: narrowed context7 allow entry present" || echo "FAIL: narrowed entry missing"

jq -e '.permissions.deny | length >= 13' staging/user/settings.json >/dev/null \
  && echo "OK: deny list mirrors deployed breadth" || echo "FAIL: deny list too short"

diff <(jq -S 'del(.model,.theme,.tui,.editorMode,.statusLine,.cleanupPeriodDays)' "$HOME/.claude/settings.json") \
     <(jq -S '.' staging/user/settings.json) \
  && echo "OK: transform matches deployed exactly, minus the 6 excluded keys"

grep -c '"PreToolUse"\|"PostToolUse"\|"SessionStart"\|"SessionEnd"\|"Stop"\|"UserPromptSubmit"' staging/user/settings.json
  # expect all 6 hook events present (mirrors the grown live hooks wiring)

for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done   # 5 green, unchanged
```

**Security due-diligence (repo `CLAUDE.md` invariant — never commit secrets):** visually confirm the transformed
file contains no literal API key, token, or credential value before it is staged. Expected: none — the deployed
file's only token-like reference is the `env` object's model-identifier strings and an `ENABLE_CLAUDEAI_MCP_SERVERS`
boolean flag, no secret material. State this confirmation explicitly in the task report.

---

## Task 6 — GREEN: extend PAIRS for `goal-loop` and `research-prompt`

**Files modified:**
- `staging/sync-to-claude.sh` — append 2 lines inside the existing `PAIRS="..."` block, after the current last
  entry (`plugin/skills/find-skills/SKILL.md|skills/find-skills/SKILL.md`), before the closing `"`:
```
plugin/skills/goal-loop/SKILL.md|skills/goal-loop/SKILL.md
plugin/skills/research-prompt/SKILL.md|skills/research-prompt/SKILL.md
```
Do not reorder, edit, or remove any of the existing 105 lines (ADR-0024's append-only discipline, continued).
Do not add PAIRS entries for any other file — see ADR-0025 SS2.3 for why the seven skills refreshed in Task 2
intentionally get none here.

**Contract:** both `staging/plugin/skills/goal-loop/SKILL.md` and `staging/plugin/skills/research-prompt/SKILL.md`
already exist (untouched by this plan, single-file directories, no `scripts/`/`tests/`) — this task only wires
their existing content into the sync table, it does not create or modify skill content.

**Expected:** `pairs-completeness.test.sh` count goes from `PASS=105 FAIL=0` to `PASS=107 FAIL=0`.
`sync-to-claude.sh`'s dry run prints exactly two `== NEW:` blocks (for these two files — expected and correct,
since neither has a deployed counterpart yet; this is the one place in this whole plan where `== NEW:` is the
right signal, not a red flag) and **no** `== CHANGED:` lines anywhere (confirms Tasks 1-5 did not regress any of
the other 105 already-covered files).

**Checkpoint:**
```bash
bash staging/plugin/scripts/tests/pairs-completeness.test.sh   # PASS=107 FAIL=0
bash staging/sync-to-claude.sh 2>&1 | tee /tmp/sync-dry-run.txt
grep -c "^== NEW:" /tmp/sync-dry-run.txt    # expect 2
grep -c "^== CHANGED:" /tmp/sync-dry-run.txt   # expect 0 -- any nonzero value means a Task 1-5 refresh does not
                                                  # actually match deployment; stop and re-check that file
for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done   # 6 green now (5 unchanged + pairs count bump)
```

---

## Task 7 — GREEN: retire `project-bootstrap` and reconcile the two blueprint lines

**Files deleted:**
- `staging/plugin/skills/project-bootstrap/` (contains only `SKILL.md` — confirm with `find
  staging/plugin/skills/project-bootstrap -type f` before deleting, expect exactly one file; if anything else is
  found, stop and report rather than deleting).

**Files modified:**
- `docs/vibe-coding-system.md` — three edits, in this exact order:

**Edit 1 (line 2282), before:**
```
**When Stefano has field-tested the 7 custom skills from sec. 8.3** (interview-driver, adr-writer, claude-md-generator, swift-vibe, fastapi-react-vibe, code-review-checklist, project-bootstrap), he can package them into a `stefano-vibe-coding` plugin (skills + agents) and share it via a private GitHub repo. Advantage: versioned, updatable, reusable.
```
**after:**
```
**When Stefano has field-tested the 6 custom skills from sec. 8.3** (interview-driver, adr-writer, claude-md-generator, swift-vibe, fastapi-react-vibe, code-review-checklist), he can package them into a `stefano-vibe-coding` plugin (skills + agents) and share it via a private GitHub repo. Advantage: versioned, updatable, reusable.
```

**Edit 2 (line 2297), before:**
```
- [ ] Create custom skills in `~/.claude/skills/` (`interview-driver`, `adr-writer`, `claude-md-generator`, `swift-vibe`, `fastapi-react-vibe`, `code-review-checklist`, `project-bootstrap`) using `skill-creator`
```
**after:**
```
- [ ] Create custom skills in `~/.claude/skills/` (`interview-driver`, `adr-writer`, `claude-md-generator`, `swift-vibe`, `fastapi-react-vibe`, `code-review-checklist`) using `skill-creator`
```

**Edit 3 — new changelog block**, inserted immediately after line 421 (the blank line ending the "`### Audit
2026-07-09 (loop taxonomy: `/loop`, `/schedule`, Routines)`" block) and before line 423
("`### Update 2026-06-23 (workflow model pinning)`"), matching the document's convention of appending each new
correction after whichever entry is currently most recent:

```markdown
### Correction 2026-07-11 (project-bootstrap retired from staging)

`docs/specs/29-refresh-stale-staging-copies-from-the-de.spec.md` (issue #29, ADR-0025) confirms
`project-bootstrap` is no longer present in the deployed skill tree (`~/.claude/skills/`) and removes the
retired skill from `staging/plugin/skills/`. Two prose references are corrected here; `staging/plugin/agents/`,
the seven repo-native `SKILL.md` files, and `staging/user/` are refreshed from the deployed tree in the same
issue (staleness tracked since ADR-0022's `staging/` bridge; ADR-0024 covered the first, larger vendoring pass).

- Sec. 14 packaging note (~line 2282) now lists the 6 remaining field-tested skills from sec. 8.3
  (`interview-driver`, `adr-writer`, `claude-md-generator`, `swift-vibe`, `fastapi-react-vibe`,
  `code-review-checklist`); `project-bootstrap` dropped from both the count and the list.
- Sec. 15 installation checklist (~line 2297) drops `project-bootstrap` from the custom-skills list.
- Sec. 8.3's per-skill design catalog (~line 1650) and sec. 8.6's deployed-skills table are left untouched by
  design: 8.3 documents what was designed (historically accurate, not a live-status claim) and 8.6 already
  omits `project-bootstrap`. Also out of scope for this correction: `docs/RUNBOOK.md`'s own stale count
  comments (Steps 4, 7, 8) and the global-CLAUDE.md template at sec. 4 (~line 970), which is illustrative
  content, not this system's live configuration.
```

**Contract:** exactly these three edits to `docs/vibe-coding-system.md`. Section numbering is untouched (no
heading is added, removed, or renumbered — the new block is a `###`-level entry inside the existing `## Changes
from previous versions` section, matching every other entry's level). No other line in the file changes.

**Expected (RED then GREEN):**
- Pre-edit: `staging/plugin/skills/project-bootstrap/SKILL.md` exists; lines 2282/2297 contain `project-bootstrap`;
  no changelog block dated 2026-07-11 exists.
- Post-edit: directory gone; lines 2282/2297 (now possibly shifted by the changelog insertion — re-locate by
  content, not by fixed line number, after Edit 3) contain no `project-bootstrap`; the new changelog block exists
  once; lines ~1650 (section 8.3 catalog) and ~970 (section 4 template) still contain `project-bootstrap`,
  unchanged.

**Checkpoint:**
```bash
[ -d staging/plugin/skills/project-bootstrap ] && echo "FAIL: directory still exists" || echo "OK: directory gone"

grep -n "project-bootstrap" docs/vibe-coding-system.md
# expect exactly two remaining hits, both inside the section 8.3 catalog / section 4 template block (~line 970,
# ~1650/1654) -- zero hits in the sec. 14 packaging note or the sec. 15 installation checklist

grep -c "the 6 custom skills from sec. 8.3" docs/vibe-coding-system.md    # expect 1
grep -c "### Correction 2026-07-11 (project-bootstrap retired from staging)" docs/vibe-coding-system.md   # expect 1

npx --yes markdownlint-cli2 "docs/vibe-coding-system.md"   # not ignored, must stay exit 0
npx --yes lychee --offline --include-fragments --no-progress "docs/vibe-coding-system.md" || true
  # sanity-check no internal anchor broke; the repo's own CI link job covers this authoritatively

bash staging/plugin/scripts/tests/pairs-completeness.test.sh   # still PASS=107 FAIL=0, unaffected by this task
```

---

## Task 8 — Final verification, `SPEC.md` checkbox update, report

**Files modified:**
- `SPEC.md` — check off the success-criteria boxes that are genuinely satisfied (see mapping below); leave any
  unchecked and explain in the report if one is not met.

**`SPEC.md` success-criteria mapping (for the coder's own verification, not to be taken on faith):**
1. "Zero diff between each refreshed staged file and its deployed counterpart (minus the documented settings.json
   exclusions)" — applies to the 19 files refreshed in Tasks 1-4 plus the Task 5 `settings.json` transform (checked
   structurally, not by raw diff, per that task's own contract). Does **not** apply to `goal-loop`/`research-prompt`
   (Task 6) — they have no deployed counterpart to diff against; their correctness signal is the `== NEW:` dry-run
   output, not a diff.
2. "`grep -c PATTERN staging/plugin/agents/coder.md` returns nonzero; `grep docs/agent-notes
   staging/plugin/agents/*.md` returns nothing" — verified in Task 1's checkpoint; re-run here for the final
   report.
3. "staged commit SKILL.md contains `--autopilot`; staged interview-driver has no `disable-model-invocation`" —
   verified in Task 2's checkpoint; re-run here.
4. "project-bootstrap gone from staging and from the two blueprint lines; PAIRS covers goal-loop and
   research-prompt" — verified in Tasks 6-7's checkpoints; re-run here.

**Verify (full, repo-wide):**
```bash
for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done
  # local test-cmd, must be 6/6 green (phase1, prep, hook-probe, hook-verify-workflow, pairs-completeness PASS=107)

bash staging/sync-to-claude.sh
  # dry-run: expect exactly the 2 == NEW: blocks from Task 6, zero == CHANGED: blocks anywhere in the other 105
  # entries (confirms every Task 1-5 refresh is byte-identical to what is currently deployed)

npx --yes markdownlint-cli2 "**/*.md"   # repo-wide, matches the CI markdownlint job's own glob

git status
  # confirm the change set matches exactly: staging/plugin/agents/*.md (8), staging/plugin/skills/{commit,
  # interview-driver,adr-writer,claude-md-generator,code-review-checklist,swift-vibe,fastapi-react-vibe}/SKILL.md
  # (7), staging/plugin/scripts/{protect-files.sh,auto-format.sh} (2), staging/user/CLAUDE.md,
  # staging/user/rules/swift.md, staging/user/rules/parallelization.md (new), staging/user/settings.json,
  # staging/sync-to-claude.sh, staging/plugin/skills/project-bootstrap/ (deleted),
  # docs/vibe-coding-system.md, SPEC.md, docs/architecture/ADR-0025-*.md,
  # docs/superpowers/plans/2026-07-11-29-*.md. Nothing under ~/.claude.
```

**Report to dispatcher:**
- ADR path, spec path, plan path.
- Final PAIRS entry count (expect 107) and file-count summary (19 refreshed, 1 new, 1 transformed, 1 deleted,
  2 PAIRS-only additions, 2 blueprint lines + 1 changelog block).
- `pairs-completeness.test.sh` PASS/FAIL count.
- `sync-to-claude.sh` dry-run output verbatim (expect exactly 2 `== NEW:` blocks, 0 `== CHANGED:` blocks — paste
  it even if it is exactly as expected, so the human reviewer sees the check was actually run).
- markdownlint outcome for `staging/user/CLAUDE.md`, `staging/user/rules/*.md`, and
  `docs/vibe-coding-system.md` specifically (not covered by the existing `staging/plugin/skills` ignore).
- Explicit confirmation: zero files under `~/.claude` were created, modified, or deleted during this session.
- Explicit restatement of the `interview-driver`/`fastapi-react-vibe` `disable-model-invocation` finding
  (ADR-0025 SS1 fact 2, SS3.5) and the claude-md-generator PAIRS-gap note for issue #39 (ADR-0025 SS2.3) — both
  already documented in the ADR, restate briefly so they surface in the chain's own summary too, not only in a
  document a future reader has to go find.
- Confidence declared in chat, not in any deliverable file (repo invariant).

---

## Risk register (for the coder executing this plan)

- **Risk A — live-tree race.** `~/.claude` is Stefano's actively-used Claude Code state directory; a file could
  change between planning and a task's actual `cp`. **Mitigation:** identical to ADR-0024's Risk A — the
  per-task `diff -q` checkpoint catches this immediately; if a checkpoint fails after a copy that should have
  succeeded, re-copy that specific file and recheck before moving on.
- **Risk B — scope creep into the other 21 `staging/plugin/skills/` directories or into `docs/RUNBOOK.md` /
  `docs/GUIDA-*.md`.** Easy to "helpfully" fix an adjacent stale comment noticed along the way (RUNBOOK Step 4's
  rules-file list, Step 7's "7 folders," Step 8's "7 custom skills" — all genuinely stale, all explicitly out of
  this issue's SPEC scope per ADR-0025 SS2.4/SS3.4). **Mitigation:** Pre-flight constraints' do-not-touch list is
  explicit; note any such observation in the final report instead of acting on it.
- **Risk C — silently widening PAIRS beyond the two named entries**, e.g. "since we're refreshing these seven
  skills anyway, might as well add PAIRS entries for them too." **Mitigation:** ADR-0025 SS2.3/SS3.2 record why
  this is deliberately out of scope (already reachable via RUNBOOK's bulk path; issue #39 will need its own entry
  for `claude-md-generator` specifically) — Task 6 is the only task that touches `sync-to-claude.sh`'s PAIRS data,
  and it adds exactly two lines.
- **Risk D — treating the `interview-driver`/`fastapi-react-vibe` `disable-model-invocation` removal as a mistake
  to correct rather than a deployed fact to mirror.** Tempting, given the blueprint's own text calls the missing
  flag a "live trap." **Mitigation:** SPEC's success criterion is explicit and this issue's scope is mechanical
  mirroring only (ADR-0025 SS3.5) — mirror it, flag it loudly in the report (Task 8), do not silently diverge from
  either SPEC or deployment to "fix" it here.
- **Risk E — hand-editing `staging/user/settings.json` instead of running the `jq del()` command**, especially
  if the coder wants to "just remove the six keys from the current staged file" rather than regenerating from the
  live file. That approach would preserve staging's current stale `hooks`/`permissions.deny`/`enabledPlugins`
  content, defeating the task's actual purpose. **Mitigation:** Task 5's contract is the exact command, not a
  description of the goal; run it as written, against the live file, not as an edit to the current staged file.
- **Risk F — `docs/vibe-coding-system.md` line numbers shifting.** Edit 3 (the new changelog block) is inserted
  well before lines 2282/2297, so after Edit 3 those two edits must be re-located by searching for their exact
  text (`the 7 custom skills from sec. 8.3` / `` `project-bootstrap`) using `skill-creator` ``), not by jumping to
  a fixed line number — the plan already sequences Edits 1-2 as edits against the *original* line numbers and
  Edit 3 last for exactly this reason; if the coder reorders them, redo the line-number lookup before editing.

## HITL gates

- No HITL gate inside this plan itself (auto mode, additive/mirroring changes, one directory deletion that is
  itself the retirement of an already-undeployed skill, nothing under `~/.claude` touched).
- Repo `CLAUDE.md` invariant still applies and is **not** overridden by "auto mode": commit and push remain
  human-gated. This plan produces a working tree ready for review; the commit/push/PR step that follows is a
  separate, standard chain gate, not a task in this plan.
- The `staging/plugin/skills/project-bootstrap/` deletion (Task 7) is a repository-tracked directory removal, not
  a "permanent deletion" in the global `CLAUDE.md` sense (nothing outside git history is lost, and the content is
  already gone from deployment) — it does not need a separate gate beyond the standard pre-commit review, but the
  coder's report should still call it out explicitly as a deletion, not bury it in a larger diff summary.
