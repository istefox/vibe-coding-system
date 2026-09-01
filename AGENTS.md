# AGENTS.md

Instructions for Codex CLI when working in this repository. This is a hand-written, purpose-built
file — not a mechanical mirror of `CLAUDE.md`. Codex has no concept of Claude Code's sub-agents,
skills, hooks, or `~/.claude/` directory layout, so none of that belongs here; where this repo's
own tooling matters to a reviewing/diagnosing run, it is described directly below.

## What is this repository

This is not a code project: it is the **blueprint repository** for the "Vibe Coding System for
Stefano Ferri — Multi-Agent Architecture v2.1". Its one authoritative artifact is
`docs/vibe-coding-system.md` (~1770 lines), the complete specification of a Claude-Code-based
multi-agent setup. Read it with offset/limit per section, not in one block — it exceeds 25k
tokens. Every design decision in this repo must be reconciled with that document.

The actual chain implementation lives under `staging/plugin/` (skills, scripts, agent definitions)
and is deployed to a separate machine's `~/.claude/` tree by `staging/sync-to-claude.sh` — nothing
under `staging/` runs in place in this repository.

## Invariant behavioral rules

Apply these regardless of what triggered the invocation (a `codex exec` review, a diagnose call, a
manual `codex` session):

- Conventional Commits in English (`feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`,
  `perf:`).
- Never `git push --force` without explicit human approval.
- Never modify a database migration already applied in production.
- Never disable or weaken a test to make it pass — if a test needs to change, say why, don't just
  make it green.
- Language: English throughout — docs, code, commits, docstrings, review findings.
- Tone: direct, concise, technical — no filler.
- A review or diagnosis is read-only: report findings, never edit files, regardless of what
  sandbox mode the invocation used.

## Repo-specific rules

This repository has twenty numbered invariants ("rules") it learned by getting them wrong, listed
in `CLAUDE.md`'s Rules section with the ADR that established each one. They govern how checks,
scans, and guards in `staging/plugin/` are built (checker vs. reporter idiom, exit-code
conventions, plant-based test verification, and so on). Read them there before reviewing changes
to anything under `staging/plugin/scripts/` or `staging/plugin/skills/*/SKILL.md` — a review that
doesn't know rule 4 (DID-NOT-RUN ≠ found-nothing) or rule 5 (checker vs. reporter) will misjudge
correct code as broken.

## Commands

Documentation-only repository at the root: no build, lint, test, or run commands for
`docs/vibe-coding-system.md` itself. Markdown only, linted with `markdownlint-cli2` (repo-wide
sweep, no path argument — a path-scoped invocation can misreport as clean due to the project's own
`.markdownlint-cli2.jsonc` globs).

`staging/plugin/scripts/tests/*.test.sh` are real bash test suites for the chain scripts — run
them directly with `bash <file>.test.sh` when reviewing a change under `staging/plugin/scripts/`.

Remote: `https://github.com/istefox/vibe-coding-system` (private).
