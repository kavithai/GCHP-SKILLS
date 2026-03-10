---
name: jira-user-stories
description: 'Jira user story management skill for reading, creating, updating, and transitioning issues via Jira REST API v2. USE FOR: Jira issue search, story creation, status updates, field editing, comment management, issue assignment, JQL queries, sprint tracking. Works cross-platform: PowerShell 5.1+ on Windows, bash/curl/python3 on macOS and Linux. Supports both Jira Cloud (Basic Auth) and Data Center (Bearer PAT). Enforces strict safety guardrails: no DELETE operations, HTTPS-only, TLS 1.2 pinned, credential masking.'
user-invocable: true
compatibility: 'Cross-platform: PowerShell 5.1+ (Windows) or bash 3.2+/curl/python3 (macOS/Linux). Jira REST API v2 access over HTTPS. PAT stored in .env or credentials.env at workspace root.'
---

# Jira User Story Management Skill

## Overview

Provides Jira issue management capabilities through scripts that interact with the Jira REST API v2. Two runtime options are available:

* **PowerShell scripts** (`scripts/*.ps1`) — for Windows and PowerShell 7+ environments.
* **Bash scripts** (`scripts/bash/*.sh`) — for macOS and Linux (uses `curl`, `python3`, and `base64`).

All operations enforce HTTPS, TLS 1.2 pinning, credential masking, and a permanent DELETE block.

### Supported Operations

| Operation          | PowerShell Script       | Bash Script               | HTTP Method | Endpoint                              |
|--------------------|-------------------------|---------------------------|-------------|---------------------------------------|
| Search issues      | Search-JiraIssues.ps1   | search-jira-issues.sh     | GET         | /rest/api/2/search                    |
| Get single issue   | Get-JiraIssue.ps1       | get-jira-issue.sh         | GET         | /rest/api/2/issue/{key}               |
| Create issue       | New-JiraIssue.ps1       | new-jira-issue.sh         | POST        | /rest/api/2/issue                     |
| Update issue       | Update-JiraIssue.ps1    | update-jira-issue.sh      | PUT         | /rest/api/2/issue/{key}               |
| Add comment        | Add-JiraComment.ps1     | add-jira-comment.sh       | POST        | /rest/api/2/issue/{key}/comment       |
| Transition status  | Set-JiraTransition.ps1  | set-jira-transition.sh    | POST        | /rest/api/2/issue/{key}/transitions   |
| Assign issue       | Set-JiraAssignee.ps1    | set-jira-assignee.sh      | PUT         | /rest/api/2/issue/{key}/assignee      |

## Prerequisites

### Windows (PowerShell)

| Requirement | Detail                                                                                     |
|-------------|--------------------------------------------------------------------------------------------|
| PowerShell  | 5.1+ (Windows built-in)                                                                   |
| Jira Access | REST API v2 over HTTPS                                                                    |
| Credentials | `.env` or `credentials.env` at workspace root with `jirapat=<PAT>` and `jiraurl=<URL>`    |
| Optional    | `jiraemail=<email>` for Jira Cloud (Basic Auth), `jiraauthtype=Basic`                      |

### macOS / Linux (Bash)

| Requirement | Detail                                                                                     |
|-------------|--------------------------------------------------------------------------------------------|
| bash        | 3.2+ (macOS built-in) or any modern bash                                                  |
| curl        | Built-in on macOS and most Linux distributions                                             |
| python3     | Built-in on macOS (via Xcode CLT) and most Linux distributions                            |
| base64      | Built-in on macOS and Linux                                                                |
| Jira Access | REST API v2 over HTTPS                                                                    |
| Credentials | `.env` or `credentials.env` at workspace root with `jirapat=<PAT>` and `jiraurl=<URL>`    |
| Optional    | `jiraemail=<email>` for Jira Cloud (Basic Auth), `jiraauthtype=Basic`                      |

## Quick Start

### PowerShell (Windows)

Retrieve a single issue with a clean, readable summary (recommended for agents):

    powershell -ExecutionPolicy Bypass -File scripts/Get-JiraIssue.ps1 -IssueKey "MYPROJ-123" -Format Summary

Search for issues and get a formatted table:

    powershell -ExecutionPolicy Bypass -File scripts/Search-JiraIssues.ps1 -Jql "project = MYPROJ AND status = 'To Do'" -MaxResults 10 -Format Summary

Retrieve raw JSON (for programmatic use):

    powershell -ExecutionPolicy Bypass -File scripts/Get-JiraIssue.ps1 -IssueKey "MYPROJ-123"

Create a new user story:

    powershell -ExecutionPolicy Bypass -File scripts/New-JiraIssue.ps1 -ProjectKey "MYPROJ" -Summary "New user story" -IssueType "Story"

Transition an issue to a new status:

    powershell -ExecutionPolicy Bypass -File scripts/Set-JiraTransition.ps1 -IssueKey "MYPROJ-123" -TransitionName "In Progress"

### Bash (macOS / Linux)

Retrieve a single issue with a clean, readable summary (recommended for agents):

    bash scripts/bash/get-jira-issue.sh --issue-key "MYPROJ-123" --format summary

Search for issues and get a formatted table:

    bash scripts/bash/search-jira-issues.sh --jql "project = MYPROJ AND status = 'To Do'" --max-results 10 --format summary

Retrieve raw JSON (for programmatic use):

    bash scripts/bash/get-jira-issue.sh --issue-key "MYPROJ-123"

Create a new user story:

    bash scripts/bash/new-jira-issue.sh --project-key "MYPROJ" --summary "New user story" --issue-type "Story"

Transition an issue to a new status:

    bash scripts/bash/set-jira-transition.sh --issue-key "MYPROJ-123" --transition-name "In Progress"

## Agent Execution Rules (Required)

When using this skill from an agent runtime:

### Platform Detection

* On macOS or Linux (no PowerShell), use the bash scripts: `bash scripts/bash/<script>.sh`
* On Windows, use PowerShell: `powershell -ExecutionPolicy Bypass -File scripts/<script>.ps1`
* On PowerShell 7+ (including non-Windows), use `pwsh -File scripts/<script>.ps1`.

### Windows (PowerShell)

* For maximum Windows compatibility, run scripts via:
  * `powershell -ExecutionPolicy Bypass -File scripts/<script>.ps1`
  * or set once per terminal: `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`
* **Prefer `-Format Summary`** for read operations. This returns a concise markdown summary.
* Use default JSON format (`-Format Json` or omit the flag) only when programmatic field extraction is required.
* When using JSON format, parse output from stdout. All scripts emit JSON via `ConvertTo-Json -Depth 10`.
* Use `ConvertTo-SafeJqlValue` from `shared.psm1` when constructing JQL with user-supplied values to prevent injection.

### macOS / Linux (Bash)

* Run scripts via: `bash scripts/bash/<script>.sh`
* **Prefer `--format summary`** for read operations. This returns a concise markdown summary.
* Use default JSON format (`--format json` or omit the flag) only when programmatic field extraction is required.
* Bash scripts use `--kebab-case` flags instead of PowerShell `-PascalCase` flags.
* Requires `curl`, `python3`, and `base64` (all pre-installed on macOS and most Linux).

### Common Rules

* Always check exit codes (`$?`) after script execution. Exit code 0 indicates success; exit code 1 indicates failure.

## Safety Policy (Mandatory)

### Blocked Operations

| Blocked Operation | HTTP Method | Why                         |
|-------------------|-------------|-----------------------------|
| Delete issue      | DELETE      | Permanent data loss         |
| Delete comment    | DELETE      | Permanent data loss         |
| Delete project    | DELETE      | Entire project destruction  |
| Delete attachment | DELETE      | Permanent data loss         |

### Three-Layer DELETE Blocking

DELETE operations are blocked at three independent layers to prevent accidental or deliberate data destruction:

**PowerShell:**

1. `Invoke-JiraApi` validates the `-Method` parameter using `[ValidateSet('Get', 'Post', 'Put')]`, rejecting DELETE at the parameter binding level.
2. A runtime guard inside `Invoke-JiraApi` checks the method string and throws before any HTTP request is made.
3. No script in this skill constructs a DELETE request. No code path exists to reach a DELETE call.

**Bash:**

1. `invoke_jira_api` validates the method against an allow-list (`GET|POST|PUT`), rejecting DELETE.
2. A runtime guard checks the method string and exits before any HTTP request is made.
3. No script in this skill constructs a DELETE request. No code path exists to reach a DELETE call.

All three layers must be bypassed simultaneously for a DELETE to succeed, which requires modifying the source code itself.

### Empty Field Protection

Both the PowerShell `Update-JiraIssue.ps1` and the bash `update-jira-issue.sh` scripts prevent blanking the `summary` field. If summary is provided, it must contain non-whitespace content. At least one update field must be specified for any update operation.

## Credentials Policy (Mandatory)

* NEVER hardcode usernames, passwords, tokens, or secrets in any file.
* Read credentials from `.env` or `credentials.env` at the workspace root only.
* Never log or echo PAT values in terminal output. All error messages pass through `Get-SanitizedErrorMessage` to redact tokens.
* Credentials are auto-cleared in the `finally` block (PowerShell) or `trap` handler (bash) after each operation.
* Recommended: use a dedicated service account with minimal Jira permissions scoped to required projects.
* Recommended: rotate your PAT every 90 days.

## Authentication (Mandatory)

Two authentication modes are supported, controlled by the `jiraauthtype` value in the credentials file.

| Environment              | Auth Type               | .env Keys Required                          |
|--------------------------|-------------------------|---------------------------------------------|
| Data Center / Server     | Bearer PAT              | `jirapat`, `jiraurl`                        |
| Jira Cloud               | Basic Auth (API token)  | `jirapat`, `jiraurl`, `jiraemail`, `jiraauthtype=Basic` |

When `jiraauthtype` is omitted or set to `Bearer`, the skill sends a `Bearer <PAT>` authorization header. When set to `Basic`, the skill constructs a `Basic <base64(email:token)>` header. Jira Cloud API tokens are passed in the `jirapat` field.

## Parameters Reference

Bash scripts use `--kebab-case` flags. PowerShell scripts use `-PascalCase` flags. The tables below show both.

### Get-JiraIssue / get-jira-issue

| Parameter         | PowerShell Flag    | Bash Flag            | Type     | Mandatory | Default | Description                                              |
|-------------------|--------------------|----------------------|----------|-----------|---------|----------------------------------------------------------|
| Issue Key         | `-IssueKey`        | `--issue-key`        | string   | Yes       | —       | Jira issue key (e.g., `PROJ-123`)                        |
| Fields            | `-Fields`          | `--fields`           | string[] | No        | All     | Specific fields to retrieve (comma-separated)            |
| Include Comments  | `-IncludeComments` | `--include-comments` | switch   | No        | false   | Also retrieve comments for the issue                     |
| Expand            | `-Expand`          | `--expand`           | string[] | No        | —       | Expand options (`renderedFields`, `changelog`, etc.)     |
| Format            | `-Format`          | `--format`           | string   | No        | Json    | Output format: `json` or `summary` (clean markdown)      |

### Search-JiraIssues / search-jira-issues

| Parameter    | PowerShell Flag | Bash Flag       | Type     | Mandatory | Default                            | Description                                  |
|--------------|-----------------|-----------------|----------|-----------|------------------------------------|----------------------------------------------|
| JQL          | `-Jql`          | `--jql`         | string   | Yes       | —                                  | JQL query string                             |
| Fields       | `-Fields`       | `--fields`      | string[] | No        | `summary,status,assignee,priority` | Fields to return (comma-separated)           |
| Max Results  | `-MaxResults`   | `--max-results` | int      | No        | `50`                               | Results per page (max 100)                   |
| Start At     | `-StartAt`      | `--start-at`    | int      | No        | `0`                                | Pagination offset                            |
| All          | `-All`          | `--all`         | switch   | No        | false                              | Paginate through all results (capped at 500) |
| Format       | `-Format`       | `--format`      | string   | No        | Json                               | Output format: `json` or `summary`           |

### New-JiraIssue / new-jira-issue

| Parameter      | PowerShell Flag  | Bash Flag        | Type      | Mandatory | Default | Description                                 |
|----------------|------------------|------------------|-----------|-----------|---------|---------------------------------------------|
| Project Key    | `-ProjectKey`    | `--project-key`  | string    | Yes       | —       | Jira project key (e.g., `MYPROJ`)           |
| Summary        | `-Summary`       | `--summary`      | string    | Yes       | —       | Issue summary/title (must not be empty)      |
| Description    | `-Description`   | `--description`  | string    | No        | —       | Issue description                           |
| Issue Type     | `-IssueType`     | `--issue-type`   | string    | No        | `Story` | Issue type (`Story`, `Task`, `Bug`, `Epic`) |
| Priority       | `-Priority`      | `--priority`     | string    | No        | —       | Priority name (e.g., `High`, `Medium`)      |
| Labels         | `-Labels`        | `--labels`       | string[]  | No        | —       | Labels (comma-separated for bash)           |
| Assignee       | `-Assignee`      | `--assignee`     | string    | No        | —       | Assignee username or account ID             |
| Custom Fields  | `-CustomFields`  | —                | hashtable | No        | —       | Custom fields (PowerShell only)             |

### Update-JiraIssue / update-jira-issue

| Parameter      | PowerShell Flag  | Bash Flag        | Type      | Mandatory | Default | Description                                      |
|----------------|------------------|------------------|-----------|-----------|---------|--------------------------------------------------|
| Issue Key      | `-IssueKey`      | `--issue-key`    | string    | Yes       | —       | Jira issue key to update                         |
| Summary        | `-Summary`       | `--summary`      | string    | No        | —       | New summary (must not be blank if provided)      |
| Description    | `-Description`   | `--description`  | string    | No        | —       | New description                                  |
| Priority       | `-Priority`      | `--priority`     | string    | No        | —       | New priority name                                |
| Labels         | `-Labels`        | `--labels`       | string[]  | No        | —       | New labels (comma-separated for bash)            |
| Custom Fields  | `-CustomFields`  | —                | hashtable | No        | —       | Custom fields (PowerShell only)                  |

### Add-JiraComment / add-jira-comment

| Parameter   | PowerShell Flag | Bash Flag      | Type      | Mandatory | Default | Description                                                        |
|-------------|-----------------|----------------|-----------|-----------|---------|--------------------------------------------------------------------| 
| Issue Key   | `-IssueKey`     | `--issue-key`  | string    | Yes       | —       | Issue to comment on                                                |
| Body        | `-Body`         | `--body`       | string    | Yes       | —       | Comment text (plain text or wiki markup)                           |
| Visibility  | `-Visibility`   | —              | hashtable | No        | —       | Visibility restriction (PowerShell only)                           |

### Set-JiraTransition / set-jira-transition

| Parameter        | PowerShell Flag     | Bash Flag              | Type   | Mandatory | Default | Description                                    |
|------------------|---------------------|------------------------|--------|-----------|---------|------------------------------------------------|
| Issue Key        | `-IssueKey`         | `--issue-key`          | string | Yes       | —       | Issue to transition                            |
| Transition ID    | `-TransitionId`     | `--transition-id`      | string | No        | —       | ID of the transition to execute                |
| Transition Name  | `-TransitionName`   | `--transition-name`    | string | No        | —       | Name of the transition (resolved to ID)        |
| List Transitions | `-ListTransitions`  | `--list-transitions`   | switch | No        | false   | List available transitions instead of executing|
| Comment          | `-Comment`          | `--comment`            | string | No        | —       | Comment to add with the transition             |

Provide either transition ID or transition name to execute a transition. Use the list option to discover available transitions before executing one.

### Set-JiraAssignee / set-jira-assignee

| Parameter | PowerShell Flag | Bash Flag      | Type   | Mandatory | Default | Description                                     |
|-----------|-----------------|----------------|--------|-----------|---------|--------------------------------------------------|
| Issue Key | `-IssueKey`     | `--issue-key`  | string | Yes       | —       | Issue to assign                                 |
| Assignee  | `-Assignee`     | `--assignee`   | string | No        | —       | Username or account ID to assign                |
| Unassign  | `-Unassign`     | `--unassign`   | switch | No        | false   | Remove the current assignee                     |

## Workflow Pattern for Agents

### Read Operations (single command, no parsing needed)

Use summary format to get clean, user-ready output in a single step:

**PowerShell (Windows):**

1. Set execution policy: `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`
2. Get issue summary: `Get-JiraIssue.ps1 -IssueKey "PROJ-123" -Format Summary`
3. Search issues: `Search-JiraIssues.ps1 -Jql "project = PROJ AND status = 'To Do'" -Format Summary`

**Bash (macOS / Linux):**

1. Get issue summary: `bash scripts/bash/get-jira-issue.sh --issue-key "PROJ-123" --format summary`
2. Search issues: `bash scripts/bash/search-jira-issues.sh --jql "project = PROJ AND status = 'To Do'" --format summary`

The output is clean markdown that can be returned to the user directly — no JSON parsing or field extraction required.

### Write Operations (standard workflow)

**PowerShell (Windows):**

1. Set execution policy: `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`
2. Create, update, or transition: `New-JiraIssue.ps1`, `Update-JiraIssue.ps1`, or `Set-JiraTransition.ps1`
3. Add comments as needed: `Add-JiraComment.ps1 -IssueKey "PROJ-123" -Body "Updated via automation"`
4. Verify changes: `Get-JiraIssue.ps1 -IssueKey "PROJ-123" -Format Summary`

**Bash (macOS / Linux):**

1. Create, update, or transition: `new-jira-issue.sh`, `update-jira-issue.sh`, or `set-jira-transition.sh`
2. Add comments as needed: `bash scripts/bash/add-jira-comment.sh --issue-key "PROJ-123" --body "Updated via automation"`
3. Verify changes: `bash scripts/bash/get-jira-issue.sh --issue-key "PROJ-123" --format summary`

## Templates and References

* `references/reference.md` â€” API endpoint reference, error codes, response formats
* `references/jql-examples.md` â€” Common JQL queries and safety notes

## Troubleshooting

| Symptom                 | Cause                          | Resolution                                                         |
|-------------------------|--------------------------------|--------------------------------------------------------------------|
| 401 Unauthorized        | Invalid or expired PAT         | Verify `jirapat` in `.env`, regenerate the PAT if expired          |
| 403 Forbidden           | Insufficient permissions       | Check Jira project permissions for the service account             |
| 404 Not Found           | Invalid issue key or project   | Verify issue key format and project existence                      |
| 429 Too Many Requests   | Rate limited                   | Script handles automatically with backoff; reduce request volume   |
| TLS/SSL error           | TLS version mismatch           | PowerShell pins TLS 1.2 via `ServicePointManager`; bash uses `curl --tlsv1.2` |
| BLOCKED: DELETE         | Attempted delete operation     | DELETE operations are permanently disabled by this skill           |
| Missing `jirapat`       | `.env` file incomplete         | Add `jirapat=<PAT>` to `.env` or `credentials.env`                |
| Invalid issue key       | Wrong format                   | Use uppercase `PROJECT-NUMBER` format (e.g., `PROJ-123`)          |
