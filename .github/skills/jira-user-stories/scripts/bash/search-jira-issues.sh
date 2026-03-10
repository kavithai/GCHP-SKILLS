#!/usr/bin/env bash
# search-jira-issues.sh — Searches for Jira issues using JQL.
#
# Usage:
#   bash search-jira-issues.sh --jql "project = PROJ" [--fields "summary,status"] [--max-results 50] [--start-at 0] [--all] [--format summary|json]
#
# Options:
#   --jql           (required) JQL query string
#   --fields        Comma-separated fields to return (default: summary,status,assignee,priority)
#   --max-results   Results per page, max 100 (default: 50)
#   --start-at      Pagination offset (default: 0)
#   --all           Paginate through all results (capped at 500)
#   --format        Output format: json (default) or summary (markdown table)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/shared.sh"

# ── Parse Arguments ──────────────────────────────────────────────────

JQL=""
FIELDS="summary,status,assignee,priority"
MAX_RESULTS=50
START_AT=0
ALL=false
FORMAT="json"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --jql)         JQL="$2"; shift 2 ;;
        --fields)      FIELDS="$2"; shift 2 ;;
        --max-results) MAX_RESULTS="$2"; shift 2 ;;
        --start-at)    START_AT="$2"; shift 2 ;;
        --all)         ALL=true; shift ;;
        --format)      FORMAT=$(echo "$2" | tr '[:upper:]' '[:lower:]'); shift 2 ;;
        *) die "Unknown option: $1" ;;
    esac
done

if [[ -z "$JQL" ]]; then
    die "Missing required --jql parameter."
fi

# ── Main ─────────────────────────────────────────────────────────────

trap cleanup_credentials EXIT

load_credentials

encoded_jql=$(url_encode "$JQL")

if [[ "$ALL" == true ]]; then
    SAFETY_CAP=500
    skill_output "Search" "Searching with pagination (cap: $SAFETY_CAP results)..."

    # Use a temp file to accumulate issues (avoids ARG_MAX with large JSON)
    tmp_issues=$(mktemp)
    printf '[]' > "$tmp_issues"
    current_start=$START_AT
    page_size=$MAX_RESULTS
    [[ $page_size -gt 100 ]] && page_size=100
    total_available=""

    while true; do
        endpoint="/rest/api/2/search?jql=$encoded_jql&startAt=$current_start&maxResults=$page_size&fields=$FIELDS"
        page_json=$(invoke_jira_api GET "$endpoint")

        if [[ -z "$total_available" ]]; then
            total_available=$(echo "$page_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('total',0))" 2>/dev/null)
            skill_output "Search" "Total matching issues: $total_available"
        fi

        # Merge issues via temp files to avoid ARG_MAX
        tmp_page=$(mktemp)
        printf '%s' "$page_json" > "$tmp_page"
        python3 -c "
import json, sys
with open(sys.argv[1]) as f: existing = json.load(f)
with open(sys.argv[2]) as f: page = json.load(f)
existing.extend(page.get('issues', []))
with open(sys.argv[1], 'w') as f: json.dump(existing, f)
" "$tmp_issues" "$tmp_page"
        rm -f "$tmp_page"

        current_start=$((current_start + page_size))

        issue_count=$(python3 -c "import json; f=open('$tmp_issues'); print(len(json.load(f)))")

        if [[ $current_start -ge $total_available ]]; then
            break
        fi
        if [[ $issue_count -ge $SAFETY_CAP ]]; then
            skill_output "Search" "Safety cap of $SAFETY_CAP results reached. Stopping pagination."
            break
        fi
    done

    # Build output object from temp file
    output_json=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f: issues = json.load(f)
cap = int(sys.argv[2])
total = int(sys.argv[3])
start = int(sys.argv[4])
if len(issues) > cap:
    issues = issues[:cap]
result = {'startAt': start, 'maxResults': len(issues), 'total': total, 'issues': issues}
print(json.dumps(result))
" "$tmp_issues" "$SAFETY_CAP" "$total_available" "$START_AT")
    rm -f "$tmp_issues"

    final_count=$(echo "$output_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('issues',[])))" 2>/dev/null)
    skill_output "Search" "Returning $final_count of $total_available total issues."

    if [[ "$FORMAT" == "summary" ]]; then
        format_search_summary "$output_json"
    else
        echo "$output_json" | python3 -m json.tool 2>/dev/null || echo "$output_json"
    fi
else
    # Single page request
    endpoint="/rest/api/2/search?jql=$encoded_jql&startAt=$START_AT&maxResults=$MAX_RESULTS&fields=$FIELDS"

    skill_output "Search" "Searching: $JQL (startAt=$START_AT, maxResults=$MAX_RESULTS)..."
    result_json=$(invoke_jira_api GET "$endpoint")

    issue_count=$(echo "$result_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('issues',[])))" 2>/dev/null || echo "0")
    total=$(echo "$result_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('total',0))" 2>/dev/null || echo "0")

    skill_output "Search" "Returned $issue_count of $total total matching issues."

    if [[ "$FORMAT" == "summary" ]]; then
        format_search_summary "$result_json"
    else
        echo "$result_json" | python3 -m json.tool 2>/dev/null || echo "$result_json"
    fi
fi

write_audit_log "SearchIssues" "" "JQL: $JQL. All=$ALL"
exit 0
