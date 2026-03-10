#!/usr/bin/env python3
"""Formats Jira search results JSON (from stdin) into a concise markdown table."""
import json
import sys


def main():
    data = json.load(sys.stdin)
    total = data.get("total", 0)
    issues = data.get("issues", [])
    count = len(issues)

    lines = []
    lines.append(f"**Found {count} of {total} matching issues.**")
    lines.append("")

    if count > 0:
        lines.append("| Key | Summary | Status | Priority | Assignee |")
        lines.append("|-----|---------|--------|----------|----------|")
        for issue in issues:
            f = issue.get("fields", {})
            status = (f.get("status") or {}).get("name", "-")
            priority = (f.get("priority") or {}).get("name", "-")
            assignee = (f.get("assignee") or {}).get("displayName", "Unassigned")
            summary = f.get("summary", "-")
            if len(summary) > 60:
                summary = summary[:57] + "..."
            lines.append(
                f'| {issue.get("key", "?")} | {summary} | {status} | {priority} | {assignee} |'
            )

    print("\n".join(lines))


if __name__ == "__main__":
    main()
