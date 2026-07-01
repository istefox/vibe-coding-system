# ADR-0023 — nightly-autopilot auto-design: issue-driven unattended design generation

**Status:** Proposed (2026-07-01)
**Date:** 2026-07-01
**Author:** istefox
**Supersedes:** none
**Amends:** ADR-0022 (extends the unattended boundary from implementation to design generation)
**Related:** ADR-0003 (concept-to-code chain), ADR-0008 (greenfield/brownfield), ADR-0014 (test-cmd TOFU trust), ADR-0020 (autopilot-build), ADR-0022 (nightly-autopilot)

---

## Context

`nightly-autopilot` (ADR-0022) presupposes that SPEC, ADR, plan, PROJECT.md, and manifests already
exist and were human-approved in the evening. Launched on a repo that only has open issues it aborts
at pre-flight (missing PROJECT.md, missing opt-in marker). The goal here is for the system to generate
the missing design artifacts itself from a labeled GitHub backlog, so a set of issues becomes PR-ready
overnight with no evening design work.

### What the chain can and cannot do headless (verified 2026-07-01)

- Everything downstream of SPEC is already headless. The `architect` agent has no `AskUserQuestion`
  and writes the ADR and plan from a SPEC; `claude-md-generator` writes CLAUDE.md; `manifest-init.sh`
  creates the manifest; `concept-to-code` autopilot auto-resolves every design gate (each carries an
  inline `[Autopilot default]`); `project-conductor nightly` (ADR-0022) already skips the per-feature
  gate. The only human touch to enter c2c autopilot is Gate 0, and it is bypassed by pre-seeding
  `manifest.autopilot: true`, which `project-conductor` already does.
- Only two artifacts have no non-interactive producer: `SPEC.md` (only `interview-driver`, which is an
  interactive `AskUserQuestion` loop; c2c autopilot hard-aborts if `SPEC.md` is absent) and
  `PROJECT.md` (only the 3-round setup interview; no issue-to-roadmap path exists).
- Two one-time human actions are irreducible by hard invariant. ADR-0014 and ADR-0020 (Alt D4a)
  reject a self-approving prep step as "self-authorizing, which undermines the entire TOFU model":
  `approve-test-cmd.sh` (TOFU trust, once per repo) and `gh auth login` (once per machine). Neither
  can be automated without dismantling the anti-self-authorization guarantee.

### The gap

To make a labeled backlog PR-ready overnight, the system needs exactly: a headless SPEC producer
(issue body to SPEC), a headless PROJECT.md producer (issues to roadmap), and the `.claude/test-cmd`
file itself. Nothing else in the design chain is missing.

---

## Decision

### D1: A prep phase in `nightly-autopilot`, not a new skill

`nightly-autopilot` gains a Phase P that runs before the Phase 0 pre-flight and fills the two headless
gaps plus the test-cmd file. One entry point stays. Rejected alternatives (a separate `nightly-prep`
skill, a new design engine) are recorded below.

### D2: Amend the ADR-0022 boundary — design generation joins the unattended set

ADR-0022 D2 allowed unattended implement, test, review, local commit, plus opt-in push and open PR.
This ADR adds unattended generation of the design artifacts (SPEC.md, ADR, plan, PROJECT.md, project
CLAUDE.md, manifests) to that set, under the same per-repo opt-in marker. The forbidden set is
unchanged: no merge, no force-push, no `--no-verify`, no write to `main`. The human merge review stays
the design checkpoint.

### D3: The TOFU and gh-auth wall stays human; the test-cmd file is auto-created

Trust registration and `gh auth` remain one-time human actions, unchanged from ADR-0014/0020. Prep
does auto-create the `.claude/test-cmd` file from stack detection (Swift/Xcode, Python, Node, and so
on), which ADR-0014 already permits (the architect authored the candidate; writing the file does not
grant trust). So the human's per-repo action collapses to a single `approve-test-cmd.sh <root>` with
nothing to author. Pre-flight still aborts if trust is absent, now with a message that names the
pre-written file and the exact one-liner.

### D4: Input is GitHub issues by label

The design source is a labeled issue set (for example `release-blocker`), configured in the opt-in
marker (`prep.source: issues`, `prep.issues_label: <label>`). One issue becomes one roadmap feature;
the issue title and body are the requirements that replace the interview.

### D5: `spec-from-issue` is headless and refuses to fabricate

A new headless generator turns an issue title and body into `docs/specs/<slug>.spec.md` in the
`interview-driver` SPEC structure. It has no `AskUserQuestion`. A hard quality gate: if the issue
lacks enough substance (no acceptance criteria, too short), it does not invent one. It marks the
feature skipped (`[~]` in PROJECT.md) with a `needs-human` note that the morning report surfaces.

### D6: `roadmap-from-issues` builds PROJECT.md

A deterministic script reads `gh issue list --label <L> --json number,title,body` and writes
`PROJECT.md` (one feature per issue) plus `docs/specs/_issue-map.tsv` (slug, issue number, title). It
is idempotent: re-runs do not duplicate features already listed. The slug is prefixed with the issue
number (`<num>-<title-slug>`) so it is unique even when two titles slugify the same, and so
`project-conductor` resolves the spec by globbing `docs/specs/<num>-*.spec.md` from the `(issue #N)`
suffix rather than re-deriving a slug that would not match.

### D7: Just-in-time SPEC copy handles the single SPEC.md path

c2c autopilot brownfield reads `<root>/SPEC.md`, but a multi-feature roadmap has one spec per feature.
`project-conductor nightly` copies `docs/specs/<slug>.spec.md` to `<root>/SPEC.md` immediately before
each feature's c2c chain. Features run sequentially, so there is no collision, and each feature's SPEC
is committed in that feature's PR.

### D8: PR is the checkpoint — no pre-implementation human gate

The generated SPEC and ADR are committed inside the feature PR and reviewed by the human at merge
time. There is no stop-after-design gate; the run goes straight from issue to open PR. Merge stays
human, so a wrong auto-design is caught before it reaches `main`.

### D9: Reuse the headless chain verbatim

Prep fills only the three gaps (SPEC, PROJECT.md, test-cmd file). The
architect/adr-writer/claude-md-generator/c2c-autopilot/conductor path is untouched. No new design
engine is introduced.

---

## Alternatives considered

### Alt A: auto-grant TOFU trust in prep

Have prep call `approve-test-cmd.sh` itself so the run needs zero human setup. Rejected: it is the
exact Alt D4a that ADR-0020 already rejected. A pre-flight that registers its own trust is
self-approving and voids the TOFU model. The one-time human `approve-test-cmd.sh` stays.

### Alt B: single high-level goal, system decomposes into features

Feed one goal string and let the system invent the feature breakdown. Rejected for v1: the
decomposition is the highest-risk, least-reviewable step, and the user has a concrete labeled backlog.
Issues give a human-authored unit of work per feature.

### Alt C: stop after design generation for a human review

Generate SPEC/ADR/PROJECT/manifest, then halt for a morning design review before implementing.
Rejected for v1 because it splits the overnight run in two and the PR already carries the generated
design for review at merge. Recorded as a future opt-in (`prep.stop_after_design: true`).

### Alt D: a separate `nightly-prep` skill

Put prep in its own skill. Rejected: the user asked for one command, and prep is meaningless outside a
nightly run. A phase inside `nightly-autopilot` keeps the entry point single and the state (opt-in
marker, `docs/specs/`) local to the run.

---

## Consequences

### Positive

- A labeled backlog becomes PR-ready overnight after a tiny one-time per-repo bootstrap.
- No new design engine; the proven headless chain is reused as-is.
- Safety invariants hold: TOFU and gh auth stay human, publish stays opt-in, the guard and no-merge /
  no-force-push / no-main rules are unchanged.
- The thin-issue quality gate stops the system from auto-designing garbage from a vague issue.

### Negative / risks

- Auto-generated SPEC and ADR can be wrong when the issue is vague. Mitigation: the quality gate skips
  thin issues, and the human merge review is the design checkpoint (the design is committed in the PR).
- Larger unattended surface (design plus implementation per feature) and higher token/time spend.
  Bounded by the `/goal` `stop after N turns` budget and the guard's run-level halts.
- The `/goal` evaluator versus in-flight subagents item from ADR-0022 is unchanged and still gated by
  the Phase 4 smoke test.

### Neutral

- The morning report schema goes to v2.1 with a `prep` block. The opt-in marker gains `prep.*` fields.
- Stop-after-design (Alt C) and single-goal input (Alt B) are documented as future options.

---

## Open verification (not a blocker to accepting the design)

- Integration smoke on a throwaway repo: one well-formed issue, run the full recipe, confirm prep
  writes test-cmd + PROJECT.md + the per-feature spec, and after the one-time `approve-test-cmd.sh`
  the run designs (ADR + plan) and implements, ending at a PR with SPEC + ADR + code and CI green,
  nothing merged.
- Thin-issue path: a vague issue is skipped with a clear report line, not auto-designed.

---

## References

- ADR-0022 `docs/architecture/ADR-0022-nightly-autopilot-goal.md` — boundary amended here
- ADR-0014 `docs/architecture/ADR-0014-architect-proposes-test-cmd.md` — TOFU trust (unchanged)
- ADR-0020 `docs/architecture/ADR-0020-autopilot-build-skill.md` — Alt D4a rejection of self-approval
- ADR-0008 `docs/architecture/ADR-0008-concept-to-code-workflow-v2-brainstorm.md` — greenfield/brownfield SPEC
- `~/.claude/skills/concept-to-code/SKILL.md` — `[auto]` brownfield requires an existing SPEC.md
- `~/.claude/skills/interview-driver/SKILL.md` — SPEC.md structure the generator mirrors
