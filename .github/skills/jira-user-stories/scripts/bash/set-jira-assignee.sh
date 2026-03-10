#!/usr/bin/env bash
# set-jira-assignee.sh — Sets or clears the assignee on a Jira issue.
#
# Usage:
#   bash set-jira-assignee.sh --issue-key "PROJ-123" --assignee "jsmith"
#   bash set-jira-assignee.sh --issue-key "PROJ-123" --unassign
#
# Options:
#   --issue-key   (required) Jira issue key to update
#   --assignee    Username or account ID to assign
#   --unassign    Remove the current assignee

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/shared.sh"

# ── Parse Arguments ──────────────────────────────────────────────────

ISSUE_KEY=""
ASSIGNEE=""
UNASSIGN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --issue-key) ISSUE_KEY="$2"; shift 2 ;;
        --assignee)  ASSIGNEE="$2"; shift 2 ;;
        --unassign)  UNASSIGN=true; shift ;;
        *) die "Unknown option: $1" ;;
    esac
done

if [[ -z "$ISSUE_KEY" ]]; then
    die "Missing required --issue-key parameter."
fi

# ── Main ─────────────────────────────────────────────────────────────

trap cleanup_credentials EXIT

validate_issue_key "$ISSUE_KEY"

has_assignee=false
[[ -n "$ASSIGNEE" ]] && has_assignee=true

if [[ "$has_assignee" == false && "$UNASSIGN" == false ]]; then
    die "Either --assignee or --unassign must be specified."
fi
if [[ "$has_assignee" == true && "$UNASSIGN" == true ]]; then
    die "Cannot use both --assignee and --unassign at the same time."
fi

load_credentials

# Determine assignee field: Jira Cloud uses accountId, Server/DC uses name
assignee_field="name"
auth_type_lower=$(echo "$JIRA_AUTH_TYPE" | tr '[:upper:]' '[:lower:]')
if [[ "$auth_type_lower" == "basic" ]]; then
    assignee_field="accountId"
fi

# Build body
if [[ "$UNASSIGN" == true ]]; then
    body_json="{\"$assignee_field\":null}"
    action_desc="Unassigning"
else
    body_json=$(python3 -c "import json,sys; print(json.dumps({sys.argv[1]: sys.argv[2]}))" "$assignee_field" "$ASSIGNEE")
    action_desc="Assigning to '$ASSIGNEE'"
fi

encoded_key=$(url_encode "$ISSUE_KEY")
endpoint="/rest/api/2/issue/$encoded_key/assignee"

skill_output "Assignee" "$action_desc issue $ISSUE_KEY..."

invoke_jira_api PUT "$endpoint" "$body_json" > /dev/null

details="Cleared assignee"
[[ "$UNASSIGN" == false ]] && details="Assigned to '$ASSIGNEE'"

write_audit_log "SetAssignee" "$ISSUE_KEY" "$details"
skill_output "Assignee" "Successfully updated assignee on $ISSUE_KEY. $details."

exit 0
