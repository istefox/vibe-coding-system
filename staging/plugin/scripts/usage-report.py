#!/usr/bin/env python3
"""
usage-report.py — Daily token usage + cache hit rate from Claude Code transcripts.

Scans ~/.claude/projects/**/*.jsonl for usage data in each assistant message.
Shows a daily table with day-over-day deltas. Flags cache hit rate drops >= 5pp
(ADR-0015 validation threshold for prompt-en-prose-detect.sh hook impact).

Also tracks Agent-tool dispatch counts (orchestrator -> sub-agent calls), resolved
to a model via each agent's ~/.claude/agents/<type>.md frontmatter. This is a
DISPATCH COUNT only, not a token cost: Claude Code never persists sub-agent turns
as sidechain entries with their own usage in these transcripts (isSidechain is
always false here), so sub-agent token cost is not locally observable at all.

Usage:
  python3 ~/.claude/scripts/usage-report.py               # last 7 days
  python3 ~/.claude/scripts/usage-report.py --days 30      # last 30 days
  python3 ~/.claude/scripts/usage-report.py --today        # today only, no table
  python3 ~/.claude/scripts/usage-report.py --compact      # one-line Stop-hook hint
  python3 ~/.claude/scripts/usage-report.py --agents       # agent-dispatch report
  python3 ~/.claude/scripts/usage-report.py --agents --by-project
"""

import json
import os
import sys
import glob
from collections import defaultdict
from datetime import datetime, timezone, timedelta

CLAUDE_DIR = os.path.expanduser("~/.claude")
AGENTS_DIR = os.path.join(CLAUDE_DIR, "agents")
CACHE_ALERT_THRESHOLD = 5.0  # percentage points drop to flag (ADR-0015)
MODEL_TIERS = ("opus", "sonnet", "haiku")


def find_jsonl_files():
    pattern = os.path.join(CLAUDE_DIR, "projects", "**", "*.jsonl")
    return glob.glob(pattern, recursive=True)


def parse_transcripts(jsonl_files, since_date=None):
    """Return (daily, agent_by_day_project).

    daily: date_str -> {input, cache_creation, cache_read, output, messages,
                         sessions, agent_dispatches: {subagent_type: count}}
    agent_by_day_project: date_str -> project_slug -> {subagent_type: count}
    """
    daily = defaultdict(
        lambda: {
            "input": 0,
            "cache_creation": 0,
            "cache_read": 0,
            "output": 0,
            "messages": 0,
            "sessions": set(),
            "agent_dispatches": defaultdict(int),
        }
    )
    agent_by_day_project = defaultdict(lambda: defaultdict(lambda: defaultdict(int)))

    for path in jsonl_files:
        project = os.path.basename(os.path.dirname(path))
        try:
            # Quick mtime check to skip very old files
            if since_date:
                mtime = datetime.fromtimestamp(os.path.getmtime(path), tz=timezone.utc)
                if mtime.date() < since_date:
                    continue

            with open(path, "r", encoding="utf-8", errors="replace") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        record = json.loads(line)
                    except json.JSONDecodeError:
                        continue

                    ts = record.get("timestamp", "")
                    if not ts:
                        continue
                    try:
                        day = ts[:10]  # YYYY-MM-DD
                    except Exception:
                        continue

                    if since_date and day < str(since_date):
                        continue

                    message = record.get("message") or {}

                    # Agent-tool dispatch detection (independent of usage presence).
                    content = message.get("content")
                    if isinstance(content, list):
                        for block in content:
                            if (
                                isinstance(block, dict)
                                and block.get("type") == "tool_use"
                                and block.get("name") == "Agent"
                            ):
                                subagent_type = (block.get("input") or {}).get(
                                    "subagent_type"
                                ) or "unknown"
                                daily[day]["agent_dispatches"][subagent_type] += 1
                                agent_by_day_project[day][project][subagent_type] += 1

                    usage = message.get("usage", {})
                    if not usage:
                        continue

                    session_id = record.get("sessionId", path)
                    d = daily[day]
                    d["input"] += usage.get("input_tokens", 0)
                    d["cache_creation"] += usage.get("cache_creation_input_tokens", 0)
                    d["cache_read"] += usage.get("cache_read_input_tokens", 0)
                    d["output"] += usage.get("output_tokens", 0)
                    d["messages"] += 1
                    d["sessions"].add(session_id)

        except (OSError, PermissionError):
            continue

    return daily, agent_by_day_project


def load_agent_model_map():
    """Read ~/.claude/agents/*.md once. subagent_type -> model string exactly as
    declared in frontmatter (e.g. 'opus', 'sonnet', 'haiku'). Built-in agent types
    (Explore, Plan, general-purpose, claude-code-guide, statusline-setup, ...) and
    plugin-qualified ids (e.g. 'pr-review-toolkit:review-pr') have no file here and
    are simply absent from the map — never guessed."""
    mapping = {}
    for path in glob.glob(os.path.join(AGENTS_DIR, "*.md")):
        name = os.path.splitext(os.path.basename(path))[0]
        model = None
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as f:
                in_fm = False
                for line in f:
                    s = line.strip()
                    if s == "---":
                        if not in_fm:
                            in_fm = True
                            continue
                        else:
                            break
                    if in_fm and s.startswith("model:"):
                        model = s.split(":", 1)[1].strip()
                        break
        except (OSError, PermissionError):
            continue
        mapping[name] = model or "unknown"
    return mapping


def resolve_model(subagent_type, agent_model_map):
    return agent_model_map.get(subagent_type, "inherits/unknown")


def rollup_by_model(subagent_counts, agent_model_map):
    """subagent_counts: subagent_type -> count (window totals).
    Returns model_str -> {"count": int, "types": [subagent_type, ...]}, where
    model_str is one of MODEL_TIERS or 'other' (anything not resolved locally)."""
    rollup = defaultdict(lambda: {"count": 0, "types": []})
    for subagent_type, count in subagent_counts.items():
        model = resolve_model(subagent_type, agent_model_map)
        tier = model if model in MODEL_TIERS else "other"
        rollup[tier]["count"] += count
        rollup[tier]["types"].append(subagent_type)
    return rollup


def cache_hit_rate(d):
    total_in = d["input"] + d["cache_creation"] + d["cache_read"]
    if total_in == 0:
        return 0.0
    return 100.0 * d["cache_read"] / total_in


def fmt_tok(n):
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n / 1_000:.0f}k"
    return str(n)


def delta_str(current, previous, pct=False):
    if previous is None:
        return ""
    diff = current - previous
    if pct:
        sign = "+" if diff >= 0 else ""
        return f"({sign}{diff:.1f}pp)"
    sign = "+" if diff >= 0 else ""
    return f"({sign}{fmt_tok(diff)})"


def compact_agent_clause(day_dispatches, agent_model_map):
    if not day_dispatches:
        return None
    total = sum(day_dispatches.values())
    tiers = {"sonnet": 0, "opus": 0, "haiku": 0, "other": 0}
    for subagent_type, count in day_dispatches.items():
        model = resolve_model(subagent_type, agent_model_map)
        tiers[model if model in tiers else "other"] += count
    return (
        f"agents={total}(sonnet:{tiers['sonnet']},opus:{tiers['opus']},"
        f"haiku:{tiers['haiku']},other:{tiers['other']})"
    )


def print_agents_report(daily, agent_by_day_project, sorted_days, agent_model_map, by_project=False):
    print(
        "NOTE: counts are DISPATCHES (Agent tool_use calls on the orchestrator's own\n"
        "transcript) only. Sub-agent TOKEN COST is NOT captured locally — isSidechain is\n"
        "always false in these transcripts, so Claude Code does not persist sub-agent\n"
        "turns with their own usage. Use this report for call-frequency / model-mix\n"
        "visibility only, never for token or cost accounting."
    )
    print()

    window_totals = defaultdict(int)

    print("By day (all projects):")
    for day_str in sorted_days:
        d = daily[day_str]
        dispatches = d["agent_dispatches"]
        if not dispatches:
            continue
        total = sum(dispatches.values())
        for subagent_type, count in dispatches.items():
            window_totals[subagent_type] += count
        parts = " ".join(
            f"{t}:{c}" for t, c in sorted(dispatches.items(), key=lambda kv: -kv[1])
        )
        print(f"  {day_str}  total={total}  {parts}")

    if not window_totals:
        print("  (no agent dispatches in this window)")
        print()
        return

    print()
    print("By subagent_type (window total -> resolved model):")
    print(f"  {'subagent_type':<22} {'model':<18} {'count':>6}")
    for subagent_type, count in sorted(window_totals.items(), key=lambda kv: -kv[1]):
        model = resolve_model(subagent_type, agent_model_map)
        print(f"  {subagent_type:<22} {model:<18} {count:>6}")

    print()
    print("Rollup by resolved model tier (window total):")
    rollup = rollup_by_model(window_totals, agent_model_map)
    for tier in list(MODEL_TIERS) + ["other"]:
        info = rollup.get(tier)
        if not info:
            continue
        types_str = ", ".join(sorted(info["types"]))
        print(f"  {tier:<8} {info['count']:>4}   ({types_str})")

    if by_project:
        print()
        print("By project:")
        project_totals = defaultdict(lambda: defaultdict(int))
        for day_str in sorted_days:
            for project, counts in agent_by_day_project.get(day_str, {}).items():
                for subagent_type, count in counts.items():
                    project_totals[project][subagent_type] += count
        for project, counts in sorted(project_totals.items()):
            parts = " ".join(
                f"{t}:{c}" for t, c in sorted(counts.items(), key=lambda kv: -kv[1])
            )
            print(f"  {project}")
            print(f"    {parts}")

    print()


def main():
    days = 7
    today_only = False
    compact = False
    agents_mode = False
    by_project = False

    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] in ("--days", "-d") and i + 1 < len(args):
            try:
                days = int(args[i + 1])
            except ValueError:
                pass
            i += 2
        elif args[i] == "--today":
            today_only = True
            days = 1
            i += 1
        elif args[i] == "--compact":
            compact = True
            days = 2
            i += 1
        elif args[i] == "--agents":
            agents_mode = True
            i += 1
        elif args[i] == "--by-project":
            by_project = True
            i += 1
        else:
            i += 1

    today = datetime.now(tz=timezone.utc).date()
    since = today - timedelta(days=days - 1)

    agent_model_map = load_agent_model_map() if (agents_mode or compact) else {}

    if agents_mode:
        print(f"Claude Code — Agent Dispatch Report  [{since} → {today}]")
        print(f"Source: {CLAUDE_DIR}/projects/**/*.jsonl")
        print()

        files = find_jsonl_files()
        if not files:
            print("No transcript files found.")
            return

        daily, agent_by_day_project = parse_transcripts(files, since_date=since)
        if not daily:
            print("No usage data found in the requested period.")
            return

        sorted_days = sorted(d for d in daily.keys() if d >= str(since))
        print_agents_report(daily, agent_by_day_project, sorted_days, agent_model_map, by_project=by_project)
        return

    print(f"Claude Code — Token Usage Report  [{since} → {today}]")
    print(f"Source: {CLAUDE_DIR}/projects/**/*.jsonl")
    print()

    files = find_jsonl_files()
    if not files:
        print("No transcript files found.")
        return

    daily, _agent_by_day_project = parse_transcripts(files, since_date=since)

    if not daily:
        print("No usage data found in the requested period.")
        return

    sorted_days = sorted(daily.keys())
    # Filter to requested window
    sorted_days = [d for d in sorted_days if d >= str(since)]

    if today_only:
        today_str = str(today)
        if today_str not in daily:
            print(f"No data for today ({today_str}) yet.")
            return
        d = daily[today_str]
        rate = cache_hit_rate(d)
        total_in = d["input"] + d["cache_creation"] + d["cache_read"]
        print(f"Today ({today_str}):")
        print(f"  Sessions:        {len(d['sessions'])}")
        print(f"  Messages:        {d['messages']}")
        print(f"  Input tokens:    {fmt_tok(d['input'])}")
        print(f"  Cache creation:  {fmt_tok(d['cache_creation'])}")
        print(f"  Cache read:      {fmt_tok(d['cache_read'])}")
        print(f"  Output tokens:   {fmt_tok(d['output'])}")
        print(f"  Total input:     {fmt_tok(total_in)}")
        print(f"  Cache hit rate:  {rate:.1f}%")
        return

    if compact:
        today_str = str(today)
        yest_str = str(today - timedelta(days=1))
        td = daily.get(today_str)
        yd = daily.get(yest_str)
        if not td:
            return  # silent if no today data yet
        rate_t = cache_hit_rate(td)
        parts = [
            f"[usage] {today_str}",
            f"sess={len(td['sessions'])}",
            f"msgs={td['messages']}",
            f"out={fmt_tok(td['output'])}",
            f"cache={rate_t:.1f}%",
        ]
        if yd:
            rate_y = cache_hit_rate(yd)
            diff = rate_t - rate_y
            sign = "+" if diff >= 0 else ""
            parts.append(f"Δcache={sign}{diff:.1f}pp")
            alert = diff < -CACHE_ALERT_THRESHOLD
            if alert:
                parts.append(f"⚠ ADR-0015: cache dropped {-diff:.1f}pp")
        agent_clause = compact_agent_clause(td.get("agent_dispatches"), agent_model_map)
        if agent_clause:
            parts.append(agent_clause)
        print("  ".join(parts))
        return

    # Table header
    col = "{:<12} {:>5} {:>6} {:>8} {:>10} {:>10} {:>8} {:>10}"
    print(
        col.format(
            "Date",
            "Sess",
            "Msgs",
            "Input",
            "CacheNew",
            "CacheHit",
            "Output",
            "HitRate%",
        )
    )
    print("-" * 78)

    prev = None
    prev_rate = None
    for day_str in sorted_days:
        d = daily[day_str]
        rate = cache_hit_rate(d)
        sessions = len(d["sessions"])

        # Build delta strings
        d_in = delta_str(d["input"], prev["input"] if prev else None)
        d_cc = delta_str(d["cache_creation"], prev["cache_creation"] if prev else None)
        d_cr = delta_str(d["cache_read"], prev["cache_read"] if prev else None)
        d_out = delta_str(d["output"], prev["output"] if prev else None)
        d_rate = delta_str(rate, prev_rate, pct=True) if prev_rate is not None else ""

        # Flag if cache hit rate dropped significantly
        alert = ""
        if prev_rate is not None and (rate - prev_rate) < -CACHE_ALERT_THRESHOLD:
            alert = f"  ⚠ cache hit rate dropped {prev_rate - rate:.1f}pp (ADR-0015 threshold: {CACHE_ALERT_THRESHOLD}pp)"

        is_today = day_str == str(today)
        prefix = "► " if is_today else "  "

        row = col.format(
            prefix + day_str,
            sessions,
            d["messages"],
            fmt_tok(d["input"]),
            fmt_tok(d["cache_creation"]),
            fmt_tok(d["cache_read"]),
            fmt_tok(d["output"]),
            f"{rate:.1f}%",
        )
        print(row)

        if d_in or d_rate:
            delta_line = col.format("  delta", "", "", d_in, d_cc, d_cr, d_out, d_rate)
            print(delta_line)

        if alert:
            print(alert)

        prev = d
        prev_rate = rate

    print("-" * 78)
    # Totals
    total_d = {
        k: sum(daily[day][k] for day in sorted_days)
        for k in ("input", "cache_creation", "cache_read", "output", "messages")
    }
    total_sess = set()
    for day in sorted_days:
        total_sess.update(daily[day]["sessions"])
    total_rate = cache_hit_rate(total_d)

    col2 = "{:<12} {:>5} {:>6} {:>8} {:>10} {:>10} {:>8} {:>10}"
    print(
        col2.format(
            "TOTAL",
            len(total_sess),
            total_d["messages"],
            fmt_tok(total_d["input"]),
            fmt_tok(total_d["cache_creation"]),
            fmt_tok(total_d["cache_read"]),
            fmt_tok(total_d["output"]),
            f"{total_rate:.1f}%",
        )
    )
    print()
    print(
        "Columns: Input=uncached input | CacheNew=cache writes | CacheHit=cache reads | HitRate=CacheHit/(Input+CacheNew+CacheHit)"
    )
    print(
        f"ADR-0015 alert threshold: cache hit rate drop >= {CACHE_ALERT_THRESHOLD}pp flagged with ⚠"
    )


if __name__ == "__main__":
    main()
