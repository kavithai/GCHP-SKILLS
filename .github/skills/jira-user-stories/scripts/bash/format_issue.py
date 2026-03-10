#!/usr/bin/env python3
"""Formats a Jira issue JSON (from stdin) into a concise markdown summary."""
import json
import sys


def main():
    issue = json.load(sys.stdin)
    f = issue.get("fields", {})

    lines = []
    type_name = (f.get("issuetype") or {}).get("name", "Issue")
    lines.append(f'## {issue.get("key", "?")} - {f.get("summary", "(no summary)")}')
    lines.append("")
    lines.append("| Field | Value |")
    lines.append("|-------|-------|")
    lines.append(f"| Type | {type_name} |")

    status = (f.get("status") or {}).get("name")
    if status:
        lines.append(f"| Status | {status} |")

    priority = (f.get("priority") or {}).get("name")
    if priority:
        lines.append(f"| Priority | {priority} |")

    reporter = (f.get("reporter") or {}).get("displayName")
    if reporter:
        lines.append(f"| Reporter | {reporter} |")

    assignee = (f.get("assignee") or {}).get("displayName")
    lines.append(f'| Assignee | {assignee or "Unassigned"} |')

    labels = f.get("labels", [])
    if labels:
        lines.append(f'| Labels | {", ".join(labels)} |')

    created = f.get("created")
    if created:
        lines.append(f"| Created | {created} |")

    updated = f.get("updated")
    if updated:
        lines.append(f"| Updated | {updated} |")

    resolution = (f.get("resolution") or {}).get("name")
    if resolution:
        lines.append(f"| Resolution | {resolution} |")

    desc = f.get("description")
    if desc:
        lines.append("")
        lines.append("### Description")
        lines.append("")
        lines.append(desc)

    # Comments from embedded or _comments
    comment_list = []
    if "_comments" in issue and issue["_comments"]:
        comment_list = issue["_comments"].get("comments", [])
    elif f.get("comment") and f["comment"].get("comments"):
        comment_list = f["comment"]["comments"]

    if comment_list:
        lines.append("")
        lines.append(f"### Comments ({len(comment_list)})")
        lines.append("")
        for i, c in enumerate(comment_list, 1):
            author = (c.get("author") or {}).get("displayName", "Unknown")
            date = (c.get("created") or "")[:10]
            body = c.get("body", "")
            lines.append(f"{i}. **{author}** ({date}): {body}")

    print("\n".join(lines))


if __name__ == "__main__":
    main()
