# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is this repository

This is not a code project: it is the **blueprint repository** for the "Vibe Coding System for
Stefano Ferri — Multi-Agent Architecture v2.1". It contains one authoritative artifact:

- `docs/vibe-coding-system.md` (~1770 lines) — complete specification of the multi-agent Claude Code
  setup: sub-agents, agent-teams, path-scoped rules, hooks, MCP, permission modes,
  concept→code workflow. This is the **single source of truth**: every decision must be reconciled
  with this document.

The file exceeds 25k tokens: read it with `Read` using `offset`/`limit` per section, not
in one block. Sections are numbered (1–17) and cross-reference each other throughout the text.

## Inherits global rules

This project inherits `~/.claude/CLAUDE.md` (Stefano Ferri), loaded in every session.
**Do not duplicate here** the general conventions (Python/Swift/web style, git workflow,
Vibrofer terminology, safety): they already apply. This file specializes only for this repo.

## Invariant behavioral rules

From section 4 of the document, consistent with global conventions — apply here and to
any system generated from this blueprint:

- Plan mode required for any task modifying >1 file or touching production migrations/config
- Conventional Commits in English (`feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`, `perf:`)
- Never `git push --force` without explicit approval from Stefano
- Never modify migrations already applied in production
- Never disable a test to make it pass: if it needs changing, explain why in chat first
- Confidence declared in chat at end of task, **never** in deliverable files
- HITL gate always before: commit, push, deploy, DB schema changes, permanent deletions
- Language: English throughout — chat, docs, code, commits, docstrings
- Tone: direct, concise, technical — no filler

## Architecture described in the document (big picture)

Use this to orient without re-reading all 1770 lines. Details and rationale in the indicated sections.

- **Topology (sec. 2):** Orchestrator (main CLI session) → up to 4 sub-agents in parallel *within*
  the session (isolated tasks, return summary) **or** 3–5 teammates in an agent-team in *separate
  sessions* (cross-layer work, experimental, `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`). Sub-agents
  do NOT spawn other sub-agents.
- **8 custom sub-agents (sec. 3)** in `~/.claude/agents/`: `architect` (Opus, plans, ADR only),
  `coder` (Sonnet, `isolation: worktree`), `reviewer`/`tester`/`debugger`/`refactorer` (Sonnet),
  `doc-writer`/`researcher` (Haiku). Model chosen to balance cost/capability (sec. 3.9).
- **Layered extension stack:** `~/.claude/CLAUDE.md` global (identity+behavior only, <200 lines)
  → path-scoped rules in `.claude/rules/` with `paths:` frontmatter (sec. 5) → sub-agents in
  `.claude/agents/` → skills in `.claude/skills/` (sec. 8) → hooks in `settings.json` (sec. 7,
  deterministic automation) → MCP in `.mcp.json` (sec. 9). The rules pattern replaces most of
  the monolithic CLAUDE.md.
- **Permission strategy (sec. 10):** `acceptEdits` default, explicit plan mode for new features,
  allowlist for recurring commands; hook-deny rules override any permission mode (layered defense).
- **concept→code workflow (sec. 11):** interview mode (`AskUserQuestion`) → `SPEC.md` → `ARCH.md`
  (+ ADR) → project CLAUDE.md → **fresh session** → scaffold in plan mode → parallel multi-agent
  implementation (worktree) → review → commit + PR. Never mix interview and coding in the same session.
- **Identity convention (sec. 4, proposed design element):** assistant "Adriano", user "Stefano" —
  noted here as a blueprint element; effective identity is governed by `~/.claude/CLAUDE.md`.

## Working with the document

- When updating `docs/vibe-coding-system.md`: keep section numbering consistent, the
  "Changes from…" blocks (version changelog at the top), and the "Final confidence" +
  "Verified vs assumed" section at the bottom.
- Preserve the explicit **verified vs assumed** distinction: the document cites
  `code.claude.com/docs` as verified primary sources. Do not promote an assumption to
  a fact without verification and a citation.
- The checklists (sec. 15) and templates (sec. 4, 6) are intended to be copied into other
  repos: keep them self-consistent and valid as standalone documents.

## Commands

Documentation-only repository: **no** build, lint, test, or run commands.
Markdown only. Remote: `https://github.com/istefox/vibe-coding-system` (private).
The artifacts of the described system (agents, skills, hooks, rules) live in `~/.claude/`
and in the `.claude/` directories of target projects — not here.


## Rules

Nineteen invariants this repository learned by getting them wrong, each with the one-clause reason
that makes it more than a slogan and the ADR that established it. **They are stated here once.**
Until issue #380 they were restated across 95 narrative blocks — over two hundred times — which is
what made this file ~75,000 tokens in every orchestrator turn.

The narrative behind each rule, including the measured counterexample, is in
`docs/chain-decisions.md`. Read it when a rule's reason is not enough; do not restate it here.

**This list is hand-curated, and that is a limitation, not a shortcut.** "A rule" is not
mechanically enumerable — re-deriving the recurring-rule table produced different counts in both
directions depending on the needle — so nothing verifies that every rule worth promoting was
promoted. What *is* verified is that no line was lost: see ADR-0136.

1. **A needle must belong to the mechanism it asserts about, and to nothing else** ("rule 12").
   A scan whose needle is the NAME of the thing it checks matches the prose explaining it, so the
   assertion passes a file with the mechanism deleted. The only way to know is to plant it.
   → ADR-0108.
2. **An assertion nobody planted pins nothing.** Every assertion must be seen RED against a
   declared plant (`# plant:` at column 1, `plant-check.sh`). A plant that does not fire is
   evidence about the assertion, not a formality — and inspect what the plant actually produced
   before believing what it reports. → ADR-0108, ADR-0090.
3. **A prose assertion must not depend on decoration.** A clause is the same clause whether it
   wraps across lines, is backticked, is bolded, or opens a sentence. Match a flattened,
   undecorated, case-insensitive copy. Structural markers stay line-wise, because there the
   decoration *is* the structure. → ADR-0073, ADR-0076, ADR-0080, ADR-0098, ADR-0101.
4. **"Did not run" is not "found nothing".** A check that could not execute must report a state
   distinct from a clean result — conventionally exit 3. Collapsing them means an unrun check reads
   as a pass, which is how a guard stays green for months. → ADR-0046, ADR-0076.
5. **A checker and a reporter have opposite caller idioms, and the call site must say which it is.**
   A checker is branched on by exit code; a reporter always exits 0 and signals on stdout, printing
   `CLEAN` when it finds nothing. Never `[ -n "$out" ]` (true even on `CLEAN`), never
   `grep -c … || echo 0` (a two-line `0\n0` on no match — use `|| true`). → ADR-0047, ADR-0048.
6. **Extract only when two copies giving different answers would be a defect.** Copies answering
   *one* question must be extracted; copies answering *different* questions stay copies, because a
   shared source that fails disables every consumer at once. → ADR-0069, ADR-0086.
7. **Guard the denominator, not only the matches.** Zero matches can be correct; zero *candidates*
   is a broken derivation, and from outside they look identical. Every derived population carries a
   count guard. → ADR-0085.
8. **Ask which direction the check runs in.** A check that validates the entries of a list is blind
   by construction to what the list omits. Run it backwards as well. → ADR-0043.
9. **A waiver that covers nothing reads as clean.** Every exemption mechanism needs a reverse check
   asserting the exemption still has a subject, or a stale waiver survives its reason. → ADR-0081,
   ADR-0084.
10. **A floor absorbs its own plant.** An assertion of the form `>= N` against a population with
    slack still passes when its plant removes one member. Prefer a frozen per-item baseline or an
    exact count; keep a floor only as a vacuity guard, and say so at the site. → ADR-0124.
11. **A manifest field has three states, not two: ABSENT, INVALID, UNREADABLE.** Read it through
    `manifest-field-state.sh`, never a bare `m.get()`, and decide what absence means from the
    manifest's `current_step`. Two call sites may apply opposite policies to the same ABSENT state
    and both be right. → ADR-0076, ADR-0109.
12. **A cross-reference names a distinctive anchor, never a line number.** Line numbers rot, and
    they rot fastest in files being actively corrected. A `<file>:<digits>` string that is
    genuinely not a reference is declared on one line in the file carrying it:
    `xref-exempt: <token>|… — <reason ≥ 40 chars>`. → ADR-0082.
13. **Measure the premise before designing on it.** Across Phase 8, measuring changed the direction
    or the premise on seven of twelve issues. A count in an issue, an ADR or a brief is a snapshot
    of its moment: re-derive it from the files. → ADR-0121, ADR-0122.
14. **A historical record is not corrected in place.** A number inside a completed ADR or manifest
    is a correct snapshot of its day; rewriting it falsifies the record for no consumer. Record the
    correction forward, in a dated `## Correction`. → ADR-0034, ADR-0075, ADR-0078.
15. **A bash fence in a `SKILL.md` that can abort declares itself and is executed by a test.**
    `<!-- fence-contract: <id> -->`, or `<!-- fence-illustration: <reason> -->` on one line. It
    carries no positional-parameter token (skill arguments are substituted into the markdown before
    the model sees it) and it runs its body under `bash` via a quoted heredoc whose terminator sits
    at column 0 (the host shell is zsh and does not word-split). → ADR-0083, ADR-0132, ADR-0133.
16. **An instruction is not an enforcement.** Prose in a `SKILL.md` that a model is asked to follow
    is a changed failure *shape*, not a guarantee. Say which one a feature ships; a green harness
    pinning that an instruction exists is not evidence it is obeyed. → ADR-0047, ADR-0088.
17. **A producer specified in one place and consumed in another needs something checking they
    meet.** A state that nothing produces, a helper that nothing calls, a remedy naming a command
    that does not exist — all three shipped here, all three passed review. → ADR-0071, ADR-0095,
    ADR-0099.
18. **A scan is satisfied by the whole population it searches, not by the part it meant.** An
    identifier whose namespace restarts per feature, matched against a repo-wide file set, is
    satisfied by a stranger's file: measured, every one of 199 declared requirement ids passed on a
    foreign match. Rule 7 guards a denominator that collapsed to zero; this is the same failure with
    the denominator too large, and it reads as coverage just as convincingly. → ADR-0138.
19. **A deleted assertion leaves a comment where it stood, naming the issue and the ADR.** Nothing
    counts assertions between runs, and nothing usefully can: a frozen per-file baseline would need
    a deliberate bump on 95 of the last 100 harness-touching commits, which is a tax and not a
    guard. What has actually kept deletions honest is the note left behind — 3 of 3 measured drops
    carry one. Enforced for the 371 planted assertions, where `plant-check.sh` reports `NOFIRE`;
    an instruction for the other 2622 (rule 16). → ADR-0150.

## Chain decision index

One line per ADR that has a narrative block, in `docs/chain-decision-index.md`. It lives there and
not here because it is lookup data, not instruction: 117 entries, 23,751 bytes, two thirds of this
file, re-read into context on every turn to answer a question nobody was asking. The narrative
behind each entry is in `docs/chain-decisions.md`; the full record is the ADR itself.
