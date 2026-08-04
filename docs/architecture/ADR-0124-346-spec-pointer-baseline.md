# ADR-0124 — SP5 stops being a count and becomes a per-manifest frozen baseline

- **Status:** Accepted
- **Date:** 2026-08-04
- **Issue:** #346
- **Supersedes in part:** the `HIST_FLOOR` mechanism introduced alongside ADR-0106's `SP5` and
  amended by issue #342
- **Files:** `staging/plugin/scripts/tests/spec-pointer-archive.test.sh`

## Context

`SP5` guards ADR-0075's rule: a historical manifest must not lose its `artifacts.spec` slot
pointer. It did so by comparing a **count** (`SLOT`) against a hand-maintained floor
(`HIST_FLOOR`).

A floor absorbs its own plant whenever the corpus carries slack. `plant-check.sh` removes one slot
pointer, so `SLOT` drops by one; if `SLOT - HIST_FLOOR >= 1` the assertion still passes and pins
nothing. Issue #346 observed this live during the #287 chain, and the file's own comment already
named the target: *"a floor that has to be bumped by hand after every such chain is the design #346
has to replace."*

## The measurement, which changed the remedy

Corpus of 48 manifests on 2026-08-04: **46 `completed`** (41 at the slot, 5 repointed to archives)
and **2 `aborted`** (1 at the slot, 1 with `spec: null`). `SLOT = 42`.

There are **two independent sources of slack, not one**:

| # | source | effect | closed by the issue's own remedy? |
|---|---|---|---|
| 1 | a chain in flight between Step 1 and Step 7.0b holds a filled slot pointer | `+1`, transient | yes |
| 2 | a chain that **aborts** keeps its slot pointer for good — Step 7.0b runs on completion only | `+1`, permanent | **no** |

Issue #346 names source 1 and proposes widening the in-flight exclusion from `spec: null` to *"not
terminal"*. That is correct and incomplete. Source 2 is not hypothetical: #288's aborted chain is
already one instance in 48 manifests, and it is precisely the `+1` that forced the hand bump
`HIST_FLOOR` 41 → 42 on 2026-08-03.

**A nightly run that halts mid-feature produces an aborted chain.** So the issue's remedy would be
re-broken by the first interrupted night — the very scenario the guard exists to make readable.
This is the fourth time in this repository's record that measuring an issue changed its premise
rather than merely confirming it.

## Decision

### D1 — The count is retired; `SP5` asserts a per-manifest property

`SP5` now checks a **frozen baseline**: the basenames of every manifest whose `artifacts.spec`
matched `*/SPEC.md` at freeze time (42 entries). For each, the file must still exist and must still
point at the slot.

A property no count can express — *this specific manifest still points at the slot* — and one that
corpus growth, in-flight chains and aborted chains all leave untouched **by construction**. The
plant therefore fires deterministically, and nothing is ever bumped by hand again.

### D2 — It also closes the weakness the file had already disclosed

`spec-pointer-archive.test.sh` disclosed that a floor "is masked by concurrency: a historical
manifest rewritten WHILE another chain sits at the slot leaves `SLOT` unchanged." A per-manifest
check cannot be masked by concurrency, because it never looks at a total. The disclosure is
retired along with the mechanism that needed it.

### D3 — A missing file and a repointed pointer are distinct reasons

`baseline_check()` reports which manifests failed and **why** — `the file is gone` versus
`repointed away from the slot, now: <value>`. "The record was deleted" and "the record was
rewritten" want different remedies, and a bare count cannot say which happened. That is the same
distinction ADR-0076 draws between ABSENT, INVALID and UNREADABLE, applied one level down.

### D4 — The baseline is a heredoc in the file, not a separate artifact

The list sits next to the assertion that reads it. A separate file invites the two to drift apart,
which is the defect class this repository keeps re-finding (ADR-0095, ADR-0099, ADR-0109 — a
producer in one place and a consumer in another with nothing checking they meet).

### D5 — The pointer reader is reused, never rewritten

`baseline_check()` extracts `artifacts.spec` with the exact idiom `count_pointers()` already uses.
A second reader would be two answers to one question (ADR-0069's rule), and #218 is the standing
example of what an independently-invented parser costs.

### D6 — A new entry is never required, and that is what makes the freeze cheap

A chain completing under ADR-0106 repoints to its own archive, so it never joins this set. A chain
that aborts keeps a slot pointer but is not a record the baseline was frozen to protect. The list
needs editing only if a manifest is legitimately deleted, which ADR-0075 declines to do.

### D7 — The freeze precondition, verified rather than assumed

Freezing is sound only while no chain is in flight with a filled slot pointer; an in-flight
manifest frozen in would legitimately fail at its own Step 7.0b. **Verified zero in flight at
generation time**, reading both terminality axes per ADR-0113. The re-derivation one-liner is
recorded in the file so a future reader can diff rather than trust.

## Verification

- `SP7` is a **denominator guard**: an unloaded heredoc leaves the baseline empty and `SP5` green
  having checked nothing, so full coverage and no coverage would be the same output. Labelled a
  forward guard in the harness — it passes before and after and is not fix evidence.
- `SP8` / `SP8b` are **both directions on fixtures**, and `SP8` is #346's acceptance criterion
  executed rather than argued: a fixture carrying an in-flight chain at the slot *and* a repointed
  non-member — the two things that used to move the floor — must leave the verdict untouched.
- The existing `plant: SP5` needed no edit. Run in isolation it produces `PASS=16 FAIL=1` with only
  `SP5` red, so the failure is attributable to `SP5` alone rather than collected by a neighbour —
  which matters because its replacement names a **real** archive, keeping `SP5d` green.
- `Z1`'s floor raised 13 → 16 in the same change. Left at 13 it would have carried three units of
  slack and three assertions could have vanished while it stayed green — **the exact defect this
  ADR removes from `SP5`, reintroduced in the same file by the change that removes it.**

## Known consequences, recorded rather than discovered

- **The baseline is a snapshot.** A manifest legitimately deleted turns `SP5` red. Correct under
  ADR-0075, and it will read as a regression the first time.
- **`SP8` carries no plant**, and the reason is the assertion's shape: it is a negative claim
  ("these additions must not reach the verdict") and deleting a mechanism cannot break "X must not
  happen" (ADR-0112). The mutation that would redden it is a structural rewrite of the loop, not
  the one-line replacement registry v1 accepts (issue #305). `SP8b` plants the same function in the
  positive direction; what stays unpinned is a structural property with no branch to break.
- **`SP5`'s plant remains subject to issue #355**, the prefix match that lets `SP5b`, `SP5c` or
  `SP5d` satisfy it. Verified on this corpus that the plant reddens none of them, so attribution
  holds today; #355 is what would make it hold in general, and it is open.
- **Nothing checks that the freeze precondition was honoured** at the moment the list was
  generated, beyond this ADR and the note in the file.
