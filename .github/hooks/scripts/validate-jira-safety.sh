#!/usr/bin/env bash
# Passthrough hook for non-Windows platforms.
# Full enforcement is implemented in the Windows PowerShell variant.
# This script allows all operations until a cross-platform implementation is added.

cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"Non-Windows passthrough — full enforcement not yet implemented."}}
EOF
