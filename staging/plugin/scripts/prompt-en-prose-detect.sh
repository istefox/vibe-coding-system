#!/usr/bin/env bash
# humanize-en: prompt-en-prose-detect.sh — UserPromptSubmit hook, bash 3.2-clean
# Detects EN prose-writing intent in the user prompt.
# Match: emit additionalContext JSON reminder (~80 tokens).
# No match: exit 0 silent (zero overhead, zero tokens added).
# Exit: 0 always (fail-open).
set -u

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('prompt', ''))
except Exception:
    print('')
" 2>/dev/null || true)

[ -z "$PROMPT" ] && exit 0

# Keyword detection: EN prose writing contexts
MATCH=$(echo "$PROMPT" | grep -iE \
  '(README|pull request|PR description|issue (body|comment|text)|reddit|hacker news|hn post|forum (post|thread)|blog post|changelog|release notes|draft.*(publish|post)|write.*(post|article)|substack|dev\.to|newsletter|announcement|product hunt)' \
  2>/dev/null || true)

[ -z "$MATCH" ] && exit 0

# Emit additionalContext — compact reminder (~80 tokens, no file link to avoid cache invalidation)
python3 -c "
import json
ctx = (
    'EN prose detected. Apply humanize-en rules: '
    'no em-dash (use comma or period instead), '
    'no delve/tapestry/leverage/foster/showcase/pivotal/seamless, '
    'no paragraph openers Additionally/Moreover/Furthermore, '
    'vary sentence length, '
    'active voice and name the actor, '
    'use is/has not serves-as/stands-as, '
    'no chatbot closers, specific details over vague claims. '
    'After drafting run /skill humanize-en for a final pass.'
)
print(json.dumps({'additionalContext': ctx}))
" 2>/dev/null || true

exit 0
