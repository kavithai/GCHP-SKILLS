<#
.SYNOPSIS
Updates an existing Jira issue.

.DESCRIPTION
Updates fields on an existing Jira issue. Supports changing summary,
description, priority, labels, and custom fields. Requires at least one
update field to be specified. Validates the issue key format and enforces
empty field protection for Summary.

.PARAMETER IssueKey
The Jira issue key to update (e.g. MYPROJ-123).

.PARAMETER Summary
Optional new summary/title. Must not be empty or whitespace if provided.

.PARAMETER Description
Optional new description body.

.PARAMETER Priority
Optional new priority name (e.g. High, Medium, Low).

.PARAMETER Labels
Optional new labels array. Replaces all existing labels on the issue.

.PARAMETER CustomFields
Optional hashtable of custom field key-value pairs to update.

.EXAMPLE
.\Update-JiraIssue.ps1 -IssueKey 'MYPROJ-123' -Summary 'Updated title'

.EXAMPLE
.\Update-JiraIssue.ps1 -IssueKey 'MYPROJ-123' -Priority 'High' -Labels @('critical','backend')
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$IssueKey,

    [Parameter()]
    [string]$Summary,

    [Parameter()]
    [string]$Description,

    [Parameter()]
    [string]$Priority,

    [Parameter()]
    [string[]]$Labels,

    [Parameter()]
    [hashtable]$CustomFields
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'shared.psm1') -Force

if ($MyInvocation.InvocationName -ne '.') {
    try {
        # Validate issue key
        if (-not (Test-JiraIssueKey -IssueKey $IssueKey)) {
            throw "Invalid issue key '$IssueKey'. Expected format: PROJ-123."
        }

        # Empty field protection: if Summary is provided, must not be empty/whitespace
        if ($PSBoundParameters.ContainsKey('Summary') -and [string]::IsNullOrWhiteSpace($Summary)) {
            throw "Summary must not be empty or whitespace when provided."
        }

        # Require at least one update field
        $updateFields = @('Summary', 'Description', 'Priority', 'Labels', 'CustomFields')
        $hasUpdate = $false
        foreach ($field in $updateFields) {
            if ($PSBoundParameters.ContainsKey($field)) {
                $hasUpdate = $true
                break
            }
        }
        if (-not $hasUpdate) {
            throw "At least one update field must be specified (Summary, Description, Priority, Labels, or CustomFields)."
        }

        # Load credentials
        $creds = Get-JiraCredentials

        # Build fields hashtable
        $fields = @{}

        if ($PSBoundParameters.ContainsKey('Summary')) {
            $fields['summary'] = $Summary
        }

        if ($PSBoundParameters.ContainsKey('Description')) {
            $fields['description'] = $Description
        }

        if ($PSBoundParameters.ContainsKey('Priority') -and $Priority) {
            $fields['priority'] = @{
                name = $Priority
            }
        }

        if ($PSBoundParameters.ContainsKey('Labels')) {
            $fields['labels'] = @($Labels)
        }

        if ($PSBoundParameters.ContainsKey('CustomFields') -and $CustomFields) {
            foreach ($cfKey in $CustomFields.Keys) {
                $fields[$cfKey] = $CustomFields[$cfKey]
            }
        }

        $body = @{
            fields = $fields
        }

        $jsonBody = $body | ConvertTo-Json -Depth 10

        $escapedKey = [Uri]::EscapeDataString($IssueKey)
        $endpoint = "/rest/api/2/issue/$escapedKey"

        Write-SkillOutput -Title 'UpdateIssue' -Message "Updating issue $IssueKey..."

        Invoke-JiraApi -Credentials $creds -Endpoint $endpoint -Method 'Put' -Body $jsonBody

        Write-AuditLog -Operation 'UpdateIssue' -IssueKey $IssueKey -Details "Updated fields: $($fields.Keys -join ', ')"
        Write-SkillOutput -Title 'UpdateIssue' -Message "Successfully updated issue: $IssueKey"

        exit 0
    }
    catch {
        Write-Error (Get-SanitizedErrorMessage -Message $_.Exception.Message)
        exit 1
    }
    finally {
        if ($creds) { $creds['jirapat'] = $null; Remove-Variable -Name creds -ErrorAction SilentlyContinue }
    }
}
