# ADR-0067 — `interview-driver` must be model-invocable for the concept-to-code chain

- **Status:** Accepted
- **Date:** 2026-07-27
- **Supersedes:** issue #56 / PR #95 (commit `4baf9b2`) **in part** — for
  `staging/plugin/skills/interview-driver/SKILL.md` only. The same commit's decision for
  `fastapi-react-vibe` stands unchanged.
- **Reported as:** a live chain failure, not an audit finding.

## Context

Running `concept-to-code` fails at Step 1:

```
Error: Skill interview-driver cannot be used with Skill tool due to disable-model-invocation
```

Step 1 (greenfield) and Step H1 (hybrid path) both instruct the orchestrator to
`Use the interview-driver skill to produce SPEC.md…`. The orchestrator is a model. The skill carried
`disable-model-invocation: true`, which restricts invocation to the user. The two are mutually
exclusive, so Step 1 could never complete.

`interview-driver` is also named in `concept-to-code` §25 as one of the skills invokable **inside**
the chain, and in the skill's own `description` frontmatter ("invocation from the concept-to-code
chain orchestrator (Step 1)"). Three separate places asserted the chain invokes it while a fourth
forbade it.

### The rule already existed, and this is its fourth enforcement site

This is not a new lesson being learned. The repo has carried the rule "a skill invoked from a chain
must not be flagged" since the `design-brainstorm` work, recorded as the memory
`feedback_disable-model-invocation-strong.md` and cited by name in:

- `docs/guida-workflow-orchestrazione.md` §10 Troubleshooting, whose entry is literally titled
  *"Skill X cannot be invoked from a skill"* with the cause and the fix spelled out.
- ADR-0008 §"disable-model-invocation": `design-brainstorm` **MUST** be invocable from the chain,
  therefore **MUST NOT** carry the flag.
- ADR-0010 §259, the same requirement for `web-e2e-test` at its gate.

Two skills already enforce it with their own negative anchors:
`staging/plugin/skills/design-brainstorm/tests/run-tests.sh` assertion 3 and
`staging/plugin/skills/clean-public-repo/tests/run-tests.sh` assertion 3.

So the rule was written down, cited in two ADRs, and mechanically enforced on two skills — and #56
still violated it on a third, because **every existing guard checked an instance and none checked
the class**. That, not the flag itself, is the defect this ADR is written against. D5 closes it.

### How it got here

The flag was restored by commit `4baf9b2` (PR #95, 2026-07-25, closing issue #56) on
`interview-driver` and `fastapi-react-vibe`, together with the `PAIRS` entries that let the fix
reach `~/.claude` at all. Both had lost it in the issue-#29 staging refresh, which mirrored the
deployed tree wholesale; ADR-0025 Consequences flagged the loss and deliberately left it, being out
of that issue's scope.

So the chain worked from #29 until #95 **by accident** — it depended on a flag being missing. #56
correctly identified the missing flag as a defect and restored the blueprint's documented default.
What nobody checked is which callers relied on the defect.

### No settings-level exemption exists

Verified against the CC 2.1.220 binary the system actually runs:

- Frontmatter `disable-model-invocation` locks the skill's state, surfaced in the `/skills` detail
  view as `(on/name-only locked by frontmatter disable-model-invocation)`.
- `skillOverrides` only ever disables further (`" is disabled via skillOverrides. …"`); there is no
  override that re-enables model invocation for a flagged skill.
- Coordinator mode carries its own refusal for the same reason: `" is user-invocable only
  (disable-model-invocation) and cannot run in coordinator mode…"`.

The contradiction therefore cannot be resolved in settings. It has to be resolved in one of the two
files that disagree.

## Decision

### D1 — Remove `disable-model-invocation: true` from `interview-driver`, and only from it

`interview-driver` is the sole chain-invoked skill carrying the flag. Checked across all 29 staged
skills: the other carriers are `fastapi-react-vibe`, `goal-loop` and `research-prompt`, none of
which any chain invokes. Every other skill named in `concept-to-code` §25 (`design-brainstorm`,
`macos-ux`, `claude-md-generator`, `review-triage-fix`, `deep-refactor`, `commit`) is already
unflagged, so this restores the file to the shape its callers already assume.

The removal is marked in the file with a comment naming this ADR, so the next reader auditing
frontmatter defaults does not "restore" it a third time.

### D2 — `fastapi-react-vibe`, `goal-loop` and `research-prompt` keep the flag

The #56 reasoning holds for all three. `fastapi-react-vibe` writes a multi-file scaffold, and none
of the three is dispatched by a chain, so nothing forces model invocation on them.

### D3 — The `/loop` trap paragraph is amended, not rewritten

Blueprint sec. 16's scheduled-fire paragraph names the flag carriers. It drops to three, and the
worked example moves from `/loop 20m /interview-driver …` to `/loop 20m /research-prompt …` because
the original example is no longer an instance of the trap it illustrates. Removing the flag closes
that trap for `interview-driver` specifically: a scheduled fire naming it will now execute rather
than paste a string.

### D5 — A class-level guard replaces the instance-level ones

`skill-text-corrections.test.sh` gains **F6**: no skill that `concept-to-code` §25 declares
chain-invokable may carry the flag. The skill list is **derived from §25 at run time** (backticked
tokens on that line that resolve to real staged skill directories), not hardcoded, so adding a
chain-invoked skill extends the guard with no test edit.

It carries a count guard — fewer than five resolved skills is a failure, not a pass — because a
derived list that silently resolves to nothing reads exactly like full coverage. That is the
`pairs-completeness.test.sh` self-test-2 lesson applied to a different derivation.

F6 was seen RED with the flag reintroduced on `interview-driver` and green with it removed, so it
demonstrably catches the exact #56 regression rather than passing by construction. The existing
per-skill anchors in `design-brainstorm` and `clean-public-repo` stay; they are cheap and they run
in those skills' own harnesses.

### D4 — Blueprint sec. 8's template is annotated, not edited

The sec. 8 `interview-driver` template still shows the flag. It gets a **Deployment note** beneath
it rather than an in-place edit, following the ADR-0034 precedent for historical illustrations and
the ADR-0036 precedent for the `architect` template specifically.

## Consequences

### Accepted residual risk

The model can again self-invoke `interview-driver` outside the chain, which is precisely what #56
restored the flag to prevent. Blast radius is bounded by the fact that no unattended path wants this
skill:

- `nightly-autopilot` Phase P uses `spec-from-issue` — ADR-0023 chose it **because** the interview
  is interactive and headless-hostile.
- `autopilot-build` starts at `ready_for_implementation`, downstream of any SPEC work.
- The `concept-to-code` autopilot path hard-aborts when `SPEC.md` is absent rather than interviewing.

A stray self-invocation therefore lands in an attended session, where it costs a wasted turn and a
human interrupt. A permanently unreachable Step 1 costs the chain's entire greenfield entry point.

### Rejected alternative

**Keep the flag; have Step 1 stop and instruct the user to type `/interview-driver`.** Rejected on
the explicit requirement that the chain invoke the skill, and because it breaks Step 1's
"CRITICAL — chain continuation (no stop)" contract, which exists because the orchestrator had a
history of halting there. It was also the weaker trade: it preserves a guard against a low-severity
annoyance by permanently converting an automated step into a manual one.

**Inline the interview instructions into `concept-to-code` Step 1.** Rejected: it creates a second
source of truth for the interview content, which ADR-0024 established as the thing this repo does
not do, and leaves `interview-driver` as a skill the chain no longer uses while still naming it.

### Test coverage, and the trap in the test itself

`skill-text-corrections.test.sh` section F is amended rather than deleted:

- **F1 is inverted** — it now asserts the flag is **absent** from `interview-driver`, with the
  reason in the comment. Seen RED against the flagged file before the fix.
- **F2** keeps the positive assertion for `fastapi-react-vibe`.
- **F6 is the new class-level guard** (D5), derived from c2c §25 with a count guard. Seen RED
  against a reintroduced flag.
- **F5 changes direction.** It used to fail if the blueprint contained the literal string
  `Three staged skills carry that flag`, a ban on one specific stale wording. Under D3 the count
  legitimately returns to three, so that ban would have fired on the **corrected** sentence. It is
  replaced by a positive check: the sentence must name the three real carriers and must not name
  `interview-driver`. Same lesson as ADR-0043 — ask which direction a guard runs in, because a
  guard written against yesterday's specific error does not generalise to tomorrow's.

### Deployment

`staging/sync-to-claude.sh` line 43 already pairs this file, so `--apply` deploys it with no `PAIRS`
change. Until that sync runs, the deployed `~/.claude/skills/interview-driver/SKILL.md` keeps the
flag and every chain run on this machine keeps failing at Step 1.

A chain already mid-run does not pick the fix up. Its unblock stays a manual `/interview-driver`.
