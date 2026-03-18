<#
.SYNOPSIS
Pre-execution safety hook for Jira operations.

.DESCRIPTION
Validates an intended Jira operation before any credentials are loaded or
API requests are made. Blocks any irreversible operation including:
  - All DELETE HTTP methods (deletes of user stories, epics, projects,
    comments, attachments, and any other resource)
  - Named destructive operations (DeleteIssue, DeleteProject, DeleteEpic, etc.)
  - POST requests to known bulk-destructive endpoints

Exits with code 0 when the operation is allowed.
Exits with code 1 (and writes a BLOCKED message) when the operation is denied.

This script can be invoked directly before calling any other skill script to
confirm an operation is permitted, or it can serve as a standalone gate in
an agent pipeline.

.PARAMETER Operation
The logical operation name (e.g. 'CreateIssue', 'UpdateIssue', 'DeleteIssue').
Compared case-insensitively against the blocked-operation list.

.PARAMETER Method
The HTTP method the operation intends to use (Get, Post, Put, Delete).
Any value of Delete is blocked unconditionally.

.PARAMETER Endpoint
The Jira REST API endpoint path (e.g. '/rest/api/2/issue/PROJ-123').

.PARAMETER IssueKey
Optional Jira issue key included in the audit log entry.

.PARAMETER IssueType
Optional issue type (e.g. Story, Epic, Task) included in the audit log entry.

.EXAMPLE
.\Invoke-PreToolHook.ps1 -Operation 'CreateIssue' -Method 'Post' -Endpoint '/rest/api/2/issue'
# Exits 0 — allowed

.EXAMPLE
.\Invoke-PreToolHook.ps1 -Operation 'DeleteIssue' -Method 'Delete' -Endpoint '/rest/api/2/issue/PROJ-1'
# Exits 1 — PRETOOL HOOK BLOCKED

.EXAMPLE
.\Invoke-PreToolHook.ps1 -Operation 'DeleteProject' -Method 'Post' -Endpoint '/rest/api/2/project/PROJ'
# Exits 1 — PRETOOL HOOK BLOCKED (operation name match)
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Operation,

    [Parameter(Mandatory = $true)]
    [string]$Method,

    [Parameter(Mandatory = $true)]
    [string]$Endpoint,

    [Parameter()]
    [string]$IssueKey,

    [Parameter()]
    [string]$IssueType
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'shared.psm1') -Force

if ($MyInvocation.InvocationName -ne '.') {
    try {
        $hookParams = @{
            Operation = $Operation
            Method    = $Method
            Endpoint  = $Endpoint
        }
        if ($PSBoundParameters.ContainsKey('IssueKey') -and $IssueKey) {
            $hookParams['IssueKey'] = $IssueKey
        }
        if ($PSBoundParameters.ContainsKey('IssueType') -and $IssueType) {
            $hookParams['IssueType'] = $IssueType
        }

        Invoke-PreToolHook @hookParams

        Write-Host "[PreToolHook] ALLOWED: '$Operation' ($Method $Endpoint)"
        exit 0
    }
    catch {
        Write-Error $_.Exception.Message
        exit 1
    }
}
