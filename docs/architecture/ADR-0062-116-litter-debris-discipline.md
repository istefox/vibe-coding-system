# ADR-0062 — Litter and debris discipline across agents

- **Status:** Accepted
- **Date:** 2026-07-26
- **Issue:** #116 (seventeenth feature of PROJECT.md Phase 2)
- **SPEC:** `SPEC.md` / `docs/specs/116-litter-debris-discipline.spec.md`
- **Closes:** gap **G-15** of `docs/books/INTEGRATION-REPORT-agentic-spec.md` (PARTIAL, P3).

## Context

`commit/SKILL.md:56-59` never auto-stages untracked files and lists them separately in the approval
gate, which surfaces most debris to the human. `auto-format.sh` handles formatting.

What is missing is the agent-side discipline. `coder.md` has **no cleanup instruction at all**, and
the spec's standing instruction to every agent — *leave it cleaner than you found it*, with
systematic debris removal after each task — is absent from every agent file. Temp branches are
registered and reconciled nowhere; the spec's case 3, a repository lost to a branch cleanup, turns on
exactly that.

## Decision

### D1 — A cleanup clause in the Output Format of `coder`, `debugger` and `refactorer`

Each lists every temporary file, scratch script, debug log statement and temp branch it created, and
its disposition, before reporting done.

Output Format rather than a prose instruction elsewhere in the file: it is the section an agent
actually fills in, and a requirement that is part of the deliverable gets met more often than a
request buried in guidance. This follows ADR-0035's finding that a contract belongs in the agent's
own file.

### D2 — The disposition list is a RECORD, not evidence, and the mechanical check already exists

This is the point that keeps the feature honest.

An agent's list of what it cleaned up is a self-report by the party being audited — the same class
of evidence ADR-0047 §A3 refused to trust for `weakening_findings`, ADR-0048 §A7 for coverage,
ADR-0055 for self-assessed `risk`, and ADR-0057 §D3 for the tracer verdict. An agent that forgot to
clean something up will also forget to list it.

**The actual signal is mechanical and already present:** `commit`'s untracked-file list. Git knows
what was left behind regardless of what any agent says. So this feature deliberately does **not**
add a second detector for stray files — it points the disposition list at the existing gate and says
which one is authoritative.

### D3 — Temp branches get a registry, because git does not surface them the way it surfaces files

Untracked files show up in the commit gate for free. A stray branch does not — it is invisible until
someone runs `git branch` and wonders what `my-101-work` was.

That is not hypothetical in this repository: worktree dispatch has left exactly that kind of
orphan. So an agent creating a temp branch records it, and reconciliation lists branches that exist
and were never reconciled.

**Reconciliation reports; it never deletes.** The spec's case 3 is a repository lost to a branch
cleanup, and a system that automatically removes branches to enforce tidiness has reproduced the
failure it was reading about. Deletion stays human, consistent with the standing rule that this
system does not delete without explicit confirmation.

### D4 — Debug log statements are named but not detected

The clause asks agents to remove and report them. No detector is added.

Distinguishing a debug print from a deliberate one needs intent, not pattern matching — and ADR-0051
already measured what happens when a heuristic of that kind meets real code: `literal-assertion-added`
came in at 25% precision and shipped disabled. A `print(` detector would be worse and would fire on
every CLI tool in the repository.

Named in the instruction, absent from the machinery, and said plainly rather than implied.

## Alternatives rejected

- **A1 — A stray-file detector.** Rejected under §D2: duplicates `commit`'s untracked list, which is
  already mechanical and already in front of a human.
- **A2 — Trust the disposition list as the check.** Rejected under §D2 — self-report by the audited
  party.
- **A3 — Auto-delete unreconciled temp branches.** Rejected under §D3: reproduces the spec's own
  case 3.
- **A4 — Detect debug log statements.** Rejected under §D4 on ADR-0051's measured precedent.
- **A5 — A dedicated cleanup agent** (the spec's §2.2.8 six-pass design). Rejected as
  disproportionate to a P3 gap: it would add an agent and a dispatch site to solve a problem whose
  mechanical half is already solved by `commit`.

## Consequences

### Positive

- Three agents gain a cleanup contract where there was none.
- Temp branches become visible, closing the one debris class git does not surface for free.
- No new detector, so no new false-positive surface and no addition to the advisory load ADR-0052
  §D5 flagged.

### Negative, stated plainly

- **This is the weakest-enforcement feature in the roadmap and it should be read that way.** §D1 is
  an instruction, §D2 explicitly declines to verify it, and §D4 declines to detect the class it
  names. The real protection is `commit`'s untracked list, which existed before this change.
- **A disposition list can be complete and wrong.** An agent that cleaned up something it should
  have kept reports that as tidiness.
- **The branch registry depends on agents registering.** An unregistered branch is exactly as
  invisible as it was before, so reconciliation catches the honest case and misses the one that
  matters most.
- P3 priority is correct. Filing it as done should not be read as the debris problem being solved.
