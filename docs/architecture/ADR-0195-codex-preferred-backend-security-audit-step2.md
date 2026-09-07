# ADR-0195 — Codex is wired into `security-audit`'s Step 2 as the preferred backend on a diff scope, and stays off the whole-tree path

- **Status:** Accepted (decision; implementation is a separate pass, no file is changed by this ADR)
- **Date:** 2026-09-06
- **Related:** ADR-0187 (the Codex review gate, `use_codex_review`, `codex-reviewer.sh`'s contract
  and availability cascade; its deferral clause names this skill), ADR-0193 (moved the ask to
  dispatch time and corrected the deployed path to `~/.claude/hooks/codex-reviewer.sh`), ADR-0194
  (unbundled `security-audit` from `deep-refactor` and named it the stronger candidate — this ADR
  answers the question it left open), ADR-0056 (`security-audit`: §D4 report-only, §D6 the
  separate-AI review step), ADR-0049 (generator/verifier separation, the framing §D6 reuses),
  ADR-0124 (frozen baselines, why a new dispatch-site declaration is not free)
- **Out of scope, deliberately:** ADR-0187's remaining deferrals — `coder`/`tester` dispatch, Gate
  5.06, and `--autopilot` runs — are not addressed here (D7).

## Context

ADR-0194 closed `deep-refactor` as a decided "no" and, in the same pass, unbundled `security-audit`
from ADR-0187's joint deferral clause, naming it "the stronger candidate" and stating explicitly
that whether Codex should actually be wired there — and whether an ADR-0187-shaped *substitution* is
even the right frame at that site — belongs to its own ADR. This is that ADR.

Everything below was measured on 2026-09-06 by reading the files, not inherited from ADR-0187's or
ADR-0194's summaries of them (rule 13). Where a measurement contradicts a prior ADR's stated reason,
that is recorded forward here and the prior ADR is left untouched (rule 14).

### M1 — Step 2's output taxonomy is `reviewer.md`'s own, unmodified: the schema gap ADR-0187 gave as its reason does not exist here

`security-audit`'s Step 2 dispatches the stock `reviewer` agent. It overrides the *brief*
(security-only: injection, auth bypass, hardcoded secrets, path traversal, insecure
deserialization, unguarded URL construction, missing input validation) and the *model pin*. It
overrides no output format, and the skill's report schema leaves the Step 2 section as
free-form findings under a "Model used" line. So what comes back is `reviewer.md`'s Output Format —
BLOCKER / MAJOR / MINOR / NIT with `path:line`, a problem, a fix and a one-line verdict.

That is exactly the taxonomy `codex-reviewer.sh`'s review-mode `--output-schema` enumerates and its
python formatter renders. **The wrapper's output is already contract-compatible with this site,
unchanged.**

ADR-0187's Context deferred three sites in one clause on the grounds that they "use different output
taxonomies (CRITICAL/IMPORTANT/SUGGESTIONS; P1/P2/P3+risk_level+fix_type)". Measured: the first
taxonomy is Gate 5.06's, stated in the two inline reviewer prompts in `hitl-gates.md` and in the
aggregated severity table there; the second is `deep-refactor`'s nine-field finding schema.
`security-audit` has neither, anywhere in its file. Two taxonomies were given as the reason for
three deferrals, and this is the site with no taxonomy of its own. ADR-0194 corrected that clause
once, on the `deep-refactor`-versus-`security-audit` asymmetry; this is the second correction to the
same clause, on the stated reason itself. The deferral was still worth making — M2 and M3 below are
real gaps — but not the one recorded.

### M2 — The gap that does exist is the prompt focus, and it narrows the step rather than breaking it

`codex-reviewer.sh`'s review-mode prompt is one fixed five-item checklist: Security, Correctness,
Performance, Consistency, Tests. Security is one line of it — "input validation, injection,
hardcoded secrets, auth/authz flow" — four classes against the seven Step 2's brief names. There is
no `--focus`, no `--prompt`, no `--brief` flag; nothing lets a caller narrow or replace the
checklist.

Substituting the wrapper as it stands would therefore do two things at once at this site: dilute a
security-only review into a general one, and shallow the security portion from seven named classes
to four. Both findings would land in a report section the skill's own schema declares security-only,
in a skill whose entire purpose is the security pass. This is a real gap, and unlike
`deep-refactor`'s it is a prompt gap, not a schema gap.

### M3 — Step 2's input surface is diff-first with a whole-tree fallback; the wrapper serves the first half exactly and cannot serve the second

Step 2's brief says: review "the current diff (or, if there is no diff, the full source tree)".

The wrapper's three `--diff-scope` values all resolve to a `git diff` or `git show`: `uncommitted` →
`git diff HEAD`, `base:<ref>` → `git diff <ref>...HEAD`, `commit:<sha>` → `git show <sha>`. The
first two map onto real `security-audit` invocations without inventing anything — an audit of
working-tree changes, and the pre-release "everything since the last tag or release branch point"
audit that is the skill's first named use. The whole-tree fallback has no counterpart and cannot be
given one without the mode ADR-0194 already rejected building (A4 below).

Two sharp edges in the same measurement:

- **The empty-diff branch exits 0, not 3.** With no diff, the wrapper writes "No detectable changes
  for scope ... **Verdict:** safe to merge (nothing to review)" and returns success. That is correct
  for its original consumers, where an empty diff genuinely means nothing changed. At this site it
  is a rule-4 trap wearing a green coat: Step 2's report line would read "performed" over a review
  that reviewed nothing, and the never-silent fallback ask — which every existing site keys on exit
  3, the only DID-NOT-RUN signal — would never fire. Rule 20 says the exit-code convention belongs
  to the consumer; this consumer has to guard it.
- **`git diff HEAD` does not show untracked files.** A newly created, unstaged source file — for a
  security audit, among the highest-interest surfaces there is — is invisible to every Codex scope
  and fully visible to the Claude reviewer, which holds `Read`/`Grep`/`Glob`.

### M4 — The step's requirement is model diversity, and today it is satisfied by an instruction the dispatcher applies to itself

ADR-0056 §D6 states the requirement plainly: the separate-AI review is a genuine second opinion or
it is nothing, and a same-model self-review is the generator/verifier problem ADR-0049 exists to fix,
reappearing in the security domain. ADR-0049's framing is that the accept decision must not be made
by the process that produced the thing being accepted; verified by reading it, the match is real,
not a borrowed slogan.

The current mechanism is a conditional pin: `model: opus`, unless the orchestrator's own session is
already opus, in which case `model: sonnet`. The skill says explicitly that the rule is not "always
opus" but "always different from whatever model is doing the dispatching", and that if the pin and
the session model coincide the step is to be treated as not performed.

Three properties of that mechanism, measured rather than assumed:

1. It is an instruction, not an enforcement (rule 16). Nothing checks that the comparison happened
   or that its result was applied; the report's "Model used: `<model>` (orchestrator session model:
   `<model>`)" line is the dispatcher's own account of its own behaviour. The harness can pin that
   Step 2 *states* the rule (assertions SG1-SG3 do exactly that) and cannot pin that it was obeyed.
2. Its proxy is the *dispatcher*, not the *author*. The code under audit is frequently written by a
   model in an earlier session, and the pin can therefore select the very model that wrote it — a
   sonnet-session audit of opus-written code pins opus. Different from the dispatcher, identical to
   the generator, which is the case ADR-0049 is actually about.
3. Same-vendor, different-tier is the weakest form of diversity available. Two models from one
   family share training lineage and, with it, blind spots — which is the property a second opinion
   exists to break.

An external, different-vendor process is different from the dispatcher *and* from the author, by
construction, with no comparison to perform and nothing to apply correctly.

### M5 — The execution path here is the one ADR-0193 verified live, not the one ADR-0194 flagged as unverified

ADR-0194 flagged, as an open premise for whoever took up `security-audit`, that "a Workflow stage can
execute `codex-reviewer.sh` at all" is unverified. Measured: it is not on this path.

`security-audit/SKILL.md` contains no Workflow reference of any kind. Its Step 2 dispatch-site marker
declares `class=inline`, and the skill's own hard constraints say "Orchestrator-session only. Step 2
dispatches a subagent. If this skill is invoked from inside a sub-agent, stop immediately" — an
inline dispatch in the orchestrator's own live turn. The invocation shape this ADR needs is a Bash
call from that live turn to `~/.claude/hooks/codex-reviewer.sh`, which is precisely what ADR-0193's
2026-09-06 correction exercised live during a standalone RTF cycle. Two consequences: the premise
ADR-0194 flagged does not apply, and `AskUserQuestion` is available at this site, so the never-silent
fallback gate needs none of Site 4's deferred-ask machinery.

### M6 — The wrapper's model pin is justified by an argument that does not extend to this site

`codex-reviewer.sh` pins `-m gpt-5.6-terra -c model_reasoning_effort=medium`, and its comment states
the reason: "review dispatch is automated and high-volume, unlike Stefano's interactive Codex
sessions — it does not need his global config's top-tier model/effort".

`security-audit` is on demand, run before a release or on explicit request, wired into no chain
(verified: zero references to it anywhere under `staging/plugin/skills/` outside its own directory,
and no autopilot path can reach it). It is the lowest-volume review in the system and the one whose
miss cost is highest. The pin's own stated justification is inapplicable here — which is an argument
from a fact in the file, not a claim about model quality, and it is the only kind of argument
available without spending live quota.

## Decision

### D1 — Codex is wired into Step 2, and the frame is not ADR-0187's

ADR-0187's frame is cost substitution: Codex replaces Claude at sites where either satisfies the same
role, motivated by Stefano's weekly token ceiling. That frame is wrong at this site, and adopting it
would understate the case.

Here, model diversity *is* the step's requirement (M4). A different-vendor backend is not an equally
acceptable alternative to the Claude reviewer; it is a stronger implementation of the property the
step exists to obtain, and it converts a self-applied instruction into a structural fact. The token
saving — one `opus`, `effort: high` dispatch over a diff — is real and is a side effect, not the
motive. This is also the reason it does not violate Stefano's founding constraint quoted in ADR-0187
("codex deve sostituire e non affiancare"): it substitutes, it does not accompany (A3).

### D2 — Codex is the *preferred* backend, offered through one per-invocation ask inside Step 2

No manifest is involved. `security-audit` resolves none — "no manifest field, no wiring into any
chain" is its own hard constraint — so `use_codex_review` is not readable here and is not extended
to this skill. The choice is per-invocation prose, exactly the shape ADR-0193 chose for a standalone
RTF cycle.

One `AskUserQuestion` inside Step 2, before the dispatch, modelled on RTF Step 0 item 6:

- `[codex]` — "Codex (Recommended — a different vendor satisfies Step 2's different-model rule by
  construction)". First in the list and marked Recommended, per this repo's gate convention.
- `[claude-opus]` / `[claude-sonnet]` — dispatch `reviewer` under the existing conditional-pin rule,
  unchanged.

The ask must display the resolved review scope and its blind spot before the operator answers (D4),
so the recommendation is informed rather than blanket. On `[codex]` and exit 3 (DID-NOT-RUN), the
never-silent fallback ask fires with the reason from stderr and offers the Claude reviewer or a halt
— byte-for-byte the convention ADR-0187 established and every existing site follows.

`security-audit` has no autopilot path today (M6), so no autopilot-skip clause is written. If a
future pass wires this skill into the chain, this ask becomes an unattended blocker and must acquire
the skip clause RTF item 6 already carries — stated here so that pass does not rediscover it.

### D3 — One additive flag on the wrapper, `--focus security`, enumerated and not caller-composed

The prompt gap (M2) is closed by a single enumerated flag on `--mode review`, selecting a
security-only checklist block in place of the five-item one. Everything else is untouched: the
`--output-schema`, the BLOCKER/MAJOR/MINOR/NIT taxonomy, the confidence filter and its python
enforcement, the availability cascade, the exit-code contract, `--carry-forward`, and both existing
modes. With the flag absent, behaviour is byte-identical for the five ADR-0187 sites — the same
additive, retro-compatible idiom the `use_codex_review` field itself used.

Three constraints on that block, each with its reason:

1. **It names the same seven vulnerability classes Step 2's brief names**, and a harness pins the two
   lists against each other. This is the first piece of the Claude/Codex prompt duplication ADR-0187
   declared as an open drift exposure to acquire an automated coupling check. It closes that exposure
   for one list at one site, not in general — the confidence-filter and output-format prose remain
   uncoupled.
2. **The value is enumerated, not free text.** A checker's exit-2 bad-invocation contract can
   validate an enum; it cannot validate prose. A model-composed prompt fragment arriving as a shell
   argument is also unpinnable before the run and unverifiable after it, which is the wrong property
   for the one review the system runs specifically to be trustworthy (A5).
3. **It does not inherit the high-volume cost pin** (M6). The elevated model/effort values are read
   from the live Codex CLI and config at implementation time and never asserted from this ADR's
   memory — the global rule against stating an external tool's current state from recollection
   applies to the values, not just to the mechanism.

### D4 — The consumer resolves the scope *before* the backend, and the whole-tree path stays on Claude

Step 2 resolves its review surface first, then offers the backend, in this order:

1. Uncommitted changes present → `--diff-scope uncommitted`. Codex-eligible.
2. Otherwise, a base ref for the audit (the release ref, the last tag, the branch point) →
   `--diff-scope base:<ref>`. Codex-eligible. This is the ordinary pre-release audit and it is why
   "no diff" is much rarer than the brief's wording suggests.
3. Otherwise, whole source tree → **Claude only.** No whole-tree mode is added to the wrapper (A4),
   and the Claude reviewer already covers this case with an agent holding `Read`/`Grep`/`Glob`.

Two guards belong to the consumer, not the producer (rule 20), both derived from M3:

- **Never invoke the wrapper on a scope that resolves empty.** Its empty-diff exit 0 would produce a
  "nothing to review" Step 2 section and a "performed" summary line, with no exit 3 to trip the
  fallback ask. The scope must be confirmed non-empty *before* the backend is chosen, which is why
  the order in this section is scope-then-backend and not the reverse.
- **Report the untracked blind spot.** When untracked, unignored source files exist, the Codex scope
  structurally cannot see them. Their count and paths are shown in the ask and recorded in the
  report's Step 2 section; a non-zero count flips the recommendation to Claude, whose reviewer can
  read them.

If scope resolution is implemented as a bash fence in the skill, that fence declares itself
(`fence-contract:`) and is executed by a test, per rule 15 — an abortable fence in a `SKILL.md` is
not exempt from that convention because it is small.

### D5 — Provenance is emitted by the producer, not recalled by the consumer

The report's "Model used: `<model>` (orchestrator session model: `<model>`)" line is the *evidence*
that the different-model requirement was met. Filling it, on the Codex path, from the dispatcher's
recollection of what a shell script pins internally would reproduce at the record level exactly the
self-report problem D1 removes at the mechanism level, and would be a rule-17 producer/consumer gap:
a value named at one site, pinned at another, with nothing keeping them in agreement.

So the wrapper appends a provenance line to its markdown output naming the model and effort it
actually ran with, and the skill copies it verbatim. RTF's reports gain the same line for free.

### D6 — Constraints the existing harnesses place on this edit, measured now rather than discovered during implementation

`sast-security-audit.test.sh` and `dispatch-completion.test.sh` already pin this site. Read today:

- **SG0** extracts Step 2 with an awk window anchored on the `### Step 2 — Separate-AI review`
  heading and terminated by the `### Step 3` heading that follows. Everything added must live inside that
  window or it is invisible to every SG assertion.
- **SG1** requires the literal `model: opus` or `model: sonnet` inside that window. The Claude branch
  must survive as first-class text — which D4 requires anyway, and which is one reason A6
  (Codex-only) is rejected.
- **SG2** (`differ`), **SG3** (`does not satisfy this step`), **SG4** (`security-only`) and **SG5**
  (`ADR-0049`) are all satisfied by prose that must be preserved verbatim, not paraphrased.
- **SD11** asserts exactly ten step headings of the form `### Step N —`. The Codex branch is prose
  inside Step 2, not
  a new step.
- **SE3** greps the whole skill for `dispatch.*(coder|refactorer|debugger)`, excluding lines
  containing "never". New prose must not phrase anything as dispatching a fixing agent.
- **DC21** compares the declared `dispatch-site:` set against a frozen baseline that contains
  `security-audit-reviewer`. The Codex branch goes inside that existing declaration; a second marker
  requires a deliberate baseline bump (ADR-0124), which is a cost with no matching benefit here.
- `sast-security-audit.test.sh` declares **no `# plant:` lines at all** today. New assertions covering
  the Codex branch are planted and seen RED before being trusted (rule 2), with needles belonging to
  the mechanism rather than to the word "codex", which the explanatory prose would satisfy (rules 1
  and 12).

### D7 — What this does not decide

ADR-0187's remaining deferrals are untouched: `coder`/`tester` dispatch, Gate 5.06, and `--autopilot`
runs. Gate 5.06 in particular is now the last skill-level review site still deferred, and its stated
reason is verified to hold: its CRITICAL/IMPORTANT/SUGGESTIONS taxonomy is genuinely different from
the wrapper's, in a way `security-audit`'s never was (M1). Whoever takes it up should expect the
`deep-refactor` shape of analysis, not this one.

## Alternatives considered

**A1 — Leave `security-audit` on Claude and decline the wiring, as ADR-0194 declined it for
`deep-refactor`.** The symmetric outcome, and the one a reader expecting consistency would predict.
Rejected on measurement: every load-bearing objection ADR-0194 raised is absent here. Its P3 (the
substituted output authorises source edits with no intervening triage) has no counterpart — this
skill is report-only end to end by ADR-0056 §D4, so no synthesised field gates anything. Its
whole-tree-scope objection applies to one of three code paths, and D4 keeps that path on Claude
rather than building the mode. Its "four more prompt copies of non-negotiable guard text" objection
becomes one focus block whose only content-bearing list is mechanically pinned against its twin. Its
silent-skip objection is inverted: an inline dispatch with `AskUserQuestion` available cannot skip
silently. And its frequency argument cuts the other way — low volume is what makes an elevated-effort
run affordable here. Declining would also leave the step's central property resting on an instruction
the dispatcher applies to itself (M4) when a structural alternative is one flag away.

**A2 — ADR-0187-shaped substitution: offer Codex with the wrapper unchanged, default to Claude.**
The cheapest option, and the one that requires no wrapper change at all. Rejected on two counts.
First, faithfulness: with the fixed five-item checklist, choosing Codex silently converts Step 2 from
a seven-class security review into a general review with security as one bullet of five, and files
the result in a report section declared security-only — a downgrade in the exact dimension the step
exists for, invisible to anyone reading the report afterwards. Second, framing: defaulting to Claude
keeps the weaker diversity guarantee as the norm at the one site whose entire purpose is the stronger
one, which is precisely the confusion ADR-0194 asked this ADR to resolve rather than inherit.

**A3 — Run Codex *alongside* the Claude reviewer, as a genuine two-model second opinion.**
Superficially the most attractive option at this site — the step is literally named "Separate-AI
review", and two independent reviews of security-sensitive code is a real quality gain, not a
rhetorical one. Rejected on Stefano's founding constraint, quoted verbatim in ADR-0187: "lo scopo è
risparmiare tokens in claude code, quindi codex deve sostituire e non affiancare per una seconda
valutazione". It also spends both budgets to satisfy a requirement that one of them satisfies alone,
and it would make the report's single "Model used" field ambiguous without a schema change. Recorded
rather than dismissed, because if that constraint is ever relaxed this is the option to reopen first,
and this site is where it would pay best.

**A4 — Add a whole-tree scope (`--diff-scope tree`) so Codex covers the no-diff case too.**
Rejected. It is the same mode ADR-0194's A1 rejected, and nothing measured since has changed its
premise: all three existing scopes resolve to a `git diff`, so a tree mode is a different content
path wearing the same flag. The alternative implementation — an agentic `codex exec --sandbox
read-only` run that explores the repository itself instead of receiving interpolated text — remains
the unmeasured premise ADR-0194 explicitly declined to build on, and this ADR does not need it: the
Claude branch covers that case today with an agent that already holds the file-reading tools. Keeping
the wrapper diff-shaped also keeps A1's rejection reason intact for `deep-refactor`, which would
otherwise be quietly undermined from a different ADR.

**A5 — A free-text `--focus <text>` or `--brief-file <file>` passthrough instead of an enumerated
value.** The strongest argument for it is real and worth stating: passthrough creates *zero* new
prompt copies, since the security brief would live only in the skill and be forwarded, whereas D3's
enumerated block is a second copy of that list. Rejected anyway, because the copy is the cheaper
problem. Passthrough moves the actual prompt content into a model-composed shell argument resolved at
runtime: nothing can pin before the run what will be sent, nothing can verify after it what was, and
the wrapper's exit-2 bad-invocation contract degrades to accepting any string. It also puts a
caller-supplied fragment upstream of the confidence filter and output instructions the wrapper's
contract depends on. D3's copy, by contrast, is a fixed list in a file that a harness can compare
against its twin — a known duplication with a check beats an unknown one without.

**A6 — Make Codex the only backend at Step 2 and drop the Claude branch.** Rejected. Codex
availability is not guaranteed — the entire availability cascade exists because it is not — the
whole-tree case has no Codex path at all (D4), and SG1's needle would go red, which is the harness
correctly objecting: a Step 2 that cannot name a model pin has no defined behaviour when the external
process is unavailable. The fallback path is part of this step's contract, not a legacy branch.

## Consequences

### Positive

- The step's central requirement stops depending on the dispatcher reasoning correctly about its own
  model. A different-vendor process is different from the dispatcher *and* from whatever model wrote
  the code — the case M4's conditional pin can silently get wrong.
- An `opus`, `effort: high` review dispatch over a diff leaves the Claude budget at a site invoked
  deliberately and infrequently. Cost and correctness point the same way here, which is rare enough
  in this system to be worth naming.
- ADR-0187's deferral list loses the item ADR-0194 identified as the one worth taking up, decided
  rather than aged, and the remaining items are separated by verified reasons rather than a single
  clause covering three sites.
- The report's "Model used" line becomes producer-emitted evidence instead of dispatcher
  recollection (D5), and RTF's reports inherit the same provenance.
- One list of the Claude/Codex prompt duplication acquires an automated coupling check — the first
  such check since ADR-0187 declared that exposure and left it open.
- ADR-0194's flagged unverified premise turns out not to be on this path at all (M5), so no new
  Workflow-execution assumption is created by adopting this.

### Negative

- **A third prompt copy in `codex-reviewer.sh`**, coupled only at the vulnerability-class list.
  ADR-0187's declared drift exposure grows in absolute terms even though its worst part, at this one
  site, is now checked.
- **The security review moves to a model nobody here has evaluated for security review quality**, on
  a site where a miss is the most expensive miss the system can make. This is unmeasured and, as with
  ADR-0194's equivalent disclosure, cannot be measured before building the mode and spending live
  quota. D3's effort elevation is derived from the cost pin's own stated justification (M6), not from
  a quality measurement, and should not be read as one.
- **The Codex path's confidence filter is enforced in code, the Claude path's only in a prompt.** The
  thresholds are identical by design, so the intent matches; in practice the Codex path will drop a
  MAJOR-at-70 security finding that a Claude reviewer might have reported in spite of its own
  instruction. Stricter enforcement is not self-evidently the safer direction at a security site, and
  this is a behavioural difference between the two backends that no amount of contract-matching
  removes.
- **The strengthened guarantee is scope-dependent.** The whole-tree path keeps the conditional pin
  and everything M4 says about it. That path is narrower than the brief's wording suggests (D4 step
  2 covers the ordinary pre-release audit), but it is the "audit this entire existing codebase"
  invocation, which is a real and important use.
- **One more interactive ask** in a skill that had exactly one gate. Bounded to once per invocation
  and placed where the operator can see the scope it applies to, but it is added friction in a
  ten-step protocol that already asks for a human checklist.
- Nothing here is implemented. Until the implementation pass lands, `security-audit` behaves exactly
  as it does today, and this ADR is a decision that a future session must still execute.

### Neutral

- No manifest field and no schema bump. `use_codex_review` remains a `concept-to-code` manifest
  field with the meaning ADR-0187 gave it and the timing ADR-0193 gave it; this skill resolves no
  manifest and does not read it.
- The report-only posture is untouched (ADR-0056 §D4). No Codex finding can authorise an edit, and
  the skill still stages nothing but its own report at its existing commit gate.
- No new entry in `hitl-gates.md`: this skill is outside the chain and its gates are local to it.
- The wrapper's two modes, availability cascade, exit-code contract and deployed location at
  `~/.claude/hooks/codex-reviewer.sh` are unchanged; `--focus` is additive and the five ADR-0187
  sites are byte-identical without it.
- Gate 5.06, `coder`/`tester` dispatch and `--autopilot` remain deferred exactly as ADR-0187 left
  them (D7).

## Verification

This ADR changes no file, so verification is about its premises rather than about a diff.

**Verified 2026-09-06 by reading the files, not by trusting a prior ADR's summary of them (rule 13):**

- Step 2 dispatches the stock `reviewer` with a brief override and a model-pin override, and no
  output-format override; `reviewer.md`'s Output Format is BLOCKER/MAJOR/MINOR/NIT with `path:line`
  and a one-line verdict; `codex-reviewer.sh`'s review-mode `--output-schema` enumerates the same
  four severities and its formatter renders the same shape (M1).
- CRITICAL / IMPORTANT / SUGGESTIONS occurs in `hitl-gates.md`'s two Gate 5.06 inline reviewer
  prompts and in that gate's aggregation instruction, and nowhere in `security-audit/SKILL.md`;
  P1/P2/P3 with `risk_level` and `fix_type` is `deep-refactor`'s schema (M1).
- Zero case-insensitive `codex` matches anywhere under `staging/plugin/skills/security-audit/`.
- Zero references to `security-audit` anywhere under `staging/plugin/skills/` outside its own
  directory: it is invoked standalone, by a human, and no chain or autopilot path reaches it (M6).
- The wrapper's fixed five-item checklist and the absence of any focus/prompt/brief flag (M2); its
  three `--diff-scope` values and their `git diff` / `git show` resolution, including `uncommitted` →
  `git diff HEAD`, which excludes untracked files; and its empty-diff branch, which writes a
  "nothing to review" report and exits 0 (M3).
- Its model/effort cost pin and the comment justifying it on high-volume automated dispatch (M6).
- `security-audit/SKILL.md` contains no Workflow reference; its Step 2 dispatch-site marker declares
  `class=inline`; its hard constraints require an orchestrator session. ADR-0193's 2026-09-06
  correction records a live, successful `codex exec` through `~/.claude/hooks/codex-reviewer.sh` from
  exactly that context (M5).
- `sync-to-claude.sh` deploys `plugin/scripts/codex-reviewer.sh` to `hooks/codex-reviewer.sh` and
  `plugin/skills/security-audit/SKILL.md` to `skills/security-audit/SKILL.md`, so both halves of this
  design reach `~/.claude/`.
- ADR-0049's own text: the generator must not be the verifier because "the accept decision is made by
  the same process that produced the thing being accepted" — the framing ADR-0056 §D6 reuses, matched
  rather than assumed (M4).
- Every harness constraint listed in D6, read from the assertion bodies: SG0's awk extraction window,
  SG1's `model: opus` / `model: sonnet` literal, SG2-SG5's needles, SD11's exact ten-heading count,
  SE3's dispatch-verb predicate with its "never" exclusion, DC21's frozen dispatch-site baseline
  containing `security-audit-reviewer`, and the absence of any `# plant:` declaration in
  `sast-security-audit.test.sh`.

**Assumed, not verified — and each is a premise the implementation pass must measure, not inherit:**

- That Codex at an elevated reasoning effort produces a security review of at least comparable depth
  to `opus` at `effort: high` on the same diff. Not measurable without building `--focus security`
  and spending live quota, which is why the Claude branch stays first-class rather than becoming a
  legacy path.
- That `-c model_reasoning_effort=<elevated>` is accepted alongside `-m` on this call the way the
  current pin is. The existing pin proves the mechanism, not the specific value.
- The exact elevated model and effort values, which are deliberately not written into this ADR: they
  are read from the live Codex CLI and configuration at implementation time.
- That a per-dispatch `model:` override on the Claude branch leaves `reviewer.md`'s frontmatter
  `effort: high` undisturbed. Inherited from ADR-0193's own disclosed, still-unmeasured expectation;
  it applies to today's Step 2 exactly as it applies to RTF, and is not made worse here.

**Not verified, and deliberately not on this path:** whether a Workflow stage can execute
`codex-reviewer.sh`. ADR-0194 flagged it for whoever took up this site; M5 shows this site dispatches
inline, so the question stays open for Step 5's Workflow path and is not resolved or depended on
here.

## References

- `staging/plugin/skills/security-audit/SKILL.md` — Step 2, its brief, its conditional model pin,
  the report schema's "Model used" line, and the orchestrator-session-only constraint
- `staging/plugin/scripts/codex-reviewer.sh` — the two modes, the three diff scopes, the fixed
  five-item prompt, the empty-diff exit-0 branch, the confidence-filtering formatter, the cost pin
- `staging/plugin/agents/reviewer.md` — the Output Format taxonomy Step 2 inherits unchanged
- `staging/plugin/skills/review-triage-fix/SKILL.md` — Step 0 item 6's ask, and Step 1's
  exit-0 / exit-3 branch shape, the idiom D2 reuses
- `staging/plugin/skills/concept-to-code/references/hitl-gates.md` — Gate 5.06's
  CRITICAL/IMPORTANT/SUGGESTIONS taxonomy, the one ADR-0187's clause actually described
- `staging/plugin/scripts/tests/sast-security-audit.test.sh` — SG0-SG5, SD11, SE3
- `staging/plugin/scripts/tests/dispatch-completion.test.sh` — DC21's frozen dispatch-site baseline
- `staging/sync-to-claude.sh` — the PAIRS entries deploying both the wrapper and the skill
- `docs/architecture/ADR-0187-codex-review-gate.md` — the deferral, the wrapper's contract, the
  substitute-never-accompany constraint
- `docs/architecture/ADR-0193-codex-review-choice-at-dispatch.md` — dispatch-time asking, and the
  live-verified `~/.claude/hooks/codex-reviewer.sh` invocation path
- `docs/architecture/ADR-0194-codex-substitution-not-extended-to-deep-refactor.md` — the unbundling
  and the open question this ADR answers
- `docs/architecture/ADR-0056-110-sast-security-audit.md` — §D4 report-only, §D6 the separate-AI
  review step
- `docs/architecture/ADR-0049-103-generator-verifier-separation.md` — the framing §D6 reuses
- `docs/architecture/ADR-0124-346-spec-pointer-baseline.md` — a floor with slack absorbs its own
  plant, the reason DC21's declaration set is a frozen baseline rather than a count
