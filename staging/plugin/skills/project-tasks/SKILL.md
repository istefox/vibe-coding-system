---
name: project-tasks
description: Maintains a single versioned TODO.md at the project root holding open issues, work in progress, feature backlog, blockers awaiting a decision, deferred review findings and a stable project map. On each run it captures issues surfaced during the current chat session, scans the codebase for TODO/FIXME/HACK markers, reads recent git activity and review reports, deduplicates against existing entries, proposes closures for entries whose evidence is gone, and writes only after an explicit approval gate. Triggers include "project-tasks", "/project-tasks", "aggiorna il TODO", "segna gli issue aperti", "cosa resta da fare", "update the task ledger", "track this issue", and invocation from the concept-to-code or project-conductor chain before a commit. NEGATIVE - do NOT use to find new bugs (that is code-review, review-triage-fix or deep-refactor), do NOT use to fix anything (it never edits source), do NOT use for the ephemeral in-session todo list (that is the TaskCreate tool).
---

# Project Tasks

One file, `TODO.md` at the project root, is the durable memory of everything open on this
project. The in-session todo list dies with the context window; this file does not.

## Hard rules

- **Never edit source files.** This skill only reads code and writes `TODO.md`.
- **Never write before the approval gate** in Step 6. No exception, including a run that
  only proposes closures.
- **Never invent an entry.** Every entry traces to an observation: a session event, a code
  marker, a git commit, a review report, or something the user said. No evidence, no entry.
- **Never delete user text.** Hand-written entries, custom sections and free notes survive
  every run untouched.
- **Never auto-close.** A stale reference is a *proposal*; the user confirms it.
- **Stay inside the session working directory.** If the resolved project root is outside the
  CWD, stop and report the mismatch.

## Modes

| Invocation | Behaviour |
|---|---|
| `/project-tasks` | Full run: all five capture sources, Steps 1-8. |
| `/project-tasks quick` | Session capture only. Skips `scan.sh`, git and reports. Use when context is nearly full and you need the session's issues saved *now*. |
| `/project-tasks add <text>` | Appends one user-dictated entry. Shows the resulting line, no scan, no gate beyond that line. |
| `/project-tasks close <ID>` | Moves an entry to Done with today's date. |
| `/project-tasks map` | Rebuilds the Project Map section only. |

## Workflow

Copy this checklist into your reply and tick as you go:

```
- [ ] 1. Resolve project root, verify it is inside the session CWD
- [ ] 2. Read or create TODO.md, index existing entries
- [ ] 3. Run scan.sh (skipped in quick mode)
- [ ] 3b. Read the open GitHub issues (gh-issues.sh)
- [ ] 4. Capture from the current session
- [ ] 5. Reconcile: dedupe, merge, propose closures
- [ ] 6. Approval gate
- [ ] 6b. Compose the candidate ledger (ledger-merge.sh)
- [ ] 7. Write the file
- [ ] 8. Report and recommend
```

### 1. Resolve the project root

```bash
git rev-parse --show-toplevel 2>/dev/null || pwd
```

The ledger lives at `<root>/TODO.md`. If the root is not a prefix of the session working
directory, **stop** and tell the user which two paths disagree.

### 2. Read or create the ledger

Read `TODO.md` if it exists and index: every entry's ID, section, priority, text, `src:`
provenance and file reference; the header comment `<!-- project-tasks: prefix=XX lastId=N -->`;
any section the user added by hand.

If the file is absent, start from `templates/TODO.template.md`. Choose the ID prefix from the
project name: two or three uppercase letters (`vibrofer-pipeline` → `VP`, `steve-skills` → `SS`).
Once written, the prefix never changes.

The exact schema, the priority definitions and the archiving rule are in
[reference/file-format.md](reference/file-format.md). Read it before your first write on a project.

### 3. Run the scanner

```bash
bash scripts/scan.sh --root <project-root>
```

TSV on stdout: `MARKER`, `GITFILE`, `GITLOG`, `STALE`, `MAP`, `NOTE`. Exit 3 means the path is
not a project root — report it, do not work around it. A `NOTE` record about truncation must be
passed on to the user; never present a capped list as complete.

### 3b. Read the open GitHub issues

```bash
bash scripts/gh-issues.sh --ledger <project-root>/TODO.md
```

A **checker**: branch on the exit code, do not read stdout for a verdict. `scan.sh` is a reporter
and this one is not — the two idioms are opposite and mixing them is how a failure reads as a clean
run.

- **0** — `ISSUE` records on stdout, possibly zero and legitimately so.
- **3** — a `DIDNOTRUN` record naming a cause and a remedy. `gh` is absent, unauthenticated, or
  there is no reachable remote. **Pass the record through to Step 6b unchanged.** The section keeps
  the entries it already holds and gains a `DID-NOT-RUN` notice; it is never rendered empty and
  never silently skipped. Report the cause and the remedy to the user in Step 8, and carry on: the
  rest of the run does not depend on GitHub, and a project with no remote keeps a working ledger
  minus one section.
- **4** — zero open issues where the section already held entries. That is a broken derivation, not
  an empty repository. Stop and report it; do not write a ledger that empties the section.

### 4. Capture from the current session

This is the source no tool can reconstruct later, and the reason the skill exists. Re-read the
conversation so far and harvest what actually happened. The heuristics, with the phrasing that
signals each one, are in [reference/capture-sources.md](reference/capture-sources.md) — read it
on every full run.

In short, an entry is warranted when the session contains: a command that failed and was not
fixed, a red test, a stack trace, a workaround stated as temporary, scope explicitly deferred
("later", "for now", "in a second pass"), an assumption never verified, a question the user
never answered, or a decision taken without recording it in an ADR.

Do **not** create an entry for something fixed within the same session and verified.

### 5. Reconcile

For each candidate, in this order:

1. **Duplicate?** Same file plus same symptom as an existing entry → update that entry
   (refresh the line reference, raise the priority if the session proves it worse), never add
   a second one. Matching is semantic, not textual: "leaks a listener" and "listener not
   removed on retry" at the same file are one issue.
2. **New?** Assign `lastId + 1`, pick the section and the priority, attach the file reference
   and the `src:` provenance.
3. **Stale?** Each `STALE` record becomes a *proposed closure* with its reason
   (`file-missing`, `line-out-of-range`, `marker-gone`). Never closed here.
4. **Map drift?** Compare the `MAP` records against the Project Map section; propose only the
   lines that actually changed.

### 6. Approval gate

Show three tables, empty ones omitted: **Add** (ID, priority, section, one-line text, source),
**Update** (ID, what changes, why), **Close** (ID, reason). Then AskUserQuestion:

- **Approve everything (Recommended)** — when nothing is contentious;
- **Select what to write** — the user names IDs to keep or drop;
- **Cancel** — nothing is written.

Recommend "Approve everything" only when every candidate has hard evidence. If any entry rests
on an inference, put **Select what to write** first and say which entry is the doubtful one.

### 6b. Compose the candidate ledger

```bash
bash scripts/ledger-merge.sh --ledger TODO.md --issues ISSUES.tsv --manifests docs/manifests --roadmap PROJECT.md --today YYYY-MM-DD --mode MODE --proposals PROPOSALS
```

One line, no continuations: `selftest.sh` rejects a backslash anywhere in this file or its
reference pages, and a line-continuation backslash is indistinguishable from a Windows path
separator to a check that looks for the character.

A pure filter: it prints the candidate and never writes the ledger. Every path is optional and an
absent one degrades with a stated reason rather than rendering as if the derivation found nothing —
which is what lets this skill run in a project with no roadmap file, no manifests and no remote.

Exit **3** is a failed self-check, and it names what it found: an issue that would not have been
rendered, or a local id appearing twice. Never write a candidate that failed its self-check.

**The promotion gate.** On a **full** run only, `--proposals` lists the entries worth turning into
GitHub issues: every `P1`, every `src:review`, and every entry that has survived two full runs.
Never on `quick`, `add`, `close` or `map` — those modes exist to be cheap, and a promotion question
on each is the friction that stops a gate from being read. Ask once, at the Step 6 gate, and record
a decline as `promote:declined`, which is never proposed again on any later run. The skill never
opens or closes an issue itself.

**The Steps section** is a header and a case token; the lines under it are yours to write from the
feature's SPEC, plan and ADRs. One non-terminal manifest names it and reads *derived*; zero omits
the section with a stated reason; two or more name both candidates and derive nothing, because
guessing which feature is the one in flight is the ambiguity this system refuses.

### 7. Write

Rewrite `TODO.md` preserving unknown sections and hand-written text verbatim. Update
`Updated:`, bump `lastId`, move surplus Done entries into the archive block. Nothing else in
the repository is touched.

### 8. Report and recommend

Three lines maximum: how many added, updated and closed; how many P1 remain open; the single
next action worth taking. If a P1 has been open for more than 14 days, say so.

## Cadence

Run it **before `/clear`, `/compact` or closing the session** — that is the only moment where
forgetting is irreversible — and **before `/commit`**, so ledger and history agree. Also after a
review-triage-fix or deep-refactor cycle, to absorb deferred findings, and at the end of each
feature in the chain. Roughly every 45-90 minutes of active work. More often than that only
re-reads the same state.

Chain wiring, with the snippets to paste into `concept-to-code` and `project-conductor`, is in
[reference/chain-integration.md](reference/chain-integration.md).
