#!/usr/bin/env python3
"""Merges a Jira issue JSON with comments JSON.

Reads two file paths from command-line arguments, merges them,
and prints the result to stdout.

Usage: python3 merge_json.py <issue_file> <comments_file>
"""
import json
import sys


def main():
    if len(sys.argv) < 3:
        print("Usage: merge_json.py <issue_file> <comments_file>", file=sys.stderr)
        sys.exit(1)

    with open(sys.argv[1]) as f:
        issue = json.load(f)

    with open(sys.argv[2]) as f:
        comments = json.load(f)

    if comments:
        issue["_comments"] = comments

    print(json.dumps(issue))


if __name__ == "__main__":
    main()
