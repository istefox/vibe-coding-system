# SPEC — the Express path says No worktree isolation and the Italian guide says the opposite

Source: GitHub issue #288

## Objectives

1. Locate both statements by distinctive anchor rather than by line number, and determine which is
   true of the code today: does the Express path pass an `isolation` value on dispatch, and what
   does ADR-0068 §D7 require of both dispatch paths?
2. Make one statement, true of the code, appear in both files.
3. Add a cross-file assertion so the two cannot drift apart again, naming which side moved when it
   fails.

## Scope

In: the Express path's isolation statement in
`staging/plugin/skills/concept-to-code/SKILL.md`; the corresponding statement in
`docs/GUIDA-USO-IT.md`; whatever the Express step E2 dispatch actually passes; the cross-file
assertion.

Out: changing the Express path's dispatch behaviour, unless the measurement shows the behaviour is
what disagrees with ADR-0068 §D7. Out: the Standard and Hybrid paths' isolation contracts, which
ADR-0068 settled. Out: ADR-0068's own body, which discloses this accurately for its moment.

## Stack

Bash 3.2 (macOS-portable) shell scripts under `staging/plugin/scripts/` and
`staging/plugin/skills/*/scripts/`; Markdown SKILL.md instruction files; awk predicates; a 68-file
`*.test.sh` harness under `staging/plugin/scripts/tests/` run by `.claude/test-cmd`; GitHub Actions
CI (`ci`, `markdownlint`, `links`). No application runtime.

## Architecture

- `staging/plugin/skills/concept-to-code/SKILL.md` — the "Express path — Steps E1–E4
  (chain_path=express)" section, whose opening note reads "**No worktree isolation** — failures
  during E2 leave partial edits in the working tree. The user must `git status` and reset manually
  if needed. Known limitation (ADR-0017)." **ADR-0068's `:1849` anchor has moved** (measured near
  line 2456 at spec time); anchor on the note's distinctive text.
- `docs/GUIDA-USO-IT.md` — the Express state-machine diagram, whose E2 line reads
  `-> step_e2_execute   (dispatch coder, worktree isolation)`. Measured at spec time the same file
  says the same of Hybrid step H3 and Standard step 5, so the Express line is the one under
  question.
- `staging/plugin/skills/concept-to-code/SKILL.md` — the Express Step E2 dispatch block itself,
  which is what decides whether an `isolation` value is passed.
- `docs/architecture/ADR-0068-176-worktree-isolation-contract.md` — §D7 ("both dispatch paths pass
  isolation explicitly"), §D1 (`worktree.baseRef: "head"`), and the Consequences bullet that
  discloses this contradiction.
- `staging/plugin/scripts/tests/worktree-isolation-contract.test.sh` — the existing harness and the
  natural home for the cross-file assertion; it already derives over the staged corpus.
- `staging/plugin/scripts/tests/plant-check.sh` — the plant registry runner (ADR-0108).

## Data model

None.

## API / Interfaces

The `isolation` parameter on an Agent-tool dispatch, and `opts` on the Workflow path. ADR-0068
records that `isolation: "none"` is a value the Agent tool rejects outright and is never to be named
again, and that frontmatter never reaches the Workflow path.

## UI flows

None user-facing beyond the Express path's own emitted messages.

## Edge cases

- **Express may genuinely have no isolation.** R-03 covers this: it must then be stated as a
  deliberate decision with its reason, not left as a bare fact. ADR-0017 is cited as the origin of
  the limitation and is the place to check what was decided.
- **The Italian guide is a diagram, not prose.** A per-step parenthetical in a state-machine diagram
  is a claim about behaviour and must be treated as one; the assertion has to reach into it.
- **A cross-file assertion that names neither side is useless when it fails.** R-02 requires the
  failure message to name which side moved — the ADR-0042 shape, where a file's prose and behaviour
  disagree with no way to tell which is authoritative.
- **Anchoring on a line number rots.** ADR-0068's own disclosure did exactly that and both its
  anchors are now questionable; ADR-0082's rule applies.
- Express writes into the working tree directly, so a wrong statement here misleads about recovery
  after a failure — `git status` and a manual reset versus a worktree that can be discarded.

## Success criteria

- [ ] R-01 — one statement, true of the code, in both files.
- [ ] R-02 — a cross-file assertion so the two cannot drift apart again, naming which side moved
      when it fails.
- [ ] R-03 — if the correct answer is that Express genuinely has no isolation, that must be stated
      as a deliberate decision with its reason, not left as a bare fact.
