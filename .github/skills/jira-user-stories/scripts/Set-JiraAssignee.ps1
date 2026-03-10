<#
.SYNOPSIS
Sets or clears the assignee on a Jira issue.

.DESCRIPTION
Updates the assignee field on a Jira issue. Use -Assignee to set a specific
user (by username or account ID), -AssignToMe to assign to the authenticated
user, or -Unassign to clear the current assignee.
Exactly one of -Assignee, -AssignToMe, or -Unassign must be specified.

.PARAMETER IssueKey
The Jira issue key to update (e.g. MYPROJ-123).

.PARAMETER Assignee
Username or account ID to assign the issue to.

.PARAMETER AssignToMe
Switch to assign the issue to the currently authenticated user.
Resolves the account ID automatically via the /rest/api/2/myself endpoint.

.PARAMETER Unassign
Switch to clear the current assignee from the issue.

.EXAMPLE
.\Set-JiraAssignee.ps1 -IssueKey 'MYPROJ-123' -Assignee 'jsmith'

.EXAMPLE
.\Set-JiraAssignee.ps1 -IssueKey 'MYPROJ-123' -AssignToMe

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
    [switch]$AssignToMe,

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

        # Require exactly one of -Assignee, -AssignToMe, or -Unassign
        $hasAssignee = $PSBoundParameters.ContainsKey('Assignee') -and -not [string]::IsNullOrWhiteSpace($Assignee)
        $hasAssignToMe = $AssignToMe.IsPresent
        $hasUnassign = $Unassign.IsPresent

        $optionCount = @($hasAssignee, $hasAssignToMe, $hasUnassign).Where({ $_ }).Count
        if ($optionCount -eq 0) {
            throw "One of -Assignee, -AssignToMe, or -Unassign must be specified."
        }
        if ($optionCount -gt 1) {
            throw "Only one of -Assignee, -AssignToMe, or -Unassign can be specified at a time."
        }

        # Load credentials
        $creds = Get-JiraCredentials

        # Resolve -AssignToMe to an account ID
        if ($hasAssignToMe) {
            Write-SkillOutput -Title 'Assignee' -Message "Resolving current user..."
            $currentUser = Get-JiraCurrentUser -Credentials $creds
            $Assignee = $currentUser.accountId
            $hasAssignee = $true
            Write-SkillOutput -Title 'Assignee' -Message "Resolved to '$($currentUser.displayName)' ($Assignee)."
        }

        # Build assignee body
        # Jira Cloud requires 'accountId'; Jira Server/DC uses 'name'.
        # Detect Cloud by checking if jiraauthtype is 'Basic' or URL contains atlassian.net
        $isCloud = ($creds['jiraauthtype'] -eq 'Basic') -or ($creds['jiraurl'] -match 'atlassian\.net')

        if ($hasUnassign) {
            if ($isCloud) {
                $assigneeBody = @{ accountId = $null }
            } else {
                $assigneeBody = @{ name = $null }
            }
            $actionDescription = 'Unassigning'
        }
        else {
            if ($isCloud) {
                $assigneeBody = @{ accountId = $Assignee }
            } else {
                $assigneeBody = @{ name = $Assignee }
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
