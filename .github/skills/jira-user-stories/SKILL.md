---
name: jira-user-stories
description: 'Jira user story management skill for reading, creating, updating, and transitioning issues via Jira REST API v2. USE FOR: Jira issue search, story creation, status updates, field editing, comment management, issue assignment, JQL queries, sprint tracking. Works with PowerShell 5.1+ on Windows. Supports both Jira Cloud (Basic Auth) and Data Center (Bearer PAT). Enforces strict safety guardrails: no DELETE operations, HTTPS-only, TLS 1.2 pinned, credential masking.'
user-invocable: true
compatibility: 'PowerShell 5.1+ (Windows built-in). Jira REST API v2 access over HTTPS. PAT stored in .env or credentials.env at workspace root.'
---

# Jira User Story Management Skill

## Overview

Provides Jira issue management capabilities through PowerShell scripts that interact with the Jira REST API v2. All operations enforce HTTPS, TLS 1.2 pinning, credential masking, and a permanent DELETE block.

### Supported Operations

| Operation          | Script                  | HTTP Method | Endpoint                              |
|--------------------|-------------------------|-------------|---------------------------------------|
| Search issues      | Search-JiraIssues.ps1   | GET         | /rest/api/2/search                    |
| Get single issue   | Get-JiraIssue.ps1       | GET         | /rest/api/2/issue/{key}               |
| Create issue       | New-JiraIssue.ps1       | POST        | /rest/api/2/issue                     |
| Update issue       | Update-JiraIssue.ps1    | PUT         | /rest/api/2/issue/{key}               |
| Add comment        | Add-JiraComment.ps1     | POST        | /rest/api/2/issue/{key}/comment       |
| Transition status  | Set-JiraTransition.ps1  | POST        | /rest/api/2/issue/{key}/transitions   |
| Assign issue       | Set-JiraAssignee.ps1    | PUT         | /rest/api/2/issue/{key}/assignee      |

## Prerequisites

| Requirement | Detail                                                                                     |
|-------------|--------------------------------------------------------------------------------------------|
| PowerShell  | 5.1+ (Windows built-in)                                                                   |
| Jira Access | REST API v2 over HTTPS                                                                    |
| Credentials | `.env` or `credentials.env` at workspace root with `jirapat=<PAT>` and `jiraurl=<URL>`    |
| Optional    | `jiraemail=<email>` for Jira Cloud (Basic Auth), `jiraauthtype=Basic`                      |

## Quick Start

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

## Agent Execution Rules (Required)

When using this skill from an agent runtime:

* For maximum Windows compatibility, run scripts via:
  * `powershell -ExecutionPolicy Bypass -File scripts/<script>.ps1`
  * or set once per terminal: `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`
* On PowerShell 7+ (including non-Windows), use `pwsh -File scripts/<script>.ps1`.
* Always check exit codes (`$LASTEXITCODE`) after script execution. Exit code 0 indicates success; exit code 1 indicates failure.
* **Prefer `-Format Summary`** for read operations (`Get-JiraIssue.ps1`, `Search-JiraIssues.ps1`). This returns a concise markdown summary that can be shown to the user directly — no JSON parsing needed.
* Use default JSON format (`-Format Json` or omit the flag) only when programmatic field extraction is required.
* When using JSON format, parse output from stdout. All scripts emit JSON via `ConvertTo-Json -Depth 10`.
* Use `ConvertTo-SafeJqlValue` from `shared.psm1` when constructing JQL with user-supplied values to prevent injection.

## Safety Policy (Mandatory)

### Blocked Operations

| Blocked Operation | HTTP Method | Why                         |
|-------------------|-------------|-----------------------------|
| Delete issue      | DELETE      | Permanent data loss         |
| Delete comment    | DELETE      | Permanent data loss         |
| Delete project    | DELETE      | Entire project destruction  |
| Delete attachment | DELETE      | Permanent data loss         |

### Five-Layer DELETE Blocking

DELETE operations are blocked at five independent layers to prevent accidental or deliberate data destruction:

1. `Invoke-JiraApi` validates the `-Method` parameter using `[ValidateSet('Get', 'Post', 'Put')]`, rejecting DELETE at the parameter binding level.
2. A runtime guard inside `Invoke-JiraApi` checks the method string and throws before any HTTP request is made.
3. No script in this skill constructs a DELETE request. No code path exists to reach a DELETE call.
4. A VS Code Copilot `PreToolUse` hook at `.github/hooks/jira-safety.json` inspects every tool invocation before execution. The hook's PowerShell script blocks DELETE method patterns (`-Method Delete`, `curl -X DELETE`), direct API bypass attempts, script tampering, and protected file deletion. This layer operates at the Copilot agent level, before any terminal command or file edit runs.
5. A workspace-wide instructions file at `.github/instructions/jira-safety.instructions.md` teaches the Copilot agent to proactively avoid DELETE operations and direct API bypass attempts. This soft guidance layer reduces the frequency of blocked operations.

All five layers must be bypassed simultaneously for a DELETE to succeed.

### Empty Field Protection

The `Update-JiraIssue.ps1` script prevents blanking the `summary` field. If `-Summary` is provided, it must contain non-whitespace content. At least one update field must be specified for any update operation.

## Credentials Policy (Mandatory)

* NEVER hardcode usernames, passwords, tokens, or secrets in any file.
* Read credentials from `.env` or `credentials.env` at the workspace root only.
* Never log or echo PAT values in terminal output. All error messages pass through `Get-SanitizedErrorMessage` to redact tokens.
* Credentials are auto-cleared in the `finally` block after each operation: the `jirapat` value is set to `$null` and the credentials hashtable is removed from scope.
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

### Get-JiraIssue

| Parameter         | Flag               | Type     | Mandatory | Default | Description                                              |
|-------------------|---------------------|----------|-----------|---------|----------------------------------------------------------|
| Issue Key         | `-IssueKey`        | string   | Yes       | â€”       | Jira issue key (e.g., `PROJ-123`)                        |
| Fields            | `-Fields`          | string[] | No        | All     | Specific fields to retrieve                              |
| Include Comments  | `-IncludeComments` | switch   | No        | `$false`| Also retrieve comments for the issue                     |
| Expand            | `-Expand`          | string[] | No        | â€”       | Expand options (`renderedFields`, `changelog`, etc.)     || Format            | `-Format`          | string   | No        | `Json`  | Output format: `Json` (full API response) or `Summary` (clean markdown) |
### Search-JiraIssues

| Parameter    | Flag           | Type     | Mandatory | Default                                 | Description                                  |
|--------------|----------------|----------|-----------|-----------------------------------------|----------------------------------------------|
| JQL          | `-Jql`         | string   | Yes       | â€”                                       | JQL query string                             |
| Fields       | `-Fields`      | string[] | No        | `summary,status,assignee,priority`      | Fields to return                             |
| Max Results  | `-MaxResults`  | int      | No        | `50`                                    | Results per page (max 100)                   |
| Start At     | `-StartAt`     | int      | No        | `0`                                     | Pagination offset                            |
| All          | `-All`         | switch   | No        | `$false`                                | Paginate through all results (capped at 500) |
| Format       | `-Format`      | string   | No        | `Json`                                  | Output format: `Json` (full response) or `Summary` (markdown table) |

### New-JiraIssue

| Parameter      | Flag             | Type      | Mandatory | Default | Description                                 |
|----------------|------------------|-----------|-----------|---------|---------------------------------------------|
| Project Key    | `-ProjectKey`    | string    | Yes       | â€”       | Jira project key (e.g., `MYPROJ`)           |
| Summary        | `-Summary`       | string    | Yes       | â€”       | Issue summary/title (must not be empty)      |
| Description    | `-Description`   | string    | No        | â€”       | Issue description                           |
| Issue Type     | `-IssueType`     | string    | No        | `Story` | Issue type (`Story`, `Task`, `Bug`, `Epic`) |
| Priority       | `-Priority`      | string    | No        | â€”       | Priority name (e.g., `High`, `Medium`)      |
| Labels         | `-Labels`        | string[]  | No        | â€”       | Labels to apply                             |
| Assignee       | `-Assignee`      | string    | No        | â€”       | Assignee username or account ID             |
| Custom Fields  | `-CustomFields`  | hashtable | No        | â€”       | Custom fields as key-value pairs            |

### Update-JiraIssue

| Parameter      | Flag             | Type      | Mandatory | Default | Description                                      |
|----------------|------------------|-----------|-----------|---------|--------------------------------------------------|
| Issue Key      | `-IssueKey`      | string    | Yes       | â€”       | Jira issue key to update                         |
| Summary        | `-Summary`       | string    | No        | â€”       | New summary (must not be blank if provided)      |
| Description    | `-Description`   | string    | No        | â€”       | New description                                  |
| Priority       | `-Priority`      | string    | No        | â€”       | New priority name                                |
| Labels         | `-Labels`        | string[]  | No        | â€”       | New labels (replaces existing)                   |
| Custom Fields  | `-CustomFields`  | hashtable | No        | â€”       | Custom fields to update                          |

### Add-JiraComment

| Parameter   | Flag           | Type      | Mandatory | Default | Description                                                        |
|-------------|----------------|-----------|-----------|---------|--------------------------------------------------------------------|
| Issue Key   | `-IssueKey`    | string    | Yes       | â€”       | Issue to comment on                                                |
| Body        | `-Body`        | string    | Yes       | â€”       | Comment text (plain text or wiki markup)                           |
| Visibility  | `-Visibility`  | hashtable | No        | â€”       | Visibility restriction (e.g., `@{type='role'; value='Developers'}`) |

### Set-JiraTransition

| Parameter        | Flag                | Type   | Mandatory | Default  | Description                                    |
|------------------|---------------------|--------|-----------|----------|------------------------------------------------|
| Issue Key        | `-IssueKey`         | string | Yes       | â€”        | Issue to transition                            |
| Transition ID    | `-TransitionId`     | string | No        | â€”        | ID of the transition to execute                |
| Transition Name  | `-TransitionName`   | string | No        | â€”        | Name of the transition (resolved to ID)        |
| List Transitions | `-ListTransitions`  | switch | No        | `$false` | List available transitions instead of executing|
| Comment          | `-Comment`          | string | No        | â€”        | Comment to add with the transition             |

Provide either `-TransitionId` or `-TransitionName` to execute a transition. Use `-ListTransitions` to discover available transitions before executing one. When both `-TransitionName` and `-TransitionId` are omitted without `-ListTransitions`, the script throws an error.

### Set-JiraAssignee

| Parameter | Flag          | Type   | Mandatory | Default  | Description                                     |
|-----------|---------------|--------|-----------|----------|-------------------------------------------------|
| Issue Key | `-IssueKey`   | string | Yes       | â€”        | Issue to assign                                 |
| Assignee  | `-Assignee`   | string | No        | â€”        | Username or account ID to assign                |
| Unassign  | `-Unassign`   | switch | No        | `$false` | Remove the current assignee                     |

## Workflow Pattern for Agents

### Read Operations (single command, no parsing needed)

Use `-Format Summary` to get clean, user-ready output in a single step:

1. Set execution policy (Windows recommended): `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`
2. Get issue summary: `Get-JiraIssue.ps1 -IssueKey "PROJ-123" -Format Summary`
3. Search issues: `Search-JiraIssues.ps1 -Jql "project = PROJ AND status = 'To Do'" -Format Summary`

The output is clean markdown that can be returned to the user directly — no JSON parsing or field extraction required.

### Write Operations (standard workflow)

1. Set execution policy (Windows recommended): `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`
2. Create, update, or transition: `New-JiraIssue.ps1`, `Update-JiraIssue.ps1`, or `Set-JiraTransition.ps1`
3. Add comments as needed: `Add-JiraComment.ps1 -IssueKey "PROJ-123" -Body "Updated via automation"`
4. Verify changes: `Get-JiraIssue.ps1 -IssueKey "PROJ-123" -Format Summary`

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
| TLS/SSL error           | PowerShell using TLS 1.0       | Script pins TLS 1.2 automatically via `ServicePointManager`       |
| BLOCKED: DELETE         | Attempted delete operation     | DELETE operations are permanently disabled by this skill           |
| Missing `jirapat`       | `.env` file incomplete         | Add `jirapat=<PAT>` to `.env` or `credentials.env`                |
| Invalid issue key       | Wrong format                   | Use uppercase `PROJECT-NUMBER` format (e.g., `PROJ-123`)          |
