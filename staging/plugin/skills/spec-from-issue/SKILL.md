---
name: spec-from-issue
description: >
  Headless SPEC generator (ADR-0023). Turns one GitHub issue (title + body) into
  docs/specs/<slug>.spec.md following the interview-driver SPEC structure, WITHOUT any
  AskUserQuestion. Runs a deterministic quality gate first (spec-issue-gate.sh): a thin or
  vague issue is SKIPPED, never fabricated. Used by nightly-autopilot Phase P to replace the
  interactive interview when driving a labeled backlog unattended.
---

# `spec-from-issue` — Headless SPEC Generator

Produces a SPEC.md from a single GitHub issue so the design chain can run unattended. This skill
replaces the interactive `interview-driver` for the overnight path. It has NO `AskUserQuestion`. It
never invents requirements the issue does not state.

**Architecture reference:** ADR-0023 (D5).

---

## 1. When to invoke

```
/skill spec-from-issue <issue-number> [--slug <slug>] [--root <dir>]
```

Called once per feature by `nightly-autopilot` Phase P. `--slug` and `--root` default to the
issue-map slug and `$PWD`. Not meant for interactive use.

---

## 2. Steps

### Step 1 — Read the issue (read-only)

```bash
gh issue view <issue-number> --json number,title,body > /tmp/issue.json
```
Extract `title` and `body`.

### Step 2 — Quality gate (deterministic, before any synthesis)

```bash
printf '%s' "<body>" | bash "$SCRIPTS/spec-issue-gate.sh"
```
(`$SCRIPTS` = `~/.claude/hooks` in the installed layout.)

- Exit 3 (THIN): do NOT synthesize. Append a run-level `needs-human` note and mark the feature
  skipped, then STOP with `SKIP`:
  ```bash
  printf 'issue #<n> "<title>" skipped: <reason from gate>\n' >> "<root>/.claude/needs-human"
  # mark [~] in PROJECT.md for this issue's feature line (bash sed on the "(issue #<n>)" line)
  ```
  Emit: `spec-from-issue #<n> · SKIP · <reason>`.
- Exit 0 (OK): proceed to Step 3.

### Step 3 — Synthesize the SPEC (only from issue content)

Write `<root>/docs/specs/<slug>.spec.md` with these sections, drawing ONLY on the issue title and
body (and, where the issue references them, files already in the repo). Do not invent scope the issue
does not imply. Keep unknowns explicit as `TBD` rather than fabricating.

```
# SPEC — <title>

Source: GitHub issue #<n>

## Objectives
<what the issue asks for, as 1-3 concrete objectives>

## Scope
In: <what this feature covers>
Out: <what it explicitly does not>

## Stack
<inferred from the repo; state the detected stack, or TBD>

## Architecture
<the components/files this feature touches, from the issue + repo>

## Data model
<entities/fields if the issue implies any; else "None" or TBD>

## API / Interfaces
<endpoints, functions, or UI entry points implied; else "None" or TBD>

## UI flows
<user-visible steps if applicable; else "None">

## Edge cases
<edge cases the issue names or that follow directly from it>

## Success criteria
<the issue's acceptance criteria, verbatim where present, as a checklist, each item prefixed
with a unique R-NN id starting at R-01 (e.g. `- [ ] R-01 — ...`) (ADR-0048)>
```

Emit: `spec-from-issue #<n> · OK · docs/specs/<slug>.spec.md`.

---

## 3. Guardrails

- **No `AskUserQuestion`.** This skill is headless by contract; if it cannot proceed it SKIPs, it
  never prompts.
- **Never fabricate.** Requirements come only from the issue (and repo files it references).
  Unknowns are `TBD`, not invented. The quality gate blocks synthesis from a thin issue.
- **IDs are assigned to criteria the issue already states; an ID is never a reason to invent a criterion.**
  Number the criteria the issue names — do not pad the checklist with additional items just to
  give every ID a home (ADR-0048).
- **Read-only on GitHub.** It uses `gh issue view` only. It never edits the issue, pushes, or opens
  a PR.
- **One SPEC per feature.** Output is `docs/specs/<slug>.spec.md`. The just-in-time copy to
  `<root>/SPEC.md` is done by `project-conductor nightly` before the feature's chain, not here.
