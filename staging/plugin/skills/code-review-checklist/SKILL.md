---
name: code-review-checklist
description: This skill should be used when a structured code review of recent changes is needed, producing findings grouped by severity. Used by the reviewer agent.
---
<!-- skill-coverage-exempt: prompt template only — an output-format instruction for the reviewer agent, with no path, script or cross-file contract to pin (ADR-0084). -->

Run `git diff` and analyze recent changes.

Output by severity:

## BLOCKER (fix before merge)
## MAJOR (should fix)
## MINOR (consider fixing)
## NIT (style/preference)

For each issue: `file:line` + description + suggested fix.

Mandatory categories: Security (input validation, secrets, auth), Correctness (logic, edge cases, error handling), Performance (N+1, blocking calls), Consistency (patterns, ADRs), Test coverage.
