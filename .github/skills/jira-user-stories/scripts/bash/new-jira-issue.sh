#!/usr/bin/env bash
# new-jira-issue.sh — Creates a new Jira issue.
#
# Usage:
#   bash new-jira-issue.sh --project-key "PROJ" --summary "Title" [--description "..."] [--issue-type "Story"] [--priority "High"] [--labels "l1,l2"] [--assignee "user"]
#
# Options:
#   --project-key   (required) Jira project key (e.g., MYPROJ)
#   --summary       (required) Issue summary/title
#   --description   Issue description
#   --issue-type    Issue type (default: Story). Values: Story, Task, Bug, Epic
#   --priority      Priority name (e.g., High, Medium, Low)
#   --labels        Comma-separated labels
#   --assignee      Username or account ID

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/shared.sh"

# ── Parse Arguments ──────────────────────────────────────────────────

PROJECT_KEY=""
SUMMARY=""
DESCRIPTION=""
ISSUE_TYPE="Story"
PRIORITY=""
LABELS=""
ASSIGNEE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project-key) PROJECT_KEY="$2"; shift 2 ;;
        --summary)     SUMMARY="$2"; shift 2 ;;
        --description) DESCRIPTION="$2"; shift 2 ;;
        --issue-type)  ISSUE_TYPE="$2"; shift 2 ;;
        --priority)    PRIORITY="$2"; shift 2 ;;
        --labels)      LABELS="$2"; shift 2 ;;
        --assignee)    ASSIGNEE="$2"; shift 2 ;;
        *) die "Unknown option: $1" ;;
    esac
done

if [[ -z "$PROJECT_KEY" ]]; then
    die "Missing required --project-key parameter."
fi
if [[ -z "$SUMMARY" ]]; then
    die "Missing required --summary parameter."
fi

# ── Main ─────────────────────────────────────────────────────────────

trap cleanup_credentials EXIT

# Validate inputs
if [[ -z "${SUMMARY// /}" ]]; then
    die "Summary must not be empty or whitespace."
fi
validate_project_key "$PROJECT_KEY"

load_credentials

# Determine assignee field name: Jira Cloud uses accountId, Server/DC uses name
assignee_field="name"
auth_type_lower=$(echo "$JIRA_AUTH_TYPE" | tr '[:upper:]' '[:lower:]')
if [[ "$auth_type_lower" == "basic" ]]; then
    assignee_field="accountId"
fi

# Build request body using python3 for safe JSON construction
body_json=$(python3 -c "
import json, sys

fields = {
    'project': {'key': sys.argv[1]},
    'summary': sys.argv[2],
    'issuetype': {'name': sys.argv[3]}
}

description = sys.argv[4]
if description:
    fields['description'] = description

priority = sys.argv[5]
if priority:
    fields['priority'] = {'name': priority}

labels = sys.argv[6]
if labels:
    fields['labels'] = [l.strip() for l in labels.split(',') if l.strip()]

assignee = sys.argv[7]
assignee_field = sys.argv[8]
if assignee:
    fields['assignee'] = {assignee_field: assignee}

print(json.dumps({'fields': fields}))
" "$PROJECT_KEY" "$SUMMARY" "$ISSUE_TYPE" "$DESCRIPTION" "$PRIORITY" "$LABELS" "$ASSIGNEE" "$assignee_field")

skill_output "CreateIssue" "Creating $ISSUE_TYPE in project $PROJECT_KEY..."

response=$(invoke_jira_api POST "/rest/api/2/issue" "$body_json")

issue_key=$(echo "$response" | python3 -c "import json,sys; print(json.load(sys.stdin).get('key',''))" 2>/dev/null)

write_audit_log "CreateIssue" "$issue_key" "Created $ISSUE_TYPE '$SUMMARY' in $PROJECT_KEY"
skill_output "CreateIssue" "Successfully created issue: $issue_key"
echo "$issue_key"

exit 0
