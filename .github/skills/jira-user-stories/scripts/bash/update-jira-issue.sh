#!/usr/bin/env bash
# update-jira-issue.sh — Updates an existing Jira issue.
#
# Usage:
#   bash update-jira-issue.sh --issue-key "PROJ-123" [--summary "New title"] [--description "..."] [--priority "High"] [--labels "l1,l2"]
#
# Options:
#   --issue-key     (required) Jira issue key to update
#   --summary       New summary (must not be blank if provided)
#   --description   New description
#   --priority      New priority name
#   --labels        Comma-separated labels (replaces existing)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/shared.sh"

# ── Parse Arguments ──────────────────────────────────────────────────

ISSUE_KEY=""
SUMMARY=""
DESCRIPTION=""
PRIORITY=""
LABELS=""
HAS_SUMMARY=false
HAS_DESCRIPTION=false
HAS_PRIORITY=false
HAS_LABELS=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --issue-key)    ISSUE_KEY="$2"; shift 2 ;;
        --summary)      SUMMARY="$2"; HAS_SUMMARY=true; shift 2 ;;
        --description)  DESCRIPTION="$2"; HAS_DESCRIPTION=true; shift 2 ;;
        --priority)     PRIORITY="$2"; HAS_PRIORITY=true; shift 2 ;;
        --labels)       LABELS="$2"; HAS_LABELS=true; shift 2 ;;
        *) die "Unknown option: $1" ;;
    esac
done

if [[ -z "$ISSUE_KEY" ]]; then
    die "Missing required --issue-key parameter."
fi

# ── Main ─────────────────────────────────────────────────────────────

trap cleanup_credentials EXIT

validate_issue_key "$ISSUE_KEY"

# Empty field protection
if [[ "$HAS_SUMMARY" == true && -z "${SUMMARY// /}" ]]; then
    die "Summary must not be empty or whitespace when provided."
fi

# Require at least one update field
if [[ "$HAS_SUMMARY" == false && "$HAS_DESCRIPTION" == false && "$HAS_PRIORITY" == false && "$HAS_LABELS" == false ]]; then
    die "At least one update field must be specified (--summary, --description, --priority, or --labels)."
fi

load_credentials

# Build request body
body_json=$(python3 -c "
import json, sys

fields = {}

has_summary = sys.argv[1] == 'true'
summary = sys.argv[2]
has_description = sys.argv[3] == 'true'
description = sys.argv[4]
has_priority = sys.argv[5] == 'true'
priority = sys.argv[6]
has_labels = sys.argv[7] == 'true'
labels = sys.argv[8]

if has_summary:
    fields['summary'] = summary
if has_description:
    fields['description'] = description
if has_priority and priority:
    fields['priority'] = {'name': priority}
if has_labels:
    fields['labels'] = [l.strip() for l in labels.split(',') if l.strip()] if labels else []

print(json.dumps({'fields': fields}))
" "$HAS_SUMMARY" "$SUMMARY" "$HAS_DESCRIPTION" "$DESCRIPTION" "$HAS_PRIORITY" "$PRIORITY" "$HAS_LABELS" "$LABELS")

encoded_key=$(url_encode "$ISSUE_KEY")
endpoint="/rest/api/2/issue/$encoded_key"

skill_output "UpdateIssue" "Updating issue $ISSUE_KEY..."

invoke_jira_api PUT "$endpoint" "$body_json" > /dev/null

write_audit_log "UpdateIssue" "$ISSUE_KEY" "Updated fields"
skill_output "UpdateIssue" "Successfully updated issue: $ISSUE_KEY"

exit 0
