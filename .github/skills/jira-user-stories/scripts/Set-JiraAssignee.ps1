<#
.SYNOPSIS
Sets or clears the assignee on a Jira issue.

.DESCRIPTION
Updates the assignee field on a Jira issue. Use -Assignee to set a specific
user (by username or account ID), or -Unassign to clear the current assignee.
Exactly one of -Assignee or -Unassign must be specified.

.PARAMETER IssueKey
The Jira issue key to update (e.g. MYPROJ-123).

.PARAMETER Assignee
Username or account ID to assign the issue to.

.PARAMETER Unassign
Switch to clear the current assignee from the issue.

.EXAMPLE
.\Set-JiraAssignee.ps1 -IssueKey 'MYPROJ-123' -Assignee 'jsmith'

.EXAMPLE
.\Set-JiraAssignee.ps1 -IssueKey 'MYPROJ-123' -Unassign
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$IssueKey,

    [Parameter()]
    [string]$Assignee,

    [Parameter()]
    [switch]$Unassign
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'shared.psm1') -Force

if ($MyInvocation.InvocationName -ne '.') {
    try {
        # Validate issue key
        if (-not (Test-JiraIssueKey -IssueKey $IssueKey)) {
            throw "Invalid issue key '$IssueKey'. Expected format: PROJ-123."
        }

        # Require either -Assignee or -Unassign
        $hasAssignee = $PSBoundParameters.ContainsKey('Assignee') -and -not [string]::IsNullOrWhiteSpace($Assignee)
        $hasUnassign = $Unassign.IsPresent

        if (-not $hasAssignee -and -not $hasUnassign) {
            throw "Either -Assignee or -Unassign must be specified."
        }

        if ($hasAssignee -and $hasUnassign) {
            throw "Cannot use both -Assignee and -Unassign at the same time."
        }

        # Load credentials
        $creds = Get-JiraCredentials

        # Build assignee body
        if ($hasUnassign) {
            $assigneeBody = @{
                name = $null
            }
            $actionDescription = 'Unassigning'
        }
        else {
            $assigneeBody = @{
                name = $Assignee
            }
            $actionDescription = "Assigning to '$Assignee'"
        }

        $jsonBody = $assigneeBody | ConvertTo-Json -Depth 10

        $escapedKey = [Uri]::EscapeDataString($IssueKey)
        $endpoint = "/rest/api/2/issue/$escapedKey/assignee"

        Write-SkillOutput -Title 'Assignee' -Message "$actionDescription issue $IssueKey..."

        Invoke-JiraApi -Credentials $creds -Endpoint $endpoint -Method 'Put' -Body $jsonBody

        $details = if ($hasUnassign) { 'Cleared assignee' } else { "Assigned to '$Assignee'" }
        Write-AuditLog -Operation 'SetAssignee' -IssueKey $IssueKey -Details $details
        Write-SkillOutput -Title 'Assignee' -Message "Successfully updated assignee on $IssueKey. $details."

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
