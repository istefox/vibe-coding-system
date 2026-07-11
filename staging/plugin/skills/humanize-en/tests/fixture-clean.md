# Clean Fixture

This document has no AI tells. It was written by a human with deliberate style choices.

The system saves files to disk on every edit. Three retries happen before a write fails. Short sentences work well here.

Use `git diff` to check what changed. The output shows added lines in green, removed lines in red.

The API returns JSON with two fields: `status` (string) and `data` (object). If `status` is `error`, check `data.message` for the reason.

Run the tests before opening a PR. If any fail, fix them first.
