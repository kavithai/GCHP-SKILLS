#!/usr/bin/env bash
# Shared utilities for Jira user stories skill bash scripts.
# Compatible with bash 3.2+ (macOS built-in) and GNU bash 4+.
# Requires: curl, base64, and optionally jq for JSON parsing.

set -euo pipefail

# Rate limiting
_LAST_REQUEST_TIME=0
_MIN_REQUEST_INTERVAL_MS=200

# ── Helpers ──────────────────────────────────────────────────────────

skill_output() {
    # Writes formatted output: [Title] Message
    local title="$1"
    local message="$2"
    echo "[$title] $message" >&2
}

sanitize_error() {
    # Redacts Bearer tokens, Basic auth, and long Base64-like strings.
    local msg="$1"
    msg=$(echo "$msg" | sed -E 's/Bearer [^ ]+/Bearer [REDACTED]/g')
    msg=$(echo "$msg" | sed -E 's/Basic [^ ]+/Basic [REDACTED]/g')
    msg=$(echo "$msg" | sed -E 's/[A-Za-z0-9+/=_]{20,}/[REDACTED]/g')
    echo "$msg"
}

die() {
    # Prints sanitized error to stderr and exits 1.
    local msg
    msg=$(sanitize_error "$1")
    echo "ERROR: $msg" >&2
    exit 1
}

# ── Repository Root ──────────────────────────────────────────────────

get_repo_root() {
    local root
    root=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
    if [[ -z "$root" ]]; then
        root="$PWD"
    fi
    echo "$root"
}

# ── Credential Loading ───────────────────────────────────────────────

load_credentials() {
    # Reads .env or credentials.env from repo root.
    # Sets global variables: JIRA_PAT, JIRA_URL, JIRA_EMAIL, JIRA_AUTH_TYPE
    local repo_root
    repo_root=$(get_repo_root)

    local env_file=""
    for candidate in "$repo_root/.env" "$repo_root/credentials.env"; do
        if [[ -f "$candidate" ]]; then
            env_file="$candidate"
            break
        fi
    done

    if [[ -z "$env_file" ]]; then
        die "No .env or credentials.env file found at repository root '$repo_root'."
    fi

    JIRA_PAT=""
    JIRA_URL=""
    JIRA_EMAIL=""
    JIRA_AUTH_TYPE="Bearer"

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Trim whitespace
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        # Skip empty lines and comments
        [[ -z "$line" || "$line" == \#* ]] && continue
        # Parse key=value
        local key="${line%%=*}"
        local value="${line#*=}"
        key=$(echo "$key" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        case "$key" in
            jirapat)      JIRA_PAT="$value" ;;
            jiraurl)      JIRA_URL="$value" ;;
            jiraemail)    JIRA_EMAIL="$value" ;;
            jiraauthtype) JIRA_AUTH_TYPE="$value" ;;
        esac
    done < "$env_file"

    if [[ -z "$JIRA_PAT" ]]; then
        die "Missing required 'jirapat' in '$env_file'."
    fi
    if [[ -z "$JIRA_URL" ]]; then
        die "Missing required 'jiraurl' in '$env_file'."
    fi

    # Strip trailing slash from URL
    JIRA_URL="${JIRA_URL%/}"

    skill_output "Credentials" "Loaded Jira credentials from '$env_file'."
}

# ── Auth Header Construction ─────────────────────────────────────────

build_auth_header() {
    # Returns the Authorization header value.
    local auth_type_lower
    auth_type_lower=$(echo "$JIRA_AUTH_TYPE" | tr '[:upper:]' '[:lower:]')
    if [[ "$auth_type_lower" == "basic" ]]; then
        if [[ -z "$JIRA_EMAIL" ]]; then
            die "Basic auth requires 'jiraemail' in credentials."
        fi
        local encoded
        encoded=$(printf '%s:%s' "$JIRA_EMAIL" "$JIRA_PAT" | base64 | tr -d '\n')
        echo "Basic $encoded"
    else
        echo "Bearer $JIRA_PAT"
    fi
}

# ── Validation ───────────────────────────────────────────────────────

validate_issue_key() {
    # Validates Jira issue key format: PROJ-123
    local key="$1"
    if [[ ! "$key" =~ ^[A-Z][A-Z0-9_]{0,9}-[0-9]{1,7}$ ]]; then
        die "Invalid Jira issue key format: '$key'. Expected format: PROJ-123."
    fi
}

validate_project_key() {
    # Validates Jira project key format: MYPROJ
    local key="$1"
    if [[ ! "$key" =~ ^[A-Z][A-Z0-9_]{0,9}$ ]]; then
        die "Invalid ProjectKey '$key'. Must match pattern ^[A-Z][A-Z0-9_]{0,9}$."
    fi
}

validate_url() {
    # Ensures URL is HTTPS and not localhost/private.
    local url="$1"
    if [[ ! "$url" =~ ^https:// ]]; then
        die "HTTPS is required. Refusing to send credentials over non-HTTPS URL."
    fi
    local host
    host=$(echo "$url" | sed -E 's|^https://([^/:]+).*|\1|' | tr '[:upper:]' '[:lower:]')
    case "$host" in
        localhost|127.0.0.1|::1)
            die "Blocked: localhost/loopback URLs are not permitted." ;;
    esac
    if [[ "$host" =~ ^10\. || "$host" =~ ^172\.(1[6-9]|2[0-9]|3[01])\. || "$host" =~ ^192\.168\. || "$host" =~ ^169\.254\. ]]; then
        die "Blocked: private IP ranges are not permitted."
    fi
}

safe_jql_value() {
    # Escapes a value for safe use in JQL queries.
    local val="$1"
    val=$(echo "$val" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\r\n')
    echo "\"$val\""
}

url_encode() {
    # Simple URL encoding for issue keys and query params.
    # Uses sys.argv to avoid shell injection via single-quote characters.
    local string="$1"
    python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$string" 2>/dev/null \
        || printf '%s' "$string"
}

# ── DELETE Blocking ──────────────────────────────────────────────────

# Layer 1: The invoke_jira_api function only accepts GET, POST, PUT.
# Layer 2: Runtime guard inside invoke_jira_api checks the method string.
# Layer 3: No script in this skill constructs a DELETE request.

# ── API Invocation ───────────────────────────────────────────────────

invoke_jira_api() {
    # Generic REST wrapper with DELETE blocking, HTTPS enforcement,
    # rate limiting, and retry with exponential backoff.
    #
    # Usage: invoke_jira_api METHOD ENDPOINT [BODY]
    # Outputs: JSON response on stdout
    local method="$1"
    local endpoint="$2"
    local body="${3:-}"

    # Layer 1+2: DELETE blocking
    local method_upper
    method_upper=$(echo "$method" | tr '[:lower:]' '[:upper:]')
    case "$method_upper" in
        GET|POST|PUT) ;;
        DELETE) die "BLOCKED: DELETE operations are not permitted by this skill." ;;
        *) die "Unsupported HTTP method: $method. Allowed: GET, POST, PUT." ;;
    esac

    # Build full URL
    local full_url="${JIRA_URL}/${endpoint#/}"

    # HTTPS enforcement
    validate_url "$full_url"

    # Build auth header
    local auth_header
    auth_header=$(build_auth_header)

    # Retry loop
    local max_retries=3
    local attempt=0
    local http_code
    local response_body
    local tmp_file
    tmp_file=$(mktemp)

    while true; do
        attempt=$((attempt + 1))

        # Rate limiting: sleep briefly between requests
        local now_ms
        now_ms=$(python3 -c "import time; print(int(time.time()*1000))")
        local elapsed=$((now_ms - _LAST_REQUEST_TIME))
        if [[ $elapsed -lt $_MIN_REQUEST_INTERVAL_MS && $_LAST_REQUEST_TIME -gt 0 ]]; then
            local sleep_s
            sleep_s=$(python3 -c "print(($_MIN_REQUEST_INTERVAL_MS - $elapsed) / 1000.0)" 2>/dev/null || echo "0.2")
            sleep "$sleep_s"
        fi
        _LAST_REQUEST_TIME=$(python3 -c "import time; print(int(time.time()*1000))")

        # Build curl command
        local curl_args=(
            --silent
            --show-error
            --tlsv1.2
            --write-out "\n%{http_code}"
            --header "Content-Type: application/json"
            --header "Authorization: $auth_header"
            --request "$method_upper"
        )

        if [[ -n "$body" && ("$method_upper" == "POST" || "$method_upper" == "PUT") ]]; then
            curl_args+=(--data "$body")
        fi

        curl_args+=("$full_url")

        # Execute
        local raw_output
        raw_output=$(curl "${curl_args[@]}" 2>"$tmp_file") || {
            local curl_err
            curl_err=$(cat "$tmp_file")
            rm -f "$tmp_file"
            die "curl failed: $(sanitize_error "$curl_err")"
        }

        # Split response body and HTTP status code
        http_code=$(echo "$raw_output" | tail -n1)
        response_body=$(echo "$raw_output" | sed '$d')

        # Handle 429 Too Many Requests (max 10 retries to prevent infinite loop)
        if [[ "$http_code" == "429" ]]; then
            if [[ $attempt -ge 10 ]]; then
                rm -f "$tmp_file"
                die "Rate limited (429) after 10 retries. Giving up."
            fi
            local wait_seconds=5
            skill_output "RateLimit" "429 received (attempt $attempt/10). Waiting ${wait_seconds} seconds before retry."
            sleep "$wait_seconds"
            continue
        fi

        # Handle 5xx with retry
        if [[ "$http_code" -ge 500 && "$http_code" -lt 600 && $attempt -lt $max_retries ]]; then
            local backoff=$((2 ** attempt))
            skill_output "Retry" "Attempt $attempt/$max_retries failed ($http_code). Retrying in ${backoff}s."
            sleep "$backoff"
            continue
        fi

        # Handle errors
        if [[ "$http_code" -ge 400 ]]; then
            rm -f "$tmp_file"
            local err_msg="Jira API request failed: $method_upper $endpoint - HTTP $http_code"
            if [[ -n "$response_body" ]]; then
                # Try to extract error message from JSON
                local jira_err
                jira_err=$(echo "$response_body" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    msgs = d.get('errorMessages', [])
    errs = d.get('errors', {})
    parts = list(msgs) + [f'{k}: {v}' for k, v in errs.items()]
    print('; '.join(parts) if parts else '')
except: pass
" 2>/dev/null || echo "")
                if [[ -n "$jira_err" ]]; then
                    err_msg="$err_msg - $jira_err"
                fi
            fi
            die "$err_msg"
        fi

        rm -f "$tmp_file"
        echo "$response_body"
        return 0
    done
}

# ── Audit Logging ────────────────────────────────────────────────────

write_audit_log() {
    # Writes a JSON Lines audit entry if JIRA_AUDIT_LOG is set.
    # Uses python3 for proper JSON escaping of all field values.
    local operation="$1"
    local issue_key="${2:-}"
    local details="${3:-}"

    [[ -z "${JIRA_AUDIT_LOG:-}" ]] && return 0

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    python3 -c "
import json, sys
entry = {'timestamp': sys.argv[1], 'operation': sys.argv[2], 'issueKey': sys.argv[3], 'details': sys.argv[4]}
print(json.dumps(entry, ensure_ascii=False))
" "$timestamp" "$operation" "$issue_key" "$details" >> "$JIRA_AUDIT_LOG" 2>/dev/null || true
}

# ── Credential Cleanup ───────────────────────────────────────────────

cleanup_credentials() {
    JIRA_PAT=""
    JIRA_EMAIL=""
    JIRA_AUTH_TYPE=""
}


# ── Output Formatting ────────────────────────────────────────────────

format_issue_summary() {
    # Formats a Jira issue JSON into a concise markdown summary.
    # Pipes JSON to the standalone Python formatter via stdin.
    local json="$1"
    echo "$json" | python3 "$SCRIPT_DIR/format_issue.py"
}

format_search_summary() {
    # Formats Jira search results JSON into a concise markdown table.
    # Pipes JSON to the standalone Python formatter via stdin.
    local json="$1"
    echo "$json" | python3 "$SCRIPT_DIR/format_search.py"
}
