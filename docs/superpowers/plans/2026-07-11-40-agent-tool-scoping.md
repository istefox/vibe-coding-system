# Plan — Agent tool scoping per blueprint section 3

**Date:** 2026-07-11
**ADR:** [ADR-0036](../../architecture/ADR-0036-40-agent-tool-scoping.md)
**Spec:** [SPEC.md](../../../SPEC.md) (= `docs/specs/40-agent-tool-scoping-per-blueprint-section.spec.md`,
issue #40, confirmed byte-identical)
**Style:** TDD (red -> green -> checkpoint). Auto mode active, no intermediate HITL inside this plan;
commit/push stay HITL per repo `CLAUDE.md` invariant (see HITL gates, end of file). Four findings
across three agent files plus the blueprint document, one shared test file, one commit — ADR-0036
§2.8/§3.8 records why this plan reuses ADR-0035's exact "one RED task, N GREEN tasks, one wiring task"
sequencing: every assertion here is a static grep/positional check against frontmatter or blueprint
prose already on disk, with no runtime behavior to extract and execute.

**Task checklist (six tasks — checked off by the coder as each completes; both `concept-to-code`
SKILL.md's Step 5 pre-dispatch check and `autopilot-build` SKILL.md's Check 5 grep this file for
`- [ ]`, so every task gets one, unlike this plan's own prose elsewhere):**

- [x] Task 1 — RED: `agent-tool-scoping.test.sh` (new file, all five lettered sections at once).
- [x] Task 2 — GREEN: fix `staging/plugin/agents/architect.md` (Section A — `tools`, `effort`).
- [x] Task 3 — GREEN: fix `staging/plugin/agents/reviewer.md` (Section B — `tools`).
- [x] Task 4 — GREEN: blueprint changelog entry + sec. 3.1/3.3 deployment notes (Section D).
- [x] Task 5 — GREEN: blueprint sec. 3.8/3.9 `mcpServers` syntax correction (Section E).
- [x] Task 6 — Wire `docs-ci.yml`, full regression sweep, scope verification, SPEC.md checkboxes,
  final report.

`staging/plugin/agents/researcher.md` is **not edited** anywhere in this plan (ADR-0036 §2.6/§3.6) —
Section C's three assertions are a non-regression invariant, verified unchanged at Task 1 and again at
Task 6, with no dedicated GREEN task in between.

---

## Why every RED in this plan is genuine RED (except explicitly-labeled companions)

Every genuine-RED assertion below was traced by hand against the real, unfixed files during planning
(ADR-0036 §1 reproduces all four findings directly, with exact current content re-verified — not
assumed — including a fresh `diff` confirming `staging/` and `~/.claude/agents/` are still
byte-identical, and a fresh `grep` confirming `type: stdio` does not collide with the unrelated
`"type": "stdio"` JSON examples in blueprint sec. 9). Ten assertions are **non-regression /
invariant** companions: three (A9/A10/A11) and three (B7/B8/B9) confirm a property this plan's edits
never touch or an invariant that holds both before and after (frontmatter still parses; untouched tool
grants survive; `permissionMode:`/`effort:` lines this plan does not target stay as they are); all
three of Section C (C1/C2/C3) hold both before and after because `researcher.md` is never edited; D6 is
a cheap structural canary. The other twenty-four are genuine RED, individually re-verified below, not
assumed:

| # | Section | Assertion | Fails today because |
|---|---|---|---|
| A1 | A | `Bash(git *)` present in `tools:` | today's `tools:` line has bare `Bash`, no scoped entries |
| A2 | A | `Bash(rg *)` present | same — bare `Bash` today |
| A3 | A | `Bash(bash *)` present | does not exist in the file yet |
| A4 | A | `Bash(npx *)` present | does not exist in the file yet |
| A5 | A | `Bash(python3 *)` present | does not exist in the file yet |
| A6 | A | `Bash(shasum *)` present | does not exist in the file yet |
| A7 | A | bare unscoped `Bash,` absent from line 4 | line 4 reads `...Glob, Bash, WebSearch...` today — bare `Bash,` is present |
| A8 | A | line 6 reads exactly `effort: xhigh` | line 6 reads `effort: max` today |
| B1 | B | `Bash(git diff*)` present in `tools:` | today's `tools:` line has bare `Bash`, no scoped entries |
| B2 | B | `Bash(git log*)` present | same — bare `Bash` today |
| B3 | B | `Bash(bash *)` present | does not exist in the file yet |
| B4 | B | `Bash(awk *)` present | does not exist in the file yet |
| B5 | B | `Bash(python3 *)` present | does not exist in the file yet |
| B6 | B | bare unscoped `Bash,` absent from line 4 | line 4 reads `...Glob, Bash, LSP` today — bare `Bash,` is present |
| D1 | D | new changelog heading present | does not exist in the file yet |
| D2 | D | architect deployment-note phrase present | does not exist in the file yet |
| D3 | D | reviewer deployment-note phrase present | does not exist in the file yet |
| D4 | D | architect note positioned inside sec. 3.1 | the note anchor does not exist yet, so the positional check has nothing to compare |
| D5 | D | reviewer note positioned inside sec. 3.3 | the note anchor does not exist yet, so the positional check has nothing to compare |
| E1 | E | sec. 3.8 example includes `type: stdio` | sec. 3.8's `mcpServers:` sub-block is map-keyed, no `type:` field, today |
| E2 | E | sec. 3.8 correction-note phrase present | does not exist in the file yet |
| E3 | E | sec. 3.9 example includes `type: stdio` | sec. 3.9's duplicate example is map-keyed, no `type:` field, today |
| E4 | E | sec. 3.9 table row says `YAML list` | today's row reads `YAML map` |
| E5 | E | sec. 3.8 range contains 2 `Deployment note`/`Correction` blockquote paragraphs | only the original 2026-05-29 note exists today (count = 1) |

**Tally arithmetic (verify this explicitly at each checkpoint, do not assume):** 10 non-regression/
invariant (A9,A10,A11,B7,B8,B9,C1,C2,C3,D6) + 24 genuine RED = 34 total assertions. Task 1's checkpoint
expects `PASS=10 FAIL=24`. Task 2 flips A1-A8 (+8/-8) -> `PASS=18 FAIL=16`. Task 3 flips B1-B6 (+6/-6)
-> `PASS=24 FAIL=10`. Task 4 flips D1-D5 (+5/-5) -> `PASS=29 FAIL=5`. Task 5 flips E1-E5 (+5/-5) ->
`PASS=34 FAIL=0`. 8+6+5+5 = 24 (matches the genuine-RED count); the running total after each task is
restated in that task's own checkpoint below — confirm the actual printed line matches exactly before
moving on, per the ADR-0029/0030-style "verify against real behavior, not assumed" discipline.

## Fixture and path conventions (read once, applies to every task below)

- **File to create:** `staging/plugin/scripts/tests/agent-tool-scoping.test.sh` (new file).
- **Header, path derivation, PASS/FAIL idiom** (copy verbatim from `skill-text-corrections.test.sh`'s
  own preamble, the closest structural precedent — multi-finding, lettered sections — adapted here to
  three agent files plus the blueprint document instead of five `SKILL.md` files):
  ```bash
  #!/bin/bash
  set -u

  SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)              # staging/plugin/scripts
  STAGING=$(cd "$SCRIPTS/../.." && pwd)                    # staging/
  REPO_ROOT=$(cd "$STAGING/.." && pwd)                     # repo root
  ARCH_AGENT="$STAGING/plugin/agents/architect.md"
  REV_AGENT="$STAGING/plugin/agents/reviewer.md"
  RES_AGENT="$STAGING/plugin/agents/researcher.md"
  BLUEPRINT="$REPO_ROOT/docs/vibe-coding-system.md"

  PASS=0; FAIL=0
  ok()  { PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
  bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }
  ```
  Full header comment block (file docstring, summarizing the five sections) is specified in Task 1's
  contract — do not skip it; every existing file in this directory has one.
- **No `mktemp -d`, no `trap`, no dynamic fixtures anywhere in this file.** Every assertion here is a
  static `grep`/`sed`/`awk` check against real file content already on disk (ADR-0036 §2.8/§3.8).
- **Shared helper — define once, call from Sections A/B/C:**
  ```bash
  # frontmatter_ok <file> -- structural sanity check, not a real YAML parser: file opens with a
  # `---` line, a second `---` closing line exists, and `name:`/`description:` both appear between
  # them. Bash-only, zero dependency, matching this directory's own convention.
  frontmatter_ok() {
    _f="$1"
    [ "$(sed -n '1p' "$_f")" = "---" ] || return 1
    _close=$(awk 'NR>1 && $0=="---"{print NR; exit}' "$_f")
    [ -n "$_close" ] || return 1
    _fm=$(sed -n "2,${_close}p" "$_f")
    printf '%s\n' "$_fm" | grep -q '^name:' || return 1
    printf '%s\n' "$_fm" | grep -q '^description:' || return 1
    return 0
  }
  ```
- **Dynamic anchor resolution for every blueprint (Sections D/E) check — never a hardcoded line
  number inside the `.test.sh` file.** Tasks 4 and 5 both insert content into `docs/vibe-coding-system.md`
  earlier in the file than sec. 3.8/3.9 live, which shifts every later line number by the inserted
  count. Every Section D/E assertion therefore resolves its own anchors at run time with `grep -n
  '<content>' "$BLUEPRINT" | head -1 | cut -d: -f1`, exactly the technique
  `skill-text-corrections.test.sh`'s C6/D3 checks already use — never a bare `sed -n 'NNNp'` against a
  number written down during planning. The task contracts below give **content anchors** (exact
  heading/line text) for the same reason, not raw line numbers; re-`grep` the anchor immediately before
  each edit rather than trusting a number carried over from an earlier task or from this plan's own
  prose (PRIOR AGENT NOTES: "Post-edit line-number citations; grep derived forms of stale numbers").
- **Quoting rule for this file:** every literal pattern below contains no apostrophe and uses `-qF`
  (fixed-string) matching throughout for safety against the parentheses in `Bash(git *)`-style
  patterns, which would otherwise be interpreted as regex groups under `grep -E`/`grep` BRE. No pattern
  in this file needs double-quoting for an apostrophe (unlike ADR-0035's Section D).
- **Bash 3.2 / BSD safety (every file touched this plan):** no `${var,,}`, no `mapfile`, no `<()`, no
  `declare -A`, no GNU-only regex shorthands (`\s`, `\d`) in any `grep -E`/`awk` pattern — plain
  `grep -q`/`grep -c`/`grep -F`/`grep -n` (BRE/fixed-string) and `awk`/`sed` only, matching every
  existing file in this directory.
- **Per-task checkpoint (three checks, all must pass before moving to the next task):**
  1. `bash -n staging/plugin/scripts/tests/agent-tool-scoping.test.sh` (the only new `.sh` file this
     plan creates; the agent `.md` files and `docs/vibe-coding-system.md` are not executable scripts —
     use the content-diff/grep checks in each task instead for those).
  2. `grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' staging/plugin/scripts/tests/agent-tool-scoping.test.sh` — must be empty.
  3. `bash staging/plugin/scripts/tests/pairs-completeness.test.sh` — must stay green at `PASS=109
     FAIL=0` throughout every task in this plan; no task here adds a `PAIRS` entry (ADR-0036 §1
     Cross-check confirms none of the three agent files carries one today, for any agent).

## Pre-flight constraints

- Confirmed baseline before Task 1 (re-verified during planning, not assumed):
  `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done` -> 13/13 files green
  (this is also `.claude/test-cmd`'s literal content — confirmed by reading the file).
  `pairs-completeness.test.sh` currently reports `PASS=109 FAIL=0` (counted directly before writing
  this plan). `staging/plugin/agents/{architect,reviewer,researcher}.md` confirmed byte-identical to
  `~/.claude/agents/{architect,reviewer,researcher}.md` by `diff` (rc=0 on all three) before writing
  this plan. `docs/vibe-coding-system.md` confirmed to have exactly ten `### 3.N` subsection headings
  (3.1 through 3.10), each checked present by exact text, before writing this plan.
- Writes are confined to: `staging/plugin/scripts/tests/agent-tool-scoping.test.sh` (new),
  `staging/plugin/agents/architect.md`, `staging/plugin/agents/reviewer.md`,
  `docs/vibe-coding-system.md`, `.github/workflows/docs-ci.yml`, `SPEC.md` (checkbox updates, final
  task), `docs/architecture/` and `docs/superpowers/plans/` (already written by this ADR/plan pass).
- Do not touch: any file under `~/.claude` (the deployed copies stay defective until a separate,
  human-gated sync — same convention as ADR-0024 through ADR-0035; agent files have no
  `sync-to-claude.sh` `PAIRS` entry to `--apply` against, confirmed by grep — deployment is a manual,
  out-of-band step for these three files, unaffected by this plan), `staging/plugin/agents/researcher.md`
  (ADR-0036 §2.6/§3.6 — deliberately unedited; only verified unchanged), `staging/plugin/agents/
  {coder,tester,debugger,doc-writer,refactorer}.md` (SPEC `Out:` scope), `staging/sync-to-claude.sh`
  (no `PAIRS` entry needed — confirmed, no agent file has one, for any agent, so none is added here
  either), `staging/plugin/scripts/protect-files.sh`, `staging/plugin/scripts/
  pre-flight-pattern-enforce.sh` (read-only investigation subjects, ADR-0036 §2.3 — confirmed neither
  enforces a per-agent write path for `architect`/`reviewer`; not modified, that would be new hook
  development out of this issue's scope), `docs/manifests/2026-07-11-40-agent-tool-scoping.manifest.yml`
  (the orchestrator's responsibility to update post-dispatch, not this plan's), any historical ADR
  (immutable records; ADR-0012/0013/0016/0020/0022/0023/0024/0025/0029 are **related to, not amended
  by**, this ADR), `docs/vibe-coding-system.md` sections outside the six edit points named in Tasks 4-5
  (no other section is touched, including sec. 7.4/7.5's own admonitions, sec. 8.3's design catalog, and
  sec. 9's MCP JSON examples — all read-only precedent/collision checks during planning, not edited).
- Blueprint edits (Tasks 4-5) preserve section numbering exactly: `### 3.1` through `### 3.10` stay at
  those exact heading texts and in that exact order; only new blockquote paragraphs and one narrow,
  in-place YAML/table-cell correction are added, no heading is renumbered, added, or removed.

## Anchor invariants (HARD — must stay true after every task)

- `bash staging/plugin/scripts/tests/phase1.test.sh` -> exit 0, 30 passed 0 failed (untouched).
- `bash staging/plugin/scripts/tests/prep.test.sh` -> exit 0, 15 passed 0 failed (untouched).
- `bash staging/plugin/scripts/tests/hook-probe.test.sh` -> exit 0, 29 passed 0 failed (untouched).
- `bash staging/plugin/scripts/tests/hook-verify-workflow.test.sh` -> exit 0, 39 passed 0 failed (untouched).
- `bash staging/plugin/scripts/tests/clean-public-repo-history-safety.test.sh` -> exit 0, PASS=14 FAIL=0 (untouched).
- `bash staging/plugin/scripts/tests/concept-to-code-bsd-autopilot-gates.test.sh` -> exit 0, PASS=17 FAIL=0 (untouched).
- `bash staging/plugin/scripts/tests/concept-to-code-manifest-helpers-guards.test.sh` -> exit 0, PASS=21 FAIL=0 (untouched).
- `bash staging/plugin/scripts/tests/scope-guards.test.sh` -> exit 0, PASS=18 FAIL=0 (untouched).
- `bash staging/plugin/scripts/tests/refactor-snapshot-deep-refactor.test.sh` -> exit 0, PASS=19 FAIL=0 (untouched).
- `bash staging/plugin/scripts/tests/claude-md-slim-content-union-whole-line.test.sh` -> exit 0, PASS=11 FAIL=0 (untouched).
- `bash staging/plugin/scripts/tests/hook-hardening.test.sh` -> exit 0, PASS=6 FAIL=0 (untouched).
- `bash staging/plugin/scripts/tests/skill-text-corrections.test.sh` -> exit 0, PASS=24 FAIL=0 (untouched).
- `bash staging/plugin/scripts/tests/pairs-completeness.test.sh` -> exit 0 throughout; `PASS=109
  FAIL=0` never changes (no task in this plan adds a `PAIRS` entry).
- `diff staging/plugin/agents/researcher.md <(git show HEAD:staging/plugin/agents/researcher.md)` ->
  no output, every task (file never edited).
- `git status` shows changes only under the Pre-flight "writes are confined to" list. Nothing under
  `~/.claude` is ever touched.

---

## Task 1 — RED: `agent-tool-scoping.test.sh` (new file, all five lettered sections at once)

- [ ] Create `staging/plugin/scripts/tests/agent-tool-scoping.test.sh` with the file header, the shared
  preamble and `frontmatter_ok` helper ("Fixture and path conventions" above), and all five sections'
  34 assertions in one pass.

**Files modified:**
- `staging/plugin/scripts/tests/agent-tool-scoping.test.sh` (new).

**Contract — file docstring (top of file, immediately after the shebang, before `set -u`):**
```bash
# agent-tool-scoping test harness (ADR-0036) -- four frontmatter defects from the audit (SPEC.md /
# issue #40) across architect.md, reviewer.md, researcher.md, and docs/vibe-coding-system.md sec. 3:
#   Section A -- architect.md: unrestricted Bash scoped to Bash(git *)/Bash(rg *) (blueprint,
#     restored) plus four verification-tool entries (deliberate widening, ADR-0036 SS2.1); effort:
#     max corrected to effort: xhigh (ADR-0036 SS2.4); permissionMode: plan deliberately NOT restored
#     (ADR-0036 SS2.2 -- verified against a live Claude Code docs constraint, not this plan's call).
#   Section B -- reviewer.md: unrestricted Bash scoped to Bash(git diff*)/Bash(git log*) (blueprint,
#     restored, still no git add/commit) plus three verification-tool entries (ADR-0036 SS2.5).
#   Section C -- researcher.md: NOT edited (ADR-0036 SS2.6/SS3.6). Non-regression invariant only --
#     confirms the file, and specifically its mcpServers-less tools: line, stays exactly as it is
#     today, both before and after every other task in this plan.
#   Section D -- docs/vibe-coding-system.md: a new dated changelog entry plus two deployment-note
#     blockquotes (sec. 3.1 architect, sec. 3.3 reviewer) recording why staging/deployed diverges from
#     the blueprint's literal example text (ADR-0036 SS2.7).
#   Section E -- docs/vibe-coding-system.md sec. 3.8/3.9: the mcpServers YAML syntax shown is
#     map-keyed with no `type:` field; current code.claude.com/docs/en/sub-agents (fetched
#     2026-07-11) documents a YAML list with an explicit `type: stdio` field. Corrected in both
#     places, plus the sec. 3.9 field-reference table cell (ADR-0036 SS2.6/SS2.7).
# Every assertion is a static grep/sed/positional check against real file content -- no mktemp -d
# fixtures, no dynamic extract-and-execute (ADR-0036 SS2.8/SS3.8). Sections D/E resolve every anchor
# dynamically with `grep -n` at run time -- never a hardcoded line number -- because Tasks 4 and 5
# insert content earlier in docs/vibe-coding-system.md than sec. 3.8/3.9 live, shifting every later
# line number.
# Zero $HOME dependency: runs identically in CI (ubuntu-latest, no ~/.claude) and locally.
# Never point any variable at $HOME/.claude/... -- that is the deployed copy, out of scope.
# Bash 3.2 clean. Run: bash agent-tool-scoping.test.sh
```

**Contract — preamble + shared helper:** exactly the block already given in "Fixture and path
conventions" above (`SCRIPTS`/`STAGING`/`REPO_ROOT`/`ARCH_AGENT`/`REV_AGENT`/`RES_AGENT`/`BLUEPRINT`,
`PASS`/`FAIL`/`ok`/`bad`, `frontmatter_ok`). Insert immediately after the docstring, before Section A.

**Contract — Section A, insert verbatim after the preamble:**
```bash
# =====================================================================================
# Section A -- architect.md: Bash scope, effort pin, permissionMode invariant
# =====================================================================================

# A1-A6 (static, genuine RED now): the six Bash entries are present in the tools: line.
sed -n '4p' "$ARCH_AGENT" | grep -qF 'Bash(git *)' \
  && ok "A1: Bash(git *) present" || bad "A1: Bash(git *) should be present"
sed -n '4p' "$ARCH_AGENT" | grep -qF 'Bash(rg *)' \
  && ok "A2: Bash(rg *) present" || bad "A2: Bash(rg *) should be present"
sed -n '4p' "$ARCH_AGENT" | grep -qF 'Bash(bash *)' \
  && ok "A3: Bash(bash *) present" || bad "A3: Bash(bash *) should be present"
sed -n '4p' "$ARCH_AGENT" | grep -qF 'Bash(npx *)' \
  && ok "A4: Bash(npx *) present" || bad "A4: Bash(npx *) should be present"
sed -n '4p' "$ARCH_AGENT" | grep -qF 'Bash(python3 *)' \
  && ok "A5: Bash(python3 *) present" || bad "A5: Bash(python3 *) should be present"
sed -n '4p' "$ARCH_AGENT" | grep -qF 'Bash(shasum *)' \
  && ok "A6: Bash(shasum *) present" || bad "A6: Bash(shasum *) should be present"

# A7 (static, genuine RED now): no bare, unscoped Bash token remains on the tools: line.
if sed -n '4p' "$ARCH_AGENT" | grep -qF 'Bash,'; then
  bad "A7: bare unscoped 'Bash,' is still present on the tools: line"
else
  ok "A7: bare unscoped 'Bash,' is gone from the tools: line"
fi

# A8 (static, genuine RED now): the effort line reads exactly 'effort: xhigh'.
[ "$(sed -n '6p' "$ARCH_AGENT")" = "effort: xhigh" ] \
  && ok "A8: effort line reads exactly 'effort: xhigh'" \
  || bad "A8: effort line should read exactly 'effort: xhigh'"

# A9 (static, invariant -- true both before and after, this plan never adds the field): no
# permissionMode: line anywhere in the file (ADR-0036 SS2.2 -- deliberately not restored).
if grep -q '^permissionMode:' "$ARCH_AGENT"; then
  bad "A9: permissionMode: should not be present (ADR-0036 SS2.2)"
else
  ok "A9: permissionMode: is absent, as decided (ADR-0036 SS2.2)"
fi

# A10 (static, non-regression companion, already passing today): frontmatter still parses.
frontmatter_ok "$ARCH_AGENT" && ok "A10: architect frontmatter still parses" \
  || bad "A10: architect frontmatter should still parse"

# A11 (static, non-regression companion, already passing today): non-Bash tool grants survive the
# tools: line rewrite (Write and both context7 tool names).
if sed -n '4p' "$ARCH_AGENT" | grep -qF 'Write' \
   && sed -n '4p' "$ARCH_AGENT" | grep -qF 'mcp__plugin_context7_context7__resolve-library-id' \
   && sed -n '4p' "$ARCH_AGENT" | grep -qF 'mcp__plugin_context7_context7__query-docs'; then
  ok "A11: Write and both context7 tools still present on the tools: line"
else
  bad "A11: Write and both context7 tools should still be present on the tools: line"
fi
```

**Contract — Section B, insert verbatim after Section A:**
```bash
# =====================================================================================
# Section B -- reviewer.md: Bash scope
# =====================================================================================

# B1-B5 (static, genuine RED now): the five Bash entries are present in the tools: line.
sed -n '4p' "$REV_AGENT" | grep -qF 'Bash(git diff*)' \
  && ok "B1: Bash(git diff*) present" || bad "B1: Bash(git diff*) should be present"
sed -n '4p' "$REV_AGENT" | grep -qF 'Bash(git log*)' \
  && ok "B2: Bash(git log*) present" || bad "B2: Bash(git log*) should be present"
sed -n '4p' "$REV_AGENT" | grep -qF 'Bash(bash *)' \
  && ok "B3: Bash(bash *) present" || bad "B3: Bash(bash *) should be present"
sed -n '4p' "$REV_AGENT" | grep -qF 'Bash(awk *)' \
  && ok "B4: Bash(awk *) present" || bad "B4: Bash(awk *) should be present"
sed -n '4p' "$REV_AGENT" | grep -qF 'Bash(python3 *)' \
  && ok "B5: Bash(python3 *) present" || bad "B5: Bash(python3 *) should be present"

# B6 (static, genuine RED now): no bare, unscoped Bash token remains, and no git add/commit/push
# entry was introduced (reviewer must stay read-only-git -- ADR-0036 SS2.5).
if sed -n '4p' "$REV_AGENT" | grep -qF 'Bash,'; then
  bad "B6: bare unscoped 'Bash,' is still present on the tools: line"
elif sed -n '4p' "$REV_AGENT" | grep -qE 'Bash\(git (add|commit|push)'; then
  bad "B6: a mutating git entry (add/commit/push) must not be present"
else
  ok "B6: bare unscoped 'Bash,' is gone and no mutating git entry was introduced"
fi

# B7 (static, non-regression companion, already passing today): LSP tool grant survives.
sed -n '4p' "$REV_AGENT" | grep -qF 'LSP' \
  && ok "B7: LSP tool still present on the tools: line" \
  || bad "B7: LSP tool should still be present on the tools: line"

# B8 (static, non-regression companion, already passing today): frontmatter still parses.
frontmatter_ok "$REV_AGENT" && ok "B8: reviewer frontmatter still parses" \
  || bad "B8: reviewer frontmatter should still parse"

# B9 (static, non-regression companion, already passing today): effort: high is untouched (this
# finding is Bash-scope only -- ADR-0036 names no reviewer effort change).
[ "$(sed -n '6p' "$REV_AGENT")" = "effort: high" ] \
  && ok "B9: effort line still reads 'effort: high' (untouched)" \
  || bad "B9: effort line should still read 'effort: high' (untouched)"
```

**Contract — Section C, insert verbatim after Section B:**
```bash
# =====================================================================================
# Section C -- researcher.md: non-regression invariant only (file is never edited)
# =====================================================================================

# C1 (static, invariant -- true both before and after): no mcpServers: block in the live file
# (ADR-0036 SS2.6 -- deliberately not deployed pending a live smoke test).
if grep -q '^mcpServers:' "$RES_AGENT"; then
  bad "C1: mcpServers: should not be present in researcher.md (ADR-0036 SS2.6)"
else
  ok "C1: mcpServers: is absent, as decided (ADR-0036 SS2.6)"
fi

# C2 (static, invariant -- true both before and after): the tools: line is byte-identical to today.
[ "$(sed -n '4p' "$RES_AGENT")" = "tools: Read, Grep, Glob, WebSearch, WebFetch, mcp__plugin_context7_context7__resolve-library-id, mcp__plugin_context7_context7__query-docs" ] \
  && ok "C2: researcher tools: line is unchanged" \
  || bad "C2: researcher tools: line should be unchanged"

# C3 (static, non-regression companion, already passing today): frontmatter still parses.
frontmatter_ok "$RES_AGENT" && ok "C3: researcher frontmatter still parses" \
  || bad "C3: researcher frontmatter should still parse"
```

**Contract — Section D, insert verbatim after Section C:**
```bash
# =====================================================================================
# Section D -- blueprint: changelog entry + sec. 3.1/3.3 deployment notes
# =====================================================================================

# D1 (static, genuine RED now): the new changelog heading is present.
grep -qF '### Correction 2026-07-11 (issue #40, agent tool scoping reconciliation)' "$BLUEPRINT" \
  && ok "D1: issue #40 changelog heading is present" \
  || bad "D1: issue #40 changelog heading should be present"

# D2 (static, genuine RED now): the architect deployment-note phrase is present.
grep -qF 'the deployed/staging `architect.md` widens' "$BLUEPRINT" \
  && ok "D2: architect deployment note is present" \
  || bad "D2: architect deployment note should be present"

# D3 (static, genuine RED now): the reviewer deployment-note phrase is present.
grep -qF 'the deployed/staging `reviewer.md` keeps' "$BLUEPRINT" \
  && ok "D3: reviewer deployment note is present" \
  || bad "D3: reviewer deployment note should be present"

# D4 (static, genuine RED now, positional): the architect note sits inside sec. 3.1, between the
# "### 3.1 architect" and "### 3.2 coder" headings.
_l31=$(grep -nF '### 3.1 architect' "$BLUEPRINT" | head -1 | cut -d: -f1)
_l32=$(grep -nF '### 3.2 coder' "$BLUEPRINT" | head -1 | cut -d: -f1)
_lnote_a=$(grep -nF 'the deployed/staging `architect.md` widens' "$BLUEPRINT" | head -1 | cut -d: -f1)
if [ -n "$_l31" ] && [ -n "$_l32" ] && [ -n "$_lnote_a" ] \
   && [ "$_lnote_a" -gt "$_l31" ] && [ "$_lnote_a" -lt "$_l32" ]; then
  ok "D4: architect deployment note sits within sec. 3.1"
else
  bad "D4: architect deployment note should sit within sec. 3.1 (3.1=$_l31, note=$_lnote_a, 3.2=$_l32)"
fi

# D5 (static, genuine RED now, positional): the reviewer note sits inside sec. 3.3, between the
# "### 3.3 reviewer" and "### 3.4 tester" headings.
_l33=$(grep -nF '### 3.3 reviewer' "$BLUEPRINT" | head -1 | cut -d: -f1)
_l34=$(grep -nF '### 3.4 tester' "$BLUEPRINT" | head -1 | cut -d: -f1)
_lnote_r=$(grep -nF 'the deployed/staging `reviewer.md` keeps' "$BLUEPRINT" | head -1 | cut -d: -f1)
if [ -n "$_l33" ] && [ -n "$_l34" ] && [ -n "$_lnote_r" ] \
   && [ "$_lnote_r" -gt "$_l33" ] && [ "$_lnote_r" -lt "$_l34" ]; then
  ok "D5: reviewer deployment note sits within sec. 3.3"
else
  bad "D5: reviewer deployment note should sit within sec. 3.3 (3.3=$_l33, note=$_lnote_r, 3.4=$_l34)"
fi

# D6 (static, non-regression companion, already passing today): sec. 3.10's heading, the last of the
# ten 3.N subsections, still exists -- cheap canary that section numbering survives every edit.
grep -qF '### 3.10 Cost model' "$BLUEPRINT" \
  && ok "D6: sec. 3.10 Cost model heading still present (numbering canary)" \
  || bad "D6: sec. 3.10 Cost model heading should still be present"
```

**Contract — Section E, insert verbatim after Section D:**
```bash
# =====================================================================================
# Section E -- blueprint sec. 3.8/3.9: mcpServers YAML syntax correction
# =====================================================================================

# E1 (static, genuine RED now, scoped to sec. 3.8's own range): the corrected 'type: stdio' field is
# present inside sec. 3.8's researcher.md template.
_l38=$(grep -nF '### 3.8 researcher' "$BLUEPRINT" | head -1 | cut -d: -f1)
_l39=$(grep -nF '### 3.9 Agent frontmatter' "$BLUEPRINT" | head -1 | cut -d: -f1)
if [ -n "$_l38" ] && [ -n "$_l39" ] \
   && sed -n "${_l38},${_l39}p" "$BLUEPRINT" | grep -qF 'type: stdio'; then
  ok "E1: sec. 3.8 mcpServers example includes 'type: stdio'"
else
  bad "E1: sec. 3.8 mcpServers example should include 'type: stdio'"
fi

# E2 (static, genuine RED now, scoped to sec. 3.8's own range): the stacked correction note is
# present, without disturbing the original 2026-05-29 note (ADR-0036 SS2.6/SS2.7 -- stacked, not
# replaced).
if [ -n "$_l38" ] && [ -n "$_l39" ] \
   && sed -n "${_l38},${_l39}p" "$BLUEPRINT" | grep -qF 'does not match deployed or staging reality'; then
  ok "E2: sec. 3.8 correction note is present"
else
  bad "E2: sec. 3.8 correction note should be present"
fi

# E3 (static, genuine RED now, scoped to sec. 3.9's own range): the corrected 'type: stdio' field is
# present inside sec. 3.9's illustrative duplicate example.
_l310=$(grep -nF '### 3.10 Cost model' "$BLUEPRINT" | head -1 | cut -d: -f1)
if [ -n "$_l39" ] && [ -n "$_l310" ] \
   && sed -n "${_l39},${_l310}p" "$BLUEPRINT" | grep -qF 'type: stdio'; then
  ok "E3: sec. 3.9 duplicate example includes 'type: stdio'"
else
  bad "E3: sec. 3.9 duplicate example should include 'type: stdio'"
fi

# E4 (static, genuine RED now, scoped to sec. 3.9's own range): the field-reference table row for
# mcpServers now says 'YAML list', matching the corrected example beneath it.
if [ -n "$_l39" ] && [ -n "$_l310" ] \
   && sed -n "${_l39},${_l310}p" "$BLUEPRINT" | grep -qF 'YAML list'; then
  ok "E4: sec. 3.9 table row says 'YAML list'"
else
  bad "E4: sec. 3.9 table row should say 'YAML list'"
fi

# E5 (static, genuine RED now, scoped to sec. 3.8's own range): exactly two deployment-note/
# correction blockquote paragraphs exist in sec. 3.8 (the original 2026-05-29 note, preserved, plus
# the new 2026-07-11 correction stacked after it) -- confirms "stacked, not replaced".
if [ -n "$_l38" ] && [ -n "$_l39" ]; then
  _cnt=$(sed -n "${_l38},${_l39}p" "$BLUEPRINT" | grep -cE '^> \*\*(Deployment note|Correction)')
  [ "$_cnt" -eq 2 ] && ok "E5: sec. 3.8 has exactly 2 stacked note paragraphs" \
    || bad "E5: sec. 3.8 should have exactly 2 stacked note paragraphs, found $_cnt"
else
  bad "E5: could not resolve sec. 3.8/3.9 anchors"
fi
```

**Contract — file footer, insert verbatim after Section E:**
```bash
printf '\nPASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
```

**Expected now (RED):** `PASS=10 FAIL=24` (see "Why every RED in this plan is genuine RED" table above
for the full per-assertion breakdown).

**Checkpoint:**
```bash
bash -n staging/plugin/scripts/tests/agent-tool-scoping.test.sh
bash staging/plugin/scripts/tests/agent-tool-scoping.test.sh
# expect: PASS=10 FAIL=24
bash staging/plugin/scripts/tests/pairs-completeness.test.sh
# expect: PASS=109 FAIL=0 (unchanged -- Task 1 adds no PAIRS entry, only the test file)
```

---

## Task 2 — GREEN: fix `staging/plugin/agents/architect.md` (Section A — `tools`, `effort`)

- [ ] Replace line 4 (`tools:`) and line 6 (`effort:`) with the widened/corrected values. No other
  line in the file changes.

**Files modified:**
- `staging/plugin/agents/architect.md`

**Contract — replace line 4 in full with:**
```
tools: Read, Grep, Glob, Bash(git *), Bash(rg *), Bash(bash *), Bash(npx *), Bash(python3 *), Bash(shasum *), WebSearch, WebFetch, Write, mcp__plugin_context7_context7__resolve-library-id, mcp__plugin_context7_context7__query-docs
```

**Contract — replace line 6 in full with:**
```
effort: xhigh
```

Lines 1-3, 5, 7-8 (the rest of the frontmatter) and every line of the body (Core Responsibilities
through Edge Cases) are byte-identical to today — this is a two-line change inside the frontmatter
block only. Do **not** add a `permissionMode:` line (ADR-0036 §2.2 — deliberate, not an omission).

**Expected (GREEN):** A1-A8 pass; A9, A10, A11 unchanged (were already passing).

**Checkpoint:**
```bash
bash staging/plugin/scripts/tests/agent-tool-scoping.test.sh
# expect: PASS=18 FAIL=16 (Section A complete: 11/11; Sections B/D/E not yet added)
diff <(git show HEAD:staging/plugin/agents/architect.md) staging/plugin/agents/architect.md
# manually confirm: only lines 4 and 6 changed
bash staging/plugin/scripts/tests/pairs-completeness.test.sh
# expect: PASS=109 FAIL=0 (unchanged)
```

---

## Task 3 — GREEN: fix `staging/plugin/agents/reviewer.md` (Section B — `tools`)

- [ ] Replace line 4 (`tools:`) with the widened value. No other line in the file changes.

**Files modified:**
- `staging/plugin/agents/reviewer.md`

**Contract — replace line 4 in full with:**
```
tools: Read, Grep, Glob, Bash(git diff*), Bash(git log*), Bash(bash *), Bash(awk *), Bash(python3 *), LSP
```

Every other line (frontmatter and body) is byte-identical to today — a one-line change.

**Expected (GREEN):** B1-B6 pass; B7, B8, B9 unchanged (were already passing).

**Checkpoint:**
```bash
bash staging/plugin/scripts/tests/agent-tool-scoping.test.sh
# expect: PASS=24 FAIL=10 (Sections A+B complete: 11+9=20 of 20; Sections D/E not yet added)
diff <(git show HEAD:staging/plugin/agents/reviewer.md) staging/plugin/agents/reviewer.md
# manually confirm: only line 4 changed
bash staging/plugin/scripts/tests/pairs-completeness.test.sh
# expect: PASS=109 FAIL=0 (unchanged)
```

---

## Task 4 — GREEN: blueprint changelog entry + sec. 3.1/3.3 deployment notes (Section D)

- [ ] Insert a new dated changelog entry after the existing two same-day corrections; insert a
  deployment-note blockquote under sec. 3.1 (architect) and under sec. 3.3 (reviewer).

**Files modified:**
- `docs/vibe-coding-system.md`

**Contract — changelog insertion.** Re-`grep -nF '### Correction 2026-07-11 (backup-before-deploy.sh retired from staging)'`
immediately before editing (do not trust a number carried over from planning). That heading's section
ends at the blank line immediately before `### Update 2026-06-23 (workflow model pinning)` — insert the
new heading and body there, i.e. immediately after that section's last line
(`` there is nothing to correct there.``) and before the blank line that precedes `### Update
2026-06-23`:

```
### Correction 2026-07-11 (issue #40, agent tool scoping reconciliation)

`docs/specs/40-agent-tool-scoping-per-blueprint-section.spec.md` (issue #40, ADR-0036) reconciles four
places where `staging/plugin/agents/{architect,reviewer,researcher}.md` (byte-identical to the deployed
`~/.claude/agents/` copies -- confirmed by diff before this correction) had drifted from sec. 3 with no
recorded reason:

- **architect Bash scope** (sec. 3.1): was fully unrestricted `Bash`; now `Bash(git *), Bash(rg *)`
  (restored, matching the example above verbatim) plus `Bash(bash *), Bash(npx *), Bash(python3 *),
  Bash(shasum *)` (a deliberate widening beyond the example, for the verification-by-execution this
  roadmap's own architect dispatches routinely use) -- see the deployment note under sec. 3.1.
- **architect `permissionMode: plan`** (sec. 3.1): was already absent from the deployed file; confirmed
  **not** restorable without breaking every unattended architect dispatch -- verified live against
  `code.claude.com/docs/en/agent-sdk/permissions` (fetched 2026-07-11), plan mode blocks all file
  writes pending manual approval regardless of allow rules, and architect's sole deliverable is writing
  the ADR and the plan. Deliberate divergence, recorded rather than silently left unexplained.
- **architect `effort`** (sec. 3.10): was `max`; restored to `xhigh` -- `max` does not persist in
  file-based agent configuration (`code.claude.com/docs/en/model-config`, fetched 2026-07-11), so the
  deployed value was very likely inert.
- **reviewer Bash scope** (sec. 3.3): was fully unrestricted `Bash`; now `Bash(git diff*), Bash(git
  log*)` (restored verbatim, still no `git add`/`git commit`) plus `Bash(bash *), Bash(awk *),
  Bash(python3 *)` for the same verify-by-execution need, narrower than architect's set since reviewer
  processes untrusted diff content -- see the deployment note under sec. 3.3.
- **researcher `mcpServers`** (sec. 3.8, sec. 3.9): the inline example was already syntactically stale
  -- current docs (`code.claude.com/docs/en/sub-agents`, fetched 2026-07-11) show a YAML **list**
  syntax with an explicit `type: stdio` field, not the map-keyed form both sections showed. Corrected
  in place in both sections. The corrected block is **not** deployed to the live `researcher.md` in
  this pass -- no live smoke test is available to confirm the resulting tool-name prefix reaches the
  agent's `tools` allowlist before trusting it unattended (same smoke-test-before-deploy posture as
  ADR-0016/ADR-0029) -- the sec. 3.8 note beneath the corrected example records this and what the
  deployed file relies on instead (the global `context7` plugin, unaffected, already working).

`staging/plugin/agents/` is **not** refreshed by this correction -- the reverse of ADR-0025's usual
direction: this time the fix lands in `staging/` first and reaches `~/.claude/` only at the next human
sync, same disclosed convention as ADR-0024 through ADR-0035.

```
(Note the trailing blank line before `### Update 2026-06-23` — preserve the existing blank-line
spacing convention between dated entries, matching the gap already present between the two existing
2026-07-11 entries.)

**Contract — sec. 3.1 deployment note.** Re-`grep -nF '### 3.2 coder'` immediately before editing.
Insert immediately before that heading (i.e., after sec. 3.1's closing ` ``` ` fence and its trailing
blank line):

```
> **Deployment note (2026-07-11, ADR-0036):** the deployed/staging `architect.md` widens `tools` beyond the two entries above -- `Bash(git *), Bash(rg *)` stay unchanged, plus `Bash(bash *), Bash(npx *), Bash(python3 *), Bash(shasum *)` for the verification-by-execution this roadmap's architect dispatches routinely use (test harness, `npx markdownlint-cli2`, frontmatter/YAML checks, content hashing) -- still far short of unrestricted Bash. `permissionMode: plan` is deliberately **not** restored: verified against `code.claude.com/docs/en/agent-sdk/permissions` (2026-07-11), plan mode blocks every file write pending manual approval "regardless of existing allow rules," and architect's only deliverable is writing the ADR and the plan -- every unattended dispatch (`autopilot-build`, `nightly-autopilot`) would stall on that gate. `effort: xhigh`, not `max` (`max` does not persist in file-based agent config -- `code.claude.com/docs/en/model-config`, 2026-07-11). `memory: project` (shown above) stays absent, superseded by ADR-0012/ADR-0013; not reintroduced. `Write` itself carries no path-scoped rule -- `code.claude.com/docs/en/tools-reference` (2026-07-11) documents path pattern matching for `Read`/`Grep`/`Edit` only, not `Write` -- the write-scope guard stays prompt-level plus the global `protect-files.sh` denylist, a disclosed residual gap. Full reasoning: ADR-0036.

```
(One single unwrapped line, matching this document's own established blockquote-paragraph convention
— e.g. the coder deployment notes at the end of sec. 3.2. The test's D2/D4 checks depend on this being
one physical line containing the exact substring `` the deployed/staging `architect.md` widens ``.)

**Contract — sec. 3.3 deployment note.** Re-`grep -nF '### 3.4 tester'` immediately before editing.
Insert immediately before that heading (i.e., after sec. 3.3's closing ` ``` ` fence and its trailing
blank line):

```
> **Deployment note (2026-07-11, ADR-0036):** the deployed/staging `reviewer.md` keeps the read-only git scope above exactly (`Bash(git diff*), Bash(git log*)` -- no `git add`/`git commit`, preserving the agent's own "never run mutating git or shell commands" invariant) and widens `tools` beyond it with `Bash(bash *), Bash(awk *), Bash(python3 *)` for the verify-by-execution capability this roadmap's reviewer dispatches and the `review-triage-fix` skill rely on -- narrower than architect's set (no `npx`, no `shasum`, no bare `git *`) since reviewer processes untrusted diff content. Full reasoning: ADR-0036.

```
(Same one-line convention; the test's D3/D5 checks depend on the exact substring `` the deployed/staging
`reviewer.md` keeps ``.)

**Expected (GREEN):** D1, D2, D3, D4, D5 pass; D6 unchanged (was already passing).

**Checkpoint:**
```bash
bash staging/plugin/scripts/tests/agent-tool-scoping.test.sh
# expect: PASS=29 FAIL=5 (Sections A+B+D complete: 11+9+6=26 of 26; Section E not yet added)
grep -c '### 3\.' docs/vibe-coding-system.md
# sanity count only -- informational, confirms nothing under sec. 3 was accidentally duplicated
bash staging/plugin/scripts/tests/pairs-completeness.test.sh
# expect: PASS=109 FAIL=0 (unchanged)
```

---

## Task 5 — GREEN: blueprint sec. 3.8/3.9 `mcpServers` syntax correction (Section E)

- [ ] Replace the map-keyed `mcpServers:` sub-block inside sec. 3.8's template with the list-keyed,
  `type: stdio` form; do the same for sec. 3.9's duplicate illustrative example; update sec. 3.9's
  table cell; stack a new correction note under sec. 3.8's existing 2026-05-29 deployment note.

**Files modified:**
- `docs/vibe-coding-system.md`

**Contract — sec. 3.8 `mcpServers:` sub-block.** Re-`grep -nF 'mcpServers:'` and confirm which match
falls inside sec. 3.8's code block (between `### 3.8 researcher` and `### 3.9 Agent frontmatter`)
immediately before editing — do not trust a number from planning or from Task 4 (Task 4 shifted every
line at or after ~line 423 downward by the size of its insertions). Replace the six lines reading:
```
mcpServers:
  context7:
    command: npx
    args:
      - -y
      - "@upstash/context7-mcp"
```
(still inside the same `` ```markdown `` fenced block, immediately before the closing `---` of that
template's frontmatter) in full with:
```
mcpServers:
  - context7:
      type: stdio
      command: npx
      args:
        - -y
        - "@upstash/context7-mcp"
```
Every other line of sec. 3.8's template (the `---`/`name:`/`description:`/`tools:`/`model:`/`effort:`
lines above it, the closing `---` and prompt body below it) is byte-identical to today.

**Contract — sec. 3.8 stacked correction note.** Re-`grep -nF '> **Deployment note (2026-05-29):**'`
immediately before editing. Insert a new blockquote paragraph immediately after that existing note (no
blank line removed, no existing text altered):

```
> **Correction (2026-07-11, ADR-0036):** the note above does not match deployed or staging reality -- no inline `mcpServers` block exists in either `~/.claude/agents/researcher.md` or `staging/plugin/agents/researcher.md` (confirmed by reading both). The syntax shown above is also stale: current `code.claude.com/docs/en/sub-agents` (2026-07-11) documents `mcpServers` as a YAML **list**, each inline entry keyed by server name with an explicit `type: stdio` field, corrected above. Not deployed to `researcher.md` in this pass -- no live smoke test is available to confirm the resulting tool-name prefix reaches the agent's `tools` allowlist before trusting it unattended (same posture as ADR-0016/ADR-0029). `researcher` currently relies entirely, and successfully, on the global `context7` plugin already installed -- unaffected by this correction.
```
(One single unwrapped line, same convention as Task 4's notes. The test's E2/E5 checks depend on this
being present as a second `` > **...`` `` paragraph in sec. 3.8's range, with the exact substring `does
not match deployed or staging reality`.)

**Contract — sec. 3.9 duplicate example.** Re-`grep -nF '# Example: researcher with inline context7'`
immediately before editing. The five lines immediately below it read:
```
mcpServers:
  context7:
    command: npx
    args:
      - -y
      - "@upstash/context7-mcp"
```
Replace in full with:
```
mcpServers:
  - context7:
      type: stdio
      command: npx
      args:
        - -y
        - "@upstash/context7-mcp"
```
The comment line above it (`# Example: researcher with inline context7 (self-contained, no plugin
dependency)`) and the closing ` ``` ` fence below it are unchanged — this is a generic syntax
illustration, independent of §2.6's researcher.md deployment decision (ADR-0036 §2.6).

**Contract — sec. 3.9 table cell.** Re-`grep -nF '| `mcpServers` | YAML map |'` immediately before
editing. Replace that exact table row in full with:
```
| `mcpServers` | YAML list | Inline MCP server definitions scoped to this agent |
```
Every other row in the table (`name`, `description`, `tools`, `model`, `effort`, `color`, `isolation`,
`memory`) is unchanged.

**Expected (GREEN):** E1, E2, E3, E4, E5 pass. Full file green: `PASS=34 FAIL=0`.

**Checkpoint:**
```bash
bash staging/plugin/scripts/tests/agent-tool-scoping.test.sh
# expect: PASS=34 FAIL=0 -- full file green (11 Section A + 9 Section B + 3 Section C + 6 Section D
# + 5 Section E = 34)
bash staging/plugin/scripts/tests/pairs-completeness.test.sh
# expect: PASS=109 FAIL=0 (unchanged)
```
**Tally check (do this arithmetic explicitly, do not assume):** Section A = 11 (A1-A11). Section B = 9
(B1-B9). Section C = 3 (C1-C3). Section D = 6 (D1-D6). Section E = 5 (E1-E5). **Total: 34 assertions,
34 passed, 0 failed** once Task 5 lands. Confirm the actual printed `PASS=`/`FAIL=` line equals this
exactly; if it does not, stop and reconcile before Task 6, do not proceed on a mismatched count.

---

## Task 6 — Wire `docs-ci.yml`, full regression sweep, scope verification, SPEC.md checkboxes, final report

- [ ] Add `agent-tool-scoping` to `docs-ci.yml`'s explicit `shell-tests` list; run the full local
  test-cmd (14/14 files green); lint the ADR with `npx markdownlint-cli2`; sweep for bash 3.2/BSD
  safety; confirm the changed-file set matches the Pre-flight "writes are confined to" list exactly;
  check off SPEC.md's satisfied success criteria; produce the final report.

**Files modified:**
- `.github/workflows/docs-ci.yml`
- `SPEC.md`

**Contract — `docs-ci.yml`, append `agent-tool-scoping` as the fourteenth entry in the `for t in ...`
list.** Re-`grep -n 'for t in '` immediately before editing (Tasks 1-5 do not touch this file, so the
line number should be unchanged from Pre-flight, but re-confirm rather than assume):
```
          for t in phase1 prep hook-probe hook-verify-workflow pairs-completeness clean-public-repo-history-safety concept-to-code-bsd-autopilot-gates concept-to-code-manifest-helpers-guards scope-guards refactor-snapshot-deep-refactor claude-md-slim-content-union-whole-line hook-hardening skill-text-corrections agent-tool-scoping; do
```

**Contract — `SPEC.md`, check off every success-criteria box genuinely satisfied (expect all 5):**
```
- [x] architect and reviewer frontmatter carry scoped Bash entries, or the ADR records the deliberate widening with a compensating control
- [x] The effort pin matches blueprint 3.10, or a deployment note in the blueprint records the divergence
- [x] researcher matches blueprint 3.8, or the 3.8 deployment note is corrected to describe plugin-tool reliance
- [x] Blueprint edits preserve section numbering and the changes-log conventions
- [x] No file under `~/.claude` modified
```

**Verify (full, repo-wide):**
```bash
for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done    # local test-cmd, 14/14 green
bash staging/plugin/scripts/tests/pairs-completeness.test.sh                       # PASS=109 FAIL=0
bash -n staging/plugin/scripts/tests/agent-tool-scoping.test.sh
grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' staging/plugin/scripts/tests/agent-tool-scoping.test.sh   # empty
grep -nF '<<<' staging/plugin/scripts/tests/agent-tool-scoping.test.sh   # empty
echo "bash 3.2 / BSD safety: clean"

npx markdownlint-cli2 --config .markdownlint-cli2.jsonc "docs/architecture/ADR-0036-40-agent-tool-scoping.md"
# expect: 0 errors attributed to this file (staging/plugin/agents is lint-exempt by config; the plan
# lives under docs/superpowers, also exempt; the ADR is the one lint-gated deliverable per SPEC)

diff <(git show HEAD:staging/plugin/agents/architect.md) staging/plugin/agents/architect.md
# manually confirm: only lines 4 and 6 changed
diff <(git show HEAD:staging/plugin/agents/reviewer.md) staging/plugin/agents/reviewer.md
# manually confirm: only line 4 changed
diff staging/plugin/agents/researcher.md <(git show HEAD:staging/plugin/agents/researcher.md)
# manually confirm: NO output -- this file is never touched by this plan
diff <(git show HEAD:docs/vibe-coding-system.md) docs/vibe-coding-system.md
# manually confirm: one new changelog entry, two new deployment-note blockquotes, one stacked
# correction note, two corrected mcpServers sub-blocks, one corrected table cell -- nothing else;
# section numbering (### 3.1 through ### 3.10) unchanged in text and order

grep -c "agent-tool-scoping" .github/workflows/docs-ci.yml   # 1, the new fourteenth entry
diff /Users/stefer/.claude/agents/architect.md staging/plugin/agents/architect.md
diff /Users/stefer/.claude/agents/reviewer.md staging/plugin/agents/reviewer.md
diff /Users/stefer/.claude/agents/researcher.md staging/plugin/agents/researcher.md
# expected: all three now show a real diff (staging fixed, deployed still defective) -- confirms the
# fix landed in staging without touching ~/.claude, matching the disclosed "deployed stays defective
# until sync" convention (read-only comparison; do not act on this diff, do not write under ~/.claude)
git status   # confirm change set matches Pre-flight "writes are confined to" list; nothing under ~/.claude
```

**Report to dispatcher (accumulate for the final report):**
- Full local `test-cmd` glob result (14/14 files green) pasted verbatim.
- `agent-tool-scoping.test.sh` final tally: `PASS=34 FAIL=0`.
- `pairs-completeness.test.sh` final tally: `PASS=109 FAIL=0` (unchanged throughout).
- `npx markdownlint-cli2` result on the ADR: 0 errors.
- Confirmation each file's diff (architect.md, reviewer.md, blueprint) touches only the regions named
  in this plan's contracts — nothing else; explicit confirmation `researcher.md` has zero diff.
- Explicit confirmation: zero files under `~/.claude` were created, modified, or deleted.
- Explicit flag for the human reviewer: the deployed copies
  (`~/.claude/agents/architect.md`, `~/.claude/agents/reviewer.md`) keep today's defects (unrestricted
  `Bash`, `effort: max` on architect) until a human manually syncs these three specific files — there is
  no `sync-to-claude.sh` `PAIRS` entry for any agent file to run `--apply` against, so this is an
  out-of-band step, not a follow-up automation gap.
- Explicit flag: `researcher.md` was deliberately left unedited (ADR-0036 §2.6/§3.6); the corrected
  `mcpServers` syntax is available in the blueprint (sec. 3.8/3.9) for a future pass once a live smoke
  test — from a context with a `Task`/`Agent` tool available — confirms the resulting tool-name prefix
  is reachable under `tools:`.
- Confidence declared in chat, not in any deliverable file (repo invariant).

---

## Risk register (for the coder executing this plan)

- **Risk A — Task 4/Task 5 line-number drift.** Task 4 inserts ~40 lines before line ~462; every
  absolute line number at or after that point (including all of sec. 3.1 through 3.10, which Task 5
  edits) shifts down by the inserted count. **Mitigation:** every contract in Tasks 4-5 gives content
  anchors (exact heading/marker text) and explicitly instructs a fresh `grep -n` immediately before
  editing, never a number carried over from planning; the test file's own D/E-section checks resolve
  every anchor dynamically at run time for the same reason (Fixture and path conventions, "Dynamic
  anchor resolution").
- **Risk B — `Bash(git *)` vs `Bash(git diff*)` space-before-`*` inconsistency being "corrected" by a
  well-meaning coder.** Blueprint's own text uses a space before `*` for architect (`Bash(git *)`) but
  not for reviewer (`Bash(git diff*)`) — this is blueprint's own pre-existing convention, not a defect
  this plan introduces or should normalize. **Mitigation:** Task 2 and Task 3's contracts give the
  exact literal replacement text for each file's line 4; a coder should paste verbatim, not "fix" the
  apparent inconsistency — doing so would silently change the matching semantics (space enforces a word
  boundary; no space also matches prefix commands like `git diff-index`), which is outside this plan's
  decided scope.
- **Risk C — E5's paragraph-count check breaking if a coder reformats the existing 2026-05-29 note
  into multiple lines while adding the new one.** The check counts lines matching `^> \*\*(Deployment
  note|Correction)` inside sec. 3.8's range and expects exactly 2. **Mitigation:** Task 5's contract is
  explicit ("no blank line removed, no existing text altered") and gives the new note as one single
  unwrapped line, matching the existing note's own one-line format; a coder who reflows either note
  across multiple lines would make E5 fail loudly rather than silently under- or over-count.
- **Risk D — A7/B6's bare-`Bash,` check false-passing if a coder leaves a trailing bare `Bash` at the
  *end* of the tools: line (no trailing comma) instead of removing it.** The check only looks for the
  literal substring `Bash,` (comma immediately after). **Mitigation:** neither target line 4 ends with
  `Bash` in this plan's contracts — `Bash(shasum *)`/`LSP` are not the final unscoped token in either
  case, and both contracts give the full literal line to paste verbatim, leaving no partial-edit path
  that could produce a trailing bare `Bash`. A11/B7's own checks (non-Bash tools survive) provide an
  independent backstop: pasting anything other than the exact contracted line changes their outcome too.
- **Risk E — the `type: stdio` scoped checks (E1/E3) accidentally matching the unrelated `"type":
  "stdio"` JSON examples in blueprint sec. 9 (~line 1789, ~1802).** Confirmed during planning that the
  literal substrings differ (`type: stdio` unquoted YAML vs. `"type": "stdio"` quoted JSON — the
  quotation mark between `type` and `:` breaks a fixed-string match either way) and that both checks
  are additionally range-scoped to sec. 3.8/3.9 only, nowhere near line ~1789. **Mitigation:** the
  double protection (distinct literal string, plus range scoping via dynamically-resolved `grep -n`
  anchors) means this risk requires two independent things to go wrong simultaneously to produce a
  false pass; documented here so a future editor of sec. 9 knows this test exists and is scoped away
  from it.
- **Risk F — scope creep into `staging/plugin/agents/researcher.md`, `staging/plugin/scripts/
  protect-files.sh`, `staging/plugin/scripts/pre-flight-pattern-enforce.sh`, or
  `docs/manifests/2026-07-11-40-agent-tool-scoping.manifest.yml`.** All four are directly discussed in
  ADR-0036 and might tempt a coder to "close the loop while in the area" (deploying the corrected
  `mcpServers` block to researcher.md; extending a hook to cover architect's write scope; advancing the
  manifest's `current_step`). **Mitigation:** Pre-flight's "do not touch" list is explicit about all
  four, with the ADR section each decision lives in; Task 6's `git status` and targeted `diff`s
  (including the explicit `diff staging/.../researcher.md <(git show HEAD:...)` expecting **no output**)
  are the automated backstop.
- **Risk G — the deployed `~/.claude/agents/` copies keep all four defects indefinitely.** Not a defect
  in this plan's own execution, but a real operational risk this plan cannot itself close — unlike the
  skill-file `PAIRS` mechanism, agent files have no incremental sync path at all today.
  **Mitigation:** flagged with explicit priority in Task 6's report, matching ADR-0024 through ADR-0035
  precedent for the equivalent "deployed stays defective until sync" disclosure.

## HITL gates

- No HITL gate inside this plan itself (auto mode; every edit is additive/corrective text inside
  frontmatter fields or existing blueprint prose, or a new, isolated hermetic test file; no destructive
  git operations; nothing in Tasks 1-5 executes against `~/.claude` or any file outside the Pre-flight
  "writes are confined to" list).
- Repo `CLAUDE.md` invariant still applies and is **not** overridden by "auto mode": commit and push
  remain human-gated, as does the eventual manual sync of the three fixed agent files into `~/.claude`
  (Risk G) — that sync is explicitly out of this plan's scope and requires its own separate human
  action, with no automated path to trigger it (unlike `sync-to-claude.sh --apply` for skill files).
- No DB schema change, no permanent deletion, no production migration in this plan — none of the
  invariant HITL triggers beyond the standard commit/push gate apply here.
