#!/usr/bin/env bash
# set-jira-transition.sh — Transitions a Jira issue to a new status or lists available transitions.
#
# Usage:
#   bash set-jira-transition.sh --issue-key "PROJ-123" --list-transitions
#   bash set-jira-transition.sh --issue-key "PROJ-123" --transition-name "In Progress"
#   bash set-jira-transition.sh --issue-key "PROJ-123" --transition-id "31" [--comment "Moving to done"]
#
# Options:
#   --issue-key         (required) Jira issue key to transition
#   --transition-id     Transition ID to execute
#   --transition-name   Transition name to resolve and execute
#   --list-transitions  List available transitions without executing
#   --comment           Comment to add with the transition

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/shared.sh"

# ── Parse Arguments ──────────────────────────────────────────────────

ISSUE_KEY=""
TRANSITION_ID=""
TRANSITION_NAME=""
LIST_TRANSITIONS=false
COMMENT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --issue-key)        ISSUE_KEY="$2"; shift 2 ;;
        --transition-id)    TRANSITION_ID="$2"; shift 2 ;;
        --transition-name)  TRANSITION_NAME="$2"; shift 2 ;;
        --list-transitions) LIST_TRANSITIONS=true; shift ;;
        --comment)          COMMENT="$2"; shift 2 ;;
        *) die "Unknown option: $1" ;;
    esac
done

if [[ -z "$ISSUE_KEY" ]]; then
    die "Missing required --issue-key parameter."
fi

# ── Main ─────────────────────────────────────────────────────────────

trap cleanup_credentials EXIT

validate_issue_key "$ISSUE_KEY"
load_credentials

encoded_key=$(url_encode "$ISSUE_KEY")
transitions_endpoint="/rest/api/2/issue/$encoded_key/transitions"

if [[ "$LIST_TRANSITIONS" == true ]]; then
    skill_output "Transitions" "Fetching available transitions for $ISSUE_KEY..."

    response=$(invoke_jira_api GET "$transitions_endpoint")

    echo "$response" | python3 "$SCRIPT_DIR/list_transitions.py" 2>&1

    write_audit_log "ListTransitions" "$ISSUE_KEY" "Listed transitions"
    exit 0
fi

# Execute mode: require either --transition-id or --transition-name
if [[ -z "$TRANSITION_ID" && -z "$TRANSITION_NAME" ]]; then
    die "Either --transition-id or --transition-name must be specified (or use --list-transitions to see available options)."
fi

resolved_id="$TRANSITION_ID"

if [[ -n "$TRANSITION_NAME" ]]; then
    skill_output "Transitions" "Looking up transition '$TRANSITION_NAME' for $ISSUE_KEY..."

    response=$(invoke_jira_api GET "$transitions_endpoint")

    resolved_id=$(echo "$response" | python3 "$SCRIPT_DIR/resolve_transition.py" "$TRANSITION_NAME" 2>&1)

    # Check for error
    if [[ "$resolved_id" == ERROR:* ]]; then
        die "${resolved_id#ERROR:}"
    fi

    skill_output "Transitions" "Resolved '$TRANSITION_NAME' to transition ID: $resolved_id"
fi

if [[ -z "$resolved_id" ]]; then
    die "Unable to determine transition ID. Provide --transition-id or a valid --transition-name."
fi

# Build transition request body
body_json=$(python3 -c "
import json, sys
body = {'transition': {'id': sys.argv[1]}}
comment = sys.argv[2] if len(sys.argv) > 2 else ''
if comment:
    body['update'] = {'comment': [{'add': {'body': comment}}]}
print(json.dumps(body))
" "$resolved_id" "$COMMENT")

skill_output "Transition" "Transitioning $ISSUE_KEY (transition ID: $resolved_id)..."

invoke_jira_api POST "$transitions_endpoint" "$body_json" > /dev/null

write_audit_log "Transition" "$ISSUE_KEY" "Executed transition ID: $resolved_id"
skill_output "Transition" "Successfully transitioned issue $ISSUE_KEY."

exit 0
