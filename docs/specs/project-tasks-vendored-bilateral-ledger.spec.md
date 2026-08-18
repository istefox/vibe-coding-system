# SPEC — project-tasks becomes a vendored chain member with a bilateral GitHub issue ledger

**Topic slug:** project-tasks-vendored-bilateral-ledger

## Objective

`TODO.md` becomes the durable answer to *what is open on this project* — everything the roadmap
does not order, everything GitHub holds in detail, and everything a coding session observed and
would otherwise lose at the next `/compact`. The skill that maintains it stops being a private
artifact on one machine and becomes a component of the system, with the same source, deployment,
test and record obligations as every other one.

Three things change together, and each is load-bearing for the others:

1. **The skill is vendored.** It lives under `staging/`, deploys through `sync-to-claude.sh`, is
   covered by a harness with planted assertions, and carries an ADR. Today it exists only at
   `~/.claude/skills/project-tasks/`, which is why its own known defect is recorded in its own
   ledger as *not fixable while that stands*.
2. **The ledger becomes bilateral with GitHub.** GitHub holds the issue: the analysis, the
   proposed solution, the measurements. `TODO.md` holds one line per open issue that points at it,
   so a session can read the index cheaply and fetch the full text when it needs to. A local entry
   captured mid-session can be promoted to a GitHub issue through a gate.
3. **The ledger describes the work in flight.** When the project has a SPEC, a plan and ADRs, the
   ledger names the steps that remain inside the feature currently being built — derived from those
   artifacts, not copied from the roadmap.

## Measured premises

Re-derived 2026-08-17 from the current tree. Every number below is a snapshot of that day and is
to be re-derived before it is relied on again (CLAUDE.md rule 13).

| Fact | Value |
|---|---|
| Open GitHub issues in this repository | 66 |
| Closed GitHub issues | 142 |
| `TODO.md` entries | 27 (`prefix=VCS lastId=27`) |
| of which open | 12 |
| of which already cite a `#NNN` | 20 |
| `selftest.sh` | 27 passed, 0 failed |
| `scan.sh` bash-4-only constructs | none |
| `MARKER` records from the 2026-08-11 run | 2, both false positives |

**The ledger currently tracks 12 open items while GitHub holds 66.** It sees roughly 18% of what
is open, and nothing about the file says so. That gap is the objective's first half stated as a
number.

**Two existing ledger entries are this feature, and one of them is itself stale — which is the
first thing this feature has to get right.** `VCS-022` records that the skill is *neither vendored
nor declared*, that the registry holds five entries, and that every `sync-to-claude.sh --apply`
prints it under *"deployed skill(s) neither vendored nor declared"*. **Re-derived 2026-08-17: it IS
declared**, at `staging/sync-to-claude.sh:116`, the registry holds **six** entries, and tonight's
`--apply` printed no such report line. So the work inverts: vendoring means **deleting** that
declaration, in the same change, or a waiver survives its own subject and reads as clean (rule 9).
The entry was a correct snapshot of its day and is not corrected in place (rule 14); it is closed
by this feature with the correction recorded forward. `VCS-023` records that `scan.sh`
matches the literal `BUG` inside prose stating the opposite — a rule-12 defect inside the scanner
whose job is to capture defects — and states in its own text that it is *not fixable in-repo while
`VCS-022` stands*. Both are resolved by this feature or it has not landed.

**One existing rule is inverted by this feature, and must be rewritten rather than contradicted.**
`VCS-027` records that this ledger's declared rule is *"an item with an issue number leaves the
file"*. Measured 2026-08-17, that rule lives in **`TODO.md`'s own header**, not in
`reference/file-format.md`, which never stated it — so a requirement naming the wrong file is
satisfiable by deleting nothing. The bilateral section makes issue-numbered items the largest
section in the file.
`reference/file-format.md` states that rule today; leaving it there means the format document
disagrees with the skill's behaviour on the first run.

**The skill's `description:` is false today.** It claims invocation *"from the concept-to-code or
project-conductor chain before a commit"*. Neither chain names it: `concept-to-code`'s own text
does not, and no staged or deployed `SKILL.md` mentions it. The correction is to make the claim
true by doing the wiring, not to narrow the sentence.

## Scope

**In scope.** The skill tree (`SKILL.md`, `scripts/scan.sh`, `scripts/selftest.sh`,
`reference/*.md`, `templates/TODO.template.md`), its vendoring under `staging/`, its
`sync-to-claude.sh` PAIRS entry, its new harness, the `TODO.md` schema changes, the chain wiring in
`concept-to-code` and `project-conductor`, and the record (ADR, `docs/chain-decisions.md`,
`CLAUDE.md` index line, `PROJECT.md` row).

**Out of scope.** Any change to `PROJECT.md`'s own format or to `project-conductor`'s roadmap
handling; any GitHub label taxonomy; any issue-template work; automatic capture through a `Stop`
hook, which `reference/chain-integration.md` already rejected for a reason this feature does not
revisit.

**Deliberately not vendored.** The deployed tree contains `.remember/` and `.claude/test-cmd`,
left behind by a session that ran with its working directory inside the skill. They are session
litter, not skill content, and vendoring them would put one project's transient state into every
project's deployment.

## Architecture

### Source of truth, stated as a field-level split

GitHub owns the **content** of an issue. `TODO.md` owns what GitHub has no field for. The two never
write the same field, which is why the bilateral design needs no conflict resolution at all.

| Field | Owner | Behaviour on each run |
|---|---|---|
| title, state, labels, body | GitHub | regenerated from `gh` output; never edited locally |
| local priority (`P1`/`P2`/`P3`) | `TODO.md` | preserved verbatim |
| file reference (`path:line`) | `TODO.md` | refreshed best-effort, as today |
| provenance (`src:`, `opened:`) | `TODO.md` | preserved; `opened:` never rewritten |
| promotion state | `TODO.md` | see below |
| roadmap phase pointer | derived | recomputed from `PROJECT.md` each run |

### The five capture sources, with one narrowed

`session`, `marker`, `review`, `git`, `manual` are unchanged in meaning. The `marker` scanner is
narrowed: it matches a marker only in its **declaration form** — `TODO:`, `FIXME:`, `HACK:`,
`XXX:`, `BUG:` with the colon, at a comment opener — never a bare word in running prose. Both
measured false positives were bare words inside sentences explaining the opposite.

Retiring the detector outright was the alternative, and it is what #314 did for a detector at the
same precision. It is rejected here because the failure mode differs: #314's detector produced a
finding a human had to dismiss, while this one produces a ledger entry, and the form that
distinguishes a real marker from prose is mechanical and cheap. The narrowing must be verified in
both directions — the two false positives no longer fire, and a genuine marker still does.

### GitHub read, and what happens when it cannot run

`gh issue list --state open` is the only GitHub call a normal run makes. It is a **checker**: the
caller branches on its exit code.

- **Success** → every open issue appears in the issues section, one line each, grouped by state.
- **Zero issues on a repository that has issues** is indistinguishable from a broken derivation
  from the outside, so the count is guarded: a run that reads zero open issues where the section
  previously held entries reports it as a failure to derive, never as an empty section (rule 7).
- **`gh` absent, unauthenticated, or no remote** → the section is written with an explicit
  `DID-NOT-RUN` marker naming the cause and the remedy, the entries already in the section are left
  **untouched**, and the rest of the run proceeds normally. It is never silently skipped and never
  rendered empty: an unrun check must not read as a clean one (rule 4).

The rest of the skill does not depend on GitHub, so a project with no remote keeps a working
ledger minus one section.

### Promotion: local entry → GitHub issue

The skill never opens or closes an issue on its own. Promotion is proposed, and the operator
decides.

**When it is proposed.** At the approval gate of a **full run** only — never on `quick`, never on
`add`, never on `close`, never on `map`. Those modes exist to be cheap, and a promotion question on
each of them is the friction that stops a gate from being read.

**Which entries qualify.** A `P1` is proposed on the first full run that sees it. Anything else is
proposed once it has **survived two full runs** — evidence it was not fixed in the session that
recorded it — or once it carries `src:review`, which already means a reviewer declined to fix it.

**What a decline costs.** Nothing, once. A declined proposal is recorded and **never proposed
again**. `reference/chain-integration.md` already rejected automatic capture on the argument that a
noisy ledger stops being read; a gate that re-asks every run is the same failure one level up.

**What survives promotion.** One line, in the issues section, carrying **both** identifiers:

```
- [ ] `VCS-031` → #470 **P2** <title regenerated from GitHub> <!-- src:session opened:2026-08-17 runs:2 promote:2026-08-18 -->
```

The local id survives because commits, notes and prior ledger entries already cite it, and ids are
never reused — dropping it would orphan every existing reference. The entry moves section; it is
not duplicated.

### Steps to be done

When the project has a feature in flight, the ledger describes what remains inside it, derived from
that feature's own artifacts: the SPEC's `R-NN` success criteria, the plan's tasks, and the ADRs the
plan cites. Each step gets one line describing what it is, not merely its title.

**"In flight" is read from the manifest**, not guessed: a manifest under `docs/manifests/` whose
`current_step` and `status` are both non-terminal.

- **No manifest directory, or no non-terminal manifest** → the section is omitted, and the ledger
  says why in one line. Omission with a stated reason is not the same as a section that is quietly
  absent.
- **More than one non-terminal manifest** → the section names them and derives nothing. Guessing
  which feature is "the" one in flight is exactly the ambiguity the rest of this system refuses.

This section describes work **inside** a feature. `PROJECT.md` orders features. Expanding the
roadmap here would make a fourth copy of one list, and copies answering one question must be
extracted, not multiplied (rule 6).

### Relationship to PROJECT.md

`TODO.md` answers *what is open*. `PROJECT.md` answers *in what order*. An issue that is also a
roadmap row appears in `TODO.md` **with a pointer to its phase**, rather than being excluded — the
ledger stays complete, and the pointer is what keeps it from becoming a second roadmap.

### Chain wiring

`concept-to-code` invokes the skill before its commit gate, and `project-conductor` invokes it
between features. Both are the placements `reference/chain-integration.md` already describes as
paste-in snippets that were never applied.

**An open `P1` blocks the commit gate only when the feature being committed introduced it.** A
pre-existing `P1` is reported and does not block. A gate that blocks every commit on a standing
debt is a gate people learn to route around, and a routed-around gate protects nothing.

This wiring is prose a model is asked to follow. It changes the failure *shape*, not the guarantee
— an instruction is not an enforcement (rule 16), and the ADR must say so rather than let a green
harness pinning the text's existence read as proof it is obeyed.

## Data model — `TODO.md`

The header comment and entry anatomy are unchanged except where stated.

```
<!-- project-tasks: prefix=VCS lastId=31 -->
```

**Entry, with the two new provenance keys:**

```
- [ ] `VCS-031` **P2** <text> — `path/file.sh:88` <!-- src:session opened:2026-08-17 runs:2 promote:declined -->
```

| Key | Meaning |
|---|---|
| `runs:<N>` | full runs this entry has survived. Incremented once per full run. Absent means zero. |
| `promote:declined` | the operator declined promotion. Never proposed again. |
| `promote:<YYYY-MM-DD>` | promoted on that date; the entry now carries an issue number. |

Promotion state lives in the entry's own provenance comment rather than in a separate state file:
one file, no second source that can diverge from the ledger it describes, invisible when rendered,
and already protected by the preservation rules.

**Sections**, in order. `GitHub Issues` is new; `Steps` is new and conditional.

| Section | Holds |
|---|---|
| `GitHub Issues` | every open issue, one line, grouped by state; roadmap rows carry a phase pointer |
| `Open Issues` | local entries not yet promoted |
| `In Progress` | what is being worked on now, with the branch |
| `Backlog / To Add` | features and ideas not started |
| `Blocked / Decisions Needed` | needs a decision or an external input |
| `Steps — <feature in flight>` | conditional; derived from that feature's SPEC, plan and ADRs |
| `Project Map` | the stable landmarks |
| `Done` | closed entries, most recent first |

## Edge cases

- **`gh` present but the repository has no remote** — the same `DID-NOT-RUN` path as an absent
  `gh`, with a cause naming the remote rather than the binary.
- **An issue closes on GitHub between runs** — regeneration drops it from the issues section. A
  local entry that had been promoted is not deleted: its line moves to `Done` with the closure date,
  because the local id is still cited elsewhere.
- **An issue is reopened** — it returns to the issues section on the next run; nothing local is
  needed.
- **A promoted entry's issue is deleted on GitHub** — the pointer resolves to nothing. Report it
  on the entry rather than dropping either identifier.
- **The 66 open issues make the section long** — that is the intended shape. Length is not noise
  when every line is a distinct open thing; the archive rule already caps `Done`, and nothing else
  in the file grows without bound.
- **A hand-written entry with no id** — untouched and not renumbered, as today.
- **The file cannot be parsed** — reported, not silently repaired, as today.
- **Two non-terminal manifests** — the steps section names both and derives nothing.
- **A run that reads zero open issues where the previous file held some** — a broken derivation,
  reported as such.

## Success criteria

- [ ] R-01 — the skill tree is vendored under `staging/` and deploys through `sync-to-claude.sh`;
      a dry run after deployment reports no difference between staging and the deployed copy.
- [ ] R-02 — the `deployed-only: project-tasks` declaration is removed from `sync-to-claude.sh` in
      the same change that vendors the skill, so no waiver survives its own subject; a stale-waiver
      check confirms none remains.
- [ ] R-03 — `.remember/` and `.claude/test-cmd` from the deployed tree are absent from the
      vendored copy, and a check asserts their absence rather than relying on the copy being done
      carefully.
- [ ] R-04 — every open GitHub issue appears exactly once in the `GitHub Issues` section, and an
      issue that appears twice or not at all is a detectable failure.
- [ ] R-05 — a run that derives zero open issues where the section previously held entries reports
      a broken derivation, never an empty section.
- [ ] R-06 — with `gh` absent, unauthenticated, or the repository lacking a remote, the section
      carries an explicit `DID-NOT-RUN` marker naming cause and remedy, the entries already there
      are unchanged, and the rest of the run completes.
- [ ] R-07 — title, state and labels are regenerated from GitHub on each run, while local priority,
      file reference and provenance survive verbatim.
- [ ] R-08 — a promotion proposal is rendered only at a full run's approval gate, and only for an
      entry that is `P1`, carries `src:review`, or has `runs:` of at least 2.
- [ ] R-09 — an entry whose provenance carries `promote:declined` is never proposed again, on any
      subsequent run.
- [ ] R-10 — `runs:` is incremented once per full run per entry, and `opened:` is never rewritten.
- [ ] R-11 — after promotion the entry is one line in the `GitHub Issues` section carrying both the
      local id and the issue number; no duplicate line remains in `Open Issues`.
- [ ] R-12 — with exactly one non-terminal manifest present, the steps section is derived from that
      feature's SPEC `R-NN` criteria, plan tasks and cited ADRs, one described line each.
- [ ] R-13 — with no non-terminal manifest, or with more than one, the steps section is omitted or
      names the candidates, and the ledger states which case applied. It is never silently absent.
- [ ] R-14 — an issue that is also a `PROJECT.md` roadmap row carries a pointer to its phase.
- [ ] R-15 — the marker scanner matches a declaration form only; the two measured false positives
      from the 2026-08-11 run no longer fire, and a genuine `TODO:`/`FIXME:` marker still does.
- [ ] R-16 — `reference/file-format.md` documents the new sections and the promotion keys, and the
      superseded rule that an item with an issue number leaves the file is removed from every place
      that states it — measured 2026-08-17, that is `TODO.md`'s own header, not `file-format.md`,
      which never stated it.
- [ ] R-17 — `concept-to-code` invokes the skill before its commit gate and `project-conductor`
      invokes it between features, both stated in their own text.
- [ ] R-18 — a `P1` introduced by the feature being committed blocks the commit gate; a
      pre-existing `P1` is reported and does not block.
- [ ] R-19 — the skill's `description:` frontmatter is true of the shipped system: every chain it
      names does invoke it.
- [ ] R-20 — the skill's hard rules are unchanged and still hold: it never edits source, never
      writes before its approval gate, never deletes user text, never auto-closes an entry, and
      refuses a project root outside the session working directory.
- [ ] R-21 — a harness covers this skill, with every new assertion seen RED against a declared
      plant.
- [ ] R-22 — the record is written: an ADR, a `docs/chain-decisions.md` block, one `CLAUDE.md` index line, and the `PROJECT.md` row (no-test: a documentation obligation no assertion can check beyond its own existence).
- [ ] R-23 — the ADR states which parts of this feature are instructions rather than enforcements (no-test: a claim about how the record is written, not a behaviour a test can execute), naming the chain wiring specifically.
- [ ] R-24 — the skill stays invokable outside the chain: its `description:` keeps the standalone trigger phrases, and every section derived from a chain artifact degrades with a stated reason when that artifact is absent, rather than rendering as if the derivation had found nothing.
