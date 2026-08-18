# TODO.md — schema

## Contents

- Full example
- Header comment
- Entry anatomy
- Sections
- Priorities
- IDs
- Provenance
- Archiving
- Preservation rules

## Full example

```markdown
<!-- project-tasks: prefix=VP lastId=12 -->
# PROJECT TASKS

Updated: 2026-08-04 · Open: 7 (P1: 2) · In progress: 1

## Open Issues

- [ ] `VP-011` **P1** Race condition on token refresh, two tabs desync the session — `src/auth/session.ts:88` <!-- src:session opened:2026-08-04 -->
- [ ] `VP-009` **P2** CSV parser has no test for quoted separators — `src/io/csv.ts` <!-- src:review opened:2026-07-29 -->
- [ ] `VP-004` **P2** Monkeypatch on the vendor client, remove once upstream 3.2 ships — `src/vendor/client.ts:14` <!-- src:marker opened:2026-07-21 -->

## In Progress

- [-] `VP-010` **P1** SwiftData migration — branch `feat/swiftdata` <!-- src:manual opened:2026-08-02 -->

## Backlog / To Add

- [ ] `VP-012` **P3** PDF export of the monthly report <!-- src:manual opened:2026-08-04 -->

## Blocked / Decisions Needed

- [ ] `VP-008` **P2** Where do user preferences live, UserDefaults or SwiftData? Blocks VP-010 <!-- src:session opened:2026-08-01 -->

## Project Map

- **Entry point**: `src/main.ts`
- **Modules**: `src/auth` (session, tokens) · `src/io` (CSV, PDF) · `src/vendor` (wrapped client)
- **Build & test**: `npm run build` · `npm test` (test-cmd: `npm test`)
- **Key ADRs**: ADR-0012 auth strategy · ADR-0019 local storage
- **Invariants**: no network call outside `src/vendor` · every migration is reversible

## Done

- [x] `VP-007` Fix crash on cold start (2026-08-02)
- [x] `VP-006` Pin dependency versions (2026-07-30)

<details>
<summary>Archived (older)</summary>

- [x] `VP-001` Project scaffolding (2026-07-10)

</details>
```

## Header comment

```
<!-- project-tasks: prefix=VP lastId=12 -->
```

Invisible when rendered, authoritative for the skill. `lastId` is a monotonic counter: it is
never decremented, so a manually deleted entry can never have its ID reused by a different
issue. If the header is missing, reconstruct `prefix` from the existing entries and set
`lastId` to the highest ID found.

## Entry anatomy

```
- [ ] `VP-011` **P1** <one line, what is wrong and why it matters> — `path/file.ts:88` <!-- src:session opened:2026-08-04 -->
```

- **Checkbox**: `[ ]` open, `[-]` in progress, `[x]` done. This is the [TODO.md](https://github.com/todomd/todo.md)
  convention and renders as a live checklist on GitHub.
- **ID** in backticks, always present, always immutable.
- **Priority** in bold, always present.
- **Text**: one line. Symptom plus consequence, not a title. "Token refresh races" says
  nothing; "two tabs desync the session" says what breaks. No trailing period.
- **Reference**: `` `path:line` `` when a specific place is implicated, `` `path` `` when the
  whole file is, a branch name for work in progress, nothing when the entry is a pure idea.
  The line number is best-effort and is refreshed on each run.
- **Provenance comment**: mandatory, invisible in rendering, consumed by the next run.

Anything longer than one line goes into a nested bullet under the entry. Keep it to three lines
at most: this ledger is a radar, not an issue tracker.

## Sections

| Section | Holds | Empty section |
|---|---|---|
| `Open Issues` | Bugs, defects, technical debt, deferred review and security findings | keep, write `_none_` |
| `In Progress` | What is actively being worked on right now, with the branch | keep, write `_none_` |
| `Backlog / To Add` | Features and ideas not yet started | keep, write `_none_` |
| `Blocked / Decisions Needed` | Needs a user decision or an external input before anyone can proceed | keep, write `_none_` |
| `Project Map` | The stable landmarks of the project | always populated |
| `Done` | Closed entries, most recent first | keep |

Sections stay in this order. A section the user adds by hand is kept where they put it.

## Priorities

- **P1** — breaks the main path, loses data, blocks the release, or is an unfixed security
  finding. An open P1 is a reason not to commit.
- **P2** — real defect or debt with a workaround, or missing coverage on non-trivial logic.
- **P3** — nice to have, cosmetic, opportunistic.

When the session proves an issue is worse than recorded, raise the priority and say so in the
update table. Never lower a priority without the user asking.

## IDs

Prefix: two or three uppercase letters from the project name, chosen on first write and never
changed afterwards. Number: zero-padded to three digits, `lastId + 1`, never reused.

## Provenance

`src:` marks where the entry came from, and drives deduplication and stale detection:

| Value | Meaning |
|---|---|
| `session` | Observed during a chat session: failed command, red test, stack trace, deferred scope |
| `marker` | A `TODO`/`FIXME`/`HACK`/`XXX`/`BUG` in the source. Closable when the marker is gone |
| `review` | Deferred finding from review-triage-fix, deep-refactor or security-audit |
| `git` | Inferred from history, e.g. a `revert:` with no follow-up |
| `manual` | Dictated by the user |

`opened:YYYY-MM-DD` is set once and never rewritten. It is what makes "open for 14 days"
answerable.

## Archiving

`Done` keeps the 25 most recent entries. Older ones move into the `<details>` block at the
bottom of the same file, in the same format. The project keeps exactly one ledger file: no
second file, no `docs/` spill.

## Preservation rules

On rewrite, the following survive verbatim: sections the skill does not know about, free
prose anywhere in the file, hand-written entries without an ID (leave them as they are, do
not renumber them), and any HTML comment other than the header.

If the file has drifted so far that it cannot be parsed, do not repair it silently: report
what could not be read and ask before writing.
