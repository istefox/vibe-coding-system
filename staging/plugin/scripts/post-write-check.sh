#!/usr/bin/env bash
# ADR-0039 D1-D4: post-write-check.sh — PostToolUse hook on Edit|Write, bash 3.2-clean.
#
# Runs a fast, file-scoped correctness check on the file just written and reports errors back
# to the model. Zero LLM tokens. Sibling of auto-format.sh, and ordered after it in
# settings.json so formatting noise is gone before this looks at the file.
#
# Contract:
#   - ADVISORY, NEVER BLOCKING (D2). Always exits 0. Never emits `decision`, which is what
#     separates advisory from blocking. Mid-implementation code is legitimately incomplete;
#     blocking on it would stall a coder on code it was about to finish.
#   - ONE FILE, NEVER THE PROJECT (D3). No project-wide type check: too slow per write, and
#     mostly noise about symbols that do not exist yet on a half-finished tree.
#   - SYNTAX ONLY, NO LINTERS (D4, revised during implementation). Every engine here answers one
#     question: does this file parse? Nothing else. External linters were tried and removed: two
#     out of two produced false positives under an "error severity only" rule, because a linter's
#     severity reflects its configuration, not the correctness of the file.
#       * swiftlint fails `let x = 1` with identifier_name (error) — the name is under 3 chars.
#       * shellcheck fails `echo ok` with SC2148 (error) — no shebang in a fragment.
#     Both files are fine. Style belongs to auto-format.sh and to the reviewer; this hook only
#     reports things that are true everywhere, on every machine.
#   - Determinism follows from that: the result no longer depends on which tools happen to be
#     installed. shellcheck is absent on the author's macOS and present on the CI runner, which
#     is exactly how the second false positive was found.
#
# Output channel — the one part that is not obvious:
#   PostToolUse stdout on exit 0 goes to the debug log, NOT into context. Only UserPromptSubmit,
#   UserPromptExpansion and SessionStart add stdout to context (code.claude.com/docs/en/hooks).
#   The model sees a PostToolUse hook only through hookSpecificOutput.additionalContext. Getting
#   this wrong is what made post-md-tells-hint.sh a no-op for its entire life (ADR-0040).
#
#   Unlike prompt-en-prose-detect.sh, this script emits ONLY the nested envelope. That script
#   emits a dual form for UserPromptSubmit for a historical reason (ADR-0034 D4); for PostToolUse
#   the nested form is the only documented shape, so there is nothing to hedge against.

set -u

INPUT=$(cat 2>/dev/null) || INPUT=""
[ -z "$INPUT" ] && exit 0

FILE_PATH=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('file_path', ''))
except Exception:
    print('')
" 2>/dev/null || true)

[ -z "$FILE_PATH" ] && exit 0
[ -f "$FILE_PATH" ] || exit 0   # written then deleted, or never landed on disk

ERR=""

# capture <label> <command...> — run a check, keep its output only if it fails.
capture() {
  _label="$1"; shift
  _out=$("$@" 2>&1)
  if [ "$?" -ne 0 ]; then
    [ -n "$ERR" ] && ERR="$ERR
"
    ERR="$ERR[$_label]
$_out"
  fi
}

case "$FILE_PATH" in
  *.sh|*.bash)
    capture "bash -n" bash -n "$FILE_PATH"
    ;;
  *.py)
    # cfile=/dev/null on purpose: `python3 -m py_compile` would write __pycache__ into the
    # project tree. A check must not leave anything behind.
    capture "py_compile" python3 -c \
      "import py_compile,sys; py_compile.compile(sys.argv[1], cfile='/dev/null', doraise=True)" \
      "$FILE_PATH"
    ;;
  *.json)
    if command -v jq >/dev/null 2>&1; then
      capture "jq" jq empty "$FILE_PATH"
    else
      capture "json" python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$FILE_PATH"
    fi
    ;;
  *.yml|*.yaml)
    # PyYAML is not in the stdlib. Without it there is no parse check to run, and reporting an
    # import failure as a file defect would be the same false-positive class as the linters.
    if python3 -c "import yaml" >/dev/null 2>&1; then
      capture "yaml" python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$FILE_PATH"
    fi
    ;;
  *.swift)
    command -v swiftc >/dev/null 2>&1 && capture "swiftc -parse" swiftc -parse "$FILE_PATH"
    ;;
  *)
    exit 0
    ;;
esac

[ -z "$ERR" ] && exit 0

FILE_PATH="$FILE_PATH" ERR="$ERR" python3 -c "
import json, os
ctx = 'post-write check failed on %s:\n\n%s\n\nFix it in the next edit if it is a real defect. This check is advisory and never blocks.' % (
    os.environ['FILE_PATH'], os.environ['ERR'])
print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'PostToolUse',
        'additionalContext': ctx
    }
}))
" 2>/dev/null || true

exit 0
