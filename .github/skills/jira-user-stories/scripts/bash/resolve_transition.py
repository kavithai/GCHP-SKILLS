#!/usr/bin/env python3
"""Resolves a transition name to its ID from JSON on stdin.

Usage: echo "$json" | python3 resolve_transition.py "Transition Name"

Prints the transition ID to stdout on success.
Prints ERROR:message to stderr and exits 1 on failure.
"""
import json
import sys


def main():
    if len(sys.argv) < 2:
        print("Usage: resolve_transition.py <transition_name>", file=sys.stderr)
        sys.exit(1)

    data = json.load(sys.stdin)
    name = sys.argv[1]
    transitions = data.get("transitions", [])
    match = [t for t in transitions if t["name"].lower() == name.lower()]

    if not match:
        available = ", ".join(
            [f"'{t['name']}' (ID: {t['id']})" for t in transitions]
        )
        print(
            f'ERROR:Transition "{name}" not found. Available: {available}',
            file=sys.stderr,
        )
        sys.exit(1)

    print(match[0]["id"])


if __name__ == "__main__":
    main()
