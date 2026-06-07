# ADR-0019 — claude-md-slim: CLAUDE.md section extraction to path-scoped rules files

**Status:** Accepted
**Date:** 2026-06-06
**Author:** istefox
**Supersedes:** none
**Superseded by:** none
**Related:** ADR-0018 (deep-refactor-skill — same skill-standalone + chain-gate pattern, bash 3.2 invariant, ok/bad harness idiom), ADR-0017 (chain-type routing Gate 0 — CLAUDE.md is loaded at every chain entry; token bloat compounds chain cost)

---

## Context

### Why CLAUDE.md token bloat matters

Every Claude Code session loads CLAUDE.md into the context window unconditionally. The global
`~/.claude/CLAUDE.md` and any project `CLAUDE.md` are always-present, regardless of what files
are in scope for the current task. This means a Swift-specific section describing `xcodebuild`
invocations burns tokens on every Python fix, and a shell-scripting section is paid for on every
TypeScript PR review. The cost is not marginal: a `CLAUDE.md` that has grown to 300+ lines over
successive feature additions can consume 3–5 k tokens per session, scaling with session count across
all projects sharing that file.

The layered extension stack described in the vibe-coding-system spec (sec. 5) already has the
correct abstraction: `.claude/rules/` files with `paths:` YAML frontmatter are loaded only when
matching files appear in context. A section about shell scripting, expressed as a `paths: ["**/*.sh"]`
rule, is zero cost on Python or Swift sessions. The problem is that no tool exists to perform this
extraction: CLAUDE.md files accumulate sections manually and are never audited for extractability.

### Why path-scoped rules are the correct solution

This is not a novel insight; it is the stated design intent of the vibe-coding-system blueprint
(sec. 5). The gap is operational: the extraction requires (a) identifying which sections are
file-pattern-specific vs. always-apply, (b) generating valid YAML frontmatter, (c) merging into
existing rules files without duplication, and (d) verifying that no content is silently dropped.
Steps (a)–(c) are mechanical enough for a keyword heuristic; step (d) requires a hard invariant.
The skill closes this operational gap without changing the architecture.

### The --global duplication problem

Many project CLAUDE.md files contain sections that partially or fully duplicate content already in
`~/.claude/CLAUDE.md`. This is natural: a user copies a convention they care about into a project
file for safety. The duplication has a cost: both copies are loaded in every session, and the project
copy does not benefit from updates to the global copy. The `--global` flag extends the extraction
analysis with a duplication scan: sections with ≥60% verbatim line overlap with the global file are
flagged as DUPLICATE and proposed for deletion from the project file (read-only on the global side).

### Settled patterns this skill inherits

The following are stable patterns in this project (5th–7th instance), not re-litigated here:

- **Single-session skill (orchestrator-only):** established in ADR-0009, ADR-0011, ADR-0018. No
  sub-agent dispatch when LLM + bash suffice. Blocking HITL gates require the orchestrator.
- **Skill-standalone + chain-gate pattern:** established in ADR-0011, ADR-0015, ADR-0018. The skill
  is invokable directly and integrated into a chain gate; both paths use identical internal behavior.
- **Backup before overwrite:** `cp file file.bak-YYYY-MM-DD` before any destructive write. Global
  CLAUDE.md safety rule and pattern from ADR-0002, ADR-0011.
- **Content-preservation invariant:** union(output) ≥ union(input). Hard gate, not advisory.
  Established as a correctness requirement for any skill that rewrites file content.
- **Bash 3.2 invariant:** all hook/skill scripts in `~/.claude/` run on bash 3.2.57 (macOS system
  shell). No associative arrays, no `mapfile`, no `${v^^}`, no here-strings (`<<<`), no process
  substitution. Temp-file + `grep` maps.
- **AskUserQuestion for HITL gates:** text-box prompts are silently bypassed in Auto mode
  (`feedback_automode-gate-bypass`). Only `AskUserQuestion` forces a pause.

---

## Decision

Introduce a new skill at `~/.claude/skills/claude-md-slim/SKILL.md` implementing a 7-step
extract-and-slim pipeline. The orchestrator (LLM) drives all steps. Four bash helper scripts
handle file I/O, section parsing, keyword classification, frontmatter validation, and the
content-preservation invariant check. A test harness covers T01–T10 with structural anchors
on SKILL.md and functional tests on the scripts using fixtures. The skill is standalone with no
chain-gate integration in v1 (no Gate insertion into concept-to-code; invoked by the user directly).

The seven key decisions are recorded below.

### D1: Single-session skill (no sub-agent dispatch)

The skill runs exclusively on the orchestrator. It never dispatches a `coder` or `refactorer`
sub-agent.

Rationale: the pipeline has two blocking HITL gates (the plan review at Step 6 and, optionally,
the --global duplicate-deletion diff). These gates require the orchestrator; a sub-agent in Auto
mode would bypass them silently. The classification task (keyword heuristic over headings/bodies)
does not require Opus-quality judgment — a deterministic keyword scan is faster and more consistent
than an LLM classification pass. The bash scripts plus the orchestrator's own Read/Write capabilities
are sufficient; no multi-file parallel execution is needed.

### D2: Keyword heuristic for extraction (not heading-only, not LLM-judged)

Section classification uses a keyword heuristic: a section is extractable if its heading or body
contains file-pattern keywords from the domain table (e.g., `*.sh`, `bash`, `zsh`, `Swift`,
`SwiftUI`, `Xcode`, `*.py`, `Python`). A section is non-extractable if it contains only global
behavioral keywords (Git, tone, security, identity, HITL, commit, "always", "never", "must") without
file-pattern anchors. A section is MIXED if it contains both.

Rationale: heading-only detection would miss sections whose heading is generic ("Environment") but
whose body is entirely Swift-specific. LLM-judged extraction would require a sub-agent dispatch,
adding latency and a non-deterministic result that changes on re-run — making the skill's output
non-reproducible for audit. The keyword heuristic is deterministic, inspectable, and fast. Its
weakness (it misses semantic duplication, e.g., two sections about "never commit secrets" phrased
differently) is acceptable in v1: the SPEC explicitly limits scope to keyword detection.

### D3: Propose-then-apply after HITL (not report-only, not two-phase with separate apply command)

The skill computes the full extraction plan (trimmed CLAUDE.md + rules file diffs), shows a unified
diff in the HITL gate, and applies on Approve. It does not offer a report-only mode, and it does not
require a second invocation to apply.

Rationale: a pure report-only mode is useful only if the user wants to review and manually apply.
But the SPEC goal is reduction without manual work — the report-only mode would shift the burden
back. A two-phase model (plan now, apply via a separate command) adds state management complexity
(where is the plan stored? is it still valid when applied?) without meaningful benefit over a single
session. The single-session propose-then-apply model is established by ADR-0009 (db-backup-guardrail),
ADR-0011 (clean-public-repo), and ADR-0018 (deep-refactor). The Reject option at the HITL gate covers
the case where the user wants to adjust the plan; re-invocation handles iteration.

### D4: Merge into existing rules files (not skip-if-exists, not create-with-suffix)

When a target rules file already exists (e.g., `.claude/rules/shell.md`), the skill appends the
new section content to it, deduplicating by exact-line match. It does not skip the extraction, and
it does not create a `.claude/rules/shell-2.md`.

Rationale: skipping would leave the CLAUDE.md section in place and defeat the extraction goal.
A suffix-numbered new file would accumulate version files over multiple runs and confuse path-scoped
loading. The correct model is a rules file per domain: all shell conventions live in `shell.md`,
all Python conventions in `python.md`. The deduplication-by-exact-line strategy avoids adding
identical lines a second time on re-run while appending genuinely new content. The content-preservation
invariant (D6) ensures no line is silently dropped during the merge.

### D5: --global flag for cross-file duplication scan (project CLAUDE.md read-only of global)

The `--global` flag enables a duplication scan comparing each project CLAUDE.md section against
`~/.claude/CLAUDE.md`. Sections with ≥60% verbatim line overlap are flagged DUPLICATE and proposed
for deletion from the project file. The global `~/.claude/CLAUDE.md` is never modified; it is
read-only in this skill.

The 60% threshold is a deliberate design choice: a lower threshold (e.g., 40%) would produce
false positives on short sections that share common phrasing without being true duplicates. A higher
threshold (e.g., 80%) would miss sections that have been slightly adapted from the global original.
60% is the SPEC value; it is not adjustable via flag in v1.

Rationale for global-as-read-only: modifying `~/.claude/CLAUDE.md` requires understanding its
role across ALL projects, not just the current one. A skill invoked from a single project context
cannot safely modify a file that affects every project. The correct place to slim the global file
is a separate invocation with `--global` scope explicitly targeting `~/.claude/` as the project root
— an extension left for v2.

### D6: Content-preservation invariant as hard gate (not best-effort)

Before showing the HITL diff, the skill validates that every non-empty, non-comment line from the
original CLAUDE.md appears verbatim in at least one output file (trimmed CLAUDE.md or a rules file).
If this invariant is violated, the plan is aborted — the diff is not shown and no files are written.
The user receives a report of which lines would be lost and is asked to re-run or report a bug.

Rationale: a soft "best-effort" preservation check that warns but proceeds would allow silent content
loss. A CLAUDE.md losing a security rule or a guardrail constraint silently is a regression that is
hard to notice post-run. The invariant is a hard gate because the cost of a false violation (aborting
a valid plan) is a re-run with diagnostics; the cost of a missed violation (silently dropping content)
is a subtle behavioral regression in every subsequent session. Asymmetric cost, hard gate.

Note: delegation notes (`<!-- domain rules moved to ... -->`) are new lines added to the trimmed
CLAUDE.md; they are not in the original and are therefore not checked by the invariant.

### D7: Backup strategy (cp .bak-YYYY-MM-DD before any write)

Before writing any output file, the skill creates `CLAUDE.md.bak-YYYY-MM-DD` via:
```bash
cp "$CLAUDE_MD" "${CLAUDE_MD}.bak-$(date +%Y-%m-%d)"
```

If a `.bak-<date>` file already exists for today, the skill aborts with an error rather than
overwriting it. Rationale: a second run on the same day would overwrite the backup with the
already-modified CLAUDE.md, making recovery impossible. The user must manually delete the existing
backup before re-running.

The `.bak-YYYY-MM-DD` pattern is assumed to be in `.gitignore` (`*.bak-*`) per the SPEC. If
`.gitignore` is absent or does not cover this pattern, the skill warns but does not block.

Only CLAUDE.md is backed up. Rules files that are created new have no pre-existing content.
Rules files that are extended (merge case) should be backed up by the orchestrator as well
(one `cp <rules-file> <rules-file>.bak-<date>` per extended file before merge). This is noted
as a SKILL.md instruction, not a script responsibility.

---

## Alternatives considered

### Alt D1a: Sub-agent dispatch for classification

The LLM classifies sections via a `researcher` or `reviewer` sub-agent invocation, returning a
structured JSON classification for each section. This allows semantic reasoning beyond keyword
matching: "this section is about Python packaging" even if it uses neither `*.py` nor `pip`.

**Rejected because:** (1) the HITL gate is blocking and requires orchestrator context; a sub-agent
cannot hold the HITL. (2) LLM classification is non-deterministic — the same CLAUDE.md produces
different classifications on successive runs, making the skill's output unpredictable and harder
to audit. (3) The SPEC explicitly restricts scope to keyword heuristics (out of scope: "Detecting
semantic duplication across sections"). The keyword approach matches the SPEC contract and is
testable with fixtures; LLM classification is not structurally testable.

### Alt D1b: Orchestrator runs classification as a pure LLM step (no sub-agent, no scripts)

The orchestrator reads the CLAUDE.md, classifies sections in-context (LLM reasoning), then plans
the extraction — no helper scripts at all.

**Rejected because:** LLM reasoning over section bodies is non-deterministic and context-dependent.
The test harness (T01–T10) requires deterministic, reproducible outcomes from the scripts. Structural
anchor tests on SKILL.md can verify that the pipeline is described correctly, but the functional
correctness of classification must be verified against fixtures with known outputs — which requires
deterministic bash scripts. Additionally, LLM reasoning on large CLAUDE.md files may fill context
before the HITL gate is reached; the scripts summarize via TSV, keeping context lean.

### Alt D2a: Heading-only keyword detection

Classification examines only the H2 heading of each section, not the body text. A section headed
`## Python Environment` is extractable; a section headed `## Environment` is not.

**Rejected because:** many sections in real CLAUDE.md files have generic headings that do not
reflect their content. A section headed `## Environment` that contains exclusively Swift/Xcode
conventions would be misclassified as non-extractable. Heading-only detection has a high false-negative
rate on the actual CLAUDE.md files this skill targets. Body keyword scanning adds one `grep` call per
section and is well within bash 3.2 capability.

### Alt D2b: Heading + full-body LLM analysis with explicit prompt per section

Each section is analyzed by a dedicated LLM call (via the orchestrator, no sub-agent) that returns
`extractable | mixed | non-extractable` with a reason. This allows nuanced judgment on ambiguous
sections.

**Rejected because:** this scales O(N) in section count: a 30-section CLAUDE.md triggers 30 LLM
calls. On long files, this approaches the context limit before the plan is even formed. The keyword
heuristic classifies all sections in a single `classify-sections.sh` pass with constant LLM overhead.
The MIXED classification path (D2) handles the ambiguous case: MIXED sections are flagged for manual
review rather than auto-extracted, giving the user the same information the LLM would provide without
the 30x overhead.

### Alt D3a: Report-only mode (extract plan presented, no apply)

The skill produces a report of what could be extracted, but never writes files. The user applies the
plan manually or via a separate `/skill claude-md-slim apply` invocation.

**Rejected because:** (1) a report-only mode shifts the burden of mechanical application back to the
user, defeating the stated goal of automated extraction after approval. (2) A separate apply command
requires persisting the plan (where? in what format?) and verifying it is still valid at apply time
(the CLAUDE.md may have changed). (3) The HITL gate at Step 6 already gives the user full control
over whether to apply; Reject exits cleanly and the plan is not applied. The Reject path is
functionally equivalent to report-only, without the state management complexity.

### Alt D3b: Two-phase with an intermediate plan file

The skill writes a `.claude/claude-md-slim-plan.json` at Step 5, shows the diff, and exits.
A second invocation reads the plan file and applies it. This separates planning from execution,
allowing the user to edit the plan manually between phases.

**Rejected because:** plan-file editing is a power-user need that can be addressed in v2 if
requested. In v1, the HITL gate + Reject loop already allows the user to say "no, but here's
what I want instead" and re-run. The plan-file approach introduces a file whose format must
be versioned and whose staleness (what if CLAUDE.md changed between plan and apply?) must be
detected. Single-session propose-then-apply avoids all of this with no functional loss for the
target use case.

### Alt D4a: Skip merge (abort if target rules file exists)

If `.claude/rules/shell.md` already exists, the skill does not touch it. The user must manually
reconcile.

**Rejected because:** many projects using the vibe-coding-system already have rules files seeded
from the project-bootstrap skill. A skip-on-exists policy would require the user to manually empty
or delete the target file before running the skill, turning a single-step automation into a
multi-step manual process. The deduplication-by-exact-line merge is safe (it can only add, never
remove content) and is verified by the content-preservation invariant.

### Alt D4b: Always create a new file with a numeric suffix

When `.claude/rules/shell.md` exists, create `.claude/rules/shell-2.md` (or `shell-slim.md`).

**Rejected because:** it undermines the path-scoped loading model. Claude Code loads all
`.claude/rules/*.md` files matching the `paths:` frontmatter glob; having both `shell.md` and
`shell-2.md` with overlapping `paths:` globs would double-load shell rules. Additionally, the
growing number of versioned files defeats the purpose of a rules directory with one file per
domain.

### Alt D5a: --global flag also modifies ~/.claude/CLAUDE.md

The skill can delete duplicated sections from the global file as well, not only from the project file.

**Rejected because:** `~/.claude/CLAUDE.md` is shared across all projects. A skill invoked from
one project context has incomplete visibility into whether a section in the global file is "truly
duplicate" across all projects using that global, or only in the current project. The risk of
silently removing a globally-needed rule is asymmetric: the harm affects all future sessions across
all projects. The correct scope for this skill is the project CLAUDE.md only. The global file
remains read-only.

### Alt D6a: Best-effort preservation with a warning

The content-preservation check emits a warning listing potentially missing lines, but proceeds to
show the HITL diff and allows the user to approve anyway.

**Rejected because:** the HITL gate is shown after a diff that the user is expected to review
quickly. A list of "potentially lost lines" buried in the diff output is easily missed. The user
who approves after seeing the warning has no way to know whether the "potentially lost" lines are
actually critical (a security guardrail) or noise (a comment). A hard abort with a diagnostic
report forces the user to make an informed decision rather than an accidental one. The invariant is
named "hard gate" in the SPEC; this ADR codifies it as such.

### Alt D7a: Timestamped backup with seconds precision (YYYY-MM-DD-HHmmss)

The backup file is named `CLAUDE.md.bak-2026-06-06-143022` to allow multiple backups per day.

**Rejected because:** the project-wide backup convention is `file.bak-YYYY-MM-DD` (established in
ADR-0002, ADR-0011 scripts, and the global CLAUDE.md safety rule). A seconds-precision variant is
inconsistent with the pattern and would not be covered by a `.gitignore` entry that matches
`*.bak-????-??-??`. The "backup file already exists" guard (abort if `.bak-<today>` exists) is the
safety mechanism for the one-per-day limit; if the user genuinely needs two runs per day, they delete
the first backup manually after verifying the run was correct.

---

## Consequences

### Positive

- **Immediate, measurable token reduction.** A CLAUDE.md that drops from 300 to 180 lines saves
  ~1.5 k tokens per session. Across 10 sessions per day, this is 15 k tokens saved — meaningful
  at Opus pricing on a Max plan.
- **Conditional loading is the correct model for file-type conventions.** Swift conventions loaded
  only on Swift sessions, Python conventions only on Python sessions. This is what path-scoped rules
  were designed for; the skill makes the migration mechanical.
- **Content-preservation invariant is structurally tested.** T04 in the harness verifies
  `content-union-check.sh` on a fixture with a deliberately missing line. The invariant is not
  advisory; the script enforces it deterministically.
- **Single-session skill with blocking HITL gate.** No content is written without user approval.
  The Reject path preserves the original CLAUDE.md exactly (no writes). The Abort path is a clean
  no-op. This makes the skill safe to invoke on any project without prior knowledge of its impact.
- **Duplicate detection (--global) surfaces hidden redundancy.** Projects that have manually
  synchronized convention notes from the global file accumulate drift: the project copy diverges
  slowly while the global copy is updated. The --global scan flags these sections for deletion,
  restoring the single-source-of-truth property.
- **Bash 3.2-clean scripts are portable.** The scripts run on the macOS system bash without any
  external dependency beyond standard POSIX tools (`grep`, `sed`, `awk`, `diff`). No `brew`, no
  Python, no Node.
- **Pattern reuse, zero blast radius.** No edits to existing agents, hooks, or chain skills. The
  only write targets are `~/.claude/skills/claude-md-slim/` (new) and the project CLAUDE.md (on
  approve). No manifest fields added; no settings changes.
- **Harness is honest.** Structural anchors on SKILL.md verify the required contracts are present
  (HITL gate, backup, content-preservation). Functional tests on scripts use fixtures with known
  outputs. The harness does not and cannot test LLM orchestrator judgment — that is the pilot.

### Negative / risks

- **Keyword heuristic has false negatives.** A section that is entirely Python-specific but whose
  heading is "Code Style" and whose body uses only colloquial language ("always use f-strings",
  "never use print for logging") will not be extracted. The user must manually extract such sections
  or rename the heading/body to include a detectable keyword. This is a known limitation of the
  SPEC's deliberate keyword-only scope.
- **MIXED sections require manual judgment.** Sections flagged MIXED (extractable content + global
  behavioral rules in the same block) are shown in the HITL diff as MANUAL flags; the skill does not
  split them automatically in v1. The user must either accept the section as non-extracted or manually
  refactor the CLAUDE.md to separate the two concerns before re-running. This is the correct tradeoff
  (auto-splitting a mixed section risks misclassifying the boundary), but it means the skill cannot
  fully slim a CLAUDE.md that has entangled sections.
- **60% duplicate threshold is a heuristic.** A section with 59% overlap is not flagged; a section
  with 61% overlap is. Short sections (≤5 lines) are sensitive to this threshold: a 5-line section
  with 3 lines shared is exactly 60%. The threshold was chosen to minimize false positives on the
  known fixture set; it may need calibration on real CLAUDE.md files after the pilot.
- **Backup-already-exists guard can block legitimate re-runs on the same day.** If the user runs
  the skill, approves, and then realizes the extraction was suboptimal and wants to re-run the same
  day, they must manually delete `CLAUDE.md.bak-<today>` first. This is intentional (protecting the
  backup from being overwritten by a second run that uses the already-modified CLAUDE.md as its
  source), but it adds friction for iterative use.
- **No chain-gate integration in v1.** The skill is not wired into concept-to-code as a gate.
  Users who want it run it manually. This is correct for a new skill that has not been piloted,
  but it means the reduction benefit is not automatic — it requires intentional user action.
- **Merge deduplication is line-exact.** If the same convention is expressed slightly differently
  in CLAUDE.md and in an existing rules file (different whitespace, reworded), both copies will
  be kept. This is safer than fuzzy-matching (which could incorrectly suppress distinct rules)
  but means the rules file may accumulate near-duplicate lines across multiple extraction runs.

### Neutral

- **No new agents, no new manifest fields.** The skill is self-contained. ADR-0016's `hook_verified`
  and ADR-0014's `.claude/test-cmd` are not read by this skill (no test command needed; the skill
  writes documentation, not code). No c2c manifest schema bump.
- **The --global flag read-only constraint is absolute.** `~/.claude/CLAUDE.md` is never modified.
  This is not a temporary limitation to be relaxed in v2 without a new ADR.
- **MIXED section flag is documented, not hidden.** The HITL diff shows MIXED sections explicitly
  with a `[MIXED — manual split required]` label. The user understands why the section is not
  extracted.
- **`section 100% extracted` edge case removes section entirely.** If a section has no non-extractable
  content, the section is fully removed from CLAUDE.md with no delegation note. This is the SPEC
  edge case; it is documented in the SKILL.md pipeline description so the user is not surprised.

---

## References

- SPEC.md: `/Users/stefanoferri/Developer/vibe-coding-system/SPEC.md` (2026-06-06)
- ADR-0018: `docs/architecture/ADR-0018-deep-refactor-skill.md` (bash 3.2 invariant, ok/bad
  harness idiom, skill-standalone pattern — 7th instance here)
- ADR-0017: `docs/architecture/ADR-0017-chain-type-routing-gate0.md` (CLAUDE.md always-loaded
  context; token cost compound at Gate 0 triage)
- ADR-0011: `docs/architecture/ADR-0011-clean-public-repo-anonymize.md` (backup-before-write
  pattern, content-preservation invariant origin, single-session + blocking HITL)
- ADR-0009: `docs/architecture/ADR-0009-db-backup-guardrail.md` (propose-then-apply after HITL
  — first instance)
- MEMORY.md `feedback_automode-gate-bypass`: only `AskUserQuestion` forces a pause in Auto mode
- MEMORY.md `feedback_bash32-constraint`: bash 3.2.57 — no assoc arrays, mapfile, ${v^^}
- vibe-coding-system.md sec. 5: path-scoped rules with `paths:` frontmatter (architectural basis)
