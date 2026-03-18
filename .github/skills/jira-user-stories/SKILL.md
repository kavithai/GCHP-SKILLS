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
| **Pre-tool check** | **Invoke-PreToolHook.ps1** | n/a      | n/a (runs before API calls)           |

## Prerequisites

| Requirement | Detail                                                                                     |
|-------------|--------------------------------------------------------------------------------------------|
| PowerShell  | 5.1+ (Windows built-in)                                                                   |
| Jira Access | REST API v2 over HTTPS                                                                    |
| Credentials | `.env` or `credentials.env` at workspace root with `jirapat=<PAT>` and `jiraurl=<URL>`    |
| Optional    | `jiraemail=<email>` for Jira Cloud (Basic Auth), `jiraauthtype=Basic`                      |

## Quick Start (Copy-Paste Ready)

All examples assume `$sd` is set to the scripts directory. Set it once per session:

    $sd = "<workspace>/.github/skills/jira-user-stories/scripts"

Retrieve a single issue (recommended — one command, clean output):

    powershell -ExecutionPolicy Bypass -File "$sd/Get-JiraIssue.ps1" -IssueKey "MYPROJ-123" -Format Summary

Search for issues:

    powershell -ExecutionPolicy Bypass -File "$sd/Search-JiraIssues.ps1" -Jql "project = MYPROJ AND status = 'To Do'" -MaxResults 10 -Format Summary

Create a new user story:

    powershell -ExecutionPolicy Bypass -File "$sd/New-JiraIssue.ps1" -ProjectKey "MYPROJ" -Summary "New user story" -IssueType "Story"

Transition an issue:

    powershell -ExecutionPolicy Bypass -File "$sd/Set-JiraTransition.ps1" -IssueKey "MYPROJ-123" -TransitionName "In Progress"

## Agent Execution Rules (Required)

When using this skill from an agent runtime:

* **Resolve `$SKILL_DIR` first.** Before running any script, resolve the skill directory path once per session:
  * `$SKILL_DIR` = the directory containing this SKILL.md file (the `.github/skills/jira-user-stories` path within the workspace).
  * Scripts live at `$SKILL_DIR/scripts/<script>.ps1`.
  * Do NOT explore the filesystem to find the scripts. Use the known path directly.
* For maximum Windows compatibility, run scripts via:
  * `powershell -ExecutionPolicy Bypass -File "$SKILL_DIR/scripts/<script>.ps1"`
  * or set once per terminal: `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`
* On PowerShell 7+ (including non-Windows), use `pwsh -File "$SKILL_DIR/scripts/<script>.ps1"`.
* Always check exit codes (`$LASTEXITCODE`) after script execution. Exit code 0 indicates success; exit code 1 indicates failure.
* **Always use `-Format Summary`** for read operations (`Get-JiraIssue.ps1`, `Search-JiraIssues.ps1`). This returns clean markdown output — no JSON parsing needed. Only use `-Format Json` when the user explicitly requests raw data.
* When using JSON format, parse output from stdout. All scripts emit JSON via `ConvertTo-Json -Depth 10`.
* Use `ConvertTo-SafeJqlValue` from `shared.psm1` when constructing JQL with user-supplied values to prevent injection.

## Agent Efficiency Rules (Required — Anti-Cycle)

These rules prevent slow multi-turn agent execution. Violations waste user time and tokens.

1. **One command, one turn.** Chain execution-policy setup and script invocation into a single terminal command. Do NOT split them across multiple turns.
2. **Scripts handle credentials internally.** Do NOT manually search for, read, or parse `.env` or `credentials.env`. The scripts auto-load credentials from the workspace root via `Get-JiraCredentials` in `shared.psm1`.
3. **Scripts handle path resolution internally.** Do NOT `cd` into the scripts directory, check if `shared.psm1` exists, or list directory contents. Just invoke the script by its full path.
4. **Do NOT retry on credential errors.** If a 401/403 occurs, report the error to the user. Do NOT re-run the same command hoping it will work.
5. **Do NOT retry on API errors more than once.** If a script fails, check the error message. If the issue is clear (wrong key, missing field), fix the input. If the error is transient (429, 5xx), retry once. If it fails again, report to the user.
6. **Do NOT explore the skill directory.** The scripts, their parameters, and their behavior are fully documented in this file and `references/reference.md`. Do NOT list or read script files to discover parameters.
7. **Maximum two turns per operation.** A single Jira operation (read, create, update) should complete in at most two terminal commands: one to run the script, one optional verification. If you find yourself on a third command for the same operation, stop and report the issue.
8. **Detailed parameter docs are in `references/reference.md`.** Only consult parameter tables below for the most common flags. For advanced parameters, read the reference file.

## Safety Policy (Mandatory)

### Blocked Operations

| Blocked Operation       | HTTP Method | Why                                    |
|-------------------------|-------------|----------------------------------------|
| Delete issue            | DELETE      | Permanent data loss                    |
| Delete comment          | DELETE      | Permanent data loss                    |
| Delete project          | DELETE      | Entire project destruction             |
| Delete epic             | DELETE      | Permanent data loss                    |
| Delete attachment       | DELETE      | Permanent data loss                    |
| Delete sprint / board   | DELETE      | Permanent data loss                    |
| Bulk delete issues      | POST        | Mass irreversible data loss            |

### Four-Layer Irreversible-Operation Blocking

Irreversible operations are blocked at four independent layers:

1. **Pretool hook — entry-point guard (`Invoke-PreToolHook`).** Every write script calls `Invoke-PreToolHook` before loading credentials or making any API request. The hook blocks: any DELETE HTTP method, named destructive operations (`DeleteIssue`, `DeleteProject`, `DeleteEpic`, `DeleteComment`, `DeleteAttachment`, `DeleteSprint`, `DeleteBoard`, `BulkDelete`, `PurgeIssue`, `ArchiveProject`, `BulkArchive`, `BulkDestroy`), and POST requests to known bulk-destructive endpoints (`/rest/api/2/issue/bulk`). Every blocked attempt is written to the audit log.
2. `Invoke-JiraApi` validates the `-Method` parameter using `[ValidateSet('Get', 'Post', 'Put')]`, rejecting DELETE at the parameter binding level.
3. A runtime guard inside `Invoke-JiraApi` checks the method string and throws before any HTTP request is made.
4. No script in this skill constructs a DELETE request. No code path exists to reach a DELETE call.

All four layers must be bypassed simultaneously for a destructive operation to succeed, which requires modifying the source code itself.

The standalone `Invoke-PreToolHook.ps1` can also be called directly by an agent pipeline to validate an operation before choosing which script to invoke:

    powershell -ExecutionPolicy Bypass -File "$sd/Invoke-PreToolHook.ps1" `
        -Operation DeleteIssue -Method Delete -Endpoint "/rest/api/2/issue/PROJ-1"
    # Exits 1 — BLOCKED

    powershell -ExecutionPolicy Bypass -File "$sd/Invoke-PreToolHook.ps1" `
        -Operation CreateIssue -Method Post -Endpoint "/rest/api/2/issue"
    # Exits 0 — ALLOWED

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

## Common Parameters (Quick Reference)

For the full parameter reference for all scripts, see `references/reference.md`.

| Script                  | Required Flags                          | Key Optional Flags                          |
|-------------------------|------------------------------------------|---------------------------------------------|
| Get-JiraIssue.ps1       | `-IssueKey "PROJ-123"`                  | `-Format Summary`, `-IncludeComments`       |
| Search-JiraIssues.ps1   | `-Jql "<query>"`                        | `-Format Summary`, `-MaxResults 10`, `-All` |
| New-JiraIssue.ps1       | `-ProjectKey "PROJ"`, `-Summary "text"` | `-IssueType`, `-Description`, `-Priority`   |
| Update-JiraIssue.ps1    | `-IssueKey "PROJ-123"`                  | `-Summary`, `-Description`, `-Priority`     |
| Add-JiraComment.ps1     | `-IssueKey "PROJ-123"`, `-Body "text"`  | `-Visibility`                               |
| Set-JiraTransition.ps1  | `-IssueKey "PROJ-123"`                  | `-TransitionName`, `-ListTransitions`       |
| Set-JiraAssignee.ps1    | `-IssueKey "PROJ-123"`                  | `-AssignToMe`, `-Assignee`, `-Unassign`     |
## Workflow Pattern for Agents

### Read Operations (one command total)

Chain execution-policy setup and script invocation in a single terminal command:

    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass; & "$sd/Get-JiraIssue.ps1" -IssueKey "PROJ-123" -Format Summary

The output is clean markdown — return it to the user directly. No JSON parsing, no second command.

### Write Operations (two commands max)

1. Run the write script:

       Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass; & "$sd/New-JiraIssue.ps1" -ProjectKey "PROJ" -Summary "New story" -IssueType "Story"

2. Optionally verify:

       & "$sd/Get-JiraIssue.ps1" -IssueKey "PROJ-456" -Format Summary

Do NOT add a third command. If the write failed, report the error — do not retry automatically.

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
| PRETOOL HOOK BLOCKED    | Attempted irreversible op      | The operation name or HTTP method is in the blocked list; no alternative exists — the operation is permanently disabled |
| Missing `jirapat`       | `.env` file incomplete         | Add `jirapat=<PAT>` to `.env` or `credentials.env`                |
| Invalid issue key       | Wrong format                   | Use uppercase `PROJECT-NUMBER` format (e.g., `PROJ-123`)          |
