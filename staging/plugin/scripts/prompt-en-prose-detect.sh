#!/usr/bin/env bash
# humanize-en: prompt-en-prose-detect.sh — UserPromptSubmit hook, bash 3.2-clean
# Detects EN prose-writing intent in the user prompt.
# Match: emit additionalContext JSON reminder (~80 tokens).
# No match: exit 0 silent (zero overhead, zero tokens added).
# Exit: 0 always (fail-open).
set -u

INPUT=$(cat)
# VCS-045: jq (~5ms startup) replaces the python3 json.load round-trip (~30-50ms) every
# other hook in this setup already uses jq for. Empty stdin or malformed JSON both yield
# empty via `// empty`, matching the old try/except's fail-silent behaviour.
PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // empty' 2>/dev/null || true)

[ -z "$PROMPT" ] && exit 0

# Keyword detection: EN prose written for an outside audience.
# Two conditions in AND — a writing verb AND a publication target. Matching the target alone
# fires on any message that merely mentions Reddit or a forum, which is what this hook used to
# do. Internal targets (README, PR, issue, changelog, release notes) are deliberately absent:
# those are written plainly, no humanize pass (see ~/.claude/CLAUDE.md, ADR-0040).
# "post" is NOT a verb here — it is far more often the noun in "a reddit post".
VERB=$(echo "$PROMPT" | grep -iE \
  '(write|draft|compose|rewrite|publish|announce|humanize|polish)' \
  2>/dev/null || true)

[ -z "$VERB" ] && exit 0

TARGET=$(echo "$PROMPT" | grep -iE \
  '(reddit|hacker news|hn post|forum (post|thread)|blog post|substack|dev\.to|newsletter|announcement|product hunt|social (post|media))' \
  2>/dev/null || true)

[ -z "$TARGET" ] && exit 0

# Emit BOTH the top-level additionalContext key (legacy shape this script has always
# used) and the documented hookSpecificOutput envelope (issue #38 finding 5 — verified
# during planning against code.claude.com/docs, "Add context for Claude" section: the
# nested hookSpecificOutput.additionalContext form is the only documented valid shape
# for a UserPromptSubmit context injection; a bare top-level key is not documented
# anywhere). Emitting both is a zero-cost safety net — no live probe confirms which
# shape the currently-installed Claude Code version actually reads (ADR-0034 §D4/§3.4).
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
print(json.dumps({
    'additionalContext': ctx,
    'hookSpecificOutput': {
        'hookEventName': 'UserPromptSubmit',
        'additionalContext': ctx
    }
}))
" 2>/dev/null || true

exit 0
