#!/usr/bin/env python3
"""Lists available Jira transitions from JSON on stdin."""
import json
import sys


def main():
    data = json.load(sys.stdin)
    transitions = data.get("transitions", [])
    if not transitions:
        print("No transitions available.", file=sys.stderr)
    else:
        print("Available transitions:", file=sys.stderr)
        for t in transitions:
            to_status = ""
            to_obj = t.get("to")
            if to_obj and to_obj.get("name"):
                to_status = f" -> {to_obj['name']}"
            print(f"  ID: {t['id']}  Name: {t['name']}{to_status}", file=sys.stderr)


if __name__ == "__main__":
    main()
