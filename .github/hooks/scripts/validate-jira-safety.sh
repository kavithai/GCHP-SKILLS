#!/usr/bin/env bash
# Cross-platform PreToolUse hook — enforces Jira safety policy on non-Windows platforms.
# Mirrors the enforcement logic in Validate-JiraSafety.ps1.
# Requires python3 (available by default on macOS and most Linux distributions).

HOOK_INPUT="$(cat)" python3 << 'PYEOF'
import sys, json, os, re

input_json = os.environ.get('HOOK_INPUT', '')

def allow():
    print('{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":""}}')
    sys.exit(0)

def deny(reason):
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason
        }
    }))
    sys.exit(0)

def is_protected_file(path):
    protected = [
        'shared.psm1',
        'Validate-JiraSafety.ps1',
        'validate-jira-safety.sh',
        'jira-safety.json',
        'jira-safety.instructions.md'
    ]
    for name in protected:
        if path.endswith(name):
            return name
    return None

try:
    hook_input = json.loads(input_json)
except json.JSONDecodeError:
    deny("Invalid hook input: unable to parse JSON.")

tool_name  = hook_input.get('tool_name', '')
tool_input = hook_input.get('tool_input', {})

if tool_name == 'run_in_terminal':
    command = tool_input.get('command', '')

    # Category 1 — DELETE method patterns
    if re.search(r"-Method\s+['\"]?Delete['\"]?", command, re.IGNORECASE):
        deny('DELETE HTTP method detected. DELETE operations are blocked by security policy.')
    if re.search(r'curl.*-X\s*DELETE', command, re.IGNORECASE):
        deny('curl DELETE request detected. DELETE operations are blocked by security policy.')
    if re.search(r'curl.*--request\s*DELETE', command, re.IGNORECASE):
        deny('curl DELETE request detected. DELETE operations are blocked by security policy.')
    if re.search(r"-CustomMethod\s+['\"]?Delete['\"]?", command, re.IGNORECASE):
        deny('DELETE via CustomMethod detected. DELETE operations are blocked by security policy.')

    # Category 5 — Protected file deletion/overwrite via terminal
    protected_files = [
        'shared.psm1',
        'Validate-JiraSafety.ps1',
        'validate-jira-safety.sh',
        'jira-safety.json',
        'jira-safety.instructions.md'
    ]
    for name in protected_files:
        escaped = re.escape(name)
        if re.search(r'Remove-Item.*' + escaped, command, re.IGNORECASE):
            deny(f'Blocked attempt to delete protected file: {name}')
        if re.search(r'rm\s+.*' + escaped, command, re.IGNORECASE):
            deny(f'Blocked attempt to delete protected file: {name}')
        if re.search(r'Set-Content.*' + escaped, command, re.IGNORECASE):
            deny(f'Blocked attempt to overwrite protected file: {name}')

    allow()

elif tool_name == 'replace_string_in_file':
    matched = is_protected_file(tool_input.get('filePath', ''))
    if matched:
        deny(f'Blocked attempt to modify protected file: {matched}')
    allow()

elif tool_name == 'multi_replace_string_in_file':
    for replacement in tool_input.get('replacements', []):
        matched = is_protected_file(replacement.get('filePath', ''))
        if matched:
            deny(f'Blocked attempt to modify protected file: {matched}')
    allow()

elif tool_name == 'create_file':
    matched = is_protected_file(tool_input.get('filePath', ''))
    if matched:
        deny(f'Blocked attempt to overwrite protected file: {matched}')

    content = tool_input.get('content', '')
    if content:
        if re.search(r"Invoke-RestMethod.*-Method\s+['\"]?Delete", content, re.IGNORECASE):
            deny('Blocked creation of file containing Invoke-RestMethod with Delete method (potential bypass script).')
        if re.search(r"Invoke-WebRequest.*-Method\s+['\"]?Delete", content, re.IGNORECASE):
            deny('Blocked creation of file containing Invoke-WebRequest with Delete method (potential bypass script).')
        if re.search(r'curl.*-X\s*DELETE.*rest/api', content, re.IGNORECASE):
            deny('Blocked creation of file containing curl DELETE against Jira API (potential bypass script).')
        if re.search(r'curl.*--request\s*DELETE.*rest/api', content, re.IGNORECASE):
            deny('Blocked creation of file containing curl DELETE against Jira API (potential bypass script).')

    allow()

else:
    allow()
PYEOF
