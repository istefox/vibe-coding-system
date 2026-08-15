---
name: security-audit
description: >
  Use this skill for an on-demand, report-only security audit run before a release or on
  explicit request — automated Semgrep scanning, a genuine second-opinion AI review from a
  different model, a human checklist, and the remaining steps of a ten-step security protocol.
  Never fixes: every finding is written to the report, consistent with deep-refactor's and
  review-triage-fix's report-only security posture. Trigger phrases: "security audit",
  "security-audit", "run a security review", "pre-release security check".
  NEGATIVE: Do NOT use this to fix a security finding — this skill never dispatches a fixing
  agent, by design (ADR-0056 §D4). Do NOT use for a general code review
  (code-review-checklist) or a full review+fix cycle (review-triage-fix) — both can fix
  non-security findings; this skill is security-only and never edits source.
---

# security-audit

On-demand, report-only security audit. Walk the ten-step protocol start to finish, write a
report, never fix anything.

## Hard constraints (read first)

- **Report-only, always.** This skill never dispatches a fixing agent (`coder`, `refactorer`,
  `debugger`) for a security finding, and never edits source itself. Every finding is written
  to the report and left for a human, or a separate fix cycle (`review-triage-fix`,
  `deep-refactor`), to act on. This matches all three existing report-only security paths in
  this system — `deep-refactor/SKILL.md`'s security dimension, `review-triage-fix/SKILL.md`'s
  CIRCUIT BREAKER C, and `reviewer.md`'s checklist — none of which auto-fix a security finding
  either. An auto-fixing security path here would contradict all three at once (ADR-0056 §D4).
- **Orchestrator-session only.** Step 2 dispatches a subagent. If this skill is invoked from
  inside a sub-agent, stop immediately and say so — you cannot dispatch from there.
- **Not a gate, not automatic.** Invoked before a release or on explicit request. No manifest
  field, no wiring into any chain. The CI-side SAST scanning is a separate, opt-in
  `security-audit` job in the project's `ci.yml`, gated on `.claude/security-audit-enabled`
  (ADR-0056 §D1) — this skill's Step 1 reads that job's output when available rather than
  duplicating it.
- **Semgrep's default ruleset is not a security programme.** It catches known patterns.
  Nothing in Step 1 covers design-level vulnerabilities — do not report the automated scan as
  coverage in itself. The other nine steps exist because of that gap, not as decoration.

## The ten-step protocol

Run every step, in order, on every invocation. A step that finds nothing still gets a line in
the report ("no findings" is itself a result, not an omission).

### Step 1 — Automated scanners

If the project has opted into the CI `security-audit` job (`.claude/security-audit-enabled`
present at the project root), read that job's most recent run rather than re-running Semgrep
locally — the CI job is the pinned, deterministic instance (ADR-0056 §D2), and a local run on
whatever Semgrep happens to be installed would reintroduce the exact machine-dependent verdict
that job exists to avoid.

If no CI run is available and `semgrep` is present locally (`command -v semgrep`), run it once
against the working tree with the same named ruleset the CI job pins:
`semgrep scan --config=p/owasp-top-ten .`. Record ERROR-severity findings as the primary
automated-scanner section of the report; WARNING/INFO findings are listed but not emphasized —
the same evidence-quality split the CI job applies (§D3).

If neither the CI job output nor a local `semgrep` is available, record "No automated scanner
run — semgrep unavailable" and continue. Tooling absence never blocks the remaining nine steps.

### Step 2 — Separate-AI review

<!-- dispatch-site: security-audit-reviewer class=inline exempt: the reviewer grant carries no Write tool, and this skill is report-only by ADR-0056 D4 so no finding of its own can gate anything -->
**Read the report before writing Step 3.** This dispatch returns before the agent has run
(issue #435): since CC 2.1.232 the `Agent` call yields metadata and the report arrives as a
notification. Nothing here previously said to wait, which was survivable only because the next
section is a human checklist.

Dispatch a `reviewer` agent with a **security-only** brief:

> "Review the current diff (or, if there is no diff, the full source tree) for security
> findings only: injection, auth bypass, hardcoded secrets, path traversal, insecure
> deserialization, unguarded URL construction, missing input validation. Ignore style,
> structure, and performance — those are out of scope for this review."

**Pin `model: opus` on this dispatch explicitly, unless the orchestrator's own session is
already running at `model: opus`, in which case pin `model: sonnet` instead.** The rule is not
"always opus" — it is "always different from whatever model is doing the dispatching". A fixed
pin that happens to coincide with the session's own model is not a second opinion; it is the
same model reviewing itself under a different label.

**A same-model self-review does not satisfy this step.** This is the generator/verifier
problem (ADR-0049) reappearing in the security domain: a model marking its own session's work
is not independent evidence, however the prompt is worded. If the dispatch pin and the
orchestrator's session model turn out identical, treat the step as not performed — repeat it
with a genuinely different model before writing the report, or record the failure explicitly
in the report rather than letting it pass silently as "reviewed".

### Step 3 — Human checklist

Present this checklist for the user to walk manually — this skill cannot execute it, only ask:

- Authn/authz boundaries on every new or changed endpoint.
- Session handling (fixation, expiry, invalidation on logout).
- CORS/CSP headers on anything user-facing.
- Dependency provenance (new packages from a trusted registry, pinned versions).
- Secrets management (nothing new hardcoded, nothing new logged in plaintext — cross-check
  against Step 7).
- Least-privilege service accounts / API scopes for anything newly granted.

Record which items the user confirms as reviewed, and which they skip.

### Step 4 — Fuzz and pen-test notes

Record whether fuzzing or penetration testing exists for this project: a fuzz target reachable
from `.claude/test-cmd`, a documented pen-test schedule, or neither. If neither exists, note it
as a gap in the report. This skill does not run fuzzing or a pen test itself.

### Step 5 — Security-focused unit tests

Check whether security-relevant code paths (authentication, input parsing, deserialization,
access-control checks) have dedicated tests in the existing suite. This is a read-only check
against what already exists — this skill does not write tests itself; that is the `tester`
agent's job, dispatched from a different skill (`concept-to-code` Step 5, ADR-0049).

### Step 6 — Training-cutoff compensation

A model's security knowledge is stale by construction: training data has a cutoff date, and
threat intelligence does not. This step exists to compensate for that gap explicitly rather
than let the model answer from stale memory.

When reviewing web-facing code, name the OWASP Top 10 by its explicit edition year. As of this
writing, the current edition is **OWASP Top 10:2025**. Do not leave the edition undated in the
report — an undated reference invites whoever reads it (this model, right now, or a human
later) to resolve it from stale memory, which is exactly the failure this step exists to
prevent.

**The year above is a fact with an expiry date, and keeping it correct here is a maintenance obligation, not a one-time note.**
A stale year is worse than no year at all: a stale year
reads as current, where an absent year would at least visibly signal its own staleness.
Whoever next edits this skill must check the OWASP project's own published edition (currently
`https://owasp.org/Top10/2025/`) before trusting the year above, rather than assuming it is
still right. This skill's own test can confirm a year is present; it cannot confirm the year is
correct, and that limitation is stated here rather than papered over.

### Step 7 — Logging hygiene

Check recently changed logging statements for secrets, tokens, session identifiers, or other
PII written to logs in plaintext. Report any found, with `file:line`. Do not redact or edit
them — that would be a fix, and this skill reports, it does not fix.

### Step 8 — Updated tooling

Read the pinned Semgrep image tag from the project's `.github/workflows/ci.yml` `security-audit`
job, if present. A pin more than roughly six months old is silently missing new rule classes —
flag it in the report as a candidate for re-pinning. **Do not re-pin it automatically.** Which
version to move to is a deliberate human decision (ADR-0056 §D2): the pin is load-bearing
determinism, not a version this skill should bump on its own initiative.

### Step 9 — Warnings in context

Re-surface any security-relevant compiler, linter, or IDE diagnostic already visible for the
changed code (a tainted-flow warning, an unchecked-return warning) that
`post-write-check.sh`'s syntax-only pass would not catch (ADR-0039 scope). Read whichever of
these already exist in CI logs or local diagnostics — do not re-run a linter this skill does
not otherwise own.

### Step 10 — Slow down on security-sensitive work

Close the report with this note, stated to the user rather than only written to the file:
security-sensitive changes — authentication, cryptography, payment handling, PII — deserve
deliberately slower review than routine code. This ten-step protocol is meant to be walked in
full for such a change, never sampled or shortened because the deadline is close.

## Report

Write path: `<project_root>/docs/security-audit/YYYY-MM-DD-<project>-audit.md`

Where `YYYY-MM-DD` is today's date (ISO 8601) and `<project>` is the project's directory name.
Create `docs/security-audit/` first if it does not exist.

**Report schema (required sections, in order, one per protocol step):**

```markdown
# security-audit — <project_name> — <YYYY-MM-DD>

## Summary

- Automated scanner: <ERROR=N WARNING=N INFO=N | CI job read | not run — semgrep unavailable>
- Separate-AI review: <performed, model=<model> | NOT PERFORMED — same-model self-review does
  not satisfy this step>
- Human checklist items confirmed: <N of 6>
- Security-focused test coverage gaps: <count>
- Deferred / ACTION REQUIRED findings: <count>

## Step 1 — Automated scanners

[ERROR findings first, then WARNING/INFO, or "No automated scanner run — semgrep unavailable"]

## Step 2 — Separate-AI review

Model used: <model> (orchestrator session model: <model>)
[Findings from the dispatched reviewer, security-only]

## Step 3 — Human checklist

[Checklist with confirmed/skipped per item]

## Step 4 — Fuzz and pen-test notes

[Existing coverage, or "No fuzzing or pen-test coverage found — gap"]

## Step 5 — Security-focused unit tests

[Coverage summary, or gaps found]

## Step 6 — Training-cutoff compensation

OWASP edition referenced: OWASP Top 10:2025 (verify this is still current before trusting it —
see the skill's own Step 6 text).

## Step 7 — Logging hygiene

[Findings with file:line, or "No plaintext secret/PII logging found"]

## Step 8 — Updated tooling

[Pinned Semgrep version and its age, or "No CI security-audit job found"]

## Step 9 — Warnings in context

[Re-surfaced diagnostics, or "None found"]

## Step 10 — Slow down on security-sensitive work

Security-sensitive changes deserve deliberately slower review than routine code. This protocol
was run in full, not sampled.
```

**Every finding across every step is report-only.** Tag high-severity items (secrets, auth
bypass, injection) with `ACTION REQUIRED — not auto-fixed`, matching `deep-refactor`'s tag
verbatim so the two reports read consistently.

## HITL Gate — commit approval

This skill never edits or stages source. It writes exactly one new file (the report).

```
AskUserQuestion:
  question: |
    security-audit — Audit complete. Report written.

    Report: docs/security-audit/<YYYY-MM-DD-project>-audit.md
    Separate-AI review: <performed, model=<model> | NOT PERFORMED>
    ACTION REQUIRED findings: <count>

    This skill made no source changes — only the report above.
  options:
    - "Stage and commit the report"
    - "Leave the report unstaged — I will handle it manually"
```

**On "Stage and commit the report":** `git add` the report file, then invoke the `commit`
skill (Skill tool) with context hint `security-audit: <project_name>`. Do not self-commit.

**On "Leave the report unstaged":** stop. The report file exists on disk; nothing is staged.
