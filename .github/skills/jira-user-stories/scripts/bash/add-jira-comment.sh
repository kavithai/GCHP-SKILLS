#!/usr/bin/env bash
# add-jira-comment.sh — Adds a comment to a Jira issue.
#
# Usage:
#   bash add-jira-comment.sh --issue-key "PROJ-123" --body "Comment text"
#
# Options:
#   --issue-key   (required) Jira issue key to comment on
#   --body        (required) Comment text (plain text or wiki markup)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/shared.sh"

# ── Parse Arguments ──────────────────────────────────────────────────

ISSUE_KEY=""
BODY=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --issue-key) ISSUE_KEY="$2"; shift 2 ;;
        --body)      BODY="$2"; shift 2 ;;
        *) die "Unknown option: $1" ;;
    esac
done

if [[ -z "$ISSUE_KEY" ]]; then
    die "Missing required --issue-key parameter."
fi
if [[ -z "$BODY" ]]; then
    die "Missing required --body parameter."
fi

# ── Main ─────────────────────────────────────────────────────────────

trap cleanup_credentials EXIT

validate_issue_key "$ISSUE_KEY"

if [[ -z "${BODY// /}" ]]; then
    die "Comment body must not be empty or whitespace."
fi

load_credentials

# Build request body using python3 for safe JSON
body_json=$(python3 -c "
import json, sys
print(json.dumps({'body': sys.argv[1]}))
" "$BODY")

encoded_key=$(url_encode "$ISSUE_KEY")
endpoint="/rest/api/2/issue/$encoded_key/comment"

skill_output "AddComment" "Adding comment to $ISSUE_KEY..."

response=$(invoke_jira_api POST "$endpoint" "$body_json")

comment_id=$(echo "$response" | python3 -c "import json,sys; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")

write_audit_log "AddComment" "$ISSUE_KEY" "Added comment ID: $comment_id"
skill_output "AddComment" "Successfully added comment to $ISSUE_KEY (comment ID: $comment_id)."

exit 0
