# ADR-0056 — SAST job in project CI, and a `security-audit` skill

- **Status:** Accepted
- **Date:** 2026-07-26
- **Issue:** #110 (eleventh feature of PROJECT.md Phase 2)
- **SPEC:** `SPEC.md` / `docs/specs/110-sast-security-audit.spec.md`
- **Builds on:** ADR-0054 (#108) for the `checks` job and the fail-closed-in-CI posture.
- **Engages:** ADR-0039 §D4, which removed linters from the write path. §D2 explains why that
  decision stands and this one does not contradict it.
- **Closes:** gap **G-14** of `docs/books/INTEGRATION-REPORT-agentic-spec.md` (PARTIAL, P2).

## Context

Security is covered three times in this system and every instance is LLM judgement. `reviewer.md`
lists Security first in its checklist. `deep-refactor/SKILL.md:47` runs a security dimension and
`:272` makes every security finding report-only regardless of risk level.
`review-triage-fix/SKILL.md:104` routes all security findings to REPORT-ONLY under CIRCUIT BREAKER C.

**No scanner runs anywhere.** No Semgrep, CodeQL, Bandit or equivalent, and no dedicated audit phase
before a release. The agentic spec's base rate for the class is what justifies the cost: 25–33% of
generated code carries a potential weakness.

## Decision

### D1 — An opt-in `security-audit` job running pinned Semgrep

Separate job in `staging/project-templates/ci/ci.yml`, opt-in because SAST is irrelevant to some
target repos (a docs repo, a shell-script repo) and adds real runtime. Opt-in by a marker in the
repo, the same shape as ADR-0022's `publish: true` and ADR-0053's `.claude/protected-interfaces`.

### D2 — This does not reverse ADR-0039 §D4, and the distinction is the version pin

ADR-0039 §D4 removed linters from `post-write-check.sh` on the rule that *a verdict that depends on
which tools are installed is not a verdict*. It cited real evidence: shellcheck's SC2148 was
invisible on macOS (not installed) and red on the CI runner (installed), and that divergence found a
bug.

Semgrep is exactly that class of tool, so the rule has to be answered rather than stepped around.

The answer is **where it runs and how it is pinned**:

- **`post-write-check.sh` runs on a developer's machine, mid-implementation**, against whatever
  happens to be installed. The verdict genuinely varies by machine. ADR-0039 is right.
- **The CI job runs on a declared runner with a pinned Semgrep version and a pinned ruleset.** Two
  runs of the same commit produce the same verdict, because the workflow file specifies the
  version. That is determinism by construction, and it is the property ADR-0039 actually wanted —
  not "no external tools", but "no verdict that changes depending on the machine".

**The pin is therefore load-bearing, not hygiene.** An unpinned `semgrep/semgrep:latest` would
reintroduce exactly the non-determinism ADR-0039 removed, one registry push at a time. Pinned by
digest or exact version, and the test asserts the pin exists.

### D3 — ERROR blocks, WARNING and INFO print

Same evidence-quality split as ADR-0054 §D5. Semgrep's ERROR-severity default rules are
high-confidence; WARNING and INFO carry the false-positive rate that would get the job disabled.

A `security-audit` job that fires on INFO is a job someone adds to the ignore list, and then the
ERROR findings go unread with it.

### D4 — The `security-audit` skill implements the spec's ten-step protocol as an on-demand run

Not a gate, not automatic. Invoked before a release or on request. Ten steps: automated scanners →
separate-AI review → human checklist → fuzz/pen notes → security-focused unit tests →
training-cutoff compensation → logging hygiene → updated tooling → warnings in context → slow down
on security-sensitive work.

It **reports**; it does not fix. Consistent with all three existing security paths
(`deep-refactor:272`, `review-triage-fix:104`, `reviewer.md`), which already make security findings
report-only. Adding an auto-fixing security path would contradict three recorded decisions at once.

### D5 — Training-cutoff compensation must name a year, and the skill must be edited to keep it true

The spec's step 6 exists because a model's security knowledge is stale by construction. The skill
therefore names the **OWASP Top 10 by explicit year** rather than saying "the current OWASP Top 10",
which a model will confidently answer from stale memory.

This creates a maintenance obligation and the skill says so in its own text: the year is a fact with
an expiry date, and a stale year is worse than no year because it reads as current. The test asserts
a year is named at all — it cannot assert the year is right, and that limitation is stated rather
than papered over.

### D6 — The separate-AI review step is a genuine second opinion or it is nothing

Step 2 of the protocol asks for review by a different model. Run by the same model in the same
session it is theatre — it is the generator/verifier problem ADR-0049 exists to fix, reappearing in
the security domain. So the skill dispatches a subagent with a different `model` pin and a
security-only brief, and says plainly that a same-model self-review does not satisfy the step.

## Alternatives rejected

- **A1 — Run Semgrep in a hook on the write path.** Rejected under §D2: that is precisely the
  machine-dependent verdict ADR-0039 removed, and no pin can fix it there because the tool is
  whatever the developer has.
- **A2 — Make the SAST job mandatory rather than opt-in.** Rejected under §D1: irrelevant to some
  repos, and a job that runs pointlessly gets disabled, taking the relevant cases with it.
- **A3 — Block on all Semgrep severities.** Rejected under §D3.
- **A4 — Let the `security-audit` skill auto-fix.** Rejected under §D4: contradicts three recorded
  report-only decisions.
- **A5 — Use `semgrep:latest`.** Rejected under §D2 — this is the alternative that looks like
  convenience and is actually a reversal of ADR-0039.
- **A6 — Say "the current OWASP Top 10" and let the model resolve it.** Rejected under §D5: that is
  the exact failure step 6 exists to prevent.

## Consequences

### Positive

- The first non-LLM security signal in the system, against a class the spec measures at 25–33%.
- A release-time audit phase exists where there was none.
- ADR-0039's rule is preserved and sharpened: the principle was determinism, not tool abstinence.

### Negative, stated plainly

- **The version pin will go stale**, and a stale pinned scanner silently stops catching new rule
  classes. This is the direct cost of §D2's determinism and it is not solved here — the same drift
  ADR-0054 §D3 accepted for vendored scripts, one layer up.
- **The named OWASP year will go stale** (§D5), and a stale year reads as current. The test can
  assert a year is present, never that it is correct.
- **Opt-in means off by default**, so like #106–#109 this ships inert for existing repos.
- **Semgrep's default ruleset is not a security programme.** It catches known patterns. Nothing here
  addresses design-level vulnerabilities, and the skill must not be read as coverage.
- The `security-audit` skill is an instruction a model follows, with the same enforcement gap as
  every skill in this system.
