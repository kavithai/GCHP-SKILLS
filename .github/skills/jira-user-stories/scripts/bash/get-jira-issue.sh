#!/usr/bin/env bash
# get-jira-issue.sh — Retrieves a single Jira issue by its key.
#
# Usage:
#   bash get-jira-issue.sh --issue-key "PROJ-123" [--fields "summary,status"] [--include-comments] [--format summary|json]
#
# Options:
#   --issue-key         (required) Jira issue key (e.g., PROJ-123)
#   --fields            Comma-separated list of fields to retrieve
#   --include-comments  Also retrieve comments for the issue
#   --expand            Comma-separated expand options (renderedFields, changelog, etc.)
#   --format            Output format: json (default) or summary (clean markdown)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/shared.sh"

# ── Parse Arguments ──────────────────────────────────────────────────

ISSUE_KEY=""
FIELDS=""
INCLUDE_COMMENTS=false
EXPAND=""
FORMAT="json"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --issue-key)      ISSUE_KEY="$2"; shift 2 ;;
        --fields)         FIELDS="$2"; shift 2 ;;
        --include-comments) INCLUDE_COMMENTS=true; shift ;;
        --expand)         EXPAND="$2"; shift 2 ;;
        --format)         FORMAT=$(echo "$2" | tr '[:upper:]' '[:lower:]'); shift 2 ;;
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

# Build endpoint with optional query parameters
endpoint="/rest/api/2/issue/$encoded_key"
query_parts=()
if [[ -n "$FIELDS" ]]; then
    query_parts+=("fields=$FIELDS")
fi
if [[ -n "$EXPAND" ]]; then
    query_parts+=("expand=$EXPAND")
fi
if [[ ${#query_parts[@]} -gt 0 ]]; then
    endpoint="${endpoint}?$(IFS='&'; echo "${query_parts[*]}")"
fi

# Fetch the issue
skill_output "GetIssue" "Retrieving issue $ISSUE_KEY..."
issue_json=$(invoke_jira_api GET "$endpoint")

# Optionally fetch comments
comments_json=""
if [[ "$INCLUDE_COMMENTS" == true || "$FORMAT" == "summary" ]]; then
    comment_endpoint="/rest/api/2/issue/$encoded_key/comment"
    skill_output "GetIssue" "Retrieving comments for $ISSUE_KEY..."
    comments_json=$(invoke_jira_api GET "$comment_endpoint")
    comment_count=$(echo "$comments_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('total',0))" 2>/dev/null || echo "0")
    skill_output "Comments" "Found $comment_count comment(s)."
fi

# Output based on format
if [[ "$FORMAT" == "summary" ]]; then
    # Merge comments into issue using temp files + Python helper
    tmp_issue=$(mktemp)
    tmp_comments=$(mktemp)
    printf '%s' "$issue_json" > "$tmp_issue"
    if [[ -z "$comments_json" ]]; then
        printf '%s' '{}' > "$tmp_comments"
    else
        printf '%s' "$comments_json" > "$tmp_comments"
    fi
    merged_json=$(python3 "$SCRIPT_DIR/merge_json.py" "$tmp_issue" "$tmp_comments")
    rm -f "$tmp_issue" "$tmp_comments"
    format_issue_summary "$merged_json"
else
    if [[ -n "$comments_json" ]]; then
        # Merge _comments into JSON output using temp files + Python helper
        tmp_issue=$(mktemp)
        tmp_comments=$(mktemp)
        printf '%s' "$issue_json" > "$tmp_issue"
        printf '%s' "$comments_json" > "$tmp_comments"
        python3 -c "
import json, sys
with open(sys.argv[1]) as f: issue = json.load(f)
with open(sys.argv[2]) as f: comments = json.load(f)
issue['_comments'] = comments
print(json.dumps(issue, indent=2))
" "$tmp_issue" "$tmp_comments"
        rm -f "$tmp_issue" "$tmp_comments"
    else
        echo "$issue_json" | python3 -m json.tool 2>/dev/null || echo "$issue_json"
    fi
fi

write_audit_log "GetIssue" "$ISSUE_KEY" "Retrieved issue. IncludeComments=$INCLUDE_COMMENTS"
exit 0
