# SPEC — Run the deterministic checks in the target project CI

Source: GitHub issue #108

Depends on issues #100, #101 and #105: the scripts must exist standalone before CI can call them.

## Objectives
1. Give a generated target repo real gates in its own CI, with no agent present.
2. Run those gates **fail-closed** in CI while leaving the hook copies fail-open.

## Scope
In: a `checks` job in `staging/project-templates/ci/ci.yml`; ensuring each check script runs from a plain shell; a new test file in both CI registries.
Out: changing the fail-open contract of any deployed hook.

## Stack
GitHub Actions YAML + bash 3.2 scripts driven by `git diff` alone, with no dependency on Claude Code hook payload JSON.

## Architecture
- Modified: `staging/project-templates/ci/ci.yml` — new `checks` job invoking the secret scan, the dependency scan and the weakening/SUSPECT detectors against the PR diff.
- Possibly modified: the check scripts, to accept a git range in addition to stdin.
- New: test file in both CI registries.

## Data model
None.

## API / Interfaces
Each script must accept a diff source that does not require a hook payload. In CI a finding **fails the job**; blocking is safe there because no agent is mid-task. The ADR must record that this is deliberately a second copy with the opposite failure direction from the hooks, not a replacement for them.

## UI flows
A red `checks` job on the PR.

## Edge cases
- The `ci` job name must remain the required status check — `set-branch-protection.sh` depends on it.
- The existing single-step template behaviour must still work when the optional checks are absent.
- A repo with no test files must not fail the weakening detector.

## Success criteria
- [ ] Each check script runs correctly from a plain shell given only a diff or a git range.
- [ ] The `ci` job name is unchanged and still required on main.
- [ ] The template works with the checks absent.
- [ ] A seeded violation fails the `checks` job.
- [ ] The new test file is registered in BOTH CI registries.
